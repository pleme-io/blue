//! Tier T3 (docs/PERFORMANCE.md, 1.7.1): a definition compiled ahead of time by
//! chuuzou, one nix derivation per `def_hash`, and the run-time side that
//! answers a call from it.
//!
//! [`defs`] is what `blue ast --resolved --defs FILE` prints: each definition
//! of the entry file with its `def_hash` and its slice, the resolved forms of
//! every entry definition it reaches, each function and value renamed to
//! `%root/d_<hex>` after its own hash. The slice is then a function of the
//! hash: a rename changes no byte of it, and an edit outside what it reaches
//! changes none either. `native/build/defs.b` reads it, and
//! `nix/native-defs.nix` builds one derivation per slice.
//!
//! [`Tier`] is the call observer that answers a call of a definition whose
//! hash has an artifact under `BLUE_CACHE_SHARED`
//! (`blue_lang_mondou::store::native_artifact`), with every argument an Int,
//! by running the artifact; any other call, and any artifact that does not
//! answer, runs in the interpreter as before. It is on by default (rule R7 of
//! the default cascade): a run whose program has an artifact answers natively
//! each definition whose outermost calls averaged [`hot_from`] or more in
//! earlier runs (0.2 ms with a library, 20 ms without), and records this run's times in the profile tier
//! (`blue_lang_mondou::store::profile`), so a definition goes native once it is
//! known to be hot. `BLUE_NATIVE=on` answers every call it can; `off` none.

use std::collections::{BTreeSet, HashMap};
use std::path::PathBuf;
use std::sync::Arc;

use blue_lang_mondou::def_hash::{DefHash, DefHashes, DefKind};
use blue_lang_runtime::observe::{Call, CallObserver, Exit};
use blue_lang_runtime::uses::ResolvedProgram;
use blue_lang_syntax::{Atom, Span, Spanned, SpannedForm};
use tatara_lisp_eval::Value;

pub(crate) const ENV: &str = "BLUE_NATIVE";

/// The name a definition takes in every slice: its own hash.
fn canonical(hash: &DefHash) -> String {
    format!("%root/d_{}", hash.hex())
}

fn renamable(form: &Spanned) -> bool {
    matches!(
        form.as_list()
            .and_then(|items| items.first())
            .and_then(Spanned::as_symbol),
        Some("define" | "define-typed")
    )
}

fn rename(form: &Spanned, names: &HashMap<&str, String>) -> Spanned {
    let renamed = match &form.form {
        SpannedForm::Atom(Atom::Symbol(s)) => match names.get(s.as_str()) {
            Some(to) => SpannedForm::Atom(Atom::Symbol(to.clone())),
            None => form.form.clone(),
        },
        SpannedForm::List(items) => {
            SpannedForm::List(items.iter().map(|i| rename(i, names)).collect())
        }
        SpannedForm::Quote(x) => SpannedForm::Quote(Box::new(rename(x, names))),
        SpannedForm::Quasiquote(x) => SpannedForm::Quasiquote(Box::new(rename(x, names))),
        SpannedForm::Unquote(x) => SpannedForm::Unquote(Box::new(rename(x, names))),
        SpannedForm::UnquoteSplice(x) => SpannedForm::UnquoteSplice(Box::new(rename(x, names))),
        other => other.clone(),
    };
    Spanned::new(form.span, renamed)
}

fn reached(hashes: &DefHashes, from: usize, entry: &dyn Fn(usize) -> bool) -> BTreeSet<usize> {
    let mut seen = BTreeSet::new();
    let mut frontier = vec![from];
    while let Some(d) = frontier.pop() {
        if !entry(hashes.defs()[d].top_level) || !seen.insert(d) {
            continue;
        }
        frontier.extend(hashes.defs()[d].calls.iter().copied());
    }
    seen
}

