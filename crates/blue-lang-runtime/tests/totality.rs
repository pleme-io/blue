//! Runtime totality — `run` must return, never abort.
//!
//! Fourth and highest-risk entry point, after the parser, formatter and
//! checker suites. `pipeline::run` takes source and *evaluates* it, so this is
//! the only one of the four where a bad input can do more than crash: it can
//! loop forever, or recurse until the stack dies.
//!
//! ## What is and is not asserted here
//!
//! **Asserted:** malformed and hostile input returns a typed `RunError` rather
//! than aborting. That is the same property the parser suite found violated —
//! deep nesting killed the process with `SIGABRT`, uncatchable — and the
//! reason to check every evaluation entry rather than assume the parser's
//! depth guard covers them all.
//!
//! **NOT asserted: termination.** A Turing-complete evaluator cannot promise
//! it, and a test that hangs is worse than a missing test — it takes CI with
//! it and gives no signal. So every input here is chosen to be *structurally*
//! hostile (unbalanced, truncated, deeply nested) rather than *semantically*
//! divergent (`loop do end`). A fuel/step bound in the interpreter is the way
//! to make divergence testable, and it is named here as absent rather than
//! quietly skipped.
//!
//! Tier: **CI-caught**, over a finite corpus.

use std::path::PathBuf;

fn corpus() -> Vec<(String, String)> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("spec");
    let mut out = Vec::new();
    for e in std::fs::read_dir(&root)
        .unwrap_or_else(|err| panic!("spec dir {} unreadable: {err}", root.display()))
        .filter_map(Result::ok)
    {
        let p = e.path();
        if p.extension().and_then(|s| s.to_str()) != Some("b") {
            continue;
        }
        let name = p.file_name().and_then(|s| s.to_str()).unwrap_or("?").to_string();
        if let Ok(src) = std::fs::read_to_string(&p) {
            out.push((name, src));
        }
    }
    out.sort();
    assert!(!out.is_empty(), "spec corpus EMPTY — suite would pass vacuously");
    out
}

/// Structurally hostile source must produce a `RunError`, not an abort.
///
/// These are the shapes that killed the parser before `MAX_EXPR_DEPTH`, plus
/// the truncations an editor produces. All are guaranteed to terminate: none
/// is a program that could loop.
#[test]
fn hostile_source_returns_a_run_error_rather_than_aborting() {
    let deep_parens = "(".repeat(2_000);
    let deep_blocks = "def a\n".repeat(2_000);
    for (label, src) in [
        ("empty", ""),
        ("nul", "\0"),
        ("lone-open", "("),
        ("lone-close", ")"),
        ("unterminated-string", "\"abc"),
        ("dangling-def", "def"),
        ("def-without-end", "def foo\n  1"),
        ("lone-end", "end"),
        ("trailing-operator", "1 +"),
        ("bare-comment", "#"),
        ("crlf", "def a\r\n1\r\nend\r\n"),
        ("emoji", "🔥"),
        ("undefined-name", "no_such_function_anywhere"),
        ("arity-nonsense", "1(2)(3)(4)"),
        ("deep-parens", deep_parens.as_str()),
        ("deep-blocks", deep_blocks.as_str()),
    ] {
        let r = std::panic::catch_unwind(|| {
            let _ = blue_lang_runtime::pipeline::run(src);
        });
        assert!(
            r.is_ok(),
            "PANIC/ABORT running hostile input `{label}` — the evaluator must \
             return RunError. shikumi, the LSP and the CLI all reach this."
        );
    }
}

/// Truncations of real programs must not abort the evaluator.
///
/// Restricted to a prefix SAMPLE rather than every prefix: unlike parsing,
/// evaluation is not cheap, and a suite that takes minutes gets disabled — a
/// disabled gate protects nothing. Sampling every 7th byte is coprime with the
/// common indent widths (2, 4, 8), so it does not systematically land on the
/// same column of every line and miss the others.
#[test]
fn truncated_programs_do_not_abort_the_evaluator() {
    let mut checked = 0usize;
    for (name, src) in corpus() {
        for end in (0..=src.len()).step_by(7) {
            let Some(slice) = src.get(..end) else { continue };
            let r = std::panic::catch_unwind(|| {
                let _ = blue_lang_runtime::pipeline::run(slice);
            });
            assert!(
                r.is_ok(),
                "PANIC/ABORT evaluating a {end}-byte prefix of {name}"
            );
            checked += 1;
        }
    }
    assert!(
        checked > 100,
        "only {checked} truncations evaluated — corpus shrank or the step is \
         too coarse, and either way this gate is weaker than it reads"
    );
}

/// Evaluation is deterministic: the same source twice yields the same verdict.
///
/// Nondeterminism in an evaluator is the hardest class of bug to report,
/// because the reporter cannot reproduce it. Cheap to pin, so pinned.
#[test]
fn running_the_same_source_twice_agrees() {
    for (name, src) in corpus() {
        let a = blue_lang_runtime::pipeline::run(&src).is_ok();
        let b = blue_lang_runtime::pipeline::run(&src).is_ok();
        assert_eq!(a, b, "{name}: run() is not deterministic across two calls");
    }
}
