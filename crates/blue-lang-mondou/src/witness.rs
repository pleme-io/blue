//! What a definition's executions showed: the blue type of every argument
//! and of the value returned, at every call that returned
//! (`theory/BLUE.md` §V.20, the blueshift).
//!
//! A loose definition runs with whatever it is given. [`Witness`] sits on the
//! evaluator's call hook (`blue_lang_runtime::observe`) and records, for every
//! loose top-level `def` a run calls, the [`Shape`] of each argument and of
//! the result: one [`Observation`] per distinct signature, keyed by the
//! definition's `def_hash` ([`crate::hash_checked`]). An edit anywhere the
//! definition reaches changes its hash, so what an older tree showed is
//! never read for a newer one.
//!
//! [`lock`] turns the observations into a typed signature only when they
//! agree: every position joins to one type `blue_lang_check::Ty` can spell.
//! `Ty` has no union and no number type (`Int` and `Float` are distinct, and
//! `accepts` is equality away from `dyn`), so the one join with a name is the
//! list's: an empty list belongs to every `List(T)`. Anything else, a value
//! no `Ty` names, or a list whose elements never showed a type, locks
//! nothing. `dyn` is not a join: it is the absence of a type, and writing it
//! would lock nothing.
//!
//! A call that raised is not recorded: a test that feeds a definition a bad
//! value to watch it fail shows what it refuses, not what it takes. The first
//! call of a chain of tail calls returns what the chain's last call returns,
//! and is recorded with that value.
//!
//! [`Witnesses`] keeps observations on disk between runs, in a [`Store`]
//! under [`default_root`]: `blue test` writes there and the language server
//! reads there, beside what its own live evaluation showed.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

use blue_lang_check::Ty;
use blue_lang_runtime::observe::{Call, CallObserver, Exit};
use blue_lang_runtime::pipeline::Checked;
use blue_lang_syntax::{Span, Spanned};
use tatara_lisp_eval::Value;

use crate::def_hash::{DefHashes, DefKind};
use crate::store::{Identity, Store};
use crate::DefHash;

/// Values one [`Shape::of`] reads before it answers [`Shape::Opaque`]: a list
/// longer than this shows no type rather than one read from its head.
pub const READ: usize = 4096;

/// Distinct observations kept per definition. Past it the definition is
/// recorded as varied ([`Observation::varied`]), which no lock accepts.
pub const MAX_SEEN: usize = 64;

/// The on-disk store's bound, every identity together.
pub const MAX_BYTES: u64 = 16 << 20;

/// The blue type one value showed.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Shape {
    Int,
    Float,
    Str,
    Bool,
    Sym,
    Nil,
    /// A list and the one shape its elements showed; `None` for an empty
    /// list, which shows no element type.
    List(Option<Box<Shape>>),
    /// A value no `Ty` names (a map, a function, a handle), a list whose
    /// elements disagree, or one longer than [`READ`].
    Opaque,
}

impl Shape {
    /// The shape `value` shows.
    #[must_use]
    pub fn of(value: &Value) -> Self {
        let mut left = READ;
        shape(value, &mut left)
    }

    /// The type the checker gives this shape, when it has one.
    #[must_use]
    pub fn ty(&self) -> Option<Ty> {
        Some(match self {
            Shape::Int => Ty::Int,
            Shape::Float => Ty::Float,
            Shape::Str => Ty::Str,
            Shape::Bool => Ty::Bool,
            Shape::Sym => Ty::Sym,
            Shape::Nil => Ty::Nil,
            Shape::List(Some(element)) => Ty::List(Box::new(element.ty()?)),
            Shape::List(None) | Shape::Opaque => return None,
        })
    }

    /// The spelling [`std::fmt::Display`] writes.
    #[must_use]
    pub fn parse(text: &str) -> Option<Self> {
        Some(match text {
            "Int" => Shape::Int,
            "Float" => Shape::Float,
            "Str" => Shape::Str,
            "Bool" => Shape::Bool,
            "Sym" => Shape::Sym,
            "Nil" => Shape::Nil,
            "?" => Shape::Opaque,
            "List()" => Shape::List(None),
            other => {
                let inner = other.strip_prefix("List(")?.strip_suffix(')')?;
                Shape::List(Some(Box::new(Shape::parse(inner)?)))
            }
        })
    }
}

