//! The rows of the standard distribution: one per package and per level
//! below it, each with its Bluefile and its `.b` files. Read by `build.rs`,
//! which compiles them in for a shipped build, and by [`crate::embedded`],
//! which reads them from the checkout when the build is a dev one.

use std::path::{Path, PathBuf};

/// A row: the level's name, its package's Bluefile, its files.
pub type Row = (String, PathBuf, Vec<PathBuf>);

/// Every row under `root`, in the order the table lists them.
#[must_use]
pub fn rows(root: &Path) -> Vec<Row> {
    let mut out = Vec::new();
    for (name, dir, files) in packages(root) {
        let bluefile = dir.join("Bluefile");
        let bluefile = bluefile.canonicalize().unwrap_or(bluefile);
        let mut rows = vec![(name.clone(), part_of_parent(files.clone()))];
        for f in &files {
            if own_level(f) {
                let stem = f.file_stem().unwrap().to_string_lossy();
                rows.push((format!("{name}/{stem}"), vec![f.clone()]));
            }
        }
        level_rows(&name, &dir, &mut rows);
        for (level, level_files) in rows {
            let level_files = level_files
                .into_iter()
                .map(|f| f.canonicalize().unwrap_or(f))
                .collect();
            out.push((level, bluefile.clone(), level_files));
        }
    }
    out
}

/// The label a file is served under in `level`.
#[must_use]
pub fn label(level: &str, file: &Path) -> String {
    format!("{level}/{}", file.file_name().unwrap().to_string_lossy())
}

fn own_level(file: &Path) -> bool {
    std::fs::read_to_string(file).is_ok_and(|t| super::levels::declares_level(&t))
}

fn part_of_parent(files: Vec<PathBuf>) -> Vec<PathBuf> {
    files.into_iter().filter(|f| !own_level(f)).collect()
}

/// A row per level below `dir`: a directory `<d>` holding `<d>/<d>.b`, and
/// each file in it that opens with `namespace()`.
fn level_rows(level: &str, dir: &Path, rows: &mut Vec<(String, Vec<PathBuf>)>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let mut subs: Vec<PathBuf> = entries
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| {
            p.is_dir()
                && p.file_name()
                    .is_some_and(|n| p.join(format!("{}.b", n.to_string_lossy())).is_file())
        })
        .collect();
    subs.sort();
    for sub in subs {
        let child = format!("{level}/{}", sub.file_name().unwrap().to_string_lossy());
        let mut files: Vec<PathBuf> = std::fs::read_dir(&sub)
            .map(|d| {
                d.filter_map(Result::ok)
                    .map(|e| e.path())
                    .filter(|f| f.extension().is_some_and(|x| x == "b"))
                    .collect()
            })
            .unwrap_or_default();
        files.sort();
        for f in &files {
            if own_level(f) {
                let stem = f.file_stem().unwrap().to_string_lossy();
                rows.push((format!("{child}/{stem}"), vec![f.clone()]));
            }
        }
        rows.push((child.clone(), part_of_parent(files)));
        level_rows(&child, &sub, rows);
    }
}

/// Every directory under `root` holding a `Bluefile`, with its `.b` files,
/// both sorted. A missing root (a registry build) is the empty set.
fn packages(root: &Path) -> Vec<(String, PathBuf, Vec<PathBuf>)> {
    let Ok(entries) = std::fs::read_dir(root) else {
        return Vec::new();
    };
    let mut pkgs: Vec<(String, PathBuf, Vec<PathBuf>)> = entries
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.join("Bluefile").is_file())
        .map(|p| {
            let mut files: Vec<PathBuf> = std::fs::read_dir(&p)
                .map(|d| {
                    d.filter_map(Result::ok)
                        .map(|e| e.path())
                        .filter(|f| f.extension().is_some_and(|x| x == "b"))
                        .collect()
                })
                .unwrap_or_default();
            files.sort();
            (
                p.file_name().unwrap().to_string_lossy().into_owned(),
                p,
                files,
            )
        })
        .collect();
    pkgs.sort();
    pkgs
}

#[cfg(test)]
mod tests {
    use super::rows;

    #[test]
    fn a_namespace_file_and_a_named_directory_are_levels_and_nothing_else_is() {
        let root = std::env::temp_dir().join(format!("blue-embed-rows-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let pkg = root.join("pkg");
        for d in ["sub", "stray", "sub/deep"] {
            std::fs::create_dir_all(pkg.join(d)).unwrap();
        }
        for (f, text) in [
            ("Bluefile", "bidama(\"pkg\", \"0.1.0\")\n"),
            ("pkg.b", "def a()\n  1\nend\n"),
            ("own.b", "namespace()\n\ndef b()\n  2\nend\n"),
            ("sub/sub.b", "def c()\n  3\nend\n"),
            ("sub/deep/deep.b", "def d()\n  4\nend\n"),
            ("stray/other.b", "def e()\n  5\nend\n"),
            ("sub.b", "def f()\n  6\nend\n"),
        ] {
            std::fs::write(pkg.join(f), text).unwrap();
        }
        std::fs::create_dir_all(root.join("loose")).unwrap();
        let got: Vec<(String, Vec<String>)> = rows(&root)
            .into_iter()
            .map(|(level, _, files)| {
                let names = files
                    .iter()
                    .map(|f| f.file_name().unwrap().to_string_lossy().into_owned())
                    .collect();
                (level, names)
            })
            .collect();
        std::fs::remove_dir_all(&root).unwrap();
        let want: Vec<(String, Vec<String>)> = [
            ("pkg", vec!["pkg.b", "sub.b"]),
            ("pkg/own", vec!["own.b"]),
            ("pkg/sub", vec!["sub.b"]),
            ("pkg/sub/deep", vec!["deep.b"]),
        ]
        .into_iter()
        .map(|(l, fs)| (l.to_string(), fs.into_iter().map(String::from).collect()))
        .collect();
        assert_eq!(got, want);
    }
}
