//! **`blue ast --resolved --json` is a stable interface**: the migration tool
//! and any outside repository proving its own migration read
//! these fields. This pins the exact output for a fixture with one reference
//! of each kind a program can make — a program definition, a builtin, and an
//! unbound name — and that every field is documented in `docs/DIAGNOSTICS.md`.
//!
//! Red run (2026-09-29): `ReferenceJson::written` renamed `symbol` —
//! `the JSON output changed`.

use std::path::PathBuf;
use std::process::Command;

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER");
    c
}

const SRC: &str = "\
def twice(x)
  x + x
end

twice(size([1]))

# waive B0001: the fixture needs an unbound reference
def g()
  nope
end
";

const EXPECTED: &str = r#"{"namespace":null,"flat":["(define (%root/twice x) (+ x x))","(%root/twice (size (list 1)))","(define (%root/g) nope)"],"ns":["(define (%root/twice x) (+ x x))","(%root/twice (size (list 1)))","(define (%root/g) nope)"],"references":[{"file":"F","line":2,"column":5,"end_line":2,"end_column":6,"byte_start":17,"byte_end":18,"top_level":0,"written":"+","opaque":false,"flat":{"kind":"builtin","namespace":null,"name":"+","key":"+"},"ns":{"kind":"builtin","namespace":null,"name":"+","key":"+"}},{"file":"F","line":5,"column":1,"end_line":5,"end_column":6,"byte_start":26,"byte_end":31,"top_level":1,"written":"twice","opaque":false,"flat":{"kind":"def","namespace":null,"name":"twice","key":"%root/twice"},"ns":{"kind":"def","namespace":null,"name":"twice","key":"%root/twice"}},{"file":"F","line":5,"column":7,"end_line":5,"end_column":11,"byte_start":32,"byte_end":36,"top_level":1,"written":"size","opaque":false,"flat":{"kind":"unbound","namespace":null,"name":null,"key":null},"ns":{"kind":"unbound","namespace":null,"name":null,"key":null}},{"file":"F","line":5,"column":12,"end_line":5,"end_column":13,"byte_start":37,"byte_end":38,"top_level":1,"written":"list","opaque":false,"flat":{"kind":"builtin","namespace":null,"name":"list","key":"list"},"ns":{"kind":"builtin","namespace":null,"name":"list","key":"list"}},{"file":"F","line":9,"column":3,"end_line":9,"end_column":7,"byte_start":108,"byte_end":112,"top_level":2,"written":"nope","opaque":false,"flat":{"kind":"unbound","namespace":null,"name":null,"key":null},"ns":{"kind":"unbound","namespace":null,"name":null,"key":null}}],"imports":[],"first_line":1}
"#;

#[test]
fn the_resolved_json_is_stable() {
    let dir = std::env::temp_dir().join(format!("blue-ast-resolved-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("mkdir");
    let p: PathBuf = dir.join("f.b");
    std::fs::write(&p, SRC).expect("write");
    let out = blue()
        .args(["ast", "--resolved", "--json", p.to_str().expect("utf-8")])
        .output()
        .expect("spawn");
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    let got = String::from_utf8(out.stdout)
        .expect("utf-8")
        .replace(p.to_str().expect("utf-8"), "F");
    assert_eq!(got, EXPECTED, "the JSON output changed");
}

#[test]
fn every_resolved_json_field_is_documented() {
    let doc = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs/DIAGNOSTICS.md"),
    )
    .expect("docs/DIAGNOSTICS.md");
    let section = doc
        .split("## `blue ast --resolved --json`")
        .nth(1)
        .expect("DIAGNOSTICS.md has a `blue ast --resolved --json` section");
    for field in [
        "namespace", "flat", "ns", "references", "top_level", "written", "opaque", "kind", "name",
        "key", "imports", "package", "names", "first_line",
    ] {
        assert!(
            section.contains(&format!("`{field}`")),
            "`{field}` is not documented in the ast --resolved section"
        );
    }
}
