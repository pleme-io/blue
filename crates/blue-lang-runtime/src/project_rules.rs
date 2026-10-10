//! The rule-plugin ABI: how a check rule written in blue is called.
//!
//! A project names its rules in its Bluefile (`rule(code, file, def)`); a rule
//! is an ordinary blue definition of one argument:
//!
//! ```text
//! def nil_predicate(form)        # form: one top-level form, as data
//!   [{at: [2, 1], message: "write x == nil", fix: tree, help: "…"}, …]
//! end
//! ```
//!
//! **In:** one top-level form of the checked file, as the parser wrote it
//! (annotations intact, nothing resolved), lowered to data the way a macro
//! receives its arguments (`tatara_lisp_eval::code::spanned_to_value`):
//! symbols are symbols, lists are lists, `quote` is `(quote x)`.
//!
//! **Out:** a list of findings, each a map: `at` (required) is the path from
//! the form to the offending node, one child index per level (`[]` is the form
//! itself); `message` (required) is a string; `help` is an optional string;
//! `fix` is an optional tree that replaces the node at `at`. Nothing else is
//! read, and a value of any other shape is a [`RuleFailure::Shape`], never a
//! guess. The code and severity are the Bluefile row's, not the rule's.
//!
//! **Why paths, not byte offsets.** A rule sees data, and data carries no
//! position; the host owns the source and resolves a path against the very
//! tree it lowered, so a rule cannot point outside the form it was given, and
//! the same rule compiled to wasm would need no access to the source at all.
//! Tree in, data out: the ABI is a pure function, which is what lets
//! `BLUE-EXECUTION.md` §I.2's wrapper run it as a module later.
//!
//! **The frame.** A rule runs under [`permits`]: every name the runtime binds
//! except the host effects (`blue_lang_waku::Capability`'s five host
//! bundles), printing, and the doors that evaluate data (`eval`, `require`,
//! `provide`). It is checked over the rule's whole program, imported bidamas
//! included, before anything runs, and a refused name the interpreter binds is
//! rebound to a refusal (`hosted::load_hosted_in_frame`). Each call runs under
//! a step budget; running past it is [`RuleFailure::Exhausted`], reported as a
//! failure of the rule, never a crash of the check.

use std::fmt;

use tatara_lisp::{Sexp, Spanned};
use tatara_lisp_eval::persist::Map;
use tatara_lisp_eval::value::MapKey;
use tatara_lisp_eval::vm::Budget;
use tatara_lisp_eval::Value;

use crate::hosted::{load_hosted_in_frame, CallError, FramedError, Hosted};
use crate::uses::{Entry, Loader};

/// The evaluation steps one rule may spend on one form, and on loading its
/// program. A bound: a terminating rule under it reports the same findings.
pub const RULE_STEPS: usize = 10_000_000;

/// The names that evaluate data or reach another module, refused besides the
/// host effects.
const EVALUATES: &[&str] = &["eval", "require", "provide"];

/// The rule frame: may a rule name `name`?
#[must_use]
pub fn permits(name: &str) -> bool {
    let host = blue_lang_waku::Capability::ALL
        .iter()
        .any(|c| c.is_host_effect() && c.grants(name));
    let prints = crate::docs::doc_of(name).is_some_and(|d| d.topic == crate::docs::Topic::Output);
    !host && !prints && !EVALUATES.contains(&name)
}

/// What a rule reported, before the host resolves it against the source.
#[derive(Clone, Debug, PartialEq)]
pub struct RawFinding {
    /// The child-index path from the form to the node.
    pub at: Vec<usize>,
    pub message: String,
    pub help: Option<String>,
    /// The tree that replaces the node at `at`.
    pub fix: Option<Sexp>,
}

/// Why a rule produced no findings for a form.
#[derive(Clone, Debug, PartialEq)]
pub enum RuleFailure {
    /// Its program did not parse, check or load.
    Load(String),
    /// Its program names what the frame refuses.
    Escapes(Vec<String>),
    /// Its file defines no such function.
    Undefined(String),
    /// It ran past its budget.
    Exhausted(String),
    /// It raised.
    Raised(String),
    /// It returned something that is not a list of findings.
    Shape(String),
}

impl fmt::Display for RuleFailure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RuleFailure::Load(m) => write!(f, "its program did not load: {m}"),
            RuleFailure::Escapes(names) => write!(
                f,
                "it names {} outside the rule frame: {}",
                if names.len() == 1 { "a name" } else { "names" },
                names.join(", ")
            ),
            RuleFailure::Undefined(m) => write!(f, "{m}"),
            RuleFailure::Exhausted(m) => write!(f, "it ran past its budget: {m}"),
            RuleFailure::Raised(m) => write!(f, "it raised: {m}"),
            RuleFailure::Shape(m) => write!(f, "it returned {m}"),
        }
    }
}

