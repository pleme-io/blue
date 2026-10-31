//! A crash trace as forensic evidence, through the `blue` binary.
//!
//! A worker held to `--allow none` takes five messages; the fourth makes it
//! reach the filesystem through a bidama. Its `.bluecrash` is `blue-trace`
//! version 3, named by the BLAKE3 hash of its canonical bytes, and names the
//! violation, the host name and capability it demanded, and the breaching
//! call's file, line and column. `blue crash dump` prints that, `blue crash
//! bisect` reduces the mailbox to the one poison message by deterministic
//! replay, and `blue crash immunize` writes a test that is red on the crashed
//! code and green once the worker is fixed.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const WORKER: &str = "use(\"shisutemu\", [:read_or])\n\ndef worker(parent)\n  msg = receive()\n  if msg == \"poison\"\n    read_or(\"/etc/hosts\", \"\")\n  end\n  send(parent, [:did, msg])\n  worker(parent)\nend\n\ndef main()\n  pid = spawn(worker, [self])\n  monitor(pid)\n  map((m) -> send(pid, m), %w[a b c poison e])\n  write_stdout(to_s(receive(%i[down _ _ _], 5000)))\nend\n";

const FIXED: &str = "def worker(parent)\n  msg = receive()\n  if msg == \"poison\"\n    :refused\n  end\n  send(parent, [:did, msg])\n  worker(parent)\nend\n\ndef main()\n  pid = spawn(worker, [self])\n  monitor(pid)\n  map((m) -> send(pid, m), %w[a b c poison e])\n  write_stdout(to_s(receive(%i[down _ _ _], 5000)))\nend\n";

struct Crash {
    dir: PathBuf,
    program: PathBuf,
    traces: PathBuf,
    file: PathBuf,
    hex: String,
    json: serde_json::Value,
}

impl Drop for Crash {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

impl Crash {
    fn blue(&self) -> Command {
        let mut c = blue();
        c.env("BLUE_TRACE_DIR", &self.traces);
        c
    }

    fn short(&self) -> String {
        format!("b3:{}", &self.hex[..8])
    }
}

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG")
        .env_remove("BLUE_CRASH_JOURNAL");
    c
}

fn out(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

fn traces_in(dir: &Path) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir)
        .expect("trace dir")
        .map(|e| e.expect("entry").path())
        .collect();
    files.sort();
    files
}

