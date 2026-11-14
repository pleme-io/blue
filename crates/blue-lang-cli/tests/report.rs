use std::path::{Path, PathBuf};
use std::process::Command;

struct Place(PathBuf);

impl Place {
    fn new(name: &str) -> Self {
        let root = std::env::temp_dir().join(format!("blue-report-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join(".git")).expect("scratch dir");
        Self(root)
    }

    fn write(&self, path: &str, text: &str) -> PathBuf {
        let p = self.0.join(path);
        std::fs::create_dir_all(p.parent().expect("parent")).expect("dir");
        std::fs::write(&p, text).expect("write");
        p
    }
}

impl Drop for Place {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn blue(dir: &Path, args: &[&str], env: &[(&str, &str)]) -> (bool, String) {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.args(args)
        .current_dir(dir)
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TEST_TODAY")
        .env("BLUE_TEST_CACHE", "off");
    for (k, v) in env {
        c.env(k, v);
    }
    let out = c.output().expect("blue runs");
    (
        out.status.success(),
        format!(
            "{}{}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        ),
    )
}

const MIXED: &str = "def one()\n  1\nend\n\ntest \"holds\"\n  assert one == 1\nend\n\ntest \"fails\"\n  assert one == 2\nend\n";

/// **`--junit FILE` writes every test of the run as JUnit XML**: a suite per
/// file, a case per test, the failed one with its failure.
///
/// Red run (2026-11-14): `junit::render` answering an empty `testsuites`:
/// `tests="2"` absent.
#[test]
fn junit_names_every_test_and_the_failure() {
    let p = Place::new("junit");
    p.write("t.b", MIXED);
    let xml = p.0.join("report.xml");
    let (ok, out) = blue(&p.0, &["test", "t.b", "--junit", "report.xml"], &[]);
    assert!(!ok, "{out}");
    let text = std::fs::read_to_string(&xml).expect("the report is written");
    assert!(text.starts_with("<?xml"), "{text}");
    assert!(text.contains("tests=\"2\" failures=\"1\""), "{text}");
    assert!(text.contains("name=\"holds\""), "{text}");
    assert!(text.contains("name=\"fails\""), "{text}");
    assert!(text.contains("<failure message="), "{text}");
}

/// **`--shard I/N` splits a tree's files into disjoint shards that together
/// hold it**, and a shard outside 1..N is refused.
#[test]
fn shards_are_disjoint_and_together_hold_the_tree() {
    let p = Place::new("shard");
    for f in ["a", "b", "c", "d", "e"] {
        p.write(
            &format!("{f}.b"),
            &format!("def {f}()\n  1\nend\n\ntest \"{f}\"\n  assert {f} == 1\nend\n"),
        );
    }
    let count = |out: &str| {
        out.lines()
            .filter(|l| l.ends_with(".b: 1 test(s): 1 passed, 0 failed"))
            .count()
    };
    let (ok1, one) = blue(&p.0, &["test", ".", "--shard", "1/2"], &[]);
    let (ok2, two) = blue(&p.0, &["test", ".", "--shard", "2/2"], &[]);
    assert!(ok1 && ok2, "{one}{two}");
    assert_eq!(count(&one) + count(&two), 5, "{one}{two}");
    assert_eq!((count(&one), count(&two)), (3, 2), "{one}{two}");
    for bad in ["0/2", "3/2", "x", "1/0"] {
        let (ok, out) = blue(&p.0, &["test", ".", "--shard", bad], &[]);
        assert!(!ok && out.contains("--shard"), "{bad}: {out}");
    }
}

/// **`--rerun N` fails a test whose verdict differs between runs.**
///
/// Red run (2026-11-14): `flaky` answering none: the run exits 0.
#[test]
fn a_test_that_flips_between_runs_is_flaky() {
    let p = Place::new("flaky");
    let mark = p.0.join("seen");
    p.write(
        "t.b",
        &format!(
            "def mark()\n  \"{}\"\nend\n\ntest \"flips\"\n  seen = path_exists(mark)\n  write_file(mark, \"x\")\n  assert not seen\nend\n",
            mark.display()
        ),
    );
    let (ok, out) = blue(
        &p.0,
        &["test", "t.b", "--rerun", "2"],
        &[("BLUE_TEST_WRITES", "anywhere")],
    );
    assert!(!ok, "{out}");
    assert!(
        out.contains("flaky: t.b: flips passed 1 of 2 runs"),
        "{out}"
    );
    let _ = std::fs::remove_file(&mark);
    let (ok, out) = blue(
        &p.0,
        &["test", "t.b", "--rerun", "1"],
        &[("BLUE_TEST_WRITES", "anywhere")],
    );
    assert!(ok, "one run has nothing to compare: {out}");
}

/// **A quarantine holds a failing test out of the verdict until its date,
/// and no longer.**
///
/// Red run (2026-11-14): `quarantine` holding nothing: `blue test` exits 1
/// before the date.
#[test]
fn a_quarantine_holds_a_failing_test_until_its_date() {
    let p = Place::new("quarantine");
    p.write("checks/t.b", MIXED);
    p.write(
        "Bluefile",
        "package(\"p\", \"0.1.0\")\nquarantine(\"checks/t.b::fails\", \"the fixture fails on purpose\", \"2099-12-31\")\n",
    );
    let (locked, out) = blue(&p.0, &["lock", "."], &[]);
    assert!(locked, "{out}");
    let (ok, out) = blue(
        &p.0,
        &["test", "checks/t.b"],
        &[("BLUE_TEST_TODAY", "2099-12-31")],
    );
    assert!(ok, "{out}");
    assert!(out.contains("quarantined until 2099-12-31"), "{out}");
    let (ok, out) = blue(
        &p.0,
        &["test", "checks/t.b"],
        &[("BLUE_TEST_TODAY", "2100-01-01")],
    );
    assert!(!ok, "{out}");
    assert!(out.contains("ended on 2099-12-31"), "{out}");
}

#[test]
fn a_quarantine_with_no_date_or_no_test_holds_nothing() {
    for entry in [
        "quarantine(\"checks/t.b::fails\", \"why\", \"someday\")",
        "quarantine(\"fails\", \"why\", \"2099-12-31\")",
        "quarantine(\"checks/t.b::fails\", \"\", \"2099-12-31\")",
    ] {
        let p = Place::new("refused");
        p.write("checks/t.b", MIXED);
        p.write("Bluefile", &format!("package(\"p\", \"0.1.0\")\n{entry}\n"));
        let _ = blue(&p.0, &["lock", "."], &[]);
        let (ok, out) = blue(
            &p.0,
            &["test", "checks/t.b"],
            &[("BLUE_TEST_TODAY", "2026-01-01")],
        );
        assert!(!ok, "{entry}: {out}");
    }
}
