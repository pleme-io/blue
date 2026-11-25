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
    assert_eq!(e["signature"], "length(seq)");
    assert!(e["doc"][0].as_str().is_some_and(|d| !d.is_empty()), "{e}");
    assert!(
        e["example"]["from"]
            .as_str()
            .is_some_and(|f| f.starts_with("spec row ")),
        "{e}"
    );
}

#[test]
fn the_rows_door_reads_every_program_the_conformance_runner_reads() {
    let o = doc(&["--rows"]);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    let rows: Vec<serde_json::Value> = serde_json::from_slice(&o.stdout).expect("a JSON array");
    let deep = rows
        .iter()
        .find(|r| r["id"] == "fn.deep_recursion")
        .unwrap_or_else(|| panic!("no fn.deep_recursion among {} rows", rows.len()));
    assert!(
        deep["src"]
            .as_str()
            .is_some_and(|s| s.contains("def depth(n)") && s.ends_with("depth(100000)")),
        "{deep}"
    );
    assert!(rows.len() > 1000, "only {} rows", rows.len());
    let marks: Vec<&serde_json::Value> = rows
        .iter()
        .flat_map(|r| {
            r["marks"]
                .as_array()
                .unwrap_or_else(|| panic!("row {} carries no marks: {r}", r["id"]))
        })
        .collect();
    assert!(!marks.is_empty(), "no row carries a mark");
    for m in marks {
        assert!(
            ["pending", "flaky"].contains(&m["mark"].as_str().unwrap_or_default())
                && m["gap"].as_str().is_some_and(|g| g.starts_with('G'))
                && (m["on"].is_null() || m["on"].is_string()),
            "{m}"
        );
    }
}

#[test]
fn every_example_of_the_doc_program_holds() {
    let o = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env("BLUE_PATH", repo().join("bidamas"))
        .env("BLUE_TEST_CACHE", "off")
        .current_dir(repo())
        .args(["test", "crates/blue-lang-cli/blue/doc.b"])
        .output()
        .expect("spawn");
    let out = String::from_utf8_lossy(&o.stdout);
    assert!(
        o.status.success() && out.contains(" 0 failed"),
        "{out}{}",
        String::from_utf8_lossy(&o.stderr)
    );
}

#[test]
fn a_builtin_takes_its_example_only_from_a_row_main_holds() {
    let o = doc(&["--rows"]);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    let rows: Vec<serde_json::Value> = serde_json::from_slice(&o.stdout).expect("a JSON array");
    let unheld = |r: &serde_json::Value| {
        r["marks"]
            .as_array()
            .is_some_and(|ms| ms.iter().any(|m| m["on"].is_null() || m["on"] == "walker"))
    };
    let names: std::collections::BTreeSet<String> = rows
        .iter()
        .filter(|r| unheld(r))
        .flat_map(|r| r["covers"].as_array().cloned().unwrap_or_default())
        .filter_map(|c| c.as_str()?.strip_prefix("builtin:").map(str::to_owned))
        .collect();
    for name in &names {
        let o = doc(&[format!("blue::{name}").as_str(), "--json"]);
        assert!(
            o.status.success(),
            "{name}: {}",
            String::from_utf8_lossy(&o.stderr)
        );
        let e = &json_lines(&o)[0];
        if let Some(from) = e["example"]["from"].as_str() {
            let id = from.strip_prefix("spec row ").unwrap_or(from);
            let row = rows.iter().find(|r| r["id"] == id);
            assert!(
                row.is_some_and(|r| !unheld(r)),
                "{name}: its example is {from}, which main does not hold: {e}"
            );
        }
    }
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

#[test]
fn the_derived_view_names_the_host_capabilities_a_definition_reaches() {
    let o = doc(&["read", "--file", "bidamas/settei/settei.b", "--derived"]);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    let v = &json_lines(&o)[0];
    assert!(
        v["reach"]
            .as_array()
            .is_some_and(|r| r.iter().any(|c| c == "filesystem")),
        "{v}"
    );
    assert!(
        v["lines"].as_array().is_some_and(|ls| ls.iter().any(|l| l
            .as_str()
            .is_some_and(|l| l.starts_with("reaches ") && l.contains("`filesystem`")))),
        "{v}"
    );

    let o = doc(&["size", "--file", "bidamas/retsu/retsu.b", "--derived"]);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    let v = &json_lines(&o)[0];
    assert_eq!(v["reach"], serde_json::json!([]), "{v}");
    assert!(
        v["lines"]
            .as_array()
            .is_some_and(|ls| ls.iter().any(|l| l == "pure: reaches no host capability")),
        "{v}"
    );
}

#[test]
fn a_bidama_definition_lists_the_defaults_it_gets_and_what_the_next_waits_on() {
    let fired = doc(&["kazu::int_sqrt_fix"]);
    let text = String::from_utf8_lossy(&fired.stdout);
    assert!(
        fired.status.success(),
        "{}",
        String::from_utf8_lossy(&fired.stderr)
    );
    assert!(
        text.contains("default R2: its repeated calls are answered from a table"),
        "{text}"
    );
    let waiting = doc(&["junjo::sort_by"]);
    let text = String::from_utf8_lossy(&waiting.stdout);
    assert!(text.contains("R2 waits on: it is not pure"), "{text}");
    let json = json_lines(&doc(&["kazu::int_sqrt_fix", "--json"]));
    let rules = json[0]["defaults"].as_array().expect("defaults");
    assert!(
        rules
            .iter()
            .any(|r| r["rule"] == "R2" && r["fires"] == true),
        "{rules:?}"
    );
}
