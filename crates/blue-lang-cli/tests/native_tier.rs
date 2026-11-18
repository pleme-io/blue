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

fn profile(f: &Fixture, hex: &str, mean_ns: u64) {
    let dir = f.dir.join("cache").join("blue").join("profile").join("v1");
    std::fs::create_dir_all(&dir).expect("profile dir");
    std::fs::write(dir.join(hex), format!("{mean_ns} 1\n")).expect("profile");
}

#[test]
fn a_library_makes_a_definition_hot_from_a_far_lower_mean_than_a_process() {
    let f = fixture("threshold");
    let keys = hashes(&f.program);
    let quick = keys
        .iter()
        .find(|(k, _)| k == "%root/quick")
        .expect("quick")
        .1
        .clone();
    profile(&f, &quick, 5_000_000);
    let slow_cold = "4499998500000";
    assert_eq!(
        run(&f, None),
        format!("[{slow_cold}, 2]"),
        "5 ms is under the 20 ms a process start needs"
    );
    library(
        &f.dir.join("shared"),
        &quick,
        "unsafe { out.write(13) };\n    0",
    );
    profile(&f, &quick, 5_000_000);
    assert_eq!(
        run(&f, None),
        "[7, 13]",
        "with a library, 5 ms is past the 0.2 ms the in-process call needs (and slow, timed by the first run, is hot)"
    );
    profile(&f, &quick, 100_000);
    assert_eq!(
        run(&f, None),
        "[7, 2]",
        "0.1 ms stays in the interpreter even with a library"
    );
    let _ = std::fs::remove_dir_all(&f.dir);
}

