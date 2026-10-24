//! **The rename bridge (`legacy_names`), end to end.** A bidama `lk` renamed
//! `lk_hours` to `hours` and declared `legacy_names("0.1.1", "lk")`. A caller
//! still writing `lk::lk_hours()`:
//!
//! - outside `lk`'s distribution, while the window is open: B0021 as a
//!   WARNING, and the program checks and runs;
//! - inside the distribution: the same B0021 as an ERROR — a bidama's own
//!   repository can never depend on its bridge;
//! - once `lk` reaches 0.2.0 the bridge is closed: the old name resolves to
//!   nothing (B0011), with a machine-applicable fix read from the ledger,
//!   which `blue check --fix` applies.
//!
//! Red run (2026-09-29), `inside_distribution` answering true for every
//! file: the outside caller's B0021 is an error and `blue check` exits 1.

use std::path::{Path, PathBuf};
use std::process::Command;

fn blue(dist: &Path) -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env("BLUE_PATH", dist)
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER");
    c
}

fn write(p: &Path, s: &str) {
    std::fs::create_dir_all(p.parent().expect("parent")).expect("mkdir");
    std::fs::write(p, s).expect("write");
}

fn check(dist: &Path, file: &Path, extra: &[&str]) -> (i32, String) {
    let out = blue(dist)
        .arg("check")
        .args(extra)
        .args(["--format", "json"])
        .arg(file)
        .output()
        .expect("spawn");
    (
        out.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&out.stdout).into_owned(),
    )
}

