//! Laws checked by a solver where one decides them, tested where none does
//! (HORIZON H6).
//!
//! A law is a typed definition named `law_…` that returns `Bool`:
//! `def law_clamp_in_range(x: Int, lo: Int, hi: Int) -> Bool`. It claims its
//! body is true for every argument. [`laws`] gives each law one `test` block
//! whose name says which check stands behind the claim:
//!
//! - **proved** (`@law `f`: proved (cooper)`): the body, with every same-file
//!   definition it calls inlined, is in the fragment the solver behind
//!   [`crate::lia::Backend`] decides, and the solver found that its negation
//!   has no model. The block still runs drawn calls, so the runtime has to
//!   agree with the proof.
//! - **refuted** (`@law `f`: refuted (cooper) at x = 3`): the solver found a
//!   model of the negation; the block asserts the law at it and fails.
//! - **tested-N** (`@law `f`: tested-64, seed 1 (not proved: …)`): the solver
//!   could not take the law, and the name says why, so N drawn calls are
//!   asserted. Tested never reads as proved.
//! - **unchecked** (`@law `f`: unchecked (…)`): neither could run, and the
//!   name says why.
//!
//! The fragment is linear integer arithmetic over the law's parameters:
//! `Int` parameters as integers, `Bool` parameters as truth values, and
//! `List` parameters by their length alone. It reads `+`, `-`, `*` and `%` by
//! a constant, `abs`, `min`, `max`, comparisons, `==`, `!=`, `and`, `or`,
//! `not`, `if`, local bindings, and the lengths of lists built by `[…]`,
//! `cons`, `append`, `reverse`, `map`, `take`, `drop`, `range` and `zip`,
//! read by `length`, `count` and `empty?`. A word the file defines is read as
//! the file defines it, inlined; a word a `use` brings in bare is outside the
//! fragment, since the solver does not see its body.
//!
//! Blue's integers are 64-bit and raise on overflow, so a law proved over the
//! integers holds at every call that returns. A law that is not typed gets no
//! block, so no program that runs today changes.

use std::collections::{BTreeMap, BTreeSet};

use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::lia::{Backend, Formula, Lin, Model, Stop, Var, Verdict};
use crate::properties::{next_seed, next_uniform, stream};
use crate::Ty;

/// The name every law's `test` block starts with.
pub const LAW_PREFIX: &str = "@law ";

/// The prefix a definition is a law by.
pub const LAW_NAME: &str = "law_";

/// The variable that picks the solver, or turns laws off.
pub const ENV: &str = "BLUE_LAWS";

/// Calls drawn for a tested law, before duplicates are dropped.
pub const DRAWS: usize = 64;

/// Calls drawn beside a proof, so the runtime has to agree with it.
pub const BESIDE_PROOF: usize = 8;

/// The longest list a counterexample is built with.
pub const LONGEST: i128 = 64;

const MAX_CASES: usize = 64;
const MAX_DEPTH: usize = 32;

/// Which check stood behind a law.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Tier {
    Proved,
    Refuted,
    Tested(usize),
    Unchecked,
}

impl Tier {
    /// The tier a law's test block names, read back from its name.
    #[must_use]
    pub fn of_test(name: &str) -> Option<Self> {
        let rest = name.strip_prefix(LAW_PREFIX)?;
        let (_, after) = rest.strip_prefix('`')?.split_once("`: ")?;
        let word = after.split([' ', ',']).next()?;
        match word {
            "proved" => Some(Self::Proved),
            "refuted" => Some(Self::Refuted),
            "unchecked" => Some(Self::Unchecked),
            w => w.strip_prefix("tested-")?.parse().ok().map(Self::Tested),
        }
    }
}

/// Whether laws are checked, and by which backend.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Setting {
    Off,
    On(Backend),
}

impl Setting {
    /// Read a setting as [`ENV`] spells it: unset, empty or `cooper` is the
    /// pure-Rust solver; `tested` is no solver, every law tested; `off` turns
    /// laws off.
    ///
    /// # Errors
    ///
    /// Any other text, named with what the variable takes.
    pub fn from_setting(setting: Option<&str>) -> Result<Self, String> {
        match setting.map(str::trim) {
            None | Some("" | "cooper") => Ok(Self::On(Backend::Cooper)),
            Some("tested") => Ok(Self::On(Backend::Absent)),
            Some("off") => Ok(Self::Off),
            Some(v) => Err(format!("{ENV} is {v:?}; it takes cooper, tested or off")),
        }
    }

    /// The setting of this process's environment.
    ///
    /// # Errors
    ///
    /// As [`Setting::from_setting`].
    pub fn configured() -> Result<Self, String> {
        Self::from_setting(std::env::var(ENV).ok().as_deref())
    }
}

/// The element a counterexample's list is filled with: its length is all the
/// solver chose, so any element of the declared type serves.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Element {
    Int,
    Float,
    Str,
    Bool,
    List,
}

impl Element {
    fn of(t: &Ty) -> Option<Self> {
        match t {
            Ty::Int | Ty::Dyn => Some(Self::Int),
            Ty::Float => Some(Self::Float),
            Ty::Str => Some(Self::Str),
            Ty::Bool => Some(Self::Bool),
            Ty::List(_) => Some(Self::List),
            _ => None,
        }
    }

    fn form(self, at: Span) -> Spanned {
        let atom = |a| Spanned::new(at, SpannedForm::Atom(a));
        match self {
            Self::Int => atom(Atom::Int(0)),
            Self::Float => atom(Atom::Float(0.0)),
            Self::Str => atom(Atom::Str(String::new())),
            Self::Bool => atom(Atom::Bool(false)),
            Self::List => Spanned::new(at, SpannedForm::List(vec![sym(at, "list")])),
        }
    }

