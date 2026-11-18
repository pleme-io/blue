use std::path::{Path, PathBuf};
use std::process::Command;

const PROGRAM: &str = "def slow(n)\n  reduce((a, x) -> a + x, 0, range(n))\nend\n\ndef main()\n  write_stdout(to_s(slow(2_000_000)))\nend\n";

const QUICK: &str =
    "def quick(n)\n  n + 1\nend\n\ndef main()\n  write_stdout(to_s(quick(41)))\nend\n";

struct Ran {
    stdout: String,
    door: String,
}

fn scratch(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("blue-fleet-memo-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).expect("scratch");
    d
}

fn run(program: &Path, cache: &Path, shared: Option<&Path>, memo: Option<&str>) -> Ran {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_DOOR")
        .env_remove("BLUE_MEMO")
        .env_remove("BLUE_NATIVE")
        .env_remove("BLUE_CACHE_SHARED")
        .env("XDG_CACHE_HOME", cache)
        .args(["run", "--quiet", "--door-receipt"])
        .arg(cache.with_extension("door.json"))
        .arg(program);
    if let Some(s) = shared {
        c.env("BLUE_CACHE_SHARED", s);
    }
    if let Some(m) = memo {
        c.env("BLUE_MEMO", m);
    }
    let out = c.output().expect("spawn blue run");
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    assert!(out.status.success(), "{stderr}");
    Ran {
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        door: std::fs::read_to_string(cache.with_extension("door.json")).unwrap_or_default(),
    }
}

fn copy_tree(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).expect("dir");
    for e in std::fs::read_dir(from).expect("read dir") {
        let e = e.expect("entry");
        let dest = to.join(e.file_name());
        if e.file_type().expect("type").is_dir() {
            copy_tree(&e.path(), &dest);
        } else {
            std::fs::copy(e.path(), &dest).expect("copy");
        }
    }
}

#[test]
fn a_costly_stored_result_is_answered_from_the_store_by_default_here_and_on_another_node() {
    let d = scratch("costly");
    let program = d.join("p.b");
    std::fs::write(&program, PROGRAM).expect("program");
    let filled = d.join("filled");
    let first = run(&program, &filled, None, Some("on"));
    assert_eq!(first.stdout, "1999999000000");
    let cold = run(&program, &d.join("empty"), None, None);
    assert_eq!(cold.stdout, first.stdout);
    assert!(!cold.door.contains("the store answers"), "{}", cold.door);
    let warm = run(&program, &filled, None, None);
    assert_eq!(warm.stdout, first.stdout);
    assert!(
        warm.door.contains("the store answers `slow`"),
        "the default run did not plan the store: {}",
        warm.door
    );
    let shelf = d.join("shelf");
    copy_tree(&filled.join("blue").join("memo"), &shelf.join("memo"));
    let other = run(&program, &d.join("other"), Some(&shelf), None);
    assert_eq!(other.stdout, first.stdout);
    assert!(
        other.door.contains("the store answers `slow`"),
        "another node did not plan from the shared root: {}",
        other.door
    );
    let off = run(&program, &filled, None, Some("off"));
    assert!(
        !off.door.contains("the store answers"),
        "BLUE_MEMO=off: {}",
        off.door
    );
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_cheap_stored_result_leaves_the_run_as_it_was() {
    let d = scratch("cheap");
    let program = d.join("q.b");
    std::fs::write(&program, QUICK).expect("program");
    let filled = d.join("filled");
    assert_eq!(run(&program, &filled, None, Some("on")).stdout, "42");
    let again = run(&program, &filled, None, None);
    assert_eq!(again.stdout, "42");
    assert!(
        !again.door.contains("the store answers"),
        "a cheap result planned the store memo: {}",
        again.door
    );
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_slow_program_records_its_pure_results_on_the_next_run_and_answers_from_them_after() {
    let d = scratch("slow");
    let program = d.join("p.b");
    std::fs::write(&program, PROGRAM).expect("program");
    let cache = d.join("cache");
    let first = run(&program, &cache, None, None);
    assert_eq!(first.stdout, "1999999000000");
    assert!(!first.door.contains("the store"), "{}", first.door);
    let second = run(&program, &cache, None, None);
    assert_eq!(second.stdout, first.stdout);
    assert!(
        second
            .door
            .contains("the store records the results of `slow`"),
        "the run after a slow one records: {}",
        second.door
    );
    let third = run(&program, &cache, None, None);
    assert_eq!(third.stdout, first.stdout);
    assert!(
        third.door.contains("the store answers `slow`"),
        "{}",
        third.door
    );
    let quick = d.join("quick.b");
    std::fs::write(&quick, QUICK).expect("program");
    let _ = run(&quick, &d.join("quick"), None, None);
    let again = run(&quick, &d.join("quick"), None, None);
    assert!(
        !again.door.contains("the store"),
        "a quick program is never marked: {}",
        again.door
    );
    let off = d.join("off");
    let _ = run(&program, &off, None, Some("off"));
    let after_off = run(&program, &off, None, None);
    assert!(
        !after_off.door.contains("the store"),
        "BLUE_MEMO=off marks nothing: {}",
        after_off.door
    );
    let _ = std::fs::remove_dir_all(&d);
}
