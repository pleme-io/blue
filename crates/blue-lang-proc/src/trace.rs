//! Crash traces, and replaying one.
//!
//! When a process exits abnormally its node writes down everything needed to
//! run that incarnation again without the rest of the system: its program
//! (definitions, copied bindings, the start form), its budget, and its
//! **tape** — every value it was handed that its program does not determine:
//! each message `receive` returned, each host read (the clock, a file, the
//! network) with its result or its error, each pid a `spawn` answered. The
//! scheduler's interleaving record (the last slices, in order) rides along for
//! the reader; the replay does not need it, because the only way the
//! interleaving reaches a process is through the order of what it received,
//! and that is on the tape.
//!
//! [`replay`] runs the program again on a fresh VM in which **every** process
//! word and **every** host name is rebound to read the tape: nothing reaches
//! the host, time is what it was, and a process that asks for something its
//! tape does not hold has diverged, which the replay reports by name.
//!
//! ## Format `blue-trace` version 3
//!
//! One canonical JSON object (keys sorted, no whitespace), written under the
//! BLAKE3 hash of its bytes, its `crash_hash`: `<hex>.bluecrash` for a fatal
//! exit, `<hex>.json` for any other ([`Trace::write_to`]).
//!
//! ```text
//! { "format": "blue-trace", "version": 3,
//!   "pid": 3, "incarnation": 0, "definition": "%root/consumer" | null,
//!   "def_hash": "b3:…" | null,
//!   "defined_at": null | { "file": PATH, "line": n, "column": n },
//!   "exit": { "kind": "crashed" | "runaway" | "killed" | "fatal", "text": "…", "reason": VALUE },
//!   "violation": null | VIOLATION,
//!   "budget": { "fuel": n | null, "max_depth": n | null, "quantum": n | null },
//!   "clock": "real" | "virtual",
//!   "code": { "defs": [FORM…], "bindings": [{ "name": "%a0", "value": VALUE }…], "start": FORM },
//!   "tape": [{ "call": "receive", "value": VALUE } | { "call": "now_ms", "raised": "…" }
//!            | { "call": "is_file?", "fatal": { "kind": "capability-breach", "message": "…", "at": [start, end] } }…],
//!   "truncated": false,
//!   "schedule": [{ "pid": 1, "outcome": "yielded" | "blocked" | "done" | "exited", "burned": n }…],
//!   "hold": null | { "granted": [LABEL…], "provided": [PROVIDER…], "withheld": [LABEL…] },
//!   "frame": null | { "granted": [LABEL…], "withheld": [LABEL…], "host_io": n },
//!   "mailbox": null | { "bound": n, "recent": [VALUE…], "unconsumed": [VALUE…], "unconsumed_total": n } }
//! ```
//!
//! Version 3 adds the `violation` block ([`crate::violation`]), the span of a
//! fatal tape entry's call, where the spawned definition is (`defined_at`),
//! and, under a hold, the receipt's frame block (`frame`, the incarnation's
//! host calls through granted names), so a crash and a receipt name a frame
//! the same way.
//!
//! Version 2 added `def_hash` (the spawned definition's identity), the
//! `fatal` tape outcome (an error no `rescue` catches, replayed as one), and,
//! for a process under a hold, the hold ([`crate::Frame`]) and its mailbox
//! journal: the last `bound` messages it took and the first `bound` still
//! waiting when it exited. A trace of a fatal exit replays under the
//! recorded hold: a name the hold withholds answers only with the breach its
//! tape recorded. Versions 1 and 2 are still read; their absent fields are
//! absent, and their violation is read off the exit and the tape.
//!
//! A VALUE is `null` (nil) or a one-key object naming its kind: `int`,
//! `float`, `str`, `sym`, `kw`, `bool`, `list` (an array), `map` (an array of
//! `[key, value]` pairs), `error` (`tag`, `message`, `data`), `form` (a quoted
//! form), or `opaque` (a host handle, by type name: replayed as a placeholder
//! only the tape can consume). A FORM is a one-key object of the same kinds
//! plus `nil`, `quote`, `quasiquote`, `unquote` and `splice`, with an optional
//! `at: [start, end]` — the source span, kept so a replayed error names the
//! same place the original did.
//!
//! The format is versioned; a reader refuses a version it does not know rather
//! than guessing.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use serde_json::{json, Map as JsonMap, Value as Json};
use tatara_lisp::{Atom, Span, Spanned, SpannedForm};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::vm::{compile_program, Budget, Vm};
use tatara_lisp_eval::{ErrorObj, EvalError, Interpreter, MapKey, Value};

