//! **blue evolves at full speed, and every break it causes fixes itself.**
//!
//! The operator's rule (2026-10-23): *"the more we write blue, the easier it
//! should be to write blue."* A pin means nobody has to upgrade, so a new rule
//! or a retired word may break working code — on one condition: the upgrade
//! that brings the break also brings its fix, and the error names the one
//! command that applies it. A break without a fixer is a gap in blue, fixed in
//! blue, never in the consumer (`docs/COMPOUNDING.md`).
//!
//! Two typed switches live here, both read from the environment so every door
//! (`run`, `test`, `check`, every bidama build) reads the same value:
//!
//! | variable | values | default | what it decides |
//! |---|---|---|---|
//! | `BLUE_FORM` | `own`, `none`, `all` | `own` | whose form this blue judges: the entry's only, nobody's (a build under a consumer's blue), or every file's |
//! | `BLUE_LAYOUT` | `judge`, `rewrite` | the door's: `judge` for `test` and `check`, `rewrite` for `run` | what a compile door does with a non-canonical entry: refuse it naming `blue fmt --write`, or rewrite it in place |
//!
//! **Form is what a machine fix can change.** A rule whose fix is
//! [`FixKind::Machine`] preserves meaning by its row's contract, so a violation
//! is a fact about how a file is written, never about what it computes. Form
//! is the producer's, judged by the blue the producer pins; meaning is
//! everyone's. A consumer never fails because a dependency is written for
//! another blue.

use crate::rules::{Code, FixKind, Severity, RULES};

/// Whose form this blue judges.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum FormJudge {
    /// The entry file's form; every loaded dependency compiles as written.
    #[default]
    Own,
    /// No file's form: meaning only. What a bidama build runs, since a
    /// consumer's blue may build a producer's bidama.
    None,
    /// Every file's form, dependencies included: the importer judges.
    All,
}

impl FormJudge {
    pub const ENV: &'static str = "BLUE_FORM";

    /// # Errors
    ///
    /// A value that is not `own`, `none` or `all`, named with the legal ones.
    pub fn parse(value: Option<&str>) -> Result<Self, String> {
        match value {
            None | Some("" | "own") => Ok(Self::Own),
            Some("none") => Ok(Self::None),
            Some("all") => Ok(Self::All),
            Some(other) => Err(format!(
                "{}={other} is not a form judge; it is one of own, none, all",
                Self::ENV
            )),
        }
    }

    /// # Errors
    ///
    /// As [`FormJudge::parse`].
    pub fn from_env() -> Result<Self, String> {
        Self::parse(std::env::var(Self::ENV).ok().as_deref())
    }

    /// Is a diagnostic of `code`, in the entry file or in a dependency,
    /// reported under this judge?
    #[must_use]
    pub fn reports(self, code: Code, in_entry: bool) -> bool {
        if !is_form(code) {
            return true;
        }
        match self {
            Self::All => true,
            Self::Own => in_entry,
            Self::None => false,
        }
    }

    /// Is the layout of a file judged under this judge?
    #[must_use]
    pub const fn judges_layout(self, in_entry: bool) -> bool {
        match self {
            Self::All => true,
            Self::Own => in_entry,
            Self::None => false,
        }
    }
}

/// What a compile door does with a non-canonical entry.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Layout {
    /// Refuse it, naming `blue fmt --write`: `blue test` and `blue check`,
    /// which never write a file.
    #[default]
    Judge,
    /// Rewrite it in place, then compile it: `blue run`'s door, and every
    /// door's until 2026-10-23.
    Rewrite,
}

impl Layout {
    pub const ENV: &'static str = "BLUE_LAYOUT";

    /// `None` when unset: the door's own default.
    ///
    /// # Errors
    ///
    /// A value that is not `judge` or `rewrite`.
    pub fn parse(value: Option<&str>) -> Result<Option<Self>, String> {
        match value {
            None | Some("") => Ok(None),
            Some("judge") => Ok(Some(Self::Judge)),
            Some("rewrite") => Ok(Some(Self::Rewrite)),
            Some(other) => Err(format!(
                "{}={other} is not a layout policy; it is one of judge, rewrite",
                Self::ENV
            )),
        }
    }

    /// # Errors
    ///
    /// As [`Layout::parse`].
    pub fn from_env() -> Result<Option<Self>, String> {
        Self::parse(std::env::var(Self::ENV).ok().as_deref())
    }

    /// `BLUE_LAYOUT` when set, else `door`'s default.
    #[must_use]
    pub fn for_door(door: Self) -> Self {
        Self::from_env().ok().flatten().unwrap_or(door)
    }
}

/// Is `code` a form rule: one whose fix preserves meaning and edits only
/// the file it is reported in? Two machine-fixable rules are meaning: B0012,
/// because the runtime's namespaces do not bind a name a file reaches only
/// through another file's `use`, so the violating program does not run; and
/// B0019, whose fix edits the Bluefile, because a needs list is what a
/// closure delivers.
#[must_use]
pub fn is_form(code: Code) -> bool {
    code.rule().fix == FixKind::Machine && !MEANING.contains(&code)
}

const MEANING: &[Code] = &[Code::B0012, Code::B0019];

