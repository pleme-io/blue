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

pub const DOCUMENTED: &[&str] = &["kakehashi", "toriyose", "umu"];

pub const DOC_CODES: &[Code] = &[Code::B0056, Code::B0057];

/// What the census counted.
pub struct Census {
    /// Files checked.
    pub files: usize,
    /// For each ratcheted code, each distinct finding, rendered.
    pub findings: BTreeMap<Code, BTreeSet<String>>,
    pub by_package: BTreeMap<(Code, String), BTreeSet<String>>,
    pub waived: BTreeMap<Code, BTreeSet<String>>,
}

impl Census {
    /// Every obligation whose waived debt is not the number its row holds:
    /// `(id, code, measured, held)`.
    #[must_use]
    pub fn held_mismatches(&self) -> Vec<(&'static str, Code, usize, u32)> {
        blue_lang_check::obligations::OBLIGATIONS
            .iter()
            .filter_map(|o| {
                let blue_lang_check::obligations::Refusal::Code(code) = o.refusal else {
                    return None;
                };
                let measured = self.waived.get(&code).map_or(0, BTreeSet::len);
                (measured != o.held as usize).then_some((o.id, code, measured, o.held))
            })
            .collect()
    }

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

    #[must_use]
    pub fn package_mismatches(&self, documented: &[&str]) -> Vec<(Code, String, usize)> {
        documented
            .iter()
            .flat_map(|p| {
                DOC_CODES.iter().filter_map(move |c| {
                    let n = self
                        .by_package
                        .get(&(*c, (*p).to_string()))
                        .map_or(0, BTreeSet::len);
                    (n > 0).then(|| (*c, (*p).to_string(), n))
                })
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
    let mut by_package: BTreeMap<(Code, String), BTreeSet<String>> = BTreeMap::new();
    let mut waived: BTreeMap<Code, BTreeSet<String>> = BTreeMap::new();
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
        let package = checked
            .program
            .file(blue_lang_runtime::uses::ResolvedProgram::ENTRY)
            .and_then(|f| f.package.as_deref())
            .map(|p| blue_lang_syntax::root_of(p).to_string());
        for d in checked
            .outcome
            .census
            .iter()
            .chain(checked.outcome.diagnostics.iter().filter(ratcheted))
        {
            let shown = render(&checked.program, d);
            if let Some(p) = &package {
                by_package
                    .entry((d.code, p.clone()))
                    .or_default()
                    .insert(shown.clone());
            }
            findings.entry(d.code).or_default().insert(shown);
        }
        for w in &checked.outcome.waived {
            if blue_lang_check::obligations::of_code(w.waiver.code).is_none() {
                continue;
            }
            let shown = format!(
                "{}: {} ({})",
                path.strip_prefix(root).unwrap_or(path).display(),
                render(&checked.program, &w.diagnostic)
                    .lines()
                    .next()
                    .unwrap_or_default(),
                w.waiver.reason
            );
            waived.entry(w.waiver.code).or_default().insert(shown);
        }
    }
    Ok(Census {
        files: files.len(),
        findings,
        by_package,
        waived,
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

fn package_roots(files: &[std::path::PathBuf]) -> Vec<std::path::PathBuf> {
    let mut roots: Vec<std::path::PathBuf> = files
        .iter()
        .filter_map(|f| {
            let dir = f.parent()?;
            (dir.file_name()? == f.file_stem()?).then(|| dir.parent().map(Path::to_path_buf))?
        })
        .collect();
    roots.sort();
    roots.dedup();
    roots
}

pub(crate) fn environment_over(
    files: &[std::path::PathBuf],
) -> blue_lang_pkg::load_path::Environment {
    let mut roots = package_roots(files);
    roots.extend(
        std::env::var_os(blue_lang_pkg::load_path::BLUE_PATH)
            .as_deref()
            .map_or_else(Vec::new, |v| std::env::split_paths(v).collect()),
    );
    blue_lang_pkg::load_path::Environment::from_vars(
        std::env::join_paths(roots).unwrap_or_default().as_os_str(),
        std::env::var_os(blue_lang_pkg::load_path::BLUE_DIST)
            .unwrap_or_default()
            .as_os_str(),
    )
}

#[must_use]
pub fn reuse_scan(root: &Path) -> ReuseScan {
    let files = blue_lang_pkg::corpus::files(root);
    let mut scan = ReuseScan {
        files: files.len(),
        ..ReuseScan::default()
    };
    let floor = blue_lang_check::shape::Near::DEFAULT.min_size;
    let environment = environment_over(&files);
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
        let loader = environment.load_path(Some(path));
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
        let entry = blue_lang_mondou::facts::of_entry(&checked);
        let shapes: Vec<(
            &blue_lang_mondou::facts::DefFact,
            &blue_lang_runtime::def_hash::Shape,
        )> = entry
            .facts
            .iter()
            .filter_map(|f| f.shape.as_ref().map(|s| (f, s)))
            .collect();
        scan.definitions += shapes.len();
        for (f, s) in shapes.into_iter().filter(|(_, s)| s.size >= floor) {
            let line = f.line;
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

#[cfg(test)]
mod documented {
    use super::*;

    fn project(name: &str, body: &str) -> std::path::PathBuf {
        let root = std::env::temp_dir().join(format!(
            "blue-census-documented-{}-{name}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let dir = root.join("bidamas").join("kagi");
        std::fs::create_dir_all(&dir).expect("mkdir");
        std::fs::write(dir.join("Bluefile"), "package(\"kagi\", \"0.1.0\")\n").expect("write");
        std::fs::write(dir.join("kagi.b"), body).expect("write");
        root
    }

    const HEAD: &str = "@moduledoc \"\"\"\nkagi holds one value.\n\n    kagi #=> 1\n\"\"\"\n\n";

    #[test]
    fn a_documented_bidama_with_an_undocumented_definition_is_named() {
        let root = project("red", &format!("{HEAD}def kagi()\n  1\nend\n"));
        let c = take(&root).expect("census");
        let _ = std::fs::remove_dir_all(&root);
        assert_eq!(
            c.package_mismatches(&["kagi"]),
            vec![(Code::B0056, "kagi".to_string(), 1)]
        );
        assert!(c.package_mismatches(&["other"]).is_empty());
    }

    #[test]
    fn a_documented_bidama_whose_every_definition_has_a_doc_and_an_example_holds() {
        let root = project(
            "green",
            &format!(
                "{HEAD}@doc \"\"\"\nkagi is one.\n\n    kagi #=> 1\n\"\"\"\ndef kagi()\n  1\nend\n"
            ),
        );
        let c = take(&root).expect("census");
        let _ = std::fs::remove_dir_all(&root);
        assert!(c.package_mismatches(&["kagi"]).is_empty());
    }

    #[test]
    fn a_doc_without_an_example_is_named_too() {
        let root = project(
            "example",
            &format!("{HEAD}@doc \"\"\"\nkagi is one.\n\"\"\"\ndef kagi()\n  1\nend\n"),
        );
        let c = take(&root).expect("census");
        let _ = std::fs::remove_dir_all(&root);
        assert_eq!(
            c.package_mismatches(&["kagi"]),
            vec![(Code::B0057, "kagi".to_string(), 1)]
        );
    }
}

#[cfg(test)]
mod held {
    use super::*;

    const POINT: &str = "@moduledoc \"\"\"\nkagi asks the machine.\n\n    1 + 1 #=> 2\n\"\"\"\n\n@doc \"\"\"\nkagi runs `date`.\n\n    1 + 1 #=> 2\n\"\"\"\ndef kagi()\n  exec_capture(\"date\")\nend\n";

    fn project(name: &str, body: &str) -> std::path::PathBuf {
        let root =
            std::env::temp_dir().join(format!("blue-census-held-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let dir = root.join("bidamas").join("kagi");
        std::fs::create_dir_all(&dir).expect("mkdir");
        std::fs::write(dir.join("Bluefile"), "package(\"kagi\", \"0.1.0\")\n").expect("write");
        std::fs::write(dir.join("kagi.b"), body).expect("write");
        root
    }

    /// **A waived integration point is debt the census counts, with its
    /// reason; a point with a test of its kind is no debt.** The count is
    /// what `held_mismatches` holds against the obligation row.
    #[test]
    fn a_waived_point_is_counted_and_a_tested_one_is_not() {
        let waived = POINT.replace(
            "@doc \"\"\"\nkagi runs",
            "# waive B0083: the fixture's debt\n@doc \"\"\"\nkagi runs",
        );
        let root = project("waived", &waived);
        let c = take(&root).expect("census");
        let _ = std::fs::remove_dir_all(&root);
        let counted: Vec<&String> = c.waived.get(&Code::B0083).into_iter().flatten().collect();
        assert_eq!(counted.len(), 1, "{counted:?}");
        assert!(counted[0].contains("the fixture's debt"), "{counted:?}");
        let tested = format!(
            "{POINT}\ntest \"kagi\", {{kind: :integration, allow: [:process]}}\n  assert kagi != nil\nend\n"
        );
        let root = project("tested", &tested);
        let c = take(&root).expect("census");
        let _ = std::fs::remove_dir_all(&root);
        assert!(c.waived.get(&Code::B0083).is_none());
    }
}
