//! deeta::read, stringify and write, blue's own JSON reader and writers (R6a
//! of docs/PURE-BLUE.md), agree with the Rust json_parse, json_stringify and
//! json_write on every in.json fixture: both refuse it, or both read it to
//! values whose blue literals are equal, kind and all. A refusal on one side
//! only is red, as is any other difference, and a corpus that compared fewer
//! than 250 files is red too, so the test cannot pass by reading nothing.

use std::path::{Path, PathBuf};

use blue_lang_host::{Canonical, Entry, Program, Value};
use blue_lang_pkg::load_path::LoadPath;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn json_fixtures(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in std::fs::read_dir(dir).expect("fixtures dir").flatten() {
        let path = entry.path();
        if path.is_dir() {
            json_fixtures(&path, out);
        } else if path.file_name().is_some_and(|n| n == "in.json") {
            out.push(path);
        }
    }
}

fn agreement() -> Program<()> {
    let text =
        std::fs::read_to_string(root().join("crates/blue-lang-yaml-diff/tests/json_agree.b"))
            .expect("json_agree.b");
    let loader = LoadPath::new([root().join("bidamas")]);
    Program::<()>::builder(Entry::anonymous(Box::leak(text.into_boxed_str())))
        .loader(Box::leak(Box::new(loader)))
        .canonical(Canonical::Required)
        .load(&mut ())
        .expect("json_agree.b loads with deeta")
}

#[test]
fn read_agrees_with_json_parse_on_every_fixture() {
    let mut program = agreement();
    let mut files = Vec::new();
    json_fixtures(&root().join("bidamas/deeta/fixtures"), &mut files);
    files.sort();
    let mut same = 0;
    let mut differs = Vec::new();
    for f in &files {
        let doc = std::fs::read_to_string(f).expect("fixture");
        match program
            .call::<Value>("agrees", (doc,), &mut ())
            .expect("agrees answers")
        {
            Value::Str(s) if &*s == "same" => same += 1,
            Value::Str(s) if &*s == "both refuse" => {}
            other => differs.push(format!("{}: {other:?}", f.display())),
        }
    }
    assert!(
        differs.is_empty(),
        "deeta differs from the Rust JSON surface on: {differs:#?}"
    );
    assert!(
        same >= 250,
        "only {same} of {} fixtures compared",
        files.len()
    );
}

#[test]
fn the_readers_agree_on_every_number_edge() {
    let mut program = agreement();
    let mut seen = Vec::new();
    for doc in [
        "9223372036854775807",
        "9223372036854775808",
        "-9223372036854775809",
        "[18446744073709551616, 1]",
        "{\"n\": 123456789012345678901234567890}",
        "1e308",
        "1e400",
        "-1e400",
        "[1, 1e400]",
        "-0",
        "[-0, 0]",
        "{\"a\": -0}",
        "+1",
        "01",
        "1.",
        ".5",
        "1.e5",
    ] {
        let said = program
            .call::<Value>("agrees", (doc.to_string(),), &mut ())
            .expect("agrees answers");
        seen.push(format!("{doc}: {said}"));
    }
    assert_eq!(
        seen,
        [
            "9223372036854775807: \"same\"",
            "9223372036854775808: \"same\"",
            "-9223372036854775809: \"same\"",
            "[18446744073709551616, 1]: \"same\"",
            "{\"n\": 123456789012345678901234567890}: \"same\"",
            "1e308: \"same\"",
            "1e400: \"both refuse\"",
            "-1e400: \"both refuse\"",
            "[1, 1e400]: \"both refuse\"",
            "-0: \"same\"",
            "[-0, 0]: \"same\"",
            "{\"a\": -0}: \"same\"",
            "+1: \"both refuse\"",
            "01: \"both refuse\"",
            "1.: \"both refuse\"",
            ".5: \"both refuse\"",
            "1.e5: \"both refuse\"",
        ]
    );
}
