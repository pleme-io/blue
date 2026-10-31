//! The fewest messages that still crash a process the way its trace says.
//!
//! A trace's tape is the process's inputs in order. Each message it took (a
//! `receive`, or a server's next message) opens a segment: that entry and
//! every entry after it up to the next message, the calls the process made
//! while handling it. [`bisect`] delta-debugs the segments (Zeller's ddmin)
//! against deterministic replay ([`crate::replay`]): a candidate is the tape
//! before the first message followed by the segments it keeps, in order, and
//! it passes when its replay ends the way the trace recorded with nothing
//! diverging. The answer is 1-minimal: drop any one message it keeps and the
//! replay no longer reproduces the crash.
//!
//! A message still waiting when the process exited never reached it: it is
//! not on the tape, so it is never in the answer. Bisecting the roots of
//! strands is not here; blue has no strands.

use tatara_lisp_eval::{Interpreter, Value};

use crate::node::SERVER_NEXT;
use crate::trace::{replay, Journal, TapeEntry, Trace};

/// What [`bisect`] found.
#[derive(Clone, Debug)]
pub struct Bisected {
    /// The messages kept, by their place among the messages taken.
    pub kept: Vec<usize>,
    /// How many messages the process took.
    pub received: usize,
    /// The kept messages, in the order the process took them.
    pub messages: Vec<Value>,
    /// Replays run, the first (the whole tape) included.
    pub replays: usize,
    /// The trace with only the kept messages: its tape, its journal and its
    /// violation's tape entry rewritten to match.
    pub reduced: Trace,
}

fn takes_a_message(e: &TapeEntry) -> bool {
    e.call == "receive" || e.call == SERVER_NEXT
}

struct Segments {
    prelude: Vec<(usize, TapeEntry)>,
    each: Vec<Vec<(usize, TapeEntry)>>,
}

impl Segments {
    fn of(tape: &[TapeEntry]) -> Self {
        let mut out = Self {
            prelude: Vec::new(),
            each: Vec::new(),
        };
        for (i, e) in tape.iter().enumerate() {
            if takes_a_message(e) {
                out.each.push(Vec::new());
            }
            match out.each.last_mut() {
                Some(seg) => seg.push((i, e.clone())),
                None => out.prelude.push((i, e.clone())),
            }
        }
        out
    }

    fn tape(&self, keep: &[usize]) -> Vec<(usize, TapeEntry)> {
        let mut tape = self.prelude.clone();
        for k in keep {
            tape.extend(self.each[*k].iter().cloned());
        }
        tape
    }

    fn message(&self, k: usize) -> Value {
        self.each[k]
            .first()
            .and_then(|(_, e)| e.outcome.clone().ok())
            .unwrap_or(Value::Nil)
    }
}

fn with_tape(trace: &Trace, tape: &[(usize, TapeEntry)]) -> Trace {
    let mut t = trace.clone();
    t.tape = tape.iter().map(|(_, e)| e.clone()).collect();
    t
}

fn chunks(c: &[usize], n: usize) -> Vec<Vec<usize>> {
    let mut out = Vec::new();
    let mut start = 0;
    for i in 0..n {
        let end = start + (c.len() - start) / (n - i);
        out.push(c[start..end].to_vec());
        start = end;
    }
    out.retain(|ch| !ch.is_empty());
    out
}

/// Zeller's ddmin over `0..n`: a 1-minimal subset `test` passes, given that
/// the whole set passes.
fn ddmin(n: usize, test: &mut dyn FnMut(&[usize]) -> bool) -> Vec<usize> {
    if test(&[]) {
        return Vec::new();
    }
    let mut c: Vec<usize> = (0..n).collect();
    let mut granularity = 2;
    while c.len() >= 2 {
        let parts = chunks(&c, granularity);
        if let Some(part) = parts.iter().find(|p| test(p)) {
            c.clone_from(part);
            granularity = 2;
            continue;
        }
        let complements: Vec<Vec<usize>> = parts
            .iter()
            .map(|p| c.iter().copied().filter(|x| !p.contains(x)).collect())
            .collect();
        if let Some(rest) = complements.into_iter().find(|r| test(r)) {
            c = rest;
            granularity = (granularity - 1).max(2);
            continue;
        }
        if granularity >= c.len() {
            break;
        }
        granularity = (granularity * 2).min(c.len());
    }
    c
}

/// The fewest of `trace`'s messages that replay to the same crash, each
/// replay on an interpreter from `fresh`.
///
/// # Errors
///
/// When the trace's tape was truncated, or the whole tape does not replay
/// to the crash it recorded: there is then nothing to bisect.
pub fn bisect(trace: &Trace, fresh: &dyn Fn() -> Interpreter<()>) -> Result<Bisected, String> {
    if trace.truncated {
        return Err("the tape outgrew its bound, and a replay needs all of it".into());
    }
    let whole = replay(trace, fresh());
    if !whole.reproduced {
        return Err(format!(
            "the trace does not replay to its crash ({} {}{}), so there is nothing to bisect",
            whole.kind,
            whole.text,
            whole
                .diverged
                .map(|d| format!("; diverged: {d}"))
                .unwrap_or_default()
        ));
    }
    let segments = Segments::of(&trace.tape);
    let mut replays = 1;
    let kept = ddmin(segments.each.len(), &mut |keep| {
        replays += 1;
        replay(&with_tape(trace, &segments.tape(keep)), fresh()).reproduced
    });
    let tape = segments.tape(&kept);
    let messages: Vec<Value> = kept.iter().map(|k| segments.message(*k)).collect();
    let mut reduced = with_tape(trace, &tape);
    if let Some(v) = reduced.violation.as_mut() {
        v.entry = v
            .entry
            .and_then(|old| tape.iter().position(|(i, _)| *i == old));
    }
    if let Some(j) = &trace.mailbox {
        let skip = messages.len().saturating_sub(j.bound);
        reduced.mailbox = Some(Journal {
            bound: j.bound,
            recent: messages[skip..].to_vec(),
            unconsumed: Vec::new(),
            unconsumed_total: 0,
        });
    }
    Ok(Bisected {
        kept,
        received: segments.each.len(),
        messages,
        replays,
        reduced,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ddmin_finds_the_one_item_a_failure_needs() {
        for poison in 0..7 {
            let mut asked = 0;
            let got = ddmin(7, &mut |keep| {
                asked += 1;
                keep.contains(&poison)
            });
            assert_eq!(got, [poison]);
            assert!(asked <= 20, "{asked} tests for 7 items");
        }
    }

    #[test]
    fn ddmin_keeps_every_item_a_failure_needs_and_nothing_else() {
        let got = ddmin(8, &mut |keep| keep.contains(&1) && keep.contains(&6));
        assert_eq!(got, [1, 6]);
        assert_eq!(ddmin(5, &mut |_| true), Vec::<usize>::new());
        let all = ddmin(3, &mut |keep| keep.len() == 3);
        assert_eq!(all, [0, 1, 2]);
    }

    #[test]
    fn chunks_cover_the_set_in_order() {
        assert_eq!(chunks(&[0, 1, 2, 3, 4], 2), [vec![0, 1], vec![2, 3, 4]]);
        assert_eq!(chunks(&[4, 9], 2), [vec![4], vec![9]]);
    }
}
