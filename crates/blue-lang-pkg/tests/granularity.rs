//! **Both distribution granularities, and the DIFFERENCE between them.**
//!
//! blue does not have an opinion about how a library is split up. A consumer
//! may depend on one bidama and get one bidama, or on the facade (`zenbu`) and
//! get all of them — and both are ordinary packages resolved by the same
//! solver, differing only in how many `needs(...)` their manifest declares.
//! Rust's `futures`/`futures-core` split is the precedent; nothing about it
//! required a facade *mechanism*, only a facade *package*.
//!
//! ## The assertion that matters is the difference, not the facade
//!
//! "Depending on the facade resolves all eighteen packages" is a claim that
//! passes just as happily if resolution is broken in the other direction — if
//! `needs("kumiawase")` also dragged the whole distribution in, every facade
//! assertion here would still be green and the fine-grained half of the
//! promise would be silently dead. A facade test alone proves that a bundle
//! arrives, never that anything was left out.
//!
//! So the load-bearing test is [`the_two_granularities_are_measurably_different`]:
//! the fine-grained closure must be a **strict** subset, and the packages in
//! the gap are named rather than counted, so "the difference is 16" cannot be
//! satisfied by an arithmetic accident.
//!
//! ## Two planes, because they can disagree
//!
//! A manifest's `needs(...)` and a source's `use(...)` are separate
//! declarations, and a facade is exactly the shape that can get one right and
//! the other wrong. So granularity is asserted twice:
//!
//! - the **solver** plane — [`blue_lang_pkg::Solver`] over the real
//!   `GitRegistry`, which answers "what does this consumer resolve to";
//! - the **import** plane — [`blue_lang_runtime::pipeline`] through the real
//!   [`LoadPath`], which answers "what can this consumer actually call".
//!
//! The import-plane test carries the control `AUTHORING.md` asks for: it
//! evaluates a call that must FAIL under the fine-grained import before
//! evaluating the same call that must succeed under the facade. Without the
//! failing half, a green run proves the function exists, not that the import
//! delivered it.

use std::collections::BTreeSet;
use std::path::PathBuf;

use blue_lang_pkg::git_registry::GitRegistry;
use blue_lang_pkg::load_path::LoadPath;
use blue_lang_pkg::{Manifest, Range, Registry, Solver};

/// The facade bidama — one `needs`, the whole standard distribution.
const FACADE: &str = "zenbu";

/// A fine-grained consumer with a SHALLOW closure: one hop.
const FINE_SHALLOW: &str = "kumiawase";

/// A fine-grained consumer with a DEEP closure: four hops, still proper.
const FINE_DEEP: &str = "toukei";

fn dist() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("bidamas")
}

/// Every package directory in the distribution.
fn every_bidama() -> BTreeSet<String> {
    std::fs::read_dir(dist())
        .expect("bidamas/ must be readable")
        .filter_map(Result::ok)
        .filter(|e| e.path().join("Bluefile").is_file())
        .filter_map(|e| e.file_name().into_string().ok())
        .collect()
}

/// What a consumer whose manifest is exactly `needs(name, "^0.1")` resolves to.
///
/// This is the resolver's own answer, from the real distribution — not a
/// re-walk of the `needs(...)` edges in this file. A test that re-derived the
/// graph and compared it to itself would be a tautology; asking `Solver` means
/// a resolution bug shows up here rather than being reproduced by the gate.
fn closure_of(name: &str) -> BTreeSet<String> {
    let registry = GitRegistry::scan(dist()).expect("bidamas/ must scan");
    let consumer = Manifest::new().needing(name, Range::parse("^0.1").expect("range"));
    Solver::new(&registry)
        .solve(&consumer)
        .unwrap_or_else(|e| panic!("a consumer needing only {name} must resolve: {e}"))
        .picks
        .into_keys()
        .collect()
}

fn set(names: &[&str]) -> BTreeSet<String> {
    names.iter().map(|s| (*s).to_string()).collect()
}

/// **Fine-grained, one hop: the package and its dependency, and nothing else.**
///
/// `kumiawase` needs only `kazu`, so a consumer naming it must resolve exactly
/// two packages out of the distribution. Asserted as set EQUALITY rather than
/// "contains kazu", because containment is satisfied by resolving everything.
#[test]
fn a_fine_grained_consumer_gets_its_closure_and_not_the_world() {
    let got = closure_of(FINE_SHALLOW);
    assert_eq!(
        got,
        set(&[FINE_SHALLOW, "kazu"]),
        "a consumer needing only {FINE_SHALLOW} must resolve {FINE_SHALLOW} and \
         its one dependency — no more. If {FINE_SHALLOW} genuinely gained an \
         edge, update this set; if it did not, the resolver is over-reaching"
    );

    // Named absences, so the assertion is about packages rather than a count.
    // `moji` has no dependents at all and `toukei` sits at the far end of the
    // deepest chain: if either arrived, resolution is pulling the distribution
    // rather than the closure.
    for stranger in ["moji", "toukei", FACADE] {
        assert!(
            !got.contains(stranger),
            "{stranger} is not reachable from {FINE_SHALLOW} and must not be \
             resolved: {got:?}"
        );
    }
}

