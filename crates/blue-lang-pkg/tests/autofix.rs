use blue_lang_check::{Code, FixKind, RULES};
use blue_lang_runtime::pipeline::{check_entry, form_diagnostics, syntax_diagnostic, Checking};
use blue_lang_runtime::uses::{Entry, Loader};
use std::path::Path;

const FIRST_SPELLING_RULE: &str = "B0023";

struct Imports(
    &'static [(&'static str, &'static str)],
    Option<&'static str>,
    Option<&'static str>,
);

impl Loader for Imports {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        self.0
            .iter()
            .find(|(n, _)| *n == name)
            .map(|(n, src)| vec![(format!("{n}.b"), (*src).to_string())])
            .ok_or_else(|| format!("no bidama named \"{name}\""))
    }

    fn needs(
        &self,
        _package: &str,
        _entry_dir: Option<&Path>,
    ) -> Option<std::collections::BTreeSet<String>> {
        Some(std::collections::BTreeSet::new())
    }

    fn version(&self, _package: &str, _entry_dir: Option<&Path>) -> Option<String> {
        Some("0.1.1".to_string())
    }

    fn entry_package(&self, _path: &Path) -> Option<String> {
        self.2.map(str::to_string)
    }

    fn frontend(&self, _entry: &Path) -> Option<blue_lang_runtime::uses::Frontend> {
        self.1.map(|t| blue_lang_runtime::uses::Frontend {
            table: Some(("schema.table".to_string(), t.to_string())),
            view: true,
        })
    }
}

fn codes(src: &str, loader: &Imports) -> Vec<Code> {
    if let Some(d) = syntax_diagnostic(src) {
        return vec![d.code];
    }
    let Ok(checked) = check_entry(
        Entry {
            path: Some(Path::new("witness.b")),
            text: src,
        },
        loader,
        None,
        Checking::WithTests,
    ) else {
        return Vec::new();
    };
    checked
        .outcome
        .diagnostics
        .iter()
        .chain(&checked.outcome.census)
        .chain(&form_diagnostics(src))
        .map(|d| d.code)
        .collect()
}

#[test]
fn every_machine_fixed_spelling_rule_is_fixed_by_fmt_write() {
    let mut failures = Vec::new();
    for r in RULES.iter().filter(|r| {
        r.fix == FixKind::Machine
            && r.code.as_str() >= FIRST_SPELLING_RULE
            && !blue_lang_check::data_laws::CODES.contains(&r.code)
            && r.package.is_none()
    }) {
        let loader = Imports(r.imports, r.frontend, None);
        let path = Path::new("witness.b");
        let written = match blue_lang_pkg::canonical::format_with(&loader, path, r.witness) {
            Ok(w) => w,
            Err(e) => {
                failures.push(format!("{}: fmt refused the witness: {e}", r.code));
                continue;
            }
        };
        if written.trim_end() == r.witness.trim_end() {
            failures.push(format!(
                "{}: fmt --write left the witness unchanged",
                r.code
            ));
            continue;
        }
        let after = codes(&written, &loader);
        if after.contains(&r.code) {
            failures.push(format!(
                "{}: still fires after fmt --write: {after:?}\n{written}",
                r.code
            ));
        }
        let again = blue_lang_pkg::canonical::format_with(&loader, path, &written)
            .unwrap_or_else(|e| panic!("{}: second fmt refused: {e}", r.code));
        if again.trim_end() != written.trim_end() {
            failures.push(format!(
                "{}: fmt --write is not idempotent on its witness:\n{written}---\n{again}",
                r.code
            ));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn a_refused_rule_offers_no_rewrite_of_its_witness() {
    for r in RULES.iter().filter(|r| r.fix == FixKind::None) {
        let loader = Imports(r.imports, r.frontend, r.package);
        let Ok(written) =
            blue_lang_pkg::canonical::format_with(&loader, Path::new("witness.b"), r.witness)
        else {
            continue;
        };
        assert!(
            codes(&written, &loader).contains(&r.code),
            "{}: a rule with no fix stopped firing after fmt --write",
            r.code
        );
    }
}

fn diagnostics(src: &str, loader: &Imports) -> Vec<blue_lang_check::Diagnostic> {
    check_entry(
        Entry {
            path: Some(Path::new("witness.b")),
            text: src,
        },
        loader,
        None,
        Checking::WithTests,
    )
    .map(|c| c.outcome.diagnostics)
    .unwrap_or_else(|e| panic!("{src:?}: {e}"))
}

#[test]
fn every_carried_machine_fix_repairs_its_witness() {
    let mut failures = Vec::new();
    let mut seen = 0;
    for r in RULES.iter().filter(|r| r.fixes.is_some()) {
        seen += 1;
        let src = r.fixes.unwrap_or_default();
        let loader = Imports(r.imports, r.frontend, r.package);
        let path = Path::new("witness.b");
        let found = diagnostics(src, &loader);
        let carried = found.iter().any(|d| {
            d.code == r.code
                && d.fixes
                    .iter()
                    .any(|f| f.applicability == blue_lang_check::Applicability::MachineApplicable)
        });
        if !carried {
            failures.push(format!(
                "{}: no machine fix on its fix witness: {found:?}",
                r.code
            ));
            continue;
        }
        let (fixed, applied) = blue_lang_check::fixes::apply_machine_fixes(&found, &|_| true, src);
        if applied == 0 {
            failures.push(format!("{}: the fix did not apply", r.code));
            continue;
        }
        let written = blue_lang_pkg::canonical::format_with(&loader, path, &fixed)
            .unwrap_or_else(|e| panic!("{}: fmt refused the fixed witness: {e}\n{fixed}", r.code));
        if written != fixed {
            failures.push(format!(
                "{}: the fixed witness is not canonical:\n{fixed}---\n{written}",
                r.code
            ));
        }
        let after = codes(&fixed, &loader);
        if after.contains(&r.code) {
            failures.push(format!(
                "{}: still fires after --fix: {after:?}\n{fixed}",
                r.code
            ));
        }
    }
    assert!(seen > 0, "no rule names a fix witness");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
