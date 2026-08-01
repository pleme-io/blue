//! blue's test framework.
//!
//! ```text
//! def add(a, b)
//!   a + b
//! end
//!
//! test "adds"
//!   assert add(1, 2) == 3
//! end
//! ```
//!
//! ## The failure message is the formatter's output
//!
//! `assert e` lowers to `(assert 'e e)` — the expression as *data* alongside
//! its value — and the runner renders that data through `blue_lang_fmt`. So a
//! failure reads:
//!
//! ```text
//! FAIL adds
//!   assert add(1, 2) == 4
//! ```
//!
//! in canonical blue syntax, not in the underlying tatara-lisp and not as a
//! quoted slice of the original file. **This costs nothing to build**: no source
//! map, no macro hygiene, no string capture at the lexer. It is what
//! homoiconicity plus a single canonical formatting buys, and it is the reason
//! `assert` is a surface form rather than a library function.
//!
//! ## Isolation is per-test, and paid for honestly
//!
//! Each test runs in a **fresh interpreter** with the file's non-test
//! top-level forms replayed into it. So one test cannot see another's
//! mutations, and a test that crashes cannot corrupt the next.
//!
//! The cost is that the preamble is evaluated once per test — O(tests ×
//! preamble). That is deliberate: sharing one interpreter would make test
//! order significant, which is the single worst property a test framework can
//! have. [`Report::preamble_evaluations`] reports the count so the cost is
//! visible rather than hidden.
//!
//! ## `pending-dojo:` blue-facet
//!
//! The fleet's ★★ DOJO doctrine says every testing quality is a typed facet
//! carried by one `(defsuite …)` over one injected Environment, and that dojo
//! owns only the border. `pleme-io/dojo` is empty (DESIGN tier, nothing
//! shipped), so this runner is blue-local and shaped to be absorbed: a
//! `(deftest …)` form is a facet's worth of declaration, and `Report` is the
//! verdict a `(defsuite …)` would collect. It is not a second testing
//! vocabulary competing with dojo; it is the first facet, waiting for the
//! border.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use tatara_lisp::{Atom, Sexp};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{Interpreter, Value};

/// One declared test.
#[derive(Clone, Debug, PartialEq)]
pub struct Test {
    pub name: String,
    pub body: Sexp,
}

/// Why a test did not pass. **Two distinct outcomes, never merged**: an
/// assertion that came out false is a *finding*, while an error thrown on the
/// way there means the assertion never ran and proves nothing about it.
/// Reporting both as "failed" is how a broken test masquerades as a caught bug.
#[derive(Clone, Debug, PartialEq)]
pub enum Failure {
    /// An `assert` evaluated to something falsy. Carries the expression as
    /// canonical blue source.
    Assertion { test: String, expression: String },
    /// The test raised before or instead of asserting.
    Errored { test: String, error: String },
}

impl Failure {
    pub fn test(&self) -> &str {
        match self {
            Failure::Assertion { test, .. } | Failure::Errored { test, .. } => test,
        }
    }
}

impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Failure::Assertion { test, expression } => {
                write!(f, "FAIL {test}\n  assert {expression}")
            }
            Failure::Errored { test, error } => write!(f, "ERROR {test}\n  {error}"),
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Report {
    pub passed: usize,
    pub failures: Vec<Failure>,
    /// How many times the file's preamble was replayed — one per test. Exposed
    /// so the cost of per-test isolation is visible rather than hidden.
    pub preamble_evaluations: usize,
}

impl Report {
    pub fn ok(&self) -> bool {
        self.failures.is_empty()
    }

    pub fn total(&self) -> usize {
        self.passed + self.failures.len()
    }
}

impl std::fmt::Display for Report {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        for failure in &self.failures {
            writeln!(f, "{failure}")?;
        }
        write!(
            f,
            "{} test(s): {} passed, {} failed",
            self.total(),
            self.passed,
            self.failures.len()
        )
    }
}

