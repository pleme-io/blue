//! The node: blue processes reachable from blue (BLUE-GAPS G11).
//!
//! Until this module, everything in this crate was reachable only from Rust:
//! a blue program could not spawn, send or receive, and a NATS subscriber had
//! to poll from the main program. A [`Node`] is the process runtime one
//! interpreter's program runs against, and [`install`] binds its words:
//!
//! ```text
//! spawn(f[, args])            spawn_link(f[, args])      spawn_server(handler, state)
//! send(pid, msg)              receive([pattern][, timeout_ms][, on_timeout])
//! self()   alive?(pid)        link(pid)  unlink(pid)     monitor(pid)  demonitor(ref)
//! exit(pid, reason)           trap_exit(flag)
//! supervisor(strategy, children[, max_restarts])         children(sup)
//! defmigrate(target, new_fn[, transform])
//! def_hash(f)
//! ```
//!
//! ## The shapes, adopted rather than invented
//!
//! - **Copy on send, share nothing** (`theory/BLUE.md` §V.8, BLUE-EXCLUSIVITY
//!   §II.3): a message is deep-copied, and a spawned function is turned back
//!   into code and recompiled in the child ([`crate::code`]), never shared.
//! - **Erlang's process vocabulary**: links propagate abnormal exits unless the
//!   receiver traps them (then they arrive as `[:exit, pid, reason]`), monitors
//!   deliver `[:down, ref, pid, reason]`, `:kill` cannot be trapped, a send to a
//!   dead process is dropped.
//! - **The supervisor strategies are [`Strategy`]'s**, with intensity checked on
//!   the child that exited and the mailbox emptied on restart, exactly as the
//!   Rust-level [`crate::Supervisor`] does.
//! - **The interleaving is replayable** (BLUE-EXCLUSIVITY §II.13): one thread,
//!   procs walked in spawn order, a fixed reduction quantum. What a process
//!   could not replay from its program alone — the messages it received, the
//!   host values it read, the pids it was handed — is recorded on its tape, and
//!   a crash writes the tape out ([`crate::trace`]).
//!
//! ## The root is the program; children are VM processes
//!
//! The program a door evaluates is process [`ROOT`] (pid 0). It runs on
//! whichever executor the door chose and is never preempted: it gives the
//! other processes the CPU by waiting — `receive`, `defmigrate` — and its
//! `receive` drives the scheduler until it has a message, its timeout passes,
//! or nothing can ever send (a deadlock, reported rather than hung on). The
//! program ends when the root does, as an escript does; a process the root
//! never waited for does not run to completion.
//!
//! Every other process runs on the bytecode VM, which is the executor that can
//! preempt (a quantum) and park (`receive` on an empty mailbox costs nothing).
//!
//! ## What a host must provide
//!
//! [`NodeConfig::child`] builds a fresh interpreter for a child. The node adds
//! its own words to it, and rebinds every host name (`blue_lang_waku`'s host
//! capabilities) to a recorder, so a child's reads of the clock, the network
//! or the filesystem land on its tape.

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::path::PathBuf;
use std::sync::{Arc, LazyLock, Mutex, MutexGuard, OnceLock, Weak};
use std::time::{Duration, Instant};

use tatara_lisp::{Span, Spanned};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::vm::{compile_program, Budget, Chunk, Vm, DEFAULT_MAX_DEPTH};
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::code::{self, Code, Entry};
use crate::mailbox::copy_data;
use crate::pattern;
use crate::receipt::{
    Frame, HostIo, Identities, Places, Receipt, ReceiptSink, Roots, StateRoot, Subject,
};
use crate::trace::{Journal, SliceRecord, TapeEntry, Trace};
use crate::violation::{defined_key, Violation};
use crate::{ExitReason, Pid, Proc, ProcState, Slice, Strategy};

/// The program itself.
pub const ROOT: Pid = Pid(0);

/// Reductions per slice. BEAM uses 4 000; a blue reduction is one VM
/// instruction, smaller than a BEAM reduction (a function call).
pub const DEFAULT_QUANTUM: usize = 1_000;

/// Tape entries one incarnation may record before its trace is marked
/// truncated. A replay needs the whole tape, so a truncated trace says so
/// rather than replaying a suffix.
pub const DEFAULT_MAX_TAPE: usize = 100_000;

/// Messages a held process's mailbox journal keeps of each kind (taken,
/// still waiting), when the host does not say.
pub const DEFAULT_JOURNAL: usize = 8;

/// Slices the interleaving record keeps.
const SCHEDULE_RING: usize = 1_024;

/// Crash traces a node keeps in memory.
const KEPT_TRACES: usize = 16;

/// Instructions a migration's definitions and transform may run.
const MIGRATION_FUEL: usize = 10_000_000;

/// Supervisor restarts of one child before it gives up, when the program does
/// not say.
pub const DEFAULT_MAX_RESTARTS: usize = 3;

/// Every word [`install`] binds that a blue program can spell.
pub const PROCESS_WORDS: &[&str] = &[
    "spawn",
    "spawn_link",
    "spawn_server",
    "send",
    "receive",
    "self",
    "alive?",
    "link",
    "unlink",
    "monitor",
    "demonitor",
    "exit",
    "trap_exit",
    "supervisor",
    "children",
    "defmigrate",
    "def_hash",
];

/// The word a server's loop waits in. Not spellable, so not in
/// [`PROCESS_WORDS`].
pub const SERVER_NEXT: &str = "%server_next";

/// A server's loop: take the next message at a boundary, hand it and the state
/// to the handler, keep what it returns.
///
/// The state lives in a process-private global rather than in a VM frame, so a
/// migration can read and replace it while the process is parked between
/// messages.
static SERVER_LOOP: LazyLock<Vec<Spanned>> = LazyLock::new(|| {
    tatara_lisp::read_spanned(
        "(define (%serve) (%serve_step (%server_next %state)))
         (define (%serve_step m) (set! %state (%handler m %state)) (%serve))",
    )
    .expect("the server loop reads")
});

static TRACE_DIR: OnceLock<Option<PathBuf>> = OnceLock::new();

/// Where nodes write crash traces. Only the first call counts, like
/// `blue_lang_runtime::set_execution_bounds`; a node built before any call
/// keeps its traces in memory only.
pub fn set_trace_dir(dir: Option<PathBuf>) {
    let _ = TRACE_DIR.set(dir);
}

static JOURNAL: OnceLock<usize> = OnceLock::new();

/// How many messages of each kind a held process's mailbox journal keeps;
/// `0` keeps none. Only the first call counts, like [`set_trace_dir`]; a
/// node built before any call keeps [`DEFAULT_JOURNAL`].
pub fn set_journal_bound(bound: usize) {
    let _ = JOURNAL.set(bound);
}

/// How a node reads time.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ClockKind {
    /// Milliseconds since the node started; an idle node sleeps until the
    /// next deadline.
    Real,
    /// Time moves only when every process is waiting: the node jumps to the
    /// next deadline. Deterministic, and the only clock a host with no clock
    /// (wasm) can offer.
    Virtual,
}

impl ClockKind {
    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            ClockKind::Real => "real",
            ClockKind::Virtual => "virtual",
        }
    }
}

struct Clock {
    kind: ClockKind,
    origin: Option<Instant>,
    virtual_ms: u64,
}

impl Clock {
    fn new(kind: ClockKind) -> Self {
        Self {
            kind,
            origin: None,
            virtual_ms: 0,
        }
    }

    fn now(&mut self) -> u64 {
        match self.kind {
            ClockKind::Real => u64::try_from(
                self.origin
                    .get_or_insert_with(Instant::now)
                    .elapsed()
                    .as_millis(),
            )
            .unwrap_or(u64::MAX),
            ClockKind::Virtual => self.virtual_ms,
        }
    }

    /// Move to `t`; the real clock answers how long to sleep.
    fn advance_to(&mut self, t: u64) -> Option<Duration> {
        match self.kind {
            ClockKind::Real => {
                let now = self.now();
                (t > now).then(|| Duration::from_millis(t - now))
            }
            ClockKind::Virtual => {
                self.virtual_ms = self.virtual_ms.max(t);
                None
            }
        }
    }
}

/// A fresh interpreter for a child, before the node adds its words.
pub type ChildFactory = Arc<dyn Fn() -> Interpreter<()> + Send + Sync>;

/// The host's allocator meter, through which a node holds each process to the
/// live-byte bound of the evaluation that spawned it (`max_alloc_bytes`).
///
/// A process is charged what its own slices leave live and the messages
/// delivered to it, never what its sender or its spawner holds: a message's
/// copy belongs to the receiver, and a process's interpreter and code belong
/// to the node. Past its bound a process exits
/// [`ExitReason::memory_exhausted`] at the end of the slice that passed it.
#[derive(Clone, Copy, Debug)]
pub struct Meter {
    /// The bound of the account running now: `None` when it has none, or the
    /// host counts nothing.
    pub bound: fn() -> Option<u64>,
    /// Run the closure charged to the account whose live bytes the `i64`
    /// carries, held to the bound; answers whether it passed the bound.
    pub charged: fn(&mut i64, Option<u64>, &mut dyn FnMut()) -> bool,
    /// Charge bytes to the account running now.
    pub charge: fn(i64),
}

