mod support;

use std::sync::Arc;

use blue_lang_proc::image::{self, Arrivals, Image};
use blue_lang_proc::{install, replay, ClockKind, Node, NodeConfig, Trace};
use blue_lang_runtime::wire::{host_clock, provide_loopback, LoopbackNet, CARRIER};
use serde_json::Value as Json;
use support::{run, show};
use tatara_lisp_eval::{Interpreter, Value};

fn moving(net: &Arc<LoopbackNet>) -> (Interpreter<()>, Arc<Node>) {
    moving_under(net, None)
}

fn moving_under(net: &Arc<LoopbackNet>, dispatch: Option<usize>) -> (Interpreter<()>, Arc<Node>) {
    moving_with(
        net,
        dispatch,
        Arc::new(blue_lang_runtime::interpreter_hostless),
    )
}

fn moving_with_wired_children(net: &Arc<LoopbackNet>) -> (Interpreter<()>, Arc<Node>) {
    let wired = Arc::clone(net);
    moving_with(
        net,
        None,
        Arc::new(move || {
            let mut child = blue_lang_runtime::interpreter_hostless();
            provide_loopback(
                &mut child,
                String::from,
                blue_lang_waku::Channel::Tide,
                &wired,
                host_clock(),
            );
            child
        }),
    )
}

fn moving_with(
    net: &Arc<LoopbackNet>,
    dispatch: Option<usize>,
    child: Arc<dyn Fn() -> Interpreter<()> + Send + Sync>,
) -> (Interpreter<()>, Arc<Node>) {
    let mut config = NodeConfig::new(child);
    config.budget.quantum = Some(50);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    config.carrier = Some(CARRIER);
    config.dispatch_steps = dispatch;
    let node = Node::new(config);
    let mut root = blue_lang_runtime::interpreter_hostless();
    install(&mut root, node.clone());
    provide_loopback(
        &mut root,
        String::from,
        blue_lang_waku::Channel::Tide,
        net,
        host_clock(),
    );
    (root, node)
}

const COUNTER: &str = "\
def counter(msg, seen)
  if nth(0, msg) == :inc
    append(seen, [nth(1, msg)])
  else
    send(nth(1, msg), [:seen, seen])
    seen
  end
end
";

const WITNESS: &str = "\
def witness(msg, seen)
  if nth(0, msg) == :inc
    append(seen, [[nth(1, msg), self()]])
  else
    send(nth(1, msg), [:seen, seen])
    seen
  end
end
";

#[test]
fn a_counter_evicted_mid_stream_keeps_its_count_and_handles_every_message_once() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, node_a) = moving(&net);
    let (mut b, node_b) = moving(&net);
    show(
        &mut b,
        "w = tide_open(\"127.0.0.1:7002\")\n\
         def resident()\n  receive()\nend\n\
         spawn(resident)",
    );
    let left = show(
        &mut a,
        &format!(
            "{WITNESS}\
             w = tide_open(\"127.0.0.1:7001\")\n\
             s = spawn_server(witness, [])\n\
             send(s, [:inc, 1])\nsend(s, [:inc, 2])\nsend(s, [:inc, 3])\n\
             send(s, [:get, self()])\nbefore = receive()\n\
             send(s, [:inc, 4])\nsend(s, [:inc, 5])\n\
             moved = evict(s, w, \"127.0.0.1:7002\")\n\
             send(s, [:inc, 99])\n\
             [before, moved.frames > 0, starts_with?(moved.image, \"b3:\"), tide_release(w, 1000000, 0) == moved.bytes, alive?(s)]"
        ),
    );
    assert_eq!(left, "((:seen ((1 1) (2 1) (3 1))) #t #t #t #f)");
    assert_eq!(node_a.process_count(), 0, "the server left node a");
    let arrived = show(
        &mut b,
        "p = accept(w, 0)\n\
         send(p, [:inc, 6])\nsend(p, [:inc, 7])\n\
         send(p, [:get, self()])\n\
         [receive(), accept(w, 0)]",
    );
    assert_eq!(
        arrived, "((:seen ((1 1) (2 1) (3 1) (4 2) (5 2) (6 2) (7 2))) ())",
        "node b never defined witness: the code came with it; 1 to 3 were handled on node a as pid 1, 4 and 5 were queued before the move and handled on node b as pid 2, 6 and 7 after; 99 went to the pid it left"
    );
    assert_eq!(node_b.process_count(), 2);
}

#[test]
fn a_server_evicted_while_it_still_runs_stops_at_its_next_boundary_and_handles_nothing_more_here() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, _) = moving(&net);
    show(
        &mut b,
        "w = tide_open(\"127.0.0.1:7062\")\n\
         def resident()\n  receive()\nend\n\
         spawn(resident)",
    );
    show(
        &mut a,
        &format!(
            "{WITNESS}\
             w = tide_open(\"127.0.0.1:7061\")\n\
             s = spawn_server(witness, [])\n\
             send(s, [:inc, 1])\nsend(s, [:inc, 2])\nsend(s, [:inc, 3])\n\
             evict(s, w, \"127.0.0.1:7062\")\n\
             tide_release(w, 1000000, 0)"
        ),
    );
    let out = show(
        &mut b,
        "p = accept(w, 0)\nsend(p, [:get, self()])\nreceive()",
    );
    assert_eq!(out, "(:seen ((1 2) (2 2) (3 2)))");
}

