//! deeta::read, stringify and write, blue's own JSON reader and writers (R6a
//! of docs/PURE-BLUE.md), agree with the Rust json_parse, json_stringify and
//! json_write on every in.json fixture json_parse accepts. A fixture json_parse refuses is skipped; any other difference is
//! red, and a corpus that compared fewer than 250 files is red too, so the
//! test cannot pass by reading nothing.

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

#[test]
fn read_agrees_with_json_parse_on_every_fixture() {
    let text =
        std::fs::read_to_string(root().join("crates/blue-lang-yaml-diff/tests/json_agree.b"))
            .expect("json_agree.b");
    let loader = LoadPath::new([root().join("bidamas")]);
    let mut program = Program::<()>::builder(Entry::anonymous(Box::leak(text.into_boxed_str())))
        .loader(Box::leak(Box::new(loader)))
        .canonical(Canonical::Required)
        .load(&mut ())
        .expect("json_agree.b loads with deeta");
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
            Value::Str(s) if &*s == "skipped" => {}
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
