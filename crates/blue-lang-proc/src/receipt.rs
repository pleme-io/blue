//! What an actor or a run is held to, what it did through the host, and the
//! receipt that says so.
//!
//! Four pieces a node shares with the runtime that builds it:
//!
//! - [`Frame`]: the hold as its artifacts name it: the host capabilities
//!   granted from the host, those a pure provider stands in for, and those
//!   withheld (a breach). Written into a crash trace and into a receipt.
//! - [`HostIo`]: one ledger of host calls per node. The runtime's counting
//!   shim (`blue_lang_runtime::Hold::bind`) tallies a call through a granted
//!   host name; the node says whose call it is by switching the ledger's
//!   current process with every slice. A name the hold withholds or provides
//!   gets no shim, so a pure frame counts nothing by construction.
//! - [`Identities`]: each definition key's `def_hash`, computed only when an
//!   artifact asks for one.
//! - [`Places`]: each definition key's file and text, read only when a crash
//!   asks where its breaching call is.
//!
//! ## Format `blue-receipt`, versions 1 and 2
//!
//! One canonical JSON object (keys sorted, no whitespace), named by the
//! BLAKE3 hash of its bytes (`blue_lang_runtime::receipt` writes and
//! verifies it):
//!
//! ```text
//! { "def_hash": "b3:…" | null, "definition": "%root/reader" | "%run" | null,
//!   "exit": { "kind": "normal" | "crashed" | "runaway" | "killed" | "fatal" | "refused", "text": "…" },
//!   "format": "blue-receipt",
//!   "frame": { "granted": [LABEL…], "host_io": n, "withheld": [LABEL…] },
//!   "incarnation": n, "pid": n,
//!   "provided": [{ "provider": "deterministic-stepped", …, "for": [PACKAGE…] }…],
//!   "subject": "actor" | "run", "version": 1 }
//! ```
//!
//! Version 2 is version 1 with two more keys, written only for a
//! `spawn_server` incarnation, whose state the node holds:
//!
//! ```text
//! { …, "input_root": "b3:…", "output_root": "b3:…", …, "version": 2 }
//! ```
//!
//! `input_root` is the [`StateRoot`] of the state the incarnation began
//! with, before its first message; `output_root` that of the state after
//! the last message its handler returned from. A receipt without roots is
//! version 1, byte for byte as before version 2 existed, so the name of
//! every receipt a run wrote before stays the name it has.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, MutexGuard};

use blue_lang_waku::{Capability, Provided};
use serde_json::{json, Value as Json};

use crate::Pid;

/// The format name every receipt carries.
pub const FORMAT: &str = "blue-receipt";
/// The version a receipt with state roots carries.
pub const VERSION: u64 = 2;
/// The version a receipt without state roots carries.
pub const VERSION_UNROOTED: u64 = 1;
/// Every version [`check`] accepts.
pub const READS: [u64; 2] = [VERSION_UNROOTED, VERSION];
/// The keys only a version 2 receipt has.
pub const ROOT_KEYS: [&str; 2] = ["input_root", "output_root"];

/// The root of a server's state: `b3:` and the BLAKE3 hash of its canonical
/// JSON. The runtime computes it (`blue_lang_runtime::json::state_root`); a
/// node only calls it.
pub type StateRoot = fn(&tatara_lisp_eval::Value) -> String;

/// A server incarnation's state roots: before its first message, and after
/// the last one its handler returned from.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Roots {
    pub input: String,
    pub output: String,
}

fn is_root(text: &str) -> bool {
    text.strip_prefix("b3:").is_some_and(|hex| {
        hex.len() == 64
            && hex
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    })
}

