//! `@doc` and `@moduledoc`: documentation as a typed child of the tree.
//!
//! ```text
//! @moduledoc """
//! retsu holds the list verbs.
//!
//!     retsu::first([1, 2]) #=> 1
//! """
//!
//! @doc """
//! clamp keeps a number inside a range.
//!
//!     clamp(99, 1, 10) #=> 10
//! """
//! def clamp(x, lo, hi)
//!   …
//! end
//! ```
//!
//! `@doc` lowers to `(blue-doc "text" (define …))`: the definition is a child
//! of its documentation, so the text travels with the tree it describes, into
//! the formatter, `def_hash`, the doc rules and mondou's views. `@moduledoc` is
//! the first form of a file and lowers to `(blue-moduledoc "text")`.
//!
//! **Two views of one parse.** [`crate::parse_program_documented`] returns the
//! tree with these nodes. Every other `parse_program*` door returns
//! [`strip`]ped forms: a documented definition becomes the definition itself,
//! spanning its documentation too, and the module doc is gone. So the checker,
//! the resolver and the evaluators see exactly the tree they saw before docs
//! existed, and only the consumers that read docs ask for them.
//!
//! The text is data, not code: no escapes and no interpolation. Its
//! indentation (the closing `"""`'s), trailing whitespace and leading and
//! trailing blank lines are stripped at lex time, so the formatter writes one
//! spelling of a text.
//!
//! **Examples are doctests.** An indented paragraph of the text that holds a
//! line `expr #=> value` is an example: its other lines run first, and each
//! `#=>` line asserts `expr == value`. [`doctests`] lowers each example to a
//! `test` block, so `blue test` runs it on the evaluator that runs every other
//! test, and a red example is a red build.

use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::ParseError;

/// The head `@doc` lowers to.
pub const DOC_HEAD: &str = "blue-doc";

/// The head `@moduledoc` lowers to.
pub const MODULEDOC_HEAD: &str = "blue-moduledoc";

/// The name every doctest's `test` block starts with.
pub const DOCTEST_PREFIX: &str = "@doc ";

/// The text and definition of a documented top-level form.
#[must_use]
pub fn documented(form: &Spanned) -> Option<(&str, &Spanned)> {
    match form.as_list()? {
        [head, text, def] if head.as_symbol() == Some(DOC_HEAD) => Some((text.as_string()?, def)),
        _ => None,
    }
}

/// The text of a `@moduledoc` form.
#[must_use]
pub fn moduledoc_text(form: &Spanned) -> Option<&str> {
    match form.as_list()? {
        [head, text] if head.as_symbol() == Some(MODULEDOC_HEAD) => text.as_string(),
        _ => None,
    }
}

/// The module documentation of a documented parse, with its span.
#[must_use]
pub fn module_doc(forms: &[Spanned]) -> Option<(&str, Span)> {
    forms
        .iter()
        .find_map(|f| moduledoc_text(f).map(|t| (t, f.span)))
}

/// Is `form` a doc node of either kind?
#[must_use]
pub fn is_doc_node(form: &Spanned) -> bool {
    documented(form).is_some() || moduledoc_text(form).is_some()
}

/// The forms every undocumented consumer sees: a documented definition is
/// the definition, spanning its documentation; a module doc is dropped.
#[must_use]
pub fn strip(forms: Vec<Spanned>) -> Vec<Spanned> {
    forms
        .into_iter()
        .filter(|f| moduledoc_text(f).is_none())
        .map(|f| match f.form {
            SpannedForm::List(mut items)
                if items.len() == 3 && items[0].as_symbol() == Some(DOC_HEAD) =>
            {
                let def = items.pop().expect("three items");
                Spanned::new(f.span, def.form)
            }
            form => Spanned::new(f.span, form),
        })
        .collect()
}

/// Put the documentation of `src` back on `forms`, a stripped parse of it
/// (or a tree built from one whose top-level spans are the parse's): a form
/// whose span is a documented definition's is wrapped again, its own span
/// returned to the definition's, and the module doc leads. Forms that are
/// already documented are returned as they are.
#[must_use]
pub fn redocument(src: &str, forms: Vec<Spanned>) -> Vec<Spanned> {
    if forms.iter().any(is_doc_node) {
        return forms;
    }
    let Ok(documented_forms) = crate::parse_program_documented(src) else {
        return forms;
    };
    let mut out = Vec::with_capacity(forms.len() + 1);
    for f in &documented_forms {
        if moduledoc_text(f).is_some() {
            out.push(f.clone());
        }
    }
    for f in forms {
        let wrapper = documented_forms
            .iter()
            .find(|d| d.span == f.span && documented(d).is_some());
        match wrapper.and_then(|w| w.as_list()) {
            Some([head, text, def]) => out.push(Spanned::new(
                f.span,
                SpannedForm::List(vec![
                    head.clone(),
                    text.clone(),
                    Spanned::new(def.span, f.form),
                ]),
            )),
            _ => out.push(f),
        }
    }
    out
}

