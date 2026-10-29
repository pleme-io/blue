//! `reach(def)`: what a definition reaches beyond its arguments
//! (`theory/BLUE-ENGINE.md` §3.5).
//!
//! One walk of each definition's erased tree (what the evaluator runs) reads
//! what the definition names on its own; the definitions it calls, from
//! [`DefHashes`]'s call graph, carry the rest. Each answer is the join of the
//! two, read until nothing changes. Two answers come off the one walk:
//!
//! - [`host_reach`]: every host capability (`blue_lang_waku::Capability::
//!   host_effects`) a definition reaches, with one chain to each: the
//!   definitions it goes through, then the primitive. What `blue query`'s
//!   `(reaches CAP)` reads.
//! - [`reach_program`]: whether a definition's answer is a function of its
//!   arguments alone. It is [`Reach::Pure`] only when every name it writes is
//!   a local, a special form that computes, or a builtin whose documented
//!   topic has no effect (`blue_lang_runtime::docs::Topic::effect`), and every
//!   definition it names is pure. Anything else is volatile, with the first
//!   reason found. What the call memo ([`crate::recall`]) caches by.
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

use blue_lang_runtime::docs::{self, Effect};
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
        let shown = |n: &str| blue_lang_runtime::observe::display_key(n);
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
/// calls, or rebind the program's names. Each is a row of
/// `blue_lang_runtime::docs::NAMES` or a special form; a test fails when one
/// stops being either.
const NONDETERMINISTIC: &[&str] = &["gensym", "defsm", "defcommand", "defquery", "defactor"];

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
    let pure_bundle = [
        Capability::CoreForms,
        Capability::Operators,
        Capability::Collections,
        Capability::Interpolation,
    ];
    if pure_bundle.iter().any(|c| c.grants(name)) {
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

/// Heads the evaluator never sees as calls: declarations the stages before
/// it consume.
const STRUCTURAL: &[&str] = &["define-typed", "defmacro", "deftest", "use"];

/// What one definition names on its own, before what it reaches.
struct Own {
    host: HostReach,
    first: Option<Volatility>,
}

/// One walk per definition of `hashes`, in its order, and every key the
/// program assigns outside the frame that binds it.
fn walk(erased: &[Spanned], hashes: &DefHashes) -> (Vec<Own>, BTreeSet<String>) {
    let keys: BTreeSet<&str> = hashes.keys().collect();
    let mut assigned = BTreeSet::new();
    let mut own: Vec<Own> = hashes
        .defs()
        .iter()
        .map(|_| Own {
            host: HostReach::new(),
            first: None,
        })
        .collect();
    for (top_level, form) in erased.iter().enumerate() {
        let mut pass = Pass {
            keys: &keys,
            frames: Vec::new(),
            own: Own {
                host: HostReach::new(),
                first: None,
            },
            assigning: false,
            assigned: &mut assigned,
        };
        blue_lang_syntax::scope::walk_top(form, &mut pass);
        if let Some(d) = hashes.index_at(top_level) {
            own[d] = pass.own;
        }
    }
    (own, assigned)
}

/// The host reach of every definition in `hashes`, in the same order.
/// `erased` is the tree the evaluator runs ([`blue_lang_runtime::
/// erase_types`] of the tree `hashes` was computed from), one form per
/// top-level form.
#[must_use]
pub fn host_reach(erased: &[Spanned], hashes: &DefHashes) -> Vec<HostReach> {
    let defs = hashes.defs();
    let mut out: Vec<HostReach> = walk(erased, hashes).0.into_iter().map(|o| o.host).collect();
    loop {
        let mut changed = false;
        for (d, def) in defs.iter().enumerate() {
            let mut found: Vec<(Capability, Vec<String>)> = Vec::new();
            for &c in &def.calls {
                if c == d {
                    continue;
                }
                for (cap, chain) in &out[c] {
                    if !out[d].contains_key(cap) && !found.iter().any(|(f, _)| f == cap) {
                        let mut via = vec![defs[c].key.clone()];
                        via.extend(chain.iter().cloned());
                        found.push((*cap, via));
                    }
                }
            }
            for (cap, via) in found {
                out[d].insert(cap, via);
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
        declarations(form, &keys, &mut declared);
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

/// Every key a `volatile(key)` call in `form` names.
fn declarations(form: &Spanned, keys: &BTreeSet<&str>, out: &mut BTreeSet<String>) {
    let Some(items) = form.as_list() else {
        return;
    };
    if let [head, target] = items {
        if head.as_symbol() == Some(DECLARE) {
            if let Some(k) = target.as_symbol().filter(|k| keys.contains(k)) {
                out.insert(k.to_string());
            }
        }
    }
    for i in items {
        declarations(i, keys, out);
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
        let checked = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(src),
            &blue_lang_runtime::uses::NoLoader,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .expect("checks");
        assert!(checked.outcome.ok(), "{:?}", checked.outcome.diagnostics);
        let lowered = blue_lang_runtime::pipeline::lower(&checked.program, &checked.names);
        let hashes = hash_program(&lowered);
        let reach = reach_program(&blue_lang_runtime::erase_types(&lowered), &hashes);
        hashes
            .defs()
            .iter()
            .zip(reach)
            .map(|(d, r)| (blue_lang_runtime::observe::display_key(&d.key), r))
            .collect()
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

    #[test]
    fn every_listed_exception_names_something_the_runtime_binds() {
        let interp = blue_lang_runtime::interpreter_hostless();
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
