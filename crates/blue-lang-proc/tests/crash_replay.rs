//! A crash writes a trace, and the trace replays the crash on its own.
//!
//! The claim under test: a process's crash can be reproduced from its trace
//! with nothing else — not the program file, not the other processes, not the
//! host — even when the crash depended on how the scheduler interleaved
//! processes that the replay never runs.

mod support;

use blue_lang_proc::{replay, ClockKind, NodeConfig, Trace};
use std::sync::Arc;
use support::{configure, node, show};

/// A consumer that crashes when `:b` arrives before `:a`. Whether it does is
/// decided by the interleaving: producer `a` spins first, so a small quantum
/// lets `b` send before `a` finishes and a large one does not.
const ORDER_SENSITIVE: &str = "\
def consumer(parent)
  first = receive()
  if first == :b
    throw(error(:order, \"b arrived before a\"))
  end
  second = receive()
  send(parent, [:done, first, second])
end
def spin(n)
  if n == 0
    0
  else
    spin(n - 1)
  end
end
def producer(target, tag, work)
  spin(work)
  send(target, tag)
end
me = self()
sup = supervisor(:one_for_one, [[consumer, [me]]], 0)
c = nth(0, children(sup))
spawn(producer, [c, :a, 60])
spawn(producer, [c, :b, 1])
m = monitor(sup)
receive(:_, 10000, :nothing)
";

fn trace_round_trip(t: &Trace) -> Trace {
    let text = serde_json::to_string(&t.to_json()).expect("serialize");
    Trace::parse(&text).expect("parse")
}

#[test]
fn replay_reproduces_a_crash_that_only_one_interleaving_produces() {
    // A coarse quantum: `a` finishes its spin and sends first. No crash.
    let (mut root, coarse) = node(10_000);
    let out = show(&mut root, ORDER_SENSITIVE);
    assert_eq!(out, "(:done :a :b)", "the coarse schedule must not crash");
    assert!(coarse.traces().is_empty());

    // A fine quantum: `b` sends while `a` is still spinning. Crash.
    let (mut root, fine) = node(5);
    let out = show(&mut root, ORDER_SENSITIVE);
    assert!(out.contains("gave_up"), "the fine schedule must crash: {out}");
    let traces = fine.traces();
    assert_eq!(traces.len(), 1);
    let trace = trace_round_trip(&traces[0]);
    assert_eq!(trace.reason_kind, "crashed");
    assert!(trace.reason_text.contains("b arrived before a"));
    assert_eq!(trace.tape.len(), 1, "the consumer received one message: {:?}", trace.tape);
    assert!(!trace.schedule.is_empty(), "the interleaving record rides along");

    // The replay runs the consumer alone: no producers, no scheduler.
    let r = replay(&trace, blue_lang_runtime::interpreter_hostless());
    assert!(r.reproduced, "{r:?}");
    assert_eq!(r.consumed, 1);

    // Anti-vacuity: the same consumer handed the OTHER order does not crash,
    // so the reproduction came from the tape and not from the code alone.
    let mut swapped = trace.clone();
    swapped.tape[0].outcome = Ok(tatara_lisp_eval::Value::Keyword(Arc::from("a")));
    let r = replay(&swapped, blue_lang_runtime::interpreter_hostless());
    assert!(!r.reproduced, "{r:?}");
    assert!(r.diverged.is_some(), "it asks for a second message the tape does not hold: {r:?}");
}

#[test]
fn host_reads_are_recorded_and_the_replay_never_reaches_the_host() {
    let dir = std::env::temp_dir().join(format!("blue-proc-replay-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("dir");
    let marker = dir.join("written-by-the-process");
    let src = format!(
        "def reader(path)\n  t = now_ms()\n  write_file(path, \"x\")\n  home = getenv(\"BLUE_REPLAY_PROBE\")\n  throw(error(:saw, \"probe=#{{home}} t=#{{t > 0}}\"))\nend\n\
         sup = supervisor(:one_for_one, [[reader, [\"{}\"]]], 0)\nm = monitor(sup)\nreceive()",
        marker.display()
    );
    // SAFETY of the test, not of code: the variable is this test's own.
    unsafe { std::env::set_var("BLUE_REPLAY_PROBE", "recorded") };
    let (mut root, node) = node(100);
    let _ = show(&mut root, &src);
    let trace = trace_round_trip(&node.traces()[0]);
    let calls: Vec<&str> = trace.tape.iter().map(|e| e.call.as_str()).collect();
    assert_eq!(calls, ["now_ms", "write_file", "getenv"], "every host read, in order");
    assert!(marker.exists(), "the live run did write");

    std::fs::remove_file(&marker).expect("rm");
    unsafe { std::env::set_var("BLUE_REPLAY_PROBE", "changed since") };
    let r = replay(&trace, blue_lang_runtime::interpreter_hostless());
    assert!(r.reproduced, "the replay saw the recorded environment, not today's: {r:?}");
    assert!(r.text.contains("probe=recorded"), "{r:?}");
    assert!(!marker.exists(), "the replay wrote nothing: write_file read its result off the tape");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_server_crash_replays_from_its_last_boundary() {
    let (mut root, node) = node(100);
    let out = show(
        &mut root,
        "def account(msg, balance)\n  next = balance - msg\n  if next < 0\n    throw(error(:overdrawn, \"balance #{next}\"))\n  end\n  next\nend\n\
         s = spawn_server(account, 100)\nm = monitor(s)\n\
         map(fn(x) send(s, x) end, [10, 20, 30, 50])\n\
         receive([:down, m, :_, :_])",
    );
    assert!(out.contains("balance -10"), "{out}");
    let trace = trace_round_trip(&node.traces()[0]);
    // The tape starts at the boundary before the fatal message: the state is
    // 40 there, and the one entry is the 50 that overdrew it.
    let state = trace.code.bindings.iter().find(|(n, _)| &**n == "%state").map(|(_, v)| v.to_string());
    assert_eq!(state.as_deref(), Some("40"));
    assert_eq!(trace.tape.len(), 1);
    let r = replay(&trace, blue_lang_runtime::interpreter_hostless());
    assert!(r.reproduced, "{r:?}");
}

#[test]
fn a_runaway_replays_as_a_runaway() {
    let mut config = NodeConfig::new(Arc::new(blue_lang_runtime::interpreter_hostless));
    config.budget.fuel = Some(5_000);
    config.budget.quantum = Some(100);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    let (mut root, node) = configure(config);
    let _ = show(
        &mut root,
        "def spin(n)\n  spin(n + 1)\nend\nsup = supervisor(:one_for_one, [[spin, [0]]], 0)\nm = monitor(sup)\nreceive()",
    );
    let trace = trace_round_trip(&node.traces()[0]);
    assert_eq!(trace.reason_kind, "runaway");
    let r = replay(&trace, blue_lang_runtime::interpreter_hostless());
    assert!(r.reproduced, "{r:?}");
}

#[test]
fn a_truncated_tape_never_claims_a_reproduction() {
    let mut config = NodeConfig::new(Arc::new(blue_lang_runtime::interpreter_hostless));
    config.max_tape = 2;
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    let (mut root, node) = configure(config);
    let _ = show(
        &mut root,
        "def take3()\n  receive()\n  receive()\n  receive()\n  throw(error(:third, \"x\"))\nend\n\
         sup = supervisor(:one_for_one, [take3], 0)\nc = nth(0, children(sup))\nm = monitor(sup)\n\
         send(c, 1)\nsend(c, 2)\nsend(c, 3)\nreceive()",
    );
    let trace = trace_round_trip(&node.traces()[0]);
    assert!(trace.truncated);
    let r = replay(&trace, blue_lang_runtime::interpreter_hostless());
    assert!(!r.reproduced, "{r:?}");
}

#[test]
fn values_and_forms_survive_the_trace_format() {
    let (mut root, node) = node(100);
    let _ = show(
        &mut root,
        "def holder(v)\n  receive()\n  throw(error(:keep, \"x\"))\nend\n\
         sup = supervisor(:one_for_one, [[holder, [[1, 2.5, \"s\", :k, nil, true, {a: [1, {b: 2}]}, -7]]]], 0)\n\
         send(nth(0, children(sup)), [:msg, 1.0e300, \"line\\nbreak\"])\nm = monitor(sup)\nreceive()",
    );
    let original = &node.traces()[0];
    let back = trace_round_trip(original);
    assert_eq!(
        format!("{:?}", back.code.bindings),
        format!("{:?}", original.code.bindings)
    );
    assert_eq!(back.code.defs, original.code.defs, "forms, spans included");
    assert_eq!(
        format!("{:?}", back.tape.iter().map(|e| e.outcome.clone()).collect::<Vec<_>>()),
        format!("{:?}", original.tape.iter().map(|e| e.outcome.clone()).collect::<Vec<_>>())
    );
    let mut wrong = original.to_json();
    wrong["version"] = serde_json::json!(99);
    assert!(Trace::from_json(&wrong).unwrap_err().contains("version 99"));
}