#[test]
fn an_image_the_ring_cannot_hold_leaves_the_server_running_here_with_its_messages() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let out = show(
        &mut a,
        &format!(
            "{COUNTER}\
             w = tide_open(\"127.0.0.1:7011\", {{ring_frames: 1, ring_bytes: 1280}})\n\
             big = join(map(fn(i) \"x\" end, range(3000)), \"\")\n\
             s = spawn_server(counter, [big])\n\
             send(s, [:inc, 1])\n\
             refused = begin\n  evict(s, w, \"127.0.0.1:7012\")\nrescue e\n  contains?(e.message, \"do not fit the send ring\")\nend\n\
             send(s, [:get, self()])\n\
             r = receive()\n\
             [refused, length(nth(1, r)), nth(1, nth(1, r)), tide_stats(w).queued, alive?(s)]"
        ),
    );
    assert_eq!(out, "(#t 2 1 0 #t)");
}

#[test]
fn a_process_eviction_cannot_carry_is_refused_by_name() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let out = show(
        &mut a,
        &format!(
            "{COUNTER}\
             w = tide_open(\"127.0.0.1:7021\")\n\
             def why(f)\n  begin\n    f()\n    :moved\n  rescue e\n    e.message\n  end\nend\n\
             def idle_loop()\n  receive()\nend\n\
             def other_loop()\n  receive()\nend\n\
             migrated = spawn(idle_loop)\n\
             receive(:never, 10, :waited)\n\
             defmigrate(migrated, other_loop)\n\
             linked = spawn_server(counter, [])\nlink(linked)\n\
             linked_plain = spawn(idle_loop)\nlink(linked_plain)\n\
             sup = supervisor(:one_for_one, [idle_loop])\n\
             [contains?(why(fn() evict(self(), w, \"127.0.0.1:9\") end), \"process 0 is the program: the door runs it on its own evaluator, the tree-walker\"),\n\
              contains?(why(fn() evict(sup, w, \"127.0.0.1:9\") end), \"is a supervisor\"),\n\
              contains?(why(fn() evict(migrated, w, \"127.0.0.1:9\") end), \"cannot move: a migration replaced its code\"),\n\
              contains?(why(fn() evict(linked, w, \"127.0.0.1:9\") end), \"is linked to\"),\n\
              contains?(why(fn() evict(linked_plain, w, \"127.0.0.1:9\") end), \"is linked to\"),\n\
              contains?(why(fn() evict(4242, w, \"127.0.0.1:9\") end), \"no process\"),\n\
              alive?(migrated)]"
        ),
    );
    assert_eq!(out, "(#t #t #t #t #t #t #t)");
}

const TALLY: &str = "\
def take(parent)
  m = receive()
  send(parent, [:took, m, self()])
  m
end
def tally(parent)
  count = 0
  seen = []
  peek = () -> [count, seen]
  twice = () -> count * 2
  m = take(parent)
  count = count + m
  seen = append(seen, [m])
  m = take(parent)
  count = count + m
  seen = append(seen, [m])
  m = take(parent)
  count = count + m
  seen = append(seen, [m])
  m = take(parent)
  count = count + m
  seen = append(seen, [m])
  send(receive(), [peek(), twice(), count])
end
";

#[test]
fn a_plain_process_evicted_after_two_messages_keeps_its_frames_and_shared_cells_and_takes_each_message_once(
) {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, node_a) = moving(&net);
    let (mut b, node_b) = moving(&net);
    show(
        &mut b,
        "w = tide_open(\"127.0.0.1:7102\")\n\
         def resident()\n  receive()\nend\n\
         spawn(resident)",
    );
    let left = show(
        &mut a,
        &format!(
            "{TALLY}\
             w = tide_open(\"127.0.0.1:7101\")\n\
             p = spawn(tally, [self()])\n\
             send(p, 1)\nsend(p, 2)\n\
             first = receive([:took, :_, :_])\nsecond = receive([:took, :_, :_])\n\
             send(p, 3)\n\
             moved = evict(p, w, \"127.0.0.1:7102\")\n\
             send(p, 99)\n\
             [first, second, receive(:_, 0, :none), starts_with?(moved.image, \"b3:\"), tide_release(w, 1000000, 0) == moved.bytes, alive?(p)]"
        ),
    );
    assert_eq!(left, "((:took 1 1) (:took 2 1) :none #t #t #f)");
    assert_eq!(node_a.process_count(), 0, "the process left node a");
    let arrived = show(
        &mut b,
        "p = accept(w, 0)\n\
         third = receive([:took, :_, :_])\n\
         send(p, 4)\n\
         fourth = receive([:took, :_, :_])\n\
         send(p, self())\n\
         [third, fourth, receive(), receive(:_, 0, :none), accept(w, 0)]",
    );
    assert_eq!(
        arrived, "((:took 3 2) (:took 4 2) ((10 (1 2 3 4)) 20 10) :none ())",
        "node b never defined tally or take: the code came with the frames; 1 and 2 were taken on node a as pid 1, 3 was queued before the move and 4 sent after, both taken on node b as pid 2; count and seen, captured by peek and twice, are one cell each on node b as on node a, so the closures see 10 and the four messages; 99 went to the pid it left"
    );
    assert_eq!(node_b.process_count(), 1, "only the resident is left");
}

