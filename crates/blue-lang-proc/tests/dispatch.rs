mod support;

use std::sync::{Arc, Mutex};

use blue_lang_proc::{ClockKind, HostIo, NodeConfig, Receipt};
use blue_lang_runtime::Hold;
use support::{configure, show};

const SERVER: &str = "def spin(k)\n  if k == 0\n    0\n  else\n    spin(k - 1)\n  end\nend\n\
def h(m, n)\n  if list?(m)\n    send(first(m), n)\n    n\n  else\n    if m == 0\n      spin(5000)\n      n + 1000\n    else\n      n + m\n    end\n  end\nend\n";

fn node(app: Option<usize>) -> (tatara_lisp_eval::Interpreter<()>, Arc<blue_lang_proc::Node>) {
    let mut config = NodeConfig::new(Arc::new(blue_lang_runtime::interpreter_hostless));
    config.budget.quantum = Some(100);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    config.dispatch_steps = app;
    configure(config)
}

fn supervised(spec: &str) -> String {
    format!(
        "{SERVER}sup = supervisor(:one_for_one, [{spec}])\ns = nth(0, children(sup))\n\
         send(s, 1)\nsend(s, 2)\nmonitor(s)\nsend(s, 0)\ndown = receive(:_, 5000)\n\
         send(s, 5)\nsend(s, [self()])\n[nth(3, down), receive(:_, 5000)]"
    )
}

fn refusal(limit: usize) -> String {
    format!("((:runaway \"execution budget exhausted: steps per dispatch (limit {limit})\") 8)")
}

#[test]
fn a_bounded_server_refuses_a_long_message_and_answers_the_next_from_the_state_before_it() {
    let (mut root, _node) = node(None);
    let out = show(
        &mut root,
        &supervised("[:server, h, 0, {dispatch_steps: 2000}]"),
    );
    assert_eq!(out, refusal(2000), "1 + 2, then 5, never the 1000: {out}");
}

#[test]
fn a_spawned_server_with_a_dispatch_bound_exits_a_runaway_its_monitor_sees() {
    let (mut root, _node) = node(None);
    let out = show(
        &mut root,
        &format!(
            "{SERVER}s = spawn_server(h, 0, {{dispatch_steps: 2000}})\nmonitor(s)\nsend(s, 1)\nsend(s, 0)\nnth(3, receive(:_, 5000))"
        ),
    );
    assert_eq!(
        out,
        "(:runaway \"execution budget exhausted: steps per dispatch (limit 2000)\")"
    );
}

#[test]
fn the_nodes_bound_and_the_spawn_option_meet_to_the_lesser() {
    for (app, opt, limit) in [
        (Some(3000), Some(2000), 2000),
        (Some(2000), Some(3000), 2000),
        (Some(2500), None, 2500),
        (None, Some(2400), 2400),
    ] {
        let (mut root, _node) = node(app);
        let spec = opt.map_or_else(
            || "[:server, h, 0]".to_string(),
            |n| format!("[:server, h, 0, {{dispatch_steps: {n}}}]"),
        );
        let out = show(&mut root, &supervised(&spec));
        assert_eq!(out, refusal(limit), "app {app:?}, spawn {opt:?}: {out}");
    }
}

#[test]
fn a_handler_within_its_bound_is_never_refused() {
    let (mut root, _node) = node(Some(1_000_000));
    let out = show(
        &mut root,
        &format!(
            "{SERVER}s = spawn_server(h, 0, {{dispatch_steps: 500000}})\nsend(s, 1)\nsend(s, 0)\nsend(s, 2)\nsend(s, [self()])\nreceive(:_, 5000)"
        ),
    );
    assert_eq!(out, "1003");
}

#[test]
fn without_a_bound_a_server_handles_the_long_message_as_before() {
    let (mut root, _node) = node(None);
    let out = show(
        &mut root,
        &format!(
            "{SERVER}s = spawn_server(h, 0)\nsend(s, 1)\nsend(s, 2)\nsend(s, 0)\nsend(s, 5)\nsend(s, [self()])\nreceive(:_, 5000)"
        ),
    );
    assert_eq!(out, "1008");
    let (mut root, _node) = node(None);
    let out = show(
        &mut root,
        &format!(
            "{SERVER}sup = supervisor(:one_for_one, [[:server, h, 0]])\ns = nth(0, children(sup))\nsend(s, 1)\nsend(s, 0)\nsend(s, [self()])\nreceive(:_, 5000)"
        ),
    );
    assert_eq!(out, "1001");
}

type Seen = Arc<Mutex<Vec<Receipt>>>;

fn held(app: Option<usize>) -> (tatara_lisp_eval::Interpreter<()>, Seen) {
    held_in(app, 100)
}

