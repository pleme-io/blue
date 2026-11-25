//! `reach(def)`: what a definition reaches beyond its arguments.
//!
//! One walk of each definition's erased tree (what the evaluator runs) reads
//! what the definition names on its own; the definitions it calls, from
//! [`DefHashes`]'s call graph, carry the rest. Three answers come off the one
//! walk; the first and the last are the join of the two, read until nothing
//! changes, and the middle one leaves the walk over calls to its caller:
//!
//! - [`host_reach`]: every host capability (`blue_lang_waku::Capability::
//!   host_effects`) a definition reaches, with one chain to each: the
//!   definitions it goes through, then the primitive. What `blue query`'s
//!   `(reaches CAP)` reads.
//! - [`form_reach`]: what each top-level form names on its own, host
//!   capabilities and definitions, so a caller can walk from the forms it
//!   runs to every definition they reach. What `blue lock`'s floors of
//!   reached definitions read.
//! - [`reach_program`]: whether a definition's answer is a function of its
//!   arguments alone. It is [`Reach::Pure`] only when every name it writes is
//!   a local, a special form that computes, or a builtin whose documented
//!   topic has no effect (`crate::docs::Topic::effect`), and every
//!   definition it names is pure. Anything else is volatile, with the first
//!   reason found. What the call memo (`blue_lang_mondou::recall`) caches by.
//!
//! | reason | example |
//! |---|---|
//! | a host capability | `now_ms`, `read_file`, `argv` |
//! | an effect that is not the host's | `print` (output), `spawn` (processes), `chan`, `verb_for` |
//! | an answer that can change between equal calls | `gensym`, `eval`, `macroexpand` |
//! | a `set!` outside the frame that binds its target | a counter closed over |
//! | a name nothing classifies | a name a macro binds, a host's own primitive |
//! | a key two forms define | which one runs depends on when |
//! | the author's `volatile(f)` | f and everything reaching it |
//!
//! The purity rule is an allow-list: a name the table does not know is
//! volatile, so a primitive added without a row cannot be cached by mistake.
//! A local that shadows a primitive is not the primitive. Tier-honest, like
//! `blue_lang_waku::check_reach`: this reads names in a tree, so code built at
//! run time and `eval`ed is outside it, which is why `eval` itself is
//! volatile.

use std::collections::{BTreeMap, BTreeSet};

use crate::docs::{self, Effect};
use blue_lang_syntax::scope::{BinderKind, HeadKind, Scopes};
use blue_lang_syntax::{Span, Spanned};
use blue_lang_waku::Capability;
use tatara_lisp_eval::special::SpecialForm;

use crate::def_hash::DefHashes;

/// Each host capability a definition reaches, and one chain to it: the keys
/// of the definitions it goes through, then the primitive.
pub type HostReach = BTreeMap<Capability, Vec<String>>;

/// Whether a definition's calls may be answered from a memo.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Reach {
    Pure,
    Volatile(Volatility),
}

impl Reach {
    #[must_use]
    pub fn is_pure(&self) -> bool {
        matches!(self, Reach::Pure)
    }
}

/// Why a definition is volatile.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Volatility {
    /// It names a host capability.
    Host {
        capability: Capability,
        name: String,
    },
    /// It names a builtin with an effect that is not the host's.
    Effect { effect: Effect, name: String },
    /// It names something whose answer can differ between two equal calls.
    Nondeterministic { name: String },
    /// It assigns `name` outside the frame that binds it.
    Mutation { name: String },
    /// It names something with no known reach.
    Unknown { name: String },
    /// It names a key that more than one top-level form defines.
    Ambiguous { key: String },
    /// `volatile(f)` names it.
    Declared,
    /// It reaches `callee`, which is volatile.
    Through { callee: String },
}

impl std::fmt::Display for Volatility {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let shown = |n: &str| crate::observe::display_key(n);
        match self {
            Volatility::Host { capability, name } => {
                write!(f, "`{name}` reaches the host ({})", capability.label())
            }
            Volatility::Effect { effect, name } => {
                write!(f, "`{name}` has an effect ({})", effect.label())
            }
            Volatility::Nondeterministic { name } => {
                write!(f, "`{name}` can answer differently for the same arguments")
            }
            Volatility::Mutation { name } => {
                write!(f, "it assigns `{}` outside its own frame", shown(name))
            }
            Volatility::Unknown { name } => write!(f, "`{}` has no known reach", shown(name)),
            Volatility::Ambiguous { key } => {
                write!(f, "`{}` is defined more than once", shown(key))
            }
            Volatility::Declared => f.write_str("declared with volatile(…)"),
            Volatility::Through { callee } => write!(f, "it reaches `{}`", shown(callee)),
        }
    }
}