/// Every unambiguous definition of the entry file of `program`: its key, its
/// `def_hash` as `def_hash(f)` answers it, its kind, the name it has in its
/// slice, and the slice. `lowered` is what the hash reads, `tree` the
/// resolved tree chuuzou reads, one form per top-level form of `program`.
///
/// # Errors
///
/// When `lowered` and `tree` do not hold one form per top-level form.
pub(crate) fn defs(
    program: &ResolvedProgram,
    lowered: &[Spanned],
    tree: &[Spanned],
) -> Result<serde_json::Value, String> {
    if lowered.len() != tree.len() {
        return Err(format!(
            "the lowered tree has {} forms and the resolved tree {}",
            lowered.len(),
            tree.len()
        ));
    }
    let hashes = blue_lang_mondou::hash_checked(program, lowered);
    let entry = |top: usize| program.owner_of(top) == Some(ResolvedProgram::ENTRY);
    let names: HashMap<&str, String> = hashes
        .defs()
        .iter()
        .filter(|d| entry(d.top_level) && !hashes.is_ambiguous(&d.key))
        .filter(|d| renamable(&tree[d.top_level]))
        .map(|d| (d.key.as_str(), canonical(&d.hash)))
        .collect();
    let mut out = Vec::new();
    for (i, d) in hashes.defs().iter().enumerate() {
        if !entry(d.top_level) || hashes.is_ambiguous(&d.key) {
            continue;
        }
        let mut seen = BTreeSet::new();
        let slice: Vec<String> = reached(&hashes, i, &entry)
            .into_iter()
            .map(|r| hashes.defs()[r].top_level)
            .collect::<BTreeSet<usize>>()
            .into_iter()
            .map(|top| rename(&tree[top], &names).to_sexp().to_string())
            .filter(|text| seen.insert(text.clone()))
            .collect();
        out.push(serde_json::json!({
            "key": d.key,
            "hash": d.hash.to_string(),
            "kind": match d.kind {
                DefKind::Function => "function",
                DefKind::Value => "value",
                DefKind::Macro => "macro",
            },
            "entry": names.get(d.key.as_str()).cloned().unwrap_or_else(|| d.key.clone()),
            "slice": slice.join("\n"),
        }));
    }
    Ok(serde_json::Value::Array(out))
}

/// A word the seam carries, as a definition's signature names it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Word {
    Int,
    Bool,
    Float,
    Str,
    List,
}

/// What a definition takes and answers, as the tier converts it across the
/// seam: an untyped definition is held to Ints, as before types crossed it.
#[derive(Clone, Debug, PartialEq, Eq)]
enum Shape {
    Untyped,
    Typed(Vec<Word>, Word),
}

impl Shape {
    /// The shape `form` declares, or `None` when it names a type the seam
    /// does not carry.
    fn of(form: &Spanned) -> Option<Self> {
        let items = form.as_list()?;
        if items.first().and_then(Spanned::as_symbol) != Some("define-typed") {
            return Some(Self::Untyped);
        }
        let word = |t: &Spanned| match t.as_symbol().or_else(|| match t.as_list()? {
            [l, i] if l.as_symbol() == Some("List") && i.as_symbol() == Some("Int") => Some("List"),
            _ => None,
        })? {
            "List" => Some(Word::List),
            "Int" => Some(Word::Int),
            "Bool" => Some(Word::Bool),
            "Float" => Some(Word::Float),
            "Str" => Some(Word::Str),
            _ => None,
        };
        let params = items
            .get(1)?
            .as_list()?
            .iter()
            .skip(1)
            .map(|p| p.as_list().and_then(|p| p.get(1)).and_then(word))
            .collect::<Option<Vec<Word>>>()?;
        Some(Self::Typed(params, word(items.get(2)?)?))
    }

    /// The arguments as the seam's words, or `None` when one is not what the
    /// signature names.
    fn words(&self, args: &[Value]) -> Option<Vec<i64>> {
        let take = |a: &Value, w: Word| match (a, w) {
            (Value::Int(n), Word::Int) => Some(*n),
            (Value::Bool(b), Word::Bool) => Some(i64::from(*b)),
            (Value::Float(x), Word::Float) => Some(x.to_bits().cast_signed()),
            _ => None,
        };
        if !self.in_words() {
            return None;
        }
        match self {
            Self::Untyped => args.iter().map(|a| take(a, Word::Int)).collect(),
            Self::Typed(ws, _) if ws.len() == args.len() => {
                args.iter().zip(ws).map(|(a, w)| take(a, *w)).collect()
            }
            Self::Typed(..) => None,
        }
    }

    /// Whether every argument and the answer fit one word each, so the word
    /// seam carries the call; a Str needs the token seam.
    fn in_words(&self) -> bool {
        match self {
            Self::Untyped => true,
            Self::Typed(ws, r) => ws
                .iter()
                .chain([r])
                .all(|w| !matches!(w, Word::Str | Word::List)),
        }
    }

