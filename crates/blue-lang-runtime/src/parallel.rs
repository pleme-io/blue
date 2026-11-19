//! When `par_map` runs apart, and on how many workers (W4.1 and W6.1 of
//! docs/FACTS.md): from two measured costs, never a size written down. The
//! first element's call, timed as it runs on the caller's thread, prices the
//! rest; one worker interpreter, built once and timed, prices a worker. The
//! rest runs apart only when what it saves is more than twice what a worker
//! costs, and the pool takes each further worker only while that worker saves
//! more than twice its own start (rule R20).

use std::sync::OnceLock;
use std::time::{Duration, Instant};

/// The word a spread map is renamed to (rule R17).
pub const WORD: &str = "par_map";

/// Whether rule R17 renames maps: the project declares more than one
/// scheduler, `BLUE_PARMAP=off` is not set, and no command holds the rewrites
/// off ([`crate::fuse::hold_off`]).
#[must_use]
pub fn spreads() -> bool {
    blue_lang_proc::node::schedulers() > 1
        && !crate::fuse::held_off()
        && !crate::kitei::switched_off("R17")
}

/// How many workers map the `rest` elements left after the first, whose call
/// took `first`: 1 means the caller's own thread. Rule R20 sizes the pool from
/// the measured load; `BLUE_POOL=fixed` takes every scheduler once the map runs
/// apart.
#[must_use]
pub fn workers(first: Duration, rest: usize) -> usize {
    let n = blue_lang_proc::node::schedulers();
    if crate::kitei::switched_off("R20") {
        fixed(n, first, rest, setup)
    } else {
        sized(n, first, rest, setup)
    }
}

fn load(first: Duration, rest: usize) -> Duration {
    first.saturating_mul(u32::try_from(rest).unwrap_or(u32::MAX))
}

/// The rule before R20, with the schedulers `n` and the cost of a worker
/// `setup` given: with `n` workers the rest takes `first * rest / n` plus one
/// setup, so it runs apart on all `n` when `first * rest * (n - 1) / n` is
/// more than twice `setup`. Each worker takes one element at least.
fn fixed(n: usize, first: Duration, rest: usize, setup: impl Fn() -> Duration) -> usize {
    let n = n.min(rest);
    if n <= 1 {
        return 1;
    }
    let saved =
        load(first, rest) / u32::try_from(n).unwrap_or(1) * u32::try_from(n - 1).unwrap_or(0);
    if saved > setup() * 2 {
        n
    } else {
        1
    }
}

/// Rule R20: once the map runs apart (as [`fixed`] decides), the `k`-th worker
/// shortens the load `w` from `w / (k - 1)` to `w / k`, a saving of
/// `w / (k * (k - 1))`, so the pool is the largest `k`, at least 2 and at most
/// `n` and the elements, whose last worker saves more than twice `setup`.
fn sized(n: usize, first: Duration, rest: usize, setup: impl Fn() -> Duration) -> usize {
    let n = n.min(rest);
    if fixed(n, first, rest, &setup) == 1 {
        return 1;
    }
    let w = load(first, rest);
    let twice = setup() * 2;
    let mut k = 2;
    while k < n {
        let pairs = u32::try_from((k + 1) * k).unwrap_or(u32::MAX);
        if w / pairs > twice {
            k += 1;
        } else {
            break;
        }
    }
    k
}

fn setup() -> Duration {
    static MEASURED: OnceLock<Duration> = OnceLock::new();
    *MEASURED.get_or_init(|| {
        let started = Instant::now();
        drop(crate::child_interpreter());
        started.elapsed()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const SETUP: Duration = Duration::from_millis(5);

    #[test]
    fn work_worth_more_than_twice_a_worker_runs_apart_and_less_stays_home() {
        let ms = Duration::from_millis;
        assert_eq!(fixed(4, ms(1), 1000, || SETUP), 4);
        assert_eq!(fixed(4, Duration::from_micros(1), 1000, || SETUP), 1);
        assert_eq!(fixed(1, ms(100), 1000, || SETUP), 1);
        assert_eq!(fixed(8, ms(100), 3, || SETUP), 3);
        assert_eq!(fixed(4, ms(100), 1, || SETUP), 1);
        assert_eq!(fixed(4, ms(100), 0, || SETUP), 1);
    }

    #[test]
    fn the_pool_takes_a_worker_only_while_it_saves_more_than_twice_its_start() {
        let ms = Duration::from_millis;
        assert_eq!(sized(16, ms(1), 1000, || SETUP), 10);
        assert_eq!(fixed(16, ms(1), 1000, || SETUP), 16);
        assert_eq!(sized(4, ms(1), 1000, || SETUP), 4);
        assert_eq!(sized(16, ms(1), 10, || SETUP), 1);
        assert_eq!(sized(16, ms(1), 12, || SETUP), 2);
        assert_eq!(sized(16, ms(1), 21, || SETUP), 2);
        assert_eq!(sized(64, ms(100), 3, || SETUP), 3);
        assert_eq!(sized(1, ms(100), 1000, || SETUP), 1);
        assert_eq!(sized(4, ms(100), 0, || SETUP), 1);
    }

    #[test]
    fn a_sized_pool_is_never_larger_than_the_fixed_one_and_runs_apart_as_it_does() {
        let us = Duration::from_micros;
        for first in [1, 10, 100, 1000, 10_000] {
            for rest in [0, 1, 2, 5, 50, 500] {
                for n in [1, 2, 4, 16] {
                    let f = fixed(n, us(first), rest, || SETUP);
                    let s = sized(n, us(first), rest, || SETUP);
                    assert!(s <= f, "n {n} first {first} rest {rest}: {s} > {f}");
                    assert_eq!(s > 1, f > 1, "n {n} first {first} rest {rest}");
                }
            }
        }
    }
}
