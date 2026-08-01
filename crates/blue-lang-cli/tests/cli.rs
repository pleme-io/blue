//! The CLI's contract, exercised as a subprocess.
//!
//! These run the real binary against real files, because that is the only way
//! to test what a user actually touches: argument parsing, file reading, what
//! lands on stdout versus stderr, and **the exit code**. A library test cannot
//! observe any of those.
//!
//! Exit codes matter most. `blue fmt --check` in CI and `blue check` in a
//! pre-commit hook are both *only* their exit code as far as the caller is
//! concerned — a subcommand that prints an error and exits 0 is a gate that
//! silently passes everything.

use std::path::PathBuf;
use std::process::{Command, Output};

/// The binary under test. Cargo sets `CARGO_BIN_EXE_<name>` for integration
/// tests, which is how this finds the just-built `blue` rather than whatever
/// is on `PATH`.
fn blue() -> Command {
    Command::new(env!("CARGO_BIN_EXE_blue"))
}

/// A scratch `.b` file, named per test so parallel tests cannot collide.
fn write(name: &str, src: &str) -> PathBuf {
    let mut p = std::env::temp_dir();
    p.push(format!("blue-cli-test-{name}.b"));
    std::fs::write(&p, src).expect("write fixture");
    p
}

fn run(args: &[&str]) -> Output {
    blue().args(args).output().expect("spawn blue")
}

fn stdout(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).to_string()
}

fn stderr(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).to_string()
}

const PROGRAM: &str = "def fact(n: Int) -> Int\n  if n < 2\n    1\n  else\n    n * fact(n - 1)\n  end\nend\nfact(6)";

// ---------------------------------------------------------------------------
// run
// ---------------------------------------------------------------------------

#[test]
fn run_executes_a_program_and_prints_its_value() {
    let f = write("run", PROGRAM);
    let o = run(&["run", f.to_str().unwrap()]);
    assert!(o.status.success(), "stderr: {}", stderr(&o));
    assert_eq!(stdout(&o).trim(), "720");
}

/// **A type error must exit non-zero.** A `blue run` that printed the error
/// and exited 0 would pass every CI gate built on it.
#[test]
fn run_rejects_a_type_error_with_a_failing_exit_code() {
    let f = write("run-bad-type", "def bad(a: Int) -> Str\n  a\nend\nbad(1)");
    let o = run(&["run", f.to_str().unwrap()]);
    assert!(!o.status.success(), "a type error must fail the process");
    assert!(
        stderr(&o).contains("Str") && stderr(&o).contains("Int"),
        "the error must name both types: {}",
        stderr(&o)
    );
    assert!(
        stdout(&o).trim().is_empty(),
        "a rejected program must not print a value: {:?}",
        stdout(&o)
    );
}

/// Anti-vacuity for the test above: the same program without annotations
/// runs, so the rejection is the annotation's doing.
#[test]
fn run_accepts_the_same_program_without_annotations() {
    let f = write("run-untyped", "def ok(a)\n  a\nend\nok(1)");
    let o = run(&["run", f.to_str().unwrap()]);
    assert!(o.status.success(), "stderr: {}", stderr(&o));
    assert_eq!(stdout(&o).trim(), "1");
}

#[test]
fn a_missing_file_fails_with_the_path_named() {
    let o = run(&["run", "/nonexistent/definitely-not-here.b"]);
    assert!(!o.status.success());
    assert!(
        stderr(&o).contains("definitely-not-here.b"),
        "the error must name the path: {}",
        stderr(&o)
    );
}

// ---------------------------------------------------------------------------
// fmt
// ---------------------------------------------------------------------------

/// Formatting is idempotent through the CLI, and the second pass is what
/// `--check` relies on being a fixed point.
#[test]
fn fmt_output_is_already_formatted() {
    let f = write("fmt-idem", PROGRAM);
    let once = run(&["fmt", f.to_str().unwrap()]);
    assert!(once.status.success(), "stderr: {}", stderr(&once));

    let g = write("fmt-idem-2", &stdout(&once));
    let check = run(&["fmt", "--check", g.to_str().unwrap()]);
    assert!(
        check.status.success(),
        "formatted output must satisfy --check; got: {}",
        stderr(&check)
    );
}