/// What a node runs its processes under.
#[derive(Clone)]
pub struct NodeConfig {
    /// Each child's budget: fuel and depth bound an incarnation, the quantum is
    /// the slice.
    pub budget: Budget,
    pub clock: ClockKind,
    pub max_tape: usize,
    /// Where crash traces are written, if anywhere.
    pub trace_dir: Option<PathBuf>,
    pub child: ChildFactory,
    /// The hold every process runs under, when the host holds them to one.
    pub frame: Option<Frame>,
    /// Messages of each kind a held process's mailbox journal keeps; `0`
    /// keeps no journal.
    pub journal: usize,
    /// The ledger the host's counting shims tally into.
    pub host_io: HostIo,
    /// Each definition's `def_hash`, for traces and receipts.
    pub identities: Identities,
    /// Each definition's file, for the place a trace names.
    pub places: Places,
    /// Where each held process's receipt goes when an incarnation ends.
    pub receipts: Option<ReceiptSink>,
    /// How a server's receipt names its state; without one, a server's
    /// receipt carries no roots.
    pub state_root: Option<StateRoot>,
    /// The allocator meter that holds each process to its live-byte bound;
    /// `None` holds no process to one.
    pub meter: Option<Meter>,
}

impl NodeConfig {
    /// Unbounded fuel, the default depth, [`DEFAULT_QUANTUM`], a virtual
    /// clock, the trace directory [`set_trace_dir`] named, the journal bound
    /// [`set_journal_bound`] named, no hold, no receipts and no meter.
    #[must_use]
    pub fn new(child: ChildFactory) -> Self {
        Self {
            budget: Budget {
                fuel: None,
                max_depth: Some(DEFAULT_MAX_DEPTH),
                quantum: Some(DEFAULT_QUANTUM),
            },
            clock: ClockKind::Virtual,
            max_tape: DEFAULT_MAX_TAPE,
            trace_dir: TRACE_DIR.get().cloned().flatten(),
            child,
            frame: None,
            journal: JOURNAL.get().copied().unwrap_or(DEFAULT_JOURNAL),
            host_io: HostIo::default(),
            identities: Identities::default(),
            places: Places::default(),
            receipts: None,
            state_root: None,
            meter: None,
        }
    }

    fn journals(&self) -> bool {
        self.frame.is_some() && self.journal > 0
    }
}

#[derive(Clone, Debug)]
struct Sup {
    strategy: Strategy,
    max_restarts: usize,
    children: Vec<Pid>,
}

#[derive(Clone, Debug)]
enum Kind {
    Root,
    Plain,
    Server,
    Supervisor(Sup),
}

/// What the node knows about one live process.
struct Info {
    kind: Kind,
    /// The program a restart recompiles and a trace writes down.
    code: Code,
    chunk: Option<Arc<Chunk>>,
    /// The definition the process runs, for `defmigrate`.
    def_name: Option<String>,
    links: BTreeSet<Pid>,
    /// `(ref, watcher)` for every monitor on this process.
    monitors: Vec<(i64, Pid)>,
    trap_exit: bool,
    sup: Option<Pid>,
    restarts: usize,
    /// Running or parked. A supervised child keeps its record after it
    /// finishes, so its supervisor can restart it, and is not live then.
    live: bool,
    /// A server's state at its last boundary: where its tape starts.
    snapshot: Option<Value>,
    /// The state a server restarts with.
    initial: Option<Value>,
    /// The state this incarnation of a server began with.
    entered: Option<Value>,
    /// Live bytes this incarnation holds ([`Meter`]).
    held: i64,
    /// The live bytes it may hold: its spawner's bound, kept across restarts.
    bound: Option<u64>,
}

impl Info {
    fn new(kind: Kind) -> Self {
        Self {
            kind,
            code: Code::default(),
            chunk: None,
            def_name: None,
            links: BTreeSet::new(),
            monitors: Vec::new(),
            trap_exit: false,
            sup: None,
            restarts: 0,
            live: true,
            snapshot: None,
            initial: None,
            entered: None,
            held: 0,
            bound: None,
        }
    }
}

/// What a parked child is waiting for.
#[derive(Clone, Debug)]
enum Wait {
    Receive {
        pattern: Value,
        deadline: Option<u64>,
    },
    /// A server between messages: its migration boundary.
    ServerNext,
}

#[derive(Clone)]
struct Migration {
    request: u64,
    code: Code,
    new_name: String,
    transform: Option<Code>,
}

#[derive(Default, Clone)]
struct Tape {
    entries: Vec<TapeEntry>,
    truncated: bool,
}

struct NodeState {
    current: Pid,
    next_pid: u64,
    next_ref: i64,
    next_request: u64,
    boxes: BTreeMap<Pid, VecDeque<Value>>,
    info: BTreeMap<Pid, Info>,
    /// Spawned, not yet in the run queue: a spawn inside a slice cannot touch
    /// the queue the scheduler is walking.
    pending: Vec<Proc<()>>,
    waits: BTreeMap<Pid, Wait>,
    tapes: BTreeMap<Pid, Tape>,
    /// The last messages each held process took, oldest first.
    journals: BTreeMap<Pid, VecDeque<Value>>,
    /// Exit signals sent inside a slice, delivered between slices.
    signals: VecDeque<(Pid, Pid, Value)>,
    migrations: BTreeMap<Pid, Migration>,
    outcomes: BTreeMap<u64, Vec<(Pid, Result<(), String>)>>,
    schedule: VecDeque<SliceRecord>,
    traces: VecDeque<Trace>,
    clock: Clock,
    /// An abnormal exit signal the root did not trap: raised by its next wait.
    root_signal: Option<(Pid, Value)>,
    /// Bytes of the messages children delivered to the root while it waited,
    /// charged to it when its wait returns.
    root_due: i64,
}

impl NodeState {
    fn new(clock: ClockKind) -> Self {
        let mut info = BTreeMap::new();
        info.insert(ROOT, Info::new(Kind::Root));
        let mut boxes = BTreeMap::new();
        boxes.insert(ROOT, VecDeque::new());
        Self {
            current: ROOT,
            next_pid: 1,
            next_ref: 1,
            next_request: 1,
            boxes,
            info,
            pending: Vec::new(),
            waits: BTreeMap::new(),
            tapes: BTreeMap::new(),
            journals: BTreeMap::new(),
            signals: VecDeque::new(),
            migrations: BTreeMap::new(),
            outcomes: BTreeMap::new(),
            schedule: VecDeque::new(),
            traces: VecDeque::new(),
            clock: Clock::new(clock),
            root_signal: None,
            root_due: 0,
        }
    }

    fn deliver(&mut self, to: Pid, msg: Value) {
        if let Some(q) = self.boxes.get_mut(&to) {
            q.push_back(msg);
        }
    }

    /// Would `pid`'s parked call succeed now? Asked by the scheduler, so it
    /// reads; the call itself is what takes.
    fn is_ready(&mut self, pid: Pid) -> bool {
        let now = self.clock.now();
        let mailbox = self.boxes.get(&pid);
        match self.waits.get(&pid) {
            Some(Wait::Receive { pattern, deadline }) => {
                mailbox.is_some_and(|b| pattern::first_match(b, pattern).is_some())
                    || deadline.is_some_and(|d| now >= d)
            }
            Some(Wait::ServerNext) => {
                mailbox.is_some_and(|b| !b.is_empty()) && !self.migrations.contains_key(&pid)
            }
            None => mailbox.is_some_and(|b| !b.is_empty()),
        }
    }

    fn earliest_deadline(&self) -> Option<u64> {
        self.waits
            .values()
            .filter_map(|w| match w {
                Wait::Receive { deadline, .. } => *deadline,
                Wait::ServerNext => None,
            })
            .min()
    }

    fn forget(&mut self, pid: Pid) {
        self.info.remove(&pid);
        self.boxes.remove(&pid);
        self.waits.remove(&pid);
        self.tapes.remove(&pid);
        self.journals.remove(&pid);
    }

    /// `pid` took `msg`: keep it among its last `bound`.
    fn note_taken(&mut self, pid: Pid, msg: &Value, bound: usize) {
        let ring = self.journals.entry(pid).or_default();
        if ring.len() == bound {
            ring.pop_front();
        }
        ring.push_back(msg.clone());
    }
}

