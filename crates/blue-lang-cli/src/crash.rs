//! `blue crash dump|bisect|immunize`: a crash trace, read by its file or by
//! its crash hash, and what can be proved from it.
//!
//! A trace is written under the BLAKE3 hash of its canonical bytes
//! (`blue_lang_proc::trace`), so a hash is a name: [`resolve`] finds the one
//! file in the trace directory that starts with it, and [`load`] refuses a
//! file whose content no longer hashes to its name.
//!
//! - `dump` prints the violation, its coordinate, the hold, the exit and the
//!   mailbox, or with `--json` the same as one object.
//! - `bisect` delta-debugs the messages the process took against
//!   deterministic replay (`blue_lang_proc::bisect`) and writes the reduced
//!   trace under its own hash.
//! - `immunize` writes the crash's regression lock: the CLI bisects and
//!   renders the plan, and the blue program `blue/crash.b` writes the test
//!   beside the target with `write_program`.

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use blue_lang_proc::{Trace, Violation};
use serde_json::{json, Value as Json};

use crate::replay;

const CRASH_PROGRAM: &str = include_str!("../blue/crash.b");

/// The control an immunizing test declares: incident handling.
const LOCK_CONTROL: &str = "nist_ir_4";

#[derive(clap::Subcommand)]
pub enum CrashCmd {
    /// What a crash violated and where: its class, the host name and
    /// capability a breach demanded, the breaching call's file, line and
    /// column, the hold, the exit and the mailbox.
    Dump {
        /// A trace file, or a crash hash (`b3:<hex>`, 8 digits at least).
        crash: String,
        #[arg(long)]
        json: bool,
    },
    /// The fewest messages the process took that still replay to the same
    /// crash, found by delta debugging against deterministic replay; the
    /// reduced trace is written beside the original under its own hash.
    Bisect {
        crash: String,
        #[arg(long)]
        json: bool,
    },
    /// The crash's regression lock: a test that spawns the target, sends it
    /// the fewest messages that crashed it and asserts it took them, red
    /// until the target is fixed. Written into FILE, by default the file
    /// that defines the target.
    Immunize {
        crash: String,
        #[arg(long, value_name = "FILE")]
        into: Option<PathBuf>,
    },
}

/// A trace read from disk, with its content address.
pub struct Loaded {
    pub trace: Trace,
    pub path: PathBuf,
    /// `b3:<hex>`: the BLAKE3 hash of the trace's canonical JSON.
    pub hash: String,
}

fn hex_of(arg: &str) -> Option<String> {
    let hex = arg.strip_prefix("b3:").unwrap_or(arg).to_ascii_lowercase();
    (hex.len() >= 8 && hex.len() <= 64 && hex.bytes().all(|b| b.is_ascii_hexdigit())).then_some(hex)
}

fn is_trace_file(p: &Path) -> bool {
    p.extension().and_then(|e| e.to_str()).is_some_and(|e| {
        e == blue_lang_proc::trace::CRASH_EXTENSION || e == blue_lang_proc::trace::TRACE_EXTENSION
    })
}

/// The trace `arg` names: a file, or a crash hash resolved in the trace
/// directory (`BLUE_TRACE_DIR`).
///
/// # Errors
///
/// When `arg` is neither a file nor a hash, the trace directory is
/// configured off, or the hash names no trace or several.
pub fn resolve(arg: &str) -> Result<PathBuf, String> {
    let path = Path::new(arg);
    if path.is_file() {
        return Ok(path.to_path_buf());
    }
    let hex = hex_of(arg).ok_or_else(|| {
        format!("{arg}: no such file, and not a crash hash (`b3:<hex>`, at least 8 hex digits)")
    })?;
    let dir = replay::trace_dir()
        .ok_or("BLUE_TRACE_DIR is empty, so no trace is kept on disk to resolve a hash in")?;
    let mut found: Vec<PathBuf> = std::fs::read_dir(&dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| {
            is_trace_file(p)
                && p.file_name()
                    .and_then(|n| n.to_str())
                    .is_some_and(|n| n.starts_with(&hex))
        })
        .collect();
    found.sort();
    match found.as_slice() {
        [one] => Ok(one.clone()),
        [] => Err(format!("no trace named {arg} in {}", dir.display())),
        many => Err(format!(
            "{arg} names {} traces in {}; give more digits: {}",
            many.len(),
            dir.display(),
            many.iter()
                .filter_map(|p| p.file_name().and_then(|n| n.to_str()))
                .collect::<Vec<_>>()
                .join(", ")
        )),
    }
}