impl std::fmt::Display for Shape {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Shape::Int => f.write_str("Int"),
            Shape::Float => f.write_str("Float"),
            Shape::Str => f.write_str("Str"),
            Shape::Bool => f.write_str("Bool"),
            Shape::Sym => f.write_str("Sym"),
            Shape::Nil => f.write_str("Nil"),
            Shape::List(None) => f.write_str("List()"),
            Shape::List(Some(element)) => write!(f, "List({element})"),
            Shape::Opaque => f.write_str("?"),
        }
    }
}

fn shape(value: &Value, left: &mut usize) -> Shape {
    if *left == 0 {
        return Shape::Opaque;
    }
    *left -= 1;
    match value {
        Value::Int(_) => Shape::Int,
        Value::Float(_) => Shape::Float,
        Value::Str(_) => Shape::Str,
        Value::Bool(_) => Shape::Bool,
        Value::Keyword(_) => Shape::Sym,
        Value::Nil => Shape::Nil,
        Value::List(items) => {
            let mut joined: Option<Shape> = None;
            for item in items.iter() {
                let s = shape(item, left);
                joined = Some(match joined {
                    None => s,
                    Some(j) => match join(&j, &s) {
                        Some(k) => k,
                        None => return Shape::Opaque,
                    },
                });
            }
            match joined {
                None => Shape::List(None),
                Some(Shape::Opaque) => Shape::Opaque,
                Some(element) => Shape::List(Some(Box::new(element))),
            }
        }
        _ => Shape::Opaque,
    }
}

/// The one shape both `a` and `b` belong to, when the checker can name it.
#[must_use]
pub fn join(a: &Shape, b: &Shape) -> Option<Shape> {
    match (a, b) {
        _ if a == b => Some(a.clone()),
        (Shape::List(None), Shape::List(x)) | (Shape::List(x), Shape::List(None)) => {
            Some(Shape::List(x.clone()))
        }
        (Shape::List(Some(x)), Shape::List(Some(y))) => {
            join(x, y).map(|j| Shape::List(Some(Box::new(j))))
        }
        _ => None,
    }
}

/// One call's shapes: its arguments, in order, and what it returned.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Observation {
    pub args: Vec<Shape>,
    pub ret: Shape,
}

impl Observation {
    /// A definition seen with more than [`MAX_SEEN`] signatures, or read from
    /// an entry that did not decode: it returns [`Shape::Opaque`], so no lock
    /// accepts it.
    #[must_use]
    pub fn varied() -> Self {
        Self {
            args: Vec::new(),
            ret: Shape::Opaque,
        }
    }

    /// The spelling [`std::fmt::Display`] writes: `Int Str -> Int`.
    #[must_use]
    pub fn parse(text: &str) -> Option<Self> {
        let mut words = text.split_whitespace();
        let mut args = Vec::new();
        for w in words.by_ref() {
            if w == "->" {
                let ret = Shape::parse(words.next()?)?;
                return words.next().is_none().then_some(Self { args, ret });
            }
            args.push(Shape::parse(w)?);
        }
        None
    }

    fn key(&self) -> [u8; 32] {
        let mut h = blake3::Hasher::new_derive_key("blue witness observation v1");
        h.update(self.to_string().as_bytes());
        *h.finalize().as_bytes()
    }
}

impl std::fmt::Display for Observation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        for a in &self.args {
            write!(f, "{a} ")?;
        }
        write!(f, "-> {}", self.ret)
    }
}

/// Observations by definition.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Witnessed {
    by_def: BTreeMap<DefHash, BTreeSet<Observation>>,
}

impl Witnessed {
    /// What calls of `def` showed.
    #[must_use]
    pub fn of(&self, def: &DefHash) -> Option<&BTreeSet<Observation>> {
        self.by_def.get(def)
    }

    /// Record one call of `def`, held to [`MAX_SEEN`].
    pub fn insert(&mut self, def: DefHash, observation: Observation) {
        let seen = self.by_def.entry(def).or_default();
        if seen.len() >= MAX_SEEN && !seen.contains(&observation) {
            seen.insert(Observation::varied());
        } else {
            seen.insert(observation);
        }
    }

    /// Everything `other` showed, added to this.
    pub fn extend(&mut self, other: &Witnessed) {
        for (def, seen) in &other.by_def {
            for o in seen {
                self.insert(*def, o.clone());
            }
        }
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.by_def.is_empty()
    }

    pub fn iter(&self) -> impl Iterator<Item = (&DefHash, &BTreeSet<Observation>)> {
        self.by_def.iter()
    }
}

