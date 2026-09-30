//! Turning observations into verdicts: the expectation, the pending mark, and
//! agreement with stage 0.

use crate::eval::{project, Obs};
use crate::rows::{Ev, Expect, Row};

#[derive(Clone, Debug, PartialEq)]
pub enum Verdict {
    Pass,
    Fail(String),
    /// The row states a destination the named gap has not reached, and the
    /// evaluator does not reach it either.
    Pending(String),
    /// Not observable by this evaluator. Never counted as a pass.
    Blind(String),
}

impl Verdict {
    pub fn is_fail(&self) -> bool {
        matches!(self, Verdict::Fail(_))
    }
}

/// Does `obs` meet `expect`? `None` when the observation cannot speak to it.
fn meets(expect: &Expect, obs: &Obs) -> Result<(), String> {
    let ok = match (expect, obs) {
        (Expect::Value(want), Obs::Value(got)) => want == got,
        (Expect::Value(want), Obs::Abi(got)) => project(&Obs::Value(want.clone())) == Some(*got),
        (Expect::Fails(stage, needle), Obs::Failed { stage: s, message }) => {
            stage == s && message.contains(needle.as_str())
        }
        (Expect::Fails(..), Obs::Abi(got)) => *got == crate::eval::Abi::Error,
        (Expect::Prints(want), Obs::Printed { stdout, ok }) => *ok && want == stdout,
        (Expect::Diagnoses(want), Obs::Codes(got)) => want == got,
        (Expect::Formats(want), Obs::Text(got)) => want.trim_end() == got.trim_end(),
        (
            Expect::Shifts(rung, holding),
            Obs::Shift {
                rung: r,
                holding: h,
            },
        ) => rung == r && holding == h,
        _ => false,
    };
    if ok {
        Ok(())
    } else {
        Err(format!("expected {}, observed {obs}", describe(expect)))
    }
}

pub fn describe(expect: &Expect) -> String {
    match expect {
        Expect::Value(v) => format!("value {v}"),
        Expect::Fails(s, n) => format!("fails :{} {n:?}", s.name()),
        Expect::Prints(o) => format!("prints {o:?}"),
        Expect::Diagnoses(c) => format!("diagnoses {c:?}"),
        Expect::Formats(t) => format!("formats {t:?}"),
        Expect::Shifts(r, h) => format!("shifts {r} holding {h:?}"),
    }
}

/// The verdict for one evaluator, before agreement is considered.
pub fn verdict(row: &Row, ev: Ev, obs: &Obs) -> Verdict {
    if let Obs::Blind(why) = obs {
        return Verdict::Blind(why.clone());
    }
    let met = meets(&row.expect, obs);
    match (row.pending_on(ev), met) {
        (None, Ok(())) => Verdict::Pass,
        (None, Err(why)) => Verdict::Fail(why),
        (Some(p), Err(_)) => Verdict::Pending(p.gap.clone()),
        // The ABI reads "not an integer" or "an error" for every value but an
        // Int, so its agreeing with a pending destination is no evidence the
        // gap closed. Only an exact integer can flip a pending row there.
        (Some(p), Ok(())) if matches!(obs, Obs::Abi(a) if !matches!(a, crate::eval::Abi::Int(_))) => {
            Verdict::Pending(p.gap.clone())
        }
        (Some(p), Ok(())) => Verdict::Fail(format!(
            "pending({:?}) but the row now PASSES: the gap may be closed — remove the mark",
            p.gap
        )),
    }
}

/// Do two observations of the same row say the same thing?
///
/// `reference` is stage 0's observation (the walker for evaluated rows, the
/// in-process front end for static ones). The WASM surface is compared at the
/// resolution its ABI has.
pub fn agrees(reference: &Obs, other: &Obs) -> bool {
    match other {
        Obs::Abi(a) => project(reference) == Some(*a),
        _ => reference == other,
    }
}

/// Which observation a given evaluator is compared against.
pub fn reference_for(ev: Ev, row: &Row) -> Option<Ev> {
    match (&row.expect, ev) {
        (Expect::Value(_) | Expect::Fails(..), Ev::Vm | Ev::Wasm | Ev::Cli) => Some(Ev::Walker),
        (Expect::Diagnoses(_) | Expect::Formats(_) | Expect::Shifts(..), Ev::Cli) => {
            Some(Ev::Static)
        }
        _ => None,
    }
}

/// How a disagreement with stage 0 is judged.
#[derive(Clone, Debug, PartialEq)]
pub enum Agreement {
    Agrees,
    /// Both sides miss a pending destination, differently. Reported, not red:
    /// neither is the behaviour the row specifies, and the gap that closes
    /// the row makes both pass — at which point they must agree.
    DivergesWhilePending(String),
    /// A failure, even when both observations meet the expectation.
    Disagrees(String),
}

/// A disagreement fails the evaluator that disagrees, even when both
/// observations meet the expectation — unless that evaluator carries its own
/// pending mark (`pending(GAP, "wasm")`), which is the declared form of "this
/// surface differs, and here is the gap that closes it", or both sides are
/// pending on the same row.
pub fn agreement(
    row: &Row,
    ev: Ev,
    v: &Verdict,
    obs: &Obs,
    reference_verdict: &Verdict,
    reference: &Obs,
) -> Agreement {
    if matches!(v, Verdict::Blind(_)) || matches!(reference, Obs::Blind(_)) {
        return Agreement::Agrees;
    }
    if agrees(reference, obs) {
        return Agreement::Agrees;
    }
    let what = format!("stage 0 observed {reference}, {} observed {obs}", ev.name());
    if row.pending.iter().any(|p| p.on == Some(ev)) {
        return Agreement::Agrees;
    }
    if matches!(reference_verdict, Verdict::Pending(_))
        && matches!(v, Verdict::Pending(_) | Verdict::Pass)
    {
        // Both miss the destination differently, or this evaluator already
        // reaches the destination stage 0 is still pending on.
        return Agreement::DivergesWhilePending(what);
    }
    Agreement::Disagrees(format!("disagrees with stage 0: {what}"))
}
