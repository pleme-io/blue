//! The doors that watch a program run: `blue test` (one file or a tree, a
//! name filter, `--coverage`), `blue profile` and `blue trace`.
//!
//! All three read one mechanism, `blue_lang_runtime::observe`: the evaluator's
//! call hook, with a `Recorder` installed as its observer. Coverage is the
//! recorder's call counts over the entry file's definitions, a profile is the
//! same counts timed, and a trace is the recorder printing one definition's
//! calls as they happen. A runtime error's call stack is the hook's other arm
//! and needs no flag. When `BLUE_MEMO` is on (`crate::memo`), the call memo
//! sits on the same hook: `blue test` installs it in place of nothing,
//! `blue profile` wraps the recorder in it and reports its counts. `blue
//! test` also wraps whatever watches the run in the witness
//! (`crate::witness`), which records what each loose definition's calls
//! showed.

use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use blue_lang_runtime::observe::{
    CallObserver, Definitions, Exit, Measured, Recorder, TraceEvent, Tracer,
};
use blue_lang_runtime::uses::Entry;

use crate::config::BlueConfig;
use crate::{read_compiled, CliError};

/// How long a rendered value in a trace line may get before it is cut.
const VALUE_WIDTH: usize = 80;

/// What one file's tests produced, printed once every file is done so a
/// parallel run reads in file order.
struct FileRun {
    path: PathBuf,
    /// Diagnostics and failures, for stderr.
    errors: String,
    report: Option<blue_lang_test::Report>,
    coverage: Option<Vec<Measured>>,
    arms: Option<Arc<blue_lang_test::Arms>>,
    /// Each definition's and each test's `def_hash`, when facts are asked.
    identities: Option<blue_lang_mondou::def_hash::TestIdentities>,
    passed_keys: Vec<String>,
    cached_keys: Vec<String>,
}

/// How `blue test` watches what it runs.
#[derive(Clone, Copy)]
pub(crate) struct Watch<'a> {
    pub filter: Option<&'a str>,
    pub coverage: bool,
    pub json: bool,
    pub memo: crate::memo::Mode,
    pub cache: Option<&'a crate::test_cache::TestCache>,
    pub proofs: Option<&'a Path>,
}

