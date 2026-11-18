//! The call memo's doors: `blue run`, `blue test` and `blue profile` can
//! answer the calls of every definition `blue-lang-mondou` proves pure from
//! a table keyed by content (`blue_lang_mondou::recall`), in process and in
//! the store under `$XDG_CACHE_HOME/blue/memo`.
//!
//! When nothing names a mode, `blue run` plans the memo itself: in process
//! for a pure definition that calls itself at two or more places (rule R2),
//! and through the store, shared roots included, for a program whose pure
//! definitions already have a stored result that cost [`COSTLY`] or more to
//! compute (rule R8, [`costly`]); every other run is as before the memo
//! existed. `BLUE_MEMO` names a mode instead: `off` turns the memo off,
//! `process` keeps the table for the run only, `on` (or `store`) also reads
//! and writes the store. `--no-memo` on a command turns
//! it off again for that command. `blue test --coverage` and `blue trace`
//! always run without it: they report what the code does, and an answered
//! call does nothing. So does a run under an execution bound other than the
//! shipped one (`BlueConfig`'s `max_call_depth`, `max_steps`): an answered
//! call takes no steps and no depth, so it would let a run the bound refuses
//! finish. A store that cannot be opened (a read-only home, a build sandbox)
//! leaves the in-process table: the run is the same either way.

use std::sync::Arc;

use blue_lang_mondou::recall::{Plan, Policy, Recall, Report};
use blue_lang_mondou::store::{self, Store};
use blue_lang_runtime::observe::{CallObserver, Definitions};

pub(crate) const ENV: &str = "BLUE_MEMO";

/// How a run is memoized.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Mode {
    Off,
    Process,
    Store,
}

impl Mode {
    /// `BLUE_MEMO`'s value read as a mode; `None` for a value it does not
    /// name, which leaves the memo off.
    pub(crate) fn parse(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "" | "off" | "0" | "false" | "no" => Some(Mode::Off),
            "process" => Some(Mode::Process),
            "on" | "1" | "true" | "yes" | "store" => Some(Mode::Store),
            _ => None,
        }
    }

    pub(crate) fn persist(self) -> bool {
        self == Mode::Store
    }

    pub(crate) fn of(no_memo: bool, env: Option<&str>, cfg: &crate::config::BlueConfig) -> Self {
        if no_memo || cfg.execution_bounds() != blue_lang_runtime::ExecutionBounds::DEFAULT {
            return Mode::Off;
        }
        env.and_then(Mode::parse).unwrap_or(Mode::Off)
    }
}

/// The mode this command runs in.
pub(crate) fn mode(no_memo: bool, cfg: &crate::config::BlueConfig) -> Mode {
    Mode::of(no_memo, std::env::var(ENV).ok().as_deref(), cfg)
}

/// `mode`, or off when a project's own bounds hold the run, as the
/// operator's do in [`Mode::of`]: an answered call skips the steps and bytes
/// a bound counts.
pub(crate) fn unless_bounded(
    mode: Mode,
    bounds: Option<blue_lang_runtime::ExecutionBounds>,
) -> Mode {
    if bounds.is_some() {
        Mode::Off
    } else {
        mode
    }
}

fn store() -> Option<Arc<Store>> {
    store::open_tier("memo").map(Arc::new)
}

/// A memo over a program about to run, wrapping `inner` when a tool already
/// watches it. `persist` opens the store as well as the in-process table.
pub(crate) fn over(
    persist: bool,
    definitions: &Arc<Definitions>,
    lowered: &[blue_lang_syntax::Spanned],
    erased: &[blue_lang_syntax::Spanned],
    inner: Option<Arc<dyn CallObserver>>,
) -> Arc<Recall> {
    let plan = Plan::of(definitions, lowered, erased);
    Arc::new(Recall::new(
        Arc::clone(definitions),
        plan,
        if persist { store() } else { None },
        inner,
        Policy::default(),
    ))
}

/// Whether `blue run` plans the memo itself: nothing named a mode
/// (`BLUE_MEMO` unset, no `--no-memo`) and the shipped bounds hold. Set
/// `BLUE_MEMO=off` to run every program without it.
pub(crate) fn planning(no_memo: bool, cfg: &crate::config::BlueConfig) -> bool {
    !no_memo
        && std::env::var_os(ENV).is_none()
        && cfg.execution_bounds() == blue_lang_runtime::ExecutionBounds::DEFAULT
}

