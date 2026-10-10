//! Project rules: check rules a project writes in blue and names in its
//! Bluefile.
//!
//! The registry ([`crate::RULES`]) is closed: its codes are `B` + four digits,
//! each with a law, an explanation and a witness compiled into blue. A project
//! states its own rules the way it states every other build fact, as a
//! Bluefile word:
//!
//! ```text
//! rule("R0001", "rules/okite.b", "nil_predicate")
//! ```
//!
//! The definition receives each top-level form of a checked file as data and
//! returns findings; `blue check` runs it under a pure frame and a step budget
//! (`blue_lang_runtime::project_rules`). This module owns what such a rule
//! produces once it is back in Rust: its code ([`ProjectCode`]), its findings
//! ([`Finding`]), and how the one waiver grammar applies to them
//! ([`apply_waivers`]).
//!
//! **A project code is never a registry code.** `B` + four digits belongs to
//! blue; a project code is one to four capital letters other than a lone `B`,
//! then four digits (`R0001`, `KZ0003`). The two sets are disjoint by shape,
//! so `# waive CODE: reason` names one or the other without a lookup, and the
//! check stage, which runs no project rule, leaves a project waiver to the
//! door that does.

use std::fmt;

use tatara_lisp::Span;

use crate::rules::{Code, Severity};
use crate::{Diagnostic, Fix};

/// A project rule's code: one to four capital letters (never `B` alone), then
/// four digits.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ProjectCode(String);

/// Why a string is not a [`ProjectCode`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProjectCodeError {
    /// Not letters then four digits.
    Shape(String),
    /// `B` + four digits: the registry's codes.
    Registry(String),
}

impl fmt::Display for ProjectCodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ProjectCodeError::Shape(s) => write!(
                f,
                "`{s}` is not a project rule code: one to four capital letters, then four digits (`R0001`)"
            ),
            ProjectCodeError::Registry(s) => write!(
                f,
                "`{s}` is a registry code: `B` + four digits belongs to blue's own rules; a project prefixes its codes with other letters"
            ),
        }
    }
}

impl std::error::Error for ProjectCodeError {}

impl ProjectCode {
    /// Parse `R0001`.
    ///
    /// # Errors
    ///
    /// [`ProjectCodeError::Registry`] for a `B` + four digits code,
    /// [`ProjectCodeError::Shape`] for anything else that is not letters then
    /// four digits.
    pub fn parse(s: &str) -> Result<ProjectCode, ProjectCodeError> {
        let letters = s.chars().take_while(char::is_ascii_uppercase).count();
        let digits = &s[letters..];
        let shaped = (1..=4).contains(&letters)
            && digits.len() == 4
            && digits.chars().all(|c| c.is_ascii_digit());
        if !shaped {
            return Err(ProjectCodeError::Shape(s.to_string()));
        }
        if &s[..letters] == "B" {
            return Err(ProjectCodeError::Registry(s.to_string()));
        }
        Ok(ProjectCode(s.to_string()))
    }

    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for ProjectCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// What a project rule reported, with its span resolved in the checked file.
///
/// The same shape as a registry [`Diagnostic`], and the same [`Fix`] type, so
/// `--fix`, the JSON lines and the text rendering treat both alike. The code
/// is the Bluefile row's, never the rule's own choice: one row is one code,
/// as in the registry.
#[derive(Clone, Debug, PartialEq)]
pub struct Finding {
    pub code: ProjectCode,
    /// The definition that reported it.
    pub rule: String,
    pub severity: Severity,
    pub message: String,
    pub span: Span,
    /// The top-level form it arose in, as [`Diagnostic::top_level`].
    pub top_level: usize,
    pub help: Option<String>,
    pub fixes: Vec<Fix>,
}

impl Finding {
    #[must_use]
    pub fn is_error(&self) -> bool {
        self.severity == Severity::Error
    }

    /// The slug a reader sees: the definition's name, kebab-cased like a
    /// registry slug.
    #[must_use]
    pub fn slug(&self) -> String {
        self.rule.replace('_', "-")
    }
}

impl fmt::Display for Finding {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}[{}]: {}", self.severity, self.code, self.message)
    }
}

/// A `# waive CODE: reason` comment naming a project code, attached to the
/// top-level form below it exactly as a registry waiver is.
#[derive(Clone, Debug, PartialEq)]
pub struct ProjectWaiver {
    pub code: ProjectCode,
    pub reason: String,
    pub span: Span,
    pub top_level: usize,
}

/// A finding a waiver suppressed.
#[derive(Clone, Debug, PartialEq)]
pub struct WaivedFinding {
    pub finding: Finding,
    pub waiver: ProjectWaiver,
}

