//! Partial evaluation of pure calls on literals: rule R4 of the default
//! cascade (tier T5 of blue's speed plan).
//!
//! `area(3, 4)` inside a loop body asks the same question on every pass.
//! When `area` is a definition of the program whose answer is a function of
//! its arguments alone ([`crate::reach::reach_program`] says
//! [`crate::reach::Reach::Pure`]) and every argument is a literal, the answer
//! is known before the run: the prepare stage evaluates the call once and
//! writes its value in place of the call. `blue bundle` prepares at build
//! time, so a bundle carries the value, not the call.
//!
//! **The rewrite is exact.** Only a call that answered is replaced, and only
//! by a literal that evaluates back to a value of the same kind and content
//! as the answer. A call that raised, ran past [`STEPS`] evaluation steps or
//! past [`BYTES`] of memory, or answered something a literal cannot spell (a
//! map, a function, a record), stays as written and runs at its own time, so
//! the run raises its own error in its own place.
//!
//! **A default fires only where its gain is known.** A call is folded where
//! it can run more than once: in the body of a definition other than `main`,
//! or inside a function written in place. A call in `main` or at the top
//! level runs once; folding it would only move its cost.
//!
//! `BLUE_FOLD=off` turns the rewrite off; [`crate::fuse::hold_off`] holds it
//! off with fusion, for the commands that observe the code as written; and
//! `blue run --timings` names each definition whose call it folded.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use blue_lang_syntax::scope::{BinderKind, HeadKind, Scopes};
use tatara_lisp::{Atom, Span, Spanned, SpannedForm};
use tatara_lisp_eval::special::SpecialForm;
use tatara_lisp_eval::Value;

use crate::def_hash::DefKind;

/// The evaluation steps one folded call may spend before it is left as
/// written.
pub const STEPS: usize = 100_000;

/// The evaluation steps the whole pass may spend, across every call.
pub const PASS_STEPS: usize = 1_000_000;

/// The bytes one folded call may allocate before it is left as written.
pub const BYTES: u64 = 64 * 1024 * 1024;

/// Whether the rewrite runs: on unless its switch in the `kitei` registry (R4) is off or
/// [`crate::fuse::hold_off`] was called.
#[must_use]
pub fn enabled() -> bool {
    !crate::fuse::held_off() && !crate::kitei::switched_off("R4")
}

/// Whether a run under `bounds` may fold: a step bound counts the work a fold
/// would move before the run, so a run held to `max_steps` or
/// `max_dispatch_steps` keeps every call where it is written.
#[must_use]
pub fn unbounded(bounds: crate::ExecutionBounds) -> bool {
    bounds.max_steps.is_none() && bounds.max_dispatch_steps.is_none()
}

fn names_a_step_bound(s: &Spanned) -> bool {
    match &s.form {
        SpannedForm::Atom(Atom::Keyword(k) | Atom::Symbol(k) | Atom::Str(k)) => {
            k.trim_start_matches(':') == DISPATCH_OPTION
        }
        SpannedForm::List(items) => items.iter().any(names_a_step_bound),
        SpannedForm::Quote(i)
        | SpannedForm::Quasiquote(i)
        | SpannedForm::Unquote(i)
        | SpannedForm::UnquoteSplice(i) => names_a_step_bound(i),
        _ => false,
    }
}

const DISPATCH_OPTION: &str = "dispatch_steps";

/// An erased program with its pure literal calls folded, and the key of the
/// definition each folded call named.
#[derive(Clone, Debug)]
pub struct Folded {
    pub forms: Vec<Spanned>,
    pub calls: Vec<String>,
    /// Each folded call with the index of the top-level form it is in.
    pub sites: Vec<(usize, String)>,
}