/// **Fine-grained, four hops: the whole chain arrives, and it still stops.**
///
/// `toukei -> junjo -> ronri -> {retsu -> kazu, kansuu}`. Same property as
/// above with transitivity switched on, and a separate test because a resolver
/// could get the one-hop case right by never recursing.
///
/// Stated as containment-plus-named-absence rather than set equality, and the
/// difference is deliberate. An exact set pins the *distribution's* shape, not
/// the *resolver's* behaviour, so it goes red on any legitimate new edge —
/// which happened within an hour of this being written, when `toukei` gained
/// `shuugou`. The properness claim does not need the exact set: eleven named
/// packages that must be absent out of nineteen catches an over-reach just as
/// well, and does not punish the distribution for growing. The tight equality
/// assertion lives on the one-hop case above, where the edge is stable.
#[test]
fn a_deep_fine_grained_consumer_gets_the_whole_chain_and_stops() {
    let got = closure_of(FINE_DEEP);

    // Transitivity: every hop of the chain must arrive, four deep.
    for hop in [FINE_DEEP, "junjo", "ronri", "retsu", "kansuu", "kazu"] {
        assert!(
            got.contains(hop),
            "{hop} is on {FINE_DEEP}'s dependency chain and must resolve — a \
             resolver that stops early loses the far end: {got:?}"
        );
    }

    // Properness: the rest of the distribution must NOT come along.
    for stranger in [
        "moji",
        "ongaku",
        "seimei",
        "angou",
        "hizuke",
        "kikagaku",
        "gyouretsu",
        "shinsuu",
        "kumiawase",
        "ran",
        FACADE,
    ] {
        assert!(
            !got.contains(stranger),
            "{stranger} is not reachable from {FINE_DEEP} and must not be \
             resolved: {got:?}"
        );
    }

    assert!(
        got.len() < every_bidama().len(),
        "a closure that covers the distribution is not a closure"
    );
}

/// **The facade: one `needs`, every bidama.**
#[test]
fn the_facade_consumer_gets_every_bidama() {
    let all = every_bidama();
    assert!(
        all.contains(FACADE),
        "{FACADE} must be an ORDINARY package directory in the distribution — \
         a facade that needed special handling would not be a facade"
    );
    assert_eq!(
        closure_of(FACADE),
        all,
        "a consumer needing only {FACADE} must resolve the entire distribution, \
         including {FACADE} itself"
    );
}

/// **The deliverable: the two granularities differ, and by named packages.**
///
/// Everything above passes if resolution is broken so that every consumer gets
/// everything — the fine-grained assertions would fail, but a reader checking
/// only the facade would see green. This states the relationship directly: one
/// closure is a STRICT subset of the other, and the packages in the gap are
/// listed.
#[test]
fn the_two_granularities_are_measurably_different() {
    let fine = closure_of(FINE_SHALLOW);
    let facade = closure_of(FACADE);

    assert!(
        fine.is_subset(&facade),
        "the facade must deliver a superset of any single package's closure; \
         fine={fine:?} facade={facade:?}"
    );
    assert!(
        fine.len() < facade.len(),
        "the two granularities resolved to the same size ({}), so either the \
         facade is not bundling or the fine-grained path is pulling the world",
        fine.len()
    );

    let only_via_facade: BTreeSet<String> = facade.difference(&fine).cloned().collect();
    // Named, not counted. Each of these is a package a `needs("kumiawase")`
    // consumer must NOT be paying for.
    for withheld in ["moji", "toukei", "ongaku", "seimei", "hizuke", "angou"] {
        assert!(
            only_via_facade.contains(withheld),
            "{withheld} must arrive with the facade and NOT with {FINE_SHALLOW}; \
             gap was {only_via_facade:?}"
        );
    }
    assert_eq!(
        only_via_facade.len(),
        every_bidama().len() - fine.len(),
        "the gap must be exactly the distribution minus the fine-grained \
         closure: {only_via_facade:?}"
    );
}

/// Evaluate a blue program against the real distribution.
fn eval(src: &str) -> Result<String, String> {
    blue_lang_runtime::pipeline::run_with_loader(
        src,
        blue_lang_runtime::inputs::Inputs::new(),
        &LoadPath::new([dist()]),
    )
    .map(|run| {
        let mut s = String::new();
        use std::fmt::Write as _;
        write!(s, "{:?}", run.value).expect("format");
        s
    })
    .map_err(|e| e.to_string())
}

