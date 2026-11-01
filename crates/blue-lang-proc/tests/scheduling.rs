mod support;

use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use blue_lang_proc::scheduling::{self, IdleLane, Priority, Scheduling};
use blue_lang_proc::trace::SliceRecord;
use blue_lang_proc::{replay, ClockKind, NodeConfig};
use support::{configure, node_with, show};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

fn probed(mut interp: Interpreter<()>) -> Interpreter<()> {
    interp.register_fn(
        "os_priority",
        Arity::Exact(0),
        |_: &[Value], _: &mut (), span| {
            let p: Priority = scheduling::current()
                .map_err(|why| EvalError::native_fn("os_priority", why, span))?;
            Ok(Value::list([
                Value::Int(i64::from(p.value)),
                Value::Bool(p.lowest),
            ]))
        },
    );
    interp
}

fn probing() -> (Interpreter<()>, Arc<blue_lang_proc::Node>) {
    let (root, node) = node_with(
        50,
        Arc::new(|| probed(blue_lang_runtime::interpreter_hostless())),
    );
    (probed(root), node)
}

const REPORTER: &str = "\
def reporter(msg, n)
  send(msg, os_priority())
  n + 1
end
";

#[test]
fn an_idle_process_reports_the_lowest_priority_the_os_gives_it_and_a_normal_one_the_spawners() {
    let (mut root, _) = probing();
    let out = show(
        &mut root,
        &format!(
            "{REPORTER}\
             idle = spawn_server(reporter, 0, {{scheduling: :idle}})\n\
             normal = spawn_server(reporter, 0, {{scheduling: :normal}})\n\
             plain = spawn_server(reporter, 0)\n\
             send(idle, self())\nfrom_idle = receive()\n\
             send(normal, self())\nfrom_normal = receive()\n\
             send(plain, self())\nfrom_plain = receive()\n\
             [os_priority(), from_idle, from_normal, from_plain]"
        ),
    );
    let root = scheduling::current().expect("the root reads its priority");
    let rendered = |p: Priority| format!("({} {})", p.value, if p.lowest { "#t" } else { "#f" });
    let lowest = if cfg!(target_vendor = "apple") {
        "(1 #t)".to_string()
    } else {
        "(19 #t)".to_string()
    };
    assert_eq!(
        out,
        format!(
            "({} {lowest} {} {})",
            rendered(root),
            rendered(root),
            rendered(root)
        ),
        "an :idle slice runs at the OS's lowest priority; :normal and no option run as the spawner does"
    );
    if !root.lowest {
        assert_ne!(
            rendered(root),
            lowest,
            "the spawner is not at the lowest priority, so the idle reading is the class's doing"
        );
    }
}

#[test]
fn an_idle_process_keeps_the_answers_a_normal_one_gives() {
    let (mut root, _) = probing();
    let program = |class: &str| {
        format!(
            "def sum(msg, n)\n  if msg == :get\n    n\n  else\n    n + msg\n  end\nend\n\
             def ask(msg, n)\n  send(nth(1, msg), sum(nth(0, msg), n))\n  sum(nth(0, msg), n)\nend\n\
             s = spawn_server(ask, 0, {{scheduling: {class}}})\n\
             map(fn(i) send(s, [i, self()])\nreceive() end, range(1, 200))"
        )
    };
    let idle = show(&mut root, &program(":idle"));
    let normal = show(&mut root, &program(":normal"));
    assert!(!idle.starts_with("error"), "{idle}");
    assert_eq!(idle, normal);
}

#[test]
fn the_realtime_class_is_refused_by_name_and_spawns_nothing() {
    let (mut root, node) = probing();
    let before = node.process_count();
    let out = show(
        &mut root,
        "def h(msg, n)\n  n\nend\n\
         begin\n  spawn_server(h, 0, {scheduling: :realtime})\nrescue :permission_denied as e\n  [e.kind, contains?(e.message, \":realtime\"), contains?(e.message, \"privileged\")]\nend",
    );
    assert_eq!(out, "(:permission_denied #t #t)");
    assert_eq!(
        node.process_count(),
        before,
        "a refused spawn starts nothing"
    );
    for word in ["spawn", "spawn_link"] {
        let out = show(
            &mut root,
            &format!(
                "def w()\n  1\nend\n\
                 begin\n  {word}(w, [], {{scheduling: :realtime}})\nrescue :permission_denied as e\n  e.kind\nend"
            ),
        );
        assert_eq!(out, ":permission_denied", "{word}");
    }
}

