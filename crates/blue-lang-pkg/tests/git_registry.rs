//! The git-backed registry, resolving the REAL distribution in this repo.
//!
//! Not a fixture. These tests point at `bidamas/` — the packages that actually
//! ship — so "packaging is git-based" is demonstrated against the tree rather
//! than against a mock that agrees with itself. A registry test that builds its
//! own input proves the test can build input.

use blue_lang_pkg::git_registry::GitRegistry;
use blue_lang_pkg::solve::Registry;
use std::path::PathBuf;

fn dist() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("bidamas")
}

#[test]
fn scanning_the_real_distribution_finds_every_bidama() {
    let reg = GitRegistry::scan(dist()).expect("bidamas/ must scan");
    assert!(
        reg.len() >= 3,
        "found {} bidamas; this asserts a FLOOR rather than 'some', because a \
         gate that accepts zero passes vacuously on an empty distribution",
        reg.len()
    );
    for pkg in ["kazu", "moji", "retsu"] {
        assert!(
            !reg.versions(pkg).is_empty(),
            "{pkg} is in bidamas/ but the git registry cannot see it"
        );
    }
}

#[test]
fn a_manifest_is_read_from_the_package_not_the_directory_name() {
    let reg = GitRegistry::scan(dist()).expect("scan");
    let v = *reg.versions("kazu").first().expect("kazu has a version");
    // Keyed by the name the MANIFEST declares, not the folder: the registry
    // only has an entry under "kazu" because kazu/Bluefile says
    // package("kazu", …). A folder-derived key would resolve even if the
    // manifest named something else, which is the silent-wrong-package case.
    assert!(
        reg.manifest("kazu", v).is_some(),
        "kazu@{v:?} must resolve from the manifest-declared name"
    );
    assert!(
        reg.versions("Bluefile").is_empty(),
        "nothing may resolve under a filename — that would mean keys come from \
         the filesystem rather than from package(...)"
    );
}

/// The dependency edge — what makes this a distribution rather than a pile of
/// files.
#[test]
fn retsu_declares_its_dependency_on_kazu() {
    let reg = GitRegistry::scan(dist()).expect("scan");
    let v = *reg.versions("retsu").first().expect("retsu has a version");
    let m = reg.manifest("retsu", v).expect("retsu manifest");
    assert!(
        m.needs.contains_key("kazu"),
        "retsu/Bluefile declares needs(\"kazu\", …) and the resolver must SEE \
         it, or dependency resolution is untested across the whole \
         distribution: {:?}",
        m.needs
    );
}

/// A missing directory is a typed error naming the path, not a panic.
#[test]
fn a_missing_distribution_is_a_typed_error_with_the_path() {
    let err = GitRegistry::scan(dist().join("definitely-not-here"))
        .expect_err("a missing directory must not scan");
    let msg = err.to_string();
    assert!(
        msg.contains("definitely-not-here"),
        "the error must name the path, or a packaging failure sends the reader \
         grepping a distribution to find which package broke: {msg}"
    );
}
