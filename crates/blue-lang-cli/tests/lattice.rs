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
        &format!(
            "{bare}virtualize(:clock, {{using: :deterministic_stepped, at_ms: 0, step_ms: 1}})\n"
        ),
    );
    let o = lock(&dir);
    assert!(o.status.success(), "{}", err(&o));
    let text = std::fs::read_to_string(dir.join("Bluefile.lock")).unwrap();
    let written: serde_json::Value = serde_json::from_str(&text).unwrap();
    let caps = &written["capabilities"];
    assert_eq!(
        caps["provided"]["clock"]["provider"], "deterministic-stepped",
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
        "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nallow([])\nvirtualize(:clock, {using: :deterministic_stepped, at_ms: 1000, step_ms: 5})\n",
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

fn run(dir: &Path, extra: &[&str]) -> Output {
    blue()
        .args(["run", "--quiet"])
        .args(extra)
        .arg(dir.join("main.b"))
        .output()
        .unwrap()
}

fn out(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn lock_leaves(dir: &Path) {
    for leaf in ["bidamas/rede", "bidamas/porta"] {
        let o = lock(&dir.join(leaf));
        assert!(o.status.success(), "{leaf}: {}", err(&o));
    }
}

const SCOPED_CLOCK: &str = "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nallow([])\nvirtualize(:clock, {using: :deterministic_stepped, at_ms: 1000, step_ms: 5, for: %w[rede]})\n";

#[test]
fn every_using_spelling_locks_and_runs_its_provider() {
    let host = "def get(u)\n  write_file(\"/t\", \"kept\")\n  \"#{now_ms} #{now_ms} #{length(random_bytes(2))} #{read_file(\"/t\")}\"\nend\n";
    let fixed = "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nallow([])\nvirtualize(:clock, {using: :deterministic_stepped, at_ms: 1000, step_ms: 5})\nvirtualize(:entropy, {using: :seeded_prng, seed: \"s\"})\n";
    let dir = project(
        "using",
        &format!("{fixed}virtualize(:filesystem, {{using: :in_memory_overlay}})\n"),
        host,
        REDE,
    );
    put(
        &dir.join("main.b"),
        "use(\"porta\", [:fetch])\n\ndef main()\n  write_stdout(fetch(\"x\"))\nend\n",
    );
    lock_leaves(&dir);
    let o = lock(&dir);
    assert!(o.status.success(), "{}", err(&o));
    let text = std::fs::read_to_string(dir.join("Bluefile.lock")).unwrap();
    let written: serde_json::Value = serde_json::from_str(&text).unwrap();
    let provided = &written["capabilities"]["provided"];
    assert_eq!(
        provided["clock"]["provider"], "deterministic-stepped",
        "{text}"
    );
    assert_eq!(provided["entropy"]["provider"], "seeded-prng", "{text}");
    assert_eq!(
        provided["filesystem"]["provider"], "in-memory-overlay",
        "{text}"
    );
    let o = run(&dir, &[]);
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "1000 1005 2 kept");

    put(
        &dir.join("Bluefile"),
        &format!("{fixed}virtualize(:filesystem, {{using: :null_sink}})\n"),
    );
    let o = lock(&dir);
    assert!(o.status.success(), "{}", err(&o));
    let text = std::fs::read_to_string(dir.join("Bluefile.lock")).unwrap();
    assert!(text.contains("\"null-sink\""), "{text}");
    let o = run(&dir, &[]);
    assert!(
        !o.status.success(),
        "a null sink keeps nothing to read back"
    );
    assert!(err(&o).contains("virtual filesystem"), "{}", err(&o));
}

#[test]
fn an_unknown_using_is_refused_by_name() {
    let dir = project(
        "unknown-using",
        "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nallow([])\nvirtualize(:clock, {using: :wall_clock})\n",
        CLOCK,
        REDE,
    );
    let o = lock(&dir);
    assert!(!o.status.success());
    assert!(
        err(&o).contains(
            "`using: :wall_clock` is not a clock provider; it takes :deterministic_stepped"
        ),
        "{}",
        err(&o)
    );
    assert!(!dir.join("Bluefile.lock").exists());

    put(
        &dir.join("Bluefile"),
        "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nallow([])\nvirtualize(:filesystem, {mode: :memory})\n",
    );
    let o = lock(&dir);
    assert!(
        !o.status.success(),
        "the retired `mode:` spelling is refused"
    );
    assert!(
        err(&o).contains("filesystem needs `using:`, one of :in_memory_overlay, :null_sink"),
        "{}",
        err(&o)
    );
}

#[test]
fn a_scoped_clock_serves_its_leaf_and_not_the_root_or_an_unscoped_package() {
    let dir = project("scoped", SCOPED_CLOCK, CLOCK, REDE);
    put(
        &dir.join("main.b"),
        "use(\"porta\", [:fetch])\n\ndef main()\n  write_stdout(\"#{fetch(\"x\")} #{fetch(\"y\")}\")\nend\n",
    );
    lock_leaves(&dir);
    let o = lock(&dir);
    assert!(o.status.success(), "{}", err(&o));
    let text = std::fs::read_to_string(dir.join("Bluefile.lock")).unwrap();
    let written: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(
        written["capabilities"]["provided"]["clock"]["for"],
        serde_json::json!(["rede"]),
        "{text}"
    );
    let o = run(&dir, &[]);
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "1000 1005", "rede reads the virtual clock");

    put(
        &dir.join("main.b"),
        "use(\"porta\", [:fetch])\n\ndef main()\n  write_stdout(\"#{fetch(\"x\")} #{now_ms}\")\nend\n",
    );
    let o = run(&dir, &[]);
    assert!(!o.status.success(), "the root's own now_ms is not rede's");
    assert_eq!(out(&o), "", "refused before it runs");
    assert!(
        err(&o).contains("refused: `now_ms` reaches the host (clock)"),
        "{}",
        err(&o)
    );

    put(
        &dir.join("main.b"),
        "use(\"porta\", [:fetch])\n\ndef main()\n  write_stdout(\"before \")\n  write_stdout(fetch(\"x\"))\nend\n",
    );
    put(
        &dir.join("bidamas/porta/porta.b"),
        "use(\"rede\", [:get])\n\ndef fetch(u)\n  \"#{get(u)} #{now_ms}\"\nend\n",
    );
    let o = run(&dir, &[]);
    assert_eq!(o.status.code(), Some(77), "{}", err(&o));
    assert_eq!(out(&o), "before ");
    assert!(
        err(&o).contains("capability breach: `now_ms` reaches the host (clock)"),
        "{}",
        err(&o)
    );
}

