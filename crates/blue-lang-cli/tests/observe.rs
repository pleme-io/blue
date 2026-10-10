//! Watching a program run, through the binary: the call stack a runtime error
//! prints, `blue test` over a tree with `--filter` and `--coverage`,
//! `blue profile` and `blue trace`. All of them read one mechanism, the
//! evaluator's call hook (`blue_lang_runtime::observe`).
//!
//! Red runs, recorded 2026-10-10, each mutation reverted after:
//!
//! - `Fault`'s `Display` without its stack: the two stack tests and
//!   `a_test_error_names_its_line_and_its_stack` fail (no `at …` lines);
//! - `Fault::json` without `stack`: `run_format_json_carries_the_stack` fails;
//! - `Recorder::enter` not counting: coverage and profile fail (every count 0,
//!   every definition uncovered);
//! - the trace sink never called: `trace_prints_each_call_and_its_value` fails;
//! - `run_checked` ignoring `filter`: `filter_runs_only_matching_tests` fails
//!   (`3 test(s)` where 1 was asked for);
//! - `blue test` treating a directory as one file:
//!   `a_directory_runs_every_file_with_tests` fails on the read error.

use std::path::PathBuf;
use std::process::{Command, Output};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER");
    c
}

/// A scratch directory per test, so parallel tests cannot collide.
fn dir(name: &str) -> PathBuf {
    let p = std::env::temp_dir().join(format!("blue-observe-test-{name}"));
    let _ = std::fs::remove_dir_all(&p);
    std::fs::create_dir_all(&p).expect("scratch dir");
    p
}

fn write(dir: &std::path::Path, rel: &str, src: &str) -> PathBuf {
    let p = dir.join(rel);
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent).expect("fixture dir");
    }
    std::fs::write(&p, src).expect("write fixture");
    p
}

fn run(args: &[&str]) -> Output {
    blue().args(args).output().expect("spawn blue")
}

fn out(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).to_string()
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).to_string()
}

const THREE_DEEP: &str = "def inner(n)\n  n / 0\nend\n\ndef middle(n)\n  inner(n) + 1\nend\n\n\
                          def outer()\n  middle(2) * 3\nend\n\nouter()\n";

/// **A runtime error prints the blue call stack**, innermost first, each
/// frame its definition and the line it was running.
#[test]
fn a_runtime_error_prints_the_blue_call_stack() {
    let d = dir("stack");
    let f = write(&d, "deep.b", THREE_DEEP);
    let o = run(&["run", f.to_str().unwrap()]);
    assert!(!o.status.success());
    let e = err(&o);
    let file = f.display().to_string();
    let expected = format!(
        "blue: runtime error: {file}:2:3: division by zero\n  \
         at inner ({file}:2:3)\n  \
         at middle ({file}:6:3)\n  \
         at outer ({file}:10:3)\n  \
         at <top level> ({file}:13:1)\n"
    );
    assert_eq!(e, expected);
}

#[test]
fn run_format_json_carries_the_stack() {
    let d = dir("json");
    let f = write(&d, "deep.b", THREE_DEEP);
    let o = run(&["run", "--format", "json", f.to_str().unwrap()]);
    assert!(!o.status.success());
    let v: serde_json::Value = serde_json::from_str(out(&o).trim()).expect("one JSON object");
    assert_eq!(v["stage"], "eval");
    assert_eq!(v["line"], 2);
    let names: Vec<&str> = v["stack"]
        .as_array()
        .expect("a stack")
        .iter()
        .map(|f| f["function"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["inner", "middle", "outer", "<top level>"]);
    assert_eq!(v["stack"][1]["line"], 6);
    assert_eq!(v["stack_depth"], 3);
}

/// `try` still catches: the stack is reported only for an error nobody
/// caught.
#[test]
fn try_still_catches_an_error_with_a_stack() {
    let d = dir("try");
    let f = write(
        &d,
        "caught.b",
        "def inner()\n  1 / 0\nend\n\ndef safe()\n  try(inner(), catch(e(), 7))\nend\n\nsafe() + 1\n",
    );
    let o = run(&["run", f.to_str().unwrap()]);
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "8\n");
}

/// A recursion past what the trace keeps folds its repeats and says how
/// much was not recorded.
#[test]
fn a_deep_stack_is_bounded_and_folded() {
    let d = dir("deep");
    let f = write(
        &d,
        "rec.b",
        "def down(n)\n  if n == 0\n    1 / 0\n  else\n    1 + down(n - 1)\n  end\nend\n\ndown(300)\n",
    );
    let o = run(&["run", f.to_str().unwrap()]);
    assert!(!o.status.success());
    let e = err(&o);
    let file = f.display().to_string();
    assert!(e.contains(&format!("  at down ({file}:3:5)\n")), "{e}");
    assert!(e.contains(&format!("  at down ({file}:5:9)\n")), "{e}");
    assert!(e.contains("  … repeated 254 more time(s)\n"), "{e}");
    assert!(e.contains("  … 45 outer frame(s) not recorded"), "{e}");
    assert!(e.lines().count() < 10, "{e}");
}

const TESTED: &str =
    "def fib(n)\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\n  end\nend\n\n\
                      def unused(x)\n  x\nend\n\ndef boom()\n  1 / 0\nend\n\n\
                      test \"fib small\"\n  assert fib(5) == 5\nend\n\n\
                      test \"fib zero\"\n  assert fib(0) == 0\nend\n\n\
                      test \"boom\"\n  assert boom() == 1\nend\n";