    fn shown(self) -> &'static str {
        match self {
            Self::Int => "0",
            Self::Float => "0.0",
            Self::Str => "\"\"",
            Self::Bool => "false",
            Self::List => "[]",
        }
    }
}

/// The value a counterexample gives one parameter.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Value {
    Int(i64),
    Bool(bool),
    List(usize, Element),
}

impl Value {
    fn form(&self, at: Span) -> Spanned {
        match self {
            Self::Int(v) => int(at, *v),
            Self::Bool(b) => Spanned::new(at, SpannedForm::Atom(Atom::Bool(*b))),
            Self::List(n, e) => {
                let mut items = vec![sym(at, "list")];
                items.extend((0..*n).map(|_| e.form(at)));
                Spanned::new(at, SpannedForm::List(items))
            }
        }
    }

    fn shown(&self) -> String {
        match self {
            Self::Int(v) => v.to_string(),
            Self::Bool(b) => b.to_string(),
            Self::List(n, e) => format!("[{}]", vec![e.shown(); *n].join(", ")),
        }
    }
}

struct Def<'a> {
    params: Vec<String>,
    body: &'a Spanned,
}

struct Scope<'a> {
    defs: BTreeMap<String, Def<'a>>,
    bound: BTreeSet<String>,
}

struct Law<'a> {
    name: String,
    span: Span,
    params: Vec<(String, Ty)>,
    plain: bool,
    body: &'a Spanned,
}

fn param_name(p: &Spanned) -> Option<String> {
    match p.as_list() {
        Some([n, _]) => n.as_symbol().map(str::to_string),
        _ => p.as_symbol().map(str::to_string),
    }
}

fn scope(forms: &[Spanned]) -> Scope<'_> {
    let mut defs = BTreeMap::new();
    let mut bound = BTreeSet::new();
    for f in forms {
        if let Some(imports) = blue_lang_syntax::scope::use_targets(f) {
            bound.extend(imports.into_iter().flat_map(|i| i.names).map(|(n, _)| n));
            continue;
        }
        let Some([head, sig, rest @ ..]) = f.as_list() else {
            continue;
        };
        let head = head.as_symbol();
        if !matches!(head, Some("define" | "define-typed" | "defmacro")) {
            continue;
        }
        let Some(name) = sig
            .as_symbol()
            .or_else(|| sig.as_list()?.first()?.as_symbol())
        else {
            continue;
        };
        bound.insert(name.to_string());
        let body = match (head, rest) {
            (Some("define-typed"), [_, body]) | (Some("define"), [body]) => body,
            _ => continue,
        };
        let Some([_, params @ ..]) = sig.as_list() else {
            continue;
        };
        if params.iter().any(crate::is_marker) {
            continue;
        }
        let Some(params) = params.iter().map(param_name).collect::<Option<Vec<_>>>() else {
            continue;
        };
        defs.insert(name.to_string(), Def { params, body });
    }
    Scope { defs, bound }
}

fn law_of(form: &Spanned) -> Option<Law<'_>> {
    let [head, sig, ret, body] = form.as_list()? else {
        return None;
    };
    if head.as_symbol()? != "define-typed" || Ty::from_sexp(&ret.to_sexp()) != Ty::Bool {
        return None;
    }
    let [name, params @ ..] = sig.as_list()? else {
        return None;
    };
    let name = name.as_symbol()?;
    if !name.starts_with(LAW_NAME) {
        return None;
    }
    let plain = !params.iter().any(crate::is_marker);
    let params = params
        .iter()
        .filter(|p| !crate::is_marker(p))
        .map(|p| match p.as_list() {
            Some([n, t]) => Some((n.as_symbol()?.to_string(), Ty::from_sexp(&t.to_sexp()))),
            _ => Some((p.as_symbol()?.to_string(), Ty::Dyn)),
        })
        .collect::<Option<Vec<_>>>()?;
    Some(Law {
        name: name.to_string(),
        span: form.span,
        params,
        plain,
        body,
    })
}

/// The law blocks of a program: `forms` is its parse. One `test` block per
/// typed law, its name carrying the tier; `seed` draws the tested calls
/// (`None`: draws are off).
#[must_use]
pub fn laws(forms: &[Spanned], backend: Backend, seed: Option<u32>) -> Vec<Spanned> {
    let found: Vec<Law<'_>> = forms.iter().filter_map(law_of).collect();
    if found.is_empty() {
        return Vec::new();
    }
    let scope = scope(forms);
    found
        .iter()
        .map(|law| block(law, &scope, backend, seed))
        .collect()
}

/// Whether `forms` holds a typed law, so a caller reads no setting for a
/// program that has none.
#[must_use]
pub fn has_laws(forms: &[Spanned]) -> bool {
    forms.iter().any(|f| law_of(f).is_some())
}

/// The result of the solver alone, for a law named in `forms`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Decision {
    Proved,
    Refuted(Vec<(String, Value)>),
    Outside(String),
}

/// What `backend` decides about the law `name` of `forms`.
#[must_use]
pub fn decide(forms: &[Spanned], name: &str, backend: Backend) -> Option<Decision> {
    let law = forms.iter().filter_map(law_of).find(|l| l.name == name)?;
    Some(decision(&law, &scope(forms), backend))
}

