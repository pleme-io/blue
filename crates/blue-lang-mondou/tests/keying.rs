//! A loop that passes a large value on every call stops paying for keys once
//! its keying time is spent, not after the chain window's 16,384 calls.
//!
//! Red run (2026-11-20): a tail-recursive walk over a 17,000-byte list ran
//! 4.5 s under `blue run`'s default memo and 0.01 s without it; each call
//! encoded the whole list as its key, and the definition retired only at
//! `Policy::chain_window`.

use std::sync::Arc;

use blue_lang_mondou::recall::{Plan, Policy, Recall, Report};
use blue_lang_runtime::pipeline::run_observed;
use blue_lang_runtime::uses::{Entry, NoLoader};
use blue_lang_runtime::Inputs;

const WALK: &str = "def walk(b, i, n, acc)\n  if i >= n\n    acc\n  else\n    walk(b, i + 1, n, acc + b[i])\n  end\nend\n\nb = range(0, 20000)\nwalk(b, 0, 20000, 0)\n";

fn memoized() -> (String, Report) {
    let mut held = None;
    let ran = run_observed(
        Entry::anonymous(WALK),
        Inputs::new(),
        &NoLoader,
        None,
        |w| {
            let m = Arc::new(Recall::new(
                Arc::clone(w.definitions),
                Plan::of(w.definitions, w.lowered, w.erased),
                None,
                None,
                Policy::default(),
            ));
            held = Some(Arc::clone(&m));
            m
        },
    );
    let memo = held.expect("the program got past the check stage");
    let answer = match ran.and_then(|o| o.outcome) {
        Ok(r) => blue_lang_runtime::literal::render_value(&r.value),
        Err(e) => format!("error: {e}"),
    };
    (answer, memo.report())
}

#[test]
fn a_loop_over_a_large_argument_retires_on_its_keying_budget() {
    let (answer, report) = memoized();
    assert_eq!(answer, "199_990_000");
    let walk = report
        .rows
        .iter()
        .find(|r| r.name == "walk")
        .unwrap_or_else(|| panic!("walk was not cached: {report:?}"));
    assert!(walk.counts.retired, "{report:?}");
    assert!(
        walk.counts.misses < Policy::default().chain_window / 4,
        "walk keyed {} calls before retiring: {report:?}",
        walk.counts.misses
    );
}
