//! A node whose processes are held to a frame: the crash journal a fatal
//! exit writes, its replay under the recorded hold, and the receipt each
//! incarnation hands its sink.

mod support;

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use blue_lang_proc::{replay, ClockKind, HostIo, NodeConfig, Receipt, Trace};
use blue_lang_runtime::Hold;
use blue_lang_waku::Capability;
use support::{configure, show};

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-proc-held-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    dir
}

/// A node holding every process to `host`, as `blue run --allow` does.
fn held(host: &[Capability]) -> (NodeConfig, Hold, HostIo) {
    let hold = Hold::from(blue_lang_runtime::session::frame_granting(host));
    let io = HostIo::new();
    let (h, i) = (hold.clone(), io.clone());
    let mut config = NodeConfig::new(Arc::new(move || {
        let mut child = blue_lang_runtime::interpreter_hostless();
        h.bind(&mut child, "this process's frame", &i);
        child
    }));
    config.budget.quantum = Some(100);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    config.frame = Some(hold.frame());
    config.host_io = io.clone();
    (config, hold, io)
}

/// A reader that takes `take` messages, then reaches the filesystem through
/// a bidama's function inside a `rescue`, which does not catch a breach.
fn breaching(take: usize, sends: &[&str]) -> String {
    let receives = "  receive()\n".repeat(take);
    let sends: String = sends
        .iter()
        .map(|m| format!("send(r, \"{m}\")\n"))
        .collect();
    format!(
        "def probe(path)\n  is_file?(path)\nend\n\
         def reader(parent)\n{receives}  send(parent, probe(\"/etc/hosts\") rescue \"swallowed\")\nend\n\
         r = spawn(reader, [self()])\nm = monitor(r)\n{sends}receive(:_, 5000)"
    )
}

fn round_trip(t: &Trace) -> Trace {
    Trace::parse(&serde_json::to_string(&t.to_json()).expect("json")).expect("parse")
}