/// The builtins whose topic computes but which answer differently for equal
/// calls, or rebind the program's names. `def_hash` is one: its answer
/// covers `@doc` text the memo's key does not, and is nil where the door
/// identifies no program. Each is a row of
/// `crate::docs::NAMES` or a special form; a test fails when one
/// stops being either.
const NONDETERMINISTIC: &[&str] = &[
    "gensym",
    "defsm",
    "defcommand",
    "defquery",
    "defactor",
    "def_hash",
    "cell",
    "cell_get",
    "cell_put",
];

/// The host capability that grants `name`, if one does.
#[must_use]
pub fn host_capability(name: &str) -> Option<Capability> {
    Capability::host_effects()
        .into_iter()
        .find(|c| c.grants(name))
}

/// The reach of one builtin name: `Ok` when calling it only computes.
///
/// # Errors
///
/// The volatility it carries.
pub fn builtin(name: &str) -> Result<(), Volatility> {
    if let Some(capability) = host_capability(name) {
        return Err(Volatility::Host {
            capability,
            name: name.to_string(),
        });
    }
    if let Some(form) = SpecialForm::from_symbol(name) {
        return special(form, name);
    }
    if NONDETERMINISTIC.contains(&name) {
        return Err(Volatility::Nondeterministic {
            name: name.to_string(),
        });
    }
    if bundled(name) {
        return Ok(());
    }
    if Capability::Assertion.grants(name) {
        return Err(Volatility::Effect {
            effect: Effect::Output,
            name: name.to_string(),
        });
    }
    match docs::doc_of(name).map(|d| d.topic.effect()) {
        Some(None) => Ok(()),
        Some(Some(effect)) => Err(Volatility::Effect {
            effect,
            name: name.to_string(),
        }),
        None => Err(Volatility::Unknown {
            name: name.to_string(),
        }),
    }
}

fn bundled(name: &str) -> bool {
    [
        Capability::CoreForms,
        Capability::Operators,
        Capability::Collections,
        Capability::Interpolation,
    ]
    .iter()
    .any(|c| c.grants(name))
}

/// Whether the builtin `name` calls its argument at position `i`: never for
/// the words the language's own syntax lowers to (operators, collections,
/// interpolation, control flow), else as its documented signature says
/// ([`docs::calls_argument`]).
#[must_use]
pub fn calls_argument(name: &str, i: usize) -> bool {
    !bundled(name) && docs::calls_argument(name, i)
}

/// Whether the builtin `name` calls any argument ([`calls_argument`]).
#[must_use]
pub fn calls_arguments(name: &str) -> bool {
    !bundled(name) && docs::calls_arguments(name)
}

/// Exhaustive, so a special form added upstream decides here.
fn special(form: SpecialForm, name: &str) -> Result<(), Volatility> {
    match form {
        SpecialForm::Quote
        | SpecialForm::Quasiquote
        | SpecialForm::If
        | SpecialForm::Cond
        | SpecialForm::When
        | SpecialForm::Unless
        | SpecialForm::Let
        | SpecialForm::LetStar
        | SpecialForm::LetRec
        | SpecialForm::Lambda
        | SpecialForm::Define
        | SpecialForm::Set
        | SpecialForm::Begin
        | SpecialForm::And
        | SpecialForm::Or
        | SpecialForm::Not
        | SpecialForm::Try
        | SpecialForm::Delay => Ok(()),
        SpecialForm::Eval | SpecialForm::MacroexpandOne | SpecialForm::MacroexpandAll => {
            Err(Volatility::Nondeterministic {
                name: name.to_string(),
            })
        }
        SpecialForm::Require | SpecialForm::Provide => Err(Volatility::Host {
            capability: Capability::FileSystem,
            name: name.to_string(),
        }),
    }
}

/// The word that declares a definition volatile.
pub const DECLARE: &str = "volatile";

/// The word that declares a definition may suspend (A-colour of
/// docs/ASYNC.md).
pub const DECLARE_SUSPENDS: &str = "suspends";

