#[macro_use]
mod moduledoc;

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use serde_json::Value as Json;

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG")
        .env_remove("BLUE_CRASH_JOURNAL")
        .env(
            "BLUE_PATH",
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../bidamas"),
        );
    c
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-storage-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir.canonicalize().expect("canonical scratch dir")
}

fn put(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().expect("a parent")).expect("fixture dir");
    std::fs::write(path, text).expect("write fixture");
}

fn out(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

fn lock(dir: &Path) -> Output {
    blue().arg("lock").arg(dir).output().expect("blue lock")
}

fn locked(dir: &Path) {
    let o = lock(dir);
    assert!(
        o.status.success(),
        "blue lock {}: {}",
        dir.display(),
        err(&o)
    );
}

fn lock_of(dir: &Path) -> Json {
    serde_json::from_str(&std::fs::read_to_string(dir.join("Bluefile.lock")).expect("lock"))
        .expect("lock json")
}

fn run(file: &Path, allow: &[&str]) -> Output {
    let mut c = blue();
    c.args(["run", "--quiet"]);
    for a in allow {
        c.args(["--allow", a]);
    }
    c.arg(file).output().expect("blue run")
}

const SPILL: &str =
    "def overwrite(p)\n  write_file(p, \"gone\")\nend\n\ndef remove(p)\n  rm(p)\nend\n";

fn appends(log: &Path) -> String {
    let l = log.display();
    format!(
        "{}def main()\n  append_log(\"{l}\", \"one\")\n  append_log(\"{l}\", \"two\")\n  write_stdout(join(read_log(\"{l}\"), \",\"))\nend\n",
        moduledoc!(
            "log appends two entries to its log, and writes what it reads back.",
            "join(%w[one two], \",\") #=> \"one,two\""
        )
    )
}

fn both(log: &Path) -> String {
    let l = log.display();
    format!(
        "{}def main()\n  append_file(\"{l}\", \"one\\n\")\n  append_log(\"{l}\", \"two\")\n  write_stdout(join(read_log(\"{l}\"), \",\"))\nend\n",
        moduledoc!(
            "both appends a line as a file and an entry as a log, and writes what it reads back.",
            "join(%w[one two], \",\") #=> \"one,two\""
        )
    )
}

fn spills(log: &Path, word: &str) -> String {
    let l = log.display();
    format!("use(\"spill\", [:{word}])\n\ndef main()\n  append_log(\"{l}\", \"three\")\n  {word}(\"{l}\") rescue write_stdout(\"swallowed\")\n  write_stdout(\"after\")\nend\n")
}

#[test]
fn a_program_held_to_storage_append_appends_and_reads_and_a_write_or_rm_is_a_fatal_breach_no_rescue_sees(
) {
    let dir = scratch("held");
    put(
        &dir.join("Bluefile"),
        "package(\"logapp\", \"0.1.0\")\npackages(\"bidamas\")\n",
    );
    put(
        &dir.join("bidamas/spill/Bluefile"),
        "package(\"spill\", \"0.1.0\")\n",
    );
    put(&dir.join("bidamas/spill/spill.b"), SPILL);
    let log = dir.join("logs/app.log");
    put(&dir.join("log.b"), &appends(&log));
    put(&dir.join("overwrite.b"), &spills(&log, "overwrite"));
    put(&dir.join("remove.b"), &spills(&log, "remove"));
    locked(&dir.join("bidamas/spill"));
    locked(&dir);

    let o = run(&dir.join("log.b"), &["storage_append"]);
    assert!(o.status.success(), "{}{}", out(&o), err(&o));
    assert_eq!(out(&o), "one,two");
    assert_eq!(std::fs::read_to_string(&log).unwrap(), "one\ntwo\n");

    for (file, host) in [("overwrite.b", "write_file"), ("remove.b", "rm")] {
        let o = run(&dir.join(file), &["storage_append"]);
        assert_eq!(o.status.code(), Some(77), "{file}: {}{}", out(&o), err(&o));
        assert!(
            err(&o).contains(&format!("`{host}` reaches the host (filesystem)")),
            "{file}: {}",
            err(&o)
        );
        assert!(
            !out(&o).contains("swallowed") && !out(&o).contains("after"),
            "{file}: {}",
            out(&o)
        );
    }
    assert_eq!(
        std::fs::read_to_string(&log).unwrap(),
        "one\ntwo\nthree\nthree\n",
        "each run appended, and neither the write nor the rm reached the log"
    );

    let named = dir.join("named.b");
    put(
        &named,
        &format!(
            "def main()\n  write_file(\"{}\", \"gone\") rescue \"swallowed\"\nend\n",
            log.display()
        ),
    );
    let o = run(&named, &["storage_append"]);
    assert_eq!(o.status.code(), Some(1), "{}{}", out(&o), err(&o));
    assert!(
        err(&o)
            .contains("`write_file` reaches the host (filesystem), which this run does not allow"),
        "a word the file names itself is refused before anything runs: {}",
        err(&o)
    );
    assert_eq!(
        std::fs::read_to_string(&log).unwrap(),
        "one\ntwo\nthree\nthree\n"
    );

    let o = run(&dir.join("log.b"), &["none"]);
    assert_eq!(o.status.code(), Some(1), "{}{}", out(&o), err(&o));
    assert!(
        err(&o).contains("`append_log` reaches the host (storage-append)"),
        "{}",
        err(&o)
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_filesystem_grant_still_appends_with_append_file_and_with_the_log_words() {
    let dir = scratch("filesystem");
    let log = dir.join("both.log");
    let file = dir.join("both.b");
    put(&file, &both(&log));
    let o = run(&file, &["filesystem"]);
    assert!(o.status.success(), "{}{}", out(&o), err(&o));
    assert_eq!(out(&o), "one,two");
    std::fs::remove_file(&log).unwrap();
    let o = run(&file, &[]);
    assert!(
        o.status.success(),
        "an undeclared run: {}{}",
        out(&o),
        err(&o)
    );
    assert_eq!(out(&o), "one,two");

    let project = scratch("filesystem-project");
    put(
        &project.join("Bluefile"),
        "package(\"fsapp\", \"0.1.0\")\nallow(%i[filesystem])\n",
    );
    let log = project.join("both.log");
    put(&project.join("both.b"), &both(&log));
    locked(&project);
    let caps = &lock_of(&project)["capabilities"];
    assert_eq!(caps["ceiling"], serde_json::json!(["filesystem"]), "{caps}");
    assert_eq!(
        caps["floor"],
        serde_json::json!(["filesystem", "storage-append"]),
        "{caps}"
    );
    let o = run(&project.join("both.b"), &[]);
    assert!(
        o.status.success(),
        "held to allow([:filesystem]): {}{}",
        out(&o),
        err(&o)
    );
    assert_eq!(out(&o), "one,two");
    let o = run(&project.join("both.b"), &["storage_append"]);
    assert_eq!(
        o.status.code(),
        Some(1),
        "--allow storage_append narrows the project's filesystem to the store: {}{}",
        out(&o),
        err(&o)
    );
    assert!(
        err(&o).contains("`append_file` reaches the host (filesystem)"),
        "{}",
        err(&o)
    );
    let _ = std::fs::remove_dir_all(dir);
    let _ = std::fs::remove_dir_all(project);
}

#[test]
fn the_in_memory_provider_appends_and_reads_with_no_host_disk() {
    let dir = scratch("memory");
    put(
        &dir.join("Bluefile"),
        "package(\"memapp\", \"0.1.0\")\nallow([])\nvirtualize(:storage_append, {using: :in_memory})\n",
    );
    let log = dir.join("logs/app.log");
    put(&dir.join("log.b"), &appends(&log));
    locked(&dir);
    let caps = &lock_of(&dir)["capabilities"];
    assert_eq!(caps["ceiling"], serde_json::json!([]), "{caps}");
    assert_eq!(
        caps["provided"]["storage-append"],
        serde_json::json!({"provider": "in-memory"}),
        "{caps}"
    );
    for _ in 0..2 {
        let o = run(&dir.join("log.b"), &[]);
        assert!(o.status.success(), "{}{}", out(&o), err(&o));
        assert_eq!(out(&o), "one,two", "each run starts from an empty store");
    }
    assert!(
        !dir.join("logs").exists(),
        "no directory and no log reached the host"
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn the_lock_records_the_storage_append_bundle_and_refuses_it_under_a_ceiling_without_it() {
    let log = scratch("lock-log").join("app.log");
    let project = |name: &str, allow: &str, program: &str| {
        let dir = scratch(name);
        put(
            &dir.join("Bluefile"),
            &format!("package(\"lockapp\", \"0.1.0\")\nallow(%i[{allow}])\n"),
        );
        put(&dir.join("log.b"), program);
        dir
    };

    let held = project("lock-held", "storage_append", &appends(&log));
    locked(&held);
    let caps = &lock_of(&held)["capabilities"];
    assert_eq!(
        caps["ceiling"],
        serde_json::json!(["storage-append"]),
        "{caps}"
    );
    assert_eq!(
        caps["floor"],
        serde_json::json!(["storage-append"]),
        "{caps}"
    );
    assert_eq!(
        caps["definitions"]["lockapp::main"],
        serde_json::json!(["storage-append"]),
        "{caps}"
    );
    let o = blue()
        .args(["bluefile", "--confirm"])
        .arg(held.join("Bluefile"))
        .output()
        .expect("blue bluefile --confirm");
    assert!(o.status.success(), "{}{}", out(&o), err(&o));

    let wide = project("lock-wide", "filesystem", &appends(&log));
    locked(&wide);
    let caps = &lock_of(&wide)["capabilities"];
    assert_eq!(caps["ceiling"], serde_json::json!(["filesystem"]), "{caps}");
    assert_eq!(
        caps["floor"],
        serde_json::json!(["storage-append"]),
        "{caps}"
    );
    let o = blue()
        .args(["bluefile", "--confirm"])
        .arg(wide.join("Bluefile"))
        .output()
        .expect("blue bluefile --confirm");
    assert!(
        o.status.success(),
        "a filesystem ceiling over an append-only floor is a fresh lock: {}{}",
        out(&o),
        err(&o)
    );

    let refused = project("lock-refused", "clock network", &appends(&log));
    let o = lock(&refused);
    assert!(!o.status.success(), "{}", out(&o));
    assert!(
        err(&o)
            .contains("[lockapp::main: needs 'storage-append'] violates ceiling [clock, network]"),
        "{}",
        err(&o)
    );
    assert!(!refused.join("Bluefile.lock").exists());

    let narrower = project(
        "lock-narrower",
        "storage_append",
        &format!(
            "def main()\n  write_file(\"{}\", \"x\")\nend\n",
            log.display()
        ),
    );
    let o = lock(&narrower);
    assert!(!o.status.success(), "{}", out(&o));
    assert!(
        err(&o).contains("[lockapp::main: needs 'filesystem'] violates ceiling [storage-append]"),
        "the store does not hold the filesystem: {}",
        err(&o)
    );
    for d in [held, wide, refused, narrower] {
        let _ = std::fs::remove_dir_all(d);
    }
    let _ = std::fs::remove_dir_all(log.parent().expect("a parent"));
}