/// Read the trace at `path`. A file named by a content address must still
/// be that content.
///
/// # Errors
///
/// When the file cannot be read, is not a trace this blue reads, or is named
/// by a hash its content no longer has.
pub fn load(path: &Path) -> Result<Loaded, String> {
    let shown = path.display();
    let bytes = std::fs::read(path).map_err(|e| format!("{shown}: {e}"))?;
    let j: Json = serde_json::from_slice(&bytes).map_err(|e| format!("{shown}: not JSON: {e}"))?;
    let hex = blue_lang_proc::trace::crash_hash(&j);
    let stem = path
        .file_name()
        .and_then(|n| n.to_str())
        .and_then(|n| n.split('.').next())
        .unwrap_or_default();
    if stem.len() == 64 && stem.bytes().all(|b| b.is_ascii_hexdigit()) && stem != hex {
        return Err(format!(
            "{shown}: named {stem}, but its content hashes to {hex}: the trace was edited"
        ));
    }
    let trace = Trace::from_json(&j).map_err(|e| format!("{shown}: {e}"))?;
    Ok(Loaded {
        trace,
        path: path.to_path_buf(),
        hash: format!("b3:{hex}"),
    })
}

fn shown_key(key: &str) -> String {
    blue_lang_runtime::observe::display_key(key)
}

fn literal(v: &tatara_lisp_eval::Value) -> String {
    blue_lang_runtime::literal::render_value(v)
}

fn violation_json(v: &Violation) -> Json {
    let mut j = v.to_json();
    if let Some(d) = v.at.as_ref().and_then(|a| a.definition.as_deref()) {
        j["at"]["definition"] = json!(shown_key(d));
    }
    j
}

fn view(l: &Loaded) -> Json {
    let t = &l.trace;
    json!({
        "crash_hash": l.hash,
        "file": l.path.display().to_string(),
        "pid": t.pid,
        "incarnation": t.incarnation,
        "definition": t.definition.as_deref().map(shown_key),
        "key": t.definition,
        "def_hash": t.def_hash,
        "defined_at": t.defined_at.as_ref().map(ToString::to_string),
        "exit": {"kind": t.reason_kind, "text": t.reason_text},
        "violation": t.violation.as_ref().map_or(Json::Null, violation_json),
        "hold": t.hold.as_ref().map_or(Json::Null, blue_lang_proc::Frame::to_json),
        "frame": t.hold.as_ref().map_or(Json::Null, |h| h.block(t.host_io.unwrap_or(0))),
        "mailbox": t.mailbox.as_ref().map_or(Json::Null, |m| json!({
            "bound": m.bound,
            "recent": m.recent.iter().map(literal).collect::<Vec<_>>(),
            "unconsumed": m.unconsumed.iter().map(literal).collect::<Vec<_>>(),
            "unconsumed_total": m.unconsumed_total,
        })),
        "tape": {"entries": t.tape.len(), "truncated": t.truncated},
    })
}

fn violation_lines(v: &Violation, tape_len: usize) -> Vec<String> {
    let mut lines = vec![match (&v.host, v.capability) {
        (Some(h), Some(c)) => format!("violation: {}: `{h}` demands {}", v.class.name(), c.label()),
        (Some(h), None) => format!("violation: {}: `{h}`", v.class.name()),
        _ => format!("violation: {}", v.class.name()),
    }];
    if let Some(at) = &v.at {
        let place = at.place.as_ref().map_or_else(
            || format!("span {}..{}", at.span.start, at.span.end),
            ToString::to_string,
        );
        let within = at
            .definition
            .as_deref()
            .map(|d| format!(" in {}", shown_key(d)))
            .unwrap_or_default();
        let entry = v
            .entry
            .map(|e| format!(" (tape entry {} of {tape_len})", e + 1))
            .unwrap_or_default();
        lines.push(format!("  at {place}{within}{entry}"));
    }
    lines
}

