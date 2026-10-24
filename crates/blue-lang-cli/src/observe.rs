//! The doors that watch a program run: `blue test` (one file or a tree, a
//! name filter, `--coverage`), `blue profile` and `blue trace`.
//!
//! All three read one mechanism, `blue_lang_runtime::observe`: the evaluator's
//! call hook, with a `Recorder` installed as its observer. Coverage is the
//! recorder's call counts over the entry file's definitions, a profile is the
//! same counts timed, and a trace is the recorder printing one definition's
//! calls as they happen. A runtime error's call stack is the hook's other arm
//! and needs no flag.

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
}

/// `blue test PATH [--filter PATTERN] [--coverage [--json]]`.
///
/// A file runs as it always has. A directory runs every `.b` file under it
/// that holds a `test` block, files in parallel, and ends with one summary
/// line. Non-zero when any file fails to check, any test fails, or no test
/// ran at all.
pub(crate) fn test(
    path: &Path,
    filter: Option<&str>,
    coverage: bool,
    json: bool,
) -> Result<ExitCode, CliError> {
    hermetic()?;
    let tree = path.is_dir();
    let files = if tree {
        test_files(path)
    } else {
        vec![path.to_path_buf()]
    };
    let runs = run_files(&files, filter, coverage)?;
    let (mut total, mut passed, mut failed, mut broken) = (0, 0, 0, 0);
    for run in &runs {
        eprint!("{}", run.errors);
        match &run.report {
            Some(r) => {
                total += r.total();
                passed += r.passed;
                failed += r.failures.len();
                if tree {
                    println!(
                        "{}: {} test(s): {} passed, {} failed",
                        run.path.display(),
                        r.total(),
                        r.passed,
                        r.failures.len()
                    );
                }
            }
            None => broken += 1,
        }
        if let Some(rows) = &run.coverage {
            print_coverage(&run.path, rows, json)?;
        }
    }
    let tally = format!("{total} test(s): {passed} passed, {failed} failed");
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

/// Run each file's tests, across as many threads as the machine has.
fn run_files(
    files: &[PathBuf],
    filter: Option<&str>,
    coverage: bool,
) -> Result<Vec<FileRun>, CliError> {
    let workers = std::thread::available_parallelism()
        .map_or(1, std::num::NonZero::get)
        .min(files.len().max(1));
    let next = AtomicUsize::new(0);
    let mut slots: Vec<Option<Result<FileRun, CliError>>> =
        std::iter::repeat_with(|| None).take(files.len()).collect();
    let results = std::sync::Mutex::new(&mut slots);
    std::thread::scope(|scope| {
        for _ in 0..workers {
            std::thread::Builder::new()
                .stack_size(64 << 20)
                .spawn_scoped(scope, || loop {
                    let i = next.fetch_add(1, Ordering::Relaxed);
                    let Some(path) = files.get(i) else { break };
                    // A file that cannot be read or loaded is that file's
                    // failure, not the tree's: its siblings still run.
                    let run = test_file(path, filter, coverage).or_else(|e| {
                        Ok(FileRun {
                            path: path.clone(),
                            errors: format!("blue: {}: {e}\n", path.display()),
                            report: None,
                            coverage: None,
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

/// Check one file, then run its (filtered) tests, recording coverage if asked.
fn test_file(path: &Path, filter: Option<&str>, coverage: bool) -> Result<FileRun, CliError> {
    use std::fmt::Write as _;
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
        });
    }
    let recorder = coverage.then(|| {
        let defs = Arc::new(Definitions::of(&checked.program, &checked.erased()));
        Arc::new(Recorder::new(defs, false, None))
    });
    let observer = recorder.clone().map(|r| r as Arc<dyn CallObserver>);
    let report = blue_lang_test::run_checked(&checked, filter, observer);
    for failure in &report.failures {
        let _ = writeln!(errors, "{failure}");
    }
    Ok(FileRun {
        path: path.to_path_buf(),
        errors,
        report: Some(report),
        coverage: recorder.map(|r| r.report()),
    })
}

/// The entry file's definitions with their call counts, uncovered ones marked.
fn print_coverage(path: &Path, rows: &[Measured], json: bool) -> Result<(), CliError> {
    let defs: Vec<&Measured> = rows
        .iter()
        .filter(|m| m.entry && m.definition.is_some())
        .collect();
    let covered = defs.iter().filter(|m| m.counts.calls > 0).count();
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
        });
        println!("{}", serde_json::to_string(&line)?);
        return Ok(());
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
    watch: impl FnOnce(&Arc<Definitions>) -> Arc<dyn CallObserver>,
) -> Result<blue_lang_runtime::pipeline::Observed, CliError> {
    blue_lang_runtime::sys::set_program_args(args);
    let src = crate::read_run(file)?;
    let inputs = crate::bind_inputs(&src, &[], cfg)?;
    Ok(blue_lang_runtime::pipeline::run_observed(
        Entry {
            path: Some(file),
            text: &src,
        },
        inputs,
        &blue_lang_pkg::load_path::LoadPath::for_entry(file),
        None,
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
    args: Vec<String>,
    cfg: &BlueConfig,
) -> Result<ExitCode, CliError> {
    let mut recorder = None;
    let started = Instant::now();
    let observed = run_watched(file, args, cfg, |defs| {
        let r = Arc::new(Recorder::new(Arc::clone(defs), true, None));
        recorder = Some(Arc::clone(&r));
        r
    })?;
    let total = started.elapsed();
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
        let line = serde_json::json!({
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
        run_watched(file, args, cfg, |defs| {
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
    use super::test_files;

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
