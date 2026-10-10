//! A file is a program (`theory/BLUE-TOOLING.md` T-C), exercised as a
//! subprocess: `blue FILE [ARGS]`, a shebang script run by the operating
//! system, the load path a script gets with no Bluefile and no `BLUE_PATH`,
//! `blue new` and `blue watch`.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::mpsc;
use std::time::Duration;

/// The binary under test, with blue's environment inputs cleared so a
/// developer's `BLUE_PATH` cannot make a test pass.
fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG");
    c
}

/// A fresh scratch directory per test, outside any project.
fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-scripts-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir.canonicalize().expect("canonical scratch dir")
}

fn put(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).expect("mkdir");
    std::fs::write(path, text).expect("write fixture");
}

fn out(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

/// Writes its arguments joined by commas, and leaves a value behind.
const ARGS: &str = "write_stdout(\"#{join(argv(), \",\")}\\n\")\n42\n";

/// `blue FILE ARGS` is `blue run --quiet FILE -- ARGS`: every argument reaches
/// the program verbatim, flags and `--` included, and no final value is
/// printed. `blue run` keeps printing it.
#[test]
fn a_bare_file_runs_quietly_with_its_arguments_verbatim() {
    let dir = scratch("bare");
    let file = dir.join("args.b");
    put(&file, ARGS);
    let o = blue()
        .arg(&file)
        .args(["a", "-q", "--", "b"])
        .output()
        .unwrap();
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "a,-q,--,b\n");
    let o = blue()
        .arg("run")
        .arg(&file)
        .args(["--", "a"])
        .output()
        .unwrap();
    assert_eq!(out(&o), "a\n42\n");
}

/// A program's failure is the script's exit code.
#[test]
fn a_failing_script_exits_non_zero() {
    let dir = scratch("failing");
    let file = dir.join("boom.b");
    put(&file, "throw(error(:boom, \"no\"))\n");
    let o = blue().arg(&file).output().unwrap();
    assert!(!o.status.success(), "{}", out(&o));
    assert!(
        err(&o).contains(":boom"),
        "the program did not run: {}",
        err(&o)
    );
}

/// A `.b` path that does not exist is a missing file, not an unknown
/// subcommand.
#[test]
fn a_missing_b_file_is_reported_as_a_missing_file() {
    let o = blue()
        .arg("/nonexistent/blue-scripts/x.b")
        .output()
        .unwrap();
    assert!(!o.status.success());
    assert!(
        err(&o).contains("x.b") && !err(&o).contains("subcommand"),
        "{}",
        err(&o)
    );
}

/// `#!/usr/bin/env blue` on an executable file, run by the operating system
/// with the built `blue` first on PATH, no Bluefile around it and no
/// `BLUE_PATH`: the script has no `.b` extension, uses two standard bidamas,
/// and gets its arguments.
#[cfg(unix)]
#[test]
fn a_shebang_script_runs_directly() {
    let dir = scratch("shebang");
    let script = dir.join("greet");
    put(
        &script,
        "#!/usr/bin/env blue\nuse(\"kazu\", [:clamp])\nuse(\"retsu\", [:size])\n\nwrite_stdout(\"#{size(argv())} #{clamp(99, 1, 10)}\\n\")\n",
    );
    executable(&script);
    let bin = Path::new(env!("CARGO_BIN_EXE_blue")).parent().unwrap();
    let path = std::env::join_paths(std::iter::once(bin.to_path_buf()).chain(
        std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()),
    ))
    .unwrap();
    let o = Command::new(&script)
        .args(["x", "y"])
        .env("PATH", path)
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .output()
        .expect("the OS runs the script");
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "2 10\n");
}

/// With no Bluefile anywhere above it and no `BLUE_PATH`, a script reaches
/// every standard bidama: the distribution compiled into `blue`.
#[test]
fn a_script_with_no_structure_uses_the_standard_distribution() {
    let dir = scratch("standard");
    let file = dir.join("s.b");
    put(
        &file,
        "use(\"retsu\", [:first])\nuse(\"shuugou\", [:frequencies])\n\nwrite_stdout(\"#{first(first(frequencies([:a, :b, :a])))}\\n\")\n",
    );
    let o = blue().arg(&file).output().unwrap();
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "a\n");
    // Every door that compiles the file sees the same load path.
    for door in ["check", "test"] {
        let o = blue().arg(door).arg(&file).output().unwrap();
        assert!(!err(&o).contains("no bidama"), "{door}: {}", err(&o));
    }
}

