//! Wall time per pipeline stage, recorded only when a door asks for it.
//!
//! `blue run --timings` turns the recorder on for its thread, runs, and prints
//! [`report`] to stderr. Off, [`stage`] runs its closure and reads no clock.

use std::cell::RefCell;
use std::time::{Duration, Instant};

/// One stage of a run, in the order the pipeline reaches it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Stage {
    /// Reading the entry file.
    Read,
    /// The formatter, admitting the entry as canonical.
    Format,
    /// Building or forking the interpreter, stdlib included.
    Runtime,
    /// The name table the check stage resolves against.
    Names,
    /// Parsing the entry file.
    Parse,
    /// Loading, admitting and parsing every imported bidama.
    Resolve,
    /// Every rule of the check stage.
    Check,
    /// Lowering and type erasure.
    Erase,
    /// Evaluating the top-level forms.
    Eval,
    /// Calling `main`.
    Main,
}

impl Stage {
    /// Every stage, in pipeline order.
    pub const ALL: [Self; 10] = [
        Self::Read,
        Self::Format,
        Self::Runtime,
        Self::Names,
        Self::Parse,
        Self::Resolve,
        Self::Check,
        Self::Erase,
        Self::Eval,
        Self::Main,
    ];

    /// The stage's name as `--timings` prints it.
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::Read => "read",
            Self::Format => "format",
            Self::Runtime => "runtime",
            Self::Names => "names",
            Self::Parse => "parse",
            Self::Resolve => "resolve",
            Self::Check => "check",
            Self::Erase => "erase",
            Self::Eval => "eval",
            Self::Main => "main",
        }
    }
}

thread_local! {
    static RECORD: RefCell<Option<Vec<(Stage, Duration)>>> = const { RefCell::new(None) };
    static NESTED: RefCell<Vec<Duration>> = const { RefCell::new(Vec::new()) };
}

/// Start recording on this thread, dropping anything recorded before.
pub fn enable() {
    RECORD.with(|r| *r.borrow_mut() = Some(Vec::new()));
    NESTED.with(|n| n.borrow_mut().clear());
}

/// Whether this thread records.
#[must_use]
pub fn enabled() -> bool {
    RECORD.with(|r| r.borrow().is_some())
}

/// Run `f`, charging its wall time to `stage` when recording is on. A stage
/// reached inside another is charged to itself and not to the outer one.
pub fn stage<T>(stage: Stage, f: impl FnOnce() -> T) -> T {
    if !enabled() {
        return f();
    }
    NESTED.with(|n| n.borrow_mut().push(Duration::ZERO));
    let start = Instant::now();
    let out = f();
    let spent = start.elapsed();
    let inner = NESTED.with(|n| {
        let mut n = n.borrow_mut();
        let inner = n.pop().unwrap_or_default();
        if let Some(outer) = n.last_mut() {
            *outer += spent;
        }
        inner
    });
    RECORD.with(|r| {
        if let Some(rows) = r.borrow_mut().as_mut() {
            rows.push((stage, spent.saturating_sub(inner)));
        }
    });
    out
}

/// Each stage's total so far, in pipeline order, stages never reached left out.
#[must_use]
pub fn totals() -> Vec<(Stage, Duration)> {
    RECORD.with(|r| {
        let r = r.borrow();
        let rows = r.as_deref().unwrap_or_default();
        Stage::ALL
            .iter()
            .filter_map(|s| {
                let mine: Vec<Duration> = rows
                    .iter()
                    .filter(|(t, _)| t == s)
                    .map(|(_, d)| *d)
                    .collect();
                (!mine.is_empty()).then(|| (*s, mine.iter().sum()))
            })
            .collect()
    })
}

/// The totals as an aligned table in milliseconds, with a total row.
#[must_use]
pub fn report() -> String {
    let rows = totals();
    let all: Duration = rows.iter().map(|(_, d)| *d).sum();
    let mut out = String::new();
    for (stage, d) in rows
        .iter()
        .map(|(s, d)| (s.name(), *d))
        .chain([("total", all)])
    {
        out.push_str(&format!("{stage:<8} {:>9.3} ms\n", d.as_secs_f64() * 1e3));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn off_records_nothing() {
        RECORD.with(|r| *r.borrow_mut() = None);
        assert_eq!(stage(Stage::Parse, || 7), 7);
        assert!(totals().is_empty());
    }

    #[test]
    fn on_sums_each_stage_in_pipeline_order() {
        enable();
        stage(Stage::Eval, || std::thread::sleep(Duration::from_millis(2)));
        stage(Stage::Parse, || ());
        stage(Stage::Eval, || std::thread::sleep(Duration::from_millis(2)));
        let t = totals();
        assert_eq!(
            t.iter().map(|(s, _)| *s).collect::<Vec<_>>(),
            [Stage::Parse, Stage::Eval]
        );
        assert!(t[1].1 >= Duration::from_millis(4));
        assert!(report().lines().last().unwrap().starts_with("total"));
    }

    #[test]
    fn a_nested_stage_is_charged_once() {
        enable();
        stage(Stage::Read, || {
            stage(Stage::Runtime, || {
                std::thread::sleep(Duration::from_millis(20))
            });
        });
        let t = totals();
        assert_eq!(t[1].0, Stage::Runtime);
        assert!(t[0].1 < Duration::from_millis(10), "{t:?}");
    }
}
