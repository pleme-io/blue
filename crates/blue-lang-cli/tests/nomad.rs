use std::net::UdpSocket;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::time::Duration;

use serde_json::Value as Json;

fn repo_bidamas() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../bidamas")
}

fn blue(path: &str) -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG")
        .env_remove("BLUE_CRASH_JOURNAL")
        .env("BLUE_PATH", path);
    c
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-nomad-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir.canonicalize().expect("canonical scratch dir")
}

fn put(path: &Path, text: &str) {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).expect("fixture dir");
    }
    std::fs::write(path, text).expect("write fixture");
}

fn out(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

const HIKKOSHI: &str = "def away(pid, wire, peer)\n  evict(pid, wire, peer)\nend\n\ndef arrive(wire)\n  accept(wire, 0)\nend\n";

fn reaching(call: &str) -> String {
    format!(
        "use(\"hikkoshi\", %i[arrive away])\n\ndef keep(msg, n)\n  n\nend\n\ndef main()\n  s = spawn_server(keep, 0)\n  {call} rescue write_stdout(\"swallowed\")\n  write_stdout(\"after\")\nend\n"
    )
}

fn run_allowing(dir: &Path, file: &str, allow: &[&str]) -> Output {
    let path = format!(
        "{}:{}",
        dir.join("bidamas").display(),
        repo_bidamas().display()
    );
    let mut c = blue(&path);
    c.args(["run", "--quiet"]);
    for a in allow {
        c.args(["--allow", a]);
    }
    c.arg(dir.join(file)).output().expect("blue run")
}

#[test]
fn eviction_without_comm_scavenger_is_a_fatal_breach_no_rescue_sees() {
    let dir = scratch("breach");
    put(&dir.join("bidamas/hikkoshi/hikkoshi.b"), HIKKOSHI);
    put(
        &dir.join("away.b"),
        &reaching("away(s, nil, \"127.0.0.1:9\")"),
    );
    put(&dir.join("arrive.b"), &reaching("arrive(nil)"));

    for (file, word) in [("away.b", "evict"), ("arrive.b", "accept")] {
        let o = run_allowing(&dir, file, &["none"]);
        assert_eq!(o.status.code(), Some(77), "{file}: {}{}", out(&o), err(&o));
        assert!(
            err(&o).contains(&format!("`{word}` reaches the host (comm-scavenger)")),
            "{file}: {}",
            err(&o)
        );
        assert!(
            !out(&o).contains("swallowed") && !out(&o).contains("after"),
            "no rescue saw the breach and nothing ran after it: {}",
            out(&o)
        );

        let o = run_allowing(&dir, file, &["comm_scavenger"]);
        assert!(o.status.success(), "{file}: {}", err(&o));
        assert_eq!(
            out(&o),
            "swallowedafter",
            "granted, the word runs and refuses the nil wire, which a rescue catches"
        );
    }

    put(
        &dir.join("named.b"),
        "def keep(msg, n)\n  n\nend\n\ndef main()\n  s = spawn_server(keep, 0)\n  write_stdout(\"ran\")\n  evict(s, nil, \"127.0.0.1:9\")\nend\n",
    );
    let o = run_allowing(&dir, "named.b", &["none"]);
    assert!(!o.status.success());
    assert!(
        !out(&o).contains("ran"),
        "named in the entry file it is refused before anything runs: {}",
        out(&o)
    );
    assert!(
        err(&o).contains("evict") && err(&o).contains("comm-scavenger"),
        "{}",
        err(&o)
    );
    let _ = std::fs::remove_dir_all(dir);
}

const MOVING: &str = r#"def witness(msg, seen)
  if msg[0] == :inc
    append(seen, [[msg[1], self]])
  else
    send(msg[1], [:seen, seen])
    seen
  end
end

def main()
  a = tide_open("127.0.0.1:PORT_A")
  b = tide_open("127.0.0.1:PORT_B")
  s = spawn_server(witness, [], {scheduling: :idle})
  send(s, [:inc, 1])
  send(s, [:get, self])
  before = receive()
  send(s, [:inc, 2])
  send(s, [:inc, 3])
  moved = evict(s, a, tide_stats(b).address)
  sent = tide_release(a, 1_000_000, 0)
  p = accept(b, 0)
  send(p, [:inc, 4])
  send(p, [:get, self])
  after = receive()
  write_stdout(
    json_stringify(
      {before:, after:, frames: moved.frames, sent: sent == moved.bytes, moved_to: p != s, here: alive?(s)}
    )
  )
end
"#;

fn listener() -> (UdpSocket, u16) {
    let l = UdpSocket::bind("127.0.0.1:0").expect("listener");
    l.set_read_timeout(Some(Duration::from_millis(400)))
        .expect("timeout");
    let port = l.local_addr().expect("addr").port();
    (l, port)
}

#[test]
fn an_idle_server_moves_over_the_loopback_tide_under_allow_none_and_touches_no_socket() {
    let (held_a, port_a) = listener();
    let (held_b, port_b) = listener();
    let dir = scratch("loop");
    put(
        &dir.join("Bluefile"),
        "package(\"nomad-loop\", \"0.1.0\")\nallow([])\nvirtualize(:comm_scavenger, {using: :loopback})\n",
    );
    put(
        &dir.join("move.b"),
        &MOVING
            .replace("PORT_A", &port_a.to_string())
            .replace("PORT_B", &port_b.to_string()),
    );
    let path = repo_bidamas().display().to_string();
    let o = blue(&path)
        .arg("lock")
        .arg(&dir)
        .output()
        .expect("blue lock");
    assert!(o.status.success(), "blue lock: {}", err(&o));
    let o = blue(&path)
        .args(["run", "--quiet"])
        .arg(dir.join("move.b"))
        .output()
        .expect("blue run");
    assert!(o.status.success(), "{}{}", out(&o), err(&o));
    let j: Json =
        serde_json::from_str(out(&o).trim()).unwrap_or_else(|e| panic!("{e}: {}", out(&o)));
    assert_eq!(j["before"], serde_json::json!(["seen", [[1, 1]]]));
    assert_eq!(
        j["after"],
        serde_json::json!(["seen", [[1, 1], [2, 2], [3, 2], [4, 2]]]),
        "2 and 3 waited out the move and were handled once, by the process it became"
    );
    assert_eq!(j["sent"], true);
    assert_eq!(j["moved_to"], true);
    assert_eq!(j["here"], false);
    assert!(j["frames"].as_i64().is_some_and(|n| n >= 1));
    let mut buf = [0u8; 2048];
    assert!(
        held_a.recv_from(&mut buf).is_err() && held_b.recv_from(&mut buf).is_err(),
        "the frames crossed in process: the ports real sockets hold heard nothing"
    );
    let _ = std::fs::remove_dir_all(dir);
}

const LEDGER: &str = r##"use("shisutemu", [:read_or])

def ledger(parent)
  t0 = now_ms
  a = receive()
  b = receive()
  send(parent, [:took, a + b, t0])
  c = receive()
  t1 = now_ms
  send(parent, [:at, t1])
  send(parent, read_or(c, "") rescue "swallowed")
end

def main()
  a = tide_open("127.0.0.1:0")
  b = tide_open("127.0.0.1:0")
  p = spawn(ledger, [self])
  send(p, 1)
  send(p, 2)
  receive(%i[took _ _])
  moved = evict(p, a, tide_stats(b).address)
  tide_release(a, 1_000_000, 0)
  q = accept(b, 5000)
  monitor(q)
  send(q, "/etc/hosts")
  write_stdout("#{moved.image} #{q != p} #{receive(%i[down _ _ _], 5000)[3][0]}")
end
"##;

const TILL: &str = r##"use("shisutemu", [:read_or])

def till(msg, total)
  t = now_ms
  if integer?(msg)
    total + msg
  elsif list?(msg)
    send(msg[1], [:total, total, t])
    total
  else
    read_or(msg, "") rescue "swallowed"
  end
end

def main()
  a = tide_open("127.0.0.1:0")
  b = tide_open("127.0.0.1:0")
  s = spawn_server(till, 0)
  send(s, 1)
  send(s, 2)
  send(s, [:get, self])
  before = receive(%i[total _ _])
  send(s, 4)
  moved = evict(s, a, tide_stats(b).address)
  tide_release(a, 1_000_000, 0)
  q = accept(b, 5000)
  monitor(q)
  send(q, "/etc/hosts")
  write_stdout("#{moved.image} #{before[1]} #{receive(%i[down _ _ _], 5000)[3][0]}")
end
"##;

fn crashed_after_moving(name: &str, program: &str) -> (PathBuf, PathBuf, Json, Vec<String>) {
    let dir = scratch(name);
    let file = dir.join("move.b");
    put(&file, program);
    let traces = dir.join("traces");
    let o = blue(&repo_bidamas().display().to_string())
        .env("BLUE_TRACE_DIR", &traces)
        .args([
            "run",
            "--quiet",
            "--allow",
            "comm_scavenger",
            "--allow",
            "clock",
        ])
        .arg(&file)
        .output()
        .expect("blue run");
    assert!(o.status.success(), "{}{}", out(&o), err(&o));
    let said: Vec<String> = out(&o).split(' ').map(str::to_string).collect();
    let files: Vec<PathBuf> = std::fs::read_dir(&traces)
        .expect("trace dir")
        .map(|e| e.expect("entry").path())
        .collect();
    assert_eq!(files.len(), 1, "{files:?}");
    assert_eq!(
        files[0].extension().and_then(|e| e.to_str()),
        Some("bluecrash")
    );
    std::fs::remove_file(&file).expect("the replay must not need the program");
    let j = serde_json::from_slice(&std::fs::read(&files[0]).expect("read")).expect("json");
    (dir, files[0].clone(), j, said)
}

fn replay(path: &Path) -> Output {
    blue(&repo_bidamas().display().to_string())
        .arg("replay")
        .arg(path)
        .output()
        .expect("blue replay")
}

#[test]
fn a_moved_plain_process_writes_a_bluecrash_that_replays_from_its_start_through_the_tape_it_carried(
) {
    let (dir, path, j, said) = crashed_after_moving("replay-plain", LEDGER);
    assert_eq!(said.len(), 3, "{said:?}");
    assert!(said[0].starts_with("b3:") && said[1] == "true" && said[2].contains("fatal"));
    assert_eq!(j["version"], 5);
    assert_eq!(
        j["carried"]["entries"], 4,
        "now_ms, two receives and a send on the node it left: {}",
        j["tape"]
    );
    assert_eq!(j["carried"]["image"], said[0].as_str());
    assert_eq!(j["truncated"], false);
    let calls: Vec<&str> = j["tape"]
        .as_array()
        .expect("tape")
        .iter()
        .filter_map(|e| e["call"].as_str())
        .collect();
    assert_eq!(
        calls,
        ["now_ms", "receive", "receive", "send", "receive", "now_ms", "send", "is_file?"],
    );
    assert_eq!(j["violation"]["entry"], 7);

    let o = replay(&path);
    let stdout = out(&o);
    assert!(o.status.success(), "{stdout}{}", err(&o));
    let recorded = j["exit"]["text"].as_str().expect("text");
    assert!(
        stdout.contains(&format!(
            "carried: the first 4 tape entries came in image {}\n",
            said[0]
        )) && stdout.contains(&format!(
            "replayed: fatal {recorded} (8 of 8 tape entries)\n"
        )),
        "the same breach at the same tape entry: {stdout}"
    );
    assert!(
        stdout.ends_with("reproduced\n") && !stdout.contains("not reproduced"),
        "{stdout}"
    );

    let mut cut = j.clone();
    cut["tape"].as_array_mut().expect("tape").remove(1);
    let cut_path = dir.join("cut.bluecrash");
    put(&cut_path, &serde_json::to_string(&cut).expect("json"));
    let o = replay(&cut_path);
    assert!(!o.status.success(), "{}", out(&o));
    assert!(
        err(&o).contains(&format!(
            "not replayed: the tape carried in image {} does not match: its first 4 entries hash to b3:",
            said[0]
        )),
        "{}",
        err(&o)
    );
    assert!(out(&o).is_empty(), "nothing ran: {}", out(&o));
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_moved_plain_processs_bluecrash_holds_the_journal_and_host_calls_of_both_wires_and_refuses_a_cut_journal(
) {
    let (dir, path, j, said) = crashed_after_moving("replay-account", LEDGER);
    assert_eq!(
        j["mailbox"]["recent"],
        serde_json::json!([{"int": 1}, {"int": 2}, {"str": "/etc/hosts"}]),
        "1 and 2 were taken before the move, the path after it"
    );
    assert_eq!(
        j["frame"]["host_io"], 2,
        "a clock reading before the move and one after"
    );
    assert_eq!(
        j["carried_account"]["journal"], 2,
        "{}",
        j["carried_account"]
    );
    assert_eq!(j["carried_account"]["host_io"], 1);
    assert_eq!(j["carried_account"]["image"], said[0].as_str());

    let o = replay(&path);
    let stdout = out(&o);
    assert!(o.status.success(), "{stdout}{}", err(&o));
    assert!(
        stdout.contains(&format!(
            "carried: its journal's first 2 and its host-call count 1 came in image {}\n",
            said[0]
        )) && stdout.contains("mailbox: 3 recent, 0 unconsumed (bound 8)\n")
            && stdout.ends_with("reproduced\n")
            && !stdout.contains("not reproduced"),
        "{stdout}"
    );

    let mut cut = j.clone();
    cut["mailbox"]["recent"]
        .as_array_mut()
        .expect("recent")
        .remove(0);
    let cut_path = dir.join("cut.bluecrash");
    put(&cut_path, &serde_json::to_string(&cut).expect("json"));
    let o = replay(&cut_path);
    assert!(!o.status.success(), "{}", out(&o));
    assert!(
        err(&o).contains(&format!(
            "not replayed: the journal and host-call count carried in image {} do not match: its journal's first 2 and its host-call count 1 hash to b3:",
            said[0]
        )),
        "{}",
        err(&o)
    );
    assert!(out(&o).is_empty(), "nothing ran: {}", out(&o));

    let mut uncounted = j.clone();
    uncounted["frame"]["host_io"] = serde_json::json!(0);
    let uncounted_path = dir.join("uncounted.bluecrash");
    put(
        &uncounted_path,
        &serde_json::to_string(&uncounted).expect("json"),
    );
    let o = replay(&uncounted_path);
    assert!(!o.status.success(), "{}", out(&o));
    assert!(
        err(&o).contains(&format!(
            "not replayed: its host-call count is cut: process 2 brought a count of 1 in image {}, and the trace counts 0",
            said[0]
        )),
        "{}",
        err(&o)
    );
    assert!(out(&o).is_empty(), "nothing ran: {}", out(&o));
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_moved_plain_processs_receipt_counts_the_host_calls_of_both_wires_and_verify_refuses_a_cut_count(
) {
    let dir = scratch("receipt-account");
    let file = dir.join("move.b");
    put(&file, LEDGER);
    let receipts = dir.join("receipts");
    let o = blue(&repo_bidamas().display().to_string())
        .env("BLUE_TRACE_DIR", dir.join("traces"))
        .args([
            "run",
            "--quiet",
            "--allow",
            "comm_scavenger",
            "--allow",
            "clock",
            "--receipts",
        ])
        .arg(&receipts)
        .arg(&file)
        .output()
        .expect("blue run");
    assert!(o.status.success(), "{}{}", out(&o), err(&o));
    let image = out(&o).split(' ').next().expect("the image").to_string();
    let carried: Vec<(PathBuf, Json)> = std::fs::read_dir(&receipts)
        .expect("receipts")
        .map(|e| e.expect("entry").path())
        .map(|p| {
            let j = serde_json::from_slice(&std::fs::read(&p).expect("read")).expect("json");
            (p, j)
        })
        .filter(|(_, j): &(PathBuf, Json)| j.get("carried").is_some())
        .collect();
    assert_eq!(
        carried.len(),
        1,
        "only the process that arrived: {carried:?}"
    );
    let (path, j) = &carried[0];
    assert_eq!(j["version"], 4);
    assert_eq!(
        j["carried"],
        serde_json::json!({"host_io": 1, "image": image})
    );
    assert_eq!(
        j["frame"]["host_io"], 2,
        "the receipt counts the call before the move and the one after"
    );
    let verify = |p: &Path| {
        blue(&repo_bidamas().display().to_string())
            .args(["receipt", "verify"])
            .arg(p)
            .output()
            .expect("blue receipt verify")
    };
    let o = verify(path);
    assert!(o.status.success(), "{}", err(&o));

    let mut cut = j.clone();
    cut["frame"]["host_io"] = serde_json::json!(0);
    let bytes = blue_lang_proc::receipt::canonical(&cut);
    let renamed = receipts.join(blue_lang_runtime::receipt::name_of(bytes.as_bytes()));
    put(&renamed, &bytes);
    let o = verify(&renamed);
    assert!(!o.status.success(), "{}", out(&o));
    assert!(
        err(&o).contains(&format!(
            "its host-call count is cut: process 2 brought a count of 1 in image {image}, and the receipt counts 0"
        )),
        "{}",
        err(&o)
    );
    let mut lowered = j.clone();
    lowered["carried"]["host_io"] = serde_json::json!(0);
    let edited = receipts.join("edited.receipt.json");
    put(&edited, &blue_lang_proc::receipt::canonical(&lowered));
    let o = verify(&edited);
    assert!(
        !o.status.success() && err(&o).contains("but its bytes hash to"),
        "an edit under the old name is refused by the name: {}",
        err(&o)
    );
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_moved_server_writes_a_bluecrash_that_replays_from_its_last_boundary_on_the_node_it_reached() {
    let (dir, path, j, said) = crashed_after_moving("replay-server", TILL);
    assert_eq!(said.len(), 3, "{said:?}");
    assert!(said[0].starts_with("b3:") && said[1] == "3" && said[2].contains("fatal"));
    assert_eq!(
        j["version"], 3,
        "a server's tape starts at its last boundary, which it reached on the node it moved to, so nothing came with it"
    );
    assert!(j["carried"].is_null());
    let state: Vec<&Json> = j["code"]["bindings"]
        .as_array()
        .expect("bindings")
        .iter()
        .filter(|b| b["name"] == "%state")
        .map(|b| &b["value"])
        .collect();
    assert_eq!(state, [&serde_json::json!({"int": 7})]);
    let o = replay(&path);
    let stdout = out(&o);
    assert!(o.status.success(), "{stdout}{}", err(&o));
    let recorded = j["exit"]["text"].as_str().expect("text");
    assert!(
        stdout.contains(&format!(
            "replayed: fatal {recorded} (3 of 3 tape entries)\n"
        )) && stdout.ends_with("reproduced\n")
            && !stdout.contains("not reproduced"),
        "{stdout}"
    );
    let _ = std::fs::remove_dir_all(dir);
}
