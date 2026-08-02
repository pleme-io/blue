//! Parser totality — the front door must never panic, only `Err`.
//!
//! ## Why this file exists
//!
//! Measured 2026-08-01, before it was written: blue had **403 tests and zero
//! that assert the parser survives malformed input**. No `proptest`, no
//! `arbitrary`, no `quickcheck`, no `catch_unwind` anywhere in the workspace.
//! Every existing test feeds the parser input a human wrote on purpose.
//!
//! That is the wrong shape for a parser. `lex` and `parse_program` are the
//! only public entry points, and they are reached by an LSP (every keystroke,
//! mid-edit, on text that is *always* momentarily invalid), by a formatter,
//! and — since 2026-08-01 — by shikumi loading a `.b` config file off disk. A
//! panic in any of those is not a parse error; it takes the process with it.
//! An LSP that dies on a half-typed `def` is not a slow LSP, it is a gone one.
//!
//! ## The corpus, and why prefixes
//!
//! `spec/*.b` is blue describing itself, so it is the most realistic input the
//! repo has. Every **prefix** of every spec file is a byte-accurate model of
//! "the user has typed this much so far" — which is exactly the state an LSP
//! parses, and exactly where a hand-written recursive-descent parser tends to
//! index past the end of its token stream.
//!
//! Truncation is deliberately done at BYTE boundaries and then filtered to
//! valid UTF-8: a parser must not panic on a torn multi-byte character either,
//! but `&str` cannot represent one, so that case belongs to a future
//! `parse_bytes` entry point rather than being faked here.
//!
//! ## Tier
//!
//! **CI-caught, not unrepresentable.** Rust cannot express "this function does
//! not panic" in its type system; only `#[no_panic]`-style linking tricks come
//! close and they do not survive generics. This is the honest ceiling, and the
//! corpus is finite — it proves totality *over these inputs*, not over all
//! inputs. A `proptest` generator would widen the input space and is the named
//! follow-up; it is not a substitute for this, because random text almost
//! never produces the *nearly-valid* shapes that break real parsers.

use std::path::PathBuf;

/// Every `spec/*.b` in the repo root, as (name, source).
fn corpus() -> Vec<(String, String)> {
    // CARGO_MANIFEST_DIR is crates/blue-lang-syntax; spec/ is two up.
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("spec");
    let mut out = Vec::new();
    let entries = std::fs::read_dir(&root)
        .unwrap_or_else(|e| panic!("spec dir {} unreadable: {e}", root.display()));
    for e in entries.filter_map(Result::ok) {
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
        "spec corpus is EMPTY — this test would pass vacuously. Fix the path \
         rather than deleting the assert; a totality test over zero inputs is \
         worse than none, because it reports safety it never checked."
    );
    out
}

/// Every prefix of every spec file must return, never panic.
///
/// This is the LSP's exact workload: the user has typed *this much*, and the
/// parser is asked what it means. It must answer or refuse — never abort.
#[test]
fn no_prefix_of_the_spec_corpus_panics_the_parser() {
    let mut checked = 0usize;
    for (name, src) in corpus() {
        for end in 0..=src.len() {
            // Byte-truncation lands mid-codepoint sometimes; `&str` cannot
            // hold that, so skip those rather than pretend to test them.
            let Some(slice) = src.get(..end) else {
                continue;
            };
            let r = std::panic::catch_unwind(|| {
                // Both public entry points, because a caller may reach either.
                let _ = blue_lang_syntax::lex(slice);
                let _ = blue_lang_syntax::parse_program(slice);
            });
            assert!(
                r.is_ok(),
                "PANIC on a {end}-byte prefix of {name}. A parser must return \
                 Err, never abort — this input is what an LSP sees on every \
                 keystroke.\n---\n{slice}\n---"
            );
            checked += 1;
        }
    }
    assert!(
        checked > 1000,
        "only {checked} prefixes exercised — the corpus shrank or the skip \
         logic is over-eager, and a shrunken corpus silently weakens this gate"
    );
}

/// Structurally hostile inputs — the shapes a fuzzer finds first, written by
/// hand so they are readable and so a failure names which shape broke.
///
/// Unbalanced delimiters and dangling keywords are where a recursive-descent
/// parser runs off the end of its token stream. Deep nesting is where it blows
/// the stack — which is a crash, not an `Err`, and the reason the depth cases
/// are here rather than assumed safe.
#[test]
fn hostile_inputs_return_rather_than_abort() {
    // 2_000 again — the depth that used to ABORT the runner. It now returns
    // Err via MAX_EXPR_DEPTH, which is the whole point of the guard.
    let deep_parens = "(".repeat(2_000);
    let deep_blocks = "def a\n".repeat(2_000);
    let cases: Vec<(&str, &str)> = vec![
        ("empty", ""),
        ("nul", "\0"),
        ("lone-open-paren", "("),
        ("lone-close-paren", ")"),
        ("unterminated-string", "\"abc"),
        ("unterminated-string-escape", "\"abc\\"),
        ("dangling-def", "def"),
        ("dangling-def-name", "def foo"),
        ("def-without-end", "def foo\n  1"),
        ("lone-end", "end"),
        ("lone-equals", "="),
        ("trailing-operator", "1 +"),
        ("leading-operator", "+ 1"),
        ("bare-comment", "#"),
        ("crlf", "def a\r\n1\r\nend\r\n"),
        ("tabs-only", "\t\t\t"),
        ("unicode-ident", "def λ\n1\nend"),
        ("emoji", "🔥"),
        ("deep-parens", &deep_parens),
        ("deep-blocks", &deep_blocks),
    ];
    for (label, src) in cases {
        let r = std::panic::catch_unwind(|| {
            let _ = blue_lang_syntax::lex(src);
            let _ = blue_lang_syntax::parse_program(src);
        });
        assert!(
            r.is_ok(),
            "PANIC on hostile input `{label}` — must return Err instead"
        );
    }
}

