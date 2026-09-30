//! **What the runtime's name resolution actually does today**, pinned beside
//! the check's tier list (`blue_lang_check::names::RESOLUTION_ORDER`).
//!
//! The runtime has no tiers. `resolve_uses` splices every file into one
//! program and every top-level `define` lands in ONE global environment, so a
//! name is bound to whichever definition of it was evaluated LAST. Each test
//! below runs a program and reads which definition answered, so a change to
//! either side — the runtime growing namespaces, or the check's order moving —
//! shows up here as a red test rather than as a silent disagreement.
//!
//! Where the runtime and the check's list disagree, the test says so. None of
//! the disagreements changes a verdict of the check stage (every name
//! involved is bound either way); they change which definition RUNS, and
//! closing them is the namespace track's work, not this file's.

use blue_lang_check::names::{Resolution, Tier};
use blue_lang_check::Namespace;
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

fn value(src: &str, loader: &dyn Loader) -> Value {
    run_in_surface(Entry::anonymous(src), Inputs::new(), loader, None)
        .unwrap_or_else(|e| panic!("{src:?}: {e}"))
        .value
}

fn keyword(v: &Value) -> String {
    match v {
        Value::Keyword(k) => k.to_string(),
        other => panic!("expected a keyword, got {other:?}"),
    }
}

/// What the CHECK resolves `name` to, referenced from namespace `own` in the
/// entry's LAST top-level form.
fn checked_tier(src: &str, loader: &dyn Loader, name: &str, own: &Namespace) -> (Tier, String) {
    let checked =
        check_entry(Entry::anonymous(src), loader, None, Checking::Program).expect("check");
    let last = checked.program.forms().len() - 1;
    match checked.names.resolve_from(name, own, last) {
        Resolution::Found { tier, scope, .. } => (tier, scope.namespace.to_string()),
        other => panic!("{name}: {other:?}"),
    }
}

/// **An imported definition beats a builtin, for the importer only.** A
/// bidama that defines `first` is `first` in a file that lists it; the
/// builtin stays `blue::first`, and stays `first` everywhere else.
#[test]
fn an_imported_definition_beats_a_builtin_for_its_importer() {
    const P: &[(&str, &str)] = &[("mine", "def first(xs)\n  :mine\nend\n")];
    let src = "use(\"mine\", [:first])\nfirst([1, 2])\n";
    assert_eq!(keyword(&value(src, &Mem(P))), "mine");
    let own = Namespace::File("<anonymous>".into());
    assert_eq!(
        checked_tier(src, &Mem(P), "first", &own),
        (Tier::Imported, "bidama `mine`".to_string())
    );
    // Qualified, both are reachable at once.
    let both = "use(\"mine\")\n[mine::first([1, 2]), blue::first([1, 2])]\n";
    assert_eq!(format!("{:?}", value(both, &Mem(P))), "[Keyword(:mine), Int(1)]");
}

/// **A bidama's own calls reach its own definition, whatever its importer
/// defines.** This was the runtime's second divergence from the check: one
/// global environment let the entry's `helper`, evaluated last, answer the
/// bidama's call. Keys are per namespace now (`kotei/helper`, `%root/helper`),
/// and the runtime agrees with the check.
///
/// Red run (2026-09-29), `pipeline::lower` returning the written tree (the
/// flat runtime): `left: "entry" right: "bidama"`.
#[test]
fn a_bidamas_own_call_reaches_its_own_definition() {
    const P: &[(&str, &str)] = &[(
        "kotei",
        "def helper()\n  :bidama\nend\n\ndef call_helper()\n  helper()\nend\n",
    )];
    let src = "use(\"kotei\", [:call_helper])\n\ndef helper()\n  :entry\nend\n\ncall_helper()\n";
    assert_eq!(keyword(&value(src, &Mem(P))), "bidama");
    assert_eq!(
        checked_tier(src, &Mem(P), "helper", &Namespace::Bidama("kotei".into())),
        (Tier::Own, "bidama `kotei`".to_string())
    );
    assert_eq!(
        checked_tier(
            src,
            &Mem(P),
            "helper",
            &Namespace::File("<anonymous>".into())
        ),
        (Tier::Own, "this file".to_string())
    );
}