/// The process runtime one program runs against.
pub struct Node {
    config: NodeConfig,
    me: Weak<Node>,
    state: Mutex<NodeState>,
    /// The run queue, in spawn order. Locked only by the root while it waits,
    /// never from inside a slice, so a child's words touch only `state`.
    sched: Mutex<Vec<Proc<()>>>,
    /// The interpreter every child forks: the host's, plus this node's child
    /// words and host recorders. Built at the first spawn.
    proto: OnceLock<Arc<Interpreter<()>>>,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn kw(s: &str) -> Value {
    Value::Keyword(Arc::from(s))
}

fn int(n: impl TryInto<i64>) -> Value {
    Value::Int(n.try_into().unwrap_or(i64::MAX))
}

/// The blue value of an exit reason.
#[must_use]
pub fn reason_value(r: &ExitReason) -> Value {
    match r {
        ExitReason::Normal => kw("normal"),
        ExitReason::Crashed(m) => Value::list([kw("crashed"), Value::Str(Arc::from(m.as_str()))]),
        ExitReason::Runaway(m) => Value::list([kw("runaway"), Value::Str(Arc::from(m.as_str()))]),
        ExitReason::Killed(m) => Value::list([kw("killed"), Value::Str(Arc::from(m.as_str()))]),
        ExitReason::Fatal(m) => Value::list([kw("fatal"), Value::Str(Arc::from(m.as_str()))]),
    }
}

fn is_keyword(v: &Value, name: &str) -> bool {
    matches!(v, Value::Keyword(k) if k.trim_start_matches(':') == name)
}

fn render(v: &Value) -> String {
    v.to_string()
}

/// Whether a crash's trace is written out, not only kept in memory: a
/// supervised crash is the one a running system recovers from, so nobody
/// sees it happen, and a fatal one is never restarted, so its trace is all
/// that is left of it.
fn written(supervised: bool, reason: &ExitReason) -> bool {
    supervised || reason.is_fatal()
}

fn refuse(word: &str, msg: impl Into<String>, span: Span) -> EvalError {
    EvalError::native_fn(Arc::<str>::from(word), msg.into(), span)
}

fn pid_arg(v: &Value, word: &str, span: Span) -> Result<Pid, EvalError> {
    match v {
        Value::Int(n) if *n >= 0 => Ok(Pid(n.unsigned_abs())),
        other => Err(refuse(
            word,
            format!("expected a pid, got {}", other.type_name()),
            span,
        )),
    }
}

fn compile(forms: &[Spanned]) -> Result<Chunk, String> {
    compile_program(forms).map_err(|e| e.to_string())
}

/// Run `forms` to completion against `interp`, bounded.
fn run_in(
    interp: &mut Interpreter<()>,
    forms: &[Spanned],
    depth: Option<usize>,
) -> Result<Value, String> {
    let chunk = compile(forms)?;
    let mut vm = Vm::with_budget(Budget {
        fuel: Some(MIGRATION_FUEL),
        max_depth: depth,
        quantum: None,
    });
    vm.run(&chunk, interp, &mut ()).map_err(|e| e.to_string())
}

fn bind_all(interp: &mut Interpreter<()>, bindings: &[(Arc<str>, Value)]) {
    for (n, v) in bindings {
        interp.define_global(n.clone(), v.clone());
    }
}

/// `receive`'s arguments: a pattern (default `:_`), a timeout in ms (default
/// forever, `nil` too), and the value to answer on timeout (default nil).
fn receive_args(args: &[Value], span: Span) -> Result<(Value, Option<u64>, Value), EvalError> {
    let pattern = args
        .first()
        .cloned()
        .unwrap_or_else(|| kw(pattern::WILDCARD));
    let timeout = match args.get(1) {
        None | Some(Value::Nil) => None,
        Some(Value::Int(n)) if *n >= 0 => Some(n.unsigned_abs()),
        Some(other) => {
            return Err(refuse(
                "receive",
                format!(
                    "the timeout is milliseconds (an Int >= 0) or nil, got {}",
                    other.type_name()
                ),
                span,
            ))
        }
    };
    let default = args.get(2).cloned().unwrap_or(Value::Nil);
    Ok((pattern, timeout, default))
}

/// Which side of the node a word was installed for.
#[derive(Clone)]
enum Side {
    /// The program. Holds the node, so the node lives exactly as long as the
    /// interpreter that runs the program.
    Root(Arc<Node>),
    /// A child. Weak, because the node holds the child's interpreter and a
    /// strong reference back would be a cycle that frees nothing.
    Child(Weak<Node>),
}

impl Side {
    fn node(&self, word: &str, span: Span) -> Result<Arc<Node>, EvalError> {
        match self {
            Side::Root(n) => Ok(n.clone()),
            Side::Child(w) => w
                .upgrade()
                .ok_or_else(|| refuse(word, "the process's node has shut down", span)),
        }
    }
}

/// Who called a word.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Who {
    Root,
    Child(Pid),
}

impl Who {
    fn pid(self) -> Pid {
        match self {
            Who::Root => ROOT,
            Who::Child(p) => p,
        }
    }
}

type Word = fn(&Node, Who, &[Value], Span) -> Result<Value, EvalError>;

/// The words, with the arity each is registered under.
const WORDS: &[(&str, Arity, Word)] = &[
    ("spawn", Arity::Range(1, 2), w_spawn),
    ("spawn_link", Arity::Range(1, 2), w_spawn_link),
    ("spawn_server", Arity::Exact(2), w_spawn_server),
    ("send", Arity::Exact(2), w_send),
    ("self", Arity::Exact(0), w_self),
    ("alive?", Arity::Exact(1), w_alive),
    ("link", Arity::Exact(1), w_link),
    ("unlink", Arity::Exact(1), w_unlink),
    ("monitor", Arity::Exact(1), w_monitor),
    ("demonitor", Arity::Exact(1), w_demonitor),
    ("exit", Arity::Exact(2), w_exit),
    ("trap_exit", Arity::Exact(1), w_trap_exit),
    ("supervisor", Arity::Range(2, 3), w_supervisor),
    ("children", Arity::Exact(1), w_children),
    ("defmigrate", Arity::Range(2, 3), w_defmigrate),
    ("def_hash", Arity::Exact(1), w_def_hash),
];

/// Bind the process words into the interpreter that runs a program, against
/// `node`. The interpreter becomes the node's root.
pub fn install<H: 'static>(interp: &mut Interpreter<H>, node: Arc<Node>) {
    let side = Side::Root(node);
    for (name, arity, word) in WORDS {
        register(interp, &side, name, *arity, *word);
    }
    // The root never parks: its `receive` drives the other processes until
    // it has an answer, so it is an ordinary function on either executor.
    let s = side.clone();
    interp.register_fn(
        "receive",
        Arity::Range(0, 3),
        move |args: &[Value], _h: &mut H, span| {
            let node = s.node("receive", span)?;
            node.receive_root(args, span)
        },
    );
}

fn register<H: 'static>(
    interp: &mut Interpreter<H>,
    side: &Side,
    name: &'static str,
    arity: Arity,
    word: Word,
) {
    let side = side.clone();
    interp.register_fn(name, arity, move |args: &[Value], _h: &mut H, span| {
        let node = side.node(name, span)?;
        let who = match side {
            Side::Root(_) => Who::Root,
            Side::Child(_) => Who::Child(node.current()),
        };
        let out = word(&node, who, args, span);
        if let Who::Child(pid) = who {
            node.record(pid, name, &out);
        }
        out
    });
}

/// The child side of the words, on the prototype every child forks.
fn install_child(proto: &mut Interpreter<()>, me: &Weak<Node>) {
    let side = Side::Child(me.clone());
    for (name, arity, word) in WORDS {
        register(proto, &side, name, *arity, *word);
    }

    // `receive` in a child parks. The two phases are the guarantee
    // `mailbox.rs` describes: readiness MATCHES (`pattern::first_match` takes
    // the mailbox by shared reference) and only `call` takes. Readiness also
    // notes the wait — what it waits for and until when — so the scheduler can
    // wake it; that bookkeeping touches `waits`, never a mailbox.
    let (r, c) = (me.clone(), me.clone());
    proto.register_awaitable_fn(
        "receive",
        Arity::Range(0, 3),
        move |args: &[Value], _h: &()| {
            let Some(node) = r.upgrade() else { return true };
            let Ok((pattern, timeout, _)) = receive_args(args, Span::synthetic()) else {
                // Let the call raise the argument error.
                return true;
            };
            let mut st = node.st();
            let pid = st.current;
            if st
                .boxes
                .get(&pid)
                .is_some_and(|b| pattern::first_match(b, &pattern).is_some())
            {
                return true;
            }
            let now = st.clock.now();
            let deadline = match st.waits.get(&pid) {
                Some(Wait::Receive { deadline, .. }) => *deadline,
                _ => timeout.map(|t| now.saturating_add(t)),
            };
            st.waits.insert(pid, Wait::Receive { pattern, deadline });
            deadline.is_some_and(|d| now >= d)
        },
        move |args: &[Value], _h: &mut (), span| {
            let node = Side::Child(c.clone()).node("receive", span)?;
            let (pattern, _, default) = receive_args(args, span)?;
            let out = {
                let mut st = node.st();
                let pid = st.current;
                st.waits.remove(&pid);
                let taken = st.boxes.get_mut(&pid).and_then(|b| {
                    let i = pattern::first_match(b, &pattern)?;
                    b.remove(i)
                });
                node.journal(&mut st, pid, taken.as_ref());
                Ok(taken.unwrap_or(default))
            };
            node.record(node.current(), "receive", &out);
            out
        },
    );

    // A server's boundary. Not ready while a migration is pending for this
    // process, so a busy server still stops here for the swap; the message
    // that was waiting stays in the mailbox for the new code.
    let (r, c) = (me.clone(), me.clone());
    proto.register_awaitable_fn(
        SERVER_NEXT,
        Arity::Exact(1),
        move |_args: &[Value], _h: &()| {
            let Some(node) = r.upgrade() else { return true };
            let mut st = node.st();
            let pid = st.current;
            let ready = st.boxes.get(&pid).is_some_and(|b| !b.is_empty())
                && !st.migrations.contains_key(&pid);
            if !ready {
                st.waits.insert(pid, Wait::ServerNext);
            }
            ready
        },
        move |args: &[Value], _h: &mut (), span| {
            let node = Side::Child(c.clone()).node(SERVER_NEXT, span)?;
            let mut st = node.st();
            let pid = st.current;
            st.waits.remove(&pid);
            let taken = st.boxes.get_mut(&pid).and_then(VecDeque::pop_front);
            node.journal(&mut st, pid, taken.as_ref());
            let msg = taken.unwrap_or(Value::Nil);
            // A boundary: the tape restarts here, from this state, so a
            // long-lived server's trace is its last message, not its life.
            if let Some(info) = st.info.get_mut(&pid) {
                info.snapshot = Some(args.first().cloned().unwrap_or(Value::Nil));
            }
            st.tapes.insert(pid, Tape::default());
            drop(st);
            let out = Ok(msg);
            node.record(pid, SERVER_NEXT, &out);
            out
        },
    );
}