/// The name a definition binds: `def f`, `defmacro m`, `x = …`.
#[must_use]
pub fn defined_name(def: &Spanned) -> Option<&str> {
    let items = def.as_list()?;
    if items.first()?.as_symbol()? == "defmacro" {
        return items.get(1)?.as_symbol();
    }
    crate::scope::defined_name_node(items)?.as_symbol()
}

/// Can `form` carry a `@doc`? A function, macro or top-level value.
#[must_use]
pub fn is_definition(form: &Spanned) -> bool {
    defined_name(form).is_some()
}

/// One line of an example.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Step {
    /// A statement the checks below it depend on.
    Run(String),
    /// `expr #=> value`.
    Check { expr: String, value: String },
}

/// One example: an indented paragraph of a doc text with at least one
/// `#=>` line.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Example {
    /// Each step with its line in the text, 0-based.
    pub steps: Vec<(usize, Step)>,
}

/// Every example in a doc text.
#[must_use]
pub fn examples(text: &str) -> Vec<Example> {
    let mut out = Vec::new();
    let mut current: Vec<(usize, Step)> = Vec::new();
    let flush = |current: &mut Vec<(usize, Step)>, out: &mut Vec<Example>| {
        if current.iter().any(|(_, s)| matches!(s, Step::Check { .. })) {
            out.push(Example {
                steps: std::mem::take(current),
            });
        } else {
            current.clear();
        }
    };
    for (i, line) in text.lines().enumerate() {
        let indented = line.starts_with([' ', '\t']) && !line.trim().is_empty();
        if !indented {
            flush(&mut current, &mut out);
            continue;
        }
        let code = line.trim();
        let step = match code.split_once(" #=> ") {
            Some((expr, value)) => Step::Check {
                expr: expr.trim().to_string(),
                value: value.trim().to_string(),
            },
            None => Step::Run(code.to_string()),
        };
        current.push((i, step));
    }
    flush(&mut current, &mut out);
    out
}

/// The intent: the text's first paragraph, its lines joined by spaces.
#[must_use]
pub fn intent(text: &str) -> String {
    text.lines()
        .take_while(|l| !l.trim().is_empty() && !l.starts_with([' ', '\t']))
        .map(str::trim)
        .collect::<Vec<_>>()
        .join(" ")
}

/// Is `form` a doctest [`doctests`] made?
#[must_use]
pub fn is_doctest(form: &Spanned) -> bool {
    match form.as_list() {
        Some([head, name, _]) => {
            head.as_symbol() == Some("deftest")
                && name
                    .as_string()
                    .is_some_and(|n| n.starts_with(DOCTEST_PREFIX))
        }
        _ => false,
    }
}

/// Every example of `src`'s documentation as a `test` block, spanned at the
/// example's lines so a failure names where the example is written.
///
/// # Errors
///
/// `src` does not parse, or an example's line does not.
pub fn doctests(src: &str) -> Result<Vec<Spanned>, ParseError> {
    let forms = crate::parse_program_documented(src)?;
    let mut out = Vec::new();
    for form in &forms {
        let (subject, text, text_span) = if let Some((text, def)) = documented(form) {
            let Some(name) = defined_name(def) else {
                continue;
            };
            let span = form.as_list().map_or(form.span, |items| items[1].span);
            (format!("`{name}`"), text, span)
        } else if let Some(text) = moduledoc_text(form) {
            ("the module".to_string(), text, form.span)
        } else {
            continue;
        };
        for (k, example) in examples(text).iter().enumerate() {
            out.push(doctest(src, text_span, &subject, k + 1, example)?);
        }
    }
    Ok(out)
}

fn doctest(
    src: &str,
    within: Span,
    subject: &str,
    k: usize,
    example: &Example,
) -> Result<Spanned, ParseError> {
    let mut body = format!("test \"{DOCTEST_PREFIX}{subject} example {k}\"\n");
    for (_, step) in &example.steps {
        match step {
            Step::Run(code) => body.push_str(&format!("  {code}\n")),
            Step::Check { expr, value } => {
                body.push_str(&format!("  assert ({expr}) == ({value})\n"));
            }
        }
    }
    body.push_str("end\n");
    let at = example_span(src, within, example);
    let parsed = crate::parse_program_tree(&body).map_err(|e| {
        ParseError::new(
            format!("{subject}'s example {k} does not parse: {}", e.message),
            at,
        )
        .located(src)
    })?;
    let test = parsed.into_iter().next().ok_or_else(|| {
        ParseError::new(format!("{subject}'s example {k} is empty"), at).located(src)
    })?;
    Ok(respan(test, at))
}

