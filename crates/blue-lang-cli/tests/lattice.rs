use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG");
    c
}

fn put(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).expect("write fixture");
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

fn project(name: &str, bluefile: &str, rede: &str, rede_bluefile: &str) -> PathBuf {
    let dir = std::env::temp_dir()
        .join(format!("blue-lattice-{name}-{}", std::process::id()))
        .join("app");
    let _ = std::fs::remove_dir_all(dir.parent().unwrap());
    put(&dir.join("Bluefile"), bluefile);
    put(
        &dir.join("main.b"),
        "use(\"porta\", [:fetch])\n\ndef main()\n  fetch(\"x\")\nend\n",
    );
    put(
        &dir.join("bidamas/porta/Bluefile"),
        "package(\"porta\", \"0.1.0\")\n",
    );
    put(
        &dir.join("bidamas/porta/porta.b"),
        "use(\"rede\", [:get])\n\ndef fetch(u)\n  get(u)\nend\n",
    );
    put(&dir.join("bidamas/rede/Bluefile"), rede_bluefile);
    put(&dir.join("bidamas/rede/rede.b"), rede);
    dir.canonicalize().unwrap()
}

const NETWORK: &str = "def get(u)\n  http_request(u)\nend\n";
const CLOCK: &str = "def get(u)\n  now_ms\nend\n";
const REDE: &str = "package(\"rede\", \"0.1.0\")\n";

fn lock(dir: &Path) -> Output {
    blue().arg("lock").arg(dir).output().unwrap()
}

#[test]
fn a_floor_past_the_ceiling_is_refused_with_the_path_to_the_breach() {
    let dir = project(
        "breach",
        "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nallow(%i[filesystem clock])\n",
        NETWORK,
        REDE,
    );
    let o = lock(&dir);
    assert!(!o.status.success(), "{}", err(&o));
    assert!(
        err(&o).contains(
            "[app] -> [porta] -> [rede: needs 'network'] violates ceiling [filesystem, clock]"
        ),
        "{}",
        err(&o)
    );
    assert!(
        !dir.join("Bluefile.lock").exists(),
        "a breach writes no lock"
    );
}

#[test]
fn a_virtual_provider_lets_a_leaf_that_needs_the_clock_resolve_under_a_pure_ceiling() {
    let bare = "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nallow([])\n";
    let dir = project("virtual", bare, CLOCK, REDE);
    let o = lock(&dir);
    assert!(!o.status.success());
    assert!(err(&o).contains("[rede: needs 'clock']"), "{}", err(&o));

    put(
        &dir.join("Bluefile"),
        &format!("{bare}virtualize(:clock, {{at_ms: 0, step_ms: 1}})\n"),
    );
    let o = lock(&dir);
    assert!(o.status.success(), "{}", err(&o));
    let text = std::fs::read_to_string(dir.join("Bluefile.lock")).unwrap();
    let written: serde_json::Value = serde_json::from_str(&text).unwrap();
    let caps = &written["capabilities"];
    assert_eq!(
        caps["provided"]["clock"]["provider"], "stepped-clock",
        "{text}"
    );
    assert_eq!(
        caps["packages"]["rede"],
        serde_json::json!(["clock"]),
        "{text}"
    );
    assert_eq!(caps["packages"]["porta"], serde_json::json!([]), "{text}");
    assert_eq!(caps["ceiling"], serde_json::json!([]), "{text}");
    assert_eq!(
        written["manifest"]["virtualized"]["clock"]["step_ms"], 1,
        "{text}"
    );

    let confirm = |dir: &Path| {
        blue()
            .args(["bluefile", "--confirm"])
            .arg(dir.join("Bluefile"))
            .output()
            .unwrap()
    };
    let fresh = confirm(&dir);
    assert!(fresh.status.success(), "{}", err(&fresh));

    let mut edited = written.clone();
    edited["capabilities"]["floor"] = serde_json::json!(["clock", "network"]);
    put(
        &dir.join("Bluefile.lock"),
        &serde_json::to_string_pretty(&edited).unwrap(),
    );
    let stale = confirm(&dir);
    assert!(!stale.status.success(), "a hand-widened floor is stale");
    assert!(
        err(&stale).contains("recorded capabilities"),
        "{}",
        err(&stale)
    );

    put(&dir.join("bidamas/rede/rede.b"), NETWORK);
    let o = lock(&dir);
    assert!(
        !o.status.success(),
        "a leaf that now reaches the network is refused"
    );
    assert!(err(&o).contains("[rede: needs 'network']"), "{}", err(&o));
}

#[test]
fn a_declared_reach_must_cover_what_the_code_names() {
    let dir = project(
        "declared",
        "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nallow(%i[clock filesystem])\n",
        CLOCK,
        "package(\"rede\", \"0.1.0\")\nreach(%i[filesystem])\n",
    );
    let o = lock(&dir);
    assert!(!o.status.success());
    assert!(
        err(&o).contains("`rede` declares reach [filesystem] but its code reaches clock"),
        "{}",
        err(&o)
    );
}

#[test]
fn only_clock_entropy_and_filesystem_have_pure_providers() {
    let dir = project(
        "provider",
        "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nvirtualize(:network, {})\n",
        NETWORK,
        REDE,
    );
    let o = lock(&dir);
    assert!(!o.status.success());
    assert!(
        err(&o).contains("network has no pure provider"),
        "{}",
        err(&o)
    );
}

#[test]
fn blue_run_holds_a_program_to_its_projects_allow_and_providers() {
    let dir = project(
        "run",
        "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nallow([])\nvirtualize(:clock, {at_ms: 1000, step_ms: 5})\n",
        CLOCK,
        REDE,
    );
    put(
        &dir.join("main.b"),
        "use(\"porta\", [:fetch])\n\ndef main()\n  write_stdout(\"#{fetch(\"x\")} #{now_ms}\")\nend\n",
    );
    for leaf in ["bidamas/rede", "bidamas/porta"] {
        let o = lock(&dir.join(leaf));
        assert!(o.status.success(), "{leaf}: {}", err(&o));
    }
    let o = blue()
        .args(["run", "--quiet"])
        .arg(dir.join("main.b"))
        .output()
        .unwrap();
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(String::from_utf8_lossy(&o.stdout), "1000 1005");

    put(
        &dir.join("bidamas/rede/rede.b"),
        "def get(u)\n  read_file(u) rescue \"swallowed\"\nend\n",
    );
    let o = blue()
        .args(["run", "--quiet"])
        .arg(dir.join("main.b"))
        .output()
        .unwrap();
    assert_eq!(o.status.code(), Some(77), "{}", err(&o));
    assert!(
        err(&o).contains("capability breach: `read_file` reaches the host (filesystem)"),
        "{}",
        err(&o)
    );
}

#[test]
fn a_root_with_no_ceiling_locks_as_before() {
    let dir = project(
        "none",
        "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\n",
        NETWORK,
        REDE,
    );
    let o = lock(&dir);
    assert!(o.status.success(), "{}", err(&o));
    let text = std::fs::read_to_string(dir.join("Bluefile.lock")).unwrap();
    assert!(!text.contains("capabilities"), "{text}");
}
