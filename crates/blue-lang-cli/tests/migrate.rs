//! **`blue migrate` makes a file's cross-bidama references explicit, and
//! proves it changed nothing.** A three-bidama distribution in a temporary
//! directory: `mk_c` uses `mk_b`, and reaches `mk_a`'s `one` only because
//! `mk_b` loaded it. The migration must list both names, add `mk_a` to
//! `mk_c`'s Bluefile and lock, leave B0012 with nothing to report, keep the
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
    package(&dist, "mk_b", &["mk_a"], "use(\"mk_a\")\n\ndef two()\n  one() + one()\nend\n");
    let c = package(
        &dist,
        "mk_c",
        &["mk_b"],
        "use(\"mk_b\")\n\ndef three()\n  two() + one()\nend\n\ntest \"three\"\n  assert three() == 3\nend\n",
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
    let bf = std::fs::read_to_string(dist.join("mk_c/Bluefile")).expect("read");
    assert!(bf.contains("needs(\"mk_a\", \"^0.1\")"), "{bf}");
    let (fresh, _, err) = run(
        blue(&dist)
            .args(["bluefile", "--confirm"])
            .arg(dist.join("mk_c/Bluefile")),
    );
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