use crate::code::Code;
use crate::node::{host_names, ClockKind, PROCESS_WORDS, SERVER_NEXT};
use crate::receipt::{canonical, Frame, Place, Places};
use crate::violation::Violation;
use crate::{classify, ExitReason};

/// The format name every trace carries.
pub const FORMAT: &str = "blue-trace";
/// The version this crate writes.
pub const VERSION: u64 = 3;
/// Every version this crate reads.
pub const READS: [u64; 3] = [1, 2, VERSION];
/// The extension of a fatal exit's trace.
pub const CRASH_EXTENSION: &str = "bluecrash";
/// The extension of any other exit's trace.
pub const TRACE_EXTENSION: &str = "json";

/// The content address of trace JSON: the BLAKE3 hash, in hex, of its
/// canonical text.
#[must_use]
pub fn crash_hash(j: &Json) -> String {
    blake3::hash(canonical(j).as_bytes()).to_hex().to_string()
}

/// One call on a process's tape and what it answered.
#[derive(Clone, Debug)]
pub struct TapeEntry {
    pub call: String,
    pub outcome: Result<Value, String>,
    /// The kind of a fatal error, when the call raised one: the `Err` is its
    /// message, and no `rescue` caught it.
    pub fatal: Option<String>,
    /// Where a fatal error was raised: the span of the call.
    pub at: Option<Span>,
}

impl TapeEntry {
    /// The entry a call's result makes.
    #[must_use]
    pub fn of(call: &str, out: &Result<Value, EvalError>) -> Self {
        let (outcome, fatal, at) = match out {
            Ok(v) => (Ok(v.clone()), None, None),
            Err(EvalError::Fatal { kind, message, at }) => (
                Err(message.to_string()),
                Some(kind.to_string()),
                Some(*at).filter(|s| !s.is_synthetic()),
            ),
            Err(e) => (Err(e.to_string()), None, None),
        };
        Self {
            call: call.to_string(),
            outcome,
            fatal,
            at,
        }
    }
}

/// A held process's mailbox at its exit: the last messages it took and the
/// first still waiting, each list at most `bound` long.
#[derive(Clone, Debug)]
pub struct Journal {
    pub bound: usize,
    pub recent: Vec<Value>,
    pub unconsumed: Vec<Value>,
    /// How many were waiting, of which `unconsumed` keeps the first `bound`.
    pub unconsumed_total: usize,
}

/// One scheduling slice: whose it was, how it ended, what it cost.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SliceRecord {
    pub pid: u64,
    pub outcome: String,
    pub burned: usize,
}

/// A crashed incarnation, replayable on its own.
#[derive(Clone, Debug)]
pub struct Trace {
    pub pid: u64,
    pub incarnation: usize,
    pub definition: Option<String>,
    /// The `def_hash` of [`Self::definition`], when it has one.
    pub def_hash: Option<String>,
    /// The exit reason as blue sees it, e.g. `[:crashed, "…"]`.
    pub reason: Value,
    /// The rendered reason; a replay reproduces the crash when it renders the
    /// same text.
    pub reason_text: String,
    pub reason_kind: String,
    pub budget: Budget,
    pub code: Code,
    pub tape: Vec<TapeEntry>,
    pub truncated: bool,
    pub schedule: Vec<SliceRecord>,
    pub clock: ClockKind,
    /// The hold the process ran under, if any.
    pub hold: Option<Frame>,
    /// Its mailbox journal, when it ran under a hold with one.
    pub mailbox: Option<Journal>,
    /// What the exit violated, if it is a violation.
    pub violation: Option<Violation>,
    /// Where [`Self::definition`] is defined, when the runtime said.
    pub defined_at: Option<Place>,
    /// Host calls the incarnation made through granted names, under a hold.
    pub host_io: Option<u64>,
}

