use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn put(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).expect("write fixture");
}

fn text(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

struct Fixture {
    top: PathBuf,
    dist: PathBuf,
    app: PathBuf,
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.top);
    }
}

const ZED: &str = "@moduledoc \"\"\"\nzed: a fixture.\n\n    one #=> 1\n\"\"\"\n\n@doc \"\"\"\none: One.\n\n    one #=> 1\n\"\"\"\ndef one()\n  1\nend\n";

fn fixture(name: &str, app_bluefile: &str) -> Fixture {
    let top = std::env::temp_dir().join(format!("blue-verified-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&top);
    let dist = top.join("dist");
    let app = top.join("app");
    put(&dist.join("zed/Bluefile"), "package(\"zed\", \"0.1.0\")\n");
    put(&dist.join("zed/zed.b"), ZED);
    put(&app.join("Bluefile"), app_bluefile);
    put(&app.join("main.b"), "use(\"zed\", [:one])\n\none\n");
    Fixture {
        dist: dist.canonicalize().unwrap(),
        app: app.canonicalize().unwrap(),
        top,
    }
}

impl Fixture {
    fn blue(&self) -> Command {
        let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
        c.env("BLUE_PATH", &self.dist)
            .env_remove("BLUE_DIST")
            .env_remove("BLUE_CONFIG")
            .env_remove("BLUE_TIER")
            .env_remove("BLUE_LANG")
            .env("BLUE_TEST_CACHE", "off")
            .env("BLUE_CHECK_CACHE", "off");
        c
    }

    fn lock(&self) -> Output {
        self.blue().arg("lock").arg(&self.app).output().unwrap()
    }

    fn run(&self) -> Output {
        self.blue()
            .arg("run")
            .arg(self.app.join("main.b"))
            .output()
            .unwrap()
    }

    fn confirm(&self) -> Output {
        self.blue()
            .args(["bluefile", "--confirm"])
            .arg(self.app.join("Bluefile"))
            .output()
            .unwrap()
    }

    fn recorded(&self) -> serde_json::Value {
        let lock = std::fs::read_to_string(self.app.join("Bluefile.lock")).unwrap();
        serde_json::from_str::<serde_json::Value>(&lock).unwrap()["contents"].clone()
    }

    fn tamper(&self) {
        put(
            &self.dist.join("zed/zed.b"),
            &ZED.replace("  1\nend", "  2\nend"),
        );
    }

    fn restore(&self) {
        put(&self.dist.join("zed/zed.b"), ZED);
    }
}

const VERIFYING: &str =
    "package(\"the-app\", \"0.1.0\")\nneeds(\"zed\", \"^0.1\")\nverify(%i[contents])\n";

#[test]
fn a_bidama_whose_files_moved_after_the_lock_is_refused_and_restoring_it_loads_again() {
    let f = fixture("tamper", VERIFYING);
    let o = f.lock();
    assert!(o.status.success(), "{}", text(&o));
    let recorded = f.recorded();
    let zed = recorded["zed"].as_str().expect("zed is recorded");
    assert!(zed.starts_with("b3:") && zed.len() == 67, "{recorded}");

    let o = f.run();
    assert!(o.status.success(), "{}", text(&o));
    assert!(
        String::from_utf8_lossy(&o.stdout).contains('1'),
        "{}",
        text(&o)
    );

    f.tamper();
    let o = f.run();
    assert!(
        !o.status.success(),
        "a tampered bidama loaded: {}",
        text(&o)
    );
    let out = text(&o);
    assert!(out.contains("bidama \"zed\""), "{out}");
    assert!(
        out.contains(zed),
        "the refusal names the locked root: {out}"
    );
    assert!(out.contains("verify(:contents)"), "{out}");
    let o = f.confirm();
    assert!(
        !o.status.success(),
        "confirm passed a moved content root: {}",
        text(&o)
    );

    f.restore();
    let o = f.run();
    assert!(o.status.success(), "{}", text(&o));
    let o = f.confirm();
    assert!(o.status.success(), "{}", text(&o));
}

#[test]
fn a_relock_accepts_the_new_content_and_an_undeclared_root_records_and_compares_nothing() {
    let f = fixture("relock", VERIFYING);
    assert!(f.lock().status.success());
    let before = f.recorded();
    f.tamper();
    assert!(!f.run().status.success());
    let o = f.lock();
    assert!(
        o.status.success(),
        "a relock of a moved bidama: {}",
        text(&o)
    );
    assert_ne!(f.recorded(), before);
    let o = f.run();
    assert!(o.status.success(), "{}", text(&o));
    assert!(
        String::from_utf8_lossy(&o.stdout).contains('2'),
        "{}",
        text(&o)
    );

    let plain = fixture(
        "plain",
        "package(\"the-app\", \"0.1.0\")\nneeds(\"zed\", \"^0.1\")\n",
    );
    assert!(plain.lock().status.success());
    assert!(plain.recorded().is_null(), "{}", plain.recorded());
    plain.tamper();
    let o = plain.run();
    assert!(o.status.success(), "{}", text(&o));
}

#[test]
fn the_project_s_own_packages_are_never_recorded() {
    let f = fixture(
        "own",
        "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nneeds(\"zed\", \"^0.1\")\nneeds(\"mine\", \"^0.1\")\nverify(%i[contents])\n",
    );
    put(
        &f.app.join("bidamas/mine/Bluefile"),
        "package(\"mine\", \"0.1.0\")\n",
    );
    put(
        &f.app.join("bidamas/mine/mine.b"),
        &ZED.replace("zed", "mine").replace("one", "two"),
    );
    put(
        &f.app.join("main.b"),
        "use(\"mine\", [:two])\nuse(\"zed\", [:one])\n\none + two\n",
    );
    let o = f.lock();
    assert!(o.status.success(), "{}", text(&o));
    let recorded = f.recorded();
    assert!(recorded["zed"].is_string(), "{recorded}");
    assert!(recorded.get("mine").is_none(), "{recorded}");
    put(
        &f.app.join("bidamas/mine/extra.b"),
        "def three()\n  3\nend\n",
    );
    let o = f.run();
    assert!(o.status.success(), "{}", text(&o));
}