fn decision(law: &Law<'_>, scope: &Scope<'_>, backend: Backend) -> Decision {
    if !law.plain {
        return Decision::Outside("an optional or rest parameter".into());
    }
    let mut tr = Translate {
        scope,
        next: law.params.len(),
        sides: Vec::new(),
        depth: 0,
    };
    let query = tr.parameters(&law.params).and_then(|env| {
        let neg = tr.form(law.body, &env)?.not().map_err(stopped)?;
        let mut parts = std::mem::take(&mut tr.sides);
        parts.push(neg);
        Ok(Formula::and(parts))
    });
    let query = match query {
        Ok(q) => q,
        Err(why) => return Decision::Outside(why),
    };
    match backend.check(&query) {
        Verdict::Unsat => Decision::Proved,
        Verdict::Sat(model) => {
            witness(law, &model).map_or_else(Decision::Outside, Decision::Refuted)
        }
        Verdict::Unknown(why) => Decision::Outside(why),
    }
}

fn witness(law: &Law<'_>, model: &Model) -> Result<Vec<(String, Value)>, String> {
    law.params
        .iter()
        .enumerate()
        .map(|(i, (p, t))| {
            let v = model.get(&i).copied().unwrap_or(0);
            let value =
                match t {
                    Ty::Bool => Value::Bool(v > 0),
                    Ty::List(of) => {
                        let e = Element::of(of).ok_or_else(|| {
                            format!(
                                "the counterexample needs a {} the block cannot build",
                                t.name()
                            )
                        })?;
                        if v > LONGEST {
                            return Err(format!("the counterexample needs a list of {v} elements"));
                        }
                        Value::List(usize::try_from(v).map_err(|e| e.to_string())?, e)
                    }
                    _ => Value::Int(i64::try_from(v).map_err(|_| {
                        "the counterexample does not fit a 64-bit integer".to_string()
                    })?),
                };
            Ok((p.clone(), value))
        })
        .collect()
}

fn block(law: &Law<'_>, scope: &Scope<'_>, backend: Backend, seed: Option<u32>) -> Spanned {
    let at = law.span;
    let name = &law.name;
    let solver = backend.name();
    let (title, calls) = match decision(law, scope, backend) {
        Decision::Proved => (
            format!("proved ({solver})"),
            draws(law, seed, BESIDE_PROOF).unwrap_or_default(),
        ),
        Decision::Refuted(values) if values.is_empty() => {
            (format!("refuted ({solver})"), vec![Vec::new()])
        }
        Decision::Refuted(values) => {
            let shown: Vec<String> = values
                .iter()
                .map(|(p, v)| format!("{p} = {}", v.shown()))
                .collect();
            let args = values.iter().map(|(_, v)| v.form(at)).collect();
            (
                format!("refuted ({solver}) at {}", shown.join(", ")),
                vec![args],
            )
        }
        Decision::Outside(why) => match (seed, draws(law, seed, DRAWS)) {
            (Some(s), Some(calls)) if !calls.is_empty() => (
                format!("tested-{}, seed {s} (not proved: {why})", calls.len()),
                calls,
            ),
            (None, _) => (format!("unchecked ({why}; draws are off)"), Vec::new()),
            _ => (
                format!("unchecked ({why}; no parameter type is drawn)"),
                Vec::new(),
            ),
        },
    };
    let mut body = vec![sym(at, "begin")];
    for args in calls {
        let mut call = vec![sym(at, name)];
        call.extend(args);
        let call = Spanned::new(at, SpannedForm::List(call));
        body.push(Spanned::new(
            at,
            SpannedForm::List(vec![
                sym(at, blue_lang_syntax::LOWERED_ASSERT),
                Spanned::new(at, SpannedForm::Quote(Box::new(call.clone()))),
                call,
            ]),
        ));
    }
    if body.len() == 1 {
        body.push(Spanned::new(at, SpannedForm::Nil));
    }
    Spanned::new(
        at,
        SpannedForm::List(vec![
            sym(at, "deftest"),
            Spanned::new(
                at,
                SpannedForm::Atom(Atom::Str(format!("{LAW_PREFIX}`{name}`: {title}"))),
            ),
            Spanned::new(at, SpannedForm::List(body)),
        ]),
    )
}

fn draw(s: &mut u32, bound: u32) -> u32 {
    let v = next_uniform(*s, bound);
    *s = next_seed(*s);
    v
}

fn drawn(t: &Ty) -> bool {
    match t {
        Ty::Int | Ty::Bool => true,
        Ty::List(of) => matches!(**of, Ty::Int | Ty::Dyn),
        _ => false,
    }
}

fn small(s: &mut u32) -> i64 {
    i64::from(draw(s, 17)) - 8
}

fn draws(law: &Law<'_>, seed: Option<u32>, n: usize) -> Option<Vec<Vec<Spanned>>> {
    let seed = seed?;
    if !law.plain || !law.params.iter().all(|(_, t)| drawn(t)) {
        return None;
    }
    let at = law.span;
    let mut s = stream(seed, &law.name, 0);
    let mut seen = BTreeSet::new();
    let mut out = Vec::new();
    for _ in 0..n {
        let mut key = Vec::new();
        let mut args = Vec::new();
        for (_, t) in &law.params {
            match t {
                Ty::Bool => {
                    let b = draw(&mut s, 2) == 0;
                    key.push(vec![i64::from(b)]);
                    args.push(Spanned::new(at, SpannedForm::Atom(Atom::Bool(b))));
                }
                Ty::List(_) => {
                    let items: Vec<i64> = (0..draw(&mut s, 7)).map(|_| small(&mut s)).collect();
                    let mut list = vec![sym(at, "list")];
                    list.extend(items.iter().map(|v| int(at, *v)));
                    key.push(items);
                    args.push(Spanned::new(at, SpannedForm::List(list)));
                }
                _ => {
                    let v = if draw(&mut s, 2) == 0 {
                        small(&mut s)
                    } else {
                        i64::from(draw(&mut s, 2001)) - 1000
                    };
                    key.push(vec![v]);
                    args.push(int(at, v));
                }
            }
        }
        if seen.insert(key) {
            out.push(args);
        }
    }
    Some(out)
}