    /// Whether every word is an Int, so an executable takes bare decimals,
    /// as executables built before tokens did.
    fn plain(&self) -> bool {
        match self {
            Self::Untyped => true,
            Self::Typed(ws, r) => ws.iter().chain([r]).all(|w| *w == Word::Int),
        }
    }

    /// The arguments as value tokens (`native/seam/host_io.rs`, `decode`), or
    /// `None` when one is not what the signature names.
    fn tokens(&self, args: &[Value]) -> Option<Vec<String>> {
        let ws: Vec<Word> = match self {
            Self::Untyped => vec![Word::Int; args.len()],
            Self::Typed(ws, _) if ws.len() == args.len() => ws.clone(),
            Self::Typed(..) => return None,
        };
        args.iter()
            .zip(ws)
            .map(|(a, w)| match (a, w) {
                (Value::Int(n), Word::Int) => Some(format!("i{n}")),
                (Value::Bool(b), Word::Bool) => Some(format!("b{}", u8::from(*b))),
                (Value::Float(x), Word::Float) => Some(format!("f{}", x.to_bits().cast_signed())),
                (Value::List(xs), Word::List) => xs
                    .iter()
                    .map(|x| match x {
                        Value::Int(n) => Some(n.to_string()),
                        _ => None,
                    })
                    .collect::<Option<Vec<String>>>()
                    .map(|ns| format!("l{}", ns.join(","))),
                (Value::Str(t), Word::Str) => {
                    Some(t.bytes().fold(String::from("s"), |mut out, b| {
                        out.push_str(&format!("{b:02x}"));
                        out
                    }))
                }
                _ => None,
            })
            .collect()
    }

    /// The answer's token as the value the signature names, or `None` when it
    /// is not one. A bare decimal is an Int, as executables built before
    /// tokens answered.
    fn from_token(&self, token: &str) -> Option<Value> {
        let want = match self {
            Self::Untyped => Word::Int,
            Self::Typed(_, r) => *r,
        };
        let (tag, rest) = (token.as_bytes().first()?, token.get(1..)?);
        match (tag, want) {
            (b'i', Word::Int) => rest.parse().ok().map(Value::Int),
            (b'b', Word::Bool) => match rest {
                "1" => Some(Value::Bool(true)),
                "0" => Some(Value::Bool(false)),
                _ => None,
            },
            (b'f', Word::Float) => rest
                .parse::<i64>()
                .ok()
                .map(|b| Value::Float(f64::from_bits(b.cast_unsigned()))),
            (b's', Word::Str) if rest.len() % 2 == 0 => {
                let bytes = (0..rest.len())
                    .step_by(2)
                    .map(|i| u8::from_str_radix(rest.get(i..i + 2)?, 16).ok())
                    .collect::<Option<Vec<u8>>>()?;
                String::from_utf8(bytes).ok().map(|t| Value::Str(t.into()))
            }
            (b'l', Word::List) if rest.is_empty() => Some(Value::List(Default::default())),
            (b'l', Word::List) => rest
                .split(',')
                .map(|n| n.parse().ok().map(Value::Int))
                .collect::<Option<Vec<Value>>>()
                .map(|xs| Value::List(std::sync::Arc::new(xs.into()))),
            (_, Word::Int) => token.parse().ok().map(Value::Int),
            _ => None,
        }
    }

    /// The seam's answer as the value the signature names.
    fn value(&self, v: i64) -> Value {
        match self {
            Self::Typed(_, Word::Bool) => Value::Bool(v != 0),
            Self::Typed(_, Word::Float) => Value::Float(f64::from_bits(v.cast_unsigned())),
            _ => Value::Int(v),
        }
    }
}

struct Target {
    name: Option<String>,
    artifact: PathBuf,
    library: Option<crate::dl::Entry>,
    shape: Shape,
    hash: DefHash,
    hot: bool,
    profiled: bool,
    from: u64,
}

/// How the tier decides, from `BLUE_NATIVE`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Mode {
    /// Unset: a call goes native only when its definition's outermost calls
    /// ran at least [`hot_from`] on average in earlier runs.
    Auto,
    /// `on`: every call with an artifact and Int arguments goes native.
    On,
    /// `off`: no call does.
    Off,
}

/// The mean an outermost call must have cost before [`Mode::Auto`] answers it
/// natively: well above what starting an artifact costs, so the default only
/// fires where the gain is known.
pub(crate) const HOT_NS: u64 = 20_000_000;