/// `blue test PATH [--filter PATTERN] [--coverage [--json]] [--allow CAP]
/// [--facts FILE]`.
///
/// A file runs as it always has. A directory runs every `.b` file under it
/// that holds a `test` block, files in parallel, and ends with one summary
/// line. Non-zero when any file fails to check, any test fails, or no test
/// ran at all. With `hold`, every file's tests are held to it; with `facts`,
/// the facts and the evidence are written once every file is done
/// (`crate::facts`).
pub(crate) fn test(
    path: &Path,
    watch: &Watch<'_>,
    hold: Option<blue_lang_runtime::Hold>,
    facts: Option<&Path>,
) -> Result<ExitCode, CliError> {
    hermetic()?;
    let (filter, json) = (watch.filter, watch.json);
    let tree = path.is_dir();
    let files = if tree {
        test_files(path)
    } else {
        vec![path.to_path_buf()]
    };
    let hold = match (hold, watch.cache) {
        (None, Some(_)) => Some(blue_lang_runtime::Hold::from(blue_lang_waku::Waku::top())),
        (hold, _) => hold,
    };
    let guard = blue_lang_test::Guard {
        hold,
        max_alloc_bytes: blue_lang_runtime::execution_bounds().max_alloc_bytes,
        identify: Some(blue_lang_mondou::def_hash::identify),
        ..blue_lang_test::Guard::default()
    };
    let runs = run_files(&files, watch, &guard, facts.is_some())?;
    if let Some(cache) = watch.cache {
        let keys: Vec<String> = runs.iter().flat_map(|r| r.passed_keys.clone()).collect();
        cache.record(&keys);
    }
    if let Some(file) = watch.proofs {
        write_proofs(file, watch.cache, &runs)?;
    }
    if let (Some(facts), Some(hold)) = (facts, &guard.hold) {
        let evidence: Vec<crate::facts::FileEvidence<'_>> = runs
            .iter()
            .map(|r| crate::facts::FileEvidence {
                path: &r.path,
                report: r.report.as_ref(),
                identities: r.identities.as_ref(),
            })
            .collect();
        crate::facts::write(facts, hold, &evidence).map_err(CliError::Fmt)?;
    }
    let (mut total, mut passed, mut failed, mut skipped, mut broken) = (0, 0, 0, 0, 0);
    let mut cached = 0;
    for run in &runs {
        eprint!("{}", run.errors);
        match &run.report {
            Some(r) => {
                total += r.total();
                passed += r.passed;
                failed += r.failures.len();
                skipped += r.skipped.len();
                cached += r.cached.len();
                if tree {
                    println!("{}: {}", run.path.display(), r.tally());
                }
            }
            None => broken += 1,
        }
        if let Some(rows) = &run.coverage {
            print_coverage(&run.path, rows, run.arms.as_deref(), json)?;
        }
    }
    let skips = if skipped > 0 {
        format!(", {skipped} skipped")
    } else {
        String::new()
    };
    let cached = if cached > 0 {
        format!(", {cached} cached")
    } else {
        String::new()
    };
    if let Some(laws) = law_tally(&runs) {
        println!("{laws}");
    }
    let tally = format!("{total} test(s): {passed} passed, {failed} failed{skips}{cached}");
    if tree {
        let files = runs.len();
        let broken = if broken > 0 {
            format!(", {broken} file(s) did not check")
        } else {
            String::new()
        };
        println!("{files} file(s), {tally}{broken}");
    } else if broken == 0 {
        println!("{tally}");
    }
    // Zero tests is a failure, not a pass: a mistyped path, a package that
    // lost its tests, or a filter that matches nothing tests nothing, and a
    // gate running `blue test` must not stay green over it.
    if total == 0 && broken == 0 {
        match filter {
            Some(f) => eprintln!("{}: no test name contains {f:?}", path.display()),
            None => eprintln!(
                "{}: no `test` blocks, so nothing was tested",
                path.display()
            ),
        }
        return Ok(ExitCode::FAILURE);
    }
    Ok(if failed == 0 && broken == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    })
}

const REPOSITORY_ENV: &[&str] = &[
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_PREFIX",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_COMMON_DIR",
    "GIT_NAMESPACE",
];

/// The laws a run checked, by the tier each block's name carries
/// (`blue_lang_check::laws::Tier`): `law(s): 1 proved, 0 refuted, 1 tested,
/// 0 unchecked`. `None` when the run checked no law, so a run without laws
/// prints what it always printed.
fn law_tally(runs: &[FileRun]) -> Option<String> {
    use blue_lang_check::laws::Tier;
    let names = runs.iter().filter_map(|r| r.report.as_ref()).flat_map(|r| {
        r.outcomes
            .iter()
            .map(|o| o.name.as_str())
            .chain(r.cached.iter().map(String::as_str))
    });
    let (mut proved, mut refuted, mut tested, mut unchecked) = (0, 0, 0, 0);
    for tier in names.filter_map(Tier::of_test) {
        match tier {
            Tier::Proved => proved += 1,
            Tier::Refuted => refuted += 1,
            Tier::Tested(_) => tested += 1,
            Tier::Unchecked => unchecked += 1,
        }
    }
    let total = proved + refuted + tested + unchecked;
    (total > 0).then(|| {
        format!("{total} law(s): {proved} proved, {refuted} refuted, {tested} tested, {unchecked} unchecked")
    })
}

fn hermetic() -> Result<(), CliError> {
    match std::env::var("BLUE_TEST_ENV").as_deref() {
        Err(_) | Ok("scrub") => {
            for name in REPOSITORY_ENV {
                std::env::remove_var(name);
            }
        }
        Ok("inherit") => {}
        Ok(other) => {
            return Err(CliError::Usage(format!(
                "BLUE_TEST_ENV is \"{other}\"; it takes scrub (the default) or inherit"
            )))
        }
    }
    match std::env::var("BLUE_TEST_WRITES").as_deref() {
        Err(_) | Ok("temp") => {
            blue_lang_runtime::sys::confine_writes(Some(vec![std::env::temp_dir()]));
        }
        Ok("anywhere") => blue_lang_runtime::sys::confine_writes(None),
        Ok(other) => {
            return Err(CliError::Usage(format!(
                "BLUE_TEST_WRITES is \"{other}\"; it takes temp (the default) or anywhere"
            )))
        }
    }
    Ok(())
}

