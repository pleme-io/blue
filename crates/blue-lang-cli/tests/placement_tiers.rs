use std::path::{Path, PathBuf};

const WRITES_CODE: &[&str] = &[
    "PROT_EXEC",
    "MAP_JIT",
    "mprotect",
    "VirtualProtect",
    "pthread_jit_write_protect",
];

const NO_WRITABLE_CODE: &[&str] = &["blue-lang-ios", "blue-lang-component", "blue-lang-wasm"];

fn crates() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("the crates directory")
        .to_path_buf()
}

fn sources(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for e in entries.flatten() {
        let p = e.path();
        if p.is_dir() {
            if p.file_name().is_some_and(|n| n == "target") {
                continue;
            }
            sources(&p, out);
        } else if p.extension().is_some_and(|x| x == "rs") {
            out.push(p);
        }
    }
}

fn writers(root: &Path) -> Vec<String> {
    let mut files = Vec::new();
    sources(root, &mut files);
    let me = Path::new(file!()).file_name().expect("this file");
    files
        .iter()
        .filter(|p| p.file_name() != Some(me))
        .filter_map(|p| {
            let text = std::fs::read_to_string(p).ok()?;
            WRITES_CODE
                .iter()
                .find(|w| text.contains(*w))
                .map(|w| format!("{} names {w}", p.display()))
        })
        .collect()
}

#[test]
fn a_placement_that_forbids_writable_code_links_no_native_tier() {
    for name in NO_WRITABLE_CODE {
        let manifest = crates().join(name).join("Cargo.toml");
        let text = std::fs::read_to_string(&manifest).expect("a manifest");
        let links = text.lines().any(|l| {
            let l = l.trim_start();
            l.starts_with("blue-lang-cli") || l.starts_with("blue_lang_cli")
        });
        assert!(
            !links,
            "{name} links blue-lang-cli, whose native tier runs artifacts the placement forbids"
        );
    }
}

#[test]
fn no_crate_writes_code_at_run_time() {
    let found = writers(&crates());
    assert!(
        found.is_empty(),
        "a JIT tier needs a placement gate first (rule R12): {found:?}"
    );
}

#[test]
fn the_scan_finds_a_writer_where_there_is_one() {
    let d = std::env::temp_dir().join(format!("blue-placement-tiers-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(d.join("src")).expect("scratch");
    std::fs::write(
        d.join("src").join("jit.rs"),
        "const P: i32 = libc::PROT_EXEC;\n",
    )
    .expect("fixture");
    assert_eq!(writers(&d).len(), 1);
    let _ = std::fs::remove_dir_all(&d);
}
