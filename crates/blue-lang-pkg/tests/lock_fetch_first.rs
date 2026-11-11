use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use blue_lang_pkg::lock::{lock_dir, LockError, Prefetch, LOCK_FILE};

const URL: &str = "github:o/up";

const BLUEFILE: &str = "package(\"app\", \"0.1.0\")\nallow(%i[network])\npackages(\"bidamas\")\nsource(\"up\", \"github:o/up\", \"bidamas\")\n";

struct Canned(BTreeMap<&'static str, String>);

impl Prefetch for Canned {
    fn prefetch(&self, url: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        self.0
            .get(url)
            .cloned()
            .ok_or_else(|| String::from("no canned answer for this url").into())
    }
}

fn fetching(rev: &str, store: &Path) -> Canned {
    Canned(BTreeMap::from([(
        URL,
        format!(
            r#"{{"hash":"sha256-{rev}","locked":{{"rev":"{rev}"}},"storePath":"{}"}}"#,
            store.display()
        ),
    )]))
}

fn tree(name: &str, files: &[(&str, &str)]) -> PathBuf {
    let root = std::env::temp_dir().join(format!("blue-lock-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    for (path, text) in files {
        let at = root.join(path);
        std::fs::create_dir_all(at.parent().expect("parent")).expect("mkdir");
        std::fs::write(at, text).expect("write");
    }
    root
}

fn project(name: &str) -> PathBuf {
    tree(
        name,
        &[
            ("Bluefile", BLUEFILE),
            ("bidamas/own/Bluefile", "package(\"own\", \"0.1.0\")\n"),
            (
                "main.b",
                "use(\"up/chozou\", [:hi])\n\ndef main()\n  hi()\nend\n",
            ),
        ],
    )
}

#[test]
fn a_new_pin_is_fetched_before_the_floor_reads_its_tree() {
    let old = tree(
        "old-store",
        &[("bidamas/up/Bluefile", "package(\"up\", \"0.1.0\")\n")],
    );
    let new = tree(
        "new-store",
        &[
            ("bidamas/up/Bluefile", "package(\"up\", \"0.2.0\")\n"),
            ("bidamas/up/chozou/chozou.b", "def hi()\n  1\nend\n"),
        ],
    );
    let dir = project("fetch-first");
    let previous =
        blue_lang_pkg::lock::lock(BLUEFILE, &BTreeMap::new(), &fetching(&"a".repeat(40), &old))
            .expect("the old pin");
    std::fs::write(
        dir.join(LOCK_FILE),
        serde_json::to_string(&previous).expect("json"),
    )
    .expect("write the old lock");
    let lock = lock_dir(&dir, &fetching(&"b".repeat(40), &new)).expect("locks in one run");
    assert_eq!(lock.sources["up"].rev, "b".repeat(40));
    let record = lock.capabilities.expect("a declared ceiling is recorded");
    assert!(
        record.packages.contains_key("up/chozou") || record.packages.contains_key("up"),
        "{:?}",
        record.packages
    );
    for d in [old, new, dir] {
        let _ = std::fs::remove_dir_all(d);
    }
}

#[test]
fn a_pin_whose_tree_is_not_on_this_machine_is_refused_by_name() {
    let dir = project("tree-gone");
    let gone = std::env::temp_dir().join(format!("blue-lock-gone-{}", std::process::id()));
    let err = lock_dir(&dir, &fetching(&"c".repeat(40), &gone)).expect_err("blind");
    assert!(
        matches!(err, LockError::SourceTree { ref name, ref rev, .. } if name == "up" && *rev == "c".repeat(40)),
        "got {err}"
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_refused_source_makes_the_floor_blind_and_names_it() {
    let dir = tree(
        "refused",
        &[
            (
                "Bluefile",
                "package(\"app\", \"0.1.0\")\nallow(%i[network])\npackages(\"bidamas\")\nsource(\"up\", \"flakehub:o/up/0.1\", \"bidamas\")\n",
            ),
            ("bidamas/own/Bluefile", "package(\"own\", \"0.1.0\")\n"),
            ("main.b", "use(\"up/chozou\", [:hi])\n\ndef main()\n  hi()\nend\n"),
        ],
    );
    let err = lock_dir(&dir, &Canned(BTreeMap::new())).expect_err("blind");
    assert!(
        matches!(err, LockError::BlindFloor { ref refused, .. } if refused == &["up".to_string()]),
        "got {err}"
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_bidama_whose_needs_resolve_locks() {
    let dist = tree(
        "bidama-dist",
        &[
            ("dep/Bluefile", "package(\"dep\", \"0.1.0\")\n"),
            ("dep/dep.b", "def hi()\n  1\nend\n"),
            (
                "me/Bluefile",
                "package(\"me\", \"0.1.0\")\nneeds(\"dep\", \"^0.1\")\n",
            ),
            (
                "me/me.b",
                "use(\"dep\", [:hi])\n\ndef twice()\n  hi() + hi()\nend\n",
            ),
        ],
    );
    let lock = lock_dir(&dist.join("me"), &Canned(BTreeMap::new())).expect("locks");
    assert_eq!(lock.manifest.needs["dep"], "^0.1.0");
    let _ = std::fs::remove_dir_all(dist);
}