/// The mean an outermost call must have cost before [`Mode::Auto`] answers it
/// through the artifact's library: ten times what one call through the
/// library costs (about 20 µs, most of it the thread that holds the board's
/// stack), where [`HOT_NS`] is sized for starting a process.
pub(crate) const HOT_LIBRARY_NS: u64 = 200_000;

/// The mean from which a definition is hot: [`HOT_LIBRARY_NS`] when its
/// artifact's library loaded, else [`HOT_NS`]. A static binary (blue on Linux
/// is static musl) cannot load a library, so there every call starts the
/// executable and the process threshold holds.
pub(crate) fn hot_from(library: bool) -> u64 {
    if library {
        HOT_LIBRARY_NS
    } else {
        HOT_NS
    }
}

pub(crate) fn mode_of(value: Option<&str>) -> Mode {
    match value.map(|v| v.trim().to_ascii_lowercase()).as_deref() {
        None | Some("" | "auto") => Mode::Auto,
        Some("on" | "1" | "true" | "yes") => Mode::On,
        Some(_) => Mode::Off,
    }
}

pub(crate) fn mode() -> Mode {
    mode_of(std::env::var(ENV).ok().as_deref())
}

#[derive(Default)]
struct Timing {
    open: HashMap<Span, (u32, Option<std::time::Instant>)>,
    seen: HashMap<DefHash, blue_lang_mondou::store::Profiled>,
    tail: Option<(Span, DefHash)>,
}

impl Timing {
    fn close(&mut self, source: Span, hash: DefHash) {
        let Some(started) = self.open.get_mut(&source).and_then(|o| o.1.take()) else {
            return;
        };
        let ns = u64::try_from(started.elapsed().as_nanos()).unwrap_or(u64::MAX);
        let p = self.seen.entry(hash).or_default();
        *p = p.plus(blue_lang_mondou::store::Profiled {
            total_ns: ns,
            calls: 1,
        });
    }
}

/// The native tier over one program: each function definition whose
/// `def_hash` has an artifact, by the span its closure carries.
pub(crate) struct Tier {
    by_source: HashMap<Span, Target>,
    inner: Option<Arc<dyn CallObserver>>,
    timing: std::sync::Mutex<Timing>,
    answers: bool,
    seeding: bool,
}

impl Tier {
    /// The tier for a program about to run, looking each definition's
    /// artifact up with `find` and its profile with `profiled`; a definition
    /// with no artifact runs as before.
    pub(crate) fn over(
        w: &blue_lang_runtime::pipeline::Watched<'_>,
        mode: Mode,
        find: &dyn Fn(&DefHash) -> Option<PathBuf>,
        profiled: &dyn Fn(&DefHash) -> Option<blue_lang_mondou::store::Profiled>,
        inner: Option<Arc<dyn CallObserver>>,
    ) -> Arc<Self> {
        let hashes = blue_lang_mondou::hash_checked(w.program, w.lowered);
        let mut by_source = HashMap::new();
        for d in w.definitions.iter() {
            let Some(hashed) = hashes.at(d.top_level) else {
                continue;
            };
            if hashed.key != *d.key || hashed.kind != DefKind::Function {
                continue;
            }
            let Some(artifact) = find(&hashed.hash) else {
                continue;
            };
            let Some(shape) = w.lowered.get(d.top_level).and_then(Shape::of) else {
                continue;
            };
            let Some(items) = w.erased.get(d.top_level).and_then(Spanned::as_list) else {
                continue;
            };
            let source = match items.get(1).and_then(Spanned::as_symbol) {
                Some(_) => items.get(2).map(|l| (l.span, None)),
                None => Some((d.span, Some(d.key.to_string()))),
            };
            let mean = profiled(&hashed.hash).and_then(blue_lang_mondou::store::Profiled::mean_ns);
            let library = if mode == Mode::Off {
                None
            } else {
                blue_lang_mondou::store::native_library(&artifact).and_then(|l| crate::dl::open(&l))
            };
            let threshold = hot_from(library.is_some());
            let hot = match mode {
                Mode::On => true,
                Mode::Off => false,
                Mode::Auto => {
                    let held: &[&str] = if mean.is_some_and(|ns| ns >= threshold) {
                        &["artifact", "hot"]
                    } else {
                        &["artifact"]
                    };
                    blue_lang_runtime::kitei::fires("R7", held)
                }
            };
            let library = library.filter(|_| hot);
            if let Some((span, name)) = source {
                by_source.insert(
                    span,
                    Target {
                        name,
                        artifact,
                        library,
                        shape,
                        hash: hashed.hash,
                        hot,
                        profiled: mean.is_some(),
                        from: threshold,
                    },
                );
            }
        }
        Arc::new(Self {
            by_source,
            inner,
            timing: std::sync::Mutex::default(),
            answers: true,
            seeding: false,
        })
    }

