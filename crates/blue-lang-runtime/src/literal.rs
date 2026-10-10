//! Runtime values as canonical blue source.
//!
//! One rendering for every door that shows a value to a person: a failed
//! assertion in `blue test`, a REPL result, a `blue serve` response. Each lifts
//! the value to the tree it is the literal of and prints that tree through
//! `blue_lang_fmt`, so a value and the source that would produce it are spelled
//! the same way.

use tatara_lisp::{Atom, Sexp};
use tatara_lisp_eval::Value;

/// A quoted form as canonical blue source.
///
/// ## Why this lifts back to `Sexp` first
///
/// A quoted form does not survive evaluation as a `Sexp`: `'(= (add 1 2) 4)`
/// evaluates to a `Value::List` of `Value::Symbol`/`Value::Int`. Rendering that
/// `Value` directly produced the tatara-lisp spelling `(= (add 1 2) 4)` — true
/// to the tree and useless to a blue author, who wrote `add(1, 2) == 4`.
///
/// Lifting to `Sexp` and rendering through `blue_lang_fmt` means the failure
/// message and the source file cannot disagree about how the expression is
/// spelled: both are the output of the one canonical formatting. That is the
/// whole reason blue has exactly one.
#[must_use]
pub fn render_form(v: &Value) -> String {
    let sexp = match v {
        Value::Sexp(s, _) => s.clone(),
        other => match value_to_sexp(other) {
            Some(s) => s,
            // Nothing sensible to lift (a closure, a foreign handle). Say so
            // rather than printing a Rust debug string at the author.
            None => return "<unrenderable expression>".to_string(),
        },
    };
    format(&sexp)
}

/// A runtime value as canonical blue source: `[1, 2]`, `"a"`, `{a: 1}`.
#[must_use]
pub fn render_value(v: &Value) -> String {
    literal(v).unwrap_or_else(|| "<a value with no literal form>".to_string())
}

/// [`render_value`], or `None` for a value no blue literal produces (a
/// function, a channel), so a caller can describe it in its own words.
#[must_use]
pub fn literal(v: &Value) -> Option<String> {
    Some(match value_literal(v)? {
        // A symbol value is data; rendered bare it reads as a name, which is
        // what the value is.
        Sexp::Atom(Atom::Symbol(s)) => s,
        sexp => format(&sexp),
    })
}

/// One tree through the one formatting.
#[must_use]
pub fn format(sexp: &Sexp) -> String {
    // format_forms, not a new single-Sexp entry point: one rendering.
    blue_lang_fmt::format_forms(std::slice::from_ref(sexp))
        .trim_end()
        .to_string()
}

/// The literal that evaluates to `v`: a list is `(list …)`, which the
/// formatter renders `[…]`, and a map is `(hash-map k v …)`, rendered
/// `{k: v}`, keys sorted so the text does not depend on hash order. Unlike
/// [`value_to_sexp`], which lifts a QUOTED form back to the code it was.
#[must_use]
pub fn value_literal(v: &Value) -> Option<Sexp> {
    Some(match v {
        Value::List(items) => {
            let mut out = vec![Sexp::Atom(Atom::Symbol("list".to_string()))];
            for i in items.iter() {
                out.push(value_literal(i)?);
            }
            Sexp::List(out)
        }
        Value::Map(m) => {
            let mut pairs: Vec<(Sexp, Sexp)> = m
                .iter()
                .map(|(k, v)| Some((key_to_sexp(k), value_literal(v)?)))
                .collect::<Option<Vec<_>>>()?;
            pairs.sort_by_key(|(k, _)| k.to_string());
            let mut items = vec![Sexp::Atom(Atom::Symbol(
                blue_lang_syntax::LOWERED_MAP.to_string(),
            ))];
            for (k, v) in pairs {
                items.push(k);
                items.push(v);
            }
            Sexp::List(items)
        }
        other => value_to_sexp(other)?,
    })
}

/// Lift an evaluated quoted form back into the syntax tree it came from.
///
/// Total over the shapes a quoted form can produce; `None` for values that were
/// never syntax (closures, foreign handles).
#[must_use]
pub fn value_to_sexp(v: &Value) -> Option<Sexp> {
    Some(match v {
        Value::Nil => Sexp::Nil,
        Value::Bool(b) => Sexp::Atom(Atom::Bool(*b)),
        Value::Int(n) => Sexp::Atom(Atom::Int(*n)),
        Value::Float(x) => Sexp::Atom(Atom::Float(*x)),
        Value::Str(s) => Sexp::Atom(Atom::Str(s.to_string())),
        Value::Symbol(s) => Sexp::Atom(Atom::Symbol(s.to_string())),
        Value::Keyword(k) => Sexp::Atom(Atom::Keyword(k.to_string())),
        Value::Sexp(s, _) => s.clone(),
        Value::List(items) => Sexp::List(
            items
                .iter()
                .map(value_to_sexp)
                .collect::<Option<Vec<_>>>()?,
        ),
        _ => return None,
    })
}

fn key_to_sexp(k: &tatara_lisp_eval::value::MapKey) -> Sexp {
    use tatara_lisp_eval::value::MapKey;
    match k {
        MapKey::Nil => Sexp::Nil,
        MapKey::Bool(b) => Sexp::Atom(Atom::Bool(*b)),
        MapKey::Int(n) => Sexp::Atom(Atom::Int(*n)),
        MapKey::Float(bits) => Sexp::Atom(Atom::Float(f64::from_bits(*bits))),
        MapKey::Str(s) => Sexp::Atom(Atom::Str(s.to_string())),
        MapKey::Symbol(s) => Sexp::Atom(Atom::Symbol(s.to_string())),
        MapKey::Keyword(s) => Sexp::Atom(Atom::Keyword(s.to_string())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn values_render_as_the_literal_that_produces_them() {
        let list = Value::List(Arc::new(vec![
            Value::Int(1),
            Value::Str(Arc::from("a")),
            Value::Keyword(Arc::from("k")),
        ]
        .into()));
        assert_eq!(render_value(&list), r#"[1, "a", :k]"#);
        assert_eq!(render_value(&Value::Nil), "nil");
        assert_eq!(render_value(&Value::List(Arc::new(Vec::new().into()))), "[]");
    }
}
