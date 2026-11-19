//! When `par_map` runs apart (W4.1 of docs/FACTS.md): from two measured
//! costs, never a size written down. The first element's call, timed as it
//! runs on the caller's thread, prices the rest; one worker interpreter, built
//! once and timed, prices a worker. The rest runs on the project's
//! schedulers only when what they save is more than twice what they cost.

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
/// took `first`: 1 means the caller's own thread.
#[must_use]
pub fn workers(first: Duration, rest: usize) -> usize {
    decide(blue_lang_proc::node::schedulers(), first, rest, setup)
}

/// The rule [`workers`] applies, with the schedulers `n` and the cost of a
/// worker `setup` given: with `n` workers the rest takes `first * rest / n`
/// plus one setup, so it runs apart when `first * rest * (n - 1) / n` is more
/// than twice `setup`. Each worker takes one element at least.
fn decide(n: usize, first: Duration, rest: usize, setup: impl Fn() -> Duration) -> usize {
    let n = n.min(rest);
    if n <= 1 {
        return 1;
    }
    let saved = first.saturating_mul(u32::try_from(rest).unwrap_or(u32::MAX))
        / u32::try_from(n).unwrap_or(1)
        * u32::try_from(n - 1).unwrap_or(0);
    if saved > setup() * 2 {
        n
    } else {
        1
    }
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
        assert_eq!(decide(4, ms(1), 1000, || SETUP), 4);
        assert_eq!(decide(4, Duration::from_micros(1), 1000, || SETUP), 1);
        assert_eq!(decide(1, ms(100), 1000, || SETUP), 1);
        assert_eq!(decide(8, ms(100), 3, || SETUP), 3);
        assert_eq!(decide(4, ms(100), 1, || SETUP), 1);
        assert_eq!(decide(4, ms(100), 0, || SETUP), 1);
    }
}