fn int(at: Span, v: i64) -> Spanned {
    Spanned::new(at, SpannedForm::Atom(Atom::Int(v)))
}

fn sym(at: Span, name: &str) -> Spanned {
    Spanned::new(at, SpannedForm::Atom(Atom::Symbol(name.into())))
}

type Cases = Vec<(Formula, Lin)>;

#[derive(Clone)]
enum Bound {
    Term(Cases),
    Form(Formula),
    List(Cases),
}

type Env = BTreeMap<String, Bound>;

struct Translate<'a, 'b> {
    scope: &'b Scope<'a>,
    next: Var,
    sides: Vec<Formula>,
    depth: usize,
}

#[allow(clippy::needless_pass_by_value)]
fn stopped(e: Stop) -> String {
    e.to_string()
}

fn constant(k: i128) -> Cases {
    vec![(Formula::True, Lin::constant(k))]
}

fn gt(a: &Lin, b: &Lin) -> Result<Formula, String> {
    Ok(Formula::pos(
        a.plus(&b.scale(-1).map_err(stopped)?).map_err(stopped)?,
    ))
}

fn eq(a: &Lin, b: &Lin) -> Result<Formula, String> {
    let one = Lin::constant(1);
    let d = a.plus(&b.scale(-1).map_err(stopped)?).map_err(stopped)?;
    Ok(Formula::and(vec![
        Formula::pos(d.plus(&one).map_err(stopped)?),
        Formula::pos(d.scale(-1).map_err(stopped)?.plus(&one).map_err(stopped)?),
    ]))
}

fn minus(a: &Lin, b: &Lin) -> Result<Lin, String> {
    a.plus(&b.scale(-1).map_err(stopped)?).map_err(stopped)
}

fn product(
    a: &Cases,
    b: &Cases,
    f: impl Fn(&Lin, &Lin) -> Result<Lin, String>,
) -> Result<Cases, String> {
    if a.len() * b.len() > MAX_CASES {
        return Err(format!("more than {MAX_CASES} cases"));
    }
    let mut out = Vec::new();
    for (ga, ta) in a {
        for (gb, tb) in b {
            let g = Formula::and(vec![ga.clone(), gb.clone()]);
            if g != Formula::False {
                out.push((g, f(ta, tb)?));
            }
        }
    }
    Ok(out)
}

fn compare(
    a: &Cases,
    b: &Cases,
    f: impl Fn(&Lin, &Lin) -> Result<Formula, String>,
) -> Result<Formula, String> {
    if a.len() * b.len() > MAX_CASES {
        return Err(format!("more than {MAX_CASES} cases"));
    }
    let mut out = Vec::new();
    for (ga, ta) in a {
        for (gb, tb) in b {
            out.push(Formula::and(vec![ga.clone(), gb.clone(), f(ta, tb)?]));
        }
    }
    Ok(Formula::or(out))
}

fn ite(c: &Formula, a: Cases, b: Cases) -> Result<Cases, String> {
    let nc = c.not().map_err(stopped)?;
    let mut out = Vec::new();
    for (g, t) in a {
        out.push((Formula::and(vec![g, c.clone()]), t));
    }
    for (g, t) in b {
        out.push((Formula::and(vec![g, nc.clone()]), t));
    }
    out.retain(|(g, _)| *g != Formula::False);
    if out.len() > MAX_CASES {
        return Err(format!("more than {MAX_CASES} cases"));
    }
    Ok(out)
}

fn extreme(a: &Cases, b: &Cases, least: bool) -> Result<Cases, String> {
    let mut out = Vec::new();
    for (ga, ta) in a {
        for (gb, tb) in b {
            let g = Formula::and(vec![ga.clone(), gb.clone()]);
            if g == Formula::False {
                continue;
            }
            let a_wins = if least { gt(tb, ta)? } else { gt(ta, tb)? };
            out.extend(ite(
                &a_wins,
                vec![(g.clone(), ta.clone())],
                vec![(g, tb.clone())],
            )?);
        }
    }
    if out.len() > MAX_CASES {
        return Err(format!("more than {MAX_CASES} cases"));
    }
    Ok(out)
}

fn kept(n: &Cases, len: &Cases) -> Result<Cases, String> {
    extreme(&extreme(n, &constant(0), false)?, len, true)
}

fn ground(c: &Cases) -> Option<i128> {
    match c.as_slice() {
        [(Formula::True, t)] if t.is_ground() => Some(t.k),
        _ => None,
    }
}

fn head_of(e: &Spanned) -> Option<(&str, &[Spanned])> {
    let [head, args @ ..] = e.as_list()? else {
        return None;
    };
    Some((head.as_symbol()?, args))
}

fn spliced(e: &Spanned) -> bool {
    head_of(e).is_some_and(|(h, _)| h == blue_lang_syntax::LOWERED_SPLICE)
}