#[test]
fn a_bool_crosses_the_seam_as_one_or_zero_both_ways() {
    let dir = std::env::temp_dir().join(format!("blue-native-tier-bool-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch");
    let program = dir.join("p.b");
    std::fs::write(
        &program,
        "def small(n: Int) -> Bool\n  n < 3\nend\n\ndef pick(b: Bool, x: Int) -> Int\n  if b\n    x\n  else\n    0\n  end\nend\n\ndef main()\n  write_stdout(to_s([small(1), pick(true, 7)]))\nend\n",
    )
    .expect("program");
    let shared = dir.join("shared");
    for (key, hex) in hashes(&program) {
        match key.as_str() {
            "%root/small" => {
                artifact(&shared, &hex, 1);
                library(&shared, &hex, "unsafe { out.write(0) };\n    0");
            }
            "%root/pick" => {
                artifact(&shared, &hex, 99);
                library(
                    &shared,
                    &hex,
                    "let flag = unsafe { *args };\n    unsafe { out.write(if flag == 1 { 40 } else { -1 }) };\n    0",
                );
            }
            _ => {}
        }
    }
    let f = Fixture { dir, program };
    assert_eq!(run(&f, Some("off")), "[true, 7]");
    assert_eq!(
        run(&f, Some("on")),
        "[false, 40]",
        "the library's 0 is false, and true reaches it as 1"
    );
    let _ = std::fs::remove_dir_all(&f.dir);
}

#[test]
fn a_loop_of_tail_calls_is_one_outermost_call_in_the_profile() {
    let dir = std::env::temp_dir().join(format!("blue-native-tier-tail-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch");
    let program = dir.join("p.b");
    std::fs::write(
        &program,
        "def down(n)\n  if n == 0\n    0\n  else\n    down(n - 1)\n  end\nend\n\ndef main()\n  write_stdout(to_s([down(10_000), down(5)]))\nend\n",
    )
    .expect("program");
    let hex = hashes(&program)
        .into_iter()
        .find(|(k, _)| k == "%root/down")
        .expect("down")
        .1;
    artifact(&dir.join("shared"), &hex, 99);
    let f = Fixture { dir, program };
    assert_eq!(run(&f, None), "[0, 0]");
    let recorded = std::fs::read_to_string(
        f.dir
            .join("cache")
            .join("blue")
            .join("profile")
            .join("v1")
            .join(&hex),
    )
    .expect("a profile");
    assert_eq!(
        recorded.split_whitespace().nth(1),
        Some("2"),
        "two outermost calls, each a loop of tail calls: {recorded}"
    );
    let _ = std::fs::remove_dir_all(&f.dir);
}

#[test]
fn a_float_crosses_the_seam_as_its_bits_both_ways() {
    let dir = std::env::temp_dir().join(format!("blue-native-tier-float-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch");
    let program = dir.join("p.b");
    std::fs::write(
        &program,
        "def half(x: Float) -> Float\n  x * 0.5\nend\n\ndef main()\n  write_stdout(to_s(half(5.0)))\nend\n",
    )
    .expect("program");
    let shared = dir.join("shared");
    let five = 5.0f64.to_bits().cast_signed();
    let answer = 1.25f64.to_bits().cast_signed();
    for (key, hex) in hashes(&program) {
        if key == "%root/half" {
            artifact(&shared, &hex, 99);
            library(
                &shared,
                &hex,
                &format!(
                    "let x = unsafe {{ *args }};\n    unsafe {{ out.write(if x == {five} {{ {answer} }} else {{ -1 }}) }};\n    0"
                ),
            );
        }
    }
    let f = Fixture { dir, program };
    assert_eq!(run(&f, Some("off")), "2.5");
    assert_eq!(
        run(&f, Some("on")),
        "1.25",
        "5.0 reaches the library as its bits, and the bits it answers are a Float"
    );
    let _ = std::fs::remove_dir_all(&f.dir);
}

#[test]
fn a_library_that_does_not_load_keeps_the_process_threshold() {
    let f = fixture("unloadable");
    let quick = hashes(&f.program)
        .into_iter()
        .find(|(k, _)| k == "%root/quick")
        .expect("quick")
        .1;
    let dir = f.dir.join("shared").join("native").join("v1").join(&quick);
    std::fs::write(dir.join("def.so"), "not a library").expect("a file that is no library");
    profile(&f, &quick, 5_000_000);
    assert_eq!(
        run(&f, None),
        "[4499998500000, 2]",
        "a static blue, or a broken file, loads no library: 5 ms stays under the 20 ms a process needs"
    );
    let _ = std::fs::remove_dir_all(&f.dir);
}

#[test]
fn a_test_run_seeds_the_profile_only_for_what_it_ran_hot() {
    let dir = std::env::temp_dir().join(format!("blue-native-tier-seed-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch");
    let program = dir.join("p.b");
    std::fs::write(
        &program,
        "@doc \"\"\"\nslow: a sum that takes a while.\n\n    slow(300_000) #=> 44999850000\n\"\"\"\ndef slow(n)\n  reduce((a, x) -> a + x, 0, range(n))\nend\n\n@doc \"\"\"\nquick: one more.\n\n    quick(1) #=> 2\n\"\"\"\ndef quick(n)\n  n + 1\nend\n",
    )
    .expect("program");
    let shared = dir.join("shared");
    let mut hexes = Vec::new();
    for (key, hex) in hashes(&program) {
        if key == "%root/slow" || key == "%root/quick" {
            artifact(&shared, &hex, 7);
            library(&shared, &hex, "unsafe { out.write(7) };\n    0");
            hexes.push((key, hex));
        }
    }
    let out = blue()
        .env("BLUE_CACHE_SHARED", &shared)
        .env("XDG_CACHE_HOME", dir.join("cache"))
        .args(["test", "--no-cache"])
        .arg(&program)
        .output()
        .expect("spawn blue test");
    assert!(
        out.status.success(),
        "the tests answer as the interpreter does, the tier answering none: {}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    let profiled = |hex: &str| dir.join("cache/blue/profile/v1").join(hex).exists();
    for (key, hex) in &hexes {
        match key.as_str() {
            "%root/slow" => assert!(profiled(hex), "slow ran hot in its doctest"),
            _ => assert!(
                !profiled(hex),
                "quick ran cold, so the first real run times it"
            ),
        }
    }
    let again = blue()
        .env("BLUE_CACHE_SHARED", &shared)
        .env("XDG_CACHE_HOME", dir.join("cache"))
        .args(["test", "--no-cache"])
        .arg(&program)
        .output()
        .expect("spawn blue test");
    assert!(
        again.status.success(),
        "slow is hot now, and a test still runs it in the interpreter, never the artifact's 7: {}",
        String::from_utf8_lossy(&again.stdout)
    );
    let _ = std::fs::remove_dir_all(&dir);
}