fn bidama(dist: &Path, name: &str, bluefile: &str, source: &str) {
    write(&dist.join(name).join("Bluefile"), bluefile);
    write(&dist.join(name).join(format!("{name}.b")), source);
    let out = blue(dist)
        .arg("lock")
        .arg(dist.join(name))
        .output()
        .expect("lock");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

fn lk(dist: &Path, version: &str) {
    bidama(
        dist,
        "lk",
        &format!("package(\"lk\", \"{version}\")\n"),
        "legacy_names(\"0.1.1\", \"lk\")\n\ndef hours()\n  1\nend\n",
    );
}

#[test]
fn the_bridge_warns_outside_refuses_inside_and_closes_at_the_next_minor() {
    let root: PathBuf = std::env::temp_dir().join(format!("blue-legacy-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dist = root.join("bidamas");
    lk(&dist, "0.1.1");
    let caller = "use(\"lk\")\n\nlk::lk_hours\n";
    let outside = root.join("app/main.b");
    write(&outside, caller);
    let inside = dist.join("user.b");
    write(&inside, caller);

    let (code, json) = check(&dist, &outside, &[]);
    assert_eq!(code, 0, "{json}");
    assert!(
        json.contains("\"code\":\"B0021\"") && json.contains("\"severity\":\"warning\""),
        "{json}"
    );
    let run = blue(&dist).arg("run").arg(&outside).output().expect("run");
    assert!(
        run.status.success(),
        "{}",
        String::from_utf8_lossy(&run.stderr)
    );

    let (code, json) = check(&dist, &inside, &[]);
    assert_eq!(code, 1, "{json}");
    assert!(
        json.contains("\"code\":\"B0021\"") && json.contains("\"severity\":\"error\""),
        "{json}"
    );

    // 0.2.0: the window is closed; the ledger still says what the name is.
    lk(&dist, "0.2.0");
    let (code, json) = check(&dist, &outside, &[]);
    assert_eq!(code, 1, "{json}");
    assert!(json.contains("\"code\":\"B0011\""), "{json}");
    assert!(
        json.contains("\"applicability\":\"machine-applicable\""),
        "{json}"
    );
    let (code, _) = check(&dist, &outside, &["--fix"]);
    assert_eq!(code, 0);
    assert_eq!(
        std::fs::read_to_string(&outside).expect("read"),
        "use(\"lk\")\n\nlk::hours\n"
    );
    let _ = std::fs::remove_dir_all(&root);
}

fn moved(dist: &Path, version: &str) {
    bidama(
        dist,
        "hm",
        "package(\"hm\", \"0.1.0\")\n",
        "def hours()\n  1\nend\n\ndef minutes()\n  60\nend\n",
    );
    bidama(
        dist,
        "mv",
        &format!("package(\"mv\", \"{version}\")\nneeds(\"hm\", \"^0.1\")\n"),
        "use(\"hm\")\n\nlegacy_names(\"0.1.1\", \"mv\")\n\nlegacy_names(\"0.1.2\", [[\"hours\", \"hm::hours\"], [\"mins\", \"hm::minutes\"]])\n\ndef days()\n  hm::hours() * 24\nend\n",
    );
}

/// **A moved definition keeps its old name as a bridge.** Bidama `mv` moved
/// `hours` to `hm::hours` and `mins` to `hm::minutes`, and declared
/// `legacy_names("0.1.2", [["hours", "hm::hours"], ["mins", "hm::minutes"]])`.
/// The old spellings — and the older prefixed one, `mv::mv_mins` — reach the
/// new home: a warning outside the distribution (and the program runs), an
/// error inside, and at 0.2.0 a closed bridge whose fix names the new home.
///
/// Red run (2026-09-30), before moved names: `mv::hours()` is B0011
/// (`bidama mv defines no hours`) and the outside caller exits 1.
#[test]
fn a_moved_name_bridges_to_its_new_home() {
    let root: PathBuf = std::env::temp_dir().join(format!("blue-moved-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dist = root.join("bidamas");
    moved(&dist, "0.1.2");
    let caller = "use(\"mv\")\n\nprint(mv::hours + mv::mins + mv::mv_mins)\n";
    let outside = root.join("app/main.b");
    write(&outside, caller);
    let inside = dist.join("user.b");
    write(&inside, caller);

    let (code, json) = check(&dist, &outside, &[]);
    assert_eq!(code, 0, "{json}");
    assert_eq!(json.matches("\"code\":\"B0021\"").count(), 3, "{json}");
    assert!(json.contains("\"severity\":\"warning\""), "{json}");
    assert!(json.contains("moved out of bidama `mv`"), "{json}");
    let run = blue(&dist).arg("run").arg(&outside).output().expect("run");
    assert!(
        run.status.success(),
        "{}",
        String::from_utf8_lossy(&run.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&run.stdout).lines().next(),
        Some("121")
    );

    let (code, json) = check(&dist, &inside, &[]);
    assert_eq!(code, 1, "{json}");
    assert!(json.contains("\"severity\":\"error\""), "{json}");

    // Inside the window, `--fix` rewrites every old spelling to the new home.
    let (code, _) = check(&dist, &outside, &["--fix"]);
    assert_eq!(code, 0);
    assert_eq!(
        std::fs::read_to_string(&outside).expect("read"),
        "use(\"hm\")\n\nprint(hm::hours + hm::minutes + hm::minutes)\n"
    );

    // 0.2.0: closed; the ledger's fix still names the new home.
    write(&outside, caller);
    moved(&dist, "0.2.0");
    let (code, json) = check(&dist, &outside, &[]);
    assert_eq!(code, 1, "{json}");
    assert!(json.contains("\"code\":\"B0011\""), "{json}");
    let (code, json) = check(&dist, &outside, &["--fix"]);
    assert_eq!(code, 0, "{json}");
    assert_eq!(
        std::fs::read_to_string(&outside).expect("read"),
        "use(\"hm\")\n\nprint(hm::hours + hm::minutes + hm::minutes)\n"
    );
    let _ = std::fs::remove_dir_all(&root);
}

/// A moves declaration that cannot mean one thing is B0022: a name still
/// defined, a home that is not loaded, a home that defines no such name.
#[test]
fn a_move_that_cannot_mean_one_thing_is_refused() {
    let root: PathBuf = std::env::temp_dir().join(format!("blue-moved-bad-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dist = root.join("bidamas");
    moved(&dist, "0.1.2");
    write(
        &dist.join("mv/mv.b"),
        "use(\"hm\")\n\nlegacy_names(\"0.1.2\", [[\"days\", \"hm::days\"], [\"x\", \"hm::nope\"], [\"y\", \"zz::y\"]])\n\ndef days()\n  hm::hours() * 24\nend\n",
    );
    let (code, json) = check(&dist, &dist.join("mv/mv.b"), &[]);
    assert_eq!(code, 1, "{json}");
    assert_eq!(json.matches("\"code\":\"B0022\"").count(), 3, "{json}");
    assert!(json.contains("is still defined in `mv`"), "{json}");
    assert!(json.contains("defines no `nope`"), "{json}");
    assert!(json.contains("which is not loaded"), "{json}");
    let _ = std::fs::remove_dir_all(&root);
}

/// **A retired word ships its fixer** (R2 in docs/COMPOUNDING.md). `rk`
/// retired `refuse(found)` for `enforce(found, [(fs) -> fs], {kind: :first})`
/// and declared the row. A caller still writing `rk::refuse(x)`, qualified or
/// imported, is refused at once (no window: the break is the upgrade's), the
/// error names `blue check --fix`, and the fix writes the replacement with
/// its arguments, after which the file checks and its test passes.
///
/// Red run (2026-10-23): the append edit dropped from `retired_edits`; the
/// fixed file read `rk::enforce(found)` and the assertion on its arguments
/// failed.
#[test]
fn a_retired_word_is_refused_and_fixed_with_its_new_arguments() {
    let root: PathBuf = std::env::temp_dir().join(format!("blue-retire-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dist = root.join("bidamas");
    write(&dist.join("rk/Bluefile"), "package(\"rk\", \"0.1.2\")\n");
    write(
        &dist.join("rk/rk.b"),
        "legacy_names(\n  \"0.1.2\",\n  [[\"refuse\", \"rk::enforce\", \"[(fs) -> fs], {kind: :first}\"]]\n)\n\ndef enforce(subject, rules, opts)\n  found = flat_map(rules, (rule) -> rule(subject))\n  if found == []\n    nil\n  else\n    raise(get(opts, :kind), \"refused\")\n  end\nend\n",
    );
    let out = blue(&dist)
        .arg("lock")
        .arg(dist.join("rk"))
        .output()
        .expect("lock");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    for (tag, src) in [
        (
            "qualified",
            "use(\"rk\")\n\ndef go(found)\n  rk::refuse(found)\nend\n\ntest \"go\"\n  assert go([]).nil?\nend\n",
        ),
        (
            "imported",
            "use(\"rk\", [:refuse])\n\ndef go(found)\n  refuse(found)\nend\n\ntest \"go\"\n  assert go([]).nil?\nend\n",
        ),
    ] {
        let file = root.join(format!("app/{tag}.b"));
        write(&file, src);
        let out = blue(&dist).arg("check").arg(&file).output().expect("check");
        let shown = String::from_utf8_lossy(&out.stderr).into_owned();
        assert!(!out.status.success(), "{tag}: a retired word must not check");
        assert!(shown.contains("retired"), "{tag}: {shown}");
        assert!(
            shown.contains(&format!("fix: blue check --fix {}", file.display())),
            "{tag}: {shown}"
        );
        let out = blue(&dist)
            .args(["check", "--fix"])
            .arg(&file)
            .output()
            .expect("fix");
        let fixed = std::fs::read_to_string(&file).expect("read");
        assert!(
            out.status.success(),
            "{tag}: {}\n{fixed}",
            String::from_utf8_lossy(&out.stderr)
        );
        assert!(
            fixed.contains("enforce(found, [(fs) -> fs], {kind: :first})"),
            "{tag}: {fixed}"
        );
        let out = blue(&dist).arg("test").arg(&file).output().expect("test");
        assert!(
            out.status.success(),
            "{tag}: {}",
            String::from_utf8_lossy(&out.stderr)
        );
    }
}

fn shadowing(dist: &Path, version: &str, declared: &str) {
    bidama(
        dist,
        "sh",
        &format!("package(\"sh\", \"{version}\")\n"),
        &format!(
            "{declared}def trim(s)\n  :sh\nend\n\ndef first(xs)\n  :sh\nend\n\ndef read(x)\n  :sh\nend\n\ndef inner(s)\n  [trim(s), first([s]), read(s)]\nend\n"
        ),
    );
}

fn run(dist: &Path, file: &Path) -> Vec<String> {
    let out = blue(dist).arg("run").arg(file).output().expect("run");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(str::to_string)
        .collect()
}

#[test]
fn a_bidama_definition_never_changes_an_importers_builtin_call() {
    let root: PathBuf = std::env::temp_dir().join(format!("blue-shadow-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dist = root.join("bidamas");
    shadowing(&dist, "0.1.0", "");
    let caller = root.join("app/main.b");
    write(
        &caller,
        "use(\"sh\")\n\nprint([trim(\"  a  \"), first([1, 2]), sh::inner(\"x\")])\nprint(read(42) rescue :dispatched)\n",
    );
    let (code, json) = check(&dist, &caller, &[]);
    assert_eq!(code, 0, "{json}");
    assert!(!json.contains("\"code\":\"B0012\""), "{json}");
    assert_eq!(
        run(&dist, &caller)[..2],
        ["(\"a\" 1 (:sh :sh :sh))", ":dispatched"]
    );
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_flat_era_name_keeps_the_implicit_reference_error_only_inside_its_window() {
    let root: PathBuf = std::env::temp_dir().join(format!("blue-flat-era-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dist = root.join("bidamas");
    let declared = "legacy_names(\"0.1.0\", [:first])\n\n";
    shadowing(&dist, "0.1.0", declared);
    let caller = root.join("app/main.b");
    let text = "use(\"sh\")\n\nprint([trim(\"  a  \"), first([1, 2])])\n";
    write(&caller, text);
    let (code, json) = check(&dist, &caller, &[]);
    assert_eq!(code, 1, "{json}");
    assert_eq!(json.matches("\"code\":\"B0012\"").count(), 1, "{json}");
    assert!(json.contains("`first` is bidama `sh`'s"), "{json}");
    let (code, _) = check(&dist, &caller, &["--fix"]);
    assert_eq!(code, 0);
    assert_eq!(
        std::fs::read_to_string(&caller).expect("read"),
        "use(\"sh\")\n\nprint([trim(\"  a  \"), sh::first([1, 2])])\n"
    );

    write(&caller, text);
    shadowing(&dist, "0.2.0", declared);
    let (code, json) = check(&dist, &caller, &[]);
    assert_eq!(code, 0, "{json}");
    assert!(!json.contains("\"code\":\"B0012\""), "{json}");
    assert_eq!(run(&dist, &caller)[..1], ["(\"a\" 1)"]);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_flat_era_entry_that_cannot_mean_one_thing_is_refused_alone() {
    let root: PathBuf =
        std::env::temp_dir().join(format!("blue-flat-era-bad-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dist = root.join("bidamas");
    shadowing(&dist, "0.1.0", "");
    let source = std::fs::read_to_string(dist.join("sh/sh.b")).expect("read");
    write(
        &dist.join("sh/sh.b"),
        &format!("legacy_names(\"0.1.0\", [:first, :inner, :nope, :read, :first])\n\n{source}"),
    );
    let (code, json) = check(&dist, &dist.join("sh/sh.b"), &[]);
    assert_eq!(code, 1, "{json}");
    assert_eq!(json.matches("\"code\":\"B0022\"").count(), 4, "{json}");
    assert!(json.contains("shares no builtin's name"), "{json}");
    assert!(json.contains("defines no `nope`"), "{json}");
    assert!(json.contains("`read` is a master verb"), "{json}");
    assert!(json.contains("`:first` is listed twice"), "{json}");
    let caller = root.join("app/main.b");
    write(&caller, "use(\"sh\")\n\nprint(first([1, 2]))\n");
    let (_, json) = check(&dist, &caller, &[]);
    assert!(json.contains("`first` is bidama `sh`'s"), "{json}");
    let _ = std::fs::remove_dir_all(&root);
}