/// **`--check` must fail on drift**, or it is not a gate.
#[test]
fn fmt_check_fails_on_unformatted_input() {
    let f = write("fmt-drift", "1   +    2");
    let o = run(&["fmt", "--check", f.to_str().unwrap()]);
    assert!(!o.status.success(), "unformatted input must fail --check");
    assert!(
        stderr(&o).contains("not formatted"),
        "and say why: {}",
        stderr(&o)
    );
}

/// `--check` must not modify the file. A gate with a side effect is not a
/// gate.
#[test]
fn fmt_check_does_not_rewrite_the_file() {
    let original = "1   +    2";
    let f = write("fmt-check-pure", original);
    let _ = run(&["fmt", "--check", f.to_str().unwrap()]);
    assert_eq!(
        std::fs::read_to_string(&f).expect("read back"),
        original,
        "--check must leave the file alone"
    );
}

#[test]
fn fmt_write_rewrites_in_place() {
    let f = write("fmt-write", "1   +    2");
    let o = run(&["fmt", "--write", f.to_str().unwrap()]);
    assert!(o.status.success(), "stderr: {}", stderr(&o));
    assert_eq!(
        std::fs::read_to_string(&f).expect("read back").trim(),
        "1 + 2"
    );
}

/// **An ordinary call must survive the CLI as a call.** This is the
/// regression that all three formatting laws missed: `fact(n - 1)` rendered
/// `(n - 1).fact`, which round-tripped perfectly and read backwards.
#[test]
fn fmt_does_not_turn_a_call_into_a_method_send() {
    let f = write("fmt-call", PROGRAM);
    let out = stdout(&run(&["fmt", f.to_str().unwrap()]));
    assert!(
        out.contains("fact(n - 1)"),
        "a recursive call must render as a call: {out}"
    );
    assert!(
        !out.contains(").fact"),
        "and must not render as a method send: {out}"
    );
}

// ---------------------------------------------------------------------------
// ast / erase — the sliding scale, made visible
// ---------------------------------------------------------------------------

/// **The difference between `ast` and `erase` IS the sliding scale.** `ast`
/// keeps the annotation; `erase` shows what actually runs. Two subcommands
/// exist so a reader can see that annotations are *consumed*, not carried.
#[test]
fn ast_keeps_annotations_and_erase_drops_them() {
    let f = write("ast-erase", PROGRAM);
    let ast = stdout(&run(&["ast", f.to_str().unwrap()]));
    let erased = stdout(&run(&["erase", f.to_str().unwrap()]));

    assert!(
        ast.contains("define-typed") && ast.contains("Int"),
        "ast must keep the annotation: {ast}"
    );
    assert!(
        !erased.contains("define-typed") && !erased.contains("Int"),
        "erase must drop every trace of it: {erased}"
    );
    assert!(
        erased.contains("(define (fact n)"),
        "and leave a plain define: {erased}"
    );
}

/// Erasing an untyped program is the identity, so `erase` is not rewriting
/// code that had no annotations to begin with.
#[test]
fn erase_is_the_identity_on_untyped_source() {
    let f = write("erase-untyped", "def f(x)\n  x + 1\nend");
    assert_eq!(
        stdout(&run(&["erase", f.to_str().unwrap()])).trim(),
        stdout(&run(&["ast", f.to_str().unwrap()])).trim()
    );
}

// ---------------------------------------------------------------------------
// check
// ---------------------------------------------------------------------------

/// **"No annotations, no analysis" is reported, not claimed.** The whole
/// sliding-scale promise is that an untyped program pays nothing, and the CLI
/// prints the number so it can be checked rather than believed.
#[test]
fn check_reports_zero_analysis_for_an_untyped_program() {
    let f = write("check-untyped", "def f(x)\n  x + 1\nend\nf(1)");
    let o = run(&["check", f.to_str().unwrap()]);
    assert!(o.status.success(), "stderr: {}", stderr(&o));
    let out = stdout(&o);
    assert!(
        out.contains("typed declarations: 0"),
        "expected no typed decls: {out}"
    );
    assert!(
        out.contains("nodes analysed:     0"),
        "an untyped program must cost zero analysis: {out}"
    );
}

