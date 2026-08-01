//! The blue pipeline: **parse → check → erase → run**, in that order, once.
//!
//! The order is the whole reason this module exists. Each stage is available
//! separately for tools that want one, but the *default* path is a single
//! function, because two of the four orderings are silently wrong:
//!
//! - **Erase before check** discards every annotation, so a program with type
//!   errors passes. The checker sees `(define …)` and has nothing to check.
//! - **Run before check** reports a type error after the side effects.
//!
//! Neither fails loudly. Both produce a green run on a program that should
//! have been rejected. Leaving the order to each caller means every caller
//! is one reordering away from turning the type checker off — so the order
//! lives here, and callers ask for a *result*, not a sequence of steps.

use tatara_lisp::Sexp;
use tatara_lisp_eval::Value;

use crate::erase::erase_types;

/// Why a run stopped short.
#[derive(Debug, thiserror::Error)]
pub enum RunError {
    #[error("parse error: {0}")]
    Parse(String),
    /// The type checker rejected the program. Carries every diagnostic, not
    /// just the first: a caller fixing one error wants to see the rest.
    #[error("{} type error(s):\n{}", .0.len(), .0.join("\n"))]
    Types(Vec<String>),
    #[error("the emitted tatara-lisp could not be read back: {0}")]
    Lower(String),
    #[error("runtime error: {0}")]
    Eval(String),
}

/// What a run produced, plus what the checker did on the way.
#[derive(Debug)]
pub struct Run {
    pub value: Value,
    /// Nodes the type walk visited. Zero for a fully untyped program — this
    /// is what makes "no annotations, no analysis" a *measurement* rather
    /// than a claim.
    pub visited: usize,
    /// Declarations that carried an annotation.
    pub typed_decls: usize,
    /// Boundaries where typed code meets untyped code.
    pub seams: usize,
}

/// Parse blue source to tatara-lisp forms.
pub fn parse(src: &str) -> Result<Vec<Sexp>, RunError> {
    blue_lang_syntax::parse_program(src).map_err(|e| RunError::Parse(e.to_string()))
}

/// Run blue source. Checks first, erases second, executes third.
pub fn run(src: &str) -> Result<Run, RunError> {
    let forms = parse(src)?;

    // CHECK, on the annotated tree — the only tree that has annotations.
    let outcome = blue_lang_check::check_program(&forms);
    if !outcome.ok() {
        return Err(RunError::Types(
            outcome.diagnostics.iter().map(ToString::to_string).collect(),
        ));
    }

    // ERASE, so the interpreter never sees a type.
    let erased = erase_types(&forms);

    // LOWER through tatara-lisp's own reader. If blue emitted a tree the
    // reader cannot read back, that is a lowering defect and this is where it
    // surfaces rather than three stages later.
    let text = erased
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join("\n");
    let spanned = tatara_lisp::read_spanned(&text).map_err(|e| RunError::Lower(format!("{e:?}")))?;

    let mut interp = crate::interpreter_hostless();
    let value = interp
        .eval_program(&spanned, &mut ())
        .map_err(|e| RunError::Eval(e.to_string()))?;

    Ok(Run {
        value,
        visited: outcome.stats.visited,
        typed_decls: outcome.stats.typed_decls,
        seams: outcome.seams.len(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn int(src: &str) -> i64 {
        match run(src).unwrap_or_else(|e| panic!("{src:?}: {e}")).value {
            Value::Int(v) => v,
            other => panic!("{src:?} produced {other:?}"),
        }
    }

    /// **The sliding scale, as one assertion.** Annotating changes the
    /// analysis and nothing else.
    #[test]
    fn annotating_buys_analysis_and_changes_nothing_else() {
        let plain = run("def add(a, b)\n  a + b\nend\nadd(2, 3)").expect("plain");
        let typed = run("def add(a: Int, b: Int) -> Int\n  a + b\nend\nadd(2, 3)").expect("typed");

        assert!(matches!(plain.value, Value::Int(5)));
        assert!(
            matches!(typed.value, Value::Int(5)),
            "the annotated program must compute the same answer"
        );
        assert_eq!(plain.visited, 0, "no annotations means no analysis");
        assert!(
            typed.visited > 0,
            "an annotation must actually buy analysis, not just decorate"
        );
        assert_eq!(plain.typed_decls, 0);
        assert_eq!(typed.typed_decls, 1);
    }

    /// **Checking happens before erasure.** This is the test that catches the
    /// reordering: a program with a declared-type violation must be rejected,
    /// and it can only be rejected while the annotations still exist.
    #[test]
    fn a_type_error_is_reported_and_the_program_does_not_run() {
        let err = run("def add(a: Int, b: Int) -> Str\n  a + b\nend\nadd(1, 2)")
            .expect_err("a declared Str return from an Int body must be rejected");
        assert!(
            matches!(err, RunError::Types(ref d) if !d.is_empty()),
            "expected type diagnostics, got {err}"
        );
    }

    /// And the untyped version of the same program runs, so the rejection
    /// above is the annotation's doing rather than a parse failure.
    #[test]
    fn the_same_program_without_annotations_runs() {
        assert_eq!(int("def add(a, b)\n  a + b\nend\nadd(1, 2)"), 3);
    }

    #[test]
    fn a_parse_error_is_reported_as_one() {
        assert!(matches!(run("def (").unwrap_err(), RunError::Parse(_)));
    }

    /// Every stage reports in its own vocabulary, so a failure names which
    /// stage failed rather than surfacing as a generic error.
    #[test]
    fn a_runtime_error_is_reported_as_one() {
        let err = run("no_such_function(1)").expect_err("unbound");
        assert!(matches!(err, RunError::Eval(_)), "got {err}");
    }

    /// Stdlib and primitives are both reachable through the pipeline — the
    /// gap that made `6 % 3` fail.
    #[test]
    fn the_pipeline_reaches_both_runtime_layers() {
        assert_eq!(int("6 % 3"), 0);
        assert_eq!(int("7 % 3"), 1);
        assert_eq!(int("2 + 3 * 4"), 14);
    }
}
