//! `blue run` writes a supervised process's crash trace; `blue replay` runs it
//! again from the file alone and exits 0 only when the crash repeats.

use std::path::PathBuf;
use std::process::Command;

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER");
    c
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-cli-replay-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir
}

/// A worker that crashes on the third job it is handed. The program and the
/// jobs are gone by the time the replay runs; the trace is all it has.
const PROGRAM: &str = "\
def worker(parent)
  job = receive()
  if job == 3
    throw(error(:bad_job, \"job #{job} is poison\"))
  end
  send(parent, [:did, job])
  worker(parent)
end
me = self
sup = supervisor(:one_for_one, [[worker, [me]]], 0)
w = nth(0, children(sup))
m = monitor(sup)
map(fn(j) send(w, j) end, [1, 2, 3])
receive([:down, m, :_, :_])
";

fn crash_trace(name: &str) -> (PathBuf, PathBuf) {
    let dir = scratch(name);
    let program = dir.join("worker.b");
    std::fs::write(&program, PROGRAM).expect("program");
    let traces = dir.join("traces");
    let out = blue()
        .env("BLUE_TRACE_DIR", &traces)
        .args(["run", "--quiet"])
        .arg(&program)
        .output()
        .expect("blue run");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("trace:"),
        "the crash names its trace: {stderr}"
    );
    let files: Vec<PathBuf> = std::fs::read_dir(&traces)
        .expect("trace dir")
        .map(|e| e.expect("entry").path())
        .collect();
    assert_eq!(files.len(), 1, "{files:?}");
    std::fs::remove_file(&program).expect("the replay must not need the program");
    (dir, files[0].clone())
}

#[test]
fn replay_reproduces_the_crash_from_the_trace_alone() {
    let (dir, trace) = crash_trace("ok");
    let out = blue()
        .arg("replay")
        .arg(&trace)
        .output()
        .expect("blue replay");
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(out.status.success(), "{stdout}");
    assert!(
        stdout.contains("job 3 is poison") && stdout.ends_with("reproduced\n"),
        "{stdout}"
    );
    // receive, send, receive, send, receive: three jobs and two answers.
    assert!(stdout.contains("5 of 5 tape entries"), "{stdout}");
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_tampered_trace_is_not_reported_as_reproduced() {
    let (dir, trace) = crash_trace("tampered");
    let text = std::fs::read_to_string(&trace).expect("read");
    let mut j: serde_json::Value = serde_json::from_str(&text).expect("json");
    // The third job becomes harmless: the worker asks for a fourth, which the
    // tape does not hold.
    assert_eq!(j["tape"][4]["call"], "receive");
    j["tape"][4]["value"] = serde_json::json!({ "int": 4 });
    let edited = serde_json::to_string(&j).expect("json");
    std::fs::write(&trace, &edited).expect("write");
    let refused = blue()
        .arg("replay")
        .arg(&trace)
        .output()
        .expect("blue replay");
    assert!(
        !refused.status.success()
            && String::from_utf8_lossy(&refused.stderr).contains("the trace was edited"),
        "under its hash name the edit is refused before it runs"
    );
    let trace = dir.join("tampered.json");
    std::fs::write(&trace, edited).expect("write");
    let out = blue()
        .arg("replay")
        .arg(&trace)
        .output()
        .expect("blue replay");
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(!out.status.success(), "{stdout}");
    assert!(
        stdout.contains("diverged") && stdout.ends_with("not reproduced\n"),
        "{stdout}"
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_file_that_is_not_a_trace_is_refused_by_name() {
    let dir = scratch("bad");
    let p = dir.join("x.json");
    std::fs::write(&p, "{\"format\": \"something-else\"}").expect("write");
    let out = blue().arg("replay").arg(&p).output().expect("blue replay");
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("not a blue-trace file"));
    let _ = std::fs::remove_dir_all(dir);
}