/// The planner `blue run` offers the pipeline: an in-process memo over the
/// program when it can cache one of the definitions that repeat their own
/// calls, named by what the author wrote.
pub(crate) fn planned(
    watched: &blue_lang_runtime::pipeline::Watched<'_>,
    repeating: &[(usize, String)],
) -> Option<blue_lang_runtime::pipeline::Planned> {
    if repeating.is_empty() {
        return None;
    }
    let recall = over(
        false,
        watched.definitions,
        watched.lowered,
        watched.erased,
        None,
    );
    let name = watched
        .definitions
        .iter()
        .enumerate()
        .find(|(i, d)| {
            let mut held = Vec::new();
            if repeating.iter().any(|(top, _)| *top == d.top_level) {
                held.push("self_overlapping");
            }
            if matches!(recall.plan().target(*i), Some(Ok(_))) {
                held.push("pure");
            }
            blue_lang_runtime::kitei::fires("R2", &held)
        })
        .map(|(_, d)| d.name.clone())?;
    Some((
        recall,
        format!(
            "the memo answers `{name}`, a pure definition that calls itself at two or more places, so its repeated calls are lookups"
        ),
    ))
}

/// The least a stored result must have cost before [`costly`] plans the
/// store-backed memo by default: the run then takes the walker, so a hit must
/// save more than leaving the VM costs.
pub(crate) const COSTLY: std::time::Duration = std::time::Duration::from_millis(20);

struct Flushing(Arc<Recall>);

impl CallObserver for Flushing {
    fn enter(
        &self,
        call: &blue_lang_runtime::observe::Call<'_>,
        args: &[tatara_lisp_eval::Value],
    ) -> Option<tatara_lisp_eval::Value> {
        self.0.enter(call, args)
    }

    fn leave(
        &self,
        call: &blue_lang_runtime::observe::Call<'_>,
        exit: blue_lang_runtime::observe::Exit<'_>,
    ) {
        self.0.leave(call, exit);
    }
}

impl Drop for Flushing {
    fn drop(&mut self) {
        let _ = self.0.flush();
    }
}

fn store_holds_anything() -> bool {
    let local = store::cache_root()
        .is_some_and(|r| std::fs::read_dir(r.join("memo")).is_ok_and(|mut d| d.next().is_some()));
    local || store::shared_roots("memo").iter().any(|r| r.is_dir())
}

/// The store-backed memo `blue run` plans by default (rule R8 of the default
/// cascade): when the store, or a shared root, already holds a result that
/// cost [`COSTLY`] or more for one of the program's pure definitions, the run
/// answers those calls from the store and adds what it computes; otherwise
/// `None`, and the run is as before.
pub(crate) fn costly(
    watched: &blue_lang_runtime::pipeline::Watched<'_>,
    slow: bool,
) -> Option<blue_lang_runtime::pipeline::Planned> {
    if !slow && !store_holds_anything() {
        return None;
    }
    let plan = Plan::of(watched.definitions, watched.lowered, watched.erased);
    let opened = store()?;
    let mut answered = false;
    let mut names: Vec<String> = watched
        .definitions
        .iter()
        .enumerate()
        .filter_map(|(i, d)| {
            let Some(Ok(hash)) = plan.target(i) else {
                return None;
            };
            let stored = opened.load(hash).entries.values().any(|s| s.cost >= COSTLY);
            answered |= stored;
            let held: &[&str] = match (stored, slow) {
                (true, _) => &["pure", "stored_costly"],
                (false, true) => &["pure", "slow_program"],
                (false, false) => &["pure"],
            };
            (blue_lang_runtime::kitei::fires("R8", held)
                || blue_lang_runtime::kitei::fires("R14", held))
            .then(|| d.name.clone())
        })
        .collect();
    if names.is_empty() {
        return None;
    }
    names.sort();
    names.dedup();
    let recall = over(
        true,
        watched.definitions,
        watched.lowered,
        watched.erased,
        None,
    );
    Some((
        Arc::new(Flushing(recall)),
        if answered {
            format!(
                "the store answers `{}`, whose stored results cost {} ms or more to compute",
                names.join("`, `"),
                COSTLY.as_millis()
            )
        } else {
            format!(
                "the store records the results of `{}` with their cost: this program's last run took {} ms or more",
                names.join("`, `"),
                COSTLY.as_millis()
            )
        },
    ))
}