#[test]
fn a_plain_process_moves_on_again_from_the_node_it_arrived_at() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, _) = moving(&net);
    let (mut c, _) = moving(&net);
    show(&mut c, "w = tide_open(\"127.0.0.1:7153\")");
    show(&mut b, "w = tide_open(\"127.0.0.1:7152\")");
    show(
        &mut a,
        &format!(
            "{TALLY}\
             w = tide_open(\"127.0.0.1:7151\")\n\
             p = spawn(tally, [self()])\n\
             send(p, 1)\nreceive([:took, :_, :_])\n\
             evict(p, w, \"127.0.0.1:7152\")\n\
             tide_release(w, 1000000, 0)"
        ),
    );
    let passed = show(
        &mut b,
        "p = accept(w, 0)\n\
         send(p, 2)\ntook = receive([:took, :_, :_])\n\
         evict(p, w, \"127.0.0.1:7153\")\n\
         tide_release(w, 1000000, 0)\n\
         took",
    );
    assert_eq!(passed, "(:took 2 1)");
    let out = show(
        &mut c,
        "p = accept(w, 0)\n\
         send(p, 3)\nsend(p, 4)\n\
         took = [receive([:took, :_, :_]), receive([:took, :_, :_])]\n\
         send(p, self())\n\
         [took, receive()]",
    );
    assert_eq!(
        out, "(((:took 3 1) (:took 4 1)) ((10 (1 2 3 4)) 20 10))",
        "the frames node b rebuilt name the same chunk its functions run in, so they park again there"
    );
}

#[test]
fn a_plain_process_evicted_while_it_still_runs_stops_at_its_next_receive_and_takes_nothing_more_here(
) {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, _) = moving(&net);
    show(&mut b, "w = tide_open(\"127.0.0.1:7112\")");
    let left = show(
        &mut a,
        &format!(
            "{TALLY}\
             w = tide_open(\"127.0.0.1:7111\")\n\
             p = spawn(tally, [self()])\n\
             send(p, 1)\nsend(p, 2)\nsend(p, 3)\n\
             evict(p, w, \"127.0.0.1:7112\")\n\
             tide_release(w, 1000000, 0)\n\
             receive(:_, 0, :none)"
        ),
    );
    assert_eq!(left, ":none", "nothing was taken on node a");
    let out = show(
        &mut b,
        "p = accept(w, 0)\n\
         took = [receive([:took, :_, :_]), receive([:took, :_, :_]), receive([:took, :_, :_])]\n\
         send(p, 4)\nreceive([:took, :_, :_])\n\
         send(p, self())\n\
         [took, receive()]",
    );
    assert_eq!(
        out,
        "(((:took 1 1) (:took 2 1) (:took 3 1)) ((10 (1 2 3 4)) 20 10))"
    );
}

#[test]
fn a_plain_process_holding_a_host_handle_is_refused_by_name_and_keeps_running_where_it_was() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving_with_wired_children(&net);
    let out = show(
        &mut a,
        "def holder(parent)\n  h = tide_open(\"127.0.0.1:7123\")\n  send(parent, :open)\n  m = receive()\n  send(parent, [:took, m, self(), tide_stats(h).queued])\nend\n\
         w = tide_open(\"127.0.0.1:7121\")\n\
         p = spawn(holder, [self()])\n\
         receive(:open)\n\
         refused = begin\n  evict(p, w, \"127.0.0.1:7122\")\n  :moved\nrescue e\n  e.message\nend\n\
         send(p, 5)\n\
         [contains?(refused, \"process 1 cannot move: it holds a host handle in stack slot \"), contains?(refused, \"which has no data form and does not cross a wire\"), receive([:took, :_, :_, :_]), tide_stats(w).queued, alive?(p)]",
    );
    assert_eq!(out, "(#t #t (:took 5 1 0) 0 #f)");
}

#[test]
fn an_arrival_holding_a_native_the_accepting_node_lacks_is_refused_by_name_and_admits_nothing() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving_with(
        &net,
        None,
        Arc::new(|| {
            let mut child = blue_lang_runtime::interpreter_hostless();
            child.register_fn(
                "only_here",
                tatara_lisp_eval::ffi::Arity::Exact(0),
                |_args: &[tatara_lisp_eval::Value], _host: &mut (), _span| {
                    Ok(tatara_lisp_eval::Value::Int(1))
                },
            );
            child
        }),
    );
    let (mut b, node_b) = moving(&net);
    show(&mut b, "w = tide_open(\"127.0.0.1:7162\")");
    show(
        &mut a,
        "def keeper(parent)\n  f = only_here\n  send(parent, :ready)\n  send(parent, [receive(), f])\nend\n\
         w = tide_open(\"127.0.0.1:7161\")\n\
         p = spawn(keeper, [self()])\n\
         receive(:ready)\n\
         evict(p, w, \"127.0.0.1:7162\")\n\
         tide_release(w, 1000000, 0)",
    );
    let out = show(&mut b, "begin\n  accept(w, 0)\nrescue e\n  e.message\nend");
    assert!(
        out.contains("the image cannot resume here: it holds the native function `only_here`, which this node does not register"),
        "{out}"
    );
    assert_eq!(node_b.process_count(), 0, "nothing was admitted");
}

