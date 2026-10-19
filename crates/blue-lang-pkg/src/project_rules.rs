//! The project pass of `blue check`: find a file's project rules, run them,
//! and turn what they report into findings against the file's source.
//!
//! **Which rules apply.** Every `rule(code, file, def)` of every Bluefile in
//! the checked file's directory and its ancestors, up to the repository root
//! (the first directory holding `.git`), so a rule the project root declares
//! covers every package under it. A code declared twice is refused, naming
//! both Bluefiles.
//!
//! **How they run.** Each rule file is loaded once under the rule frame
//! (`blue_lang_runtime::project_rules`), and each rule is called on each
//! top-level form of the checked file. A path a rule reports is resolved to
//! a span in the form it was given. A `fix` tree is rendered by the formatter
//! and proved before it is offered as machine-applicable: the edit is applied
//! to a copy of the file, the copy is parsed, and the node at the same path
//! must be exactly the rule's tree; when it is not (an operator binding
//! differently in its new place), the rendering is tried in parentheses, and
//! failing that the fix is offered as maybe-incorrect, which `--fix` leaves.
//!
//! **What a rule cannot do** is stop the check: a rule that will not load,
//! reaches outside its frame, raises, runs past its budget or returns a
//! malformed value is a [`Failure`], reported once with its code (the rule is
//! not run on the file's remaining forms) and counted as an error, while every
//! other rule's findings are still reported.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use blue_lang_check::project::{
    apply_waivers, Finding, ProjectCode, ProjectCodeError, WaivedFinding,
};
use blue_lang_check::{Applicability, Diagnostic, Edit, Fix, Severity};
use blue_lang_runtime::project_rules::{RawFinding, RuleFailure, RuleProgram};
use blue_lang_runtime::uses::{Entry, Loader, ResolvedProgram};
use tatara_lisp::{Sexp, Span, Spanned, SpannedForm};

use crate::bluefile::{read_bluefile, BluefileError, MANIFEST_FILE};

/// A rule a Bluefile declares, with its file resolved.
#[derive(Clone, Debug, PartialEq)]
pub struct Declared {
    pub code: ProjectCode,
    pub def: String,
    pub severity: Severity,
    /// The rule file, joined onto the declaring Bluefile's directory.
    pub file: PathBuf,
    /// The Bluefile that declares it.
    pub bluefile: PathBuf,
}

/// Why the rules for a file could not be found.
#[derive(Debug, thiserror::Error)]
pub enum DiscoverError {
    #[error("{path}: {source}")]
    Read {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("{path}: {source}")]
    Bluefile {
        path: PathBuf,
        #[source]
        source: BluefileError,
    },
    #[error("{path}: {source}")]
    Code {
        path: PathBuf,
        #[source]
        source: ProjectCodeError,
    },
    #[error("project rule {code} is declared by both {first} and {second}")]
    Twice {
        code: ProjectCode,
        first: PathBuf,
        second: PathBuf,
    },
}

/// The project rules that apply to `file`, sorted by code.
///
/// # Errors
///
/// A Bluefile on the way up that cannot be read, or a code two of them
/// declare.
pub fn discover(file: &Path) -> Result<Vec<Declared>, DiscoverError> {
    let absolute = std::path::absolute(file).map_err(|source| DiscoverError::Read {
        path: file.to_path_buf(),
        source,
    })?;
    let mut found: Vec<Declared> = Vec::new();
    let mut dir = absolute.parent();
    while let Some(d) = dir {
        let bluefile = d.join(MANIFEST_FILE);
        if bluefile.is_file() {
            let text =
                std::fs::read_to_string(&bluefile).map_err(|source| DiscoverError::Read {
                    path: bluefile.clone(),
                    source,
                })?;
            let manifest = read_bluefile(&text).map_err(|source| DiscoverError::Bluefile {
                path: bluefile.clone(),
                source,
            })?;
            for (code, rule) in manifest.project.rules {
                let code = ProjectCode::parse(&code).map_err(|source| DiscoverError::Code {
                    path: bluefile.clone(),
                    source,
                })?;
                if let Some(first) = found.iter().find(|r| r.code == code) {
                    return Err(DiscoverError::Twice {
                        code,
                        first: first.bluefile.clone(),
                        second: bluefile,
                    });
                }
                found.push(Declared {
                    code,
                    def: rule.def,
                    severity: if rule.severity == "warning" {
                        Severity::Warning
                    } else {
                        Severity::Error
                    },
                    file: d.join(&rule.file),
                    bluefile: bluefile.clone(),
                });
            }
        }
        if d.join(".git").exists() {
            break;
        }
        dir = d.parent();
    }
    found.sort_by(|a, b| a.code.cmp(&b.code));
    Ok(found)
}

