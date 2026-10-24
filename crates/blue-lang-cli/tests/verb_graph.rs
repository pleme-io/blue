use std::collections::BTreeSet;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn blue(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env("BLUE_PATH", repo().join("bidamas"))
        .current_dir(repo())
        .arg("verbs")
        .args(args)
        .output()
        .expect("spawn")
}

fn duckdb(script: &str) -> String {
    let mut child = Command::new("duckdb")
        .args(["-noheader", "-list"])
        .current_dir(repo())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("duckdb is on PATH: the devShell carries it, and a missing second implementation fails this test rather than skipping it");
    child
        .stdin
        .take()
        .expect("stdin")
        .write_all(script.as_bytes())
        .expect("write");
    let out = child.wait_with_output().expect("wait");
    assert!(
        out.status.success(),
        "duckdb: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).into_owned()
}

fn lines(text: &str) -> BTreeSet<String> {
    text.lines()
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect()
}

fn fixture(name: &str) -> String {
    format!("bidamas/mokuroku/graph/fixtures/{name}")
}

fn sql_findings(dir: &str) -> BTreeSet<String> {
    lines(&duckdb(&format!(
        "set variable vdir='{dir}';\n.read docs/verbs/queries/gate-h0.sql\n"
    )))
}

fn blue_findings(dir: &str) -> BTreeSet<String> {
    let o = blue(&["findings", "--tsv", dir]);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    lines(&String::from_utf8_lossy(&o.stdout))
}

#[test]
fn every_gate_names_its_bad_row_and_the_sql_agrees() {
    let expected: BTreeSet<String> = [
        "g1-meaning\tfairu::read fairu::slurp",
        "g2-vocab\tfairu::fetch",
        "g4-cycle\ta::x",
        "g4-cycle\ta::y",
        "g4-wave\tfairu::write -> deeta::read",
        "g7-inverse\tjisho::put",
        "g9-dangling\tfairu::rd",
        "g9-relation\tfairu::read frobs fairu::write",
    ]
    .iter()
    .map(|s| (*s).to_string())
    .collect();
    let dir = fixture("red");
    assert_eq!(blue_findings(&dir), expected);
    assert_eq!(sql_findings(&dir), expected);
}

#[test]
fn the_fixture_with_its_faults_removed_is_green_in_both() {
    let dir = fixture("green");
    assert!(blue_findings(&dir).is_empty());
    assert!(sql_findings(&dir).is_empty());
}

#[test]
fn the_merged_tables_get_the_same_findings_from_both() {
    let scratch = std::env::temp_dir().join(format!("verb-graph-merged-{}", std::process::id()));
    std::fs::create_dir_all(&scratch).expect("scratch");
    for (from, to) in [
        ("docs/verbs/merged/verbs.tsv", "verbs.tsv"),
        ("docs/verbs/merged/edges.tsv", "edges.tsv"),
        ("docs/verbs/contracts.tsv", "contracts.tsv"),
    ] {
        std::fs::copy(repo().join(from), scratch.join(to)).expect("copy");
    }
    let dir = scratch.display().to_string();
    let theirs = sql_findings(&dir);
    let ours = blue_findings(&dir);
    std::fs::remove_dir_all(&scratch).ok();
    assert!(!theirs.is_empty(), "a vacuous comparison");
    assert_eq!(ours, theirs);
}

fn except_rows(left: &Path, right: &Path) -> String {
    duckdb(&format!(
        "create macro t(f) as table select * from read_csv(f, delim='\\t', header=true, quote='', escape='', all_varchar=true);\n\
         select count(*) from (select * from t('{l}') except select * from t('{r}'));\n",
        l = left.display(),
        r = right.display()
    ))
    .trim()
    .to_string()
}

fn row_count(path: &Path) -> String {
    duckdb(&format!(
        "select count(*) from read_csv('{}', delim='\\t', header=true, quote='', escape='', all_varchar=true);\n",
        path.display()
    ))
    .trim()
    .to_string()
}

#[test]
fn export_of_import_is_the_input_by_except_both_ways() {
    let scratch = std::env::temp_dir().join(format!("verb-graph-roundtrip-{}", std::process::id()));
    std::fs::remove_dir_all(&scratch).ok();
    let graph = scratch.join("graph");
    let out = scratch.join("out");
    let inputs = [
        ("docs/verbs/merged/verbs.tsv", "verbs.tsv"),
        ("docs/verbs/merged/edges.tsv", "edges.tsv"),
        ("docs/verbs/contracts.tsv", "contracts.tsv"),
    ];
    let mut args = vec!["import", "--dir", graph.to_str().expect("utf8")];
    args.extend(inputs.iter().map(|(from, _)| *from));
    let imported = blue(&args);
    assert!(
        imported.status.success(),
        "{}",
        String::from_utf8_lossy(&imported.stderr)
    );
    let exported = blue(&[
        "export",
        "--dir",
        graph.to_str().expect("utf8"),
        "--out",
        out.to_str().expect("utf8"),
    ]);
    assert!(
        exported.status.success(),
        "{}",
        String::from_utf8_lossy(&exported.stderr)
    );
    for (from, to) in inputs {
        let original = repo().join(from);
        let written = out.join(to);
        assert_eq!(
            except_rows(&original, &written),
            "0",
            "{to}: input minus output"
        );
        assert_eq!(
            except_rows(&written, &original),
            "0",
            "{to}: output minus input"
        );
        assert_eq!(row_count(&original), row_count(&written), "{to}: row count");
        assert_ne!(row_count(&written), "0", "{to}: a vacuous round trip");
    }
    std::fs::remove_dir_all(&scratch).ok();
}

#[test]
fn the_committed_graph_holds_its_baseline() {
    let o = blue(&["check"]);
    assert!(
        o.status.success(),
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    );
}

#[test]
fn the_untested_query_and_the_gate_name_the_same_rows() {
    let scratch = std::env::temp_dir().join(format!("verb-graph-untested-{}", std::process::id()));
    std::fs::remove_dir_all(&scratch).ok();
    let out = scratch.join("out");
    let exported = blue(&["export", "--out", out.to_str().expect("utf8")]);
    assert!(
        exported.status.success(),
        "{}",
        String::from_utf8_lossy(&exported.stderr)
    );
    let mut child = Command::new("duckdb")
        .args(["-noheader", "-list"])
        .current_dir(repo())
        .env("VERBS_TSV", out.join("verbs.tsv"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("duckdb is on PATH: the devShell carries it");
    child
        .stdin
        .take()
        .expect("stdin")
        .write_all(b".read docs/verbs/queries/untested.sql\n")
        .expect("write");
    let queried = child.wait_with_output().expect("wait");
    assert!(
        queried.status.success(),
        "duckdb: {}",
        String::from_utf8_lossy(&queried.stderr)
    );
    let theirs = lines(&String::from_utf8_lossy(&queried.stdout));
    let gated = blue(&["untested"]);
    assert!(
        gated.status.success(),
        "{}",
        String::from_utf8_lossy(&gated.stderr)
    );
    let ours = lines(&String::from_utf8_lossy(&gated.stdout));
    std::fs::remove_dir_all(&scratch).ok();
    assert!(!theirs.is_empty(), "a vacuous comparison");
    assert_eq!(ours, theirs);
}

/// **The committed tables are the graph's export.** An existing verb's
/// meaning lives in its bidama's `@doc`, a planned verb's in its row, and the
/// merged TSVs are generated from both; a doc edit not re-exported is red
/// here, so the tables cannot drift from the docs they are made from.
///
/// Red run (2026-10-24): with the TSVs as committed before `@doc` held the
/// meanings, `verbs.tsv: committed minus export` was 145.
#[test]
fn the_committed_tables_are_the_graphs_export() {
    let out = std::env::temp_dir().join(format!("verb-graph-fresh-{}", std::process::id()));
    std::fs::remove_dir_all(&out).ok();
    let exported = blue(&["export", "--out", out.to_str().expect("utf8")]);
    assert!(
        exported.status.success(),
        "{}",
        String::from_utf8_lossy(&exported.stderr)
    );
    for (committed, written) in [
        ("docs/verbs/merged/verbs.tsv", "verbs.tsv"),
        ("docs/verbs/merged/edges.tsv", "edges.tsv"),
        ("docs/verbs/contracts.tsv", "contracts.tsv"),
    ] {
        let c = repo().join(committed);
        let w = out.join(written);
        assert_eq!(
            except_rows(&c, &w),
            "0",
            "{written}: committed minus export"
        );
        assert_eq!(
            except_rows(&w, &c),
            "0",
            "{written}: export minus committed"
        );
        assert_eq!(row_count(&c), row_count(&w), "{written}: row count");
    }
    std::fs::remove_dir_all(&out).ok();
}
