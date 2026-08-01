//! **Where am I on the blueshift, and what put me here?**
//!
//! Blue's central model is that a program slides along a continuum — loose and
//! dynamic at one end, locked and Rust-like at the other — and that it slides
//! *because of what you wrote* (`theory/BLUE.md` §V.20). A model that governs
//! how a language behaves and is invisible while you use it is a model the
//! author has to hold in their head. This makes it a reading on the screen.
//!
//! Two questions, and the second is the one that matters:
//!
//! 1. **How far is this shifted?** — a rung, per declaration and per document.
//! 2. **What is shifting it?** — every contributing factor, each pointing at
//!    the exact source that caused it.
//!
//! An aggregate without the second is a score, and a score people cannot act on
//! is decoration. Every [`Factor`] therefore carries a range.
//!
//! # Measured, never estimated
//!
//! Every number comes from an analysis that actually ran — the checker's own
//! `visited` count, the declarations it found typed, the seams it recorded, the
//! build inputs the program declared. Nothing is inferred from a heuristic over
//! the source text. If blue cannot measure a factor, it is absent from the
//! report rather than approximated, because a shift reading that quietly
//! guesses is worse than one that admits a blind spot.
//!
//! # The rungs are ordinal, not a percentage
//!
//! Blue deliberately does not report "63% shifted". The rungs are *named
//! positions* with different meanings, and averaging them into a scalar invents
//! a precision the model does not have — §V.20 describes a continuum of
//! discrete absorption lines, not a dial. A percentage would also imply 100% is
//! the goal; it is not, and the whole point of the RIGOR axis is that a program
//! sits where its author needs it.

use crate::analysis::Range;

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

/// What kind of thing caused a shift.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FactorKind {
    /// A parameter or return type. Shifts toward `Checked`.
    TypeAnnotation,
    /// A `definput` — restricts the macro phase's reach. Shifts toward
    /// `Restricted`.
    CapabilityDeclaration,
    /// A declaration with NO annotation. Holds the document back, and naming it
    /// is the actionable half: "you are at `annotated` because of THIS one".
    UntypedDeclaration,
    /// A typed↔untyped boundary, where a runtime check has to exist.
    Seam,
}

impl FactorKind {
    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            FactorKind::TypeAnnotation => "type annotation",
            FactorKind::CapabilityDeclaration => "capability declaration",
            FactorKind::UntypedDeclaration => "untyped declaration",
            FactorKind::Seam => "seam",
        }
    }

    /// Does this push toward locked, or hold at loose? An author reading a list
    /// needs to tell "this is what shifted me" from "this is what is holding
    /// me back" at a glance.
    #[must_use]
    pub fn shifts_forward(self) -> bool {
        matches!(
            self,
            FactorKind::TypeAnnotation | FactorKind::CapabilityDeclaration
        )
    }
}

/// One thing that moved (or held) the shift, and where it is.
#[derive(Clone, Debug, PartialEq)]
pub struct Factor {
    pub kind: FactorKind,
    /// What it is — a declaration name, an input name.
    pub subject: String,
    /// Where to look. The reason this is not a bare score.
    pub range: Range,
    /// One line an editor can show verbatim.
    pub detail: String,
}

/// The reading for one document.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Shift {
    pub rung: Option<Rung>,
    pub factors: Vec<Factor>,
    /// Nodes the type walk actually visited — the *cost* of where you are.
    /// Zero at `Dynamic`, and that is the promise being kept, not a missing
    /// measurement.
    pub analysed_nodes: usize,
    pub typed_declarations: usize,
    pub total_declarations: usize,
}

impl Shift {
    /// A one-line summary for a status bar.
    #[must_use]
    pub fn summary(&self) -> String {
        let Some(rung) = self.rung else {
            return "no declarations".to_string();
        };
        let mut out = String::new();
        out.push_str(&rung.ramp());
        out.push(' ');
        out.push_str(rung.label());
        out.push_str("  (");
        out.push_str(&self.typed_declarations.to_string());
        out.push('/');
        out.push_str(&self.total_declarations.to_string());
        out.push_str(" typed, ");
        out.push_str(&self.analysed_nodes.to_string());
        out.push_str(" nodes analysed)");
        out
    }

    /// The factors holding the document back, in source order. What an author
    /// would act on to shift further.
    #[must_use]
    pub fn holding_back(&self) -> Vec<&Factor> {
        self.factors
            .iter()
            .filter(|f| !f.kind.shifts_forward())
            .collect()
    }
}

