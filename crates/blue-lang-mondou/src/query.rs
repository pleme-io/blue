//! `query(document, q)`: the definitions of a file that satisfy a query, where
//! each one matched and what its pattern bound (`theory/BLUE-TOOLING.md`
//! T-K). `blue query` and any later door ask this one call.
//!
//! A query is tatara-lisp data, read by tatara's own reader; several forms
//! are their conjunction:
//!
//! | clause | holds for a definition when |
//! |---|---|
//! | `(match PATTERN)` | a form of its resolved tree matches `PATTERN`; each matching form is a hit, with what the pattern bound |
//! | `(reaches CAP)` | it names a primitive of host capability `CAP` (`process`, `filesystem`, `environment`, `clock`, `network`; `host` for any), directly or through the definitions it references |
//! | `(annotated)`, `(unannotated)` | it is, or is not, a typed definition (`define-typed`) |
//! | `(calls NAME)` | a reference in it resolves to NAME: `retsu/first` (or `retsu::first`) for a bidama's definition, `%root/f` for a script's own, `first` for the builtin |
//! | `(package NAME)` | it is defined in bidama NAME |
//! | `(longer-than N)` | its tree has more than N forms |
//! | `(kind K)` | it is a `function`, `macro` or `value` |
//! | `(and C …)`, `(or C …)`, `(not C)` | the connectives |
//!
//! **A pattern is tatara's `match` pattern, compiled by tatara's own
//! `compile-match-pattern`**, not a second matcher. Its quasipatterns read as
//! the code they match: `` `(retsu/first ,xs) `` is a call to retsu's `first`
//! with one argument, bound to `xs`; `` `(define (,name ,@params) ,@body) ``
//! is any function definition. Outside an unquote a symbol matches itself;
//! `,_` matches anything; `,(? string? s)` runs a predicate.
//!
//! **Patterns see the resolved tree** ([`Resolved::resolved_tree`]), the one
//! the runtime evaluates: every reference to a definition is written as its
//! key, so `` `(retsu/first ,@_) `` finds a call whether the file wrote
//! `first` after `use("retsu", [:first])` or `retsu::first`, and a local
//! named `first` is not one. `blue ast FILE` prints a file's tree.
//!
//! **A predicate runs under a pure frame.** A pattern whose compiled test
//! names a host-effect primitive, or `eval`, is refused before anything runs,
//! and each test runs under a step budget.
//!
//! [`Resolved::resolved_tree`]: blue_lang_check::names::Resolved::resolved_tree

use std::cell::RefCell;
use std::collections::{BTreeSet, HashMap};

use blue_lang_check::names::{key, Rule};
use blue_lang_check::Namespace;
use blue_lang_syntax::{Atom, Sexp, Span, Spanned, SpannedForm};
use blue_lang_waku::Capability;
use tatara_lisp_eval::{Interpreter, Value};

use crate::reach::{host_capability, HostReach};
use crate::{Analysis, Engine, FileRef, ItemKind};

/// The steps one pattern test may take on one form.
pub const MATCH_STEPS: usize = 100_000;

/// The names a pattern's test may not reach besides the host effects: the
/// doors that evaluate data.
const EVALUATES: &[&str] = &["eval", "require", "provide"];

/// What a pattern's test is called with, and what a miss returns.
const NODE: &str = "blue-query-node";
const MISS: &str = "blue-query-miss";

/// Why a query was refused.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum QueryError {
    /// The text is not tatara-lisp data.
    Read(String),
    /// A clause the grammar does not have, or one given the wrong arguments.
    Clause { clause: String, reason: String },
    /// A pattern `match` cannot compile.
    Pattern { pattern: String, reason: String },
    /// A pattern whose test names what a query may not run.
    Refused { pattern: String, names: Vec<String> },
    /// A pattern's test failed or ran past [`MATCH_STEPS`] on a form.
    Test { pattern: String, reason: String },
}