/// Whether `receipt` has the form its `version` names: version 1 carries no
/// state root, version 2 carries both, each `b3:` and 64 lowercase hex
/// digits.
///
/// # Errors
///
/// Naming a version this blue does not read, or the root that is missing,
/// present where it may not be, or not a hash.
pub fn check(receipt: &Json) -> Result<(), String> {
    let version = receipt.get("version").and_then(Json::as_u64);
    let rooted = match version {
        Some(VERSION_UNROOTED) => false,
        Some(VERSION) => true,
        _ => {
            return Err(format!(
                "{FORMAT} version {}; this blue reads versions {} to {VERSION}",
                receipt.get("version").unwrap_or(&Json::Null),
                READS[0]
            ))
        }
    };
    for key in ROOT_KEYS {
        match (rooted, receipt.get(key)) {
            (false, None) => {}
            (false, Some(_)) => {
                return Err(format!(
                    "a version {VERSION_UNROOTED} receipt carries `{key}`, which only version {VERSION} has"
                ))
            }
            (true, None) => return Err(format!("a version {VERSION} receipt without `{key}`")),
            (true, Some(root)) if !root.as_str().is_some_and(is_root) => {
                return Err(format!("`{key}` is {root}, not b3: and 64 hex digits"))
            }
            (true, Some(_)) => {}
        }
    }
    Ok(())
}

fn locked<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// A hold as an artifact names it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Frame {
    /// Host capabilities granted from the host.
    pub granted: Vec<Capability>,
    /// The pure providers standing in for host capabilities, each for the
    /// whole program or, under `for`, for the packages it names.
    pub provided: Vec<Provided>,
    /// Host capabilities neither granted nor provided: a call is a breach.
    pub withheld: Vec<Capability>,
}

fn labels(caps: &[Capability]) -> Json {
    Json::Array(caps.iter().map(|c| json!(c.label())).collect())
}

fn capability(label: &str) -> Option<Capability> {
    Capability::host_effects()
        .into_iter()
        .find(|c| c.label() == label)
}

fn capabilities(j: Option<&Json>, what: &str) -> Result<Vec<Capability>, String> {
    j.and_then(Json::as_array)
        .ok_or_else(|| format!("a hold without `{what}`"))?
        .iter()
        .map(|l| {
            l.as_str()
                .and_then(capability)
                .ok_or_else(|| format!("`{l}` in `{what}` is not a host capability"))
        })
        .collect()
}

impl Frame {
    /// The receipt's frame block: `{"granted":[…],"withheld":[…],"host_io":n}`.
    #[must_use]
    pub fn block(&self, host_io: u64) -> Json {
        json!({
            "granted": labels(&self.granted),
            "withheld": labels(&self.withheld),
            "host_io": host_io,
        })
    }

    /// The providers as the lock records them: the provider, its settings,
    /// and `for` with the packages it serves when it is scoped.
    #[must_use]
    pub fn provided_json(&self) -> Json {
        Json::Array(
            self.provided
                .iter()
                .map(|p| serde_json::to_value(p).unwrap_or(Json::Null))
                .collect(),
        )
    }

    /// The hold as a crash trace writes it.
    #[must_use]
    pub fn to_json(&self) -> Json {
        json!({
            "granted": labels(&self.granted),
            "provided": self.provided_json(),
            "withheld": labels(&self.withheld),
        })
    }

    /// Read a hold back.
    ///
    /// # Errors
    ///
    /// When a list is missing, a label names no host capability, or a
    /// provider does not parse.
    pub fn from_json(j: &Json) -> Result<Self, String> {
        let provided = j
            .get("provided")
            .and_then(Json::as_array)
            .ok_or("a hold without `provided`")?
            .iter()
            .map(|p| serde_json::from_value(p.clone()).map_err(|e| format!("a provider: {e}")))
            .collect::<Result<_, _>>()?;
        Ok(Self {
            granted: capabilities(j.get("granted"), "granted")?,
            provided,
            withheld: capabilities(j.get("withheld"), "withheld")?,
        })
    }

    /// Every host name the hold withholds, with its capability.
    #[must_use]
    pub fn withheld_names(&self) -> Vec<(&'static str, Capability)> {
        self.withheld
            .iter()
            .flat_map(|c| c.names().into_iter().map(move |n| (n, *c)))
            .collect()
    }
}

#[derive(Debug, Default)]
struct Ledger {
    current: Pid,
    total: u64,
    by_pid: BTreeMap<Pid, u64>,
}

/// Host calls made through granted host names, per process of one node.
#[derive(Clone, Debug, Default)]
pub struct HostIo(Arc<Mutex<Ledger>>);

