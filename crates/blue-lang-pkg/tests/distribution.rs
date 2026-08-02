//! The distribution gate: every bidama, its own tests, run by `cargo test`.
//!
//! ## Why the tests live in the packages
//!
//! The older gate (`blue-lang-runtime/tests/bidama_distribution.rs`, still
//! present for the original three packages) asserts bidama behaviour in Rust —
//! `assert_eq!(eval_with("kazu", "abs(0 - 5)"), "Int(5)")`. That does not
//! scale past about three packages, and worse, it puts a package's tests
//! somewhere other than the package: adding a bidama meant editing a Rust file
//! in another crate, so the natural failure mode was a package that shipped
//! with no tests at all and nothing to say so.
//!
//! Each bidama now carries its own `test` blocks **in blue**, and this gate
//! runs all of them. Adding a package adds its tests automatically; the
//! distribution is self-describing, and `cargo test` still fails when any of
//! it breaks.
//!
//! ## The three anti-vacuity floors
//!
//! A gate that walks a directory can pass by walking nothing, so this asserts
//! floors rather than "no failures":
//!
//! 1. the distribution holds at least as many packages as it did when written;
//! 2. **every** package declares at least one test IN ITS OWN SOURCE — counted
//!    before imports resolve, because a dependency's tests come along with the
//!    import and would otherwise count as the importer's. It caught `moji`
//!    shipping with zero, and the own-source refinement caught that `kikagaku`
//!    could have done the same invisibly;
//! 3. the total test count clears a floor (82 at the time of writing, floored
//!    at 80), so a package silently losing its tests cannot pass as "green".
//!    The count is of each package's OWN tests: imported tests are stripped by
//!    the resolver, so this number does not inflate with the dependency graph.
//!
//! Without those, "0 packages, 0 tests, 0 failures" is a passing run.

use blue_lang_pkg::load_path::LoadPath;
use blue_lang_runtime::uses::{resolve_uses, Loader};
use std::path::PathBuf;

fn dist() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("bidamas")
}

/// Every package directory in the distribution, sorted.
fn packages() -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dist())
        .expect("bidamas/ must be readable")
        .filter_map(Result::ok)
        .filter(|e| e.path().join("Bluefile").is_file())
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    names.sort();
    names
}

/// How many `test` blocks a package declares IN ITS OWN SOURCE.
///
/// Counted before imports are resolved, and that is the entire point. The
/// first version of this gate counted tests from the *resolved* program, so a
/// package's dependencies' tests counted as its own — which meant a package
/// with zero tests of its own passed as long as it imported something tested.
///
/// Measured: emptying every test out of `kikagaku` (which imports kazu and retsu)
/// left the gate green, because kazu's and retsu's tests came along with the
/// import. Only `moji`, which has no dependencies, was ever really checked.
/// A gate that only catches the leaf packages is worse than none — it reports
/// coverage it never measured.
fn own_test_count(name: &str) -> usize {
    let src = std::fs::read_to_string(dist().join(name).join(format!("{name}.b")))
        .unwrap_or_else(|e| panic!("{name} source unreadable: {e}"));
    let forms = blue_lang_runtime::pipeline::parse(&src)
        .unwrap_or_else(|e| panic!("{name} must parse: {e}"));
    blue_lang_test::split(&forms).0.len()
}

/// Run one bidama's own `test` blocks, returning (passed, failures).
fn run_tests(name: &str) -> (usize, Vec<String>) {
    let lp = LoadPath::new([dist()]);
    let sources = lp
        .load(name)
        .unwrap_or_else(|e| panic!("{name} must load: {e}"));
    let src = sources
        .into_iter()
        .map(|(_, s)| s)
        .collect::<Vec<_>>()
        .join("\n");

    let forms = blue_lang_runtime::pipeline::parse(&src)
        .unwrap_or_else(|e| panic!("{name} must parse: {e}"));
    // Through the real loader: a package's tests exercise its dependencies'
    // functions, so resolution has to happen or every test errors on `use`.
    let forms = resolve_uses(forms, &lp)
        .unwrap_or_else(|e| panic!("{name}: imports must resolve: {e}"));

    let report = blue_lang_test::run(&forms);
    (
        report.passed,
        report.failures.iter().map(ToString::to_string).collect(),
    )
}