/// Split a program into its tests and everything else.
///
/// The remainder is the *preamble* — the definitions a test needs. Keeping
/// them in source order matters: a `defmacro` must be registered before a
/// later form uses it.
pub fn split(forms: &[Sexp]) -> (Vec<Test>, Vec<Sexp>) {
    let mut tests = Vec::new();
    let mut preamble = Vec::new();
    for form in forms {
        match as_test(form) {
            Some(t) => tests.push(t),
            None => preamble.push(form.clone()),
        }
    }
    (tests, preamble)
}

fn as_test(form: &Sexp) -> Option<Test> {
    let Sexp::List(items) = form else { return None };
    if items.len() != 3 {
        return None;
    }
    match (&items[0], &items[1]) {
        (Sexp::Atom(Atom::Symbol(h)), Sexp::Atom(Atom::Str(name))) if &**h == "deftest" => {
            Some(Test {
                name: name.to_string(),
                body: items[2].clone(),
            })
        }
        _ => None,
    }
}

/// The host a test runs against: one flag recording whether an `assert`
/// failed, and the expression that failed.
///
/// A flag rather than an early return, because a primitive cannot unwind the
/// interpreter — and because a test with several asserts should report the
/// FIRST failure, which is the one whose cause is still local.
#[derive(Default)]
struct Recorder {
    failed: Arc<AtomicBool>,
    expression: Arc<std::sync::Mutex<Option<String>>>,
}

/// Install the assertion primitive, recording failures into `rec`.
fn install_assert(interp: &mut Interpreter<()>, rec: &Recorder) {
    let failed = rec.failed.clone();
    let expression = rec.expression.clone();
    interp.register_fn(
        blue_lang_syntax::LOWERED_ASSERT,
        Arity::Exact(2),
        move |args: &[Value], _host: &mut (), _span| {
            if truthy(&args[1]) {
                return Ok(Value::Bool(true));
            }
            // Record the FIRST failure only: later asserts in the same test
            // are usually consequences of it.
            if !failed.swap(true, Ordering::SeqCst) {
                if let Ok(mut slot) = expression.lock() {
                    *slot = Some(render_form(&args[0]));
                }
            }
            Ok(Value::Bool(false))
        },
    );
}

/// A quoted form as canonical blue source.
///
/// ## Why this lifts back to `Sexp` first
///
/// A quoted form does not survive evaluation as a `Sexp`: `'(= (add 1 2) 4)`
/// evaluates to a `Value::List` of `Value::Symbol`/`Value::Int`. Rendering that
/// `Value` directly produced the tatara-lisp spelling `(= (add 1 2) 4)` — true
/// to the tree and useless to a blue author, who wrote `add(1, 2) == 4`.
///
/// Lifting to `Sexp` and rendering through `blue_lang_fmt` means the failure
/// message and the source file cannot disagree about how the expression is
/// spelled: both are the output of the one canonical formatting. That is the
/// whole reason blue has exactly one.
fn render_form(v: &Value) -> String {
    let sexp = match v {
        Value::Sexp(s, _) => s.clone(),
        other => match value_to_sexp(other) {
            Some(s) => s,
            // Nothing sensible to lift (a closure, a foreign handle). Say so
            // rather than printing a Rust debug string at the author.
            None => return "<unrenderable expression>".to_string(),
        },
    };
    // format_forms, not a new single-Sexp entry point: one rendering.
    blue_lang_fmt::format_forms(std::slice::from_ref(&sexp))
        .trim_end()
        .to_string()
}

