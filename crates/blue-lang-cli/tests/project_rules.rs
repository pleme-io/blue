//! **A project's own check rules, through `blue check`.** The fixtures in
//! `tests/fixtures/project-rules/` are three small projects, each a Bluefile
//! naming rules written in blue: `ok/` (a finding with a fix, a warning, and
//! a waived finding), `runaway/` (a rule that never returns, beside one that
//! does) and `reads/` (a rule naming `read_file`). Each test copies its
//! project into a fresh directory with a `.git` marker, so discovery stops
//! there and `--fix` never touches the committed fixture.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER");
    c
}

fn project(name: &str, test: &str) -> PathBuf {
    let from = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/project-rules")
        .join(name);
    let to = std::env::temp_dir().join(format!("blue-project-rules-{}-{test}", std::process::id()));
    let _ = std::fs::remove_dir_all(&to);
    std::fs::create_dir_all(to.join(".git")).expect("mkdir");
    for entry in std::fs::read_dir(&from).expect("fixture") {
        let p = entry.expect("entry").path();
        std::fs::copy(&p, to.join(p.file_name().expect("name"))).expect("copy");
    }
    to
}

fn check(file: &Path, extra: &[&str]) -> Output {
    blue()
        .arg("check")
        .args(extra)
        .arg(file)
        .output()
        .expect("spawn")
}

fn text(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned() + &String::from_utf8_lossy(&o.stderr)
}

/// A rule's finding carries the Bluefile row's code, at the node the rule's
/// path names, and fails the check.
///
/// Red run (2026-10-10): `discover` returning no rules: exit 0 and no
/// `FX0001` in the output.
#[test]
fn a_project_rule_reports_a_finding_at_its_node() {
    let dir = project("ok", "finding");
    let o = check(&dir.join("finding.b"), &[]);
    let out = text(&o);
    assert_eq!(o.status.code(), Some(1), "{out}");
    assert!(
        out.contains("finding.b:10:3: error[FX0001]: loud(x) is quiet(x)"),
        "{out}"
    );
    assert!(out.contains("project rules:      2"), "{out}");
}

/// In JSON the finding has the registry's shape: the project code, the
/// definition as its slug, and a machine-applicable fix proved by reparsing.
#[test]
fn a_project_finding_is_a_json_diagnostic_with_its_fix() {
    let dir = project("ok", "json");
    let o = check(&dir.join("finding.b"), &["--format", "json"]);
    let line = String::from_utf8_lossy(&o.stdout)
        .lines()
        .find(|l| l.contains("FX0001"))
        .map(str::to_owned)
        .unwrap_or_else(|| panic!("no FX0001 line: {}", text(&o)));
    let v: serde_json::Value = serde_json::from_str(&line).expect("json");
    assert_eq!(v["code"], "FX0001");
    assert_eq!(v["slug"], "loud-call");
    assert_eq!(v["severity"], "error");
    assert_eq!(v["line"], 10);
    assert_eq!(v["fixes"][0]["applicability"], "machine-applicable");
    assert_eq!(v["fixes"][0]["edits"][0]["original"], "loud(x)");
    assert_eq!(v["fixes"][0]["edits"][0]["replacement"], "quiet(x)");
}

/// `# waive CODE: reason` above the definition moves the finding to the
/// waived list, and the check passes.
///
/// Red run (2026-10-10): `apply_waivers` call removed from the project
/// pass: exit 1, `waived: 0`.
#[test]
fn a_waiver_names_a_project_code_like_a_registry_one() {
    let dir = project("ok", "waiver");
    let o = check(&dir.join("waived.b"), &[]);
    let out = text(&o);
    assert_eq!(o.status.code(), Some(0), "{out}");
    assert!(out.contains("waived:             1"), "{out}");
    assert!(
        out.contains("waived: loud(x) is quiet(x) (this one must be loud)"),
        "{out}"
    );
}

