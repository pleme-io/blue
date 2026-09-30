//! **blue's executable specification: every row on every evaluator.**
//!
//! `spec/rows/*.b` holds one row per observable language behaviour — a small
//! blue program and what it must produce. This runs every row on every
//! evaluator blue has, reports per evaluator and per blueshift position, and
//! fails when:
//!
//! - a row does not hold on an evaluator that observes it;
//! - an evaluator **disagrees** with stage 0 (the tree-walker, or for static
//!   rows the in-process front end), even when both meet the expectation;
//! - a `pending` row starts passing, so a closed gap flips the run red until
//!   its mark is removed;
//! - a row's `position` is not where its program measures on the blueshift;
//! - a row is malformed, or a registry entry has no row (`coverage`).
//!
//! The row format, how to add one, and the pending mechanism are in
//! `spec/README.md`.
//!
//! Environment:
//!
//! - `BLUE_BIN` — the `blue` binary the `cli` column runs. Without it the
//!   column is blind, and `BLUE_CONFORMANCE_STRICT=1` (set by the nix check)
//!   turns a blind column into a failure, so the gate cannot pass by default.
//! - `BLUE_CONFORMANCE_JSON` — also write every verdict as JSON lines there,
//!   one object per (row, evaluator), for DuckDB.
//! - `BLUE_CONFORMANCE_PROBE=1` — print every observation, not only failures.
//! - a first argument filters rows by id substring (coverage is then skipped);
//!   `--coverage-only` runs the missing-row gate and the controls alone.

mod coverage;
mod eval;
mod judge;
mod rows;

use std::collections::BTreeMap;
use std::io::Write as _;
use std::path::{Path, PathBuf};

use eval::{Env, Obs};
use judge::Verdict;
use rows::{Ev, Expect, Row};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .expect("repo root")
        .to_path_buf()
}

/// The binary the `cli` column runs: `BLUE_BIN`, else a workspace build.
fn blue_bin(repo: &Path) -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("BLUE_BIN") {
        return Some(PathBuf::from(p));
    }
    let target = std::env::var_os("CARGO_TARGET_DIR")
        .map_or_else(|| repo.join("target"), PathBuf::from);
    ["debug", "release"]
        .iter()
        .map(|p| target.join(p).join("blue"))
        .find(|p| p.is_file())
}

/// One row's observations and verdicts.
struct Outcome {
    row: Row,
    rung: String,
    obs: BTreeMap<Ev, Obs>,
    verdicts: BTreeMap<Ev, Verdict>,
    /// Disagreements between evaluators that are both pending on this row.
    divergences: Vec<String>,
}

thread_local! {
    /// The message of the last panic on this thread, captured by the hook
    /// `main` installs so a crashing evaluator is reported, not printed.
    static LAST_PANIC: std::cell::RefCell<String> = const { std::cell::RefCell::new(String::new()) };
}

/// One in-process evaluator, with a panic turned into an observation.
fn observe_in_process(env: &mut Env, row: &Row, ev: Ev, n: usize) -> Obs {
    let run = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| match ev {
        Ev::Walker => eval::walker(env, row),
        Ev::Vm => eval::vm(env, row),
        Ev::Wasm => eval::wasm(env, row),
        Ev::Cli => eval::cli(env, row, n),
        Ev::Static => eval::statics(row, &env.roots),
    }));
    run.unwrap_or_else(|_| {
        Obs::Crashed(format!("panic: {}", LAST_PANIC.with(|p| p.borrow().clone())))
    })
}

