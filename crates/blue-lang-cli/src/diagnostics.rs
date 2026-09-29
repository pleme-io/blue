//! How `blue check` shows what the check stage found: text for a person,
//! JSON Lines for a tool, and `--fix` for the machine-applicable repairs.
//!
//! ## `--format json`: one object per line, per diagnostic
//!
//! The field names are a stable interface; `docs/DIAGNOSTICS.md` documents
//! each one and `tests/check_json.rs` pins the exact output for a fixture, so
//! a rename is a red test rather than a silent break in someone's tool.
//!
//! ```json
//! {"code":"B0001","slug":"unbound-name","severity":"error",
//!  "message":"unbound name `lenght`","file":"f.b",
//!  "line":2,"column":3,"end_line":2,"end_column":9,"byte_start":12,"byte_end":18,
//!  "help":"did you mean `length` (builtin)?","related":[],
//!  "fixes":[{"message":"replace with `length` (builtin)","applicability":"maybe-incorrect",
//!            "edits":[{"file":"f.b","line":2,"column":3,"end_line":2,"end_column":9,
//!                      "byte_start":12,"byte_end":18,"original":"lenght","replacement":"length"}]}],
//!  "waiver":null}
//! ```

use std::path::Path;

use blue_lang_check::{Applicability, Diagnostic, Outcome};
use blue_lang_runtime::uses::{ResolvedProgram, SourceFile};
use blue_lang_syntax::Span;
use serde::Serialize;

/// A position range in one file. Lines and columns are 1-based; columns count
/// characters, not bytes. `byte_start`/`byte_end` are the half-open byte range.
#[derive(Serialize)]
pub struct Location {
    pub file: Option<String>,
    pub line: Option<usize>,
    pub column: Option<usize>,
    pub end_line: Option<usize>,
    pub end_column: Option<usize>,
    pub byte_start: Option<usize>,
    pub byte_end: Option<usize>,
}

impl Location {
    fn of(file: Option<&SourceFile>, span: Span) -> Self {
        let name = file.map(|f| {
            f.path
                .as_ref()
                .map_or_else(|| "<anonymous>".to_string(), |p| p.display().to_string())
        });
        let text = file.map(|f| f.text.as_str());
        match text {
            Some(t) if !span.is_synthetic() && span.end <= t.len() => {
                let (line, column) = Span::line_col(t, span.start);
                let (end_line, end_column) = Span::line_col(t, span.end);
                Self {
                    file: name,
                    line: Some(line),
                    column: Some(column),
                    end_line: Some(end_line),
                    end_column: Some(end_column),
                    byte_start: Some(span.start),
                    byte_end: Some(span.end),
                }
            }
            _ => Self {
                file: name,
                line: None,
                column: None,
                end_line: None,
                end_column: None,
                byte_start: None,
                byte_end: None,
            },
        }
    }
}

#[derive(Serialize)]
pub struct JsonRelated {
    #[serde(flatten)]
    pub at: Location,
    pub message: String,
}

#[derive(Serialize)]
pub struct JsonEdit {
    #[serde(flatten)]
    pub at: Location,
    pub original: String,
    pub replacement: String,
}

#[derive(Serialize)]
pub struct JsonFix {
    pub message: String,
    pub applicability: &'static str,
    pub edits: Vec<JsonEdit>,
}

#[derive(Serialize)]
pub struct JsonWaiver {
    pub reason: String,
    pub line: Option<usize>,
}

/// One line of `blue check --format json`.
#[derive(Serialize)]
pub struct JsonDiagnostic {
    pub code: &'static str,
    pub slug: &'static str,
    pub severity: &'static str,
    pub message: String,
    #[serde(flatten)]
    pub at: Location,
    pub help: Option<String>,
    pub related: Vec<JsonRelated>,
    pub fixes: Vec<JsonFix>,
    /// Set when an in-source waiver suppressed this diagnostic.
    pub waiver: Option<JsonWaiver>,
}

fn file_of(program: &ResolvedProgram, top_level: usize) -> Option<&SourceFile> {
    program.owner_of(top_level).and_then(|id| program.file(id))
}

