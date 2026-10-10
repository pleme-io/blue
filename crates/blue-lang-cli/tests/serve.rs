//! `blue serve`, `blue repl` and `blue eval` driven as a person or an editor
//! drives them: the binary as a subprocess, the protocol of
//! `theory/BLUE-TOOLING.md` §4 on its pipes.

use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

use serde_json::{json, Value};

fn bidamas() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../bidamas")
}

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env("BLUE_PATH", bidamas()).env_remove("BLUE_LANG");
    c
}

struct Server {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

impl Server {
    fn start(args: &[&str]) -> Self {
        let mut child = blue()
            .arg("serve")
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .expect("blue serve starts");
        let stdin = child.stdin.take().unwrap();
        let stdout = BufReader::new(child.stdout.take().unwrap());
        Self {
            child,
            stdin,
            stdout,
        }
    }

    fn send(&mut self, request: &Value) {
        writeln!(self.stdin, "{request}").unwrap();
        self.stdin.flush().unwrap();
    }

    fn next(&mut self) -> Value {
        let mut line = String::new();
        self.stdout.read_line(&mut line).unwrap();
        serde_json::from_str(&line).unwrap_or_else(|e| panic!("{e}: {line:?}"))
    }

    fn ask(&mut self, request: Value) -> Value {
        self.send(&request);
        let reply = self.next();
        assert_eq!(reply["id"], request["id"], "{reply}");
        reply
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn scratch(name: &str, text: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-serve-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(name);
    std::fs::write(&path, text).unwrap();
    path
}

#[test]
fn eval_answers_a_value_and_what_the_code_wrote() {
    let mut s = Server::start(&[]);
    let r = s.ask(json!({"id": 1, "op": "eval", "code": "write_stdout(\"hi\")\n[1 + 2, \"x\"]"}));
    assert_eq!(r["status"], "ok", "{r}");
    assert_eq!(r["value"], "[3, \"x\"]");
    assert_eq!(r["out"], "hi");
    let r = s.ask(json!({"id": "two", "op": "eval", "code": "nope()"}));
    assert_eq!(r["status"], "error", "{r}");
    assert_eq!(r["error"]["code"], "B0001");
    assert!(r["error"]["message"]
        .as_str()
        .unwrap()
        .starts_with("<eval>:1:1:"));
}

#[test]
fn a_function_redefined_in_the_session_changes_every_caller() {
    let mut s = Server::start(&[]);
    s.ask(json!({"id": 1, "op": "eval", "code": "def rate()\n  1\nend\n"}));
    s.ask(json!({"id": 2, "op": "eval", "code": "def total(n)\n  n * rate()\nend\n"}));
    assert_eq!(
        s.ask(json!({"id": 3, "op": "eval", "code": "total(5)"}))["value"],
        "5"
    );
    s.ask(json!({"id": 4, "op": "eval", "code": "def rate()\n  3\nend\n"}));
    assert_eq!(
        s.ask(json!({"id": 5, "op": "eval", "code": "total(5)"}))["value"],
        "15"
    );
}

#[test]
fn reaching_the_host_is_refused_as_volatile_unless_the_session_allows_it() {
    let path = scratch("hosted.txt", "abc");
    let code = format!("read_file(\"{}\")", path.display());
    let mut pure = Server::start(&[]);
    let r = pure.ask(json!({"id": 1, "op": "eval", "code": code}));
    assert_eq!(r["status"], "volatile", "{r}");
    assert_eq!(r["reach"], "filesystem");
    assert_eq!(r["name"], "read_file");
    assert!(r.get("value").is_none());
    let mut host = Server::start(&["--allow", "host"]);
    let r = host.ask(json!({"id": 1, "op": "eval", "code": code}));
    assert_eq!(r["status"], "ok", "{r}");
    assert_eq!(r["value"], "\"abc\"");
}

#[test]
fn a_budget_ends_an_infinite_loop_as_exhausted() {
    let mut s = Server::start(&[]);
    s.ask(json!({"id": 1, "op": "eval", "code": "def spin(n)\n  spin(n + 1)\nend\n"}));
    let r = s.ask(json!({"id": 2, "op": "eval", "code": "spin(0)", "budget": 20000}));
    assert_eq!(r["status"], "exhausted", "{r}");
    assert_eq!(r["limit"], 20000);
    let r = s.ask(json!({"id": 3, "op": "eval", "code": "1"}));
    assert_eq!(r["value"], "1");
}

#[test]
fn interrupt_halts_an_infinite_loop_while_it_runs() {
    let mut s = Server::start(&[]);
    s.ask(json!({"id": 1, "op": "eval", "code": "def spin(n)\n  spin(n + 1)\nend\n"}));
    s.send(&json!({"id": 2, "op": "eval", "code": "spin(0)"}));
    s.send(&json!({"id": 3, "op": "eval", "code": "spin(0)"}));
    std::thread::sleep(std::time::Duration::from_millis(300));
    s.send(&json!({"id": 4, "op": "interrupt", "target": 3}));
    s.send(&json!({"id": 5, "op": "interrupt", "target": 2}));
    let mut replies = std::collections::BTreeMap::new();
    while replies.len() < 4 {
        let r = s.next();
        replies.insert(r["id"].as_i64().unwrap(), r);
    }
    assert_eq!(replies[&2]["status"], "interrupted", "{}", replies[&2]);
    assert_eq!(
        replies[&3]["status"], "interrupted",
        "a queued request is cancelled"
    );
    assert_eq!(replies[&4]["status"], "ok");
    assert_eq!(replies[&5]["status"], "ok");
    let r = s.ask(json!({"id": 6, "op": "interrupt", "target": 2}));
    assert_eq!(r["error"]["code"], "no-such-request", "{r}");
    assert_eq!(
        s.ask(json!({"id": 7, "op": "eval", "code": "2"}))["value"],
        "2"
    );
}

#[test]
fn load_then_eval_complete_and_doc_in_the_files_context() {
    let path = scratch(
        "lib.b",
        "use(\"retsu\", [:size])\n\n# How many, twice.\ndef double_size(xs)\n  size(xs) * 2\nend\n",
    );
    let file = path.display().to_string();
    let mut s = Server::start(&[]);
    let r = s.ask(json!({"id": 1, "op": "load", "file": file}));
    assert_eq!(r["status"], "ok", "{r}");
    assert_eq!(r["defined"], json!(["double_size"]));
    let r = s.ask(json!({"id": 2, "op": "eval", "file": file, "code": "double_size([1, 2, 3])"}));
    assert_eq!(r["value"], "6", "{r}");
    let r = s.ask(json!({"id": 3, "op": "complete", "file": file, "prefix": "double"}));
    assert_eq!(r["items"][0]["name"], "double_size", "{r}");
    assert_eq!(r["items"][0]["doc"], "How many, twice.");
    let r = s.ask(json!({"id": 4, "op": "complete", "file": file, "prefix": "retsu::si"}));
    let names: Vec<&str> = r["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["name"].as_str().unwrap())
        .collect();
    assert!(names.contains(&"retsu::size"), "{r}");
    let r = s.ask(json!({"id": 5, "op": "doc", "file": file, "name": "double_size"}));
    assert_eq!(r["signature"], "def double_size(xs)", "{r}");
    assert_eq!(r["namespace"], "this file");
    let r = s.ask(json!({"id": 6, "op": "doc", "name": "length"}));
    assert_eq!(r["namespace"], "builtin", "{r}");
    assert_eq!(r["signature"], "length(xs)");
    let r = s.ask(json!({"id": 7, "op": "doc", "name": "no_such"}));
    assert_eq!(r["error"]["code"], "not-found", "{r}");
}

#[test]
fn expand_answers_the_form_one_step_or_fully() {
    let mut s = Server::start(&[]);
    s.ask(json!({"id": 1, "op": "eval",
        "code": "defmacro twice(e)\n  quote\n    [unquote(e), unquote(e)]\n  end\nend\n"}));
    let r = s.ask(json!({"id": 2, "op": "expand", "code": "twice(length(\"ab\"))", "step": "one"}));
    assert_eq!(r["status"], "ok", "{r}");
    assert_eq!(r["form"], "[length(\"ab\"), length(\"ab\")]");
    let r = s.ask(json!({"id": 3, "op": "expand", "code": "1 + 2", "step": "all"}));
    assert_eq!(
        r["form"], "1 + 2",
        "a form with no macro is its own expansion"
    );
}

#[test]
fn reset_forgets_and_bad_requests_are_named() {
    let mut s = Server::start(&[]);
    s.ask(json!({"id": 1, "op": "eval", "code": "def kept()\n  1\nend\n"}));
    assert_eq!(s.ask(json!({"id": 2, "op": "reset"}))["status"], "ok");
    let r = s.ask(json!({"id": 3, "op": "eval", "code": "kept()"}));
    assert_eq!(r["error"]["code"], "B0001", "{r}");
    let r = s.ask(json!({"id": 4, "op": "fly"}));
    assert_eq!(r["error"]["code"], "unknown-op", "{r}");
    let r = s.ask(json!({"id": 5, "op": "eval"}));
    assert_eq!(r["error"]["code"], "bad-request", "{r}");
    writeln!(s.stdin, "not json").unwrap();
    let r = s.next();
    assert_eq!(r["id"], Value::Null);
    assert_eq!(r["error"]["code"], "bad-request", "{r}");
}

#[test]
fn the_repl_reads_multi_line_input_and_its_commands_from_a_pipe() {
    let state = std::env::temp_dir().join(format!("blue-repl-state-{}", std::process::id()));
    let path = scratch("repl.b", "def from_file()\n  41\nend\n");
    let input = format!(
        "def f(x)\n  x + 10\nend\nf(1)\nwrite_stdout(\"hi\")\n:load {}\nfrom_file() + 1\n:expand1 1 + 1\n:doc length\nread_file(\"x\")\n:reset\n:quit\n1\n",
        path.display()
    );
    let mut child = blue()
        .arg("repl")
        .env("XDG_STATE_HOME", &state)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(input.as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(out.status.success());
    let text = String::from_utf8(out.stdout).unwrap();
    let expected = format!(
        "=> nil\n=> 11\nhi\n=> nil\nloaded {}: from_file\n=> 42\n=> 1 + 1\nlength(xs)  (builtin)\n",
        path.display()
    );
    assert!(text.starts_with(&expected), "{text}");
    assert!(
        text.contains("volatile: `read_file` reaches the host (filesystem)"),
        "{text}"
    );
    assert!(!text.contains("=> 1\n"), "nothing after :quit runs: {text}");
    let history = std::fs::read_to_string(state.join("blue/history")).unwrap();
    assert!(
        history.starts_with("def f(x)\n  x + 10\nend\nf(1)\n"),
        "{history}"
    );
}

#[test]
fn eval_once_prints_the_value_or_says_why_not() {
    let out = blue()
        .args(["eval", "[1, 2] |> length()"])
        .output()
        .unwrap();
    assert!(out.status.success());
    assert_eq!(String::from_utf8_lossy(&out.stdout), "2\n");
    let out = blue().args(["eval", "now_ms()"]).output().unwrap();
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("volatile: `now_ms`"));
    let path = scratch(
        "point.b",
        "def sq(x)\n  x * x\nend\n\nwrite_stdout(\"main\")\nsq(7)\n",
    );
    let out = blue()
        .args(["eval", &format!("{}:6:2", path.display())])
        .output()
        .unwrap();
    assert!(out.status.success(), "{out:?}");
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        "49\n",
        "only the form at the point runs"
    );
}