impl std::fmt::Display for QueryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            QueryError::Read(e) => write!(f, "the query does not read as tatara-lisp data: {e}"),
            QueryError::Clause { clause, reason } => write!(f, "`{clause}`: {reason}"),
            QueryError::Pattern { pattern, reason } => {
                write!(f, "pattern `{pattern}` does not compile: {reason}")
            }
            QueryError::Refused { pattern, names } => write!(
                f,
                "pattern `{pattern}` names {}, which a query may not run",
                names.join(", ")
            ),
            QueryError::Test { pattern, reason } => write!(f, "pattern `{pattern}`: {reason}"),
        }
    }
}

impl std::error::Error for QueryError {}

/// A host capability a `reaches` clause names, or any of them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reaches {
    Any,
    One(Capability),
}

#[derive(Debug)]
enum Clause {
    All(Vec<Clause>),
    Any(Vec<Clause>),
    Not(Box<Clause>),
    Match(usize),
    Reaches(Reaches),
    Annotated(bool),
    Calls(String),
    Package(String),
    LongerThan(usize),
    Kind(ItemKind),
}

/// One compiled pattern.
struct Matcher {
    pattern: String,
    names: Vec<String>,
    /// A form whose first element is not this symbol cannot match.
    head: Option<String>,
    /// Only a list can match.
    list: bool,
    test: Value,
}

/// A parsed, compiled query.
pub struct Query {
    source: String,
    clause: Clause,
    matchers: Vec<Matcher>,
    interp: RefCell<Interpreter<()>>,
}

impl std::fmt::Debug for Query {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Query")
            .field("source", &self.source)
            .finish()
    }
}

/// One answer: a definition, and the form in it that matched.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Hit {
    pub file: FileRef,
    /// The matched form, or the definition when no pattern placed the hit.
    pub span: Span,
    pub line: usize,
    pub column: usize,
    /// The definition's name as written.
    pub definition: String,
    /// Its runtime key: `retsu/first`, `%root/f`.
    pub key: String,
    pub kind: ItemKind,
    /// The whole definition.
    pub def_span: Span,
    /// What the pattern bound, in the pattern's order, as tatara-lisp text.
    pub bindings: Vec<(String, String)>,
    /// Every host capability the definition reaches, with the chain of
    /// definitions it reaches it through, ending at the primitive.
    pub reach: HostReach,
}

impl Hit {
    /// The hit as every door prints it under `--json`, with `file` the name
    /// the door gives its file:
    ///
    /// ```text
    /// {"file", "line", "column", "definition", "key", "kind",
    ///  "bindings": {name: text}, "reach": {capability: [via…, primitive]}}
    /// ```
    #[must_use]
    pub fn json(&self, file: &str) -> serde_json::Value {
        let kind = match self.kind {
            ItemKind::Function => "function",
            ItemKind::Macro => "macro",
            ItemKind::Value => "value",
            ItemKind::Test => "test",
            ItemKind::Use => "use",
        };
        serde_json::json!({
            "file": file,
            "line": self.line,
            "column": self.column,
            "definition": self.definition,
            "key": self.key,
            "kind": kind,
            "bindings": self
                .bindings
                .iter()
                .map(|(n, v)| (n.clone(), serde_json::Value::String(v.clone())))
                .collect::<serde_json::Map<_, _>>(),
            "reach": self
                .reach
                .iter()
                .map(|(c, via)| (c.label().to_string(), serde_json::json!(via)))
                .collect::<serde_json::Map<_, _>>(),
        })
    }
}

impl Query {
    /// Read `text` as a query.
    ///
    /// # Errors
    ///
    /// The text does not read, a clause is not in the grammar, or a pattern
    /// does not compile or names what a query may not run.
    pub fn parse(text: &str) -> Result<Query, QueryError> {
        let forms = tatara_lisp_eval::read(text).map_err(|e| QueryError::Read(e.to_string()))?;
        if forms.is_empty() {
            return Err(QueryError::Read("it is empty".into()));
        }
        let mut q = Query {
            source: forms
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join(" "),
            clause: Clause::All(Vec::new()),
            matchers: Vec::new(),
            interp: RefCell::new(blue_lang_runtime::interpreter_hostless()),
        };
        let mut all = Vec::with_capacity(forms.len());
        for f in &forms {
            all.push(q.clause(f)?);
        }
        q.clause = Clause::All(all);
        Ok(q)
    }

