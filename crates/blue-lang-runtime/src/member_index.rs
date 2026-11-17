//! A membership test in a loop gets a set: rule R10 of the default cascade.
//!
//! `filter((x) -> member?(x, allowed), xs)` scans `allowed` once per element
//! of `xs`. When a callback handed to [`LOOPS`] tests membership in a local
//! of an enclosing scope, the definition never assigns that local, and the
//! callback names it nowhere else, the list cannot change while the loop
//! runs. Erasure then binds an index of it around the call
//! (`blue-member-index`) and the callback asks the index
//! (`blue-member-indexed?`). The index lives for that one call, so it holds
//! no list past it, and it is built only after [`SCANS`] lookups, so a short
//! loop pays nothing for it.
//!
//! **The answer is `member?`'s.** Elements are grouped by a key two values
//! [`crate::stdlib::blue_equal`] calls equal always share (`4` and `4.0`
//! share one), and each candidate is confirmed with `blue_equal`; values with
//! no key (lists, maps, NaN) are compared with every keyless element. A value
//! that is not a list answers as `member?` does, at each call.
//!
//! `BLUE_INDEX=off` turns the rewrite off; [`crate::fuse::hold_off`] holds it
//! off with fusion; `blue run --timings` prints an `indexed` row.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, OnceLock};

use blue_lang_syntax::scope::{BinderKind, HeadKind, Scopes};
use tatara_lisp::{Atom, Span, Spanned, SpannedForm};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::special::SpecialForm;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

/// The builtins whose written-out callback the rewrite indexes for.
pub const LOOPS: &[&str] = &["map", "filter", "reduce", "any?", "all?", "find", "count"];

/// The lookups an index answers by scanning before it builds its set.
pub const SCANS: u32 = 8;

const INDEX: &str = "blue-member-index";
const INDEXED: &str = "blue-member-indexed?";
const MEMBER: &str = "member?";

/// Whether the rewrite runs.
#[must_use]
pub fn enabled() -> bool {
    !crate::fuse::held_off() && !crate::kitei::switched_off("R10")
}

#[derive(Clone, PartialEq, Eq, Hash)]
enum Key {
    Nil,
    Bool(bool),
    Number(u64),
    Str(Arc<str>),
    Symbol(Arc<str>),
    Keyword(Arc<str>),
}

fn number(n: f64) -> Option<Key> {
    (!n.is_nan()).then(|| Key::Number(if n == 0.0 { 0 } else { n.to_bits() }))
}

#[allow(clippy::cast_precision_loss)]
fn key(v: &Value) -> Option<Key> {
    match v {
        Value::Nil => Some(Key::Nil),
        Value::Bool(b) => Some(Key::Bool(*b)),
        Value::Int(i) => number(*i as f64),
        Value::Float(f) => number(*f),
        Value::Str(s) => Some(Key::Str(Arc::clone(s))),
        Value::Symbol(s) => Some(Key::Symbol(Arc::clone(s))),
        Value::Keyword(s) => Some(Key::Keyword(Arc::clone(s))),
        _ => None,
    }
}

struct Built {
    items: Vec<Value>,
    keyed: HashMap<Key, Vec<usize>>,
    keyless: Vec<usize>,
}

impl Built {
    fn of(list: &Value) -> Self {
        let items: Vec<Value> = match list {
            Value::List(xs) => xs.iter().cloned().collect(),
            _ => Vec::new(),
        };
        let mut keyed: HashMap<Key, Vec<usize>> = HashMap::new();
        let mut keyless = Vec::new();
        for (i, v) in items.iter().enumerate() {
            match key(v) {
                Some(k) => keyed.entry(k).or_default().push(i),
                None => keyless.push(i),
            }
        }
        Self {
            items,
            keyed,
            keyless,
        }
    }