/// Heads the evaluator never sees as calls: declarations the stages before
/// it consume.
const STRUCTURAL: &[&str] = &["define-typed", "defmacro", "deftest", "use"];

/// What one definition names on its own, before what it reaches.
struct Own {
    host: HostReach,
    first: Option<Volatility>,
    calls_value: bool,
    suspends: Option<String>,
}

impl Own {
    fn empty() -> Self {
        Own {
            host: HostReach::new(),
            first: None,
            calls_value: false,
            suspends: None,
        }
    }
}

/// What `form` names on its own, and every key it assigns outside the frame
/// that binds it, added to `assigned`.
fn own_of(form: &Spanned, keys: &BTreeSet<&str>, assigned: &mut BTreeSet<String>) -> Own {
    own_within(form, keys, assigned, Vec::new())
}

fn own_within(
    form: &Spanned,
    keys: &BTreeSet<&str>,
    assigned: &mut BTreeSet<String>,
    frames: Vec<BTreeSet<String>>,
) -> Own {
    let mut pass = Pass {
        keys,
        frames,
        own: Own::empty(),
        assigning: false,
        assigned,
    };
    blue_lang_syntax::scope::walk_top(form, &mut pass);
    pass.own
}

/// One walk per definition of `hashes`, in its order, and every key the
/// program assigns outside the frame that binds it.
fn walk(erased: &[Spanned], hashes: &DefHashes) -> (Vec<Own>, BTreeSet<String>) {
    let keys: BTreeSet<&str> = hashes.keys().collect();
    let mut assigned = BTreeSet::new();
    let mut own: Vec<Own> = hashes.defs().iter().map(|_| Own::empty()).collect();
    for (top_level, form) in erased.iter().enumerate() {
        let found = own_of(form, &keys, &mut assigned);
        if let Some(d) = hashes.index_at(top_level) {
            own[d] = found;
        }
    }
    (own, assigned)
}

/// What one top-level form names on its own, before what it reaches.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct FormReach {
    /// Each host capability the form's own code names, with the first
    /// primitive that names it.
    pub host: BTreeMap<Capability, String>,
    /// The other definitions the form names, by index in
    /// [`DefHashes::defs`]: a call, or a definition passed as a value. A key
    /// more than one form binds names each of them, since which one runs
    /// depends on when.
    pub names: Vec<usize>,
}

/// One [`FormReach`] per top-level form of `erased`, a definition or not,
/// `erased` as for [`host_reach`]. The edges a walk from some forms follows
/// to every definition they can call: what a floor of only the reached
/// definitions reads (`blue_lang_pkg::capabilities`). A form that is not a
/// definition, such as a bare call at the top level, runs when its file
/// loads, so it is here too.
#[must_use]
pub fn form_reach(erased: &[Spanned], hashes: &DefHashes) -> Vec<FormReach> {
    let keys: BTreeSet<&str> = hashes.keys().collect();
    let mut by_key: BTreeMap<&str, Vec<usize>> = BTreeMap::new();
    for (i, def) in hashes.defs().iter().enumerate() {
        by_key.entry(def.key.as_str()).or_default().push(i);
    }
    let mut assigned = BTreeSet::new();
    erased
        .iter()
        .enumerate()
        .map(|(top_level, form)| {
            let own = own_of(form, &keys, &mut assigned);
            let itself = hashes.index_at(top_level);
            let mut named = Vec::new();
            names_of_keys(form, &keys, &mut named);
            let mut names: Vec<usize> = named
                .into_iter()
                .filter_map(|k| by_key.get(k))
                .flatten()
                .copied()
                .filter(|&d| Some(d) != itself)
                .collect();
            names.sort_unstable();
            names.dedup();
            FormReach {
                host: own
                    .host
                    .into_iter()
                    .filter_map(|(cap, chain)| Some((cap, chain.into_iter().next()?)))
                    .collect(),
                names,
            }
        })
        .collect()
}

/// The host reach of every definition in `hashes`, in the same order.
/// `erased` is the tree the evaluator runs ([`crate::erase::unfused`] of the tree `hashes` was computed from), one form per
/// top-level form.
#[must_use]
pub fn host_reach(erased: &[Spanned], hashes: &DefHashes) -> Vec<HostReach> {
    chained(
        hashes,
        walk(erased, hashes).0.into_iter().map(|o| o.host).collect(),
    )
}

