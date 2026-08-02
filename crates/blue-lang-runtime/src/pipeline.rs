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
    /// **No longer reachable, and that is the point.** This reported "blue
    /// emitted a tree the reader could not read back" — a failure only a
    /// print-then-reparse hop could have. [`crate::lower_to_spanned`] deleted
    /// the hop, so there is nothing left to fail: the tree the evaluator gets
    /// IS the tree erasure produced, not a re-reading of its text.
    ///
    /// Kept rather than removed because it is public API on a released crate
    /// and a consumer may still match on it, per ★★ MODULARIZE, DON'T DELETE.
    /// It is retired, not orphaned — if a future stage ever serialises again
    /// it has a typed home. **Nothing constructs it today**; do not read its
    /// presence as evidence the pipeline can still fail this way.
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
    parse_with_depth(src, blue_lang_syntax::MAX_EXPR_DEPTH)
}

/// [`parse`] with the parser's nesting bound supplied by the caller.
///
/// The bound exists so a stack overflow — which `catch_unwind` cannot catch —
/// arrives as a typed `Err` instead. It is a *limit*, not a dialect: raising
/// it changes no program's meaning, which is exactly why it is safe to expose
/// as configuration (`blue-lang-cli`'s `config` module holds the rule).
pub fn parse_with_depth(src: &str, max_depth: usize) -> Result<Vec<Sexp>, RunError> {
    blue_lang_syntax::parse_program_with_depth(src, max_depth)
        .map_err(|e| RunError::Parse(e.to_string()))
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
    run_in_surface(src, inputs, loader, None)
}