/// And an annotated program reports non-zero, so the number above is a
/// measurement and not a constant.
#[test]
fn check_reports_analysis_for_an_annotated_program() {
    let f = write("check-typed", PROGRAM);
    let out = stdout(&run(&["check", f.to_str().unwrap()]));
    assert!(
        out.contains("typed declarations: 1"),
        "expected one typed decl: {out}"
    );
    assert!(
        !out.contains("nodes analysed:     0"),
        "an annotation must buy real analysis: {out}"
    );
}

#[test]
fn check_exits_non_zero_on_a_type_error() {
    let f = write("check-bad", "def bad(a: Int) -> Str\n  a\nend");
    let o = run(&["check", f.to_str().unwrap()]);
    assert!(!o.status.success(), "check must fail on a type error");
}

// ---------------------------------------------------------------------------
// the surface itself
// ---------------------------------------------------------------------------

/// Every subcommand is reachable and documented. A subcommand that exists in
/// code but not in `--help` is one nobody can find.
#[test]
fn help_lists_every_subcommand() {
    let o = run(&["--help"]);
    assert!(o.status.success());
    let help = stdout(&o);
    for cmd in ["run", "fmt", "ast", "erase", "check", "test", "deps", "posture", "lsp", "banner", "shift"] {
        assert!(help.contains(cmd), "--help must list `{cmd}`: {help}");
    }
}

#[test]
fn no_arguments_is_an_error_not_a_silent_success() {
    let o = blue().output().expect("spawn");
    assert!(!o.status.success(), "bare `blue` must not exit 0");
}

// ---------------------------------------------------------------------------
// test
// ---------------------------------------------------------------------------

const SUITE: &str = "def add(a, b)\n  a + b\nend\n\ntest \"adds\"\n  assert add(1, 2) == 3\nend";

#[test]
fn test_runs_a_passing_suite_and_exits_zero() {
    let f = write("test-pass", SUITE);
    let o = run(&["test", f.to_str().unwrap()]);
    assert!(o.status.success(), "stderr: {}", stderr(&o));
    assert!(
        stdout(&o).contains("1 passed, 0 failed"),
        "expected a tally: {}",
        stdout(&o)
    );
}

/// **A failing suite must exit non-zero.** `blue test` in CI is only its exit
/// code; a runner that prints failures and exits 0 is a gate that passes
/// everything.
#[test]
fn test_exits_non_zero_when_a_test_fails() {
    let f = write(
        "test-fail",
        "test \"wrong\"\n  assert 1 + 1 == 3\nend",
    );
    let o = run(&["test", f.to_str().unwrap()]);
    assert!(!o.status.success(), "a failing suite must fail the process");
    assert!(
        stdout(&o).contains("0 passed, 1 failed"),
        "tally: {}",
        stdout(&o)
    );
}

/// **The failure names the expression, in blue syntax.** The whole point of
/// `assert` being a surface form rather than a library call.
#[test]
fn test_failure_reports_the_expression_as_written() {
    let f = write(
        "test-msg",
        "def add(a, b)\n  a + b\nend\n\ntest \"wrong\"\n  assert add(1, 2) == 4\nend",
    );
    let o = run(&["test", f.to_str().unwrap()]);
    assert!(
        stderr(&o).contains("assert add(1, 2) == 4"),
        "the message must be the expression in canonical blue source: {}",
        stderr(&o)
    );
}

/// A file with no tests is not a pass by default — the tally must say zero, so
/// a mis-typed filename or an un-run suite cannot read as success.
#[test]
fn test_on_a_file_with_no_tests_reports_zero() {
    let f = write("test-none", "def f(x)\n  x\nend");
    let o = run(&["test", f.to_str().unwrap()]);
    assert!(
        stdout(&o).contains("0 test(s)"),
        "an empty run must be visibly empty: {}",
        stdout(&o)
    );
}

// ---------------------------------------------------------------------------
// deps / posture — the Bluefile
// ---------------------------------------------------------------------------

/// A Bluefile whose version is COMPUTED. A data-format manifest could not
/// express this, and it is the reason the Bluefile is a blue program.
const BLUEFILE: &str = "def app_version()\n  \"0.2.0\"\nend\n\npackage(\"myapp\", app_version())\nneeds(\"gaming\", \"^1.2\")\nposture(:preceding)";