/// One evaluator in a child process: this binary with `--row ID --ev NAME`.
/// A death by signal (a stack overflow aborts) or a run past the limit is the
/// observation, which no in-process call could survive to report.
fn observe_isolated(row: &Row, ev: Ev) -> Obs {
    let exe = std::env::current_exe().expect("the runner's own binary");
    let mut cmd = std::process::Command::new(exe);
    cmd.args(["--row", &row.id, "--ev", ev.name()]);
    let out = match eval::output_within(&mut cmd) {
        Ok(o) => o,
        Err(crashed) => return crashed,
    };
    let stdout = String::from_utf8_lossy(&out.stdout);
    match stdout.lines().last().map(serde_json::from_str::<Obs>) {
        Some(Ok(o)) if out.status.success() => o,
        _ => Obs::Crashed(format!("the process exited {} without an observation", out.status)),
    }
}

fn run_row(env: &mut Env, row: &Row, n: usize) -> Outcome {
    let mut obs = BTreeMap::new();
    for ev in Ev::ALL {
        let o = if row.isolate && ev != Ev::Cli {
            observe_isolated(row, ev)
        } else {
            observe_in_process(env, row, ev, n)
        };
        obs.insert(ev, o);
    }

    let mut verdicts = BTreeMap::new();
    let mut divergences = Vec::new();
    let first: BTreeMap<Ev, Verdict> = Ev::ALL
        .into_iter()
        .map(|ev| (ev, judge::verdict(row, ev, &obs[&ev])))
        .collect();
    for ev in Ev::ALL {
        let o = &obs[&ev];
        let mut v = first[&ev].clone();
        // A mark scoped to this evaluator records how it differs from stage
        // 0, so it flips only when the evaluator meets the row AND agrees.
        if let (Some(p), Some(reference)) = (
            row.pending.iter().find(|p| p.on == Some(ev)),
            judge::reference_for(ev, row),
        ) {
            if v.is_fail() && !judge::agrees(&obs[&reference], o) {
                v = Verdict::Pending(p.gap.clone());
            }
        }
        if let Some(reference) = judge::reference_for(ev, row) {
            match judge::agreement(row, ev, &v, o, &first[&reference], &obs[&reference]) {
                judge::Agreement::Agrees => {}
                judge::Agreement::DivergesWhilePending(what) => divergences.push(what),
                judge::Agreement::Disagrees(why) => v = Verdict::Fail(why),
            }
        }
        // An evaluator whose kind of row this is must see it: blind there is a
        // hole in the door, not a design.
        if eval::observes(ev, row) {
            if let Verdict::Blind(why) = &v {
                if ev == Ev::Cli && std::env::var_os("BLUE_CONFORMANCE_STRICT").is_some() {
                    v = Verdict::Fail(format!("the cli column is blind: {why}"));
                }
            }
        }
        verdicts.insert(ev, v);
    }
    let rung = eval::rung_of(&row.src);
    Outcome {
        row: row.clone(),
        rung,
        obs,
        verdicts,
        divergences,
    }
}

/// Negative controls. A runner that passes everything is caught here: each
/// synthetic row has a known wrong answer, and the run is red unless the
/// runner judges it as such.
fn controls(env: &mut Env) -> Vec<String> {
    let mut failures = Vec::new();
    let control = |id: &str, src: &str, expect: Expect, pending: Vec<rows::Pending>| Row {
        file: "<control>".into(),
        id: id.into(),
        src: src.into(),
        expect,
        pending,
        position: None,
        covers: Vec::new(),
        host: false,
        isolate: false,
    };

    let wrong = control("control.wrong-value", "1 + 1", Expect::Value("3".into()), vec![]);
    let out = run_row(env, &wrong, usize::MAX);
    for ev in [Ev::Walker, Ev::Vm, Ev::Wasm] {
        if !out.verdicts[&ev].is_fail() {
            failures.push(format!(
                "control: a wrong value was not failed by {} ({:?})",
                ev.name(),
                out.verdicts[&ev]
            ));
        }
    }

    let flipped = control(
        "control.pending-passes",
        "1 + 1",
        Expect::Value("2".into()),
        vec![rows::Pending {
            gap: "G0".into(),
            on: None,
        }],
    );
    let out = run_row(env, &flipped, usize::MAX - 1);
    for ev in [Ev::Walker, Ev::Vm, Ev::Wasm] {
        if !out.verdicts[&ev].is_fail() {
            failures.push(format!(
                "control: a pending row that passes was not failed by {}",
                ev.name()
            ));
        }
    }

    let held = control(
        "control.pending-holds",
        "1 + 1",
        Expect::Value("3".into()),
        vec![rows::Pending {
            gap: "G0".into(),
            on: None,
        }],
    );
    let out = run_row(env, &held, usize::MAX - 2);
    for ev in [Ev::Walker, Ev::Vm, Ev::Wasm] {
        if !matches!(out.verdicts[&ev], Verdict::Pending(_)) {
            failures.push(format!(
                "control: a pending row that still misses was not reported pending by {}",
                ev.name()
            ));
        }
    }

    // Agreement is judged on the observation, not the verdict: two readings
    // that both "work" and differ are a failure.
    let a = Obs::Failed {
        stage: rows::Stage::Eval,
        message: "division by zero".into(),
    };
    let b = Obs::Failed {
        stage: rows::Stage::Eval,
        message: "vm: division by zero".into(),
    };
    if judge::agrees(&a, &b) {
        failures.push("control: two different messages were judged to agree".into());
    }
    failures
}

