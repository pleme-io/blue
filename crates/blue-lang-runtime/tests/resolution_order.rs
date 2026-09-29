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

/// What the CHECK resolves `name` to, referenced from namespace `own`.
fn checked_tier(src: &str, loader: &dyn Loader, name: &str, own: &Namespace) -> (Tier, String) {
    let checked =
        check_entry(Entry::anonymous(src), loader, None, Checking::Program).expect("check");
    match checked.names.resolve_from(name, own) {
        Resolution::Found { tier, scope, .. } => (tier, scope.namespace.to_string()),
        other => panic!("{name}: {other:?}"),
    }
}

/// **A bidama's definition replaces a builtin, program-wide.** `first` is a
/// builtin; a bidama that defines its own rebinds it for the importer.
/// Runtime and check agree: Imported beats Builtin.
#[test]
fn a_bidama_definition_replaces_a_builtin() {
    const P: &[(&str, &str)] = &[("mine", "def first(xs)\n  :mine\nend\n")];
    let src = "use(\"mine\")\nfirst([1, 2])\n";
    assert_eq!(keyword(&value(src, &Mem(P))), "mine");
    let own = Namespace::File("<anonymous>".into());
    assert_eq!(
        checked_tier(src, &Mem(P), "first", &own),
        (Tier::Imported, "bidama `mine`".to_string())
    );
}

/// **An importer's definition replaces a bidama's, for the bidama's own calls
/// too.** The runtime's last-define-wins; the check's list says the bidama's
/// reference resolves to its OWN definition. A disagreement, reported here and
/// not changed: which definition runs is the namespace track's to settle.
#[test]
fn an_importer_definition_replaces_the_bidamas_own() {
    const P: &[(&str, &str)] = &[(
        "kotei",
        "def helper()\n  :bidama\nend\n\ndef call_helper()\n  helper()\nend\n",
    )];
    let src = "use(\"kotei\")\n\ndef helper()\n  :entry\nend\n\ncall_helper()\n";
    // The runtime: the entry's `helper`, evaluated last, answers the bidama's call.
    assert_eq!(keyword(&value(src, &Mem(P))), "entry");
    // The check: from inside the bidama, `helper` is Own.
    assert_eq!(
        checked_tier(src, &Mem(P), "helper", &Namespace::Bidama("kotei".into())),
        (Tier::Own, "bidama `kotei`".to_string())
    );
    // From the entry file, the entry's own `helper` is Own as well.
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

/// **For a head, a macro beats every definition — including the definition
/// itself.** The evaluator consults a special form, then a macro, then the
/// environment. `def while(c, body)` lowers to `(define (while c body) …)`,
/// and the stdlib macro `while` expands the signature list before `define`
/// sees it, so the definition cannot even be made: it dies as a malformed
/// `lambda`. No tier ordering describes that; the check follows the
/// evaluator for heads (`NameTable::head_kind`).
#[test]
fn a_macro_beats_a_definition_for_a_head() {
    let src = "def while(c, body)\n  :mine\nend\n\nwhile(false, 1)\n";
    let err = run_in_surface(Entry::anonymous(src), Inputs::new(), &Mem(&[]), None)
        .expect_err("a def named like a stdlib macro cannot be made");
    assert!(err.to_string().contains("bad `lambda`"), "{err}");
}
