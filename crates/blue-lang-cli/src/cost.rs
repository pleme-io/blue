//! `blue cost FILE`: each definition's predicted price (S1 of docs/ENGINES.md).
//!
//! The runtime prices a form from a table ([`blue_lang_runtime::cost`]); this
//! measures the table. Each probe runs as `blue run --timings` on the walker
//! with every lever off, so the steps and allocations it reports are the
//! word's own; the table is measured once per binary and kept in
//! `$XDG_CACHE_HOME/blue/cost/`, keyed by the binary's path, size and time.
//! An allocation's weight in steps is the ratio of their measured times: two
//! probes, one heavy in steps and one in allocations, solved for both.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Instant;

use blue_lang_runtime::cost::{self, Price, Table, WordPrice};

/// The list length a definition's lists are taken to hold.
pub(crate) const NOMINAL: f64 = 1000.0;

const LEVERS_OFF: &[(&str, &str)] = &[
    ("BLUE_DOOR", "walker"),
    ("BLUE_MEMO", "off"),
    ("BLUE_NATIVE", "off"),
    ("BLUE_FUSE", "off"),
    ("BLUE_FOLD", "off"),
    ("BLUE_INDEX", "off"),
    ("BLUE_PARMAP", "off"),
];

fn scratch() -> PathBuf {
    std::env::temp_dir().join(format!("blue-cost-{}", std::process::id()))
}

fn row(report: &str, name: &str) -> Option<f64> {
    report.lines().find_map(|l| {
        let rest = l.strip_prefix(name)?;
        rest.split_whitespace().next()?.parse().ok()
    })
}

/// A probe program's price and its evaluation time in milliseconds.
fn run_probe(src: &str) -> Option<(Price, f64)> {
    let dir = scratch();
    std::fs::create_dir_all(&dir).ok()?;
    let file = dir.join("probe.b");
    std::fs::write(&file, src).ok()?;
    let me = std::env::current_exe().ok()?;
    let out = Command::new(me)
        .envs(LEVERS_OFF.iter().copied())
        .args(["run", "--quiet", "--timings"])
        .arg(&file)
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let report = String::from_utf8_lossy(&out.stderr);
    Some((
        Price {
            steps: row(&report, "steps ")?,
            allocs: row(&report, "allocs ").unwrap_or(0.0),
        },
        row(&report, "eval ")?,
    ))
}

const STEP_HEAVY: &str = "keep = reduce((a, x) -> a + x * 3 - x % 7, 0, range(200000))\n";
const ALLOC_HEAVY: &str = "keep = map((x) -> [x], range(200000))\n";

fn alloc_weight() -> f64 {
    let (Some((s, ts)), Some((a, ta))) = (run_probe(STEP_HEAVY), run_probe(ALLOC_HEAVY)) else {
        return 1.0;
    };
    let det = s.steps * a.allocs - s.allocs * a.steps;
    if det.abs() < f64::EPSILON {
        return 1.0;
    }
    let per_step = (ts * a.allocs - s.allocs * ta) / det;
    let per_alloc = (s.steps * ta - ts * a.steps) / det;
    if per_step <= 0.0 || per_alloc <= 0.0 {
        return 1.0;
    }
    (per_alloc / per_step).clamp(0.1, 100.0)
}

/// Measure the table on this binary.
pub(crate) fn measured() -> Table {
    let measure = |expr: &str, n: usize| run_probe(&cost::probe_program(expr, n)).map(|(p, _)| p);
    let table = cost::calibrate(&measure, alloc_weight());
    let _ = std::fs::remove_dir_all(scratch());
    table
}

fn cache_file() -> Option<PathBuf> {
    let me = std::env::current_exe().ok()?;
    let meta = std::fs::metadata(&me).ok()?;
    let stamp = meta
        .modified()
        .ok()?
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_nanos();
    let key = blue_lang_runtime::check_cache::digest(&[
        me.to_string_lossy().as_bytes(),
        &meta.len().to_le_bytes(),
        &stamp.to_le_bytes(),
    ]);
    let hex: String = key.iter().take(16).map(|b| format!("{b:02x}")).collect();
    Some(
        blue_lang_mondou::store::cache_root()?
            .join("cost")
            .join(format!("{hex}.tsv")),
    )
}

