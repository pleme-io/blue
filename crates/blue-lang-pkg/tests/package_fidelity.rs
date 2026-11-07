//! The package must ship every file the embedded build reads.
//!
//! 0.0.163's predecessor shipped a distribution silently missing all 217
//! level files: `include` stopped at `bidamas/*/*.b` while `build.rs`
//! recurses into levels at any depth, and every test ran beside the full
//! `bidamas/` tree, so the checkout stayed green while the registry crate
//! answered `no bidama named "todokede/motenashi"`. This test is the gate
//! that class needs: it compares the PACKAGED file list against the
//! checkout's filesystem — the one truth `build.rs` reads — so an include
//! pattern that drops any `.b` or `Bluefile` under `bidamas/` fails the
//! build, not the next consumer.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::Command;

fn bidamas_root() -> Option<PathBuf> {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    [manifest.join("../../bidamas"), manifest.join("bidamas")]
        .into_iter()
        .find(|p| p.is_dir())
}

fn walk(paths: &mut BTreeSet<String>, root: &Path, dir: &Path) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.filter_map(Result::ok) {
        let path = entry.path();
        if path.is_dir() {
            walk(paths, root, &path);
        } else {
            let name = path.file_name().unwrap_or_default().to_string_lossy();
            if name == "Bluefile" || name.ends_with(".b") {
                let rel = path
                    .strip_prefix(root.parent().unwrap_or(root))
                    .unwrap_or(&path);
                paths.insert(rel.to_string_lossy().into_owned());
            }
        }
    }
}

#[test]
fn the_package_ships_every_bidama_file_the_embedded_build_reads() {
    let Some(root) = bidamas_root() else {
        // A registry source carries no ../../bidamas: the packaged files ARE
        // the shipped ones and there is nothing to compare against. The
        // checkout's CI is where this gate bites.
        return;
    };
    let workspace = root
        .parent()
        .map(Path::to_path_buf)
        .expect("bidamas sits inside the workspace");
    let mut wanted = BTreeSet::new();
    walk(&mut wanted, &root, &root);
    assert!(
        !wanted.is_empty(),
        "bidamas/ holds no Bluefile or .b — the embedded build has nothing to read"
    );

    let target =
        std::env::temp_dir().join(format!("blue-lang-pkg-fidelity-{}", std::process::id()));
    let listed = Command::new(env!("CARGO"))
        .args([
            "package",
            "--list",
            "--allow-dirty",
            "--offline",
            "-p",
            "blue-lang-pkg",
        ])
        .current_dir(&workspace)
        .env("CARGO_TARGET_DIR", &target)
        .output()
        .expect("cargo package --list runs");
    let _ = std::fs::remove_dir_all(&target);
    assert!(
        listed.status.success(),
        "cargo package --list failed: {}",
        String::from_utf8_lossy(&listed.stderr)
    );
    let listing = String::from_utf8_lossy(&listed.stdout).into_owned();
    let shipped: BTreeSet<&str> = listing.lines().collect();

    let missing: Vec<&String> = wanted
        .iter()
        .filter(|w| !shipped.contains(w.as_str()))
        .collect();
    assert!(
        missing.is_empty(),
        "the package drops {} file(s) the embedded build reads from the \
         checkout — extend the Cargo.toml include: {:?}",
        missing.len(),
        missing
    );
}
