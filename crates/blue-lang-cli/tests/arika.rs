use std::collections::BTreeSet;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_DIST")
        .env("BLUE_PATH", repo().join("bidamas"));
    c
}

fn run(dir: &Path, args: &[&str]) -> Output {
    blue().current_dir(dir).args(args).output().expect("spawn")
}

fn with_stdin(dir: &Path, args: &[&str], stdin: &str) -> Output {
    let mut child = blue()
        .current_dir(dir)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn");
    child
        .stdin
        .take()
        .expect("stdin")
        .write_all(stdin.as_bytes())
        .expect("write");
    child.wait_with_output().expect("wait")
}

fn text(out: &Output) -> String {
    String::from_utf8_lossy(&out.stdout).into_owned()
}

struct Dir(PathBuf);

impl Dir {
    fn new(name: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("blue-arika-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("mkdir");
        Dir(dir)
    }

    fn write(&self, file: &str, source: &str) -> String {
        let path = self.0.join(file);
        std::fs::write(&path, source).expect("write");
        path.display().to_string()
    }
}

impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

const EXACT: &str = "@doc \"\"\"\nabs: distance from zero.\n\n    abs(0) #=> 0\n\"\"\"\ndef magnitude(n)\n  if n < 0\n    -n\n  else\n    n\n  end\nend\n";

const RENAMED: &str = "def drop_value(ys, w)\n  filter((y) -> y != w, ys)\nend\n";

const WRAPPED: &str = "def remove_all(xs, v)\n  filter((x) -> x != v, xs)\nend\n\ndef strip(ys, w)\n  remove_all(ys, w)\nend\n";

const NOTHING: &str = "def unrelated(x)\n  x * 7 + 3\nend\n";

fn like(dir: &Dir, file: &str) -> serde_json::Value {
    let out = run(&dir.0, &["arika", "like", "--json", file]);
    assert_eq!(
        out.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    serde_json::from_str(text(&out).trim()).expect("one JSON object")
}

fn hits(facts: &serde_json::Value) -> Vec<(String, String, String, String)> {
    facts["defs"]
        .as_array()
        .expect("defs")
        .iter()
        .flat_map(|d| {
            d["hits"].as_array().expect("hits").iter().map(move |h| {
                (
                    d["name"].as_str().unwrap_or_default().to_string(),
                    h["word"].as_str().unwrap_or_default().to_string(),
                    h["tier"].as_str().unwrap_or_default().to_string(),
                    h["id"].as_str().unwrap_or_default().to_string(),
                )
            })
        })
        .collect()
}

fn is_id(id: &str, word: &str) -> bool {
    id.strip_prefix(&format!("blue:blue:{word}@"))
        .is_some_and(|h| h.len() == 12 && h.bytes().all(|b| b.is_ascii_hexdigit()))
}

#[test]
fn each_tier_names_the_word_with_a_readable_id() {
    let d = Dir::new("tiers");
    let cases = [
        (EXACT, vec![("magnitude", "kazu::abs", "T0")]),
        (RENAMED, vec![("drop_value", "retsu::without", "T1")]),
        (
            WRAPPED,
            vec![
                ("remove_all", "retsu::without", "T0"),
                ("strip", "retsu::without", "T2"),
            ],
        ),
        (NOTHING, vec![]),
    ];
    for (i, (source, want)) in cases.iter().enumerate() {
        let file = d.write(&format!("f{i}.b"), source);
        let got = hits(&like(&d, &file));
        let named: Vec<(&str, &str, &str)> = got
            .iter()
            .map(|(n, w, t, _)| (n.as_str(), w.as_str(), t.as_str()))
            .collect();
        assert_eq!(&named, want, "{source}");
        for (_, word, _, id) in &got {
            assert!(is_id(id, word), "{id} is not blue:blue:{word}@<12 hex>");
        }
    }
}

fn b0070_words(dir: &Dir, file: &str) -> BTreeSet<(String, String)> {
    let out = run(&dir.0, &["check", "--reuse", file]);
    text(&out)
        .lines()
        .filter_map(|l| {
            let (_, rest) = l.split_once(": `")?;
            let (name, rest) = rest.split_once("` is the shape of `")?;
            let (word, _) = rest.split_once('`')?;
            Some((name.to_string(), word.to_string()))
        })
        .collect()
}

#[test]
fn arika_and_b0070_name_the_same_word_g4() {
    let d = Dir::new("g4");
    let mut seen = 0;
    for (i, source) in [EXACT, RENAMED, WRAPPED, NOTHING].iter().enumerate() {
        let file = d.write(&format!("p{i}.b"), source);
        let ours: BTreeSet<(String, String)> = hits(&like(&d, &file))
            .into_iter()
            .map(|(n, w, _, _)| (n, w))
            .collect();
        let theirs = b0070_words(&d, &file);
        assert_eq!(ours, theirs, "{source}");
        seen += theirs.len();
    }
    assert_eq!(seen, 4, "the fixtures stopped exercising B0070");
}

#[test]
fn a_line_narrows_to_the_definition_it_falls_in() {
    let d = Dir::new("line");
    let file = d.write("w.b", WRAPPED);
    let at = |line: usize| hits(&like(&d, &format!("{file}:{line}")));
    assert_eq!(
        at(2).iter().map(|h| h.0.as_str()).collect::<Vec<_>>(),
        ["remove_all"]
    );
    assert_eq!(
        at(6).iter().map(|h| h.0.as_str()).collect::<Vec<_>>(),
        ["strip"]
    );
    assert!(at(4).is_empty());
}

fn hook(dir: &Dir, payload: &serde_json::Value) -> Output {
    with_stdin(&dir.0, &["arika", "like", "--hook"], &payload.to_string())
}

#[test]
fn the_hook_advises_on_the_draft_before_the_write_and_never_blocks() {
    let d = Dir::new("hook");
    let target = d.0.join("new.b").display().to_string();
    let write = hook(
        &d,
        &serde_json::json!({"tool_name": "Write", "tool_input": {"file_path": target, "content": RENAMED}}),
    );
    assert_eq!(write.status.code(), Some(0));
    let shown = text(&write);
    assert!(!d.0.join("new.b").exists());
    assert!(shown.contains("arika: "), "{shown}");
    assert!(shown.contains("retsu::without"), "{shown}");
    assert!(shown.contains("use(\"retsu\", [:without])"), "{shown}");
    assert!(shown.contains("nothing is blocked"), "{shown}");

    let file = d.write("old.b", NOTHING);
    let edit = hook(
        &d,
        &serde_json::json!({"tool_name": "Edit", "tool_input": {
            "file_path": file,
            "old_string": "def unrelated(x)\n  x * 7 + 3",
            "new_string": "def unrelated(xs, v)\n  filter((x) -> x != v, xs)"}}),
    );
    assert_eq!(edit.status.code(), Some(0));
    assert!(
        text(&edit).contains("def unrelated is an exact copy of retsu::without"),
        "{}",
        text(&edit)
    );
    assert_eq!(std::fs::read_to_string(&file).expect("read"), NOTHING);
    let edit = hook(
        &d,
        &serde_json::json!({"tool_name": "MultiEdit", "tool_input": {"file_path": file, "edits": [
            {"old_string": "def unrelated(x)", "new_string": "def unrelated(xs, v)"},
            {"old_string": "x * 7 + 3", "new_string": "filter((x) -> x != v, xs)"}]}}),
    );
    assert!(
        text(&edit).contains("def unrelated is an exact copy of retsu::without"),
        "{}",
        text(&edit)
    );

    for silent in [
        String::new(),
        "not json".to_string(),
        serde_json::json!({"tool_name": "Write", "tool_input": {"file_path": d.0.join("a.txt"), "content": RENAMED}}).to_string(),
        serde_json::json!({"tool_name": "Write", "tool_input": {"file_path": target, "content": "def broken(\n"}}).to_string(),
        serde_json::json!({"tool_name": "Edit", "tool_input": {"file_path": d.0.join("gone.b"), "old_string": "a", "new_string": "b"}}).to_string(),
        serde_json::json!({"tool_name": "Edit", "tool_input": {"file_path": file, "old_string": "absent", "new_string": "b"}}).to_string(),
        serde_json::json!({"tool_name": "Write", "tool_input": {"file_path": target, "content": NOTHING}}).to_string(),
    ] {
        let out = with_stdin(&d.0, &["arika", "like", "--hook"], &silent);
        assert_eq!(out.status.code(), Some(0), "{silent}");
        assert!(text(&out).is_empty(), "{silent}: {}", text(&out));
    }
}

#[test]
fn a_word_is_found_by_name_old_spelling_and_gloss() {
    let d = Dir::new("word");
    let by_name = text(&run(&d.0, &["arika", "word", "without"]));
    assert!(
        by_name
            .lines()
            .next()
            .is_some_and(|l| l == "T5 name    retsu::without (foundation)"),
        "{by_name}"
    );
    let by_old = text(&run(&d.0, &["arika", "word", "find_index_of"]));
    assert!(
        by_old.contains("T5 old     angou::find_index_of is retsu::index_of_at since 0.1.1"),
        "{by_old}"
    );
    let json = run(&d.0, &["arika", "word", "--json", "running"]);
    let m: serde_json::Value = serde_json::from_str(text(&json).trim()).expect("json");
    assert_eq!(m["catalog"], "found");
    assert!(m["parts"]
        .as_array()
        .is_some_and(|p| p.iter().any(|w| w["word"] == "retsu::running_sum")));
    let none = text(&run(&d.0, &["arika", "word", "zzqqxx"]));
    assert!(
        none.contains("no blue word is named or glossed `zzqqxx`"),
        "{none}"
    );
}