fn tally_line(name: &str, counts: &[usize; 4]) -> String {
    format!(
        "  {name:<12} pass {:>4}   pending {:>4}   fail {:>4}   blind {:>4}",
        counts[0], counts[1], counts[2], counts[3]
    )
}

fn slot(v: &Verdict) -> usize {
    match v {
        Verdict::Pass => 0,
        Verdict::Pending(_) => 1,
        Verdict::Fail(_) => 2,
        Verdict::Blind(_) => 3,
    }
}

fn json_line(o: &Outcome, ev: Ev) -> String {
    let (verdict, detail) = match &o.verdicts[&ev] {
        Verdict::Pass => ("pass", String::new()),
        Verdict::Pending(g) => ("pending", g.clone()),
        Verdict::Fail(w) => ("fail", w.clone()),
        Verdict::Blind(w) => ("blind", w.clone()),
    };
    serde_json::json!({
        "file": o.row.file,
        "id": o.row.id,
        "area": o.row.file.trim_end_matches(".b"),
        "kind": o.row.expect.kind(),
        "position": o.rung,
        "evaluator": ev.name(),
        "verdict": verdict,
        "detail": detail,
        "observed": o.obs[&ev].to_string(),
        "pending": o.row.pending.iter().map(|p| p.gap.clone()).collect::<Vec<_>>(),
    })
    .to_string()
}

