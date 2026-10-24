//! The memo's doors: `blue run`, `blue test` and `blue profile` cache the
//! calls of every definition `blue-lang-mondou` proves pure, in process and in
//! the store under `$XDG_CACHE_HOME/blue/memo` (`theory/BLUE-TOOLING.md` T-M).
//!
//! On by default. `--no-memo` on a command, or `BLUE_MEMO=off` in the
//! environment, runs every call. `blue test --coverage` and `blue trace` run
//! without it: they report what the code does, and a call answered from the
//! store does nothing. So does a run under an execution bound other than the
//! shipped one (`BlueConfig`'s `max_call_depth`, `max_steps`): an answered call
//! takes no steps and no depth, so it would let a run the bound refuses
//! finish, and an operator who set a bound asked for the refusal. A store that
//! cannot be opened (a read-only home, a build sandbox) leaves the in-process
//! table: the run is the same either way.

use std::sync::Arc;

use blue_lang_mondou::recall::{Memo, Plan, Policy, Report};
use blue_lang_mondou::store::{self, Identity, Store};
use blue_lang_runtime::observe::{CallObserver, Definitions};

/// The variable that turns the memo off for every command.
pub(crate) const ENV: &str = "BLUE_MEMO";

/// Whether this run is memoized: not when the command said `--no-memo`,
/// not when `BLUE_MEMO` is `off`, `0`, `false` or `no`, and not under an
/// execution bound other than the shipped one.
pub(crate) fn enabled(no_memo: bool, cfg: &crate::config::BlueConfig) -> bool {
    if no_memo || cfg.execution_bounds() != blue_lang_runtime::ExecutionBounds::DEFAULT {
        return false;
    }
    !std::env::var(ENV).is_ok_and(|v| {
        matches!(
            v.trim().to_ascii_lowercase().as_str(),
            "off" | "0" | "false" | "no"
        )
    })
}

/// The disk tier, when it can be opened.
fn store() -> Option<Arc<Store>> {
    let root = store::default_root()?;
    Store::open(&root, Identity::of_this_build(), store::DEFAULT_MAX_BYTES)
        .ok()
        .map(Arc::new)
}

/// A memo over a program about to run, wrapping `inner` when a tool already
/// watches it.
pub(crate) fn over(
    definitions: &Arc<Definitions>,
    lowered: &[blue_lang_syntax::Spanned],
    erased: &[blue_lang_syntax::Spanned],
    inner: Option<Arc<dyn CallObserver>>,
) -> Arc<Memo> {
    let plan = Plan::of(definitions, lowered, erased);
    Arc::new(Memo::new(
        Arc::clone(definitions),
        plan,
        store(),
        inner,
        Policy::default(),
    ))
}

/// Write the run's results to the store. A failure costs the next run its
/// hits, never this run its result, so it is not an error.
pub(crate) fn finish(memo: &Memo) {
    let _ = memo.flush();
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
