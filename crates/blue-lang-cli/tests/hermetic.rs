use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const PROBE: &str = "test \"a fixture repo of its own\"
  d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"hermetic-#{to_s(now_ns)}\")
  mkdir_p(d)
  exec_capture(\"git\", \"-C\", d, \"init\", \"-q\")
  exec_capture(\"git\", \"-C\", d, \"config\", \"blue.probe\", \"written\")
  assert true
end

test \"a write outside the temporary root\"
  out = path_join(getenv(\"PROBE_REPO\"), \"leaked.txt\")
  r = write_file(out, \"x\") rescue :refused
  assert r == :refused
end
";

fn place(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR"))
        .join(format!("hermetic-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir.canonicalize().expect("canonical scratch dir")
}

fn git(dir: &Path, args: &[&str]) -> Output {
    Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .env_remove("GIT_DIR")
        .output()
        .expect("git runs")
}

fn run(root: &Path, env: &[(&str, &str)]) -> (Output, PathBuf, PathBuf) {
    let repo = root.join("repo");
    let tmp = root.join("tmp");
    std::fs::create_dir_all(&repo).expect("repo dir");
    std::fs::create_dir_all(&tmp).expect("tmp dir");
    assert!(git(&repo, &["init", "-q"]).status.success());
    let file = tmp.join("probe.b");
    std::fs::write(&file, PROBE).expect("probe");
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.arg("test")
        .arg(&file)
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_TEST_ENV")
        .env_remove("BLUE_TEST_WRITES")
        .env("GIT_DIR", repo.join(".git"))
        .env("TMPDIR", &tmp)
        .env("PROBE_REPO", &repo);
    for (k, v) in env {
        c.env(k, v);
    }
    (c.output().expect("blue test runs"), repo, tmp)
}

fn probe_value(repo: &Path) -> String {
    String::from_utf8_lossy(&git(repo, &["config", "blue.probe"]).stdout)
        .trim()
        .to_string()
}

#[test]
fn a_test_run_neither_reaches_the_inherited_repository_nor_writes_outside_its_temporary_root() {
    let root = place("default");
    let (o, repo, _) = run(&root, &[]);
    assert!(
        o.status.success(),
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    );
    assert_eq!(probe_value(&repo), "");
    assert!(!repo.join("leaked.txt").exists());
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn the_off_switches_restore_the_inherited_environment_and_unconfined_writes() {
    let root = place("off");
    let (o, repo, _) = run(
        &root,
        &[
            ("BLUE_TEST_ENV", "inherit"),
            ("BLUE_TEST_WRITES", "anywhere"),
        ],
    );
    assert!(
        !o.status.success(),
        "the write test expects a refusal and gets none"
    );
    assert_eq!(probe_value(&repo), "written");
    assert!(repo.join("leaked.txt").exists());
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_switch_outside_its_set_is_refused() {
    let root = place("bad");
    let (o, _, _) = run(&root, &[("BLUE_TEST_WRITES", "sometimes")]);
    assert!(!o.status.success());
    assert!(String::from_utf8_lossy(&o.stderr).contains("BLUE_TEST_WRITES"));
    let _ = std::fs::remove_dir_all(&root);
}