/// Every `.b` file under `root` with a top-level `test` block, in path order.
/// Hidden directories, `target` and nix `result` links are not walked.
/// Whether a skip counts as a failure on this host: `BLUE_TEST_SKIP=refuse`.
/// The default lets a test name why it cannot run here.
fn refuse_skips() -> Result<bool, CliError> {
    match std::env::var("BLUE_TEST_SKIP").as_deref() {
        Err(_) | Ok("allow") => Ok(false),
        Ok("refuse") => Ok(true),
        Ok(other) => Err(CliError::Usage(format!(
            "BLUE_TEST_SKIP is \"{other}\"; it takes allow (the default) or refuse"
        ))),
    }
}

fn test_files(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut dirs = vec![root.to_path_buf()];
    while let Some(dir) = dirs.pop() {
        if !std::fs::canonicalize(&dir).is_ok_and(|c| seen.insert(c)) {
            continue;
        }
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            let Ok(kind) = std::fs::metadata(&path).map(|m| m.file_type()) else {
                continue;
            };
            if kind.is_dir() {
                if !name.starts_with('.') && name != "target" && !name.starts_with("result") {
                    dirs.push(path);
                }
            } else if kind.is_file()
                && path.extension().is_some_and(|e| e == "b")
                && std::fs::read_to_string(&path).is_ok_and(|t| {
                    t.lines().any(|l| {
                        l.starts_with("test \"")
                            || l.starts_with("@doc ")
                            || l.starts_with("@moduledoc ")
                    })
                })
            {
                out.push(path);
            }
        }
    }
    out.sort();
    out
}

/// The order to start `files` in: the largest first, so the file that runs
/// longest does not start last and run alone. Ties keep their given order.
fn longest_first(files: &[PathBuf]) -> Vec<usize> {
    let size = |p: &PathBuf| std::fs::metadata(p).map_or(0, |m| m.len());
    let mut order: Vec<usize> = (0..files.len()).collect();
    order.sort_by_key(|&i| std::cmp::Reverse(size(&files[i])));
    order
}

/// Run each file's tests, across as many threads as the machine has, the
/// largest file first.
fn run_files(
    files: &[PathBuf],
    watch: &Watch<'_>,
    guard: &blue_lang_test::Guard,
    identify: bool,
) -> Result<Vec<FileRun>, CliError> {
    let workers = std::thread::available_parallelism()
        .map_or(1, std::num::NonZero::get)
        .min(files.len().max(1));
    let order = longest_first(files);
    let next = AtomicUsize::new(0);
    let mut slots: Vec<Option<Result<FileRun, CliError>>> =
        std::iter::repeat_with(|| None).take(files.len()).collect();
    let results = std::sync::Mutex::new(&mut slots);
    std::thread::scope(|scope| {
        for _ in 0..workers {
            std::thread::Builder::new()
                .stack_size(64 << 20)
                .spawn_scoped(scope, || loop {
                    let Some(&i) = order.get(next.fetch_add(1, Ordering::Relaxed)) else {
                        break;
                    };
                    let path = &files[i];
                    // A file that cannot be read or loaded is that file's
                    // failure, not the tree's: its siblings still run.
                    let run = test_file(path, watch, guard, identify).or_else(|e| {
                        Ok(FileRun {
                            path: path.clone(),
                            errors: format!("blue: {}: {e}\n", path.display()),
                            report: None,
                            coverage: None,
                            arms: None,
                            identities: None,
                            passed_keys: Vec::new(),
                            cached_keys: Vec::new(),
                        })
                    });
                    if let Ok(mut slots) = results.lock() {
                        slots[i] = Some(run);
                    }
                })
                .expect("spawn a test worker");
        }
    });
    slots.into_iter().flatten().collect()
}