/// The kind of an abnormal exit, as a trace names it.
#[must_use]
pub fn reason_kind(r: &ExitReason) -> &'static str {
    match r {
        ExitReason::Normal => "normal",
        ExitReason::Crashed(_) => "crashed",
        ExitReason::Runaway(_) => "runaway",
        ExitReason::Killed(_) => "killed",
        ExitReason::Fatal(_) => "fatal",
    }
}

/// The comparable text of an exit.
#[must_use]
pub fn reason_text(r: &ExitReason) -> String {
    match r {
        ExitReason::Normal => "normal".into(),
        ExitReason::Crashed(m)
        | ExitReason::Runaway(m)
        | ExitReason::Killed(m)
        | ExitReason::Fatal(m) => m.clone(),
    }
}

// ── values ─────────────────────────────────────────────────────────────────

/// A host handle read back from a trace: something the process held and
/// passed back to the host, never something it can look inside.
#[derive(Debug)]
pub struct Opaque(pub String);

fn one(kind: &str, v: Json) -> Json {
    let mut m = JsonMap::new();
    m.insert(kind.to_string(), v);
    Json::Object(m)
}

fn float_json(x: f64) -> Json {
    serde_json::Number::from_f64(x)
        .map_or_else(|| one("float_bits", json!(x.to_bits())), Json::Number)
}

/// A value as trace JSON.
#[must_use]
pub fn value_to_json(v: &Value) -> Json {
    match v {
        Value::Nil => Json::Null,
        Value::Bool(b) => one("bool", json!(b)),
        Value::Int(n) => one("int", json!(n)),
        Value::Float(x) => one("float", float_json(*x)),
        Value::Str(s) => one("str", json!(&**s)),
        Value::Symbol(s) => one("sym", json!(&**s)),
        Value::Keyword(s) => one("kw", json!(&**s)),
        Value::List(items) => one(
            "list",
            Json::Array(items.iter().map(value_to_json).collect()),
        ),
        Value::Map(m) => one(
            "map",
            Json::Array(
                m.iter()
                    .map(|(k, v)| Json::Array(vec![value_to_json(&k.to_value()), value_to_json(v)]))
                    .collect(),
            ),
        ),
        Value::Error(e) => one(
            "error",
            json!({
                "tag": &*e.tag,
                "message": &*e.message,
                "data": e.data.iter().map(|(k, v)| json!([value_to_json(k), value_to_json(v)])).collect::<Vec<_>>(),
            }),
        ),
        Value::Sexp(s, span) => one("form", form_to_json(&Spanned::from_sexp_at(s, *span))),
        Value::Foreign(any) if any.is::<Opaque>() => one(
            "opaque",
            json!(any.downcast_ref::<Opaque>().map_or("", |o| o.0.as_str())),
        ),
        other => one("opaque", json!(other.type_name())),
    }
}

fn bad(what: &str) -> String {
    format!("not a {FORMAT} {what}")
}

/// Trace JSON back to a value.
///
/// # Errors
///
/// When the JSON is not a value in this format.
pub fn value_from_json(j: &Json) -> Result<Value, String> {
    if j.is_null() {
        return Ok(Value::Nil);
    }
    let (kind, v) = single(j, "value")?;
    Ok(match kind {
        "bool" => Value::Bool(v.as_bool().ok_or_else(|| bad("bool"))?),
        "int" => Value::Int(v.as_i64().ok_or_else(|| bad("int"))?),
        "float" => match v {
            Json::Object(_) => {
                let (_, bits) = single(v, "float")?;
                Value::Float(f64::from_bits(bits.as_u64().ok_or_else(|| bad("float"))?))
            }
            _ => Value::Float(v.as_f64().ok_or_else(|| bad("float"))?),
        },
        "float_bits" => Value::Float(f64::from_bits(v.as_u64().ok_or_else(|| bad("float"))?)),
        "str" => Value::Str(Arc::from(v.as_str().ok_or_else(|| bad("str"))?)),
        "sym" => Value::Symbol(Arc::from(v.as_str().ok_or_else(|| bad("sym"))?)),
        "kw" => Value::Keyword(Arc::from(v.as_str().ok_or_else(|| bad("kw"))?)),
        "list" => Value::list(
            v.as_array()
                .ok_or_else(|| bad("list"))?
                .iter()
                .map(value_from_json)
                .collect::<Result<Vec<_>, _>>()?,
        ),
        "map" => {
            let mut entries = Vec::new();
            for pair in v.as_array().ok_or_else(|| bad("map"))? {
                let [k, v] = pair.as_array().map(Vec::as_slice).unwrap_or_default() else {
                    return Err(bad("map entry"));
                };
                let key = MapKey::from_value(&value_from_json(k)?).ok_or_else(|| bad("map key"))?;
                entries.push((key, value_from_json(v)?));
            }
            Value::map(entries)
        }
        "error" => {
            let tag = v
                .get("tag")
                .and_then(Json::as_str)
                .ok_or_else(|| bad("error"))?;
            let message = v
                .get("message")
                .and_then(Json::as_str)
                .ok_or_else(|| bad("error"))?;
            let mut data = Vec::new();
            for pair in v
                .get("data")
                .and_then(Json::as_array)
                .cloned()
                .unwrap_or_default()
            {
                let [k, v] = pair.as_array().map(Vec::as_slice).unwrap_or_default() else {
                    return Err(bad("error data"));
                };
                data.push((value_from_json(k)?, value_from_json(v)?));
            }
            Value::Error(Arc::new(ErrorObj {
                tag: Arc::from(tag),
                message: Arc::from(message),
                data,
            }))
        }
        "form" => {
            let f = form_from_json(v)?;
            Value::Sexp(f.to_sexp(), f.span)
        }
        "opaque" => Value::Foreign(Arc::new(Opaque(v.as_str().unwrap_or_default().to_string()))),
        other => return Err(format!("unknown value kind `{other}`")),
    })
}

