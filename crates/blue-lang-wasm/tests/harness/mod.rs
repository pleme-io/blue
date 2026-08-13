//! Shared by every in-engine test: build the artifact, don't assume one.
//!
//! Extracted when the second test needed it. A test that skips when its input
//! is missing is a gate that passes by default, so both gates build their own
//! input — and both must build the *same* one, which is the reason this is one
//! function rather than two copies that can drift on a flag.

use std::path::PathBuf;
use std::process::Command;

fn repo_root() -> PathBuf {
    // CARGO_MANIFEST_DIR is .../crates/blue-lang-wasm
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .expect("repo root")
        .to_path_buf()
}

/// Build the wasm module and return its path.
pub fn build_wasm() -> PathBuf {
    let root = repo_root();
    let out = Command::new(env!("CARGO"))
        .current_dir(&root)
        .args([
            "build",
            "-p",
            "blue-lang-wasm",
            "--release",
            "--target",
            "wasm32-unknown-unknown",
        ])
        .output()
        .expect("spawn cargo");
    assert!(
        out.status.success(),
        "the wasm build must succeed:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let path = root.join("target/wasm32-unknown-unknown/release/blue_lang_wasm.wasm");
    assert!(
        path.exists(),
        "expected a wasm artifact at {}",
        path.display()
    );
    path
}
