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
use blue_lang_runtime::word_shapes::Standing;

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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReuseFact {
    pub scope: String,
    pub file: String,
    pub line: usize,
    pub name: String,
    pub shape: String,
    pub size: usize,
    pub home: Option<String>,
    pub fix: Option<&'static str>,
    pub word: bool,
    pub waived: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ReuseScan {
    pub files: usize,
    pub definitions: usize,
    pub facts: Vec<ReuseFact>,
    pub blind: Vec<(String, String)>,
}

impl ReuseScan {
    #[must_use]
    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "files": self.files,
            "definitions": self.definitions,
            "blind": self.blind.iter().map(|(file, why)| serde_json::json!({
                "file": file,
                "why": why,
            })).collect::<Vec<_>>(),
            "facts": self.facts.iter().map(ReuseFact::to_json).collect::<Vec<_>>(),
        })
    }
}

impl ReuseFact {
    #[must_use]
    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "scope": self.scope,
            "file": self.file,
            "line": self.line,
            "name": self.name,
            "shape": self.shape,
            "size": self.size,
            "home": self.home,
            "fix": self.fix,
            "word": self.word,
            "waived": self.waived,
        })
    }
}

#[must_use]
pub fn reuse_scan(root: &Path) -> ReuseScan {
    let files = blue_lang_pkg::corpus::files(root);
    let mut scan = ReuseScan {
        files: files.len(),
        ..ReuseScan::default()
    };
    let floor = blue_lang_check::shape::Near::DEFAULT.min_size;
    for path in &files {
        let rel = path
            .strip_prefix(root)
            .unwrap_or(path)
            .display()
            .to_string();
        let text = match std::fs::read_to_string(path) {
            Ok(t) => t,
            Err(e) => {
                scan.blind.push((rel, e.to_string()));
                continue;
            }
        };
        let loader = blue_lang_pkg::load_path::LoadPath::for_entry(path);
        let checked = match check_entry(
            Entry {
                path: Some(path),
                text: &text,
            },
            &loader,
            None,
            Checking::WithTests,
        ) {
            Ok(c) => c,
            Err(e) => {
                scan.blind.push((rel, e.to_string()));
                continue;
            }
        };
        let package = checked
            .program
            .file(blue_lang_runtime::uses::ResolvedProgram::ENTRY)
            .and_then(|f| f.package.clone());
        let scope = package.unwrap_or_else(|| format!("%root:{rel}"));
        let shapes = checked.entry_shapes();
        scan.definitions += shapes.len();
        for s in shapes.iter().filter(|s| s.size >= floor) {
            let start = checked.program.forms()[s.top_level].span.start;
            let line = text
                .get(..start)
                .map_or(1, |head| head.matches('\n').count() + 1);
            let standing = blue_lang_runtime::word_shapes::standing(&s.hash, &s.key);
            let (home, fix, word) = match standing {
                Standing::NoWord => (None, None, false),
                Standing::OwnWord => (None, None, true),
                Standing::CopyOf { word, foundation } => (
                    Some(word.to_string()),
                    Some(if foundation { "import" } else { "move_down" }),
                    false,
                ),
            };
            let waived = checked
                .outcome
                .waived
                .iter()
                .any(|w| w.waiver.code == Code::B0070 && w.waiver.top_level == s.top_level);
            scan.facts.push(ReuseFact {
                scope: scope.clone(),
                file: rel.clone(),
                line,
                name: s.name().to_string(),
                shape: s.hash.hex(),
                size: s.size,
                home,
                fix,
                word,
                waived,
            });
        }
    }
    scan
}

#[must_use]
pub fn word_copy_lines(file: &Path) -> Vec<String> {
    let Ok(text) = std::fs::read_to_string(file) else {
        return Vec::new();
    };
    let loader = blue_lang_pkg::load_path::LoadPath::for_entry(file);
    let found = blue_lang_runtime::pipeline::word_copies(
        Entry {
            path: Some(file),
            text: &text,
        },
        &loader,
    );
    found
        .unwrap_or_default()
        .iter()
        .map(|d| {
            let (line, column) = blue_lang_syntax::Span::line_col(&text, d.span.start);
            format!(
                "{}:{line}:{column}: {}: {}",
                file.display(),
                d.message,
                d.help.as_deref().unwrap_or_default()
            )
        })
        .collect()
}

fn hook_file(input: &str) -> Option<std::path::PathBuf> {
    let doc: serde_json::Value = serde_json::from_str(input).ok()?;
    let path = Path::new(doc.get("tool_input")?.get("file_path")?.as_str()?);
    (path.extension().is_some_and(|x| x == "b") && path.is_file()).then(|| path.to_path_buf())
}

pub fn reuse_hook() {
    use std::io::{Read, Write};
    std::panic::set_hook(Box::new(|_| {}));
    let _ = std::panic::catch_unwind(|| {
        let mut input = String::new();
        let _ = std::io::stdin().read_to_string(&mut input);
        let Some(file) = hook_file(&input) else {
            return;
        };
        let mut out = std::io::stdout().lock();
        for line in word_copy_lines(&file) {
            let _ = writeln!(out, "{line}");
        }
    });
}