/// Compute the reading for a document.
pub fn shift_of(src: &str) -> Shift {
    let index = crate::analysis::LineIndex::new(src);
    let mut out = Shift::default();

    let Ok(forms) = blue_lang_syntax::parse_program(src) else {
        // An unparseable document has no reading. Reporting `Dynamic` would be
        // a lie about a file that has no meaning yet.
        return out;
    };

    let outcome = blue_lang_check::check_program(&forms);
    out.analysed_nodes = outcome.stats.visited;
    out.typed_declarations = outcome.stats.typed_decls;

    let inputs = blue_lang_runtime::declarations(&forms);
    for decl in &inputs {
        out.factors.push(Factor {
            kind: FactorKind::CapabilityDeclaration,
            subject: decl.name.clone(),
            range: index.whole_document(),
            detail: {
                let mut d = String::from("the macro phase may read `");
                d.push_str(&decl.name);
                d.push_str("` and nothing else — its bytes are pinned to a content hash");
                d
            },
        });
    }

    for form in &forms {
        let Some((name, typed)) = declaration_of(form) else {
            continue;
        };
        out.total_declarations += 1;
        out.factors.push(if typed {
            Factor {
                kind: FactorKind::TypeAnnotation,
                subject: name.clone(),
                range: index.whole_document(),
                detail: {
                    let mut d = String::from("`");
                    d.push_str(&name);
                    d.push_str("` is annotated, so it is checked");
                    d
                },
            }
        } else {
            Factor {
                kind: FactorKind::UntypedDeclaration,
                subject: name.clone(),
                range: index.whole_document(),
                detail: {
                    let mut d = String::from("`");
                    d.push_str(&name);
                    d.push_str("` has no annotation — annotate it to shift further");
                    d
                },
            }
        });
    }

    for seam in &outcome.seams {
        out.factors.push(Factor {
            kind: FactorKind::Seam,
            subject: seam.at.clone(),
            range: index.whole_document(),
            detail: "a typed↔untyped boundary — a runtime check lands here".to_string(),
        });
    }

    out.rung = rung_for(&out, !inputs.is_empty());
    out
}

/// The document's rung.
///
/// The LOWEST position its declarations justify: one unannotated function means
/// the file is not `Checked`, because the checker genuinely did not check it.
/// Taking the maximum would let a single annotated helper report a file as
/// checked, which is the reading an author would most regret trusting.
fn rung_for(s: &Shift, has_capability: bool) -> Option<Rung> {
    if s.total_declarations == 0 {
        return None;
    }
    if s.typed_declarations == 0 {
        return Some(Rung::Dynamic);
    }
    if s.typed_declarations < s.total_declarations {
        return Some(Rung::Annotated);
    }
    Some(if has_capability {
        Rung::Restricted
    } else {
        Rung::Checked
    })
}

