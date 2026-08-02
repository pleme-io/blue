//! The bidama distribution — every package's behaviour, asserted.
//!
//! A `bidamas/` directory whose files merely PARSE is not a standard library;
//! it is a folder. These tests run each bidama's source and assert what its
//! functions actually compute, so a distribution claim rests on behaviour.
//!
//! ## Why the tests are here and not in blue
//!
//! Blue has no test-assertion form of its own yet (`blue-lang-test` handles
//! the `spec/*.b` corpus, which is blue describing itself). Until it does, the
//! honest place to assert a bidama's behaviour is Rust, where a failure is a
//! red build. Writing them in blue first would mean the distribution's
//! correctness depended on an untested assertion form — pushing the trust
//! problem one layer down rather than solving it.
//!
//! Tier: **CI-caught**, and each case names the value it expects rather than
//! merely checking `is_ok()` — a test that only asserts "it ran" would pass
//! against a function that returns the wrong number every time.

use std::path::PathBuf;

fn bidama(name: &str) -> String {
    let p = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("bidamas")
        .join(name)
        .join(format!("{name}.b"));
    std::fs::read_to_string(&p)
        .unwrap_or_else(|e| panic!("bidama {name} unreadable at {}: {e}", p.display()))
}

/// Run a bidama's source followed by an expression, and return the value's
/// debug form.
fn eval_with(name: &str, expr: &str) -> String {
    let src = format!("{}\n{expr}", bidama(name));
    match blue_lang_runtime::pipeline::run(&src) {
        Ok(r) => format!("{:?}", r.value),
        Err(e) => panic!("{name} + `{expr}` failed to run: {e:?}"),
    }
}

#[test]
fn kazu_abs_and_sign() {
    assert_eq!(eval_with("kazu", "abs(0 - 5)"), "Int(5)");
    assert_eq!(eval_with("kazu", "abs(5)"), "Int(5)");
    assert_eq!(eval_with("kazu", "abs(0)"), "Int(0)");
    // Sign must return -1/0/1, and ZERO is the case implementations drop —
    // a two-branch sign() silently reports 0 as positive.
    assert_eq!(eval_with("kazu", "sign(0 - 7)"), "Int(-1)");
    assert_eq!(eval_with("kazu", "sign(0)"), "Int(0)");
    assert_eq!(eval_with("kazu", "sign(7)"), "Int(1)");
}

#[test]
fn kazu_min_max_and_clamp() {
    assert_eq!(eval_with("kazu", "max(3, 9)"), "Int(9)");
    assert_eq!(eval_with("kazu", "min(3, 9)"), "Int(3)");
    // Equal arguments must not depend on comparison direction.
    assert_eq!(eval_with("kazu", "max(4, 4)"), "Int(4)");
    assert_eq!(eval_with("kazu", "min(4, 4)"), "Int(4)");
    // Clamp at and beyond both bounds — the interior case alone would pass
    // against an implementation that ignores its bounds entirely.
    assert_eq!(eval_with("kazu", "clamp(5, 1, 10)"), "Int(5)");
    assert_eq!(eval_with("kazu", "clamp(0 - 3, 1, 10)"), "Int(1)");
    assert_eq!(eval_with("kazu", "clamp(99, 1, 10)"), "Int(10)");
    assert_eq!(eval_with("kazu", "clamp(1, 1, 10)"), "Int(1)");
    assert_eq!(eval_with("kazu", "clamp(10, 1, 10)"), "Int(10)");
}

#[test]
fn kazu_pow_and_even() {
    // exp = 0 is the identity case a recursive pow gets wrong by returning 0.
    assert_eq!(eval_with("kazu", "pow(2, 0)"), "Int(1)");
    assert_eq!(eval_with("kazu", "pow(2, 1)"), "Int(2)");
    assert_eq!(eval_with("kazu", "pow(2, 10)"), "Int(1024)");
    assert_eq!(eval_with("kazu", "pow(5, 3)"), "Int(125)");
    assert_eq!(eval_with("kazu", "even(4)"), "Bool(true)");
    assert_eq!(eval_with("kazu", "even(7)"), "Bool(false)");
    assert_eq!(eval_with("kazu", "even(0)"), "Bool(true)");
}

#[test]
fn moji_predicates() {
    assert_eq!(eval_with("moji", "empty(\"\")"), "Bool(true)");
    assert_eq!(eval_with("moji", "empty(\"a\")"), "Bool(false)");
    assert_eq!(eval_with("moji", "present(\"\")"), "Bool(false)");
    assert_eq!(eval_with("moji", "present(\"ab\")"), "Bool(true)");
}

#[test]
fn moji_longer_resolves_ties_deterministically() {
    assert_eq!(eval_with("moji", "longer(\"a\", \"bbb\")"), "Str(\"bbb\")");
    assert_eq!(eval_with("moji", "longer(\"aaa\", \"b\")"), "Str(\"aaa\")");
    // The tie. Documented to favour the first argument; if that ever flips,
    // callers see different answers for equal-length input across versions.
    assert_eq!(eval_with("moji", "longer(\"ab\", \"cd\")"), "Str(\"ab\")");
}

#[test]
fn moji_counts_characters_not_bytes() {
    // The property blue's own stdlib exists to provide. A byte-length
    // implementation returns 3 for a CJK character and 4 for an emoji —
    // exactly the bug the UTF-8 crash in the LSP came from.
    assert_eq!(eval_with("moji", "\"日本語\".length"), "Int(3)");
    assert_eq!(eval_with("moji", "\"🔥\".length"), "Int(1)");
}

#[test]
fn retsu_recursion() {
    assert_eq!(eval_with("retsu", "sum_to(0)"), "Int(0)");
    assert_eq!(eval_with("retsu", "sum_to(1)"), "Int(1)");
    assert_eq!(eval_with("retsu", "sum_to(10)"), "Int(55)");
    assert_eq!(eval_with("retsu", "count_down(50)"), "Int(0)");
}

/// Every bidama directory must carry a Bluefile, and it must be a valid one.
///
/// The manifest is itself blue code (`package(name, version)`), so this also
/// proves the manifest language stays runnable — a Bluefile that stopped
/// parsing would be invisible until someone tried to resolve the package.
#[test]
fn every_bidama_has_a_parseable_bluefile() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("bidamas");
    let mut seen = 0usize;
    for e in std::fs::read_dir(&root)
        .unwrap_or_else(|err| panic!("bidamas/ unreadable: {err}"))
        .filter_map(Result::ok)
    {
        if !e.path().is_dir() {
            continue;
        }
        let name = e.file_name().to_string_lossy().to_string();
        let manifest = e.path().join("Bluefile");
        let text = std::fs::read_to_string(&manifest)
            .unwrap_or_else(|err| panic!("{name} has no Bluefile: {err}"));
        assert!(
            text.contains(&format!("package(\"{name}\"")),
            "{name}/Bluefile must declare package(\"{name}\", …) — a manifest \
             naming a different package resolves to the wrong thing silently"
        );
        assert!(
            blue_lang_syntax::parse_program(&text).is_ok(),
            "{name}/Bluefile does not parse as blue — the manifest IS blue code"
        );
        seen += 1;
    }
    assert!(
        seen >= 3,
        "found only {seen} bidamas; this gate would pass vacuously on an \
         empty distribution"
    );
}
