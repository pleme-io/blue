//! Automatic memoization of pure definitions (`theory/BLUE-TOOLING.md` T-M).
//!
//! A call of a definition [`crate::reach`] proves pure is answered by its
//! key when the key was answered before:
//!
//! ```text
//! key   = def_hash(definition) ++ canonical(arguments)     in process
//!       = BLAKE3(that)                                      on disk
//! value = canonical(result)
//! ```
//!
//! The `def_hash` is the definition's resolved tree with every callee's hash
//! inside it ([`crate::def_hash`]), so an edit anywhere a definition reaches
//! changes its key and nothing goes stale; the arguments' encoding
//! ([`crate::canon`]) is the value itself, never its address. A call whose
//! arguments or result have no encoding (a function, a foreign handle) is
//! not cached.
//!
//! [`Recall`] is a `CallObserver` on the evaluator's one call hook
//! (`blue_lang_runtime::observe`): `enter` answers a hit without running the
//! body, `leave` stores what a miss returned. It wraps the observer a tool
//! already installed (the profiler), which sees every call, answered or not.
//!
//! **What is worth caching** ([`Policy`]). A result is stored only when
//! computing it took at least [`Policy::store_min`]: below that, a lookup
//! costs about what the call does, and storing only fills the table and the
//! disk. A definition whose first [`Policy::window`] calls produced no hit
//! and stored nothing stops being looked up for the rest of the run, so a
//! cheap pure helper called with fresh arguments a million times pays for
//! the key of its first calls only.
//!
//! **A tail call** leaves its activation without a value of its own: the
//! callee that replaces it returns the value of both. The first activation of
//! a chain of tail calls waits for the chain's value and is stored with it;
//! the activations in between are not, since only the first is what a caller
//! asked for.
//!
//! Every hit decodes a fresh value, so a cached answer is as unshared as a
//! computed one (`eq?` on lists compares identity).

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, PoisonError};
use std::time::{Duration, Instant};

use blue_lang_runtime::observe::{Call, CallObserver, Definitions, Exit};
use blue_lang_syntax::{Span, Spanned};
use tatara_lisp_eval::Value;

use crate::def_hash::{hash_program, DefKind};
use crate::reach::{reach_program, Volatility};
use crate::store::{Bucket, Store};
use crate::{canon, DefHash};

/// When a result is worth keeping.
#[derive(Clone, Copy, Debug)]
pub struct Policy {
    /// The least a call must have cost for its result to be stored.
    pub store_min: Duration,
    /// Calls a definition gets to produce a hit or a stored result before
    /// it stops being looked up.
    pub window: u64,
    /// The in-process table's bound on stored bytes; past it, nothing more
    /// is stored this run.
    pub table_bytes: usize,
}

impl Default for Policy {
    /// Measured (release, `tests/memo.rs`'s `measure_the_cost_of_a_lookup`,
    /// 2026-10-11): a lookup that misses adds about 180 ns to a call with one
    /// small argument, and a hit costs about what a one-line call does
    /// (~200 ns). A result that took 5 µs is therefore some 25 lookups: a
    /// hit saves at least 96% of it, while results cheaper than that would
    /// fill the table and the disk for little. After a definition retires,
    /// the memo costs every call about 14 ns, and the 256 calls it took to
    /// retire cost about 46 µs once.
    fn default() -> Self {
        Self {
            store_min: Duration::from_micros(5),
            window: 256,
            table_bytes: 256 << 20,
        }
    }
}

/// What the memo may cache in one program: per definition of
/// `blue_lang_runtime::observe::Definitions`, its hash when it is a pure
/// function, else why not.
#[derive(Clone, Debug, Default)]
pub struct Plan {
    targets: Vec<Result<DefHash, Refused>>,
    /// Each cacheable definition by the span its closure carries (the
    /// `define`, or the `lambda` a value definition binds) and its name.
    by_source: HashMap<Span, (usize, Option<String>), BuildMix>,
}

/// The hasher of the per-call lookup, which every closure call pays: two
/// offsets mixed with one multiply each (FxHash's step), not SipHash's
/// rounds. Spans are not attacker-chosen keys.
#[derive(Clone, Copy, Debug, Default)]
struct BuildMix;

