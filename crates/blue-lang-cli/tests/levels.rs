//! A tree on disk, through the real binary: directories and files as levels,
//! an entry inside a level, the lock's capability floor joining through every
//! depth, a part of a bidama that is no level, and a data directory nothing
//! loads.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_DIST")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG");
    c
}

fn put(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).expect("write fixture");
}

fn say(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

const PROJECT: &str = "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\n";

fn tree(name: &str, project: &str, deep: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-levels-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    put(&dir.join("Bluefile"), project);
    let root = dir.join("bidamas/tree");
    put(&root.join("Bluefile"), "package(\"tree\", \"0.1.0\")\n");
    put(
        &root.join("tree.b"),
        "def top()\n  \"top\"\nend\n\ntest \"top\"\n  assert top == \"top\"\nend\n",
    );
    put(&root.join("part.b"), "def merged()\n  \"merged\"\nend\n");
    put(
        &root.join("door.b"),
        "namespace()\n\ndef key()\n  \"key\"\nend\n\ntest \"key\"\n  assert key == \"key\"\nend\n",
    );
    put(
        &root.join("room/room.b"),
        "def bed()\n  \"bed\"\nend\n\ntest \"bed\"\n  assert bed == \"bed\"\nend\n",
    );
    put(&root.join("room/deep/deep.b"), deep);
    put(&root.join("fixtures/data.b"), "this is ( not blue\n");
    dir.canonicalize().unwrap()
}

const PURE: &str = "def word()\n  \"deep\"\nend\n\ntest \"word\"\n  assert word == \"deep\"\nend\n";
const CLOCK: &str = "def word()\n  now_ms\nend\n";

#[test]
fn directories_and_files_are_levels_and_a_part_stays_a_part() {
    let dir = tree("shape", PROJECT, PURE);
    put(
        &dir.join("main.b"),
        "use(\"tree\")\n\nwrite_stdout(concat(tree::top, tree::merged, door::key, tree::door::key, room::bed, tree::room::deep::word, room::deep::word))\n",
    );
    let o = blue().current_dir(&dir).args(["main.b"]).output().unwrap();
    assert!(o.status.success(), "{}", say(&o));
    assert_eq!(
        String::from_utf8_lossy(&o.stdout),
        "topmergedkeykeybeddeepdeep"
    );

    put(&dir.join("bad.b"), "use(\"tree/part\")\n\n1\n");
    let o = blue()
        .current_dir(&dir)
        .args(["run", "bad.b"])
        .output()
        .unwrap();
    assert!(!o.status.success());
    assert!(
        say(&o).contains("is a part of `tree`, not a level of its own"),
        "{}",
        say(&o)
    );
}

#[test]
fn a_file_inside_a_level_is_tested_in_that_level() {
    let dir = tree("entry", PROJECT, PURE);
    for file in [
        "bidamas/tree/tree.b",
        "bidamas/tree/door.b",
        "bidamas/tree/room/room.b",
        "bidamas/tree/room/deep/deep.b",
    ] {
        let o = blue()
            .current_dir(&dir)
            .args(["test", file])
            .output()
            .unwrap();
        assert!(o.status.success(), "{file}: {}", say(&o));
    }
    let o = blue()
        .current_dir(&dir)
        .args(["explain-name", "word", "bidamas/tree/room/deep/deep.b:1"])
        .output()
        .unwrap();
    assert!(say(&o).contains("tree/room/deep"), "{}", say(&o));
}

#[test]
fn a_host_word_three_levels_down_joins_the_root_floor_in_the_lock() {
    let none = format!("{PROJECT}allow(%i[])\n");
    let dir = tree("floor", &none, CLOCK);
    put(
        &dir.join("main.b"),
        "use(\"tree/room\")\n\nwrite_stdout(room::deep::word)\n",
    );
    let o = blue().arg("lock").arg(&dir).output().unwrap();
    assert!(
        !o.status.success(),
        "a ceiling of none holds the deep word: {}",
        say(&o)
    );
    assert!(say(&o).contains("tree/room/deep::word"), "{}", say(&o));
    assert!(say(&o).contains("clock"), "{}", say(&o));

    put(
        &dir.join("Bluefile"),
        &format!("{PROJECT}allow(%i[clock])\n"),
    );
    let o = blue().arg("lock").arg(&dir).output().unwrap();
    assert!(o.status.success(), "{}", say(&o));
    let text = std::fs::read_to_string(dir.join("Bluefile.lock")).unwrap();
    let lock: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(
        lock["capabilities"]["packages"]["tree"],
        serde_json::json!(["clock"]),
        "{text}"
    );
    assert!(
        lock["capabilities"]["definitions"]
            .as_object()
            .unwrap()
            .contains_key("tree/room/deep::word"),
        "{text}"
    );
}

#[test]
fn a_levels_import_joins_the_bidamas_one_lock() {
    let dir = tree("needs", PROJECT, "use(\"retsu\", [:first])\n\ndef word()\n  first([\"deep\"])\nend\n\ntest \"word\"\n  assert word == \"deep\"\nend\n");
    let root = dir.join("bidamas/tree");
    let o = blue().arg("lock").arg(&root).output().unwrap();
    assert!(o.status.success(), "{}", say(&o));
    let text = std::fs::read_to_string(root.join("Bluefile.lock")).unwrap();
    let lock: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert!(lock["manifest"]["needs"]["retsu"].is_string(), "{text}");
    assert!(lock["manifest"]["needs"].get("tree").is_none(), "{text}");
}

#[test]
fn a_level_with_a_bluefile_of_its_own_is_refused() {
    let dir = tree("own-bluefile", PROJECT, PURE);
    put(
        &dir.join("bidamas/tree/room/Bluefile"),
        "package(\"room\", \"0.1.0\")\n",
    );
    put(&dir.join("main.b"), "use(\"tree/room\")\n\nroom::bed\n");
    let o = blue()
        .current_dir(&dir)
        .args(["run", "main.b"])
        .output()
        .unwrap();
    assert!(!o.status.success());
    assert!(say(&o).contains("has a Bluefile of its own"), "{}", say(&o));
}