/// A signature every observation agrees on.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Locked {
    pub params: Vec<Ty>,
    pub ret: Ty,
}

/// The signature of a definition of `arity` parameters that `observations`
/// show, or `None` when there is none, when a call passed another number of
/// arguments, or when any position saw shapes with no join or no type.
#[must_use]
pub fn lock<'a>(
    observations: impl IntoIterator<Item = &'a Observation>,
    arity: usize,
) -> Option<Locked> {
    let mut params: Vec<Option<Shape>> = vec![None; arity];
    let mut ret: Option<Shape> = None;
    for o in observations {
        if o.args.len() != arity {
            return None;
        }
        for (slot, s) in params.iter_mut().zip(&o.args) {
            *slot = Some(match slot.take() {
                None => s.clone(),
                Some(j) => join(&j, s)?,
            });
        }
        ret = Some(match ret.take() {
            None => o.ret.clone(),
            Some(j) => join(&j, &o.ret)?,
        });
    }
    Some(Locked {
        params: params
            .into_iter()
            .map(|s| s?.ty())
            .collect::<Option<Vec<Ty>>>()?,
        ret: ret?.ty()?,
    })
}

struct Frame {
    depth: usize,
    own: Option<(DefHash, Vec<Shape>)>,
    heads: Vec<(DefHash, Vec<Shape>)>,
}

#[derive(Default)]
struct State {
    stack: Vec<Frame>,
    pending: Vec<(DefHash, Vec<Shape>)>,
    seen: Witnessed,
}

/// The observer. A call of anything but a loose top-level `def` takes no
/// lock and keeps no frame, unless it ends a chain of tail calls.
pub struct Witness {
    targets: HashMap<Arc<str>, (DefHash, Span)>,
    inner: Option<Arc<dyn CallObserver>>,
    state: Mutex<State>,
    depth: AtomicUsize,
    top: AtomicUsize,
    carrying: AtomicBool,
}

impl Witness {
    /// A witness over a program's loose top-level definitions: `lowered` is
    /// the tree before erasure and `hashes` its [`crate::hash_checked`].
    /// `inner`, when a tool already watches the run, sees every call too.
    #[must_use]
    pub fn new(
        lowered: &[Spanned],
        hashes: &DefHashes,
        inner: Option<Arc<dyn CallObserver>>,
    ) -> Self {
        let mut targets = HashMap::new();
        for d in hashes.defs() {
            if d.kind != DefKind::Function || hashes.is_ambiguous(&d.key) {
                continue;
            }
            let Some(form) = lowered.get(d.top_level) else {
                continue;
            };
            if loose_def(form) {
                targets.insert(Arc::from(d.key.as_str()), (d.hash, form.span));
            }
        }
        Self {
            targets,
            inner,
            state: Mutex::new(State::default()),
            depth: AtomicUsize::new(0),
            top: AtomicUsize::new(0),
            carrying: AtomicBool::new(false),
        }
    }

    /// [`Witness::new`] over a checked program, hashed as the engine hashes it.
    #[must_use]
    pub fn of_checked(checked: &Checked, inner: Option<Arc<dyn CallObserver>>) -> Self {
        let lowered = blue_lang_runtime::pipeline::lower(&checked.program, &checked.names);
        let hashes = crate::hash_checked(&checked.program, &lowered);
        Self::new(&lowered, &hashes, inner)
    }

    /// Everything recorded so far.
    #[must_use]
    pub fn witnessed(&self) -> Witnessed {
        self.state().seen.clone()
    }

    fn state(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn target(&self, call: &Call<'_>) -> Option<DefHash> {
        let (hash, source) = self.targets.get(&**call.name?)?;
        (*source == call.source).then_some(*hash)
    }
}

/// `(define (name …) body)`: a named function with no annotation.
fn loose_def(form: &Spanned) -> bool {
    matches!(form.as_list(), Some([head, sig, ..])
        if head.as_symbol() == Some("define") && sig.as_list().is_some())
}

impl CallObserver for Witness {
    fn enter(&self, call: &Call<'_>, args: &[Value]) -> Option<Value> {
        let answered = self.inner.as_ref().and_then(|i| i.enter(call, args));
        let depth = self.depth.fetch_add(1, Ordering::Relaxed) + 1;
        let target = self.target(call);
        if target.is_none() && !self.carrying.load(Ordering::Relaxed) {
            return answered;
        }
        let mut st = self.state();
        let heads = std::mem::take(&mut st.pending);
        self.carrying.store(false, Ordering::Relaxed);
        st.stack.push(Frame {
            depth,
            own: target.map(|h| (h, args.iter().map(Shape::of).collect())),
            heads,
        });
        self.top.store(depth, Ordering::Relaxed);
        answered
    }