fn single<'a>(j: &'a Json, what: &str) -> Result<(&'a str, &'a Json), String> {
    let obj = j.as_object().ok_or_else(|| bad(what))?;
    obj.iter()
        .find(|(k, _)| k.as_str() != "at")
        .map(|(k, v)| (k.as_str(), v))
        .ok_or_else(|| bad(what))
}

// ── forms ──────────────────────────────────────────────────────────────────

/// A form as trace JSON, spans kept.
#[must_use]
pub fn form_to_json(f: &Spanned) -> Json {
    let mut m = JsonMap::new();
    let (kind, v) = match &f.form {
        SpannedForm::Nil => ("nil", json!(true)),
        SpannedForm::Atom(Atom::Symbol(s)) => ("sym", json!(s)),
        SpannedForm::Atom(Atom::Keyword(s)) => ("kw", json!(s)),
        SpannedForm::Atom(Atom::Str(s)) => ("str", json!(s)),
        SpannedForm::Atom(Atom::Int(n)) => ("int", json!(n)),
        SpannedForm::Atom(Atom::Float(x)) => ("float", float_json(*x)),
        SpannedForm::Atom(Atom::Bool(b)) => ("bool", json!(b)),
        SpannedForm::List(items) => (
            "list",
            Json::Array(items.iter().map(form_to_json).collect()),
        ),
        SpannedForm::Quote(x) => ("quote", form_to_json(x)),
        SpannedForm::Quasiquote(x) => ("quasiquote", form_to_json(x)),
        SpannedForm::Unquote(x) => ("unquote", form_to_json(x)),
        SpannedForm::UnquoteSplice(x) => ("splice", form_to_json(x)),
    };
    m.insert(kind.to_string(), v);
    if f.span != Span::synthetic() {
        m.insert("at".into(), json!([f.span.start, f.span.end]));
    }
    Json::Object(m)
}

