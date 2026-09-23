//! Blue as the authoring surface for Rust types: a blue value becomes a
//! `#[derive(TataraDomain)]` struct.
//!
//! A `TataraDomain` compiles from exactly one shape, `(KEYWORD :kebab-key v …)`
//! (`tatara_lisp::domain`, `compile_from_sexp`). Blue's map literal lowers to a
//! different one: `{max_replicas: 3}` is `(hash-map :max_replicas 3)`, whose
//! head is `hash-map` and whose keys keep blue's underscores, because a blue
//! identifier cannot contain `-`. Two mismatches, and nothing converted between
//! them, so no blue value could ever reach a Rust domain type.
//!
//! This module is that conversion, and it lives at blue's border rather than in
//! tatara-lisp: teaching `TataraDomain` a second spelling of every key would give
//! every Lisp author two ways to write one field. Here the one blue spelling is
//! translated once into the one Lisp spelling:
//!
//! - the head becomes the domain's `KEYWORD`;
//! - every key `max_replicas` becomes `:max-replicas`;
//! - a nested map becomes a keyword list `(:k v …)`, the shape the derive reads
//!   for struct-valued fields;
//! - keys are emitted in sorted order, so one value always yields one form.
//!
//! [`compile`] is the whole round trip for a Rust caller: blue source in, a typed
//! Rust value out, with every failure a typed [`DomainError`].

use tatara_lisp::{Atom, Sexp, TataraDomain};
use tatara_lisp_eval::{MapKey, Value};

use crate::pipeline::{run, RunError};

