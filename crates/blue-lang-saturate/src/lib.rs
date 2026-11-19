//! Equality saturation over blue's erased trees: S2 of docs/ENGINES.md.
//!
//! The typed surface blue reaches `egg` through (Willsey et al., POPL 2021);
//! nothing else in blue names `egg`. An erased tree goes in as a
//! [`RecExpr`] over `egg`'s [`SymbolLang`], rules saturate it within
//! [`Limits`], and a cost function picks the form that comes out.
//!
//! The encoding is one to one. A list whose head is a symbol and which has
//! arguments is an e-node named by that symbol, its arguments the children;
//! any other list is a `#list` node over all its items, so a call with no
//! arguments is never read back as a bare name. A symbol is a leaf of its
//! own name; every other atom is a leaf whose name starts with a mark no
//! blue symbol can start with (`#`, `:` or `"`). Positions do not survive:
//! what comes back carries synthetic spans.

use egg::{
    Applier, AstSize, CostFunction, EGraph, Extractor, Id, Language, Pattern, PatternAst, RecExpr,
    Rewrite, Runner, Subst, Symbol, SymbolLang,
};
use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

/// One rewrite rule over encoded trees.
pub type Rule = Rewrite<SymbolLang, ()>;

/// How far saturation may go before it stops.
#[derive(Clone, Copy, Debug)]
pub struct Limits {
    pub iterations: usize,
    pub nodes: usize,
    pub time: std::time::Duration,
}

impl Default for Limits {
    fn default() -> Self {
        Limits {
            iterations: 30,
            nodes: 10_000,
            time: std::time::Duration::from_millis(200),
        }
    }
}

const LIST: &str = "#list";

fn leaf(atom: &Atom) -> String {
    match atom {
        Atom::Symbol(s) => s.clone(),
        Atom::Keyword(k) => format!(":{k}"),
        Atom::Str(s) => format!("{s:?}"),
        Atom::Int(n) => format!("#i{n}"),
        Atom::Float(f) => format!("#f{}", f.to_bits()),
        Atom::Bool(true) => "#t".into(),
        Atom::Bool(false) => "#f".into(),
    }
}

fn atom(name: &str) -> Option<Atom> {
    if let Some(k) = name.strip_prefix(':') {
        return Some(Atom::Keyword(k.into()));
    }
    if name.starts_with('"') {
        return serde_json_like_unquote(name).map(Atom::Str);
    }
    match name {
        "#t" => return Some(Atom::Bool(true)),
        "#f" => return Some(Atom::Bool(false)),
        _ => {}
    }
    if let Some(n) = name.strip_prefix("#i") {
        return n.parse().ok().map(Atom::Int);
    }
    if let Some(bits) = name.strip_prefix("#f") {
        return bits.parse().ok().map(f64::from_bits).map(Atom::Float);
    }
    (!name.starts_with('#')).then(|| Atom::Symbol(name.into()))
}

fn serde_json_like_unquote(quoted: &str) -> Option<String> {
    let inner = quoted.strip_prefix('"')?.strip_suffix('"')?;
    let mut out = String::with_capacity(inner.len());
    let mut chars = inner.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next()? {
            'n' => out.push('\n'),
            't' => out.push('\t'),
            'r' => out.push('\r'),
            '0' => out.push('\0'),
            '\\' => out.push('\\'),
            '"' => out.push('"'),
            '\'' => out.push('\''),
            'u' => {
                let hex: String = chars.by_ref().skip(1).take_while(|c| *c != '}').collect();
                out.push(char::from_u32(u32::from_str_radix(&hex, 16).ok()?)?);
            }
            _ => return None,
        }
    }
    Some(out)
}

const QUOTES: [&str; 4] = ["#quote", "#quasiquote", "#unquote", "#splice"];