    /// The tier a test run seeds the profile through (W1 of docs/FACTS.md):
    /// it answers no call, times every definition with an artifact, and
    /// records a definition's time only when it ran hot, so a definition its
    /// tests call cheaply stays unprofiled and the first real run times it.
    /// `None` when the program has no definition with an artifact.
    pub(crate) fn seeding(
        w: &blue_lang_runtime::pipeline::Watched<'_>,
        inner: Option<Arc<dyn CallObserver>>,
    ) -> Option<Arc<Self>> {
        if !seeds() {
            return None;
        }
        let tier = Self::over(
            w,
            Mode::Auto,
            &blue_lang_mondou::store::native_artifact,
            &blue_lang_mondou::store::profile,
            inner,
        );
        let mut tier = Arc::into_inner(tier)?;
        if tier.by_source.is_empty() {
            return None;
        }
        tier.answers = false;
        tier.seeding = true;
        Some(Arc::new(tier))
    }

    /// The definitions this run answers natively, and the ones it measures
    /// because no run has profiled them yet, each by the name a call uses.
    fn plan(&self) -> (Vec<String>, Vec<String>) {
        let named = |t: &Target| t.name.clone().unwrap_or_else(|| t.hash.hex());
        let mut hot: Vec<String> = self
            .by_source
            .values()
            .filter(|t| t.hot)
            .map(named)
            .collect();
        let mut fresh: Vec<String> = self
            .by_source
            .values()
            .filter(|t| !t.hot && !t.profiled)
            .map(named)
            .collect();
        hot.sort();
        fresh.sort();
        (hot, fresh)
    }

    fn target(&self, call_: &Call<'_>) -> Option<&Target> {
        let target = self.by_source.get(&call_.source)?;
        (target.name.as_deref() == call_.name.map(|n| &**n)).then_some(target)
    }

    /// The time this run's outermost calls of each definition took, added to
    /// the profile tier through `record`.
    /// When the tier seeds, only the times of definitions that ran hot.
    pub(crate) fn flush(&self, record: &dyn Fn(&DefHash, blue_lang_mondou::store::Profiled)) {
        let seen = self
            .timing
            .lock()
            .map(|mut t| std::mem::take(&mut t.seen))
            .unwrap_or_default();
        let from: HashMap<DefHash, u64> =
            self.by_source.values().map(|t| (t.hash, t.from)).collect();
        for (hash, p) in seen {
            let hot = p
                .mean_ns()
                .is_some_and(|ns| ns >= from.get(&hash).copied().unwrap_or(HOT_NS));
            if !self.seeding || hot {
                record(&hash, p);
            }
        }
    }
}

impl Drop for Tier {
    fn drop(&mut self) {
        self.flush(&blue_lang_mondou::store::record_profile);
    }
}

/// The planner `blue run` offers the pipeline by default: the native tier when
/// the program has a definition with an artifact that is hot or not yet
/// profiled, over the memo [`crate::memo::planned`] or [`crate::memo::costly`]
/// offers when `memo`; else that memo.
pub(crate) fn planned(
    w: &blue_lang_runtime::pipeline::Watched<'_>,
    repeating: &[(usize, String)],
    memo: bool,
    native: bool,
) -> Option<blue_lang_runtime::pipeline::Planned> {
    let memo = if memo {
        crate::memo::planned(w, repeating).or_else(|| crate::memo::costly(w))
    } else {
        None
    };
    let current = mode();
    if !native || current == Mode::Off || !blue_lang_mondou::store::native_present() {
        return memo;
    }
    let (inner, memo_reason) = match memo {
        Some((o, r)) => (Some(o), Some(r)),
        None => (None, None),
    };
    let tier = Tier::over(
        w,
        current,
        &blue_lang_mondou::store::native_artifact,
        &blue_lang_mondou::store::profile,
        inner.clone(),
    );
    let (hot, fresh) = tier.plan();
    if hot.is_empty() && fresh.is_empty() {
        return inner.zip(memo_reason);
    }
    let mut reason = Vec::new();
    if !hot.is_empty() {
        reason.push(format!(
            "native code answers `{}`, whose calls ran {} ms or more in earlier runs ({} ms through a library)",
            hot.join("`, `"),
            HOT_NS / 1_000_000,
            HOT_LIBRARY_NS as f64 / 1_000_000.0
        ));
    }
    if !fresh.is_empty() {
        reason.push(format!(
            "the native tier times `{}`, which has an artifact and no profile yet",
            fresh.join("`, `")
        ));
    }
    reason.extend(memo_reason);
    Some((tier, reason.join("; ")))
}