/// Lift an evaluated quoted form back into the syntax tree it came from.
///
/// Total over the shapes a quoted form can produce; `None` for values that were
/// never syntax (closures, foreign handles).
fn value_to_sexp(v: &Value) -> Option<Sexp> {
    Some(match v {
        Value::Nil => Sexp::Nil,
        Value::Bool(b) => Sexp::Atom(Atom::Bool(*b)),
        Value::Int(n) => Sexp::Atom(Atom::Int(*n)),
        Value::Float(x) => Sexp::Atom(Atom::Float(*x)),
        Value::Str(s) => Sexp::Atom(Atom::Str(s.to_string())),
        Value::Symbol(s) => Sexp::Atom(Atom::Symbol(s.to_string())),
        Value::Keyword(k) => Sexp::Atom(Atom::Keyword(k.to_string())),
        Value::Sexp(s, _) => s.clone(),
        Value::List(items) => {
            Sexp::List(items.iter().map(value_to_sexp).collect::<Option<Vec<_>>>()?)
        }
        _ => return None,
    })
}

fn truthy(v: &Value) -> bool {
    !matches!(v, Value::Bool(false) | Value::Nil)
}

/// Run every test in a program.
///
/// Each test gets a fresh interpreter with `preamble` replayed, so test order
/// cannot matter. See the module docs for why that cost is paid deliberately.
pub fn run(forms: &[Sexp]) -> Report {
    let (tests, preamble) = split(forms);
    let mut report = Report::default();

    for test in &tests {
        let rec = Recorder::default();
        let mut interp = blue_lang_runtime::interpreter_hostless();
        install_assert(&mut interp, &rec);
        report.preamble_evaluations += 1;

        // The preamble and the body go through the same erase-then-read path
        // the pipeline uses, so a test sees exactly the program `blue run`
        // would have run.
        let mut program: Vec<Sexp> = preamble.clone();
        program.push(test.body.clone());

        match eval_all(&mut interp, &program) {
            Err(error) => report.failures.push(Failure::Errored {
                test: test.name.clone(),
                error,
            }),
            Ok(()) => {
                if rec.failed.load(Ordering::SeqCst) {
                    let expression = rec
                        .expression
                        .lock()
                        .ok()
                        .and_then(|s| s.clone())
                        .unwrap_or_else(|| "<expression unavailable>".to_string());
                    report.failures.push(Failure::Assertion {
                        test: test.name.clone(),
                        expression,
                    });
                } else {
                    report.passed += 1;
                }
            }
        }
    }

    report
}

