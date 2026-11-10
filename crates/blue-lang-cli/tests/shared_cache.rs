use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::Command;

use blue_lang_mondou::def_hash::DefHash;
use blue_lang_mondou::store::{Identity, Store, DEFAULT_MAX_BYTES};

const DEP: &str = "def g(x)\n  x * 2\nend\n\ndef unrelated(x)\n  x\nend\n";
const TEST: &str = "use(\"dep\", [:g])\n\ntest \"g doubles\"\n  assert g(2) == 4\nend\n";
const APP: &str = "@moduledoc \"\"\"\napp quadruples.\n\n    quad(1) #=> 4\n\"\"\"\n\nuse(\"dep\", [:g])\n\n@doc \"\"\"\nquad: the number times four.\n\n    quad(1) #=> 4\n\"\"\"\ndef quad(n)\n  g(g(n))\nend\n";
const MAIN: &str = "use(\"dep\")\n\ndef main()\n  println(dep::g(21))\nend\n";

struct Place {
    root: PathBuf,
}

impl Place {
    fn new(name: &str) -> Self {
        let root =
            std::env::temp_dir().join(format!("blue-shared-cache-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).expect("scratch dir");
        Self { root }
    }

    fn lib(&self, at: &str, dep: &str) -> PathBuf {
        let lib = self.root.join(at);
        std::fs::create_dir_all(lib.join("dep")).expect("dep dir");
        std::fs::write(
            lib.join("dep").join("Bluefile"),
            "package(\"dep\", \"0.1.0\")\n",
        )
        .expect("Bluefile");
        std::fs::write(lib.join("dep").join("dep.b"), dep).expect("dep.b");
        lib
    }

    fn file(&self, at: &str, src: &str) -> PathBuf {
        let dir = self.root.join(at);
        std::fs::create_dir_all(&dir).expect("dir");
        let f = dir.join("t.b");
        std::fs::write(&f, src).expect("t.b");
        f
    }

    fn node(&self, name: &str) -> PathBuf {
        self.root.join(name).join("blue")
    }

    fn engine_at(&self, name: &str) -> PathBuf {
        let dir = self.root.join(name);
        std::fs::create_dir_all(&dir).expect("engine dir");
        let to = dir.join("blue");
        std::fs::copy(env!("CARGO_BIN_EXE_blue"), &to).expect("copies the engine");
        to
    }

    #[allow(clippy::too_many_arguments)]
    fn blue(
        &self,
        engine: &Path,
        args: &[&str],
        file: &Path,
        lib: &Path,
        node: &str,
        shared: Option<&str>,
    ) -> (bool, String) {
        let mut c = Command::new(engine);
        c.args(args)
            .arg(file)
            .env_remove("BLUE_CONFIG")
            .env_remove("BLUE_TIER")
            .env_remove("BLUE_MEMO")
            .env_remove("BLUE_CHECK_CACHE")
            .env_remove("BLUE_CACHE_SHARED")
            .env("BLUE_TEST_CACHE", "on")
            .env("BLUE_PATH", lib)
            .env("XDG_CACHE_HOME", self.root.join(node));
        if let Some(s) = shared {
            c.env("BLUE_CACHE_SHARED", self.node(s));
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

    fn check_keys(&self, node: &str) -> BTreeSet<[u8; 32]> {
        let tier = self.node(node).join("check");
        let mut keys = BTreeSet::new();
        for id_dir in std::fs::read_dir(&tier).expect("a check tier").flatten() {
            let name = id_dir.file_name().to_string_lossy().into_owned();
            let id = DefHash::from_hex(name.trim_start_matches("v1-")).expect("identity dir");
            let store = Store::open(&tier, Identity(id.0), DEFAULT_MAX_BYTES).expect("opens");
            for f in std::fs::read_dir(id_dir.path()).expect("buckets").flatten() {
                let bucket = DefHash::from_hex(&f.file_name().to_string_lossy()).expect("bucket");
                keys.extend(store.load(&bucket).entries.into_keys());
            }
        }
        keys
    }
}

impl Drop for Place {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn says(out: &(bool, String), tally: &str) {
    assert!(out.1.contains(tally), "expected {tally:?} in:\n{}", out.1);
}

#[test]
fn a_test_passed_on_one_node_is_cached_on_another_running_the_same_bytes_elsewhere() {
    let p = Place::new("node");
    let lib = p.lib("lib", DEP);
    let t = p.file("src", TEST);
    let here = p.engine_at("engine-a");
    let there = p.engine_at("engine-b");
    says(
        &p.blue(&here, &["test"], &t, &lib, "a", None),
        "1 test(s): 1 passed, 0 failed\n",
    );
    says(
        &p.blue(&there, &["test"], &t, &lib, "b", Some("a")),
        "1 test(s): 0 passed, 0 failed, 1 cached\n",
    );
    says(
        &p.blue(&there, &["test"], &t, &lib, "b", None),
        "1 test(s): 0 passed, 0 failed, 1 cached\n",
    );
    says(
        &p.blue(&there, &["test"], &t, &lib, "c", None),
        "1 test(s): 1 passed, 0 failed\n",
    );
}

#[test]
fn a_changed_dependency_runs_the_test_again_whatever_a_shared_root_holds() {
    let p = Place::new("dep-test");
    let lib = p.lib("lib", DEP);
    let t = p.file("src", TEST);
    let engine = PathBuf::from(env!("CARGO_BIN_EXE_blue"));
    says(
        &p.blue(&engine, &["test"], &t, &lib, "a", None),
        "1 test(s): 1 passed, 0 failed\n",
    );
    let changed = p.lib("lib2", &DEP.replace("x * 2", "x * 3"));
    let out = p.blue(&engine, &["test"], &t, &changed, "b", Some("a"));
    says(&out, "1 test(s): 0 passed, 1 failed\n");
    assert!(!out.0, "{}", out.1);
    let unrelated = p.lib("lib3", &DEP.replace("  x\nend", "  x + 1\nend"));
    says(
        &p.blue(&engine, &["test"], &t, &unrelated, "c", Some("a")),
        "1 test(s): 0 passed, 0 failed, 1 cached\n",
    );
}

#[test]
fn a_package_checked_from_two_places_keys_every_check_the_same() {
    let p = Place::new("check-place");
    let engine = PathBuf::from(env!("CARGO_BIN_EXE_blue"));
    let lib_a = p.lib("there/lib", DEP);
    let lib_b = p.lib("here/lib", DEP);
    for lib in [&lib_a, &lib_b] {
        std::fs::create_dir_all(lib.join("app")).expect("app dir");
        std::fs::write(
            lib.join("app").join("Bluefile"),
            "package(\"app\", \"0.1.0\")\nneeds(\"dep\", \"^0.1\")\n",
        )
        .expect("Bluefile");
        std::fs::write(lib.join("app").join("app.b"), APP).expect("app.b");
    }
    let file = |lib: &Path| lib.join("app").join("app.b");
    let first = p.blue(&engine, &["check"], &file(&lib_a), &lib_a, "a", None);
    assert!(first.0, "{}", first.1);
    let theirs = p.check_keys("a");
    assert!(!theirs.is_empty());
    assert!(
        p.blue(&engine, &["check"], &file(&lib_b), &lib_b, "b", None)
            .0
    );
    assert_eq!(
        p.check_keys("b"),
        theirs,
        "the same package keyed its checks differently in another place"
    );
}

#[test]
fn a_dependency_that_drops_a_name_is_checked_again_whatever_a_shared_root_holds() {
    let p = Place::new("dep-check");
    let engine = PathBuf::from(env!("CARGO_BIN_EXE_blue"));
    let lib = p.lib("lib", DEP);
    let t = p.file("src", MAIN);
    assert!(p.blue(&engine, &["check"], &t, &lib, "a", None).0);
    let renamed = p.lib("lib2", &DEP.replace("def g(x)", "def h(x)"));
    let out = p.blue(&engine, &["check"], &t, &renamed, "b", Some("a"));
    assert!(
        !out.0,
        "a check served from the shared root hid a dropped name:\n{}",
        out.1
    );
    assert!(
        out.1.contains("error[B0011]: bidama `dep` defines no `g`"),
        "{}",
        out.1
    );
    let off = p.blue(&engine, &["check", "--no-cache"], &t, &renamed, "c", None);
    assert!(!off.0);
}