#[test]
fn a_plain_process_waiting_with_a_timeout_keeps_what_is_left_of_it_on_the_new_node() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, _) = moving(&net);
    show(&mut b, "w = tide_open(\"127.0.0.1:7132\")");
    show(
        &mut a,
        "def waiter(parent)\n  send(parent, :ready)\n  send(parent, [:woke, receive(:go, 1000, :late), self()])\nend\n\
         w = tide_open(\"127.0.0.1:7131\")\n\
         p = spawn(waiter, [self()])\n\
         receive(:ready)\n\
         receive(:never, 600, :waited)\n\
         evict(p, w, \"127.0.0.1:7132\")\n\
         tide_release(w, 1000000, 0)",
    );
    let out = show(
        &mut b,
        "p = accept(w, 0)\n\
         [receive([:woke, :_, :_], 399, :early), receive([:woke, :_, :_], 2, :none)]",
    );
    assert_eq!(
        out, "(:early (:woke :late 1))",
        "600 of its 1000 ms passed on node a, so it times out 400 ms after it arrives, not 1000"
    );
}

const STEPS: &str = "\
def steps(parent)
  n = receive()
  if n == :boom
    raise(:boom, \"asked to crash\")
  end
  send(parent, [:at, n, self()])
  steps(parent)
end
";

#[test]
fn a_supervised_plain_process_is_handed_over_and_restarts_from_its_code_on_its_new_node() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, node_b) = moving(&net);
    show(&mut b, "w = tide_open(\"127.0.0.1:7142\")");
    let left = show(
        &mut a,
        &format!(
            "{STEPS}\
             w = tide_open(\"127.0.0.1:7141\")\n\
             sup = supervisor(:one_for_one, [[steps, [self()]]], 2)\n\
             s = nth(0, children(sup))\n\
             send(s, :boom)\n\
             receive(:never, 10, :waited)\n\
             send(s, 1)\nfirst = receive([:at, :_, :_])\n\
             send(s, 2)\n\
             evict(s, w, \"127.0.0.1:7142\")\n\
             tide_release(w, 1000000, 0)\n\
             [first, children(sup), alive?(s)]"
        ),
    );
    assert_eq!(left, "((:at 1 2) () #f)");
    let arrived = show(
        &mut b,
        "p = accept(w, 0)\n\
         moved = receive([:at, :_, :_])\n\
         send(p, :boom)\nreceive(:never, 10, :waited)\n\
         send(p, 3)\nrestarted = receive([:at, :_, :_])\n\
         send(p, :boom)\nreceive(:never, 10, :waited)\n\
         [moved, restarted, alive?(p)]",
    );
    assert_eq!(
        arrived, "((:at 2 2) (:at 3 2) #f)",
        "on node b the message queued before the move is taken by the frames that moved; a crash restarts it from its code under a one_for_one supervisor of its own, and the restart it spent on node a counts, so the second crash there is the one its supervisor gives up on"
    );
    assert_eq!(node_b.process_count(), 0);
    let traces = node_b.traces();
    assert_eq!(
        traces
            .iter()
            .map(|t| (t.truncated, t.carried.as_ref().map(|c| c.entries), t.tape.len()))
            .collect::<Vec<_>>(),
        [(false, Some(3), 7), (false, None, 4)],
        "the incarnation that arrived starts its tape with the three entries its incarnation made on node a (receive 1, self, send), then takes 2 and :boom on node b; the one its supervisor restarted from its code starts an empty tape, as a restart empties the mailbox"
    );
    for t in &traces {
        let r = replay(&round_trip(t), blue_lang_runtime::interpreter_hostless());
        assert!(r.reproduced, "{r:?}");
    }
}

#[test]
fn a_child_cannot_evict_because_only_the_program_waits_for_a_boundary() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let out = show(
        &mut a,
        "def mover(me)\n  r = begin\n    evict(me, nil, \"127.0.0.1:9\")\n  rescue e\n    e.message\n  end\n  send(me, r)\nend\n\
         spawn(mover, [self()])\n\
         contains?(receive(), \"only the program waits\")",
    );
    assert_eq!(out, "#t");
}

#[test]
fn a_monitor_hears_the_eviction_and_the_process_is_not_alive_here() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let out = show(
        &mut a,
        &format!(
            "{COUNTER}\
             w = tide_open(\"127.0.0.1:7031\")\n\
             s = spawn_server(counter, [])\n\
             r = monitor(s)\n\
             evict(s, w, \"127.0.0.1:7032\")\n\
             d = receive()\n\
             [nth(0, d) == :down, nth(1, d) == r, nth(2, d) == s, nth(3, d), alive?(s)]"
        ),
    );
    assert_eq!(out, "(#t #t #t :evicted #f)");
}

