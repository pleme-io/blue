mod support;

use std::sync::Arc;

use blue_lang_proc::{install, ClockKind, Node, NodeConfig};
use blue_lang_runtime::wire::{host_clock, provide_loopback, LoopbackNet, CARRIER};
use support::show;
use tatara_lisp_eval::Interpreter;

fn moving(net: &Arc<LoopbackNet>) -> (Interpreter<()>, Arc<Node>) {
    let mut config = NodeConfig::new(Arc::new(blue_lang_runtime::interpreter_hostless));
    config.budget.quantum = Some(50);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    config.carrier = Some(CARRIER);
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
             plain = spawn(idle_loop)\n\
             linked = spawn_server(counter, [])\nlink(linked)\n\
             sup = supervisor(:one_for_one, [[:server, counter, []]])\n\
             held = nth(0, children(sup))\n\
             [contains?(why(fn() evict(plain, w, \"127.0.0.1:9\") end), \"not a server\"),\n\
              contains?(why(fn() evict(linked, w, \"127.0.0.1:9\") end), \"is linked to\"),\n\
              contains?(why(fn() evict(held, w, \"127.0.0.1:9\") end), \"is supervised by\"),\n\
              contains?(why(fn() evict(4242, w, \"127.0.0.1:9\") end), \"no process\")]"
        ),
    );
    assert_eq!(out, "(#t #t #t #t)");
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
