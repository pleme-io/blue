use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const SLOW: &str = "def slow(n)\n  reduce((a, x) -> a + x, 0, range(n))\nend\n\ndef main()\n  write_stdout(to_s(slow(3_000_000)))\nend\n";

const QUICK: &str = "def main()\n  write_stdout(to_s(1 + 1))\nend\n";

struct Node {
    dir: PathBuf,
}

impl Drop for Node {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn node(name: &str, tier: bool) -> Node {
    let dir = std::env::temp_dir().join(format!("blue-native-build-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("cache")).expect("cache");
    if tier {
        std::fs::create_dir_all(dir.join("cache/blue/native/v1")).expect("tier");
    }
    let builder = dir.join("builder");
    std::fs::write(
        &builder,
        format!("#!/bin/sh\ntouch {}\n", dir.join("started").display()),
    )
    .expect("builder");
    std::fs::set_permissions(&builder, std::fs::Permissions::from_mode(0o755)).expect("chmod");
    Node { dir }
}

fn run(n: &Node, src: &str, native: Option<&str>) {
    let program = n.dir.join("p.b");
    std::fs::write(&program, src).expect("program");
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_NATIVE")
        .env_remove("BLUE_CACHE_SHARED")
        .env("BLUE_MEMO", "off")
        .env("XDG_CACHE_HOME", n.dir.join("cache"))
        .env("BLUE_NATIVE_BUILDER", n.dir.join("builder"))
        .args(["run", "--quiet"])
        .arg(&program);
    if let Some(v) = native {
        c.env("BLUE_NATIVE", v);
    }
    let out = c.output().expect("spawn blue run");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

fn requests(n: &Node) -> Vec<String> {
    let dir = n.dir.join("cache/blue/native/wanted");
    let mut keys: Vec<String> = std::fs::read_dir(&dir)
        .map(|d| {
            d.flatten()
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .collect()
        })
        .unwrap_or_default();
    keys.sort();
    keys
}

fn started(n: &Node) -> bool {
    let flag = n.dir.join("started");
    let until = std::time::Instant::now() + std::time::Duration::from_secs(10);
    while std::time::Instant::now() < until {
        if flag.exists() {
            return true;
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    false
}

fn holds(path: &Path, text: &str) -> bool {
    std::fs::read_to_string(path).is_ok_and(|t| t.contains(text))
}

#[test]
fn a_slow_run_with_a_native_tier_asks_once_for_its_program_and_starts_the_builder() {
    let n = node("slow", true);
    run(&n, SLOW, None);
    let keys = requests(&n);
    assert_eq!(keys.len(), 1, "{keys:?}");
    assert!(holds(
        &n.dir.join("cache/blue/native/wanted").join(&keys[0]),
        "p.b"
    ));
    assert!(
        started(&n),
        "the builder BLUE_NATIVE_BUILDER names was not started"
    );
    std::fs::remove_file(n.dir.join("started")).expect("reset");
    run(&n, SLOW, None);
    assert_eq!(requests(&n), keys, "the same text is not asked for twice");
    std::fs::write(
        n.dir
            .join("cache/blue/native/wanted")
            .join(format!("{}.done", keys[0])),
        "",
    )
    .expect("done");
    std::fs::remove_file(n.dir.join("cache/blue/native/wanted").join(&keys[0])).expect("taken");
    run(&n, SLOW, None);
    assert_eq!(
        requests(&n),
        [format!("{}.done", keys[0])],
        "a done text is not asked for again"
    );
    run(&n, &format!("{SLOW}\n"), None);
    assert_eq!(requests(&n).len(), 2, "an edited text is asked for");
}

#[test]
fn no_request_without_a_tier_for_a_quick_run_or_with_the_tier_off() {
    let bare = node("bare", false);
    run(&bare, SLOW, None);
    assert!(requests(&bare).is_empty(), "no native tier on the node");
    let quick = node("quick", true);
    run(&quick, QUICK, None);
    assert!(requests(&quick).is_empty(), "a run under 20 ms");
    let off = node("off", true);
    run(&off, SLOW, Some("off"));
    assert!(requests(&off).is_empty(), "BLUE_NATIVE=off");
}