/// Whether a test run seeds the profile: the tier is not off and a native
/// tier is present, checked before any hashing.
pub(crate) fn seeds() -> bool {
    mode() != Mode::Off && blue_lang_mondou::store::native_present()
}

/// The variable naming the command a run starts, detached, when it asks for
/// its program to be built (`nix run .#native-build`, which reads the
/// requests); unset, the requests wait for a builder the node runs itself.
pub(crate) const BUILDER_ENV: &str = "BLUE_NATIVE_BUILDER";

/// After a run of `file` whose evaluation took `took`: ask for the program to
/// be built into this node's native tier when the tier decides by profile
/// ([`Mode::Auto`]), a native tier is present, and the evaluation took
/// [`HOT_NS`] or more, the cost from which a definition earns native code even
/// as a process; start the builder [`BUILDER_ENV`] names when this run asked.
/// Answers whether it asked.
pub(crate) fn ask_for_build(file: &std::path::Path, took: std::time::Duration) -> bool {
    if mode() != Mode::Auto
        || took.as_nanos() < u128::from(HOT_NS)
        || !blue_lang_mondou::store::native_present()
    {
        return false;
    }
    let (Ok(text), Ok(path)) = (std::fs::read(file), file.canonicalize()) else {
        return false;
    };
    let asked = blue_lang_mondou::store::want_native(&text, &path);
    if asked {
        if let Some(builder) = std::env::var_os(BUILDER_ENV).filter(|b| !b.is_empty()) {
            let _ = std::process::Command::new(builder)
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn();
        }
    }
    asked
}

/// Run one artifact on its arguments' text: the one line it answered, or
/// `None` when it did not answer (a fault, arguments it refuses, an output
/// that is not one line).
fn answer(artifact: &std::path::Path, args: impl IntoIterator<Item = String>) -> Option<String> {
    let out = std::process::Command::new(artifact)
        .args(args)
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8(out.stdout).ok()?;
    let mut lines = text.lines();
    let value = lines.next()?.trim().to_string();
    lines.next().is_none().then_some(value)
}

impl CallObserver for Tier {
    fn enter(&self, call_: &Call<'_>, args: &[Value]) -> Option<Value> {
        if let Some(answered) = self.inner.as_ref().and_then(|i| i.enter(call_, args)) {
            return Some(answered);
        }
        if let Ok(mut t) = self.timing.lock() {
            if let Some((source, hash)) = t.tail.take() {
                if source != call_.source {
                    t.close(source, hash);
                }
            }
        }
        let target = self.target(call_)?;
        if self.answers && target.hot {
            let shape = &target.shape;
            let answered = match target.library {
                Some(entry) if shape.in_words() => shape
                    .words(args)
                    .and_then(|words| crate::dl::call(entry, &words))
                    .map(|v| shape.value(v)),
                Some(entry) => shape
                    .tokens(args)
                    .and_then(|t| crate::dl::call_tokens(entry, &t.join(" ")))
                    .and_then(|token| shape.from_token(&token)),
                None if shape.plain() => shape
                    .words(args)
                    .and_then(|words| answer(&target.artifact, words.iter().map(i64::to_string)))
                    .and_then(|token| shape.from_token(&token)),
                None => shape
                    .tokens(args)
                    .and_then(|t| answer(&target.artifact, t))
                    .and_then(|token| shape.from_token(&token)),
            };
            if answered.is_some() {
                return answered;
            }
        }
        if let Ok(mut t) = self.timing.lock() {
            let open = t.open.entry(call_.source).or_insert((0, None));
            if open.0 == 0 && open.1.is_none() {
                open.1 = Some(std::time::Instant::now());
            }
            open.0 += 1;
        }
        None
    }

