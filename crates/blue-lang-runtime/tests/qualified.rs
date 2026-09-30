//! **Qualified names and import lists, under flat semantics.** `retsu::first`
//! is checked to be retsu's — the package must be one the file `use`s
//! (B0010), and must define the name (B0011) — then lowered to the key it runs
//! under, which while one global environment holds every definition is the
//! bare `first`. `use("retsu", [:first])` lists `first` for bare use, which
//! the namespaced rule reads; the flat rule, and so the runtime, is
//! unchanged by it.

use blue_lang_check::names::Target;
use blue_lang_check::{Code, Namespace};
use blue_lang_runtime::inputs::Inputs;
use blue_lang_runtime::pipeline::{check_entry, run_in_surface, Checking};
use blue_lang_runtime::uses::{Entry, Loader};
use tatara_lisp_eval::Value;

struct Mem(&'static [(&'static str, &'static str)]);

impl Loader for Mem {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        self.0
            .iter()
            .find(|(n, _)| *n == name)
            .map(|(n, s)| vec![(format!("{n}.b"), (*s).to_string())])
            .ok_or_else(|| format!("no bidama named \"{name}\""))
    }
}

const DIST: &[(&str, &str)] = &[
    ("retsu", "def first(xs)\n  :retsu_first\nend\n\ndef size(xs)\n  length(xs)\nend\n"),
    ("kazu", "def abs(n)\n  n\nend\n"),
];

fn codes(src: &str) -> Vec<(Code, String)> {
    let checked =
        check_entry(Entry::anonymous(src), &Mem(DIST), None, Checking::Program).expect("check");
    checked
        .outcome
        .diagnostics
        .iter()
        .map(|d| (d.code, d.message.clone()))
        .collect()
}

/// **The qualifier is exact: `kazu::first` is not retsu's `first`.** Without
/// qualified names it was a parse error; with them unchecked, it would lower
/// to `first` and silently run retsu's.
///
/// Red run (2026-09-29): `qualified_reference`'s definition check skipped —
/// the program checks clean and runs retsu's `first`.
#[test]
fn a_qualifier_that_does_not_own_the_name_is_an_error_naming_the_owner() {
    let src = "use(\"kazu\")\nuse(\"retsu\")\n\nkazu::first([1])\n";
    let checked =
        check_entry(Entry::anonymous(src), &Mem(DIST), None, Checking::Program).expect("check");
    let d = &checked.outcome.diagnostics;
    assert_eq!(d.len(), 1, "{d:?}");
    assert_eq!(d[0].code, Code::B0011);
    assert_eq!(d[0].message, "bidama `kazu` defines no `first`");
    assert_eq!(d[0].help.as_deref(), Some("`first` is defined in bidama `retsu`"));
    assert_eq!(d[0].fixes[0].edits[0].replacement, "retsu::first");
}

#[test]
fn a_qualified_name_runs_the_definition_it_names() {
    let src = "use(\"retsu\")\n\nretsu::first([1])\n";
    assert!(codes(src).is_empty(), "{:?}", codes(src));
    let v = run_in_surface(Entry::anonymous(src), Inputs::new(), &Mem(DIST), None)
        .expect("run")
        .value;
    assert!(matches!(&v, Value::Keyword(k) if &**k == "retsu_first"));
}

#[test]
fn a_qualifier_the_file_does_not_use_is_an_error() {
    let c = codes("use(\"kazu\")\n\nretsu::first([1])\n");
    assert_eq!(c.len(), 1, "{c:?}");
    assert_eq!(c[0].0, Code::B0010);
}

#[test]
fn blue_qualifies_only_builtins() {
    // Bare `length` is the builtin already: the qualifier is B0018.
    assert_eq!(codes("blue::length([1])\n")[0].0, Code::B0018);
    let c = codes("blue::lenght([1])\n");
    assert_eq!(c, vec![(Code::B0011, "`blue::lenght` names no builtin".into())]);
}

#[test]
fn a_listed_name_must_be_the_packages() {
    let c = codes("use(\"retsu\", [:frist])\n");
    assert_eq!(c.len(), 1, "{c:?}");
    assert_eq!(c[0], (Code::B0011, "bidama `retsu` defines no `frist`".into()));
}

/// A listed name is the namespaced rule's import tier; a whole-package `use`
/// lists nothing, so the same bare reference is the builtin there.
#[test]
fn a_listed_name_is_what_the_namespaced_rule_binds() {
    let target = |src: &str| {
        let checked = check_entry(Entry::anonymous(src), &Mem(DIST), None, Checking::Program)
            .expect("check");
        let r = checked.resolve();
        let first = r
            .references
            .iter()
            .find(|r| r.written == "first")
            .expect("a reference to first")
            .clone();
        (first.flat, first.ns)
    };
    let retsu = Target::Def(Namespace::Bidama("retsu".into()), "first".into());
    assert_eq!(
        target("use(\"retsu\", [:first])\n\nfirst([1])\n"),
        (retsu.clone(), retsu.clone())
    );
    assert_eq!(
        target("use(\"retsu\")\n\nfirst([1])\n"),
        (retsu, Target::Builtin("first".into()))
    );
}

