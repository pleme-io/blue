//! `blue query` (`theory/BLUE-TOOLING.md` T-K) as a subprocess: a query
//! named in a Bluefile, the JSON lines, a skipped file, and blue's own
//! `bidamas/` asked which definitions reach the filesystem.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

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

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-query-{name}-{}", std::process::id()));
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

const PROGRAM: &str = "def load(path)\n  read_file(path)\nend\n\n\
def boot()\n  load(\"/etc/app\")\nend\n\n\
def pure(x)\n  x + 1\nend\n";

/// `blue query NAME` runs the Bluefile's `query(NAME, …)`, from the project
/// directory or below it, and a name the Bluefile does not declare is an
/// error listing the ones it does.
#[test]
fn a_query_named_in_the_bluefile_runs_by_its_name() {
    let dir = scratch("named");
    put(
        &dir.join("Bluefile"),
        "package(\"app\", \"0.1.0\")\nquery(\"touches_disk\", \"(reaches filesystem) (unannotated)\")\n",
    );
    put(&dir.join("src/app.b"), PROGRAM);
    let o = blue()
        .current_dir(dir.join("src"))
        .args(["query", "touches_disk", "app.b"])
        .output()
        .expect("blue runs");
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(
        out(&o),
        "app.b:1:1: load  filesystem via read_file\n\
         app.b:5:1: boot  filesystem via %root/load -> read_file\n"
    );
    let o = blue()
        .current_dir(&dir)
        .args(["query", "nothing", "src"])
        .output()
        .expect("blue runs");
    assert!(!o.status.success());
    assert!(
        err(&o).contains("declares no query `nothing`; it declares: touches_disk"),
        "{}",
        err(&o)
    );
}

/// `--json` is one object per hit per line, the engine's `Hit::json`.
///
/// Red run (2026-10-11): before definitions' signatures were skipped,
/// `load`'s own `(load path)` was a second hit.
#[test]
fn json_is_one_object_per_hit_with_the_bindings() {
    let dir = scratch("json");
    put(&dir.join("app.b"), PROGRAM);
    let o = blue()
        .current_dir(&dir)
        .args(["query", "--json", "(match `(%root/load ,path))", "app.b"])
        .output()
        .expect("blue runs");
    assert!(o.status.success(), "{}", err(&o));
    let lines: Vec<serde_json::Value> = out(&o)
        .lines()
        .map(|l| serde_json::from_str(l).expect("a JSON line"))
        .collect();
    assert_eq!(
        lines,
        [serde_json::json!({
            "file": "app.b",
            "line": 6,
            "column": 3,
            "definition": "boot",
            "key": "%root/boot",
            "kind": "function",
            "bindings": {"path": "\"/etc/app\""},
            "reach": {"filesystem": ["%root/load", "read_file"]},
        })]
    );
}

/// A file whose imports do not load has nothing to ask; it is named and the
/// exit is 1, so it never reads as a file with no hits.
///
/// Red run (2026-10-11): `unanswerable` answering `None`: the run exited 0.
#[test]
fn a_file_that_cannot_be_resolved_is_named_and_fails_the_run() {
    let dir = scratch("skipped");
    put(&dir.join("app.b"), PROGRAM);
    put(
        &dir.join("broken.b"),
        "use(\"no_such_bidama\")\n\ndef f()\n  1\nend\n",
    );
    let o = blue()
        .current_dir(&dir)
        .args(["query", "(kind function)", "."])
        .output()
        .expect("blue runs");
    assert!(!o.status.success());
    assert!(
        err(&o).contains("broken.b: skipped, its imports do not load"),
        "{}",
        err(&o)
    );
    assert!(
        err(&o).contains("3 hit(s) in 1 file(s), 1 skipped"),
        "{}",
        err(&o)
    );
}

/// The docs' example over blue's own standard bidamas: which definitions
/// reach the filesystem. Every hit names the chain it reaches it through,
/// and the chain ends at a primitive the filesystem capability grants.
#[test]
fn which_bidama_definitions_reach_the_filesystem() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let o = blue()
        .current_dir(&root)
        .args(["query", "--json", "(reaches filesystem)", "bidamas"])
        .output()
        .expect("blue runs");
    assert!(o.status.success(), "{}", err(&o));
    let hits: Vec<serde_json::Value> = out(&o)
        .lines()
        .map(|l| serde_json::from_str(l).expect("a JSON line"))
        .collect();
    assert!(!hits.is_empty());
    for h in &hits {
        let via = h["reach"]["filesystem"].as_array().expect("a chain");
        let primitive = via.last().and_then(|p| p.as_str()).expect("a primitive");
        assert!(
            blue_lang_waku::Capability::FileSystem.grants(primitive),
            "{h}"
        );
    }
}
