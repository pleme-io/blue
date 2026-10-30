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
//! ## Isolation is per-test, and no longer paid for per-test
//!
//! Each test runs in its own **forked interpreter**: it reads every preamble
//! definition, its own `define`s land in a private frame no sibling can see,
//! and a `set!` reaching an inherited binding is refused rather than silently
//! mutating state the next test would observe. Test order cannot matter, and a
//! test that crashes cannot corrupt the next.
//!
//! This used to be a *fresh* interpreter per test with the preamble replayed
//! into it — O(tests × preamble), and measured at ~900µs per test of which
//! ~945µs was building the interpreter, so essentially the entire cost of
//! running a test was evaluating the standard library again to reach the same
//! state. `Interpreter::fork` shares the evaluated globals instead: 29µs
//! against 1.59ms, and the isolation is a property of the seal rather than of
//! having thrown the interpreter away.
//!
//! [`Report::preamble_evaluations`] still reports the count — it is now 1
//! regardless of test count, which is the whole point, and a regression to
//! per-test replay would show up there.
//!
//! ## A refusal is proven in a child
//!
//! `assert_panics expr` lowers to `(blue-assert-panics 'expr (lambda ()
//! expr))`. A capability breach is fatal: it ends the evaluation that reaches
//! it and no `rescue` sees it, so a test cannot catch one in its own
//! interpreter. The harness turns the function back into code the way `spawn`
//! does, runs it in a fresh interpreter held to a pure frame, and passes only
//! when that child ends on the breach having made no host call. A test's
//! declaration (`test "n", {satisfies: [:nist_ac_6], target: f}`) rides in
//! each [`Outcome`], for the evidence `blue test --facts` writes.
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

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use tatara_lisp::{Atom, Sexp, Spanned};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{Interpreter, Value};

use blue_lang_runtime::literal::{render_form, render_value};

/// One declared test.
#[derive(Clone, Debug, PartialEq)]
pub struct Test {
    pub name: String,
    pub body: Sexp,
    pub declared: Declared,
}

/// What a test declares: `test "n", {satisfies: [:nist_ac_6], target: f}`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Declared {
    /// The control keywords, sorted, without the colon: `nist_ac_6`.
    pub satisfies: Vec<String>,
    /// The definition the target names, as the tree the harness runs names
    /// it: the runtime key `%root/parse_token` after resolution.
    pub target: Option<String>,
}

impl Declared {
    fn of(meta: Option<&Spanned>) -> Self {
        let Some(meta) = meta.and_then(blue_lang_syntax::test_meta) else {
            return Self::default();
        };
        Self {
            satisfies: meta
                .satisfies
                .iter()
                .map(|(c, _)| (*c).to_string())
                .collect(),
            target: blue_lang_syntax::target_key(&meta).map(str::to_string),
        }
    }
}

/// Assertions that held and assertions that failed.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Tally {
    pub passed: u64,
    pub failed: u64,
}

/// What one test did: its declaration, its verdict, and what it cost.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Outcome {
    pub name: String,
    /// The top-level form the test is, in the checked program.
    pub top_level: Option<usize>,
    pub declared: Declared,
    pub passed: bool,
    /// Every assertion the test evaluated. A test that raised counts one
    /// failed assertion: the verification it was making did not hold.
    pub assertions: Tally,
    /// Evaluation steps, the children `assert_panics` ran included.
    pub steps: u64,
    /// Host calls through granted names while the test ran; 0 under a pure
    /// frame by construction.
    pub host_io: u64,
}

/// Why a test did not pass. **Two distinct outcomes, never merged**: an
/// assertion that came out false is a *finding*, while an error thrown on the
/// way there means the assertion never ran and proves nothing about it.
/// Reporting both as "failed" is how a broken test masquerades as a caught bug.
#[derive(Clone, Debug, PartialEq)]
pub enum Failure {
    /// An `assert` evaluated to something falsy. Carries the expression as
    /// canonical blue source, and — when the expression was a comparison —
    /// the value each side produced.
    Assertion {
        test: String,
        expression: String,
        operands: Option<Operands>,
    },
    /// The test raised before or instead of asserting.
    Errored { test: String, error: String },
    /// An `assert_panics` whose expression, run in a child held to a pure
    /// frame, did not end on a capability breach, or reached the host first.
    /// Carries the expression as canonical blue source and how it ended.
    NoBreach {
        test: String,
        expression: String,
        ended: String,
    },
}

/// The two sides of a failed comparison, as canonical blue source.
///
/// `assert size(xs) == 3` failing says only that the sizes differ; showing
/// `left: 2` is the difference between reading the failure and re-running
/// the test with a print in it.
#[derive(Clone, Debug, PartialEq)]
pub struct Operands {
    pub left: String,
    pub right: String,
    pub difference: Option<String>,
}