#[test]
fn accept_takes_only_image_frames_and_leaves_the_rest_for_tide_next() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, _) = moving(&net);
    show(&mut b, "w = tide_open(\"127.0.0.1:7042\")");
    show(
        &mut a,
        &format!(
            "{COUNTER}\
             w = tide_open(\"127.0.0.1:7041\")\n\
             tide_send(w, \"127.0.0.1:7042\", \"hello\", 5)\n\
             s = spawn_server(counter, [7])\n\
             evict(s, w, \"127.0.0.1:7042\")\n\
             tide_release(w, 1000000, 6)"
        ),
    );
    let out = show(
        &mut b,
        "p = accept(w, 0)\n\
         send(p, [:get, self()])\n\
         [receive(), tide_next(w, 0).payload, tide_next(w, 0)]",
    );
    assert_eq!(out, "((:seen (7)) \"hello\" ())");
}

#[test]
fn an_image_whose_bytes_hash_to_another_name_or_a_broken_frame_raises_decode_error() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, node_b) = moving(&net);
    let zeros = "0".repeat(64);
    show(&mut b, "w = tide_open(\"127.0.0.1:7052\")");
    show(
        &mut a,
        &format!(
            "w = tide_open(\"127.0.0.1:7051\")\n\
             tide_send(w, \"127.0.0.1:7052\", \"blue-image 1 {zeros} 0000 0001\\n{{}}\", 0)"
        ),
    );
    let forged = show(
        &mut b,
        "begin\n  accept(w, 0)\nrescue :decode_error as e\n  [e.kind, contains?(e.message, \"hash to another name\")]\nend",
    );
    assert_eq!(forged, "(:decode_error #t)");
    show(
        &mut a,
        "tide_send(w, \"127.0.0.1:7052\", \"blue-image 1 not-a-header\\nx\", 0)",
    );
    let broken = show(
        &mut b,
        "begin\n  accept(w, 0)\nrescue :decode_error as e\n  e.kind\nend",
    );
    assert_eq!(broken, ":decode_error");
    assert_eq!(node_b.process_count(), 0, "nothing was admitted");
}

const KEEPER: &str = "\
def keeper(msg, seen)
  if msg == :boom
    raise(:boom, \"asked to crash\")
  end
  if nth(0, msg) == :inc
    append(seen, [nth(1, msg)])
  else
    send(nth(1, msg), [:seen, seen])
    seen
  end
end
";

#[test]
fn a_supervised_server_is_handed_over_and_restarts_on_its_new_node_as_its_supervisor_would() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, node_b) = moving(&net);
    show(&mut b, "w = tide_open(\"127.0.0.1:7072\")");
    let left = show(
        &mut a,
        &format!(
            "{KEEPER}\
             w = tide_open(\"127.0.0.1:7071\")\n\
             sup = supervisor(:one_for_one, [[:server, keeper, [0]]], 2)\n\
             s = nth(0, children(sup))\n\
             send(s, :boom)\n\
             receive(:never, 10, :waited)\n\
             send(s, [:inc, 1])\nsend(s, [:inc, 2])\n\
             send(s, [:get, self()])\nbefore = receive()\n\
             send(s, [:inc, 3])\n\
             moved = evict(s, w, \"127.0.0.1:7072\")\n\
             [before, children(sup), alive?(s), tide_release(w, 1000000, 0) == moved.bytes]"
        ),
    );
    assert_eq!(
        left, "((:seen (0 1 2)) () #f #t)",
        "the supervisor on node a drops the child it handed over, as it drops one that exits for good"
    );
    let arrived = show(
        &mut b,
        "p = accept(w, 0)\n\
         send(p, [:get, self()])\nmoved = receive()\n\
         send(p, :boom)\nreceive(:never, 10, :waited)\n\
         send(p, [:get, self()])\nrestarted = receive()\n\
         send(p, :boom)\nreceive(:never, 10, :waited)\n\
         [moved, restarted, alive?(p)]",
    );
    assert_eq!(
        arrived, "((:seen (0 1 2 3)) (:seen (0)) #f)",
        "on node b the server keeps the state it left with and the message queued for it; a crash restarts it from the state its supervisor began it with, not the state it moved with; the restart it spent on node a counts, so with max_restarts 2 the second crash on node b is the one its supervisor gives up on"
    );
    assert_eq!(node_b.process_count(), 0);
}

