//! Exact fusion of higher-order chains: tier T2 of blue's speed plan.
//!
//! `reduce(f, z, filter(p, map(g, xs)))` builds two lists only to fold them
//! away. Erasure rewrites such a chain to one pass, a `reduce` whose step
//! does `g`, then `p`, then `f`, in plain tatara-lisp, so no evaluator needs a
//! new word and every column runs the same tree.
//!
//! **The rewrite is exact.** Fusing changes only the order in which the
//! callbacks run: the unfused program runs `g` on every element before `p`
//! sees one. With callbacks that only compute, the one difference that can
//! show is which error comes first, so the fused pass runs under `try`, and
//! when it raises, the unfused chain runs instead and raises its own error.
//! Running it again undoes nothing because the callbacks reached nothing.
//! The list and the fold's start are evaluated once, before either, in the
//! order the unfused call evaluates them.
//!
//! **A callback is fused only when calling it provably only computes**
//! ([`crate::reach::first_order_callback`] for a function written in place,
//! [`crate::reach::first_order_program`] for a definition): a callback that
//! writes, reads the host, assigns outside its frame, or calls a function it
//! was handed keeps its chain unfused, so its effects keep their order.
//!
//! The shapes are [`STAGES`] and [`REWRITES`]; `BLUE_FUSE=off` turns the
//! rewrite off, and `blue run --timings` names every chain it fused.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::OnceLock;

use blue_lang_syntax::scope::{BinderKind, HeadKind, Scopes};
use tatara_lisp::{Atom, Span, Spanned, SpannedForm};
use tatara_lisp_eval::special::SpecialForm;

use crate::def_hash::DefKind;

/// What one stage of a chain does to the list it is handed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    /// Each element, transformed.
    Map,
    /// The elements a predicate accepts.
    Filter,
    /// The list folded to one value from a start.
    Reduce,
}

/// A builtin a chain is made of: `(word callback [start] list)`, its
/// callback taking `params` arguments.
#[derive(Clone, Copy, Debug)]
pub struct Stage {
    pub word: &'static str,
    pub kind: Kind,
    pub arity: usize,
    pub params: usize,
}

/// The stages a chain is made of, each in its one fused-call shape.
pub const STAGES: &[Stage] = &[
    Stage {
        word: "map",
        kind: Kind::Map,
        arity: 2,
        params: 1,
    },
    Stage {
        word: "filter",
        kind: Kind::Filter,
        arity: 2,
        params: 1,
    },
    Stage {
        word: "reduce",
        kind: Kind::Reduce,
        arity: 3,
        params: 2,
    },
];

/// A chain the rewrite fuses: an `outer` stage over any run of `inner`
/// stages. A chain that ends in a list (`filter(p, map(g, xs))`) and mixes
/// kinds is not here, because one pass that builds its list needs a word
/// tatara-lisp does not have.
#[derive(Clone, Copy, Debug)]
pub struct Rewrite {
    pub outer: Kind,
    pub inner: &'static [Kind],
}

/// Every chain shape the rewrite fuses.
pub const REWRITES: &[Rewrite] = &[
    Rewrite {
        outer: Kind::Reduce,
        inner: &[Kind::Map, Kind::Filter],
    },
    Rewrite {
        outer: Kind::Map,
        inner: &[Kind::Map],
    },
    Rewrite {
        outer: Kind::Filter,
        inner: &[Kind::Filter],
    },
];

/// The variable that turns the rewrite off: `BLUE_FUSE=off`.
pub const SWITCH: &str = "BLUE_FUSE";

static HELD_OFF: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Hold this rewrite and [`crate::fold`] off for the rest of the process: a
/// command that observes the code as written (`blue test --coverage`,
/// `blue trace`, `blue profile`) must see each call run where the author
/// wrote it, not inside a fused pass or before the run.
pub fn hold_off() {
    HELD_OFF.store(true, std::sync::atomic::Ordering::Relaxed);
}

/// Whether [`hold_off`] was called.
#[must_use]
pub fn held_off() -> bool {
    HELD_OFF.load(std::sync::atomic::Ordering::Relaxed)
}

