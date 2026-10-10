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
    /// The comment block directly above the form, without its `#`s.
    pub doc: Option<String>,
}

/// Every item of a file's forms.
#[must_use]
pub fn of(forms: &[Spanned], text: &str) -> Vec<Item> {
    forms.iter().filter_map(|f| item(f, text)).collect()
}

fn item(form: &Spanned, text: &str) -> Option<Item> {
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
        doc: doc_above(text, form.span.start),
    })
}

/// The first line of `form` as the formatter writes it: hover, completion
/// and the file cannot disagree about how a signature is spelled.
#[must_use]
pub fn signature_of(form: &Spanned) -> String {
    let rendered = blue_lang_fmt::format_forms(std::slice::from_ref(&form.to_sexp()));
    rendered.lines().next().unwrap_or_default().to_string()
}

/// The comment lines directly above byte `start`, joined, without their
/// `#`. A waiver is a directive, not documentation, and is left out.
#[must_use]
pub fn doc_above(text: &str, start: usize) -> Option<String> {
    let before = text.get(..start)?;
    let mut lines: Vec<&str> = before.lines().collect();
    if !before.ends_with('\n') {
        let last = lines.pop()?;
        if !last.trim().is_empty() {
            return None;
        }
    }
    let mut out = Vec::new();
    while let Some(line) = lines.pop() {
        let t = line.trim();
        match t.strip_prefix('#') {
            Some(c) if !c.trim_start().starts_with("waive ") => out.push(c.trim().to_string()),
            Some(_) => {}
            None => break,
        }
    }
    out.reverse();
    let joined = out.join(" ");
    (!joined.trim().is_empty()).then_some(joined)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_doc_is_the_comment_block_directly_above_and_skips_a_waiver() {
        let text = "x = 1\n\n# Adds.\n# Twice over.\n# waive B0002: kept for callers\ndef add(a, b)\n  a + b\nend\n";
        let at = text.find("def add").expect("def");
        assert_eq!(doc_above(text, at).as_deref(), Some("Adds. Twice over."));
        assert_eq!(doc_above(text, 0), None);
        let detached = "# a header\n\ndef f()\n  1\nend\n";
        assert_eq!(
            doc_above(detached, detached.find("def").expect("def")),
            None
        );
    }

    #[test]
    fn items_name_each_definition_test_and_use() {
        let text = "use(\"retsu\", [:size])\n\nlimit = 3\n\ndef f(xs)\n  size(xs)\nend\n\ntest \"f counts\"\n  assert f([1]) == 1\nend\n";
        let forms = blue_lang_syntax::parse_program_tree(text).expect("parses");
        let got: Vec<(String, ItemKind, String)> = of(&forms, text)
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