fn add(form: &Spanned, expr: &mut RecExpr<SymbolLang>) -> Id {
    let node = |op: &str, children: Vec<Id>| SymbolLang::new(op, children);
    match &form.form {
        SpannedForm::Nil => expr.add(node("#nil", vec![])),
        SpannedForm::Atom(a) => expr.add(node(&leaf(a), vec![])),
        SpannedForm::Quote(q) => {
            let c = add(q, expr);
            expr.add(node(QUOTES[0], vec![c]))
        }
        SpannedForm::Quasiquote(q) => {
            let c = add(q, expr);
            expr.add(node(QUOTES[1], vec![c]))
        }
        SpannedForm::Unquote(q) => {
            let c = add(q, expr);
            expr.add(node(QUOTES[2], vec![c]))
        }
        SpannedForm::UnquoteSplice(q) => {
            let c = add(q, expr);
            expr.add(node(QUOTES[3], vec![c]))
        }
        SpannedForm::List(items) => match items.split_first() {
            Some((head, args)) if !args.is_empty() && head.as_symbol().is_some() => {
                let op = head.as_symbol().unwrap_or_default().to_string();
                let children = args.iter().map(|a| add(a, expr)).collect();
                expr.add(node(&op, children))
            }
            _ => {
                let children = items.iter().map(|a| add(a, expr)).collect();
                expr.add(node(LIST, children))
            }
        },
    }
}

/// `form` as an expression `egg` saturates.
#[must_use]
pub fn to_expr(form: &Spanned) -> RecExpr<SymbolLang> {
    let mut expr = RecExpr::default();
    add(form, &mut expr);
    expr
}

fn spanned(form: SpannedForm) -> Spanned {
    Spanned::new(Span::synthetic(), form)
}

fn back(expr: &RecExpr<SymbolLang>, id: Id) -> Option<Spanned> {
    let node = &expr[id];
    let op = node.op.as_str();
    let children: Vec<Spanned> = node
        .children()
        .iter()
        .map(|c| back(expr, *c))
        .collect::<Option<_>>()?;
    if let Some(i) = QUOTES.iter().position(|q| *q == op) {
        let [inner] = <[Spanned; 1]>::try_from(children).ok()?;
        let inner = Box::new(inner);
        return Some(spanned(match i {
            0 => SpannedForm::Quote(inner),
            1 => SpannedForm::Quasiquote(inner),
            2 => SpannedForm::Unquote(inner),
            _ => SpannedForm::UnquoteSplice(inner),
        }));
    }
    if op == "#nil" && children.is_empty() {
        return Some(spanned(SpannedForm::Nil));
    }
    if op == LIST {
        return Some(spanned(SpannedForm::List(children)));
    }
    if children.is_empty() {
        return atom(op).map(|a| spanned(SpannedForm::Atom(a)));
    }
    let mut items = vec![spanned(SpannedForm::Atom(Atom::Symbol(op.into())))];
    items.extend(children);
    Some(spanned(SpannedForm::List(items)))
}

/// The tree `expr` encodes, or `None` when it encodes none.
#[must_use]
pub fn from_expr(expr: &RecExpr<SymbolLang>) -> Option<Spanned> {
    let root = Id::from(expr.as_ref().len().checked_sub(1)?);
    back(expr, root)
}

/// A rule from two patterns written over encoded trees, `?x` a variable:
/// `rule("double-reverse", "(reverse (reverse ?x))", "?x")`.
///
/// # Errors
///
/// A pattern that does not parse, or a right side naming a variable the left
/// does not bind.
pub fn rule(name: &str, lhs: &str, rhs: &str) -> Result<Rule, String> {
    let l: Pattern<SymbolLang> = lhs.parse().map_err(|e| format!("{name}: {e}"))?;
    let r: Pattern<SymbolLang> = rhs.parse().map_err(|e| format!("{name}: {e}"))?;
    Rewrite::new(name, l, r)
}

/// A rewrite a pattern cannot write, such as one that builds a function:
/// each class `pattern` matches has its smallest member decoded and handed
/// to `transform`, and what comes back joins the class.
struct Transformed<F> {
    transform: F,
}

