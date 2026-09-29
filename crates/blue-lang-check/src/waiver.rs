//! The one escape hatch: an in-source waiver on the offending definition.
//!
//! ```text
//! # waive B0002: the parameter is part of a callback's fixed shape
//! def on_event(event, ctx)
//!   ...
//! end
//! ```
//!
//! A waiver is a comment reading `waive <CODE>: <reason>`, on its own line,
//! above a top-level form with nothing but whitespace and other comments in
//! between. It suppresses that code in that form and nowhere else. There is no
//! file-wide waiver and no global switch, so every exception is local, named
//! and justified where it is made.
//!
//! **Waived is not deleted.** A suppressed diagnostic moves to
//! [`crate::Outcome::waived`] with its waiver, so `blue check` counts it and
//! `--format json` lists it. A waiver that names no known code or gives no
//! reason is [`B0007`](crate::Code::B0007), an error; one that suppresses
//! nothing is [`B0008`](crate::Code::B0008), a warning, because a stale waiver
//! would silently cover the next real violation.
//!
//! Comments are not in the tree (the parser drops them to keep the tree
//! canonical), so waivers are read from the file's text, and attached to a
//! top-level form by position, the same way the formatter re-attaches
//! comments.

use tatara_lisp::Span;

use crate::rules::Code;
use crate::Diagnostic;

/// A parsed waiver, attached to the top-level form below it.
#[derive(Clone, Debug, PartialEq)]
pub struct Waiver {
    pub code: Code,
    pub reason: String,
    /// The comment's span, in the file it came from.
    pub span: Span,
    /// The top-level form it covers.
    pub top_level: usize,
}

/// A diagnostic a waiver suppressed.
#[derive(Clone, Debug, PartialEq)]
pub struct Waived {
    pub diagnostic: Diagnostic,
    pub waiver: Waiver,
}

/// The codes no waiver may name: there is no tree to waive a syntax error in,
/// and waiving a malformed waiver would be a waiver nobody can read.
const UNWAIVABLE: &[Code] = &[Code::B0006, Code::B0007];

/// Read the waivers in one file.
///
/// `text` is the file; `forms` are `(top_level index, span)` for every
/// top-level form that came from it, in source order. Returns the waivers and
/// a [`B0007`](Code::B0007) for each malformed or misplaced one.
#[must_use]
pub fn collect(text: &str, forms: &[(usize, Span)]) -> (Vec<Waiver>, Vec<Diagnostic>) {
    let mut waivers = Vec::new();
    let mut malformed = Vec::new();
    for c in blue_lang_syntax::comments(text) {
        let body = c.text.trim_start_matches('#').trim();
        let Some(rest) = body.strip_prefix("waive") else {
            continue;
        };
        // `waiver` or `waived` in prose is not a waiver.
        if !rest.starts_with(char::is_whitespace) {
            continue;
        }
        // The form directly below: the first form starting after the comment
        // with only whitespace and comments between.
        let target = forms
            .iter()
            .find(|(_, s)| s.start >= c.span.end)
            .filter(|(_, s)| only_trivia(&text[c.span.end..s.start]))
            .map(|(i, _)| *i);
        let bad = |why: String| Diagnostic::new(Code::B0007, why, c.span);
        let Some(top_level) = target else {
            // Not above a top-level form: attach it to the form it sits in, if
            // any, so it is reported against the right file.
            let within = forms
                .iter()
                .rev()
                .find(|(_, s)| s.start <= c.span.start)
                .map_or(0, |(i, _)| *i);
            malformed.push(
                bad("a waiver must sit directly above a top-level definition".into())
                    .at_top_level(within)
                    .with_help("move it to the line above the `def` it waives"),
            );
            continue;
        };
        let rest = rest.trim();
        let (code_text, reason) = match rest.split_once(':') {
            Some((code, reason)) => (code.trim(), reason.trim()),
            None => (rest.split_whitespace().next().unwrap_or(""), ""),
        };
        let Some(code) = Code::parse(code_text) else {
            malformed.push(
                bad(format!("`{code_text}` is not a diagnostic code"))
                    .at_top_level(top_level)
                    .with_help(
                        "write `# waive B0001: <reason>`; `blue explain --list` lists the codes",
                    ),
            );
            continue;
        };
        if UNWAIVABLE.contains(&code) {
            malformed.push(
                bad(format!("{code} cannot be waived"))
                    .at_top_level(top_level)
                    .with_help("fix the file instead"),
            );
            continue;
        }
        if reason.is_empty() {
            malformed.push(
                bad(format!("the waiver of {code} gives no reason"))
                    .at_top_level(top_level)
                    .with_help(format!(
                        "write `# waive {code}: <why this is correct here>`"
                    )),
            );
            continue;
        }
        waivers.push(Waiver {
            code,
            reason: reason.to_string(),
            span: c.span,
            top_level,
        });
    }
    (waivers, malformed)
}

