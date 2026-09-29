//! **`blue check --format json` is a stable interface.** A tool — an editor,
//! CI, an agent repairing its own code — parses these field names, so a rename
//! must be a red test, not a silent break. This pins the exact bytes for a
//! fixture that exercises every field: an error with suggestions, a warning
//! with a machine-applicable fix, and a waived diagnostic. And every field
//! name the output uses must be documented in `docs/DIAGNOSTICS.md`.
//!
//! Red run (2026-09-29): `JsonDiagnostic::slug` renamed `rule` —
//! `the JSON output changed` with the first line differing at `"rule"`.

use std::path::PathBuf;
use std::process::Command;

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER");
    c
}

fn fixture(name: &str, src: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-check-json-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("mkdir");
    let p = dir.join(format!("{name}.b"));
    std::fs::write(&p, src).expect("write");
    p
}

const SRC: &str = "\
def f(xs)
  lenght(xs)
end

def g(x, y)
  x
end

# waive B0002: the callback shape is fixed
def h(event, ctx)
  event
end
";

/// The exact output, with the fixture's path written `F`.
const EXPECTED: &str = r#"{"code":"B0001","slug":"unbound-name","severity":"error","message":"unbound name `lenght`","file":"F","line":2,"column":3,"end_line":2,"end_column":9,"byte_start":12,"byte_end":18,"help":"did you mean `length` (builtin)?","related":[],"fixes":[{"message":"replace with `length` (builtin)","applicability":"maybe-incorrect","edits":[{"file":"F","line":2,"column":3,"end_line":2,"end_column":9,"byte_start":12,"byte_end":18,"original":"lenght","replacement":"length"}]}],"waiver":null}
{"code":"B0002","slug":"unused-binding","severity":"warning","message":"parameter `y` is never read","file":"F","line":5,"column":10,"end_line":5,"end_column":11,"byte_start":37,"byte_end":38,"help":"rename it `_y` to say it is deliberately unused, or remove it","related":[],"fixes":[{"message":"rename to `_y`","applicability":"machine-applicable","edits":[{"file":"F","line":5,"column":10,"end_line":5,"end_column":11,"byte_start":37,"byte_end":38,"original":"y","replacement":"_y"}]}],"waiver":null}
{"code":"B0002","slug":"unused-binding","severity":"warning","message":"parameter `ctx` is never read","file":"F","line":10,"column":14,"end_line":10,"end_column":17,"byte_start":105,"byte_end":108,"help":"rename it `_ctx` to say it is deliberately unused, or remove it","related":[],"fixes":[{"message":"rename to `_ctx`","applicability":"machine-applicable","edits":[{"file":"F","line":10,"column":14,"end_line":10,"end_column":17,"byte_start":105,"byte_end":108,"original":"ctx","replacement":"_ctx"}]}],"waiver":{"reason":"the callback shape is fixed","line":9}}
"#;

#[test]
fn the_json_output_is_stable() {
    let p = fixture("stable", SRC);
    let out = blue()
        .args(["check", "--format", "json", p.to_str().expect("utf-8")])
        .output()
        .expect("spawn");
    assert_eq!(
        out.status.code(),
        Some(1),
        "an error is present, so the exit is 1"
    );
    let got = String::from_utf8(out.stdout)
        .expect("utf-8")
        .replace(p.to_str().expect("utf-8"), "F");
    assert_eq!(got, EXPECTED, "the JSON output changed");
    // Every line is one JSON object.
    for line in got.lines() {
        let v: serde_json::Value = serde_json::from_str(line).expect("each line parses");
        assert!(v.is_object());
    }
}

/// A syntax error comes out in the same shape.
#[test]
fn a_syntax_error_is_a_json_diagnostic_too() {
    let p = fixture("syntax", "def f(\n");
    let out = blue()
        .args(["check", "--format", "json", p.to_str().expect("utf-8")])
        .output()
        .expect("spawn");
    let got = String::from_utf8(out.stdout).expect("utf-8");
    let v: serde_json::Value = serde_json::from_str(got.trim()).expect("one object");
    assert_eq!(v["code"], "B0006");
    assert_eq!(v["line"], 2);
}

/// Every key the output uses is documented, and so is every code.
#[test]
fn every_field_and_code_is_documented() {
    let doc = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs/DIAGNOSTICS.md"),
    )
    .expect("docs/DIAGNOSTICS.md");
    let mut keys = std::collections::BTreeSet::new();
    for line in EXPECTED.lines() {
        collect_keys(&serde_json::from_str(line).expect("json"), &mut keys);
    }
    let missing: Vec<&String> = keys
        .iter()
        .filter(|k| !doc.contains(&format!("`{k}`")))
        .collect();
    assert!(missing.is_empty(), "undocumented JSON fields: {missing:?}");
    for r in blue_lang_check::RULES {
        assert!(
            doc.contains(r.code.as_str()),
            "{} is not in docs/DIAGNOSTICS.md",
            r.code
        );
    }
}

fn collect_keys(v: &serde_json::Value, out: &mut std::collections::BTreeSet<String>) {
    match v {
        serde_json::Value::Object(m) => {
            for (k, v) in m {
                out.insert(k.clone());
                collect_keys(v, out);
            }
        }
        serde_json::Value::Array(xs) => xs.iter().for_each(|x| collect_keys(x, out)),
        _ => {}
    }
}

/// `--fix` applies the machine-applicable fixes, leaves the suggestions, and
/// re-checks: the unbound name remains, the unused parameters are renamed.
#[test]
fn fix_applies_only_machine_applicable_fixes() {
    let p = fixture("fix", SRC);
    let out = blue()
        .args(["check", "--fix", p.to_str().expect("utf-8")])
        .output()
        .expect("spawn");
    let after = std::fs::read_to_string(&p).expect("read");
    assert!(
        after.contains("lenght(xs)"),
        "a maybe-incorrect suggestion was applied:\n{after}"
    );
    assert!(after.contains("def g(x, _y)"), "{after}");
    // The waived one stays as written: a waived diagnostic is not reported, so
    // it offers nothing to fix.
    assert!(after.contains("def h(event, ctx)"), "{after}");
    let err = String::from_utf8(out.stderr).expect("utf-8");
    assert!(err.contains("applied 1 fix(es)"), "{err}");
    assert!(
        err.contains("B0001"),
        "the re-check still reports the unbound name: {err}"
    );
    assert_eq!(out.status.code(), Some(1));
}