impl<F> Applier<SymbolLang, ()> for Transformed<F>
where
    F: Fn(&Spanned) -> Option<Spanned> + Send + Sync + 'static,
{
    fn apply_one(
        &self,
        egraph: &mut EGraph<SymbolLang, ()>,
        eclass: Id,
        _subst: &Subst,
        _searcher_ast: Option<&PatternAst<SymbolLang>>,
        _rule_name: Symbol,
    ) -> Vec<Id> {
        let (_, smallest) = Extractor::new(egraph, AstSize).find_best(eclass);
        let Some(out) = from_expr(&smallest).and_then(|form| (self.transform)(&form)) else {
            return Vec::new();
        };
        let added = egraph.add_expr(&to_expr(&out));
        if egraph.union(eclass, added) {
            vec![added]
        } else {
            Vec::new()
        }
    }
}

/// A rule whose right side is `transform`, run on each tree `pattern`
/// matches; `None` from it adds nothing.
///
/// # Errors
///
/// A pattern that does not parse.
pub fn form_rule<F>(name: &str, pattern: &str, transform: F) -> Result<Rule, String>
where
    F: Fn(&Spanned) -> Option<Spanned> + Send + Sync + 'static,
{
    let l: Pattern<SymbolLang> = pattern.parse().map_err(|e| format!("{name}: {e}"))?;
    Rewrite::new(name, l, Transformed { transform })
}

fn runner(
    exprs: &[&RecExpr<SymbolLang>],
    rules: &[Rule],
    limits: Limits,
) -> Runner<SymbolLang, ()> {
    let mut r = Runner::default()
        .with_iter_limit(limits.iterations)
        .with_node_limit(limits.nodes)
        .with_time_limit(limits.time);
    for e in exprs {
        r = r.with_expr(e);
    }
    r.run(rules)
}

/// Whether `rules` prove `a` and `b` equal within `limits`: `Some(true)`
/// when they land in one class, `Some(false)` when the graph saturated and
/// they did not, `None` when a limit stopped it first.
#[must_use]
pub fn equivalent(a: &Spanned, b: &Spanned, rules: &[Rule], limits: Limits) -> Option<bool> {
    let (ea, eb) = (to_expr(a), to_expr(b));
    let r = runner(&[&ea, &eb], rules, limits);
    let same = r.egraph.find(r.roots[0]) == r.egraph.find(r.roots[1]);
    match (same, &r.stop_reason) {
        (true, _) => Some(true),
        (false, Some(egg::StopReason::Saturated)) => Some(false),
        _ => None,
    }
}

/// What a node costs when its children cost what they do: a function of the
/// node's name and its children's costs.
pub struct Priced<F: FnMut(&str, &[f64]) -> f64>(pub F);

impl<F: FnMut(&str, &[f64]) -> f64> CostFunction<SymbolLang> for Priced<F> {
    type Cost = Cost;
    fn cost<C>(&mut self, enode: &SymbolLang, mut costs: C) -> Cost
    where
        C: FnMut(Id) -> Cost,
    {
        let children: Vec<f64> = enode.children().iter().map(|c| costs(*c).0).collect();
        Cost((self.0)(enode.op.as_str(), &children))
    }
}

/// A cost `egg` can order: a finite price, a NaN read as the dearest.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Cost(pub f64);

impl PartialOrd for Cost {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.0.total_cmp(&other.0))
    }
}

/// The cheapest form `rules` prove equal to `form` within `limits`, by
/// `price`; `form` itself when nothing cheaper is found. The cost the form
/// had and the cost of what comes back.
#[must_use]
pub fn cheapest<F: FnMut(&str, &[f64]) -> f64>(
    form: &Spanned,
    rules: &[Rule],
    limits: Limits,
    price: F,
) -> (Spanned, f64, f64) {
    let expr = to_expr(form);
    let mut priced = Priced(price);
    let before = priced.cost_rec(&expr).0;
    let r = runner(&[&expr], rules, limits);
    let extractor = Extractor::new(&r.egraph, priced);
    let (after, best) = extractor.find_best(r.roots[0]);
    match from_expr(&best) {
        Some(out) if after.0 < before => (out, before, after.0),
        _ => (form.clone(), before, before),
    }
}

/// The node count of `form`, the price [`cheapest`] uses when no table is
/// given.
#[must_use]
pub fn size(form: &Spanned) -> usize {
    AstSize.cost_rec(&to_expr(form))
}