/// Whether the rewrite runs: on unless [`SWITCH`] is `off` or [`hold_off`]
/// was called.
#[must_use]
pub fn enabled() -> bool {
    !held_off() && std::env::var(SWITCH).map_or(true, |v| v != "off")
}

/// An erased program with its chains fused, and each chain it fused, spelled
/// outermost first (`reduce∘filter∘map`).
#[derive(Clone, Debug)]
pub struct Fused {
    pub forms: Vec<Spanned>,
    pub chains: Vec<String>,
    /// Each fused chain with the index of the top-level form it is in.
    pub sites: Vec<(usize, String)>,
}

/// Fuse every chain of `erased` whose callbacks only compute. `defined` is
/// the tree `erased` was erased from, one form per form, read for the keys
/// the program binds and, when a callback names one, their reach.
#[must_use]
pub fn fuse(erased: Vec<Spanned>, defined: &[Spanned]) -> Fused {
    let globals: BTreeSet<&str> = defined
        .iter()
        .filter_map(crate::def_hash::defined)
        .map(|(k, _)| k)
        .collect();
    let mut sites = Sites {
        globals: &globals,
        frames: Vec::new(),
        found: HashMap::new(),
    };
    for form in &erased {
        blue_lang_syntax::scope::walk_top(form, &mut sites);
    }
    if sites.found.is_empty() {
        return Fused {
            forms: erased,
            chains: Vec::new(),
            sites: Vec::new(),
        };
    }
    let found = sites.found;
    let mut rewriter = Rewriter {
        sites: &found,
        purity: Purity {
            defined,
            erased: &erased,
            keys: &globals,
            first_order: OnceLock::new(),
        },
        chains: Vec::new(),
        next: 0,
    };
    let mut sites = Vec::new();
    let forms = erased
        .iter()
        .enumerate()
        .map(|(i, f)| {
            let before = rewriter.chains.len();
            let out = rewriter.form(f);
            sites.extend(rewriter.chains[before..].iter().map(|c| (i, c.clone())));
            out
        })
        .collect();
    let chains = rewriter.chains;
    Fused {
        forms,
        chains,
        sites,
    }
}

fn stage(name: &str, args: usize) -> Option<&'static Stage> {
    STAGES.iter().find(|s| s.word == name && s.arity == args)
}

struct Sites<'a> {
    globals: &'a BTreeSet<&'a str>,
    frames: Vec<BTreeSet<String>>,
    found: HashMap<*const Spanned, BTreeSet<String>>,
}

impl Sites<'_> {
    fn bound(&self, name: &str) -> bool {
        self.frames.iter().any(|f| f.contains(name))
    }
}

impl Scopes for Sites<'_> {
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
    fn reference(&mut self, _: &Spanned, _: &str, _: bool) {}
    fn call(&mut self, _: &Spanned, whole: &Spanned, name: &str, opaque: bool) {
        let args = whole.as_list().map_or(0, |items| items.len() - 1);
        if opaque || stage(name, args).is_none() || self.bound(name) || self.globals.contains(name)
        {
            return;
        }
        let locals = self.frames.iter().flatten().cloned().collect();
        self.found.insert(std::ptr::from_ref(whole), locals);
    }
}

struct Purity<'a> {
    defined: &'a [Spanned],
    erased: &'a [Spanned],
    keys: &'a BTreeSet<&'a str>,
    first_order: OnceLock<BTreeMap<String, bool>>,
}

impl Purity<'_> {
    fn key(&self, key: &str) -> bool {
        let all = self.first_order.get_or_init(|| {
            let hashes = crate::def_hash::hash_program(self.defined);
            let fo = crate::reach::first_order_program(self.erased, &hashes);
            let mut out: BTreeMap<String, bool> = BTreeMap::new();
            for (d, ok) in hashes.defs().iter().zip(fo) {
                let kind = self
                    .defined
                    .get(d.top_level)
                    .and_then(crate::def_hash::defined)
                    .map(|(_, k)| k);
                let ok = ok
                    && !hashes.is_ambiguous(&d.key)
                    && matches!(kind, Some(DefKind::Function | DefKind::Value));
                *out.entry(d.key.clone()).or_insert(true) &= ok;
            }
            out
        });
        all.get(key).copied().unwrap_or(false)
    }

    fn callback(&self, cb: &Spanned, params: usize, locals: &BTreeSet<String>) -> bool {
        if let Some(name) = cb.as_symbol() {
            if locals.contains(name) {
                return false;
            }
            if self.keys.contains(name) {
                return self.key(name);
            }
            return SpecialForm::from_symbol(name).is_none()
                && crate::reach::builtin(name).is_ok()
                && !crate::reach::calls_arguments(name)
                && crate::docs::doc_of(name).map_or_else(
                    || blue_lang_waku::Capability::Operators.grants(name),
                    |d| !matches!(d.topic, crate::docs::Topic::Form | crate::docs::Topic::Lisp),
                );
        }
        if lambda(cb, params).is_none() {
            return false;
        }
        crate::reach::first_order_callback(cb, locals, self.keys)
            .is_some_and(|named| named.iter().all(|k| self.key(k)))
    }
}

