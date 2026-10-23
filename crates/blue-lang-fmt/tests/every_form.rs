//! The round-trip law over every tree the parser can build — not only the
//! trees the snippet corpus happens to spell.
//!
//! `laws.rs`'s generator writes calls with random names, so it could never
//! name `define`, `lambda`, `deftest`, `not` or `concat`: the heads the
//! printer dispatches on. And the printer dispatches on the head alone. So
//! `q = define(zz, 5)` — a plain call whose tree is exactly a binding's —
//! printed as `q = zz = 5`, which does not parse, and every law stayed green
//! (found by the 2026-09-29 audit, `probe/q.b`). A binding had only ever been
//! written at statement position, so nothing had asked the printer to render
//! one anywhere else.
//!
//! Two things make this generator reach what that one could not:
//!
//! 1. **Call names are drawn from what the parser LOWERS TO**, read off the
//!    parser's own output over a seed corpus, plus the infix table's callees.
//!    A new lowering enters the vocabulary by being emitted, with no list here
//!    to forget to update. Only names a call can spell are kept — one
//!    identifier token, not reserved — since those are the heads a program can
//!    reach both ways.
//! 2. **Every surface form is generated in every position**: blocks as call
//!    arguments and operands, unary operators nested, assertions inside
//!    chains, strings holding the characters the lexer treats specially.
//!
//! Input that does not parse is discarded, so the law is exactly: for every
//! source the parser accepts, the formatter's output parses back to the same
//! tree, and formatting it again changes nothing.

use blue_lang_fmt::{format_forms, format_source, format_source_lossless};
use blue_lang_syntax::parse_program;
use common::gen::{program, vocabulary};
use proptest::prelude::*;

mod common;

/// The law, stated once so both properties below check the same thing.
fn round_trips(src: &str) -> Result<(), TestCaseError> {
    let Ok(before) = parse_program(src) else {
        return Err(TestCaseError::reject("not blue"));
    };
    if blue_lang_fmt::comment_count(src) > 0 {
        return Err(TestCaseError::reject("a comment inside interpolated code"));
    }
    let once = format_forms(&before);
    let after = parse_program(&once).map_err(|e| {
        TestCaseError::fail(format!(
            "output does not parse: {e}\n--- source\n{src}\n--- output\n{once}"
        ))
    })?;
    prop_assert_eq!(
        &after,
        &before,
        "tree changed\n--- source\n{}\n--- output\n{}",
        src,
        once
    );
    let twice = format_source(&once).expect("parsed a moment ago");
    prop_assert_eq!(&twice, &once, "not idempotent");
    // The door a person's file goes through renders from the SPANNED tree;
    // it must agree with the tree-only rendering on comment-free source.
    let lossless = format_source_lossless(src)
        .map_err(|e| TestCaseError::fail(format!("lossless refused: {e}\n--- source\n{src}")))?;
    prop_assert_eq!(
        &lossless,
        &once,
        "the two doors disagree\n--- source\n{}",
        src
    );
    Ok(())
}

proptest! {
    #![proptest_config(ProptestConfig {
        max_global_rejects: 1 << 16,
        ..common::config(4096)
    })]

    /// Every accepted source, formatted, parses back to the same tree.
    #[test]
    fn every_accepted_program_round_trips(src in program()) {
        round_trips(&src)?;
    }
}

/// The cases this file was written for, pinned so a regression names itself
/// without waiting for the generator to find it again.
#[test]
fn found_cases_round_trip() {
    for src in [
        "q = define(zz, 5)",
        "f(define(x, 1))",
        "[define(x, 1)]",
        "fn(y) define(x, y) end",
        "define(x, define(y, 1))",
        "(assert a) |> if a\na\nelse\na\nend",
        "(assert a) |> f",
        "(assert a) |> f(1)",
        "(assert a) |> fn(x) x end",
        "(assert a) + b",
        "(assert a) == b",
        "(assert a) and b",
        "(assert a).m(1)",
        "f((assert a))",
        "(not a) |> f",
        "(-a) |> f",
    ] {
        round_trips(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
    }
}
