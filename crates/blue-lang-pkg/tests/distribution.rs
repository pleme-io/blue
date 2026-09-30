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
//! 3. the total test count clears a floor (633 across 35 packages on
//!    2026-09-27, summed from `CATALOG.md`'s tests column, floored at 624),
//!    so a package silently losing its tests
//!    cannot pass as "green".
//!    The count is of each package's OWN tests: imported tests are stripped by
//!    the resolver, so this number does not inflate with the dependency graph.
//!
//! Without those, "0 packages, 0 tests, 0 failures" is a passing run.

use blue_lang_pkg::load_path::LoadPath;
use blue_lang_runtime::uses::{Entry, Loader};
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

    // Through the pipeline's check door and the real loader, as `blue test`
    // runs a package: its tests exercise its dependencies' functions, and
    // what runs is the resolved tree, every definition at its namespaced key.
    // The entry is the package's own file, so it is checked as the bidama.
    let path = dist().join(name).join(format!("{name}.b"));
    let checked = blue_lang_runtime::pipeline::check_entry(
        Entry {
            path: Some(&path),
            text: &src,
        },
        &lp,
        None,
        blue_lang_runtime::pipeline::Checking::WithTests,
    )
    .unwrap_or_else(|e| panic!("{name}: imports must resolve: {e}"));
    assert!(
        checked.outcome.ok(),
        "{name} does not check: {:?}",
        checked
            .outcome
            .errors()
            .map(|d| d.message.clone())
            .collect::<Vec<_>>()
    );
    let report = blue_lang_test::run(&checked.evaluable());
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
        pkgs.len() >= 38,
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
        total >= 628,
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
                // `use("dep")` or `use("dep", [:names])`, however it wraps.
                source
                    .split_whitespace()
                    .collect::<String>()
                    .contains(&format!("use(\"{dep}\"")),
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
    // Only the ledger table's rows are packages; the reserved-name and
    // legacy-prefix tables above it name other things.
    let table = ledger.split("## The ledger").nth(1).unwrap_or(&ledger);
    for line in table.lines() {
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

/// Which duplicates the name gate refuses.
///
/// `Distribution` is the rule blue's single global environment needed: no
/// two packages define one name, because under a flat `use()` the second
/// silently shadowed the first (retsu and moji independently gaining
/// `slice` and `index_of` at the same arity, during the session that wrote
/// this distribution). `Namespace` is the rule per-bidama namespaces need:
/// a name is defined once WITHIN a package. Across packages a duplicate is
/// legal now — `retsu::slice` and `moji::slice` are two keys the runtime
/// cannot confuse — so the class the first rule policed is unrepresentable
/// rather than gated. The first stays, configured off, for a distribution
/// built with a blue from before namespaces.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Scope {
    #[allow(dead_code)]
    Distribution,
    Namespace,
}