/// Trace JSON back to a form.
///
/// # Errors
///
/// When the JSON is not a form in this format.
pub fn form_from_json(j: &Json) -> Result<Spanned, String> {
    let span = match j.get("at").and_then(Json::as_array).map(Vec::as_slice) {
        Some([s, e]) => Span::new(
            usize::try_from(s.as_u64().ok_or_else(|| bad("span"))?).map_err(|e| e.to_string())?,
            usize::try_from(e.as_u64().ok_or_else(|| bad("span"))?).map_err(|e| e.to_string())?,
        ),
        _ => Span::synthetic(),
    };
    let (kind, v) = single(j, "form")?;
    let text = || v.as_str().map(str::to_string).ok_or_else(|| bad("form"));
    let boxed = |v: &Json| form_from_json(v).map(Box::new);
    let form = match kind {
        "nil" => SpannedForm::Nil,
        "sym" => SpannedForm::Atom(Atom::Symbol(text()?)),
        "kw" => SpannedForm::Atom(Atom::Keyword(text()?)),
        "str" => SpannedForm::Atom(Atom::Str(text()?)),
        "int" => SpannedForm::Atom(Atom::Int(v.as_i64().ok_or_else(|| bad("form"))?)),
        "float" => SpannedForm::Atom(Atom::Float(match v {
            Json::Object(_) => {
                f64::from_bits(single(v, "float")?.1.as_u64().ok_or_else(|| bad("float"))?)
            }
            _ => v.as_f64().ok_or_else(|| bad("float"))?,
        })),
        "bool" => SpannedForm::Atom(Atom::Bool(v.as_bool().ok_or_else(|| bad("form"))?)),
        "list" => SpannedForm::List(
            v.as_array()
                .ok_or_else(|| bad("form"))?
                .iter()
                .map(form_from_json)
                .collect::<Result<_, _>>()?,
        ),
        "quote" => SpannedForm::Quote(boxed(v)?),
        "quasiquote" => SpannedForm::Quasiquote(boxed(v)?),
        "unquote" => SpannedForm::Unquote(boxed(v)?),
        "splice" => SpannedForm::UnquoteSplice(boxed(v)?),
        other => return Err(format!("unknown form kind `{other}`")),
    };
    Ok(Spanned::new(span, form))
}

// ── the trace ──────────────────────────────────────────────────────────────

fn opt(n: Option<usize>) -> Json {
    n.map_or(Json::Null, |n| json!(n))
}

fn opt_from(j: Option<&Json>) -> Option<usize> {
    j.and_then(Json::as_u64)
        .and_then(|n| usize::try_from(n).ok())
}

impl Trace {
    /// This trace as `blue-trace` JSON.
    #[must_use]
    pub fn to_json(&self) -> Json {
        json!({
            "format": FORMAT,
            "version": VERSION,
            "pid": self.pid,
            "incarnation": self.incarnation,
            "definition": self.definition,
            "def_hash": self.def_hash,
            "defined_at": self.defined_at.as_ref().map_or(Json::Null, |p| json!({"file": p.file, "line": p.line, "column": p.column})),
            "exit": { "kind": self.reason_kind, "text": self.reason_text, "reason": value_to_json(&self.reason) },
            "violation": self.violation.as_ref().map_or(Json::Null, Violation::to_json),
            "budget": { "fuel": opt(self.budget.fuel), "max_depth": opt(self.budget.max_depth), "quantum": opt(self.budget.quantum) },
            "clock": self.clock.label(),
            "code": {
                "defs": self.code.defs.iter().map(form_to_json).collect::<Vec<_>>(),
                "bindings": self.code.bindings.iter().map(|(n, v)| json!({"name": &**n, "value": value_to_json(v)})).collect::<Vec<_>>(),
                "start": self.code.start.as_ref().map_or(Json::Null, form_to_json),
            },
            "tape": self.tape.iter().map(|e| match (&e.outcome, &e.fatal) {
                (Ok(v), _) => json!({"call": e.call, "value": value_to_json(v)}),
                (Err(m), Some(kind)) => {
                    let mut fatal = json!({"kind": kind, "message": m});
                    if let Some(s) = e.at {
                        fatal["at"] = json!([s.start, s.end]);
                    }
                    json!({"call": e.call, "fatal": fatal})
                }
                (Err(m), None) => json!({"call": e.call, "raised": m}),
            }).collect::<Vec<_>>(),
            "truncated": self.truncated,
            "schedule": self.schedule.iter().map(|s| json!({"pid": s.pid, "outcome": s.outcome, "burned": s.burned})).collect::<Vec<_>>(),
            "hold": self.hold.as_ref().map_or(Json::Null, Frame::to_json),
            "frame": self.hold.as_ref().map_or(Json::Null, |h| h.block(self.host_io.unwrap_or(0))),
            "mailbox": self.mailbox.as_ref().map_or(Json::Null, |m| json!({
                "bound": m.bound,
                "recent": m.recent.iter().map(value_to_json).collect::<Vec<_>>(),
                "unconsumed": m.unconsumed.iter().map(value_to_json).collect::<Vec<_>>(),
                "unconsumed_total": m.unconsumed_total,
            })),
        })
    }