fn lambda(cb: &Spanned, params: usize) -> Option<(&[Spanned], &[Spanned])> {
    let items = cb.as_list()?;
    if items.first()?.as_symbol()? != "lambda" || items.len() < 3 {
        return None;
    }
    let ps = items[1].as_list()?;
    let plain = ps
        .iter()
        .all(|p| p.as_symbol().is_some_and(|n| !n.starts_with('&')));
    (ps.len() == params && plain).then(|| (ps, &items[2..]))
}

struct Link<'a> {
    call: &'a Spanned,
    stage: &'static Stage,
}

struct Rewriter<'a> {
    sites: &'a HashMap<*const Spanned, BTreeSet<String>>,
    purity: Purity<'a>,
    chains: Vec<String>,
    next: usize,
}

fn synthetic_symbol(name: &str) -> Spanned {
    Spanned::new(
        Span::synthetic(),
        SpannedForm::Atom(Atom::Symbol(name.into())),
    )
}

fn list(at: Span, items: Vec<Spanned>) -> Spanned {
    Spanned::new(at, SpannedForm::List(items))
}

fn generated(at: Span, head: &str, rest: Vec<Spanned>) -> Spanned {
    let mut items = vec![synthetic_symbol(head)];
    items.extend(rest);
    list(at, items)
}

