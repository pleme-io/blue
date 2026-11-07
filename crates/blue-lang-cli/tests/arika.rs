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

const FORWARDED: &str = "def fold(ys, start, f)\n  reduce(f, start, ys)\nend\n\ndef total(ys)\n  fold(ys, 0, (p, q) -> p + q)\nend\n";

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

const KAGI: &str = "@moduledoc \"\"\"\nkagi holds small words.\n\n    kagi::twice(2) #=> 4\n\"\"\"\n\n@doc \"\"\"\ntwice: the number doubled.\n\n    twice(2) #=> 4\n\"\"\"\ndef twice(n)\n  n * 2\nend\n\nLIMIT = 3\n\ndef capped(xs)\n  filter((x) -> x < LIMIT, xs)\nend\n";

const TOBIRA: &str = "use(\"kagi\", [:twice])\n\ndef quad(n)\n  twice(twice(n))\nend\n";

fn fixture_tree(dir: &Dir, under: &str) -> PathBuf {
    let root = dir.0.join(under).join("bidamas");
    for (pkg, source) in [("kagi", KAGI), ("tobira", TOBIRA)] {
        let p = root.join(pkg);
        std::fs::create_dir_all(&p).expect("mkdir");
        std::fs::write(
            p.join("Bluefile"),
            format!("package(\"{pkg}\", \"0.1.0\")\n"),
        )
        .expect("write");
        std::fs::write(p.join(format!("{pkg}.b")), source).expect("write");
    }
    root
}

fn emit(dir: &Path, root: &Path, out: &Path, facts: &Path) -> Output {
    run(
        dir,
        &[
            "arika",
            "emit",
            &root.display().to_string(),
            "--out",
            &out.display().to_string(),
            "--facts",
            &facts.display().to_string(),
        ],
    )
}

fn snapshot(path: &Path) -> serde_json::Value {
    serde_json::from_str(&std::fs::read_to_string(path).expect("read")).expect("json")
}

fn rows_of(facts: &Path) -> Vec<serde_json::Value> {
    std::fs::read_to_string(facts)
        .expect("read")
        .lines()
        .map(|l| serde_json::from_str(l).expect("one JSON row per line"))
        .collect()
}

fn emitted(d: &Dir, root: &Path, name: &str) -> (PathBuf, PathBuf) {
    let (header, facts) = (
        d.0.join(format!("{name}.json")),
        d.0.join(format!("{name}.jsonl")),
    );
    let o = emit(&d.0, root, &header, &facts);
    assert_eq!(
        o.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&o.stderr)
    );
    (header, facts)
}

#[test]
fn emit_is_byte_identical_for_the_same_tree_wherever_it_lies() {
    let d = Dir::new("determinism");
    let here = fixture_tree(&d, "here");
    let there = fixture_tree(&d, "elsewhere/deeper");
    let a = emitted(&d, &here, "a");
    let b = emitted(&d, &here, "b");
    let c = emitted(&d, &there, "c");
    for (x, y) in [(&a, &b), (&a, &c)] {
        assert_eq!(std::fs::read(&x.0).ok(), std::fs::read(&y.0).ok());
        assert_eq!(std::fs::read(&x.1).ok(), std::fs::read(&y.1).ok());
    }
    let header = std::fs::read_to_string(&a.0).expect("read");
    assert!(!header.contains("\"word\""), "the header carries no rows");
    std::fs::write(
        here.join("kagi/kagi.b"),
        KAGI.replace("x < LIMIT", "x <= LIMIT"),
    )
    .expect("write");
    let moved = snapshot(&emitted(&d, &here, "b").0);
    let old = snapshot(&a.0);
    assert_ne!(old["snapshot_root"], moved["snapshot_root"]);
    let units = moved["units"].as_array().expect("units");
    let old_units = old["units"].as_array().expect("units");
    assert_ne!(
        units[0]["unit_root"], old_units[0]["unit_root"],
        "kagi changed"
    );
    assert_eq!(
        units[1]["unit_root"], old_units[1]["unit_root"],
        "tobira did not"
    );
}