/// **An error inside a test names its line and its stack**, the same shape
/// `blue run` prints.
#[test]
fn a_test_error_names_its_line_and_its_stack() {
    let d = dir("testerr");
    let f = write(&d, "a.b", TESTED);
    let o = run(&["test", f.to_str().unwrap()]);
    assert!(!o.status.success());
    let file = f.display().to_string();
    assert!(
        err(&o).contains(&format!(
            "ERROR boom\n  {file}:14:3: division by zero\n  at boom ({file}:14:3)\n  \
             at <top level> ({file}:26:10)"
        )),
        "{}",
        err(&o)
    );
    assert_eq!(out(&o), "3 test(s): 2 passed, 1 failed\n");
}

#[test]
fn filter_runs_only_matching_tests() {
    let d = dir("filter");
    let f = write(&d, "a.b", TESTED);
    let o = run(&["test", f.to_str().unwrap(), "--filter", "zero"]);
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "1 test(s): 1 passed, 0 failed\n");
    let none = run(&["test", f.to_str().unwrap(), "--filter", "nothing-matches"]);
    assert!(!none.status.success());
    assert!(
        err(&none).contains("no test name contains"),
        "{}",
        err(&none)
    );
}

/// **A directory runs every `.b` file holding a test**, and a file with no
/// test block is not counted.
#[test]
fn a_directory_runs_every_file_with_tests() {
    let d = dir("tree");
    write(&d, "a.b", TESTED);
    write(
        &d,
        "sub/b.b",
        "def sq(x)\n  x * x\nend\n\ntest \"squares\"\n  assert sq(3) == 9\nend\n",
    );
    write(&d, "sub/plain.b", "def nothing()\n  1\nend\n");
    let o = run(&["test", d.to_str().unwrap()]);
    assert!(!o.status.success(), "one test fails");
    let stdout = out(&o);
    assert!(
        stdout.ends_with("2 file(s), 4 test(s): 3 passed, 1 failed\n"),
        "{stdout}"
    );
    let ok = run(&["test", d.to_str().unwrap(), "--filter", "s"]);
    assert!(ok.status.success(), "{}", err(&ok));
    assert!(
        out(&ok).ends_with("2 file(s), 2 test(s): 2 passed, 0 failed\n"),
        "{}",
        out(&ok)
    );
}

#[test]
fn coverage_counts_calls_and_lists_the_uncovered() {
    let d = dir("cov");
    let f = write(&d, "a.b", TESTED);
    let o = run(&["test", f.to_str().unwrap(), "--coverage", "--filter", "fib"]);
    assert!(o.status.success(), "{}", err(&o));
    let stdout = out(&o);
    // fib(5) is 15 activations, fib(0) one.
    assert!(stdout.contains("        16  fib "), "{stdout}");
    assert!(
        stdout.contains("  1/3 definitions covered (33.3%)"),
        "{stdout}"
    );
    let j = run(&[
        "test",
        f.to_str().unwrap(),
        "--coverage",
        "--json",
        "--filter",
        "fib",
    ]);
    let first = out(&j).lines().next().unwrap_or_default().to_string();
    let v: serde_json::Value = serde_json::from_str(&first).expect("one JSON object per file");
    assert_eq!(v["covered"], 1);
    assert_eq!(v["total"], 3);
    assert_eq!(v["uncovered"], serde_json::json!(["unused", "boom"]));
}

const PROGRAM: &str = "def fib(n)\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\n  end\nend\n\n\
                       def count(n, acc)\n  if n == 0\n    acc\n  else\n    count(n - 1, acc + n)\n  end\nend\n\n\
                       count(3, 0) + fib(10)\n";

#[test]
fn profile_counts_every_call() {
    let d = dir("profile");
    let f = write(&d, "p.b", PROGRAM);
    let o = run(&["profile", "--json", f.to_str().unwrap()]);
    assert!(o.status.success(), "{}", err(&o));
    let v: serde_json::Value = serde_json::from_str(out(&o).trim()).expect("JSON");
    let calls = |name: &str| {
        v["functions"]
            .as_array()
            .unwrap()
            .iter()
            .find(|f| f["name"] == name)
            .map(|f| f["calls"].as_u64().unwrap())
    };
    // fib(10) is 177 activations; count(3, 0) is four, tail calls included.
    assert_eq!(calls("fib"), Some(177));
    assert_eq!(calls("count"), Some(4));
    let text = run(&["profile", f.to_str().unwrap()]);
    assert!(out(&text).contains("fib"), "{}", out(&text));
}

#[test]
fn trace_prints_each_call_and_its_value() {
    let d = dir("trace");
    let f = write(&d, "p.b", PROGRAM);
    let o = run(&["trace", "count", f.to_str().unwrap()]);
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(
        err(&o),
        "-> count(3, 0)\n<- count(3, 0) tail call\n-> count(2, 3)\n<- count(2, 3) tail call\n\
         -> count(1, 5)\n<- count(1, 5) tail call\n-> count(0, 6)\n<- count(0, 6) = 6\n\
         count: 4 call(s)\n"
    );
    let nested = run(&["trace", "fib", f.to_str().unwrap(), "--limit", "3"]);
    assert_eq!(
        err(&nested),
        "-> fib(10)\n  -> fib(9)\n    -> fib(8)\n… trace stopped after 3 line(s) (--limit)\nfib: 177 call(s)\n"
    );
    let missing = run(&["trace", "nope", f.to_str().unwrap()]);
    assert!(!missing.status.success());
    assert!(err(&missing).contains("no definition named `nope`"));
}
