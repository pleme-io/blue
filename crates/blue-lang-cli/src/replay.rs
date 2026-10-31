//! `blue replay TRACE`: run a crashed process again from its trace.
//!
//! The trace (`blue_lang_proc::trace`) holds the process's program and its
//! tape. The replay runs on a fresh interpreter in which every process word
//! and host name reads the tape, so it touches nothing outside itself and sees
//! the clock exactly as the crashed run did. A `.bluecrash` (a fatal exit's
//! trace) replays under the hold it recorded: a breach replays as the same
//! breach at the same tape entry. TRACE is a file or a crash hash, resolved
//! in the trace directory (`crate::crash::resolve`).

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use blue_lang_proc::replay;

/// Where `blue run` writes crash traces: `BLUE_TRACE_DIR`, or a `blue-traces`
/// directory under the system's temporary directory. `BLUE_TRACE_DIR=` (empty)
/// keeps traces in memory only.
pub fn trace_dir() -> Option<PathBuf> {
    match std::env::var_os("BLUE_TRACE_DIR") {
        Some(d) if d.is_empty() => None,
        Some(d) => Some(PathBuf::from(d)),
        None => Some(std::env::temp_dir().join("blue-traces")),
    }
}

/// How many messages of each kind a held process's crash journal keeps:
/// `BLUE_CRASH_JOURNAL`, or [`blue_lang_proc::node::DEFAULT_JOURNAL`].
/// `BLUE_CRASH_JOURNAL=0` keeps no journal.
pub fn journal_bound() -> usize {
    std::env::var("BLUE_CRASH_JOURNAL")
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(blue_lang_proc::node::DEFAULT_JOURNAL)
}

fn labels(caps: &[blue_lang_waku::Capability]) -> String {
    if caps.is_empty() {
        return "none".into();
    }
    caps.iter()
        .map(|c| c.label())
        .collect::<Vec<_>>()
        .join(", ")
}

/// The hold line a replay and a dump print.
pub fn hold_line(hold: &blue_lang_proc::Frame) -> String {
    format!(
        "hold: granted {}; provided {}; withheld {}",
        labels(&hold.granted),
        if hold.provided.is_empty() {
            "none".to_string()
        } else {
            hold.provided
                .iter()
                .map(|p| {
                    let served = p.scope.as_ref().map_or_else(String::new, |s| {
                        format!(" for {}", s.iter().cloned().collect::<Vec<_>>().join(", "))
                    });
                    format!(
                        "{} ({}{served})",
                        p.provision.capability().label(),
                        p.provision.label()
                    )
                })
                .collect::<Vec<_>>()
                .join(", ")
        },
        labels(&hold.withheld),
    )
}

/// The mailbox lines a replay and a dump print: the counts, then each
/// message still waiting.
pub fn mailbox_lines(m: &blue_lang_proc::Journal) -> Vec<String> {
    let mut lines = vec![format!(
        "mailbox: {} recent, {} unconsumed (bound {})",
        m.recent.len(),
        m.unconsumed_total,
        m.bound
    )];
    lines.extend(m.unconsumed.iter().map(|v| format!("  waiting: {v}")));
    lines
}

/// Replay `path`; success when the replay ends the way the trace recorded.
pub fn run(path: &Path) -> Result<ExitCode, String> {
    let trace = crate::crash::load(path)?.trace;
    println!(
        "process {}{} incarnation {}: {} tape entries{}",
        trace.pid,
        trace
            .definition
            .as_deref()
            .map(|d| format!(" ({d})"))
            .unwrap_or_default(),
        trace.incarnation,
        trace.tape.len(),
        if trace.truncated { ", truncated" } else { "" },
    );
    if let Some(h) = &trace.def_hash {
        println!("def_hash: {h}");
    }
    if let Some(hold) = &trace.hold {
        println!("{}", hold_line(hold));
    }
    if let Some(m) = &trace.mailbox {
        for line in mailbox_lines(m) {
            println!("{line}");
        }
    }
    println!("recorded: {} {}", trace.reason_kind, trace.reason_text);
    let r = replay(&trace, blue_lang_runtime::interpreter_hostless());
    println!(
        "replayed: {} {} ({} of {} tape entries)",
        r.kind, r.text, r.consumed, r.tape_len
    );
    if let Some(d) = &r.diverged {
        println!("diverged: {d}");
    }
    if trace.truncated {
        println!("not replayable: the tape outgrew its bound, and a replay needs all of it");
    }
    if r.reproduced {
        println!("reproduced");
        Ok(ExitCode::SUCCESS)
    } else {
        println!("not reproduced");
        Ok(ExitCode::FAILURE)
    }
}
