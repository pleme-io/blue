//! **`blue shift --json` is a stable interface.** CI gates a project's blueshift
//! floor on it (`docs/BUILD-ASSURANCE.md` §4, `pleme-io/actions` `blue-shift`), so
//! the field names and the rung words are pinned here.
//!
//! Red run (2026-10-27): before `--json` existed the flag was refused by clap,
//! `unexpected argument '--json'`.

use std::process::Command;

fn shift_json(name: &str, src: &str) -> serde_json::Value {
    let dir = std::env::temp_dir().join(format!("blue-shift-json-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("mkdir");
    let path = dir.join(format!("{name}.b"));
    std::fs::write(&path, src).expect("write");
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .args(["shift", "--json"])
        .arg(&path)
        .output()
        .expect("run blue");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    serde_json::from_slice(&out.stdout).expect("one JSON object")
}

#[test]
fn an_untyped_file_reads_dynamic_and_names_what_holds_it_back() {
    let v = shift_json("untyped", "def add(a, b)\n  a + b\nend\n");
    assert_eq!(v["rung"], "dynamic");
    assert_eq!(v["typed"], 0);
    assert_eq!(v["total"], 1);
    assert_eq!(v["analysed_nodes"], 0);
    let held = &v["holding_back"][0];
    assert_eq!(held["subject"], "add");
    assert_eq!(held["line"], 1);
    assert_eq!(held["kind"], "untyped declaration");
}

#[test]
fn a_typed_file_reads_checked_with_nothing_holding_it_back() {
    let v = shift_json("typed", "def add(a: Int, b: Int) -> Int\n  a + b\nend\n");
    assert_eq!(v["rung"], "checked");
    assert_eq!(v["typed"], 1);
    assert_eq!(v["holding_back"], serde_json::json!([]));
}