/// `--fix` applies a project rule's proved fix, and the file then checks
/// clean.
///
/// Red run (2026-10-10): the project findings dropped from
/// `apply_machine_fixes`' chain: the file was left as written and the check
/// still failed.
#[test]
fn fix_applies_a_project_rules_fix() {
    let dir = project("ok", "fix");
    let file = dir.join("finding.b");
    let o = check(&file, &["--fix"]);
    let out = text(&o);
    assert_eq!(o.status.code(), Some(0), "{out}");
    let after = std::fs::read_to_string(&file).expect("read");
    assert!(after.contains("def shout(x)\n  quiet(x)\nend"), "{after}");
}

/// A rule that never returns is stopped by its budget and reported as a
/// failure of that rule, once; the other rule still reports.
#[test]
fn a_runaway_rule_is_a_rule_failure_not_a_hang() {
    let dir = project("runaway", "budget");
    let o = check(&dir.join("target.b"), &[]);
    let out = text(&o);
    assert_eq!(o.status.code(), Some(1), "{out}");
    let failures: Vec<&str> = out
        .lines()
        .filter(|l| l.contains("error[FX0003]"))
        .collect();
    assert_eq!(failures.len(), 1, "{out}");
    assert!(failures[0].contains("ran past its budget"), "{out}");
    assert!(failures[0].contains("in `spin`"), "{out}");
    assert_eq!(out.matches("error[FX0004]: seen").count(), 2, "{out}");
}

/// A rule that names `read_file` never runs: the frame refuses it, here
/// where the host layer is bound.
///
/// Red run (2026-10-10): `permits` returning true for every name: the rule
/// loaded, read the file and reported nothing, exit 0.
#[test]
fn a_rule_reaching_for_read_file_is_refused_by_the_frame() {
    let dir = project("reads", "frame");
    let o = check(&dir.join("target.b"), &["--format", "json"]);
    let out = text(&o);
    assert_eq!(o.status.code(), Some(1), "{out}");
    let line = String::from_utf8_lossy(&o.stdout)
        .lines()
        .find(|l| l.contains("FX0005"))
        .map(str::to_owned)
        .unwrap_or_else(|| panic!("no FX0005 line: {out}"));
    let v: serde_json::Value = serde_json::from_str(&line).expect("json");
    assert_eq!(v["slug"], "rule-failure");
    assert!(
        v["message"]
            .as_str()
            .is_some_and(|m| m.contains("outside the rule frame: read_file")),
        "{line}"
    );
}

/// A file with no project rules above it reports no project lines at all,
/// and its project waivers are left alone, as a bidama checked by itself in
/// the sandbox has none of its root's rules above it.
///
/// Red run (2026-10-10): the pass run with no rules: `error[B0007]: no
/// project rule has the code R0001`, exit 1 (as `bidama-okite` failed in
/// nix before the pass learned this).
#[test]
fn a_file_with_no_project_rules_is_checked_as_before() {
    let dir = std::env::temp_dir().join(format!("blue-project-rules-{}-none", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join(".git")).expect("mkdir");
    let file = dir.join("plain.b");
    std::fs::write(
        &file,
        "# waive R0001: the root's rule\ndef f()\n  1 == nil\nend\n",
    )
    .expect("write");
    let o = check(&file, &[]);
    let out = text(&o);
    assert_eq!(o.status.code(), Some(0), "{out}");
    assert!(!out.contains("project rules"), "{out}");
}

/// A rule the Bluefile names a `warning` reports and does not fail the check.
#[test]
fn a_warning_rule_reports_without_failing() {
    let dir = project("ok", "warning");
    let o = check(&dir.join("todo.b"), &[]);
    let out = text(&o);
    assert_eq!(o.status.code(), Some(0), "{out}");
    assert!(
        out.contains("todo.b:5:1: warning[FX0002]: a todo is left"),
        "{out}"
    );
    assert!(out.contains("help: finish it"), "{out}");
}
