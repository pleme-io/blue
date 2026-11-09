use std::path::{Path, PathBuf};
use std::process::Command;

const SRC: &str = "def g(x)\n  x * 2\nend\n\ndef main()\n  write_stdout(unlines([g(21)]))\nend\n\ntest \"g doubles\"\n  assert g(2) == 4\nend\n";

struct Place {
    root: PathBuf,
    file: PathBuf,
}

impl Place {
    fn new(name: &str) -> Self {
        let root =
            std::env::temp_dir().join(format!("blue-check-doors-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).expect("scratch dir");
        let file = root.join("t.b");
        std::fs::write(&file, SRC).expect("write fixture");
        Self { root, file }
    }

    fn blue(&self, args: &[&str], env: &[(&str, &str)]) -> String {
        let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
        c.args(args)
            .arg(&self.file)
            .env_remove("BLUE_PATH")
            .env_remove("BLUE_CONFIG")
            .env_remove("BLUE_TIER")
            .env_remove("BLUE_MEMO")
            .env_remove("BLUE_CHECK_CACHE")
            .env("BLUE_TEST_CACHE", "off")
            .env("XDG_CACHE_HOME", self.root.join("cache"));
        for (k, v) in env {
            c.env(k, v);
        }
        let out = c.output().expect("blue runs");
        assert!(
            out.status.success(),
            "{}{}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );
        String::from_utf8_lossy(&out.stdout).into_owned()
    }

    fn stored(&self) -> usize {
        files_under(&self.root.join("cache").join("blue").join("check"))
    }
}

impl Drop for Place {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn files_under(dir: &Path) -> usize {
    std::fs::read_dir(dir).map_or(0, |entries| {
        entries
            .flatten()
            .map(|e| {
                let p = e.path();
                if p.is_dir() {
                    files_under(&p)
                } else {
                    1
                }
            })
            .sum()
    })
}

#[test]
fn run_and_test_keep_their_checks_in_the_check_cache() {
    for (name, args, says) in [
        ("run", &["run"][..], "42\n"),
        ("test", &["test"][..], "1 test(s): 1 passed, 0 failed\n"),
    ] {
        let p = Place::new(name);
        assert!(p.blue(args, &[]).contains(says), "{name}");
        let stored = p.stored();
        assert!(stored > 0, "`blue {name}` kept no check in the cache");
        assert!(p.blue(args, &[]).contains(says), "{name}, again");
        assert_eq!(
            p.stored(),
            stored,
            "{name}: the second run stored a new bucket"
        );
    }
}

#[test]
fn the_check_cache_off_keeps_nothing() {
    let p = Place::new("off");
    p.blue(&["run"], &[("BLUE_CHECK_CACHE", "off")]);
    p.blue(&["test", "--no-cache"], &[]);
    assert_eq!(p.stored(), 0);
}

#[test]
fn a_run_that_stored_a_check_keeps_the_cache_to_its_bound() {
    let p = Place::new("bound");
    let old = p
        .root
        .join("cache")
        .join("blue")
        .join("check")
        .join("v0-old");
    std::fs::create_dir_all(&old).expect("an old identity");
    let junk = old.join("junk");
    std::fs::File::create(&junk)
        .and_then(|f| f.set_len(blue_lang_mondou::store::DEFAULT_MAX_BYTES + 1))
        .expect("a store past its bound");
    let _ = std::fs::File::options()
        .write(true)
        .open(&junk)
        .and_then(|f| f.set_modified(std::time::SystemTime::UNIX_EPOCH));
    p.blue(&["run"], &[]);
    assert!(
        !junk.exists(),
        "the run wrote past the bound and evicted nothing"
    );
}