fn only_trivia(between: &str) -> bool {
    between
        .lines()
        .all(|l| l.trim().is_empty() || l.trim_start().starts_with('#'))
}

/// Move every diagnostic a waiver covers out of `diagnostics` and into the
/// returned list, and report each waiver that covered nothing
/// ([`B0008`](Code::B0008)) when `report_unused(top_level)` says so.
pub fn apply(
    diagnostics: &mut Vec<Diagnostic>,
    waivers: Vec<Waiver>,
    report_unused: &dyn Fn(usize) -> bool,
) -> Vec<Waived> {
    let mut waived = Vec::new();
    for w in waivers {
        let (hit, keep): (Vec<Diagnostic>, Vec<Diagnostic>) = std::mem::take(diagnostics)
            .into_iter()
            .partition(|d| d.code == w.code && d.top_level == w.top_level);
        *diagnostics = keep;
        if hit.is_empty() {
            if report_unused(w.top_level) {
                diagnostics.push(
                    Diagnostic::new(
                        Code::B0008,
                        format!("this waiver of {} suppresses nothing", w.code),
                        w.span,
                    )
                    .at_top_level(w.top_level)
                    .with_help("delete it"),
                );
            }
            continue;
        }
        for d in hit {
            waived.push(Waived {
                diagnostic: d,
                waiver: w.clone(),
            });
        }
    }
    waived
}

#[cfg(test)]
mod tests {
    use super::*;

    fn forms_of(src: &str) -> Vec<(usize, Span)> {
        blue_lang_syntax::parse_program_tree(src)
            .expect("parse")
            .iter()
            .enumerate()
            .map(|(i, f)| (i, f.span))
            .collect()
    }

    #[test]
    fn a_waiver_attaches_to_the_definition_below_it() {
        let src = "def a()\n  1\nend\n\n# waive B0002: fixed callback shape\ndef b(x)\n  1\nend\n";
        let (w, bad) = collect(src, &forms_of(src));
        assert!(bad.is_empty(), "{bad:?}");
        assert_eq!(w.len(), 1);
        assert_eq!(w[0].code, Code::B0002);
        assert_eq!(w[0].top_level, 1);
        assert_eq!(w[0].reason, "fixed callback shape");
    }

    #[test]
    fn prose_mentioning_waivers_is_not_a_waiver() {
        let src = "# waivers are rare\n# waived: nothing\ndef a()\n  1\nend\n";
        let (w, bad) = collect(src, &forms_of(src));
        assert!(w.is_empty() && bad.is_empty(), "{w:?} {bad:?}");
    }

    #[test]
    fn a_waiver_without_a_reason_or_code_is_malformed() {
        for src in [
            "# waive B0001\ndef a()\n  1\nend\n",
            "# waive B0001:\ndef a()\n  1\nend\n",
            "# waive B9999: no such code\ndef a()\n  1\nend\n",
            "# waive B0006: syntax cannot be waived\ndef a()\n  1\nend\n",
        ] {
            let (w, bad) = collect(src, &forms_of(src));
            assert!(w.is_empty(), "{src:?}: {w:?}");
            assert_eq!(bad.len(), 1, "{src:?}");
            assert_eq!(bad[0].code, Code::B0007);
        }
    }

    #[test]
    fn a_waiver_inside_a_definition_is_misplaced() {
        let src = "def a(x)\n  # waive B0002: inner\n  1\nend\n";
        let (w, bad) = collect(src, &forms_of(src));
        assert!(w.is_empty());
        assert_eq!(bad.len(), 1);
        assert!(
            bad[0].message.contains("directly above"),
            "{}",
            bad[0].message
        );
    }

    #[test]
    fn apply_moves_only_the_named_code_in_the_named_form() {
        let span = Span::new(0, 1);
        let mut ds = vec![
            Diagnostic::new(Code::B0002, "a", span).at_top_level(1),
            Diagnostic::new(Code::B0002, "b", span).at_top_level(2),
            Diagnostic::new(Code::B0001, "c", span).at_top_level(1),
        ];
        let w = Waiver {
            code: Code::B0002,
            reason: "r".into(),
            span,
            top_level: 1,
        };
        let waived = apply(&mut ds, vec![w], &|_| true);
        assert_eq!(waived.len(), 1);
        assert_eq!(waived[0].diagnostic.message, "a");
        let left: Vec<&str> = ds.iter().map(|d| d.message.as_str()).collect();
        assert_eq!(left, vec!["b", "c"]);
    }

    #[test]
    fn a_waiver_that_suppresses_nothing_is_reported() {
        let span = Span::new(0, 1);
        let mut ds = Vec::new();
        let w = Waiver {
            code: Code::B0001,
            reason: "r".into(),
            span,
            top_level: 0,
        };
        let waived = apply(&mut ds, vec![w], &|_| true);
        assert!(waived.is_empty());
        assert_eq!(ds.len(), 1);
        assert_eq!(ds[0].code, Code::B0008);
    }
}