/// Each definition of `hashes`, in the same order, that can reach a
/// suspension point (`blue_lang_proc::node::SUSPENDING`), with one chain to
/// it: the definitions it goes through, then the word. `erased` as for
/// [`host_reach`]. Tier-honest: it reads names, so a definition that names
/// `receive` only inside a function it hands to `spawn` counts too.
#[must_use]
pub fn suspension_reach(erased: &[Spanned], hashes: &DefHashes) -> Vec<Option<Vec<String>>> {
    let own = walk(erased, hashes)
        .0
        .into_iter()
        .map(|o| o.suspends.map(|w| ((), vec![w])).into_iter().collect())
        .collect();
    chained(hashes, own)
        .into_iter()
        .map(|mut m: BTreeMap<(), Vec<String>>| m.remove(&()))
        .collect()
}

/// The keys `suspends(key)` declares in `erased`.
#[must_use]
pub fn declared_suspending(erased: &[Spanned], hashes: &DefHashes) -> BTreeSet<String> {
    let keys: BTreeSet<&str> = hashes.keys().collect();
    let mut out = BTreeSet::new();
    for form in erased {
        declarations(form, DECLARE_SUSPENDS, &keys, &mut out);
    }
    out
}

/// `own` joined over the call graph of `hashes` until nothing changes: each
/// definition gains every key a definition it calls reaches, with the callee
/// put in front of its chain.
fn chained<K: Ord + Clone>(
    hashes: &DefHashes,
    mut out: Vec<BTreeMap<K, Vec<String>>>,
) -> Vec<BTreeMap<K, Vec<String>>> {
    let defs = hashes.defs();
    loop {
        let mut changed = false;
        for (d, def) in defs.iter().enumerate() {
            let mut found: Vec<(K, Vec<String>)> = Vec::new();
            for &c in &def.calls {
                if c == d {
                    continue;
                }
                for (k, chain) in &out[c] {
                    if !out[d].contains_key(k) && !found.iter().any(|(f, _)| f == k) {
                        let mut via = vec![defs[c].key.clone()];
                        via.extend(chain.iter().cloned());
                        found.push((k.clone(), via));
                    }
                }
            }
            for (k, via) in found {
                out[d].insert(k, via);
                changed = true;
            }
        }
        if !changed {
            return out;
        }
    }
}

/// The reach of every definition in `hashes`, in the same order, `erased` as
/// for [`host_reach`]: what reaches the host is what runs, and a type is not
/// a name anything calls.
#[must_use]
pub fn reach_program(erased: &[Spanned], hashes: &DefHashes) -> Vec<Reach> {
    let defs = hashes.defs();
    let keys: BTreeSet<&str> = hashes.keys().collect();
    let (own, assigned) = walk(erased, hashes);
    let mut declared: BTreeSet<String> = BTreeSet::new();
    for form in erased {
        declarations(form, DECLARE, &keys, &mut declared);
    }
    let mut out: Vec<Reach> = own
        .into_iter()
        .zip(defs)
        .map(|(o, def)| {
            let why = o.first.or_else(|| {
                if hashes.is_ambiguous(&def.key) {
                    Some(Volatility::Ambiguous {
                        key: def.key.clone(),
                    })
                } else if declared.contains(&def.key) {
                    Some(Volatility::Declared)
                } else if assigned.contains(&def.key) {
                    Some(Volatility::Mutation {
                        name: def.key.clone(),
                    })
                } else {
                    None
                }
            });
            why.map_or(Reach::Pure, Reach::Volatile)
        })
        .collect();
    for (d, def) in defs.iter().enumerate() {
        if !out[d].is_pure() {
            continue;
        }
        let Some(form) = erased.get(def.top_level) else {
            continue;
        };
        let mut named = Vec::new();
        names_of_keys(form, &keys, &mut named);
        if let Some(k) = named.into_iter().find(|k| hashes.is_ambiguous(k)) {
            out[d] = Reach::Volatile(Volatility::Ambiguous { key: k.to_string() });
        }
    }
    loop {
        let mut changed = false;
        for (d, def) in defs.iter().enumerate() {
            if !out[d].is_pure() {
                continue;
            }
            if let Some(&c) = def.calls.iter().find(|&&c| !out[c].is_pure()) {
                out[d] = Reach::Volatile(Volatility::Through {
                    callee: defs[c].key.clone(),
                });
                changed = true;
            }
        }
        if !changed {
            return out;
        }
    }
}

