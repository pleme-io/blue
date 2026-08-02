//! Checker totality — `check_program` must never panic on any parseable input.
//!
//! Third entry point in the same family as `blue-lang-syntax` and
//! `blue-lang-fmt`'s totality suites. The parser one found a real crash (deep
//! nesting aborted the process); this exists so the checker cannot hide the
//! same class.
//!
//! The exposure is identical and the reason is worth stating precisely: an LSP
//! runs diagnostics on **every keystroke**, so `check_program` is fed the AST
//! of text the user is mid-way through typing. That AST is well-formed (the
//! parser accepted it) but semantically nonsense — half-applied calls, bindings
//! with no body, references to names that do not exist yet. A checker that
//! panics on those does not produce a diagnostic; it takes the editor with it.
//!
//! `check_program` takes `&[Sexp]`, not `&str`, so this suite feeds it the
//! forms of every corpus prefix that PARSES. That is the honest input domain:
//! the checker is never handed raw text, and testing it with hand-built ASTs
//! would exercise shapes the parser cannot actually produce.
//!
//! Tier: **CI-caught**. Finite corpus; proves the property over these inputs.

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
        let name = p
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("?")
            .to_string();
        if let Ok(src) = std::fs::read_to_string(&p) {
            out.push((name, src));
        }
    }
    out.sort();
    assert!(
        !out.is_empty(),
        "spec corpus EMPTY — suite would pass vacuously"
    );
    out
}

/// Every prefix that parses must also check, without panicking.
///
/// The interesting inputs are the *partial* ones — a program truncated
/// mid-expression still parses often enough to reach the checker, and those are
/// exactly the ASTs a hand-written test never thinks to build.
#[test]
fn no_parseable_prefix_panics_the_checker() {
    let mut checked = 0usize;
    let mut reached = 0usize;
    for (name, src) in corpus() {
        for end in 0..=src.len() {
            let Some(slice) = src.get(..end) else {
                continue;
            };
            checked += 1;
            let Ok(forms) = blue_lang_syntax::parse_program(slice) else {
                continue;
            };
            reached += 1;
            let r = std::panic::catch_unwind(|| {
                let _ = blue_lang_check::check_program(&forms);
            });
            assert!(
                r.is_ok(),
                "PANIC checking a {end}-byte prefix of {name} — this is an AST \
                 an LSP produces mid-keystroke.\n---\n{slice}\n---"
            );
        }
    }
    assert!(
        checked > 1000,
        "only {checked} prefixes seen — corpus shrank, gate weakened"
    );
    // The parser rejects most truncations, which is correct — but if it
    // rejected ALL of them this suite would be vacuous while still passing.
    assert!(
        reached > 20,
        "only {reached} prefixes actually REACHED the checker out of {checked}. \
         This gate is nearly vacuous — it reports checker safety having barely \
         exercised the checker. Widen the corpus rather than lowering this."
    );
}

/// Checking is deterministic — the same forms yield the same outcome.
///
/// Nondeterminism here shows up as diagnostics that flicker in the editor
/// between identical runs, which reads as an editor bug and is nearly
/// impossible to report. Cheap to pin, so pinned.
#[test]
fn checking_the_same_forms_twice_agrees() {
    for (name, src) in corpus() {
        let Ok(forms) = blue_lang_syntax::parse_program(&src) else {
            continue;
        };
        let a = format!("{:?}", blue_lang_check::check_program(&forms));
        let b = format!("{:?}", blue_lang_check::check_program(&forms));
        assert_eq!(a, b, "{name}: check_program is not deterministic");
    }
}

/// The empty program is a valid program and must not panic.
///
/// A degenerate case, and the one a checker most often forgets: an empty buffer
/// is what an LSP sees the instant a new file is created.
#[test]
fn the_empty_program_checks_cleanly() {
    let forms = blue_lang_syntax::parse_program("").unwrap_or_default();
    let r = std::panic::catch_unwind(|| {
        let _ = blue_lang_check::check_program(&forms);
    });
    assert!(r.is_ok(), "PANIC checking an empty program");
}
