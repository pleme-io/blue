use std::path::{Path, PathBuf};
use std::process::{Command, Output};

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
    let dir = std::env::temp_dir().join(format!("blue-run-replay-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir.canonicalize().expect("canonical scratch dir")
}

fn text(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

const CLOCKED: &str = "def main()
  me = self
  spawn(
    fn()
      sleep_for(500)
      send(me, [:woke, node_time])
    end
  )
  [argv, now_ms > 0, random_bytes(4), receive()]
end
";

const ECHO: &str = "def main()
  l = tcp_listen(\"127.0.0.1:0\")
  port = tcp_port(l)
  me = self
  spawn(
    fn()
      c = tcp_connect(\"127.0.0.1:#{port}\", 1000)
      net_wait([[c, :write]], 1000)
      tcp_write(c, \"ping\")
      net_wait([[c, :read]], 5000)
      send(me, [:client, bytes_text(tcp_read(c, 64))])
    end
  )
  net_wait([[l, :read]], 5000)
  s = tcp_accept(l)
  net_wait([[s, :read]], 5000)
  got = bytes_text(tcp_read(s, 64))
  tcp_write(s, \"pong\")
  [got, receive()]
end
";

struct Recorded {
    receipt: PathBuf,
    record: PathBuf,
    printed: String,
}

fn record(dir: &Path, program: &str, args: &[&str]) -> Recorded {
    let file = dir.join("p.b");
    std::fs::write(&file, program).expect("program");
    let into = dir.join("receipts");
    let o = blue()
        .arg("run")
        .arg("--receipts")
        .arg(&into)
        .arg("--record")
        .arg(&file)
        .arg("--")
        .args(args)
        .output()
        .expect("blue run");
    assert!(o.status.success(), "{}", text(&o));
    let runs: Vec<PathBuf> = std::fs::read_dir(&into)
        .expect("receipts")
        .map(|e| e.expect("entry").path())
        .filter(|p| p.to_string_lossy().ends_with(".run.json"))
        .collect();
    assert_eq!(runs.len(), 1, "one run record in {}", into.display());
    let record = runs[0].clone();
    let receipt = PathBuf::from(
        record
            .to_string_lossy()
            .replace(".run.json", ".receipt.json"),
    );
    assert!(receipt.exists(), "{} beside its record", receipt.display());
    Recorded {
        receipt,
        record,
        printed: String::from_utf8_lossy(&o.stdout).into_owned(),
    }
}

fn replay(receipt: &Path) -> Output {
    blue()
        .arg("replay")
        .arg(receipt)
        .output()
        .expect("blue replay")
}

fn named(receipt: &Path) -> String {
    let name = receipt.file_name().and_then(|n| n.to_str()).expect("name");
    format!("b3:{}", name.trim_end_matches(".receipt.json"))
}

fn json(path: &Path) -> serde_json::Value {
    serde_json::from_slice(&std::fs::read(path).expect("read")).expect("json")
}

#[test]
fn a_recorded_run_replays_to_a_receipt_equal_to_the_original() {
    let dir = scratch("equal");
    let run = record(&dir, CLOCKED, &["one", "two"]);
    assert!(
        run.printed.starts_with("[[one, two], true, ["),
        "{}",
        run.printed
    );
    assert!(
        run.printed.trim_end().ends_with("[:woke, 500]]"),
        "{}",
        run.printed
    );
    let receipt = json(&run.receipt);
    assert_eq!(receipt["version"], 6);
    assert_eq!(receipt["subject"], "run");
    let o = blue()
        .args(["receipt", "verify"])
        .arg(&run.receipt)
        .output()
        .expect("verify");
    assert!(o.status.success(), "{}", text(&o));
    let o = replay(&run.receipt);
    let shown = text(&o);
    assert!(o.status.success(), "{shown}");
    let original = named(&run.receipt);
    assert!(shown.contains(&format!("recorded: {original}")), "{shown}");
    assert!(shown.contains(&format!("replayed: {original}")), "{shown}");
    assert!(shown.contains("3 of 3 host answers read"), "{shown}");
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_changed_input_makes_the_replayed_receipt_differ() {
    let dir = scratch("changed");
    let run = record(&dir, CLOCKED, &["one", "two"]);
    let mut r = json(&run.record);
    r["run"]["args"] = serde_json::json!(["one", "three"]);
    std::fs::write(&run.record, serde_json::to_vec(&r).expect("bytes")).expect("edit");
    let o = replay(&run.receipt);
    let shown = text(&o);
    assert!(!o.status.success(), "{shown}");
    assert!(shown.contains("not reproduced"), "{shown}");
    let original = named(&run.receipt);
    let replayed = shown
        .lines()
        .find_map(|l| l.strip_prefix("replayed: "))
        .expect("a replayed line");
    assert_ne!(replayed, original);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn two_runs_with_different_inputs_have_different_receipts() {
    let a = record(&scratch("first"), CLOCKED, &["one"]);
    let b = record(&scratch("second"), CLOCKED, &["two"]);
    let (ja, jb) = (json(&a.receipt), json(&b.receipt));
    assert_ne!(named(&a.receipt), named(&b.receipt));
    assert_ne!(ja["replay"]["inputs"], jb["replay"]["inputs"]);
    assert_ne!(ja["replay"]["output"], jb["replay"]["output"]);
}

#[test]
fn the_tape_answers_the_replay_so_entropy_and_the_clock_are_what_they_were() {
    let dir = scratch("tape");
    let run = record(&dir, CLOCKED, &[]);
    let mut r = json(&run.record);
    let root = r["tapes"]["0"].as_array_mut().expect("the root's tape");
    let entropy = root
        .iter_mut()
        .find(|e| e["call"] == "random_bytes")
        .expect("random_bytes on the tape");
    entropy["value"] =
        serde_json::json!({"list": [{"int": 0}, {"int": 0}, {"int": 0}, {"int": 0}]});
    std::fs::write(&run.record, serde_json::to_vec(&r).expect("bytes")).expect("edit");
    let o = replay(&run.receipt);
    assert!(!o.status.success(), "{}", text(&o));
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_networked_run_replays_with_no_socket_open() {
    let dir = scratch("echo");
    let run = record(&dir, ECHO, &[]);
    assert_eq!(run.printed.trim_end(), "[ping, [:client, pong]]");
    let tapes = json(&run.record)["tapes"].clone();
    let calls: Vec<String> = tapes["1"]
        .as_array()
        .expect("the client's tape")
        .iter()
        .map(|e| e["call"].as_str().unwrap_or_default().to_string())
        .collect();
    assert_eq!(
        calls,
        [
            "tcp_connect",
            "net_wait",
            "tcp_write",
            "net_wait",
            "tcp_read"
        ]
    );
    let o = replay(&run.receipt);
    let shown = text(&o);
    assert!(o.status.success(), "{shown}");
    assert!(shown.contains("12 of 12 host answers read"), "{shown}");
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_receipt_without_a_record_beside_it_is_refused_by_name() {
    let dir = scratch("alone");
    let run = record(&dir, CLOCKED, &[]);
    std::fs::remove_file(&run.record).expect("remove the record");
    let o = replay(&run.receipt);
    let shown = text(&o);
    assert!(!o.status.success(), "{shown}");
    assert!(shown.contains("--record"), "{shown}");
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_frame_without_the_network_refuses_net_wait_before_the_run() {
    let dir = scratch("held");
    let file = dir.join("p.b");
    std::fs::write(&file, ECHO).expect("program");
    let o = blue()
        .args(["run", "--allow", "process"])
        .arg(&file)
        .output()
        .expect("blue run");
    let shown = text(&o);
    assert!(!o.status.success(), "{shown}");
    assert!(shown.contains("network"), "{shown}");
    let _ = std::fs::remove_dir_all(dir);
}
