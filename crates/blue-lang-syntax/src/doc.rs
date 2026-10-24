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
        let step = match code.rsplit_once(" #=> ") {
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
        let mut from = text_span.start;
        for (k, example) in examples(text).iter().enumerate() {
            out.push(doctest(
                src,
                text,
                &mut from,
                text_span.end,
                &subject,
                k + 1,
                example,
            )?);
        }
    }
    Ok(out)
}

/// One example as a `test` block whose every node is spanned at the source
/// it was written as, so a failure, a reference and a rename land on the
/// example's own characters.
fn doctest(
    src: &str,
    text: &str,
    from: &mut usize,
    until: usize,
    subject: &str,
    k: usize,
    example: &Example,
) -> Result<Spanned, ParseError> {
    let fail = |at: Span, why: &str| {
        ParseError::new(format!("{subject}'s example {k} {why}"), at).located(src)
    };
    let mut stmts = Vec::new();
    for (line_no, step) in &example.steps {
        let written = text.lines().nth(*line_no).unwrap_or("").trim();
        let at = next_line(src, from, until, written)
            .ok_or_else(|| fail(Span::new(*from, *from), "is not where its text is"))?;
        match step {
            Step::Run(code) => {
                stmts.push(snippet(src, code, at).map_err(|e| fail(e, "does not parse"))?)
            }
            Step::Check { expr, value } => {
                let marker = at + written.rfind(" #=> ").unwrap_or(0);
                let after = &written[written.rfind(" #=> ").map_or(0, |i| i + 5)..];
                let value_at = marker + 5 + (after.len() - after.trim_start().len());
                let e = snippet(src, expr, at).map_err(|e| fail(e, "does not parse"))?;
                let v = snippet(src, value, value_at).map_err(|e| fail(e, "does not parse"))?;
                let op = Span::new(marker + 1, marker + 4);
                let compared = Span::new(e.span.start, v.span.end);
                let cmp = Spanned::new(
                    compared,
                    SpannedForm::List(vec![symbol(op, "equal?"), e, v]),
                );
                let quoted = Spanned::new(compared, SpannedForm::Quote(Box::new(cmp.clone())));
                stmts.push(Spanned::new(
                    compared,
                    SpannedForm::List(vec![symbol(op, crate::LOWERED_ASSERT), quoted, cmp]),
                ));
            }
        }
    }
    let first = stmts.first().map_or(*from, |s| s.span.start);
    let last = stmts.last().map_or(*from, |s| s.span.end);
    let whole = Span::new(first, last);
    let body = if stmts.len() == 1 {
        stmts.remove(0)
    } else {
        let mut items = vec![symbol(Span::new(first, first), "begin")];
        items.extend(stmts);
        Spanned::new(whole, SpannedForm::List(items))
    };
    Ok(Spanned::new(
        whole,
        SpannedForm::List(vec![
            symbol(Span::new(first, first), "deftest"),
            text_node(
                Span::new(first, first),
                format!("{DOCTEST_PREFIX}{subject} example {k}"),
            ),
            body,
        ]),
    ))
}

/// Where the next source line reading `written` starts its code, at or
/// after `from` and before `until`; `from` moves past it.
fn next_line(src: &str, from: &mut usize, until: usize, written: &str) -> Option<usize> {
    let region = src.get(*from..until.min(src.len()))?;
    let mut offset = *from;
    for line in region.split_inclusive('\n') {
        if line.trim() == written {
            let code = offset + (line.len() - line.trim_start().len());
            *from = offset + line.len();
            return Some(code);
        }
        offset += line.len();
    }
    None
}

/// One expression or statement of an example, parsed as part of its text
/// and spanned where it is written.
fn snippet(src: &str, code: &str, at: usize) -> Result<Spanned, Span> {
    let here = Span::new(at, at + code.len());
    let mut forms = crate::parse::parse_snippet(code).map_err(|_| here)?;
    if forms.len() != 1 || src.get(here.start..here.end) != Some(code) {
        return Err(here);
    }
    Ok(shift(forms.remove(0), at))
}

fn symbol(span: Span, name: &str) -> Spanned {
    Spanned::new(span, SpannedForm::Atom(Atom::Symbol(name.into())))
}

fn shift(node: Spanned, by: usize) -> Spanned {
    let span = if node.span.is_synthetic() {
        node.span
    } else {
        Span::new(node.span.start + by, node.span.end + by)
    };
    let form = match node.form {
        SpannedForm::List(items) => {
            SpannedForm::List(items.into_iter().map(|i| shift(i, by)).collect())
        }
        SpannedForm::Quote(x) => SpannedForm::Quote(Box::new(shift(*x, by))),
        SpannedForm::Quasiquote(x) => SpannedForm::Quasiquote(Box::new(shift(*x, by))),
        SpannedForm::Unquote(x) => SpannedForm::Unquote(Box::new(shift(*x, by))),
        SpannedForm::UnquoteSplice(x) => SpannedForm::UnquoteSplice(Box::new(shift(*x, by))),
        other => other,
    };
    Spanned::new(span, form)
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
        assert_eq!(
            &SRC[at.start..at.end],
            "x = 1\n    f(x) #=> 2\n    f(2) #=> 3"
        );
        fn refs(n: &Spanned, out: &mut Vec<Span>) {
            if n.as_symbol() == Some("f") {
                out.push(n.span);
            }
            if let Some(items) = n.as_list() {
                for i in items {
                    refs(i, out);
                }
            }
        }
        let mut found = Vec::new();
        refs(&tests[1], &mut found);
        assert!(!found.is_empty());
        for s in found {
            assert_eq!(&SRC[s.start..s.end], "f");
        }
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