#[test]
fn every_definition_is_one_leaf_with_its_facts_g2() {
    let d = Dir::new("coverage");
    let root = fixture_tree(&d, "t");
    let (header, facts) = emitted(&d, &root, "s");
    let snap = snapshot(&header);
    let rows = rows_of(&facts);
    assert_eq!(snap["format"], "arika/1");
    assert_eq!(snap["definitions"], 4);
    assert_eq!(snap["leaves"], 4);
    assert_eq!(snap["blind"], serde_json::json!([]));
    let named: Vec<(&str, &str)> = rows
        .iter()
        .map(|r| {
            (
                r["word"].as_str().unwrap_or_default(),
                r["kind"].as_str().unwrap_or_default(),
            )
        })
        .collect();
    assert_eq!(
        named,
        [
            ("kagi::LIMIT", "value"),
            ("kagi::capped", "function"),
            ("kagi::twice", "function"),
            ("tobira::quad", "function")
        ]
    );
    let twice = &rows[2];
    assert!(is_id(
        twice["id"].as_str().unwrap_or_default(),
        "kagi::twice"
    ));
    assert_eq!(twice["gloss"], "twice: the number doubled.");
    assert_eq!(twice["file"], "kagi/kagi.b");
    for key in ["def_hash", "shape", "written_shape"] {
        assert!(
            twice[key]
                .as_str()
                .is_some_and(|h| h.starts_with("b3:") && h.len() == 67),
            "{key}: {}",
            twice[key]
        );
    }
    assert_eq!(
        &twice["def_hash"].as_str().unwrap_or_default()[3..15],
        twice["id"]
            .as_str()
            .unwrap_or_default()
            .rsplit_once('@')
            .map_or("", |(_, h)| h)
    );
    let units = snap["units"].as_array().expect("units");
    assert_eq!(
        units
            .iter()
            .map(|u| (u["package"].clone(), u["leaves"].clone()))
            .collect::<Vec<_>>(),
        [
            (serde_json::json!("kagi"), serde_json::json!(3)),
            (serde_json::json!("tobira"), serde_json::json!(1))
        ]
    );
    for u in units {
        assert!(u["unit_root"]
            .as_str()
            .is_some_and(|h| h.starts_with("b3:")));
    }
}

fn repo_snapshot() -> PathBuf {
    repo().join("bidamas/SNAPSHOT.json")
}

fn repo_facts() -> &'static Path {
    static FACTS: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
    FACTS.get_or_init(|| {
        let dir = std::env::temp_dir().join(format!("blue-arika-{}-repo", std::process::id()));
        std::fs::create_dir_all(&dir).expect("mkdir");
        let (header, facts) = (dir.join("SNAPSHOT.json"), dir.join("facts.jsonl"));
        let o = emit(&dir, &repo().join("bidamas"), &header, &facts);
        assert_eq!(
            o.status.code(),
            Some(0),
            "{}",
            String::from_utf8_lossy(&o.stderr)
        );
        facts
    })
}

#[test]
fn every_word_shapes_row_is_a_fact_row_with_the_same_home_g3() {
    let rows = rows_of(repo_facts());
    let by_word: std::collections::BTreeMap<&str, Vec<&str>> =
        rows.iter()
            .fold(std::collections::BTreeMap::new(), |mut m, r| {
                if let (Some(w), Some(s)) = (r["word"].as_str(), r["shape"].as_str()) {
                    m.entry(w).or_insert_with(Vec::new).push(&s[3..]);
                }
                m
            });
    let mut missing = Vec::new();
    for (prefix, word, _) in blue_lang_runtime::word_shapes::WORD_SHAPES {
        let held = by_word
            .get(word)
            .is_some_and(|shapes| shapes.iter().any(|s| s.starts_with(prefix)));
        if !held {
            missing.push(format!("{prefix} {word}"));
        }
    }
    assert!(
        missing.is_empty(),
        "WORD_SHAPES rows with no fact row: {missing:?}"
    );
    let prefixes: BTreeSet<&str> = blue_lang_runtime::word_shapes::WORD_SHAPES
        .iter()
        .map(|(p, _, _)| *p)
        .collect();
    let unlisted: Vec<&str> = rows
        .iter()
        .filter(|r| r["size"].as_u64().is_some_and(|s| s >= 12))
        .filter_map(|r| r["shape"].as_str())
        .filter(|s| !prefixes.contains(&s[3..19]))
        .collect();
    assert!(
        unlisted.is_empty(),
        "fact shapes WORD_SHAPES lacks: {unlisted:?}"
    );
}