/// Rebind every host name the prototype binds to a recorder, so a child's
/// host reads land on its tape in order.
fn record_host_names(proto: &mut Interpreter<()>, me: &Weak<Node>) {
    for name in host_names() {
        let Some(original @ Value::NativeFn(_)) = proto.lookup_global(name) else {
            continue;
        };
        let Value::NativeFn(nf) = &original else {
            continue;
        };
        let arity = nf.arity;
        let wrapper = format!("%host:{name}");
        let me = me.clone();
        proto.register_higher_order_fn(
            wrapper.clone(),
            arity,
            move |args: &[Value], h: &mut (), caller: &tatara_lisp_eval::ffi::Caller<()>, span| {
                let out = caller.apply_value(&original, args.to_vec(), h, span);
                if let Some(node) = me.upgrade() {
                    let pid = node.current();
                    if pid != ROOT {
                        node.record(pid, name, &out);
                    }
                }
                out
            },
        );
        if let Some(w) = proto.lookup_global(&wrapper) {
            proto.define_global(name, w);
        }
    }
}

/// Every host name blue has, from the closed capability universe.
#[must_use]
pub fn host_names() -> Vec<&'static str> {
    blue_lang_waku::capability::Capability::host_effects()
        .into_iter()
        .flat_map(blue_lang_waku::capability::Capability::names)
        .collect()
}

/// How a root wait ended.
enum Driven<T> {
    Done(T),
    TimedOut,
    Deadlock(Vec<Pid>),
}

impl Node {
    /// A node with no processes.
    #[must_use]
    pub fn new(config: NodeConfig) -> Arc<Self> {
        let clock = config.clock;
        Arc::new_cyclic(|me| Self {
            config,
            me: me.clone(),
            state: Mutex::new(NodeState::new(clock)),
            sched: Mutex::new(Vec::new()),
            proto: OnceLock::new(),
        })
    }