/// Mark the program at `file` slow when this run's evaluation took
/// [`COSTLY`] or more (rule R14), so the next run records its pure results
/// with their cost, and R8 answers the costly ones from then on. Under
/// `BLUE_MEMO=off` nothing is marked.
pub(crate) fn note_slow(file: &std::path::Path, took: std::time::Duration) -> bool {
    if took < COSTLY
        || std::env::var_os(ENV).is_some()
        || blue_lang_runtime::kitei::switched_off("R14")
    {
        return false;
    }
    std::fs::read(file).is_ok_and(|text| store::mark_slow(&text))
}

/// How many results the store holds for `hash` that cost [`COSTLY`] or more:
/// what R8 answers from on the next run.
pub(crate) fn costly_results(hash: &blue_lang_runtime::def_hash::DefHash) -> usize {
    if !store_holds_anything() {
        return 0;
    }
    store().map_or(0, |s| {
        s.load(hash)
            .entries
            .values()
            .filter(|e| e.cost >= COSTLY)
            .count()
    })
}

/// Write the run's results to the store. A failure costs the next run its
/// hits, never this run its result, so it is not an error.
pub(crate) fn finish(recall: &Recall) {
    let _ = recall.flush();
}

#[allow(clippy::cast_precision_loss)]
fn ms(d: std::time::Duration) -> f64 {
    d.as_secs_f64() * 1000.0
}

/// The memo's part of `blue profile`, as text.
pub(crate) fn print(report: &Report) {
    let t = report.total();
    println!(
        "memo: {} hit(s) ({} from disk), {} miss(es), {} stored, {:.2} ms saved{}",
        t.hits + t.disk_hits,
        t.disk_hits,
        t.misses,
        t.stored,
        ms(t.saved),
        if report.damaged > 0 {
            format!(", {} damaged store entr(ies) ignored", report.damaged)
        } else {
            String::new()
        }
    );
    if report.rows.is_empty() {
        return;
    }
    println!(
        "  {:>8}  {:>8}  {:>8}  {:>8}  {:>10}  {:<32}",
        "hits", "disk", "misses", "stored", "saved ms", "function"
    );
    let mut rows: Vec<_> = report.rows.iter().collect();
    rows.sort_by(|a, b| {
        b.counts
            .saved
            .cmp(&a.counts.saved)
            .then_with(|| a.name.cmp(&b.name))
    });
    for r in rows {
        let c = &r.counts;
        println!(
            "  {:>8}  {:>8}  {:>8}  {:>8}  {:>10.2}  {:<32}{}",
            c.hits,
            c.disk_hits,
            c.misses,
            c.stored,
            ms(c.saved),
            r.name,
            if c.retired { "  (stopped looking)" } else { "" }
        );
    }
}

/// The memo's part of `blue profile --json`.
pub(crate) fn json(report: &Report) -> serde_json::Value {
    let t = report.total();
    serde_json::json!({
        "hits": t.hits,
        "disk_hits": t.disk_hits,
        "misses": t.misses,
        "stored": t.stored,
        "saved_ms": ms(t.saved),
        "damaged": report.damaged,
        "store": report.store,
        "functions": report.rows.iter().map(|r| serde_json::json!({
            "name": r.name,
            "hits": r.counts.hits,
            "disk_hits": r.counts.disk_hits,
            "misses": r.counts.misses,
            "stored": r.counts.stored,
            "saved_ms": ms(r.counts.saved),
            "retired": r.counts.retired,
        })).collect::<Vec<_>>(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::BlueConfig;

    #[test]
    fn the_memo_is_off_unless_the_environment_turns_it_on() {
        let cfg = BlueConfig::default();
        assert_eq!(Mode::of(false, None, &cfg), Mode::Off);
        assert_eq!(Mode::of(false, Some("off"), &cfg), Mode::Off);
        assert_eq!(Mode::of(false, Some("maybe"), &cfg), Mode::Off);
        assert_eq!(Mode::of(false, Some("process"), &cfg), Mode::Process);
        assert_eq!(Mode::of(false, Some(" On "), &cfg), Mode::Store);
        assert_eq!(Mode::of(false, Some("store"), &cfg), Mode::Store);
    }

    #[test]
    fn no_memo_and_a_changed_bound_turn_it_off_whatever_the_environment_says() {
        let cfg = BlueConfig::default();
        assert_eq!(Mode::of(true, Some("on"), &cfg), Mode::Off);
        let bounded = BlueConfig {
            max_steps: Some(1_000),
            ..BlueConfig::default()
        };
        assert_eq!(Mode::of(false, Some("on"), &bounded), Mode::Off);
    }
}
