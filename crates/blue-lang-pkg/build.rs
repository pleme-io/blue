//! With feature `embedded`, compile `bidamas/` (the standard distribution)
//! into `$OUT_DIR/embedded.rs`: every `<pkg>/*.b`, sorted, as `include_str!`
//! of its absolute path, so an edit re-runs the build.

use std::fmt::Write as _;
use std::path::{Path, PathBuf};

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    if std::env::var_os("CARGO_FEATURE_EMBEDDED").is_none() {
        return;
    }
    let manifest = PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").expect("cargo sets CARGO_MANIFEST_DIR"));
    let root = manifest.join("../../bidamas");
    println!("cargo:rerun-if-changed={}", root.display());
    let mut out = String::from("pub const PACKAGES: &[(&str, &[(&str, &str)])] = &[\n");
    for (name, files) in packages(&root) {
        writeln!(out, "    ({name:?}, &[").unwrap();
        for f in files {
            let label = format!("{name}/{}", f.file_name().unwrap().to_string_lossy());
            let abs = f.canonicalize().unwrap_or(f);
            println!("cargo:rerun-if-changed={}", abs.display());
            writeln!(out, "        ({label:?}, include_str!({:?})),", abs.display().to_string()).unwrap();
        }
        out.push_str("    ]),\n");
    }
    out.push_str("];\n");
    let dest = PathBuf::from(std::env::var_os("OUT_DIR").expect("cargo sets OUT_DIR")).join("embedded.rs");
    std::fs::write(dest, out).expect("write embedded.rs");
}

/// Every directory under `root` holding a `Bluefile`, with its `.b` files,
/// both sorted. A missing root (a registry build) is the empty set.
fn packages(root: &Path) -> Vec<(String, Vec<PathBuf>)> {
    let Ok(entries) = std::fs::read_dir(root) else { return Vec::new() };
    let mut pkgs: Vec<(String, Vec<PathBuf>)> = entries
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.join("Bluefile").is_file())
        .map(|p| {
            let mut files: Vec<PathBuf> = std::fs::read_dir(&p)
                .map(|d| d.filter_map(Result::ok).map(|e| e.path()).filter(|f| f.extension().is_some_and(|x| x == "b")).collect())
                .unwrap_or_default();
            files.sort();
            (p.file_name().unwrap().to_string_lossy().into_owned(), files)
        })
        .collect();
    pkgs.sort();
    pkgs
}