#[test]
fn an_unsupervised_fatal_exit_is_written_as_a_bluecrash() {
    let dir = scratch("written");
    let (mut config, _, _) = held(&[]);
    config.trace_dir = Some(dir.clone());
    let (mut root, node) = configure(config);
    let out = show(&mut root, &breaching(0, &[]));
    assert!(
        out.contains(":fatal") && out.contains("capability-breach"),
        "{out}"
    );
    let files: Vec<PathBuf> = std::fs::read_dir(&dir)
        .expect("the trace directory")
        .map(|e| e.expect("entry").path())
        .collect();
    assert_eq!(files.len(), 1, "{files:?}");
    assert_eq!(
        files[0].extension().and_then(|e| e.to_str()),
        Some("bluecrash")
    );
    let trace = Trace::parse(&std::fs::read_to_string(&files[0]).expect("read")).expect("parse");
    assert_eq!(trace.reason_kind, "fatal");
    assert_eq!(node.traces().len(), 1);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn an_unsupervised_crash_that_is_not_fatal_is_kept_but_not_written() {
    let dir = scratch("kept");
    let (mut config, _, _) = held(&[]);
    config.trace_dir = Some(dir.clone());
    let (mut root, node) = configure(config);
    let out = show(
        &mut root,
        "def w(parent)\n  throw(error(:plain, \"x\"))\nend\nr = spawn(w, [self()])\nm = monitor(r)\nreceive(:_, 5000)",
    );
    assert!(out.contains(":crashed"), "{out}");
    assert_eq!(node.traces().len(), 1, "every crash is kept in memory");
    assert_eq!(node.traces()[0].reason_kind, "crashed");
    assert!(
        !dir.exists(),
        "an unsupervised crash that is not fatal writes nothing"
    );
}

#[test]
fn a_breach_replays_as_the_same_breach_at_the_same_tape_entry() {
    let (config, _, _) = held(&[]);
    let (mut root, node) = configure(config);
    let _ = show(&mut root, &breaching(1, &["first"]));
    let trace = round_trip(&node.traces()[0]);
    let hold = trace.hold.as_ref().expect("the hold is recorded");
    assert!(hold.granted.is_empty() && hold.provided.is_empty());
    assert_eq!(hold.withheld, Capability::host_effects());
    let calls: Vec<(&str, bool)> = trace
        .tape
        .iter()
        .map(|e| (e.call.as_str(), e.fatal.is_some()))
        .collect();
    assert_eq!(calls, [("receive", false), ("is_file?", true)]);

    let r = replay(&trace, blue_lang_runtime::interpreter_hostless());
    assert!(r.reproduced, "{r:?}");
    assert_eq!((r.kind.as_str(), r.consumed, r.tape_len), ("fatal", 2, 2));
    assert_eq!(r.text, trace.reason_text);

    let mut answered = trace.clone();
    answered.tape[1].outcome = Ok(tatara_lisp_eval::Value::Bool(true));
    answered.tape[1].fatal = None;
    let r = replay(&answered, blue_lang_runtime::interpreter_hostless());
    assert!(!r.reproduced, "{r:?}");
    assert!(
        r.diverged
            .as_deref()
            .is_some_and(|d| d.contains("withholds (filesystem)")),
        "a withheld name may not answer from the tape: {r:?}"
    );

    let mut unheld = answered.clone();
    unheld.hold = None;
    let r = replay(&unheld, blue_lang_runtime::interpreter_hostless());
    assert_eq!(r.consumed, 2, "without the hold the tape answers: {r:?}");
    assert!(
        r.diverged
            .as_deref()
            .is_some_and(|d| !d.contains("withholds")),
        "{r:?}"
    );
}

#[test]
fn the_journal_keeps_the_last_taken_and_the_first_waiting_within_its_bound() {
    let (mut config, _, _) = held(&[]);
    config.journal = 2;
    let (mut root, node) = configure(config);
    let _ = show(
        &mut root,
        &breaching(3, &["m1", "m2", "m3", "m4", "m5", "m6"]),
    );
    let trace = round_trip(&node.traces()[0]);
    let m = trace.mailbox.expect("a held process keeps a journal");
    let text =
        |vs: &[tatara_lisp_eval::Value]| vs.iter().map(ToString::to_string).collect::<Vec<_>>();
    assert_eq!(m.bound, 2);
    assert_eq!(text(&m.recent), ["\"m2\"", "\"m3\""]);
    assert_eq!(text(&m.unconsumed), ["\"m4\"", "\"m5\""]);
    assert_eq!(m.unconsumed_total, 3);
}

#[test]
fn a_journal_configured_off_or_an_unheld_node_keeps_no_mailbox() {
    let (mut config, _, _) = held(&[]);
    config.journal = 0;
    let (mut root, node) = configure(config);
    let _ = show(&mut root, &breaching(1, &["a", "b"]));
    let trace = round_trip(&node.traces()[0]);
    assert!(trace.mailbox.is_none());
    assert!(trace.hold.is_some(), "the hold is recorded either way");

    let (mut root, node) = support::node(100);
    let _ = show(
        &mut root,
        "def w()\n  receive()\n  throw(error(:x, \"x\"))\nend\nsup = supervisor(:one_for_one, [w], 0)\nm = monitor(sup)\nsend(nth(0, children(sup)), 1)\nsend(nth(0, children(sup)), 2)\nreceive()",
    );
    let trace = round_trip(&node.traces()[0]);
    assert!(trace.hold.is_none() && trace.mailbox.is_none());
}

#[test]
fn each_held_incarnation_hands_its_receipt_with_its_own_host_io() {
    let dir = scratch("io");
    std::fs::create_dir_all(&dir).expect("dir");
    let file = dir.join("data");
    std::fs::write(&file, "data").expect("write");
    let (mut config, _, io) = held(&[Capability::FileSystem]);
    let seen: Arc<Mutex<Vec<Receipt>>> = Arc::default();
    let s = Arc::clone(&seen);
    config.receipts = Some(Arc::new(move |r: &Receipt| {
        s.lock().expect("lock").push(r.clone());
    }));
    let (mut root, _node) = configure(config);
    let out = show(
        &mut root,
        &format!(
            "def twice(parent, p)\n  read_file(p)\n  send(parent, read_file(p))\nend\n\
             def none(parent)\n  send(parent, 1)\nend\n\
             spawn(twice, [self(), \"{0}\"])\nreceive(:_, 5000)\nspawn(none, [self()])\nreceive(:_, 5000)",
            file.display()
        ),
    );
    assert_eq!(out, "1", "{out}");
    let seen = seen.lock().expect("lock").clone();
    let counts: Vec<(Option<&str>, u64, &str)> = seen
        .iter()
        .map(|r| (r.definition.as_deref(), r.host_io, r.exit_kind.as_str()))
        .collect();
    assert_eq!(
        counts,
        [(Some("twice"), 2, "normal"), (Some("none"), 0, "normal")]
    );
    assert_eq!(seen[0].frame.granted, [Capability::FileSystem]);
    assert_eq!(io.total(), 2, "the root read nothing");
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_version_1_trace_is_still_read_and_replayed() {
    let (mut root, node) = support::node(100);
    let _ = show(
        &mut root,
        "def w()\n  receive()\n  throw(error(:x, \"boom\"))\nend\nsup = supervisor(:one_for_one, [w], 0)\nm = monitor(sup)\nsend(nth(0, children(sup)), 1)\nreceive()",
    );
    let mut j = node.traces()[0].to_json();
    assert_eq!(j["version"], 2);
    j["version"] = serde_json::json!(1);
    for k in ["def_hash", "hold", "mailbox"] {
        j.as_object_mut().expect("object").remove(k);
    }
    let v1 = Trace::from_json(&j).expect("a version 1 trace reads");
    assert!(v1.def_hash.is_none() && v1.hold.is_none() && v1.mailbox.is_none());
    let r = replay(&v1, blue_lang_runtime::interpreter_hostless());
    assert!(r.reproduced, "{r:?}");
}