/// **The same granularity, at the plane a program actually experiences.**
///
/// The solver tests above read manifests. This one runs code: `needs(...)` and
/// `use(...)` are separate declarations, and a facade is precisely the shape
/// that can have one without the other.
///
/// The middle assertion is the control. Without it, the last one is green
/// because `median` exists somewhere — not because importing the facade is what
/// put it in scope.
#[test]
fn granularity_holds_at_the_import_plane_too() {
    // In closure: kumiawase's own function.
    assert_eq!(
        eval("use(\"kumiawase\")\nfactorial(5)").expect("kumiawase must import"),
        "Int(120)"
    );

    // THE CONTROL. `median` lives only in toukei, which is outside
    // kumiawase's closure, so this must fail as an unbound name.
    let err = eval("use(\"kumiawase\")\nmedian([1, 2, 3])").expect_err(
        "median resolved under a kumiawase-only import — either it is ambient \
         (making the facade assertion below vacuous) or the fine-grained import \
         is pulling the whole distribution",
    );
    assert!(
        err.contains("median"),
        "the failure must name the unbound function, or it may be failing for \
         an unrelated reason and still reading as proof: {err}"
    );

    // And the facade delivers exactly what the fine-grained import withheld.
    assert_eq!(
        eval("use(\"zenbu\")\nmedian([1, 2, 3])").expect("the facade must import toukei"),
        "Int(2)"
    );
}

/// The facade must be reached by ORDINARY resolution — no special case.
///
/// If `zenbu` needed the solver, the registry or the nix builder to know its
/// name, the generality the operator asked for would be a claim about one
/// hard-coded package rather than about the mechanism. It is asserted by
/// absence: nothing in this file, and nothing in the crates it drives, names
/// the facade except as a string a consumer typed.
#[test]
fn the_facade_is_an_ordinary_bidama_with_many_needs() {
    let registry = GitRegistry::scan(dist()).expect("scan");
    let declared = literal_needs_count(FACADE);

    assert_eq!(
        declared,
        every_bidama().len() - 1,
        "the facade must declare every OTHER bidama; a distribution that grew \
         without the facade growing is a facade that no longer means 'all'"
    );
    assert_eq!(
        registry.len(),
        every_bidama().len(),
        "the facade must be scanned by the same registry pass as every other \
         package, from the same directory layout"
    );
}

/// How many `needs("…")` STRING LITERALS a manifest contains.
///
/// Deliberately the same dull text split `bidamas/mk-bidama.nix`'s `depsOf`
/// performs, because the point of the test below is to compare that view
/// against a different one — not to be a better parser than it.
fn literal_needs_count(name: &str) -> usize {
    std::fs::read_to_string(dist().join(name).join("Bluefile"))
        .unwrap_or_else(|e| panic!("{name}/Bluefile: {e}"))
        .matches("needs(\"")
        .count()
}

/// **Nix's regex view and blue's evaluated view must agree, package by package.**
///
/// `mk-bidama.nix` extracts the dependency graph by splitting the manifest text
/// on `needs("`, and states its own ceiling: a `needs` whose argument is
/// *computed* is invisible to nix. A Bluefile is blue code, so that is a real
/// limit rather than a hypothetical — and the facade is the single most likely
/// place for someone to reach past it, because "every sibling in the
/// distribution" is exactly the sort of list an author wants to compute rather
/// than type seventeen times.
///
/// The failure that would cause is one-sided and therefore quiet: blue's
/// resolver EVALUATES the manifest, so `blue deps` and every test in this file
/// would stay green while the nix closure silently shipped a facade with no
/// dependencies in it — "recorded and not delivered", which `mk-bidama.nix`
/// records as a bug that already happened once.
///
/// This makes the divergence loud instead. It is not a fix for the ceiling —
/// **tier: CI-gate-caught, not unrepresentable.** The fix named in
/// `mk-bidama.nix` is a `blue bluefile --deps --json` subcommand so nix consumes
/// blue's own evaluation; until that exists, this at least refuses to let the
/// two views drift apart unnoticed.
#[test]
fn the_regex_and_evaluated_dependency_views_agree() {
    let registry = GitRegistry::scan(dist()).expect("scan");
    let mut disagreed = Vec::new();

    for name in every_bidama() {
        let version = *registry
            .versions(&name)
            .first()
            .unwrap_or_else(|| panic!("{name} must have a version"));
        let evaluated = registry
            .manifest(&name, version)
            .unwrap_or_else(|| panic!("{name} must have a manifest"))
            .needs
            .len();
        let by_regex = literal_needs_count(&name);
        if evaluated != by_regex {
            disagreed.push((name, by_regex, evaluated));
        }
    }

    assert!(
        disagreed.is_empty(),
        "nix reads dependencies with a text split and blue reads them by \
         EVALUATING the manifest; these packages have a `needs` the text split \
         cannot see, so their nix closure will be missing dependencies that \
         resolve fine in blue — (package, by-regex, evaluated): {disagreed:?}"
    );

    // Anti-vacuity: a run where every package happens to declare nothing would
    // pass the loop above having compared zeros.
    assert!(
        literal_needs_count(FACADE) >= 17,
        "the comparison above is only meaningful over manifests that actually \
         declare dependencies"
    );
}
