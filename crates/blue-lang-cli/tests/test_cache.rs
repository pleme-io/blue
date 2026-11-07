use std::path::{Path, PathBuf};
use std::process::Command;

const BASE: &str = "k = 1\n\n\
                    def g(x)\n  x * 2\nend\n\n\
                    def f(x)\n  g(x) + k\nend\n\n\
                    def unrelated(x)\n  x\nend\n\n\
                    test \"f adds\"\n  assert f(1) == 3\nend\n";

struct Place {
    root: PathBuf,
    file: PathBuf,
}

impl Place {
    fn new(name: &str) -> Self {
        let root =
            std::env::temp_dir().join(format!("blue-test-cache-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).expect("scratch dir");
        let file = root.join("t.b");
        Self { root, file }
    }

    fn write(&self, src: &str) {
        std::fs::write(&self.file, src).expect("write fixture");
    }

    fn test(&self, env: &[(&str, &str)], args: &[&str]) -> String {
        let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
        c.arg("test")
            .arg(&self.file)
            .args(args)
            .env_remove("BLUE_PATH")
            .env_remove("BLUE_CONFIG")
            .env_remove("BLUE_TIER")
            .env_remove("BLUE_MEMO")
            .env_remove("BLUE_WITNESS")
            .env("BLUE_TEST_CACHE", "on")
            .env("XDG_CACHE_HOME", self.root.join("cache"));
        for (k, v) in env {
            c.env(k, v);
        }
        let out = c.output().expect("blue test runs");
        format!(
            "{}{}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        )
    }

    fn run(&self) -> String {
        self.test(&[], &[])
    }
}

impl Drop for Place {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn says(out: &str, tally: &str) {
    assert!(out.contains(tally), "expected {tally:?} in:\n{out}");
}

fn primed(name: &str, src: &str) -> Place {
    let p = Place::new(name);
    p.write(src);
    says(&p.run(), "1 test(s): 1 passed, 0 failed\n");
    says(&p.run(), "1 test(s): 0 passed, 0 failed, 1 cached\n");
    p
}

#[test]
fn a_changed_callee_runs_its_test_again() {
    let p = primed("callee", BASE);
    p.write(&BASE.replace("x * 2", "x + x"));
    says(&p.run(), "1 test(s): 1 passed, 0 failed\n");
    says(&p.run(), "1 test(s): 0 passed, 0 failed, 1 cached\n");
}

#[test]
fn an_unrelated_change_keeps_the_test_cached() {
    let p = primed("unrelated", BASE);
    p.write(&BASE.replace("  x\nend", "  x + 1\nend"));
    says(&p.run(), "1 test(s): 0 passed, 0 failed, 1 cached\n");
    p.write(&format!("{BASE}\ndef another(y)\n  y\nend\n"));
    says(&p.run(), "1 test(s): 0 passed, 0 failed, 1 cached\n");
}

#[test]
fn a_changed_preamble_runs_a_test_that_names_nothing_in_it() {
    let src = "send(self, 41)\n\ntest \"mail\"\n  assert receive(:_, 0, nil) == 41\nend\n";
    let p = primed("preamble", src);
    p.write(&src.replace("send(self, 41)", "send(self, 42)"));
    says(&p.run(), "1 test(s): 0 passed, 1 failed\n");
    p.write(src);
    says(&p.run(), "1 test(s): 0 passed, 0 failed, 1 cached\n");
}

#[test]
fn a_failing_test_is_never_cached() {
    let p = Place::new("failing");
    p.write(&BASE.replace("f(1) == 3", "f(1) == 4"));
    says(&p.run(), "1 test(s): 0 passed, 1 failed\n");
    let again = p.run();
    says(&again, "1 test(s): 0 passed, 1 failed\n");
    assert!(!again.contains("cached"), "{again}");
}

#[test]
fn a_test_that_reaches_the_host_is_never_cached() {
    let p = Place::new("host");
    p.write("test \"clock\"\n  assert now_ms > 0\nend\n");
    says(&p.run(), "1 test(s): 1 passed, 0 failed\n");
    says(&p.run(), "1 test(s): 1 passed, 0 failed\n");
}

#[test]
fn the_cache_off_runs_everything() {
    let p = primed("off", BASE);
    says(
        &p.test(&[], &["--no-cache"]),
        "1 test(s): 1 passed, 0 failed\n",
    );
    says(
        &p.test(&[("BLUE_TEST_CACHE", "off")], &[]),
        "1 test(s): 1 passed, 0 failed\n",
    );
    let unset = {
        let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
        c.arg("test")
            .arg(&p.file)
            .env_remove("BLUE_TEST_CACHE")
            .env_remove("BLUE_PATH")
            .env_remove("BLUE_MEMO")
            .env("XDG_CACHE_HOME", p.root.join("cache"));
        String::from_utf8_lossy(&c.output().expect("blue test runs").stdout).into_owned()
    };
    says(&unset, "1 test(s): 1 passed, 0 failed\n");
    let facts = p.root.join("facts").join("facts.json");
    let with_facts = p.test(&[], &["--facts", facts.to_str().expect("utf-8 path")]);
    says(&with_facts, "1 test(s): 1 passed, 0 failed\n");
    says(&p.run(), "1 test(s): 0 passed, 0 failed, 1 cached\n");
}

#[test]
fn an_unknown_cache_value_is_refused() {
    let p = Place::new("unknown");
    p.write(BASE);
    let out = p.test(&[("BLUE_TEST_CACHE", "store")], &[]);
    assert!(out.contains("BLUE_TEST_CACHE"), "{out}");
    assert!(!Path::new(&p.root.join("cache")).exists(), "{out}");
}
