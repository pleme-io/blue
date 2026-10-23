//! Shared by the corpus laws and the property laws: the width, and the one
//! exception to it.

#![allow(dead_code)]

pub mod gen;

use blue_lang_syntax::{lex, TokenKind};
use proptest::prelude::*;
use proptest::test_runner::FileFailurePersistence;

/// The property-test configuration every law file shares: a case count that
/// `PROPTEST_CASES` raises for a deeper run, and failures persisted beside the
/// test file that found them. The default persistence looks for `lib.rs` or
/// `main.rs` above the test and finds neither for an integration test, so it
/// warned and saved nothing; `WithSource` writes `<test>.proptest-regressions`.
pub fn config(default_cases: u32) -> ProptestConfig {
    ProptestConfig {
        cases: std::env::var("PROPTEST_CASES")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(default_cases),
        failure_persistence: Some(Box::new(FileFailurePersistence::WithSource(
            "proptest-regressions",
        ))),
        ..ProptestConfig::default()
    }
}

/// The width the law holds lines to — the operator's 80, stated here as well
/// as in the crate so that moving [`blue_lang_fmt::WIDTH`] is a red test rather
/// than a silently looser law.
pub const WIDTH: usize = 80;

/// Is `line` allowed past [`WIDTH`]?
///
/// The formatter owns every break it can make, so a long line is lawful only
/// where no break exists. Precisely, a line wider than `WIDTH` is lawful iff,
/// with its indentation removed, it is one of:
///
/// 1. **A comment, or code whose trailing comment is what overflows.** The part
///    before the comment fits. A comment is prose the formatter never rewraps,
///    and moving a trailing one would change what it annotates.
/// 2. **One long string**, as `[head] STRING [tail]`, where STRING is a single
///    string literal (plain or interpolated), which the formatter never splits;
///    `head` is at most one of the heads welded to their operand — a map label
///    `key:`, a binding `name =`, a rocket key `k =>` (one token), or the
///    keyword `test` / `when` / `assert`; and `tail` is only closing or
///    separating punctuation (`,` `)` `]` `}`) plus at most one infix operator
///    the line breaks after.
///
/// 3. **The first line of a multi-line interpolation**: `"…#{f(` where the
///    code inside `#{}` holds a block, which always breaks. The line does not
///    lex alone because the string closes lines later, and the string is the
///    token that cannot be split.
///
/// Anything else past the width is the formatter failing to break.
pub fn lawful_overflow(line: &str) -> bool {
    let body = line.trim_start();
    let Ok(toks) = lex(body) else {
        return body.contains("#{");
    };
    let toks: Vec<_> = toks
        .into_iter()
        .filter(|t| !matches!(t.kind, TokenKind::Newline | TokenKind::Eof))
        .collect();
    // (1) a comment, or code whose trailing comment overflows.
    if let Some(last) = toks.last() {
        if let TokenKind::Comment(_) = last.kind {
            let indent = line.len() - body.len();
            let code = body[..last.span.start].trim_end();
            return indent + code.chars().count() <= WIDTH;
        }
    }
    // (2) [head] STRING [tail]
    let is_str = |k: &TokenKind| matches!(k, TokenKind::Str(_) | TokenKind::InterpolatedStr { .. });
    // The longest string on the line is the one that cannot be broken; a
    // rocket key before it (`"k" => "…"`) is its head.
    let Some(s) = toks
        .iter()
        .enumerate()
        .filter(|(_, t)| is_str(&t.kind))
        .max_by_key(|(_, t)| t.span.end - t.span.start)
        .map(|(i, _)| i)
    else {
        return false;
    };
    let mut head = &toks[..s];
    match toks.get(s + 1).map(|t| &t.kind) {
        Some(TokenKind::RParen) => {
            if let [rest @ .., call, open] = head {
                if matches!(call.kind, TokenKind::Ident(_)) && open.kind == TokenKind::LParen {
                    head = rest;
                    if let [before @ .., pkg, sep] = head {
                        if matches!(pkg.kind, TokenKind::Ident(_)) && sep.kind == TokenKind::PathSep
                        {
                            head = before;
                        }
                    }
                }
            }
        }
        Some(TokenKind::RBracket) => {
            if let [rest @ .., open] = head {
                if open.kind == TokenKind::LBracket {
                    head = rest;
                }
            }
        }
        _ => {}
    }
    let head_ok = match head {
        [] => true,
        [t] => {
            matches!(&t.kind, TokenKind::Label(_))
                || matches!(&t.kind, TokenKind::Ident(k) if k == "test" || k == "when" || k == "assert")
        }
        [a, b] => {
            (matches!(a.kind, TokenKind::Ident(_))
                && matches!(&b.kind, TokenKind::Op(o) if o == "="))
                || (!matches!(a.kind, TokenKind::Comment(_)) && b.kind == TokenKind::Rocket)
        }
        _ => false,
    };
    let tail = &toks[s + 1..];
    let ops = tail
        .iter()
        .filter(|t| matches!(t.kind, TokenKind::Op(_)))
        .count();
    let tail_ok = ops <= 1
        && tail.iter().all(|t| {
            matches!(
                t.kind,
                TokenKind::Comma
                    | TokenKind::RParen
                    | TokenKind::RBracket
                    | TokenKind::RBrace
                    | TokenKind::Op(_)
            )
        });
    head_ok && tail_ok
}