fn dump(l: &Loaded, as_json: bool) {
    if as_json {
        println!("{}", view(l));
        return;
    }
    let t = &l.trace;
    println!("crash {}", l.hash);
    println!(
        "process {}{} incarnation {}{}",
        t.pid,
        t.definition
            .as_deref()
            .map(|d| format!(" ({})", shown_key(d)))
            .unwrap_or_default(),
        t.incarnation,
        t.defined_at
            .as_ref()
            .map(|p| format!(", defined at {p}"))
            .unwrap_or_default(),
    );
    if let Some(h) = &t.def_hash {
        println!("def_hash: {h}");
    }
    println!("exit: {} {}", t.reason_kind, t.reason_text);
    match &t.violation {
        Some(v) => {
            for line in violation_lines(v, t.tape.len()) {
                println!("{line}");
            }
        }
        None => println!("violation: none (a {} exit is not one)", t.reason_kind),
    }
    if let Some(hold) = &t.hold {
        println!("{}", replay::hold_line(hold));
        println!(
            "host calls through granted names: {}",
            t.host_io.unwrap_or(0)
        );
    }
    if let Some(m) = &t.mailbox {
        for line in replay::mailbox_lines(m) {
            println!("{line}");
        }
    }
    println!(
        "tape: {} entries{}",
        t.tape.len(),
        if t.truncated { ", truncated" } else { "" }
    );
}

fn bisected(l: &Loaded) -> Result<blue_lang_proc::Bisected, String> {
    blue_lang_proc::bisect(&l.trace, &blue_lang_runtime::interpreter_hostless)
        .map_err(|e| format!("{}: {e}", l.hash))
}