#[test]
fn evict_breaks_a_link_with_evicted_for_every_partner_that_traps_exits_and_names_one_that_does_not()
{
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let out = show(
        &mut a,
        &format!(
            "{COUNTER}\
             def relay(parent)\n  send(parent, [:heard, receive()])\n  relay(parent)\nend\n\
             def watcher(parent, s)\n  trap_exit(true)\n  link(s)\n  send(parent, :ready)\n  relay(parent)\nend\n\
             def deaf(parent, s)\n  link(s)\n  send(parent, :ready)\n  receive()\n  unlink(s)\n  send(parent, :unlinked)\n  receive()\nend\n\
             w = tide_open(\"127.0.0.1:7081\")\n\
             s = spawn_server(counter, [5])\n\
             v = spawn(watcher, [self(), s])\nreceive(:ready)\n\
             d = spawn(deaf, [self(), s])\nreceive(:ready)\n\
             refused = begin\n  evict(s, w, \"127.0.0.1:7082\")\n  :moved\nrescue e\n  [contains?(e.message, \"is linked to #{{d}},\"), contains?(e.message, \"does not trap exits\")]\nend\n\
             send(v, :probe)\nfirst = receive([:heard, :_])\n\
             send(s, [:get, self()])\nstill = receive([:seen, :_])\n\
             send(d, :unlink)\nreceive(:unlinked)\n\
             trap_exit(true)\nlink(s)\n\
             evict(s, w, \"127.0.0.1:7082\")\n\
             heard = receive([:heard, :_])\n\
             [refused, first, still, heard, receive([:exit, :_, :_]), alive?(s)]"
        ),
    );
    assert_eq!(
        out, "((#t #t) (:heard :probe) (:seen (5)) (:heard (:exit 1 :evicted)) (:exit 1 :evicted) #f)",
        "a partner that does not trap exits refuses the move by name and nothing reaches the one that does; once it unlinks, the watcher and the program, both trapping, each hear [:exit, pid, :evicted]"
    );
}

const LONG: &str = "\
def spin(k)
  if k == 0
    0
  else
    spin(k - 1)
  end
end
def long(m, n)
  if m == 0
    spin(5000)
    n + 1000
  else
    n + m
  end
end
";

#[test]
fn an_evicted_server_keeps_its_own_dispatch_bound_met_with_the_accepting_nodes() {
    for (port, accepting, limit) in [
        (7091, None, 2000),
        (7093, Some(1500), 1500),
        (7095, Some(3000), 2000),
    ] {
        let net = Arc::new(LoopbackNet::default());
        let (mut a, _) = moving_under(&net, None);
        let (mut b, _) = moving_under(&net, accepting);
        show(
            &mut b,
            &format!("w = tide_open(\"127.0.0.1:{}\")", port + 1),
        );
        let left = show(
            &mut a,
            &format!(
                "{LONG}w = tide_open(\"127.0.0.1:{port}\")\n\
                 s = spawn_server(long, 0, {{dispatch_steps: 2000}})\n\
                 send(s, 1)\n\
                 evict(s, w, \"127.0.0.1:{}\")\n\
                 tide_release(w, 1000000, 0) > 0",
                port + 1
            ),
        );
        assert_eq!(left, "#t");
        let out = show(
            &mut b,
            "p = accept(w, 0)\nmonitor(p)\nsend(p, 0)\nnth(3, receive(:_, 5000))",
        );
        assert_eq!(
            out,
            format!("(:runaway \"execution budget exhausted: steps per dispatch (limit {limit})\")"),
            "the server's own {{dispatch_steps: 2000}} travels in its image and meets the accepting node's bound {accepting:?}"
        );
    }
}

fn round_trip(t: &Trace) -> Trace {
    Trace::parse(&String::from_utf8(t.bytes()).expect("utf-8")).expect("a trace")
}