fn first_difference(a: &Value, b: &Value) -> Option<String> {
    use blue_lang_runtime::stdlib::blue_equal;
    match (a, b) {
        (Value::List(x), Value::List(y)) => {
            for (i, (p, q)) in x.iter().zip(y.iter()).enumerate() {
                if !blue_equal(p, q) {
                    let inner = first_difference(p, q).map_or_else(
                        || format!("{} vs {}", render_value(p), render_value(q)),
                        |d| d,
                    );
                    return Some(format!("[{i}]{}", path_tail(&inner)));
                }
            }
            (x.len() != y.len()).then(|| format!(" lengths {} vs {}", x.len(), y.len()))
        }
        (Value::Map(x), Value::Map(y)) => {
            let mut keys: Vec<_> = x
                .iter()
                .map(|(k, _)| k.clone())
                .chain(y.iter().map(|(k, _)| k.clone()))
                .collect();
            keys.sort_by_key(|k| render_value(&k.to_value()));
            keys.dedup();
            for k in keys {
                let p = x.iter().find(|(j, _)| *j == &k).map(|(_, v)| v.clone());
                let q = y.iter().find(|(j, _)| *j == &k).map(|(_, v)| v.clone());
                let name = render_value(&k.to_value());
                match (p, q) {
                    (Some(p), Some(q)) if !blue_equal(&p, &q) => {
                        let inner = first_difference(&p, &q).map_or_else(
                            || format!("{} vs {}", render_value(&p), render_value(&q)),
                            |d| d,
                        );
                        return Some(format!("[{name}]{}", path_tail(&inner)));
                    }
                    (Some(_), None) => return Some(format!("[{name}] only on the left")),
                    (None, Some(_)) => return Some(format!("[{name}] only on the right")),
                    _ => {}
                }
            }
            None
        }
        _ => None,
    }
}

fn path_tail(inner: &str) -> String {
    if inner.starts_with('[') || inner.starts_with(' ') {
        inner.to_string()
    } else {
        format!(": {inner}")
    }
}

impl Failure {
    pub fn test(&self) -> &str {
        match self {
            Failure::Assertion { test, .. }
            | Failure::Errored { test, .. }
            | Failure::NoBreach { test, .. } => test,
        }
    }
}

impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Failure::Assertion {
                test,
                expression,
                operands,
            } => {
                write!(f, "FAIL {test}\n  assert {expression}")?;
                if let Some(Operands {
                    left,
                    right,
                    difference,
                }) = operands
                {
                    write!(f, "\n  left:  {left}\n  right: {right}")?;
                    if let Some(d) = difference {
                        write!(f, "\n  differ: at {}", d.trim_start())?;
                    }
                }
                Ok(())
            }
            Failure::Errored { test, error } => write!(f, "ERROR {test}\n  {error}"),
            Failure::NoBreach {
                test,
                expression,
                ended,
            } => write!(
                f,
                "FAIL {test}\n  assert_panics {expression}\n  ended: {ended}"
            ),
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Report {
    pub passed: usize,
    pub failures: Vec<Failure>,
    /// How many times the file's preamble was evaluated. **One**, regardless
    /// of test count — the tests fork a prototype that already holds it.
    ///
    /// Kept rather than deleted because it was one-per-test until forks landed,
    /// and a regression to replay would show up here as a number that tracks
    /// the test count again.
    pub preamble_evaluations: usize,
    /// Each test that ran, in file order.
    pub outcomes: Vec<Outcome>,
    /// Every assertion of every test.
    pub assertions: Tally,
    /// Evaluation steps: the preamble once, then every test.
    pub steps: u64,
    /// Host calls through granted names over the whole run, when it was
    /// held to a frame; `None` for an unheld run, which counts nothing.
    pub host_io: Option<u64>,
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
    if !matches!(items.first(), Some(Sexp::Atom(Atom::Symbol(h))) if &**h == "deftest") {
        return None;
    }
    let lifted = Spanned::from_sexp_synthetic(form);
    let parts = blue_lang_syntax::test_parts(&lifted)?;
    Some(Test {
        name: parts.name.to_string(),
        body: parts.body.to_sexp(),
        declared: Declared::of(parts.meta),
    })
}

/// The host a test runs against: one flag recording whether an `assert`
/// failed, and the expression that failed.
///
/// A flag rather than an early return, because a primitive cannot unwind the
/// interpreter — and because a test with several asserts should report the
/// FIRST failure, which is the one whose cause is still local.
#[derive(Clone, Default)]
struct Recorder {
    failed: Arc<AtomicBool>,
    expression: Arc<std::sync::Mutex<Option<String>>>,
    operands: Arc<std::sync::Mutex<Option<Operands>>>,
    /// How the child of a failed `assert_panics` ended, when that was the
    /// first failure.
    ended: Arc<std::sync::Mutex<Option<String>>>,
    held: Arc<AtomicU64>,
    broken: Arc<AtomicU64>,
    /// Steps the children `assert_panics` ran spent.
    child_steps: Arc<AtomicU64>,
}

impl Recorder {
    fn count(&self, held: bool) {
        let counter = if held { &self.held } else { &self.broken };
        counter.fetch_add(1, Ordering::SeqCst);
    }

    fn tally(&self) -> Tally {
        Tally {
            passed: self.held.load(Ordering::SeqCst),
            failed: self.broken.load(Ordering::SeqCst),
        }
    }
}

/// What `assert_panics` runs its expression under: the bounds the test
/// itself runs under.
#[derive(Clone, Default)]
struct Bounds {
    steps: Option<usize>,
    interrupt: Option<Arc<AtomicBool>>,
}

/// How the child an `assert_panics` ran ended.
struct Attempt {
    ended: Result<Value, tatara_lisp_eval::EvalError>,
    host_io: u64,
    steps: u64,
}

