//! `reach(def)`: what a definition reaches beyond its arguments
//! (`theory/BLUE-ENGINE.md` §3.5).
//!
//! One walk of each definition's erased tree (what the evaluator runs) reads
//! what the definition names on its own; the definitions it calls, from
//! [`DefHashes`]'s call graph, carry the rest. The answer is the join of the
//! two, read until nothing changes.
//!
//! [`host_reach`] is every host capability (`blue_lang_waku::Capability::
//! host_effects`) a definition reaches, with one chain to each: the
//! definitions it goes through, then the primitive. A local that shadows a
//! primitive is not the primitive. Tier-honest, like `blue_lang_waku::
//! check_reach`: this reads names in a tree, so code built at run time and
//! `eval`ed is outside it.

use std::collections::{BTreeMap, BTreeSet};

use blue_lang_syntax::scope::{BinderKind, HeadKind, Scopes};
use blue_lang_syntax::{Span, Spanned};
use blue_lang_waku::Capability;
use tatara_lisp_eval::special::SpecialForm;

use crate::def_hash::DefHashes;

/// Each host capability a definition reaches, and one chain to it: the keys
/// of the definitions it goes through, then the primitive.
pub type HostReach = BTreeMap<Capability, Vec<String>>;

/// The host capability that grants `name`, if one does.
#[must_use]
pub fn host_capability(name: &str) -> Option<Capability> {
    Capability::host_effects()
        .into_iter()
        .find(|c| c.grants(name))
}

/// Heads the evaluator never sees as calls: declarations the stages before
/// it consume.
const STRUCTURAL: &[&str] = &["define-typed", "defmacro", "deftest", "use"];

/// The host reach of every definition in `hashes`, in the same order.
/// `erased` is the tree the evaluator runs ([`blue_lang_runtime::
/// erase_types`] of the tree `hashes` was computed from), one form per
/// top-level form.
#[must_use]
pub fn host_reach(erased: &[Spanned], hashes: &DefHashes) -> Vec<HostReach> {
    let defs = hashes.defs();
    let keys: BTreeSet<&str> = hashes.keys().collect();
    let mut out: Vec<HostReach> = defs
        .iter()
        .map(|d| {
            let Some(form) = erased.get(d.top_level) else {
                return HostReach::new();
            };
            let mut pass = Pass {
                keys: &keys,
                frames: Vec::new(),
                host: HostReach::new(),
            };
            blue_lang_syntax::scope::walk_top(form, &mut pass);
            pass.host
        })
        .collect();
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

/// One top-level form's walk: the first primitive of each host capability it
/// names on its own.
struct Pass<'a> {
    keys: &'a BTreeSet<&'a str>,
    frames: Vec<BTreeSet<String>>,
    host: HostReach,
}

impl Pass<'_> {
    fn bound(&self, name: &str) -> bool {
        self.frames.iter().any(|f| f.contains(name))
    }

    fn name(&mut self, name: &str) {
        if self.bound(name) || self.keys.contains(name) {
            return;
        }
        if let Some(cap) = host_capability(name) {
            self.host
                .entry(cap)
                .or_insert_with(|| vec![name.to_string()]);
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
        if !STRUCTURAL.contains(&name) {
            self.name(name);
        }
    }
    fn template_symbol(&mut self, _: &Spanned, name: &str) {
        self.name(name);
    }
}
