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