/// Fold every call of `erased` that names a pure definition of the program
/// with only literal arguments and can run more than once. `defined` is the
/// tree `erased` was erased from, one form per form.
#[must_use]
pub fn fold(erased: Vec<Spanned>, defined: &[Spanned]) -> Folded {
    let unchanged = |forms| Folded {
        forms,
        calls: Vec::new(),
        sites: Vec::new(),
    };
    let globals: BTreeSet<&str> = defined
        .iter()
        .filter_map(crate::def_hash::defined)
        .map(|(k, _)| k)
        .collect();
    if erased.iter().any(names_a_step_bound) {
        return unchanged(erased);
    }
    let mut repeated = HashSet::new();
    for form in &erased {
        top(form, &mut repeated);
    }
    if repeated.is_empty() {
        return unchanged(erased);
    }
    let mut sites = Sites {
        globals: &globals,
        repeated: &repeated,
        frames: Vec::new(),
        found: HashMap::new(),
    };
    for form in &erased {
        blue_lang_syntax::scope::walk_top(form, &mut sites);
    }
    if sites.found.is_empty() {
        return unchanged(erased);
    }
    let found = sites.found;
    let pure = pure_keys(&erased, defined);
    if !found.values().any(|k| pure.contains(k)) {
        return unchanged(erased);
    }
    let mut sandbox = Sandbox::new(&erased, defined, &pure);
    let mut folder = Folder {
        found: &found,
        pure: &pure,
        sandbox: &mut sandbox,
        calls: Vec::new(),
    };
    let mut sites = Vec::new();
    let forms: Vec<Spanned> = erased
        .iter()
        .enumerate()
        .map(|(i, f)| {
            let before = folder.calls.len();
            let out = folder.form(f);
            sites.extend(folder.calls[before..].iter().map(|c| (i, c.clone())));
            out
        })
        .collect();
    let calls = folder.calls;
    Folded {
        forms,
        calls,
        sites,
    }
}

fn pure_keys(erased: &[Spanned], defined: &[Spanned]) -> BTreeSet<String> {
    let hashes = crate::def_hash::hash_program(defined);
    let reach = crate::reach::reach_program(erased, &hashes);
    let mut out: BTreeMap<String, bool> = BTreeMap::new();
    for (d, r) in hashes.defs().iter().zip(reach) {
        let kind = defined
            .get(d.top_level)
            .and_then(crate::def_hash::defined)
            .map(|(_, k)| k);
        let ok = r.is_pure()
            && !hashes.is_ambiguous(&d.key)
            && matches!(kind, Some(DefKind::Function | DefKind::Value));
        *out.entry(d.key.clone()).or_insert(true) &= ok;
    }
    out.into_iter()
        .filter(|(_, ok)| *ok)
        .map(|(k, _)| k)
        .collect()
}

fn is_lambda(s: &Spanned) -> Option<&[Spanned]> {
    let items = s.as_list()?;
    (items.first()?.as_symbol()? == "lambda" && items.len() >= 3).then(|| &items[2..])
}

fn top(form: &Spanned, repeated: &mut HashSet<*const Spanned>) {
    if let Some(items) = form.as_list() {
        if matches!(
            items.first().and_then(Spanned::as_symbol),
            Some("define" | "define-typed")
        ) && items.len() >= 3
        {
            let (name, body): (Option<&str>, &[Spanned]) = match items[1].as_list() {
                Some(sig) => (sig.first().and_then(Spanned::as_symbol), &items[2..]),
                None => match is_lambda(&items[2]) {
                    Some(body) => (items[1].as_symbol(), body),
                    None => (None, &items[2..]),
                },
            };
            let once = name.is_none_or(|n| n == "main" || n.ends_with("/main"));
            let function = items[1].as_list().is_some() || is_lambda(&items[2]).is_some();
            let depth = usize::from(!once && function);
            for b in body {
                walk(b, depth, repeated);
            }
            return;
        }
    }
    walk(form, 0, repeated);
}

fn walk(s: &Spanned, depth: usize, repeated: &mut HashSet<*const Spanned>) {
    let Some(items) = s.as_list() else {
        return;
    };
    if depth > 0 {
        repeated.insert(std::ptr::from_ref(s));
    }
    if let Some(body) = is_lambda(s) {
        for b in body {
            walk(b, depth + 1, repeated);
        }
        return;
    }
    for i in items {
        walk(i, depth, repeated);
    }
}

