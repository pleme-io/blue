//! **Every rule in the registry fires on its witness, through the pipeline.**
//!
//! Each `blue_lang_check::RULES` row carries a `witness`: a program that
//! violates that rule and nothing else. This runs each one through the same
//! check stage `blue run`, `blue test` and `blue check` use, and fails unless
//! the diagnostics that come out are exactly that one code. So:
//!
//! - a row cannot be added without a program proving it can fire;
//! - a rule whose implementation stops firing turns its own row red;
//! - a witness that trips a SECOND rule is caught, which keeps each witness a
//!   precise example for `blue explain`.
//!
//! B0006 (syntax) has no tree to check, so its witness goes through
//! `pipeline::syntax_diagnostic`, the door `blue check` reports it from.
//!
//! Red run (2026-09-29): `check_names` removed from `check_stage` — the
//! B0001 and B0002 rows fail with `B0001: expected [B0001], got []`.

use blue_lang_check::{Code, Severity, RULES};
use blue_lang_runtime::pipeline::{check_entry, run, syntax_diagnostic, Checking, RunError};
use blue_lang_runtime::uses::{Entry, Loader};

/// The witness's bidamas, in memory.
struct Imports(&'static [(&'static str, &'static str)]);

impl Loader for Imports {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        self.0
            .iter()
            .find(|(n, _)| *n == name)
            .map(|(n, src)| vec![(format!("{n}.b"), (*src).to_string())])
            .ok_or_else(|| format!("no bidama named \"{name}\""))
    }
}

fn codes_with(src: &str, imports: &'static [(&'static str, &'static str)]) -> Vec<Code> {
    if let Some(d) = syntax_diagnostic(src) {
        return vec![d.code];
    }
    let checked = check_entry(
        Entry::anonymous(src),
        &Imports(imports),
        None,
        Checking::WithTests,
    )
    .unwrap_or_else(|e| panic!("{src:?}: {e}"));
    checked.outcome.diagnostics.iter().map(|d| d.code).collect()
}

fn codes_of(src: &str) -> Vec<Code> {
    codes_with(src, &[])
}

#[test]
fn every_rule_fires_on_its_witness_and_only_it() {
    let mut failures = Vec::new();
    for r in RULES {
        let got = codes_with(r.witness, r.imports);
        if got != vec![r.code] {
            failures.push(format!("{}: expected [{}], got {got:?}", r.code, r.code));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// Anti-vacuity for the test above: a program that breaks no rule produces
/// nothing, so "exactly one code" is the witness's doing.
#[test]
fn a_clean_program_produces_no_diagnostic() {
    let src = "# waive B0002: the callback shape is fixed\ndef on(event, ctx)\n  event\nend\n\n\
               def add(a: Int, b: Int) -> Int\n  a + b\nend\n\n\
               test \"adds\"\n  assert add(1, 2) == 3\nend\n";
    assert_eq!(codes_of(src), Vec::<Code>::new());
}

/// **The motivating case: a typo in a function that never runs stops
/// `blue run`.** Before the name pass it ran green, and failed only when the
/// branch was finally taken.
///
/// Red run (2026-09-29): `check_names` removed from `check_stage`:
/// `a typo in a dead function must stop the run: Ok(Run { value: Int(1),
/// visited: 0, typed_decls: 0, seams: 0 })`.
#[test]
fn a_typo_in_a_dead_function_stops_the_run() {
    let r = run("def f(xs)\n  lenght(xs)\nend\n\n1\n");
    match r {
        Err(RunError::Types(errors)) => {
            assert_eq!(errors.len(), 1, "{errors:?}");
            assert_eq!(
                errors[0],
                "<anonymous>:2:3: error[B0001]: unbound name `lenght`\n  \
                 help: did you mean `length` (builtin)?"
            );
        }
        other => panic!("a typo in a dead function must stop the run: {other:?}"),
    }
}

/// A warning is reported and does not stop the pipeline.
#[test]
fn a_warning_does_not_stop_the_run() {
    assert!(run("def f(x, unused)\n  x\nend\n\nf(1, 2)\n").is_ok());
    assert_eq!(Code::B0002.severity(), Severity::Warning);
}

/// Every diagnostic in a file comes out of ONE check, not the first only.
#[test]
fn every_diagnostic_is_reported_in_one_pass() {
    let src = "def f()\n  aa()\nend\n\ndef g()\n  bb()\nend\n\ndef h(x: Int) -> Str\n  x\nend\n";
    let got = codes_of(src);
    assert_eq!(got, vec![Code::B0001, Code::B0001, Code::B0003], "{got:?}");
}

/// **A name a builtin macro defines is bound.** `defflow(slug, …)` expands to
/// `(define slug …)`; the check stage expands top-level builtin macro calls to
/// see it. Found by the examples corpus (`examples/08_tatara_forms.b`, five
/// false positives) the day it landed.
///
/// Red run (2026-09-29): the expansion loop in `pipeline::program_names`
/// skipped — `left: [B0001, B0001]`.
#[test]
fn a_name_a_builtin_macro_defines_is_bound() {
    let src = "defflow(slug, trim, downcase)\n\nslug(\" A \")\n\n\
               defsm(door, :initial, :closed, :transitions, [[:closed, :open, :opened]])\n\ndoor(:current)\n";
    assert_eq!(codes_of(src), Vec::<Code>::new());
}