fn eval_all(interp: &mut Interpreter<()>, forms: &[Sexp]) -> Result<(), String> {
    let erased = blue_lang_runtime::erase_types(forms);
    let text = erased
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join("\n");
    let spanned = tatara_lisp::read_spanned(&text).map_err(|e| format!("{e:?}"))?;
    interp
        .eval_program(&spanned, &mut ())
        .map(|_| ())
        .map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn report(src: &str) -> Report {
        let forms = blue_lang_syntax::parse_program(src).expect("parse");
        run(&forms)
    }

    const PREAMBLE: &str = "def add(a, b)\n  a + b\nend\n";

    #[test]
    fn a_passing_test_passes() {
        let r = report(&format!("{PREAMBLE}test \"adds\"\n  assert add(1, 2) == 3\nend"));
        assert!(r.ok(), "{r}");
        assert_eq!(r.passed, 1);
    }

    /// **The failure names the expression, in blue syntax.** This is the
    /// property the framework exists for: "assertion failed" alone makes the
    /// author re-derive what they were checking.
    #[test]
    fn a_failing_assertion_reports_the_expression_as_blue_source() {
        let r = report(&format!("{PREAMBLE}test \"adds\"\n  assert add(1, 2) == 4\nend"));
        assert!(!r.ok());
        match &r.failures[0] {
            Failure::Assertion { test, expression } => {
                assert_eq!(test, "adds");
                assert_eq!(
                    expression, "add(1, 2) == 4",
                    "the message must be canonical BLUE source, not tatara-lisp"
                );
            }
            other => panic!("expected an Assertion failure, got {other:?}"),
        }
    }

    /// **An error is not an assertion failure.** A test that raised before
    /// asserting proves nothing about the assertion, and merging the two is
    /// how a broken test masquerades as a caught bug.
    #[test]
    fn a_raising_test_is_reported_as_an_error_not_an_assertion() {
        let r = report("test \"boom\"\n  no_such_function(1)\nend");
        assert!(!r.ok());
        assert!(
            matches!(&r.failures[0], Failure::Errored { .. }),
            "expected Errored, got {:?}",
            r.failures[0]
        );
    }

    /// **Test order cannot matter.** Two tests each defining the same name
    /// must both pass; sharing one interpreter would make the second see the
    /// first's definition.
    #[test]
    fn tests_are_isolated_from_each_other() {
        let r = report(
            "test \"first\"\n  def f(x)\n    1\n  end\n  assert f(0) == 1\nend\n\
             test \"second\"\n  def f(x)\n    2\n  end\n  assert f(0) == 2\nend",
        );
        assert!(r.ok(), "{r}");
        assert_eq!(r.passed, 2);
        assert_eq!(
            r.preamble_evaluations, 2,
            "isolation costs one preamble replay per test, and it is reported"
        );
    }

    /// A test may use the file's definitions AND its macros.
    #[test]
    fn a_test_sees_the_preamble_including_macros() {
        let r = report(
            "defmacro double(x)\n  quote\n    unquote(x) + unquote(x)\n  end\nend\n\
             test \"macro works\"\n  assert double(21) == 42\nend",
        );
        assert!(r.ok(), "{r}");
    }

    /// Several asserts report the FIRST failure — the one whose cause is still
    /// local. Later ones are usually consequences.
    #[test]
    fn the_first_failing_assertion_is_the_one_reported() {
        let r = report("test \"two\"\n  assert 1 == 2\n  assert 3 == 4\nend");
        match &r.failures[0] {
            Failure::Assertion { expression, .. } => assert_eq!(expression, "1 == 2"),
            other => panic!("got {other:?}"),
        }
        assert_eq!(r.failures.len(), 1, "one failure per test, not one per assert");
    }

    /// Anti-vacuity: a file with no tests reports zero, rather than reporting
    /// success because nothing ran. `ok()` being true on an empty run is
    /// correct, but `total()` must show it was empty.
    #[test]
    fn a_file_with_no_tests_reports_zero_rather_than_a_hollow_pass() {
        let r = report(PREAMBLE);
        assert!(r.ok());
        assert_eq!(r.total(), 0, "an empty run must be visibly empty");
    }

    /// Anti-vacuity on truthiness: only `false` and `nil` fail. If everything
    /// were truthy, every assertion above would pass regardless.
    #[test]
    fn only_false_and_nil_fail_an_assertion() {
        assert!(report("test \"t\"\n  assert true\nend").ok());
        assert!(report("test \"t\"\n  assert 0\nend").ok(), "0 is truthy in blue");
        assert!(!report("test \"t\"\n  assert false\nend").ok());
        assert!(!report("test \"t\"\n  assert nil\nend").ok());
    }

    #[test]
    fn split_separates_tests_from_the_preamble() {
        let forms = blue_lang_syntax::parse_program(&format!(
            "{PREAMBLE}test \"a\"\n  assert true\nend"
        ))
        .expect("parse");
        let (tests, preamble) = split(&forms);
        assert_eq!(tests.len(), 1);
        assert_eq!(tests[0].name, "a");
        assert_eq!(preamble.len(), 1, "the def stays in the preamble");
    }
}


#[cfg(test)]
mod shadowing {
    use super::*;