/// A rule file, loaded under the rule frame, whose definitions can be called.
pub struct RuleProgram {
    hosted: Hosted<()>,
}

fn budget(steps: usize) -> Budget {
    Budget {
        fuel: Some(steps),
        max_depth: Some(crate::execution_bounds().max_call_depth),
        quantum: None,
    }
}

impl RuleProgram {
    /// Parse, check, frame-check and load a rule file.
    ///
    /// # Errors
    ///
    /// [`RuleFailure::Escapes`] for a program reaching outside the frame,
    /// [`RuleFailure::Load`] for every other refusal.
    pub fn load(entry: Entry<'_>, loader: &dyn Loader, steps: usize) -> Result<Self, RuleFailure> {
        match load_hosted_in_frame(entry, loader, &mut (), |_| {}, &permits, budget(steps)) {
            Ok(hosted) => Ok(Self { hosted }),
            Err(FramedError::Escapes { names }) => Err(RuleFailure::Escapes(names)),
            Err(FramedError::Run(e)) => Err(RuleFailure::Load(e.to_string())),
        }
    }

    /// Call `def` on one form under a budget of `steps`.
    ///
    /// # Errors
    ///
    /// A [`RuleFailure`] naming why the rule produced nothing.
    pub fn run(
        &mut self,
        def: &str,
        form: &Spanned,
        steps: usize,
    ) -> Result<Vec<RawFinding>, RuleFailure> {
        let arg = tatara_lisp_eval::code::spanned_to_value(form);
        let value = self
            .hosted
            .call_budgeted(def, vec![arg], &mut (), budget(steps))
            .map_err(|e| match e {
                CallError::Exhausted { .. } => {
                    RuleFailure::Exhausted(crate::pipeline::display_keys(&e.to_string()))
                }
                CallError::Raised { .. } => {
                    RuleFailure::Raised(crate::pipeline::display_keys(&e.to_string()))
                }
                CallError::Undefined(_) | CallError::NotAFunction { .. } => {
                    RuleFailure::Undefined(e.to_string())
                }
            })?;
        findings_of(&value)
    }
}

fn findings_of(value: &Value) -> Result<Vec<RawFinding>, RuleFailure> {
    match value {
        Value::Nil => Ok(Vec::new()),
        Value::List(items) => items.iter().map(finding_of).collect(),
        other => Err(RuleFailure::Shape(format!(
            "{}, where a list of findings belongs",
            other.type_name()
        ))),
    }
}

fn field<'a>(m: &'a Map, key: &str) -> Option<&'a Value> {
    m.get(&MapKey::Keyword(std::sync::Arc::from(key)))
        .filter(|v| !matches!(v, Value::Nil))
}