fn fold(
    parts: Vec<Cases>,
    f: impl Fn(&Lin, &Lin) -> Result<Lin, String> + Copy,
) -> Result<Cases, String> {
    let mut it = parts.into_iter();
    let first = it.next().ok_or("an operator with no arguments")?;
    it.try_fold(first, |acc, c| product(&acc, &c, f))
}

type Reader<'a, 'b, T> = fn(&mut Translate<'a, 'b>, &Spanned, &Env) -> Result<T, String>;

impl<'a, 'b> Translate<'a, 'b> {
    fn fresh(&mut self) -> Var {
        self.next += 1;
        self.next - 1
    }

    fn parameters(&mut self, params: &[(String, Ty)]) -> Result<Env, String> {
        let mut env = Env::new();
        for (i, (p, t)) in params.iter().enumerate() {
            let v = Lin::var(i);
            let b = match t {
                Ty::Int => Bound::Term(vec![(Formula::True, v)]),
                Ty::Bool => {
                    self.sides.push(gt(&v, &Lin::constant(-1))?);
                    self.sides.push(gt(&Lin::constant(2), &v)?);
                    Bound::Form(Formula::pos(v))
                }
                Ty::List(_) => {
                    self.sides.push(gt(&v, &Lin::constant(-1))?);
                    Bound::List(vec![(Formula::True, v)])
                }
                other => return Err(format!("`{p}` is {}, not Int, Bool or List", other.name())),
            };
            env.insert(p.clone(), b);
        }
        Ok(env)
    }

    fn bind(&mut self, e: &Spanned, env: &Env) -> Result<Bound, String> {
        match self.term(e, env) {
            Ok(c) => Ok(Bound::Term(c)),
            Err(term_why) => self
                .form(e, env)
                .map(Bound::Form)
                .or_else(|_| self.len(e, env).map(Bound::List))
                .map_err(|_| term_why),
        }
    }

    fn block<T>(
        &mut self,
        args: &[Spanned],
        env: &Env,
        last: Reader<'a, 'b, T>,
    ) -> Result<T, String> {
        let Some((tail, init)) = args.split_last() else {
            return Err("an empty block".into());
        };
        let mut env = env.clone();
        for stmt in init {
            match head_of(stmt) {
                Some(("define", [name, value])) => {
                    let name = name
                        .as_symbol()
                        .ok_or("a binding that is not a name")?
                        .to_string();
                    let b = self.bind(value, &env)?;
                    env.insert(name, b);
                }
                _ => return Err("a statement other than a binding".into()),
            }
        }
        last(self, tail, &env)
    }

    fn defined<T>(
        &mut self,
        name: &str,
        args: &[Spanned],
        env: &Env,
        body: Reader<'a, 'b, T>,
    ) -> Option<Result<T, String>> {
        let scope = self.scope;
        let Some(def) = scope.defs.get(name) else {
            return scope.bound.contains(name).then(|| {
                Err(format!(
                    "`{name}` is bound in this file to something the solver does not read"
                ))
            });
        };
        if def.params.len() != args.len() {
            return Some(Err(format!(
                "`{name}` is called with {} arguments",
                args.len()
            )));
        }
        if self.depth >= MAX_DEPTH {
            return Some(Err(format!("`{name}` calls past depth {MAX_DEPTH}")));
        }
        let mut inner = Env::new();
        for (p, a) in def.params.iter().zip(args) {
            match self.bind(a, env) {
                Ok(b) => {
                    inner.insert(p.clone(), b);
                }
                Err(why) => return Some(Err(why)),
            }
        }
        self.depth += 1;
        let out = body(self, def.body, &inner);
        self.depth -= 1;
        Some(out)
    }

    fn term(&mut self, e: &Spanned, env: &Env) -> Result<Cases, String> {
        if let SpannedForm::Atom(Atom::Int(v)) = &e.form {
            return Ok(constant(i128::from(*v)));
        }
        if let Some(s) = e.as_symbol() {
            return match env.get(s) {
                Some(Bound::Term(c)) => Ok(c.clone()),
                _ => Err(format!("`{s}` is not an Int the solver reads")),
            };
        }
        let Some((head, args)) = head_of(e) else {
            return Err(format!(
                "`{}` is outside linear integer arithmetic",
                e.to_sexp()
            ));
        };
        if let Some(out) = self.defined(head, args, env, Self::term) {
            return out;
        }
        let terms = |tr: &mut Self| -> Result<Vec<Cases>, String> {
            args.iter().map(|a| tr.term(a, env)).collect()
        };
        match head {
            "+" => fold(terms(self)?, |a, b| a.plus(b).map_err(stopped)),
            "-" if args.len() == 1 => {
                let a = self.term(&args[0], env)?;
                a.into_iter()
                    .map(|(g, t)| Ok((g, t.scale(-1).map_err(stopped)?)))
                    .collect()
            }
            "-" => fold(terms(self)?, minus),
            "*" => fold(terms(self)?, |a, b| match (a.is_ground(), b.is_ground()) {
                (true, _) => b.scale(a.k).map_err(stopped),
                (_, true) => a.scale(b.k).map_err(stopped),
                _ => Err("a product of two variables is not linear".into()),
            }),
            "mod" if args.len() == 2 => {
                let a = self.term(&args[0], env)?;
                let k = ground(&self.term(&args[1], env)?)
                    .filter(|k| *k != 0)
                    .ok_or("`%` by something other than a non-zero constant")?;
                let mut out = Vec::new();
                for (g, t) in a {
                    let (q, r) = (self.fresh(), self.fresh());
                    let qr = Lin::var(q)
                        .scale(k)
                        .map_err(stopped)?
                        .plus(&Lin::var(r))
                        .map_err(stopped)?;
                    let r = Lin::var(r);
                    self.sides.push(Formula::or(vec![
                        g.not().map_err(stopped)?,
                        Formula::and(vec![
                            eq(&t, &qr)?,
                            gt(&r, &Lin::constant(-1))?,
                            gt(&Lin::constant(k.abs()), &r)?,
                        ]),
                    ]));
                    out.push((g, r));
                }
                Ok(out)
            }
            "abs" if args.len() == 1 => {
                let a = self.term(&args[0], env)?;
                let mut out = Vec::new();
                for (g, t) in a {
                    let neg = t.scale(-1).map_err(stopped)?;
                    let c = gt(&Lin::constant(0), &t)?;
                    out.extend(ite(&c, vec![(g.clone(), neg)], vec![(g, t)])?);
                }
                Ok(out)
            }
            "min" | "max" if !args.is_empty() => {
                let mut parts = terms(self)?.into_iter();
                let first = parts.next().ok_or("an empty `min`")?;
                parts.try_fold(first, |acc, c| extreme(&acc, &c, head == "min"))
            }
            "length" | "count" if args.len() == 1 => self.len(&args[0], env),
            "if" if args.len() == 3 => {
                let c = self.form(&args[0], env)?;
                let a = self.term(&args[1], env)?;
                let b = self.term(&args[2], env)?;
                ite(&c, a, b)
            }
            "begin" => self.block(args, env, Self::term),
            name => Err(format!("`{name}` is outside the fragment the solver reads")),
        }
    }