    fn st(&self) -> MutexGuard<'_, NodeState> {
        lock(&self.state)
    }

    fn current(&self) -> Pid {
        self.st().current
    }

    fn proto(&self) -> Arc<Interpreter<()>> {
        self.proto
            .get_or_init(|| {
                let mut p = (self.config.child)();
                install_child(&mut p, &self.me);
                record_host_names(&mut p, &self.me);
                Arc::new(p)
            })
            .clone()
    }

    fn builder(
        &self,
        bindings: &[(Arc<str>, Value)],
    ) -> Arc<dyn Fn() -> Interpreter<()> + Send + Sync> {
        let proto = self.proto();
        let bindings = bindings.to_vec();
        Arc::new(move || {
            let mut i = proto.fork();
            bind_all(&mut i, &bindings);
            i
        })
    }

    fn record(&self, pid: Pid, call: &str, out: &Result<Value, EvalError>) {
        let max = self.config.max_tape;
        let mut st = self.st();
        let Some(tape) = st.tapes.get_mut(&pid) else {
            return;
        };
        if tape.truncated {
            return;
        }
        if tape.entries.len() >= max {
            // The whole tape or nothing: a replay of a suffix would run the
            // process from a state it never had.
            tape.truncated = true;
            tape.entries = Vec::new();
            return;
        }
        tape.entries.push(TapeEntry::of(call, out));
    }

    /// The process running now took `msg`, if `taken`.
    fn journal(&self, st: &mut NodeState, pid: Pid, taken: Option<&Value>) {
        if let (true, Some(msg)) = (self.config.journals(), taken) {
            st.note_taken(pid, msg, self.config.journal);
        }
    }

    /// `pid` runs now: the scheduler's current process and the host ledger's.
    fn switch(&self, st: &mut NodeState, pid: Pid) {
        st.current = pid;
        self.config.host_io.enter(pid);
    }

    /// `f` charged to the account `held` carries, held to `bound`, and
    /// whether it passed the bound; run uncharged with no meter.
    fn charged<T>(&self, held: &mut i64, bound: Option<u64>, f: impl FnOnce() -> T) -> (T, bool) {
        let Some(meter) = self.config.meter else {
            return (f(), false);
        };
        let mut f = Some(f);
        let mut out = None;
        let over = (meter.charged)(held, bound, &mut || out = f.take().map(|f| f()));
        match (out, f) {
            (Some(v), _) => (v, over),
            (None, Some(f)) => (f(), false),
            (None, None) => unreachable!("a closure that ran left its value"),
        }
    }

    /// `f` charged to no process, and the bytes it left live.
    fn apart<T>(&self, f: impl FnOnce() -> T) -> (T, i64) {
        let mut held = 0;
        let (value, _) = self.charged(&mut held, None, f);
        (value, held)
    }

    /// `bytes` now belong to `to`: a message copied into its mailbox.
    fn credit(&self, to: Pid, bytes: i64) {
        let Some(meter) = self.config.meter.filter(|_| bytes != 0) else {
            return;
        };
        let mut st = self.st();
        if to == st.current {
            drop(st);
            (meter.charge)(bytes);
        } else if to == ROOT {
            st.root_due += bytes;
        } else if let Some(info) = st.info.get_mut(&to) {
            info.held += bytes;
        }
    }

    /// Charge the root what its children delivered to it while it waited.
    fn settle_root(&self) {
        let due = std::mem::take(&mut self.st().root_due);
        if let (Some(meter), true) = (self.config.meter, due != 0) {
            (meter.charge)(due);
        }
    }

    /// Give `p` one slice charged to its own account; past its bound it exits
    /// [`ExitReason::memory_exhausted`], whatever the slice did.
    fn slice_held(&self, p: &mut Proc<()>) -> Slice {
        let pid = p.pid;
        let (mut held, bound) = self
            .st()
            .info
            .get(&pid)
            .map_or((0, None), |i| (i.held, i.bound));
        let Some(limit) = bound else {
            return p.slice(&mut ());
        };
        let (out, over) = self.charged(&mut held, bound, || p.slice(&mut ()));
        if let Some(info) = self.st().info.get_mut(&pid) {
            info.held = held;
        }
        if !over {
            return out;
        }
        let reason = ExitReason::memory_exhausted(limit);
        p.state = ProcState::Exited(reason.clone());
        Slice::Exited(reason)
    }

    /// Compile `code` and queue a process running it, held to the bound of
    /// the account that spawns it. Building it is charged to no one.
    fn start(
        &self,
        code: Code,
        kind: Kind,
        def_name: Option<String>,
        sup: Option<Pid>,
    ) -> Result<Pid, String> {
        let bound = self.config.meter.and_then(|m| (m.bound)());
        self.apart(|| self.start_unmetered(code, kind, def_name, sup, bound))
            .0
    }

    fn start_unmetered(
        &self,
        code: Code,
        kind: Kind,
        def_name: Option<String>,
        sup: Option<Pid>,
        bound: Option<u64>,
    ) -> Result<Pid, String> {
        let chunk = Arc::new(compile(&code.program())?);
        let build = self.builder(&code.bindings);
        let initial = match kind {
            Kind::Server => code
                .bindings
                .iter()
                .find(|(n, _)| &**n == "%state")
                .map(|(_, v)| v.clone()),
            _ => None,
        };
        let mut st = self.st();
        let pid = Pid(st.next_pid);
        st.next_pid += 1;
        let proc = Proc::new(pid, chunk.clone(), self.config.budget, build);
        let mut info = Info::new(kind);
        info.code = code;
        info.chunk = Some(chunk);
        info.def_name = def_name;
        info.sup = sup;
        info.snapshot.clone_from(&initial);
        info.entered.clone_from(&initial);
        info.initial = initial;
        info.bound = bound;
        st.info.insert(pid, info);
        st.boxes.insert(pid, VecDeque::new());
        st.tapes.insert(pid, Tape::default());
        st.pending.push(proc);
        Ok(pid)
    }

    // ── the scheduler ──────────────────────────────────────────────────────

    fn adopt(&self, sched: &mut Vec<Proc<()>>) {
        let pending = std::mem::take(&mut self.st().pending);
        sched.extend(pending);
    }

    fn has_work(&self, sched: &[Proc<()>]) -> bool {
        let mut st = self.st();
        sched
            .iter()
            .any(|p| p.is_runnable() || (p.state.is_blocked() && st.is_ready(p.pid)))
    }

    /// One pass over the run queue: wake what can proceed, give every runnable
    /// process one quantum, deliver the exits and signals that produced.
    fn round(&self, sched: &mut Vec<Proc<()>>) {
        {
            let mut st = self.st();
            for p in sched.iter_mut() {
                if p.state.is_blocked() && st.is_ready(p.pid) {
                    p.state = ProcState::Runnable;
                }
            }
        }
        for idx in 0..sched.len() {
            if !sched[idx].is_runnable() {
                continue;
            }
            let pid = sched[idx].pid;
            self.switch(&mut self.st(), pid);
            let before = sched[idx].vm.burned();
            let out = self.slice_held(&mut sched[idx]);
            let burned = sched[idx].vm.burned().saturating_sub(before);
            {
                let mut st = self.st();
                self.switch(&mut st, ROOT);
                let outcome = match &out {
                    Slice::Yielded => "yielded",
                    Slice::Blocked => "blocked",
                    Slice::Done(_) => "done",
                    Slice::Exited(_) => "exited",
                };
                if st.schedule.len() == SCHEDULE_RING {
                    st.schedule.pop_front();
                }
                st.schedule.push_back(SliceRecord {
                    pid: pid.0,
                    outcome: outcome.to_string(),
                    burned,
                });
            }
            match out {
                Slice::Done(v) => {
                    self.on_exit(sched, pid, &ExitReason::Normal, kw("normal"), Some(v))
                }
                Slice::Exited(r) => {
                    let rv = reason_value(&r);
                    self.on_exit(sched, pid, &r, rv, None);
                }
                Slice::Yielded | Slice::Blocked => {}
            }
            self.adopt(sched);
            self.process_signals(sched);
        }
        self.reap(sched);
    }

    /// Drop finished processes nothing can restart, so a long-running node's
    /// memory follows its live processes, not every process it ever ran.
    fn reap(&self, sched: &mut Vec<Proc<()>>) {
        let st = self.st();
        sched.retain(|p| {
            p.is_runnable()
                || p.state.is_blocked()
                || st.info.get(&p.pid).is_some_and(|i| i.sup.is_some())
        });
    }

    fn process_signals(&self, sched: &mut Vec<Proc<()>>) {
        loop {
            let next = self.st().signals.pop_front();
            let Some((from, to, reason)) = next else {
                break;
            };
            self.signal(sched, from, to, reason);
        }
    }

    /// Deliver an exit signal from `from` to `to`.
    fn signal(&self, sched: &mut Vec<Proc<()>>, from: Pid, to: Pid, reason: Value) {
        let normal = is_keyword(&reason, "normal");
        let kill = is_keyword(&reason, "kill");
        let mut st = self.st();
        let Some(info) = st.info.get(&to) else { return };
        let trapping = info.trap_exit && !kill;
        let is_sup = matches!(info.kind, Kind::Supervisor(_));
        if trapping {
            st.deliver(to, Value::list([kw("exit"), int(from.0), reason]));
            return;
        }
        if normal {
            return;
        }
        if to == ROOT {
            st.root_signal = Some((from, reason));
            return;
        }
        drop(st);
        let reason = if kill { kw("killed") } else { reason };
        if is_sup {
            self.shutdown_sup(sched, to, reason);
        } else {
            self.kill(sched, to, reason);
        }
    }

    fn kill(&self, sched: &mut Vec<Proc<()>>, pid: Pid, reason: Value) {
        let text = render(&reason);
        let killed = ExitReason::Killed(text);
        let alive = match sched.iter_mut().find(|p| p.pid == pid) {
            Some(p) if p.is_runnable() || p.state.is_blocked() => {
                p.state = ProcState::Exited(killed.clone());
                true
            }
            _ => false,
        };
        if alive {
            self.on_exit(sched, pid, &killed, reason, None);
        }
    }

    /// A process ended: write its trace, tell its monitors and links, and let
    /// its supervisor decide.
    fn on_exit(
        &self,
        sched: &mut Vec<Proc<()>>,
        pid: Pid,
        reason: &ExitReason,
        value: Value,
        _result: Option<Value>,
    ) {
        let mut st = self.st();
        if !st.info.contains_key(&pid) {
            return;
        }
        let trace = reason
            .is_abnormal()
            .then(|| self.trace_of(&mut st, pid, reason, &value));
        let receipt = self.receipt_of(&st, sched, pid, reason);
        let (links, monitors, sup) = {
            let info = st.info.get_mut(&pid).expect("checked above");
            (
                std::mem::take(&mut info.links),
                std::mem::take(&mut info.monitors),
                info.sup,
            )
        };
        for l in &links {
            if let Some(li) = st.info.get_mut(l) {
                li.links.remove(&pid);
            }
        }
        for (r, watcher) in monitors {
            st.deliver(
                watcher,
                Value::list([kw("down"), int(r), int(pid.0), value.clone()]),
            );
        }
        st.waits.remove(&pid);
        if let Some(m) = st.migrations.remove(&pid) {
            st.outcomes.entry(m.request).or_default().push((
                pid,
                Err("the process exited before it reached a boundary".into()),
            ));
        }
        let supervised =
            sup.filter(|s| matches!(st.info.get(s).map(|i| &i.kind), Some(Kind::Supervisor(_))));
        if reason.is_fatal() {
            if let Some(Kind::Supervisor(spec)) = supervised
                .and_then(|s| st.info.get_mut(&s))
                .map(|i| &mut i.kind)
            {
                spec.children.retain(|c| *c != pid);
            }
            st.forget(pid);
        } else if supervised.is_none() {
            st.forget(pid);
        } else if let Some(info) = st.info.get_mut(&pid) {
            info.live = false;
        }
        drop(st);

        if let (Some(r), Some(sink)) = (&receipt, &self.config.receipts) {
            sink(r);
        }
        if let Some(t) = trace {
            // Every crash is kept in memory; a supervised one is also written
            // out, because it is the crash a running system recovers from and
            // so the one nobody sees happen.
            self.keep_trace(t, written(supervised.is_some(), reason));
        }
        for l in links {
            self.signal(sched, pid, l, value.clone());
        }
        if let (Some(s), true) = (supervised, reason.is_restartable()) {
            self.supervise(sched, s, pid);
        }
    }

    fn supervise(&self, sched: &mut Vec<Proc<()>>, sup: Pid, child: Pid) {
        let (spec, restarts) = {
            let st = self.st();
            let Some(Kind::Supervisor(spec)) = st.info.get(&sup).map(|i| i.kind.clone()) else {
                return;
            };
            let restarts = st.info.get(&child).map_or(0, |i| i.restarts);
            (spec, restarts)
        };
        // Intensity is checked on the child that exited, as `Supervisor` does:
        // a sibling restarted as collateral has not misbehaved.
        if restarts >= spec.max_restarts {
            self.shutdown_sup(sched, sup, Value::list([kw("gave_up"), int(child.0)]));
            return;
        }
        let Some(pos) = spec.children.iter().position(|c| *c == child) else {
            return;
        };
        for t in spec.strategy.targets(pos, spec.children.len()) {
            self.restart(sched, spec.children[t]);
        }
    }

    /// A fresh incarnation under the same pid: new VM, new interpreter from
    /// the current code, an empty mailbox and an empty tape.
    fn restart(&self, sched: &mut [Proc<()>], pid: Pid) {
        let Some(p) = sched.iter_mut().find(|p| p.pid == pid) else {
            return;
        };
        let chunk = {
            let mut st = self.st();
            // The messages in flight were addressed to the incarnation that
            // died; replaying them is how a poison message kills a process
            // forever.
            if let Some(b) = st.boxes.get_mut(&pid) {
                b.clear();
            }
            st.waits.remove(&pid);
            st.tapes.insert(pid, Tape::default());
            st.journals.remove(&pid);
            self.config.host_io.take(pid);
            st.info.get_mut(&pid).and_then(|info| {
                info.restarts += 1;
                info.live = true;
                info.held = 0;
                info.snapshot.clone_from(&info.initial);
                info.entered.clone_from(&info.initial);
                info.chunk.clone()
            })
        };
        if let Some(c) = chunk {
            p.chunk = c;
        }
        p.restart();
    }

    /// Stop a supervisor: its children first (they are not restarted), then
    /// the supervisor itself, which its own links and monitors hear about.
    fn shutdown_sup(&self, sched: &mut Vec<Proc<()>>, sup: Pid, reason: Value) {
        let (children, links, monitors) = {
            let mut st = self.st();
            let Some(info) = st.info.remove(&sup) else {
                return;
            };
            st.boxes.remove(&sup);
            let children = match info.kind {
                Kind::Supervisor(s) => s.children,
                _ => Vec::new(),
            };
            for c in &children {
                if let Some(ci) = st.info.get_mut(c) {
                    ci.sup = None;
                }
            }
            for l in &info.links {
                if let Some(li) = st.info.get_mut(l) {
                    li.links.remove(&sup);
                }
            }
            (children, info.links, info.monitors)
        };
        for c in children {
            self.kill(sched, c, kw("shutdown"));
            // A child that had already finished is not in the run queue to
            // kill; it is simply forgotten.
            let mut st = self.st();
            if st.info.get(&c).is_some_and(|i| i.sup.is_none())
                && !sched
                    .iter()
                    .any(|p| p.pid == c && (p.is_runnable() || p.state.is_blocked()))
            {
                st.forget(c);
            }
        }
        {
            let mut st = self.st();
            for (r, watcher) in monitors {
                st.deliver(
                    watcher,
                    Value::list([kw("down"), int(r), int(sup.0), reason.clone()]),
                );
            }
        }
        for l in links {
            self.signal(sched, sup, l, reason.clone());
        }
    }

    // ── migrations ─────────────────────────────────────────────────────────

    /// Apply every pending migration whose process is at a boundary.
    ///
    /// Answers whether any was applied, so a waiting root checks again.
    fn apply_migrations(&self, sched: &mut [Proc<()>]) -> bool {
        let pending: Vec<Pid> = self.st().migrations.keys().copied().collect();
        let mut applied = false;
        for pid in pending {
            let Some(idx) = sched.iter().position(|p| p.pid == pid) else {
                continue;
            };
            let (ready, m, kind) = {
                let st = self.st();
                let Some(info) = st.info.get(&pid) else {
                    continue;
                };
                let p = &sched[idx];
                let ready = match info.kind {
                    Kind::Server => {
                        p.state.is_blocked() && matches!(st.waits.get(&pid), Some(Wait::ServerNext))
                    }
                    Kind::Plain => p.is_runnable() || p.state.is_blocked(),
                    _ => false,
                };
                (ready, st.migrations.get(&pid).cloned(), info.kind.clone())
            };
            let (true, Some(m)) = (ready, m) else {
                continue;
            };
            self.switch(&mut self.st(), pid);
            let result = self.migrate(&mut sched[idx], &kind, &m);
            let mut st = self.st();
            self.switch(&mut st, ROOT);
            st.migrations.remove(&pid);
            st.outcomes
                .entry(m.request)
                .or_default()
                .push((pid, result));
            applied = true;
        }
        applied
    }

    /// Swap `p`'s code, and for a server its state. Everything is tried on a
    /// fork of the process's interpreter first; only a migration that
    /// succeeded there is committed, so one that raises leaves the old code
    /// running and its state untouched.
    fn migrate(&self, p: &mut Proc<()>, kind: &Kind, m: &Migration) -> Result<(), String> {
        let depth = self.config.budget.max_depth;
        let (old_name, initial) = {
            let st = self.st();
            let info = st.info.get(&p.pid).ok_or("the process is gone")?;
            (info.def_name.clone(), info.initial.clone())
        };
        let server = matches!(kind, Kind::Server);
        if !server && m.transform.is_some() {
            return Err(
                "a plain process keeps its state in its own frames, so there is no state to \
                        transform; run it with spawn_server to migrate state"
                    .into(),
            );
        }

        let mut scratch = p.interp.fork();
        bind_all(&mut scratch, &m.code.bindings);
        run_in(&mut scratch, &m.code.defs, depth)?;
        let (state, initial) = if server {
            let old = p.interp.lookup_global("%state").unwrap_or(Value::Nil);
            match &m.transform {
                Some(t) => {
                    bind_all(&mut scratch, &t.bindings);
                    run_in(&mut scratch, &t.defs, depth)?;
                    let apply = |scratch: &mut Interpreter<()>, v: Value| {
                        scratch.define_global("%old", v);
                        run_in(
                            scratch,
                            &[code::call(code::symbol("%transform"), &["%old"])],
                            depth,
                        )
                    };
                    let state = apply(&mut scratch, old)?;
                    let initial = match initial {
                        Some(i) => Some(apply(&mut scratch, i)?),
                        None => None,
                    };
                    (Some(state), initial)
                }
                None => (Some(old), initial),
            }
        } else {
            (None, None)
        };
        drop(scratch);

        // Commit. The definitions already ran once, so they run again here.
        bind_all(&mut p.interp, &m.code.bindings);
        run_in(&mut p.interp, &m.code.defs, depth)?;
        let new_fn = p
            .interp
            .lookup_global(&m.new_name)
            .ok_or_else(|| format!("the migration did not define `{}`", m.new_name))?;
        let alias = if server {
            "%handler".to_string()
        } else {
            old_name.clone().unwrap_or_default()
        };
        if !alias.is_empty() && alias != m.new_name {
            p.interp.define_global(alias.as_str(), new_fn);
        }
        if let Some(s) = &state {
            p.interp.define_global("%state", s.clone());
        }

        // A later restart, trace or migration starts from the new program.
        let mut st = self.st();
        let info = st.info.get_mut(&p.pid).ok_or("the process is gone")?;
        let mut defs = info.code.defs.clone();
        defs.extend(m.code.defs.iter().cloned());
        if !alias.is_empty() && alias != m.new_name {
            defs.push(code::define_value(&alias, code::symbol(&m.new_name)));
        }
        if server {
            // The loop stays last so it is defined after everything it calls.
            defs.retain(|d| !SERVER_LOOP.contains(d));
            defs.extend(SERVER_LOOP.iter().cloned());
        }
        let mut new_code = Code {
            defs,
            bindings: info.code.bindings.clone(),
            start: info.code.start.clone(),
        };
        for (n, v) in &m.code.bindings {
            new_code.bind(n, v.clone());
        }
        if let Some(i) = &initial {
            new_code.bind("%state", i.clone());
        }
        let chunk = Arc::new(compile(&new_code.program())?);
        info.code = new_code;
        info.chunk = Some(chunk);
        info.def_name = Some(m.new_name.clone());
        info.initial = initial;
        if state.is_some() {
            info.snapshot = state;
        }
        let bindings = info.code.bindings.clone();
        st.tapes.insert(p.pid, Tape::default());
        drop(st);
        p.build = self.builder(&bindings);
        Ok(())
    }

    // ── traces ─────────────────────────────────────────────────────────────

    fn trace_of(&self, st: &mut NodeState, pid: Pid, reason: &ExitReason, value: &Value) -> Trace {
        let info = st.info.get(&pid).expect("a live process");
        let mut code = info.code.clone();
        if let (Kind::Server, Some(s)) = (&info.kind, &info.snapshot) {
            code.bind("%state", s.clone());
        }
        let tape = st.tapes.get(&pid).cloned().unwrap_or_default();
        let bound = self.config.journal;
        let mailbox = self.config.journals().then(|| {
            let waiting = st.boxes.get(&pid);
            Journal {
                bound,
                recent: st
                    .journals
                    .get(&pid)
                    .map(|r| r.iter().cloned().collect())
                    .unwrap_or_default(),
                unconsumed: waiting
                    .map(|b| b.iter().take(bound).cloned().collect())
                    .unwrap_or_default(),
                unconsumed_total: waiting.map_or(0, VecDeque::len),
            }
        });
        let reason_kind = crate::trace::reason_kind(reason).to_string();
        let places = &self.config.places;
        let violation = Violation::of(&reason_kind, &tape.entries, &code.defs, places);
        let defined_at = info.def_name.as_deref().and_then(|d| {
            let form = code.defs.iter().find(|f| defined_key(f) == Some(d))?;
            places.locate(d, form.span)
        });
        Trace {
            pid: pid.0,
            incarnation: info.restarts,
            definition: info.def_name.clone(),
            def_hash: info
                .def_name
                .as_deref()
                .and_then(|d| self.config.identities.of(d)),
            hold: self.config.frame.clone(),
            host_io: self
                .config
                .frame
                .as_ref()
                .map(|_| self.config.host_io.of(pid)),
            mailbox,
            violation,
            defined_at,
            reason: value.clone(),
            reason_text: crate::trace::reason_text(reason),
            reason_kind,
            budget: self.config.budget,
            code,
            tape: tape.entries,
            truncated: tape.truncated,
            schedule: st.schedule.iter().cloned().collect(),
            clock: self.config.clock,
        }
    }

    /// The receipt of `pid`'s incarnation, which is ending: only a held
    /// node's processes have one, since only a hold's shims count host calls.
    fn receipt_of(
        &self,
        st: &NodeState,
        sched: &[Proc<()>],
        pid: Pid,
        reason: &ExitReason,
    ) -> Option<Receipt> {
        let host_io = self.config.host_io.take(pid);
        let frame = self.config.frame.clone()?;
        self.config.receipts.as_ref()?;
        let info = st.info.get(&pid)?;
        let roots = match (&info.kind, self.config.state_root, &info.entered) {
            (Kind::Server, Some(root), Some(entered)) => {
                let left = sched
                    .iter()
                    .find(|p| p.pid == pid)
                    .and_then(|p| p.interp.lookup_global("%state"))
                    .or_else(|| info.snapshot.clone())
                    .unwrap_or(Value::Nil);
                Some(Roots {
                    input: root(entered),
                    output: root(&left),
                })
            }
            _ => None,
        };
        Some(Receipt {
            subject: Subject::Actor {
                pid,
                incarnation: info.restarts,
            },
            definition: info.def_name.clone(),
            def_hash: info
                .def_name
                .as_deref()
                .and_then(|d| self.config.identities.of(d)),
            frame,
            host_io,
            exit_kind: crate::trace::reason_kind(reason).to_string(),
            exit_text: crate::trace::reason_text(reason),
            roots,
        })
    }

    fn keep_trace(&self, trace: Trace, write: bool) {
        if let Some(dir) = self.config.trace_dir.as_ref().filter(|_| write) {
            match trace.write_to(dir) {
                Ok(path) => eprintln!(
                    "blue: process {} exited ({}); trace: {}",
                    trace.pid,
                    trace.reason_text,
                    path.display()
                ),
                Err(e) => eprintln!(
                    "blue: process {} exited; its trace could not be written: {e}",
                    trace.pid
                ),
            }
        }
        let mut st = self.st();
        if st.traces.len() == KEPT_TRACES {
            st.traces.pop_front();
        }
        st.traces.push_back(trace);
    }

    /// The crash traces this node kept, oldest first.
    #[must_use]
    pub fn traces(&self) -> Vec<Trace> {
        self.st().traces.iter().cloned().collect()
    }

    // ── driving, for the root ──────────────────────────────────────────────

    /// Run the other processes until `goal` answers, `deadline` passes, or
    /// nothing can change.
    ///
    /// The scheduling is charged to no one: each slice to its process, the
    /// node's own work (restarts, traces, reaping) to nobody, and what the
    /// children sent the root to the root once it has its answer.
    fn drive<T>(
        &self,
        goal: impl FnMut(&mut NodeState) -> Option<T>,
        deadline: Option<u64>,
        word: &str,
        span: Span,
    ) -> Result<Driven<T>, EvalError> {
        let (driven, _) = self.apart(|| self.drive_unmetered(goal, deadline, word, span));
        self.settle_root();
        driven
    }

    fn drive_unmetered<T>(
        &self,
        mut goal: impl FnMut(&mut NodeState) -> Option<T>,
        deadline: Option<u64>,
        word: &str,
        span: Span,
    ) -> Result<Driven<T>, EvalError> {
        let mut sched = lock(&self.sched);
        loop {
            self.adopt(&mut sched);
            self.process_signals(&mut sched);
            {
                let mut st = self.st();
                if let Some((from, reason)) = st.root_signal.take() {
                    return Err(refuse(
                        word,
                        format!("linked process {} exited: {}", from.0, render(&reason)),
                        span,
                    ));
                }
                if let Some(t) = goal(&mut st) {
                    return Ok(Driven::Done(t));
                }
                if deadline.is_some_and(|d| st.clock.now() >= d) {
                    return Ok(Driven::TimedOut);
                }
            }
            if self.apply_migrations(&mut sched) {
                continue;
            }
            if self.has_work(&sched) {
                self.round(&mut sched);
                continue;
            }
            // Nothing can run now: move time to the next deadline, or say that
            // nothing will ever change.
            let next = {
                let st = self.st();
                match (st.earliest_deadline(), deadline) {
                    (Some(a), Some(b)) => Some(a.min(b)),
                    (a, b) => a.or(b),
                }
            };
            match next {
                Some(t) => {
                    let pause = self.st().clock.advance_to(t);
                    if let Some(d) = pause {
                        std::thread::sleep(d);
                    }
                }
                None => {
                    if self.fail_stuck_migrations() {
                        continue;
                    }
                    let blocked = sched
                        .iter()
                        .filter(|p| p.state.is_blocked())
                        .map(|p| p.pid)
                        .collect();
                    return Ok(Driven::Deadlock(blocked));
                }
            }
        }
    }

    /// Migrations whose process is parked somewhere other than a boundary,
    /// with nothing left to wake it, can never apply: answer them.
    fn fail_stuck_migrations(&self) -> bool {
        let mut st = self.st();
        let stuck: Vec<(Pid, Migration)> = std::mem::take(&mut st.migrations).into_iter().collect();
        let any = !stuck.is_empty();
        for (pid, m) in stuck {
            st.outcomes.entry(m.request).or_default().push((
                pid,
                Err("the process is waiting inside its handler and nothing can wake it, so it never \
                     reached a boundary"
                    .into()),
            ));
        }
        any
    }

    fn receive_root(&self, args: &[Value], span: Span) -> Result<Value, EvalError> {
        let (pattern, timeout, default) = receive_args(args, span)?;
        let deadline = timeout.map(|t| self.st().clock.now().saturating_add(t));
        let driven = self.drive(
            |st| {
                let b = st.boxes.get_mut(&ROOT)?;
                let i = pattern::first_match(b, &pattern)?;
                b.remove(i)
            },
            deadline,
            "receive",
            span,
        )?;
        match driven {
            Driven::Done(msg) => Ok(msg),
            Driven::TimedOut => Ok(default),
            Driven::Deadlock(blocked) => Err(refuse(
                "receive",
                format!(
                    "would wait forever: no process can send (deadlock; waiting: {})",
                    blocked
                        .iter()
                        .map(|p| p.0.to_string())
                        .collect::<Vec<_>>()
                        .join(", ")
                ),
                span,
            )),
        }
    }

    /// Run every process until none can make progress. For hosts and tests;
    /// a blue program waits with `receive`.
    pub fn run_until_idle(&self) {
        let _ = self.drive(|_| None::<()>, None, "run", Span::synthetic());
    }

    /// Processes the node still holds: queued, running, parked, or finished
    /// under a supervisor that may restart them. A finished unsupervised
    /// process is not among them; its interpreter has been dropped.
    #[must_use]
    pub fn process_count(&self) -> usize {
        lock(&self.sched).len() + self.st().pending.len()
    }

    /// The mailbox of `pid`, oldest first. For hosts and tests.
    #[must_use]
    pub fn mailbox(&self, pid: Pid) -> Vec<Value> {
        self.st()
            .boxes
            .get(&pid)
            .map(|b| b.iter().cloned().collect())
            .unwrap_or_default()
    }
}