fn finding_of(v: &Value) -> Result<RawFinding, RuleFailure> {
    let Value::Map(m) = v else {
        return Err(RuleFailure::Shape(format!(
            "a finding that is {}, not a map",
            v.type_name()
        )));
    };
    let at = match field(m, "at") {
        Some(Value::List(xs)) => xs
            .iter()
            .map(|x| match x {
                Value::Int(n) if *n >= 0 => usize::try_from(*n).ok(),
                _ => None,
            })
            .collect::<Option<Vec<usize>>>()
            .ok_or_else(|| RuleFailure::Shape("an `at` that is not a list of indices".into()))?,
        Some(Value::Nil) | None => Vec::new(),
        Some(other) => {
            return Err(RuleFailure::Shape(format!(
                "an `at` that is {}, not a list of indices",
                other.type_name()
            )))
        }
    };
    let text = |key: &str, required: bool| -> Result<Option<String>, RuleFailure> {
        match field(m, key) {
            Some(Value::Str(s)) => Ok(Some(s.to_string())),
            None if !required => Ok(None),
            None => Err(RuleFailure::Shape(format!("a finding with no `{key}`"))),
            Some(other) => Err(RuleFailure::Shape(format!(
                "a `{key}` that is {}, not a string",
                other.type_name()
            ))),
        }
    };
    let message = text("message", true)?.unwrap_or_default();
    let help = text("help", false)?;
    let fix = match field(m, "fix") {
        None => None,
        Some(tree) => Some(
            tatara_lisp_eval::code::value_to_spanned(tree, tatara_lisp::Span::synthetic())
                .map_err(|e| RuleFailure::Shape(format!("a `fix` that is not a tree: {e}")))?
                .to_sexp(),
        ),
    };
    Ok(RawFinding {
        at,
        message,
        help,
        fix,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::uses::NoLoader;

    fn form(src: &str) -> Spanned {
        blue_lang_syntax::parse_program_tree(src)
            .expect("parse")
            .remove(0)
    }

    fn load(src: &str) -> Result<RuleProgram, RuleFailure> {
        RuleProgram::load(Entry::anonymous(src), &NoLoader, RULE_STEPS)
    }

    /// The frame refuses the host and printing, and admits the pure stdlib.
    ///
    /// Red run (2026-10-10): `!host &&` dropped from `permits`: `read_file`
    /// was admitted and the first assertion failed.
    #[test]
    fn the_rule_frame_refuses_the_host_printing_and_eval() {
        for refused in [
            "read_file",
            "rm_rf",
            "exec_capture",
            "getenv",
            "now",
            "http_request",
        ] {
            assert!(!permits(refused), "{refused}");
        }
        for refused in ["write_stdout", "println", "eval", "require"] {
            assert!(!permits(refused), "{refused}");
        }
        for admitted in [
            "map", "filter", "first", "to_s", "symbol?", "list", "define",
        ] {
            assert!(permits(admitted), "{admitted}");
        }
    }

    #[test]
    fn a_rule_reports_findings_with_paths_messages_and_fixes() {
        let mut p = load(
            "def r(form)\n  tree = quote\n    b(unquote(nth(2, form)))\n  end\n  [{at: [2], message: \"two\", help: \"h\", fix: tree}]\nend\n",
        )
        .expect("loads");
        let got = p.run("r", &form("f(1, 2)\n"), RULE_STEPS).expect("runs");
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].at, vec![2]);
        assert_eq!(got[0].message, "two");
        assert_eq!(got[0].help.as_deref(), Some("h"));
        assert_eq!(
            got[0].fix.as_ref().map(ToString::to_string).as_deref(),
            Some("(b 2)")
        );
    }

    #[test]
    fn a_rule_receives_the_form_as_data() {
        let mut p = load(
            "def r(form)\n  if symbol?(first(form)) && to_s(first(form)) == \"f\"\n    [{at: [], message: \"a call to f\"}]\n  else\n    []\n  end\nend\n",
        )
        .expect("loads");
        assert_eq!(p.run("r", &form("f(1)\n"), RULE_STEPS).unwrap().len(), 1);
        assert!(p.run("r", &form("g(1)\n"), RULE_STEPS).unwrap().is_empty());
    }

    /// A rule that names what the frame refuses never runs. This crate's
    /// tests build without `sys`, so the host names are unbound here and the
    /// check stage refuses them first; printing and `eval` are bound, and
    /// the frame is what refuses them. `blue-lang-cli`'s `project_rules`
    /// test shows `read_file` refused by the frame where it is bound.
    ///
    /// Red run (2026-10-10): the escape check in `load_hosted_in_frame`
    /// skipped: the program loaded, and the assertion failed on `Ok`.
    #[test]
    fn a_rule_naming_a_refused_name_is_refused_by_the_frame() {
        let err = load("def r(form)\n  display(form)\n  eval(form)\nend\n")
            .err()
            .expect("refused");
        assert_eq!(
            err,
            RuleFailure::Escapes(vec!["display".into(), "eval".into()])
        );
    }

    /// A runaway rule is stopped by its budget and reported as a failure.
    ///
    /// Red run (2026-10-10): `fuel: Some(steps)` replaced by `fuel: None` in
    /// `budget`: the test had not returned after a minute, and was stopped.
    #[test]
    fn a_runaway_rule_is_exhausted_not_a_crash() {
        let mut p = load("def spin(n)\n  spin(n + 1)\nend\n\ndef r(form)\n  spin(0)\nend\n")
            .expect("loads");
        let err = p.run("r", &form("f(1)\n"), 10_000).unwrap_err();
        assert!(matches!(err, RuleFailure::Exhausted(_)), "{err:?}");
        assert!(err.to_string().contains("budget"), "{err}");
    }

    #[test]
    fn a_value_that_is_not_findings_is_a_shape_failure() {
        for body in ["1", "[1]", "[{message: \"m\", at: \"x\"}]", "[{at: []}]"] {
            let mut p = load(&format!("def r(form)\n  {body}\nend\n")).expect("loads");
            let err = p.run("r", &form("f(1)\n"), RULE_STEPS).unwrap_err();
            assert!(matches!(err, RuleFailure::Shape(_)), "{body}: {err:?}");
        }
    }
}