/// **A package's definition does not replace a builtin another package
/// calls.** `a` defines `first`; `b` calls the builtin `first`. Under one
/// global environment b's call reached a's definition (the `member`
/// incident, AUTHORING.md); now b gets the builtin.
///
/// Red run (2026-09-29), the flat runtime: `[:a, :a]`.
#[test]
fn a_definition_does_not_replace_the_builtin_another_bidama_calls() {
    const P: &[(&str, &str)] = &[
        ("a", "def first(_xs)\n  :a\nend\n"),
        ("b", "def firsts(xs)\n  first(xs)\nend\n"),
    ];
    let src = "use(\"a\", [:first])\nuse(\"b\", [:firsts])\n[first([1]), firsts([1])]\n";
    assert_eq!(format!("{:?}", value(src, &Mem(P))), "[Keyword(:a), Int(1)]");
}

/// **Two bidamas may define one name**; each is reachable qualified. Before
/// namespaces this was a collision the distribution gate refused (retsu and
/// moji each gaining `slice`).
#[test]
fn two_bidamas_define_one_name_and_both_are_callable() {
    const P: &[(&str, &str)] = &[
        ("p_one", "def slice(xs, a, b)\n  :one\nend\n"),
        ("p_two", "def slice(xs, a, b)\n  :two\nend\n"),
    ];
    let src = "use(\"p_one\")\nuse(\"p_two\")\n[p_one::slice([], 0, 1), p_two::slice([], 0, 1)]\n";
    assert_eq!(
        format!("{:?}", value(src, &Mem(P))),
        "[Keyword(:one), Keyword(:two)]"
    );
}

/// **A qualified macro expands, and its template means the definer's
/// names.** `mac::twice` expands in the importer; the template's `helper`
/// is mac's, although the importer defines one too.
#[test]
fn a_qualified_macro_expands_with_the_definers_names() {
    const P: &[(&str, &str)] = &[(
        "mac",
        "def helper(x)\n  x * 10\nend\n\ndefmacro twice(e)\n  quote\n    helper(unquote(e)) + helper(unquote(e))\n  end\nend\n",
    )];
    let src = "use(\"mac\")\n\ndef helper(x)\n  x\nend\n\nmac::twice(3)\n";
    assert_eq!(format!("{:?}", value(src, &Mem(P))), "Int(60)");
}

/// **A local beats every definition**, at runtime and in the check.
#[test]
fn a_local_beats_a_definition() {
    let src = "def first(_xs)\n  :global\nend\n\ndef f(first)\n  first\nend\n\nf(:local)\n";
    assert_eq!(keyword(&value(src, &Mem(&[]))), "local");
    let checked =
        check_entry(Entry::anonymous(src), &Mem(&[]), None, Checking::Program).expect("check");
    assert!(
        checked.outcome.diagnostics.is_empty(),
        "{:?}",
        checked.outcome.diagnostics
    );
}

/// **For a head, a program's own definition beats a builtin macro.** One
/// global environment made `def while(c, body)` impossible: the stdlib macro
/// `while` expanded the definition's own signature, and it died as a
/// malformed `lambda`. Keyed per namespace (`%root/while`), the definition is
/// made, and the tier order decides the call: own (tier 2) beats builtin
/// (tier 4), for a head as for any reference. A special form is in no tier
/// and cannot be defined.
///
/// Red run (2026-09-29), before per-namespace keys: `bad `lambda``.
#[test]
fn an_own_definition_beats_a_builtin_macro_for_a_head() {
    let src = "def while(c, body)\n  :mine\nend\n\nwhile(false, 1)\n";
    assert_eq!(keyword(&value(src, &Mem(&[]))), "mine");
    assert_eq!(
        checked_tier(src, &Mem(&[]), "while", &Namespace::File("<anonymous>".into())),
        (Tier::Own, "this file".to_string())
    );
}