// ── the words ──────────────────────────────────────────────────────────────

fn spawn_args(args: &[Value], word: &str, span: Span) -> Result<Vec<Value>, EvalError> {
    match args.get(1) {
        None | Some(Value::Nil) => Ok(Vec::new()),
        Some(Value::List(l)) => Ok(l.iter().cloned().collect()),
        Some(other) => Err(refuse(
            word,
            format!("the arguments are a list, got {}", other.type_name()),
            span,
        )),
    }
}

fn spawn_one(
    node: &Node,
    f: &Value,
    args: &[Value],
    sup: Option<Pid>,
    word: &str,
    span: Span,
) -> Result<Pid, EvalError> {
    let (code, entry) = code::spawn_code(f, args).map_err(|m| refuse(word, m, span))?;
    let def_name = match entry {
        Entry::Named(n) | Entry::Builtin(n) => Some(n),
        Entry::Lambda(_) => None,
    };
    node.start(code, Kind::Plain, def_name, sup)
        .map_err(|m| refuse(word, m, span))
}

fn w_spawn(node: &Node, _who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let a = spawn_args(args, "spawn", span)?;
    Ok(int(spawn_one(node, &args[0], &a, None, "spawn", span)?.0))
}

fn w_spawn_link(node: &Node, who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let a = spawn_args(args, "spawn_link", span)?;
    let pid = spawn_one(node, &args[0], &a, None, "spawn_link", span)?;
    let mut st = node.st();
    let me = who.pid();
    if let Some(i) = st.info.get_mut(&me) {
        i.links.insert(pid);
    }
    if let Some(i) = st.info.get_mut(&pid) {
        i.links.insert(me);
    }
    Ok(int(pid.0))
}