#[test]
fn a_class_or_option_blue_does_not_know_is_refused_by_name() {
    let (mut root, _) = probing();
    let out = show(
        &mut root,
        "def h(msg, n)\n  n\nend\n\
         a = begin\n  spawn_server(h, 0, {scheduling: :fast})\nrescue :bad_option as e\n  [e.kind, contains?(e.message, \":fast\")]\nend\n\
         b = begin\n  spawn_server(h, 0, {priority: :idle})\nrescue :bad_option as e\n  [e.kind, contains?(e.message, \"priority\")]\nend\n\
         c = begin\n  spawn_server(h, 0, :idle)\nrescue :bad_option as e\n  e.kind\nend\n\
         [a, b, c]",
    );
    assert_eq!(out, "((:bad_option #t) (:bad_option #t) :bad_option)");
}

#[test]
fn every_class_has_a_spelling_and_the_privileged_one_has_none() {
    for class in Scheduling::ALL {
        assert_eq!(Scheduling::named(class.label()), Ok(class));
    }
    assert_eq!(
        Scheduling::named("realtime"),
        Err(scheduling::Refusal::Privileged)
    );
    assert_eq!(Scheduling::default(), Scheduling::Normal);
}

fn stalled(stall: Duration) -> Interpreter<()> {
    let mut interp = blue_lang_runtime::interpreter_hostless();
    interp.register_fn(
        "wait_for_core",
        Arity::Exact(0),
        move |_: &[Value], _: &mut (), _span| {
            std::thread::sleep(stall);
            Ok(Value::Nil)
        },
    );
    interp
}

fn stalling(lane: IdleLane, stall: Duration) -> (Interpreter<()>, Arc<blue_lang_proc::Node>) {
    let mut config = NodeConfig::new(Arc::new(move || stalled(stall)));
    config.budget.quantum = Some(10);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    config.idle_lane = lane;
    configure(config)
}

const SPINNER: &str = "\
def spin(n)
  wait_for_core()
  spin(n + 1)
end
def echo(msg, n)
  send(msg, n)
  n + 1
end
";

fn answers_beside_a_spinner(
    lane: IdleLane,
    stall: Duration,
    asks: usize,
) -> (Vec<Duration>, String) {
    let (mut root, _node) = stalling(lane, stall);
    let started = show(
        &mut root,
        &format!(
            "{SPINNER}spinner = spawn(spin, [0], {{scheduling: :idle}})\ne = spawn_server(echo, 0)\n:started"
        ),
    );
    assert_eq!(started, ":started");
    let mut took = Vec::new();
    let mut answers = Vec::new();
    for _ in 0..asks {
        let t = Instant::now();
        answers.push(show(&mut root, "send(e, self())\nreceive()"));
        took.push(t.elapsed());
    }
    (took, answers.join(" "))
}

#[test]
fn a_normal_process_keeps_answering_while_an_idle_one_waits_for_a_core() {
    let stall = Duration::from_millis(250);
    let (took, answers) = answers_beside_a_spinner(IdleLane::Apart, stall, 8);
    assert_eq!(answers, "0 1 2 3 4 5 6 7");
    let slowest = took.iter().max().copied().unwrap_or_default();
    assert!(
        slowest < stall,
        "an idle slice runs apart from the node, so no answer waits the {stall:?} its slice waits: the slowest took {slowest:?} ({took:?})"
    );
    let (took, held) = answers_beside_a_spinner(IdleLane::Held, stall, 3);
    assert_eq!(held, "0 1 2");
    let quickest = took.iter().min().copied().unwrap_or_default();
    assert!(
        quickest >= stall,
        "a held lane is the node waiting for the idle slice, so every answer comes after one: the quickest took {quickest:?} ({took:?})"
    );
}