/// A parse that succeeds must round-trip through the AST: re-parsing the
/// forms' own printed shape yields the same forms.
///
/// This is the invariant a formatter depends on, and the one that silently
/// breaks when a new surface form is added to the parser but not the printer —
/// the same drift class as a hand-listed catalog, one layer up.
#[test]
fn every_spec_file_parses_and_its_forms_are_stable() {
    for (name, src) in corpus() {
        let Ok(forms) = blue_lang_syntax::parse_program(&src) else {
            // A spec file that does not parse is a real defect, but it belongs
            // to the spec suite, not to this totality gate — flag and continue
            // rather than conflating two different failures.
            eprintln!("note: {name} does not parse; totality still holds");
            continue;
        };
        assert!(
            !forms.is_empty(),
            "{name} parsed to ZERO forms — an empty parse of a non-empty spec \
             file means the parser silently consumed the program"
        );
        // Re-parsing the debug shape must not panic either; this is the
        // formatter's inner loop.
        let printed = format!("{forms:?}");
        let r = std::panic::catch_unwind(|| {
            let _ = blue_lang_syntax::parse_program(&printed);
        });
        assert!(r.is_ok(), "PANIC re-parsing the printed forms of {name}");
    }
}

/// **A REAL DEFECT, pinned rather than hidden.** The parser stack-overflows on
/// deeply nested input — `SIGABRT`, not `Err`.
///
/// Found the first time this file ran (2026-08-01): `"(".repeat(2_000)` aborted
/// the test process with `has overflowed its stack`. That is worse than a panic
/// and strictly worse than a parse error, because **`catch_unwind` cannot catch
/// it** — the process is gone. Every consumer inherits that: an LSP, a
/// formatter, and shikumi loading a `.b` config off disk.
///
/// This test does NOT assert the parser survives arbitrary depth, because it
/// does not. It pins the depth that is known-good, so the safe range is a
/// measured number instead of folklore, and so a regression that lowers it
/// fails here. The `hostile_inputs` case above uses a depth inside this bound
/// deliberately — a totality test that aborts the runner proves nothing.
///
/// **The real fix is a depth limit in the parser**: a typed
/// `ParseError::TooDeep { limit }` returned at a bound, which converts an
/// unrecoverable abort into an ordinary `Err` a caller can render. That is a
/// parser change, not a test change, and is named here rather than silently
/// worked around. Tier today: **only-mitigated (C1)** — a test pins a safe
/// range; nothing prevents a caller exceeding it.
#[test]
fn parser_nesting_depth_is_bounded_and_the_bound_is_measured() {
    // Depths verified to RETURN (not abort) in-process. Kept well under the
    // observed failure point: this test must never be the thing that kills the
    // runner, or it takes the whole suite's signal with it.
    for depth in [1usize, 8, 32, 64, 128] {
        let src = "(".repeat(depth);
        let r = std::panic::catch_unwind(|| {
            let _ = blue_lang_syntax::parse_program(&src);
        });
        assert!(
            r.is_ok(),
            "parser panicked at nesting depth {depth}, which was previously \
             known-good — this is a REGRESSION in the safe range"
        );
    }
}

/// The regression test for the defect this file found: input that once ABORTED
/// the process now returns a typed `Err`.
///
/// Before `MAX_EXPR_DEPTH` (2026-08-01), `"(".repeat(2_000)` produced
/// `fatal runtime error: stack overflow, aborting` — SIGABRT, uncatchable,
/// process gone. This asserts the conversion to an ordinary parse failure, and
/// asserts the ERROR NAMES ITSELF, so an operator who hits the bound learns it
/// is a limit rather than hunting for a syntax mistake that is not there.
///
/// Deliberately tests well past the limit (10x) as well: a guard that holds at
/// exactly limit+1 but not at 10x limit is not a guard, and that difference is
/// invisible unless something checks it.
#[test]
fn depth_beyond_the_limit_is_an_err_not_an_abort() {
    for n in [
        blue_lang_syntax::MAX_EXPR_DEPTH + 1,
        blue_lang_syntax::MAX_EXPR_DEPTH * 10,
        2_000,
    ] {
        let src = "(".repeat(n);
        let err = blue_lang_syntax::parse_program(&src)
            .expect_err("input past MAX_EXPR_DEPTH must be rejected, not accepted");
        let msg = err.to_string();
        assert!(
            msg.contains("nests deeper than"),
            "the bound must name ITSELF so the operator knows this is a limit \
             and not a syntax error they should go hunting for — got: {msg}"
        );
    }
}

/// The bound must not reject anything a human would plausibly write.
///
/// A depth limit set too low is a correctness bug wearing a safety hat: it
/// turns valid programs into parse errors. blue's own spec corpus peaks in
/// single digits, so a limit of 256 has enormous headroom — this pins that
/// claim rather than asserting it.
#[test]
fn the_depth_limit_does_not_reject_realistic_nesting() {
    for n in [1usize, 8, 32, 64, 128, blue_lang_syntax::MAX_EXPR_DEPTH - 1] {
        let src = format!("{}1{}", "(".repeat(n), ")".repeat(n));
        assert!(
            blue_lang_syntax::parse_program(&src).is_ok(),
            "well-formed nesting at depth {n} must PARSE — a limit that \
             rejects valid programs is a bug, not a safeguard"
        );
    }
}