/// Check one file, then run its (filtered) tests, recording coverage if asked
/// and memoized when `memo` is on and coverage was not asked: coverage
/// reports what the code does, and an answered call does nothing.
fn test_file(
    path: &Path,
    watch: &Watch<'_>,
    guard: &blue_lang_test::Guard,
    identify: bool,
) -> Result<FileRun, CliError> {
    use std::fmt::Write as _;
    let own;
    let guard = match blue_lang_pkg::capabilities::bounds_for(path) {
        Some(bounds) => {
            own = blue_lang_test::Guard {
                bounds: Some(bounds),
                ..guard.clone()
            };
            &own
        }
        None => guard,
    };
    let (filter, coverage) = (watch.filter, watch.coverage);
    let memo = crate::memo::unless_bounded(watch.memo, guard.bounds);
    let src = read_compiled(path)?;
    // The check stage first, test blocks included: no test runs over a
    // program with an error, as `run` would not evaluate it.
    let checked = blue_lang_runtime::pipeline::check_entry(
        Entry {
            path: Some(path),
            text: &src,
        },
        &blue_lang_pkg::load_path::LoadPath::for_entry(path),
        None,
        blue_lang_runtime::pipeline::Checking::WithTests,
    )?;
    let mut errors = String::new();
    for d in &checked.outcome.diagnostics {
        let _ = writeln!(
            errors,
            "{}",
            blue_lang_runtime::pipeline::render(&checked.program, d)
        );
    }
    if !checked.outcome.ok() {
        let _ = writeln!(
            errors,
            "blue: {}: the check stage rejected the file, so no test ran",
            path.display()
        );
        return Ok(FileRun {
            path: path.to_path_buf(),
            errors,
            report: None,
            coverage: None,
            arms: None,
            identities: None,
            passed_keys: Vec::new(),
            cached_keys: Vec::new(),
        });
    }
    let memoized = memo != crate::memo::Mode::Off && !coverage;
    let witnessing = crate::witness::enabled();
    let lowered = (coverage || memoized || witnessing).then(|| checked.lowered());
    let watched = lowered
        .as_ref()
        .filter(|_| coverage || memoized)
        .map(|lowered| {
            let erased = blue_lang_runtime::erase_types(lowered);
            let defs = Arc::new(Definitions::of(&checked.program, &erased));
            (lowered, erased, defs)
        });
    let recorder = watched
        .as_ref()
        .filter(|_| coverage)
        .map(|(_, _, defs)| Arc::new(Recorder::new(Arc::clone(defs), false, None)));
    let recall = watched
        .as_ref()
        .filter(|_| memoized)
        .map(|(lowered, erased, defs)| {
            crate::memo::over(memo.persist(), defs, lowered, erased, None)
        });
    let watching = match (&recall, &recorder) {
        (Some(m), _) => Some(Arc::clone(m) as Arc<dyn CallObserver>),
        (None, Some(r)) => Some(Arc::clone(r) as Arc<dyn CallObserver>),
        (None, None) => None,
    };
    let witness = lowered
        .as_ref()
        .filter(|_| witnessing)
        .map(|lowered| crate::witness::over(lowered, &checked.program, watching.clone()));
    let observer = match &witness {
        Some(w) => Some(Arc::clone(w) as Arc<dyn CallObserver>),
        None => watching,
    };
    let identities = (identify || watch.cache.is_some()).then(|| {
        let lowered = checked.lowered();
        blue_lang_mondou::def_hash::test_identities(
            &lowered,
            &blue_lang_mondou::program_docs(&checked.program),
        )
    });
    let bounds = format!(
        "{:?} {:?} {:?}",
        guard.bounds,
        blue_lang_runtime::execution_bounds(),
        guard.max_alloc_bytes
    );
    let key_of = |test: usize| {
        watch
            .cache
            .zip(identities.as_ref())
            .and_then(|(cache, ids)| cache.key(ids, test, &bounds))
    };
    let own;
    let mut cached_keys = Vec::new();
    let guard = match (watch.cache, &identities) {
        (Some(cache), Some(ids)) => {
            let hits: Vec<(usize, String)> = ids
                .tests
                .keys()
                .filter_map(|&t| key_of(t).filter(|k| cache.passed(k)).map(|k| (t, k)))
                .collect();
            own = blue_lang_test::Guard {
                cached: hits.iter().map(|(t, _)| *t).collect(),
                ..guard.clone()
            };
            cached_keys = hits.into_iter().map(|(_, k)| k).collect();
            &own
        }
        _ => guard,
    };
    let arms = recorder
        .as_ref()
        .map(|_| Arc::new(blue_lang_test::Arms::default()));
    let armed;
    let guard = match &arms {
        Some(a) => {
            armed = blue_lang_test::Guard {
                arms: Some(Arc::clone(a)),
                ..guard.clone()
            };
            &armed
        }
        None => guard,
    };
    let report = blue_lang_test::run_guarded(&checked, filter, observer, guard);
    let passed_keys = if report.preamble_host_io == 0 {
        report
            .outcomes
            .iter()
            .filter(|o| o.passed && o.host_io == 0)
            .filter_map(|o| o.top_level.and_then(key_of))
            .collect()
    } else {
        Vec::new()
    };
    let identities = identities.filter(|_| identify);
    if let Some(m) = &recall {
        crate::memo::finish(m);
    }
    if let Some(w) = &witness {
        crate::witness::finish(w);
    }
    let mut report = report;
    if refuse_skips()? {
        report.refuse_skips();
    }
    for failure in &report.failures {
        let _ = writeln!(errors, "{failure}");
    }
    for skip in &report.skipped {
        let _ = writeln!(errors, "{skip}");
    }
    Ok(FileRun {
        path: path.to_path_buf(),
        errors,
        report: Some(report),
        coverage: recorder.map(|r| r.report()),
        arms,
        identities,
        passed_keys,
        cached_keys,
    })
}

