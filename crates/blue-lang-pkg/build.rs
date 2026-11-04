//! With feature `embedded`, compile `bidamas/` (the standard distribution)
//! into `$OUT_DIR/embedded.rs`: every `<pkg>/Bluefile` and `<pkg>/*.b`,
//! sorted, as `include_str!` of its absolute path, so an edit re-runs the
//! build, with a row per level below each package. Without it the table is
//! empty.

use std::fmt::Write as _;
use std::path::{Path, PathBuf};

#[path = "src/levels.rs"]
mod levels;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    let dest =
        PathBuf::from(std::env::var_os("OUT_DIR").expect("cargo sets OUT_DIR")).join("embedded.rs");
    let mut out = String::from("pub const PACKAGES: &[Package] = &[\n");
    if std::env::var_os("CARGO_FEATURE_EMBEDDED").is_some() {
        embed(&mut out);
    }
    out.push_str("];\n");
    std::fs::write(dest, out).expect("write embedded.rs");
}

/// One table row per package of the checkout's `bidamas/`.
fn embed(out: &mut String) {
    let manifest = PathBuf::from(
        std::env::var_os("CARGO_MANIFEST_DIR").expect("cargo sets CARGO_MANIFEST_DIR"),
    );
    // cargo runs this from the crate's directory; nix's buildRustCrate, which
    // substrate hands the whole workspace, runs it from the workspace root.
    // Both see the same `bidamas/`, so both binaries carry the same packages.
    let root = [manifest.join("../../bidamas"), manifest.join("bidamas")]
        .into_iter()
        .find(|r| r.is_dir())
        .unwrap_or_else(|| {
            panic!(
                "blue-lang-pkg: no bidamas/ beside {} or two levels up; the standard distribution would be empty. A nix build of this crate as a git dependency needs the whole repository as its source (substrate: [package.metadata.substrate] sources)",
                manifest.display()
            )
        });
    println!("cargo:rerun-if-changed={}", root.display());
    for (name, dir, files) in packages(&root) {
        let bluefile = dir.join("Bluefile");
        let bluefile = bluefile.canonicalize().unwrap_or(bluefile);
        println!("cargo:rerun-if-changed={}", bluefile.display());
        let mut rows = vec![(name.clone(), part_of_parent(files.clone()))];
        for f in &files {
            if own_level(f) {
                let stem = f.file_stem().unwrap().to_string_lossy();
                rows.push((format!("{name}/{stem}"), vec![f.clone()]));
            }
        }
        level_rows(&name, &dir, &mut rows);
        for (level, level_files) in rows {
            writeln!(
                out,
                "    ({level:?}, include_str!({:?}), &[",
                bluefile.display().to_string()
            )
            .unwrap();
            for f in level_files {
                let label = format!("{level}/{}", f.file_name().unwrap().to_string_lossy());
                let abs = f.canonicalize().unwrap_or(f);
                println!("cargo:rerun-if-changed={}", abs.display());
                writeln!(
                    out,
                    "        ({label:?}, include_str!({:?})),",
                    abs.display().to_string()
                )
                .unwrap();
            }
            out.push_str("    ]),\n");
        }
    }
}

fn own_level(file: &Path) -> bool {
    std::fs::read_to_string(file).is_ok_and(|t| levels::declares_level(&t))
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