impl Attempt {
    /// The verdict: a capability breach, with no host call made first.
    fn breached(&self) -> bool {
        matches!(&self.ended, Err(e) if blue_lang_runtime::is_breach(e)) && self.host_io == 0
    }

    fn describe(&self) -> String {
        match &self.ended {
            Ok(v) => format!("returned {}", render_value(v)),
            Err(e) if blue_lang_runtime::is_breach(e) => format!(
                "a capability breach after {} host call(s): {}",
                self.host_io,
                e.short_message()
            ),
            Err(e) => format!("raised, not a capability breach: {}", e.short_message()),
        }
    }
}

/// Run `thunk` the way a process runs a spawned function: turned back into
/// code (its helpers defined, the data it reaches copied, nothing of the
/// test's interpreter shared), in a fresh interpreter held to a pure frame,
/// whose processes are held to it too. A breach ends this child, not the
/// test, and no `rescue` inside it sees the breach.
fn attempt(thunk: &Value, bounds: &Bounds) -> Result<Attempt, String> {
    let (code, _) = blue_lang_proc::code::spawn_code(thunk, &[])?;
    let hold = blue_lang_runtime::Hold::from(blue_lang_runtime::session::pure_frame());
    let account = blue_lang_runtime::Account::default();
    let mut child = blue_lang_runtime::interpreter_hostless();
    hold.bind(&mut child, "assert_panics's pure frame", &account.host_io);
    blue_lang_runtime::attach_node_accounted(&mut child, Some(&hold), &account);
    if let Some(flag) = &bounds.interrupt {
        child.set_interrupt(Arc::clone(flag));
    }
    if let Some(steps) = bounds.steps {
        let _ = child.set_budget(tatara_lisp_eval::vm::Budget {
            fuel: Some(steps),
            ..child.budget()
        });
    }
    for (name, value) in &code.bindings {
        child.define_global(name.clone(), value.clone());
    }
    let mut ended = Ok(Value::Nil);
    for form in code.program() {
        ended = child.eval_top_form(&form, &mut ());
        if ended.is_err() {
            break;
        }
    }
    Ok(Attempt {
        ended,
        host_io: account.host_io.total(),
        steps: child.steps_spent() as u64,
    })
}

/// The harness's comparison assertion: `(blue-assert-compare 'e lhs rhs
/// result)`. Never written by the parser — [`compare_asserts`] rewrites a
/// comparison `assert` into it inside the harness, so the name is the
/// harness's own, like [`blue_lang_syntax::LOWERED_ASSERT`].
pub const ASSERT_COMPARE: &str = "blue-assert-compare";

/// The surface comparison operators whose failing `assert` reports both
/// sides. Their callees are read from `INFIX`, the one table.
const COMPARISON_OPS: &[&str] = &["==", "!=", "<", "<=", ">", ">="];

fn comparison_callee(name: &str) -> bool {
    blue_lang_syntax::INFIX
        .iter()
        .any(|i| i.callee == name && COMPARISON_OPS.contains(&i.op))
}

/// Rewrite every `(blue-assert 'e (op a b))` whose `op` is a comparison into
///
/// ```text
/// (let ((blue-assert-lhs a) (blue-assert-rhs b))
///   (blue-assert-compare 'e blue-assert-lhs blue-assert-rhs
///                        (op blue-assert-lhs blue-assert-rhs)))
/// ```
///
/// so the harness sees each side's value. Each side is evaluated once, in
/// the order it was before, in the scope it was before (`let`'s inits see
/// the outer scope); the bound names are unspellable in blue, so no user
/// name is captured. Quoted data is left alone.
#[must_use]
pub fn compare_asserts(form: &Sexp) -> Sexp {
    compare_asserts_spanned(&Spanned::from_sexp_synthetic(form)).to_sexp()
}

/// [`compare_asserts`] on the spanned tree: every node it keeps keeps its
/// span, and the nodes it builds carry the `assert`'s.
#[must_use]
pub fn compare_asserts_spanned(form: &Spanned) -> Spanned {
    use tatara_lisp::SpannedForm;
    let at = form.span;
    let node = |f: SpannedForm| Spanned::new(at, f);
    let sym = |s: &str| node(SpannedForm::Atom(Atom::Symbol(s.to_string())));
    let list = |items: Vec<Spanned>| node(SpannedForm::List(items));
    match &form.form {
        SpannedForm::List(items) => {
            let is_assert = items.first().and_then(Spanned::as_symbol)
                == Some(blue_lang_syntax::LOWERED_ASSERT);
            if is_assert && items.len() == 3 {
                if let Some([op, a, b]) = items[2].as_list() {
                    if op.as_symbol().is_some_and(comparison_callee) {
                        let (l, r) = ("blue-assert-lhs", "blue-assert-rhs");
                        return list(vec![
                            sym("let"),
                            list(vec![
                                list(vec![sym(l), compare_asserts_spanned(a)]),
                                list(vec![sym(r), compare_asserts_spanned(b)]),
                            ]),
                            list(vec![
                                sym(ASSERT_COMPARE),
                                items[1].clone(),
                                sym(l),
                                sym(r),
                                list(vec![op.clone(), sym(l), sym(r)]),
                            ]),
                        ]);
                    }
                }
            }
            Spanned::new(
                at,
                SpannedForm::List(items.iter().map(compare_asserts_spanned).collect()),
            )
        }
        SpannedForm::Quasiquote(inner) => Spanned::new(
            at,
            SpannedForm::Quasiquote(Box::new(compare_asserts_spanned(inner))),
        ),
        SpannedForm::Unquote(inner) => Spanned::new(
            at,
            SpannedForm::Unquote(Box::new(compare_asserts_spanned(inner))),
        ),
        SpannedForm::UnquoteSplice(inner) => Spanned::new(
            at,
            SpannedForm::UnquoteSplice(Box::new(compare_asserts_spanned(inner))),
        ),
        _ => form.clone(),
    }
}