fn b3(bytes: &[u8; 32]) -> String {
    format!("b3:{}", blue_lang_mondou::def_hash::DefHash(*bytes).hex())
}

fn write_proofs(
    file: &Path,
    cache: Option<&crate::test_cache::TestCache>,
    runs: &[FileRun],
) -> Result<(), CliError> {
    let cached: Vec<serde_json::Value> = runs
        .iter()
        .flat_map(|r| r.cached_keys.iter().map(move |k| (r, k)))
        .filter_map(|(r, k)| {
            let proof = cache?.prove(k)?;
            Some(serde_json::json!({
                "file": r.path.display().to_string(),
                "key": format!("b3:{k}"),
                "index": proof.index,
                "path": proof.path.iter().map(b3).collect::<Vec<_>>(),
            }))
        })
        .collect();
    let doc = serde_json::json!({
        "root": cache.map(|c| b3(&c.root())),
        "total": cache.map_or(0, crate::test_cache::TestCache::total),
        "cached": cached,
    });
    std::fs::write(file, format!("{doc}\n"))
        .map_err(|e| CliError::Fmt(format!("{}: {e}", file.display())))
}

/// The entry file's definitions with their call counts, uncovered ones marked.
fn print_coverage(
    path: &Path,
    rows: &[Measured],
    arms: Option<&blue_lang_test::Arms>,
    json: bool,
) -> Result<(), CliError> {
    let defs: Vec<&Measured> = rows
        .iter()
        .filter(|m| m.entry && m.definition.is_some())
        .collect();
    let covered = defs.iter().filter(|m| m.counts.calls > 0).count();
    let untaken = arms.map(blue_lang_test::Arms::untaken).unwrap_or_default();
    if json {
        let line = serde_json::json!({
            "file": path.display().to_string(),
            "covered": covered,
            "total": defs.len(),
            "definitions": defs.iter().map(|m| serde_json::json!({
                "name": m.name,
                "line": m.place.line,
                "calls": m.counts.calls,
            })).collect::<Vec<_>>(),
            "uncovered": defs.iter().filter(|m| m.counts.calls == 0)
                .map(|m| m.name.clone()).collect::<Vec<_>>(),
            "arms": arms.map_or(0, blue_lang_test::Arms::total),
            "untaken": untaken,
        });
        println!("{}", serde_json::to_string(&line)?);
        return Ok(());
    }
    for arm in &untaken {
        println!("  untaken arm {arm}");
    }
    println!("coverage: {}", path.display());
    println!("  {:>8}  {:<32}  defined at", "calls", "definition");
    for m in &defs {
        let mark = if m.counts.calls == 0 {
            "  uncovered"
        } else {
            ""
        };
        println!("  {:>8}  {:<32}  {}{mark}", m.counts.calls, m.name, m.place);
    }
    let pct = if defs.is_empty() {
        100.0
    } else {
        #[allow(clippy::cast_precision_loss)]
        let p = covered as f64 * 100.0 / defs.len() as f64;
        p
    };
    println!("  {covered}/{} definitions covered ({pct:.1}%)", defs.len());
    Ok(())
}