impl HostIo {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// One host call, by the process running now.
    pub fn tally(&self) {
        let mut l = locked(&self.0);
        l.total += 1;
        let pid = l.current;
        *l.by_pid.entry(pid).or_default() += 1;
    }

    /// Every call tallied, by every process.
    #[must_use]
    pub fn total(&self) -> u64 {
        locked(&self.0).total
    }

    /// The calls `pid` made since its incarnation began.
    #[must_use]
    pub fn of(&self, pid: Pid) -> u64 {
        locked(&self.0).by_pid.get(&pid).copied().unwrap_or(0)
    }

    /// `pid` runs now: what is tallied is its.
    pub fn enter(&self, pid: Pid) {
        locked(&self.0).current = pid;
    }

    /// `pid`'s count, which starts again at zero.
    pub fn take(&self, pid: Pid) -> u64 {
        locked(&self.0).by_pid.remove(&pid).unwrap_or(0)
    }
}

type Deferred<T> = Box<dyn FnOnce() -> T + Send>;

enum Table<T> {
    Unknown,
    Deferred(Deferred<T>),
    Known(T),
}

/// A table the runtime hands a node unfinished: computed the first time an
/// artifact asks, and never when none does.
struct Lazy<T>(Arc<Mutex<Table<T>>>);

impl<T> Clone for Lazy<T> {
    fn clone(&self) -> Self {
        Self(Arc::clone(&self.0))
    }
}

impl<T> Default for Lazy<T> {
    fn default() -> Self {
        Self(Arc::new(Mutex::new(Table::Unknown)))
    }
}

impl<T> Lazy<T> {
    fn defer(&self, compute: impl FnOnce() -> T + Send + 'static) {
        *locked(&self.0) = Table::Deferred(Box::new(compute));
    }

    fn read<R>(&self, f: impl FnOnce(&T) -> Option<R>) -> Option<R> {
        let mut state = locked(&self.0);
        if let Table::Deferred(_) = &*state {
            if let Table::Deferred(compute) = std::mem::replace(&mut *state, Table::Unknown) {
                *state = Table::Known(compute());
            }
        }
        match &*state {
            Table::Known(table) => f(table),
            Table::Unknown | Table::Deferred(_) => None,
        }
    }

    fn state(&self) -> &'static str {
        match &*locked(&self.0) {
            Table::Unknown => "unknown",
            Table::Deferred(_) => "deferred",
            Table::Known(_) => "known",
        }
    }
}

/// Each definition key's `def_hash` (`b3:<hex>`), computed on first ask.
#[derive(Clone, Default)]
pub struct Identities(Lazy<BTreeMap<String, String>>);

impl std::fmt::Debug for Identities {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Identities({})", self.0.state())
    }
}

impl Identities {
    /// Compute the table with `hash` when the first identity is asked for.
    pub fn defer(&self, hash: impl FnOnce() -> BTreeMap<String, String> + Send + 'static) {
        self.0.defer(hash);
    }

    /// The `def_hash` of the definition bound to `key`, if it has one.
    #[must_use]
    pub fn of(&self, key: &str) -> Option<String> {
        self.0.read(|table| table.get(key).cloned())
    }
}

/// The file a definition was read from: the name a reader opens it by, and
/// the text its spans index.
#[derive(Clone, Debug)]
pub struct Source {
    pub file: String,
    pub text: Arc<str>,
}

/// A position a reader can open: a file, and a 1-based line and column.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Place {
    pub file: String,
    pub line: usize,
    pub column: usize,
}

impl std::fmt::Display for Place {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}:{}", self.file, self.line, self.column)
    }
}

/// Each definition key's [`Source`], computed on first ask: what turns a
/// span in a crashed process's code into a [`Place`].
#[derive(Clone, Default)]
pub struct Places(Lazy<BTreeMap<String, Source>>);

impl std::fmt::Debug for Places {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Places({})", self.0.state())
    }
}

impl Places {
    /// Compute the table with `read` when the first place is asked for.
    pub fn defer(&self, read: impl FnOnce() -> BTreeMap<String, Source> + Send + 'static) {
        self.0.defer(read);
    }