impl Rewriter<'_> {
    fn form(&mut self, s: &Spanned) -> Spanned {
        if self.sites.contains_key(&std::ptr::from_ref(s)) {
            if let Some(fused) = self.at(s) {
                return fused;
            }
        }
        self.children(s)
    }

    fn children(&mut self, s: &Spanned) -> Spanned {
        let form = match &s.form {
            SpannedForm::List(items) => {
                SpannedForm::List(items.iter().map(|i| self.form(i)).collect())
            }
            SpannedForm::Quasiquote(i) => SpannedForm::Quasiquote(Box::new(self.form(i))),
            SpannedForm::Unquote(i) => SpannedForm::Unquote(Box::new(self.form(i))),
            SpannedForm::UnquoteSplice(i) => SpannedForm::UnquoteSplice(Box::new(self.form(i))),
            other => other.clone(),
        };
        Spanned::new(s.span, form)
    }

    fn chain<'s>(&self, s: &'s Spanned) -> Option<(Vec<Link<'s>>, &'s Spanned)> {
        let items = s.as_list()?;
        let outer = stage(items[0].as_symbol()?, items.len() - 1)?;
        let rule = REWRITES.iter().find(|r| r.outer == outer.kind)?;
        let locals = self.sites.get(&std::ptr::from_ref(s))?;
        if !self.purity.callback(&items[1], outer.params, locals) {
            return None;
        }
        let mut links = vec![Link {
            call: s,
            stage: outer,
        }];
        let mut base = items.last()?;
        while let Some(locals) = self.sites.get(&std::ptr::from_ref(base)) {
            let inner = base.as_list()?;
            let Some(st) = inner[0]
                .as_symbol()
                .and_then(|n| stage(n, inner.len() - 1))
                .filter(|st| rule.inner.contains(&st.kind))
            else {
                break;
            };
            if !self.purity.callback(&inner[1], st.params, locals) {
                break;
            }
            links.push(Link {
                call: base,
                stage: st,
            });
            base = inner.last()?;
        }
        (links.len() >= 2).then_some((links, base))
    }

    fn at(&mut self, s: &Spanned) -> Option<Spanned> {
        let (links, base) = self.chain(s)?;
        let n = self.next;
        self.next += 1;
        let var = |what: &str| format!("%fuse{n}_{what}");
        let at = s.span;
        let outer = links[0].stage;
        let xs = var("xs");
        let z = var("z");
        let callbacks: Vec<Spanned> = links
            .iter()
            .map(|l| self.form(&l.call.as_list().expect("a stage is a call")[1]))
            .collect();
        let start = (outer.kind == Kind::Reduce)
            .then(|| self.form(&s.as_list().expect("a stage is a call")[2]));
        let listed = self.form(base);

        let mut unfused = Spanned::new(
            base.span,
            SpannedForm::Atom(Atom::Symbol(xs.clone().into())),
        );
        for (l, cb) in links.iter().zip(&callbacks).rev() {
            let items = l.call.as_list().expect("a stage is a call");
            let mut call = vec![items[0].clone(), cb.clone()];
            if l.stage.kind == Kind::Reduce {
                call.push(Spanned::new(
                    items[2].span,
                    SpannedForm::Atom(Atom::Symbol(z.clone().into())),
                ));
            }
            call.push(unfused);
            unfused = list(l.call.span, call);
        }

        let acc = var("acc");
        let x = var("x");
        let step_body = {
            let order: Vec<(&Link, &Spanned)> = links.iter().zip(&callbacks).rev().collect();
            let mut value = synthetic_symbol(&x);
            let mut wrap: Vec<Box<dyn FnOnce(Spanned) -> Spanned>> = Vec::new();
            let mut tests: Vec<Spanned> = Vec::new();
            let mut last = None;
            for (i, (l, cb)) in order.iter().enumerate() {
                match l.stage.kind {
                    Kind::Map => {
                        let v = var(&format!("v{i}"));
                        let bound = apply(cb, vec![value.clone()]);
                        value = synthetic_symbol(&v);
                        wrap.push(Box::new(move |inner| {
                            generated(
                                at,
                                "let",
                                vec![
                                    list(at, vec![list(at, vec![synthetic_symbol(&v), bound])]),
                                    inner,
                                ],
                            )
                        }));
                    }
                    Kind::Filter => {
                        let test = apply(cb, vec![value.clone()]);
                        if outer.kind == Kind::Filter {
                            tests.push(test);
                        } else {
                            let acc = acc.clone();
                            wrap.push(Box::new(move |inner| {
                                generated(at, "if", vec![test, inner, synthetic_symbol(&acc)])
                            }));
                        }
                    }
                    Kind::Reduce => {
                        last = Some(apply(cb, vec![synthetic_symbol(&acc), value.clone()]));
                    }
                }
            }
            let mut body = match outer.kind {
                Kind::Reduce => last.expect("a reduce chain ends in its fold"),
                Kind::Map => value,
                Kind::Filter => generated(at, "and", tests),
            };
            for w in wrap.into_iter().rev() {
                body = w(body);
            }
            body
        };
        let step_params = if outer.kind == Kind::Reduce {
            vec![synthetic_symbol(&acc), synthetic_symbol(&x)]
        } else {
            vec![synthetic_symbol(&x)]
        };
        let step = generated(at, "lambda", vec![list(at, step_params), step_body]);
        let mut fused_call = vec![step];
        if outer.kind == Kind::Reduce {
            fused_call.push(synthetic_symbol(&z));
        }
        fused_call.push(synthetic_symbol(&xs));
        let fused = generated(at, outer.word, fused_call);

        let attempt = generated(
            at,
            "try",
            vec![
                fused,
                generated(
                    at,
                    "catch",
                    vec![list(at, vec![synthetic_symbol(&var("e"))]), unfused],
                ),
            ],
        );
        let mut bindings = Vec::new();
        if let Some(start) = start {
            bindings.push(list(at, vec![synthetic_symbol(&z), start]));
        }
        bindings.push(list(at, vec![synthetic_symbol(&xs), listed]));
        self.chains.push(
            links
                .iter()
                .map(|l| l.stage.word)
                .collect::<Vec<_>>()
                .join("∘"),
        );
        Some(generated(at, "let", vec![list(at, bindings), attempt]))
    }
}

