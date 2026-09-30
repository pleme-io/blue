//! `blue reference`: the language as its implementation states it, as JSON.
//!
//! Every section is read from the table the implementation itself runs on,
//! never restated: operators from `blue_lang_syntax::INFIX`, reserved words
//! from `SURFACE_KEYWORDS` and `BLOCK_KEYWORDS`, the surface forms from
//! `blue_lang_syntax::FORMS` (each row parsed by a gate), the Bluefile words
//! from `blue_lang_pkg::bluefile::words`, and the bound names from a live
//! interpreter, described by `blue_lang_runtime::docs`. `gen/reference.b`
//! renders this into `docs/REFERENCE.md`, and `generated-reference-fresh`
//! fails when the committed file is stale, so the reference cannot drift from
//! the compiler that produced it.
//!
//! No version is printed: a release bumps it, and a version in the rendered
//! file would make every release stale the reference it did not change.

use std::collections::BTreeSet;

use blue_lang_syntax::{
    keyword_doc, lex, TokenKind, BLOCK_KEYWORDS, FORMS, INFIX, SURFACE_KEYWORDS,
};
use serde::Serialize;
use tatara_lisp_eval::{Arity, HeadBinding, Interpreter, Value};

#[derive(Serialize)]
pub struct Reference {
    operators: Vec<Operator>,
    keywords: Vec<Keyword>,
    forms: Vec<Form>,
    bluefile: Vec<blue_lang_pkg::bluefile::WordDoc>,
    topics: Vec<Topic>,
    names: Vec<Name>,
    /// How many bound names cannot head a blue call: kebab-case ones, and the
    /// reserved words, which the keyword table describes instead.
    uncallable: usize,
}

#[derive(Serialize)]
struct Operator {
    op: &'static str,
    left: u8,
    right: u8,
    callee: &'static str,
    doc: &'static str,
}

#[derive(Serialize)]
struct Keyword {
    word: &'static str,
    /// `form` begins an expression; `block` delimits one or is a literal.
    kind: &'static str,
    doc: &'static str,
}

#[derive(Serialize)]
struct Form {
    example: &'static str,
    lowers_to: &'static str,
    doc: &'static str,
}

#[derive(Serialize)]
struct Topic {
    slug: String,
    title: &'static str,
}

#[derive(Serialize)]
pub struct Name {
    pub name: String,
    pub topic: String,
    /// `special form`, `macro`, `function` or `value`: which of the
    /// interpreter's three arbiters claims the name, and for a binding
    /// whether it can be called.
    pub arbiter: &'static str,
    /// The arity the bound function declares (`2`, `1..3`, `1+`, `any`), or
    /// null when the name is not a function.
    pub arity: Option<String>,
    pub signature: &'static str,
    pub doc: &'static str,
}

/// The arity a bound value declares, in the reference's spelling.
#[must_use]
pub fn arity_of(value: &Value) -> Option<String> {
    match value {
        Value::NativeFn(f) => Some(match f.arity {
            Arity::Exact(n) => n.to_string(),
            Arity::AtLeast(n) => format!("{n}+"),
            Arity::Range(a, b) => format!("{a}..{b}"),
            Arity::Any => "any".into(),
        }),
        Value::Closure(c) => Some(if c.rest.is_some() {
            format!("{}+", c.params.len())
        } else {
            c.params.len().to_string()
        }),
        _ => None,
    }
}