/// Move every finding a waiver covers into the returned list, and report a
/// waiver naming a code no project rule declares as
/// [`B0007`](Code::B0007) and one that covered nothing as
/// [`B0008`](Code::B0008).
///
/// `declared` says whether a project rule has the code. A rule that failed to
/// run reported nothing, so its waivers are not reported unused:
/// `ran(code)` says whether the code's rule ran to the end on every form.
pub fn apply_waivers(
    findings: &mut Vec<Finding>,
    waivers: Vec<ProjectWaiver>,
    declared: &dyn Fn(&ProjectCode) -> bool,
    ran: &dyn Fn(&ProjectCode) -> bool,
) -> (Vec<WaivedFinding>, Vec<Diagnostic>) {
    let mut waived = Vec::new();
    let mut reported = Vec::new();
    for w in waivers {
        if !declared(&w.code) {
            reported.push(
                Diagnostic::new(
                    Code::B0007,
                    format!("no project rule has the code {}", w.code),
                    w.span,
                )
                .at_top_level(w.top_level)
                .with_help("the Bluefile's `rule(code, file, def)` rows name the project's codes"),
            );
            continue;
        }
        let (hit, keep): (Vec<Finding>, Vec<Finding>) = std::mem::take(findings)
            .into_iter()
            .partition(|f| f.code == w.code && f.top_level == w.top_level);
        *findings = keep;
        if hit.is_empty() {
            if ran(&w.code) {
                reported.push(
                    Diagnostic::new(
                        Code::B0008,
                        format!("this waiver of {} suppresses nothing", w.code),
                        w.span,
                    )
                    .at_top_level(w.top_level)
                    .with_help("delete it"),
                );
            }
            continue;
        }
        for finding in hit {
            waived.push(WaivedFinding {
                finding,
                waiver: w.clone(),
            });
        }
    }
    (waived, reported)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_project_code_is_letters_then_four_digits_and_never_a_registry_code() {
        for ok in ["R0001", "KZ0003", "ABCD9999"] {
            assert_eq!(ProjectCode::parse(ok).map(|c| c.to_string()), Ok(ok.into()));
        }
        for shape in ["R001", "R00001", "r0001", "ABCDE0001", "0001", "R-0001", ""] {
            assert!(
                matches!(ProjectCode::parse(shape), Err(ProjectCodeError::Shape(_))),
                "{shape}"
            );
        }
        assert!(matches!(
            ProjectCode::parse("B0001"),
            Err(ProjectCodeError::Registry(_))
        ));
        assert!(ProjectCode::parse("BR0001").is_ok());
    }

    fn finding(code: &str, top_level: usize) -> Finding {
        Finding {
            code: ProjectCode::parse(code).unwrap(),
            rule: "r".into(),
            severity: Severity::Error,
            message: "m".into(),
            span: Span::new(0, 1),
            top_level,
            help: None,
            fixes: Vec::new(),
        }
    }

    fn waiver(code: &str, top_level: usize) -> ProjectWaiver {
        ProjectWaiver {
            code: ProjectCode::parse(code).unwrap(),
            reason: "why".into(),
            span: Span::new(0, 1),
            top_level,
        }
    }

    #[test]
    fn a_waiver_moves_only_its_code_in_its_form() {
        let mut fs = vec![
            finding("R0001", 1),
            finding("R0001", 2),
            finding("R0002", 1),
        ];
        let (waived, reported) =
            apply_waivers(&mut fs, vec![waiver("R0001", 1)], &|_| true, &|_| true);
        assert_eq!(waived.len(), 1);
        assert!(reported.is_empty());
        let left: Vec<(String, usize)> = fs
            .iter()
            .map(|f| (f.code.to_string(), f.top_level))
            .collect();
        assert_eq!(left, vec![("R0001".into(), 2), ("R0002".into(), 1)]);
    }

    #[test]
    fn an_undeclared_or_unused_project_waiver_is_reported() {
        let mut fs = Vec::new();
        let (_, reported) = apply_waivers(
            &mut fs,
            vec![waiver("R0001", 0), waiver("R0009", 0)],
            &|c| c.as_str() == "R0001",
            &|_| true,
        );
        let codes: Vec<Code> = reported.iter().map(|d| d.code).collect();
        assert_eq!(codes, vec![Code::B0008, Code::B0007]);
        let (_, quiet) = apply_waivers(&mut fs, vec![waiver("R0001", 0)], &|_| true, &|_| false);
        assert!(
            quiet.is_empty(),
            "a rule that failed reports no unused waiver"
        );
    }
}
