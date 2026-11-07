use std::collections::BTreeSet;
use std::path::PathBuf;
use std::process::{Command, Output};

const GUARDED: [&str; 3] = ["tameshi", "blue-lang-senses", "blue-lang-kernel"];

const SPLIT: [(&str, &[&str]); 7] = [
    ("", &[]),
    ("host", &[]),
    ("threshold", &["tameshi"]),
    ("storage-append", &[]),
    ("kernel", &["blue-lang-kernel"]),
    ("senses", &["blue-lang-senses"]),
    ("sys", &["tameshi", "blue-lang-senses", "blue-lang-kernel"]),
];

fn workspace_root() -> PathBuf {
    PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../.."))
}

fn cargo(verb: &str, feature: &str, extra: &[&str]) -> Output {
    let out = Command::new(env!("CARGO"))
        .arg(verb)
        .args([
            "-p",
            "blue-lang-runtime",
            "--no-default-features",
            "--features",
            feature,
            "--offline",
        ])
        .args(extra)
        .current_dir(workspace_root())
        .output()
        .unwrap_or_else(|e| panic!("cargo {verb} --features {feature:?}: {e}"));
    assert!(
        out.status.success(),
        "cargo {verb} --features {feature:?} failed:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    out
}

fn linked(feature: &str) -> BTreeSet<String> {
    let out = cargo("tree", feature, &["-e", "normal", "--prefix", "none"]);
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|line| line.split_whitespace().next())
        .filter(|name| GUARDED.contains(name))
        .map(str::to_string)
        .collect()
}

#[test]
fn each_feature_links_only_its_own_host_crates() {
    let mut failures = Vec::new();
    for (feature, expected) in SPLIT {
        let expected: BTreeSet<String> = expected.iter().map(|s| (*s).to_string()).collect();
        let got = linked(feature);
        if got != expected {
            failures.push(format!(
                "{feature:?}: expected {expected:?}, linked {got:?}"
            ));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn each_feature_builds_alone() {
    for (feature, _) in SPLIT {
        cargo("check", feature, &["--lib"]);
    }
}

#[test]
fn the_split_names_every_feature_the_manifest_declares() {
    let manifest = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/Cargo.toml"))
        .expect("read Cargo.toml");
    let declared: BTreeSet<&str> = manifest
        .split("[features]")
        .nth(1)
        .and_then(|rest| rest.split("\n[").next())
        .expect("a [features] table")
        .lines()
        .filter(|line| !line.trim_start().starts_with('#'))
        .filter_map(|line| line.split_once('=').map(|(name, _)| name.trim()))
        .collect();
    let split: BTreeSet<&str> = SPLIT
        .iter()
        .map(|(f, _)| *f)
        .filter(|f| !f.is_empty())
        .collect();
    assert_eq!(declared, split);
}