struct Renamer<'p> {
    params: &'p BTreeMap<String, Spanned>,
    frames: Vec<BTreeSet<String>>,
    found: HashMap<*const Spanned, Spanned>,
    refused: bool,
}

impl Renamer<'_> {
    fn resolve(&mut self, node: &Spanned, name: &str, opaque: bool) {
        let Some(to) = self.params.get(name) else {
            return;
        };
        let innermost = self.frames.iter().rposition(|f| f.contains(name));
        if innermost == Some(0) {
            if opaque {
                self.refused = true;
            }
            self.found.insert(
                std::ptr::from_ref(node),
                Spanned::new(node.span, to.form.clone()),
            );
        }
    }
}

impl Scopes for Renamer<'_> {
    fn head_kind(&self, name: &str) -> Option<HeadKind> {
        (SpecialForm::from_symbol(name).is_some()
            || blue_lang_syntax::scope::SHAPED_FORMS.contains(&name))
        .then_some(HeadKind::SpecialForm)
    }
    fn open(&mut self) {
        self.frames.push(BTreeSet::new());
    }
    fn bind(&mut self, name: &str, _: Span, kind: BinderKind) {
        if self.frames.len() == 1 && kind != BinderKind::Parameter {
            self.refused = true;
        }
        if let Some(f) = self.frames.last_mut() {
            f.insert(name.to_string());
        }
    }
    fn close(&mut self) {
        self.frames.pop();
    }
    fn reference(&mut self, node: &Spanned, name: &str, opaque: bool) {
        self.resolve(node, name, opaque);
    }
    fn place(&mut self, _: &Spanned, name: &str, _: bool) {
        if self.params.contains_key(name)
            && self.frames.iter().rposition(|f| f.contains(name)) == Some(0)
        {
            self.refused = true;
        }
    }
}

fn renamed(s: &Spanned, found: &HashMap<*const Spanned, Spanned>) -> Spanned {
    if let Some(to) = found.get(&std::ptr::from_ref(s)) {
        return to.clone();
    }
    let form = match &s.form {
        SpannedForm::List(items) => {
            SpannedForm::List(items.iter().map(|i| renamed(i, found)).collect())
        }
        SpannedForm::Quasiquote(i) => SpannedForm::Quasiquote(Box::new(renamed(i, found))),
        SpannedForm::Unquote(i) => SpannedForm::Unquote(Box::new(renamed(i, found))),
        SpannedForm::UnquoteSplice(i) => SpannedForm::UnquoteSplice(Box::new(renamed(i, found))),
        other => other.clone(),
    };
    Spanned::new(s.span, form)
}

fn substituted(
    cb: &Spanned,
    params: &[Spanned],
    body: &[Spanned],
    args: &[Spanned],
) -> Option<Spanned> {
    let names: BTreeMap<String, Spanned> = params
        .iter()
        .zip(args)
        .map(|(p, a)| Some((p.as_symbol()?.to_string(), a.clone())))
        .collect::<Option<_>>()?;
    if names.len() != params.len() || args.iter().any(|a| a.as_symbol().is_none()) {
        return None;
    }
    let mut renamer = Renamer {
        params: &names,
        frames: Vec::new(),
        found: HashMap::new(),
        refused: false,
    };
    blue_lang_syntax::scope::walk_top(cb, &mut renamer);
    if renamer.refused {
        return None;
    }
    let mut forms: Vec<Spanned> = body.iter().map(|f| renamed(f, &renamer.found)).collect();
    Some(if forms.len() == 1 {
        forms.remove(0)
    } else {
        generated(cb.span, "begin", forms)
    })
}

