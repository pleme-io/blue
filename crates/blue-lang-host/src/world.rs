use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use blue_lang_pkg::load_path::{Environment, LoadPath};
use blue_lang_runtime::json::value_to_json;
use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::{json, Value};

use crate::{Budget, CallError, Canonical, Capability, Entry, Host, Hosted, Program};

pub const DEFAULT_FUEL: usize = 20_000_000;
pub const DEFAULT_MEMORY_MB: u64 = 1024;
pub const READ_LIMIT: Duration = Duration::from_secs(10);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Refusal {
    pub kind: String,
    pub why: String,
}

impl Refusal {
    #[must_use]
    pub fn new(kind: &str, why: impl Into<String>) -> Self {
        Self {
            kind: kind.to_owned(),
            why: why.into(),
        }
    }
}

impl std::fmt::Display for Refusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.kind, self.why)
    }
}

impl From<&CallError> for Refusal {
    fn from(e: &CallError) -> Self {
        let kind = match e {
            CallError::Exhausted { .. } => "exhausted",
            CallError::Undefined(_) | CallError::NotAFunction { .. } => "load",
            CallError::Raised { .. } => "raised",
        };
        Self::new(kind, e.to_string())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Load {
    Absent,
    Judged(Value),
    Refused(Refusal),
}

#[derive(Debug, Clone, Copy)]
pub struct Spec<'a> {
    pub call: &'a str,
    pub kinds: &'a str,
    pub allow: &'a [Capability],
    pub fuel: usize,
}

#[must_use]
pub fn budget(fuel: usize) -> Budget {
    Budget {
        fuel: Some(fuel),
        ..Budget::tree_walker_default()
    }
}

#[must_use]
pub fn loader_for(entry: &Path) -> LoadPath {
    let mut folders: Vec<PathBuf> = Vec::new();
    if let Some(dir) = entry.parent() {
        folders.push(dir.join("bidamas"));
        if let Some(up) = dir.parent() {
            folders.push(up.join("bidamas"));
        }
    }
    Environment::from_env()
        .with_workspace(folders)
        .load_path(Some(entry))
}

pub fn load_file<H: Host>(
    file: &Path,
    allow: &[Capability],
    fuel: usize,
    host: &mut H,
) -> Result<Hosted<H>, Refusal> {
    let text = std::fs::read_to_string(file)
        .map_err(|e| Refusal::new("load", format!("{}: {e}", file.display())))?;
    let loader = loader_for(file);
    let entry = Entry {
        path: Some(file),
        text: &text,
    };
    let permits = |_: &str| true;
    Program::<H>::builder(entry)
        .loader(&loader)
        .canonical(Canonical::AsWritten)
        .posture(allow)
        .frame(&permits, budget(fuel))
        .load(host)
        .map(Program::into_hosted)
        .map_err(|e| Refusal::new("load", e.to_string()))
}

pub fn judged<H: Host + Default>(file: &Path, spec: &Spec<'_>) -> Result<Value, Refusal> {
    let mut host = H::default();
    let mut world = load_file(file, spec.allow, spec.fuel, &mut host)?;
    let entries = world
        .call_budgeted(spec.call, Vec::new(), &mut host, budget(spec.fuel))
        .map_err(|e| Refusal::from(&e))?;
    let source = format!(
        "use(\"motenashi\", %i[host_kinds judged_for schema])\n\ndef judged(entries)\n  judged_for({}, entries)\nend\n",
        spec.kinds
    );
    let loader = Environment::from_env().load_path(None);
    let mut judge = Program::<()>::builder(Entry::anonymous(&source))
        .loader(&loader)
        .canonical(Canonical::AsWritten)
        .posture(&[])
        .load(&mut ())
        .map(Program::into_hosted)
        .map_err(|e| Refusal::new("load", e.to_string()))?;
    let judged = judge
        .call_budgeted("judged", vec![entries], &mut (), budget(spec.fuel))
        .map_err(|e| Refusal::from(&e))?;
    Ok(value_to_json(&judged))
}

pub fn write_reply(out: &mut impl Write, result: &Result<Value, Refusal>) -> std::io::Result<()> {
    let line = match result {
        Ok(judged) => json!({ "judged": judged }),
        Err(r) => json!({ "refused": { "kind": r.kind, "why": r.why } }),
    };
    writeln!(out, "{line}")?;
    out.flush()
}

#[must_use]
pub fn serve<H: Host + Default>(file: &Path, spec: &Spec<'_>, memory_mb: u64) -> i32 {
    bound_memory(memory_mb);
    let result = judged::<H>(file, spec);
    let stdout = std::io::stdout();
    i32::from(write_reply(&mut stdout.lock(), &result).is_err())
}

#[cfg(target_os = "linux")]
pub fn bound_memory(mb: u64) {
    use rustix::process::{setrlimit, Resource, Rlimit};
    let bytes = mb.saturating_mul(1024 * 1024);
    let limit = Rlimit {
        current: Some(bytes),
        maximum: Some(bytes),
    };
    if let Err(e) = setrlimit(Resource::As, limit) {
        eprintln!("could not bound this worker's memory: {e}");
    }
}

#[cfg(not(target_os = "linux"))]
pub fn bound_memory(_mb: u64) {}

#[derive(Debug)]
pub enum Bounded {
    Finished {
        stdout: Vec<u8>,
        status: std::process::ExitStatus,
    },
    TimedOut,
    Failed(std::io::Error),
}

#[must_use]
pub fn run_bounded(command: Command, limit: Duration) -> Bounded {
    run_bounded_with(command, &[], limit)
}

#[must_use]
pub fn run_bounded_with(mut command: Command, input: &[u8], limit: Duration) -> Bounded {
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(e) => return Bounded::Failed(e),
    };
    if let Some(mut pipe) = child.stdin.take() {
        let input = input.to_vec();
        std::thread::spawn(move || {
            let _ = pipe.write_all(&input);
        });
    }
    let reader = child.stdout.take().map(|mut pipe| {
        std::thread::spawn(move || {
            let mut bytes = Vec::new();
            let _ = pipe.read_to_end(&mut bytes);
            bytes
        })
    });
    let started = Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if started.elapsed() >= limit => {
                let _ = child.kill();
                let _ = child.wait();
                return Bounded::TimedOut;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(2)),
            Err(e) => return Bounded::Failed(e),
        }
    };
    let stdout = reader.and_then(|r| r.join().ok()).unwrap_or_default();
    Bounded::Finished { stdout, status }
}