    fn leave(&self, call: &Call<'_>, exit: Exit<'_>) {
        let depth = self.depth.fetch_sub(1, Ordering::Relaxed);
        let ours = self.top.load(Ordering::Relaxed) == depth;
        if ours || self.carrying.load(Ordering::Relaxed) {
            let mut st = self.state();
            st.pending.clear();
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

impl Witness {
    fn left(&self, st: &mut State, frame: Frame, exit: Exit<'_>) {
        let Frame { own, mut heads, .. } = frame;
        match exit {
            Exit::Returned(v) | Exit::Supplied(v) => {
                let ret = Shape::of(v);
                for (def, args) in own.into_iter().chain(heads) {
                    st.seen.insert(
                        def,
                        Observation {
                            args,
                            ret: ret.clone(),
                        },
                    );
                }
            }
            Exit::TailCalled => {
                heads.extend(own);
                if !heads.is_empty() {
                    st.pending = heads;
                    self.carrying.store(true, Ordering::Relaxed);
                }
            }
            Exit::Raised(_) => {}
        }
    }
}

/// Where observations are kept when nothing names a place:
/// `crate::store::cache_root()/witness`.
#[must_use]
pub fn default_root() -> Option<PathBuf> {
    Some(crate::store::cache_root()?.join("witness"))
}

/// Observations on disk: one [`Store`] file per definition, an entry per
/// distinct [`Observation`], held to [`MAX_BYTES`] as the memo's store is.
pub struct Witnesses {
    store: Store,
}

impl Witnesses {
    /// The observations of evaluator `identity` under `root`.
    ///
    /// # Errors
    ///
    /// The directory cannot be created.
    pub fn open(root: &Path, identity: Identity) -> std::io::Result<Self> {
        Ok(Self {
            store: Store::open(root, identity, MAX_BYTES)?,
        })
    }

    /// This build's observations under [`default_root`]; `None` when there is
    /// no cache directory or it cannot be created.
    #[must_use]
    pub fn open_default() -> Option<Self> {
        Self::open(&default_root()?, Identity::of_this_build()).ok()
    }

    /// Every observation recorded for `def`. An entry that does not decode,
    /// or one the store skipped as damaged, reads as [`Observation::varied`]:
    /// what it held is unknown, so nothing may be locked over it.
    #[must_use]
    pub fn load(&self, def: &DefHash) -> BTreeSet<Observation> {
        let bucket = self.store.load(def);
        let mut out = BTreeSet::new();
        if bucket.damaged > 0 {
            out.insert(Observation::varied());
        }
        for stored in bucket.entries.values() {
            let decoded = std::str::from_utf8(&stored.value)
                .ok()
                .and_then(Observation::parse);
            out.insert(decoded.unwrap_or_else(Observation::varied));
        }
        out
    }

    /// Add what `seen` holds that the store does not, then hold the store to
    /// its bound. A definition past [`MAX_SEEN`] gets [`Observation::varied`]
    /// in place of the rest. Answers the entries written.
    ///
    /// # Errors
    ///
    /// A file cannot be written or the store cannot be listed.
    pub fn record(&self, seen: &Witnessed) -> std::io::Result<usize> {
        let mut written = 0;
        for (def, observations) in seen.iter() {
            let have = self.store.load(def).entries;
            let mut fresh: Vec<&Observation> = observations
                .iter()
                .filter(|o| !have.contains_key(&o.key()))
                .collect();
            if fresh.is_empty() {
                continue;
            }
            let varied = Observation::varied();
            if have.len() + fresh.len() > MAX_SEEN {
                if have.contains_key(&varied.key()) {
                    continue;
                }
                fresh = vec![&varied];
            }
            let entries: Vec<([u8; 32], Duration, Vec<u8>)> = fresh
                .iter()
                .map(|o| (o.key(), Duration::ZERO, o.to_string().into_bytes()))
                .collect();
            written += self.store.append(def, &entries)?;
        }
        if written > 0 {
            self.store.evict()?;
        }
        Ok(written)
    }
}
