//! The formatter laws over EVERY `.b` file in the repository.
//!
//! `laws.rs` checks a hand-written corpus of one-line snippets, and that corpus
//! is exactly what let the formatter refuse 31 of blue's own 52 files: on
//! 2026-09-27 `format_source_lossless` refused every file with a comment inside
//! a form, drifted 12 more, and emitted 44 lines past the width (widest 211),
//! while every law in `laws.rs` stayed green. A snippet corpus proves the laws
//! over the snippets. This file proves them over the code blue is actually
//! written in, so a formatter that cannot format blue's own repository cannot
//! build.
//!
//! Five laws, per file:
//!
//! 1. **No refusal.** Every file formats.
//! 2. **Idempotence.** `fmt(fmt(s)) == fmt(s)`.
//! 3. **Round-trip.** `parse(fmt(s)) == parse(s)`, compared as trees.
//! 4. **Comments are kept, in order.** The same comment texts, in the same
//!    sequence — a count alone would pass a formatter that swapped two notes.
//! 5. **Width.** No formatted line is wider than 80 columns
//!    unless [`lawful_overflow`] says the width is not the formatter's to give.
//!
//! Tier: **CI-caught**, over a corpus that grows with the repo. The positive
//! control (`>= 40` files) keeps it from passing because the walk found
//! nothing.

use std::path::{Path, PathBuf};

mod common;

use blue_lang_fmt::format_source_lossless;
use blue_lang_syntax::parse_program;
use common::{lawful_overflow, WIDTH};

#[test]
fn the_formatter_width_is_the_law_width() {
    assert_eq!(blue_lang_fmt::WIDTH, WIDTH);
}

/// Every `.b` file under the repository root, `target/` and dot-directories
/// skipped, sorted so a failure report is stable.
fn corpus() -> Vec<PathBuf> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("..");
    let mut out = Vec::new();
    walk(&root, &mut out);
    out.sort();
    out
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for e in entries.filter_map(Result::ok) {
        let p = e.path();
        let name = e.file_name();
        let name = name.to_string_lossy();
        // symlink_metadata, so a `result` link into /nix/store is not walked:
        // the store holds OTHER revisions of these same files.
        let Ok(meta) = std::fs::symlink_metadata(&p) else {
            continue;
        };
        if meta.is_dir() {
            if name == "target" || name.starts_with('.') {
                continue;
            }
            walk(&p, out);
        } else if meta.is_file() && p.extension().is_some_and(|x| x == "b") {
            out.push(p);
        }
    }
}

/// The comment texts of `src`, in source order.
fn comment_texts(src: &str) -> Vec<String> {
    blue_lang_syntax::comments(src)
        .into_iter()
        .map(|c| c.text.trim_end().to_string())
        .collect()
}

#[derive(Default)]
struct Tally {
    files: usize,
    refused: Vec<String>,
    drifted: usize,
    over: Vec<String>,
    over_raw: usize,
    widest: usize,
    broken: Vec<String>,
}

fn tally() -> Tally {
    let mut t = Tally::default();
    for path in corpus() {
        t.files += 1;
        let name = path.display().to_string();
        let src = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{name}: {e}"));
        let once = match format_source_lossless(&src) {
            Ok(s) => s,
            Err(e) => {
                t.refused.push(format!("{name}: {e}"));
                continue;
            }
        };
        if once.trim_end() != src.trim_end() {
            t.drifted += 1;
        }
        match format_source_lossless(&once) {
            Ok(twice) if twice == once => {}
            Ok(_) => t.broken.push(format!("{name}: not idempotent")),
            Err(e) => t
                .broken
                .push(format!("{name}: its own output is refused: {e}")),
        }
        match (parse_program(&src), parse_program(&once)) {
            (Ok(a), Ok(b)) if a == b => {}
            (Ok(_), Ok(_)) => t
                .broken
                .push(format!("{name}: formatting changed the tree")),
            (_, Err(e)) => t.broken.push(format!("{name}: output does not parse: {e}")),
            (Err(e), _) => t.broken.push(format!("{name}: source does not parse: {e}")),
        }
        if comment_texts(&src) != comment_texts(&once) {
            t.broken.push(format!(
                "{name}: comments changed ({} before, {} after, or reordered)",
                comment_texts(&src).len(),
                comment_texts(&once).len()
            ));
        }
        for (i, line) in once.lines().enumerate() {
            let w = line.chars().count();
            t.widest = t.widest.max(w);
            if w > WIDTH {
                t.over_raw += 1;
            }
            if w > WIDTH && !lawful_overflow(line) {
                t.over.push(format!("{name}:{}: {w} cols: {line}", i + 1));
            }
        }
    }
    eprintln!(
        "corpus: {} files, {} refused, {} drift, {} lines over {WIDTH} ({} unlawful), widest {}",
        t.files,
        t.refused.len(),
        t.drifted,
        t.over_raw,
        t.over.len(),
        t.widest
    );
    t
}

/// POSITIVE CONTROL. A walk that found nothing would pass every law below.
#[test]
fn the_corpus_walk_finds_the_repository() {
    let n = corpus().len();
    assert!(
        n >= 40,
        "found only {n} .b files — the walk is broken, and every corpus law \
         would pass vacuously"
    );
}

/// LAW 1 — every file in the repository formats. No refusals.
#[test]
fn every_file_formats() {
    let t = tally();
    assert!(
        t.refused.is_empty(),
        "{} of {} files refused:\n{}",
        t.refused.len(),
        t.files,
        t.refused.join("\n")
    );
}

/// LAWS 2–4 — idempotent, tree-preserving, comment-preserving, per file.
#[test]
fn every_file_keeps_its_meaning_and_its_comments() {
    let t = tally();
    assert!(t.broken.is_empty(), "{}", t.broken.join("\n"));
}

/// LAW 5 — the width.
#[test]
fn no_formatted_line_is_wider_than_the_width_unless_it_must_be() {
    let t = tally();
    assert!(
        t.over.is_empty(),
        "{} line(s) over {WIDTH} with a break the formatter could have made:\n{}",
        t.over.len(),
        t.over.join("\n")
    );
}

/// The width law's own controls: it must refuse a breakable long line and
/// accept the ones no break can shorten. Without these a `lawful_overflow`
/// that returned `true` would make law 5 vacuous.
#[test]
fn the_width_law_tells_a_long_token_from_a_missed_break() {
    let long = "x".repeat(90);
    let s = format!("\"{long}\"");
    for ok in [
        format!("  {s},"),
        format!("  why: {s}"),
        format!("  msg = {s}"),
        format!("test {s}"),
        format!("  {s} +"),
        format!("  # {long}"),
        format!("  f(x) # {long}"),
    ] {
        assert!(lawful_overflow(&ok), "must be lawful: {ok}");
    }
    for bad in [
        format!("  f({s})"),
        format!("  a: {s}, b: 1"),
        format!("  {}", "abc, ".repeat(20)),
        format!("  f(x, y, {}) # note", "z".repeat(80)),
    ] {
        assert!(!lawful_overflow(&bad), "must be unlawful: {bad}");
    }
}