    /// Read a trace back.
    ///
    /// # Errors
    ///
    /// When the JSON is not a `blue-trace`, or is a version this crate does
    /// not read.
    pub fn from_json(j: &Json) -> Result<Self, String> {
        if j.get("format").and_then(Json::as_str) != Some(FORMAT) {
            return Err(format!("not a {FORMAT} file"));
        }
        let version = j.get("version").and_then(Json::as_u64).unwrap_or(0);
        if !READS.contains(&version) {
            return Err(format!(
                "{FORMAT} version {version}; this blue reads versions 1 to {VERSION}"
            ));
        }
        let field = |k: &str| j.get(k).ok_or_else(|| format!("{FORMAT}: missing `{k}`"));
        let exit = field("exit")?;
        let budget = field("budget")?;
        let code = field("code")?;
        let mut bindings = Vec::new();
        for b in code
            .get("bindings")
            .and_then(Json::as_array)
            .cloned()
            .unwrap_or_default()
        {
            let name = b
                .get("name")
                .and_then(Json::as_str)
                .ok_or_else(|| bad("binding"))?;
            bindings.push((
                Arc::from(name),
                value_from_json(b.get("value").unwrap_or(&Json::Null))?,
            ));
        }
        let mut tape = Vec::new();
        for e in field("tape")?.as_array().ok_or_else(|| bad("tape"))? {
            let call = e
                .get("call")
                .and_then(Json::as_str)
                .ok_or_else(|| bad("tape entry"))?;
            let text = |f: &Json, k: &str| {
                f.get(k)
                    .and_then(Json::as_str)
                    .map(str::to_string)
                    .ok_or_else(|| bad("fatal entry"))
            };
            let (outcome, fatal) = match (e.get("fatal"), e.get("raised").and_then(Json::as_str)) {
                (Some(f), _) => (Err(text(f, "message")?), Some(text(f, "kind")?)),
                (None, Some(m)) => (Err(m.to_string()), None),
                (None, None) => (
                    Ok(value_from_json(e.get("value").unwrap_or(&Json::Null))?),
                    None,
                ),
            };
            let at = match e
                .get("fatal")
                .and_then(|f| f.get("at"))
                .and_then(Json::as_array)
                .map(Vec::as_slice)
            {
                Some([s, e]) => match (opt_from(Some(s)), opt_from(Some(e))) {
                    (Some(s), Some(e)) => Some(Span::new(s, e)),
                    _ => return Err(bad("fatal span")),
                },
                _ => None,
            };
            tape.push(TapeEntry {
                call: call.to_string(),
                outcome,
                fatal,
                at,
            });
        }
        let schedule = j
            .get("schedule")
            .and_then(Json::as_array)
            .cloned()
            .unwrap_or_default()
            .iter()
            .map(|s| SliceRecord {
                pid: s.get("pid").and_then(Json::as_u64).unwrap_or(0),
                outcome: s
                    .get("outcome")
                    .and_then(Json::as_str)
                    .unwrap_or("")
                    .to_string(),
                burned: opt_from(s.get("burned")).unwrap_or(0),
            })
            .collect();
        let reason_kind = exit
            .get("kind")
            .and_then(Json::as_str)
            .unwrap_or("")
            .to_string();
        let defs: Vec<Spanned> = code
            .get("defs")
            .and_then(Json::as_array)
            .cloned()
            .unwrap_or_default()
            .iter()
            .map(form_from_json)
            .collect::<Result<_, _>>()?;
        let violation = if version >= 3 {
            match j.get("violation") {
                None | Some(Json::Null) => None,
                Some(v) => Some(Violation::from_json(v)?),
            }
        } else {
            Violation::of(&reason_kind, &tape, &defs, &Places::default())
        };
        let defined_at = j.get("defined_at").and_then(|p| {
            Some(Place {
                file: p.get("file")?.as_str()?.to_string(),
                line: opt_from(p.get("line"))?,
                column: opt_from(p.get("column"))?,
            })
        });
        Ok(Self {
            violation,
            defined_at,
            host_io: j
                .get("frame")
                .and_then(|f| f.get("host_io"))
                .and_then(Json::as_u64),
            pid: field("pid")?.as_u64().ok_or_else(|| bad("pid"))?,
            incarnation: opt_from(j.get("incarnation")).unwrap_or(0),
            definition: j
                .get("definition")
                .and_then(Json::as_str)
                .map(str::to_string),
            def_hash: j.get("def_hash").and_then(Json::as_str).map(str::to_string),
            reason: value_from_json(exit.get("reason").unwrap_or(&Json::Null))?,
            reason_text: exit
                .get("text")
                .and_then(Json::as_str)
                .unwrap_or("")
                .to_string(),
            reason_kind,
            budget: Budget {
                fuel: opt_from(budget.get("fuel")),
                max_depth: opt_from(budget.get("max_depth")),
                quantum: opt_from(budget.get("quantum")),
            },
            code: Code {
                defs,
                bindings,
                start: match code.get("start") {
                    None | Some(Json::Null) => None,
                    Some(f) => Some(form_from_json(f)?),
                },
            },
            tape,
            truncated: j.get("truncated").and_then(Json::as_bool).unwrap_or(false),
            schedule,
            clock: match j.get("clock").and_then(Json::as_str) {
                Some("real") => ClockKind::Real,
                _ => ClockKind::Virtual,
            },
            hold: match j.get("hold") {
                None | Some(Json::Null) => None,
                Some(h) => Some(Frame::from_json(h)?),
            },
            mailbox: match j.get("mailbox") {
                None | Some(Json::Null) => None,
                Some(m) => Some(journal_from_json(m)?),
            },
        })
    }

