use std::collections::BTreeMap;

fn sections() -> BTreeMap<String, BTreeMap<String, String>> {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../Cargo.toml");
    let text = std::fs::read_to_string(path).expect("the workspace Cargo.toml");
    let mut out: BTreeMap<String, BTreeMap<String, String>> = BTreeMap::new();
    let mut current = String::new();
    for line in text.lines().map(str::trim) {
        if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            current = name.to_string();
            out.entry(current.clone()).or_default();
        } else if let Some((k, v)) = line.split_once('=') {
            if !line.starts_with('#') {
                out.entry(current.clone())
                    .or_default()
                    .insert(k.trim().to_string(), v.trim().to_string());
            }
        }
    }
    out
}

#[test]
fn a_local_release_build_is_incremental_and_split_wide() {
    let s = sections();
    let local = s
        .get("profile.release-local")
        .expect("[profile.release-local]");
    assert_eq!(
        local.get("inherits").map(String::as_str),
        Some("\"release\"")
    );
    assert_eq!(local.get("incremental").map(String::as_str), Some("true"));
    assert_eq!(local.get("codegen-units").map(String::as_str), Some("256"));
    assert!(
        !s.contains_key("profile.release") || s["profile.release"].get("incremental").is_none(),
        "the shipped release profile stays as it was"
    );
}

#[test]
fn the_dev_build_optimizes_the_crates_that_check_and_format() {
    let s = sections();
    for krate in [
        "tatara-lisp-eval",
        "tatara-lisp",
        "blue-lang-runtime",
        "blue-lang-test",
        "blue-lang-check",
        "blue-lang-syntax",
        "blue-lang-fmt",
        "blue-lang-pkg",
    ] {
        let section = format!("profile.dev.package.{krate}");
        assert_eq!(
            s.get(&section)
                .and_then(|p| p.get("opt-level"))
                .map(String::as_str),
            Some("3"),
            "{section}"
        );
    }
}
