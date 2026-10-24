//! `item_tree(file)`: a file's top-level definitions, tests and imports, with
//! where each is and how its signature reads. No body is resolved, so an
//! edit inside one leaves the items of every other form as they were.

use blue_lang_syntax::{Atom, Span, Spanned, SpannedForm};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ItemKind {
    /// `def f(…)`.
    Function,
    /// `defmacro m(…)`.
    Macro,
    /// `x = …` at the top level.
    Value,
    /// `test "…" … end`.
    Test,
    /// `use("pkg", …)`.
    Use,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Item {
    pub name: String,
    pub kind: ItemKind,
    /// The whole form.
    pub span: Span,
    /// The name as written.
    pub name_span: Span,
    /// The form's first line, as the formatter writes it.
    pub signature: String,
    /// The form's `@doc` text.
    pub doc: Option<String>,
}

/// Every item of a file's documented parse: a documented definition is its
/// definition, spanning its doc, with the doc's text.
#[must_use]
pub fn of(documented: &[Spanned]) -> Vec<Item> {
    documented
        .iter()
        .filter_map(|f| match blue_lang_syntax::doc::documented(f) {
            Some((text, def)) => item(
                &Spanned::new(f.span, def.form.clone()),
                Some(text.to_string()),
            ),
            None => item(f, None),
        })
        .collect()
}

fn item(form: &Spanned, doc: Option<String>) -> Option<Item> {
    let items = form.as_list()?;
    let head = items.first()?.as_symbol()?;
    let (name, kind, name_span) = match head {
        "define" | "define-typed" => {
            let node = blue_lang_syntax::scope::defined_name_node(items)?;
            let function = items.get(1).is_some_and(|t| t.as_list().is_some());
            let kind = if function {
                ItemKind::Function
            } else {
                ItemKind::Value
            };
            (node.as_symbol()?.to_string(), kind, node.span)
        }
        "defmacro" => {
            let node = items.get(1)?;
            (node.as_symbol()?.to_string(), ItemKind::Macro, node.span)
        }
        "deftest" => {
            let node = items.get(1)?;
            match &node.form {
                SpannedForm::Atom(Atom::Str(s)) => (s.clone(), ItemKind::Test, node.span),
                _ => return None,
            }
        }
        _ => {
            let import = blue_lang_syntax::scope::use_target(form)?;
            (import.package, ItemKind::Use, import.package_span)
        }
    };
    Some(Item {
        name,
        kind,
        span: form.span,
        name_span,
        signature: signature_of(form),
        doc,
    })
}

/// The first line of `form` as the formatter writes it: hover, completion
/// and the file cannot disagree about how a signature is spelled.
#[must_use]
pub fn signature_of(form: &Spanned) -> String {
    let rendered = blue_lang_fmt::format_forms(std::slice::from_ref(&form.to_sexp()));
    rendered.lines().next().unwrap_or_default().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Red run (2026-10-24): with `doc` read from the comment above the
    /// form, as it was, `f`'s doc was the `#` line and `g`'s was `None`.
    #[test]
    fn the_doc_is_the_doc_and_a_comment_is_not() {
        let text = "# a comment, not a doc\ndef f()\n  1\nend\n\n@doc \"\"\"\ng is two.\n\"\"\"\ndef g()\n  2\nend\n";
        let forms = blue_lang_syntax::parse_program_documented(text).expect("parses");
        let docs: Vec<Option<String>> = of(&forms).into_iter().map(|i| i.doc).collect();
        assert_eq!(docs, vec![None, Some("g is two.".to_string())]);
    }

    #[test]
    fn items_name_each_definition_test_and_use() {
        let text = "use(\"retsu\", [:size])\n\nlimit = 3\n\ndef f(xs)\n  size(xs)\nend\n\ntest \"f counts\"\n  assert f([1]) == 1\nend\n";
        let forms = blue_lang_syntax::parse_program_tree(text).expect("parses");
        let got: Vec<(String, ItemKind, String)> = of(&forms)
            .into_iter()
            .map(|i| (i.name, i.kind, i.signature))
            .collect();
        assert_eq!(
            got,
            vec![
                (
                    "retsu".into(),
                    ItemKind::Use,
                    "use(\"retsu\", [:size])".into()
                ),
                ("limit".into(), ItemKind::Value, "limit = 3".into()),
                ("f".into(), ItemKind::Function, "def f(xs)".into()),
                (
                    "f counts".into(),
                    ItemKind::Test,
                    "test \"f counts\"".into()
                ),
            ]
        );
    }
}