#[must_use]
pub fn read(command: Command, file: &Path, limit: Duration) -> Load {
    if !file.exists() {
        return Load::Absent;
    }
    match run_bounded(command, limit) {
        Bounded::Finished { stdout, status } => reply_of(&stdout).unwrap_or_else(|| {
            Load::Refused(Refusal::new(
                "died",
                format!("the world worker ended: {status}"),
            ))
        }),
        Bounded::TimedOut => Load::Refused(Refusal::new(
            "killed",
            format!("the world gave no answer in {} ms", limit.as_millis()),
        )),
        Bounded::Failed(e) => Load::Refused(Refusal::new("spawn", e.to_string())),
    }
}

fn reply_of(stdout: &[u8]) -> Option<Load> {
    let text = String::from_utf8_lossy(stdout);
    let line = text.lines().rev().find(|l| !l.trim().is_empty())?;
    let reply: Value = serde_json::from_str(line).ok()?;
    if let Some(judged) = reply.get("judged") {
        return Some(Load::Judged(judged.clone()));
    }
    let refused = reply.get("refused")?;
    Some(Load::Refused(Refusal::new(
        refused.get("kind")?.as_str()?,
        refused.get("why")?.as_str()?,
    )))
}

#[must_use]
pub fn word(value: &Value) -> Option<&str> {
    value.as_str().map(|s| s.trim_start_matches(':'))
}

#[must_use]
pub fn listed(judged: &Value, key: &str) -> Vec<Value> {
    judged
        .get(key)
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

#[must_use]
pub fn refusals_of(judged: &Value) -> Vec<Refusal> {
    listed(judged, "refusals")
        .iter()
        .map(|r| {
            Refusal::new(
                r.get("kind").and_then(word).unwrap_or("invalid"),
                r.get("why").and_then(Value::as_str).unwrap_or_default(),
            )
        })
        .collect()
}

fn overlay(base: &mut Value, over: &Value) {
    match (base, over) {
        (Value::Object(base), Value::Object(over)) => {
            for (key, value) in over {
                overlay(base.entry(key.clone()).or_insert(Value::Null), value);
            }
        }
        (base, over) => *base = over.clone(),
    }
}

pub fn merged<T: Serialize + DeserializeOwned>(config: &T, over: &Value) -> Result<T, String> {
    let mut base = serde_json::to_value(config).map_err(|e| e.to_string())?;
    overlay(&mut base, over);
    let next: T = serde_json::from_value(base).map_err(|e| e.to_string())?;
    let back = serde_json::to_value(&next).map_err(|e| e.to_string())?;
    match unread(&back, over) {
        Some(field) => Err(format!("no such field: {field}")),
        None => Ok(next),
    }
}

fn unread(back: &Value, over: &Value) -> Option<String> {
    let Value::Object(fields) = over else {
        return None;
    };
    fields.iter().find_map(|(key, value)| match back.get(key) {
        Some(found) => unread(found, value).map(|inner| format!("{key}.{inner}")),
        None => Some(key.clone()),
    })
}

enum Waiting<T> {
    Nothing,
    Finished(T),
    GaveUp,
}

pub fn within<T: Send + 'static>(
    patience: Duration,
    work: impl FnOnce() -> T + Send + 'static,
    late: impl FnOnce(T) + Send + 'static,
) -> Option<T> {
    let slot = Arc::new((Mutex::new(Waiting::Nothing), Condvar::new()));
    let worker_slot = Arc::clone(&slot);
    let spawned = std::thread::Builder::new()
        .name("blue-first-world".to_owned())
        .spawn(move || {
            let value = work();
            let (state, finished) = &*worker_slot;
            let mut state = state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if matches!(*state, Waiting::GaveUp) {
                drop(state);
                late(value);
            } else {
                *state = Waiting::Finished(value);
                finished.notify_all();
            }
        });
    if spawned.is_err() {
        return None;
    }
    let (state, finished) = &*slot;
    let guard = state
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let (mut guard, _) = finished
        .wait_timeout_while(guard, patience, |state| matches!(state, Waiting::Nothing))
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    match std::mem::replace(&mut *guard, Waiting::GaveUp) {
        Waiting::Finished(value) => Some(value),
        Waiting::Nothing | Waiting::GaveUp => None,
    }
}
