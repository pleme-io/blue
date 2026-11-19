//! The blueshift rung of a file, measured from what it declares: the one
//! reading the language server shows and the check stage holds a file to
//! (`blue_lang_lsp::shift` draws its factors; A-colour of docs/ASYNC.md
//! refuses at [`Rung::Restricted`]).

use tatara_lisp::Spanned;

/// A named position on the loose→locked continuum.
///
/// Ordinal: `Dynamic < Annotated < Checked < Restricted`. Comparable so a
/// document's rung is the *lowest* of its declarations — a single unannotated
/// function means the document as a whole is not checked, which is the honest
/// reading and the one an author needs.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Rung {
    /// No annotations. Blue's default, and blue's fastest — the checker visits
    /// nothing. Not a deficiency.
    Dynamic = 0,
    /// Some declarations carry types; others do not. The mixed state, where
    /// seams exist.
    Annotated = 1,
    /// Every declaration is annotated, so the type walk covers the whole file.
    Checked = 2,
    /// Checked, *and* the macro phase's reach is restricted to declared,
    /// content-addressed inputs — a capability shift, not just a type shift.
    Restricted = 3,
}

impl Rung {
    /// The word an editor shows.
    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            Rung::Dynamic => "dynamic",
            Rung::Annotated => "annotated",
            Rung::Checked => "checked",
            Rung::Restricted => "restricted",
        }
    }

    /// What being here actually means, in one line, for a hover or status bar.
    #[must_use]
    pub fn meaning(self) -> &'static str {
        match self {
            Rung::Dynamic => "no annotations — no analysis runs, and nothing is checked",
            Rung::Annotated => "some declarations are typed; untyped ones are unchecked",
            Rung::Checked => "every declaration is typed, so the whole file is checked",
            Rung::Restricted => {
                "typed, and the macro phase may read only declared content-addressed inputs"
            }
        }
    }

    /// The mark rendered as a progress ramp — the same four Frost cells the
    /// wordmark uses, filled to this rung. The identity and the reading are the
    /// same object, which is the point of having a mark that means something.
    #[must_use]
    pub fn ramp(self) -> String {
        let filled = self as usize + 1;
        let mut out = String::with_capacity(4);
        for i in 0..4 {
            out.push(if i < filled { '█' } else { '░' });
        }
        out
    }
}

/// The rung `total` declarations justify when `typed` of them are typed and
/// the file declares an input or not: the LOWEST position. One unannotated
/// function means the file is not `Checked`, because the checker did not check
/// it; the maximum would let one annotated helper report a file as checked.
/// `None` when there is no declaration.
#[must_use]
pub fn rung_for(total: usize, typed: usize, has_capability: bool) -> Option<Rung> {
    if total == 0 {
        return None;
    }
    if typed == 0 {
        return Some(Rung::Dynamic);
    }
    if typed < total {
        return Some(Rung::Annotated);
    }
    Some(if has_capability {
        Rung::Restricted
    } else {
        Rung::Checked
    })
}

/// `(name, is_typed)` for a declaration form.
#[must_use]
pub fn declaration_of(form: &Spanned) -> Option<(String, bool)> {
    let items = form.as_list()?;
    let typed = match items.first()?.as_symbol()? {
        "define" => false,
        "define-typed" => true,
        _ => return None,
    };
    let name = items.get(1)?.as_list()?.first()?.as_symbol()?;
    Some((name.to_string(), typed))
}

/// The rung of `forms`, one file's parsed tree.
#[must_use]
pub fn rung_of(forms: &[Spanned]) -> Option<Rung> {
    let declared: Vec<bool> = forms
        .iter()
        .filter_map(declaration_of)
        .map(|(_, typed)| typed)
        .collect();
    let spanless: Vec<tatara_lisp::Sexp> = forms.iter().map(Spanned::to_sexp).collect();
    rung_for(
        declared.len(),
        declared.iter().filter(|t| **t).count(),
        !crate::declarations(&spanless).is_empty(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rung(src: &str) -> Option<Rung> {
        rung_of(&blue_lang_syntax::parse_program_tree(src).expect("parses"))
    }

    #[test]
    fn a_file_is_restricted_only_when_every_definition_is_typed_and_it_declares_an_input() {
        let typed = "def add(a: Int, b: Int) -> Int\n  a + b\nend\n";
        let input = "definput(\"schema\", \"b3:abc\")\n\n";
        assert_eq!(rung(""), None);
        assert_eq!(rung("def add(a, b)\n  a + b\nend\n"), Some(Rung::Dynamic));
        assert_eq!(rung(typed), Some(Rung::Checked));
        assert_eq!(rung(&format!("{input}{typed}")), Some(Rung::Restricted));
        assert_eq!(
            rung(&format!("{input}{typed}def b(x)\n  x\nend\n")),
            Some(Rung::Annotated)
        );
    }
}