#[test]
fn every_bidama_passes_its_own_tests() {
    let pkgs = packages();
    assert!(
        pkgs.len() >= 17,
        "found {} bidamas; this asserts a FLOOR because a gate that walks a \
         directory passes vacuously when the directory is empty: {pkgs:?}",
        pkgs.len()
    );

    let mut total = 0usize;
    let mut broken: Vec<String> = Vec::new();
    for name in &pkgs {
        let (passed, failures) = run_tests(name);
        total += passed;
        // A package with no tests OF ITS OWN is the regression this catches.
        // `moji` shipped that way and read as green, because zero failures is
        // zero failures — and `kikagaku` would have too, hidden behind its
        // dependencies' tests, until this counted own-source blocks.
        if own_test_count(name) == 0 {
            broken.push(format!("{name}: ZERO tests of its own — untested"));
        }
        for f in failures {
            broken.push(format!("{name}: {f}"));
        }
    }

    assert!(
        broken.is_empty(),
        "{} problem(s) across the distribution:\n{}",
        broken.len(),
        broken.join("\n")
    );
    assert!(
        total >= 80,
        "only {total} bidama tests ran across {} packages; the distribution \
         lost tests without any of them failing",
        pkgs.len()
    );
}

/// Every package's manifest must name the package its directory is called.
///
/// The registry keys on `package(...)`, not the directory, precisely so the
/// filesystem cannot lie about identity — which is only a real protection if
/// something checks the two agree.
#[test]
fn every_manifest_names_its_own_directory() {
    for name in packages() {
        let manifest = std::fs::read_to_string(dist().join(&name).join("Bluefile"))
            .unwrap_or_else(|e| panic!("{name}/Bluefile unreadable: {e}"));
        assert!(
            manifest.contains(&format!("package(\"{name}\"")),
            "{name}/Bluefile does not declare package(\"{name}\", …)"
        );
    }
}

/// Every dependency a manifest declares must exist in the distribution.
///
/// A `needs(...)` naming a package that is not here resolves to nothing and
/// fails at import time with an unbound symbol pointing at innocent code.
#[test]
fn every_declared_dependency_exists() {
    let pkgs = packages();
    for name in &pkgs {
        let manifest =
            std::fs::read_to_string(dist().join(name).join("Bluefile")).expect("manifest");
        for chunk in manifest.split("needs(\"").skip(1) {
            let dep = chunk.split('"').next().unwrap_or_default().to_string();
            assert!(
                pkgs.contains(&dep),
                "{name} needs \"{dep}\", which is not in the distribution"
            );
        }
    }
}

/// Every package a manifest declares must actually be imported by its source.
///
/// The gap this closes is the one the whole import system was built for:
/// `retsu` declared `needs("kazu")` for weeks while its source never mentioned
/// kazu, because the language had no import form. A declared-but-unused
/// dependency is a claim about the distribution that nothing was checking.
#[test]
fn every_declared_dependency_is_actually_imported() {
    for name in packages() {
        let dir = dist().join(&name);
        let manifest = std::fs::read_to_string(dir.join("Bluefile")).expect("manifest");
        let source = std::fs::read_to_string(dir.join(format!("{name}.b"))).expect("source");
        for chunk in manifest.split("needs(\"").skip(1) {
            let dep = chunk.split('"').next().unwrap_or_default();
            assert!(
                source.contains(&format!("use(\"{dep}\")")),
                "{name} declares needs(\"{dep}\") but never writes use(\"{dep}\") — \
                 the manifest claims a dependency the code does not have"
            );
        }
    }
}
