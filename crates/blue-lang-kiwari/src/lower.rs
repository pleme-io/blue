//! A concrete syntax tree, lowered to blue's tree by the spec.
//!
//! Every node kind the grammar names has a template in the spec saying what
//! tatara-lisp value it means; this module only evaluates templates. So the
//! lowering of `case` to `(let ((case-subject …)) (cond …))`, of `unless` to
//! `(if (not c) …)`, of a typed `def` to `define-typed`, lives in the spec
//! beside the rule that parses it, and the parser emitted from the spec at M3
//! inherits it from there rather than from a second copy.
//!
//! The one thing taken from outside the spec is a lexeme's VALUE: an integer,
//! float or string token's text is decoded by `blue_lang_syntax::lex`, the
//! lexer blue's parser uses, so a number with underscores or a `\u{…}` escape
//! has exactly one decoder. Where the grammar put the token's edges is still
//! the grammar's claim, and the differential checks it.

use blue_lang_syntax::{lex, TokenKind};
use tatara_lisp::{Atom, Sexp};

use crate::spec::{Spec, Template};

/// A node of any concrete syntax tree the spec can lower.
pub trait Cst: Copy {
    fn kind(&self) -> &str;
    fn start(&self) -> usize;
    fn end(&self) -> usize;
    fn is_named(&self) -> bool;
    fn is_extra(&self) -> bool;
    /// Every child in order, with the field it fills.
    fn fields(&self) -> Vec<(Option<&str>, Self)>;
}

impl<'t> Cst for crate::ts::Node<'t> {
    fn kind(&self) -> &str {
        crate::ts::Node::kind(self)
    }
    fn start(&self) -> usize {
        crate::ts::Node::start(self)
    }
    fn end(&self) -> usize {
        crate::ts::Node::end(self)
    }
    fn is_named(&self) -> bool {
        crate::ts::Node::is_named(self)
    }
    fn is_extra(&self) -> bool {
        crate::ts::Node::is_extra(self)
    }
    fn fields(&self) -> Vec<(Option<&str>, Self)> {
        self.children().into_iter().map(|c| (c.field, c.node)).collect()
    }
}

/// Why a node could not be lowered: the spec and the tree disagree about it.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
#[error("{kind} at {start}..{end}: {why}")]
pub struct LowerError {
    pub kind: String,
    pub start: usize,
    pub end: usize,
    pub why: String,
}

pub struct Lowerer<'a> {
    spec: &'a Spec,
    src: &'a str,
}

impl<'a> Lowerer<'a> {
    pub fn new(spec: &'a Spec, src: &'a str) -> Self {
        Self { spec, src }
    }

    /// What `node` means, as the sequence its kind's template produces.
    pub fn lower<N: Cst>(&self, node: N) -> Result<Vec<Sexp>, LowerError> {
        let template = self
            .spec
            .lower
            .get(node.kind())
            .ok_or_else(|| self.err(node, format!("the spec has no lowering for `{}`", node.kind())))?;
        self.eval(template, node)
    }

    /// [`Self::lower`] where the node must mean exactly one value.
    pub fn lower_one<N: Cst>(&self, node: N) -> Result<Sexp, LowerError> {
        one(self.lower(node)?).map_err(|n| self.err(node, format!("lowers to {n} values, not one")))
    }

    fn err<N: Cst>(&self, node: N, why: String) -> LowerError {
        LowerError { kind: node.kind().to_string(), start: node.start(), end: node.end(), why }
    }

