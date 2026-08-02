//! Formatter totality + idempotence — the two invariants a formatter owes.
//!
//! Companion to `blue-lang-syntax/tests/totality.rs`, which found that the
//! parser **aborted the process** on deep input rather than returning `Err`.
//! The formatter has the same exposure and worse consequences: an LSP calls it
//! on every format-on-save, and `format_source` is reached by editor tooling on
//! text the user is still typing.
//!
//! Two properties, and the second is the one formatters actually break:
//!
//! 1. **Totality** — no input panics. Same corpus-prefix method as the parser
//!    suite, because every prefix is a byte-accurate model of a mid-edit buffer.
//! 2. **Idempotence** — `format(format(x)) == format(x)`. A formatter that is
//!    not idempotent makes the file oscillate between two shapes on successive
//!    saves, which shows up as spurious diffs and as two developers "fighting"
//!    through their editors. It is invisible to any test that formats once.
//!
//! Tier: **CI-caught**. Rust cannot type "does not panic", and the corpus is
//! finite — this proves the properties over these inputs, not all inputs.

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
    assert!(
        !out.is_empty(),
        "spec corpus is EMPTY — this suite would pass vacuously. Fix the path \
         rather than deleting the assert."
    );
    out
}

/// Every prefix of every spec file must return from the formatter, never abort.
#[test]
fn no_prefix_of_the_corpus_panics_the_formatter() {
    let mut checked = 0usize;
    for (name, src) in corpus() {
        for end in 0..=src.len() {
            let Some(slice) = src.get(..end) else { continue };
            let r = std::panic::catch_unwind(|| {
                let _ = blue_lang_fmt::format_source(slice);
                let _ = blue_lang_fmt::format_source_lossless(slice);
                let _ = blue_lang_fmt::comment_count(slice);
            });
            assert!(
                r.is_ok(),
                "PANIC formatting a {end}-byte prefix of {name} — this is what \
                 format-on-save sees mid-edit.\n---\n{slice}\n---"
            );
            checked += 1;
        }
    }
    assert!(
        checked > 1000,
        "only {checked} prefixes exercised — corpus shrank, gate weakened"
    );
}

/// **Idempotence.** Formatting twice must equal formatting once.
///
/// The failure this catches is not a crash — it is a file that changes on every
/// save, forever. That is invisible to a test that formats once, which is why
/// most formatters ship with this bug at least once.
#[test]
fn formatting_is_idempotent_over_the_corpus() {
    for (name, src) in corpus() {
        let Ok(once) = blue_lang_fmt::format_source(&src) else {
            continue; // unparseable input is the parser suite's problem
        };
        let twice = blue_lang_fmt::format_source(&once).unwrap_or_else(|e| {
            panic!("{name}: formatter output does not re-parse — that is worse \
                    than non-idempotence, it means format() emits invalid blue: {e}")
        });
        assert_eq!(
            once, twice,
            "{name}: format(format(x)) != format(x). The file will oscillate \
             between two shapes on successive saves."
        );
    }
}

/// The lossless formatter must not silently drop comments.
///
/// `format_source_lossless` exists precisely because the plain path loses
/// trivia; this pins that it does what its name promises. A "lossless"
/// formatter that eats comments is a name that lies, and the damage is
/// permanent — the comment is gone from the file.
#[test]
fn lossless_formatting_preserves_comment_count() {
    for (name, src) in corpus() {
        let before = blue_lang_fmt::comment_count(&src);
        if before == 0 {
            continue;
        }
        let Ok(out) = blue_lang_fmt::format_source_lossless(&src) else {
            continue;
        };
        let after = blue_lang_fmt::comment_count(&out);
        assert_eq!(
            before, after,
            "{name}: lossless formatting changed the comment count \
             ({before} -> {after}) — 'lossless' must mean it"
        );
    }
}

/// Hostile inputs, mirroring the parser suite so a crash in either is caught
/// by the same shapes rather than depending on which suite someone ran.
#[test]
fn hostile_inputs_do_not_abort_the_formatter() {
    let deep = "(".repeat(2_000);
    let deep_blocks = "def a\n".repeat(2_000);
    for (label, src) in [
        ("empty", ""),
        ("nul", "\0"),
        ("lone-open", "("),
        ("unterminated-string", "\"abc"),
        ("dangling-def", "def"),
        ("def-without-end", "def foo\n  1"),
        ("bare-comment", "#"),
        ("crlf", "def a\r\n1\r\nend\r\n"),
        ("emoji", "🔥"),
        ("deep-parens", deep.as_str()),
        ("deep-blocks", deep_blocks.as_str()),
    ] {
        let r = std::panic::catch_unwind(|| {
            let _ = blue_lang_fmt::format_source(src);
            let _ = blue_lang_fmt::format_source_lossless(src);
        });
        assert!(r.is_ok(), "PANIC formatting hostile input `{label}`");
    }
}
