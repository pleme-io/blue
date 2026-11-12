//! `blue check --fix`: every MACHINE-APPLICABLE fix a check found, applied to
//! one file's text. One function, so the CLI's `--fix` and an editor's "fix
//! all" rewrite a file identically.

use crate::{Applicability, Diagnostic, Edit, Fix};
use tatara_lisp::Span;

/// Apply every machine-applicable fix of `diagnostics` whose diagnostic
/// `in_file` says belongs to `text`'s file, by top-level index.
///
/// An edit applies only when its span still holds `original`, and only when it
/// overlaps no edit already taken; the rest are skipped, never forced. Returns
/// the rewritten text and the number of fixes applied.
#[must_use]
pub fn apply_machine_fixes(
    diagnostics: &[Diagnostic],
    in_file: &dyn Fn(usize) -> bool,
    text: &str,
) -> (String, usize) {
    apply_fixes(
        diagnostics
            .iter()
            .map(|d| (d.top_level, d.fixes.as_slice())),
        in_file,
        text,
    )
}

/// [`apply_machine_fixes`] over any reported fixes, each with the top-level
/// form it arose in: a registry diagnostic's, or a project rule's finding's.
#[must_use]
pub fn apply_fixes<'a>(
    reported: impl IntoIterator<Item = (usize, &'a [Fix])>,
    in_file: &dyn Fn(usize) -> bool,
    text: &str,
) -> (String, usize) {
    let mut edits: Vec<(Span, &str)> = Vec::new();
    let mut applied = 0;
    for (top_level, fixes) in reported {
        if !in_file(top_level) {
            continue;
        }
        for fix in fixes
            .iter()
            .filter(|f| f.applicability == Applicability::MachineApplicable)
        {
            // An edit another fix already queued, exactly (two moved names
            // adding the same `use`), is shared rather than a conflict.
            let queued = |e: &Edit, edits: &[(Span, &str)]| {
                edits
                    .iter()
                    .any(|(s, r)| *s == e.span && *r == e.replacement.as_str())
            };
            let fits = fix.edits.iter().all(|e| {
                queued(e, &edits)
                    || (text.get(e.span.start..e.span.end) == Some(e.original.as_str())
                        && !edits
                            .iter()
                            .any(|(s, _)| e.span.start < s.end && s.start < e.span.end))
            });
            if !fits {
                continue;
            }
            for e in &fix.edits {
                if !queued(e, &edits) {
                    edits.push((e.span, e.replacement.as_str()));
                }
            }
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

/// What a rewrite fix says it does.
pub const REWRITE: &str = "rewrite the file as `blue fmt --write` writes it";

/// Give each diagnostic `in_file` of a rule whose fix is the formatter's, and
/// that carries no edit of its own, one machine-applicable fix: a single edit
/// that replaces `text` with `rewritten`, the file as `blue fmt --write`
/// writes it. So every such diagnostic carries a concrete edit a reader can
/// apply from the diagnostic alone. Nothing is added when `rewritten` is
/// `text`.
pub fn complete_with_rewrite(
    diagnostics: &mut [Diagnostic],
    in_file: &dyn Fn(usize) -> bool,
    text: &str,
    rewritten: &str,
) {
    if rewritten == text {
        return;
    }
    for d in diagnostics.iter_mut() {
        if d.code.rule().fix != crate::FixKind::Machine
            || !in_file(d.top_level)
            || d.fixes.iter().any(|f| !f.edits.is_empty())
        {
            continue;
        }
        d.fixes.push(Fix {
            message: REWRITE.to_string(),
            edits: vec![Edit {
                span: Span::new(0, text.len()),
                original: text.to_string(),
                replacement: rewritten.to_string(),
            }],
            applicability: Applicability::MachineApplicable,
        });
    }
}

/// The census of rules (HORIZON H9), whose diagnostic does not yet carry a complete
/// repair: a fix whose edits, applied to the rule's own witness, clear it. It
/// only shrinks: a rule that gains a repair must leave this list, and a new
/// rule must arrive with one (`every_rule_outside_the_census_is_repaired_by_its_own_diagnostic` in
/// `blue-lang-pkg/tests/autofix.rs` holds the list exact).
pub const REPAIR_CENSUS: &[crate::Code] = &[
    crate::Code::B0003,
    crate::Code::B0004,
    crate::Code::B0005,
    crate::Code::B0006,
    crate::Code::B0007,
    crate::Code::B0008,
    crate::Code::B0009,
    crate::Code::B0010,
    crate::Code::B0013,
    crate::Code::B0014,
    crate::Code::B0017,
    crate::Code::B0019,
    crate::Code::B0020,
    crate::Code::B0022,
    crate::Code::B0038,
    crate::Code::B0039,
    crate::Code::B0040,
    crate::Code::B0050,
    crate::Code::B0051,
    crate::Code::B0052,
    crate::Code::B0053,
    crate::Code::B0056,
    crate::Code::B0057,
    crate::Code::B0058,
    crate::Code::B0059,
    crate::Code::B0061,
    crate::Code::B0062,
    crate::Code::B0069,
    crate::Code::B0071,
    crate::Code::B0072,
    crate::Code::B0073,
    crate::Code::B0079,
    crate::Code::B0080,
    crate::Code::B0081,
    crate::Code::B0082,
];