    fn holds(&self, x: &Value) -> bool {
        let same = |i: &usize| crate::stdlib::blue_equal(&self.items[*i], x);
        match key(x) {
            Some(k) => self.keyed.get(&k).is_some_and(|c| c.iter().any(same)),
            None => self.keyless.iter().any(same),
        }
    }
}

/// One loop's index of one list.
pub struct MemberIndex {
    list: Value,
    asked: AtomicU32,
    built: OnceLock<Built>,
}

impl MemberIndex {
    /// Whether `x` is a member, as `member?(x, list)` answers.
    ///
    /// # Errors
    ///
    /// As `member?`: when the list is neither a list nor `nil`.
    pub fn holds(&self, x: &Value, sp: Span) -> Result<bool, EvalError> {
        if !matches!(self.list, Value::List(_)) {
            return crate::stdlib::member(x, &self.list, sp);
        }
        if self.asked.fetch_add(1, Ordering::Relaxed) < SCANS {
            return crate::stdlib::member(x, &self.list, sp);
        }
        Ok(self.built.get_or_init(|| Built::of(&self.list)).holds(x))
    }
}

/// Bind the two words the rewrite emits.
pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(INDEX, Arity::Exact(1), |a: &[Value], _: &mut H, _| {
        Ok(Value::Foreign(Arc::new(MemberIndex {
            list: a[0].clone(),
            asked: AtomicU32::new(0),
            built: OnceLock::new(),
        })))
    });
    interp.register_fn(
        INDEXED,
        Arity::Exact(2),
        |a: &[Value], _: &mut H, sp| match &a[1] {
            Value::Foreign(f) => match f.downcast_ref::<MemberIndex>() {
                Some(idx) => idx.holds(&a[0], sp).map(Value::Bool),
                None => crate::stdlib::member(&a[0], &a[1], sp).map(Value::Bool),
            },
            other => crate::stdlib::member(&a[0], other, sp).map(Value::Bool),
        },
    );
}

/// An erased program with its loop membership tests indexed, and how many
/// lists it indexes.
#[derive(Clone, Debug)]
pub struct Indexed {
    pub forms: Vec<Spanned>,
    pub lists: usize,
    /// Each indexed list by its name, with the index of the top-level form it
    /// is in.
    pub sites: Vec<(usize, String)>,
}

/// Index every loop membership test of `erased` the rewrite can prove the
/// list of fixed for the loop. `defined` is the tree `erased` was erased from.
#[must_use]
pub fn index(erased: Vec<Spanned>, defined: &[Spanned]) -> Indexed {
    let globals: BTreeSet<&str> = defined
        .iter()
        .filter_map(crate::def_hash::defined)
        .map(|(k, _)| k)
        .collect();
    if globals.contains(MEMBER) || LOOPS.iter().any(|l| globals.contains(l)) {
        return Indexed {
            forms: erased,
            lists: 0,
            sites: Vec::new(),
        };
    }
    let mut lists = 0;
    let mut sites_named = Vec::new();
    let forms = erased
        .into_iter()
        .enumerate()
        .map(|(i, form)| {
            let mut assigned = HashSet::new();
            assignments(&form, &mut assigned);
            let mut sites = Sites {
                frames: Vec::new(),
                found: HashMap::new(),
            };
            blue_lang_syntax::scope::walk_top(&form, &mut sites);
            if sites.found.is_empty() {
                return form;
            }
            let mut names = Vec::new();
            let mut r = Rewriter {
                found: &sites.found,
                assigned: &assigned,
                next: &mut lists,
                names: &mut names,
            };
            let out = r.form(&form);
            sites_named.extend(names.into_iter().map(|n| (i, n)));
            out
        })
        .collect();
    Indexed {
        forms,
        lists,
        sites: sites_named,
    }
}

fn assignments(s: &Spanned, out: &mut HashSet<String>) {
    let Some(items) = s.as_list() else {
        return;
    };
    if items.first().and_then(Spanned::as_symbol) == Some("set!") {
        if let Some(n) = items.get(1).and_then(Spanned::as_symbol) {
            out.insert(n.to_string());
        }
    }
    for i in items {
        assignments(i, out);
    }
}

