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

use blue_lang_waku::{imports_of, Capability, Reach, Waku, When, Where};

/// **The frame this crate's artifact is minted from.**
///
/// `theory/BLUE-EXECUTION.md` M1: *"a module's import table is the lowering of
/// the `waku` it was minted from."* Until M2 wires an engine border there is no
/// minting step to read a frame from, so this states the frame the build
/// already realises — `blue-lang-wasm` compiles `blue-lang-runtime` with the
/// `sys` feature OFF, so **no host capability is granted**, and every pure
/// bundle is.
///
/// It is written as the pure half of the universe rather than as a literal
/// `Reach::nothing()`, because the interesting claim is not "an empty frame
/// opens nothing" — it is that a frame granting six real capabilities still
/// opens nothing, since none of the six reaches the host.
fn wasm_surface_frame() -> Waku {
    Waku {
        reach: Reach::only(Capability::ALL.into_iter().filter(|c| !c.is_host_effect())),
        when: When::Anytime,
        place: Where::Process,
    }
}

/// The `imports: N` line `host/drive.mjs` prints, read back.
fn reported_imports(stdout: &str) -> usize {
    stdout
        .lines()
        .find_map(|l| l.strip_prefix("imports: "))
        .expect("the driver must report an import count")
        .trim()
        .parse()
        .expect("the import count is a number")
}

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

    // **The engine's count and the frame's lowering are the same number.**
    //
    // `theory/BLUE-EXECUTION.md` M1's gate. The line above pins the engine's
    // observation; this pins that blue's derivation *agrees* with it, which is
    // the only thing that makes the derivation about this artifact rather than
    // about itself. If M2 ever mints a module from a frame, this comparison is
    // already the assertion it has to satisfy.
    assert_eq!(
        reported_imports(&stdout),
        imports_of(&wasm_surface_frame()).len(),
        "the engine and the frame disagree about the import table: {stdout}"
    );
}

/// **The derivation moves when the frame does** — the anti-vacuity half of the
/// gate above, and the reason `imports: 0` matching `0` is evidence at all.
///
/// A lowering that returned an empty table for every frame would satisfy the
/// engine comparison perfectly. This is the control: the same function, one
/// capability added, a different answer.
///
/// It runs on the host with no wasm build, so it is a cheap gate that cannot be
/// skipped when `node` or the `wasm32-unknown-unknown` target is missing.
#[test]
fn the_derived_table_follows_the_frame_and_the_wasm_frame_is_genuinely_closed() {
    let closed = wasm_surface_frame();
    assert!(
        imports_of(&closed).is_empty(),
        "the frame the wasm surface is minted from must open nothing"
    );
    assert!(
        !closed.reach.grants(Capability::FileSystem),
        "the wasm surface grants no host capability"
    );

    // Grant one host capability and the table gains exactly its import.
    let opened = Waku {
        reach: closed.reach.join(&Reach::only([Capability::FileSystem])),
        ..closed.clone()
    };
    let table = imports_of(&opened);
    assert_eq!(table.len(), 1, "{table:?}");
    assert_eq!(
        table[0],
        Capability::FileSystem
            .import()
            .expect("filesystem is a host effect")
    );

    // And narrowing back closes it again — the property the whole design rests
    // on, checked on the frame this crate actually ships.
    assert!(imports_of(&opened.narrow(&closed)).is_empty());
}