    /// The query as tatara-lisp text, one space between its forms.
    #[must_use]
    pub fn source(&self) -> &str {
        &self.source
    }

    /// Every capability a `reaches` clause names, wherever it sits.
    #[must_use]
    pub fn reaches(&self) -> Vec<Reaches> {
        fn walk(c: &Clause, out: &mut Vec<Reaches>) {
            match c {
                Clause::All(cs) | Clause::Any(cs) => cs.iter().for_each(|c| walk(c, out)),
                Clause::Not(c) => walk(c, out),
                Clause::Reaches(r) => out.push(*r),
                Clause::Match(_)
                | Clause::Annotated(_)
                | Clause::Calls(_)
                | Clause::Package(_)
                | Clause::LongerThan(_)
                | Clause::Kind(_) => {}
            }
        }
        let mut out = Vec::new();
        walk(&self.clause, &mut out);
        out
    }

    fn clause(&mut self, form: &Sexp) -> Result<Clause, QueryError> {
        let bad = |reason: &str| QueryError::Clause {
            clause: form.to_string(),
            reason: reason.to_string(),
        };
        let Sexp::List(items) = form else {
            return Err(bad("a clause is a list: (match P), (reaches C), (and …)"));
        };
        let Some(Sexp::Atom(Atom::Symbol(head))) = items.first() else {
            return Err(bad("a clause starts with its name"));
        };
        let args = &items[1..];
        let one = || match args {
            [a] => Ok(a),
            _ => Err(bad("takes one argument")),
        };
        let none = || {
            if args.is_empty() {
                Ok(())
            } else {
                Err(bad("takes no argument"))
            }
        };
        Ok(match head.as_str() {
            "and" | "begin" => Clause::All(self.clauses(args)?),
            "or" => Clause::Any(self.clauses(args)?),
            "not" => Clause::Not(Box::new(self.clause(one()?)?)),
            "match" => {
                let pattern = one()?.clone();
                let m = self.compile(&pattern)?;
                self.matchers.push(m);
                Clause::Match(self.matchers.len() - 1)
            }
            "reaches" => {
                let label = word(one()?).ok_or_else(|| bad("names a capability"))?;
                if label == "host" {
                    Clause::Reaches(Reaches::Any)
                } else {
                    let cap = Capability::host_effects()
                        .into_iter()
                        .find(|c| c.label() == label)
                        .ok_or_else(|| {
                            bad(&format!(
                                "`{label}` is not a host capability: host, {}",
                                Capability::host_effects()
                                    .iter()
                                    .map(|c| c.label())
                                    .collect::<Vec<_>>()
                                    .join(", ")
                            ))
                        })?;
                    Clause::Reaches(Reaches::One(cap))
                }
            }
            "annotated" => {
                none()?;
                Clause::Annotated(true)
            }
            "unannotated" => {
                none()?;
                Clause::Annotated(false)
            }
            "calls" => {
                let name = word(one()?).ok_or_else(|| bad("names a definition"))?;
                Clause::Calls(name.replace("::", "/"))
            }
            "package" => Clause::Package(word(one()?).ok_or_else(|| bad("names a bidama"))?),
            "longer-than" => match one()? {
                Sexp::Atom(Atom::Int(n)) if *n >= 0 => {
                    Clause::LongerThan(usize::try_from(*n).unwrap_or(usize::MAX))
                }
                _ => return Err(bad("takes a count of forms")),
            },
            "kind" => Clause::Kind(match word(one()?).as_deref() {
                Some("function") => ItemKind::Function,
                Some("macro") => ItemKind::Macro,
                Some("value") => ItemKind::Value,
                _ => return Err(bad("is function, macro or value")),
            }),
            other => {
                return Err(bad(&format!(
                    "`{other}` is not a clause: match, reaches, annotated, unannotated, calls, package, longer-than, kind, and, or, not"
                )))
            }
        })
    }

    fn clauses(&mut self, forms: &[Sexp]) -> Result<Vec<Clause>, QueryError> {
        forms.iter().map(|f| self.clause(f)).collect()
    }