struct Sites<'a> {
    globals: &'a BTreeSet<&'a str>,
    repeated: &'a HashSet<*const Spanned>,
    frames: Vec<BTreeSet<String>>,
    found: HashMap<*const Spanned, String>,
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
        let at = std::ptr::from_ref(whole);
        if opaque
            || !self.repeated.contains(&at)
            || !self.globals.contains(name)
            || self.frames.iter().any(|f| f.contains(name))
        {
            return;
        }
        let literal = whole
            .as_list()
            .is_some_and(|items| items[1..].iter().all(literal_argument));
        if literal {
            self.found.insert(at, name.to_string());
        }
    }
}

fn literal_argument(s: &Spanned) -> bool {
    matches!(
        &s.form,
        SpannedForm::Nil
            | SpannedForm::Atom(
                Atom::Int(_) | Atom::Float(_) | Atom::Str(_) | Atom::Bool(_) | Atom::Keyword(_)
            )
    )
}

struct Sandbox {
    interp: tatara_lisp_eval::Interpreter<()>,
    spent: usize,
}

impl Sandbox {
    fn new(erased: &[Spanned], defined: &[Spanned], pure: &BTreeSet<String>) -> Self {
        let mut sandbox = Sandbox {
            interp: crate::interpreter_hostless(),
            spent: 0,
        };
        for (form, source) in erased.iter().zip(defined) {
            if crate::def_hash::defined(source).is_some_and(|(k, _)| pure.contains(k)) {
                let _ = sandbox.bounded(form);
            }
        }
        sandbox
    }

    fn bounded(&mut self, form: &Spanned) -> Option<Value> {
        let left = PASS_STEPS.saturating_sub(self.spent);
        if left == 0 {
            return None;
        }
        let depth = crate::execution_bounds().max_call_depth;
        self.interp
            .set_budget(tatara_lisp_eval::vm::Budget {
                fuel: Some(STEPS.min(left)),
                max_depth: Some(depth),
                quantum: None,
            })
            .ok()?;
        let (outcome, over) = crate::memory::held_on(&mut self.interp, Some(BYTES), |interp| {
            interp.eval_top_form(form, &mut ())
        });
        self.spent = self.spent.saturating_add(self.interp.steps_spent());
        if over.is_some() {
            return None;
        }
        outcome.ok()
    }
}

struct Folder<'a> {
    found: &'a HashMap<*const Spanned, String>,
    pure: &'a BTreeSet<String>,
    sandbox: &'a mut Sandbox,
    calls: Vec<String>,
}

impl Folder<'_> {
    fn form(&mut self, s: &Spanned) -> Spanned {
        if self.found.contains_key(&std::ptr::from_ref(s)) {
            if let Some(folded) = self.at(s) {
                return folded;
            }
        }
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

    fn at(&mut self, s: &Spanned) -> Option<Spanned> {
        let key = s.as_list()?.first()?.as_symbol()?;
        if !self.pure.contains(key) {
            return None;
        }
        let value = self.sandbox.bounded(s)?;
        let literal = spell(&value, s.span)?;
        let back = self.sandbox.bounded(&literal)?;
        if !same(&value, &back) {
            return None;
        }
        self.calls.push(key.to_string());
        Some(literal)
    }
}

fn atom(at: Span, a: Atom) -> Spanned {
    Spanned::new(at, SpannedForm::Atom(a))
}

/// A literal that evaluates to `value`, or `None` when no literal spells it.
fn spell(value: &Value, at: Span) -> Option<Spanned> {
    Some(match value {
        Value::Nil => Spanned::new(at, SpannedForm::Nil),
        Value::Bool(b) => atom(at, Atom::Bool(*b)),
        Value::Int(i) => atom(at, Atom::Int(*i)),
        Value::Float(f) if f.is_finite() => atom(at, Atom::Float(*f)),
        Value::Str(s) => atom(at, Atom::Str(s.to_string())),
        Value::Keyword(k) => atom(at, Atom::Keyword(k.to_string())),
        Value::List(xs) => {
            let mut items = vec![atom(Span::synthetic(), Atom::Symbol("list".into()))];
            for x in xs.iter() {
                items.push(spell(x, at)?);
            }
            Spanned::new(at, SpannedForm::List(items))
        }
        _ => return None,
    })
}

