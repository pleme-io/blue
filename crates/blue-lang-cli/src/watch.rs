//! `blue watch [CMD] PATH… [-- ARGS…]`: rerun `check`, `test` or `run` on
//! every save.
//!
//! **Polling, not an fs-notify crate.** Every 300 ms the watch reads the
//! modification time of each watched file. That costs a few hundred `stat`
//! calls a second on a project the size of blue's own distribution, sees an
//! editor's write-to-temp-then-rename the same as an in-place write, and adds
//! no dependency (notify is in Cargo.lock only through another crate, and its
//! backends differ per platform in exactly the way a poll does not).
//!
//! **What is watched.** A directory PATH: every `.b` file and `Bluefile`
//! under it. A file PATH: the file and the package roots of the project it
//! sits in (`blue_lang_pkg::load_path::project_roots`), the local code it can
//! `use`. `BLUE_PATH` and the compiled-in distribution are not watched; they
//! do not change under an edit.
//!
//! **Each run is a fresh `blue` process** (this binary, `CMD PATH`), so a
//! program that aborts (deep recursion does) ends that run and not the watch,
//! and no state leaks from one run into the next. A save while a run is going
//! is seen on the next poll after it. The snapshot is taken after each run, so
//! a file the run itself rewrites (the canonical-source rule formats a messy
//! file in place) does not trigger another.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::time::{Duration, Instant, SystemTime};

/// The subcommands a watch reruns.
const VERBS: [&str; 3] = ["check", "test", "run"];

const POLL: Duration = Duration::from_millis(300);

/// Split `[CMD] PATH…` into the subcommand (`check` when none is named) and
/// the paths. A path named like a verb is written `./test`, as for `blue FILE`.
pub fn parse(targets: &[String]) -> Result<(&str, Vec<PathBuf>), String> {
    let (verb, paths) = match targets.split_first() {
        Some((v, rest)) if VERBS.contains(&v.as_str()) => (v.as_str(), rest),
        _ => ("check", targets),
    };
    if paths.is_empty() {
        return Err(format!("`blue watch {verb}` needs a PATH to watch"));
    }
    Ok((verb, paths.iter().map(PathBuf::from).collect()))
}

/// Run `verb` over `paths` now and after every change, until interrupted.
pub fn watch(verb: &str, paths: &[PathBuf], args: &[String]) -> Result<ExitCode, String> {
    let me = std::env::current_exe().map_err(|e| format!("cannot find this blue: {e}"))?;
    loop {
        for path in paths {
            let mut cmd = Command::new(&me);
            cmd.arg(verb).arg(path);
            if verb == "run" && !args.is_empty() {
                cmd.arg("--").args(args);
            }
            println!("── blue {verb} {}", path.display());
            let started = Instant::now();
            let verdict = match cmd.status() {
                Ok(s) if s.success() => "ok".to_string(),
                Ok(s) => format!("failed ({s})"),
                Err(e) => format!("could not start: {e}"),
            };
            println!("── {verdict} in {} ms", started.elapsed().as_millis());
        }
        let before = snapshot(paths);
        println!(
            "── watching {} file(s); a save reruns, Ctrl-C stops",
            before.len()
        );
        let mut seen = before.clone();
        loop {
            std::thread::sleep(POLL);
            let now = snapshot(paths);
            // A change is acted on once it has held for one poll, so an
            // editor's several writes for one save are one run.
            if now != before && now == seen {
                break;
            }
            seen = now;
        }
    }
}

/// Every watched file and its modification time.
fn snapshot(paths: &[PathBuf]) -> BTreeMap<PathBuf, SystemTime> {
    let mut files = BTreeMap::new();
    for path in paths {
        if path.is_dir() {
            sources(path, &mut files);
        } else {
            stamp(path, &mut files);
            for root in blue_lang_pkg::load_path::project_roots(path) {
                sources(&root, &mut files);
            }
        }
    }
    files
}

fn stamp(path: &Path, files: &mut BTreeMap<PathBuf, SystemTime>) {
    let time = std::fs::metadata(path)
        .and_then(|m| m.modified())
        .unwrap_or(SystemTime::UNIX_EPOCH);
    files.insert(path.to_path_buf(), time);
}

/// The `.b` files and Bluefiles under `dir`, skipping hidden directories and
/// build output (`target`, `result`).
fn sources(dir: &Path, files: &mut BTreeMap<PathBuf, SystemTime>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.filter_map(Result::ok) {
        let path = entry.path();
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if path.is_dir() {
            if !name.starts_with('.') && name != "target" && name != "result" {
                sources(&path, files);
            }
        } else if name == "Bluefile" || path.extension().is_some_and(|e| e == "b") {
            stamp(&path, files);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_verb_is_optional_and_defaults_to_check() {
        let s = |v: &[&str]| v.iter().map(ToString::to_string).collect::<Vec<_>>();
        assert_eq!(
            parse(&s(&["x.b"])).unwrap(),
            ("check", vec![PathBuf::from("x.b")])
        );
        assert_eq!(
            parse(&s(&["test", "a.b", "d"])).unwrap(),
            ("test", vec![PathBuf::from("a.b"), PathBuf::from("d")])
        );
        assert_eq!(
            parse(&s(&["./test"])).unwrap(),
            ("check", vec![PathBuf::from("./test")])
        );
        assert!(parse(&s(&["run"])).is_err());
    }
}