/// Why a blue value could not become a domain type.
#[derive(Debug, thiserror::Error)]
pub enum DomainError {
    /// The blue program itself failed to parse, type-check or run.
    #[error("the blue source did not run: {0}")]
    Run(#[from] RunError),
    /// A domain is built from a map; the program produced something else.
    #[error("a domain is authored as a map (`{{key: value}}`), but the value was {found}")]
    NotAMap { found: &'static str },
    /// A map key blue can write that a domain cannot name (a number, a string).
    #[error("domain keys are labels (`name:`), but a key was {found}")]
    KeyNotALabel { found: &'static str },
    /// A value with no Lisp spelling: a function, a promise, an error object.
    #[error("the field `{field}` holds {found}, which has no form a domain can read")]
    Unrepresentable { field: String, found: &'static str },
    /// The form was well-shaped and the domain still refused it: an unknown
    /// field, a missing required one, a wrong type. The message is the
    /// domain's own, which names the field.
    #[error("the domain `{keyword}` refused the form: {message}")]
    Refused { keyword: &'static str, message: String },
}

/// Compile blue source into a Rust domain type.
///
/// The program's final value must be a map: the domain's fields as labels.
///
/// ```ignore
/// #[derive(tatara_lisp::DeriveTataraDomain)]
/// #[tatara(keyword = "defreplica")]
/// struct Replica { name: String, max_replicas: i64 }
///
/// let r: Replica = blue_lang_runtime::domain::compile(r#"{name: "api", max_replicas: 3}"#)?;
/// ```
///
/// # Errors
///
/// Every failure is a [`DomainError`] variant: the program did not run, it did
/// not produce a map, a key or value has no domain spelling, or the domain
/// refused the form.
pub fn compile<T: TataraDomain>(src: &str) -> Result<T, DomainError> {
    let value = run(src)?.value;
    compile_value(&value)
}

/// Compile an already-evaluated blue value into a Rust domain type.
///
/// # Errors
///
/// As [`compile`], minus the run.
pub fn compile_value<T: TataraDomain>(value: &Value) -> Result<T, DomainError> {
    let form = domain_form(T::KEYWORD, value)?;
    T::compile_from_sexp(&form).map_err(|e| DomainError::Refused {
        keyword: T::KEYWORD,
        message: e.to_string(),
    })
}

/// The canonical `(KEYWORD :kebab-key v …)` form for a blue map.
///
/// Public so a caller can also WRITE the form: printed, it is the `.tlisp` text
/// a hand author would have written.
///
/// # Errors
///
/// [`DomainError::NotAMap`], [`DomainError::KeyNotALabel`] or
/// [`DomainError::Unrepresentable`].
pub fn domain_form(keyword: &str, value: &Value) -> Result<Sexp, DomainError> {
    let Value::Map(map) = value else {
        return Err(DomainError::NotAMap { found: kind_of(value) });
    };
    let mut form = vec![Sexp::Atom(Atom::Symbol(keyword.to_string()))];
    form.extend(keyword_args(map)?);
    Ok(Sexp::List(form))
}

/// `:kebab-key v` pairs for a map, keys sorted so one map yields one form.
fn keyword_args(
    map: &std::collections::HashMap<MapKey, Value>,
) -> Result<Vec<Sexp>, DomainError> {
    let mut pairs: Vec<(String, &Value)> = map
        .iter()
        .map(|(k, v)| label_of(k).map(|label| (label, v)))
        .collect::<Result<_, _>>()?;
    pairs.sort_by(|a, b| a.0.cmp(&b.0));

    let mut args = Vec::with_capacity(pairs.len() * 2);
    for (label, v) in pairs {
        let field = kebab(&label);
        let arg = to_sexp(&field, v)?;
        args.push(Sexp::Atom(Atom::Keyword(field)));
        args.push(arg);
    }
    Ok(args)
}

/// A map key as a label. Blue writes `name:` as a keyword; a symbol is accepted
/// for maps built by code rather than by literal.
fn label_of(key: &MapKey) -> Result<String, DomainError> {
    match key {
        MapKey::Keyword(k) | MapKey::Symbol(k) => Ok(k.to_string()),
        MapKey::Str(_) => Err(DomainError::KeyNotALabel { found: "a string" }),
        MapKey::Int(_) => Err(DomainError::KeyNotALabel { found: "an integer" }),
        MapKey::Float(_) => Err(DomainError::KeyNotALabel { found: "a float" }),
        MapKey::Bool(_) => Err(DomainError::KeyNotALabel { found: "a boolean" }),
        MapKey::Nil => Err(DomainError::KeyNotALabel { found: "nil" }),
    }
}

/// Blue's one spelling of a field to Lisp's one spelling: `max_replicas` →
/// `max-replicas`. The same rule the derive applies to Rust field names
/// (`snake_to_kebab`), so the two meet exactly.
fn kebab(label: &str) -> String {
    label.replace('_', "-")
}

/// A field value as a form the derive reads.
fn to_sexp(field: &str, value: &Value) -> Result<Sexp, DomainError> {
    Ok(match value {
        Value::Nil => Sexp::Nil,
        Value::Bool(b) => Sexp::Atom(Atom::Bool(*b)),
        Value::Int(i) => Sexp::Atom(Atom::Int(*i)),
        Value::Float(f) => Sexp::Atom(Atom::Float(*f)),
        Value::Str(s) => Sexp::Atom(Atom::Str(s.to_string())),
        Value::Symbol(s) => Sexp::Atom(Atom::Symbol(s.to_string())),
        Value::Keyword(k) => Sexp::Atom(Atom::Keyword(kebab(k))),
        Value::List(items) => Sexp::List(
            items
                .iter()
                .map(|v| to_sexp(field, v))
                .collect::<Result<_, _>>()?,
        ),
        Value::Map(map) => Sexp::List(keyword_args(map)?),
        Value::Sexp(s, _) => s.clone(),
        other => {
            return Err(DomainError::Unrepresentable {
                field: field.to_string(),
                found: kind_of(other),
            })
        }
    })
}

fn kind_of(value: &Value) -> &'static str {
    match value {
        Value::Nil => "nil",
        Value::Bool(_) => "a boolean",
        Value::Int(_) => "an integer",
        Value::Float(_) => "a float",
        Value::Str(_) => "a string",
        Value::Symbol(_) => "a symbol",
        Value::Keyword(_) => "a keyword",
        Value::List(_) => "a list",
        Value::Map(_) => "a map",
        Value::Closure(_) | Value::NativeFn(_) => "a function",
        Value::Promise(_) => "a promise",
        Value::Error(_) => "an error object",
        Value::Sexp(..) => "a quoted form",
        _ => "a host value",
    }
}
