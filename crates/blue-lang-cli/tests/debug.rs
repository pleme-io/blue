use std::io::BufReader;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

use blue_lang_lsp::frame::{read_message, write_message};
use serde_json::{json, Value};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_DIST")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG")
        .env_remove("BLUE_MEMO")
        .env("BLUE_TRACE_DIR", "");
    c
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-debug-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir.canonicalize().expect("canonical scratch dir")
}

const SEEDED: &str = "def bump(n)
  n + 1
end

def main()
  seed = first(random_bytes(1))
  a = bump(seed)
  b = bump(a)
  print(\"between\")
  [seed, a, b]
end
";

fn record(dir: &Path) -> (PathBuf, i64) {
    let file = dir.join("p.b");
    std::fs::write(&file, SEEDED).expect("program");
    let into = dir.join("receipts");
    let o = blue()
        .arg("run")
        .arg("--receipts")
        .arg(&into)
        .arg("--record")
        .arg(&file)
        .output()
        .expect("blue run");
    assert!(
        o.status.success(),
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    );
    let record = std::fs::read_dir(&into)
        .expect("receipts")
        .map(|e| e.expect("entry").path())
        .find(|p| p.to_string_lossy().ends_with(".run.json"))
        .expect("a run record");
    let r: Value = serde_json::from_slice(&std::fs::read(&record).expect("read")).expect("json");
    let seed = r["tapes"]["0"]
        .as_array()
        .expect("the root's tape")
        .iter()
        .find(|e| e["call"] == "random_bytes")
        .and_then(|e| e["value"]["list"][0]["int"].as_i64())
        .expect("the recorded random byte");
    let receipt = PathBuf::from(
        record
            .to_string_lossy()
            .replace(".run.json", ".receipt.json"),
    );
    (receipt, seed)
}

struct Session {
    child: Child,
    input: ChildStdin,
    output: BufReader<ChildStdout>,
    seq: i64,
}

impl Session {
    fn start() -> Self {
        let mut child = blue()
            .arg("debug")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("blue debug");
        let input = child.stdin.take().expect("stdin");
        let output = BufReader::new(child.stdout.take().expect("stdout"));
        Self {
            child,
            input,
            output,
            seq: 0,
        }
    }

    fn read(&mut self) -> Value {
        read_message(&mut self.output)
            .expect("read")
            .expect("a message before the end of the stream")
    }

    fn call(&mut self, command: &str, arguments: Value) -> Value {
        self.seq += 1;
        let seq = self.seq;
        write_message(
            &mut self.input,
            &json!({"seq": seq, "type": "request", "command": command, "arguments": arguments}),
        )
        .expect("write");
        loop {
            let m = self.read();
            if m["type"] == "response" && m["request_seq"] == seq {
                return m;
            }
        }
    }

    fn event(&mut self, name: &str) -> Value {
        loop {
            let m = self.read();
            if m["type"] == "event" && m["event"] == name {
                return m;
            }
            assert!(
                !(m["type"] == "event" && m["event"] == "terminated"),
                "terminated while waiting for {name}"
            );
        }
    }

    fn top(&mut self) -> (String, Vec<(String, String)>) {
        let st = self.call("stackTrace", json!({"threadId": 1}));
        assert_eq!(st["success"], true, "{st}");
        let top = &st["body"]["stackFrames"][0];
        let name = top["name"].as_str().expect("frame name").to_string();
        let id = top["id"].clone();
        let vars = self.call("variables", json!({"variablesReference": id}));
        let vars = vars["body"]["variables"]
            .as_array()
            .expect("variables")
            .iter()
            .map(|v| {
                (
                    v["name"].as_str().unwrap_or_default().to_string(),
                    v["value"].as_str().unwrap_or_default().to_string(),
                )
            })
            .collect();
        (name, vars)
    }

    fn launch(&mut self, receipt: &Path, stop_on_entry: bool) {
        let init = self.call("initialize", json!({"adapterID": "blue"}));
        assert_eq!(init["body"]["supportsStepBack"], true, "{init}");
        let launched = self.call(
            "launch",
            json!({"receipt": receipt, "stopOnEntry": stop_on_entry}),
        );
        assert_eq!(launched["success"], true, "{launched}");
        self.event("initialized");
    }

    fn finish(mut self) {
        let _ = self.call("disconnect", json!({}));
        drop(self.input);
        let status = self.child.wait().expect("wait");
        assert!(status.success());
    }
}

fn var(vars: &[(String, String)], name: &str) -> String {
    vars.iter()
        .find(|(n, _)| n == name)
        .map(|(_, v)| v.clone())
        .unwrap_or_else(|| panic!("no `{name}` among {vars:?}"))
}

#[test]
fn a_step_back_replays_to_the_earlier_value() {
    let dir = scratch("back");
    let (receipt, seed) = record(&dir);
    let mut s = Session::start();
    s.launch(&receipt, false);
    let set = s.call(
        "setFunctionBreakpoints",
        json!({"breakpoints": [{"name": "bump"}]}),
    );
    assert_eq!(set["body"]["breakpoints"][0]["verified"], true, "{set}");
    s.call("configurationDone", json!({}));
    assert_eq!(s.event("stopped")["body"]["reason"], "breakpoint");
    let (name, vars) = s.top();
    assert_eq!(name, "bump");
    assert_eq!(var(&vars, "n"), seed.to_string());

    s.call("continue", json!({"threadId": 1}));
    s.event("stopped");
    let (_, vars) = s.top();
    assert_eq!(var(&vars, "n"), (seed + 1).to_string());

    let back = s.call("stepBack", json!({"threadId": 1}));
    assert_eq!(back["success"], true, "{back}");
    s.event("stopped");
    let (name, vars) = s.top();
    assert_eq!(name, "bump");
    assert_eq!(var(&vars, "n"), seed.to_string());
    assert_eq!(var(&vars, "return"), (seed + 1).to_string());

    s.call("stepBack", json!({"threadId": 1}));
    s.event("stopped");
    let (_, vars) = s.top();
    assert_eq!(var(&vars, "n"), seed.to_string());
    assert!(vars.iter().all(|(n, _)| n != "return"), "{vars:?}");

    s.call("reverseContinue", json!({"threadId": 1}));
    assert_eq!(s.event("stopped")["body"]["reason"], "entry");
    let (name, _) = s.top();
    assert_eq!(name, "main");
    s.finish();
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn stepping_forward_walks_calls_and_returns_to_the_end() {
    let dir = scratch("forward");
    let (receipt, seed) = record(&dir);
    let mut s = Session::start();
    s.launch(&receipt, true);
    s.call("configurationDone", json!({}));
    assert_eq!(s.event("stopped")["body"]["reason"], "entry");
    let st = s.call("stackTrace", json!({"threadId": 1}));
    assert_eq!(st["body"]["stackFrames"][0]["name"], "main", "{st}");
    assert_eq!(st["body"]["stackFrames"][0]["line"], 5, "{st}");

    s.call("stepIn", json!({"threadId": 1}));
    s.event("stopped");
    let st = s.call("stackTrace", json!({"threadId": 1}));
    let frames = st["body"]["stackFrames"].as_array().expect("frames");
    assert_eq!(frames.len(), 2, "{st}");
    assert_eq!(frames[0]["name"], "bump");
    assert_eq!(frames[0]["line"], 1);
    assert_eq!(frames[1]["name"], "main");
    assert_eq!(frames[1]["line"], 7, "the caller stands on its call: {st}");

    s.call("stepOut", json!({"threadId": 1}));
    s.event("stopped");
    let (_, vars) = s.top();
    assert_eq!(var(&vars, "return"), (seed + 1).to_string());

    s.call("next", json!({"threadId": 1}));
    s.event("stopped");
    s.call("next", json!({"threadId": 1}));
    s.event("stopped");
    let (name, vars) = s.top();
    assert_eq!(name, "bump");
    assert_eq!(var(&vars, "return"), (seed + 2).to_string());

    s.call("next", json!({"threadId": 1}));
    s.event("stopped");
    let (name, vars) = s.top();
    assert_eq!(name, "main");
    assert_eq!(
        var(&vars, "return"),
        format!("[{seed}, {}, {}]", seed + 1, seed + 2)
    );
    s.call("next", json!({"threadId": 1}));
    s.event("terminated");
    s.finish();
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_breakpoint_on_a_line_stops_where_a_definition_starts() {
    let dir = scratch("line");
    let (receipt, seed) = record(&dir);
    let mut s = Session::start();
    s.launch(&receipt, false);
    let set = s.call(
        "setBreakpoints",
        json!({"source": {"path": dir.join("p.b")}, "breakpoints": [{"line": 1}, {"line": 2}]}),
    );
    let bps = &set["body"]["breakpoints"];
    assert_eq!(bps[0]["verified"], true, "{set}");
    assert_eq!(bps[1]["verified"], false, "{set}");
    s.call("configurationDone", json!({}));
    s.event("stopped");
    let (name, vars) = s.top();
    assert_eq!(name, "bump");
    assert_eq!(var(&vars, "n"), seed.to_string());
    s.finish();
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn an_unknown_function_breakpoint_is_unverified_and_the_run_ends() {
    let dir = scratch("unknown");
    let (receipt, _) = record(&dir);
    let mut s = Session::start();
    s.launch(&receipt, false);
    let set = s.call(
        "setFunctionBreakpoints",
        json!({"breakpoints": [{"name": "nowhere"}, {"name": "b3:00"}]}),
    );
    assert_eq!(set["body"]["breakpoints"][0]["verified"], false, "{set}");
    assert_eq!(set["body"]["breakpoints"][1]["verified"], false, "{set}");
    s.call("configurationDone", json!({}));
    s.event("terminated");
    s.finish();
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_tampered_tape_is_refused_at_launch() {
    let dir = scratch("tampered");
    let (receipt, seed) = record(&dir);
    let record = PathBuf::from(
        receipt
            .to_string_lossy()
            .replace(".receipt.json", ".run.json"),
    );
    let mut r: Value =
        serde_json::from_slice(&std::fs::read(&record).expect("read")).expect("json");
    let entry = r["tapes"]["0"]
        .as_array_mut()
        .expect("tape")
        .iter_mut()
        .find(|e| e["call"] == "random_bytes")
        .expect("random_bytes");
    entry["value"] = json!({"list": [{"int": (seed + 1) % 256}]});
    std::fs::write(&record, serde_json::to_vec(&r).expect("bytes")).expect("edit");
    let mut s = Session::start();
    s.call("initialize", json!({}));
    let launched = s.call("launch", json!({"receipt": receipt}));
    assert_eq!(launched["success"], false, "{launched}");
    assert!(
        launched["message"]
            .as_str()
            .unwrap_or_default()
            .contains("does not reproduce"),
        "{launched}"
    );
    s.finish();
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_breakpoint_on_a_definitions_hash_stops_at_its_calls() {
    let dir = scratch("hash");
    let (receipt, seed) = record(&dir);
    let mut s = Session::start();
    s.launch(&receipt, true);
    s.call("configurationDone", json!({}));
    s.event("stopped");
    s.call("stepIn", json!({"threadId": 1}));
    s.event("stopped");
    let st = s.call("stackTrace", json!({"threadId": 1}));
    let hash = st["body"]["stackFrames"][0]["defHash"]
        .as_str()
        .expect("the frame's definition hash")
        .to_string();
    assert!(hash.starts_with("b3:"), "{hash}");
    assert_ne!(st["body"]["stackFrames"][1]["defHash"], hash.as_str());
    s.call("reverseContinue", json!({"threadId": 1}));
    s.event("stopped");
    let set = s.call(
        "setFunctionBreakpoints",
        json!({"breakpoints": [{"name": hash}]}),
    );
    assert_eq!(set["body"]["breakpoints"][0]["verified"], true, "{set}");
    s.call("continue", json!({"threadId": 1}));
    assert_eq!(s.event("stopped")["body"]["reason"], "breakpoint");
    s.call("continue", json!({"threadId": 1}));
    s.event("stopped");
    let (name, vars) = s.top();
    assert_eq!(name, "bump");
    assert_eq!(var(&vars, "n"), (seed + 1).to_string());
    s.finish();
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn the_programs_output_never_enters_the_protocol_stream() {
    let dir = scratch("output");
    let (receipt, _) = record(&dir);
    let mut child = blue()
        .arg("debug")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("blue debug");
    let mut input = child.stdin.take().expect("stdin");
    for (seq, command, arguments) in [
        (1, "initialize", json!({})),
        (2, "launch", json!({"receipt": receipt})),
        (3, "configurationDone", json!({})),
        (4, "disconnect", json!({})),
    ] {
        write_message(
            &mut input,
            &json!({"seq": seq, "type": "request", "command": command, "arguments": arguments}),
        )
        .expect("write");
    }
    drop(input);
    let o = child.wait_with_output().expect("wait");
    assert!(o.status.success());
    let stdout = String::from_utf8_lossy(&o.stdout);
    let stderr = String::from_utf8_lossy(&o.stderr);
    assert!(!stdout.contains("between"), "{stdout}");
    assert!(stdout.contains("\"terminated\""), "{stdout}");
    assert!(stderr.contains("between"), "{stderr}");
    let _ = std::fs::remove_dir_all(dir);
}
