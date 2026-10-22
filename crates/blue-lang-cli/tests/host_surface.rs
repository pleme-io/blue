use std::path::PathBuf;
use std::process::{Command, Output};

const PROGRAM: &str = "def go()\n  ledger_add(\"a\")\n  ledger_count\nend\n";

const SURFACE: &str = r#"{
  "functions": [
    { "name": "ledger_add", "params": ["entry"], "required": 1, "doc": "" },
    { "name": "ledger_count", "params": [], "required": 0, "doc": "" }
  ]
}
"#;

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-host-surface-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("rules")).expect("scratch dir");
    dir
}

fn check(file: &std::path::Path) -> Output {
    Command::new(env!("CARGO_BIN_EXE_blue"))
        .args(["check", file.to_str().expect("utf-8 path")])
        .output()
        .expect("spawn blue")
}

fn text(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

#[test]
fn a_host_program_checks_against_the_nearest_surface_file() {
    let dir = scratch("found");
    let file = dir.join("rules").join("go.b");
    std::fs::write(&file, PROGRAM).expect("program");

    let without = check(&file);
    assert!(!without.status.success(), "{}", text(&without));
    assert!(text(&without).contains("B0001"), "{}", text(&without));

    std::fs::write(dir.join("blue-host.json"), SURFACE).expect("surface");
    let with = check(&file);
    assert!(with.status.success(), "{}", text(&with));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_nullary_host_function_is_called_bare() {
    let dir = scratch("nullary");
    std::fs::write(dir.join("blue-host.json"), SURFACE).expect("surface");
    let file = dir.join("rules").join("go.b");
    std::fs::write(&file, "def go()\n  ledger_count()\nend\n").expect("program");
    let o = check(&file);
    assert!(text(&o).contains("B0023"), "{}", text(&o));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_malformed_surface_file_is_refused_by_name() {
    let dir = scratch("malformed");
    std::fs::write(dir.join("blue-host.json"), "{\"functions\": [{}]}").expect("surface");
    let file = dir.join("rules").join("go.b");
    std::fs::write(&file, PROGRAM).expect("program");
    let o = check(&file);
    assert!(!o.status.success());
    assert!(text(&o).contains("blue-host.json"), "{}", text(&o));
    let _ = std::fs::remove_dir_all(&dir);
}
