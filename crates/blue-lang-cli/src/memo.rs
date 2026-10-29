//! The call memo's doors: `blue run`, `blue test` and `blue profile` can
//! answer the calls of every definition `blue-lang-mondou` proves pure from
//! a table keyed by content (`blue_lang_mondou::recall`), in process and in
//! the store under `$XDG_CACHE_HOME/blue/memo`.
//!
//! Off by default: every call runs, as before the memo existed. `BLUE_MEMO`
//! turns it on: `process` keeps the table for the run only, `on` (or
//! `store`) also reads and writes the store. `--no-memo` on a command turns
//! it off again for that command. `blue test --coverage` and `blue trace`
//! always run without it: they report what the code does, and an answered
//! call does nothing. So does a run under an execution bound other than the
//! shipped one (`BlueConfig`'s `max_call_depth`, `max_steps`): an answered
//! call takes no steps and no depth, so it would let a run the bound refuses
//! finish. A store that cannot be opened (a read-only home, a build sandbox)
//! leaves the in-process table: the run is the same either way.

use std::sync::Arc;

use blue_lang_mondou::recall::{Plan, Policy, Recall, Report};
use blue_lang_mondou::store::{self, Identity, Store};
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

fn store() -> Option<Arc<Store>> {
    let root = store::default_root()?;
    Store::open(&root, Identity::of_this_build(), store::DEFAULT_MAX_BYTES)
        .ok()
        .map(Arc::new)
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