/// The `def_hash` the node's identities give the definition `f` is bound
/// under, as a trace and a receipt name it; nil when they give none.
fn w_def_hash(node: &Node, _who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let f = &args[0];
    if !code::is_function(f) {
        return Err(refuse(
            "def_hash",
            format!("expected a function, got {}", f.type_name()),
            span,
        ));
    }
    Ok(code::name_of(f)
        .and_then(|key| node.config.identities.of(&key))
        .map_or(Value::Nil, |hash| Value::Str(Arc::from(hash))))
}

fn w_spawn_server(node: &Node, _who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    Ok(int(server(
        node,
        &args[0],
        &args[1],
        None,
        "spawn_server",
        span,
    )?
    .0))
}

fn server(
    node: &Node,
    handler: &Value,
    state: &Value,
    sup: Option<Pid>,
    word: &str,
    span: Span,
) -> Result<Pid, EvalError> {
    let mut code = code::function_code(handler, "%handler").map_err(|m| refuse(word, m, span))?;
    code.defs.extend(SERVER_LOOP.iter().cloned());
    code.start = Some(code::call(code::symbol("%serve"), &[]));
    let state = copy_data(state).map_err(|kind| {
        refuse(
            word,
            format!("a server's state is copied into the process, and a {kind} is not data"),
            span,
        )
    })?;
    code.bind("%state", state);
    node.start(code, Kind::Server, code::name_of(handler), sup)
        .map_err(|m| refuse(word, m, span))
}

fn w_send(node: &Node, _who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let to = pid_arg(&args[0], "send", span)?;
    let (copied, bytes) = node.apart(|| {
        copy_data(&args[1]).map(|msg| {
            // A send to a process that has exited is dropped, as in Erlang: the
            // sender cannot know, and a send that raised would race the exit.
            node.st().deliver(to, msg);
        })
    });
    copied.map_err(|kind| {
        refuse(
            "send",
            format!("a message is copied to the receiver, and a {kind} is not data"),
            span,
        )
    })?;
    node.credit(to, bytes);
    Ok(args[1].clone())
}