/// A script beside a project's Bluefile uses the project's own packages; the
/// same script outside the project does not find them (the control).
#[test]
fn a_script_in_a_project_uses_the_projects_packages() {
    let dir = scratch("project");
    let proj = dir.join("proj");
    put(
        &proj.join("Bluefile"),
        "package(\"my-proj\", \"0.1.0\")\n\npackages(\"pkgs\")\n",
    );
    put(
        &proj.join("pkgs/hoshi/Bluefile"),
        "package(\"hoshi\", \"0.1.0\")\n",
    );
    put(
        &proj.join("pkgs/hoshi/hoshi.b"),
        "def twinkle()\n  \"*\"\nend\n",
    );
    let script = "use(\"hoshi\", [:twinkle])\n\nwrite_stdout(\"#{twinkle()}\\n\")\n";
    put(&proj.join("tools/s.b"), script);
    let o = blue().arg(proj.join("tools/s.b")).output().unwrap();
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "*\n");
    put(&dir.join("s.b"), script);
    let o = blue().arg(dir.join("s.b")).output().unwrap();
    assert!(!o.status.success());
    assert!(err(&o).contains("no bidama named \"hoshi\""), "{}", err(&o));
}

/// `BLUE_PATH` still comes first: a root on it holding `retsu` beats the
/// compiled-in `retsu`.
#[test]
fn blue_path_overrides_the_compiled_in_distribution() {
    let dir = scratch("override");
    put(
        &dir.join("root/retsu/Bluefile"),
        "package(\"retsu\", \"0.1.0\")\n",
    );
    put(
        &dir.join("root/retsu/retsu.b"),
        "def precedence_marker()\n  42\nend\n",
    );
    let file = dir.join("s.b");
    put(
        &file,
        "use(\"retsu\", [:precedence_marker])\n\nwrite_stdout(\"#{precedence_marker()}\\n\")\n",
    );
    let o = blue().arg(&file).output().unwrap();
    assert!(!o.status.success(), "the compiled-in retsu has no marker");
    let o = blue()
        .env("BLUE_PATH", dir.join("root"))
        .arg(&file)
        .output()
        .unwrap();
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "42\n");
}

/// A subcommand beats a file of its name; `./NAME` runs the file.
#[test]
fn a_subcommand_beats_a_file_of_its_name() {
    let dir = scratch("precedence");
    put(
        &dir.join("test"),
        "#!/usr/bin/env blue\nwrite_stdout(\"script\\n\")\n",
    );
    let o = blue().current_dir(&dir).arg("test").output().unwrap();
    assert!(
        !o.status.success(),
        "`blue test` with no FILE is a usage error"
    );
    assert!(!out(&o).contains("script"), "{}", out(&o));
    let o = blue().current_dir(&dir).arg("./test").output().unwrap();
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "script\n");
}

/// A file whose first line is not a blue shebang is not a script.
#[test]
fn a_file_without_a_blue_shebang_is_not_run() {
    let dir = scratch("not-a-script");
    put(&dir.join("notes"), "#!/bin/sh\nwrite_stdout(\"ran\\n\")\n");
    let o = blue().arg(dir.join("notes")).output().unwrap();
    assert!(!o.status.success());
    assert!(!out(&o).contains("ran"));
    assert!(err(&o).contains("subcommand"), "{}", err(&o));
}

/// The shebang is a line the formatter keeps: a canonical script checks clean,
/// and a messy one rewritten by its first run still opens with it.
#[test]
fn the_formatter_keeps_the_shebang() {
    let dir = scratch("fmt");
    let file = dir.join("s.b");
    put(
        &file,
        "#!/usr/bin/env blue\nx = 1\n\n\n\nwrite_stdout(\"#{x}\\n\")\n",
    );
    let o = blue().arg(&file).output().unwrap();
    assert!(o.status.success(), "{}", err(&o));
    let text = std::fs::read_to_string(&file).unwrap();
    assert!(text.starts_with("#!/usr/bin/env blue\n"), "{text}");
    let o = blue().args(["fmt", "--check"]).arg(&file).output().unwrap();
    assert!(o.status.success(), "{}", err(&o));
}