impl std::hash::BuildHasher for BuildMix {
    type Hasher = Mix;
    fn build_hasher(&self) -> Mix {
        Mix(0)
    }
}

struct Mix(u64);

impl std::hash::Hasher for Mix {
    fn finish(&self) -> u64 {
        self.0
    }
    fn write(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.write_u64(u64::from(*b));
        }
    }
    fn write_u64(&mut self, n: u64) {
        self.0 = (self.0.rotate_left(5) ^ n).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
    }
    fn write_usize(&mut self, n: usize) {
        self.write_u64(n as u64);
    }
}

/// Why a definition is not cached.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Refused {
    Volatile(Volatility),
    /// The runtime's definition is not the one the hash was computed for.
    Unmatched,
}

impl Plan {
    /// Plan for a program, given the tree before erasure (what `def_hash`
    /// reads) and after it (what runs, which `reach` reads), one form per
    /// top-level form of the program `defs` was read from.
    #[must_use]
    pub fn of(defs: &Definitions, lowered: &[Spanned], erased: &[Spanned]) -> Self {
        let hashes = hash_program(lowered);
        let reach = reach_program(erased, &hashes);
        let index: HashMap<usize, usize> = hashes
            .defs()
            .iter()
            .enumerate()
            .map(|(i, d)| (d.top_level, i))
            .collect();
        let targets: Vec<Result<DefHash, Refused>> = defs
            .iter()
            .map(|d| {
                let Some(&h) = index.get(&d.top_level) else {
                    return Err(Refused::Unmatched);
                };
                let hashed = &hashes.defs()[h];
                if hashed.key != *d.key || hashed.kind != DefKind::Function {
                    return Err(Refused::Unmatched);
                }
                match &reach[h] {
                    crate::Reach::Pure => Ok(hashed.hash),
                    crate::Reach::Volatile(v) => Err(Refused::Volatile(v.clone())),
                }
            })
            .collect();
        let mut by_source = HashMap::with_hasher(BuildMix);
        for (i, d) in defs.iter().enumerate() {
            if targets[i].is_err() {
                continue;
            }
            let Some(items) = erased.get(d.top_level).and_then(Spanned::as_list) else {
                continue;
            };
            let source = match items.get(1).and_then(Spanned::as_symbol) {
                Some(_) => items.get(2).map(|l| (l.span, None)),
                None => Some((d.span, Some(d.key.to_string()))),
            };
            if let Some((span, name)) = source {
                by_source.insert(span, (i, name));
            }
        }
        Self { targets, by_source }
    }

    /// The cacheable definition an activation is a call of, and its hash.
    fn of_call(&self, call: &Call<'_>) -> Option<(usize, DefHash)> {
        let (d, name) = self.by_source.get(&call.source)?;
        if name.as_deref() != call.name.map(|n| &**n) {
            return None;
        }
        match self.targets.get(*d)? {
            Ok(h) => Some((*d, *h)),
            Err(_) => None,
        }
    }

    /// The hash a definition is cached under, or why it is not.
    #[must_use]
    pub fn target(&self, definition: usize) -> Option<&Result<DefHash, Refused>> {
        self.targets.get(definition)
    }
}

/// One definition's counts.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Counts {
    /// Calls the memo saw.
    pub calls: u64,
    /// Answered from the in-process table.
    pub hits: u64,
    /// Answered from the disk.
    pub disk_hits: u64,
    /// Looked up and not found: the body ran.
    pub misses: u64,
    /// Results stored.
    pub stored: u64,
    /// Calls whose arguments or result had no encoding.
    pub unencodable: u64,
    /// What the answered calls cost when they were computed.
    pub saved: Duration,
    /// Time spent making keys.
    pub keying: Duration,
    /// It stopped being looked up ([`Policy::window`]).
    pub retired: bool,
}

/// One row of [`Recall::report`].
#[derive(Clone, Debug)]
pub struct Row {
    pub name: String,
    pub definition: usize,
    pub counts: Counts,
}

/// The whole memo after a run.
#[derive(Clone, Debug, Default)]
pub struct Report {
    /// Every cacheable definition that was called.
    pub rows: Vec<Row>,
    /// Entries skipped on disk because they were damaged.
    pub damaged: usize,
    /// Results not stored because the table was full.
    pub full: u64,
    /// The disk tier, when there is one.
    pub store: Option<String>,
}