fn bisect(l: &Loaded, as_json: bool) -> Result<(), String> {
    let b = bisected(l)?;
    let dir = l.path.parent().unwrap_or_else(|| Path::new("."));
    let written = b
        .reduced
        .write_to(dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?;
    let reduced = format!("b3:{}", b.reduced.crash_hash());
    let waiting = l.trace.mailbox.as_ref().map_or(0, |m| m.unconsumed_total);
    if as_json {
        println!(
            "{}",
            json!({
                "crash_hash": l.hash,
                "received": b.received,
                "kept": b.kept,
                "messages": b.messages.iter().map(literal).collect::<Vec<_>>(),
                "unconsumed": waiting,
                "replays": b.replays,
                "reduced": {"crash_hash": reduced, "file": written.display().to_string()},
            })
        );
        return Ok(());
    }
    println!(
        "crash {}: {} of {} messages taken replay to {} {} ({} replays)",
        l.hash,
        b.messages.len(),
        b.received,
        l.trace.reason_kind,
        l.trace.reason_text,
        b.replays
    );
    for (k, m) in b.kept.iter().zip(&b.messages) {
        println!("  message {}: {}", k + 1, literal(m));
    }
    if waiting > 0 {
        println!("  {waiting} still waiting never reached the process");
    }
    println!("reduced: {reduced} {}", written.display());
    Ok(())
}

fn lock_target(l: &Loaded) -> Result<(String, String), String> {
    let t = &l.trace;
    match (
        t.reason_kind.as_str(),
        t.violation.as_ref().map(|v| v.class),
    ) {
        ("fatal", Some(blue_lang_proc::Class::LatticeCeilingBreach)) | ("crashed", _) => {}
        ("runaway", _) => {
            return Err(format!(
                "{}: a runaway's lock needs the step bound it ran under (fuel {}), and a test \
                 cannot declare one",
                l.hash,
                t.budget
                    .fuel
                    .map_or_else(|| "unbounded".to_string(), |f| f.to_string())
            ))
        }
        (kind, _) => {
            return Err(format!(
                "{}: a {kind} exit is not the process's own failure, so there is nothing to lock",
                l.hash
            ))
        }
    }
    let key = t.definition.clone().ok_or_else(|| {
        format!(
            "{}: the process ran an anonymous function; a test can name only a definition",
            l.hash
        )
    })?;
    Ok((key.clone(), shown_key(&key)))
}

fn start_args(t: &Trace) -> Result<Vec<String>, String> {
    let Some(items) = t.code.start.as_ref().and_then(|s| s.as_list()) else {
        return Ok(Vec::new());
    };
    items
        .iter()
        .skip(1)
        .map(|arg| {
            let name = arg
                .as_symbol()
                .ok_or("an argument that is not a copied value")?;
            let value = t
                .code
                .bindings
                .iter()
                .find(|(n, _)| &**n == name)
                .map(|(_, v)| v)
                .ok_or_else(|| format!("the argument `{name}` was not recorded"))?;
            blue_lang_runtime::literal::literal(value)
                .ok_or_else(|| format!("the argument `{name}` has no literal form"))
        })
        .collect()
}

fn immunize(l: &Loaded, into: Option<PathBuf>) -> Result<ExitCode, String> {
    let (key, shown) = lock_target(l)?;
    let t = &l.trace;
    let file = into
        .or_else(|| t.defined_at.as_ref().map(|p| PathBuf::from(&p.file)))
        .ok_or_else(|| {
            format!(
                "{}: the trace does not say which file defines {shown}; pass --into FILE",
                l.hash
            )
        })?;
    let defining = t
        .defined_at
        .as_ref()
        .is_some_and(|p| Path::new(&p.file) == file);
    let target = if defining {
        shown.rsplit("::").next().unwrap_or(&shown).to_string()
    } else {
        shown.clone()
    };
    let b = bisected(l)?;
    let messages = b
        .messages
        .iter()
        .map(|m| {
            blue_lang_runtime::literal::literal(m)
                .ok_or_else(|| format!("{}: a message with no literal form", l.hash))
        })
        .collect::<Result<Vec<_>, _>>()?;
    let args = start_args(t).map_err(|e| format!("{}: {e}", l.hash))?;
    blue_lang_check::controls::oscal_id(LOCK_CONTROL)?;
    let short: String = l.hash.trim_start_matches("b3:").chars().take(12).collect();
    let allow: Vec<String> = t.hold.as_ref().map_or_else(Vec::new, |h| {
        if h.granted.is_empty() {
            vec!["none".to_string()]
        } else {
            h.granted.iter().map(|c| c.label().to_string()).collect()
        }
    });
    let plan = json!({
        "file": file.display().to_string(),
        "crash_hash": l.hash,
        "short": short,
        "key": key,
        "target": target,
        "args": args,
        "messages": messages,
        "taken": b.received,
        "control": LOCK_CONTROL,
        "allow": allow,
        "violation": t.violation.as_ref().map(|v| v.class.name()),
        "exit": t.reason_kind,
    });
    blue_lang_runtime::sys::set_program_args(vec!["immunize".to_string(), plan.to_string()]);
    let out = blue_lang_runtime::pipeline::run_in_surface(
        blue_lang_runtime::uses::Entry {
            path: Some(Path::new("crates/blue-lang-cli/blue/crash.b")),
            text: CRASH_PROGRAM,
        },
        blue_lang_runtime::inputs::Inputs::new(),
        &blue_lang_pkg::load_path::Environment::from_env().load_path(None),
        None,
    )
    .map_err(|e| e.to_string())?;
    Ok(
        if matches!(out.value, tatara_lisp_eval::Value::Bool(false)) {
            ExitCode::FAILURE
        } else {
            ExitCode::SUCCESS
        },
    )
}

/// `blue crash …`.
pub fn run(cmd: CrashCmd) -> Result<ExitCode, String> {
    match cmd {
        CrashCmd::Dump { crash, json } => {
            dump(&load(&resolve(&crash)?)?, json);
            Ok(ExitCode::SUCCESS)
        }
        CrashCmd::Bisect { crash, json } => {
            bisect(&load(&resolve(&crash)?)?, json)?;
            Ok(ExitCode::SUCCESS)
        }
        CrashCmd::Immunize { crash, into } => immunize(&load(&resolve(&crash)?)?, into),
    }
}