/// Run blue source written in a `yakugo` surface.
///
/// The pack applies at PARSE time and nowhere else — by the time the checker
/// sees the program it is canonical, so every stage below is identical whatever
/// surface the author wrote in. That is what makes a surface a surface: it
/// changes how a program is spelled and nothing about how it runs.
///
/// # Errors
///
/// As [`run_with_loader`].
pub fn run_in_surface(
    src: &str,
    inputs: Inputs,
    loader: &dyn crate::uses::Loader,
    surface: Option<&blue_lang_syntax::yakugo::Yakugo>,
) -> Result<Run, RunError> {
    let forms = match surface {
        Some(pack) => blue_lang_syntax::parse_program_in(src, pack)
            .map_err(|e| RunError::Parse(e.to_string()))?,
        None => parse(src)?,
    };

    // RESOLVE imports first, so everything below sees ONE program.
    //
    // Before the check on purpose: imported code is type-checked at the point
    // its consumer imports it, rather than at whatever later moment its code
    // first runs. A package that does not typecheck should break its importer's
    // build, not their production run.
    let forms = crate::uses::resolve_uses(forms, loader).map_err(RunError::Import)?;

    // `test` blocks are declarations for the harness, not code to run.
    //
    // Dropped here rather than in `resolve_uses`, because `blue test` calls
    // the resolver and then NEEDS the entry file's blocks — so the two
    // callers want different things and the split has to live at this level.
    //
    // Without this, `blue run` on a file containing its own tests fails with
    // `unbound symbol: deftest`: every package in the bidama distribution
    // carries tests, so every one of them was unrunnable.
    let forms: Vec<_> = forms
        .into_iter()
        .filter(|f| !crate::uses::is_test_form(f))
        .collect();

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

    // LOWER to what the evaluator eats. This used to print the tree and read
    // it back through `tatara_lisp::read_spanned` — a round trip through a
    // lexer, over bytes blue had just written itself. See
    // `crate::lower_to_spanned` for why that is a silent-miscompile path and
    // not merely wasteful.
    let spanned = crate::lower_to_spanned(&erased);

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

    /// **The deleted hop was a no-op on everything blue emits — so removing it
    /// is a swap, not a behaviour change.**
    ///
    /// The old lowering printed the erased tree and read it back through
    /// `tatara_lisp::read_spanned`. This walks a corpus and asserts the two
    /// paths land on the same tree, which is the equivalence the swap rests on.
    /// It is stated as a *measurement over this corpus*, not as a theorem:
    /// the round trip is not identity in general (that is precisely why it had
    /// to go), it merely happened to be identity for the bytes blue emits.
    #[test]
    fn the_deleted_round_trip_agreed_with_the_direct_lowering() {
        let corpus = [
            "def add(a, b)\n  a + b\nend\nadd(2, 3)",
            "def fact(n)\n  if n < 2\n    1\n  else\n    n * fact(n - 1)\n  end\nend\nfact(5)",
            "def f(a, b)\n  c = a + b\n  c * 2\nend\nf(1, 2)",
            "defmacro sq(e)\n  quote\n    unquote(e) * unquote(e)\n  end\nend\nsq(2 + 3)",
            "\"a string with spaces, a ( and a )\"",
            "def g(a: Int) -> Int\n  a + 1\nend\ng(1)",
            "6 % 3",
            "1.5 + 2.25",
        ];
        for src in corpus {
            let erased = erase_types(&parse(src).expect("parse"));

            let direct: Vec<Sexp> = crate::lower_to_spanned(&erased)
                .iter()
                .map(tatara_lisp::Spanned::to_sexp)
                .collect();
            assert_eq!(direct, erased, "the direct lowering must be the identity");

            let text = erased
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join("\n");
            let round_tripped: Vec<Sexp> = tatara_lisp::read_spanned(&text)
                .unwrap_or_else(|e| panic!("{src:?}: the old path could not read back: {e:?}"))
                .iter()
                .map(tatara_lisp::Spanned::to_sexp)
                .collect();
            assert_eq!(
                round_tripped, erased,
                "{src:?}: the old print-and-reparse path changed the tree"
            );
        }
    }

    /// Anti-vacuity for the test above: the round trip really is *not* the
    /// identity in general, so agreeing on the corpus was a property of what
    /// blue happens to emit rather than a property of the reader.
    ///
    /// **`Atom::Symbol`'s `Display` writes the name raw, with no escaping.**
    /// `Atom::Str` escapes and its docs explain at length why; the symbol arm
    /// is `f.write_str(s)`. So print-then-read is not inverse over the symbol
    /// domain, and the failure is *silent*: a symbol containing a space prints
    /// as two tokens, reads back as two symbols, and the result is a perfectly
    /// well-formed tree with a different meaning. No error, nothing to catch.
    ///
    /// Measured 2026-08-02 across the separators: `a b` and `x'y` come back
    /// `Ok` with a different tree; `x)y`, `x"y` and `x;y` come back `Err`;
    /// `x{y` and `x[y` DO round-trip at this level — those two are one symbol
    /// in and one symbol out, so the brace-fusion reported in tatara *source*
    /// is not what bites a printed tree. The silent pair is what makes this a
    /// miscompile class rather than a noisy one.
    #[test]
    fn the_round_trip_is_not_the_identity_in_general() {
        let tree = Sexp::List(vec![
            Sexp::Atom(tatara_lisp::Atom::Symbol("f".into())),
            Sexp::Atom(tatara_lisp::Atom::Symbol("a b".into())),
        ]);
        let text = tree.to_string();
        let back: Vec<Sexp> = tatara_lisp::read_spanned(&text)
            .expect("it reads back cleanly — that IS the problem")
            .iter()
            .map(tatara_lisp::Spanned::to_sexp)
            .collect();
        assert_ne!(
            back,
            vec![tree.clone()],
            "if print-then-read became inverse over symbols, the class would be \
             closed upstream and this test should be deleted rather than relaxed"
        );
        // …and the direct lowering is unaffected by any of it.
        let direct: Vec<Sexp> = crate::lower_to_spanned(std::slice::from_ref(&tree))
            .iter()
            .map(tatara_lisp::Spanned::to_sexp)
            .collect();
        assert_eq!(direct, vec![tree]);
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
