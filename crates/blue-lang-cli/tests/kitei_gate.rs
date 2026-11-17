use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;

struct Row {
    switch: String,
    state: String,
}

fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn registry() -> BTreeMap<String, Row> {
    static CALLS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let n = CALLS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let d = std::env::temp_dir().join(format!("blue-kitei-gate-{}-{n}", std::process::id()));
    std::fs::create_dir_all(&d).expect("scratch");
    let p = d.join("rows.b");
    std::fs::write(
        &p,
        "use(\"kitei\", [:rules])\n\ndef main()\n  write_stdout(join(map((r) -> \"#{r.id}\\t#{r.switch}\\t#{r.state}\", rules), \"\\n\"))\nend\n",
    )
    .expect("program");
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env("BLUE_PATH", root().join("bidamas"))
        .args(["run", "--quiet"])
        .arg(&p)
        .output()
        .expect("spawn blue");
    let _ = std::fs::remove_dir_all(&d);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(|l| {
            let mut f = l.split('\t');
            let id = f.next().expect("id").to_string();
            let switch = f.next().expect("switch").to_string();
            let state = f.next().expect("state").trim_start_matches(':').to_string();
            (id, Row { switch, state })
        })
        .collect()
}

fn table() -> BTreeMap<String, String> {
    let text = std::fs::read_to_string(root().join("docs/PERFORMANCE.md")).expect("PERFORMANCE.md");
    text.lines()
        .filter_map(|l| {
            let cells: Vec<&str> = l.split('|').map(str::trim).collect();
            let id = cells.get(1)?;
            let numbered =
                id.len() > 1 && id.starts_with('R') && id[1..].chars().all(|c| c.is_ascii_digit());
            numbered.then(|| {
                (
                    id.to_string(),
                    cells.get(4).map_or("", |s| s).trim_matches('`').to_string(),
                )
            })
        })
        .collect()
}

fn sources(dir: &Path, out: &mut String) {
    for e in std::fs::read_dir(dir)
        .expect("a source directory")
        .flatten()
    {
        let p = e.path();
        if p.is_dir() {
            sources(&p, out);
        } else if p.extension().is_some_and(|x| x == "rs") {
            out.push_str(&std::fs::read_to_string(&p).unwrap_or_default());
        }
    }
}

#[test]
fn the_performance_table_holds_every_rule_the_registry_ships_with_its_switch() {
    let reg = registry();
    let tab = table();
    assert!(!tab.is_empty(), "no rule rows read from PERFORMANCE.md");
    for (id, row) in &reg {
        if row.state == "folded" {
            assert!(
                !tab.contains_key(id),
                "{id} is folded, yet PERFORMANCE.md has a row"
            );
            continue;
        }
        let shown = tab
            .get(id)
            .unwrap_or_else(|| panic!("{id} has no row in PERFORMANCE.md"));
        if row.switch == "none" {
            assert!(
                !shown.starts_with("BLUE_"),
                "{id}: the registry has no switch, PERFORMANCE.md shows {shown}"
            );
        } else {
            assert_eq!(
                shown, &row.switch,
                "{id}: the switch in PERFORMANCE.md is not the registry's"
            );
        }
    }
    for id in tab.keys() {
        assert!(
            reg.contains_key(id),
            "PERFORMANCE.md has {id}, the registry does not"
        );
    }
}

#[test]
fn every_switch_the_registry_names_is_read_by_the_code() {
    let mut code = String::new();
    sources(&root().join("crates"), &mut code);
    for (id, row) in registry() {
        if let Some((var, _)) = row.switch.split_once('=') {
            assert!(
                code.contains(&format!("\"{var}\"")),
                "{id}: no crate reads {var}"
            );
        }
    }
}

#[test]
fn every_rule_blue_shift_names_is_a_shipped_rule() {
    let reg = registry();
    let mut named = Vec::new();
    for file in [
        "crates/blue-lang-runtime/src/defaults.rs",
        "crates/blue-lang-cli/src/defaults.rs",
    ] {
        let text = std::fs::read_to_string(root().join(file)).expect("defaults source");
        for piece in text.split("\"R").skip(1) {
            let digits: String = piece.chars().take_while(char::is_ascii_digit).collect();
            if !digits.is_empty() && piece[digits.len()..].starts_with('"') {
                named.push(format!("R{digits}"));
            }
        }
    }
    assert!(named.len() >= 6, "read {named:?}");
    for id in named {
        let row = reg
            .get(&id)
            .unwrap_or_else(|| panic!("blue shift names {id}, the registry has no row"));
        assert_eq!(
            row.state, "shipped",
            "blue shift names {id}, which is not shipped"
        );
    }
}