    /// Where `span` is, inside the definition bound to `key`. `None` for a
    /// synthetic span, a key with no source, or a span past the end of the
    /// key's file: an offset outside the file is proof it indexes another
    /// one, and answering it anyway would name a line that is not the place.
    #[must_use]
    pub fn locate(&self, key: &str, span: tatara_lisp::Span) -> Option<Place> {
        if span.is_synthetic() {
            return None;
        }
        self.0.read(|table| {
            let source = table.get(key)?;
            (span.end <= source.text.len()).then(|| {
                let (line, column) = tatara_lisp::Span::line_col(&source.text, span.start);
                Place {
                    file: source.file.clone(),
                    line,
                    column,
                }
            })
        })
    }
}

/// What a receipt attests about.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Subject {
    /// One incarnation of a process.
    Actor { pid: Pid, incarnation: usize },
    /// A whole run, its root and every process it started.
    Run,
}

/// One actor's or one run's account of itself.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Receipt {
    pub subject: Subject,
    /// The definition key it ran.
    pub definition: Option<String>,
    /// That definition's `def_hash`.
    pub def_hash: Option<String>,
    pub frame: Frame,
    /// Calls through granted host names.
    pub host_io: u64,
    pub exit_kind: String,
    pub exit_text: String,
    /// A server incarnation's state roots; `None` for any other subject,
    /// and then the receipt is version 1.
    pub roots: Option<Roots>,
}

impl Receipt {
    /// This receipt as `blue-receipt` JSON: version 2 with its roots, version
    /// 1 without.
    #[must_use]
    pub fn to_json(&self) -> Json {
        let (subject, pid, incarnation) = match self.subject {
            Subject::Actor { pid, incarnation } => ("actor", pid.0, incarnation),
            Subject::Run => ("run", crate::ROOT.0, 0),
        };
        let mut j = json!({
            "format": FORMAT,
            "version": VERSION_UNROOTED,
            "subject": subject,
            "pid": pid,
            "incarnation": incarnation,
            "definition": self.definition,
            "def_hash": self.def_hash,
            "exit": { "kind": self.exit_kind, "text": self.exit_text },
            "frame": self.frame.block(self.host_io),
            "provided": self.frame.provided_json(),
        });
        if let Some(roots) = &self.roots {
            j["version"] = json!(VERSION);
            j["input_root"] = json!(roots.input);
            j["output_root"] = json!(roots.output);
        }
        j
    }

    /// The bytes a receipt is: its JSON, canonical.
    #[must_use]
    pub fn bytes(&self) -> Vec<u8> {
        canonical(&self.to_json()).into_bytes()
    }
}

/// Where a node hands each actor's receipt.
pub type ReceiptSink = Arc<dyn Fn(&Receipt) + Send + Sync>;

/// `j` with every object's keys sorted and no whitespace: one text per value.
#[must_use]
pub fn canonical(j: &Json) -> String {
    let mut out = String::new();
    write_canonical(j, &mut out);
    out
}

