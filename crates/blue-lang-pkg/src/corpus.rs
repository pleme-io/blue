//! The repository's blue corpus: every `.b` file a whole-tree gate checks,
//! and the load path that resolves their imports. One walk, shared by
//! `blue census` and the check-stage corpus gate, so the two count the same
//! files.

use std::path::{Path, PathBuf};

use crate::load_path::LoadPath;

/// Distributions of conformance fixtures, relative to the root: packages
/// that violate rules ON PURPOSE (`spec/bidamas/README.md`), loaded only by
/// the conformance runner, which states what each must produce. Not corpus.
pub const FIXTURE_DISTRIBUTIONS: &[&str] = &["spec/bidamas"];

/// Directories of `.b` DATA, relative to the root: `spec/rows/*.b` are row
/// declarations (`row(…)`, `value(…)`) whose words only the conformance
/// runner binds. They are formatted like every `.b` file, and are not
/// programs to check.
pub const DATA_DIRECTORIES: &[&str] = &["spec/rows"];

/// Every `.b` file under `root`, sorted: `target/`, dot directories,
/// symlinks (a `result` into the store), [`FIXTURE_DISTRIBUTIONS`] and
/// [`DATA_DIRECTORIES`] skipped.
#[must_use]
pub fn files(root: &Path) -> Vec<PathBuf> {
    fn walk(root: &Path, dir: &Path, out: &mut Vec<PathBuf>) {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        for e in entries.flatten() {
            let p = e.path();
            let name = e.file_name().to_string_lossy().into_owned();
            let Ok(meta) = std::fs::symlink_metadata(&p) else {
                continue;
            };
            if meta.is_dir() {
                let fixture = FIXTURE_DISTRIBUTIONS
                    .iter()
                    .chain(DATA_DIRECTORIES)
                    .any(|f| p == root.join(f));
                if name == "target" || name.starts_with('.') || fixture {
                    continue;
                }
                walk(root, &p, out);
            } else if meta.is_file() && p.extension().is_some_and(|x| x == "b") {
                out.push(p);
            }
        }
    }
    let mut out = Vec::new();
    walk(root, root, &mut out);
    out.sort();
    out
}

/// A load path over every distribution `files` live in (each `bidamas/`
/// ancestor), `root/bidamas` first: it is the one every project builds on.
#[must_use]
pub fn load_path(root: &Path, files: &[PathBuf]) -> LoadPath {
    let mut roots: Vec<PathBuf> = files
        .iter()
        .filter_map(|f| {
            f.ancestors()
                .find(|a| a.file_name().is_some_and(|n| n == "bidamas"))
                .map(Path::to_path_buf)
        })
        .collect();
    roots.sort();
    roots.dedup();
    roots.sort_by_key(|r| r != &root.join("bidamas"));
    LoadPath::new(roots)
}
