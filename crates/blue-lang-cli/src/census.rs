//! `blue census`: count, over a whole tree, every finding of every rule that
//! is being ratcheted in, and compare each count with its row's `ratchet`.
//!
//! A rule with `ratchet: Some(n)` for `n > 0` is computed on every program
//! and not enforced (`blue_lang_check::Rule::active`); this is where its
//! findings are counted. The census fails unless every count EQUALS its
//! ratchet: a count that rises is a new violation, and a count that falls is
//! progress the row has not recorded yet. Either way the fix is an edit of
//! the number, which a reviewer sees. `checks.namespace-census` runs it over
//! the repository.
//!
//! Each `.b` file is checked as an entry, as `blue check` would, against a
//! load path over every `bidamas/` directory in the tree (blue's own first).
//! A finding in a bidama is seen from every file that imports it, so findings
//! are counted once per (file, position, code).

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use blue_lang_check::{Code, RULES};
use blue_lang_runtime::pipeline::{check_entry, render, Checking};
use blue_lang_runtime::uses::Entry;

/// What the census counted.
pub struct Census {
    /// Files checked.
    pub files: usize,
    /// For each ratcheted code, each distinct finding, rendered.
    pub findings: BTreeMap<Code, BTreeSet<String>>,
}

impl Census {
    /// Every ratcheted rule whose measured count is not its ratchet:
    /// `(code, measured, ratchet)`.
    #[must_use]
    pub fn mismatches(&self) -> Vec<(Code, usize, u32)> {
        RULES
            .iter()
            .filter_map(|r| {
                let ratchet = r.ratchet?;
                let measured = self.findings.get(&r.code).map_or(0, BTreeSet::len);
                (measured != ratchet as usize).then_some((r.code, measured, ratchet))
            })
            .collect()
    }
}

/// Take the census of `root`.
///
/// # Errors
///
/// A file that does not parse or whose imports do not resolve: the census
/// has nothing to count there, and a skipped file would under-count.
pub fn take(root: &Path) -> Result<Census, String> {
    let files = blue_lang_pkg::corpus::files(root);
    let loader = blue_lang_pkg::corpus::load_path(root, &files);
    let mut findings: BTreeMap<Code, BTreeSet<String>> = BTreeMap::new();
    for path in &files {
        let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
        let checked = check_entry(
            Entry {
                path: Some(path),
                text: &text,
            },
            &loader,
            None,
            Checking::WithTests,
        )
        .map_err(|e| format!("{}: {e}", path.display()))?;
        // Enforced findings of a ratcheted rule count too: a rule at
        // `Some(0)` that fires is a count of one, not a pass.
        let ratcheted = |d: &&blue_lang_check::Diagnostic| d.code.rule().ratchet.is_some();
        for d in checked
            .outcome
            .census
            .iter()
            .chain(checked.outcome.diagnostics.iter().filter(ratcheted))
        {
            findings
                .entry(d.code)
                .or_default()
                .insert(render(&checked.program, d));
        }
    }
    Ok(Census {
        files: files.len(),
        findings,
    })
}
