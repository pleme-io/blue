//! The node: blue processes reachable from blue (BLUE-GAPS G11).
//!
//! Until this module, everything in this crate was reachable only from Rust:
//! a blue program could not spawn, send or receive, and a NATS subscriber had
//! to poll from the main program. A [`Node`] is the process runtime one
//! interpreter's program runs against, and [`install`] binds its words:
//!
//! ```text
//! spawn(f[, args][, opts])    spawn_link(f[, args][, opts])
//! spawn_server(handler, state[, opts])                   opts: {scheduling: :normal | :idle}
//! send(pid, msg)              receive([pattern][, timeout_ms][, on_timeout])
//! self()   alive?(pid)        link(pid)  unlink(pid)     monitor(pid)  demonitor(ref)
//! exit(pid, reason)           trap_exit(flag)
//! supervisor(strategy, children[, max_restarts])         children(sup)
//! defmigrate(target, new_fn[, transform])
//! def_hash(f)
//! evict(pid, wire, peer)      accept(wire, timeout_ms)   (with a Carrier: comm-scavenger)
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
//!   a crash writes the tape out ([`crate::trace`]). An `:idle` process is the
//!   one exception to the one thread: its slices run on a low-priority thread
//!   of its own while the node runs the rest ([`IdleLane::Apart`]), so where
//!   they fall among the others is the OS's choice and not replayable; its
//!   own crash still replays from its tape. It still acts only while the root
//!   waits: a word it calls between waits holds until the next one. [`IdleLane::Held`] keeps the whole
//!   interleaving replayable by waiting for each idle slice.
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
use std::sync::{mpsc, Arc, Condvar, LazyLock, Mutex, MutexGuard, OnceLock, Weak};
use std::time::{Duration, Instant};

use tatara_lisp::{Span, Spanned};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::vm::run::CompiledClosure;
use tatara_lisp_eval::vm::{
    compile_program, Budget, Chunk, FnRef, ParkError, Vm, DEFAULT_MAX_DEPTH,
};
use tatara_lisp_eval::{EvalError, Interpreter, MapKey, Value};

use blue_lang_waku::Capability;

use crate::code::{self, Code, Entry};
use crate::image::{self, Account, Arrivals, Continuation, Image, Supervision};
use crate::mailbox::copy_data;
use crate::pattern;
use crate::receipt::{
    CarriedIo, Frame, HostIo, Identities, Places, Receipt, ReceiptSink, Roots, StateRoot, Subject,
};
use crate::scheduling::{self, IdleLane, Scheduling};
use crate::trace::{Carried, CarriedAccount, Journal, SliceRecord, TapeEntry, Trace};
use crate::violation::{breach, defined_key, Violation};
use crate::{provided_name, raised, ExitReason, Pid, Proc, ProcState, Slice, Strategy};

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
    "node_time",
    "after",
    "context",
    "remaining",
    "sleep_for",
    "sleep_until",
    "deadline",
    "timeout",
];

pub const CARRIED_WORDS: &[&str] = &["evict", "accept"];

pub const EVICTED: &str = "evicted";

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
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ClockKind {
    /// Milliseconds since the node started; an idle node sleeps until the
    /// next deadline.
    Real,
    /// Time moves only when every process is waiting: the node jumps to the
    /// next deadline. Deterministic, and the only clock a host with no clock
    /// (wasm) can offer.
    #[default]
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

#[derive(Clone, Copy, Debug)]
pub struct Carrier {
    pub room: usize,
    pub queue: fn(&Value, &Value, &[String], bool) -> Result<usize, String>,
    pub take: fn(&Value, &str, Duration, bool) -> Result<Vec<String>, String>,
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
    pub carrier: Option<Carrier>,
    pub dispatch_steps: Option<usize>,
    pub count_steps: bool,
    pub idle_lane: IdleLane,
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
            carrier: None,
            dispatch_steps: None,
            count_steps: false,
            idle_lane: IdleLane::default(),
        }
    }

    fn journals(&self) -> bool {
        self.frame.is_some() && self.journal > 0
    }

    fn carrying(&self) -> Carrying {
        let cap = Capability::CommScavenger;
        Carrying {
            carrier: self.carrier.is_some(),
            scoped: self.frame.as_ref().is_some_and(|f| {
                f.provided
                    .iter()
                    .any(|p| p.scope.is_some() && p.provision.capability() == cap)
            }),
            withheld: self
                .frame
                .as_ref()
                .is_some_and(|f| f.withheld.contains(&cap)),
        }
    }
}

#[derive(Clone, Copy)]
struct Carrying {
    carrier: bool,
    scoped: bool,
    withheld: bool,
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
    scheduling: Scheduling,
    dispatch: Option<usize>,
    dispatch_from: Option<usize>,
    armed: bool,
    kept: Option<Value>,
    asked: Option<usize>,
    deadline: Option<u64>,
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
            scheduling: Scheduling::Normal,
            dispatch: None,
            dispatch_from: None,
            armed: false,
            kept: None,
            asked: None,
            deadline: None,
        }
    }

    fn ask_dispatch(&mut self, own: Option<usize>) {
        self.asked = own;
        self.dispatch = match (self.dispatch, own) {
            (Some(app), Some(own)) => Some(app.min(own)),
            (app, own) => app.or(own),
        };
    }
}

/// What a parked child is waiting for.
#[derive(Clone, Debug)]
enum Wait {
    Receive {
        pattern: Value,
        deadline: Option<u64>,
        bound: Option<u64>,
    },
    Timer {
        until: u64,
        bound: Option<u64>,
    },
    /// A server between messages: its migration boundary.
    ServerNext,
}

impl Wait {
    fn wakes(&self) -> Option<u64> {
        match self {
            Wait::Receive {
                deadline, bound, ..
            } => earliest(*deadline, *bound),
            Wait::Timer { until, bound } => earliest(Some(*until), *bound),
            Wait::ServerNext => None,
        }
    }
}

fn earliest(a: Option<u64>, b: Option<u64>) -> Option<u64> {
    match (a, b) {
        (Some(a), Some(b)) => Some(a.min(b)),
        (a, b) => a.or(b),
    }
}

fn bound_fired(bound: Option<u64>, own: Option<u64>, now: u64) -> bool {
    bound.is_some_and(|b| now >= b && own.is_none_or(|o| b < o))
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
    carried: Option<Carried>,
}

impl Tape {
    fn arrived(carried: Option<Vec<TapeEntry>>, image: &str) -> Self {
        match carried {
            Some(entries) => Self {
                carried: Some(Carried::of(&entries, image)),
                entries,
                truncated: false,
            },
            None => Self {
                entries: Vec::new(),
                truncated: true,
                carried: None,
            },
        }
    }
}