    /// Compile `pattern` with tatara's `compile-match-pattern` into a test
    /// that returns the bound values, or the miss keyword.
    fn compile(&self, pattern: &Sexp) -> Result<Matcher, QueryError> {
        let text = pattern.to_string();
        let fail = |reason: String| QueryError::Pattern {
            pattern: text.clone(),
            reason,
        };
        let mut interp = self.interp.borrow_mut();
        let call = Sexp::List(vec![
            sym("compile-match-pattern"),
            Sexp::Quote(Box::new(sym(NODE))),
            Sexp::Quote(Box::new(pattern.clone())),
        ]);
        let compiled = interp
            .eval_spanned(&Spanned::from_sexp_at(&call, Span::synthetic()), &mut ())
            .map_err(|e| fail(e.to_string()))?;
        let compiled = as_sexp(&compiled).map_err(&fail)?;
        let (test, binds) = match &compiled {
            Sexp::List(parts) if parts.len() == 2 => (parts[0].clone(), parts[1].clone()),
            other => return Err(fail(format!("compiled to {other}"))),
        };
        let mut names = Vec::new();
        let mut values = vec![sym("list")];
        if let Sexp::List(binds) = binds {
            for b in binds {
                match b {
                    Sexp::List(pair) if pair.len() == 2 => {
                        names.push(pair[0].to_string());
                        values.push(pair[1].clone());
                    }
                    other => return Err(fail(format!("a binding compiled to {other}"))),
                }
            }
        }
        let lambda = Sexp::List(vec![
            sym("lambda"),
            Sexp::List(vec![sym(NODE)]),
            Sexp::List(vec![
                sym("if"),
                test,
                Sexp::List(values),
                Sexp::Atom(Atom::Keyword(MISS.into())),
            ]),
        ]);
        let spanned = Spanned::from_sexp_at(&lambda, Span::synthetic());
        let refused = blue_lang_waku::free_names(std::slice::from_ref(&spanned), &|n| may_name(n));
        if !refused.is_empty() {
            return Err(QueryError::Refused {
                pattern: text,
                names: refused.into_iter().collect(),
            });
        }
        let test = interp
            .eval_spanned(&spanned, &mut ())
            .map_err(|e| fail(e.to_string()))?;
        let (head, list) = shape(pattern);
        Ok(Matcher {
            pattern: text,
            names,
            head,
            list,
            test,
        })
    }

    /// Every form under `form` (itself included) that matcher `m` matches,
    /// with what it bound.
    fn sites(&self, m: &Matcher, form: &Spanned) -> Result<Vec<Site>, QueryError> {
        let mut out = Vec::new();
        let mut interp = self.interp.borrow_mut();
        let mut stack = vec![form];
        while let Some(node) = stack.pop() {
            match &node.form {
                SpannedForm::List(items) => stack.extend(
                    items
                        .iter()
                        .enumerate()
                        .filter(|(i, _)| !(*i == 1 && signature_of_definition(items)))
                        .map(|(_, f)| f)
                        .rev(),
                ),
                SpannedForm::Quote(x)
                | SpannedForm::Quasiquote(x)
                | SpannedForm::Unquote(x)
                | SpannedForm::UnquoteSplice(x) => stack.push(x),
                SpannedForm::Nil | SpannedForm::Atom(_) => {}
            }
            if m.list && !matches!(node.form, SpannedForm::List(_)) {
                continue;
            }
            if let Some(h) = &m.head {
                let first = node.as_list().and_then(|l| l.first());
                if first.and_then(Spanned::as_symbol) != Some(h.as_str()) {
                    continue;
                }
            }
            let _ = interp.set_budget(tatara_lisp_eval::vm::Budget {
                fuel: Some(MATCH_STEPS),
                max_depth: Some(blue_lang_runtime::execution_bounds().max_call_depth),
                quantum: None,
            });
            let value = tatara_lisp_eval::code::spanned_to_value(node);
            let got = interp
                .apply_external_value(&m.test, vec![value], &mut (), node.span)
                .map_err(|e| QueryError::Test {
                    pattern: m.pattern.clone(),
                    reason: e.to_string(),
                })?;
            if let Value::List(bound) = got {
                out.push(Site {
                    span: node.span,
                    bindings: m
                        .names
                        .iter()
                        .cloned()
                        .zip(bound.iter().map(ToString::to_string))
                        .collect(),
                });
            }
        }
        out.sort_by_key(|s| (s.span.start, s.span.end));
        Ok(out)
    }
}