/// **`blue::first` is the builtin, whatever the file lists.** The file lists
/// retsu's `first`, so bare `first` is retsu's; the qualifier reaches past it.
///
/// Red run (2026-09-29), before per-namespace keys: the qualifier was lowered
/// to the one global `first`, retsu's, and this returned `:retsu_first`.
#[test]
fn blue_first_is_the_builtin_whatever_the_file_lists() {
    let src = "use(\"retsu\", [:first])\n\n[first([1]), blue::first([1])]\n";
    assert!(codes(src).is_empty(), "{:?}", codes(src));
    let v = run_in_surface(Entry::anonymous(src), Inputs::new(), &Mem(DIST), None)
        .expect("run")
        .value;
    assert_eq!(format!("{v:?}"), "[Keyword(:retsu_first), Int(1)]");
}

/// **A facade makes its members' qualifiers reachable, and no bare name.**
/// `use("fz")`, where fz defines nothing and uses retsu, lets the file write
/// `retsu::first`; bare `first` is still the builtin's (and B0012's).
///
/// Red run (2026-09-29), the facade fixpoint in `program_names` skipped:
/// B0010 (`retsu::first` is qualified by `retsu`, which this file does not
/// `use`) and B0016 (nothing reaches `fz`).
#[test]
fn a_facade_makes_its_members_qualifiers_reachable() {
    const WITH_FACADE: &[(&str, &str)] = &[
        ("retsu", "def first(xs)\n  :retsu_first\nend\n"),
        ("fz", "use(\"retsu\")\n"),
    ];
    let checked = check_entry(
        Entry::anonymous("use(\"fz\")\n\nretsu::first([1])\n"),
        &Mem(WITH_FACADE),
        None,
        Checking::WithTests,
    )
    .expect("check");
    let d: Vec<_> = checked
        .outcome
        .diagnostics
        .iter()
        .map(|d| (d.code, d.message.clone()))
        .collect();
    assert!(d.is_empty(), "{d:?}");
}

/// A bidama at 0.1.1, for the `legacy_names` rows.
struct Versioned(&'static [(&'static str, &'static str)]);

impl Loader for Versioned {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        Mem(self.0).load(name)
    }
    fn version(&self, _: &str, _: Option<&std::path::Path>) -> Option<String> {
        Some("0.1.1".into())
    }
}

/// **A definition that keeps its prefix has two names, one definition**
/// (operator decision 2). kk's `kk_count` keeps its prefix, waived, and
/// `kk::count` names it too. Both spellings resolve to the same entry, and
/// the second name cannot be defined separately. Inside kk a bare `count` is
/// now kk's own (tier 2 over the builtin, decision 4), so kk reaches the
/// list builtin as `blue::count` — written bare, this recursed forever.
///
/// Red run (2026-09-29), the permanent alias skipped in `apply_legacy`: the
/// check refuses — with no second name, kk's `blue::count` is redundant
/// (B0018) and `kk::count` names nothing.
#[test]
fn a_kept_prefix_gives_one_definition_two_names() {
    use blue_lang_check::names::Target;
    const KK: &[(&str, &str)] = &[(
        "kk",
        "legacy_names(\"0.1.1\", \"kk\")\n\n# waive B0013: count is the list builtin, which kk also uses\ndef kk_count(xs)\n  blue::count(xs) + 100\nend\n",
    )];
    let src = "use(\"kk\")\n\n[kk::count([1]), kk::kk_count([1])]\n";
    let checked =
        check_entry(Entry::anonymous(src), &Versioned(KK), None, Checking::Program).expect("check");
    assert!(checked.outcome.diagnostics.is_empty(), "{:?}", checked.outcome.diagnostics);
    let r = checked.resolve();
    let targets: Vec<_> = r
        .references
        .iter()
        .filter(|r| r.written.starts_with("kk/"))
        .map(|r| r.ns.clone())
        .collect();
    let one = Target::Def(Namespace::Bidama("kk".into()), "kk_count".into());
    assert_eq!(targets, vec![one.clone(), one]);
    let v = run_in_surface(Entry::anonymous(src), Inputs::new(), &Versioned(KK), None)
        .expect("run")
        .value;
    assert_eq!(format!("{v:?}"), "[Int(101), Int(101)]");

    // The second name cannot also be a definition.
    const TWICE: &[(&str, &str)] = &[(
        "kk",
        "legacy_names(\"0.1.1\", \"kk\")\n\n# waive B0013: count is the list builtin\ndef kk_count(xs)\n  1\nend\n\ndef count(xs)\n  2\nend\n",
    )];
    let checked = check_entry(Entry::anonymous("use(\"kk\")\n\nkk::count([1])\n"), &Versioned(TWICE), None, Checking::Program)
        .expect("check");
    let codes: Vec<Code> = checked.outcome.diagnostics.iter().map(|d| d.code).collect();
    assert!(codes.contains(&Code::B0022), "{codes:?}");
}