fn held_in(app: Option<usize>, quantum: usize) -> (tatara_lisp_eval::Interpreter<()>, Seen) {
    let hold = Hold::from(blue_lang_runtime::session::frame_granting(&[]));
    let seen: Seen = Arc::default();
    let s = Arc::clone(&seen);
    let mut config = NodeConfig::new(Arc::new(blue_lang_runtime::interpreter_hostless));
    config.budget.quantum = Some(quantum);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    config.frame = Some(hold.frame());
    config.host_io = HostIo::new();
    config.receipts = Some(Arc::new(move |r: &Receipt| {
        s.lock().expect("lock").push(r.clone());
    }));
    config.state_root = Some(blue_lang_runtime::json::state_root);
    config.count_steps = true;
    config.dispatch_steps = app;
    let (root, _node) = configure(config);
    (root, seen)
}

fn root_of(n: i64) -> String {
    blue_lang_runtime::json::state_root(&tatara_lisp_eval::Value::Int(n))
}

#[test]
fn a_refused_incarnations_receipt_ends_on_the_state_before_the_refused_message() {
    let (mut root, seen) = held(Some(2000));
    let out = show(&mut root, &supervised("[:server, h, 0]"));
    assert_eq!(out, refusal(2000));
    let seen = seen.lock().expect("lock").clone();
    let refused = seen.first().expect("the refused incarnation's receipt");
    assert_eq!(refused.exit_kind, "runaway");
    assert_eq!(
        refused.exit_text,
        "execution budget exhausted: steps per dispatch (limit 2000)"
    );
    let roots = refused.roots.as_ref().expect("a server's roots");
    assert_eq!(roots.input, root_of(0));
    assert_eq!(roots.output, root_of(3), "1 + 2, never the refused 1000");
    assert!(
        refused.steps.is_some_and(|n| n > 2000),
        "{:?}",
        refused.steps
    );
}

#[test]
fn a_handler_that_returns_past_its_bound_within_one_slice_is_refused_at_its_boundary() {
    let (mut root, seen) = held_in(Some(2000), 1_000_000);
    let out = show(&mut root, &supervised("[:server, h, 0]"));
    assert_eq!(out, refusal(2000));
    let seen = seen.lock().expect("lock").clone();
    let refused = seen.first().expect("the refused incarnation's receipt");
    assert_eq!(refused.exit_kind, "runaway");
    assert_eq!(
        refused.roots.as_ref().map(|r| r.output.clone()),
        Some(root_of(3)),
        "the handler returned 1003 before the boundary saw its count"
    );
}

fn spent(app: Option<usize>, sends: &[i64]) -> u64 {
    let (mut root, seen) = held(app);
    let lines: String = sends.iter().map(|n| format!("send(s, {n})\n")).collect();
    let out = show(
        &mut root,
        &format!(
            "{SERVER}s = spawn_server(h, 0)\n{lines}send(s, [self()])\nn = receive(:_, 5000)\nmonitor(s)\nexit(s, :kill)\nreceive(:_, 5000)\nn"
        ),
    );
    assert_eq!(out, sends.iter().sum::<i64>().to_string());
    let seen = seen.lock().expect("lock").clone();
    assert_eq!(seen.len(), 1, "{seen:?}");
    seen[0].steps.expect("counted")
}

#[test]
fn a_receipt_counts_the_steps_an_incarnation_spent_alike_for_alike_runs() {
    let once = spent(None, &[1, 2, 3]);
    assert_eq!(spent(None, &[1, 2, 3]), once, "an identical run");
    assert!(
        spent(None, &[1, 2, 3, 4, 5, 6]) > once,
        "three more messages"
    );
}

#[test]
fn without_a_bound_a_server_spends_no_steps_opening_each_dispatch() {
    let sends = [1, 2, 3, 4, 5, 6];
    let free = spent(None, &sends);
    let bounded = spent(Some(1_000_000), &sends);
    assert!(
        free < bounded,
        "a bound parks at each boundary, its absence never: {free} against {bounded}"
    );
}

#[test]
fn a_dispatch_bound_that_is_not_a_positive_integer_is_refused_by_name() {
    for (opt, says) in [
        ("0", "a positive integer"),
        ("-4", "a positive integer"),
        ("1.5", "a positive integer"),
        (":many", "a positive integer"),
    ] {
        let (mut root, _node) = node(None);
        let out = show(
            &mut root,
            &format!(
                "{SERVER}begin\n  spawn_server(h, 0, {{dispatch_steps: {opt}}})\nrescue :bad_option as e\n  e.message\nend"
            ),
        );
        assert!(out.contains(says), "{opt}: {out}");
    }
    let (mut root, _node) = node(None);
    let out = show(
        &mut root,
        &format!(
            "{SERVER}def w()\n  1\nend\nbegin\n  spawn(w, [], {{dispatch_steps: 10}})\nrescue :bad_option as e\n  e.message\nend"
        ),
    );
    assert!(out.contains("spawn takes scheduling:"), "{out}");
}
