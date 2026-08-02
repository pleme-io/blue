//! `interpreter_hostless` must FORK the prebuilt substrate, never rebuild it.
//!
//! Guards a measured 48× regression risk, and it is a cost gate rather than a
//! correctness gate for a specific reason: rebuilding the stdlib per run is
//! perfectly *correct*. Every behavioural test stays green while it happens.
//! Only a timing assertion can see it, which is why this file exists next to
//! the ones that check what the interpreter computes.
//!
//! ## What was measured (2026-08-01)
//!
//! Profiling a trivial blue program found one dominant cost:
//!
//! ```text
//! parse                     9.6 µs
//! check                     1.6 µs
//! interpreter_hostless()  5 820 µs   <- 98.4% of the run
//! ```
//!
//! `Interpreter::new()` is 24 µs of that; the rest is `install_full_stdlib_with`
//! rebuilding blue's whole surface (`map`, `filter`, string ops) from scratch on
//! every single run. `fork` already existed upstream for exactly this — its own
//! `fork_cost.rs` opens with *"cheapness is the entire reason it exists"* — and
//! blue was not using it.
//!
//! | | per call |
//! |---|---|
//! | rebuild | 9.03 ms |
//! | fork    | 0.102 ms |
//! | config-shaped `run()` before | 5.92 ms |
//! | config-shaped `run()` after  | 0.12 ms |
//!
//! ## Why the threshold is loose
//!
//! A wall-clock assert on shared CI is a flake generator, so the bound is set
//! at 20× the observed fork cost — far above timing noise, far below the
//! rebuild it guards against. It is a TRIPWIRE for "someone reintroduced the
//! rebuild", not a benchmark. Tightening it to look impressive would convert a
//! reliable gate into an intermittent one, which trains people to ignore it.

use std::time::Instant;

/// Forking must be dramatically cheaper than rebuilding — the property the
/// optimisation rests on.
///
/// Compares the two directly in-process, so a machine being slow moves BOTH
/// arms and the ratio survives. An absolute threshold would not.
#[test]
fn interpreter_hostless_forks_rather_than_rebuilding() {
    use tatara_lisp_eval::{install_full_stdlib_with, Interpreter};

    // Untimed warm pass so neither arm pays first-touch cost.
    let _ = blue_lang_runtime::interpreter_hostless();

    let n = 20;
    let t = Instant::now();
    for _ in 0..n {
        let _ = blue_lang_runtime::interpreter_hostless();
    }
    let forked = t.elapsed() / n;

    let t = Instant::now();
    for _ in 0..n {
        let mut i: Interpreter<()> = Interpreter::new();
        install_full_stdlib_with(&mut i, &mut ());
    }
    let rebuilt = t.elapsed() / n;

    assert!(
        forked * 20 < rebuilt,
        "interpreter_hostless() costs {forked:?} vs {rebuilt:?} to rebuild — \
         that is not a fork. Someone reintroduced the per-run stdlib build, \
         which is CORRECT and 48x slower, so no behavioural test can see it."
    );
}

/// The forked interpreter must actually work — cheapness is worthless if the
/// substrate is not there.
///
/// Probes BOTH substrate layers a fork could lose, which is why there are two
/// cases rather than one:
///
/// - `1 + 2` exercises tatara-lisp's own installed primitives.
/// - `"ab".length` exercises **blue's layer-3 stdlib** (`install_blue_stdlib`),
///   which the interpreter builder documents as absent from tatara-lisp
///   entirely. A fork that carried the base and dropped blue's own layer would
///   pass a single-case test while breaking every string operation.
///
/// The first draft of this test used `[1,2,3].map { |x| x * 2 }` and failed —
/// with a **Parse** error, not an eval one. Blue has no Ruby block syntax yet,
/// so the probe never reached the interpreter and proved nothing about the
/// fork. Recorded because the failure mode is instructive: a substrate test
/// written in syntax the language does not have reports a runtime defect that
/// is really a test bug, and it fails in the direction that looks alarming.
#[test]
fn the_forked_interpreter_still_has_every_substrate_layer() {
    let base = blue_lang_runtime::pipeline::run("1 + 2");
    assert!(
        base.is_ok(),
        "base primitives unavailable in a forked interpreter: {base:?}"
    );

    let blue_layer = blue_lang_runtime::pipeline::run("\"ab\".length");
    assert!(
        blue_layer.is_ok(),
        "blue's OWN stdlib layer (string ops) is missing from the fork — the \
         fork carried tatara-lisp's primitives and dropped layer 3: {blue_layer:?}"
    );
}

/// Repeated runs stay cheap, which is the case that actually matters.
///
/// shikumi loading a `.b` config and an LSP re-evaluating on keystroke both do
/// exactly this. Before the fork each of those paid a full stdlib build.
#[test]
fn repeated_runs_do_not_each_pay_for_a_stdlib() {
    let src = "def config\n  1\nend\nconfig";
    let _ = blue_lang_runtime::pipeline::run(src);

    let n = 20;
    let t = Instant::now();
    for _ in 0..n {
        let r = blue_lang_runtime::pipeline::run(src);
        assert!(r.is_ok(), "config-shaped program must run: {r:?}");
    }
    let per = t.elapsed() / n;

    assert!(
        per < std::time::Duration::from_millis(3),
        "a config-shaped run takes {per:?}; it was 5.92 ms before the fork and \
         0.12 ms after, so anything near the old number means the stdlib is \
         being rebuilt per run again"
    );
}
