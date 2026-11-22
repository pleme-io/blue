//! SAFETY.md D3: an undeclared script (a `blue` shebang with no `--allow`,
//! held by no Bluefile) runs as `--allow none`, `BLUE_SCRIPTS=ambient` runs
//! it with the host, and `blue census` counts the ones that reach the host.

use std::path::{Path, PathBuf};
use std::process::Output;

fn blue(dir: &Path, args: &[&str], ambient: bool) -> Output {
    let mut cmd = std::process::Command::new(env!("CARGO_BIN_EXE_blue"));
    cmd.env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_DIST")
        .env_remove("BLUE_SCRIPTS")
        .env(
            "BLUE_PATH",
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../bidamas"),
        )
        .current_dir(dir)
        .args(args);
    if ambient {
        cmd.env("BLUE_SCRIPTS", "ambient");
    }
    cmd.output().expect("spawn")
}

fn tree(files: &[(&str, &str)]) -> PathBuf {
    static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let dir = std::env::temp_dir().join(format!(
        "blue-census-undeclared-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&dir);
    for (name, text) in files {
        let at = dir.join(name);
        std::fs::create_dir_all(at.parent().expect("a parent")).expect("mkdir");
        std::fs::write(at, text).expect("write");
    }
    dir
}

fn measured(files: &[(&str, &str)]) -> (usize, String, String) {
    let dir = tree(files);
    let out = blue(&dir, &["census", ".", "--findings"], false);
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

fn ran(files: &[(&str, &str)], args: &[&str], ambient: bool) -> (bool, String, String) {
    let dir = tree(files);
    let out = blue(&dir, args, ambient);
    let _ = std::fs::remove_dir_all(&dir);
    (
        out.status.success(),
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

const READS: &str = "write_stdout(\"#{getenv(\"HOME\") != nil}\")\n";

#[test]
fn an_undeclared_script_that_reaches_the_host_is_refused_and_ambient_runs_it() {
    let files = [("s.b", &*format!("#!/usr/bin/env blue\n{READS}"))];
    let (ok, out, err) = ran(&files, &["s.b"], false);
    assert!(!ok, "{out}\n{err}");
    assert!(
        err.contains("refused") && err.contains("environment"),
        "{err}"
    );
    assert!(!out.contains("true"), "{out}");
    let (ok, out, err) = ran(&files, &["run", "--quiet", "s.b"], false);
    assert!(!ok && err.contains("refused"), "{out}\n{err}");
    let (ok, out, err) = ran(&files, &["s.b"], true);
    assert!(ok && out == "true", "{out}\n{err}");
}

#[test]
fn a_declared_a_held_a_pure_or_a_shebangless_run_reaches_what_it_did() {
    let declared = format!("#!/usr/bin/env -S blue --allow environment\n{READS}");
    let undeclared = format!("#!/usr/bin/env blue\n{READS}");
    let held = "package(\"app\", \"0.1.0\")\nallow(%i[environment])\n";
    let documented = format!(
        "#!/usr/bin/env blue\n@moduledoc \"\"\"\nSays whether HOME is set.\n\n    1 + 1 #=> 2\n\"\"\"\n\n{READS}"
    );
    for (files, args) in [
        (&[("s.b", &*declared)][..], &["s.b"][..]),
        (&[("s.b", &*undeclared)], &["--allow", "environment", "s.b"]),
        (&[("s.b", &*documented), ("Bluefile", held)], &["s.b"]),
        (&[("s.b", READS)], &["run", "--quiet", "s.b"]),
    ] {
        let (ok, out, err) = ran(files, args, false);
        assert!(ok && out == "true", "{files:?} {args:?}\n{out}\n{err}");
    }
    let (ok, out, err) = ran(
        &[("s.b", "#!/usr/bin/env blue\nwrite_stdout(\"hi\")\n")],
        &["s.b"],
        false,
    );
    assert!(ok && out == "hi", "{out}\n{err}");
}

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