/// Whether each definition of `hashes`, in the same order, is first-order
/// pure: [`Reach::Pure`], it never calls a function value it was handed (a
/// local in a call's head, or anything but a lambda written in place or a
/// global in an argument a builtin calls), and every definition it names is
/// first-order pure. Calling one only computes, whatever it is handed, so
/// the order of its calls is unobservable but for which error comes first.
/// `erased` as for [`host_reach`].
#[must_use]
pub fn first_order_program(erased: &[Spanned], hashes: &DefHashes) -> Vec<bool> {
    let defs = hashes.defs();
    let keys: BTreeSet<&str> = hashes.keys().collect();
    let (own, _) = walk(erased, hashes);
    let mut out: Vec<bool> = reach_program(erased, hashes)
        .iter()
        .zip(&own)
        .map(|(r, o)| r.is_pure() && !o.calls_value)
        .collect();
    let named: Vec<Vec<usize>> = defs
        .iter()
        .map(|def| {
            let mut names = Vec::new();
            if let Some(form) = erased.get(def.top_level) {
                names_of_keys(form, &keys, &mut names);
            }
            names
                .into_iter()
                .flat_map(|k| (0..defs.len()).filter(move |&c| defs[c].key == k))
                .collect()
        })
        .collect();
    loop {
        let mut changed = false;
        for d in 0..defs.len() {
            if out[d] && named[d].iter().any(|&c| !out[c]) {
                out[d] = false;
                changed = true;
            }
        }
        if !changed {
            return out;
        }
    }
}

/// The keys a function written in place names, when calling it only
/// computes and never calls a function value it was handed
/// ([`first_order_program`]'s rule for one expression); `None` otherwise.
/// `outer` are the locals in scope where it is written, `keys` every key the
/// program binds. The keys it names are the caller's to hold to
/// [`first_order_program`].
#[must_use]
pub fn first_order_callback<'a>(
    form: &'a Spanned,
    outer: &BTreeSet<String>,
    keys: &BTreeSet<&str>,
) -> Option<Vec<&'a str>> {
    let mut assigned = BTreeSet::new();
    let own = own_within(form, keys, &mut assigned, vec![outer.clone()]);
    if own.first.is_some() || own.calls_value {
        return None;
    }
    let mut names = Vec::new();
    names_of_keys(form, keys, &mut names);
    Some(names)
}

/// Every key a `word(key)` call in `form` names.
fn declarations(form: &Spanned, word: &str, keys: &BTreeSet<&str>, out: &mut BTreeSet<String>) {
    let Some(items) = form.as_list() else {
        return;
    };
    if let [head, target] = items {
        if head.as_symbol() == Some(word) {
            if let Some(k) = declared_key(target).filter(|k| keys.contains(k)) {
                out.insert(k.to_string());
            }
        }
    }
    for i in items {
        declarations(i, word, keys, out);
    }
}

/// The key a declaration's argument names: `f`, or `fn() f end` for an `f`
/// with no parameters, which is called where its name is written bare.
fn declared_key(target: &Spanned) -> Option<&str> {
    if let Some(k) = target.as_symbol() {
        return Some(k);
    }
    match target.as_list()? {
        [lambda, params, body] if lambda.as_symbol() == Some("lambda") => {
            if !params.as_list().is_some_and(<[Spanned]>::is_empty) {
                return None;
            }
            match body.as_list()? {
                [call] => call.as_symbol(),
                _ => None,
            }
        }
        _ => None,
    }
}

fn names_of_keys<'a>(form: &'a Spanned, keys: &BTreeSet<&str>, out: &mut Vec<&'a str>) {
    if let Some(s) = form.as_symbol() {
        if keys.contains(s) {
            out.push(s);
        }
    } else if let Some(items) = form.as_list() {
        for i in items {
            names_of_keys(i, keys, out);
        }
    }
}

/// One top-level form's walk: the first primitive of each host capability it
/// names on its own, the first volatile name, and every key it assigns.
struct Pass<'a> {
    keys: &'a BTreeSet<&'a str>,
    frames: Vec<BTreeSet<String>>,
    own: Own,
    /// The next reference is the target of a `set!`.
    assigning: bool,
    assigned: &'a mut BTreeSet<String>,
}

