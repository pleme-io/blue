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
use crate::inputs::Inputs;

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
    /// A `use("name")` could not be resolved.
    ///
    /// Its own variant rather than folded into `Parse`, because the reader's
    /// next action is different: a parse error is in the source in front of
    /// them, an import error is in their packaging — a missing bidama, a
    /// BLUE_PATH that does not contain it, or no loader at all.
    #[error("import error: {0}")]
    Import(String),
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

/// Run blue source with no build inputs.
pub fn run(src: &str) -> Result<Run, RunError> {
    run_with_inputs(src, Inputs::new())
}

/// Run blue source, giving the macro phase access to verified build inputs.
///
/// `inputs` is already verified — [`Inputs`] cannot hold bytes that do not match
/// their declared hash — so nothing here re-checks. The capability a macro gains
/// is exactly "these hashed bytes", never a path.
pub fn run_with_inputs(src: &str, inputs: Inputs) -> Result<Run, RunError> {
    run_with_loader(src, inputs, &crate::uses::NoLoader)
}

/// Run blue source with a loader, so `use("name")` can resolve.
///
/// Split from [`run_with_inputs`] rather than folded into it because loading a
/// package reads a filesystem, and this crate has a `wasm32-unknown-unknown`
/// consumer with zero host imports. The capability is injected by callers that
/// have it — `blue_lang_pkg::LoadPath` is the real one — and absent by default,
/// where a `use` is a typed error naming the package.
pub fn run_with_loader(
    src: &str,
    inputs: Inputs,
    loader: &dyn crate::uses::Loader,
) -> Result<Run, RunError> {
    let forms = parse(src)?;

    // RESOLVE imports first, so everything below sees ONE program.
    //
    // Before the check on purpose: imported code is type-checked at the point
    // its consumer imports it, rather than at whatever later moment its code
    // first runs. A package that does not typecheck should break its importer's
    // build, not their production run.
    let forms = crate::uses::resolve_uses(forms, loader).map_err(RunError::Import)?;

    // CHECK, on the annotated tree — the only tree that has annotations.
    let outcome = blue_lang_check::check_program(&forms);
    if !outcome.ok() {
        return Err(RunError::Types(
            outcome
                .diagnostics
                .iter()
                .map(ToString::to_string)
                .collect(),
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
    let spanned =
        tatara_lisp::read_spanned(&text).map_err(|e| RunError::Lower(format!("{e:?}")))?;

    let mut interp = crate::interpreter_hostless();
    crate::inputs::install_input_primitives(&mut interp, inputs);
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

#[cfg(test)]
mod macro_tests {
    use super::*;

    fn int(src: &str) -> i64 {
        match run(src).unwrap_or_else(|e| panic!("{src:?}: {e}")).value {
            Value::Int(v) => v,
            other => panic!("{src:?} produced {other:?}"),
        }
    }

    /// **A blue macro expands and runs.** Tenet 2's surface, end to end.
    #[test]
    fn a_macro_expands_and_runs() {
        assert_eq!(
            int("defmacro double(x)\n  quote\n    unquote(x) + unquote(x)\n  end\nend\ndouble(21)"),
            42
        );
    }

    /// A macro receives *source forms*, not values — so it can duplicate its
    /// argument, which a function cannot do without re-evaluating it.
    #[test]
    fn a_macro_operates_on_syntax_not_values() {
        assert_eq!(
            int("defmacro sq(e)\n  quote\n    unquote(e) * unquote(e)\n  end\nend\nsq(2 + 3)"),
            25,
            "the argument form `2 + 3` must be substituted twice"
        );
    }

    /// **A runaway macro is a typed error, not a dead compiler.** This is the
    /// property that makes the metaprogramming surface safe to hand to a user.
    #[test]
    fn a_runaway_macro_fails_the_compilation_rather_than_the_process() {
        let err =
            run("defmacro forever(x)\n  quote\n    forever(unquote(x))\n  end\nend\nforever(1)")
                .expect_err("a self-referential macro must be rejected");
        let msg = err.to_string();
        assert!(
            msg.contains("forever") && msg.contains("expansion limit"),
            "the error must name the macro and the limit: {msg}"
        );
    }
}

#[cfg(test)]
mod input_tests {
    use super::*;
    use crate::inputs::{Declaration, Inputs};

    /// A schema a macro will generate code from.
    const SCHEMA: &[u8] = b"3";

    fn with_schema(src: &str) -> Result<Run, RunError> {
        let hash = Inputs::hash_of(SCHEMA);
        let mut inputs = Inputs::new();
        inputs
            .bind(
                &Declaration {
                    name: "schema".to_string(),
                    hash,
                },
                SCHEMA.to_vec(),
            )
            .expect("bind");
        run_with_inputs(src, inputs)
    }

    fn decl_line() -> String {
        let mut s = String::from("definput(\"schema\", \"");
        s.push_str(&Inputs::hash_of(SCHEMA));
        s.push_str("\")\n");
        s
    }

    /// **A macro reads a declared build input.** This is §VI OPEN #6 closed —
    /// the spec names it as gating blue's whole "stronger than Ruby's
    /// metaprogramming" claim, because a macro that cannot read a schema cannot
    /// generate code from one.
    #[test]
    fn a_macro_can_read_a_declared_build_input() {
        let src = decl_line() + "input(\"schema\")";
        let out = with_schema(&src).expect("run");
        assert!(
            matches!(out.value, Value::Str(ref s) if &**s == "3"),
            "got {:?}",
            out.value
        );
    }

    /// **An undeclared input is an error, not a file read and not nil.**
    /// Returning nil is how a macro generates an empty table and nobody notices
    /// until runtime.
    #[test]
    fn an_undeclared_input_is_an_error() {
        let err = with_schema("input(\"not_declared\")").expect_err("must fail");
        let msg = err.to_string();
        assert!(msg.contains("not_declared"), "must name it: {msg}");
        assert!(msg.contains("definput"), "and say how to declare it: {msg}");
    }

    /// **There is no path-based read at all.** The capability is the absence of
    /// the primitive, not a check inside one — so this is an unbound symbol.
    #[test]
    fn there_is_no_ambient_file_read() {
        for attempt in [
            "read_file(\"/etc/passwd\")",
            "File(\"/etc/passwd\")",
            "slurp(\"/etc/passwd\")",
            "open(\"/etc/passwd\")",
        ] {
            let err = with_schema(attempt).expect_err("must not resolve");
            assert!(
                err.to_string().contains("unbound"),
                "{attempt} must be UNBOUND — a capability removed by absence, \
                 not guarded by a check: {err}"
            );
        }
    }

    /// Anti-vacuity: with no inputs supplied at all, even a declared name fails
    /// — so the success above is the binding's doing.
    #[test]
    fn a_declared_input_with_no_bytes_supplied_fails() {
        let src = decl_line() + "input(\"schema\")";
        assert!(run(&src).is_err(), "no bytes were supplied");
    }
}

#[cfg(test)]
mod tier2_tests {
    use super::*;
    use crate::inputs::{Declaration, Inputs};

    /// **The Tier-2 conversion §V.6.3 said was gated: a macro that emits real
    /// declarations FROM A SCHEMA.**
    ///
    /// `theory/BLUE.md` §VI OPEN #6 states the blocker plainly — "tenet 2
    /// installs a `NoLoader`, so a macro cannot read a schema — which gates
    /// every Tier-2 conversion in §V.6 and therefore blue's whole 'stronger than
    /// Ruby's metaprogramming' claim."
    ///
    /// Here the schema supplies a *value the generated code depends on*, read at
    /// expansion time. Ruby and Elixir can both do this — with the whole
    /// filesystem open. blue does it through a name bound to a content hash.
    #[test]
    fn a_macro_generates_code_from_a_schema() {
        let schema = b"7";
        let mut inputs = Inputs::new();
        inputs
            .bind(
                &Declaration {
                    name: "arity".to_string(),
                    hash: Inputs::hash_of(schema),
                },
                schema.to_vec(),
            )
            .expect("bind");

        // The macro reads the input at EXPANSION time and splices the value it
        // found into the code it emits.
        let mut src = String::from("definput(\"arity\", \"");
        src.push_str(&Inputs::hash_of(schema));
        src.push_str("\")\n");
        src.push_str(
            "defmacro from_schema()\n  quote\n    unquote(to_int(input(\"arity\")))\n  end\nend\n\
             from_schema() * 6",
        );

        let out = run_with_inputs(&src, inputs).expect("run");
        assert!(
            matches!(out.value, Value::Int(42)),
            "the schema's 7 must reach the generated code: got {:?}",
            out.value
        );
    }
}