/// Whether two values are the same kind with the same content: stricter than
/// blue's `==`, which says `4 == 4.0`.
fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Nil, Value::Nil) => true,
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::Int(x), Value::Int(y)) => x == y,
        (Value::Float(x), Value::Float(y)) => x.to_bits() == y.to_bits(),
        (Value::Str(x), Value::Str(y)) | (Value::Keyword(x), Value::Keyword(y)) => x == y,
        (Value::List(x), Value::List(y)) => {
            x.len() == y.len() && x.iter().zip(y.iter()).all(|(p, q)| same(p, q))
        }
        _ => false,
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

    fn folded(src: &str) -> Folded {
        let (e, l) = erased(src);
        fold(e, &l)
    }

    #[test]
    fn a_pure_call_on_literals_in_a_loop_body_folds() {
        let f = folded(
            "def area(w, h)\n  w * h\nend\n\ndef total(xs)\n  map((x) -> x + area(3, 4), xs)\nend\n",
        );
        assert_eq!(f.calls, ["%root/area"]);
    }

    #[test]
    fn a_call_in_main_runs_once_and_stays() {
        let f = folded("def area(w, h)\n  w * h\nend\n\ndef main()\n  area(3, 4)\nend\n");
        assert!(f.calls.is_empty());
    }

    #[test]
    fn a_call_that_raises_stays() {
        let f = folded(
            "def boom(x)\n  raise(:k, \"no\")\nend\n\ndef go(xs)\n  map((x) -> boom(1), xs)\nend\n",
        );
        assert!(f.calls.is_empty());
        let f = folded(
            "def inv(x)\n  10 / x\nend\n\ndef go(xs)\n  map((x) -> [inv(2), inv(0)], xs)\nend\n",
        );
        assert_eq!(f.calls, ["%root/inv"]);
    }

    #[test]
    fn a_call_past_its_budget_stays() {
        let f = folded(
            "def spin(n)\n  if n == 0\n    0\n  else\n    spin(n - 1)\n  end\nend\n\ndef go(xs)\n  map((x) -> spin(10_000_000), xs)\nend\n",
        );
        assert!(f.calls.is_empty());
    }

    #[test]
    fn a_call_that_reaches_the_host_stays() {
        let f =
            folded("def stamp(x)\n  now_ms\nend\n\ndef go(xs)\n  map((x) -> stamp(1), xs)\nend\n");
        assert!(f.calls.is_empty());
    }

    #[test]
    fn a_call_with_a_variable_argument_stays() {
        let f = folded(
            "def area(w, h)\n  w * h\nend\n\ndef go(xs)\n  map((x) -> area(x, 4), xs)\nend\n",
        );
        assert!(f.calls.is_empty());
    }

    #[test]
    fn a_shadowed_name_is_not_the_definition() {
        let f = folded(
            "def area(w, h)\n  w * h\nend\n\ndef go(xs, area)\n  map((x) -> area(3, 4), xs)\nend\n",
        );
        assert!(f.calls.is_empty());
    }

    #[test]
    fn a_program_that_bounds_its_steps_folds_nothing() {
        let f = folded(
            "def area(w, h)\n  w * h\nend\n\ndef h(msg, n)\n  n + area(3, 4)\nend\n\ndef go()\n  spawn_server(h, 0, {dispatch_steps: 2000})\nend\n",
        );
        assert!(f.calls.is_empty());
        let bounded = crate::ExecutionBounds {
            max_steps: Some(10),
            ..crate::ExecutionBounds::DEFAULT
        };
        assert!(unbounded(crate::ExecutionBounds::DEFAULT));
        assert!(!unbounded(bounded));
        assert!(!unbounded(crate::ExecutionBounds {
            max_dispatch_steps: Some(10),
            ..crate::ExecutionBounds::DEFAULT
        }));
    }

    #[test]
    fn spelled_values_keep_their_kind() {
        let at = Span::synthetic();
        assert!(matches!(
            spell(&Value::Float(4.0), at).unwrap().form,
            SpannedForm::Atom(Atom::Float(_))
        ));
        assert!(spell(&Value::Float(f64::NAN), at).is_none());
        assert!(!same(&Value::Int(4), &Value::Float(4.0)));
        assert!(!same(&Value::Nil, &Value::list(Vec::new())));
    }
}
