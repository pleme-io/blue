//! **`blue doc`**, the blue program compiled into the binary, against the
//! repository's own distribution (`bidamas/` on `BLUE_PATH`).

use std::path::PathBuf;
use std::process::{Command, Output};

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn doc(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env("BLUE_PATH", repo().join("bidamas"))
        .current_dir(repo())
        .arg("doc")
        .args(args)
        .output()
        .expect("spawn")
}

fn json_lines(o: &Output) -> Vec<serde_json::Value> {
    String::from_utf8_lossy(&o.stdout)
        .lines()
        .map(|l| serde_json::from_str(l).unwrap_or_else(|e| panic!("{l}: {e}")))
        .collect()
}

/// A builtin: its signature, doc line and topic from the interpreter's own
/// table, and its example from the conformance row that specifies it.
///
/// Red run (2026-10-10): `rows_for` answering `[]` in doc.b: `example` was
/// null and the last assertion failed.
#[test]
fn a_builtin_has_its_signature_doc_tier_and_spec_row_example() {
    let o = doc(&["blue::length", "--json"]);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    let found = json_lines(&o);
    assert_eq!(found.len(), 1, "{found:?}");
    let e = &found[0];
    assert_eq!(e["name"], "length");
    assert_eq!(e["namespace"], "blue");
    assert_eq!(e["tier"], "builtin");
    assert_eq!(e["signature"], "length(xs)");
    assert!(e["doc"][0].as_str().is_some_and(|d| !d.is_empty()), "{e}");
    assert!(
        e["example"]["from"]
            .as_str()
            .is_some_and(|f| f.starts_with("spec row ")),
        "{e}"
    );
}

/// A bidama's definition: qualified signature, the comment above it, and
/// the first of its package's tests that calls it.
///
/// Red run (2026-10-10): `test_example` answering nil in doc.b: `example`
/// was null.
#[test]
fn a_bidama_definition_has_its_doc_namespace_and_test_example() {
    let o = doc(&["retsu::size", "--json"]);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    let e = &json_lines(&o)[0];
    assert_eq!(e["name"], "retsu::size");
    assert_eq!(e["namespace"], "retsu");
    assert_eq!(e["tier"], "qualified");
    assert_eq!(e["signature"], "retsu::size(xs)");
    assert_eq!(
        e["doc"][0],
        "size: Total length: nil counts as empty rather than erroring."
    );
    assert!(
        e["example"]["code"].as_array().is_some_and(|c| c
            .iter()
            .any(|l| l.as_str().is_some_and(|l| l.contains("size(")))),
        "{e}"
    );
}

/// A bare name answers every builtin and bidama defining it; with `--file`
/// each answer's tier is how that file reaches it.
#[test]
fn a_bare_name_answers_every_owner_and_file_gives_the_tier() {
    let o = doc(&["first", "--json"]);
    let names: Vec<String> = json_lines(&o)
        .iter()
        .map(|e| e["name"].as_str().unwrap_or_default().to_string())
        .collect();
    assert!(names.contains(&"retsu::first".to_string()), "{names:?}");
    assert!(names.contains(&"first".to_string()), "{names:?}");

    let o = doc(&["first", "--file", "bidamas/moji/moji.b", "--json"]);
    let found = json_lines(&o);
    let retsu = found
        .iter()
        .find(|e| e["name"] == "retsu::first")
        .expect("retsu::first");
    assert_eq!(retsu["tier"], "imported", "moji lists first from retsu");
}

/// A name nothing defines is a failure that says where it looked.
///
/// Red run (2026-10-10): doc.b's not-found branch answering true: exit 0.
#[test]
fn an_unknown_name_fails_naming_where_it_looked() {
    let o = doc(&["no_such_definition_anywhere"]);
    assert_eq!(o.status.code(), Some(1));
    let err = String::from_utf8_lossy(&o.stderr);
    assert!(
        err.contains("no `no_such_definition_anywhere` in the builtins and"),
        "{err}"
    );
    assert!(o.stdout.is_empty());
}

/// A bidama's name lists the package: its gloss and every definition.
#[test]
fn a_package_name_lists_the_package() {
    let o = doc(&["kazu", "--json"]);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    let p = &json_lines(&o)[0];
    assert_eq!(p["package"], "kazu");
    assert!(
        p["gloss"].as_str().is_some_and(|g| g.starts_with("kazu")),
        "{p}"
    );
    assert!(
        p["definitions"]
            .as_array()
            .is_some_and(|d| d.iter().any(|d| d["name"] == "abs")),
        "{p}"
    );
}
