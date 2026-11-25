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

const MAP_CRASH: &str = "\
def poisoned()
  receive()
  raise(:poison, \"bad message\", {data: {a: 1, b: 2, c: 3, d: 4, e: 5}})
end
sup = supervisor(:one_for_one, [poisoned], 0)
c = nth(0, children(sup))
m = monitor(sup)
send(c, :bad)
receive()
";

const MAP_KILL: &str = "\
def worker()
  receive()
end
sup = supervisor(:one_for_one, [worker], 0)
c = nth(0, children(sup))
m = monitor(sup)
exit(c, {a: 1, b: 2, c: 3, d: 4, e: 5})
receive()
";

fn trace_round_trip(t: &Trace) -> Trace {
    let text = serde_json::to_string(&t.to_json()).expect("serialize");
    Trace::parse(&text).expect("parse")
}

fn first_traces_of_fresh_runs(program: &str) -> Vec<Trace> {
    (0..8)
        .map(|_| {
            let (mut root, node) = node(100);
            let _ = show(&mut root, program);
            node.traces().into_iter().next().expect("a kept trace")
        })
        .collect()
}

fn assert_one_exit_text_in_key_order(traces: &[Trace]) {
    let names: std::collections::BTreeSet<String> = traces.iter().map(Trace::crash_hash).collect();
    let texts: std::collections::BTreeSet<String> = traces
        .iter()
        .map(|t| trace_round_trip(t).reason_text)
        .collect();
    assert_eq!(texts.len(), 1, "one exit text: {texts:#?}");
    assert_eq!(names.len(), 1, "one crash name: {names:#?}");
    let text = texts.into_iter().next().unwrap_or_default();
    assert!(
        text.contains("{:a 1, :b 2, :c 3, :d 4, :e 5}"),
        "the map's pairs follow map_entries' key order: {text}"
    );
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
    assert!(
        out.contains("gave_up"),
        "the fine schedule must crash: {out}"
    );
    let traces = fine.traces();
    assert_eq!(traces.len(), 1);
    let trace = trace_round_trip(&traces[0]);
    assert_eq!(trace.reason_kind, "crashed");
    assert!(trace.reason_text.contains("b arrived before a"));
    assert_eq!(
        trace.tape.len(),
        1,
        "the consumer received one message: {:?}",
        trace.tape
    );
    assert!(
        !trace.schedule.is_empty(),
        "the interleaving record rides along"
    );

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
    assert!(
        r.diverged.is_some(),
        "it asks for a second message the tape does not hold: {r:?}"
    );
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
    assert_eq!(
        calls,
        ["now_ms", "write_file", "getenv"],
        "every host read, in order"
    );
    assert!(marker.exists(), "the live run did write");

    std::fs::remove_file(&marker).expect("rm");
    unsafe { std::env::set_var("BLUE_REPLAY_PROBE", "changed since") };
    let r = replay(&trace, blue_lang_runtime::interpreter_hostless());
    assert!(
        r.reproduced,
        "the replay saw the recorded environment, not today's: {r:?}"
    );
    assert!(r.text.contains("probe=recorded"), "{r:?}");
    assert!(
        !marker.exists(),
        "the replay wrote nothing: write_file read its result off the tape"
    );
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
    let state = trace
        .code
        .bindings
        .iter()
        .find(|(n, _)| &**n == "%state")
        .map(|(_, v)| v.to_string());
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
        format!(
            "{:?}",
            back.tape
                .iter()
                .map(|e| e.outcome.clone())
                .collect::<Vec<_>>()
        ),
        format!(
            "{:?}",
            original
                .tape
                .iter()
                .map(|e| e.outcome.clone())
                .collect::<Vec<_>>()
        )
    );
    let mut wrong = original.to_json();
    wrong["version"] = serde_json::json!(99);
    assert!(Trace::from_json(&wrong).unwrap_err().contains("version 99"));
}