/// A diagnostic as its JSON object.
#[must_use]
pub fn to_json(
    program: &ResolvedProgram,
    d: &Diagnostic,
    waiver: Option<JsonWaiver>,
) -> JsonDiagnostic {
    let file = file_of(program, d.top_level);
    let rule = d.code.rule();
    JsonDiagnostic {
        code: d.code.as_str(),
        slug: rule.slug,
        severity: d.severity.label(),
        message: d.message.clone(),
        at: Location::of(file, d.span),
        help: d.help.clone(),
        related: d
            .related
            .iter()
            .map(|r| JsonRelated {
                at: Location::of(file, r.span),
                message: r.message.clone(),
            })
            .collect(),
        fixes: d
            .fixes
            .iter()
            .map(|f| JsonFix {
                message: f.message.clone(),
                applicability: f.applicability.label(),
                edits: f
                    .edits
                    .iter()
                    .map(|e| JsonEdit {
                        at: Location::of(file, e.span),
                        original: e.original.clone(),
                        replacement: e.replacement.clone(),
                    })
                    .collect(),
            })
            .collect(),
        waiver,
    }
}

/// Every diagnostic in `outcome` — reported and waived — as JSON Lines.
///
/// # Errors
///
/// Serialisation cannot fail for these types; the `Result` is serde's.
pub fn json_lines(program: &ResolvedProgram, outcome: &Outcome) -> serde_json::Result<String> {
    let mut out = String::new();
    for d in &outcome.diagnostics {
        out.push_str(&serde_json::to_string(&to_json(program, d, None))?);
        out.push('\n');
    }
    for w in &outcome.waived {
        let file = file_of(program, w.waiver.top_level);
        let line = file.map(|f| Span::line_col(&f.text, w.waiver.span.start).0);
        let waiver = JsonWaiver {
            reason: w.waiver.reason.clone(),
            line,
        };
        out.push_str(&serde_json::to_string(&to_json(
            program,
            &w.diagnostic,
            Some(waiver),
        ))?);
        out.push('\n');
    }
    Ok(out)
}

/// A syntax error, which has no resolved program behind it, as JSON.
///
/// # Errors
///
/// As [`json_lines`].
pub fn syntax_json(path: &Path, text: &str, d: &Diagnostic) -> serde_json::Result<String> {
    let file = SourceFile {
        id: ResolvedProgram::ENTRY,
        path: Some(path.to_path_buf()),
        package: None,
        text: text.to_string(),
    };
    let rule = d.code.rule();
    let j = JsonDiagnostic {
        code: d.code.as_str(),
        slug: rule.slug,
        severity: d.severity.label(),
        message: d.message.clone(),
        at: Location::of(Some(&file), d.span),
        help: d.help.clone(),
        related: Vec::new(),
        fixes: Vec::new(),
        waiver: None,
    };
    let mut s = serde_json::to_string(&j)?;
    s.push('\n');
    Ok(s)
}

/// Apply every MACHINE-APPLICABLE fix whose edits land in the entry file.
///
/// An edit applies only when its span still holds `original`, and only when it
/// overlaps no edit already taken; the rest are skipped, never forced. Returns
/// the rewritten text and the number of fixes applied.
#[must_use]
pub fn apply_machine_fixes(
    program: &ResolvedProgram,
    outcome: &Outcome,
    text: &str,
) -> (String, usize) {
    let mut edits: Vec<(Span, &str)> = Vec::new();
    let mut applied = 0;
    for d in &outcome.diagnostics {
        if program.owner_of(d.top_level) != Some(ResolvedProgram::ENTRY) {
            continue;
        }
        for fix in d
            .fixes
            .iter()
            .filter(|f| f.applicability == Applicability::MachineApplicable)
        {
            let fits = fix.edits.iter().all(|e| {
                text.get(e.span.start..e.span.end) == Some(e.original.as_str())
                    && !edits
                        .iter()
                        .any(|(s, _)| e.span.start < s.end && s.start < e.span.end)
            });
            if !fits {
                continue;
            }
            edits.extend(fix.edits.iter().map(|e| (e.span, e.replacement.as_str())));
            applied += 1;
            // One fix per diagnostic: the best one.
            break;
        }
    }
    edits.sort_by_key(|(s, _)| std::cmp::Reverse(s.start));
    let mut out = text.to_string();
    for (span, replacement) in edits {
        out.replace_range(span.start..span.end, replacement);
    }
    (out, applied)
}