/// The source lines an example was written on, inside `within`.
fn example_span(src: &str, within: Span, example: &Example) -> Span {
    let region = src
        .get(within.start..within.end.min(src.len()))
        .unwrap_or("");
    let lines: Vec<&str> = example
        .steps
        .iter()
        .map(|(_, s)| match s {
            Step::Run(c) => c.as_str(),
            Step::Check { .. } => "",
        })
        .collect();
    let first_check = example.steps.iter().find_map(|(_, s)| match s {
        Step::Check { expr, .. } => Some(expr.as_str()),
        Step::Run(_) => None,
    });
    let needle = lines
        .iter()
        .copied()
        .find(|l| !l.is_empty())
        .or(first_check)
        .unwrap_or("");
    let mut offset = 0;
    let mut start = None;
    for line in region.split_inclusive('\n') {
        if start.is_none() && !needle.is_empty() && line.trim().starts_with(needle) {
            start = Some(within.start + offset + (line.len() - line.trim_start().len()));
        }
        offset += line.len();
    }
    let s = start.unwrap_or(within.start);
    let line_end = src[s..].find('\n').map_or(src.len(), |i| s + i);
    Span::new(s, line_end.max(s))
}

fn respan(node: Spanned, at: Span) -> Spanned {
    let form = match node.form {
        SpannedForm::List(items) => {
            SpannedForm::List(items.into_iter().map(|i| respan(i, at)).collect())
        }
        SpannedForm::Quote(x) => SpannedForm::Quote(Box::new(respan(*x, at))),
        SpannedForm::Quasiquote(x) => SpannedForm::Quasiquote(Box::new(respan(*x, at))),
        SpannedForm::Unquote(x) => SpannedForm::Unquote(Box::new(respan(*x, at))),
        SpannedForm::UnquoteSplice(x) => SpannedForm::UnquoteSplice(Box::new(respan(*x, at))),
        other => other,
    };
    Spanned::new(at, form)
}

/// A doc text node, as the parser builds it.
pub(crate) fn text_node(span: Span, text: String) -> Spanned {
    Spanned::new(span, SpannedForm::Atom(Atom::Str(text.into())))
}

#[cfg(test)]
mod tests {
    use super::*;

    const SRC: &str = "@moduledoc \"\"\"\n  m does a thing.\n\n      f(1) #=> 2\n  \"\"\"\n\n@doc \"\"\"\nf adds one.\n\n    x = 1\n    f(x) #=> 2\n    f(2) #=> 3\n\"\"\"\ndef f(n)\n  n + 1\nend\n";

    #[test]
    fn the_documented_tree_holds_both_kinds_and_the_stripped_one_neither() {
        let doc = crate::parse_program_documented(SRC).unwrap();
        assert_eq!(doc.len(), 2);
        assert_eq!(
            module_doc(&doc).map(|(t, _)| t),
            Some("m does a thing.\n\n    f(1) #=> 2")
        );
        let (text, def) = documented(&doc[1]).unwrap();
        assert!(text.starts_with("f adds one."));
        assert_eq!(defined_name(def), Some("f"));
        let plain = crate::parse_program_tree(SRC).unwrap();
        assert_eq!(plain.len(), 1);
        assert_eq!(plain[0].to_sexp().to_string(), "(define (f n) (+ n 1))");
        assert_eq!(plain[0].span, doc[1].span);
    }

    #[test]
    fn redocument_restores_what_strip_took() {
        let doc = crate::parse_program_documented(SRC).unwrap();
        let plain = crate::parse_program_tree(SRC).unwrap();
        assert_eq!(redocument(SRC, plain), doc);
    }

    #[test]
    fn examples_and_intent_are_read_from_the_text() {
        let text = "f adds one,\nto a number.\n\n    x = 1\n    f(x) #=> 2\n\nprose\n\n    g(1)\n";
        assert_eq!(intent(text), "f adds one, to a number.");
        let ex = examples(text);
        assert_eq!(ex.len(), 1, "a paragraph with no `#=>` is not an example");
        assert_eq!(
            ex[0].steps,
            vec![
                (3, Step::Run("x = 1".into())),
                (
                    4,
                    Step::Check {
                        expr: "f(x)".into(),
                        value: "2".into()
                    }
                )
            ]
        );
    }

    #[test]
    fn each_example_is_one_test_spanned_at_its_lines() {
        let tests = doctests(SRC).unwrap();
        assert_eq!(tests.len(), 2);
        assert!(tests.iter().all(is_doctest));
        assert_eq!(
            tests[1].to_sexp().to_string(),
            "(deftest \"@doc `f` example 1\" (begin (define x 1) (blue-assert '(equal? (f x) 2) (equal? (f x) 2)) (blue-assert '(equal? (f 2) 3) (equal? (f 2) 3))))"
        );
        let at = tests[1].span;
        assert_eq!(&SRC[at.start..at.end], "x = 1");
    }

    #[test]
    fn a_doc_must_document_a_definition_and_a_moduledoc_must_lead() {
        let e = crate::parse_program_documented("@doc \"\"\"\nx\n\"\"\"\nf(1)\n").unwrap_err();
        assert!(
            e.message.contains("documents the definition below it"),
            "{e}"
        );
        let e =
            crate::parse_program_documented("x = 1\n@moduledoc \"\"\"\nm\n\"\"\"\n").unwrap_err();
        assert!(e.message.contains("first form"), "{e}");
        let e =
            crate::parse_program_documented("def f()\n  @doc \"\"\"\n  x\n  \"\"\"\n  1\nend\n")
                .unwrap_err();
        assert!(e.message.contains("top level"), "{e}");
    }
}