fn crash(name: &str) -> Crash {
    let dir = std::env::temp_dir().join(format!("blue-forensics-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    let dir = dir.canonicalize().expect("canonical dir");
    let program = dir.join("worker.b");
    std::fs::write(&program, WORKER).expect("program");
    let traces = dir.join("traces");
    let o = blue()
        .env("BLUE_TRACE_DIR", &traces)
        .args(["run", "--quiet", "--allow", "none"])
        .arg(&program)
        .output()
        .expect("blue run");
    assert!(o.status.success(), "{}", err(&o));
    assert_eq!(
        std::fs::read_to_string(&program).expect("program"),
        WORKER,
        "the program is canonical, so the run leaves it as written"
    );
    let files = traces_in(&traces);
    assert_eq!(files.len(), 1, "{files:?}");
    let file = files[0].clone();
    let name = file.file_name().and_then(|n| n.to_str()).expect("name");
    let (hex, ext) = name.split_once('.').expect("hash.ext");
    assert_eq!(ext, "bluecrash");
    let json = serde_json::from_slice(&std::fs::read(&file).expect("read")).expect("json");
    Crash {
        hex: hex.to_string(),
        dir,
        program,
        traces,
        file,
        json,
    }
}

/// Where `is_file?` is called inside `read_or`, in the shisutemu the binary
/// carries: 1-based line and column.
fn read_or_call_site() -> (u64, u64) {
    let src = std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../bidamas/shisutemu/shisutemu.b"),
    )
    .expect("shisutemu source");
    let def = src.find("def read_or(").expect("read_or");
    let at = def + src[def..].find("is_file?(path)").expect("the call");
    let line = src[..at].matches('\n').count() + 1;
    let column = at - src[..at].rfind('\n').map_or(0, |n| n + 1) + 1;
    (line as u64, column as u64)
}

#[test]
fn a_breach_writes_a_version_3_bluecrash_named_by_its_crash_hash() {
    let c = crash("v3");
    let bytes = std::fs::read(&c.file).expect("read");
    assert_eq!(
        tameshi::hash::Blake3Hash::digest(&bytes).to_hex(),
        c.hex,
        "the file is named by the BLAKE3 hash of its bytes"
    );
    let ingested = tameshi::forensics::bluecrash::BlueCrash::parse(&bytes)
        .expect("tameshi ingests the crash as incident evidence");
    assert_eq!(
        ingested.digest().to_hex(),
        c.hex,
        "tameshi's digest of the canonical artifact is the crash hash"
    );
    let mut v2 = c.json.clone();
    v2.as_object_mut().expect("object").remove("frame");
    assert!(
        tameshi::forensics::bluecrash::BlueCrash::parse(&serde_json::to_vec(&v2).expect("json"))
            .is_err(),
        "without the frame block, as version 2 wrote it, tameshi refuses the crash"
    );

    let j = &c.json;
    assert_eq!(j["version"], 3);
    let v = &j["violation"];
    assert_eq!(v["class"], "LatticeCeilingBreach");
    assert_eq!(v["host"], "is_file?");
    assert_eq!(v["capability"], "filesystem");
    let tape = j["tape"].as_array().expect("tape");
    assert_eq!(v["entry"], tape.len() - 1);
    assert_eq!(tape.last().expect("entry")["call"], "is_file?");
    let at = &v["at"];
    assert_eq!(at["definition"], "shisutemu/read_or");
    assert!(
        at["file"]
            .as_str()
            .is_some_and(|f| f.ends_with("shisutemu/shisutemu.b")),
        "{at}"
    );
    let (line, column) = read_or_call_site();
    assert_eq!(
        (&at["line"], &at["column"]),
        (&line.into(), &column.into()),
        "{at}"
    );
    assert_eq!(
        j["defined_at"],
        serde_json::json!({"file": c.program.display().to_string(), "line": 3, "column": 1})
    );
    assert_eq!(
        j["frame"],
        serde_json::json!({
            "granted": [],
            "withheld": [
                "process",
                "filesystem",
                "environment",
                "clock",
                "network",
                "entropy",
                "comm-flash",
                "comm-scavenger",
            ],
            "host_io": 0,
        })
    );
}

#[test]
fn dump_prints_the_violation_its_coordinate_the_hold_the_exit_and_the_mailbox() {
    let c = crash("dump");
    let o = c
        .blue()
        .args(["crash", "dump", &c.short()])
        .output()
        .expect("dump");
    let text = out(&o);
    assert!(o.status.success(), "{text}{}", err(&o));
    let (line, column) = read_or_call_site();
    for want in [
        format!("crash b3:{}\n", c.hex),
        format!(
            "process 1 (worker) incarnation 0, defined at {}:3:1\n",
            c.program.display()
        ),
        "exit: fatal fatal capability-breach: `is_file?` reaches the host (filesystem)".into(),
        "violation: LatticeCeilingBreach: `is_file?` demands filesystem\n".into(),
        format!("shisutemu/shisutemu.b:{line}:{column} in shisutemu::read_or (tape entry 8 of 8)\n"),
        "hold: granted none; provided none; withheld process, filesystem, environment, clock, network, entropy, comm-flash, comm-scavenger\n".into(),
        "host calls through granted names: 0\n".into(),
        "mailbox: 4 recent, 1 unconsumed (bound 8)\n  waiting: \"e\"\n".into(),
    ] {
        assert!(text.contains(&want), "missing {want:?} in:\n{text}");
    }

    let o = c
        .blue()
        .args(["crash", "dump", "--json"])
        .arg(&c.file)
        .output()
        .expect("dump --json");
    let j: serde_json::Value = serde_json::from_slice(&o.stdout).expect("one object");
    assert_eq!(j["crash_hash"], format!("b3:{}", c.hex));
    assert_eq!(j["definition"], "worker");
    assert_eq!(j["violation"]["at"]["definition"], "shisutemu::read_or");
    assert_eq!(j["mailbox"]["unconsumed"], serde_json::json!(["\"e\""]));
    assert_eq!(j["exit"]["kind"], "fatal");

    let o = c
        .blue()
        .args(["crash", "dump", "b3:00000000"])
        .output()
        .expect("dump");
    assert!(!o.status.success());
    assert!(
        err(&o).contains("no trace named b3:00000000"),
        "{}",
        err(&o)
    );
}

#[test]
fn bisect_reduces_a_five_message_mailbox_to_the_one_poison_message() {
    let c = crash("bisect");
    let o = c
        .blue()
        .args(["crash", "bisect", "--json", &c.short()])
        .output()
        .expect("bisect");
    assert!(o.status.success(), "{}{}", out(&o), err(&o));
    let j: serde_json::Value = serde_json::from_slice(&o.stdout).expect("one object");
    assert_eq!(
        j["received"], 4,
        "the fifth message never reached the worker"
    );
    assert_eq!(j["unconsumed"], 1);
    assert_eq!(j["kept"], serde_json::json!([3]));
    assert_eq!(j["messages"], serde_json::json!(["\"poison\""]));
    let reduced = j["reduced"]["crash_hash"].as_str().expect("reduced hash");
    assert_ne!(reduced, format!("b3:{}", c.hex));
    assert_eq!(traces_in(&c.traces).len(), 2, "written beside the original");

    let o = c.blue().args(["replay", reduced]).output().expect("replay");
    let text = out(&o);
    assert!(o.status.success(), "{text}");
    assert!(
        text.contains("(2 of 2 tape entries)") && text.ends_with("reproduced\n"),
        "the poison message alone replays to the same breach: {text}"
    );
    let r: serde_json::Value = serde_json::from_slice(
        &std::fs::read(c.traces.join(format!("{}.bluecrash", &reduced[3..]))).expect("reduced"),
    )
    .expect("json");
    assert_eq!(r["violation"]["entry"], 1);
    assert_eq!(
        r["mailbox"]["recent"],
        serde_json::json!([{"str": "poison"}])
    );
}

#[test]
fn immunize_writes_a_lock_that_is_red_on_the_crashed_code_and_green_once_fixed() {
    let c = crash("immunize");
    let o = c
        .blue()
        .args(["crash", "immunize", &c.short()])
        .output()
        .expect("immunize");
    let text = out(&o);
    assert!(o.status.success(), "{text}{}", err(&o));
    assert!(
        text.contains("input: 1 of 4 messages taken (bisected)")
            && text.contains(&format!(
                "run: blue test --allow none {}",
                c.program.display()
            )),
        "{text}"
    );
    let written = std::fs::read_to_string(&c.program).expect("program");
    let short = &c.hex[..12];
    assert!(
        written.starts_with(WORKER),
        "appended, nothing else changed"
    );
    for want in [
        format!("def immunize_{short}()"),
        "  pid = spawn(worker, [0])".into(),
        "  send(pid, \"poison\")".into(),
        "satisfies: [:nist_ir_4]".into(),
        "target: worker".into(),
        format!("  assert immunize_{short} == :survived"),
    ] {
        assert!(written.contains(&want), "missing {want:?} in:\n{written}");
    }
    let fmt = blue()
        .args(["fmt", "--check"])
        .arg(&c.program)
        .output()
        .expect("fmt");
    assert!(
        fmt.status.success(),
        "write_program wrote it canonical: {}",
        err(&fmt)
    );

    let test = |allow: bool| {
        let mut cmd = c.blue();
        cmd.arg("test");
        if allow {
            cmd.args(["--allow", "none"]);
        }
        cmd.arg(&c.program).output().expect("blue test")
    };
    let red = test(true);
    let said = format!("{}{}", out(&red), err(&red));
    assert!(!red.status.success(), "{said}");
    assert!(
        said.contains("left:  [\n  :fatal,\n  \"fatal capability-breach: `is_file?` reaches the host (filesystem)")
            && said.contains("0 passed, 1 failed"),
        "red on the crashed code, naming the crash: {said}"
    );
    assert!(
        test(false).status.success(),
        "unheld the breach cannot happen, so the lock needs the hold it prints"
    );

    let lock = &written[WORKER.len()..];
    std::fs::write(&c.program, format!("{FIXED}{lock}")).expect("fix");
    let green = test(true);
    assert!(green.status.success(), "{}{}", out(&green), err(&green));
    assert!(
        out(&green).contains("1 passed, 0 failed"),
        "{}",
        out(&green)
    );
}

#[test]
fn a_trace_named_by_a_hash_its_content_no_longer_has_is_refused() {
    let c = crash("edited");
    let mut j = c.json.clone();
    j["mailbox"]["bound"] = serde_json::json!(9);
    std::fs::write(&c.file, serde_json::to_vec(&j).expect("json")).expect("edit");
    for args in [vec!["crash", "dump"], vec!["replay"]] {
        let o = c.blue().args(&args).arg(c.short()).output().expect("blue");
        assert!(!o.status.success(), "{args:?}: {}", out(&o));
        assert!(
            err(&o).contains("the trace was edited"),
            "{args:?}: {}",
            err(&o)
        );
    }
}