fn w_self(_node: &Node, who: Who, _args: &[Value], _span: Span) -> Result<Value, EvalError> {
    Ok(int(who.pid().0))
}

fn w_alive(node: &Node, _who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let pid = pid_arg(&args[0], "alive?", span)?;
    Ok(Value::Bool(
        node.st().info.get(&pid).is_some_and(|i| i.live),
    ))
}

fn w_link(node: &Node, who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let other = pid_arg(&args[0], "link", span)?;
    let me = who.pid();
    let mut st = node.st();
    if other == me || !st.info.contains_key(&other) {
        return Ok(Value::Bool(false));
    }
    if let Some(i) = st.info.get_mut(&me) {
        i.links.insert(other);
    }
    if let Some(i) = st.info.get_mut(&other) {
        i.links.insert(me);
    }
    Ok(Value::Bool(true))
}

fn w_unlink(node: &Node, who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let other = pid_arg(&args[0], "unlink", span)?;
    let me = who.pid();
    let mut st = node.st();
    if let Some(i) = st.info.get_mut(&me) {
        i.links.remove(&other);
    }
    if let Some(i) = st.info.get_mut(&other) {
        i.links.remove(&me);
    }
    Ok(Value::Bool(true))
}

fn w_monitor(node: &Node, who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let target = pid_arg(&args[0], "monitor", span)?;
    let me = who.pid();
    let mut st = node.st();
    let r = st.next_ref;
    st.next_ref += 1;
    match st.info.get_mut(&target) {
        Some(i) => i.monitors.push((r, me)),
        None => st.deliver(
            me,
            Value::list([kw("down"), int(r), int(target.0), kw("noproc")]),
        ),
    }
    Ok(int(r))
}

fn w_demonitor(node: &Node, _who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let Value::Int(r) = args[0] else {
        return Err(refuse(
            "demonitor",
            "expected a monitor reference (an Int)",
            span,
        ));
    };
    let mut st = node.st();
    for i in st.info.values_mut() {
        i.monitors.retain(|(x, _)| *x != r);
    }
    Ok(Value::Bool(true))
}

fn w_exit(node: &Node, who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let to = pid_arg(&args[0], "exit", span)?;
    let reason = copy_data(&args[1])
        .map_err(|kind| refuse("exit", format!("a reason is data, not a {kind}"), span))?;
    let me = who.pid();
    if to == me {
        return Err(refuse(
            "exit",
            format!("process {} exits: {}", me.0, render(&reason)),
            span,
        ));
    }
    node.st().signals.push_back((me, to, reason));
    if who == Who::Root {
        // The root is not inside a slice, so the signal is delivered now.
        let mut sched = lock(&node.sched);
        node.adopt(&mut sched);
        node.process_signals(&mut sched);
        node.reap(&mut sched);
    }
    Ok(Value::Bool(true))
}

fn truthy(v: &Value) -> bool {
    !matches!(v, Value::Nil | Value::Bool(false))
}

fn w_trap_exit(node: &Node, who: Who, args: &[Value], _span: Span) -> Result<Value, EvalError> {
    let mut st = node.st();
    let Some(i) = st.info.get_mut(&who.pid()) else {
        return Ok(Value::Bool(false));
    };
    let previous = i.trap_exit;
    i.trap_exit = truthy(&args[0]);
    Ok(Value::Bool(previous))
}

fn w_supervisor(node: &Node, _who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let strategy = match &args[0] {
        Value::Keyword(k) => Strategy::from_keyword(k.trim_start_matches(':')),
        _ => None,
    }
    .ok_or_else(|| {
        refuse(
            "supervisor",
            "the strategy is :one_for_one, :one_for_all or :rest_for_one",
            span,
        )
    })?;
    let Value::List(specs) = &args[1] else {
        return Err(refuse(
            "supervisor",
            "the children are a list of functions or [f, args] pairs",
            span,
        ));
    };
    let max_restarts = match args.get(2) {
        None | Some(Value::Nil) => DEFAULT_MAX_RESTARTS,
        Some(Value::Int(n)) if *n >= 0 => usize::try_from(*n).unwrap_or(usize::MAX),
        Some(other) => {
            return Err(refuse(
                "supervisor",
                format!("max_restarts is an Int >= 0, got {}", other.type_name()),
                span,
            ))
        }
    };
    let sup = {
        let mut st = node.st();
        let sup = Pid(st.next_pid);
        st.next_pid += 1;
        st.info.insert(
            sup,
            Info::new(Kind::Supervisor(Sup {
                strategy,
                max_restarts,
                children: Vec::new(),
            })),
        );
        st.boxes.insert(sup, VecDeque::new());
        sup
    };
    for spec in specs.iter() {
        let pid = match spec {
            // `[:server, handler, state]`: a supervised spawn_server.
            Value::List(t) if t.len() == 3 && is_keyword(&t[0], "server") => {
                server(node, &t[1], &t[2], Some(sup), "supervisor", span)?
            }
            Value::List(pair) if pair.len() == 2 && code::is_function(&pair[0]) => {
                let Value::List(a) = &pair[1] else {
                    return Err(refuse(
                        "supervisor",
                        "a child [f, args] takes its args as a list",
                        span,
                    ));
                };
                let a: Vec<Value> = a.iter().cloned().collect();
                spawn_one(node, &pair[0], &a, Some(sup), "supervisor", span)?
            }
            f => spawn_one(node, f, &[], Some(sup), "supervisor", span)?,
        };
        if let Some(Info {
            kind: Kind::Supervisor(s),
            ..
        }) = node.st().info.get_mut(&sup)
        {
            s.children.push(pid);
        }
    }
    Ok(int(sup.0))
}

fn w_children(node: &Node, _who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let sup = pid_arg(&args[0], "children", span)?;
    let st = node.st();
    match st.info.get(&sup).map(|i| &i.kind) {
        Some(Kind::Supervisor(s)) => Ok(Value::list(s.children.iter().map(|p| int(p.0)))),
        _ => Ok(Value::list([])),
    }
}

fn w_defmigrate(node: &Node, who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let targets: Vec<Pid> = match &args[0] {
        Value::Int(_) => vec![pid_arg(&args[0], "defmigrate", span)?],
        f if code::is_function(f) => {
            let Some(name) = code::name_of(f) else {
                return Err(refuse(
                    "defmigrate",
                    "the target function has no name to match processes by",
                    span,
                ));
            };
            let st = node.st();
            st.info
                .iter()
                .filter(|(_, i)| {
                    matches!(i.kind, Kind::Plain | Kind::Server)
                        && i.def_name.as_deref() == Some(&name)
                })
                .map(|(p, _)| *p)
                .collect()
        }
        other => {
            return Err(refuse(
                "defmigrate",
                format!(
                    "the target is a pid or the function processes run, got {}",
                    other.type_name()
                ),
                span,
            ))
        }
    };
    let request = {
        let mut st = node.st();
        let r = st.next_request;
        st.next_request += 1;
        r
    };
    let new_name = code::name_of(&args[1]).unwrap_or_else(|| format!("%migration{request}"));
    let new_code =
        code::function_code(&args[1], &new_name).map_err(|m| refuse("defmigrate", m, span))?;
    let transform = match args.get(2) {
        None | Some(Value::Nil) => None,
        Some(t) => {
            Some(code::function_code(t, "%transform").map_err(|m| refuse("defmigrate", m, span))?)
        }
    };
    let mut answers: Vec<(Pid, Result<(), String>)> = Vec::new();
    let mut queued = Vec::new();
    {
        let mut st = node.st();
        for pid in targets {
            match st.info.get(&pid).map(|i| &i.kind) {
                Some(Kind::Plain | Kind::Server) => {
                    st.migrations.insert(
                        pid,
                        Migration {
                            request,
                            code: new_code.clone(),
                            new_name: new_name.clone(),
                            transform: transform.clone(),
                        },
                    );
                    queued.push(pid);
                }
                _ => answers.push((pid, Err("no such process".into()))),
            }
        }
    }
    if who != Who::Root {
        // A child cannot wait for other processes inside its slice; the
        // migration is applied at the target's next boundary.
        return Ok(Value::list(
            queued.iter().map(|p| Value::list([int(p.0), kw("queued")])),
        ));
    }
    if !queued.is_empty() {
        let want = queued.len();
        let driven = node.drive(
            |st| {
                (st.outcomes.get(&request).map_or(0, Vec::len) >= want)
                    .then(|| st.outcomes.remove(&request).unwrap_or_default())
            },
            None,
            "defmigrate",
            span,
        )?;
        if let Driven::Done(done) = driven {
            answers.extend(done);
        }
    }
    answers.sort_by_key(|(p, _)| *p);
    Ok(Value::list(answers.into_iter().map(|(p, r)| {
        Value::list([
            int(p.0),
            match r {
                Ok(()) => kw("ok"),
                Err(m) => Value::list([kw("error"), Value::Str(Arc::from(m.as_str()))]),
            },
        ])
    })))
}