    fn leave(&self, call_: &Call<'_>, exit: Exit<'_>) {
        if let Some(inner) = &self.inner {
            inner.leave(call_, exit);
        }
        if matches!(exit, Exit::Supplied(_)) {
            return;
        }
        let Some(target) = self.target(call_) else {
            return;
        };
        let hash = target.hash;
        if let Ok(mut t) = self.timing.lock() {
            let Some(open) = t.open.get_mut(&call_.source) else {
                return;
            };
            open.0 = open.0.saturating_sub(1);
            if open.0 > 0 {
                return;
            }
            if matches!(exit, Exit::TailCalled) {
                t.tail = Some((call_.source, hash));
                return;
            }
            t.close(call_.source, hash);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;

    fn shape(src: &str) -> Option<Shape> {
        Shape::of(&tatara_lisp::read_spanned(src).expect("a form").remove(0))
    }

    #[test]
    fn a_signature_names_what_crosses_the_seam() {
        assert_eq!(shape("(define (%root/f x) x)"), Some(Shape::Untyped));
        let pick =
            shape("(define-typed (%root/pick (b Bool) (x Int)) Int (if b x 0))").expect("a shape");
        assert_eq!(pick, Shape::Typed(vec![Word::Bool, Word::Int], Word::Int));
        assert_eq!(
            pick.words(&[Value::Bool(true), Value::Int(7)]),
            Some(vec![1, 7])
        );
        assert_eq!(pick.words(&[Value::Int(1), Value::Int(7)]), None);
        assert_eq!(pick.words(&[Value::Bool(true)]), None);
        let small = shape("(define-typed (%root/small (n Int)) Bool (< n 3))").expect("a shape");
        assert!(matches!(small.value(0), Value::Bool(false)));
        assert!(matches!(small.value(1), Value::Bool(true)));
        assert_eq!(shape("(define-typed (%root/s (t String)) Int 0)"), None);
    }

    #[test]
    fn a_float_crosses_the_seam_as_its_bits_both_ways() {
        let half = shape("(define-typed (%root/half (x Float)) Float (* x 0.5))").expect("a shape");
        assert_eq!(half, Shape::Typed(vec![Word::Float], Word::Float));
        let bits = (-2.5f64).to_bits().cast_signed();
        assert_eq!(half.words(&[Value::Float(-2.5)]), Some(vec![bits]));
        assert_eq!(half.words(&[Value::Int(3)]), None);
        assert!(matches!(half.value(bits), Value::Float(x) if x == -2.5));
        assert!(matches!(half.value(0), Value::Float(x) if x == 0.0));
    }

    fn checked(src: &str) -> blue_lang_runtime::pipeline::Checked {
        let loader = blue_lang_pkg::load_path::LoadPath::for_entry(
            &std::env::temp_dir().join("native-test.b"),
        );
        let c = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(src),
            &loader,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .expect("checks");
        assert!(c.outcome.ok(), "{:?}", c.outcome.diagnostics);
        c
    }

    fn slices(src: &str) -> BTreeMap<String, (String, String)> {
        let c = checked(src);
        let tree = c
            .resolve()
            .resolved_tree(c.program.forms(), blue_lang_check::names::Rule::Namespaced);
        let v = defs(&c.program, &c.lowered(), &tree).expect("aligned");
        v.as_array()
            .expect("a list")
            .iter()
            .map(|d| {
                (
                    d["key"].as_str().expect("key").to_string(),
                    (
                        d["hash"].as_str().expect("hash").to_string(),
                        d["slice"].as_str().expect("slice").to_string(),
                    ),
                )
            })
            .collect()
    }

    const BASE: &str = "def sq(x: Int) -> Int\n  x * x\nend\n\ndef sum(n: Int, acc: Int) -> Int\n  if n == 0\n    acc\n  else\n    sum(n - 1, acc + sq(n))\n  end\nend\n\ndef fib(n: Int) -> Int\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\n  end\nend\n";

    #[test]
    fn a_slice_holds_what_its_definition_reaches_named_by_hash() {
        let s = slices(BASE);
        let (sq_hash, sq_slice) = &s["%root/sq"];
        let (_, sum_slice) = &s["%root/sum"];
        let (_, fib_slice) = &s["%root/fib"];
        let sq_name = format!("%root/d_{}", sq_hash.trim_start_matches("b3:"));
        assert!(sq_slice.contains(&sq_name), "{sq_slice}");
        assert!(sum_slice.contains(&sq_name), "{sum_slice}");
        assert!(!fib_slice.contains(&sq_name), "{fib_slice}");
        assert!(!fib_slice.contains("%root/fib"), "{fib_slice}");
        assert_eq!(sq_slice.lines().count(), 1);
        assert_eq!(sum_slice.lines().count(), 2);
    }

    #[test]
    fn an_edit_moves_what_reaches_it_and_a_rename_moves_nothing() {
        let base = slices(BASE);
        let edited = slices(&BASE.replace("x * x", "x * x + 1"));
        let renamed = slices(&BASE.replace("fib", "fibonacci"));
        assert_ne!(base["%root/sq"], edited["%root/sq"]);
        assert_ne!(base["%root/sum"], edited["%root/sum"]);
        assert_eq!(base["%root/fib"], edited["%root/fib"]);
        assert_eq!(base["%root/fib"], renamed["%root/fibonacci"]);
    }

    #[test]
    fn the_hash_is_the_one_def_hash_answers() {
        let c = checked(BASE);
        let lowered = c.lowered();
        let ids = blue_lang_mondou::def_hash::identified(
            &lowered,
            &blue_lang_mondou::program_docs(&c.program),
            None,
        );
        let s = slices(BASE);
        for key in ["%root/sq", "%root/sum", "%root/fib"] {
            assert_eq!(ids[key], s[key].0, "{key}");
        }
    }

    #[test]
    fn the_tier_decides_by_profile_unless_named() {
        assert_eq!(mode_of(None), Mode::Auto);
        assert_eq!(mode_of(Some("auto")), Mode::Auto);
        assert_eq!(mode_of(Some("off")), Mode::Off);
        assert_eq!(mode_of(Some("maybe")), Mode::Off);
        assert_eq!(mode_of(Some(" On ")), Mode::On);
        assert_eq!(mode_of(Some("1")), Mode::On);
    }

    #[test]
    fn an_artifact_that_does_not_answer_one_line_is_no_answer() {
        assert_eq!(
            answer(std::path::Path::new("/no/such/artifact"), ["1".to_string()]),
            None
        );
    }

    #[test]
    fn a_list_of_ints_crosses_the_seam_as_a_token_both_ways() {
        let sum = shape("(define-typed (%root/s (xs (List Int))) (List Int) xs)").expect("a shape");
        assert_eq!(sum, Shape::Typed(vec![Word::List], Word::List));
        assert!(!sum.in_words() && !sum.plain());
        let xs = Value::List(std::sync::Arc::new(
            vec![Value::Int(-1), Value::Int(20)].into(),
        ));
        assert_eq!(sum.tokens(&[xs]), Some(vec!["l-1,20".to_string()]));
        let strs = Value::List(std::sync::Arc::new(vec![Value::Str("a".into())].into()));
        assert_eq!(sum.tokens(&[strs]), None);
        assert!(matches!(sum.from_token("l3,4"), Some(Value::List(l)) if l.len() == 2));
        assert!(matches!(sum.from_token("l"), Some(Value::List(l)) if l.is_empty()));
        assert!(sum.from_token("l3,x").is_none());
        let bare = shape("(define-typed (%root/b (xs List)) Int 0)").expect("a shape");
        assert_eq!(bare, Shape::Typed(vec![Word::List], Word::Int));
    }

    #[test]
    fn a_str_crosses_the_seam_as_a_token_both_ways() {
        let greet =
            shape("(define-typed (%root/g (s Str) (n Int)) Str (concat s n))").expect("a shape");
        assert!(!greet.in_words() && !greet.plain());
        assert_eq!(greet.words(&[Value::Str("é".into()), Value::Int(2)]), None);
        assert_eq!(
            greet.tokens(&[Value::Str("é!".into()), Value::Int(2)]),
            Some(vec!["sc3a921".to_string(), "i2".to_string()])
        );
        assert!(matches!(greet.from_token("sc3a921"), Some(Value::Str(t)) if &*t == "é!"));
        assert!(greet.from_token("i2").is_none());
        let n = shape("(define-typed (%root/n (x Int)) Int x)").expect("a shape");
        assert!(n.plain());
        assert!(matches!(n.from_token("42"), Some(Value::Int(42))));
        assert!(matches!(n.from_token("i-7"), Some(Value::Int(-7))));
    }
}
