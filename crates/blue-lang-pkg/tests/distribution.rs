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
//! 3. the total test count clears a floor (471 at the time of writing, floored
//!    at 450), so a package silently losing its tests cannot pass as "green".
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
    let forms =
        resolve_uses(forms, &lp).unwrap_or_else(|e| panic!("{name}: imports must resolve: {e}"));

    let report = blue_lang_test::run(&forms);
    (
        report.passed,
        report.failures.iter().map(ToString::to_string).collect(),
    )
}

/// Run `body` on a thread with the stack a real blue process has.
///
/// The Rust test harness gives each test thread 2 MiB; a binary's main thread
/// gets 8. That difference is an artefact of the harness, not a property of
/// blue — and it is load-bearing here, because blue's evaluator recurses per
/// nested call, so the deepest bidama test overflowed 2 MiB while passing
/// under the CLI. Measured: every one of the 17 packages passes
/// `blue test <pkg>` individually; only the harness aborted.
///
/// Running the gate at 8 MiB makes it test what a user actually runs. It does
/// NOT paper over a real limit — see the ceiling recorded below, which is a
/// genuine constraint on blue and is documented rather than raised away.
fn with_real_stack<T: Send + 'static>(body: impl FnOnce() -> T + Send + 'static) -> T {
    std::thread::Builder::new()
        .stack_size(8 * 1024 * 1024)
        .spawn(body)
        .expect("spawn gate thread")
        .join()
        .expect("the distribution gate panicked")
}

/// blue's evaluator recursion ceiling, measured 2026-08-02.
///
/// `junjo.sort` is insertion sort and recurses once per element. At the 8 MiB
/// a real process has it sorts 200 elements and dies somewhere before 400 —
/// silently, as a stack overflow, not a typed error. That is a real limit on
/// the distribution and it is recorded here rather than hidden: any bidama
/// test that walks a list must stay well inside it, and the fix is a
/// trampolined or iterative evaluator, not a larger stack.
const _RECURSION_CEILING_NOTE: () = ();

#[test]
fn every_bidama_passes_its_own_tests() {
    with_real_stack(every_bidama_passes_its_own_tests_inner)
}

fn every_bidama_passes_its_own_tests_inner() {
    let pkgs = packages();
    assert!(
        pkgs.len() >= 19,
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
        total >= 450,
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

/// Every package must have a row in the name ledger, and every row a package.
///
/// This is the gate for the failure that actually happened: fourteen names were
/// minted inline, without the `/naming` collision sweep, and three of them
/// collided with live fleet primitives — one exactly, on the same subject.
/// Nothing caught it, because nothing required a name to have been adjudicated
/// before it shipped.
///
/// A skill cannot enforce that. A skill runs when somebody invokes it, and the
/// entire failure was *not invoking it*. So the requirement lands where adding
/// a package actually happens: a package without a ledger row fails the build.
///
/// **Tier: CI-caught, not unrepresentable.** A careless row still passes — this
/// proves the question was ASKED at the moment the package landed, not that it
/// was answered well. That is the step that was skipped, so that is the step
/// gated.
#[test]
fn every_bidama_has_a_name_ledger_row() {
    let ledger = std::fs::read_to_string(dist().join("NAMES.md"))
        .expect("bidamas/NAMES.md must exist — it is the name adjudication ledger");

    let pkgs = packages();
    let mut missing = Vec::new();
    for name in &pkgs {
        // A row starts with the name in backticks in the first column.
        if !ledger.contains(&format!("| `{name}` |")) {
            missing.push(format!(
                "{name}: no row in NAMES.md — run /naming, sweep the word, its                  near-homophones AND its gloss against the fleet, then add the row"
            ));
        }
    }

    // And the reverse: a row whose package is gone means a rename or deletion
    // left the ledger describing a distribution that no longer exists.
    let mut orphaned = Vec::new();
    for line in ledger.lines() {
        let Some(rest) = line.strip_prefix("| `") else {
            continue;
        };
        let Some(name) = rest.split('`').next() else {
            continue;
        };
        if !pkgs.iter().any(|p| p == name) {
            orphaned.push(format!("{name}: ledger row with no package directory"));
        }
    }

    assert!(
        missing.is_empty() && orphaned.is_empty(),
        "name ledger out of sync with the distribution:\n{}",
        missing
            .into_iter()
            .chain(orphaned)
            .collect::<Vec<_>>()
            .join("\n")
    );
}

/// No two packages may define the same name.
///
/// `use()` inlines a package's forms into ONE FLAT namespace, so two packages
/// defining the same name shadow each other with no error, no warning and no
/// failing test. Whichever import lands second wins.
///
/// This is not hypothetical and it is not rare — it happened DURING the session
/// that wrote this distribution. `retsu` gained `slice(xs, start, count)` and
/// `index_of(xs, v)` while `moji` was independently writing string functions of
/// the same names, at the SAME ARITY. Same arity is what makes it dangerous: a
/// mismatched arity fails loudly, whereas these would have silently answered a
/// string question with a list function.
///
/// The class dies here. A duplicate is a red build naming both packages, which
/// is the whole reason to have a distribution gate rather than trusting each
/// package's own green suite.
#[test]
fn no_two_packages_define_the_same_name() {
    let mut owner: std::collections::BTreeMap<String, String> = std::collections::BTreeMap::new();
    let mut clashes = Vec::new();

    for name in packages() {
        let src = std::fs::read_to_string(dist().join(&name).join(format!("{name}.b")))
            .unwrap_or_else(|e| panic!("{name} source unreadable: {e}"));
        for line in src.lines() {
            let Some(rest) = line.strip_prefix("def ") else {
                continue;
            };
            let Some(fname) = rest.split('(').next().map(str::trim) else {
                continue;
            };
            if fname.is_empty() {
                continue;
            }
            match owner.get(fname) {
                Some(first) if first != &name => clashes.push(format!(
                    "`{fname}` is defined by BOTH {first} and {name} — under \
                     use() the second silently shadows the first"
                )),
                _ => {
                    owner.insert(fname.to_owned(), name.clone());
                }
            }
        }
    }

    assert!(
        clashes.is_empty(),
        "{} cross-package name collision(s):\n{}",
        clashes.len(),
        clashes.join("\n")
    );
    assert!(
        owner.len() >= 700,
        "only {} distinct function names found across the distribution; the \
         scan is not seeing the definitions it is meant to police",
        owner.len()
    );
}