    /// **No name blue lowers to may already be bound by the runtime.**
    ///
    /// This gates the class behind the worst defect in this crate's history:
    /// `assert e` lowered to `(assert 'e e)`, tatara-lisp's stdlib already
    /// bound `assert` to a macro, and a macro in the expander is consulted
    /// before any primitive in the registry. `pred` bound to the *quoted form*
    /// — truthy — so **every assertion in every test silently passed**. The
    /// suite was green and measured nothing.
    ///
    /// It is not enough to have fixed the one name. Any future lowering that
    /// reuses a tatara stdlib name fails the same way, silently, and a green
    /// suite is exactly the symptom that hides it.
    #[test]
    fn no_lowered_name_is_shadowed_by_the_runtime() {
        // Every callee blue's lowering introduces that must be BLUE's.
        // Names blue must OWN. Read from the PARSER, so a lowering that changes
        // to a shadowed name is caught — a local copy would let the gate check
        // itself.
        //
        // NOT every lowered name belongs here. `LOWERED_MAP` is `hash-map`,
        // which blue deliberately DELEGATES to the runtime; for that direction
        // being bound is required, and `every_delegated_name_resolves` asserts
        // the opposite. Conflating the two made this gate flag a correct
        // delegation as a bug.
        const LOWERED: &[&str] = &[blue_lang_syntax::LOWERED_ASSERT];

        let mut shadowed: Vec<(&str, String)> = Vec::new();
        for name in LOWERED {
            // A bare blue runtime — primitives + the Lisp stdlib, no blue
            // additions. If the name resolves here, blue's definition would be
            // the loser.
            let mut interp = blue_lang_runtime::interpreter_hostless();
            let probe = format!("({name})");
            let forms = tatara_lisp::read_spanned(&probe).expect("read probe");
            match interp.eval_program(&forms, &mut ()) {
                // An arity or type complaint means the name RESOLVED — it is
                // bound to something, and that something is not blue's.
                Ok(_) => shadowed.push((name, "resolved and returned a value".to_string())),
                Err(e) => {
                    let msg = e.to_string();
                    if !msg.contains("unbound") {
                        shadowed.push((name, msg));
                    }
                }
            }
        }
        assert!(
            shadowed.is_empty(),
            "these names are already bound by the runtime, so blue's definition is silently \
             shadowed: {shadowed:#?}"
        );
    }

    /// **Every name blue DELEGATES to must resolve.** The mirror of the gate
    /// above, and a real one: a typo in a delegated name is not caught by
    /// "must not be shadowed" — it is caught by "must be bound".
    ///
    /// `{a: 1}` lowering to `(map …)` failed exactly here in spirit: `map` was
    /// bound, but to the higher-order function rather than the constructor, so
    /// the literal called the HOF with key/value pairs. Resolution alone cannot
    /// catch a wrong-but-bound name, which is why the map literal also has an
    /// end-to-end test.
    #[test]
    fn every_delegated_name_resolves() {
        const DELEGATED: &[&str] = &[blue_lang_syntax::LOWERED_MAP];
        let mut missing: Vec<&str> = Vec::new();
        for name in DELEGATED {
            let mut interp = blue_lang_runtime::interpreter_hostless();
            let probe = format!("({name})");
            let forms = tatara_lisp::read_spanned(&probe).expect("read probe");
            if let Err(e) = interp.eval_program(&forms, &mut ()) {
                if e.to_string().contains("unbound") {
                    missing.push(name);
                }
            }
        }
        assert!(
            missing.is_empty(),
            "blue lowers to these names but the runtime does not bind them: {missing:?}"
        );
    }

    /// Anti-vacuity for the gate above: the probe must actually be able to
    /// DETECT a bound name. `assert` itself is bound, so probing it must be
    /// reported — otherwise the gate would pass on anything.
    #[test]
    fn the_shadowing_probe_detects_a_name_that_is_bound() {
        let mut interp = blue_lang_runtime::interpreter_hostless();
        let forms = tatara_lisp::read_spanned("(assert)").expect("read");
        let outcome = interp.eval_program(&forms, &mut ());
        let detected = match &outcome {
            Ok(_) => true,
            Err(e) => !e.to_string().contains("unbound"),
        };
        assert!(
            detected,
            "`assert` IS bound in a bare runtime — if the probe cannot see that, \
             it cannot see any collision. Got: {outcome:?}"
        );
    }
}