/// A place a pattern matched.
#[derive(Clone, Debug, PartialEq, Eq)]
struct Site {
    span: Span,
    bindings: Vec<(String, String)>,
}

/// What a clause sees of one definition.
struct Def<'a> {
    kind: ItemKind,
    annotated: bool,
    namespace: Namespace,
    resolved: &'a Spanned,
    forms: usize,
    references: &'a BTreeSet<String>,
    reach: &'a HostReach,
}

impl Query {
    /// `None` when the clause does not hold; otherwise the places that placed
    /// it (none for a clause about the whole definition).
    fn holds(&self, c: &Clause, d: &Def<'_>) -> Result<Option<Vec<Site>>, QueryError> {
        let whole = |b: bool| Ok(b.then(Vec::new));
        match c {
            Clause::All(cs) => {
                let mut sites = Vec::new();
                for c in cs {
                    match self.holds(c, d)? {
                        Some(s) => sites.extend(s),
                        None => return Ok(None),
                    }
                }
                Ok(Some(sites))
            }
            Clause::Any(cs) => {
                let mut any = None;
                for c in cs {
                    if let Some(s) = self.holds(c, d)? {
                        any.get_or_insert_with(Vec::new).extend(s);
                    }
                }
                Ok(any)
            }
            Clause::Not(c) => whole(self.holds(c, d)?.is_none()),
            Clause::Match(i) => {
                let sites = self.sites(&self.matchers[*i], d.resolved)?;
                Ok((!sites.is_empty()).then_some(sites))
            }
            Clause::Reaches(Reaches::Any) => whole(!d.reach.is_empty()),
            Clause::Reaches(Reaches::One(cap)) => whole(d.reach.contains_key(cap)),
            Clause::Annotated(want) => whole(d.annotated == *want),
            Clause::Calls(name) => whole(d.references.contains(name)),
            Clause::Package(p) => whole(d.namespace == Namespace::Bidama(p.clone())),
            Clause::LongerThan(n) => whole(d.forms > *n),
            Clause::Kind(k) => whole(d.kind == *k),
        }
    }
}

impl Engine {
    /// Every definition of document `id` that satisfies `query`, in source
    /// order. Empty when the document does not parse or its imports do not
    /// load: there is no resolved tree to ask.
    ///
    /// # Errors
    ///
    /// A pattern's test failed on a form.
    pub fn query(&self, id: &str, query: &Query) -> Result<Vec<Hit>, QueryError> {
        match self.analysis(id) {
            Some(a) => a.query(query),
            None => Ok(Vec::new()),
        }
    }
}

impl Analysis {
    /// [`Engine::query`] over this analysis.
    ///
    /// # Errors
    ///
    /// A pattern's test failed on a form.
    pub fn query(&self, query: &Query) -> Result<Vec<Hit>, QueryError> {
        let (Some(c), Some(resolved)) = (self.checked(), self.resolved()) else {
            return Ok(Vec::new());
        };
        let tree = resolved.resolved_tree(c.program.forms(), Rule::Namespaced);
        let none_reach = HostReach::new();
        let mut references: HashMap<usize, BTreeSet<String>> = HashMap::new();
        for r in &resolved.references {
            if let Some(s) = r.ns.resolved_symbol() {
                references.entry(r.top_level).or_default().insert(s);
            }
        }
        let none = BTreeSet::new();
        let file = match &self.id {
            Some(doc) => FileRef::Document(doc.clone()),
            None => FileRef::Path(self.path.clone().unwrap_or_default()),
        };
        let mut hits = Vec::new();
        for (i, form) in self.entry_forms() {
            let Some((name, kind, annotated)) = definition(form) else {
                continue;
            };
            let namespace = blue_lang_runtime::pipeline::namespace_of(&c.program, i);
            let d = Def {
                kind,
                annotated,
                namespace: namespace.clone(),
                resolved: &tree[i],
                forms: count_forms(form),
                references: references.get(&i).unwrap_or(&none),
                reach: self.host_reach_at(i).unwrap_or(&none_reach),
            };
            let Some(mut sites) = query.holds(&query.clause, &d)? else {
                continue;
            };
            if sites.is_empty() {
                sites.push(Site {
                    span: form.span,
                    bindings: Vec::new(),
                });
            }
            sites.dedup();
            for s in sites {
                let (line, column) = Span::line_col(&self.text, s.span.start);
                hits.push(Hit {
                    file: file.clone(),
                    span: s.span,
                    line,
                    column,
                    definition: name.clone(),
                    key: key(&namespace, &name),
                    kind,
                    def_span: form.span,
                    bindings: s.bindings,
                    reach: d.reach.clone(),
                });
            }
        }
        Ok(hits)
    }
}

