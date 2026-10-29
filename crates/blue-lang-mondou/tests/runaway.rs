//! A runaway under the call memo is bounded by the fuel budget exactly as
//! without it (spec row `fn.runaway_is_bounded`). Its own test binary, since
//! the execution bounds are set once per process.
//!
//! Red run (2026-10-29): a tail-call chain's first call held its definition
//! open as a miss in flight, so `spin` never retired; every one of its calls
//! paid for a key and a lookup, and the conformance memo column ran past its
//! 45 s limit on CI before the 50M budget ran out. `spin` reported
//! `retired: false` after 333333 misses.

use std::path::PathBuf;
use std::sync::Arc;

use blue_lang_mondou::recall::{Plan, Policy, Recall, Report};
use blue_lang_mondou::store::{Identity, Store, DEFAULT_MAX_BYTES};
use blue_lang_runtime::pipeline::{run_in_surface, run_observed};
use blue_lang_runtime::uses::{Entry, NoLoader};
use blue_lang_runtime::{ExecutionBounds, Inputs};

const RUNAWAY: &str = "def spin(n)\n  spin(n + 1)\nend\n\nspin(0)\n";

const STEPS: usize = 2_000_000;

fn memoized(store: Option<Arc<Store>>) -> (String, Report) {
    let mut held = None;
    let ran = run_observed(
        Entry::anonymous(RUNAWAY),
        Inputs::new(),
        &NoLoader,
        None,
        |w| {
            let m = Arc::new(Recall::new(
                Arc::clone(w.definitions),
                Plan::of(w.definitions, w.lowered, w.erased),
                store,
                None,
                Policy::default(),
            ));
            held = Some(Arc::clone(&m));
            m
        },
    );
    let memo = held.expect("the program got past the check stage");
    let _ = memo.flush();
    let answer = match ran.and_then(|o| o.outcome) {
        Ok(r) => blue_lang_runtime::literal::render_value(&r.value),
        Err(e) => format!("error: {e}"),
    };
    (answer, memo.report())
}

#[test]
fn a_runaway_under_the_memo_fails_on_the_fuel_budget_and_its_loop_retires() {
    blue_lang_runtime::set_execution_bounds(ExecutionBounds {
        max_steps: Some(STEPS),
        ..ExecutionBounds::DEFAULT
    });
    let plain = match run_in_surface(Entry::anonymous(RUNAWAY), Inputs::new(), &NoLoader, None) {
        Ok(r) => panic!("the runaway returned {:?}", r.value),
        Err(e) => format!("error: {e}"),
    };
    assert!(plain.contains("fuel budget"), "{plain}");
    let dir: PathBuf = std::env::temp_dir().join(format!("blue-runaway-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let store = Arc::new(
        Store::open(&dir, Identity::from_parts(&[b"runaway"]), DEFAULT_MAX_BYTES).expect("store"),
    );
    for store in [None, Some(store)] {
        let (answer, report) = memoized(store);
        assert_eq!(answer, plain, "the memo changed what the runaway does");
        let spin = report
            .rows
            .iter()
            .find(|r| r.name == "spin")
            .unwrap_or_else(|| panic!("spin was not cached: {report:?}"));
        assert!(spin.counts.retired, "{report:?}");
        assert!(
            spin.counts.misses <= Policy::default().chain_window + 1,
            "{report:?}"
        );
    }
    let _ = std::fs::remove_dir_all(&dir);
}