    fn len(&mut self, e: &Spanned, env: &Env) -> Result<Cases, String> {
        if let Some(s) = e.as_symbol() {
            return match env.get(s) {
                Some(Bound::List(c)) => Ok(c.clone()),
                _ => Err(format!("`{s}` is not a List the solver reads")),
            };
        }
        let Some((head, args)) = head_of(e) else {
            return Err(format!("`{}` is not a List the solver reads", e.to_sexp()));
        };
        if let Some(out) = self.defined(head, args, env, Self::len) {
            return out;
        }
        match (head, args) {
            ("list", items) if !items.iter().any(spliced) => Ok(constant(
                i128::try_from(items.len()).map_err(|e| e.to_string())?,
            )),
            ("cons", [_, tail]) => product(&self.len(tail, env)?, &constant(1), |a, b| {
                a.plus(b).map_err(stopped)
            }),
            ("append", parts) if !parts.is_empty() => {
                let lens = parts
                    .iter()
                    .map(|p| self.len(p, env))
                    .collect::<Result<Vec<_>, _>>()?;
                fold(lens, |a, b| a.plus(b).map_err(stopped))
            }
            ("reverse", [xs]) | ("map", [_, xs]) => self.len(xs, env),
            ("take", [n, xs]) => {
                let n = self.term(n, env)?;
                kept(&n, &self.len(xs, env)?)
            }
            ("drop", [n, xs]) => {
                let n = self.term(n, env)?;
                let len = self.len(xs, env)?;
                product(&len, &kept(&n, &len)?, minus)
            }
            ("range", [n]) => extreme(&self.term(n, env)?, &constant(0), false),
            ("range", [a, b]) => {
                let a = self.term(a, env)?;
                let b = self.term(b, env)?;
                extreme(&product(&b, &a, minus)?, &constant(0), false)
            }
            ("zip", [a, b]) => {
                let a = self.len(a, env)?;
                let b = self.len(b, env)?;
                extreme(&a, &b, true)
            }
            ("if", [c, a, b]) => {
                let c = self.form(c, env)?;
                let a = self.len(a, env)?;
                let b = self.len(b, env)?;
                ite(&c, a, b)
            }
            ("begin", _) => self.block(args, env, Self::len),
            _ => Err(format!("`{head}` is not a list word the solver reads")),
        }
    }