/// Install the assertion primitive, recording failures into `rec`.
fn install_assert(interp: &mut Interpreter<()>, rec: &Recorder, bounds: &Bounds) {
    {
        let rec = rec.clone();
        interp.register_fn(
            ASSERT_COMPARE,
            Arity::Exact(4),
            move |args: &[Value], _host: &mut (), _span| {
                let held = truthy(&args[3]);
                rec.count(held);
                if held {
                    return Ok(Value::Bool(true));
                }
                if !rec.failed.swap(true, Ordering::SeqCst) {
                    if let Ok(mut slot) = rec.expression.lock() {
                        *slot = Some(render_form(&args[0]));
                    }
                    if let Ok(mut slot) = rec.operands.lock() {
                        *slot = Some(Operands {
                            left: render_value(&args[1]),
                            right: render_value(&args[2]),
                            difference: first_difference(&args[1], &args[2]),
                        });
                    }
                }
                Ok(Value::Bool(false))
            },
        );
    }
    {
        let rec = rec.clone();
        interp.register_fn(
            blue_lang_syntax::LOWERED_ASSERT,
            Arity::Exact(2),
            move |args: &[Value], _host: &mut (), _span| {
                let held = truthy(&args[1]);
                rec.count(held);
                if held {
                    return Ok(Value::Bool(true));
                }
                if !rec.failed.swap(true, Ordering::SeqCst) {
                    if let Ok(mut slot) = rec.expression.lock() {
                        *slot = Some(render_form(&args[0]));
                    }
                }
                Ok(Value::Bool(false))
            },
        );
    }
    let rec = rec.clone();
    let bounds = bounds.clone();
    interp.register_fn(
        blue_lang_syntax::LOWERED_ASSERT_PANICS,
        Arity::Exact(2),
        move |args: &[Value], _host: &mut (), _span| {
            let (held, ended) = match attempt(&args[1], &bounds) {
                Ok(a) => {
                    rec.child_steps.fetch_add(a.steps, Ordering::SeqCst);
                    (a.breached(), a.describe())
                }
                Err(why) => (false, format!("it could not be moved into a child: {why}")),
            };
            rec.count(held);
            if held {
                return Ok(Value::Bool(true));
            }
            if !rec.failed.swap(true, Ordering::SeqCst) {
                if let Ok(mut slot) = rec.expression.lock() {
                    *slot = Some(render_form(&args[0]));
                }
                if let Ok(mut slot) = rec.ended.lock() {
                    *slot = Some(ended);
                }
            }
            Ok(Value::Bool(false))
        },
    );
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

    // Build the interpreter and evaluate the preamble ONCE, then fork per test.
    //
    // This used to be a fresh `interpreter_hostless()` plus a preamble replay
    // inside the loop — O(tests x preamble), and measured at ~900µs per test of
    // which ~945µs was the interpreter alone, so essentially the whole cost of
    // a test was building the standard library again to get the same answer.
    //
    // The isolation is not weakened, and that is the point of using `fork`
    // rather than reusing one interpreter: a fork's own `define`s land in a
    // private frame the parent and every sibling are blind to, and a `set!`
    // reaching an inherited binding raises `SetSealed` instead of mutating
    // state the next test would observe. Test order still cannot matter — see
    // `tatara-lisp-eval/tests/fork.rs`, whose isolation gates all go red if
    // `fork` is weakened to a clone.
    let mut prototype = blue_lang_runtime::interpreter_hostless();
    // The preamble may legitimately assert at the top level, so `assert` has to
    // be bound while it runs. Each fork overwrites this with its own recorder.
    let preamble_rec = Recorder::default();
    install_assert(&mut prototype, &preamble_rec, &Bounds::default());

    let preamble_error = match eval_all(&mut prototype, &preamble) {
        Err(e) => Some(e),
        Ok(()) if preamble_rec.failed.load(Ordering::SeqCst) => {
            Some("an assertion in the file's preamble failed".to_string())
        }
        Ok(()) => None,
    };
    report.preamble_evaluations = 1;
    report.steps = prototype.steps_spent() as u64;

    // A broken preamble fails every test, exactly as it did when each test
    // replayed it. Reported per test rather than once so the shape of the
    // report does not change with the shape of the runner.
    if let Some(error) = preamble_error {
        for test in &tests {
            let ran = Ran {
                name: &test.name,
                top_level: None,
                declared: &test.declared,
                steps: 0,
                host_io: 0,
            };
            finish(&mut report, &ran, &Recorder::default(), Err(error.clone()));
        }
        return report;
    }

    for test in &tests {
        let rec = Recorder::default();
        let mut interp = prototype.fork();
        install_assert(&mut interp, &rec, &Bounds::default());
        // A process node per test, so one test's processes and mailbox are
        // not the next test's: the fork shares the prototype's node otherwise.
        blue_lang_runtime::attach_node(&mut interp);

        // Only the body: the preamble is already in the frames this fork
        // inherits. It still goes through the same erase-then-read path the
        // pipeline uses, so a test sees exactly the program `blue run` would.
        let program: Vec<Sexp> = vec![test.body.clone()];

        let ended = eval_all(&mut interp, &program);
        let ran = Ran {
            name: &test.name,
            top_level: None,
            declared: &test.declared,
            steps: interp.steps_spent() as u64,
            host_io: 0,
        };
        finish(&mut report, &ran, &rec, ended);
    }

    report
}