fn apply(cb: &Spanned, args: Vec<Spanned>) -> Spanned {
    let at = cb.span;
    match lambda(cb, args.len()) {
        Some((params, body)) => {
            if let Some(inline) = substituted(cb, params, body, &args) {
                return inline;
            }
            let bindings = params
                .iter()
                .zip(args)
                .map(|(p, a)| list(at, vec![p.clone(), a]))
                .collect();
            let mut items = vec![synthetic_symbol("let"), list(at, bindings)];
            items.extend(body.iter().cloned());
            list(at, items)
        }
        None => {
            let mut items = vec![cb.clone()];
            items.extend(args);
            list(at, items)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn erased(src: &str) -> (Vec<Spanned>, Vec<Spanned>) {
        let checked = crate::pipeline::check_entry(
            crate::uses::Entry::anonymous(src),
            &crate::uses::NoLoader,
            None,
            crate::pipeline::Checking::Program,
        )
        .expect("checks");
        assert!(checked.outcome.ok(), "{:?}", checked.outcome.diagnostics);
        let lowered = crate::pipeline::lower(&checked.program, &checked.names);
        (crate::erase::unfused(&lowered), lowered)
    }

    fn chains(src: &str) -> Vec<String> {
        let (erased, lowered) = erased(src);
        fuse(erased, &lowered).chains
    }

    #[test]
    fn a_fold_over_a_filter_over_a_map_of_pure_callbacks_fuses_to_one_pass() {
        let src = "def sq(x)\n  x * x\nend\n\ndef main()\n  reduce((a, x) -> a + x, 0, filter((x) -> x > 2, map(sq, [1, 2, 3])))\nend\n";
        assert_eq!(chains(src), ["reduce∘filter∘map"]);
    }

    #[test]
    fn maps_over_maps_and_filters_over_filters_fuse_and_a_filter_over_a_map_does_not() {
        let src = "def main(k)\n  a = map((x) -> x + k, map((x) -> x * 2, [1]))\n  b = filter((x) -> x > k, filter((x) -> x < 9, [1]))\n  c = filter((x) -> x > 1, map((x) -> x * 2, [1]))\n  [a, b, c]\nend\n";
        assert_eq!(chains(src), ["map∘map", "filter∘filter"]);
    }

    #[test]
    fn a_callback_that_writes_reads_the_host_or_calls_a_value_it_was_handed_keeps_its_chain() {
        let writes = "def main()\n  reduce((a, x) -> a + x, 0, map((x) -> write_stdout(to_s(x)), [1]))\nend\n";
        let host = "def main()\n  reduce((a, x) -> a + x, 0, map((x) -> x + now_ms, [1]))\nend\n";
        let handed = "def main(g)\n  reduce((a, x) -> a + x, 0, map(g, [1]))\nend\n";
        let calls = "def main(g)\n  reduce((a, x) -> a + x, 0, map((x) -> g(x), [1]))\nend\n";
        let passes =
            "def main(g)\n  reduce((a, x) -> a + x, 0, map((x) -> map(g, x), [[1]]))\nend\n";
        let def_calls = "def app(f, x)\n  f(x)\nend\n\ndef main(g)\n  reduce((a, x) -> a + x, 0, map((x) -> app(g, x), [1]))\nend\n";
        let shout = "def shout(x)\n  write_stdout(to_s(x))\n  x\nend\n\ndef main()\n  reduce((a, x) -> a + x, 0, map(shout, [1]))\nend\n";
        for src in [writes, host, handed, calls, passes, def_calls, shout] {
            assert!(chains(src).is_empty(), "{src}");
        }
    }

    #[test]
    fn a_shadowed_word_or_a_lambda_of_the_wrong_arity_is_not_a_stage() {
        let shadow = "def main(map)\n  reduce((a, x) -> a + x, 0, map((x) -> x, [1]))\nend\n";
        let arity = "def main()\n  reduce((a) -> a, 0, map((x) -> x, [1]))\nend\n";
        for src in [shadow, arity] {
            assert!(chains(src).is_empty(), "{src}");
        }
    }

    #[test]
    fn the_fused_tree_keeps_the_unfused_chain_as_its_fallback_over_the_list_bound_once() {
        let (erased, lowered) =
            erased("def main()\n  reduce((a, x) -> a + x, 0, map((x) -> x * 3, range(5)))\nend\n");
        let fused = fuse(erased, &lowered);
        let text = fused.forms[0].to_sexp().to_string();
        assert!(text.contains("(let ((%fuse0_z 0) (%fuse0_xs (range 5))) (try (reduce (lambda (%fuse0_acc %fuse0_x)"), "{text}");
        assert!(text.contains("(catch (%fuse0_e) (reduce (lambda (a x) (+ a x)) %fuse0_z (map (lambda (x) (* x 3)) %fuse0_xs)))"), "{text}");
    }
}
