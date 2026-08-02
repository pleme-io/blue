//! LSP totality — `analyse` and `hover` on every mid-edit state.
//!
//! Fifth entry point, and the one where "mid-edit" is not an edge case but the
//! *entire* workload. The parser, formatter, checker and runtime suites test
//! partial input because an LSP might hand it to them; this suite tests the LSP
//! itself, which is handed partial input on **every keystroke, by design**.
//!
//! ## `hover` is the interesting one, and the reason is the position
//!
//! `analyse(src)` takes text. `hover(src, pos)` takes text **and a cursor**,
//! and the cursor arrives from the editor — meaning it can point anywhere,
//! including places that do not exist in the buffer. An editor that is one
//! keystroke ahead of the language server will ask about line 40 of a
//! 3-line file, and it will do so routinely: the user typed, the server was
//! still analysing the previous version, and the position refers to a document
//! the server has not seen yet.
//!
//! So the out-of-bounds cases below are not adversarial inventions. They are
//! the normal consequence of a protocol where two processes disagree about the
//! document for a few milliseconds, which is every real editing session.
//!
//! Tier: **CI-caught**, finite corpus.

use blue_lang_lsp::analysis::{analyse, hover, Position};
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

/// Every prefix of every spec file must analyse without panicking.
#[test]
fn no_prefix_of_the_corpus_panics_analyse() {
    let mut checked = 0usize;
    for (name, src) in corpus() {
        for end in 0..=src.len() {
            let Some(slice) = src.get(..end) else {
                continue;
            };
            let r = std::panic::catch_unwind(|| {
                let _ = analyse(slice);
            });
            assert!(
                r.is_ok(),
                "PANIC analysing a {end}-byte prefix of {name} — this is \
                 literally every keystroke.\n---\n{slice}\n---"
            );
            checked += 1;
        }
    }
    assert!(checked > 1000, "only {checked} prefixes — gate weakened");
}

/// `hover` must survive **any** position, including ones off the end of the
/// document.
///
/// Not adversarial: an editor one keystroke ahead of the server routinely asks
/// about a position in a document the server has not received yet. Sampled
/// across files rather than exhaustively, so the suite stays fast enough to
/// keep running — a slow gate gets disabled, and a disabled gate protects
/// nothing.
#[test]
fn hover_survives_any_position_including_out_of_bounds() {
    for (name, src) in corpus() {
        let lines = src.lines().count() as u32;
        let widest = src.lines().map(|l| l.len()).max().unwrap_or(0) as u32;
        let positions = [
            Position {
                line: 0,
                character: 0,
            },
            Position {
                line: 0,
                character: u32::MAX,
            },
            Position {
                line: lines,
                character: 0,
            }, // one past the end
            Position {
                line: lines + 100,
                character: 0,
            }, // far past
            Position {
                line: u32::MAX,
                character: u32::MAX,
            }, // the pathological case
            Position {
                line: lines.saturating_sub(1),
                character: widest + 50,
            },
        ];
        for pos in positions {
            let r = std::panic::catch_unwind(|| {
                let _ = hover(&src, pos);
            });
            assert!(
                r.is_ok(),
                "PANIC on hover({name}, line {}, char {}) — an editor that is \
                 one keystroke ahead of the server sends exactly this",
                pos.line,
                pos.character
            );
        }
    }
}

/// Hover on a truncated buffer at a position past its (now shorter) end.
///
/// This is the precise race: the user deleted a chunk, the editor asked about
/// where the cursor used to be, and the server is holding the older, longer
/// text — or the newer, shorter one. Both orders must be survivable.
#[test]
fn hover_survives_the_delete_race() {
    for (name, src) in corpus() {
        let full_lines = src.lines().count() as u32;
        for frac in [2usize, 4, 8] {
            let cut = src.len() / frac;
            let Some(shorter) = src.get(..cut) else {
                continue;
            };
            // Ask the SHORTER text about a position valid only in the longer.
            let pos = Position {
                line: full_lines,
                character: 0,
            };
            let r = std::panic::catch_unwind(|| {
                let _ = hover(shorter, pos);
                let _ = analyse(shorter);
            });
            assert!(
                r.is_ok(),
                "PANIC on the delete race for {name} at 1/{frac} truncation"
            );
        }
    }
}

/// Analysis is deterministic — diagnostics must not flicker between identical
/// runs, which reads to a user as an editor bug and is near-impossible to report.
#[test]
fn analysing_the_same_source_twice_agrees() {
    for (name, src) in corpus() {
        let a = format!("{:?}", analyse(&src));
        let b = format!("{:?}", analyse(&src));
        assert_eq!(a, b, "{name}: analyse is not deterministic");
    }
}

/// Hostile sources, mirroring the other four suites so one shape cannot crash
/// a surface that a sibling suite already proved safe.
#[test]
fn hostile_sources_do_not_abort_the_lsp() {
    let deep = "(".repeat(2_000);
    let deep_blocks = "def a\n".repeat(2_000);
    for (label, src) in [
        ("empty", ""),
        ("nul", "\0"),
        ("lone-open", "("),
        ("unterminated-string", "\"abc"),
        ("dangling-def", "def"),
        ("bare-comment", "#"),
        ("crlf", "def a\r\n1\r\nend\r\n"),
        ("emoji-only", "🔥🔥🔥"),
        ("deep-parens", deep.as_str()),
        ("deep-blocks", deep_blocks.as_str()),
    ] {
        let r = std::panic::catch_unwind(|| {
            let _ = analyse(src);
            let _ = hover(
                src,
                Position {
                    line: 0,
                    character: 0,
                },
            );
        });
        assert!(r.is_ok(), "PANIC on hostile LSP input `{label}`");
    }
}

/// Regression: non-ASCII source must not panic the offset→Position mapping.
///
/// Found by the `emoji-only` case above (2026-08-01):
///
/// ```text
/// byte index 1 is not a char boundary; it is inside '🔥' (bytes 0..4)
/// ```
///
/// `LineIndex::position` clamped its offset to `len()` but never snapped it to
/// a char boundary, so any offset landing mid-codepoint aborted. Offsets come
/// from parser error spans — byte indices into a buffer the user may be
/// half-way through typing a character into — so mid-codepoint is a NORMAL
/// arrival, not a corrupt one.
///
/// Covers several scripts, not just emoji: the bug is about byte width, and
/// 2-byte (Cyrillic), 3-byte (CJK) and 4-byte (emoji) characters exercise
/// different boundary arithmetic. A fix verified only against emoji would look
/// complete while leaving the 2- and 3-byte paths untested.
#[test]
fn non_ascii_source_does_not_panic_the_offset_mapping() {
    for (label, src) in [
        ("emoji-4byte", "🔥🔥🔥"),
        ("cjk-3byte", "日本語"),
        ("cyrillic-2byte", "привет"),
        ("mixed", "def 日本\n  🔥 = 1\nend"),
        ("emoji-in-comment", "# 🔥 a comment\ndef a\n1\nend"),
        ("emoji-in-string", "\"🔥\""),
        ("unterminated-string-with-emoji", "\"🔥"),
        ("combining-marks", "e\u{0301}\u{0301}\u{0301}"),
    ] {
        let r = std::panic::catch_unwind(|| {
            let _ = analyse(src);
            let _ = hover(
                src,
                Position {
                    line: 0,
                    character: 1,
                },
            );
        });
        assert!(
            r.is_ok(),
            "PANIC on non-ASCII input `{label}` — offsets must snap to a char \
             boundary before slicing"
        );
    }
}