impl Report {
    #[must_use]
    pub fn total(&self) -> Counts {
        let mut t = Counts::default();
        for r in &self.rows {
            let c = &r.counts;
            t.calls += c.calls;
            t.hits += c.hits;
            t.disk_hits += c.disk_hits;
            t.misses += c.misses;
            t.stored += c.stored;
            t.unencodable += c.unencodable;
            t.saved += c.saved;
            t.keying += c.keying;
        }
        t
    }
}

/// What [`Recall::flush`] did.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Flushed {
    pub written: usize,
    pub evicted: usize,
    /// The first write that failed, if one did: the run's results stand
    /// either way.
    pub error: Option<String>,
}

struct Probe {
    definition: usize,
    key: Box<[u8]>,
    start: Instant,
    /// Started inside another miss of the same definition.
    nested: bool,
}

/// One activation the memo saw enter.
struct Frame {
    /// How many activations deep it entered: the one `leave` at the same
    /// depth is its own.
    depth: usize,
    /// A miss of a cacheable definition: stored when it returns.
    probe: Option<Probe>,
    /// The first activation of the tail-call chain this one ends, waiting
    /// for its value.
    chain: Option<Probe>,
}

struct Entry {
    definition: usize,
    value: Arc<[u8]>,
    cost: Duration,
    /// On disk, or queued to be.
    persisted: bool,
}

#[derive(Default)]
struct State {
    stack: Vec<Frame>,
    /// A chain head waiting for the callee its last activation tail-called.
    pending: Option<Probe>,
    table: HashMap<Box<[u8]>, Entry>,
    table_bytes: usize,
    counts: Vec<Counts>,
    /// Misses of each definition still waiting for their value: running, or
    /// the first call of a tail-call chain that has not ended.
    active: Vec<u32>,
    buckets: HashMap<usize, Bucket>,
    writes: Vec<(usize, [u8; 32], Duration, Vec<u8>)>,
    damaged: usize,
    full: u64,
}

/// The memo observer. See the module docs.
pub struct Recall {
    defs: Arc<Definitions>,
    plan: Plan,
    store: Option<Arc<Store>>,
    inner: Option<Arc<dyn CallObserver>>,
    policy: Policy,
    state: Mutex<State>,
    /// Activations entered and not yet left, every closure counted.
    depth: AtomicUsize,
    /// The depth of the innermost frame the memo keeps; 0 for none.
    top: AtomicUsize,
    /// A tail-call chain's first call is waiting for the next activation.
    carrying: AtomicBool,
    /// Per definition: it stopped being looked up.
    retired: Vec<AtomicBool>,
}

impl Recall {
    /// A memo over a program's definitions, with the disk tier `store` when
    /// there is one, wrapping `inner` when a tool already watches the run.
    #[must_use]
    pub fn new(
        defs: Arc<Definitions>,
        plan: Plan,
        store: Option<Arc<Store>>,
        inner: Option<Arc<dyn CallObserver>>,
        policy: Policy,
    ) -> Self {
        let state = State {
            counts: vec![Counts::default(); defs.len()],
            active: vec![0; defs.len()],
            ..State::default()
        };
        let retired = (0..defs.len()).map(|_| AtomicBool::new(false)).collect();
        Self {
            defs,
            plan,
            store,
            inner,
            policy,
            state: Mutex::new(state),
            depth: AtomicUsize::new(0),
            top: AtomicUsize::new(0),
            carrying: AtomicBool::new(false),
            retired,
        }
    }

    fn push(&self, st: &mut State, frame: Frame) {
        self.top.store(frame.depth, Ordering::Relaxed);
        st.stack.push(frame);
    }

    /// One of the memo's frames left.
    fn left(&self, st: &mut State, frame: Frame, exit: Exit<'_>) {
        match exit {
            Exit::Returned(v) | Exit::Supplied(v) => {
                let now = Instant::now();
                for p in [frame.probe, frame.chain].into_iter().flatten() {
                    done(st, &p);
                    self.store_result(st, p, v, now);
                }
            }
            Exit::TailCalled => {
                let head = match (frame.chain, frame.probe) {
                    (Some(head), probe) => {
                        if let Some(p) = probe {
                            done(st, &p);
                        }
                        Some(head)
                    }
                    (None, probe) => probe,
                };
                if head.is_some() {
                    self.carrying.store(true, Ordering::Relaxed);
                }
                st.pending = head;
            }
            Exit::Raised(_) => {
                for p in [frame.probe, frame.chain].into_iter().flatten() {
                    done(st, &p);
                }
            }
        }
    }