#[test]
fn deps_reports_the_manifest_including_a_computed_version() {
    let f = write("deps", BLUEFILE);
    let o = run(&["deps", f.to_str().unwrap()]);
    assert!(o.status.success(), "stderr: {}", stderr(&o));
    let out = stdout(&o);
    assert!(
        out.contains("myapp 0.2.0"),
        "the version came from a function call: {out}"
    );
    assert!(out.contains("needs gaming ^1.2.0"), "{out}");
}

/// **`deps` must not claim to have resolved anything.** There is no registry
/// client, and printing an empty resolution would read as success.
#[test]
fn deps_says_it_cannot_resolve_rather_than_printing_a_hollow_resolution() {
    let f = write("deps-honest", BLUEFILE);
    let out = stdout(&run(&["deps", f.to_str().unwrap()]));
    assert!(
        out.contains("requires a registry"),
        "it must say resolution is not configured: {out}"
    );
}

#[test]
fn posture_reports_the_declared_floor() {
    let f = write("posture", BLUEFILE);
    let o = run(&["posture", f.to_str().unwrap()]);
    assert!(o.status.success(), "stderr: {}", stderr(&o));
    let out = stdout(&o);
    assert!(out.contains("Preceding"), "the declared `when`: {out}");
    assert!(out.contains("unrestricted"), "undeclared reach is the top: {out}");
}

/// A Bluefile with no `package` call fails, rather than defaulting to an
/// anonymous package at 0.0.0.
#[test]
fn a_bluefile_without_a_package_call_fails() {
    let f = write("bluefile-nopkg", "needs(\"a\", \"*\")");
    let o = run(&["deps", f.to_str().unwrap()]);
    assert!(!o.status.success(), "must fail");
    assert!(
        stderr(&o).contains("package"),
        "and say what is missing: {}",
        stderr(&o)
    );
}

/// **`fmt --write` must not delete comments.**
///
/// It used to delete every one: comments are lexed as trivia and were never
/// attached to a node, so formatting dropped them silently. A comment is the one
/// part of a program a machine cannot reconstruct, so that was data loss on a
/// routine operation. The formatter now re-interleaves them by position.
#[test]
fn fmt_write_preserves_comments() {
    let f = write("fmt-comments", "# keep me\n1   +   2\n");
    let o = run(&["fmt", "--write", f.to_str().unwrap()]);
    assert!(o.status.success(), "stderr: {}", stderr(&o));
    let after = std::fs::read_to_string(&f).expect("read back");
    assert!(after.contains("# keep me"), "the comment must survive: {after:?}");
    assert!(after.contains("1 + 2"), "and the code must be formatted: {after:?}");
}

/// And `--check` settles on a commented file. Comparing against the
/// comment-stripped rendering made every commented file report "not formatted"
/// forever — a gate that can never be satisfied.
#[test]
fn fmt_check_settles_on_a_commented_file() {
    let f = write("fmt-check-comments", "# note\n1 + 2\n");
    let o = run(&["fmt", "--check", f.to_str().unwrap()]);
    assert!(
        o.status.success(),
        "an already-canonical commented file must pass --check: {}",
        stderr(&o)
    );
}

/// A comment *inside* a form is still refused, because those lines are re-laid
/// out and there is nowhere to put it back. Refusing names the line.
#[test]
fn fmt_write_refuses_a_comment_it_cannot_place() {
    let original = "def f(x)\n  # inside\n  x\nend\n";
    let f = write("fmt-inner-comment", original);
    let o = run(&["fmt", "--write", f.to_str().unwrap()]);
    assert!(!o.status.success(), "it must refuse");
    assert!(
        stderr(&o).contains("comment"),
        "and say why: {}",
        stderr(&o)
    );
    assert_eq!(
        std::fs::read_to_string(&f).expect("read back"),
        original,
        "the file must be untouched"
    );
}

/// And `--write` still works on a file with no comments, so the refusal is
/// narrow rather than a blanket failure.
#[test]
fn fmt_write_still_works_without_comments() {
    let f = write("fmt-nocomments", "1   +   2");
    let o = run(&["fmt", "--write", f.to_str().unwrap()]);
    assert!(o.status.success(), "stderr: {}", stderr(&o));
    assert_eq!(
        std::fs::read_to_string(&f).expect("read back").trim(),
        "1 + 2"
    );
}