    /// `bluecrash` for a fatal exit, `json` for any other.
    #[must_use]
    pub fn extension(&self) -> &'static str {
        if self.reason_kind == "fatal" {
            CRASH_EXTENSION
        } else {
            TRACE_EXTENSION
        }
    }

    /// The bytes this trace is written as: its JSON, canonical.
    #[must_use]
    pub fn bytes(&self) -> Vec<u8> {
        canonical(&self.to_json()).into_bytes()
    }

    /// This trace's content address: the BLAKE3 hash of [`Self::bytes`], in
    /// hex.
    #[must_use]
    pub fn crash_hash(&self) -> String {
        crash_hash(&self.to_json())
    }

    /// Parse a trace file's text.
    ///
    /// # Errors
    ///
    /// As [`Trace::from_json`], or when the text is not JSON.
    pub fn parse(text: &str) -> Result<Self, String> {
        let j: Json = serde_json::from_str(text).map_err(|e| format!("not JSON: {e}"))?;
        Self::from_json(&j)
    }

    /// Write this trace into `dir`, creating it, under its content address
    /// (`<crash_hash>.bluecrash` or `<crash_hash>.json`), and answer the
    /// file's path. The same crash is the same file.
    ///
    /// # Errors
    ///
    /// When the directory or the file cannot be written.
    pub fn write_to(&self, dir: &Path) -> std::io::Result<PathBuf> {
        std::fs::create_dir_all(dir)?;
        let bytes = self.bytes();
        let path = dir.join(format!(
            "{}.{}",
            blake3::hash(&bytes).to_hex(),
            self.extension()
        ));
        std::fs::write(&path, bytes)?;
        Ok(path)
    }
}

// ── replay ─────────────────────────────────────────────────────────────────

/// What a replay did.
#[derive(Clone, Debug)]
pub struct Replayed {
    /// The replay ended the way the trace says the process did.
    pub reproduced: bool,
    /// How the replay ended: `normal`, or the kind and text of its exit.
    pub kind: String,
    pub text: String,
    /// Tape entries the replay consumed, of how many.
    pub consumed: usize,
    pub tape_len: usize,
    /// Where the replay left the recorded run, if it did.
    pub diverged: Option<String>,
}

struct Cursor {
    tape: Vec<TapeEntry>,
    pos: usize,
    diverged: Option<String>,
}

fn journal_from_json(j: &Json) -> Result<Journal, String> {
    let values = |k: &str| -> Result<Vec<Value>, String> {
        j.get(k)
            .and_then(Json::as_array)
            .ok_or_else(|| bad("mailbox"))?
            .iter()
            .map(value_from_json)
            .collect()
    };
    Ok(Journal {
        bound: opt_from(j.get("bound")).ok_or_else(|| bad("mailbox"))?,
        recent: values("recent")?,
        unconsumed: values("unconsumed")?,
        unconsumed_total: opt_from(j.get("unconsumed_total")).unwrap_or(0),
    })
}