fn one_map_built(rotation: usize) -> tatara_lisp_eval::Value {
    use tatara_lisp_eval::{MapKey, Value};
    let inner = Value::map([
        (MapKey::Keyword(Arc::from("y")), Value::Int(2)),
        (MapKey::Keyword(Arc::from("x")), Value::Int(1)),
        (MapKey::Keyword(Arc::from("z")), Value::Int(3)),
    ]);
    let pairs: Vec<(MapKey, Value)> = vec![
        (MapKey::Keyword(Arc::from("rate")), Value::Int(48_000)),
        (MapKey::Keyword(Arc::from("channels")), Value::Int(2)),
        (MapKey::Str(Arc::from("s")), Value::Str(Arc::from("t"))),
        (MapKey::Int(10), Value::Int(10)),
        (MapKey::Int(9), Value::Float(9.5)),
        (MapKey::Nil, Value::Nil),
        (MapKey::Bool(true), Value::Bool(false)),
        (
            MapKey::Float(1.5f64.to_bits()),
            Value::Keyword(Arc::from("f")),
        ),
        (
            MapKey::Symbol(Arc::from("sym")),
            Value::list([inner.clone()]),
        ),
        (MapKey::Keyword(Arc::from("inner")), inner),
    ];
    let n = pairs.len();
    Value::map((0..n).map(|i| pairs[(i * 3 + rotation) % n].clone()))
}

#[test]
fn a_map_has_one_trace_text_however_it_was_built() {
    use blue_lang_proc::trace::{account_hash, tape_hash, value_to_json, TapeEntry};
    use tatara_lisp_eval::{ErrorObj, MapKey, Value};
    let mut texts = std::collections::BTreeSet::new();
    let mut tapes = std::collections::BTreeSet::new();
    let mut accounts = std::collections::BTreeSet::new();
    for rotation in 0..16 {
        let m = one_map_built(rotation);
        let raised = Value::Error(Arc::new(ErrorObj {
            tag: Arc::from("poison"),
            message: Arc::from("bad"),
            data: vec![(Value::Keyword(Arc::from("data")), m.clone())],
        }));
        let nested = Value::list([
            m.clone(),
            Value::map([(MapKey::Keyword(Arc::from("again")), m.clone())]),
            raised,
        ]);
        texts.insert(value_to_json(&nested).to_string());
        tapes.insert(tape_hash(&[TapeEntry {
            call: "flash_stats".to_string(),
            outcome: Ok(m.clone()),
            fatal: None,
            at: None,
        }]));
        accounts.insert(account_hash(Some(&[m.clone(), m]), 3));
    }
    assert_eq!(texts.len(), 1, "{texts:#?}");
    assert_eq!(tapes.len(), 1, "{tapes:#?}");
    assert_eq!(accounts.len(), 1, "{accounts:#?}");
    let text = texts.into_iter().next().unwrap_or_default();
    let keys: Vec<&str> = [
        "null",
        "{\"bool\":true}",
        "{\"float\":1.5}",
        "{\"int\":9}",
        "{\"int\":10}",
        "{\"str\":\"s\"}",
        "{\"sym\":\"sym\"}",
        "{\"kw\":\"channels\"}",
        "{\"kw\":\"inner\"}",
        "{\"kw\":\"rate\"}",
    ]
    .into_iter()
    .collect();
    let at: Vec<usize> = keys
        .iter()
        .map(|k| text.find(&format!("[{k},")).unwrap_or(usize::MAX))
        .collect();
    assert!(
        at.windows(2).all(|w| w[0] < w[1]),
        "the pairs follow map_entries' key order: {at:?} in {text}"
    );
}

#[test]
#[ignore = "G32: a crash's exit text is tatara-lisp-eval's Display, which walks a map in hash order in 0.4.26; the mark comes off with the bump to tatara-lisp 6011c03 (docs/ROADMAP.md, placement parity)"]
fn a_crash_whose_error_holds_a_map_has_one_name_and_reproduces() {
    let traces = first_traces_of_fresh_runs(MAP_CRASH);
    assert_one_exit_text_in_key_order(&traces);
    let reproduced: Vec<bool> = traces
        .iter()
        .map(|t| {
            replay(
                &trace_round_trip(t),
                blue_lang_runtime::interpreter_hostless(),
            )
            .reproduced
        })
        .collect();
    assert!(
        reproduced.iter().all(|r| *r),
        "every replay reproduces: {reproduced:?}"
    );
}

#[test]
#[ignore = "G32: a killed process's exit text is tatara-lisp-eval's Display of its exit reason, which walks a map in hash order in 0.4.26; the mark comes off with the bump to tatara-lisp 6011c03 (docs/ROADMAP.md, placement parity)"]
fn a_process_killed_with_a_map_has_one_exit_text_and_one_name() {
    assert_one_exit_text_in_key_order(&first_traces_of_fresh_runs(MAP_KILL));
}