fn write_canonical(j: &Json, out: &mut String) {
    match j {
        Json::Object(m) => {
            let mut keys: Vec<&String> = m.keys().collect();
            keys.sort();
            out.push('{');
            for (i, k) in keys.into_iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                out.push_str(&Json::String(k.clone()).to_string());
                out.push(':');
                write_canonical(&m[k], out);
            }
            out.push('}');
        }
        Json::Array(items) => {
            out.push('[');
            for (i, v) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_canonical(v, out);
            }
            out.push(']');
        }
        other => out.push_str(&other.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame() -> Frame {
        Frame {
            granted: vec![Capability::FileSystem],
            provided: vec![
                blue_lang_waku::Provision::DeterministicStepped {
                    at_ms: 5,
                    step_ms: 1,
                }
                .into(),
                Provided {
                    provision: blue_lang_waku::Provision::NullSink,
                    scope: Some(std::collections::BTreeSet::from(["kazu".to_string()])),
                },
            ],
            withheld: vec![
                Capability::Process,
                Capability::Environment,
                Capability::Network,
                Capability::Entropy,
            ],
        }
    }

    #[test]
    fn the_frame_block_is_granted_withheld_and_host_io_and_nothing_else() {
        let block = frame().block(3);
        let keys: Vec<&String> = block.as_object().expect("object").keys().collect();
        let mut sorted = keys.clone();
        sorted.sort();
        assert_eq!(sorted, ["granted", "host_io", "withheld"]);
        assert_eq!(
            canonical(&block),
            r#"{"granted":["filesystem"],"host_io":3,"withheld":["process","environment","network","entropy"]}"#
        );
    }

    #[test]
    fn a_hold_survives_the_trace_format() {
        let f = frame();
        assert_eq!(Frame::from_json(&f.to_json()).expect("parse"), f);
        let mut bad = f.to_json();
        bad["withheld"] = json!(["disk"]);
        assert!(Frame::from_json(&bad).unwrap_err().contains("disk"));
        assert!(Frame::from_json(&json!({})).is_err());
    }

    #[test]
    fn withheld_names_are_every_name_of_every_withheld_capability() {
        let names = frame().withheld_names();
        assert!(names.contains(&("getenv", Capability::Environment)));
        assert!(names.iter().all(|(_, c)| *c != Capability::FileSystem));
        assert_eq!(
            names.len(),
            frame()
                .withheld
                .iter()
                .map(|c| c.names().len())
                .sum::<usize>()
        );
        assert!(Frame::default().withheld_names().is_empty());
    }

    #[test]
    fn the_ledger_tallies_to_the_process_running_and_takes_per_incarnation() {
        let io = HostIo::new();
        io.tally();
        io.enter(Pid(3));
        io.tally();
        io.tally();
        io.enter(crate::ROOT);
        io.tally();
        assert_eq!(io.total(), 4);
        assert_eq!(io.of(crate::ROOT), 2);
        assert_eq!(io.of(Pid(3)), 2);
        assert_eq!(io.take(Pid(3)), 2);
        assert_eq!(io.of(Pid(3)), 0);
        assert_eq!(io.total(), 4, "the run total keeps every call");
        assert_eq!(HostIo::new().total(), 0);
    }

    #[test]
    fn identities_are_hashed_once_and_only_when_asked() {
        let ids = Identities::default();
        assert_eq!(ids.of("%root/f"), None);
        let calls = Arc::new(Mutex::new(0));
        let c = Arc::clone(&calls);
        ids.defer(move || {
            *locked(&c) += 1;
            BTreeMap::from([("%root/f".to_string(), "b3:00".to_string())])
        });
        assert_eq!(*locked(&calls), 0);
        assert_eq!(ids.of("%root/f").as_deref(), Some("b3:00"));
        assert_eq!(ids.clone().of("%root/g"), None);
        assert_eq!(*locked(&calls), 1);
    }

    #[test]
    fn a_place_is_read_once_and_only_inside_its_own_file() {
        let places = Places::default();
        let at = tatara_lisp::Span::new(10, 14);
        assert_eq!(places.locate("%root/f", at), None);
        let calls = Arc::new(Mutex::new(0));
        let c = Arc::clone(&calls);
        places.defer(move || {
            *locked(&c) += 1;
            BTreeMap::from([(
                "%root/f".to_string(),
                Source {
                    file: "w.b".into(),
                    text: Arc::from("def f()\n  g(1)\nend\n"),
                },
            )])
        });
        assert_eq!(*locked(&calls), 0);
        let place = places.locate("%root/f", at).expect("in its file");
        assert_eq!(place.to_string(), "w.b:2:3");
        assert_eq!(
            places.locate("%root/f", tatara_lisp::Span::new(10, 99)),
            None
        );
        assert_eq!(
            places.locate("%root/f", tatara_lisp::Span::synthetic()),
            None
        );
        assert_eq!(places.clone().locate("%root/g", at), None);
        assert_eq!(*locked(&calls), 1);
    }

    #[test]
    fn canonical_text_sorts_keys_at_every_depth_and_has_no_whitespace() {
        let j = json!({"b": [ {"z": 1, "a": "x y"} ], "a": null});
        assert_eq!(canonical(&j), r#"{"a":null,"b":[{"a":"x y","z":1}]}"#);
        let r = Receipt {
            subject: Subject::Actor {
                pid: Pid(2),
                incarnation: 1,
            },
            definition: Some("%root/w".into()),
            def_hash: Some("b3:ab".into()),
            frame: frame(),
            host_io: 7,
            exit_kind: "normal".into(),
            exit_text: "normal".into(),
            roots: None,
        };
        let text = String::from_utf8(r.bytes()).expect("utf8");
        assert!(!text.contains(' ') && !text.contains('\n'), "{text}");
        let back: Json = serde_json::from_str(&text).expect("json");
        assert_eq!(canonical(&back), text);
        assert_eq!(back["frame"]["host_io"], 7);
        assert_eq!(back["subject"], "actor");
        assert_eq!(back["provided"][0]["provider"], "deterministic-stepped");
        assert!(
            back["provided"][0].get("for").is_none(),
            "a whole-program provider"
        );
        assert_eq!(
            back["provided"][1],
            json!({"provider": "null-sink", "for": ["kazu"]})
        );
    }

    const V1: &str = r#"{"def_hash":"b3:ab","definition":"%root/w","exit":{"kind":"normal","text":"normal"},"format":"blue-receipt","frame":{"granted":["filesystem"],"host_io":7,"withheld":["process","environment","network","entropy"]},"incarnation":1,"pid":2,"provided":[{"at_ms":5,"provider":"deterministic-stepped","step_ms":1},{"for":["kazu"],"provider":"null-sink"}],"subject":"actor","version":1}"#;

    fn actor(roots: Option<Roots>) -> Receipt {
        Receipt {
            subject: Subject::Actor {
                pid: Pid(2),
                incarnation: 1,
            },
            definition: Some("%root/w".into()),
            def_hash: Some("b3:ab".into()),
            frame: frame(),
            host_io: 7,
            exit_kind: "normal".into(),
            exit_text: "normal".into(),
            roots,
        }
    }

    fn root(c: char) -> String {
        format!("b3:{}", c.to_string().repeat(64))
    }

    #[test]
    fn a_receipt_without_roots_is_the_version_1_receipt_byte_for_byte() {
        let r = actor(None);
        assert_eq!(String::from_utf8(r.bytes()).expect("utf8"), V1);
        assert_eq!(check(&r.to_json()), Ok(()));
    }

    #[test]
    fn a_receipt_with_roots_is_version_2_and_without_them_is_version_1_again() {
        let r = actor(Some(Roots {
            input: root('a'),
            output: root('b'),
        }));
        let j = r.to_json();
        assert_eq!(j["version"], VERSION);
        assert_eq!(j["input_root"], root('a'));
        assert_eq!(j["output_root"], root('b'));
        assert_eq!(check(&j), Ok(()));
        let mut stripped = j.clone();
        for key in ROOT_KEYS {
            stripped.as_object_mut().expect("object").remove(key);
        }
        stripped["version"] = json!(VERSION_UNROOTED);
        assert_eq!(canonical(&stripped), V1);
    }

    #[test]
    fn check_reads_versions_1_and_2_and_refuses_a_root_out_of_place() {
        let v1 = actor(None).to_json();
        let v2 = actor(Some(Roots {
            input: root('0'),
            output: root('f'),
        }))
        .to_json();
        let edited = |base: &Json, key: &str, value: Json| {
            let mut j = base.clone();
            j[key] = value;
            j
        };
        let refused = |j: &Json, why: &str| {
            let e = check(j).expect_err(why);
            assert!(e.contains(why), "{e}");
        };
        refused(
            &edited(&v1, "input_root", json!(root('a'))),
            "carries `input_root`",
        );
        refused(&edited(&v1, "version", json!(3)), "reads versions 1 to 2");
        refused(
            &edited(&v2, "output_root", json!("b3:00")),
            "not b3: and 64 hex",
        );
        refused(
            &edited(&v2, "input_root", json!(root('A'))),
            "not b3: and 64 hex",
        );
        let mut half = v2.clone();
        half.as_object_mut().expect("object").remove("output_root");
        refused(&half, "without `output_root`");
        let mut unversioned = v1.clone();
        unversioned
            .as_object_mut()
            .expect("object")
            .remove("version");
        refused(&unversioned, "reads versions 1 to 2");
    }
}