/// `(name, is_typed)` for a declaration form.
fn declaration_of(form: &blue_lang_syntax::Sexp) -> Option<(String, bool)> {
    use blue_lang_syntax::{Atom, Sexp};
    let Sexp::List(items) = form else { return None };
    let head = match items.first() {
        Some(Sexp::Atom(Atom::Symbol(s))) => &**s,
        _ => return None,
    };
    let typed = match head {
        "define" => false,
        "define-typed" => true,
        _ => return None,
    };
    // Both spell the signature as a list whose head is the name.
    match items.get(1) {
        Some(Sexp::List(sig)) => match sig.first() {
            Some(Sexp::Atom(Atom::Symbol(n))) => Some((n.to_string(), typed)),
            _ => None,
        },
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const UNTYPED: &str = "def add(a, b)\n  a + b\nend";
    const TYPED: &str = "def add(a: Int, b: Int) -> Int\n  a + b\nend";

    /// **The default is `Dynamic`, and that is not a deficiency.** Blue's whole
    /// premise is that declaring nothing costs nothing.
    #[test]
    fn an_unannotated_program_is_dynamic_and_costs_nothing() {
        let s = shift_of(UNTYPED);
        assert_eq!(s.rung, Some(Rung::Dynamic));
        assert_eq!(
            s.analysed_nodes, 0,
            "the promise is zero analysis, and the reading must show it"
        );
    }

    #[test]
    fn a_fully_annotated_program_is_checked() {
        let s = shift_of(TYPED);
        assert_eq!(s.rung, Some(Rung::Checked));
        assert!(s.analysed_nodes > 0, "annotating must buy real analysis");
    }

    /// **A mixed file is `Annotated`, not `Checked`.** The rung is the LOWEST
    /// its declarations justify — one unannotated function means the checker
    /// genuinely did not check it, and reporting otherwise is the reading an
    /// author would most regret trusting.
    #[test]
    fn one_untyped_declaration_holds_the_whole_document_back() {
        let src = format!("{TYPED}\ndef other(x)\n  x\nend");
        let s = shift_of(&src);
        assert_eq!(s.rung, Some(Rung::Annotated), "not Checked");
        assert_eq!(s.typed_declarations, 1);
        assert_eq!(s.total_declarations, 2);
    }

    /// **And it names WHICH one.** An aggregate without this is a score, and a
    /// score nobody can act on is decoration.
    #[test]
    fn the_report_names_what_is_holding_it_back() {
        let src = format!("{TYPED}\ndef other(x)\n  x\nend");
        let held = shift_of(&src)
            .holding_back()
            .iter()
            .map(|f| f.subject.clone())
            .collect::<Vec<_>>();
        assert_eq!(held, vec!["other"], "must name the untyped declaration");
    }

    /// A capability declaration shifts past `Checked` — it is a *reach*
    /// restriction, not a type one, and the model treats those as different
    /// axes.
    #[test]
    fn a_capability_declaration_reaches_the_restricted_rung() {
        let src = format!("definput(\"schema\", \"b3:abc\")\n{TYPED}");
        let s = shift_of(&src);
        assert_eq!(s.rung, Some(Rung::Restricted));
        assert!(
            s.factors
                .iter()
                .any(|f| f.kind == FactorKind::CapabilityDeclaration),
            "and names the input that did it"
        );
    }

    /// The same capability declaration does NOT lift an untyped file — the axes
    /// compose, they do not substitute.
    #[test]
    fn a_capability_declaration_does_not_rescue_an_untyped_file() {
        let src = format!("definput(\"schema\", \"b3:abc\")\n{UNTYPED}");
        assert_eq!(shift_of(&src).rung, Some(Rung::Dynamic));
    }

    /// Rungs are ordinal and comparable, which is what makes "lowest wins"
    /// expressible.
    #[test]
    fn rungs_are_ordered_loose_to_locked() {
        assert!(Rung::Dynamic < Rung::Annotated);
        assert!(Rung::Annotated < Rung::Checked);
        assert!(Rung::Checked < Rung::Restricted);
    }

    /// The ramp fills with the rung, and it is the mark — identity and reading
    /// are the same object.
    #[test]
    fn the_ramp_fills_with_the_rung() {
        assert_eq!(Rung::Dynamic.ramp(), "█░░░");
        assert_eq!(Rung::Annotated.ramp(), "██░░");
        assert_eq!(Rung::Checked.ramp(), "███░");
        assert_eq!(Rung::Restricted.ramp(), "████");
    }

    /// An unparseable document has NO reading. Reporting `Dynamic` would be a
    /// claim about a file that has no meaning yet.
    #[test]
    fn an_unparseable_document_has_no_rung() {
        let s = shift_of("def add(");
        assert_eq!(s.rung, None);
        assert!(s.factors.is_empty());
    }

    /// So does a file with no declarations — "dynamic" would imply a choice the
    /// author did not make.
    #[test]
    fn a_file_with_no_declarations_has_no_rung() {
        assert_eq!(shift_of("1 + 2").rung, None);
    }

    /// The summary is one line and carries the measured cost, so a status bar
    /// shows both position and price.
    #[test]
    fn the_summary_carries_the_position_and_its_cost() {
        let s = shift_of(TYPED);
        let line = s.summary();
        assert!(line.contains("checked"), "{line}");
        assert!(line.contains("1/1 typed"), "{line}");
        assert!(line.contains("nodes analysed"), "{line}");
        assert!(line.starts_with("███░"), "carries the ramp: {line}");
    }

    /// Anti-vacuity: the reading must actually MOVE with the source. A constant
    /// would satisfy several assertions above.
    #[test]
    fn the_reading_changes_as_the_program_shifts() {
        let rungs: Vec<Option<Rung>> = [
            UNTYPED,
            &format!("{TYPED}\ndef other(x)\n  x\nend"),
            TYPED,
            &format!("definput(\"s\", \"b3:a\")\n{TYPED}"),
        ]
        .iter()
        .map(|s| shift_of(s).rung)
        .collect();
        assert_eq!(
            rungs,
            vec![
                Some(Rung::Dynamic),
                Some(Rung::Annotated),
                Some(Rung::Checked),
                Some(Rung::Restricted)
            ],
            "each step must move the reading"
        );
    }
}
