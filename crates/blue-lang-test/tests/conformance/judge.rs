//! Turning observations into verdicts: the expectation, the pending mark, and
//! agreement with stage 0.

use crate::eval::{project, Obs};
use crate::rows::{Ev, Expect, Pending, Row, Stage};

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
        (Expect::Leaks(n), Obs::Value(got)) => *got == format!("leaks {n}"),
        (Expect::ClosesAtEnd, Obs::Value(got)) => got == "open 0",
        (Expect::Value(want), Obs::Abi(got)) => project(&Obs::Value(want.clone())) == Some(*got),
        (Expect::Fails(stage, needle), Obs::Failed { stage: s, message }) => {
            stage == s && message.contains(needle.as_str())
        }
        (Expect::Fails(..), Obs::Abi(got)) => *got == crate::eval::Abi::Error,
        (Expect::Prints(want), Obs::Printed { stdout, ok }) => *ok && want == stdout,
        (Expect::Diagnoses(want), Obs::Codes(got)) => want == got,
        (Expect::Formats(want) | Expect::Fixes(want), Obs::Text(got)) => {
            want.trim_end() == got.trim_end()
        }
        (
            Expect::Shifts(rung, holding),
            Obs::Shift {
                rung: r,
                holding: h,
            },
        ) => rung == r && holding == h,
        (Expect::Facts(want), Obs::Facts(got)) => want == got,
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
        Expect::Fixes(t) => format!("fixes {t:?}"),
        Expect::Shifts(r, h) => format!("shifts {r} holding {h:?}"),
        Expect::Facts(f) => format!("facts {f:?}"),
        Expect::Leaks(n) => format!("leaks {n}"),
        Expect::ClosesAtEnd => "open 0".to_owned(),
    }
}

pub fn meets_row(row: &Row, obs: &Obs) -> bool {
    meets(&row.expect, obs).is_ok()
}

fn subject_stage(expect: &Expect) -> Stage {
    match expect {
        Expect::Fails(stage, _) => *stage,
        Expect::Value(_) | Expect::Prints(_) | Expect::Leaks(_) | Expect::ClosesAtEnd => {
            Stage::Eval
        }
        Expect::Diagnoses(_)
        | Expect::Formats(_)
        | Expect::Fixes(_)
        | Expect::Shifts(..)
        | Expect::Facts(_) => Stage::Check,
    }
}

fn stop(obs: &Obs) -> Option<Stage> {
    match obs {
        Obs::Failed { stage, .. } => Some(*stage),
        Obs::Codes(codes)
            if codes
                .iter()
                .any(|c| c == blue_lang_check::Code::B0006.as_str()) =>
        {
            Some(Stage::Parse)
        }
        _ => None,
    }
}

fn missed(row: &Row, p: &Pending, obs: &Obs) -> Verdict {
    match (&p.misses, stop(obs)) {
        (Some(miss), _) if meets(miss, obs).is_ok() => Verdict::Pending(p.gap.clone()),
        (Some(miss), _) => Verdict::Fail(format!(
            "pending({:?}) names its miss as {}, but the row now misses with {obs}: the miss moved — re-record the mark or remove it",
            p.gap,
            describe(miss)
        )),
        (None, Some(stage)) if stage < subject_stage(&row.expect) => Verdict::Fail(format!(
            "pending({:?}) but the program stops at :{} ({obs}), before the behaviour the row states, so closing {} cannot flip it — fix the row, or name the miss: pending({:?}, {})",
            p.gap,
            stage.name(),
            p.gap,
            p.gap,
            as_expectation(obs)
        )),
        (None, _) => Verdict::Pending(p.gap.clone()),
    }
}

fn as_expectation(obs: &Obs) -> String {
    match obs {
        Obs::Failed { stage, message } => format!("fails(:{}, {message:?})", stage.name()),
        Obs::Codes(codes) => format!("diagnoses({codes:?})"),
        other => other.to_string(),
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
        (Some(p), Err(_)) => missed(row, p, obs),
        // The ABI reads "not an integer" or "an error" for every value but an
        // Int, so its agreeing with a pending destination is no evidence the
        // gap closed. Only an exact integer can flip a pending row there.
        (Some(p), Ok(())) if matches!(obs, Obs::Abi(a) if !matches!(a, crate::eval::Abi::Int(_))) => {
            Verdict::Pending(p.gap.clone())
        }
        (Some(p), Ok(())) if p.flaky => Verdict::Pending(p.gap.clone()),
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
        (
            Expect::Value(_) | Expect::Fails(..),
            Ev::Vm | Ev::Wasm | Ev::Cli | Ev::Memo | Ev::Default | Ev::Scheduled,
        ) => Some(Ev::Walker),
        (Expect::Value(_), Ev::Native | Ev::Ir) => Some(Ev::Walker),
        (Expect::Leaks(_), Ev::Vm) => Some(Ev::Walker),
        (Expect::ClosesAtEnd, Ev::Vm) => Some(Ev::Walker),
        (
            Expect::Diagnoses(_) | Expect::Formats(_) | Expect::Fixes(_) | Expect::Shifts(..),
            Ev::Cli,
        ) => Some(Ev::Static),
        (Expect::Prints(_) | Expect::Fails(..), Ev::Component) => Some(Ev::Cli),
        (Expect::Prints(_), Ev::Default | Ev::Scheduled) => Some(Ev::Cli),
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
pub fn first_difference(reference: &Obs, other: &Obs) -> String {
    fn text(field: &str, a: &str, b: &str) -> String {
        let at = a
            .char_indices()
            .zip(b.chars())
            .find(|((_, x), y)| x != y)
            .map_or_else(|| a.len().min(b.len()), |((i, _), _)| i);
        format!("{field} at byte {at}")
    }
    match (reference, other) {
        (Obs::Printed { stdout: a, ok: x }, Obs::Printed { stdout: b, ok: y }) => {
            if x != y {
                "exit".into()
            } else {
                text("stdout", a, b)
            }
        }
        (
            Obs::Failed {
                stage: s,
                message: a,
            },
            Obs::Failed {
                stage: t,
                message: b,
            },
        ) => {
            if s != t {
                "stage".into()
            } else {
                text("message", a, b)
            }
        }
        (Obs::Value(a), Obs::Value(b)) | (Obs::Text(a), Obs::Text(b)) => text("value", a, b),
        _ if std::mem::discriminant(reference) != std::mem::discriminant(other) => "outcome".into(),
        _ => "value".into(),
    }
}

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
    let reference_name = reference_for(ev, row).map_or("stage 0", Ev::name);
    let what = format!(
        "{reference_name} observed {reference}, {} observed {obs}; first differing field: {}",
        ev.name(),
        first_difference(reference, obs)
    );
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
    Agreement::Disagrees(format!("disagrees with {reference_name}: {what}"))
}