/// The one command that fixes `d` in `file`, when blue ships a fixer for
/// it: its rule's, or the machine-applicable fix the diagnostic carries (a
/// closed bridge or a retired word, read from the producer's ledger).
#[must_use]
pub fn fix_command(d: &crate::Diagnostic, file: &str) -> Option<String> {
    let carried = d
        .fixes
        .iter()
        .any(|f| f.applicability == crate::Applicability::MachineApplicable);
    match d.code.rule().fix {
        FixKind::Machine if (Code::B0024..=Code::B0035).contains(&d.code) => {
            Some(format!("blue fmt --write {file}"))
        }
        FixKind::Machine => Some(format!("blue check --fix {file}")),
        FixKind::Suggested | FixKind::None if carried => Some(format!("blue check --fix {file}")),
        FixKind::Suggested | FixKind::None => None,
    }
}

/// An evolution rule with no fixer yet, and why: the ledger of gaps.
#[derive(Clone, Copy, Debug)]
pub struct Gap {
    pub code: Code,
    pub why: &'static str,
}

/// Every evolution rule (one brought in over an existing corpus, its row's
/// `ratchet`) that blocks a program and ships no machine fix. Each is a
/// primitive gap: closing one is writing its fixer and deleting its row.
pub const GAPS: &[Gap] = &[
    Gap {
        code: Code::B0013,
        why: "its fixer is `blue migrate --strip PREFIX BIDAMA CALLER...`, a rename across files, not a `check --fix` edit",
    },
    Gap {
        code: Code::B0014,
        why: "its fixer is `blue migrate --strip PREFIX BIDAMA CALLER...`, a rename across files, not a `check --fix` edit",
    },
    Gap {
        code: Code::B0016,
        why: "a `use` nothing reaches carries its removal as a fix; a listed name never read carries none yet",
    },
    Gap {
        code: Code::B0017,
        why: "two definitions of one name need one to be renamed, which a person chooses",
    },
    Gap {
        code: Code::B0020,
        why: "a bidama written as a value has no single call it stands for",
    },
    Gap {
        code: Code::B0022,
        why: "a malformed legacy_names declaration is the producer's own, fixed where it is declared",
    },
    Gap {
        code: Code::B0048,
        why: "an undeclared read has two repairs, declare the field or move the read into the component that declares it; the declaration is offered as a suggestion",
    },
    Gap {
        code: Code::B0052,
        why: "operation text becomes a root fragment and its components' fragments, a restructuring no edit derives from the text",
    },
];

/// The evolution rules that block a program: ratcheted, error severity.
pub fn evolution_errors() -> impl Iterator<Item = Code> {
    RULES
        .iter()
        .filter(|r| r.ratchet.is_some() && r.severity == Severity::Error)
        .map(|r| r.code)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_evolution_error_ships_its_fixer_or_is_a_named_gap() {
        let mut naked = Vec::new();
        for code in evolution_errors() {
            let fixed = code.rule().fix == FixKind::Machine;
            let gap = GAPS.iter().any(|g| g.code == code);
            if !fixed && !gap {
                naked.push(code.as_str());
            }
            assert!(
                !(fixed && gap),
                "{code} ships a fixer and is still a gap row"
            );
        }
        assert!(
            naked.is_empty(),
            "evolution breaks with no fixer and no gap row: {naked:?}"
        );
        for g in GAPS {
            assert!(
                evolution_errors().any(|c| c == g.code),
                "{} is a gap row and not an evolution error",
                g.code
            );
        }
    }

    #[test]
    fn todays_breaks_name_their_command() {
        let at = |code| crate::Diagnostic::new(code, String::new(), tatara_lisp::Span::new(0, 0));
        assert_eq!(
            fix_command(&at(Code::B0024), "x.b").as_deref(),
            Some("blue fmt --write x.b")
        );
        for code in [Code::B0012, Code::B0015, Code::B0047, Code::B0021] {
            assert_eq!(
                fix_command(&at(code), "x.b").as_deref(),
                Some("blue check --fix x.b"),
                "{code}"
            );
        }
        assert_eq!(fix_command(&at(Code::B0011), "x.b"), None);
        let carried = at(Code::B0011).with_fix(crate::Fix {
            message: String::new(),
            edits: Vec::new(),
            applicability: crate::Applicability::MachineApplicable,
        });
        assert_eq!(
            fix_command(&carried, "x.b").as_deref(),
            Some("blue check --fix x.b")
        );
    }

    #[test]
    fn the_form_judge_reports_form_only_where_it_judges() {
        assert!(FormJudge::Own.reports(Code::B0015, true));
        assert!(!FormJudge::Own.reports(Code::B0015, false));
        assert!(!FormJudge::None.reports(Code::B0047, true));
        assert!(FormJudge::All.reports(Code::B0015, false));
        assert!(
            FormJudge::Own.reports(Code::B0012, false),
            "B0012 is meaning"
        );
        for judge in [FormJudge::Own, FormJudge::None, FormJudge::All] {
            assert!(judge.reports(Code::B0001, false), "{judge:?} hides meaning");
        }
    }

    #[test]
    fn a_switch_value_outside_its_set_is_refused() {
        assert_eq!(FormJudge::parse(None), Ok(FormJudge::Own));
        assert!(FormJudge::parse(Some("some")).is_err());
        assert_eq!(Layout::parse(Some("rewrite")), Ok(Some(Layout::Rewrite)));
        assert_eq!(Layout::parse(None), Ok(None));
        assert!(Layout::parse(Some("yes")).is_err());
    }
}
