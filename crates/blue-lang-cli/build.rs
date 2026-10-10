//! Compile `spec/rows/*.b` (the conformance rows) into `$OUT_DIR/rows.rs`, as
//! `include_str!` of each file's absolute path, sorted, so `blue doc` shows a
//! builtin's example from the row that specifies it and an edit re-runs the
//! build. A registry build carries no `spec/`, and the set is then empty.

use std::fmt::Write as _;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    let manifest = PathBuf::from(
        std::env::var_os("CARGO_MANIFEST_DIR").expect("cargo sets CARGO_MANIFEST_DIR"),
    );
    let root = manifest.join("../../spec/rows");
    println!("cargo:rerun-if-changed={}", root.display());
    let mut files: Vec<PathBuf> = std::fs::read_dir(&root)
        .map(|d| {
            d.filter_map(Result::ok)
                .map(|e| e.path())
                .filter(|f| f.extension().is_some_and(|x| x == "b"))
                .collect()
        })
        .unwrap_or_default();
    files.sort();
    let mut out = String::from("pub const ROWS: &[(&str, &str)] = &[\n");
    for f in files {
        let abs = f.canonicalize().unwrap_or(f);
        println!("cargo:rerun-if-changed={}", abs.display());
        let name = abs.file_name().unwrap().to_string_lossy().into_owned();
        writeln!(
            out,
            "    ({name:?}, include_str!({:?})),",
            abs.display().to_string()
        )
        .unwrap();
    }
    out.push_str("];\n");
    let dest =
        PathBuf::from(std::env::var_os("OUT_DIR").expect("cargo sets OUT_DIR")).join("rows.rs");
    std::fs::write(dest, out).expect("write rows.rs");
}
