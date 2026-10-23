//! **`blue migrate` makes a file's cross-bidama references explicit, and
//! proves it changed nothing.** A three-bidama distribution in a temporary
//! directory: `mk_c` uses `mk_b`, and reaches `mk_a`'s `one` only because
//! `mk_b` loaded it. The migration must list both names, relock so `mk_c`'s
//! lock derives `mk_a`, leave B0012 with nothing to report, keep the
//! package's tests passing, and be a no-op the second time.
//!
//! Red run (2026-09-29): the proof in `blue/migrate.b` made to compare the
//! wrong trees (`flat` after against `ns` before): the run refuses,
//! `refused …/mk_c.b: its resolved tree changed; restored`, and this test
//! fails.

use std::path::{Path, PathBuf};
use std::process::Command;

fn blue(dist: &Path) -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env("BLUE_PATH", dist)
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER");
    c
}

fn package(dist: &Path, name: &str, needs: &[&str], src: &str) -> PathBuf {
    let dir = dist.join(name);
    std::fs::create_dir_all(&dir).expect("mkdir");
    let mut bf = format!("package(\"{name}\", \"0.1.0\")\n");
    for n in needs {
        bf.push_str(&format!("needs(\"{n}\", \"^0.1\")\n"));
    }
    std::fs::write(dir.join("Bluefile"), bf).expect("write Bluefile");
    let file = dir.join(format!("{name}.b"));
    std::fs::write(&file, src).expect("write source");
    file
}