/// Install a tape reader under `name`. `withheld` names the capability when
/// the recorded hold withholds `name`: the tape may then answer only with the
/// fatal error the live call raised.
fn reader(
    interp: &mut Interpreter<()>,
    name: &str,
    cursor: &Arc<Mutex<Cursor>>,
    withheld: Option<&'static str>,
) {
    let cursor = cursor.clone();
    let word: Arc<str> = Arc::from(name);
    interp.register_fn(
        name.to_string(),
        Arity::Any,
        move |_args: &[Value], _h: &mut (), span| {
            let mut c = cursor
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let pos = c.pos;
            let Some(entry) = c.tape.get(pos).cloned() else {
                let why = format!("the process called `{word}` after its tape ended ({pos} calls)");
                c.diverged.get_or_insert(why.clone());
                return Err(EvalError::native_fn(word.clone(), why, span));
            };
            if entry.call != *word {
                let why = format!(
                    "at tape entry {pos} the process called `{word}` where the trace recorded `{}`",
                    entry.call
                );
                c.diverged.get_or_insert(why.clone());
                return Err(EvalError::native_fn(word.clone(), why, span));
            }
            if let (Some(cap), None) = (withheld, &entry.fatal) {
                let why = format!(
                    "at tape entry {pos} the trace records `{word}` reaching the host, which its hold withholds ({cap})"
                );
                c.diverged.get_or_insert(why.clone());
                return Err(EvalError::native_fn(word.clone(), why, span));
            }
            c.pos += 1;
            match (entry.outcome, entry.fatal) {
                (Ok(v), _) => Ok(v),
                (Err(m), Some(kind)) => Err(EvalError::fatal(kind, m, span)),
                (Err(m), None) => Err(EvalError::native_fn(word.clone(), m, span)),
            }
        },
    );
}

/// Run `trace`'s incarnation again in `interp`, from its tape alone.
///
/// `interp` is a fresh interpreter from the same runtime the process ran on;
/// every process word and host name in it is rebound to the tape before
/// anything runs, so the replay is sandboxed and time-frozen by construction.
/// A trace with a hold replays under it: a name the hold withholds answers
/// only with the fatal error its tape recorded, so a breach replays as the
/// same breach at the same tape entry.
#[must_use]
pub fn replay(trace: &Trace, mut interp: Interpreter<()>) -> Replayed {
    let cursor = Arc::new(Mutex::new(Cursor {
        tape: trace.tape.clone(),
        pos: 0,
        diverged: None,
    }));
    let withheld: std::collections::BTreeMap<&str, &'static str> = trace
        .hold
        .iter()
        .flat_map(Frame::withheld_names)
        .map(|(n, c)| (n, c.label()))
        .collect();
    let host = host_names();
    for name in PROCESS_WORDS
        .iter()
        .chain([&SERVER_NEXT])
        .chain(host.iter())
    {
        reader(&mut interp, name, &cursor, withheld.get(name).copied());
    }
    for (n, v) in &trace.code.bindings {
        interp.define_global(n.clone(), v.clone());
    }
    let ran = compile_program(&trace.code.program())
        .map_err(|e| ExitReason::Crashed(e.to_string()))
        .and_then(|chunk| {
            let mut vm = Vm::with_budget(Budget {
                quantum: None,
                ..trace.budget
            });
            vm.run(&chunk, &mut interp, &mut ())
                .map_err(|e| classify(&e))
        });
    let c = cursor
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let (kind, text) = match &ran {
        Ok(_) => ("normal".to_string(), "normal".to_string()),
        Err(r) => (reason_kind(r).to_string(), reason_text(r)),
    };
    // A process killed from outside did not crash itself: its replay runs the
    // tape to the end and stops where the signal arrived.
    let killed_at_tape_end =
        trace.reason_kind == "killed" && c.pos == c.tape.len() && c.diverged.is_some();
    let reproduced = !trace.truncated
        && (killed_at_tape_end
            || (c.diverged.is_none() && kind == trace.reason_kind && text == trace.reason_text));
    Replayed {
        reproduced,
        kind,
        text,
        consumed: c.pos,
        tape_len: c.tape.len(),
        diverged: if killed_at_tape_end {
            None
        } else {
            c.diverged.clone()
        },
    }
}
