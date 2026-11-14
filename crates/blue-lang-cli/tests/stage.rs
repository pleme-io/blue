use std::path::{Path, PathBuf};
use std::process::Command;

const GREEN: &str = "def one()\n  1\nend\n\ntest \"one\"\n  assert one == 1\nend\n";
const RED: &str = "def one()\n  1\nend\n\ntest \"one\"\n  assert one == 2\nend\n";

struct Project(PathBuf);

impl Project {
    fn new(name: &str, bluefile: &str, files: &[(&str, &str)]) -> Self {
        let root = std::env::temp_dir().join(format!("blue-stage-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join(".git")).expect("scratch dir");
        std::fs::write(root.join("Bluefile"), bluefile).expect("Bluefile");
        for (path, src) in files {
            let p = root.join(path);
            std::fs::create_dir_all(p.parent().expect("parent")).expect("dir");
            std::fs::write(p, src).expect("file");
        }
        let locked = blue(&root, &["lock", "."]);
        assert!(locked.0, "blue lock: {}", locked.1);
        Self(root)
    }

    fn stage(&self, args: &[&str]) -> (bool, String) {
        let mut all = vec!["test", "."];
        all.extend_from_slice(args);
        blue(&self.0, &all)
    }
}

impl Drop for Project {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn blue(dir: &Path, args: &[&str]) -> (bool, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .args(args)
        .current_dir(dir)
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("GEN_ROOT")
        .env("BLUE_TEST_CACHE", "off")
        .output()
        .expect("blue runs");
    (
        out.status.success(),
        format!(
            "{}{}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        ),
    )
}

const BLUEFILE: &str = "package(\"p\", \"0.1.0\")\n\
    check(\"quick\", \"gate/quick.b\", {stage: :push, kind: :unit})\n\
    check(\"slow\", \"gate/slow.b\", [\"gate\"], {stage: :ci})\n";

/// **`blue test DIR --stage S` runs exactly the rows of that stage.** A red
/// row of another stage is not run, a red row of the stage fails the run,
/// and `--kind` narrows it further.
///
/// Red run (2026-11-13): `stage::selected` answering every row: `a red ci
/// row reached a push run`.
#[test]
fn a_stage_runs_its_own_rows_and_no_other() {
    let p = Project::new(
        "select",
        BLUEFILE,
        &[("gate/quick.b", GREEN), ("gate/slow.b", RED)],
    );
    let (ok, out) = p.stage(&["--stage", "push"]);
    assert!(ok, "a red ci row reached a push run: {out}");
    assert!(out.contains("✅ check quick"), "{out}");
    assert!(!out.contains("check slow"), "{out}");
    let (ok, out) = p.stage(&["--stage", "ci"]);
    assert!(!ok, "the red ci row fails its stage: {out}");
    assert!(out.contains("❌ check slow"), "{out}");
    let (ok, out) = p.stage(&["--stage", "push", "--kind", "e2e"]);
    assert!(ok && out.contains("no check row"), "{out}");
    let (ok, out) = p.stage(&["--stage", "release"]);
    assert!(ok && out.contains("no check row"), "{out}");
}

#[test]
fn a_stage_or_kind_blue_does_not_know_is_refused() {
    let p = Project::new(
        "refuse",
        BLUEFILE,
        &[("gate/quick.b", GREEN), ("gate/slow.b", GREEN)],
    );
    let (ok, out) = p.stage(&["--stage", "nightly"]);
    assert!(!ok && out.contains("push, ci, release"), "{out}");
    let (ok, out) = p.stage(&["--stage", "push", "--kind", "fuzz"]);
    assert!(!ok && out.contains("--kind"), "{out}");
}

/// **A check row with no stage is refused where its program is checked.**
#[test]
fn an_unstaged_row_s_program_is_refused_by_b0092() {
    let p = Project::new(
        "unstaged",
        "package(\"p\", \"0.1.0\")\ncheck(\"bare\", \"gate/bare.b\")\n",
        &[("gate/bare.b", GREEN)],
    );
    let (ok, out) = blue(&p.0, &["test", "gate/bare.b"]);
    assert!(!ok && out.contains("B0092"), "{out}");
}
