//! `blue check --fix`: every MACHINE-APPLICABLE fix a check found, applied to
//! one file's text. One function, so the CLI's `--fix` and an editor's "fix
//! all" rewrite a file identically.

use crate::{Applicability, Diagnostic, Edit};
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
    let mut edits: Vec<(Span, &str)> = Vec::new();
    let mut applied = 0;
    for d in diagnostics {
        if !in_file(d.top_level) {
            continue;
        }
        for fix in d
            .fixes
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
