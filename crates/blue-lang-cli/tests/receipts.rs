//! `blue run --receipts DIR` writes one receipt for the run and one for each
//! process incarnation; `blue receipt verify` recomputes a receipt's name
//! from its bytes.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
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
    receipts(&into).into_iter().map(|(_, v)| v).collect()
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
        "mpc-threshold",
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
        Some(9)
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
