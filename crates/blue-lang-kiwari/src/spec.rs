//! The spec as Rust reads it.
//!
//! `kiwari` is authored in blue (`bidamas/kiwari`), and the part of it a Rust
//! consumer needs is rendered to `blue.kiwari.json` beside this crate by the
//! same program that renders `grammar.js` and the queries, gated fresh by
//! `generated-kiwari-spec-fresh`. Nothing in this module states a fact about
//! blue's syntax; it only gives the rendered spec a type, refusing at load any
//! lowering operation it does not know rather than ignoring it.

use std::collections::HashMap;

use serde::Deserialize;
use serde_json::Value;

/// The rendered spec, committed beside this crate.
pub const BLUE: &str = include_str!("../blue.kiwari.json");

#[derive(Debug, thiserror::Error)]
pub enum SpecError {
    #[error("the rendered spec is not the expected JSON: {0}")]
    Json(#[from] serde_json::Error),
    #[error("lowering for `{kind}`: {why}")]
    Template { kind: String, why: String },
}

#[derive(Debug, Clone, Deserialize)]
pub struct Infix {
    pub op: String,
    pub aliases: Vec<String>,
    pub power: (u8, u8),
    pub callee: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Pipe {
    pub op: String,
    pub power: (u8, u8),
}

#[derive(Debug, Clone)]
pub struct Unary {
    pub op: String,
    pub aliases: Vec<String>,
    pub power: u8,
    pub head: Template,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Keywords {
    pub surface: Vec<String>,
    pub block: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct RawSpec {
    name: String,
    infix: Vec<Infix>,
    pipe: Pipe,
    unary: Vec<RawUnary>,
    keywords: Keywords,
    lower: serde_json::Map<String, Value>,
}

#[derive(Debug, Clone, Deserialize)]
struct RawUnary {
    op: String,
    aliases: Vec<String>,
    power: u8,
    head: Value,
}

/// kiwari's spec of one language, as far as lowering and its gates need it.
#[derive(Debug, Clone)]
pub struct Spec {
    pub name: String,
    pub infix: Vec<Infix>,
    pub pipe: Pipe,
    pub unary: Vec<Unary>,
    pub keywords: Keywords,
    /// Node kind → how a node of that kind becomes blue's tree.
    pub lower: HashMap<String, Template>,
}

impl Spec {
    pub fn blue() -> Result<Self, SpecError> {
        Self::parse(BLUE)
    }

    pub fn parse(json: &str) -> Result<Self, SpecError> {
        let raw: RawSpec = serde_json::from_str(json)?;
        let mut lower = HashMap::new();
        for (kind, v) in raw.lower {
            let t = Template::from_value(&v).map_err(|why| SpecError::Template {
                kind: kind.clone(),
                why,
            })?;
            lower.insert(kind, t);
        }
        let unary = raw
            .unary
            .into_iter()
            .map(|u| {
                let head = Template::from_value(&u.head).map_err(|why| SpecError::Template {
                    kind: format!("unary `{}`", u.op),
                    why,
                })?;
                Ok(Unary {
                    op: u.op,
                    aliases: u.aliases,
                    power: u.power,
                    head,
                })
            })
            .collect::<Result<Vec<_>, SpecError>>()?;
        Ok(Self {
            name: raw.name,
            infix: raw.infix,
            pipe: raw.pipe,
            unary,
            keywords: raw.keywords,
            lower,
        })
    }

    /// The infix row an operator's spelling names, by its ASCII form or an alias.
    pub fn infix_for(&self, spelling: &str) -> Option<&Infix> {
        self.infix
            .iter()
            .find(|i| i.op == spelling || i.aliases.iter().any(|a| a == spelling))
    }

    pub fn unary_for(&self, spelling: &str) -> Option<&Unary> {
        self.unary
            .iter()
            .find(|u| u.op == spelling || u.aliases.iter().any(|a| a == spelling))
    }
}

/// One step of a lowering, as the spec writes it: `["op", args…]`.
///
/// A template evaluates, against one node, to a SEQUENCE of tatara-lisp
/// values, so a `list` can splice what its parts produce: a call's arguments
/// are a sequence, an absent optional field is the empty one.
#[derive(Debug, Clone, PartialEq)]
pub enum Template {
    Sym(String),
    Int(i64),
    Nil,
    List(Vec<Template>),
    Seq(Vec<Template>),
    Field {
        name: String,
        default: Option<Box<Template>>,
    },
    FieldOpt(String),
    Each {
        path: Vec<String>,
        each: Box<Template>,
    },
    Named,
    Block {
        head: String,
    },
    Quote(Box<Template>),
    Quasiquote(Box<Template>),
    Unquote(Box<Template>),
    UnquoteSplice(Box<Template>),
    Symbol,
    SymbolOf(String),
    Keyword,
    Lexeme,
    Interpolate {
        join: String,
        part: String,
    },
    Qualify {
        package: String,
        name: String,
    },
    Callee(String),
    Unary(String),
    Thread {
        left: String,
        right: String,
    },
    IfAny {
        paths: Vec<Vec<String>>,
        then: Box<Template>,
        otherwise: Box<Template>,
    },
    IfKind {
        kind: String,
        then: Box<Template>,
        otherwise: Box<Template>,
    },
}

fn s(v: &Value, what: &str) -> Result<String, String> {
    v.as_str()
        .map(str::to_owned)
        .ok_or_else(|| format!("{what} must be a string, got {v}"))
}

fn path(v: &Value) -> Result<Vec<String>, String> {
    v.as_array()
        .ok_or_else(|| format!("a path is a list of field names, got {v}"))?
        .iter()
        .map(|p| s(p, "a path step"))
        .collect()
}

impl Template {
    pub fn from_value(v: &Value) -> Result<Self, String> {
        let items = v
            .as_array()
            .ok_or_else(|| format!("a template is a list `[op, …]`, got {v}"))?;
        let (op, args) = items.split_first().ok_or("an empty template")?;
        let op = s(op, "a template's op")?;
        let arg = |i: usize| {
            args.get(i)
                .ok_or_else(|| format!("`{op}` needs an argument at {i}"))
        };
        let sub = |i: usize| -> Result<Box<Template>, String> {
            Ok(Box::new(Template::from_value(arg(i)?)?))
        };
        let arity = |n: usize| {
            if args.len() == n {
                Ok(())
            } else {
                Err(format!("`{op}` takes {n} argument(s), got {}", args.len()))
            }
        };
        Ok(match op.as_str() {
            "sym" => {
                arity(1)?;
                Self::Sym(s(arg(0)?, "a symbol")?)
            }
            "int" => {
                arity(1)?;
                Self::Int(arg(0)?.as_i64().ok_or("`int` takes an integer")?)
            }
            "nil" => {
                arity(0)?;
                Self::Nil
            }
            "list" => Self::List(
                args.iter()
                    .map(Template::from_value)
                    .collect::<Result<_, _>>()?,
            ),
            "seq" => Self::Seq(
                args.iter()
                    .map(Template::from_value)
                    .collect::<Result<_, _>>()?,
            ),
            "field" => match args.len() {
                1 => Self::Field {
                    name: s(arg(0)?, "a field")?,
                    default: None,
                },
                2 => Self::Field {
                    name: s(arg(0)?, "a field")?,
                    default: Some(sub(1)?),
                },
                n => return Err(format!("`field` takes 1 or 2 arguments, got {n}")),
            },
            "field?" => {
                arity(1)?;
                Self::FieldOpt(s(arg(0)?, "a field")?)
            }
            "each" => {
                arity(2)?;
                Self::Each {
                    path: path(arg(0)?)?,
                    each: sub(1)?,
                }
            }
            "named" => {
                arity(0)?;
                Self::Named
            }
            "block" => {
                arity(1)?;
                Self::Block {
                    head: s(arg(0)?, "the head symbol")?,
                }
            }
            "quote" => {
                arity(1)?;
                Self::Quote(sub(0)?)
            }
            "quasiquote" => {
                arity(1)?;
                Self::Quasiquote(sub(0)?)
            }
            "unquote" => {
                arity(1)?;
                Self::Unquote(sub(0)?)
            }
            "unquote_splice" => {
                arity(1)?;
                Self::UnquoteSplice(sub(0)?)
            }
            "symbol" => {
                arity(0)?;
                Self::Symbol
            }
            "symbol_of" => {
                arity(1)?;
                Self::SymbolOf(s(arg(0)?, "a field")?)
            }
            "keyword" => {
                arity(0)?;
                Self::Keyword
            }
            "lexeme" => {
                arity(0)?;
                Self::Lexeme
            }
            "interpolate" => {
                arity(2)?;
                Self::Interpolate {
                    join: s(arg(0)?, "the join symbol")?,
                    part: s(arg(1)?, "the interpolation kind")?,
                }
            }
            "qualify" => {
                arity(2)?;
                Self::Qualify {
                    package: s(arg(0)?, "a field")?,
                    name: s(arg(1)?, "a field")?,
                }
            }
            "callee" => {
                arity(1)?;
                Self::Callee(s(arg(0)?, "a field")?)
            }
            "unary" => {
                arity(1)?;
                Self::Unary(s(arg(0)?, "a field")?)
            }
            "thread" => {
                arity(2)?;
                Self::Thread {
                    left: s(arg(0)?, "a field")?,
                    right: s(arg(1)?, "a field")?,
                }
            }
            "if_any" => {
                arity(3)?;
                let paths = arg(0)?
                    .as_array()
                    .ok_or("`if_any` takes a list of paths first")?
                    .iter()
                    .map(path)
                    .collect::<Result<_, _>>()?;
                Self::IfAny {
                    paths,
                    then: sub(1)?,
                    otherwise: sub(2)?,
                }
            }
            "if_kind" => {
                arity(3)?;
                Self::IfKind {
                    kind: s(arg(0)?, "a node kind")?,
                    then: sub(1)?,
                    otherwise: sub(2)?,
                }
            }
            other => return Err(format!("unknown lowering op `{other}`")),
        })
    }
}