/// What `blue new` writes passes `blue test`, `blue fmt --check` and `blue
/// bluefile --confirm` as written, runs, and nothing existing is overwritten.
#[test]
fn blue_new_writes_what_passes_its_own_gates() {
    let dir = scratch("new");
    let ok = |o: Output| {
        assert!(o.status.success(), "{}{}", out(&o), err(&o));
        out(&o)
    };
    ok(blue()
        .current_dir(&dir)
        .args(["new", "kumo"])
        .output()
        .unwrap());
    ok(blue()
        .current_dir(&dir)
        .args(["new", "--bidama", "hoshi"])
        .output()
        .unwrap());
    ok(blue()
        .current_dir(&dir)
        .args(["new", "--script", "hi.b"])
        .output()
        .unwrap());

    for test in ["kumo/bidamas/kumo/kumo.b", "hoshi/hoshi.b"] {
        let o = ok(blue()
            .current_dir(&dir)
            .args(["test", test])
            .output()
            .unwrap());
        assert!(o.contains("passed, 0 failed"), "{test}: {o}");
    }
    ok(blue()
        .current_dir(&dir)
        .args(["fmt", "--check", "kumo/main.b", "kumo/Bluefile"])
        .args([
            "kumo/bidamas/kumo/kumo.b",
            "hoshi/hoshi.b",
            "hoshi/Bluefile",
            "hi.b",
        ])
        .output()
        .unwrap());
    ok(blue()
        .current_dir(&dir)
        .args(["bluefile", "--confirm", "kumo/Bluefile"])
        .args(["kumo/bidamas/kumo/Bluefile", "hoshi/Bluefile"])
        .output()
        .unwrap());
    assert!(dir.join("kumo/flake.nix").is_file());

    let o = ok(blue()
        .current_dir(&dir)
        .args(["kumo/main.b", "blue"])
        .output()
        .unwrap());
    assert_eq!(o, "hello, blue\n");
    let o = ok(blue()
        .current_dir(&dir)
        .args(["hi.b", "x"])
        .output()
        .unwrap());
    assert_eq!(o, "hello, x (1 argument(s))\n");

    for refused in [
        &["new", "kumo"][..],
        &["new", "my-tool"],
        &["new", "--bidama", "retsu"],
    ] {
        let o = blue().current_dir(&dir).args(refused).output().unwrap();
        assert!(!o.status.success(), "{refused:?} was accepted");
    }
}

/// `blue watch test FILE` runs once, then again after a save, reporting the
/// new verdict; it is stopped by being killed, as Ctrl-C stops it.
#[test]
fn blue_watch_reruns_on_save() {
    let dir = scratch("watch");
    let file = dir.join("w.b");
    let passing = "def f()\n  1\nend\n\ntest \"f is one\"\n  assert f() == 1\nend\n";
    put(&file, passing);
    let mut child = blue()
        .args(["watch", "test"])
        .arg(&file)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn blue watch");
    let (tx, rx) = mpsc::channel();
    let stdout = child.stdout.take().unwrap();
    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if tx.send(line).is_err() {
                break;
            }
        }
    });
    let wait_for = |want: &str| -> Vec<String> {
        let mut seen = Vec::new();
        while let Ok(line) = rx.recv_timeout(Duration::from_secs(20)) {
            let done = line.contains(want);
            seen.push(line);
            if done {
                return seen;
            }
        }
        panic!("no line containing {want:?}; saw {seen:?}");
    };
    let first = wait_for("── watching");
    assert!(
        first
            .iter()
            .any(|l| l == "── ok" || l.starts_with("── ok in")),
        "{first:?}"
    );
    std::thread::sleep(Duration::from_millis(1100));
    put(&file, &passing.replace("  1\n", "  2\n"));
    let second = wait_for("── watching");
    let _ = child.kill();
    let _ = child.wait();
    assert!(
        second.iter().any(|l| l.starts_with("── failed")),
        "the save did not rerun the tests: {second:?}"
    );
}

#[cfg(unix)]
fn executable(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}