    fn state(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// The key of a call of `hash` with `args`, when every argument has an
    /// encoding.
    fn key(hash: &DefHash, args: &[Value]) -> Option<Box<[u8]>> {
        let mut key = Vec::with_capacity(48);
        key.extend_from_slice(hash.bytes());
        key.extend_from_slice(&(args.len() as u64).to_le_bytes());
        for a in args {
            if !canon::encode_into(a, &mut key) {
                return None;
            }
        }
        Some(key.into_boxed_slice())
    }

    /// A lookup: the in-process table, then the definition's file on disk.
    fn find(&self, st: &mut State, definition: usize, hash: &DefHash, key: &[u8]) -> Option<Value> {
        let persist = self.store.is_some();
        if let Some(e) = st.table.get_mut(key) {
            if let Some(v) = canon::decode(&e.value) {
                let cost = e.cost;
                let queue = (persist && !e.persisted).then(|| {
                    e.persisted = true;
                    (e.definition, e.value.to_vec())
                });
                if let Some((d, value)) = queue {
                    st.writes
                        .push((d, *blake3::hash(key).as_bytes(), cost, value));
                }
                let c = &mut st.counts[definition];
                c.hits += 1;
                c.saved += cost;
                return Some(v);
            }
        }
        let store = self.store.as_ref()?;
        let (found, damaged) = {
            let bucket = st
                .buckets
                .entry(definition)
                .or_insert_with(|| store.load(hash));
            (
                bucket.entries.get(blake3::hash(key).as_bytes()).cloned(),
                std::mem::take(&mut bucket.damaged),
            )
        };
        st.damaged += damaged;
        let stored = found?;
        let Some(v) = canon::decode(&stored.value) else {
            st.damaged += 1;
            return None;
        };
        let c = &mut st.counts[definition];
        c.disk_hits += 1;
        c.saved += stored.cost;
        st.table_bytes += stored.value.len() + key.len();
        st.table.insert(
            key.into(),
            Entry {
                definition,
                value: Arc::from(stored.value),
                cost: stored.cost,
                persisted: true,
            },
        );
        Some(v)
    }

    /// Keep what a miss returned. A miss inside a miss of the same
    /// definition (each level of a deep recursion) goes to disk only once it
    /// is asked for again: the outer result already answers a rerun, and a
    /// deep recursion would otherwise write one entry per level.
    fn store_result(&self, st: &mut State, probe: Probe, value: &Value, now: Instant) {
        let cost = now.saturating_duration_since(probe.start);
        if cost < self.policy.store_min {
            return;
        }
        let Some(bytes) = canon::encode(value) else {
            st.counts[probe.definition].unencodable += 1;
            return;
        };
        let size = bytes.len() + probe.key.len();
        if st.table_bytes + size > self.policy.table_bytes {
            st.full += 1;
            return;
        }
        st.table_bytes += size;
        st.counts[probe.definition].stored += 1;
        let persisted = self.store.is_some() && !probe.nested;
        if persisted {
            st.writes.push((
                probe.definition,
                *blake3::hash(&probe.key).as_bytes(),
                cost,
                bytes.clone(),
            ));
        }
        st.table.insert(
            probe.key,
            Entry {
                definition: probe.definition,
                value: Arc::from(bytes),
                cost,
                persisted,
            },
        );
    }

    /// Every cacheable definition that was called, with its counts.
    #[must_use]
    pub fn report(&self) -> Report {
        let st = self.state();
        let rows = st
            .counts
            .iter()
            .enumerate()
            .filter(|(_, c)| c.calls > 0)
            .map(|(i, c)| Row {
                name: self
                    .defs
                    .get(i)
                    .map_or_else(String::new, |d| d.name.clone()),
                definition: i,
                counts: c.clone(),
            })
            .collect();
        Report {
            rows,
            damaged: st.damaged,
            full: st.full,
            store: self.store.as_ref().map(|s| s.dir().display().to_string()),
        }
    }

    /// Why each definition is or is not cached.
    #[must_use]
    pub fn plan(&self) -> &Plan {
        &self.plan
    }

    /// Write what this run stored to disk, then hold the store under its
    /// bound. Nothing to write, no disk tier: nothing happens.
    pub fn flush(&self) -> Flushed {
        let mut out = Flushed::default();
        let Some(store) = &self.store else {
            return out;
        };
        let writes = std::mem::take(&mut self.state().writes);
        if writes.is_empty() {
            return out;
        }
        let mut by_def: HashMap<usize, Vec<([u8; 32], Duration, Vec<u8>)>> = HashMap::new();
        for (d, key, cost, value) in writes {
            by_def.entry(d).or_default().push((key, cost, value));
        }
        for (d, entries) in by_def {
            let Some(Ok(hash)) = self.plan.target(d) else {
                continue;
            };
            match store.append(hash, &entries) {
                Ok(n) => out.written += n,
                Err(e) => {
                    out.error.get_or_insert_with(|| e.to_string());
                }
            }
        }
        match store.evict() {
            Ok(n) => out.evicted = n,
            Err(e) => {
                out.error.get_or_insert_with(|| e.to_string());
            }
        }
        out
    }
}

/// A miss stops waiting for its value.
fn done(st: &mut State, probe: &Probe) {
    let a = &mut st.active[probe.definition];
    *a = a.saturating_sub(1);
}

/// A call the memo has no stake in takes no lock and keeps no frame: a frame
/// is kept only for a cacheable call, or to carry a tail-call chain's first
/// call to the callee that ends it.
impl CallObserver for Recall {
    fn enter(&self, call: &Call<'_>, args: &[Value]) -> Option<Value> {
        let answered = self.inner.as_ref().and_then(|i| i.enter(call, args));
        let depth = self.depth.fetch_add(1, Ordering::Relaxed) + 1;
        let target = self
            .plan
            .of_call(call)
            .filter(|&(d, _)| !self.retired[d].load(Ordering::Relaxed))
            .filter(|_| answered.is_none());
        if target.is_none() && !self.carrying.load(Ordering::Relaxed) {
            return answered;
        }
        let mut st = self.state();
        let chain = st.pending.take();
        self.carrying.store(false, Ordering::Relaxed);
        let mut frame = Frame {
            depth,
            probe: None,
            chain,
        };
        let Some((d, hash)) = target else {
            self.push(&mut st, frame);
            return answered;
        };
        let waiting = st.active[d];
        let c = &mut st.counts[d];
        c.calls += 1;
        if waiting == 0
            && c.calls > self.policy.window
            && c.hits + c.disk_hits == 0
            && c.stored == 0
        {
            c.retired = true;
            self.retired[d].store(true, Ordering::Relaxed);
            self.push(&mut st, frame);
            return None;
        }
        let started = Instant::now();
        let key = Self::key(&hash, args);
        st.counts[d].keying += started.elapsed();
        let Some(key) = key else {
            st.counts[d].unencodable += 1;
            self.push(&mut st, frame);
            return None;
        };
        if let Some(v) = self.find(&mut st, d, &hash, &key) {
            self.push(&mut st, frame);
            return Some(v);
        }
        st.counts[d].misses += 1;
        let nested = st.active[d] > 0;
        st.active[d] += 1;
        frame.probe = Some(Probe {
            definition: d,
            key,
            start: Instant::now(),
            nested,
        });
        self.push(&mut st, frame);
        None
    }

    fn leave(&self, call: &Call<'_>, exit: Exit<'_>) {
        let depth = self.depth.fetch_sub(1, Ordering::Relaxed);
        let ours = self.top.load(Ordering::Relaxed) == depth;
        if ours || self.carrying.load(Ordering::Relaxed) {
            let mut st = self.state();
            if let Some(stale) = st.pending.take() {
                done(&mut st, &stale);
            }
            self.carrying.store(false, Ordering::Relaxed);
            if ours {
                if let Some(frame) = st.stack.pop() {
                    self.top
                        .store(st.stack.last().map_or(0, |f| f.depth), Ordering::Relaxed);
                    self.left(&mut st, frame, exit);
                }
            }
        }
        if let Some(inner) = &self.inner {
            inner.leave(call, exit);
        }
    }
}