impl Pass<'_> {
    fn note(&mut self, v: Volatility) {
        if let Volatility::Host { capability, name } = &v {
            self.own
                .host
                .entry(*capability)
                .or_insert_with(|| vec![name.clone()]);
        }
        if self.own.first.is_none() {
            self.own.first = Some(v);
        }
    }

    fn bound(&self, name: &str) -> bool {
        self.frames.iter().any(|f| f.contains(name))
    }

    fn built_here(&self, arg: &Spanned) -> bool {
        match arg.as_symbol() {
            Some(n) => !self.bound(n) && (self.keys.contains(n) || !calls_arguments(n)),
            None => arg
                .as_list()
                .and_then(|items| items.first())
                .and_then(Spanned::as_symbol)
                .is_some_and(|h| h == "lambda" && !self.bound(h)),
        }
    }

    fn name(&mut self, name: &str) {
        if self.assigning {
            self.assigning = false;
            let innermost = self.frames.last().is_some_and(|f| f.contains(name));
            if !innermost {
                if self.keys.contains(name) {
                    self.assigned.insert(name.to_string());
                }
                self.note(Volatility::Mutation {
                    name: name.to_string(),
                });
            }
            return;
        }
        if self.bound(name) || self.keys.contains(name) {
            return;
        }
        if self.own.suspends.is_none() && blue_lang_proc::node::SUSPENDING.contains(&name) {
            self.own.suspends = Some(name.to_string());
        }
        if let Err(v) = builtin(name) {
            self.note(v);
        }
    }
}