struct Sites {
    frames: Vec<BTreeSet<String>>,
    found: HashMap<*const Spanned, BTreeSet<String>>,
}

impl Scopes for Sites {
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
        let bound = |n: &str| self.frames.iter().any(|f| f.contains(n));
        if opaque || !LOOPS.contains(&name) || bound(name) || bound(MEMBER) {
            return;
        }
        let locals = self.frames.iter().flatten().cloned().collect();
        self.found.insert(std::ptr::from_ref(whole), locals);
    }
}

struct Rewriter<'a> {
    found: &'a HashMap<*const Spanned, BTreeSet<String>>,
    assigned: &'a HashSet<String>,
    next: &'a mut usize,
    names: &'a mut Vec<String>,
}

fn lambda_parts(s: &Spanned) -> Option<(&[Spanned], &[Spanned])> {
    let items = s.as_list()?;
    if items.first()?.as_symbol()? != "lambda" || items.len() < 3 {
        return None;
    }
    Some((items[1].as_list()?, &items[2..]))
}

fn uses(s: &Spanned, name: &str, member_lists: &mut usize, other: &mut usize) {
    match &s.form {
        SpannedForm::Atom(Atom::Symbol(n)) if n == name => *other += 1,
        SpannedForm::List(items) => {
            if items.len() == 3
                && items[0].as_symbol() == Some(MEMBER)
                && items[2].as_symbol() == Some(name)
            {
                *member_lists += 1;
                uses(&items[1], name, member_lists, other);
                return;
            }
            for i in items {
                uses(i, name, member_lists, other);
            }
        }
        SpannedForm::Quote(_) => {}
        SpannedForm::Quasiquote(i) | SpannedForm::Unquote(i) | SpannedForm::UnquoteSplice(i) => {
            uses(i, name, member_lists, other);
        }
        _ => {}
    }
}

fn candidates(cb: &Spanned) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    collect(cb, &mut out);
    out
}

fn collect(s: &Spanned, out: &mut BTreeSet<String>) {
    let Some(items) = s.as_list() else {
        return;
    };
    if items.len() == 3 && items[0].as_symbol() == Some(MEMBER) {
        if let Some(n) = items[2].as_symbol() {
            out.insert(n.to_string());
        }
    }
    for i in items {
        collect(i, out);
    }
}

fn sym(at: Span, name: &str) -> Spanned {
    Spanned::new(at, SpannedForm::Atom(Atom::Symbol(name.into())))
}

fn list(at: Span, items: Vec<Spanned>) -> Spanned {
    Spanned::new(at, SpannedForm::List(items))
}

fn swap(s: &Spanned, name: &str, idx: &str) -> Spanned {
    match &s.form {
        SpannedForm::List(items) => {
            if items.len() == 3
                && items[0].as_symbol() == Some(MEMBER)
                && items[2].as_symbol() == Some(name)
            {
                return list(
                    s.span,
                    vec![
                        sym(items[0].span, INDEXED),
                        swap(&items[1], name, idx),
                        sym(items[2].span, idx),
                    ],
                );
            }
            list(s.span, items.iter().map(|i| swap(i, name, idx)).collect())
        }
        _ => s.clone(),
    }
}

