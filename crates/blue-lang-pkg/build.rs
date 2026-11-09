//! With feature `embedded`, compile `bidamas/` (the standard distribution)
//! into `$OUT_DIR/embedded.rs`: every `<pkg>/Bluefile` and `<pkg>/*.b`,
//! sorted, as `include_str!` of its absolute path, so an edit re-runs the
//! build, with a row per level below each package. A dev build (`PROFILE`
//! debug) compiles in only the checkout's `bidamas/` path, `LIVE`, and reads
//! the same rows from it when it runs, so an edit to a `.b` file rebuilds no
//! Rust. Without the feature the table is empty.

use std::fmt::Write as _;
use std::path::PathBuf;

#[path = "src/levels.rs"]
mod levels;

#[path = "src/embed_rows.rs"]
mod embed_rows;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=src/embed_rows.rs");
    println!("cargo:rerun-if-changed=src/levels.rs");
    let dest =
        PathBuf::from(std::env::var_os("OUT_DIR").expect("cargo sets OUT_DIR")).join("embedded.rs");
    let mut out = String::from("pub const COMPILED: &[Package] = &[\n");
    let mut live = None;
    if std::env::var_os("CARGO_FEATURE_EMBEDDED").is_some() {
        live = embed(&mut out);
    }
    out.push_str("];\n");
    writeln!(out, "pub const LIVE: Option<&str> = {live:?};").unwrap();
    std::fs::write(dest, out).expect("write embedded.rs");
}

/// One table row per package of the checkout's `bidamas/`, or, for a dev
/// build, none and the path the rows are read from when it runs.
fn embed(out: &mut String) -> Option<String> {
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
    if std::env::var("PROFILE").as_deref() == Ok("debug") {
        let root = root.canonicalize().unwrap_or(root);
        return Some(root.display().to_string());
    }
    println!("cargo:rerun-if-changed={}", root.display());
    for (level, bluefile, level_files) in embed_rows::rows(&root) {
        println!("cargo:rerun-if-changed={}", bluefile.display());
        writeln!(
            out,
            "    ({level:?}, include_str!({:?}), &[",
            bluefile.display().to_string()
        )
        .unwrap();
        for f in level_files {
            println!("cargo:rerun-if-changed={}", f.display());
            writeln!(
                out,
                "        ({:?}, include_str!({:?})),",
                embed_rows::label(&level, &f),
                f.display().to_string()
            )
            .unwrap();
        }
        out.push_str("    ]),\n");
    }
    None
}
