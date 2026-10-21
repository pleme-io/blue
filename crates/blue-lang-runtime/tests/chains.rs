use blue_lang_runtime::pipeline::{check_entry, lower_with, Checking};
use blue_lang_runtime::uses::{Entry, NoLoader};
use std::path::Path;
use tatara_lisp::Spanned;
use tatara_lisp_eval::vm::Budget;

fn checked(src: &str) -> blue_lang_runtime::pipeline::Checked {
    let entry = Entry {
        path: Some(Path::new("stored.b")),
        text: src,
    };
    check_entry(entry, &NoLoader, None, Checking::WithTests).expect("checks")
}

fn codes(src: &str) -> Vec<String> {
    checked(src)
        .outcome
        .diagnostics
        .iter()
        .map(|d| d.code.as_str().to_string())
        .collect()
}

fn lowered(src: &str, simplify: bool) -> Vec<Spanned> {
    let c = checked(src);
    if simplify {
        c.erased()
    } else {
        blue_lang_runtime::erase_types(&lower_with(&c.program, &c.names, false))
    }
}

fn shown(forms: &[Spanned]) -> Vec<String> {
    forms.iter().map(|f| f.to_sexp().to_string()).collect()
}

fn run_within(forms: &[Spanned], fuel: usize) -> Option<String> {
    let mut interp = blue_lang_runtime::interpreter_hostless();
    interp
        .set_budget(Budget {
            fuel: Some(fuel),
            max_depth: Some(tatara_lisp_eval::vm::DEFAULT_MAX_DEPTH),
            quantum: None,
        })
        .expect("budget");
    let mut last = tatara_lisp_eval::Value::Nil;
    for f in forms {
        last = interp.eval_top_form(f, &mut ()).ok()?;
    }
    Some(blue_lang_runtime::literal::render_value(&last))
}

fn least_fuel(forms: &[Spanned]) -> usize {
    let (mut lo, mut hi) = (1, 1 << 22);
    assert!(
        run_within(forms, hi).is_some(),
        "does not run in {hi} steps"
    );
    while lo < hi {
        let mid = (lo + hi) / 2;
        if run_within(forms, mid).is_some() {
            hi = mid;
        } else {
            lo = mid + 1;
        }
    }
    lo
}

const CHAIN: &str = "def go(x)\n  to_s(to_s(to_s(to_s(x))))\nend\n\ngo(5)\n";
const PLAIN: &str = "def go(x)\n  to_s(x)\nend\n\ngo(5)\n";

#[test]
fn a_redundant_chain_is_reported_once_per_redundant_call() {
    assert_eq!(codes(CHAIN), ["B0045", "B0045", "B0045"]);
    assert_eq!(codes(PLAIN), Vec::<String>::new());
}

#[test]
fn a_chain_that_changes_a_value_is_left_alone() {
    for src in [
        "def f(x)\n  to_int(to_int(x))\nend\n",
        "def f(x)\n  to_float(to_float(x))\nend\n",
        "def f(x)\n  to_s(to_int(x))\nend\n",
        "def f(x)\n  upcase(downcase(x))\nend\n",
    ] {
        assert_eq!(codes(src), Vec::<String>::new(), "{src}");
    }
}

#[test]
fn a_local_called_like_a_conversion_is_not_the_conversion() {
    let src = "def f(to_s)\n  to_s(to_s(1))\nend\n";
    assert_eq!(codes(src), Vec::<String>::new());
    let unsimplified = shown(&lowered(src, false));
    assert_eq!(shown(&lowered(src, true)), unsimplified);
}

#[test]
fn the_canonical_rewrite_writes_the_simplified_chain() {
    let c = checked(CHAIN);
    let tree = c.canonical_entry(CHAIN).expect("canonical");
    let plain = checked(PLAIN).canonical_entry(PLAIN).expect("canonical");
    assert_eq!(
        tree.iter()
            .map(|f| f.to_sexp().to_string())
            .collect::<Vec<_>>(),
        plain
            .iter()
            .map(|f| f.to_sexp().to_string())
            .collect::<Vec<_>>()
    );
}

#[test]
fn the_evaluator_runs_the_simplified_chain_without_the_author_formatting_it() {
    assert_eq!(shown(&lowered(CHAIN, true)), shown(&lowered(PLAIN, true)));
    assert_ne!(shown(&lowered(CHAIN, false)), shown(&lowered(PLAIN, false)));
}

#[test]
fn the_simplified_chain_takes_fewer_evaluation_steps_and_the_same_value() {
    let with = lowered(CHAIN, true);
    let without = lowered(CHAIN, false);
    let (a, b) = (least_fuel(&with), least_fuel(&without));
    assert!(a < b, "with the pass {a} steps, without {b}");
    assert_eq!(run_within(&with, 1 << 22), run_within(&without, 1 << 22));
    println!("chain steps: {a} with the pass, {b} without");
}