const LEDGER: &str = "\
def ledger(parent)
  t0 = now_ms()
  a = receive()
  b = receive()
  send(parent, [:took, a + b, self()])
  c = receive()
  t1 = now_ms()
  throw(error(:moved, \"took #{a} and #{b} at #{t0} as #{self()}, then #{c} at #{t1}\"))
end
";

fn ledger_left(a: &mut Interpreter<()>, from: u16, to: u16) -> String {
    show(
        a,
        &format!(
            "{LEDGER}\
             w = tide_open(\"127.0.0.1:{from}\")\n\
             p = spawn(ledger, [self()])\n\
             send(p, 1)\nsend(p, 2)\n\
             receive([:took, :_, :_])\n\
             moved = evict(p, w, \"127.0.0.1:{to}\")\n\
             tide_release(w, 1000000, 0)\n\
             moved.image"
        ),
    )
    .trim_matches('"')
    .to_string()
}

fn ledger_crashed(b: &mut Interpreter<()>, node_b: &Node) -> Trace {
    let down = show(
        b,
        "p = accept(w, 0)\nmonitor(p)\nsend(p, 3)\nnth(3, receive(:_, 5000))",
    );
    assert!(
        down.starts_with("(:crashed ")
            && down.contains("took 1 and 2 at ")
            && down.contains(" as 2, then 3 at "),
        "{down}"
    );
    let traces = node_b.traces();
    assert_eq!(traces.len(), 1, "{traces:?}");
    round_trip(&traces[0])
}

const RESIDENT: &str = "def resident()\n  receive()\nend\nspawn(resident)\n";

fn ledger_moved(ports: (u16, u16)) -> (Trace, String) {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, node_b) = moving(&net);
    show(
        &mut b,
        &format!("{RESIDENT}w = tide_open(\"127.0.0.1:{}\")", ports.1),
    );
    let image = ledger_left(&mut a, ports.0, ports.1);
    (ledger_crashed(&mut b, &node_b), image)
}

#[test]
fn a_plain_process_that_crashes_on_the_node_it_moved_to_replays_from_its_start_through_the_tape_it_carried(
) {
    let (trace, image) = ledger_moved((7171, 7172));
    assert!(image.starts_with("b3:"), "{image}");
    assert!(
        !trace.truncated,
        "the tape node a recorded came in the image, so the trace on node b is whole"
    );
    let calls: Vec<&str> = trace.tape.iter().map(|e| e.call.as_str()).collect();
    assert_eq!(
        calls,
        ["now_ms", "receive", "receive", "self", "send", "receive", "now_ms", "self"],
        "five calls on node a, then the receive it parked in and two more on node b"
    );
    let carried = trace.carried.as_ref().expect("a carried block");
    assert_eq!(
        (carried.entries, carried.image.as_str()),
        (5, image.as_str()),
        "the first five entries came in the image evict named"
    );
    assert_eq!(trace.to_json()["version"], 4);
    let r = replay(&trace, blue_lang_runtime::interpreter_hostless());
    assert!(r.reproduced, "{r:?}");
    assert_eq!(
        (r.kind.as_str(), r.consumed, r.tape_len),
        ("crashed", 8, 8),
        "the same crash at the same tape entry"
    );
    assert_eq!(r.text, trace.reason_text);
    assert!(
        r.text.contains(" as 2, then 3 at "),
        "self() answered 1 on node a and 2 on node b, and the replay read both off the tape: {}",
        r.text
    );
}

#[test]
fn a_trace_whose_carried_tape_was_cut_or_forged_is_refused_by_name_and_not_replayed() {
    let (trace, image) = ledger_moved((7173, 7174));
    let refused = |t: &Trace| {
        let r = replay(t, blue_lang_runtime::interpreter_hostless());
        assert!(!r.reproduced, "{r:?}");
        assert_eq!(r.consumed, 0, "nothing ran: {r:?}");
        r.refused.expect("refused")
    };
    let mut cut = trace.clone();
    cut.tape.remove(1);
    let why = refused(&cut);
    assert!(
        why.contains(&format!(
            "the tape carried in image {image} does not match: its first 5 entries hash to b3:"
        )),
        "{why}"
    );
    let mut short = trace.clone();
    short.tape.truncate(3);
    assert_eq!(
        refused(&short),
        format!("its tape is cut: 5 entries came with process 2 in image {image}, and the trace holds 3")
    );
    let mut forged = trace.clone();
    forged.tape[2].outcome = Ok(Value::Int(9));
    assert!(refused(&forged).contains("does not match"));
    let mut after = trace.clone();
    after.tape[5].outcome = Ok(Value::Int(9));
    let r = replay(&after, blue_lang_runtime::interpreter_hostless());
    assert!(
        r.refused.is_none() && !r.reproduced,
        "an edit past the carried part replays and diverges, as any edit to a tape does: {r:?}"
    );
    let mut j = trace.to_json();
    j.as_object_mut().expect("an object").remove("carried");
    assert!(Trace::from_json(&j).is_err_and(|e| e.contains(
        "blue-trace version 4 carries a tape from the node its process left, and this one carries none"
    )));
    j["version"] = Json::from(3);
    let unmarked = Trace::from_json(&j).expect("a version 3 trace");
    assert!(
        replay(&unmarked, blue_lang_runtime::interpreter_hostless()).reproduced,
        "the whole tape from the start replays with or without the block that names where it began"
    );
    let mut wrong = trace.to_json();
    wrong["version"] = Json::from(3);
    assert!(Trace::from_json(&wrong).is_err_and(
        |e| e.contains("version 3 carries no tape from another node, and this one does")
    ));
    for (field, bad) in [
        ("image", format!("b3:{}", "z".repeat(64))),
        ("image", "b3:abcd".to_string()),
        ("tape", "abcd".repeat(16)),
    ] {
        let mut named = trace.to_json();
        named["carried"][field] = Json::from(bad.clone());
        assert!(
            Trace::from_json(&named)
                .is_err_and(|e| e.contains(&format!("`carried.{field}` is not a b3: hash"))),
            "{field} = {bad}"
        );
    }
}

const TILL: &str = "\
def till(msg, total)
  t = now_ms()
  if msg == :boom
    throw(error(:boom, \"total #{total} at #{t} as #{self()}\"))
  end
  if integer?(msg)
    total + msg
  else
    send(nth(1, msg), [:total, total, t])
    total
  end
end
";

#[test]
fn a_server_that_crashes_on_the_node_it_moved_to_replays_from_its_last_boundary_there() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, node_b) = moving(&net);
    show(
        &mut b,
        &format!("{RESIDENT}w = tide_open(\"127.0.0.1:7176\")"),
    );
    let left = show(
        &mut a,
        &format!(
            "{TILL}\
             w = tide_open(\"127.0.0.1:7175\")\n\
             s = spawn_server(till, 0)\n\
             send(s, 1)\nsend(s, 2)\n\
             send(s, [:get, self()])\n\
             before = receive([:total, :_, :_])\n\
             send(s, 4)\n\
             evict(s, w, \"127.0.0.1:7176\")\n\
             tide_release(w, 1000000, 0) > 0\n\
             nth(1, before)"
        ),
    );
    assert_eq!(left, "3");
    let down = show(
        &mut b,
        "p = accept(w, 0)\nmonitor(p)\nsend(p, :boom)\nnth(3, receive(:_, 5000))",
    );
    assert!(
        down.starts_with("(:crashed ")
            && down.contains("total 7 at ")
            && down.contains(" as 2\\\""),
        "{down}"
    );
    let traces = node_b.traces();
    assert_eq!(traces.len(), 1, "{traces:?}");
    let trace = round_trip(&traces[0]);
    assert!(!trace.truncated);
    let calls: Vec<&str> = trace.tape.iter().map(|e| e.call.as_str()).collect();
    assert_eq!(calls, ["%server_next", "now_ms", "self"]);
    let r = replay(&trace, blue_lang_runtime::interpreter_hostless());
    assert!(r.reproduced, "{r:?}");
    assert_eq!((r.kind.as_str(), r.consumed, r.tape_len), ("crashed", 3, 3));
    assert_eq!(r.text, trace.reason_text);
}

#[test]
fn a_plain_process_whose_tape_the_send_ring_cannot_hold_still_moves_and_its_trace_says_the_tape_stayed(
) {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, node_b) = moving(&net);
    show(
        &mut b,
        &format!("{RESIDENT}w = tide_open(\"127.0.0.1:7186\")"),
    );
    let left = show(
        &mut a,
        "def chatty(parent)\n  map(fn(i) now_ms() end, range(5000))\n  send(parent, :ready)\n  m = receive()\n  throw(error(:moved, \"took #{m}\"))\nend\n\
         w = tide_open(\"127.0.0.1:7185\", {ring_frames: 64, ring_bytes: 81920})\n\
         p = spawn(chatty, [self()])\n\
         receive(:ready)\n\
         moved = evict(p, w, \"127.0.0.1:7186\")\n\
         [moved.frames <= 64, tide_release(w, 1000000, 0) == moved.bytes, alive?(p)]",
    );
    assert_eq!(
        left, "(#t #t #f)",
        "five thousand clock readings do not fit a ring of 64 frames, and the process moves without them, as it did before its tape could travel"
    );
    let down = show(
        &mut b,
        "p = accept(w, 0)\nmonitor(p)\nsend(p, 5)\nnth(3, receive(:_, 5000))",
    );
    assert!(down.contains("took 5"), "{down}");
    let traces = node_b.traces();
    assert_eq!(traces.len(), 1, "{traces:?}");
    let trace = round_trip(&traces[0]);
    assert!(
        trace.truncated && trace.carried.is_none(),
        "the tape stayed behind, and the trace says so"
    );
}