/// **Both rules, per reference, for the migration to be proven on.** junjo
/// calls retsu's `first` and never `use`s retsu: retsu arrives through ronri.
/// Today's flat rule binds that `first` to retsu's, because retsu's
/// definition is in the one global environment; per-bidama namespaces bind
/// it to the builtin, because junjo neither defines nor imports `first`. That
/// disagreement is exactly what the explicit-reference migration closes.
///
/// Red run (2026-09-29): `NameTable::flat_target` made to skip program
/// definitions: `left: Builtin("first") right: Def(Bidama("retsu"), "first")`.
#[test]
fn a_transitive_definition_is_the_flat_binding_and_not_the_namespaced_one() {
    use blue_lang_check::names::Target;
    const P: &[(&str, &str)] = &[
        ("retsu", "def first(xs)\n  nil\nend\n"),
        ("ronri", "use(\"retsu\")\n\ndef both(a, b)\n  a && b\nend\n"),
    ];
    let src = "use(\"ronri\")\n\ndef head(xs)\n  first(xs)\nend\n";
    let checked =
        check_entry(Entry::anonymous(src), &Mem(P), None, Checking::Program).expect("check");
    let resolved = checked.resolve();
    let first: Vec<_> = resolved
        .references
        .iter()
        .filter(|r| r.written == "first")
        .collect();
    assert_eq!(first.len(), 1, "{first:?}");
    assert_eq!(
        first[0].flat,
        Target::Def(Namespace::Bidama("retsu".into()), "first".into())
    );
    assert_eq!(first[0].ns, Target::Builtin("first".into()));
    // The resolved trees say the same, as symbols.
    use blue_lang_check::names::Rule;
    let entry_form = |rule| {
        resolved
            .resolved_tree(checked.program.forms(), rule)
            .last()
            .expect("the entry's def")
            .to_sexp()
            .to_string()
    };
    assert_eq!(
        entry_form(Rule::Flat),
        "(define (%root/head xs) (retsu/first xs))"
    );
    assert_eq!(entry_form(Rule::Namespaced), "(define (%root/head xs) (first xs))");
}

/// **Own beats builtin**, the third tier boundary: a file's own `count` is
/// its `count`, over the builtin's.
#[test]
fn an_own_definition_beats_a_builtin() {
    let src = "def count(_xs)\n  :mine\nend\n\ncount([1])\n";
    assert_eq!(keyword(&value(src, &Mem(&[]))), "mine");
    assert_eq!(
        checked_tier(src, &Mem(&[]), "count", &Namespace::File("<anonymous>".into())),
        (Tier::Own, "this file".to_string())
    );
}

/// **Resolution is deterministic**: the same program with its imports in
/// every order resolves every name to the same thing and runs to the same
/// value. The order of `use` forms is layout (B0015 fixes one), never
/// meaning. Every permutation of three imports, each defining a name the
/// others also define, one of them listed.
///
/// Red run (2026-09-29), the flat runtime: the permutations disagree on
/// `pick`, which is whichever package loaded last.
#[test]
fn resolution_does_not_depend_on_import_order() {
    const P: &[(&str, &str)] = &[
        ("q_a", "def pick()\n  :a\nend\n"),
        ("q_b", "def pick()\n  :b\nend\n"),
        ("q_c", "def pick()\n  :c\nend\n"),
    ];
    let uses = [
        "use(\"q_a\")",
        "use(\"q_b\", [:pick])",
        "use(\"q_c\")",
    ];
    let orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]];
    let mut seen = std::collections::BTreeSet::new();
    for o in orders {
        let waived: Vec<String> = o
            .iter()
            .map(|i| format!("# waive B0015: the order is what this test varies\n{}", uses[*i]))
            .collect();
        let src = format!("{}\n\n[pick(), q_a::pick(), q_c::pick()]\n", waived.join("\n"));
        seen.insert(format!("{:?}", value(&src, &Mem(P))));
    }
    assert_eq!(
        seen.into_iter().collect::<Vec<_>>(),
        vec!["[Keyword(:b), Keyword(:a), Keyword(:c)]".to_string()]
    );
}