/// A rule that produced nothing, and why.
#[derive(Clone, Debug, PartialEq)]
pub struct Failure {
    pub code: ProjectCode,
    pub rule: String,
    pub source: PathBuf,
    /// The form it failed on; `None` when its program never loaded.
    pub top_level: Option<usize>,
    pub failure: RuleFailure,
}

/// What the project pass found in one file.
#[derive(Clone, Debug, Default)]
pub struct Outcome {
    pub findings: Vec<Finding>,
    pub waived: Vec<WaivedFinding>,
    /// Malformed, undeclared and unused project waivers (B0007, B0008).
    pub diagnostics: Vec<Diagnostic>,
    pub failures: Vec<Failure>,
}

impl Outcome {
    /// No error-severity finding, no waiver error and no failed rule.
    #[must_use]
    pub fn ok(&self) -> bool {
        !self.findings.iter().any(Finding::is_error)
            && !self.diagnostics.iter().any(Diagnostic::is_error)
            && self.failures.is_empty()
    }
}

/// Run `rules` over the entry file of `program`, each call bounded by
/// `steps`.
#[must_use]
pub fn check(
    program: &ResolvedProgram,
    explicit: &[Spanned],
    rules: &[Declared],
    loader: &dyn Loader,
    steps: usize,
) -> Outcome {
    let mut out = Outcome::default();
    // With no rules there is no project pass, and a waiver of a project code
    // is left alone, as the check stage leaves it: a package checked by
    // itself (`mkBidama` in the sandbox) has no Bluefile above it naming the
    // root's rules.
    if rules.is_empty() {
        return out;
    }
    let Some(entry) = program.file(ResolvedProgram::ENTRY) else {
        return out;
    };
    let forms: Vec<(usize, &Spanned)> = explicit
        .iter()
        .enumerate()
        .filter(|(i, _)| program.owner_of(*i) == Some(ResolvedProgram::ENTRY))
        .collect();
    let mut failed: BTreeSet<ProjectCode> = BTreeSet::new();
    let files: BTreeSet<&PathBuf> = rules.iter().map(|r| &r.file).collect();
    for file in files {
        let mine: Vec<&Declared> = rules.iter().filter(|r| &r.file == file).collect();
        let fail_all = |out: &mut Outcome, failed: &mut BTreeSet<ProjectCode>, f: RuleFailure| {
            for r in &mine {
                failed.insert(r.code.clone());
                out.failures.push(Failure {
                    code: r.code.clone(),
                    rule: r.def.clone(),
                    source: file.clone(),
                    top_level: None,
                    failure: f.clone(),
                });
            }
        };
        let text = match std::fs::read_to_string(file) {
            Ok(t) => t,
            Err(e) => {
                fail_all(&mut out, &mut failed, RuleFailure::Load(e.to_string()));
                continue;
            }
        };
        let mut program_of_rules = match RuleProgram::load(
            Entry {
                path: Some(file),
                text: &text,
            },
            loader,
            steps,
        ) {
            Ok(p) => p,
            Err(f) => {
                fail_all(&mut out, &mut failed, f);
                continue;
            }
        };
        for rule in mine {
            for (k, (top_level, form)) in forms.iter().enumerate() {
                let reported = program_of_rules
                    .run(&rule.def, form, steps)
                    .and_then(|raw| {
                        raw.into_iter()
                            .map(|r| resolve(rule, &entry.text, k, *top_level, form, r))
                            .collect::<Result<Vec<Finding>, RuleFailure>>()
                    });
                match reported {
                    Ok(found) => out.findings.extend(found),
                    Err(failure) => {
                        failed.insert(rule.code.clone());
                        out.failures.push(Failure {
                            code: rule.code.clone(),
                            rule: rule.def.clone(),
                            source: file.clone(),
                            top_level: Some(*top_level),
                            failure,
                        });
                        break;
                    }
                }
            }
        }
    }
    let spans: Vec<(usize, Span)> = forms.iter().map(|(i, f)| (*i, f.span)).collect();
    let (waivers, malformed) = blue_lang_check::waiver::collect_project(&entry.text, &spans);
    out.diagnostics.extend(malformed);
    let declared = |c: &ProjectCode| rules.iter().any(|r| &r.code == c);
    let ran = |c: &ProjectCode| !failed.contains(c);
    let (waived, reported) = apply_waivers(&mut out.findings, waivers, &declared, &ran);
    out.waived = waived;
    out.diagnostics.extend(reported);
    out.findings
        .sort_by(|a, b| (a.top_level, a.span.start).cmp(&(b.top_level, b.span.start)));
    out
}

/// The node `path` names inside `form`: a list's child by index, and for a
/// quote form (data `(quote x)`) index 1 is the quoted node.
fn node_at<'a>(form: &'a Spanned, path: &[usize]) -> Option<&'a Spanned> {
    let Some((first, rest)) = path.split_first() else {
        return Some(form);
    };
    match &form.form {
        SpannedForm::List(items) => node_at(items.get(*first)?, rest),
        SpannedForm::Quote(inner)
        | SpannedForm::Quasiquote(inner)
        | SpannedForm::Unquote(inner)
        | SpannedForm::UnquoteSplice(inner)
            if *first == 1 =>
        {
            node_at(inner, rest)
        }
        _ => None,
    }
}