fn without_tape(frames: &[String]) -> Vec<String> {
    let mut arrivals = Arrivals::default();
    for f in frames {
        arrivals.file(f).expect("a frame");
    }
    let text = arrivals.complete().expect("whole").expect("intact");
    let mut j: Json = serde_json::from_str(&text).expect("json");
    let o = j.as_object_mut().expect("an object");
    o.remove("tape");
    o.insert("version".to_string(), Json::from(3));
    let old = Image::from_json(&j).expect("a version 3 image").text();
    assert!(!old.contains("\"tape\""), "{old}");
    image::frames(&image::id_of(&old), &old, CARRIER.room).expect("frames")
}

#[test]
fn a_process_that_moved_in_an_image_without_its_tape_still_writes_a_truncated_trace() {
    let net = Arc::new(LoopbackNet::default());
    let (mut a, _) = moving(&net);
    let (mut b, node_b) = moving(&net);
    show(
        &mut b,
        &format!("{RESIDENT}w = tide_open(\"127.0.0.1:7179\")"),
    );
    show(&mut a, "w2 = tide_open(\"127.0.0.1:7180\")");
    let _ = ledger_left(&mut a, 7178, 7180);
    let Value::List(sent) = run(
        &mut a,
        "def drain(w, acc)\n  x = tide_next(w, 0)\n  if not x\n    acc\n  else\n    drain(w, append(acc, [x.payload]))\n  end\nend\n\
         drain(w2, [])",
    )
    .expect("frames") else {
        panic!("not a list of frames");
    };
    let sent: Vec<String> = sent
        .iter()
        .map(|f| match f {
            Value::Str(s) => s.to_string(),
            other => panic!("not a frame: {other}"),
        })
        .collect();
    assert!(!sent.is_empty());
    a.define_global(
        "old",
        Value::list(
            without_tape(&sent)
                .into_iter()
                .map(|f| Value::Str(Arc::from(f))),
        ),
    );
    show(
        &mut a,
        "map(fn(f) tide_send(w, \"127.0.0.1:7179\", f, 0) end, old)\ntide_release(w, 1000000, 0)",
    );
    let trace = ledger_crashed(&mut b, &node_b);
    assert!(
        trace.truncated,
        "an image that carries no tape leaves the tape on the node it left, and the trace says so"
    );
    assert!(trace.carried.is_none() && trace.tape.is_empty());
    assert_eq!(trace.to_json()["version"], 3);
    let r = replay(&trace, blue_lang_runtime::interpreter_hostless());
    assert!(!r.reproduced && r.refused.is_none(), "{r:?}");
}