fn run(cmd: &mut Command) -> (bool, String, String) {
    let out = cmd.output().expect("spawn");
    (
        out.status.success(),
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

#[test]
fn a_transitive_reference_is_listed_needed_and_proven() {
    let root = std::env::temp_dir().join(format!("blue-migrate-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dist = root.join("bidamas");
    package(&dist, "mk_a", &[], "def one()\n  1\nend\n");
    package(
        &dist,
        "mk_b",
        &["mk_a"],
        "use(\"mk_a\", [:one])\n\ndef two()\n  one() + one()\nend\n",
    );
    let c = package(
        &dist,
        "mk_c",
        &["mk_b"],
        "use(\"mk_b\")\n\ndef three()\n  two + one\nend\n\ntest \"three\"\n  assert three == 3\nend\n",
    );
    for p in ["mk_a", "mk_b", "mk_c"] {
        let (ok, _, err) = run(blue(&dist).arg("lock").arg(dist.join(p)));
        assert!(ok, "lock {p}: {err}");
    }

    let (ok, out, err) = run(blue(&dist).arg("migrate").arg(&c));
    assert!(ok, "{out}{err}");
    assert!(out.contains("2 name(s) made explicit"), "{out}");
    let src = std::fs::read_to_string(&c).expect("read");
    assert!(
        src.starts_with("use(\"mk_a\", [:one])\nuse(\"mk_b\", [:two])\n"),
        "{src}"
    );
    let lock = std::fs::read_to_string(dist.join("mk_c/Bluefile.lock")).expect("read");
    assert!(lock.contains("\"mk_a\": \"^0.1.0\""), "{lock}");
    let (fresh, _, err) = run(blue(&dist)
        .args(["bluefile", "--confirm"])
        .arg(dist.join("mk_c/Bluefile")));
    assert!(fresh, "the lock must follow the Bluefile: {err}");

    // Nothing is implicit any more, and the package still passes its tests.
    let (ok, json, _) = run(blue(&dist).args(["ast", "--resolved", "--json"]).arg(&c));
    assert!(ok);
    assert!(!json.contains("\"kind\":\"unbound\""), "{json}");
    let (ok, out, err) = run(blue(&dist).arg("test").arg(&c));
    assert!(ok, "{out}{err}");

    // A second run finds nothing to do.
    let (ok, out, err) = run(blue(&dist).arg("migrate").arg(&c));
    assert!(ok, "{err}");
    assert!(out.contains("unchanged"), "{out}");
    let _ = std::fs::remove_dir_all(&root);
}

fn swap_dist(tag: &str, caller: &str) -> (PathBuf, PathBuf, PathBuf) {
    let root = std::env::temp_dir().join(format!("blue-swap-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dist = root.join("bidamas");
    let lib = package(
        &dist,
        "mk_a",
        &[],
        "def apply_all(f, xs)\n  map(f, xs)\nend\n",
    );
    let user = package(&dist, "mk_b", &[], caller);
    for p in ["mk_a", "mk_b"] {
        let (ok, _, err) = run(blue(&dist).arg("lock").arg(dist.join(p)));
        assert!(ok, "lock {p}: {err}");
    }
    (dist, lib, user)
}

const CALLER: &str = "use(\"mk_a\", [:apply_all])

def twice(xs)
  apply_all(
    (x) -> x * 2,
    xs
  )
end

def nested(xs)
  apply_all(
    (s) -> \"a,)#{s}\",
    apply_all(
      (x) -> [x, x],
      xs
    )
  )
end

test \"twice and nested\"
  assert twice([1, 2]) == [2, 4]
  assert nested([1]) == [\"a,)[1, 1]\"]
end
";

#[test]
fn a_swap_rewrites_every_call_and_proves_the_tree_moved_only_that_way() {
    let (dist, lib, user) = swap_dist("ok", CALLER);
    let (ok, out, err) = run(blue(&dist)
        .args(["migrate", "--swap", "mk_a/apply_all"])
        .arg(&user));
    assert!(ok, "{out}{err}");
    assert!(out.contains("swapped"), "{out}");
    assert!(out.contains("3 call(s)"), "{out}");
    let src = std::fs::read_to_string(&user).expect("read");
    assert!(!src.contains("(x) -> x * 2,\n    xs"), "{src}");

    std::fs::write(&lib, "def apply_all(xs, f)\n  map(f, xs)\nend\n").expect("write");
    let (ok, out, err) = run(blue(&dist).arg("test").arg(&user));
    assert!(ok, "{out}{err}");
}

#[test]
fn a_swap_flags_a_comment_inside_a_call_and_leaves_the_file_alone() {
    let caller = "use(\"mk_a\", [:apply_all])

def twice(xs)
  apply_all(
    (x) -> x * 2, # keep this
    xs
  )
end
";
    let (dist, _, user) = swap_dist("comment", caller);
    let (ok, out, err) = run(blue(&dist)
        .args(["migrate", "--swap", "mk_a/apply_all"])
        .arg(&user));
    assert!(!ok, "{out}{err}");
    assert!(out.contains("flagged"), "{out}");
    assert!(out.contains("a comment inside the call"), "{out}");
    assert_eq!(std::fs::read_to_string(&user).expect("read"), caller);
}

#[test]
fn a_swap_flags_a_splat_call_and_leaves_the_file_alone() {
    let caller = "use(\"mk_a\", [:apply_all])

def twice(xs)
  args = [(x) -> x * 2, xs]
  apply_all(*args)
end
";
    let (dist, _, user) = swap_dist("pipe", caller);
    let (ok, out, err) = run(blue(&dist)
        .args(["migrate", "--swap", "mk_a/apply_all"])
        .arg(&user));
    assert!(!ok, "{out}{err}");
    assert!(out.contains("flagged"), "{out}");
    assert_eq!(std::fs::read_to_string(&user).expect("read"), caller);
}

#[test]
fn a_swap_leaves_a_file_that_calls_nothing_it_names_unchanged() {
    let (dist, _, user) = swap_dist("none", "def one()\n  1\nend\n");
    let (ok, out, err) = run(blue(&dist)
        .args(["migrate", "--swap", "mk_a/apply_all"])
        .arg(&user));
    assert!(ok, "{out}{err}");
    assert!(out.contains("unchanged"), "{out}");
}
