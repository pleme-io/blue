mod support;

use std::sync::Arc;
use std::time::{Duration, Instant};

use blue_lang_proc::{ClockKind, NodeConfig};
use support::{configure, node, show};

fn timed(src: &str) -> (String, Duration) {
    let (mut root, _) = node(50);
    let started = Instant::now();
    let out = show(&mut root, src);
    (out, started.elapsed())
}

#[test]
fn a_ten_minute_sleep_on_the_virtual_clock_takes_no_wall_time_and_observes_ten_minutes() {
    let (out, wall) = timed("t0 = node_time()\nsleep_for(600000)\n[t0, node_time()]");
    assert_eq!(out, "(0 600000)");
    assert!(wall < Duration::from_secs(1), "took {wall:?}");
}

#[test]
fn a_thirty_second_timeout_raises_timeout_at_thirty_seconds_in_milliseconds() {
    let (out, wall) = timed(
        "begin\n  timeout(30000, fn() receive([:never]) end)\n  :finished\n\
         rescue :timeout as e\n  [e.kind, node_time(), e.data[:deadline]]\nend",
    );
    assert_eq!(out, "(:timeout 30000 30000)");
    assert!(wall < Duration::from_secs(1), "took {wall:?}");
}

#[test]
fn two_timers_fire_in_the_order_of_their_deadlines_not_of_their_creation() {
    let (out, _) = timed(
        "after(300, :late)\nafter(100, :early)\nafter(200, :middle)\n\
         a = receive()\nta = node_time()\nb = receive()\nc = receive()\n[a, ta, b, c, node_time()]",
    );
    assert_eq!(out, "(:early 100 :middle :late 300)");
}

#[test]
fn timers_with_one_deadline_fire_in_the_order_they_were_set() {
    let (out, _) =
        timed("after(50, 1)\nafter(50, 2)\nafter(50, 3)\n[receive(), receive(), receive()]");
    assert_eq!(out, "(1 2 3)");
}

#[test]
fn after_sends_to_another_process_at_its_time() {
    let (out, _) = timed(
        "me = self()\n\
         p = spawn(fn() m = receive()\n  send(me, [m, node_time()]) end)\n\
         after(700, :wake, p)\nreceive()",
    );
    assert_eq!(out, "(:wake 700)");
}

#[test]
fn a_sleeping_process_parks_and_never_holds_the_node() {
    let (out, _) = timed(
        "me = self()\n\
         spawn(fn() sleep_for(1000)\n  send(me, [:slow, node_time()]) end)\n\
         spawn(fn() send(me, [:fast, node_time()]) end)\n\
         spawn(fn() sleep_until(400)\n  send(me, [:until, node_time()]) end)\n\
         [receive(), receive(), receive()]",
    );
    assert_eq!(out, "((:fast 0) (:until 400) (:slow 1000))");
}

#[test]
fn a_deadline_scopes_the_root_and_restores_the_one_outside() {
    let (out, _) = timed(
        "inner = deadline(250, fn() [context()[:deadline], remaining()] end)\n\
         [inner, context()[:deadline], remaining(), context()[:clock]]",
    );
    assert_eq!(out, "((250 250) () () :virtual)");
}

#[test]
fn a_nested_deadline_only_narrows() {
    let (out, _) = timed("deadline(100, fn() deadline(5000, fn() context()[:deadline] end) end)");
    assert_eq!(out, "100");
}

#[test]
fn a_receive_whose_own_timeout_comes_first_answers_its_default_inside_a_deadline() {
    let (out, _) = timed("timeout(1000, fn() receive([:x], 10, :none) end)");
    assert_eq!(out, ":none");
}

#[test]
fn a_spawned_process_inherits_its_spawners_deadline_and_cannot_sleep_past_it() {
    let (out, _) = timed(
        "me = self()\n\
         timeout(500, fn()\n  spawn(fn()\n    begin\n      sleep_for(10000)\n      send(me, :slept)\n    \
         rescue :timeout as e\n      send(me, [e.kind, node_time(), context()[:deadline]])\n    end\n  end)\nend)\n\
         receive()",
    );
    assert_eq!(out, "(:timeout 500 500)");
}

#[test]
fn a_process_spawned_outside_any_deadline_holds_none() {
    let (out, _) = timed("me = self()\nspawn(fn() send(me, context()[:deadline]) end)\nreceive()");
    assert_eq!(out, "()");
}

#[test]
fn narrowing_a_deadline_inside_a_process_is_refused_by_name() {
    let (out, _) = timed(
        "me = self()\n\
         spawn(fn() send(me, begin\n  deadline(10, fn() 1 end)\nrescue e\n  e.message\nend) end)\n\
         receive()",
    );
    assert!(out.contains("async phase A2"), "{out}");
}

#[test]
fn a_time_that_is_not_a_non_negative_int_is_refused() {
    let (out, _) = timed("sleep_for(-1)");
    assert!(out.contains("milliseconds on the node clock"), "{out}");
}

const RACE: &str = "me = self()\n\
    def worker(me, id, wait)\n  sleep_for(wait)\n  after(wait, [:echo, id], me)\n  send(me, [id, node_time()])\nend\n\
    spawn(worker, [me, :a, 300])\nspawn(worker, [me, :b, 100])\nspawn(worker, [me, :c, 200])\n\
    spawn(worker, [me, :d, 100])\n\
    [receive(), receive(), receive(), receive(), receive(), receive(), receive(), receive(), node_time()]";

#[test]
fn the_same_timed_program_gives_the_same_answer_every_run() {
    let first = timed(RACE).0;
    assert_eq!(
        first,
        "((:b 100) (:d 100) (:echo :b) (:echo :d) (:c 200) (:a 300) (:echo :c) (:echo :a) 600)"
    );
    for _ in 0..8 {
        assert_eq!(timed(RACE).0, first);
    }
}

#[test]
fn the_wall_clock_is_a_position_and_takes_real_time() {
    let mut config = NodeConfig::new(Arc::new(blue_lang_runtime::interpreter_hostless));
    config.clock = ClockKind::Real;
    config.trace_dir = None;
    let (mut root, _) = configure(config);
    let started = Instant::now();
    let out = show(
        &mut root,
        "sleep_for(60)\n[context()[:clock], node_time() >= 60]",
    );
    assert_eq!(out, "(:real #t)");
    assert!(started.elapsed() >= Duration::from_millis(60));
}