fn canonical_homes(facts: &serde_json::Value) -> serde_json::Value {
    let mut f = facts.clone();
    if let Some(o) = f.as_object_mut() {
        o.remove("snapshot_root");
    }
    for d in f["defs"].as_array_mut().into_iter().flatten() {
        for h in d["hits"].as_array_mut().into_iter().flatten() {
            if let Some(file) = h["home"]["file"].as_str() {
                h["home"]["file"] = serde_json::json!(std::fs::canonicalize(file)
                    .map_or_else(|_| file.to_string(), |p| p.display().to_string()));
            }
        }
    }
    f
}

fn from_snapshot(dir: &Dir, facts: &Path, args: &[&str]) -> serde_json::Value {
    let snap = repo_snapshot().display().to_string();
    let facts = facts.display().to_string();
    let mut all = vec!["arika"];
    all.extend_from_slice(&args[..1]);
    all.extend_from_slice(&["--json", "--snapshot", &snap, "--facts", &facts]);
    all.extend_from_slice(&args[1..]);
    let out = run(&dir.0, &all);
    assert_eq!(
        out.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    serde_json::from_str(text(&out).trim()).expect("json")
}

#[test]
fn like_from_the_facts_answers_as_the_engine_does() {
    let d = Dir::new("parity");
    let root = snapshot(&repo_snapshot())["snapshot_root"].clone();
    let mut hits_seen = 0;
    let mut tiers = BTreeSet::new();
    for (i, source) in [EXACT, RENAMED, WRAPPED, NOTHING, FORWARDED]
        .iter()
        .enumerate()
    {
        let file = d.write(&format!("s{i}.b"), source);
        let engine = like(&d, &file);
        let from = from_snapshot(&d, repo_facts(), &["like", &file]);
        assert_eq!(from["snapshot_root"], root, "{from}");
        assert_eq!(canonical_homes(&from), canonical_homes(&engine), "{source}");
        hits_seen += hits(&engine).len();
        tiers.extend(hits(&engine).into_iter().map(|h| (h.1, h.2)));
    }
    assert_eq!(hits_seen, 5, "the fixtures stopped exercising a home");
    assert!(tiers.contains(&("kazu::sum".to_string(), "T1".to_string())));
}

#[test]
fn word_from_the_facts_finds_what_the_engine_finds() {
    let d = Dir::new("wordsnap");
    for q in ["without", "find_index_of", "running", "abs"] {
        let engine: serde_json::Value =
            serde_json::from_str(text(&run(&d.0, &["arika", "word", "--json", q])).trim())
                .expect("json");
        let from = from_snapshot(&d, repo_facts(), &["word", q]);
        assert_eq!(from["old"], engine["old"], "{q}");
        for key in ["names", "parts"] {
            let ours = from[key].as_array().expect("list");
            for w in engine[key].as_array().expect("list") {
                assert!(ours.contains(w), "{q} {key}: {w} not in {ours:?}");
            }
        }
    }
}

#[test]
fn facts_that_do_not_hash_to_the_header_are_refused_as_blind() {
    let d = Dir::new("stale");
    let text = std::fs::read_to_string(repo_facts()).expect("read");
    let edited = text.replacen("\"gloss\":null", "\"gloss\":\"edited\"", 1);
    assert_ne!(edited, text);
    let stale = d.0.join("stale.jsonl");
    std::fs::write(&stale, edited).expect("write");
    let file = d.write("r.b", RENAMED);
    let like = from_snapshot(&d, &stale, &["like", &file]);
    assert_eq!(like["outcome"], "blind", "{like}");
    assert!(like["why"].as_str().is_some_and(|w| w.contains("stale")));
    assert_eq!(like["defs"], serde_json::json!([]));
    let word = from_snapshot(&d, &stale, &["word", "without"]);
    assert_eq!(word["outcome"], "blind", "{word}");
}