/// Every name `interp` binds that blue can spell, described. A name with no
/// row in `blue_lang_runtime::docs` is listed with an empty doc, so the gate
/// in `tests/reference.rs` can name it rather than the reference hiding it.
pub fn names_of<H: 'static>(interp: &Interpreter<H>) -> (Vec<Name>, usize) {
    let mut names = Vec::new();
    let mut uncallable = 0;
    let all: BTreeSet<String> = interp
        .reserved_head_names()
        .iter()
        .map(ToString::to_string)
        .collect();
    for name in all {
        if !blue_lang_syntax::is_callable_name(&name) {
            uncallable += 1;
            continue;
        }
        let value = interp.lookup_global(&name);
        let arbiter = match interp.resolve_head(&name) {
            Some(HeadBinding::SpecialForm) => "special form",
            Some(HeadBinding::Macro) => "macro",
            _ => match value {
                Some(Value::NativeFn(_) | Value::Closure(_)) => "function",
                _ => "value",
            },
        };
        let doc = blue_lang_runtime::docs::doc_of(&name);
        names.push(Name {
            arity: value.as_ref().and_then(arity_of),
            topic: doc.map(|d| slug(d.topic)).unwrap_or_default(),
            signature: doc.map_or("", |d| d.signature),
            doc: doc.map_or("", |d| d.doc),
            arbiter,
            name,
        });
    }
    (names, uncallable)
}

fn slug(t: blue_lang_runtime::docs::Topic) -> String {
    format!("{t:?}").to_lowercase()
}

/// The whole reference, from the interpreter every `blue run` builds.
pub fn reference() -> Reference {
    let interp = blue_lang_runtime::interpreter(&mut ());
    let (names, uncallable) = names_of(&interp);
    Reference {
        operators: INFIX
            .iter()
            .map(|i| Operator {
                op: i.op,
                left: i.power.0,
                right: i.power.1,
                callee: i.callee,
                doc: i.doc,
            })
            .collect(),
        keywords: SURFACE_KEYWORDS
            .iter()
            .map(|w| (w, "form"))
            .chain(BLOCK_KEYWORDS.iter().map(|w| (w, "block")))
            .map(|(w, kind)| Keyword {
                word: w,
                kind,
                doc: keyword_doc(w),
            })
            .collect(),
        forms: FORMS
            .iter()
            .map(|f| Form {
                example: f.example,
                lowers_to: f.lowers_to,
                doc: f.doc,
            })
            .collect(),
        bluefile: blue_lang_pkg::bluefile::words().collect(),
        topics: blue_lang_runtime::docs::Topic::ALL
            .iter()
            .map(|t| Topic {
                slug: slug(*t),
                title: t.title(),
            })
            .collect(),
        names,
        uncallable,
    }
}

/// The parameter counts a signature states: (required, optional, variadic).
///
/// `f(a, b)` is (2, 0, false); `f(a[, b])` is (1, 1, false); `f(a, more...)`
/// is (1, 0, true). Only the text between the first `(` and the last `)` is
/// read, and a bracketed group counts its names as optional.
fn declared_params(signature: &str) -> Option<(usize, usize, bool)> {
    let open = signature.find('(')?;
    let close = signature.rfind(')')?;
    let inner = &signature[open + 1..close];
    let (mut outside, mut optional) = (String::new(), 0);
    let mut rest = inner;
    while let Some(start) = rest.find('[') {
        outside.push_str(&rest[..start]);
        let end = rest[start..].find(']')? + start;
        optional += rest[start + 1..end]
            .split(',')
            .filter(|p| !p.trim().is_empty())
            .count();
        rest = &rest[end + 1..];
    }
    outside.push_str(rest);
    let params: Vec<&str> = outside
        .split(',')
        .map(str::trim)
        .filter(|p| !p.is_empty())
        .collect();
    let variadic = params.iter().any(|p| p.ends_with("..."));
    let required = params.iter().filter(|p| !p.ends_with("...")).count();
    Some((required, optional, variadic))
}

/// Whether a signature's counts are the arity the runtime declares.
fn agrees(arity: &str, (required, optional, variadic): (usize, usize, bool)) -> bool {
    let (min, max) = match arity.split_once("..") {
        Some((a, b)) => (a.parse().ok(), b.parse().ok()),
        None if arity == "any" => (Some(0), None),
        None => match arity.strip_suffix('+') {
            Some(n) => (n.parse().ok(), None),
            None => (arity.parse().ok(), arity.parse().ok()),
        },
    };
    let declared_max = if variadic {
        None
    } else {
        Some(required + optional)
    };
    min == Some(required) && max == declared_max
}