/// Is `items` a `define`/`define-typed` of a function, so `items[1]` its
/// signature?
fn signature_of_definition(items: &[Spanned]) -> bool {
    matches!(
        items.first().and_then(Spanned::as_symbol),
        Some("define" | "define-typed")
    ) && items.get(1).is_some_and(|s| s.as_list().is_some())
}

/// May a pattern's test name `name`?
fn may_name(name: &str) -> bool {
    host_capability(name).is_none() && !EVALUATES.contains(&name)
}

/// A definition form's name, kind and whether it is typed.
fn definition(form: &Spanned) -> Option<(String, ItemKind, bool)> {
    let items = form.as_list()?;
    match items.first()?.as_symbol()? {
        head @ ("define" | "define-typed") => {
            let name = blue_lang_syntax::scope::defined_name_node(items)?.as_symbol()?;
            let function = items.get(1).is_some_and(|t| t.as_list().is_some());
            let kind = if function {
                ItemKind::Function
            } else {
                ItemKind::Value
            };
            Some((name.to_string(), kind, head == "define-typed"))
        }
        "defmacro" => Some((
            items.get(1)?.as_symbol()?.to_string(),
            ItemKind::Macro,
            false,
        )),
        _ => None,
    }
}

fn count_forms(form: &Spanned) -> usize {
    1 + match &form.form {
        SpannedForm::List(items) => items.iter().map(count_forms).sum(),
        SpannedForm::Quote(x)
        | SpannedForm::Quasiquote(x)
        | SpannedForm::Unquote(x)
        | SpannedForm::UnquoteSplice(x) => count_forms(x),
        SpannedForm::Nil | SpannedForm::Atom(_) => 0,
    }
}

/// What a form must look like before its test is worth running: a list
/// whose first element is a given symbol, or any list.
fn shape(pattern: &Sexp) -> (Option<String>, bool) {
    let list_pattern = |items: &[Sexp]| !matches!(items.first(), Some(Sexp::Atom(Atom::Symbol(s))) if s == "?" || s == "quote");
    match pattern {
        Sexp::Quasiquote(inner) => match inner.as_ref() {
            Sexp::List(items) => match items.first() {
                Some(Sexp::Atom(Atom::Symbol(s))) => (Some(s.clone()), true),
                _ => (None, true),
            },
            _ => (None, false),
        },
        Sexp::List(items) if list_pattern(items) => (None, true),
        _ => (None, false),
    }
}

/// A clause argument written as a symbol, keyword or string.
fn word(s: &Sexp) -> Option<String> {
    match s {
        Sexp::Atom(Atom::Symbol(w) | Atom::Keyword(w) | Atom::Str(w)) => Some(w.clone()),
        _ => None,
    }
}

fn sym(s: &str) -> Sexp {
    Sexp::Atom(Atom::Symbol(s.into()))
}

fn as_sexp(v: &Value) -> Result<Sexp, String> {
    tatara_lisp_eval::code::value_to_spanned(v, Span::synthetic()).map(|s| s.to_sexp())
}

#[cfg(test)]
mod tests {
    use std::path::{Path, PathBuf};

    use blue_lang_runtime::uses::Loader;

    use super::*;
    use crate::{Reach, Volatility};

    /// Two bidamas, in memory: `retsu` (a pure `first`) and `shisu`, whose
    /// `read_or` reaches the filesystem.
    struct Mem;