#[test]
fn blue_lock_refuses_an_unscoped_package_that_needs_the_scoped_capability() {
    let dir = project("scoped-lock", SCOPED_CLOCK, CLOCK, REDE);
    put(
        &dir.join("bidamas/porta/porta.b"),
        "use(\"rede\", [:get])\n\ndef fetch(u)\n  \"#{get(u)} #{now_ms}\"\nend\n",
    );
    let o = lock(&dir);
    assert!(!o.status.success());
    assert!(
        err(&o).contains(
            "[app] -> [porta: needs 'clock'] violates ceiling [] (clock is virtualized only for [rede] and what they use)"
        ),
        "{}",
        err(&o)
    );
    assert!(!dir.join("Bluefile.lock").exists());

    put(
        &dir.join("Bluefile"),
        &SCOPED_CLOCK.replace("%w[rede]", "%w[porta]"),
    );
    let o = lock(&dir);
    assert!(
        o.status.success(),
        "porta and rede, which it uses: {}",
        err(&o)
    );

    put(
        &dir.join("Bluefile"),
        &SCOPED_CLOCK.replace("%w[rede]", "%w[nowhere]"),
    );
    let o = lock(&dir);
    assert!(!o.status.success());
    assert!(
        err(&o).contains("is for `nowhere`, which [app] does not use"),
        "{}",
        err(&o)
    );
}

#[test]
fn allow_none_still_runs_a_leaf_its_project_virtualizes() {
    let scoped = "package(\"app\", \"0.1.0\")\npackages(\"bidamas\")\nvirtualize(:clock, {using: :deterministic_stepped, at_ms: 42, for: %w[rede]})\n";
    let dir = project("allow-none", scoped, CLOCK, REDE);
    lock_leaves(&dir);
    put(
        &dir.join("main.b"),
        "use(\"porta\", [:fetch])\n\ndef main()\n  write_stdout(\"#{fetch(\"x\")}\")\nend\n",
    );
    let o = run(&dir, &["--allow", "none"]);
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "42");

    put(
        &dir.join("bidamas/rede/rede.b"),
        "def get(u)\n  \"#{now_ms} #{getenv(\"HOME\")}\"\nend\n",
    );
    let o = run(&dir, &["--allow", "none"]);
    assert_eq!(
        o.status.code(),
        Some(77),
        "the provider stands in for the clock only: {}",
        err(&o)
    );
    assert!(
        err(&o).contains("capability breach: `getenv` reaches the host (environment)"),
        "{}",
        err(&o)
    );

    put(
        &dir.join("Bluefile"),
        &scoped.replace(", for: %w[rede]", ""),
    );
    put(&dir.join("bidamas/rede/rede.b"), CLOCK);
    let o = run(&dir, &["--allow", "none"]);
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(out(&o), "42", "a whole-program provider runs it too");
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