/// Run FILE the way `blue run` does, with `watch` observing every call.
fn run_watched(
    file: &Path,
    args: Vec<String>,
    cfg: &BlueConfig,
    watch: impl FnOnce(&blue_lang_runtime::pipeline::Watched<'_>) -> Arc<dyn CallObserver>,
) -> Result<blue_lang_runtime::pipeline::Observed, CliError> {
    blue_lang_runtime::sys::set_program_args(args);
    let src = crate::read_run(file)?;
    let inputs = crate::bind_inputs(&src, &[], cfg)?;
    Ok(blue_lang_runtime::pipeline::run_observed_accounted(
        Entry {
            path: Some(file),
            text: &src,
        },
        inputs,
        &blue_lang_pkg::load_path::LoadPath::for_entry(file),
        None,
        None,
        &crate::receipt::account(None),
        watch,
    )?)
}

#[allow(clippy::cast_precision_loss)]
fn ms(d: Duration) -> f64 {
    d.as_secs_f64() * 1000.0
}

/// `blue profile FILE [--top N] [--json]`: run FILE, then every function it
/// called with its call count, inclusive and exclusive time, and what it
/// allocated (this binary installs `blue_lang_runtime::alloc::Counting`), most
/// exclusive time first.
pub(crate) fn profile(
    file: &Path,
    top: usize,
    json: bool,
    memo: crate::memo::Mode,
    args: Vec<String>,
    cfg: &BlueConfig,
) -> Result<ExitCode, CliError> {
    let mut recorder = None;
    let mut memoized = None;
    let started = Instant::now();
    let observed = run_watched(file, args, cfg, |w| {
        let r = Arc::new(Recorder::new(Arc::clone(w.definitions), true, None));
        recorder = Some(Arc::clone(&r));
        if memo == crate::memo::Mode::Off {
            return r;
        }
        let m = crate::memo::over(memo.persist(), w.definitions, w.lowered, w.erased, Some(r));
        memoized = Some(Arc::clone(&m));
        m
    })?;
    let total = started.elapsed();
    if let Some(m) = &memoized {
        crate::memo::finish(m);
    }
    let memo_report = memoized.as_ref().map(|m| m.report());
    let counted = recorder.as_ref().is_some_and(|r| r.counts_allocations());
    let mut rows: Vec<Measured> = recorder
        .map(|r| r.report())
        .unwrap_or_default()
        .into_iter()
        .filter(|m| m.counts.calls > 0)
        .collect();
    rows.sort_by(|a, b| {
        b.counts
            .exclusive
            .cmp(&a.counts.exclusive)
            .then_with(|| a.name.cmp(&b.name))
    });
    let failed = report_outcome(&observed.outcome);
    if json {
        let mut line = serde_json::json!({
            "file": file.display().to_string(),
            "total_ms": ms(total),
            "functions": rows.iter().take(top).map(|m| serde_json::json!({
                "name": m.name,
                "file": m.place.file,
                "line": m.place.line,
                "calls": m.counts.calls,
                "inclusive_ms": ms(m.counts.inclusive),
                "exclusive_ms": ms(m.counts.exclusive),
                "inclusive_allocations": counted.then_some(m.counts.allocated.count),
                "inclusive_bytes": counted.then_some(m.counts.allocated.bytes),
                "exclusive_allocations": counted.then_some(m.counts.allocated_exclusive.count),
                "exclusive_bytes": counted.then_some(m.counts.allocated_exclusive.bytes),
            })).collect::<Vec<_>>(),
        });
        if let Some(r) = &memo_report {
            line["memo"] = crate::memo::json(r);
        }
        println!("{}", serde_json::to_string(&line)?);
    } else {
        println!(
            "profile: {} ({:.1} ms wall, parse and check included; {} function(s) called)",
            file.display(),
            ms(total),
            rows.len()
        );
        println!(
            "  {:>10}  {:>10}  {:>10}  {:>6}  {:>10}  {:>10}  {:<32}  defined at",
            "calls", "incl ms", "excl ms", "excl%", "excl alloc", "excl KiB", "function"
        );
        for m in rows.iter().take(top) {
            #[allow(clippy::cast_precision_loss)]
            let share = ms(m.counts.exclusive) * 100.0 / ms(total).max(f64::MIN_POSITIVE);
            // Unmeasured reads as a dash, never as a zero that claims nothing
            // was allocated.
            let (allocs, kib) = if counted {
                #[allow(clippy::cast_precision_loss)]
                let kib = m.counts.allocated_exclusive.bytes as f64 / 1024.0;
                (
                    m.counts.allocated_exclusive.count.to_string(),
                    format!("{kib:.1}"),
                )
            } else {
                ("-".to_string(), "-".to_string())
            };
            println!(
                "  {:>10}  {:>10.2}  {:>10.2}  {:>5.1}%  {:>10}  {:>10}  {:<32}  {}",
                m.counts.calls,
                ms(m.counts.inclusive),
                ms(m.counts.exclusive),
                share,
                allocs,
                kib,
                m.name,
                m.place
            );
        }
        if rows.len() > top {
            println!("  … {} more (--top)", rows.len() - top);
        }
        if let Some(r) = &memo_report {
            crate::memo::print(r);
        }
    }
    Ok(if failed {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    })
}

/// Print a watched run's runtime error, if it had one. True when it did.
fn report_outcome(outcome: &Result<blue_lang_runtime::Run, blue_lang_runtime::RunError>) -> bool {
    match outcome {
        Ok(_) => false,
        Err(e) => {
            eprintln!("blue: {e}");
            true
        }
    }
}

/// A value as blue source, cut at [`VALUE_WIDTH`] characters.
fn short(v: &tatara_lisp_eval::Value) -> String {
    let text = blue_lang_runtime::literal::render_value(v);
    if text.chars().count() <= VALUE_WIDTH {
        return text;
    }
    let cut: String = text.chars().take(VALUE_WIDTH).collect();
    format!("{cut}…")
}

/// `blue trace DEF FILE [--limit N]`: run FILE and print every call of DEF
/// with its arguments, and every exit with its value, nested calls indented.
/// Trace lines go to stderr so the program's own output stays on stdout.
pub(crate) fn trace(
    def: &str,
    file: &Path,
    limit: usize,
    args: Vec<String>,
    cfg: &BlueConfig,
) -> Result<ExitCode, CliError> {
    // Refused before anything runs: a trace of a name the program does not
    // define would run the program for nothing.
    let src = crate::read_run(file)?;
    let checked = blue_lang_runtime::pipeline::check_entry(
        Entry {
            path: Some(file),
            text: &src,
        },
        &blue_lang_pkg::load_path::LoadPath::for_entry(file),
        None,
        blue_lang_runtime::pipeline::Checking::Program,
    )?;
    if checked.outcome.ok()
        && Definitions::of(&checked.program, &checked.erased())
            .named(def)
            .is_empty()
    {
        eprintln!(
            "blue: {}: no definition named `{def}` in the file or what it imports",
            file.display()
        );
        return Ok(ExitCode::FAILURE);
    }
    let lines = Arc::new(AtomicUsize::new(0));
    let calls = Arc::new(AtomicUsize::new(0));
    let observed = {
        let lines = Arc::clone(&lines);
        let calls = Arc::clone(&calls);
        run_watched(file, args, cfg, |w| {
            let defs = w.definitions;
            let targets = defs.named(def);
            let sink = move |event: &TraceEvent<'_>| {
                if matches!(event, TraceEvent::Call { .. }) {
                    calls.fetch_add(1, Ordering::Relaxed);
                }
                let n = lines.fetch_add(1, Ordering::Relaxed);
                if n == limit {
                    eprintln!("… trace stopped after {limit} line(s) (--limit)");
                }
                if n >= limit {
                    return;
                }
                let render = |args: &[tatara_lisp_eval::Value]| {
                    args.iter().map(short).collect::<Vec<_>>().join(", ")
                };
                match event {
                    TraceEvent::Call { depth, name, args } => {
                        eprintln!("{}-> {name}({})", "  ".repeat(*depth), render(args));
                    }
                    TraceEvent::Exit {
                        depth,
                        name,
                        args,
                        exit,
                    } => {
                        let how = match exit {
                            Exit::Returned(v) => format!("= {}", short(v)),
                            Exit::Supplied(v) => format!("= {} (supplied)", short(v)),
                            Exit::TailCalled => "tail call".to_string(),
                            Exit::Raised(e) => format!("raised: {}", e.short_message()),
                        };
                        eprintln!("{}<- {name}({}) {how}", "  ".repeat(*depth), render(args));
                    }
                }
            };
            Arc::new(Recorder::new(
                Arc::clone(defs),
                false,
                Some(Tracer {
                    targets,
                    sink: Box::new(sink),
                }),
            ))
        })?
    };
    let failed = report_outcome(&observed.outcome);
    eprintln!("{def}: {} call(s)", calls.load(Ordering::Relaxed));
    Ok(if failed {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    })
}