impl Rewriter<'_> {
    fn form(&mut self, s: &Spanned) -> Spanned {
        let rebuilt = match &s.form {
            SpannedForm::List(items) => Spanned::new(
                s.span,
                SpannedForm::List(items.iter().map(|i| self.form(i)).collect()),
            ),
            _ => return s.clone(),
        };
        match self.found.get(&std::ptr::from_ref(s)) {
            Some(locals) => self.at(&rebuilt, locals),
            None => rebuilt,
        }
    }

    fn at(&mut self, call: &Spanned, locals: &BTreeSet<String>) -> Spanned {
        let Some(items) = call.as_list() else {
            return call.clone();
        };
        let mut items = items.to_vec();
        let mut binds = Vec::new();
        for arg in items.iter_mut().skip(1) {
            let Some((params, _)) = lambda_parts(arg) else {
                continue;
            };
            let params: BTreeSet<String> = params
                .iter()
                .filter_map(Spanned::as_symbol)
                .map(str::to_string)
                .collect();
            for name in candidates(arg) {
                if !locals.contains(&name)
                    || params.contains(&name)
                    || self.assigned.contains(&name)
                {
                    continue;
                }
                let (mut member_lists, mut other) = (0, 0);
                uses(arg, &name, &mut member_lists, &mut other);
                if member_lists == 0 || other > 0 {
                    continue;
                }
                let idx = format!("%member_index{}", *self.next);
                *self.next += 1;
                self.names.push(name.clone());
                *arg = swap(arg, &name, &idx);
                binds.push(list(
                    call.span,
                    vec![
                        sym(call.span, &idx),
                        list(
                            call.span,
                            vec![sym(call.span, INDEX), sym(call.span, &name)],
                        ),
                    ],
                ));
            }
        }
        if binds.is_empty() {
            return call.clone();
        }
        list(
            call.span,
            vec![
                sym(Span::synthetic(), "let"),
                list(call.span, binds),
                list(call.span, items),
            ],
        )
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

    fn lists(src: &str) -> usize {
        let (e, l) = erased(src);
        index(e, &l).lists
    }

    #[test]
    fn a_membership_test_in_a_loop_over_a_fixed_local_is_indexed() {
        assert_eq!(
            lists("def hits(xs, allowed)\n  filter((x) -> member?(x, allowed), xs)\nend\n"),
            1
        );
    }

    #[test]
    fn a_list_the_callback_uses_otherwise_or_the_definition_assigns_stays_a_scan() {
        let other = "def go(xs, s)\n  map((x) -> [member?(x, s), length(s)], xs)\nend\n";
        let param = "def go(xs)\n  map((s) -> member?(1, s), xs)\nend\n";
        let global =
            "ALLOWED = [1, 2]\n\ndef go(xs)\n  filter((x) -> member?(x, ALLOWED), xs)\nend\n";
        let outside = "def go(x, s)\n  member?(x, s)\nend\n";
        for src in [other, param, global, outside] {
            assert_eq!(lists(src), 0, "{src}");
        }
    }

    #[test]
    fn the_index_answers_what_a_scan_answers() {
        let xs = Value::list([
            Value::Int(4),
            Value::Float(f64::NAN),
            Value::Str(Arc::from("a")),
            Value::list([Value::Int(1)]),
            Value::Float(-0.0),
            Value::Nil,
        ]);
        let idx = MemberIndex {
            list: xs.clone(),
            asked: AtomicU32::new(SCANS),
            built: OnceLock::new(),
        };
        let probes = [
            Value::Float(4.0),
            Value::Int(4),
            Value::Int(5),
            Value::Float(f64::NAN),
            Value::Str(Arc::from("a")),
            Value::Keyword(Arc::from("a")),
            Value::list([Value::Float(1.0)]),
            Value::list([Value::Int(2)]),
            Value::Int(0),
            Value::Nil,
            Value::Bool(false),
        ];
        for p in &probes {
            let scan = crate::stdlib::member(p, &xs, Span::synthetic()).expect("scans");
            let indexed = idx.holds(p, Span::synthetic()).expect("indexes");
            assert_eq!(scan, indexed, "{p:?}");
        }
        let not_a_list = MemberIndex {
            list: Value::Int(5),
            asked: AtomicU32::new(SCANS),
            built: OnceLock::new(),
        };
        assert!(not_a_list.holds(&Value::Int(1), Span::synthetic()).is_err());
    }
}