const SCOPE: Scope = Scope::Namespace;

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
            let key = match SCOPE {
                Scope::Distribution => fname.to_owned(),
                Scope::Namespace => format!("{name}::{fname}"),
            };
            match owner.get(&key) {
                Some(first) if SCOPE == Scope::Distribution && first != &name => {
                    clashes.push(format!(
                        "`{fname}` is defined by BOTH {first} and {name} — under \
                         use() the second silently shadows the first"
                    ));
                }
                Some(_) if SCOPE == Scope::Namespace => {
                    clashes.push(format!("`{fname}` is defined twice in {name}"));
                }
                _ => {
                    owner.insert(key, name.clone());
                }
            }
        }
    }

    assert!(
        clashes.is_empty(),
        "{} name collision(s):\n{}",
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

/// **The ledger records every bidama's legacy prefix**, as its own
/// `legacy_names(since, prefix)` declares it, and reserves `blue`.
///
/// Red run (2026-09-29): kueri's row removed from the legacy table —
/// `kueri declares legacy_names("0.1.1", "q") and NAMES.md has no row`.
#[test]
fn every_legacy_prefix_is_in_the_ledger() {
    let ledger = std::fs::read_to_string(dist().join("NAMES.md")).expect("NAMES.md");
    assert!(
        ledger.contains("| `blue` | the builtins' qualifier"),
        "`blue` must be reserved"
    );
    let mut problems = Vec::new();
    for name in packages() {
        let src =
            std::fs::read_to_string(dist().join(&name).join(format!("{name}.b"))).expect("source");
        // The prefix form: `legacy_names("0.1.1", "lc")`, two strings.
        for line in src
            .lines()
            .filter(|l| l.starts_with("legacy_names(") && l.split('"').count() == 5)
        {
            let parts: Vec<&str> = line.split('"').collect();
            let (since, prefix) = (parts[1], parts[3]);
            let row = format!("| `{name}` | `{prefix}_` | {since} |");
            if !ledger.contains(&row) {
                problems.push(format!(
                    "{name} declares legacy_names(\"{since}\", \"{prefix}\") and NAMES.md has no row `{row}`"
                ));
            }
        }
    }
    assert!(problems.is_empty(), "{}", problems.join("\n"));
    assert!(
        !packages().iter().any(|p| p == "blue"),
        "no bidama may be named blue"
    );
}

/// Exact-duplicate SHAPES: two definitions whose bodies are the same tree once
/// their parameters are numbered and their own package's qualifier is read as
/// `self`. Measured on the resolved tree, so `join` and `blue::join` are one
/// word and `kinji::refusal_kind` and `kueri::refusal_kind` are each `self`'s.
/// A group is a shape two or more definitions share.
///
/// The count is pinned: moving a twin to one home lowers it, and a new copy
/// raises it and fails here. Lower the pin when a move lands; never raise it.
const SHAPE_GROUPS: usize = 18;

fn shape(pkg: &str, params: &[String], body: &tatara_lisp::Sexp) -> String {
    use tatara_lisp::ast::{Atom, Sexp};
    fn walk(pkg: &str, params: &[String], s: &Sexp) -> Sexp {
        match s {
            Sexp::Atom(Atom::Symbol(n)) => {
                if let Some(i) = params.iter().position(|p| p == n) {
                    Sexp::Atom(Atom::Symbol(format!("%p{i}")))
                } else if let Some(rest) = n.strip_prefix(&format!("{pkg}/")) {
                    Sexp::Atom(Atom::Symbol(format!("self/{rest}")))
                } else {
                    s.clone()
                }
            }
            Sexp::List(xs) => Sexp::List(xs.iter().map(|x| walk(pkg, params, x)).collect()),
            Sexp::Quote(x) => Sexp::Quote(Box::new(walk(pkg, params, x))),
            Sexp::Quasiquote(x) => Sexp::Quasiquote(Box::new(walk(pkg, params, x))),
            Sexp::Unquote(x) => Sexp::Unquote(Box::new(walk(pkg, params, x))),
            Sexp::UnquoteSplice(x) => Sexp::UnquoteSplice(Box::new(walk(pkg, params, x))),
            other => other.clone(),
        }
    }
    format!("{}/{}", params.len(), walk(pkg, params, body))
}

/// Every package's definitions, keyed `pkg/name`, to their shape.
fn shapes() -> std::collections::BTreeMap<String, String> {
    use blue_lang_check::names::Rule;
    let lp = LoadPath::new([dist()]);
    let mut out = std::collections::BTreeMap::new();
    for name in packages() {
        let path = dist().join(&name).join(format!("{name}.b"));
        let src = std::fs::read_to_string(&path).expect("source");
        let checked = blue_lang_runtime::pipeline::check_entry(
            Entry {
                path: Some(&path),
                text: &src,
            },
            &lp,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .unwrap_or_else(|e| panic!("{name}: imports must resolve: {e}"));
        let forms = checked.program.forms();
        let tree = checked.resolve().resolved_tree(forms, Rule::Namespaced);
        let own = format!("{name}/");
        for form in &tree {
            let sexp = form.to_sexp();
            let tatara_lisp::Sexp::List(items) = &sexp else {
                continue;
            };
            let (Some(head), Some(tatara_lisp::Sexp::List(sig))) = (items.first(), items.get(1))
            else {
                continue;
            };
            if head.as_symbol() != Some("define") {
                continue;
            }
            let Some(key) = sig.first().and_then(|s| s.as_symbol()) else {
                continue;
            };
            if !key.starts_with(&own) {
                continue;
            }
            let params: Vec<String> = sig[1..]
                .iter()
                .filter_map(|p| p.as_symbol().map(str::to_owned))
                .collect();
            let body = tatara_lisp::Sexp::List(items[2..].to_vec());
            out.insert(key.to_owned(), shape(&name, &params, &body));
        }
    }
    out
}

#[test]
fn exact_duplicate_shapes_only_fall() {
    let shapes = shapes();
    assert!(
        shapes.len() >= 1500,
        "only {} definitions measured; the scan is not seeing the distribution",
        shapes.len()
    );
    let mut groups: std::collections::BTreeMap<&str, Vec<&str>> = std::collections::BTreeMap::new();
    for (key, s) in &shapes {
        groups.entry(s).or_default().push(key);
    }
    let shared: Vec<&Vec<&str>> = groups.values().filter(|g| g.len() > 1).collect();
    let listing = shared
        .iter()
        .map(|g| g.join(" "))
        .collect::<Vec<_>>()
        .join("\n");
    assert_eq!(
        shared.len(),
        SHAPE_GROUPS,
        "exact-duplicate shape groups moved from {SHAPE_GROUPS} to {}:\n{listing}",
        shared.len()
    );
}

/// **The ledger records every moved name**, as each bidama's moves
/// declaration (`legacy_names(since, [[old, "home::new"], …])`) states it.
///
/// Red run (2026-09-30): kinji's `refuse` row removed —
/// `kinji moves refuse to kyohi::refuse in 0.1.2 and NAMES.md has no row`.
#[test]
fn every_moved_name_is_in_the_ledger() {
    use blue_lang_syntax::scope::{legacy_target, LegacyKind};
    let ledger = std::fs::read_to_string(dist().join("NAMES.md")).expect("NAMES.md");
    let mut declared = Vec::new();
    for name in packages() {
        let src =
            std::fs::read_to_string(dist().join(&name).join(format!("{name}.b"))).expect("source");
        let forms = blue_lang_syntax::parse::parse_program_tree(&src).expect("parses");
        for decl in forms.iter().filter_map(legacy_target) {
            if let LegacyKind::Moved(moves) = decl.kind {
                for m in moves {
                    declared.push(format!(
                        "| `{name}` | `{}` | `{}::{}` | {} |",
                        m.old, m.home, m.new, decl.since
                    ));
                }
            }
        }
    }
    let rows: Vec<&str> = ledger
        .lines()
        .skip_while(|l| !l.starts_with("## Moved names"))
        .skip(1)
        .take_while(|l| !l.starts_with("## "))
        .filter(|l| l.starts_with("| `"))
        .collect();
    let missing: Vec<&String> = declared
        .iter()
        .filter(|d| !rows.contains(&d.as_str()))
        .collect();
    let stale: Vec<&&str> = rows
        .iter()
        .filter(|r| !declared.iter().any(|d| d == **r))
        .collect();
    assert!(
        missing.is_empty() && stale.is_empty(),
        "moved names without a ledger row: {missing:?}\nledger rows no declaration makes: {stale:?}"
    );
    assert!(
        !declared.is_empty(),
        "no moves declaration found; the scan read nothing"
    );
}