/// A `RunError` as one JSON object, for `blue run --format json`: a runtime
/// error carries its position and call stack (`observe::Fault::json`), every
/// other stage its message.
pub(crate) fn error_json(e: &blue_lang_runtime::RunError) -> serde_json::Value {
    use blue_lang_runtime::RunError;
    let stage = |stage: &str, message: String| serde_json::json!({ "stage": stage, "severity": "error", "message": message });
    match e {
        RunError::Eval(fault) => fault.json(),
        RunError::Parse(m) => stage("parse", m.clone()),
        RunError::Types(lines) => stage("check", lines.join("\n")),
        RunError::Import(m) => stage("import", m.clone()),
        RunError::Lower(m) => stage("lower", m.clone()),
    }
}

#[cfg(test)]
mod tests {
    use super::{longest_first, test_files};

    #[test]
    fn the_largest_file_starts_first_and_ties_keep_their_order() {
        let base = std::env::temp_dir().join(format!("blue-longest-{}", std::process::id()));
        std::fs::create_dir_all(&base).unwrap();
        let files: Vec<std::path::PathBuf> = [("a.b", 1), ("b.b", 30), ("c.b", 1), ("d.b", 7)]
            .iter()
            .map(|(n, len)| {
                let p = base.join(n);
                std::fs::write(&p, "x".repeat(*len)).unwrap();
                p
            })
            .collect();
        let order = longest_first(&files);
        std::fs::remove_dir_all(&base).unwrap();
        assert_eq!(order, vec![1, 3, 0, 2]);
        assert!(longest_first(&[]).is_empty());
    }

    #[test]
    fn a_bidama_of_symlinks_is_walked_as_its_files() {
        let base = std::env::temp_dir().join(format!("blue-test-files-{}", std::process::id()));
        let real = base.join("real");
        let linked = base.join("linked");
        std::fs::create_dir_all(&real).unwrap();
        std::fs::create_dir_all(&linked).unwrap();
        std::fs::write(real.join("k.b"), "test \"one\"\n  assert true\nend\n").unwrap();
        std::os::unix::fs::symlink(real.join("k.b"), linked.join("k.b")).unwrap();
        std::os::unix::fs::symlink(&linked, linked.join("loop")).unwrap();
        let found = test_files(&linked);
        std::fs::remove_dir_all(&base).unwrap();
        assert_eq!(found, vec![linked.join("k.b")]);
    }
}