    impl Loader for Mem {
        fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
            let text = match name {
                "retsu" => "def first(xs)\n  car(xs)\nend\n",
                "shisu" => "def read_or(p, d)\n  if file_exists?(p)\n    read_file(p)\n  else\n    d\n  end\nend\n",
                _ => return Err(format!("no bidama {name}")),
            };
            Ok(vec![(format!("/b/{name}/{name}.b"), text.to_string())])
        }

        fn entry_package(&self, path: &Path) -> Option<String> {
            path.starts_with("/b/kaki").then(|| "kaki".to_string())
        }
    }

    const ENTRY: &str = "use(\"retsu\", [:first])\nuse(\"shisu\", [:read_or])\n\n\
def head_of(a, b)\n  first([a, b])\nend\n\n\
def boot()\n  config(\"/etc/k\")\nend\n\n\
def config(path)\n  read_or(path, \"{}\")\nend\n\n\
def stamp() -> Int\n  now_ms()\nend\n\n\
def own(first)\n  first + 1\nend\n\n\
def qualified(xs)\n  retsu::first(xs)\nend\n\n\
defmacro twice(x)\n  quote\n    unquote(x)\n    unquote(x)\n  end\nend\n\n\
limit = 3\n";

    fn hits(text: &str, query: &str) -> Vec<Hit> {
        let mut engine = Engine::new(Box::new(Mem));
        engine.set_document("e", Some(PathBuf::from("/b/kaki/kaki.b")), text);
        let q = Query::parse(query).expect("query reads");
        engine.query("e", &q).expect("query runs")
    }

    fn names(text: &str, query: &str) -> Vec<String> {
        hits(text, query)
            .into_iter()
            .map(|h| h.definition)
            .collect()
    }

    /// `boot` reaches the filesystem two definitions away, through one
    /// defined after it.
    ///
    /// Red run (2026-10-11): `reach_table` cut to one pass: `boot` reached
    /// nothing, because `config`'s reach was not known yet when it was read.
    #[test]
    fn reaches_follows_references_to_the_primitive_and_names_the_chain() {
        let got = hits(ENTRY, "(reaches filesystem)");
        assert_eq!(
            got.iter()
                .map(|h| h.definition.as_str())
                .collect::<Vec<_>>(),
            ["boot", "config"]
        );
        assert_eq!(
            got[0].reach[&Capability::FileSystem],
            ["kaki/config", "shisu/read_or", "read_file"]
        );
        assert_eq!(
            got[1].reach[&Capability::FileSystem],
            ["shisu/read_or", "read_file"]
        );
        assert_eq!(names(ENTRY, "(reaches :clock)"), ["stamp"]);
        assert_eq!(names(ENTRY, "(reaches host)"), ["boot", "config", "stamp"]);
    }

    #[test]
    fn the_analysis_reads_purity_across_bidamas_off_the_same_walk() {
        let mut engine = Engine::new(Box::new(Mem));
        engine.set_document("e", Some(PathBuf::from("/b/kaki/kaki.b")), ENTRY);
        let a = engine.analysis("e").expect("analysed");
        let hashes = a.def_hashes().expect("hashes");
        let reach = a.reach().expect("reach");
        assert_eq!(reach.len(), hashes.defs().len());
        let of = |key: &str| {
            let i = hashes
                .defs()
                .iter()
                .position(|d| d.key == key)
                .unwrap_or_else(|| panic!("{key} is not defined"));
            reach[i].clone()
        };
        assert!(of("kaki/head_of").is_pure(), "{:?}", of("kaki/head_of"));
        assert!(of("kaki/own").is_pure());
        assert!(matches!(
            of("kaki/stamp"),
            Reach::Volatile(Volatility::Host {
                capability: Capability::Clock,
                ..
            })
        ));
        assert!(matches!(
            of("kaki/boot"),
            Reach::Volatile(Volatility::Through { callee }) if callee == "kaki/config"
        ));
        let stamp = hashes
            .defs()
            .iter()
            .find(|d| d.key == "kaki/stamp")
            .expect("stamp");
        assert_eq!(a.reach_at(stamp.top_level), Some(&of("kaki/stamp")));
    }

    /// Red run (2026-10-11): `Annotated` compared with `!=`: the two
    /// answers swapped.
    #[test]
    fn annotated_is_a_typed_definition_and_unannotated_the_rest() {
        assert_eq!(names(ENTRY, "(annotated)"), ["stamp"]);
        assert_eq!(
            names(ENTRY, "(unannotated) (reaches host)"),
            ["boot", "config"],
            "the operator's example: unannotated definitions that reach the host"
        );
    }

    /// Red run (2026-10-11): `calls` read `written` instead of the resolved
    /// symbol: `head_of`, which wrote `first`, was missed.
    #[test]
    fn calls_reads_what_the_reference_resolved_to_not_how_it_was_written() {
        assert_eq!(
            names(ENTRY, "(calls retsu/first)"),
            ["head_of", "qualified"]
        );
        assert_eq!(
            names(ENTRY, "(calls retsu::first)"),
            ["head_of", "qualified"]
        );
        assert!(names(ENTRY, "(calls first)").is_empty());
    }

    #[test]
    fn package_kind_and_size_read_the_definition_itself() {
        assert_eq!(names(ENTRY, "(package kaki) (kind macro)"), ["twice"]);
        assert!(names(ENTRY, "(package retsu)").is_empty());
        assert_eq!(names(ENTRY, "(kind value)"), ["limit"]);
        assert_eq!(
            names(ENTRY, "(kind function) (not (longer-than 8))"),
            ["boot", "stamp", "qualified"]
        );
        assert_eq!(
            names(ENTRY, "(or (kind value) (annotated))"),
            ["stamp", "limit"]
        );
    }

    /// A quasipattern over the resolved tree: both spellings of the call are
    /// `retsu/first`, each hit is the call itself, and `xs` is what it bound.
    ///
    /// Red run (2026-10-11): `sites` over the unresolved form: `head_of`'s
    /// `first([a, b])` did not match.
    #[test]
    fn a_pattern_binds_and_places_each_hit_at_the_matching_form() {
        let got = hits(ENTRY, "(match `(retsu/first ,xs))");
        let seen: Vec<String> = got
            .iter()
            .map(|h| format!("{}:{} {:?}", h.definition, h.line, h.bindings))
            .collect();
        assert_eq!(
            seen,
            [
                r#"head_of:5 [("xs", "(list a b)")]"#,
                r#"qualified:25 [("xs", "xs")]"#,
            ]
        );
        assert_eq!(got[0].column, 3);
        assert!(
            names(ENTRY, "(match `(kaki/own ,_))").is_empty(),
            "own's signature `(own first)` is not a call to it"
        );
        let defs = names(ENTRY, "(match `(define (,name ,@_) ,@_)) (reaches host)");
        assert_eq!(defs, ["boot", "config"], "stamp is a define-typed");
    }

    #[test]
    fn the_json_shape_names_every_field() {
        let got = hits(ENTRY, "(match `(%root/read_or ,p ,_))");
        assert!(got.is_empty(), "read_or is shisu's, not the file's own");
        let got = hits(ENTRY, "(match `(shisu/read_or ,p ,_))");
        assert_eq!(
            got[0].json("kaki.b"),
            serde_json::json!({
                "file": "kaki.b",
                "line": 13,
                "column": 3,
                "definition": "config",
                "key": "kaki/config",
                "kind": "function",
                "bindings": {"p": "path"},
                "reach": {"filesystem": ["shisu/read_or", "read_file"]},
            })
        );
    }

    #[test]
    fn a_malformed_query_is_refused_naming_what_is_wrong() {
        for (text, needle) in [
            ("(reaches disk)", "not a host capability"),
            ("(calls)", "takes one argument"),
            ("(frobnicate)", "is not a clause"),
            ("(longer-than :x)", "count of forms"),
            ("reaches", "a clause is a list"),
            ("(match (? (lambda (x) (read_file x)) y))", "read_file"),
            ("(match (? (lambda (x) (eval x)) y))", "eval"),
            ("(unclosed", "does not read"),
        ] {
            let err = Query::parse(text).expect_err(text).to_string();
            assert!(err.contains(needle), "{text}: {err}");
        }
    }
}