fn resolve(
    rule: &Declared,
    text: &str,
    entry_index: usize,
    top_level: usize,
    form: &Spanned,
    raw: RawFinding,
) -> Result<Finding, RuleFailure> {
    let node = node_at(form, &raw.at).ok_or_else(|| {
        RuleFailure::Shape(format!(
            "an `at` of {:?}, which names no node of the form",
            raw.at
        ))
    })?;
    let fixes = raw
        .fix
        .map(|tree| fix_for(text, entry_index, &raw.at, node.span, &tree))
        .into_iter()
        .collect();
    Ok(Finding {
        code: rule.code.clone(),
        rule: rule.def.clone(),
        severity: rule.severity,
        message: raw.message,
        span: node.span,
        top_level,
        help: raw.help,
        fixes,
    })
}

/// The edit that writes `tree` over `span`, machine-applicable only when the
/// edited file is proven to hold exactly `tree` at `path`.
fn fix_for(text: &str, entry_index: usize, path: &[usize], span: Span, tree: &Sexp) -> Fix {
    let rendered = blue_lang_fmt::format_forms(std::slice::from_ref(tree))
        .trim_end()
        .to_string();
    let original = text
        .get(span.start..span.end)
        .unwrap_or_default()
        .to_string();
    let proves = |replacement: &str| {
        let mut edited = text.to_string();
        edited.replace_range(span.start..span.end, replacement);
        blue_lang_syntax::parse_program_tree(&edited)
            .ok()
            .and_then(|forms| {
                let form = forms.get(entry_index)?;
                node_at(form, path).map(|n| n.to_sexp() == *tree)
            })
            .unwrap_or(false)
    };
    let parenthesised = format!("({rendered})");
    let (replacement, applicability) = if proves(&rendered) {
        (rendered, Applicability::MachineApplicable)
    } else if proves(&parenthesised) {
        (parenthesised, Applicability::MachineApplicable)
    } else {
        (rendered, Applicability::MaybeIncorrect)
    };
    Fix {
        message: format!("replace with `{replacement}`"),
        edits: vec![Edit {
            span,
            original,
            replacement,
        }],
        applicability,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tree(src: &str) -> Spanned {
        blue_lang_syntax::parse_program_tree(src).unwrap().remove(0)
    }

    #[test]
    fn a_path_names_a_node_and_an_absent_one_names_none() {
        let f = tree("f(g(1), 2)\n");
        assert_eq!(
            node_at(&f, &[1, 1])
                .map(Spanned::to_sexp)
                .map(|s| s.to_string()),
            Some("1".into())
        );
        assert!(node_at(&f, &[5]).is_none());
        assert!(node_at(&f, &[2, 0]).is_none());
        assert_eq!(node_at(&f, &[]).map(|n| n.span), Some(f.span));
    }

    /// A fix is machine-applicable only once the edited file proves it; an
    /// operator that would bind differently in place is parenthesised.
    ///
    /// Red run (2026-10-10): the parenthesised retry removed: the second fix
    /// was `![] == nil`, maybe-incorrect, and the assertion on its
    /// applicability failed.
    #[test]
    fn a_fix_is_proved_by_reparsing_and_parenthesised_when_it_must_be() {
        let text = "def f(x)\n  nil?(x)\nend\n";
        let f = tree(text);
        let node = node_at(&f, &[2]).unwrap();
        let want = tree("x == nil\n").to_sexp();
        let fix = fix_for(text, 0, &[2], node.span, &want);
        assert_eq!(fix.applicability, Applicability::MachineApplicable);
        assert_eq!(fix.edits[0].replacement, "x == nil");
        assert_eq!(fix.edits[0].original, "nil?(x)");

        let text = "def f()\n  !nil?([])\nend\n";
        let f = tree(text);
        let node = node_at(&f, &[2, 1]).unwrap();
        let want = tree("[] == nil\n").to_sexp();
        let fix = fix_for(text, 0, &[2, 1], node.span, &want);
        assert_eq!(fix.applicability, Applicability::MachineApplicable);
        assert_eq!(fix.edits[0].replacement, "([] == nil)");
    }

    #[test]
    fn a_fix_that_cannot_be_proved_is_maybe_incorrect() {
        let text = "def f(x)\n  g(x)\nend\n";
        let f = tree(text);
        let node = node_at(&f, &[2]).unwrap();
        let want = Sexp::List(vec![Sexp::symbol("not a name"), Sexp::symbol("x")]);
        let fix = fix_for(text, 0, &[2], node.span, &want);
        assert_eq!(fix.applicability, Applicability::MaybeIncorrect);
    }
}