#[cfg(test)]
mod tests {
    //! The gate between `blue_lang_runtime::docs` and the runtime it
    //! describes. Evidence is a live interpreter, the same one `blue run`
    //! builds (with the `sys` layer, which this crate turns on), never the
    //! table read against itself.
    //!
    //! Red runs, 2026-09-29, each reverted:
    //! - deleting the `nth` row failed `every_bound_name_is_described` with
    //!   ``bound with no row in blue_lang_runtime::docs: ["nth"]``;
    //! - adding a row for `lenght` failed `every_row_names_a_bound_name` with
    //!   ``rows naming nothing the runtime binds: ["lenght"]``;
    //! - writing `nth(i)` failed `every_signature_matches_its_arity` with
    //!   ``nth: `nth(i)` against arity 2``;
    //! - probing a bare `Interpreter::new()` instead of blue's failed the
    //!   positive control with ``only 21 names``.
    use super::*;

    fn bound() -> Vec<Name> {
        names_of(&blue_lang_runtime::interpreter(&mut ())).0
    }

    /// POSITIVE CONTROL: the probe sees the whole surface, sys layer included,
    /// so "every name is described" is not passing over a partial set.
    #[test]
    fn the_probe_sees_the_full_runtime() {
        let names = bound();
        assert!(names.len() >= 220, "only {} names", names.len());
        assert!(names.iter().any(|n| n.name == "read_file"), "no sys layer");
    }

    #[test]
    fn every_bound_name_is_described() {
        let missing: Vec<String> = bound()
            .into_iter()
            .filter(|n| n.doc.is_empty())
            .map(|n| n.name)
            .collect();
        assert!(
            missing.is_empty(),
            "bound with no row in blue_lang_runtime::docs: {missing:?}"
        );
    }

    #[test]
    fn every_row_names_a_bound_name() {
        let names: BTreeSet<String> = bound().into_iter().map(|n| n.name).collect();
        let stale: Vec<&str> = blue_lang_runtime::docs::NAMES
            .iter()
            .map(|d| d.name)
            .filter(|n| !names.contains(*n))
            .collect();
        assert!(
            stale.is_empty(),
            "rows naming nothing the runtime binds: {stale:?}"
        );
        let mut seen = BTreeSet::new();
        for d in blue_lang_runtime::docs::NAMES {
            assert!(seen.insert(d.name), "`{}` has two rows", d.name);
        }
    }

    #[test]
    fn every_signature_matches_its_arity() {
        let mut wrong = Vec::new();
        for n in bound() {
            let Some(arity) = &n.arity else { continue };
            match declared_params(n.signature) {
                Some(p) if agrees(arity, p) => {}
                _ => wrong.push(format!(
                    "{}: `{}` against arity {arity}",
                    n.name, n.signature
                )),
            }
        }
        assert!(wrong.is_empty(), "{}", wrong.join("\n"));
    }

    #[test]
    fn the_signature_grammar_reads_what_it_says() {
        assert_eq!(declared_params("f(a, b)"), Some((2, 0, false)));
        assert_eq!(declared_params("f(a[, b][, c])"), Some((1, 2, false)));
        assert_eq!(declared_params("f(g, [init, ]xs)"), Some((2, 1, false)));
        assert_eq!(declared_params("f(a, more...)"), Some((1, 0, true)));
        assert_eq!(declared_params("f()"), Some((0, 0, false)));
        assert!(agrees("1..3", (1, 2, false)));
        assert!(agrees("2+", (2, 0, true)));
        assert!(agrees("any", (0, 0, true)));
        assert!(!agrees("2", (1, 0, false)));
        assert!(!agrees("2", (2, 0, true)));
    }
}