// ---------------------------------------------------------------------------
// build inputs — capability-restricted, content-addressed macro I/O
// ---------------------------------------------------------------------------

fn write_bytes(name: &str, bytes: &[u8]) -> PathBuf {
    let mut p = std::env::temp_dir();
    p.push(format!("blue-cli-input-{name}"));
    std::fs::write(&p, bytes).expect("write input");
    p
}

const SCHEMA: &[u8] = b"id,name,email\n";
/// BLAKE3 of SCHEMA. Written out rather than computed so the test pins the
/// *value*: if hashing ever changed, a computed expectation would follow it
/// silently.
const SCHEMA_HASH: &str = "b3:1e8c349d3151d7c4c19836c6ba0e0d82270a2c174d98af445e102055040ac92c";

fn schema_program() -> String {
    let mut s = String::from("definput(\"schema\", \"");
    s.push_str(SCHEMA_HASH);
    s.push_str("\")\n");
    s.push_str(
        "defmacro column_count()\n  quote\n    length(split(trim(input(\"schema\")), \",\"))\n  end\nend\n\
         column_count()",
    );
    s
}

/// **A macro generates code from a schema, read at expansion time.** The
/// Tier-2 conversion `theory/BLUE.md` §VI OPEN #6 named as gating blue's
/// "stronger than Ruby's metaprogramming" claim.
#[test]
fn a_macro_reads_a_content_addressed_input() {
    let f = write("input-ok", &schema_program());
    let schema = write_bytes("schema-ok", SCHEMA);
    let o = run(&[
        "run",
        f.to_str().unwrap(),
        "--input",
        &format!("schema={}", schema.display()),
    ]);
    assert!(o.status.success(), "stderr: {}", stderr(&o));
    assert_eq!(stdout(&o).trim(), "3", "three columns in the schema");
}

/// **Bytes that do not match the declared hash are refused**, and the error
/// names both so the author can tell "I edited the file" from "I pasted the
/// wrong hash".
#[test]
fn input_bytes_must_match_the_declared_hash() {
    let f = write("input-tampered", &schema_program());
    let schema = write_bytes("schema-tampered", b"id,name,email,extra\n");
    let o = run(&[
        "run",
        f.to_str().unwrap(),
        "--input",
        &format!("schema={}", schema.display()),
    ]);
    assert!(!o.status.success(), "a hash mismatch must fail the run");
    let err = stderr(&o);
    assert!(err.contains(SCHEMA_HASH), "must name the expected: {err}");
    assert!(err.contains("hash to"), "and the actual: {err}");
}

/// **A declared input with no `--input` names the FLAG**, not the macro. The
/// first version short-circuited when the flag list was empty, so this reported
/// the macro-level "no input named …" from deep inside expansion — pointing at
/// the wrong thing entirely.
#[test]
fn a_declared_input_with_no_flag_names_the_missing_flag() {
    let f = write("input-missing", &schema_program());
    let o = run(&["run", f.to_str().unwrap()]);
    assert!(!o.status.success());
    let err = stderr(&o);
    assert!(err.contains("--input schema="), "must name the flag: {err}");
}

/// Supplying a name the program never declared is a DIFFERENT mistake, and
/// reads differently.
#[test]
fn an_undeclared_input_name_is_its_own_error() {
    let f = write("input-undeclared", &schema_program());
    let schema = write_bytes("schema-undeclared", SCHEMA);
    let o = run(&[
        "run",
        f.to_str().unwrap(),
        "--input",
        &format!("nosuch={}", schema.display()),
    ]);
    assert!(!o.status.success());
    assert!(
        stderr(&o).contains("never declares it"),
        "got: {}",
        stderr(&o)
    );
}

/// A program with no declarations is unaffected — the check is narrow.
#[test]
fn a_program_without_declarations_still_runs() {
    let f = write("input-none", PROGRAM);
    let o = run(&["run", f.to_str().unwrap()]);
    assert!(o.status.success(), "stderr: {}", stderr(&o));
    assert_eq!(stdout(&o).trim(), "720");
}