fn render(t: &Table) -> String {
    let mut out = format!("alloc_weight\t{}\n", t.alloc_weight);
    for (w, p) in &t.words {
        out.push_str(&format!(
            "{w}\t{}\t{}\t{}\t{}\n",
            p.call.steps, p.call.allocs, p.element.steps, p.element.allocs
        ));
    }
    out
}

fn parse(text: &str) -> Option<Table> {
    let mut lines = text.lines();
    let alloc_weight = lines.next()?.strip_prefix("alloc_weight\t")?.parse().ok()?;
    let mut words = std::collections::BTreeMap::new();
    for l in lines {
        let f: Vec<&str> = l.split('\t').collect();
        let [w, cs, ca, es, ea] = f.as_slice() else {
            return None;
        };
        let n = |s: &str| s.parse::<f64>().ok();
        words.insert(
            (*w).to_string(),
            WordPrice {
                call: Price {
                    steps: n(cs)?,
                    allocs: n(ca)?,
                },
                element: Price {
                    steps: n(es)?,
                    allocs: n(ea)?,
                },
            },
        );
    }
    Some(Table {
        words,
        alloc_weight,
    })
}

/// The table this binary's cache holds, never measured here: what a run
/// prices by (rule R19).
pub(crate) fn cached() -> Option<Table> {
    let text = std::fs::read_to_string(cache_file()?).ok()?;
    parse(&text)
}

/// The table for this binary: read from the cache, else measured and kept.
pub(crate) fn table() -> Table {
    let file = cache_file();
    if let Some(t) = file
        .as_deref()
        .and_then(|f| std::fs::read_to_string(f).ok())
        .and_then(|text| parse(&text))
    {
        return t;
    }
    let t = measured();
    if let Some(f) = file {
        if let Some(dir) = f.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let _ = std::fs::write(f, render(&t));
    }
    t
}

/// Each top-level definition of the entry file at `path`, with its price.
pub(crate) fn of(path: &Path, src: &str) -> Result<Vec<(String, Price)>, crate::CliError> {
    let checked = blue_lang_runtime::pipeline::check_entry(
        blue_lang_runtime::uses::Entry {
            path: Some(path),
            text: src,
        },
        &blue_lang_pkg::load_path::LoadPath::for_entry(path),
        None,
        blue_lang_runtime::pipeline::Checking::Program,
    )?;
    if !checked.outcome.ok() {
        return Err(crate::CliError::Pkg(format!(
            "{} does not pass the check stage: run `blue check {}`",
            path.display(),
            path.display()
        )));
    }
    let table = table();
    let lowered = checked.lowered();
    let erased = blue_lang_runtime::erase::unfused(&lowered);
    Ok(erased
        .iter()
        .enumerate()
        .filter(|(i, _)| {
            checked.program.owner_of(*i) == Some(blue_lang_runtime::uses::ResolvedProgram::ENTRY)
        })
        .filter_map(|(_, form)| {
            let (key, _) = blue_lang_runtime::def_hash::defined(form)?;
            Some((
                blue_lang_runtime::observe::display_key(key),
                cost::estimate(form, &table, NOMINAL),
            ))
        })
        .collect())
}

/// The report `blue cost` prints.
pub(crate) fn report(path: &Path, src: &str) -> Result<String, crate::CliError> {
    let started = Instant::now();
    let table = table();
    let rows = of(path, src)?;
    let mut out = format!(
        "cost: {} (lists of {NOMINAL} elements; an allocation weighs {:.2} steps; {:.0} ms)\n",
        path.display(),
        table.alloc_weight,
        started.elapsed().as_secs_f64() * 1000.0
    );
    out.push_str(&format!(
        "{:>14} {:>14} {:>14}  definition\n",
        "units", "steps", "allocs"
    ));
    for (name, p) in rows {
        out.push_str(&format!(
            "{:>14.0} {:>14.0} {:>14.0}  {name}\n",
            p.units(table.alloc_weight),
            p.steps,
            p.allocs
        ));
    }
    Ok(out)
}