#[derive(Clone, Debug)]
struct Brought {
    mark: CarriedAccount,
    input_root: Option<String>,
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
    accounts: BTreeMap<Pid, Brought>,
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
    evicting: BTreeSet<Pid>,
    arrivals: Arrivals,
    aloft: BTreeSet<Pid>,
    doomed: BTreeMap<Pid, Value>,
    recalled: BTreeSet<Pid>,
    timers: BTreeMap<(u64, u64), (Pid, Value)>,
    next_timer: u64,
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
            accounts: BTreeMap::new(),
            signals: VecDeque::new(),
            migrations: BTreeMap::new(),
            outcomes: BTreeMap::new(),
            schedule: VecDeque::new(),
            traces: VecDeque::new(),
            clock: Clock::new(clock),
            root_signal: None,
            root_due: 0,
            evicting: BTreeSet::new(),
            arrivals: Arrivals::default(),
            aloft: BTreeSet::new(),
            doomed: BTreeMap::new(),
            recalled: BTreeSet::new(),
            timers: BTreeMap::new(),
            next_timer: 1,
        }
    }

    fn running(&self) -> Pid {
        scheduling::lane().unwrap_or(self.current)
    }

    fn supervisor(&mut self, strategy: Strategy, max_restarts: usize) -> Pid {
        let sup = Pid(self.next_pid);
        self.next_pid += 1;
        self.info.insert(
            sup,
            Info::new(Kind::Supervisor(Sup {
                strategy,
                max_restarts,
                children: Vec::new(),
            })),
        );
        self.boxes.insert(sup, VecDeque::new());
        sup
    }

    fn enrol(&mut self, sup: Pid, child: Pid) {
        if let Some(Info {
            kind: Kind::Supervisor(s),
            ..
        }) = self.info.get_mut(&sup)
        {
            s.children.push(child);
        }
    }

    fn drop_child(&mut self, sup: Pid, child: Pid) {
        if let Some(Info {
            kind: Kind::Supervisor(s),
            ..
        }) = self.info.get_mut(&sup)
        {
            s.children.retain(|c| *c != child);
        }
    }

    fn held_at_boundary(&self, pid: Pid) -> bool {
        self.migrations.contains_key(&pid) || self.evicting.contains(&pid)
    }

    fn held_at_receive(&self, pid: Pid) -> bool {
        self.evicting.contains(&pid)
            && self
                .info
                .get(&pid)
                .is_some_and(|i| matches!(i.kind, Kind::Plain))
    }

    fn opens_dispatch(&mut self, pid: Pid) -> bool {
        match self.info.get_mut(&pid) {
            Some(info) if info.dispatch.is_some() && !info.armed => {
                info.armed = true;
                true
            }
            _ => false,
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
            Some(w @ Wait::Receive { pattern, .. }) => {
                !self.held_at_receive(pid)
                    && (mailbox.is_some_and(|b| pattern::first_match(b, pattern).is_some())
                        || w.wakes().is_some_and(|d| now >= d))
            }
            Some(w @ Wait::Timer { .. }) => w.wakes().is_some_and(|d| now >= d),
            Some(Wait::ServerNext) => {
                mailbox.is_some_and(|b| !b.is_empty()) && !self.held_at_boundary(pid)
            }
            None => mailbox.is_some_and(|b| !b.is_empty()),
        }
    }

    fn earliest_deadline(&self) -> Option<u64> {
        let waits = self.waits.values().filter_map(Wait::wakes).min();
        earliest(waits, self.timers.keys().next().map(|(at, _)| *at))
    }

    fn bound_of(&self, pid: Pid) -> Option<u64> {
        self.info.get(&pid).and_then(|i| i.deadline)
    }

    fn fire_timers(&mut self) {
        let now = self.clock.now();
        while let Some(entry) = self.timers.first_entry() {
            if entry.key().0 > now {
                break;
            }
            let (to, msg) = entry.remove();
            self.deliver(to, msg);
        }
    }

    fn forget(&mut self, pid: Pid) {
        self.info.remove(&pid);
        self.boxes.remove(&pid);
        self.waits.remove(&pid);
        self.tapes.remove(&pid);
        self.journals.remove(&pid);
        self.accounts.remove(&pid);
        self.evicting.remove(&pid);
    }

    /// `pid` took `msg`: keep it among its last `bound`.
    fn note_taken(&mut self, pid: Pid, msg: &Value, bound: usize) {
        let ring = self.journals.entry(pid).or_default();
        if ring.len() == bound {
            ring.pop_front();
            if let Some(a) = self.accounts.get_mut(&pid) {
                a.mark.dropped_oldest(ring);
            }
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
    lanes: Mutex<BTreeMap<Pid, mpsc::Sender<Proc<()>>>>,
    flights: Mutex<mpsc::Receiver<Flight>>,
    radio: mpsc::Sender<Flight>,
    gate: Mutex<Gate>,
    gated: Condvar,
    rooted: Mutex<Option<Weak<()>>>,
}

#[derive(Default)]
struct Gate {
    driving: usize,
    inside: usize,
}

struct Pass<'a>(&'a Node);

impl Drop for Pass<'_> {
    fn drop(&mut self) {
        let mut g = lock(&self.0.gate);
        g.inside -= 1;
        self.0.gated.notify_all();
    }
}

struct Driving<'a>(&'a Node);

impl Drop for Driving<'_> {
    fn drop(&mut self) {
        let node = self.0;
        let mut g = lock(&node.gate);
        g.driving -= 1;
        while g.driving == 0 && g.inside > 0 {
            g = node
                .gated
                .wait(g)
                .unwrap_or_else(std::sync::PoisonError::into_inner);
        }
    }
}

enum Flight {
    Landed(Proc<()>, Slice, usize),
    Poked,
    Fell(Box<dyn std::any::Any + Send>),
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

fn parking(e: &ParkError) -> String {
    match e {
        ParkError::NoFrames => "it holds no frames: it has not started, or it has returned".into(),
        ParkError::NoDataForm { what, at } => format!(
            "it holds {what} in {at}, which has no data form and does not cross a wire; open it \
             inside the process once it has moved"
        ),
        ParkError::OtherChunk { what, at } => format!(
            "it runs code it was not spawned with ({what}, {at}), and its image carries only the \
             code it was spawned with"
        ),
        ParkError::ChunkMismatch { parked, chunk } => format!(
            "its frames were parked in chunk {parked}, and its code compiles here to chunk \
             {chunk}: this blue compiles it differently from the one it left"
        ),
        ParkError::UnknownNative { name } => {
            format!("it holds the native function `{name}`, which this node does not register")
        }
        ParkError::Malformed(why) => format!("its frames are malformed: {why}"),
    }
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
    ("spawn", Arity::Range(1, 3), w_spawn),
    ("spawn_link", Arity::Range(1, 3), w_spawn_link),
    ("spawn_server", Arity::Range(2, 3), w_spawn_server),
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
    ("node_time", Arity::Exact(0), w_node_time),
    ("after", Arity::Range(2, 3), w_after),
    ("context", Arity::Exact(0), w_context),
    ("remaining", Arity::Exact(0), w_remaining),
];

const CARRIED: &[(&str, Arity, Word, Word)] = &[
    ("evict", Arity::Exact(3), w_evict, w_evict_provided),
    ("accept", Arity::Exact(2), w_accept, w_accept_provided),
];

/// Bind the process words into the interpreter that runs a program, against
/// `node`. The interpreter becomes the node's root.
pub fn install<H: 'static>(interp: &mut Interpreter<H>, node: Arc<Node>) {
    let carrying = node.config.carrying();
    let rooted = Arc::new(());
    *lock(&node.rooted) = Some(Arc::downgrade(&rooted));
    let side = Side::Root(node);
    for (name, arity, word) in WORDS {
        register(interp, &side, name, *arity, *word);
    }
    carry(interp, &side, carrying);
    // The root never parks: its `receive` drives the other processes until
    // it has an answer, so it is an ordinary function on either executor.
    let s = side.clone();
    interp.register_fn(
        "receive",
        Arity::Range(0, 3),
        move |args: &[Value], _h: &mut H, span| {
            let _rooted = &rooted;
            let node = s.node("receive", span)?;
            node.receive_root(args, span)
        },
    );
    for (name, relative) in [("sleep_for", true), ("sleep_until", false)] {
        let s = side.clone();
        interp.register_fn(
            name,
            Arity::Exact(1),
            move |args: &[Value], _h: &mut H, span| {
                let node = s.node(name, span)?;
                let target = wake_at(&node, name, &args[0], relative, span)?;
                node.sleep_root(name, target, span)
            },
        );
    }
    for (name, relative) in [("deadline", false), ("timeout", true)] {
        let s = side.clone();
        interp.register_higher_order_fn(
            name,
            Arity::Exact(2),
            move |args: &[Value], h: &mut H, caller: &tatara_lisp_eval::ffi::Caller<H>, span| {
                let node = s.node(name, span)?;
                let at = wake_at(&node, name, &args[0], relative, span)?;
                let prev = node.st().bound_of(ROOT);
                let held = earliest(prev, Some(at));
                node.bind_deadline(ROOT, held);
                let out = caller.apply_value(&args[1], Vec::new(), h, span);
                node.bind_deadline(ROOT, prev);
                let now = node.st().clock.now();
                match (out, held) {
                    (Ok(_), Some(d)) if now > d => Err(passed(name, d, now, span)),
                    (out, _) => out,
                }
            },
        );
    }
}

fn wake_at(
    node: &Node,
    word: &str,
    v: &Value,
    relative: bool,
    span: Span,
) -> Result<u64, EvalError> {
    let n = match v {
        Value::Int(n) if *n >= 0 => n.unsigned_abs(),
        other => {
            return Err(refuse(
                word,
                format!(
                    "the time is milliseconds on the node clock (an Int >= 0), got {}",
                    other.type_name()
                ),
                span,
            ))
        }
    };
    Ok(if relative {
        node.st().clock.now().saturating_add(n)
    } else {
        n
    })
}