    fn text<N: Cst>(&self, node: N) -> &'a str {
        &self.src[node.start()..node.end()]
    }

    fn named<N: Cst>(node: N) -> Vec<N> {
        node.fields().into_iter().map(|(_, n)| n).filter(|n| n.is_named() && !n.is_extra()).collect()
    }

    fn field<N: Cst>(node: N, name: &str) -> Option<N> {
        node.fields().into_iter().find(|(f, _)| *f == Some(name)).map(|(_, n)| n)
    }

    /// The nodes a path reaches: a field name selects the children filling
    /// that field, `*` every named child.
    fn walk<N: Cst>(node: N, path: &[String]) -> Vec<N> {
        let mut at = vec![node];
        for step in path {
            at = at
                .into_iter()
                .flat_map(|n| {
                    if step == "*" {
                        Self::named(n)
                    } else {
                        n.fields().into_iter().filter(|(f, _)| *f == Some(step.as_str())).map(|(_, c)| c).collect()
                    }
                })
                .collect();
        }
        at
    }

    fn eval_one<N: Cst>(&self, t: &Template, node: N) -> Result<Sexp, LowerError> {
        one(self.eval(t, node)?).map_err(|n| self.err(node, format!("{t:?} produced {n} values where one belongs")))
    }

    fn eval<N: Cst>(&self, t: &Template, node: N) -> Result<Vec<Sexp>, LowerError> {
        Ok(match t {
            Template::Sym(s) => vec![sym(s)],
            Template::Int(i) => vec![Sexp::Atom(Atom::Int(*i))],
            Template::Nil => vec![Sexp::Nil],
            Template::List(parts) => {
                let mut items = Vec::new();
                for p in parts {
                    items.extend(self.eval(p, node)?);
                }
                vec![Sexp::List(items)]
            }
            Template::Seq(parts) => {
                let mut items = Vec::new();
                for p in parts {
                    items.extend(self.eval(p, node)?);
                }
                items
            }
            Template::Field { name, default } => match (Self::field(node, name), default) {
                (Some(child), _) => self.lower(child)?,
                (None, Some(d)) => self.eval(d, node)?,
                (None, None) => return Err(self.err(node, format!("no `{name}` field"))),
            },
            Template::FieldOpt(name) => match Self::field(node, name) {
                Some(child) => self.lower(child)?,
                None => Vec::new(),
            },
            Template::Each { path, each } => {
                let mut out = Vec::new();
                for n in Self::walk(node, path) {
                    out.extend(self.eval(each, n)?);
                }
                out
            }
            Template::Named => {
                let mut out = Vec::new();
                for n in Self::named(node) {
                    out.extend(self.lower(n)?);
                }
                out
            }
            Template::Block { head } => {
                let mut items = Vec::new();
                for n in Self::named(node) {
                    items.extend(self.lower(n)?);
                }
                match items.len() {
                    0 => vec![Sexp::Nil],
                    1 => items,
                    _ => {
                        items.insert(0, sym(head));
                        vec![Sexp::List(items)]
                    }
                }
            }
            Template::Quote(inner) => vec![Sexp::Quote(Box::new(self.eval_one(inner, node)?))],
            Template::Quasiquote(inner) => vec![Sexp::Quasiquote(Box::new(self.eval_one(inner, node)?))],
            Template::Unquote(inner) => vec![Sexp::Unquote(Box::new(self.eval_one(inner, node)?))],
            Template::UnquoteSplice(inner) => vec![Sexp::UnquoteSplice(Box::new(self.eval_one(inner, node)?))],
            Template::Symbol => vec![sym(self.text(node).trim_end_matches(':'))],
            Template::Keyword => {
                let t = self.text(node);
                let name = t.strip_prefix(':').or_else(|| t.strip_suffix(':')).unwrap_or(t);
                vec![Sexp::Atom(Atom::Keyword(name.to_string()))]
            }
            Template::Lexeme => match self.token(node)? {
                TokenKind::Int(v) => vec![Sexp::Atom(Atom::Int(v))],
                TokenKind::Float(v) => vec![Sexp::Atom(Atom::Float(v))],
                TokenKind::Str(s) => vec![Sexp::Atom(Atom::Str(s))],
                TokenKind::True => vec![Sexp::Atom(Atom::Bool(true))],
                TokenKind::False => vec![Sexp::Atom(Atom::Bool(false))],
                TokenKind::Nil => vec![Sexp::Nil],
                other => return Err(self.err(node, format!("the lexeme is {other}, not a literal"))),
            },
            Template::Interpolate { join, part } => match self.token(node)? {
                TokenKind::Str(s) => vec![Sexp::Atom(Atom::Str(s))],
                TokenKind::InterpolatedStr { parts, exprs } => {
                    let inner: Vec<N> = Self::named(node).into_iter().filter(|n| n.kind() == part).collect();
                    if inner.len() != exprs.len() {
                        return Err(self.err(
                            node,
                            format!("the grammar found {} interpolations, the lexeme has {}", inner.len(), exprs.len()),
                        ));
                    }
                    let mut acc = Sexp::Atom(Atom::Str(parts[0].clone()));
                    for (i, n) in inner.into_iter().enumerate() {
                        acc = Sexp::List(vec![sym(join), acc, self.lower_one(n)?]);
                        acc = Sexp::List(vec![sym(join), acc, Sexp::Atom(Atom::Str(parts[i + 1].clone()))]);
                    }
                    vec![acc]
                }
                other => return Err(self.err(node, format!("the lexeme is {other}, not a string"))),
            },
            Template::Qualify { package, name } => {
                let p = Self::field(node, package).ok_or_else(|| self.err(node, format!("no `{package}` field")))?;
                let n = Self::field(node, name).ok_or_else(|| self.err(node, format!("no `{name}` field")))?;
                let pkg = self.text(p).trim_end_matches(':');
                vec![sym(&blue_lang_syntax::parse::qualify(pkg, self.text(n)))]
            }
            Template::Callee(field) => {
                let op = Self::field(node, field).ok_or_else(|| self.err(node, format!("no `{field}` field")))?;
                let row = self
                    .spec
                    .infix_for(self.text(op))
                    .ok_or_else(|| self.err(node, format!("`{}` is in no infix row", self.text(op))))?;
                vec![sym(&row.callee)]
            }
            Template::Unary(field) => {
                let op = Self::field(node, field).ok_or_else(|| self.err(node, format!("no `{field}` field")))?;
                let row = self
                    .spec
                    .unary_for(self.text(op))
                    .ok_or_else(|| self.err(node, format!("`{}` is in no unary row", self.text(op))))?;
                self.eval(&row.head, node)?
            }
            Template::Thread { left, right } => {
                let l = Self::field(node, left).ok_or_else(|| self.err(node, format!("no `{left}` field")))?;
                let r = Self::field(node, right).ok_or_else(|| self.err(node, format!("no `{right}` field")))?;
                let l = self.lower_one(l)?;
                vec![match self.lower_one(r)? {
                    Sexp::List(mut items) if !items.is_empty() => {
                        items.insert(1, l);
                        Sexp::List(items)
                    }
                    callee => Sexp::List(vec![callee, l]),
                }]
            }
            Template::IfAny { paths, then, otherwise } => {
                if paths.iter().any(|p| !Self::walk(node, p).is_empty()) {
                    self.eval(then, node)?
                } else {
                    self.eval(otherwise, node)?
                }
            }
            Template::IfKind { kind, then, otherwise } => {
                if node.kind() == kind {
                    self.eval(then, node)?
                } else {
                    self.eval(otherwise, node)?
                }
            }
        })
    }

    /// The one token blue's lexer reads from the node's text.
    fn token<N: Cst>(&self, node: N) -> Result<TokenKind, LowerError> {
        let toks = lex(self.text(node)).map_err(|e| self.err(node, format!("blue's lexer refuses the lexeme: {e}")))?;
        match toks.as_slice() {
            [t, eof] if eof.kind == TokenKind::Eof => Ok(t.kind.clone()),
            _ => Err(self.err(node, format!("the lexeme is {} tokens to blue's lexer, not one", toks.len() - 1))),
        }
    }
}

fn sym(s: &str) -> Sexp {
    Sexp::Atom(Atom::Symbol(s.to_string()))
}

fn one(mut v: Vec<Sexp>) -> Result<Sexp, usize> {
    if v.len() == 1 {
        Ok(v.pop().expect("checked len"))
    } else {
        Err(v.len())
    }
}
