//! A process held to a frame that breaches it writes a `.bluecrash`,
//! supervised or not: its hold, its mailbox journal and its definition's
//! `def_hash`. `blue replay` runs it again under that hold and stops at the
//! same breach, at the same tape entry.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG")
        .env_remove("BLUE_CRASH_JOURNAL");
    c
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-crash-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir.canonicalize().expect("canonical scratch dir")
}

fn out(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

/// A reader that takes one path, then reaches the filesystem through a
/// bidama inside a `rescue`, with two more messages waiting behind it.
const BREACHING: &str = "use(\"shisutemu\", [:read_or])\n\ndef reader(parent)\n  path = receive()\n  send(parent, read_or(path, \"\") rescue \"swallowed\")\nend\n\ndef main()\n  pid = spawn(reader, [self])\n  monitor(pid)\n  send(pid, \"/etc/hosts\")\n  send(pid, \"second\")\n  send(pid, \"third\")\n  write_stdout(to_s(receive(:_, 5000)))\nend\n";

/// Run `BREACHING` under `--allow none` and answer the one crash file it
/// wrote, with the program removed: the replay has only the file.
fn crash(name: &str, journal: Option<&str>) -> (PathBuf, PathBuf, serde_json::Value) {
    let dir = scratch(name);
    let file = dir.join("reader.b");
    std::fs::write(&file, BREACHING).expect("program");
    let traces = dir.join("traces");
    let mut c = blue();
    if let Some(j) = journal {
        c.env("BLUE_CRASH_JOURNAL", j);
    }
    let o = c
        .env("BLUE_TRACE_DIR", &traces)
        .args(["run", "--quiet", "--allow", "none"])
        .arg(&file)
        .output()
        .expect("blue run");
    assert!(o.status.success(), "{}", err(&o));
    assert!(
        out(&o).contains(":fatal") && !out(&o).contains("swallowed"),
        "{}",
        out(&o)
    );
    assert!(
        err(&o).contains(".bluecrash"),
        "the crash names its file: {}",
        err(&o)
    );
    let files: Vec<PathBuf> = std::fs::read_dir(&traces)
        .expect("trace dir")
        .map(|e| e.expect("entry").path())
        .collect();
    assert_eq!(
        files.len(),
        1,
        "an unsupervised fatal exit is written: {files:?}"
    );
    assert_eq!(
        files[0].extension().and_then(|e| e.to_str()),
        Some("bluecrash")
    );
    std::fs::remove_file(&file).expect("the replay must not need the program");
    let j = serde_json::from_slice(&std::fs::read(&files[0]).expect("read")).expect("json");
    (dir, files[0].clone(), j)
}

fn replay(path: &Path) -> Output {
    blue()
        .arg("replay")
        .arg(path)
        .output()
        .expect("blue replay")
}

#[test]
fn a_breach_under_allow_none_writes_a_bluecrash_that_replays_as_the_same_breach() {
    let (dir, path, j) = crash("breach", None);
    assert_eq!(j["version"], 2);
    assert_eq!(j["definition"], "%root/reader");
    assert!(
        j["def_hash"]
            .as_str()
            .is_some_and(|h| h.starts_with("b3:") && h.len() == 67),
        "{}",
        j["def_hash"]
    );
    assert_eq!(j["exit"]["kind"], "fatal");
    assert_eq!(
        j["hold"],
        serde_json::json!({
            "granted": [],
            "provided": [],
            "withheld": ["process", "filesystem", "environment", "clock", "network", "entropy"],
        })
    );
    let tape = j["tape"].as_array().expect("tape");
    assert_eq!(tape.len(), 2, "{tape:?}");
    assert_eq!(tape[1]["call"], "is_file?");
    assert_eq!(tape[1]["fatal"]["kind"], "capability-breach");

    let o = replay(&path);
    let stdout = out(&o);
    assert!(o.status.success(), "{stdout}{}", err(&o));
    let recorded = j["exit"]["text"].as_str().expect("text");
    assert!(
        recorded.contains("`is_file?` reaches the host (filesystem)"),
        "{recorded}"
    );
    assert!(
        stdout.contains(&format!("recorded: fatal {recorded}\n"))
            && stdout.contains(&format!(
                "replayed: fatal {recorded} (2 of 2 tape entries)\n"
            )),
        "the same breach at the same tape entry: {stdout}"
    );
    assert!(
        stdout.contains("hold: granted none; provided none; withheld process, filesystem"),
        "{stdout}"
    );
    assert!(
        stdout.ends_with("reproduced\n") && !stdout.contains("not reproduced"),
        "{stdout}"
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn the_mailbox_journal_holds_the_unconsumed_messages() {
    let (dir, path, j) = crash("journal", None);
    assert_eq!(
        j["mailbox"],
        serde_json::json!({
            "bound": 8,
            "recent": [{"str": "/etc/hosts"}],
            "unconsumed": [{"str": "second"}, {"str": "third"}],
            "unconsumed_total": 2,
        })
    );
    let stdout = out(&replay(&path));
    assert!(
        stdout.contains("mailbox: 1 recent, 2 unconsumed (bound 8)\n  waiting: \"second\"\n  waiting: \"third\"\n"),
        "{stdout}"
    );
    let _ = std::fs::remove_dir_all(dir);

    let (dir, _, j) = crash("journal-off", Some("0"));
    assert!(j["mailbox"].is_null(), "configured off: {}", j["mailbox"]);
    assert!(!j["hold"].is_null(), "the hold is recorded either way");
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_bluecrash_whose_tape_says_a_withheld_name_answered_does_not_replay() {
    let (dir, path, mut j) = crash("tampered", None);
    j["tape"][1] = serde_json::json!({"call": "is_file?", "value": {"bool": true}});
    std::fs::write(&path, serde_json::to_string(&j).expect("json")).expect("write");
    let o = replay(&path);
    let stdout = out(&o);
    assert!(!o.status.success(), "{stdout}");
    assert!(
        stdout.contains("diverged: at tape entry 1 the trace records `is_file?` reaching the host, which its hold withholds (filesystem)")
            && stdout.ends_with("not reproduced\n"),
        "{stdout}"
    );
    let _ = std::fs::remove_dir_all(dir);
}
