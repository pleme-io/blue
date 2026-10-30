//! `blueshift: lock invariants`: a loose definition rewritten as the typed one
//! its executions showed (`theory/BLUE.md` §V.20).
//!
//! **Transport-free**, like [`crate::analysis`]: the engine and the evidence
//! in, [`Lock`]s out. The evidence is `blue_lang_mondou::witness`:
//! observations keyed by the definition's `def_hash`, from live evaluation
//! ([`crate::live::witness`]) and from `blue test` runs. A lock is offered on
//! a loose `def` head only when every gate holds:
//!
//! 1. the observations lock (`witness::lock`): every parameter and the
//!    return saw one type the checker spells, and no type is guessed;
//! 2. the edited document, through `blue_lang_fmt::format_source_lossless`,
//!    passes the check stage with no diagnostic code the document did not
//!    already have;
//! 3. the definition's rung ([`crate::shift`]) rises.

use std::collections::BTreeMap;

use blue_lang_mondou::witness::{self, Locked, Observation};
use blue_lang_mondou::{Analysis, DefHash, Engine};
use blue_lang_runtime::uses::ResolvedProgram;
use blue_lang_syntax::{Span, Spanned};

use crate::analysis::{LineIndex, Range, TextEdit};
use crate::shift::shift_of_tree;

/// The action's title, as an editor lists it.
pub const TITLE: &str = "blueshift: lock invariants";

/// The action's kind.
pub const KIND: &str = "refactor.rewrite";

/// One definition locked: its name, the signature written, and the edit.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Lock {
    pub name: String,
    pub signature: String,
    pub edit: TextEdit,
}

struct Head {
    name: String,
    params: Vec<String>,
    sig: Span,
}

/// Every lock on a loose `def` head `range` touches in document `id`, with
/// `evidence` answering what a definition's calls showed.
#[must_use]
pub fn locks(
    engine: &Engine,
    id: &str,
    range: Range,
    evidence: &dyn Fn(&DefHash) -> Vec<Observation>,
) -> Vec<Lock> {
    let Some(a) = engine.analysis(id) else {
        return Vec::new();
    };
    let (Some(checked), Some(hashes)) = (a.checked(), a.def_hashes()) else {
        return Vec::new();
    };
    let index = LineIndex::new(&a.text);
    let program = &checked.program;
    program
        .forms()
        .iter()
        .enumerate()
        .filter(|&(i, _)| program.owner_of(i) == Some(ResolvedProgram::ENTRY))
        .filter_map(|(i, form)| {
            let head = loose_head(form)?;
            let at = index.range(Span::new(form.span.start, head.sig.end));
            if at.end < range.start || range.end < at.start {
                return None;
            }
            let locked = witness::lock(&evidence(&hashes.at(i)?.hash), head.params.len())?;
            lock_one(engine, &a, &head, &locked)
        })
        .collect()
}

/// `(define (name p …) body)` with every parameter plain.
fn loose_head(form: &Spanned) -> Option<Head> {
    let [head, sig, ..] = form.as_list()? else {
        return None;
    };
    if head.as_symbol() != Some("define") {
        return None;
    }
    let [name, params @ ..] = sig.as_list()? else {
        return None;
    };
    let params = params
        .iter()
        .map(|p| {
            p.as_symbol()
                .filter(|n| !n.starts_with('&'))
                .map(str::to_string)
        })
        .collect::<Option<Vec<String>>>()?;
    Some(Head {
        name: name.as_symbol()?.to_string(),
        params,
        sig: sig.span,
    })
}

fn lock_one(engine: &Engine, a: &Analysis, head: &Head, locked: &Locked) -> Option<Lock> {
    let params = head
        .params
        .iter()
        .zip(&locked.params)
        .map(|(p, t)| format!("{p}: {}", t.name()))
        .collect::<Vec<_>>()
        .join(", ");
    let signature = format!("{}({params}) -> {}", head.name, locked.ret.name());
    let text: &str = &a.text;
    let edited = format!(
        "{}{signature}{}",
        text.get(..head.sig.start)?,
        text.get(head.sig.end..)?
    );
    let formatted = blue_lang_fmt::format_source_lossless(&edited).ok()?;
    let after = engine.analyse_text(a.path.clone(), &formatted);
    let ok = after.checked().is_some_and(|c| c.outcome.ok());
    if !ok || !no_new_codes(a, &after) {
        return None;
    }
    let before = shift_of_tree(text, forms(a)).declaration_rung(&head.name);
    let rung = shift_of_tree(&formatted, forms(&after)).declaration_rung(&head.name);
    if rung <= before {
        return None;
    }
    let (span, new_text) = difference(text, &formatted);
    Some(Lock {
        name: head.name.clone(),
        signature,
        edit: TextEdit {
            range: LineIndex::new(text).range(span),
            new_text,
        },
    })
}

fn forms(a: &Analysis) -> Option<&[Spanned]> {
    a.parsed.as_ref().as_ref().ok().map(Vec::as_slice)
}

/// The document's own check-stage findings, counted by code.
fn codes(a: &Analysis) -> BTreeMap<&'static str, usize> {
    let mut out = BTreeMap::new();
    if let Some(c) = a.checked() {
        for d in &c.outcome.diagnostics {
            if c.program.owner_of(d.top_level) == Some(ResolvedProgram::ENTRY) {
                *out.entry(d.code.as_str()).or_default() += 1;
            }
        }
    }
    out
}

fn no_new_codes(before: &Analysis, after: &Analysis) -> bool {
    let had = codes(before);
    codes(after)
        .iter()
        .all(|(code, n)| had.get(code).is_some_and(|h| n <= h))
}

/// The one span of `before` to replace, and with what, to make `after`.
fn difference(before: &str, after: &str) -> (Span, String) {
    let mut start = before
        .bytes()
        .zip(after.bytes())
        .take_while(|(a, b)| a == b)
        .count();
    while !before.is_char_boundary(start) || !after.is_char_boundary(start) {
        start -= 1;
    }
    let room = before.len().min(after.len()) - start;
    let mut tail = before
        .bytes()
        .rev()
        .zip(after.bytes().rev())
        .take(room)
        .take_while(|(a, b)| a == b)
        .count();
    while !before.is_char_boundary(before.len() - tail)
        || !after.is_char_boundary(after.len() - tail)
    {
        tail -= 1;
    }
    (
        Span::new(start, before.len() - tail),
        after[start..after.len() - tail].to_string(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_difference_is_the_one_changed_span() {
        let (span, text) = difference("def inc(x)\n", "def inc(x: Int) -> Int\n");
        assert_eq!((span.start, span.end), (9, 10));
        assert_eq!(text, ": Int) -> Int");
        let (span, text) = difference("abc", "abc");
        assert_eq!((span.start, span.end, text.as_str()), (3, 3, ""));
        let (span, text) = difference("aé", "aè");
        assert_eq!((span.start, span.end, text.as_str()), (1, 3, "è"));
    }
}
