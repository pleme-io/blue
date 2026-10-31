//! `blue run --receipts DIR` writes one receipt for the run and one for each
//! process incarnation; `blue receipt verify` recomputes a receipt's name
//! from its bytes.

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
    let dir = std::env::temp_dir().join(format!("blue-receipts-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir.canonicalize().expect("canonical scratch dir")
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

/// Every receipt in `dir`, each verified by `blue receipt verify`.
fn receipts(dir: &Path) -> Vec<(PathBuf, serde_json::Value)> {
    let mut out: Vec<(PathBuf, serde_json::Value)> = std::fs::read_dir(dir)
        .expect("the receipts directory")
        .map(|e| {
            let p = e.expect("entry").path();
            let v = serde_json::from_slice(&std::fs::read(&p).expect("read")).expect("json");
            (p, v)
        })
        .collect();
    out.sort_by_key(|(_, v)| v["pid"].as_u64());
    for (p, _) in &out {
        let o = blue()
            .args(["receipt", "verify"])
            .arg(p)
            .output()
            .expect("verify");
        assert!(o.status.success(), "{}: {}", p.display(), err(&o));
    }
    out
}

fn run_with_receipts(dir: &Path, allow: &[&str], program: &str) -> Vec<serde_json::Value> {
    run_printing(dir, allow, program).0
}

/// [`run_with_receipts`], with what the run wrote on stdout.
fn run_printing(dir: &Path, allow: &[&str], program: &str) -> (Vec<serde_json::Value>, String) {
    let file = dir.join("p.b");
    std::fs::write(&file, program).expect("program");
    let into = dir.join("receipts");
    let mut c = blue();
    c.args(["run", "--quiet"]);
    for a in allow {
        c.args(["--allow", a]);
    }
    let o = c
        .arg("--receipts")
        .arg(&into)
        .arg(&file)
        .output()
        .expect("blue run");
    assert!(o.status.success(), "{}", err(&o));
    let got = receipts(&into).into_iter().map(|(_, v)| v).collect();
    (got, String::from_utf8_lossy(&o.stdout).into_owned())
}

/// One process that computes, and one that reaches the filesystem through a
/// bidama and breaches: under `--allow none` neither reaches the host.
const PURE: &str = "use(\"shisutemu\", [:read_or])\n\ndef double(parent, n)\n  send(parent, n * 2)\nend\n\ndef reader(parent)\n  send(parent, read_or(\"/etc/hosts\", \"\") rescue \"swallowed\")\nend\n\ndef main()\n  spawn(double, [self, 21])\n  write_stdout(to_s(receive(:_, 5000)))\n  r = spawn(reader, [self])\n  monitor(r)\n  write_stdout(to_s(receive(:_, 5000)))\nend\n";

#[test]
fn a_pure_frames_receipts_count_no_host_io_and_list_every_withheld_capability() {
    let dir = scratch("pure");
    let all = [
        "process",
        "filesystem",
        "environment",
        "clock",
        "network",
        "entropy",
        "comm-flash",
        "comm-scavenger",
    ];
    let got = run_with_receipts(&dir, &["none"], PURE);
    assert_eq!(got.len(), 3, "the run and its two processes: {got:?}");
    for r in &got {
        assert_eq!(r["frame"]["host_io"], 0, "{r}");
        assert_eq!(r["frame"]["granted"], serde_json::json!([]), "{r}");
        assert_eq!(r["frame"]["withheld"], serde_json::json!(all), "{r}");
        let keys: Vec<&String> = r["frame"].as_object().expect("frame").keys().collect();
        assert_eq!(
            keys.len(),
            3,
            "the frame block is granted, withheld, host_io: {r}"
        );
        assert!(
            r["def_hash"]
                .as_str()
                .is_some_and(|h| h.starts_with("b3:") && h.len() == 67),
            "{r}"
        );
    }
    let shape: Vec<(&str, &str, &str)> = got
        .iter()
        .map(|r| {
            (
                r["subject"].as_str().unwrap_or_default(),
                r["definition"].as_str().unwrap_or_default(),
                r["exit"]["kind"].as_str().unwrap_or_default(),
            )
        })
        .collect();
    assert_eq!(
        shape,
        [
            ("run", "%run", "normal"),
            ("actor", "%root/double", "normal"),
            ("actor", "%root/reader", "fatal"),
        ]
    );
    for r in &got {
        assert_eq!(
            r["version"], 1,
            "no server ran, so no receipt has roots: {r}"
        );
        assert!(r.get("input_root").is_none() && r.get("output_root").is_none());
    }
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_granted_run_counts_each_host_call_and_each_process_its_own() {
    let dir = scratch("granted");
    let data = dir.join("data");
    std::fs::write(&data, "data").expect("data");
    let program = format!(
        "def child(parent, path)\n  send(parent, read_file(path))\nend\n\ndef main()\n  path = \"{}\"\n  a = read_file(path)\n  b = read_file(path)\n  spawn(child, [self, path])\n  write_stdout(receive(:_, 5000))\nend\n",
        data.display()
    );
    let got = run_with_receipts(&dir, &["filesystem"], &program);
    assert_eq!(got.len(), 2, "{got:?}");
    let (run, child) = (&got[0], &got[1]);
    assert_eq!(run["frame"]["granted"], serde_json::json!(["filesystem"]));
    assert_eq!(
        run["frame"]["host_io"], 3,
        "two reads at the root, one in the child: {run}"
    );
    assert_eq!(child["definition"], "%root/child");
    assert_eq!(child["frame"]["host_io"], 1, "{child}");

    let unheld = run_with_receipts(&scratch("unheld"), &[], &program);
    assert_eq!(unheld[0]["frame"]["withheld"], serde_json::json!([]));
    assert_eq!(
        unheld[0]["frame"]["granted"].as_array().map(Vec::len),
        Some(8)
    );
    assert_eq!(unheld[0]["frame"]["host_io"], 3, "{}", unheld[0]);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn receipt_verify_passes_then_fails_after_a_one_byte_edit() {
    let dir = scratch("verify");
    let _ = run_with_receipts(&dir, &["none"], PURE);
    let (path, _) = receipts(&dir.join("receipts")).remove(0);
    let o = blue()
        .args(["receipt", "verify"])
        .arg(&path)
        .output()
        .expect("verify");
    assert!(o.status.success(), "{}", err(&o));
    let name = path.file_name().and_then(|n| n.to_str()).expect("name");
    assert_eq!(
        String::from_utf8_lossy(&o.stdout),
        format!("verified b3:{}\n", &name[..64])
    );
    let mut bytes = std::fs::read(&path).expect("read");
    let at = bytes
        .iter()
        .position(|b| *b == b'0')
        .expect("a digit to edit");
    bytes[at] = b'1';
    std::fs::write(&path, &bytes).expect("edit");
    let o = blue()
        .args(["receipt", "verify"])
        .arg(&path)
        .output()
        .expect("verify");
    assert!(!o.status.success());
    assert!(err(&o).contains("but its bytes hash to"), "{}", err(&o));
    let _ = std::fs::remove_dir_all(dir);
}

/// A server that adds each number it is sent to its state, and answers
/// `[pid]` with its state, then adds 100. It prints its `def_hash` as the
/// word answers it, and the roots blue computes for its first and last
/// state.
const SERVER: &str = "def counter(m, n)\n  if list?(m)\n    send(first(m), n)\n    n + 100\n  else\n    n + m\n  end\nend\n\ndef root_of(state)\n  \"b3:#{blake3_hex(json_canonical(json_stringify(state)))}\"\nend\n\ndef main()\n  srv = spawn_server(counter, 0)\nSENDS  send(srv, [self])\n  n = receive(:_, 5000)\n  monitor(srv)\n  exit(srv, :kill)\n  receive(%i[down _ _ _], 5000)\n  write_stdout(unlines([def_hash(counter), root_of(0), root_of(n + 100)]))\nend\n";

fn server(sends: &[i64]) -> String {
    let lines: String = sends
        .iter()
        .map(|n| format!("  send(srv, {n})\n"))
        .collect();
    SERVER.replace("SENDS", &lines)
}

/// The server's receipt, and the three lines its run printed.
fn served(name: &str, sends: &[i64]) -> (serde_json::Value, Vec<String>) {
    let dir = scratch(name);
    let (got, out) = run_printing(&dir, &["none"], &server(sends));
    let _ = std::fs::remove_dir_all(dir);
    let lines: Vec<String> = out.lines().map(str::to_string).collect();
    assert_eq!(lines.len(), 3, "{out}");
    let mut actors = got.into_iter().filter(|r| r["subject"] == "actor");
    let receipt = actors.next().expect("the server's receipt");
    assert!(actors.next().is_none(), "one process, one incarnation");
    assert_eq!(receipt["definition"], "%root/counter", "{receipt}");
    (receipt, lines)
}

#[test]
fn the_def_hash_word_answers_the_hash_the_servers_receipt_records() {
    let (receipt, lines) = served("word", &[2, 3]);
    assert!(
        lines[0].starts_with("b3:") && lines[0].len() == 67,
        "{lines:?}"
    );
    assert_eq!(receipt["def_hash"], lines[0].as_str(), "{receipt}");
}

#[test]
fn a_server_receipt_binds_its_state_before_its_first_message_and_after_its_last() {
    let (first, lines) = served("roots", &[2, 3]);
    assert_eq!(first["version"], 2, "{first}");
    assert_eq!(
        first["input_root"],
        lines[1].as_str(),
        "the state it began with: 0"
    );
    assert_eq!(
        first["output_root"],
        lines[2].as_str(),
        "the state after its last message: 2 + 3 + 100"
    );
    assert_ne!(first["input_root"], first["output_root"]);

    let (again, _) = served("roots-again", &[2, 3]);
    assert_eq!(again, first, "an identical run writes an identical receipt");

    let (other, other_lines) = served("roots-other", &[2, 4]);
    assert_eq!(
        other["input_root"], first["input_root"],
        "the same first state"
    );
    assert_ne!(
        other["output_root"], first["output_root"],
        "a different last state"
    );
    assert_eq!(other["output_root"], other_lines[2].as_str());
}

/// One ibuki Strand step run as a process, then again in `main`, which
/// prints the record's `def_hash`.
const STRAND: &str = "use(\"ibuki\", %i[step strand])\n\ndef main()\n  s = strand({})\n  op = {op: :put, key: \"k\", value: 1, at: 1, by: \"r\"}\n  p = spawn(step, [s, op])\n  monitor(p)\n  receive(%i[down _ _ _], 5000)\n  write_stdout(step(s, op).record.def_hash)\nend\n";

#[test]
fn the_strand_record_names_the_def_hash_its_step_process_receipt_records() {
    let dir = scratch("strand");
    let (got, out) = run_printing(&dir, &["none"], STRAND);
    let step = got
        .iter()
        .find(|r| r["subject"] == "actor")
        .expect("the step process's receipt");
    assert_eq!(step["definition"], "ibuki/step", "{step}");
    assert!(out.starts_with("b3:") && out.len() == 67, "{out}");
    assert_eq!(step["def_hash"], out.as_str(), "{step}");
    let _ = std::fs::remove_dir_all(dir);
}

/// `j`'s canonical bytes under their content address in `dir`, as `blue
/// receipt verify` sees them.
fn verified(dir: &Path, j: &serde_json::Value) -> Output {
    let bytes = blue_lang_proc::receipt::canonical(j).into_bytes();
    let path = dir.join(blue_lang_runtime::receipt::name_of(&bytes));
    std::fs::write(&path, bytes).expect("write");
    blue()
        .args(["receipt", "verify"])
        .arg(&path)
        .output()
        .expect("verify")
}

#[test]
fn receipt_verify_reads_versions_1_and_2_and_refuses_a_root_out_of_place() {
    let dir = scratch("versions");
    let v1: serde_json::Value = serde_json::from_str(r#"{"def_hash":"b3:ab","definition":"%root/w","exit":{"kind":"normal","text":"normal"},"format":"blue-receipt","frame":{"granted":["filesystem"],"host_io":7,"withheld":["process","environment","network","entropy"]},"incarnation":1,"pid":2,"provided":[],"subject":"actor","version":1}"#).expect("json");
    let o = verified(&dir, &v1);
    assert!(o.status.success(), "a version 1 receipt: {}", err(&o));
    let (v2, _) = served("versions-v2", &[1]);
    let o = verified(&dir, &v2);
    assert!(o.status.success(), "a version 2 receipt: {}", err(&o));

    let mut rooted_v1 = v1.clone();
    rooted_v1["input_root"] = v2["input_root"].clone();
    rooted_v1["output_root"] = v2["output_root"].clone();
    let mut unrooted_v2 = v2.clone();
    let m = unrooted_v2.as_object_mut().expect("object");
    m.remove("input_root");
    m.remove("output_root");
    let mut v3 = v2.clone();
    v3["version"] = serde_json::json!(3);
    for (j, why) in [
        (&rooted_v1, "carries `input_root`"),
        (&unrooted_v2, "without `input_root`"),
        (&v3, "reads versions 1 to 2"),
    ] {
        let o = verified(&dir, j);
        assert!(!o.status.success(), "{why}: {j}");
        assert!(err(&o).contains(why), "{why}: {}", err(&o));
    }
    let _ = std::fs::remove_dir_all(dir);
}