    fn form(&mut self, e: &Spanned, env: &Env) -> Result<Formula, String> {
        if let SpannedForm::Atom(Atom::Bool(b)) = &e.form {
            return Ok(Formula::truth(*b));
        }
        if let Some(s) = e.as_symbol() {
            return match env.get(s) {
                Some(Bound::Form(f)) => Ok(f.clone()),
                _ => Err(format!("`{s}` is not a Bool the solver reads")),
            };
        }
        let Some((head, args)) = head_of(e) else {
            return Err(format!(
                "`{}` is outside linear integer arithmetic",
                e.to_sexp()
            ));
        };
        if let Some(out) = self.defined(head, args, env, Self::form) {
            return out;
        }
        let pair = |tr: &mut Self| -> Result<(Cases, Cases), String> {
            match args {
                [a, b] => Ok((tr.term(a, env)?, tr.term(b, env)?)),
                _ => Err(format!("`{head}` takes two arguments here")),
            }
        };
        match head {
            "and" => Ok(Formula::and(
                args.iter()
                    .map(|a| self.form(a, env))
                    .collect::<Result<_, _>>()?,
            )),
            "or" => Ok(Formula::or(
                args.iter()
                    .map(|a| self.form(a, env))
                    .collect::<Result<_, _>>()?,
            )),
            "not" if args.len() == 1 => self.form(&args[0], env)?.not().map_err(stopped),
            ">" => {
                let (a, b) = pair(self)?;
                compare(&a, &b, gt)
            }
            "<" => {
                let (a, b) = pair(self)?;
                compare(&b, &a, gt)
            }
            ">=" => {
                let (a, b) = pair(self)?;
                compare(&b, &a, |x, y| gt(x, y)?.not().map_err(stopped))
            }
            "<=" => {
                let (a, b) = pair(self)?;
                compare(&a, &b, |x, y| gt(x, y)?.not().map_err(stopped))
            }
            "equal?" | "=" | "not=" => {
                let same = match pair(self) {
                    Ok((a, b)) => compare(&a, &b, eq)?,
                    Err(why) => {
                        let [a, b] = args else { return Err(why) };
                        let fa = self.form(a, env).map_err(|_| why.clone())?;
                        let fb = self.form(b, env).map_err(|_| why)?;
                        Formula::or(vec![
                            Formula::and(vec![fa.clone(), fb.clone()]),
                            Formula::and(vec![
                                fa.not().map_err(stopped)?,
                                fb.not().map_err(stopped)?,
                            ]),
                        ])
                    }
                };
                if head == "not=" {
                    same.not().map_err(stopped)
                } else {
                    Ok(same)
                }
            }
            "empty?" if args.len() == 1 => compare(&self.len(&args[0], env)?, &constant(0), eq),
            "if" if args.len() == 3 => {
                let c = self.form(&args[0], env)?;
                let a = self.form(&args[1], env)?;
                let b = self.form(&args[2], env)?;
                Ok(Formula::or(vec![
                    Formula::and(vec![c.clone(), a]),
                    Formula::and(vec![c.not().map_err(stopped)?, b]),
                ]))
            }
            "begin" => self.block(args, env, Self::form),
            name => Err(format!("`{name}` is outside the fragment the solver reads")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CLAMP: &str = "def clamp(x: Int, lo: Int, hi: Int) -> Int
  if x < lo
    lo
  elsif x > hi
    hi
  else
    x
  end
end

def law_clamp_in_range(x: Int, lo: Int, hi: Int) -> Bool
  lo > hi or (clamp(x, lo, hi) >= lo and clamp(x, lo, hi) <= hi)
end

def law_clamp_is_identity(x: Int, lo: Int, hi: Int) -> Bool
  clamp(x, lo, hi) == x
end
";

    fn decided(src: &str, name: &str, backend: Backend) -> Decision {
        let forms = blue_lang_syntax::parse_program_tree(src).unwrap();
        decide(&forms, name, backend).unwrap()
    }

    fn proved(body: &str) -> Decision {
        let src = format!("def law_x(a: Int, b: Int) -> Bool\n  {body}\nend\n");
        decided(&src, "law_x", Backend::Cooper)
    }

    fn listed(body: &str) -> Decision {
        let src =
            format!("def law_x(xs: List(Int), ys: List(Int), n: Int) -> Bool\n  {body}\nend\n");
        decided(&src, "law_x", Backend::Cooper)
    }

    fn ints(values: Vec<(String, Value)>) -> BTreeMap<String, i64> {
        values
            .into_iter()
            .map(|(p, v)| match v {
                Value::Int(i) => (p, i),
                Value::Bool(b) => (p, i64::from(b)),
                Value::List(n, _) => (p, i64::try_from(n).unwrap()),
            })
            .collect()
    }

    #[test]
    fn a_true_law_is_proved() {
        assert_eq!(
            decided(CLAMP, "law_clamp_in_range", Backend::Cooper),
            Decision::Proved
        );
    }

    #[test]
    fn a_false_law_is_refuted_at_a_point_where_it_is_false() {
        let Decision::Refuted(at) = decided(CLAMP, "law_clamp_is_identity", Backend::Cooper) else {
            panic!("not refuted");
        };
        let v = ints(at);
        let (x, lo, hi) = (v["x"], v["lo"], v["hi"]);
        let clamp = if x < lo {
            lo
        } else if x > hi {
            hi
        } else {
            x
        };
        assert_ne!(clamp, x, "{v:?}");
    }

    #[test]
    fn the_fragment_covers_mod_abs_min_max_and_bindings() {
        for body in [
            "a + b == b + a",
            "(a * 3) % 3 == 0",
            "a % 2 == 0 or a % 2 == 1",
            "abs(a) >= 0 and abs(0 - a) == abs(a)",
            "min(a, b) <= max(a, b)",
            "t = a * 2\n  t % 2 == 0",
            "not (a < b and b < a)",
            "a % (0 - 3) >= 0",
        ] {
            assert_eq!(proved(body), Decision::Proved, "{body}");
        }
        for body in ["a % 2 == 0", "a * 2 > a", "abs(a) > 0", "min(a, b) == a"] {
            assert!(matches!(proved(body), Decision::Refuted(_)), "{body}");
        }
    }

    #[test]
    fn the_fragment_reads_list_lengths() {
        for body in [
            "length(append(xs, ys)) == length(xs) + length(ys)",
            "length(reverse(xs)) == count(xs)",
            "length(cons(n, xs)) > length(xs)",
            "length(take(n, xs)) <= length(xs)",
            "length(take(n, xs)) + length(drop(n, xs)) == length(xs)",
            "length(zip(xs, ys)) <= length(ys)",
            "length(range(n)) >= 0 and length(range(n, n + 3)) == 3",
            "length([n, n]) == 2",
            "empty?(xs) == (length(xs) == 0)",
            "length(map(fn(x) x + 1 end, xs)) == length(xs)",
            "zs = append(xs, [n])\n  length(zs) > length(xs)",
        ] {
            assert_eq!(listed(body), Decision::Proved, "{body}");
        }
        for body in [
            "length(take(n, xs)) == n",
            "length(append(xs, ys)) > length(xs)",
            "not empty?(xs)",
        ] {
            assert!(matches!(listed(body), Decision::Refuted(_)), "{body}");
        }
        for body in [
            "xs == reverse(xs)",
            "length(rest(xs)) == length(xs) - 1",
            "first(xs) == n",
        ] {
            assert!(matches!(listed(body), Decision::Outside(_)), "{body}");
        }
    }

    #[test]
    fn a_refuted_list_law_names_a_list_of_the_length_the_solver_chose() {
        let Decision::Refuted(at) = listed("length(take(n, xs)) == n") else {
            panic!("not refuted");
        };
        let v = ints(at);
        assert_ne!(v["n"].max(0).min(v["xs"]), v["n"], "{v:?}");
    }

    #[test]
    fn a_bool_parameter_is_read_as_a_truth_value() {
        let src = "def law_b(a: Int, up: Bool) -> Bool
  b = if up
    a + 1
  else
    a - 1
  end
  b != a
end

def law_c(a: Int, up: Bool) -> Bool
  up or a > 0
end
";
        assert_eq!(decided(src, "law_b", Backend::Cooper), Decision::Proved);
        let Decision::Refuted(at) = decided(src, "law_c", Backend::Cooper) else {
            panic!("not refuted");
        };
        assert_eq!(at[1], ("up".to_string(), Value::Bool(false)));
    }

    #[test]
    fn outside_the_fragment_is_named_and_never_proved() {
        for body in ["a * b == b * a", "a / 2 == 0", "size([a]) == 1"] {
            assert!(matches!(proved(body), Decision::Outside(_)), "{body}");
        }
    }

    #[test]
    fn a_word_the_file_rebinds_is_read_as_the_file_defines_it() {
        let src =
            "def abs(x: Int) -> Int\n  x\nend\n\ndef law_x(a: Int) -> Bool\n  abs(a) >= 0\nend\n";
        assert!(matches!(
            decided(src, "law_x", Backend::Cooper),
            Decision::Refuted(_)
        ));
    }

    #[test]
    fn a_word_a_use_brings_in_bare_is_outside() {
        let src = "use(\"kazu\", [:abs])\n\ndef law_x(a: Int) -> Bool\n  abs(a) >= 0\nend\n";
        assert!(matches!(
            decided(src, "law_x", Backend::Cooper),
            Decision::Outside(_)
        ));
    }

    #[test]
    fn no_solver_proves_nothing() {
        assert!(matches!(
            decided(CLAMP, "law_clamp_in_range", Backend::Absent),
            Decision::Outside(_)
        ));
    }

    fn titles(src: &str, backend: Backend, seed: Option<u32>) -> Vec<String> {
        let forms = blue_lang_syntax::parse_program_tree(src).unwrap();
        laws(&forms, backend, seed)
            .iter()
            .map(|t| t.as_list().unwrap()[1].as_string().unwrap().to_string())
            .collect()
    }

    #[test]
    fn each_law_block_names_its_tier() {
        let got = titles(CLAMP, Backend::Cooper, Some(1));
        assert_eq!(got[0], "@law `law_clamp_in_range`: proved (cooper)");
        assert!(
            got[1].starts_with("@law `law_clamp_is_identity`: refuted (cooper) at x = "),
            "{}",
            got[1]
        );
        let tested = titles(CLAMP, Backend::Absent, Some(1));
        assert!(
            tested[0].starts_with("@law `law_clamp_in_range`: tested-"),
            "{}",
            tested[0]
        );
        assert!(matches!(Tier::of_test(&tested[0]), Some(Tier::Tested(n)) if n > 32));
        let none = titles(CLAMP, Backend::Absent, None);
        assert!(none[0].contains(": unchecked ("), "{}", none[0]);
        assert_eq!(Tier::of_test(&got[0]), Some(Tier::Proved));
        assert_eq!(Tier::of_test(&got[1]), Some(Tier::Refuted));
        assert_eq!(Tier::of_test(&none[0]), Some(Tier::Unchecked));
    }

    #[test]
    fn a_list_counterexample_is_written_as_a_list() {
        let src = "def law_x(xs: List(Str), n: Int) -> Bool\n  length(take(n, xs)) == n\nend\n";
        let got = titles(src, Backend::Cooper, Some(1));
        assert!(got[0].contains("refuted (cooper) at xs = ["), "{}", got[0]);
        let unbuilt = "def law_x(xs: List(Map), n: Int) -> Bool\n  length(take(n, xs)) == n\nend\n";
        let got = titles(unbuilt, Backend::Cooper, Some(1));
        assert!(
            got[0].contains("unchecked (the counterexample needs a"),
            "{}",
            got[0]
        );
    }

    #[test]
    fn an_untyped_law_gets_no_block() {
        let src = "def law_x(a)\n  a == a\nend\n";
        assert!(titles(src, Backend::Cooper, Some(1)).is_empty());
    }

    #[test]
    fn the_setting_reads_cooper_tested_or_off_and_refuses_the_rest() {
        assert_eq!(
            Setting::from_setting(None),
            Ok(Setting::On(Backend::Cooper))
        );
        assert_eq!(
            Setting::from_setting(Some("tested")),
            Ok(Setting::On(Backend::Absent))
        );
        assert_eq!(Setting::from_setting(Some("off")), Ok(Setting::Off));
        assert!(Setting::from_setting(Some("z3")).unwrap_err().contains(ENV));
    }
}
