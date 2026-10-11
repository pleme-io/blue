//! `blue check --fix`: every MACHINE-APPLICABLE fix a check found, applied to
//! one file's text. One function, so the CLI's `--fix` and an editor's "fix
//! all" rewrite a file identically.

use crate::{Applicability, Diagnostic, Edit, Fix, FixKind};
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
    let (out, applied) = apply_indexed(reported, in_file, text);
    (out, applied.len())
}

/// [`apply_machine_fixes`] for the rules whose fixes only respell the program
/// ([`FixKind::Canonical`]): what `blue run`, `check` and `test` apply before
/// compiling a file, as they apply the formatter. Returns the rewritten text
/// and the index of every diagnostic whose fix was applied, so the door can
/// still report what it fixed.
#[must_use]
pub fn apply_canonical_fixes(
    diagnostics: &[Diagnostic],
    in_file: &dyn Fn(usize) -> bool,
    text: &str,
) -> (String, Vec<usize>) {
    let canonical: Vec<usize> = diagnostics
        .iter()
        .enumerate()
        .filter(|(_, d)| d.code.rule().fix == FixKind::Canonical)
        .map(|(i, _)| i)
        .collect();
    let (out, applied) = apply_indexed(
        canonical
            .iter()
            .map(|i| (diagnostics[*i].top_level, diagnostics[*i].fixes.as_slice())),
        in_file,
        text,
    );
    (out, applied.into_iter().map(|k| canonical[k]).collect())
}

/// The one applier: the position, in `reported`, of every fix it applied.
fn apply_indexed<'a>(
    reported: impl IntoIterator<Item = (usize, &'a [Fix])>,
    in_file: &dyn Fn(usize) -> bool,
    text: &str,
) -> (String, Vec<usize>) {
    let mut edits: Vec<(Span, &str)> = Vec::new();
    let mut applied = Vec::new();
    for (k, (top_level, fixes)) in reported.into_iter().enumerate() {
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
            applied.push(k);
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
