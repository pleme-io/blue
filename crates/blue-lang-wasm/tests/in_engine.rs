//! Blue running in a real WebAssembly engine.
//!
//! The unit tests in `lib.rs` check the tagging and the pipeline **on the
//! host**, which proves the encoding and proves nothing about wasm. This test
//! compiles the module for `wasm32-unknown-unknown` and executes it in an
//! actual engine, because "compiles to wasm" and "runs as wasm" are different
//! claims and only the second one is the tenet.
//!
//! It builds the artifact itself rather than assuming one is present. A test
//! that skips when its input is missing is a gate that passes by default, and
//! this is the only gate standing behind the WASM claim.
//!
//! The engine is Node's, driven by `host/drive.mjs`. That file is *also* the
//! worked example of embedding blue: ~30 lines to instantiate and call, with
//! **no import object at all**.

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
fn build_wasm() -> PathBuf {
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

/// **Blue runs in a WebAssembly engine, and imports nothing.**
///
/// The driver instantiates with an empty import object. If the module needed a
/// single host function — a clock, a random source, a file descriptor —
/// instantiation would throw. That is the capability argument: restriction is
/// the absence of an import, not a policy checked at call time.
#[test]
fn blue_runs_inside_a_wasm_engine_with_zero_imports() {
    let wasm = build_wasm();
    let driver = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("host/drive.mjs");

    let out = Command::new("node")
        .arg(&driver)
        .arg(&wasm)
        .output()
        .expect("spawn node — the engine under test");

    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        out.status.success(),
        "the engine run must pass every case:\nstdout:\n{stdout}\nstderr:\n{stderr}"
    );
    assert!(
        stdout.contains("imports: 0"),
        "the module must import NOTHING — that is the sandbox: {stdout}"
    );
    assert!(
        stdout.contains("ALL WASM CASES PASSED"),
        "every case must pass in the engine: {stdout}"
    );
}
