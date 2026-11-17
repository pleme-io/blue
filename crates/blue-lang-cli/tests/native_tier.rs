use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const PROGRAM: &str = "def slow(n)\n  reduce((a, x) -> a + x, 0, range(n))\nend\n\ndef quick(n)\n  n + 1\nend\n\ndef main()\n  write_stdout(to_s([slow(3_000_000), quick(1)]))\nend\n";

const INTERPRETED: &str = "[4499998500000, 2]";

struct Fixture {
    dir: PathBuf,
    program: PathBuf,
}

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_DOOR")
        .env_remove("BLUE_NATIVE")
        .env_remove("BLUE_CACHE_SHARED");
    c
}

fn hashes(program: &Path) -> Vec<(String, String)> {
    let out = blue()
        .args(["ast", "--resolved", "--defs"])
        .arg(program)
        .output()
        .expect("spawn blue ast");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).expect("defs json");
    v.as_array()
        .expect("a list")
        .iter()
        .map(|d| {
            (
                d["key"].as_str().expect("key").to_string(),
                d["hash"]
                    .as_str()
                    .expect("hash")
                    .trim_start_matches("b3:")
                    .to_string(),
            )
        })
        .collect()
}

fn artifact(root: &Path, hex: &str, answer: i64) {
    let dir = root.join("native").join("v1").join(hex);
    std::fs::create_dir_all(&dir).expect("artifact dir");
    let def = dir.join("def");
    std::fs::write(&def, format!("#!/bin/sh\necho {answer}\n")).expect("artifact");
    std::fs::set_permissions(&def, std::fs::Permissions::from_mode(0o755)).expect("chmod");
}

fn fixture(name: &str) -> Fixture {
    let dir = std::env::temp_dir().join(format!("blue-native-tier-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch");
    let program = dir.join("p.b");
    std::fs::write(&program, PROGRAM).expect("program");
    for (key, hex) in hashes(&program) {
        match key.as_str() {
            "%root/slow" => artifact(&dir.join("shared"), &hex, 7),
            "%root/quick" => artifact(&dir.join("shared"), &hex, 99),
            _ => {}
        }
    }
    Fixture { dir, program }
}

fn run(f: &Fixture, native: Option<&str>) -> String {
    let mut c = blue();
    c.env("BLUE_CACHE_SHARED", f.dir.join("shared"))
        .env("XDG_CACHE_HOME", f.dir.join("cache"))
        .args(["run", "--quiet"])
        .arg(&f.program);
    if let Some(v) = native {
        c.env("BLUE_NATIVE", v);
    }
    let out = c.output().expect("spawn blue run");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

#[test]
fn a_definition_known_to_be_hot_runs_native_by_default_and_a_cold_one_never_does() {
    let f = fixture("hot");
    assert_eq!(run(&f, None), INTERPRETED, "the first run has no profile");
    assert_eq!(
        run(&f, None),
        "[7, 2]",
        "the second run answers the hot definition natively and leaves the cold one"
    );
    assert_eq!(run(&f, Some("off")), INTERPRETED, "BLUE_NATIVE=off");
    assert_eq!(
        run(&f, Some("on")),
        "[7, 99]",
        "BLUE_NATIVE=on answers every call it can"
    );
    let _ = std::fs::remove_dir_all(&f.dir);
}

#[test]
fn a_run_with_no_artifact_takes_no_profile_and_answers_as_before() {
    let f = fixture("none");
    let mut c = blue();
    c.env("XDG_CACHE_HOME", f.dir.join("cache"))
        .args(["run", "--quiet"])
        .arg(&f.program);
    let out = c.output().expect("spawn blue run");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), INTERPRETED);
    assert!(
        !f.dir.join("cache").join("blue").join("profile").exists(),
        "a run with no native tier must not write profiles"
    );
    let _ = std::fs::remove_dir_all(&f.dir);
}

fn library(root: &Path, hex: &str, body: &str) {
    let dir = root.join("native").join("v1").join(hex);
    let src = dir.join("lib.rs");
    std::fs::write(
        &src,
        format!("#[no_mangle]\npub extern \"C\" fn blue_def_entry(args: *const i64, len: usize, out: *mut i64) -> i32 {{\n    let _ = (args, len);\n    {body}\n}}\n"),
    )
    .expect("library source");
    let built = Command::new("rustc")
        .args(["--edition", "2021", "--crate-type", "cdylib", "-o"])
        .arg(dir.join("def.so"))
        .arg(&src)
        .output()
        .expect("spawn rustc");
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
}

#[test]
fn a_definition_with_a_library_is_answered_in_process_and_a_refusal_runs_in_the_interpreter() {
    let f = fixture("library");
    let keys = hashes(&f.program);
    let hex_of = |want: &str| {
        keys.iter()
            .find(|(k, _)| k == want)
            .expect("the definition")
            .1
            .clone()
    };
    let slow = hex_of("%root/slow");
    let quick = hex_of("%root/quick");
    let shared = f.dir.join("shared");
    library(&shared, &slow, "unsafe { out.write(11) };\n    0");
    library(&shared, &quick, "let _ = out;\n    1");
    assert_eq!(
        run(&f, Some("on")),
        "[11, 2]",
        "the library answers over the executable (7), and a library that refuses leaves the call to the interpreter, not to the executable (99)"
    );
    let _ = std::fs::remove_dir_all(&f.dir);
}