impl Scopes for Pass<'_> {
    fn head_kind(&self, name: &str) -> Option<HeadKind> {
        (SpecialForm::from_symbol(name).is_some()
            || blue_lang_syntax::scope::SHAPED_FORMS.contains(&name))
        .then_some(HeadKind::SpecialForm)
    }
    fn open(&mut self) {
        self.frames.push(BTreeSet::new());
    }
    fn bind(&mut self, name: &str, _: Span, _: BinderKind) {
        if let Some(f) = self.frames.last_mut() {
            f.insert(name.to_string());
        }
    }
    fn close(&mut self) {
        self.frames.pop();
    }
    fn reference(&mut self, _: &Spanned, name: &str, _opaque: bool) {
        self.name(name);
    }
    fn call(&mut self, _: &Spanned, whole: &Spanned, name: &str, _opaque: bool) {
        self.name(name);
        if self.bound(name) {
            self.own.calls_value = true;
            return;
        }
        if self.keys.contains(name) {
            return;
        }
        let args = whole.as_list().map_or(&[][..], |items| &items[1..]);
        if args
            .iter()
            .enumerate()
            .any(|(i, a)| calls_argument(name, i) && !self.built_here(a))
        {
            self.own.calls_value = true;
        }
    }
    fn value_head(&mut self, _: &Spanned) {
        self.own.calls_value = true;
    }
    fn head(&mut self, _: &Spanned, name: &str, _: HeadKind) {
        if name == "set!" {
            self.assigning = true;
            return;
        }
        if STRUCTURAL.contains(&name) || self.bound(name) || self.keys.contains(name) {
            return;
        }
        if let Err(v) = builtin(name) {
            self.note(v);
        }
    }
    fn template_symbol(&mut self, _: &Spanned, name: &str) {
        if self.bound(name) || self.keys.contains(name) {
            return;
        }
        match builtin(name) {
            Ok(()) | Err(Volatility::Unknown { .. }) => {}
            Err(v) => self.note(v),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    use crate::def_hash::hash_program;

    fn reaches(src: &str) -> HashMap<String, Reach> {
        let checked = crate::pipeline::check_entry(
            crate::uses::Entry::anonymous(src),
            &crate::uses::NoLoader,
            None,
            crate::pipeline::Checking::Program,
        )
        .expect("checks");
        assert!(checked.outcome.ok(), "{:?}", checked.outcome.diagnostics);
        let lowered = crate::pipeline::lower(&checked.program, &checked.names);
        let hashes = hash_program(&lowered);
        let reach = reach_program(&crate::erase_types(&lowered), &hashes);
        hashes
            .defs()
            .iter()
            .zip(reach)
            .map(|(d, r)| (crate::observe::display_key(&d.key), r))
            .collect()
    }

    fn suspending(src: &str) -> (HashMap<String, Option<Vec<String>>>, BTreeSet<String>) {
        let checked = crate::pipeline::check_entry(
            crate::uses::Entry::anonymous(src),
            &crate::uses::NoLoader,
            None,
            crate::pipeline::Checking::Program,
        )
        .expect("checks");
        let lowered = crate::pipeline::lower(&checked.program, &checked.names);
        let hashes = hash_program(&lowered);
        let erased = crate::erase_types(&lowered);
        let shown = |k: &String| crate::observe::display_key(k);
        let chains = hashes
            .defs()
            .iter()
            .zip(suspension_reach(&erased, &hashes))
            .map(|(d, c)| (shown(&d.key), c.map(|c| c.iter().map(shown).collect())))
            .collect();
        let declared = declared_suspending(&erased, &hashes)
            .iter()
            .map(shown)
            .collect();
        (chains, declared)
    }

    #[test]
    fn a_definition_that_reaches_a_park_word_suspends_and_so_does_every_caller() {
        let src = "def wait()\n  receive(:_, 10, nil)\nend\n\ndef outer()\n  wait()\nend\n\ndef nap(ms)\n  sleep_for(ms)\nend\n\ndef clean(x)\n  x + 1\nend\n\nsuspends(fn() outer end)\n";
        let (r, declared) = suspending(src);
        assert_eq!(r["wait"], Some(vec!["receive".to_string()]));
        assert_eq!(
            r["outer"],
            Some(vec!["wait".to_string(), "receive".to_string()])
        );
        assert_eq!(r["nap"], Some(vec!["sleep_for".to_string()]));
        assert_eq!(r["clean"], None);
        assert_eq!(declared, BTreeSet::from(["outer".to_string()]));
    }

    #[test]
    fn a_local_named_like_a_park_word_does_not_suspend() {
        let src = "def f(receive)\n  receive + 1\nend\n";
        assert_eq!(suspending(src).0["f"], None);
    }

    fn pure(src: &str, name: &str) -> bool {
        reaches(src)
            .get(name)
            .unwrap_or_else(|| panic!("{name} is not defined"))
            .is_pure()
    }

    #[test]
    fn arithmetic_lists_maps_strings_and_recursion_are_pure() {
        let src = "def fib(n)\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\n  end\nend\n\ndef shape(xs)\n  m = {a: 1}\n  \"#{length(xs)} #{m}\"\nend\n\ndef twice(xs)\n  map(xs, fn(x) x * 2 end)\nend\n";
        for name in ["fib", "shape", "twice"] {
            assert!(pure(src, name), "{name}: {:?}", reaches(src)[name]);
        }
    }

    #[test]
    fn a_rescue_that_reads_no_field_stays_pure() {
        let src = "def caught(x)\n  1 / x\nrescue e\n  e\nend\n";
        assert!(pure(src, "caught"), "{:?}", reaches(src)["caught"]);
    }

    #[test]
    fn a_host_capability_an_effect_or_a_fresh_name_is_volatile_and_so_is_every_caller() {
        let src = "def stamp()\n  now_ms()\nend\n\ndef caller()\n  stamp() + 1\nend\n\ndef shout(x)\n  print(x)\n  x\nend\n\ndef fresh()\n  gensym()\nend\n\ndef args()\n  argv()\nend\n\ndef clean(x)\n  x + 1\nend\n";
        let r = reaches(src);
        assert!(matches!(
            r["stamp"],
            Reach::Volatile(Volatility::Host {
                capability: Capability::Clock,
                ..
            })
        ));
        assert!(matches!(
            &r["caller"],
            Reach::Volatile(Volatility::Through { callee }) if callee == "%root/stamp"
        ));
        assert!(matches!(
            r["shout"],
            Reach::Volatile(Volatility::Effect {
                effect: Effect::Output,
                ..
            })
        ));
        assert!(matches!(
            r["fresh"],
            Reach::Volatile(Volatility::Nondeterministic { .. })
        ));
        assert!(matches!(
            r["args"],
            Reach::Volatile(Volatility::Host {
                capability: Capability::Environment,
                ..
            })
        ));
        assert!(r["clean"].is_pure());
    }

    #[test]
    fn the_declaration_makes_a_definition_and_its_callers_volatile() {
        let src = "def f(x)\n  x * 2\nend\n\ndef g(x)\n  f(x) + 1\nend\n\ndef h(x)\n  x - 1\nend\n\nvolatile(f)\n";
        let r = reaches(src);
        assert_eq!(r["f"], Reach::Volatile(Volatility::Declared));
        assert!(matches!(
            r["g"],
            Reach::Volatile(Volatility::Through { .. })
        ));
        assert!(r["h"].is_pure());
    }

    #[test]
    fn assigning_outside_the_own_frame_is_volatile_and_a_local_assignment_is_not() {
        let src = "def make_counter()\n  n = 0\n  fn()\n    set!(n, n + 1)\n    n\n  end\nend\n\ncounter = make_counter()\n\ndef next_id()\n  counter()\nend\n\ndef local(x)\n  y = x\n  set!(y, y + 1)\n  y\nend\n\ntotal = 0\n\ndef bump(x)\n  set!(total, total + x)\nend\n\ndef read_total()\n  total\nend\n";
        let r = reaches(src);
        assert!(matches!(
            r["make_counter"],
            Reach::Volatile(Volatility::Mutation { .. })
        ));
        assert!(!r["next_id"].is_pure(), "{:?}", r["next_id"]);
        assert!(r["local"].is_pure(), "{:?}", r["local"]);
        assert!(!r["bump"].is_pure());
        assert!(
            matches!(&r["total"], Reach::Volatile(Volatility::Mutation { .. })),
            "{:?}",
            r["total"]
        );
        assert!(!r["read_total"].is_pure(), "{:?}", r["read_total"]);
    }

    fn forms(src: &str) -> (Vec<FormReach>, DefHashes) {
        let checked = crate::pipeline::check_entry(
            crate::uses::Entry::anonymous(src),
            &crate::uses::NoLoader,
            None,
            crate::pipeline::Checking::Program,
        )
        .expect("checks");
        let lowered = crate::pipeline::lower(&checked.program, &checked.names);
        let hashes = hash_program(&lowered);
        (form_reach(&crate::erase_types(&lowered), &hashes), hashes)
    }

    #[test]
    fn each_form_names_its_own_host_words_and_the_definitions_it_names_and_nothing_further() {
        let src = "def stamp()\n  now_ms\nend\n\ndef wrap()\n  stamp + 1\nend\n\ndef pure(x)\n  x * 2\nend\n\nwrite_stdout(\"#{wrap} #{read_file(\"/x\")}\")\n";
        let (forms, hashes) = forms(src);
        let index = |name: &str| {
            hashes
                .defs()
                .iter()
                .position(|d| crate::observe::display_key(&d.key) == name)
                .unwrap_or_else(|| panic!("{name} is not defined"))
        };
        let at = |name: &str| &forms[hashes.defs()[index(name)].top_level];
        assert_eq!(
            at("stamp").host,
            BTreeMap::from([(Capability::Clock, "now_ms".to_string())])
        );
        assert!(
            at("wrap").host.is_empty(),
            "the clock is stamp's, reached through it, not wrap's own"
        );
        assert_eq!(at("wrap").names, vec![index("stamp")]);
        assert!(at("pure").host.is_empty() && at("pure").names.is_empty());
        let top = forms.last().expect("the bare call is a form");
        assert_eq!(
            top.host,
            BTreeMap::from([(Capability::FileSystem, "read_file".to_string())])
        );
        assert_eq!(top.names, vec![index("wrap")]);
        assert_eq!(forms.len(), 4);
    }

    #[test]
    fn every_listed_exception_names_something_the_runtime_binds() {
        let interp = crate::interpreter_hostless();
        for name in NONDETERMINISTIC {
            assert!(
                interp.resolve_head(name).is_some(),
                "`{name}` is listed as nondeterministic and the runtime binds nothing by that name"
            );
        }
    }

    #[test]
    fn every_documented_builtin_is_classified_by_its_topic_or_an_exception() {
        for d in docs::NAMES {
            let got = builtin(d.name);
            let listed = NONDETERMINISTIC.contains(&d.name)
                || SpecialForm::from_symbol(d.name).is_some_and(|f| special(f, d.name).is_err())
                || Capability::host_effects().iter().any(|c| c.grants(d.name));
            match (d.topic.effect(), got) {
                (None, Ok(())) => assert!(!listed, "{}", d.name),
                (None, Err(_)) => assert!(listed, "{} is volatile with a pure topic", d.name),
                (Some(_), Err(_)) => {}
                (Some(e), Ok(())) => panic!("{} has effect {e:?} and reads as pure", d.name),
            }
        }
    }
}
