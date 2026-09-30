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