#[test]
fn an_idle_process_that_ran_beside_the_node_replays_its_crash_from_its_tape() {
    let stall = Duration::from_millis(20);
    let (mut root, node) = stalling(IdleLane::Apart, stall);
    let out = show(
        &mut root,
        "\
def picky(parent)
  first = receive()
  wait_for_core()
  second = receive()
  send(parent, [:got, first, second])
  if second == :b
    raise(:order, \"b came second\")
  end
  :fine
end
def feeder(target, tag)
  send(target, tag)
end
p = spawn(picky, [self()], {scheduling: :idle})
m = monitor(p)
send(p, :a)
spawn(feeder, [p, :b])
got = receive([:got, :_, :_])
down = receive([:down, m, :_, :_])
[got, nth(0, nth(3, down))]",
    );
    assert_eq!(out, "((:got :a :b) :crashed)");
    let traces = node.traces();
    assert_eq!(traces.len(), 1, "{traces:?}");
    let trace = &traces[0];
    assert_eq!(trace.pid, 1);
    let calls: Vec<&str> = trace.tape.iter().map(|e| e.call.as_str()).collect();
    assert_eq!(
        calls,
        ["receive", "receive", "send"],
        "every value that reached the idle process while it ran apart is on its own tape"
    );
    let r = replay(trace, stalled(Duration::ZERO));
    assert!(r.reproduced, "{r:?}");
    assert_eq!(r.consumed, trace.tape.len());
}

fn schedule_of(lane: IdleLane, class: &str) -> Vec<SliceRecord> {
    let (mut root, node) = stalling(lane, Duration::ZERO);
    let out = show(
        &mut root,
        &format!(
            "\
def spin(n)
  if n == 0
    0
  else
    spin(n - 1)
  end
end
def worker(target, n)
  spin(n)
  send(target, n)
end
def crasher(parent)
  a = receive()
  b = receive()
  raise(:done, \"#{{a}} then #{{b}}\")
end
c = spawn(crasher, [self()], {{scheduling: {class}}})
m = monitor(c)
spawn(worker, [c, 40])
spawn(worker, [c, 7])
nth(3, receive([:down, m, :_, :_]))"
        ),
    );
    assert!(out.contains("7 then 40"), "{out}");
    let traces = node.traces();
    assert_eq!(traces.len(), 1, "{traces:?}");
    traces[0].schedule.clone()
}

#[test]
fn a_held_lane_interleaves_as_a_normal_process_does_and_apart_changes_nothing_without_an_idle_process(
) {
    let held = schedule_of(IdleLane::Held, ":idle");
    assert!(held.iter().any(|s| s.pid == 1), "{held:?}");
    for _ in 0..3 {
        assert_eq!(
            schedule_of(IdleLane::Held, ":idle"),
            held,
            "a held lane replays its interleaving"
        );
    }
    assert_eq!(
        schedule_of(IdleLane::Held, ":normal"),
        held,
        "and it is the interleaving the same process has at :normal"
    );
    assert_eq!(
        schedule_of(IdleLane::Apart, ":normal"),
        held,
        "a node with no idle process interleaves alike under either lane"
    );
}

#[test]
fn every_lane_has_a_label_and_apart_is_the_default() {
    let labels: Vec<&str> = IdleLane::ALL.iter().map(|l| l.label()).collect();
    assert_eq!(labels, ["apart", "held"]);
    assert_eq!(IdleLane::default(), IdleLane::Apart);
    assert_eq!(
        NodeConfig::new(Arc::new(blue_lang_runtime::interpreter_hostless)).idle_lane,
        IdleLane::Apart
    );
}

#[test]
fn an_idle_server_running_apart_is_held_to_its_dispatch_bound() {
    let (mut root, _node) = stalling(IdleLane::Apart, Duration::ZERO);
    let out = show(
        &mut root,
        "def spin(k)\n  if k == 0\n    0\n  else\n    spin(k - 1)\n  end\nend\n\
         def long(m, n)\n  if m == 0\n    spin(5000)\n    n + 1000\n  else\n    n + m\n  end\nend\n\
         s = spawn_server(long, 0, {scheduling: :idle, dispatch_steps: 2000})\n\
         monitor(s)\nsend(s, 1)\nsend(s, 0)\nnth(3, receive(:_, 5000))",
    );
    assert_eq!(
        out,
        "(:runaway \"execution budget exhausted: steps per dispatch (limit 2000)\")"
    );
}

#[test]
fn an_idle_process_running_apart_touches_nothing_the_program_sees_until_it_waits_again() {
    let latch: Arc<(Mutex<(bool, bool)>, Condvar)> = Arc::default();
    let l = Arc::clone(&latch);
    let mut config = NodeConfig::new(Arc::new(move || {
        let mut interp = blue_lang_runtime::interpreter_hostless();
        let l = Arc::clone(&l);
        interp.register_fn(
            "hold",
            Arity::Exact(0),
            move |_: &[Value], _: &mut (), _span| {
                let (m, c) = &*l;
                let mut g = m.lock().expect("latch");
                while !g.0 {
                    g = c.wait(g).expect("latch");
                }
                g.1 = true;
                c.notify_all();
                Ok(Value::Nil)
            },
        );
        interp
    }));
    config.budget.quantum = Some(100_000);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    let (mut root, node) = configure(config);
    let first = show(
        &mut root,
        "def talker(parent)\n  receive()\n  send(parent, :one)\n  hold()\n  send(parent, :two)\nend\n\
         p = spawn(talker, [self()], {scheduling: :idle})\nsend(p, :go)\nreceive()",
    );
    assert_eq!(first, ":one");
    {
        let (m, c) = &*latch;
        let mut g = m.lock().expect("latch");
        g.0 = true;
        c.notify_all();
        let deadline = Instant::now() + Duration::from_secs(30);
        while !g.1 {
            let left = deadline.saturating_duration_since(Instant::now());
            assert!(!left.is_zero(), "the idle slice never came back from hold");
            g = c.wait_timeout(g, left).expect("latch").0;
        }
    }
    std::thread::sleep(Duration::from_millis(100));
    assert!(
        node.mailbox(blue_lang_proc::ROOT).is_empty(),
        "processes run while the program waits: the idle slice still out holds its next send until the program waits again"
    );
    assert_eq!(show(&mut root, "receive()"), ":two");
}