/// What a finished test was, beside its recorder.
struct Ran<'a> {
    name: &'a str,
    top_level: Option<usize>,
    declared: &'a Declared,
    steps: u64,
    host_io: u64,
}

/// Record a finished test: its failure, if it has one, and its outcome.
fn finish(report: &mut Report, ran: &Ran<'_>, rec: &Recorder, ended: Result<(), String>) {
    let mut assertions = rec.tally();
    let passed = match ended {
        Err(error) => {
            assertions.failed += 1;
            report.failures.push(Failure::Errored {
                test: ran.name.to_string(),
                error,
            });
            false
        }
        Ok(()) => record_verdict(report, ran.name, rec),
    };
    let steps = ran.steps + rec.child_steps.load(Ordering::SeqCst);
    report.assertions.passed += assertions.passed;
    report.assertions.failed += assertions.failed;
    report.steps += steps;
    report.outcomes.push(Outcome {
        name: ran.name.to_string(),
        top_level: ran.top_level,
        declared: ran.declared.clone(),
        passed,
        assertions,
        steps,
        host_io: ran.host_io,
    });
}

/// One `test` block of a checked program: its name, its body, the top-level
/// form it is, and what it declares.
struct Block<'a> {
    name: String,
    body: &'a Spanned,
    top_level: usize,
    declared: Declared,
}

/// What a run is held to beyond its program. The default holds it to
/// nothing more, as `blue test` runs.
#[derive(Clone, Debug, Default)]
pub struct Guard {
    /// The frame and providers: every host name it withholds raises the
    /// capability breach, in the preamble, every test and every process they
    /// start.
    pub hold: Option<blue_lang_runtime::Hold>,
    /// Steps the preamble, and then each test, may take.
    pub steps: Option<usize>,
    /// Set from another thread to halt the run.
    pub interrupt: Option<Arc<AtomicBool>>,
}

/// Run the test blocks of a checked program whose name contains `filter`,
/// on the tree `blue run` evaluates.
///
/// The spanned path, so an error in a test or in anything it calls reads
/// `file:line:col: message` with the blue call stack under it
/// (`blue_lang_runtime::observe::Fault`). `observer`, when given, watches the
/// preamble and every test (each test's fork inherits it): `blue test
/// --coverage` passes a `Recorder`.
#[must_use]
pub fn run_checked(
    checked: &blue_lang_runtime::pipeline::Checked,
    filter: Option<&str>,
    observer: Option<Arc<dyn blue_lang_runtime::observe::CallObserver>>,
) -> Report {
    run_guarded(checked, filter, observer, &Guard::default())
}

/// [`run_checked`] held to `guard`: what the language server runs to watch a
/// document's tests without letting them reach the host or run away.
#[must_use]
pub fn run_guarded(
    checked: &blue_lang_runtime::pipeline::Checked,
    filter: Option<&str>,
    observer: Option<Arc<dyn blue_lang_runtime::observe::CallObserver>>,
    guard: &Guard,
) -> Report {
    use blue_lang_runtime::observe::Fault;
    let erased = checked.erased();
    let program = &checked.program;
    let mut blocks = Vec::new();
    let mut preamble = Vec::new();
    for (i, form) in erased.iter().enumerate() {
        match blue_lang_syntax::test_parts(form) {
            Some(parts) => blocks.push(Block {
                name: parts.name.to_string(),
                body: parts.body,
                top_level: i,
                declared: Declared::of(parts.meta),
            }),
            None => preamble.push((i, form)),
        }
    }
    blocks.retain(|b| filter.is_none_or(|f| b.name.contains(f)));

    let mut report = Report::default();
    let mut prototype = blue_lang_runtime::interpreter_hostless();
    let account = blue_lang_runtime::Account::default();
    if let Some(hold) = &guard.hold {
        hold.bind(&mut prototype, "this run's frame", &account.host_io);
        blue_lang_runtime::attach_node_accounted(&mut prototype, Some(hold), &account);
    }
    let held = guard.hold.is_some();
    let bounds = Bounds {
        steps: guard.steps,
        interrupt: guard.interrupt.clone(),
    };
    if let Some(flag) = &guard.interrupt {
        prototype.set_interrupt(Arc::clone(flag));
    }
    if let Some(steps) = guard.steps {
        let _ = prototype.set_budget(tatara_lisp_eval::vm::Budget {
            fuel: Some(steps),
            ..prototype.budget()
        });
    }
    prototype.set_call_observer(observer);
    let preamble_rec = Recorder::default();
    install_assert(&mut prototype, &preamble_rec, &bounds);
    let fault = |interp: &Interpreter<()>, i: usize, e: &tatara_lisp_eval::EvalError| {
        Fault::of(program, &erased, i, e, &interp.take_trace()).to_string()
    };
    let mut preamble_error = None;
    for (i, form) in preamble {
        if let Err(e) = prototype.eval_top_form(&compare_asserts_spanned(form), &mut ()) {
            preamble_error = Some(fault(&prototype, i, &e));
            break;
        }
    }
    if preamble_error.is_none() && preamble_rec.failed.load(Ordering::SeqCst) {
        preamble_error = Some("an assertion in the file's preamble failed".to_string());
    }
    report.preamble_evaluations = 1;
    report.steps = prototype.steps_spent() as u64;
    report.host_io = held.then(|| account.host_io.total());
    if let Some(error) = preamble_error {
        for block in &blocks {
            let ran = Ran {
                name: &block.name,
                top_level: Some(block.top_level),
                declared: &block.declared,
                steps: 0,
                host_io: 0,
            };
            finish(&mut report, &ran, &Recorder::default(), Err(error.clone()));
        }
        return report;
    }

    for block in &blocks {
        let rec = Recorder::default();
        let mut interp = prototype.fork();
        install_assert(&mut interp, &rec, &bounds);
        let before = account.host_io.total();
        let ended = interp
            .eval_top_form(&compare_asserts_spanned(block.body), &mut ())
            .map(drop)
            .map_err(|e| fault(&interp, block.top_level, &e));
        let ran = Ran {
            name: &block.name,
            top_level: Some(block.top_level),
            declared: &block.declared,
            steps: interp.steps_spent() as u64,
            host_io: account.host_io.total() - before,
        };
        finish(&mut report, &ran, &rec, ended);
    }
    report.host_io = held.then(|| account.host_io.total());
    report
}