fn passed(word: &str, deadline: u64, now: u64, span: Span) -> EvalError {
    crate::raised(
        "timeout",
        format!("{word}: the deadline at {deadline} ms on the node clock passed (now {now} ms)"),
        record(&[("deadline", int(deadline)), ("now", int(now))]),
        span,
    )
}

fn carry<H: 'static>(interp: &mut Interpreter<H>, side: &Side, carrying: Carrying) {
    for (name, arity, word, provided) in CARRIED {
        if !carrying.carrier {
            if interp.lookup_global(name).is_some() {
                register_as(interp, side, name, (*name).to_string(), *arity, w_uncarried);
            }
            continue;
        }
        if carrying.withheld {
            refuse_as(interp, side, name);
        } else {
            register_as(interp, side, name, (*name).to_string(), *arity, *word);
        }
        if carrying.scoped {
            register_as(interp, side, name, provided_name(name), *arity, *provided);
        }
    }
}

fn refuse_as<H: 'static>(interp: &mut Interpreter<H>, side: &Side, name: &'static str) {
    let who = match side {
        Side::Root(_) => "this run's frame",
        Side::Child(_) => "this process's frame",
    };
    interp.register_fn(name, Arity::Any, move |_: &[Value], _h: &mut H, span| {
        Err(breach(name, Capability::CommScavenger, who, span))
    });
}

fn register_as<H: 'static>(
    interp: &mut Interpreter<H>,
    side: &Side,
    name: &'static str,
    bound: String,
    arity: Arity,
    word: Word,
) {
    bind_word(interp, side, name, bound, arity, word, false);
}

fn register<H: 'static>(
    interp: &mut Interpreter<H>,
    side: &Side,
    name: &'static str,
    arity: Arity,
    word: Word,
) {
    bind_word(interp, side, name, name.to_string(), arity, word, true);
}

fn bind_word<H: 'static>(
    interp: &mut Interpreter<H>,
    side: &Side,
    name: &'static str,
    bound: String,
    arity: Arity,
    word: Word,
    taped: bool,
) {
    let side = side.clone();
    interp.register_fn(bound, arity, move |args: &[Value], _h: &mut H, span| {
        let node = side.node(name, span)?;
        let _pass = node.pass(name, span)?;
        let who = match side {
            Side::Root(_) => Who::Root,
            Side::Child(_) => Who::Child(node.current()),
        };
        let out = word(&node, who, args, span);
        if let (true, Who::Child(pid)) = (taped, who) {
            node.record(pid, name, &out);
        }
        node.poke();
        out
    });
}