fn main() {
    // Before any interpreter exists: every in-process column, and every
    // isolated child (this same binary), runs rows under the suite's budget.
    blue_lang_runtime::set_execution_bounds(blue_lang_runtime::ExecutionBounds {
        max_steps: Some(eval::ROW_STEPS),
        ..blue_lang_runtime::ExecutionBounds::DEFAULT
    });
    std::panic::set_hook(Box::new(|info| {
        let msg = info
            .payload()
            .downcast_ref::<&str>()
            .map(|s| (*s).to_owned())
            .or_else(|| info.payload().downcast_ref::<String>().cloned())
            .unwrap_or_default();
        LAST_PANIC.with(|p| *p.borrow_mut() = msg);
    }));
    let repo = repo_root();
    let args: Vec<String> = std::env::args().collect();

    // Child mode: one row, one evaluator, the observation as JSON on stdout.
    if let Some(i) = args.iter().position(|a| a == "--row") {
        let id = args.get(i + 1).expect("--row ID");
        let ev_name = args
            .iter()
            .position(|a| a == "--ev")
            .and_then(|j| args.get(j + 1))
            .expect("--ev NAME");
        let ev = Ev::ALL
            .into_iter()
            .find(|e| e.name() == ev_name)
            .expect("a known evaluator");
        let (rows, _) = rows::load(&repo.join("spec/rows"));
        let row = rows.iter().find(|r| &r.id == id).expect("a known row");
        let scratch = std::env::temp_dir().join(format!("blue-conformance-{}", std::process::id()));
        let roots = vec![repo.join("spec/bidamas"), repo.join("bidamas")];
        let mut env = Env::new(roots, None, scratch.clone());
        let o = observe_in_process(&mut env, row, ev, 0);
        let _ = std::fs::remove_dir_all(&scratch);
        println!("{}", serde_json::to_string(&o).expect("an observation serializes"));
        return;
    }

    let filter: Option<String> = args.get(1).filter(|a| !a.starts_with('-')).cloned();
    let probe = std::env::var_os("BLUE_CONFORMANCE_PROBE").is_some();
    let scratch = std::env::temp_dir().join(format!("blue-conformance-{}", std::process::id()));
    let roots = vec![repo.join("spec/bidamas"), repo.join("bidamas")];
    let mut env = Env::new(roots, blue_bin(&repo), scratch.clone());

    let (all_rows, refusals) = rows::load(&repo.join("spec/rows"));
    // `--coverage-only`: the missing-row gate and the controls, no rows run.
    let coverage_only = args.iter().any(|a| a == "--coverage-only");
    let rows: Vec<&Row> = all_rows
        .iter()
        .filter(|_| !coverage_only)
        .filter(|r| filter.as_ref().is_none_or(|f| r.id.contains(f.as_str())))
        .collect();

    let mut red = false;
    let mut out = std::io::stdout().lock();

    writeln!(out, "blue conformance: {} rows from spec/rows/", rows.len()).ok();
    writeln!(
        out,
        "  cli column: {}",
        env.cli
            .as_ref()
            .map_or("BLIND (no binary; set BLUE_BIN)".to_string(), |p| p.display().to_string())
    )
    .ok();

    for r in &refusals {
        writeln!(out, "MALFORMED {r}").ok();
        red = true;
    }

    let mut ids = std::collections::BTreeSet::new();
    for r in &rows {
        if !ids.insert(r.id.clone()) {
            writeln!(out, "MALFORMED {}: duplicate row id `{}`", r.file, r.id).ok();
            red = true;
        }
    }

    let outcomes: Vec<Outcome> = rows
        .iter()
        .enumerate()
        .map(|(n, r)| run_row(&mut env, r, n))
        .collect();

    // Per-row failures, grouped by row.
    for o in &outcomes {
        if let Some(p) = &o.row.position {
            if *p != o.rung {
                writeln!(
                    out,
                    "FAIL {} [{}]: declares position({p}) but its program measures `{}`",
                    o.row.id, o.row.file, o.rung
                )
                .ok();
                red = true;
            }
        }
        for ev in Ev::ALL {
            match &o.verdicts[&ev] {
                Verdict::Fail(why) => {
                    writeln!(out, "FAIL {} [{}] on {}: {why}", o.row.id, o.row.file, ev.name()).ok();
                    red = true;
                }
                v if probe => {
                    writeln!(out, "     {} on {}: {:?} — {}", o.row.id, ev.name(), v, o.obs[&ev]).ok();
                }
                _ => {}
            }
        }
    }

    // Per evaluator.
    writeln!(out, "\nper evaluator:").ok();
    for ev in Ev::ALL {
        let mut c = [0usize; 4];
        for o in &outcomes {
            c[slot(&o.verdicts[&ev])] += 1;
        }
        writeln!(out, "{}", tally_line(ev.name(), &c)).ok();
    }

    // Per area (row file): rows, and verdict counts summed over evaluators.
    writeln!(out, "\nper area (rows; verdicts summed over evaluators):").ok();
    let mut areas: BTreeMap<&str, (usize, [usize; 4])> = BTreeMap::new();
    for o in &outcomes {
        let e = areas.entry(o.row.file.as_str()).or_default();
        e.0 += 1;
        for ev in Ev::ALL {
            e.1[slot(&o.verdicts[&ev])] += 1;
        }
    }
    for (area, (n, c)) in &areas {
        writeln!(
            out,
            "  {:<22} rows {:>4}   pass {:>4}   pending {:>4}   fail {:>4}",
            area.trim_end_matches(".b"),
            n,
            c[0],
            c[1],
            c[2]
        )
        .ok();
    }

    // Per blueshift position, per evaluator.
    writeln!(out, "\nper blueshift position (measured rung of each row's program):").ok();
    for rung in ["none", "dynamic", "annotated", "checked", "restricted"] {
        let at: Vec<&Outcome> = outcomes.iter().filter(|o| o.rung == rung).collect();
        writeln!(out, "  {rung} ({} rows)", at.len()).ok();
        for ev in Ev::ALL {
            let mut c = [0usize; 4];
            for o in &at {
                c[slot(&o.verdicts[&ev])] += 1;
            }
            if c.iter().sum::<usize>() > 0 && c[3] < at.len() {
                writeln!(out, "  {}", tally_line(ev.name(), &c)).ok();
            }
        }
    }

    // Pending, by gap.
    let mut by_gap: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for o in &outcomes {
        for ev in Ev::ALL {
            if let Verdict::Pending(g) = &o.verdicts[&ev] {
                by_gap
                    .entry(g.clone())
                    .or_default()
                    .push(format!("{}@{}", o.row.id, ev.name()));
            }
        }
    }
    writeln!(out, "\ndivergences while pending (evaluators missing a destination differently):").ok();
    for o in &outcomes {
        for d in &o.divergences {
            writeln!(out, "  {}: {d}", o.row.id).ok();
        }
    }

    writeln!(out, "\npending, by gap:").ok();
    for (gap, items) in &by_gap {
        writeln!(out, "  {gap:<12} {:>4}  {}", items.len(), items.join(" ")).ok();
    }

    // Negative controls.
    let control_failures = controls(&mut env);
    for c in &control_failures {
        writeln!(out, "FAIL {c}").ok();
        red = true;
    }
    writeln!(
        out,
        "\ncontrols: {}",
        if control_failures.is_empty() { "4 of 4 judged as expected" } else { "RED" }
    )
    .ok();

    // The missing-row gate, over the whole suite (not a filtered run).
    if filter.is_none() {
        let reg = coverage::registry(&repo);
        // Anti-vacuity: an empty registry would cover itself.
        for (kind, min) in [("rule", 9), ("form", 10), ("builtin", 200), ("op", 10), ("okite", 12)] {
            if reg[kind].len() < min {
                writeln!(out, "FAIL coverage: the {kind} registry has {} entries, expected ≥{min}", reg[kind].len()).ok();
                red = true;
            }
        }
        let cov = coverage::gate(&all_rows, &reg, eval::rung_of);
        writeln!(out, "\nmissing-row gate:").ok();
        for (kind, (n, have)) in &cov.totals {
            writeln!(out, "  {kind:<8} {have:>4} of {n:>4} covered").ok();
        }
        for (kind, keys) in &cov.missing {
            for k in keys {
                writeln!(out, "MISSING {kind}:{k} has no spec row").ok();
            }
        }
        for r in &cov.refused {
            writeln!(out, "REFUSED {r}").ok();
        }
        if !cov.ok() {
            red = true;
        }
    }

    if let Some(path) = std::env::var_os("BLUE_CONFORMANCE_JSON") {
        let mut lines = String::new();
        for o in &outcomes {
            for ev in Ev::ALL {
                lines.push_str(&json_line(o, ev));
                lines.push('\n');
            }
        }
        std::fs::write(&path, lines).expect("write the JSON report");
    }

    let _ = std::fs::remove_dir_all(&scratch);
    writeln!(out, "\nconformance: {}", if red { "RED" } else { "green" }).ok();
    drop(out);
    if red {
        std::process::exit(1);
    }
}
