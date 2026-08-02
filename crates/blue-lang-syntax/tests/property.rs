//! Property-based totality + the cross-crate differential.
//!
//! The `totality.rs` suites prove their properties over `spec/*.b` — a finite,
//! human-written corpus. This file widens that in the two directions a corpus
//! structurally cannot reach:
//!
//! 1. **Unbounded input** — proptest generates source the corpus does not
//!    contain. The generators are deliberately *structured*, not purely random:
//!    uniformly-random bytes are rejected by the lexer almost immediately and
//!    exercise nothing past it, whereas near-valid programs assembled from real
//!    tokens reach the parser's interesting paths. Random-noise fuzzing is
//!    included as one strategy among several, not as the whole plan.
//!
//! 2. **Cross-crate agreement** — the parser and the formatter must agree about
//!    what a program IS. Each is separately total (their own suites prove it)
//!    and can still disagree, and that disagreement is invisible to any test
//!    that exercises one crate at a time.
//!
//! Tier: **CI-caught**, and proptest is a *sampler* — it explores, it does not
//! prove. A passing run means "no counterexample in N cases", never "no
//! counterexample exists". Failures are reproducible via the `proptest-regressions`
//! file proptest writes next to this one; that file is a test artifact worth
//! committing, because a shrunk counterexample is expensive to rediscover.

use proptest::prelude::*;

/// Fragments the parser actually has arms for. Assembling from these produces
/// input that is *structurally plausible* — which is where a recursive-descent
/// parser breaks, unlike random bytes that die in the lexer.
fn token_fragment() -> impl Strategy<Value = String> {
    prop_oneof![
        Just("def".to_string()),
        Just("end".to_string()),
        Just("do".to_string()),
        Just("if".to_string()),
        Just("else".to_string()),
        Just("(".to_string()),
        Just(")".to_string()),
        Just("[".to_string()),
        Just("]".to_string()),
        Just("=".to_string()),
        Just("+".to_string()),
        Just("*".to_string()),
        Just(".".to_string()),
        Just(",".to_string()),
        Just("\n".to_string()),
        Just("  ".to_string()),
        Just("#".to_string()),
        Just("\"".to_string()),
        Just("1".to_string()),
        Just("x".to_string()),
        Just("🔥".to_string()),
        Just("日本".to_string()),
    ]
}

/// A "program" of shuffled real fragments — almost never valid, always plausible.
fn plausible_source() -> impl Strategy<Value = String> {
    prop::collection::vec(token_fragment(), 0..40).prop_map(|v| v.concat())
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 512, ..ProptestConfig::default() })]

    /// Totality over generated near-valid source.
    ///
    /// This is the generalisation of the corpus-prefix test: the corpus proves
    /// the parser survives truncations of programs a human wrote; this proves
    /// it survives token soup a human never would.
    #[test]
    fn parser_is_total_over_plausible_source(src in plausible_source()) {
        let r = std::panic::catch_unwind(|| {
            let _ = blue_lang_syntax::lex(&src);
            let _ = blue_lang_syntax::parse_program(&src);
        });
        prop_assert!(r.is_ok(), "PANIC on generated source:\n---\n{src}\n---");
    }

    /// Totality over arbitrary UTF-8, including control characters.
    ///
    /// Weaker than the above at finding parser bugs (most of this dies in the
    /// lexer) but it is the only strategy that covers bytes no hand-written
    /// generator would think to emit.
    #[test]
    fn parser_is_total_over_arbitrary_utf8(src in ".*") {
        let r = std::panic::catch_unwind(|| {
            let _ = blue_lang_syntax::parse_program(&src);
        });
        prop_assert!(r.is_ok(), "PANIC on arbitrary source:\n---\n{src}\n---");
    }

    /// Every PREFIX of a generated program is also survivable.
    ///
    /// Composes the two ideas: generated input *and* mid-edit truncation, which
    /// is the state an LSP is in while the user types something unusual.
    #[test]
    fn every_prefix_of_generated_source_is_total(src in plausible_source()) {
        for end in 0..=src.len() {
            let Some(slice) = src.get(..end) else { continue };
            let r = std::panic::catch_unwind(|| {
                let _ = blue_lang_syntax::parse_program(slice);
            });
            prop_assert!(r.is_ok(), "PANIC on {end}-byte prefix of:\n---\n{src}\n---");
        }
    }

    /// **Cross-crate differential: parse ∘ format ∘ parse == parse.**
    ///
    /// If a program parses, formatting it and re-parsing must yield the SAME
    /// forms. This is the property that catches a parser and formatter drifting
    /// apart — a surface form the parser accepts but the printer renders
    /// differently, so the file changes meaning when saved.
    ///
    /// Both crates are separately total; that does not make them agree, and
    /// nothing testing one crate alone can see the disagreement.
    #[test]
    fn format_preserves_meaning_over_generated_source(src in plausible_source()) {
        let Ok(before) = blue_lang_syntax::parse_program(&src) else {
            return Ok(()); // unparseable input is the totality tests' concern
        };
        let Ok(formatted) = blue_lang_fmt::format_source(&src) else {
            // A formatter that refuses a program the parser accepted is itself
            // worth knowing about, but it is a REFUSAL, not a corruption —
            // distinct failure, not this property's.
            return Ok(());
        };
        let after = blue_lang_syntax::parse_program(&formatted).map_err(|e| {
            TestCaseError::fail(format!(
                "formatter emitted source the PARSER REJECTS — that is \
                 corruption, not a style choice: {e}\n--- in ---\n{src}\n\
                 --- out ---\n{formatted}\n"
            ))
        })?;
        prop_assert_eq!(
            format!("{before:?}"),
            format!("{after:?}"),
            "format() CHANGED THE MEANING of a program.\n--- in ---\n{}\n\
             --- out ---\n{}\n",
            src,
            formatted
        );
    }

    /// Formatting is idempotent over generated input, not just the corpus.
    #[test]
    fn formatting_is_idempotent_over_generated_source(src in plausible_source()) {
        let Ok(once) = blue_lang_fmt::format_source(&src) else {
            return Ok(());
        };
        let Ok(twice) = blue_lang_fmt::format_source(&once) else {
            return Err(TestCaseError::fail(
                "format() output does not re-format — the formatter does not \
                 accept its own emission",
            ));
        };
        prop_assert_eq!(once, twice, "format(format(x)) != format(x)");
    }
}
