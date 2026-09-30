//! Building a collection in a `reduce` is linear, not quadratic (G7).
//!
//! blue overrides `append` and `cdr` (for its `[]`-not-nil semantics), so the
//! persistent `List` upstream is only reached if those overrides share
//! structure too; this gate reads the path a blue program actually takes.
//!
//! Measured with the release binary (blue at tatara-lisp 0.3.64 against 0.4),
//! reduce over 10k / 20k / 40k elements: `append(acc, [x])` 0.14 / 0.55 /
//! 2.49 s user -> 0.01 / 0.01 / 0.03 s; `assoc(acc, x, x)` 0.23 / 0.95 /
//! 3.98 s -> 0.01 / 0.03 / 0.07 s.
//!
//! Red run, recorded 2026-09-30: with blue's `append` restored to extending a
//! `Vec` with every operand's elements: `append scales as 15.9x for 4x the
//! elements` (5k 0.48 s, 20k 7.70 s in debug).

use std::time::Instant;

/// The minimum of three runs: load only ever adds time, so the minimum is the
/// cost the code has.
fn seconds(src: &str) -> f64 {
    (0..3)
        .map(|_| {
            let t = Instant::now();
            blue_lang_runtime::run(src).expect("runs");
            t.elapsed().as_secs_f64()
        })
        .fold(f64::INFINITY, f64::min)
}

#[test]
fn reduce_builds_lists_and_maps_in_linear_time() {
    let list = |n: usize| {
        format!("xs = reduce(fn(acc, x) append(acc, [x]) end, [], range({n}))\nlength(xs)")
    };
    let map = |n: usize| {
        format!("m = reduce(fn(acc, x) assoc(acc, x, x) end, {{}}, range({n}))\nget(m, 7)")
    };
    for (what, src) in [
        ("append", &list as &dyn Fn(usize) -> String),
        ("assoc", &map),
    ] {
        seconds(&src(1_000));
        let small = seconds(&src(5_000));
        let large = seconds(&src(20_000));
        let ratio = large / small;
        println!("{what}: 5k {small:.3}s, 20k {large:.3}s, ratio {ratio:.1}");
        assert!(
            ratio < 8.0,
            "{what} scales as {ratio:.1}x for 4x the elements"
        );
    }
}