/// The child side of the words, on the prototype every child forks.
fn install_child(proto: &mut Interpreter<()>, me: &Weak<Node>, carrying: Carrying) {
    let side = Side::Child(me.clone());
    for (name, arity, word) in WORDS {
        register(proto, &side, name, *arity, *word);
    }
    carry(proto, &side, carrying);

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
            let Ok(_pass) = node.pass("receive", Span::synthetic()) else {
                return true;
            };
            let Ok((pattern, timeout, _)) = receive_args(args, Span::synthetic()) else {
                // Let the call raise the argument error.
                return true;
            };
            let mut st = node.st();
            let pid = st.running();
            let held = st.held_at_receive(pid);
            if !held
                && st
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
            let bound = st.bound_of(pid);
            let wait = Wait::Receive {
                pattern,
                deadline,
                bound,
            };
            let wakes = wait.wakes();
            st.waits.insert(pid, wait);
            !held && wakes.is_some_and(|d| now >= d)
        },
        move |args: &[Value], _h: &mut (), span| {
            let node = Side::Child(c.clone()).node("receive", span)?;
            let _pass = node.pass("receive", span)?;
            let (pattern, _, default) = receive_args(args, span)?;
            let out = {
                let mut st = node.st();
                let pid = st.running();
                let waited = st.waits.remove(&pid);
                let taken = st.boxes.get_mut(&pid).and_then(|b| {
                    let i = pattern::first_match(b, &pattern)?;
                    b.remove(i)
                });
                node.journal(&mut st, pid, taken.as_ref());
                let now = st.clock.now();
                match (taken, waited) {
                    (Some(msg), _) => Ok(msg),
                    (
                        None,
                        Some(Wait::Receive {
                            deadline, bound, ..
                        }),
                    ) if bound_fired(bound, deadline, now) => {
                        Err(passed("receive", bound.unwrap_or(now), now, span))
                    }
                    (None, _) => Ok(default),
                }
            };
            node.record(node.current(), "receive", &out);
            out
        },
    );

    for (name, relative) in [("sleep_for", true), ("sleep_until", false)] {
        let (r, c) = (me.clone(), me.clone());
        proto.register_awaitable_fn(
            name,
            Arity::Exact(1),
            move |args: &[Value], _h: &()| {
                let Some(node) = r.upgrade() else { return true };
                let Ok(_pass) = node.pass(name, Span::synthetic()) else {
                    return true;
                };
                let pid = node.current();
                let waiting = match node.st().waits.get(&pid) {
                    Some(Wait::Timer { until, .. }) => Some(*until),
                    _ => None,
                };
                let until = match waiting {
                    Some(until) => until,
                    None => match wake_at(&node, name, &args[0], relative, Span::synthetic()) {
                        Ok(t) => t,
                        Err(_) => return true,
                    },
                };
                let mut st = node.st();
                let pid = st.running();
                let now = st.clock.now();
                let wait = Wait::Timer {
                    until,
                    bound: st.bound_of(pid),
                };
                let wakes = wait.wakes();
                st.waits.insert(pid, wait);
                wakes.is_some_and(|d| now >= d)
            },
            move |args: &[Value], _h: &mut (), span| {
                let node = Side::Child(c.clone()).node(name, span)?;
                let _pass = node.pass(name, span)?;
                let (waited, now) = {
                    let mut st = node.st();
                    let pid = st.running();
                    (st.waits.remove(&pid), st.clock.now())
                };
                let out = match waited {
                    Some(Wait::Timer { until, bound }) if bound_fired(bound, Some(until), now) => {
                        Err(passed(name, bound.unwrap_or(now), now, span))
                    }
                    Some(_) => Ok(Value::Nil),
                    None => wake_at(&node, name, &args[0], relative, span).map(|_| Value::Nil),
                };
                node.record(node.current(), name, &out);
                out
            },
        );
    }
    for name in ["deadline", "timeout"] {
        register(proto, &side, name, Arity::Exact(2), w_scoped_in_process);
    }

    // A server's boundary. Not ready while a migration is pending for this
    // process, so a busy server still stops here for the swap; the message
    // that was waiting stays in the mailbox for the new code.
    let (r, c) = (me.clone(), me.clone());
    proto.register_awaitable_fn(
        SERVER_NEXT,
        Arity::Exact(1),
        move |_args: &[Value], _h: &()| {
            let Some(node) = r.upgrade() else { return true };
            let Ok(_pass) = node.pass(SERVER_NEXT, Span::synthetic()) else {
                return true;
            };
            let mut st = node.st();
            let pid = st.running();
            let opens = st.opens_dispatch(pid);
            let ready = !opens
                && st.boxes.get(&pid).is_some_and(|b| !b.is_empty())
                && !st.held_at_boundary(pid);
            if !ready {
                st.waits.insert(pid, Wait::ServerNext);
            }
            ready
        },
        move |args: &[Value], _h: &mut (), span| {
            let node = Side::Child(c.clone()).node(SERVER_NEXT, span)?;
            let _pass = node.pass(SERVER_NEXT, span)?;
            let mut st = node.st();
            let pid = st.running();
            st.waits.remove(&pid);
            let taken = st.boxes.get_mut(&pid).and_then(VecDeque::pop_front);
            node.journal(&mut st, pid, taken.as_ref());
            let msg = taken.unwrap_or(Value::Nil);
            // A boundary: the tape restarts here, from this state, so a
            // long-lived server's trace is its last message, not its life.
            if let Some(info) = st.info.get_mut(&pid) {
                info.snapshot = Some(args.first().cloned().unwrap_or(Value::Nil));
                info.armed = false;
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

fn unclassed(p: &mut Proc<()>, why: &str) -> Slice {
    let reason = ExitReason::Crashed(format!("the OS refused the idle class: {why}"));
    p.state = ProcState::Exited(reason.clone());
    Slice::Exited(reason)
}

fn note_slice(st: &mut NodeState, pid: Pid, out: &Slice, burned: usize) {
    let outcome = match out {
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

fn fly(me: &Weak<Node>, pid: Pid, queue: &mpsc::Receiver<Proc<()>>, radio: &mpsc::Sender<Flight>) {
    let lowered = scheduling::lower();
    scheduling::board(pid);
    while let Ok(mut p) = queue.recv() {
        let Some(node) = me.upgrade() else { break };
        let before = p.vm.burned();
        let ran = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| match &lowered {
            Ok(()) => {
                let out = node.slice_held(&mut p);
                node.dispatch_held(&mut p, out)
            }
            Err(why) => unclassed(&mut p, why),
        }));
        let flight = match ran {
            Ok(out) => {
                let burned = p.vm.burned().saturating_sub(before);
                Flight::Landed(p, out, burned)
            }
            Err(panic) => Flight::Fell(panic),
        };
        drop(node);
        if radio.send(flight).is_err() {
            break;
        }
    }
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
        let (radio, flights) = mpsc::channel();
        Arc::new_cyclic(|me| Self {
            config,
            me: me.clone(),
            state: Mutex::new(NodeState::new(clock)),
            sched: Mutex::new(Vec::new()),
            proto: OnceLock::new(),
            lanes: Mutex::new(BTreeMap::new()),
            flights: Mutex::new(flights),
            radio,
            gate: Mutex::new(Gate::default()),
            gated: Condvar::new(),
            rooted: Mutex::new(None),
        })
    }

    fn st(&self) -> MutexGuard<'_, NodeState> {
        lock(&self.state)
    }

    fn current(&self) -> Pid {
        self.st().running()
    }

    fn pass(&self, word: &str, span: Span) -> Result<Option<Pass<'_>>, EvalError> {
        if scheduling::lane().is_none() {
            return Ok(None);
        }
        let mut g = lock(&self.gate);
        while g.driving == 0 {
            let rooted = lock(&self.rooted)
                .as_ref()
                .is_some_and(|w| w.strong_count() > 0);
            if !rooted {
                return Err(refuse(word, "the process's node has shut down", span));
            }
            g = self
                .gated
                .wait_timeout(g, Duration::from_millis(100))
                .map_or_else(|e| e.into_inner().0, |(g, _)| g);
        }
        g.inside += 1;
        Ok(Some(Pass(self)))
    }

    fn driving(&self) -> Driving<'_> {
        lock(&self.gate).driving += 1;
        self.gated.notify_all();
        Driving(self)
    }

    fn poke(&self) {
        if scheduling::lane().is_some() {
            let _ = self.radio.send(Flight::Poked);
        }
    }

    fn proto(&self) -> Arc<Interpreter<()>> {
        self.proto
            .get_or_init(|| {
                let mut p = (self.config.child)();
                install_child(&mut p, &self.me, self.config.carrying());
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
            tape.carried = None;
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
        if to == st.running() {
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
        let start = held;
        let (out, over) = self.charged(&mut held, bound, || p.slice(&mut ()));
        if let Some(info) = self.st().info.get_mut(&pid) {
            info.held += held - start;
        }
        if !over {
            return out;
        }
        let reason = ExitReason::memory_exhausted(limit);
        p.state = ProcState::Exited(reason.clone());
        Slice::Exited(reason)
    }

    fn dispatch_held(&self, p: &mut Proc<()>, out: Slice) -> Slice {
        if !matches!(out, Slice::Yielded | Slice::Blocked) {
            return out;
        }
        let burned = p.vm.burned();
        let mut st = self.st();
        let boundary = matches!(st.waits.get(&p.pid), Some(Wait::ServerNext));
        let Some(info) = st.info.get_mut(&p.pid) else {
            return out;
        };
        let Some(limit) = info.dispatch else {
            return out;
        };
        if info
            .dispatch_from
            .is_some_and(|from| burned.saturating_sub(from) > limit)
        {
            info.dispatch_from = None;
            info.armed = false;
            info.kept.clone_from(&info.snapshot);
            let kept = info.kept.clone();
            drop(st);
            if let Some(state) = kept {
                p.interp.define_global("%state", state);
            }
            let reason = ExitReason::dispatch_exhausted(limit);
            p.state = ProcState::Exited(reason.clone());
            return Slice::Exited(reason);
        }
        if boundary {
            info.dispatch_from = info.armed.then_some(burned);
        }
        out
    }

    fn slice_idle(&self, p: &mut Proc<()>) -> Slice {
        let ran = std::thread::scope(|s| {
            std::thread::Builder::new()
                .name("blue-idle".to_string())
                .stack_size(scheduling::LANE_STACK)
                .spawn_scoped(s, || scheduling::lower().map(|()| self.slice_held(p)))
                .map_err(|e| e.to_string())
                .and_then(|lane| {
                    lane.join()
                        .unwrap_or_else(|panic| std::panic::resume_unwind(panic))
                })
        });
        ran.unwrap_or_else(|why| unclassed(p, &why))
    }

    fn launch(&self, p: Proc<()>) {
        let pid = p.pid;
        self.st().aloft.insert(pid);
        let mut p = p;
        let mut why = String::new();
        for _ in 0..2 {
            let lane = {
                let mut lanes = lock(&self.lanes);
                match lanes.get(&pid) {
                    Some(lane) => Ok(lane.clone()),
                    None => self.lane(pid).inspect(|lane| {
                        lanes.insert(pid, lane.clone());
                    }),
                }
            };
            match lane {
                Ok(lane) => match lane.send(p) {
                    Ok(()) => return,
                    Err(mpsc::SendError(back)) => {
                        lock(&self.lanes).remove(&pid);
                        why = "its lane closed".to_string();
                        p = back;
                    }
                },
                Err(e) => {
                    why = e;
                    break;
                }
            }
        }
        let out = unclassed(&mut p, &why);
        let _ = self.radio.send(Flight::Landed(p, out, 0));
    }

    fn lane(&self, pid: Pid) -> Result<mpsc::Sender<Proc<()>>, String> {
        let (work, queue) = mpsc::channel::<Proc<()>>();
        let me = self.me.clone();
        let radio = self.radio.clone();
        std::thread::Builder::new()
            .name(format!("blue-idle-{}", pid.0))
            .stack_size(scheduling::LANE_STACK)
            .spawn(move || fly(&me, pid, &queue, &radio))
            .map(|_| work)
            .map_err(|e| e.to_string())
    }

    fn land(&self, sched: &mut Vec<Proc<()>>) -> bool {
        let mut any = false;
        loop {
            let next = lock(&self.flights).try_recv();
            let Ok(flight) = next else { return any };
            any |= self.touch_down(sched, flight);
        }
    }

    fn await_flight(&self, sched: &mut Vec<Proc<()>>, limit: Option<Duration>) {
        let next = {
            let flights = lock(&self.flights);
            match limit {
                Some(d) => flights.recv_timeout(d).ok(),
                None => flights.recv().ok(),
            }
        };
        if let Some(flight) = next {
            self.touch_down(sched, flight);
        }
        self.land(sched);
    }

    fn touch_down(&self, sched: &mut Vec<Proc<()>>, flight: Flight) -> bool {
        let (p, out, burned) = match flight {
            Flight::Landed(p, out, burned) => (p, out, burned),
            Flight::Poked => return false,
            Flight::Fell(panic) => std::panic::resume_unwind(panic),
        };
        let pid = p.pid;
        let (known, doomed, recalled) = {
            let mut st = self.st();
            st.aloft.remove(&pid);
            note_slice(&mut st, pid, &out, burned);
            (
                st.info.contains_key(&pid),
                st.doomed.remove(&pid),
                st.recalled.remove(&pid),
            )
        };
        if !known {
            lock(&self.lanes).remove(&pid);
            return true;
        }
        let at = sched.partition_point(|q| q.pid < pid);
        sched.insert(at, p);
        if recalled {
            self.restart(sched, pid);
        } else {
            match out {
                Slice::Yielded | Slice::Blocked => {
                    if let Some(reason) = doomed {
                        self.kill(sched, pid, reason);
                    }
                }
                out => self.conclude(sched, pid, out),
            }
        }
        self.adopt(sched);
        self.process_signals(sched);
        true
    }

    fn conclude(&self, sched: &mut Vec<Proc<()>>, pid: Pid, out: Slice) {
        match out {
            Slice::Done(v) => self.on_exit(sched, pid, &ExitReason::Normal, kw("normal"), Some(v)),
            Slice::Exited(r) => {
                let rv = reason_value(&r);
                self.on_exit(sched, pid, &r, rv, None);
            }
            Slice::Yielded | Slice::Blocked => {}
        }
    }

    fn detached(&self, pid: Pid) -> bool {
        self.config.idle_lane == IdleLane::Apart
            && self
                .st()
                .info
                .get(&pid)
                .is_some_and(|i| i.scheduling == Scheduling::Idle)
    }

    /// Compile `code` and queue a process running it, held to the bound of
    /// the account that spawns it. Building it is charged to no one.
    fn start(
        &self,
        code: Code,
        kind: Kind,
        def_name: Option<String>,
        sup: Option<Pid>,
        scheduling: Scheduling,
    ) -> Result<Pid, String> {
        let bound = self.config.meter.and_then(|m| (m.bound)());
        self.apart(|| self.start_unmetered(code, kind, def_name, sup, bound, scheduling))
            .0
    }

    fn start_unmetered(
        &self,
        code: Code,
        kind: Kind,
        def_name: Option<String>,
        sup: Option<Pid>,
        bound: Option<u64>,
        scheduling: Scheduling,
    ) -> Result<Pid, String> {
        let chunk = Arc::new(compile(&code.program())?);
        let build = self.builder(&code.bindings);
        let dispatch = matches!(kind, Kind::Server)
            .then_some(self.config.dispatch_steps)
            .flatten();
        let initial = match kind {
            Kind::Server => code
                .bindings
                .iter()
                .find(|(n, _)| &**n == "%state")
                .map(|(_, v)| v.clone()),
            _ => None,
        };
        let mut st = self.st();
        let inherited = st.bound_of(st.running());
        let pid = Pid(st.next_pid);
        st.next_pid += 1;
        let proc = Proc::new(pid, chunk.clone(), self.config.budget, build);
        let mut info = Info::new(kind);
        info.deadline = inherited;
        info.code = code;
        info.chunk = Some(chunk);
        info.def_name = def_name;
        info.sup = sup;
        info.snapshot.clone_from(&initial);
        info.entered.clone_from(&initial);
        info.initial = initial;
        info.bound = bound;
        info.scheduling = scheduling;
        info.dispatch = dispatch;
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
        let mut end = sched.len();
        let mut idx = 0;
        while idx < end {
            if !sched[idx].is_runnable() {
                idx += 1;
                continue;
            }
            let pid = sched[idx].pid;
            if self.detached(pid) {
                self.launch(sched.remove(idx));
                end -= 1;
                continue;
            }
            self.switch(&mut self.st(), pid);
            let idle = self
                .st()
                .info
                .get(&pid)
                .is_some_and(|i| i.scheduling == Scheduling::Idle);
            let before = sched[idx].vm.burned();
            let out = if idle {
                self.slice_idle(&mut sched[idx])
            } else {
                self.slice_held(&mut sched[idx])
            };
            let out = self.dispatch_held(&mut sched[idx], out);
            let burned = sched[idx].vm.burned().saturating_sub(before);
            {
                let mut st = self.st();
                self.switch(&mut st, ROOT);
                note_slice(&mut st, pid, &out, burned);
            }
            self.conclude(sched, pid, out);
            self.adopt(sched);
            self.process_signals(sched);
            idx += 1;
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
        let mut lanes = lock(&self.lanes);
        if !lanes.is_empty() {
            lanes.retain(|pid, _| st.aloft.contains(pid) || sched.iter().any(|p| p.pid == *pid));
        }
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
        } else {
            let mut st = self.st();
            if st.aloft.contains(&pid) {
                st.doomed.entry(pid).or_insert(reason);
            }
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
            if let Some(s) = supervised {
                st.drop_child(s, pid);
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
            let mut st = self.st();
            if st.aloft.contains(&pid) {
                st.recalled.insert(pid);
            }
            return;
        };
        let (chunk, kept) = {
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
            st.accounts.remove(&pid);
            self.config.host_io.take(pid);
            st.info.get_mut(&pid).map_or((None, None), |info| {
                info.restarts += 1;
                info.live = true;
                info.held = 0;
                info.dispatch_from = None;
                info.armed = false;
                let kept = info.kept.take();
                let state = kept.clone().or_else(|| info.initial.clone());
                info.snapshot.clone_from(&state);
                info.entered = state;
                (info.chunk.clone(), kept)
            })
        };
        if let Some(c) = chunk {
            p.chunk = c;
        }
        p.restart();
        if let Some(state) = kept {
            p.interp.define_global("%state", state);
        }
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
                && !st.aloft.contains(&c)
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

    // ── eviction ───────────────────────────────────────────────────────────

    fn tally(&self) {
        if self
            .config
            .frame
            .as_ref()
            .is_some_and(|f| f.granted.contains(&Capability::CommScavenger))
        {
            self.config.host_io.tally();
        }
    }

    fn carrier(&self, word: &str, span: Span) -> Result<Carrier, EvalError> {
        self.config
            .carrier
            .ok_or_else(|| refuse(word, "this node has no wire to carry a process", span))
    }

    fn evictable(&self, pid: Pid) -> Result<(), String> {
        let st = self.st();
        let info = st
            .info
            .get(&pid)
            .filter(|i| i.live)
            .ok_or_else(|| format!("no process {}", pid.0))?;
        match info.kind {
            Kind::Server | Kind::Plain => {}
            Kind::Root => {
                return Err(format!(
                    "process {} is the program: the door runs it on its own evaluator, the \
                     tree-walker under `blue run`, which this node does not hold, so it has no \
                     frames to carry; spawn the work as a process and evict that",
                    pid.0
                ))
            }
            Kind::Supervisor(_) => {
                return Err(format!(
                    "process {} is a supervisor: it runs no code of its own to carry; evict its \
                     children one at a time",
                    pid.0
                ))
            }
        }
        if st.held_at_boundary(pid) {
            return Err(format!("process {} is already being moved", pid.0));
        }
        drop(st);
        self.reachable_links(pid)
    }

    fn reachable_links(&self, pid: Pid) -> Result<(), String> {
        let st = self.st();
        let deaf: Vec<String> = st
            .info
            .get(&pid)
            .map(|i| i.links.iter())
            .into_iter()
            .flatten()
            .filter(|l| !st.info.get(l).is_some_and(|i| i.trap_exit))
            .map(|l| l.0.to_string())
            .collect();
        if deaf.is_empty() {
            return Ok(());
        }
        Err(format!(
            "process {} is linked to {}, which does not trap exits; a link cannot follow a \
             process to another node, so evict breaks it and tells each partner [:exit, {}, \
             :{EVICTED}], which a partner hears only when it traps exits: unlink it first, or \
             trap exits in the partner",
            pid.0,
            deaf.join(", "),
            pid.0
        ))
    }

    fn evict(
        &self,
        pid: Pid,
        wire: &Value,
        peer: &Value,
        loopback: bool,
        span: Span,
    ) -> Result<Value, EvalError> {
        let word = "evict";
        let carrier = self.carrier(word, span)?;
        self.evictable(pid).map_err(|m| refuse(word, m, span))?;
        self.st().evicting.insert(pid);
        let parked = self.drive(
            |st| {
                let info = st.info.get(&pid).filter(|i| i.live);
                let boundary = match (info.map(|i| &i.kind), st.waits.get(&pid)) {
                    (None, _) => return Some(false),
                    (Some(Kind::Server), Some(Wait::ServerNext))
                    | (Some(Kind::Plain), Some(Wait::Receive { .. })) => true,
                    _ => false,
                };
                (boundary && !st.aloft.contains(&pid)).then_some(true)
            },
            None,
            word,
            span,
        );
        let moved = match parked {
            Ok(Driven::Done(true)) => self.depart_over(pid, wire, peer, loopback, carrier),
            Ok(Driven::Done(false)) => Err(format!(
                "process {} exited before it reached a message boundary",
                pid.0
            )),
            Ok(Driven::Deadlock(_) | Driven::TimedOut) => Err(format!(
                "process {} is waiting {} and nothing can wake it, so it never reached a message \
                 boundary",
                pid.0,
                match self.st().info.get(&pid).map(|i| &i.kind) {
                    Some(Kind::Plain) => "outside receive",
                    _ => "inside its handler",
                }
            )),
            Err(e) => {
                self.st().evicting.remove(&pid);
                return Err(e);
            }
        };
        self.st().evicting.remove(&pid);
        moved.map_err(|m| refuse(word, m, span))
    }

    fn image_of(&self, pid: Pid) -> Result<Image, String> {
        let state = lock(&self.sched)
            .iter()
            .find(|p| p.pid == pid)
            .and_then(|p| p.interp.lookup_global("%state"))
            .unwrap_or(Value::Nil);
        let state = copy_data(&state).map_err(|kind| {
            format!(
                "process {}'s state holds a {kind}, which is not data and does not cross a wire",
                pid.0
            )
        })?;
        let st = self.st();
        let info = st.info.get(&pid).ok_or("the process is gone")?;
        let plain = matches!(info.kind, Kind::Plain);
        let mut code = info.code.clone();
        if !plain {
            code.bind("%state", state);
        }
        let supervision = match info.sup.and_then(|s| st.info.get(&s)).map(|s| &s.kind) {
            Some(Kind::Supervisor(spec)) => Some(Supervision {
                max_restarts: spec.max_restarts,
                restarts: info.restarts,
                initial: info.initial.clone().unwrap_or(Value::Nil),
            }),
            _ => None,
        };
        let tape = st
            .tapes
            .get(&pid)
            .filter(|t| plain && !t.truncated)
            .map(|t| t.entries.clone());
        let input_root = (!plain && self.config.frame.is_some())
            .then(|| {
                st.accounts
                    .get(&pid)
                    .and_then(|b| b.input_root.clone())
                    .or_else(|| {
                        self.config
                            .state_root
                            .zip(info.entered.as_ref())
                            .map(|(root, entered)| root(entered))
                    })
            })
            .flatten();
        let carries = if plain {
            tape.is_some()
        } else {
            input_root.is_some()
        };
        let account = self
            .config
            .frame
            .as_ref()
            .filter(|_| carries)
            .map(|_| Account {
                host_io: self.config.host_io.of(pid),
                journal: self.config.journals().then(|| {
                    st.journals
                        .get(&pid)
                        .map(|r| r.iter().cloned().collect())
                        .unwrap_or_default()
                }),
                input_root,
            });
        let mut image = Image {
            definition: info.def_name.clone(),
            scheduling: info.scheduling,
            trap_exit: info.trap_exit,
            code,
            mailbox: st
                .boxes
                .get(&pid)
                .map(|b| b.iter().cloned().collect())
                .unwrap_or_default(),
            supervision,
            dispatch_steps: info.asked,
            parked: None,
            tape,
            account,
        };
        drop(st);
        if plain {
            image.parked = Some(self.continuation(pid)?);
        }
        Ok(image)
    }

    fn continuation(&self, pid: Pid) -> Result<Continuation, String> {
        let sched = lock(&self.sched);
        let p = sched
            .iter()
            .find(|p| p.pid == pid)
            .ok_or("the process is gone")?;
        let mut st = self.st();
        let now = st.clock.now();
        let wait_ms = match st.waits.get(&pid) {
            Some(Wait::Receive {
                deadline: Some(d), ..
            }) => Some(d.saturating_sub(now)),
            _ => None,
        };
        let info = st.info.get(&pid).ok_or("the process is gone")?;
        let cannot = |why: String| format!("process {} cannot move: {why}", pid.0);
        if !info
            .chunk
            .as_ref()
            .is_some_and(|c| Arc::ptr_eq(c, &p.chunk))
        {
            return Err(cannot(
                "a migration replaced its code, and its frames still run the code it had \
                 before, which its image does not carry; let it restart or finish first"
                    .to_string(),
            ));
        }
        let vm = p.vm.parked(&p.chunk).map_err(|e| cannot(parking(&e)))?;
        let functions = info
            .code
            .defs
            .iter()
            .filter_map(defined_key)
            .map(|name| {
                let index = match p.interp.lookup_global(name) {
                    Some(Value::Foreign(any)) => any
                        .downcast_ref::<CompiledClosure>()
                        .filter(|c| {
                            c.captures.is_empty()
                                && (Arc::ptr_eq(&c.chunk, &p.chunk)
                                    || c.chunk.fingerprint() == p.chunk.fingerprint())
                        })
                        .map(|c| c.fn_index),
                    _ => None,
                };
                index.map(|i| (name.to_string(), i)).ok_or_else(|| {
                    cannot(format!(
                        "its global `{name}` is not the function its code defines"
                    ))
                })
            })
            .collect::<Result<_, _>>()?;
        Ok(Continuation {
            vm,
            functions,
            wait_ms,
        })
    }

    fn resume(&self, pid: Pid, c: &Continuation, tape: Tape) -> Result<(), String> {
        let mut st = self.st();
        let p = st
            .pending
            .iter_mut()
            .find(|p| p.pid == pid)
            .ok_or("the process is gone")?;
        for (name, index) in &c.functions {
            let body = FnRef::Table(*index)
                .resolve(&p.chunk)
                .filter(|f| f.captures.is_empty())
                .ok_or_else(|| {
                    format!(
                        "its function `{name}` names entry {index}, which its code does not define"
                    )
                })?;
            let function = CompiledClosure {
                body: Arc::new(body.clone()),
                captures: Vec::new(),
                chunk: Arc::clone(&p.chunk),
                globals: p.interp.globals_snapshot().clone(),
                fn_index: *index,
            };
            p.interp
                .define_global(name.as_str(), Value::Foreign(Arc::new(function)));
        }
        p.vm = Vm::from_parked(&c.vm, &p.chunk, &p.interp, self.config.budget)
            .map_err(|e| parking(&e))?;
        if let Some(ms) = c.wait_ms {
            let deadline = st.clock.now().saturating_add(ms);
            st.waits.insert(
                pid,
                Wait::Receive {
                    pattern: kw(pattern::WILDCARD),
                    deadline: Some(deadline),
                    bound: None,
                },
            );
        }
        st.tapes.insert(pid, tape);
        Ok(())
    }

    fn depart_over(
        &self,
        pid: Pid,
        wire: &Value,
        peer: &Value,
        loopback: bool,
        carrier: Carrier,
    ) -> Result<Value, String> {
        let image = self.image_of(pid)?;
        let queue = |image: &Image| -> Result<(String, usize, usize), String> {
            let text = image.text();
            let id = image::id_of(&text);
            let frames = image::frames(&id, &text, carrier.room)?;
            self.reachable_links(pid)?;
            let bytes = (carrier.queue)(wire, peer, &frames, loopback)?;
            Ok((id, frames.len(), bytes))
        };
        let (id, frames, bytes) = match queue(&image) {
            Err(_) if image.tape.is_some() || image.account.is_some() => queue(&Image {
                tape: None,
                account: None,
                ..image
            }),
            queued => queued,
        }?;
        self.depart(pid);
        Ok(record(&[
            ("image", Value::Str(Arc::from(format!("b3:{id}")))),
            ("frames", int(frames)),
            ("bytes", int(bytes)),
        ]))
    }

    fn depart(&self, pid: Pid) {
        lock(&self.sched).retain(|p| p.pid != pid);
        lock(&self.lanes).remove(&pid);
        let mut st = self.st();
        let (monitors, links, sup) = st
            .info
            .get_mut(&pid)
            .map(|i| {
                (
                    std::mem::take(&mut i.monitors),
                    std::mem::take(&mut i.links),
                    i.sup,
                )
            })
            .unwrap_or_default();
        for (r, watcher) in monitors {
            st.deliver(
                watcher,
                Value::list([kw("down"), int(r), int(pid.0), kw(EVICTED)]),
            );
        }
        for l in links {
            let trapping = st.info.get_mut(&l).is_some_and(|i| {
                i.links.remove(&pid);
                i.trap_exit
            });
            if trapping {
                st.deliver(l, Value::list([kw("exit"), int(pid.0), kw(EVICTED)]));
            }
        }
        if let Some(s) = sup {
            st.drop_child(s, pid);
        }
        st.forget(pid);
        drop(st);
        self.config.host_io.take(pid);
    }

    fn accept(
        &self,
        wire: &Value,
        timeout: Duration,
        loopback: bool,
        span: Span,
    ) -> Result<Value, EvalError> {
        let word = "accept";
        let carrier = self.carrier(word, span)?;
        let deadline = Instant::now() + timeout;
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            let frames = (carrier.take)(wire, image::FRAME, left, loopback)
                .map_err(|m| refuse(word, m, span))?;
            let (done, flaw) = {
                let mut st = self.st();
                let mut flaw = None;
                for f in &frames {
                    if let Err(why) = st.arrivals.file(f) {
                        flaw.get_or_insert(why);
                    }
                }
                (st.arrivals.complete(), flaw)
            };
            match (done, flaw) {
                (Some(Ok(text)), _) => return self.admit(&text, span),
                (Some(Err(why)), _) | (None, Some(why)) => {
                    return Err(raised("decode_error", why, Value::Nil, span))
                }
                (None, None) if frames.is_empty() => return Ok(Value::Nil),
                (None, None) => {}
            }
        }
    }

    fn admit(&self, text: &str, span: Span) -> Result<Value, EvalError> {
        let (parsed, _) = self.apart(|| Image::parse(text));
        let mut image = parsed.map_err(|why| raised("decode_error", why, Value::Nil, span))?;
        let parked = image.parked.take();
        let id = image::id_of(text);
        let tape = Tape::arrived(image.tape.take(), &id);
        let account = image.account.take();
        let state = bound_state(&image.code);
        let handed = image.supervision.take();
        if let (Some(s), None) = (&handed, &parked) {
            image.code.bind("%state", s.initial.clone());
        }
        let sup = handed
            .as_ref()
            .map(|s| self.st().supervisor(Strategy::OneForOne, s.max_restarts));
        let started = self.start(
            image.code,
            if parked.is_some() {
                Kind::Plain
            } else {
                Kind::Server
            },
            image.definition,
            sup,
            image.scheduling,
        );
        let resumed = started.and_then(|pid| match &parked {
            Some(c) => self
                .apart(|| self.resume(pid, c, tape))
                .0
                .map(|()| pid)
                .map_err(|why| {
                    let mut st = self.st();
                    st.pending.retain(|p| p.pid != pid);
                    st.forget(pid);
                    format!("the image cannot resume here: {why}")
                }),
            None => Ok(pid),
        });
        let pid = match resumed {
            Ok(pid) => pid,
            Err(m) => {
                if let Some(sup) = sup {
                    self.st().forget(sup);
                }
                return Err(refuse("accept", m, span));
            }
        };
        if let (Some(sup), Some(s)) = (sup, &handed) {
            let mut st = self.st();
            st.enrol(sup, pid);
            if parked.is_none() {
                if let Some(p) = st.pending.iter_mut().find(|p| p.pid == pid) {
                    p.interp.define_global("%state", state.clone());
                }
            }
            if let Some(i) = st.info.get_mut(&pid) {
                i.restarts = s.restarts;
                if parked.is_none() {
                    i.snapshot = Some(state.clone());
                    i.entered = Some(state);
                }
            }
        }
        let (mailbox, bytes) = self.apart(|| {
            image
                .mailbox
                .iter()
                .filter_map(|m| copy_data(m).ok())
                .collect::<VecDeque<_>>()
        });
        {
            let mut st = self.st();
            if let Some(i) = st.info.get_mut(&pid) {
                i.trap_exit = image.trap_exit;
                i.ask_dispatch(image.dispatch_steps);
            }
            st.boxes.insert(pid, mailbox);
        }
        self.credit(pid, bytes);
        if let Some(a) = account {
            self.brought(pid, a, &id);
        }
        Ok(int(pid.0))
    }

    fn brought(&self, pid: Pid, account: Account, image: &str) {
        if self.config.frame.is_none() {
            return;
        }
        let journal: Option<Vec<Value>> =
            account.journal.filter(|_| self.config.journals()).map(|j| {
                let skip = j.len().saturating_sub(self.config.journal);
                j.into_iter().skip(skip).collect()
            });
        let mark = CarriedAccount::of(journal.as_deref(), account.host_io, image);
        self.config.host_io.carry(pid, account.host_io);
        let mut st = self.st();
        if let Some(j) = journal {
            st.journals.insert(pid, j.into());
        }
        st.accounts.insert(
            pid,
            Brought {
                mark,
                input_root: account.input_root,
            },
        );
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
            carried: tape.carried,
            carried_account: st.accounts.get(&pid).map(|b| b.mark.clone()),
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
        let proc = sched.iter().find(|p| p.pid == pid);
        let steps = proc
            .filter(|_| self.config.count_steps)
            .map(|p| u64::try_from(p.vm.burned()).unwrap_or(u64::MAX));
        let brought = st.accounts.get(&pid);
        let roots = match (&info.kind, self.config.state_root, &info.entered) {
            (Kind::Server, Some(root), Some(entered)) => {
                let left = proc
                    .and_then(|p| p.interp.lookup_global("%state"))
                    .or_else(|| info.snapshot.clone())
                    .unwrap_or(Value::Nil);
                Some(Roots {
                    input: brought
                        .and_then(|b| b.input_root.clone())
                        .unwrap_or_else(|| root(entered)),
                    output: root(&left),
                })
            }
            _ => None,
        };
        let carried = brought.map(|b| CarriedIo {
            image: b.mark.image.clone(),
            host_io: b.mark.host_io,
            input_root: b.input_root.clone().filter(|_| roots.is_some()),
        });
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
            steps,
            carried,
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
        let driving = self.driving();
        let (driven, _) = self.apart(|| self.drive_unmetered(goal, deadline, word, span));
        drop(driving);
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
                st.fire_timers();
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
            if self.land(&mut sched) {
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
            let aloft = {
                let mut st = self.st();
                let now = st.clock.now();
                (!st.aloft.is_empty()).then(|| match st.clock.kind {
                    ClockKind::Real => next.map(|t| Duration::from_millis(t.saturating_sub(now))),
                    ClockKind::Virtual => None,
                })
            };
            if let Some(limit) = aloft {
                self.await_flight(&mut sched, limit);
                continue;
            }
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
        let (now, bound) = {
            let mut st = self.st();
            (st.clock.now(), st.bound_of(ROOT))
        };
        let deadline = timeout.map(|t| now.saturating_add(t));
        let driven = self.drive(
            |st| {
                let b = st.boxes.get_mut(&ROOT)?;
                let i = pattern::first_match(b, &pattern)?;
                b.remove(i)
            },
            earliest(deadline, bound),
            "receive",
            span,
        )?;
        match driven {
            Driven::Done(msg) => Ok(msg),
            Driven::TimedOut => {
                let now = self.st().clock.now();
                if bound_fired(bound, deadline, now) {
                    Err(passed("receive", bound.unwrap_or(now), now, span))
                } else {
                    Ok(default)
                }
            }
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

    fn sleep_root(&self, word: &str, until: u64, span: Span) -> Result<Value, EvalError> {
        let bound = self.st().bound_of(ROOT);
        let driven = self.drive(|_| None::<()>, earliest(Some(until), bound), word, span)?;
        let now = self.st().clock.now();
        match driven {
            Driven::TimedOut if bound_fired(bound, Some(until), now) => {
                Err(passed(word, bound.unwrap_or(now), now, span))
            }
            _ => Ok(Value::Nil),
        }
    }

    fn bind_deadline(&self, pid: Pid, deadline: Option<u64>) {
        if let Some(info) = self.st().info.get_mut(&pid) {
            info.deadline = deadline;
        }
    }

    #[must_use]
    pub fn now(&self) -> u64 {
        self.st().clock.now()
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
        let sched = lock(&self.sched).len();
        let st = self.st();
        sched + st.pending.len() + st.aloft.len()
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

fn bound_state(code: &Code) -> Value {
    code.bindings
        .iter()
        .find(|(n, _)| &**n == "%state")
        .map_or(Value::Nil, |(_, v)| v.clone())
}

fn record(fields: &[(&str, Value)]) -> Value {
    Value::map(
        fields
            .iter()
            .map(|(k, v)| (MapKey::Keyword(Arc::from(*k)), v.clone())),
    )
}

const DISPATCH_OPTION: &str = "dispatch_steps";

const SPAWN_OPTIONS: &[&str] = &[scheduling::OPTION];

const SERVER_OPTIONS: &[&str] = &[scheduling::OPTION, DISPATCH_OPTION];

#[derive(Clone, Copy, Debug, Default)]
struct Opts {
    scheduling: Scheduling,
    dispatch_steps: Option<usize>,
}

fn dispatch_steps(v: &Value, span: Span) -> Result<usize, EvalError> {
    match v {
        Value::Int(n) if *n > 0 => Ok(usize::try_from(*n).unwrap_or(usize::MAX)),
        other => Err(raised(
            "bad_option",
            format!(
                "{DISPATCH_OPTION} is a positive integer, got {}",
                match other {
                    Value::Int(n) => n.to_string(),
                    other => other.type_name().to_string(),
                }
            ),
            Value::Nil,
            span,
        )),
    }
}

fn spawn_opts(
    v: Option<&Value>,
    word: &str,
    takes: &[&str],
    span: Span,
) -> Result<Opts, EvalError> {
    let m = match v {
        None | Some(Value::Nil) => return Ok(Opts::default()),
        Some(Value::Map(m)) => m,
        Some(other) => {
            return Err(raised(
                "bad_option",
                format!(
                    "{word}'s options are a map {{{}: …}}, got {}",
                    scheduling::OPTION,
                    other.type_name()
                ),
                Value::Nil,
                span,
            ))
        }
    };
    let mut opts = Opts::default();
    for (k, val) in m.iter() {
        let key = match k {
            MapKey::Keyword(s) | MapKey::Symbol(s) | MapKey::Str(s) => {
                s.trim_start_matches(':').to_string()
            }
            other => other.to_value().to_string(),
        };
        if !takes.contains(&key.as_str()) {
            let named: Vec<String> = takes.iter().map(|t| format!("{t}:")).collect();
            return Err(raised(
                "bad_option",
                format!("{word} takes {}, got {key}:", named.join(" or ")),
                Value::Nil,
                span,
            ));
        }
        if key == DISPATCH_OPTION {
            opts.dispatch_steps = Some(dispatch_steps(val, span)?);
            continue;
        }
        opts.scheduling = match val {
            Value::Keyword(w) => Scheduling::named(w),
            other => Err(scheduling::Refusal::Unknown(format!(
                "a {}",
                other.type_name()
            ))),
        }
        .map_err(|r| raised(r.kind(), r.to_string(), Value::Nil, span))?;
    }
    Ok(opts)
}

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
    scheduling: Scheduling,
) -> Result<Pid, EvalError> {
    let (code, entry) = code::spawn_code(f, args).map_err(|m| refuse(word, m, span))?;
    let def_name = match entry {
        Entry::Named(n) | Entry::Builtin(n) => Some(n),
        Entry::Lambda(_) => None,
    };
    node.start(code, Kind::Plain, def_name, sup, scheduling)
        .map_err(|m| refuse(word, m, span))
}

fn w_spawn(node: &Node, _who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let a = spawn_args(args, "spawn", span)?;
    let class = spawn_opts(args.get(2), "spawn", SPAWN_OPTIONS, span)?.scheduling;
    Ok(int(spawn_one(
        node, &args[0], &a, None, "spawn", span, class,
    )?
    .0))
}

fn w_spawn_link(node: &Node, who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let a = spawn_args(args, "spawn_link", span)?;
    let class = spawn_opts(args.get(2), "spawn_link", SPAWN_OPTIONS, span)?.scheduling;
    let pid = spawn_one(node, &args[0], &a, None, "spawn_link", span, class)?;
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
    let opts = spawn_opts(args.get(2), "spawn_server", SERVER_OPTIONS, span)?;
    Ok(int(server(
        node,
        &args[0],
        &args[1],
        None,
        "spawn_server",
        span,
        opts,
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
    opts: Opts,
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
    let pid = node
        .start(
            code,
            Kind::Server,
            code::name_of(handler),
            sup,
            opts.scheduling,
        )
        .map_err(|m| refuse(word, m, span))?;
    if let Some(info) = node.st().info.get_mut(&pid) {
        info.ask_dispatch(opts.dispatch_steps);
    }
    Ok(pid)
}

fn w_evict(node: &Node, who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    node.tally();
    evicting(node, who, args, false, span)
}

fn w_evict_provided(node: &Node, who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    evicting(node, who, args, true, span)
}

fn evicting(
    node: &Node,
    who: Who,
    args: &[Value],
    loopback: bool,
    span: Span,
) -> Result<Value, EvalError> {
    if who != Who::Root {
        return Err(refuse(
            "evict",
            "evict waits for the process to reach a message boundary, and only the program \
             waits; a process asks the program to evict",
            span,
        ));
    }
    let pid = pid_arg(&args[0], "evict", span)?;
    node.evict(pid, &args[1], &args[2], loopback, span)
}

fn w_accept(node: &Node, _who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    node.tally();
    accepting(node, args, false, span)
}

fn w_accept_provided(
    node: &Node,
    _who: Who,
    args: &[Value],
    span: Span,
) -> Result<Value, EvalError> {
    accepting(node, args, true, span)
}

fn accepting(node: &Node, args: &[Value], loopback: bool, span: Span) -> Result<Value, EvalError> {
    let timeout = match &args[1] {
        Value::Int(n) if *n >= 0 => Duration::from_millis(n.unsigned_abs()),
        other => {
            return Err(refuse(
                "accept",
                format!(
                    "the timeout is milliseconds (an Int >= 0), got {}",
                    other.type_name()
                ),
                span,
            ))
        }
    };
    node.accept(&args[0], timeout, loopback, span)
}

fn w_uncarried(_node: &Node, _who: Who, _args: &[Value], span: Span) -> Result<Value, EvalError> {
    Err(refuse(
        "evict",
        "this node has no wire to carry a process",
        span,
    ))
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

fn w_scoped_in_process(
    _node: &Node,
    _who: Who,
    _args: &[Value],
    span: Span,
) -> Result<Value, EvalError> {
    Err(refuse(
        "deadline",
        "a process holds the deadline it was spawned under; narrowing it inside a process is \
         async phase A2 (docs/ASYNC.md)",
        span,
    ))
}

fn w_node_time(node: &Node, _who: Who, _args: &[Value], _span: Span) -> Result<Value, EvalError> {
    Ok(int(node.now()))
}

fn w_after(node: &Node, who: Who, args: &[Value], span: Span) -> Result<Value, EvalError> {
    let at = wake_at(node, "after", &args[0], true, span)?;
    let to = match args.get(2) {
        Some(p) => pid_arg(p, "after", span)?,
        None => who.pid(),
    };
    let (copied, bytes) = node.apart(|| copy_data(&args[1]));
    let msg = copied.map_err(|kind| {
        refuse(
            "after",
            format!("a message is copied to the receiver, and a {kind} is not data"),
            span,
        )
    })?;
    let timer = {
        let mut st = node.st();
        let seq = st.next_timer;
        st.next_timer += 1;
        st.timers.insert((at, seq), (to, msg));
        seq
    };
    node.credit(to, bytes);
    Ok(int(timer))
}

fn w_context(node: &Node, who: Who, _args: &[Value], _span: Span) -> Result<Value, EvalError> {
    let st = node.st();
    let deadline = st.bound_of(who.pid());
    Ok(record(&[
        ("clock", kw(st.clock.kind.label())),
        ("deadline", deadline.map_or(Value::Nil, int)),
    ]))
}

fn w_remaining(node: &Node, who: Who, _args: &[Value], _span: Span) -> Result<Value, EvalError> {
    let mut st = node.st();
    let now = st.clock.now();
    Ok(st
        .bound_of(who.pid())
        .map_or(Value::Nil, |d| int(d.saturating_sub(now))))
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
    let sup = node.st().supervisor(strategy, max_restarts);
    for spec in specs.iter() {
        let pid = match spec {
            // `[:server, handler, state]`: a supervised spawn_server.
            Value::List(t) if (3..=4).contains(&t.len()) && is_keyword(&t[0], "server") => server(
                node,
                &t[1],
                &t[2],
                Some(sup),
                "supervisor",
                span,
                spawn_opts(t.get(3), "supervisor", SERVER_OPTIONS, span)?,
            )?,
            Value::List(pair) if pair.len() == 2 && code::is_function(&pair[0]) => {
                let Value::List(a) = &pair[1] else {
                    return Err(refuse(
                        "supervisor",
                        "a child [f, args] takes its args as a list",
                        span,
                    ));
                };
                let a: Vec<Value> = a.iter().cloned().collect();
                spawn_one(
                    node,
                    &pair[0],
                    &a,
                    Some(sup),
                    "supervisor",
                    span,
                    Scheduling::Normal,
                )?
            }
            f => spawn_one(
                node,
                f,
                &[],
                Some(sup),
                "supervisor",
                span,
                Scheduling::Normal,
            )?,
        };
        node.st().enrol(sup, pid);
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