/// A finished test's verdict: its first failed assertion, or a pass.
fn record_verdict(report: &mut Report, test: &str, rec: &Recorder) -> bool {
    if !rec.failed.load(Ordering::SeqCst) {
        report.passed += 1;
        return true;
    }
    let expression = rec
        .expression
        .lock()
        .ok()
        .and_then(|s| s.clone())
        .unwrap_or_else(|| "<expression unavailable>".to_string());
    let ended = rec.ended.lock().ok().and_then(|s| s.clone());
    report.failures.push(match ended {
        Some(ended) => Failure::NoBreach {
            test: test.to_string(),
            expression,
            ended,
        },
        None => Failure::Assertion {
            test: test.to_string(),
            expression,
            operands: rec.operands.lock().ok().and_then(|s| s.clone()),
        },
    });
    false
}

// The spanless path, kept for a caller holding only parsed `Sexp` (the spec
// runner). It lifts with `Span::synthetic()` and then round-trips the erased
// forms through text, the print-then-reparse hop `blue_lang_runtime` pins as a
// silent-miscompile path; a caller with a checked program uses
// [`run_checked`], which evaluates the real tree and reports positions and
// the call stack.
fn eval_all(interp: &mut Interpreter<()>, forms: &[Sexp]) -> Result<(), String> {
    let lifted: Vec<_> = forms
        .iter()
        .map(|f| Spanned::from_sexp_synthetic(&compare_asserts(f)))
        .collect();
    let erased = blue_lang_runtime::to_sexps(&blue_lang_runtime::erase_types(&lifted));
    let text = erased
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join("\n");
    let spanned = tatara_lisp::read_spanned(&text).map_err(|e| format!("{e:?}"))?;
    // `describe`, not `Display`: the spans here index the re-printed lisp
    // text above, which no author has seen, so upstream's ` at 41..48` suffix
    // is noise — but they DO index `spanned`, so a wrong argument count can
    // still be matched to its call and name the function.
    interp
        .eval_program(&spanned, &mut ())
        .map(|_| ())
        .map_err(|e| blue_lang_runtime::messages::describe(&e, &spanned))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn report(src: &str) -> Report {
        let forms = blue_lang_syntax::parse_program(src).expect("parse");
        run(&forms)
    }

    const PREAMBLE: &str = "def add(a, b)\n  a + b\nend\n";

    /// **A failing comparison shows both sides.**
    ///
    /// Red run (2026-09-29): `eval_all` lifting the forms without
    /// `compare_asserts` — the assertion still fails, with no values:
    /// `left: None`, `right: Some(Operands { left: "3", right: "4" })`.
    #[test]
    fn a_failing_comparison_reports_both_values() {
        let r = report(&format!(
            "{PREAMBLE}test \"adds\"\n  xs = [1, 2]\n  assert add(1, 2) == size_of(xs) + 2\nend\n\
             def size_of(xs)\n  2\nend\n"
        ));
        match &r.failures[..] {
            [Failure::Assertion {
                expression,
                operands,
                ..
            }] => {
                assert_eq!(expression, "add(1, 2) == size_of(xs) + 2");
                assert_eq!(
                    operands.clone(),
                    Some(Operands {
                        left: "3".into(),
                        right: "4".into(),
                        difference: None
                    })
                );
            }
            other => panic!("expected one assertion failure: {other:?}"),
        }
        assert_eq!(
            r.failures[0].to_string(),
            "FAIL adds\n  assert add(1, 2) == size_of(xs) + 2\n  left:  3\n  right: 4"
        );
    }

    /// Values render as blue literals: a list, a string, a map.
    #[test]
    fn operands_render_as_blue_literals() {
        let r = report("test \"t\"\n  assert [1, \"a\", {k: :v}] != [1, \"a\", {k: :v}]\nend\n");
        match &r.failures[..] {
            [Failure::Assertion {
                operands: Some(o), ..
            }] => {
                assert_eq!(o.left, "[1, \"a\", {k: :v}]");
                assert_eq!(o.right, o.left);
            }
            other => panic!("{other:?}"),
        }
    }

    /// A passing comparison still passes, and a non-comparison assert carries
    /// no operands: the rewrite changes what is REPORTED, never what passes.
    #[test]
    fn the_rewrite_changes_no_verdict() {
        let r = report(&format!(
            "{PREAMBLE}test \"a\"\n  assert add(1, 2) == 3\nend\n\
             test \"b\"\n  assert add(1, 2) < 1 == false\nend\n\
             test \"c\"\n  assert false\nend\n"
        ));
        assert_eq!(r.passed, 2, "{r}");
        match &r.failures[..] {
            [Failure::Assertion { operands, .. }] => assert_eq!(operands, &None),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn a_passing_test_passes() {
        let r = report(&format!(
            "{PREAMBLE}test \"adds\"\n  assert add(1, 2) == 3\nend"
        ));
        assert!(r.ok(), "{r}");
        assert_eq!(r.passed, 1);
    }

    /// **The failure names the expression, in blue syntax.** This is the
    /// property the framework exists for: "assertion failed" alone makes the
    /// author re-derive what they were checking.
    #[test]
    fn a_failing_assertion_reports_the_expression_as_blue_source() {
        let r = report(&format!(
            "{PREAMBLE}test \"adds\"\n  assert add(1, 2) == 4\nend"
        ));
        assert!(!r.ok());
        match &r.failures[0] {
            Failure::Assertion {
                test, expression, ..
            } => {
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
    }

    /// **Isolation no longer costs a preamble replay.** One evaluation, however
    /// many tests — the forks inherit it.
    ///
    /// This asserted `== tests.len()` until forks landed, which was an honest
    /// record of a real cost and is now the regression signal: if someone
    /// reverts to a fresh interpreter per test, this number tracks the test
    /// count again and says so.
    #[test]
    fn the_preamble_is_evaluated_once_however_many_tests_there_are() {
        let preamble = "def base(x)\n  x + 1\nend\n";
        for n in [1usize, 2, 5] {
            let body: String = (0..n)
                .map(|i| format!("test \"t{i}\"\n  assert base(1) == 2\nend\n"))
                .collect();
            let r = report(&(preamble.to_string() + &body));
            assert!(r.ok(), "{r}");
            assert_eq!(r.passed, n);
            assert_eq!(
                r.preamble_evaluations, 1,
                "{n} tests must still cost exactly one preamble evaluation"
            );
        }
    }

    /// **A test may not write a binding it inherited from the preamble.**
    ///
    /// The mutable half of isolation, and the half a shared interpreter loses
    /// silently: with one interpreter this `set!` would succeed and the next
    /// test would read the mutated value. The fork refuses it.
    #[test]
    fn a_test_cannot_mutate_the_preamble_out_from_under_its_siblings() {
        let r = report(
            "counter = 0\n\
             test \"mutates\"\n  counter = 99\n  assert counter == 99\nend\n\
             test \"unaffected\"\n  assert counter == 0\nend",
        );
        assert!(
            r.ok(),
            "the second test saw the first's write — isolation is broken:\n{r}"
        );
        assert_eq!(r.passed, 2);
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
        assert_eq!(
            r.failures.len(),
            1,
            "one failure per test, not one per assert"
        );
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
        assert!(
            report("test \"t\"\n  assert 0\nend").ok(),
            "0 is truthy in blue"
        );
        assert!(!report("test \"t\"\n  assert false\nend").ok());
        assert!(!report("test \"t\"\n  assert nil\nend").ok());
    }

    #[test]
    fn split_separates_tests_from_the_preamble() {
        let forms =
            blue_lang_syntax::parse_program(&format!("{PREAMBLE}test \"a\"\n  assert true\nend"))
                .expect("parse");
        let (tests, preamble) = split(&forms);
        assert_eq!(tests.len(), 1);
        assert_eq!(tests[0].name, "a");
        assert_eq!(preamble.len(), 1, "the def stays in the preamble");
    }

    const READER: &str = "def reader(path)\n  read_file(path)\nend\n";

    #[test]
    fn assert_panics_passes_when_its_expression_breaches_in_a_pure_child() {
        let r = report(&format!(
            "{READER}test \"refused\"\n  assert_panics reader(\"/etc/hosts\")\nend\n"
        ));
        assert!(r.ok(), "{r}");
        assert_eq!(
            r.assertions,
            Tally {
                passed: 1,
                failed: 0
            }
        );
    }

    #[test]
    fn assert_panics_fails_naming_how_an_expression_that_did_not_breach_ended() {
        let r = report("test \"pure\"\n  assert_panics 1 + 1\nend\n");
        match &r.failures[..] {
            [Failure::NoBreach {
                expression, ended, ..
            }] => {
                assert_eq!(expression, "1 + 1");
                assert_eq!(ended, "returned 2");
            }
            other => panic!("expected one NoBreach failure: {other:?}"),
        }
        assert_eq!(
            r.failures[0].to_string(),
            "FAIL pure\n  assert_panics 1 + 1\n  ended: returned 2"
        );
        let raised = report("test \"raises\"\n  assert_panics raise(:boom, \"no\")\nend\n");
        match &raised.failures[..] {
            [Failure::NoBreach { ended, .. }] => {
                assert!(
                    ended.starts_with("raised, not a capability breach"),
                    "{ended}"
                );
            }
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn a_rescue_inside_the_expression_does_not_turn_a_breach_into_a_value() {
        let r = report(&format!(
            "{READER}test \"rescued\"\n  assert_panics reader(\"/etc/hosts\") rescue \"swallowed\"\nend\n"
        ));
        assert!(r.ok(), "{r}");
    }

    #[test]
    fn each_outcome_carries_its_declaration_and_its_assertions() {
        let r = report(&format!(
            "{READER}test \"declared\", {{satisfies: %i[nist_ac_6 nist_cm_7], target: reader}}\n  \
             assert_panics reader(\"x\")\n  assert 1 == 1\nend\n\
             test \"plain\"\n  assert 1 == 2\nend\n"
        ));
        assert_eq!(r.outcomes.len(), 2, "{r}");
        let declared = &r.outcomes[0];
        assert_eq!(declared.declared.satisfies, ["nist_ac_6", "nist_cm_7"]);
        assert_eq!(declared.declared.target.as_deref(), Some("reader"));
        assert!(declared.passed);
        assert_eq!(
            declared.assertions,
            Tally {
                passed: 2,
                failed: 0
            }
        );
        let plain = &r.outcomes[1];
        assert_eq!(plain.declared, Declared::default());
        assert!(!plain.passed);
        assert_eq!(
            plain.assertions,
            Tally {
                passed: 0,
                failed: 1
            }
        );
        assert_eq!(
            r.assertions,
            Tally {
                passed: 2,
                failed: 1
            }
        );
        assert!(r.steps > 0);
    }

    fn checked(src: &str) -> blue_lang_runtime::pipeline::Checked {
        let checked = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(src),
            &blue_lang_runtime::uses::NoLoader,
            None,
            blue_lang_runtime::pipeline::Checking::WithTests,
        )
        .expect("checks");
        assert!(checked.outcome.ok(), "{:?}", checked.outcome.diagnostics);
        checked
    }

    #[test]
    fn under_a_pure_frame_a_breach_outside_assert_panics_ends_its_test_past_a_rescue() {
        let src = format!(
            "{READER}test \"bare\", {{satisfies: [:nist_ac_6], target: reader}}\n  \
             got = reader(\"/nonexistent/blue-harness\") rescue \"swallowed\"\n  assert got == \"swallowed\"\nend\n"
        );
        let pure = Guard {
            hold: Some(blue_lang_runtime::Hold::from(
                blue_lang_runtime::session::pure_frame(),
            )),
            ..Guard::default()
        };
        let r = run_guarded(&checked(&src), None, None, &pure);
        match &r.failures[..] {
            [Failure::Errored { error, .. }] => {
                assert!(error.contains("capability breach"), "{error}");
            }
            other => panic!("expected the breach to end the test: {other:?}"),
        }
        assert_eq!(r.host_io, Some(0));
        assert_eq!(
            r.outcomes[0].declared.target.as_deref(),
            Some("%root/reader")
        );
        let ambient = run_guarded(&checked(&src), None, None, &Guard::default());
        assert!(ambient.ok(), "unheld, the rescue answers: {ambient}");
        assert_eq!(ambient.host_io, None);
    }
}

#[cfg(test)]
mod shadowing {

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
        // `ASSERT_COMPARE` and its two bound names are the harness's own
        // rewrite of a comparison `assert`, so they belong here too: a runtime
        // macro named `blue-assert-compare` would swallow every comparison.
        const LOWERED: &[&str] = &[
            blue_lang_syntax::LOWERED_ASSERT,
            blue_lang_syntax::LOWERED_ASSERT_PANICS,
            blue_lang_syntax::LOWERED_TEST_META,
            super::ASSERT_COMPARE,
            "blue-assert-lhs",
            "blue-assert-rhs",
        ];

        // A bare blue runtime — primitives + the Lisp stdlib, no blue
        // additions. If a name resolves here, blue's definition is the loser.
        //
        // Asked through `resolve_head`, which consults all three arbiters in
        // the evaluator's own order and says WHICH one claims the name. The
        // previous probe evaluated `(name)` and matched the error text for
        // "unbound" — it worked, and it decided a silent-failure question by
        // string comparison against a message nothing stops anyone rewording.
        let interp = blue_lang_runtime::interpreter_hostless();
        let shadowed: Vec<(&str, String)> = LOWERED
            .iter()
            .filter_map(|name| {
                interp
                    .resolve_head(name)
                    .map(|by| (*name, format!("{by:?}")))
            })
            .collect();
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
        let interp = blue_lang_runtime::interpreter_hostless();
        let missing: Vec<&str> = DELEGATED
            .iter()
            .filter(|name| interp.resolve_head(name).is_none())
            .copied()
            .collect();
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
