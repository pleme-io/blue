//! SAFETY.md D3, phase 4: `blue census` counts the undeclared scripts that
//! reach the host, and refuses none of them.

use std::path::{Path, PathBuf};
use std::process::Output;

fn census(dir: &Path) -> Output {
    std::process::Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_DIST")
        .env(
            "BLUE_PATH",
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../bidamas"),
        )
        .current_dir(dir)
        .args(["census", ".", "--findings"])
        .output()
        .expect("spawn")
}

fn measured(files: &[(&str, &str)]) -> (usize, String, String) {
    static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let dir = std::env::temp_dir().join(format!(
        "blue-census-undeclared-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("mkdir");
    for (name, text) in files {
        let at = dir.join(name);
        std::fs::create_dir_all(at.parent().expect("a parent")).expect("mkdir");
        std::fs::write(at, text).expect("write");
    }
    let out = census(&dir);
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    let _ = std::fs::remove_dir_all(&dir);
    let line = stdout
        .lines()
        .find(|l| l.contains("undeclared-host-script"))
        .unwrap_or_else(|| panic!("no D3 row\n{stdout}\n{stderr}"));
    let n = line
        .split_whitespace()
        .nth(3)
        .and_then(|n| n.parse().ok())
        .unwrap_or_else(|| panic!("{line}"));
    (n, stdout, stderr)
}

const READS: &str = "write_stdout(getenv(\"HOME\"))\n";

#[test]
fn an_undeclared_script_that_reaches_the_host_is_counted_and_named() {
    let (n, out, err) = measured(&[("s.b", &format!("#!/usr/bin/env blue\n{READS}"))]);
    assert_eq!(n, 1, "{out}");
    assert!(out.contains("    s.b: environment"), "{out}");
    assert!(
        err.contains("1 undeclared script(s) reach the host"),
        "{err}"
    );
}

#[test]
fn a_tree_with_no_bidamas_of_its_own_resolves_the_standard_ones() {
    let (n, out, err) = measured(&[(
        "tools/s.b",
        "#!/usr/bin/env blue\nuse(\"retsu\", [:size])\nwrite_stdout(\"#{size([getenv(\"HOME\")])}\")\n",
    )]);
    assert_eq!(n, 1, "{out}\n{err}");
    assert!(out.contains("    tools/s.b: environment"), "{out}");
}

#[test]
fn a_loaded_definition_the_script_calls_carries_its_reach_to_the_script() {
    let home = "def home()\n  getenv(\"HOME\")\nend\n\ndef two()\n  2\nend\n";
    let (n, out, err) = measured(&[
        ("bidamas/k/k.b", home),
        (
            "s.b",
            "#!/usr/bin/env blue\nuse(\"k\")\nwrite_stdout(k::home)\n",
        ),
    ]);
    assert_eq!(n, 1, "{out}\n{err}");
    let (n, out, err) = measured(&[
        ("bidamas/k/k.b", home),
        ("s.b", "#!/usr/bin/env blue\nuse(\"k\")\nk::two\n"),
    ]);
    assert_eq!(n, 0, "{out}\n{err}");
}

#[test]
fn a_declared_a_pure_a_held_or_a_plain_file_is_not_counted() {
    for files in [
        &[(
            "s.b",
            &*format!("#!/usr/bin/env -S blue --allow environment\n{READS}"),
        )][..],
        &[("s.b", "#!/usr/bin/env blue\nwrite_stdout(\"hi\")\n")],
        &[("s.b", READS)],
        &[(
            "s.b",
            "#!/usr/bin/env blue\nwrite_stdout(\"hi\")\n\ntest \"t\"\n  assert getenv(\"HOME\") != 1\nend\n",
        )],
        &[
            ("s.b", &*format!("#!/usr/bin/env blue\n{READS}")),
            (
                "Bluefile",
                "package(\"app\", \"0.1.0\")\nallow(%i[environment])\n",
            ),
        ],
    ] {
        let (n, out, err) = measured(files);
        assert_eq!(n, 0, "{files:?}\n{out}\n{err}");
    }
}
