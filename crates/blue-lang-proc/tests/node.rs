//! G11: processes reachable from blue — spawn, send, receive, links,
//! monitors and supervisors, written as blue programs.
//!
//! Each test runs a program as the root of a node with a virtual clock, so
//! every schedule here is the same on every run and every timeout fires at the
//! same instant.

mod support;

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use support::{node, node_with, run, show};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::Value;

#[test]
fn a_spawned_function_brings_its_helpers_and_copies_what_it_captured() {
    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        "def double(x)\n  x * 2\nend\n\
         def worker(parent, n)\n  send(parent, [:result, double(n)])\nend\n\
         me = self()\nk = 5\n\
         spawn(worker, [me, 21])\n\
         spawn(fn() send(me, [:captured, k + 1]) end)\n\
         [receive([:result, :_]), receive([:captured, :_])]",
    );
    assert_eq!(out, "((:result 42) (:captured 6))");
}

#[test]
fn the_program_is_pid_zero_and_children_count_up_from_one() {
    let (mut root, _) = node(50);
    assert_eq!(
        show(
            &mut root,
            "a = spawn(fn() 1 end)\nb = spawn(fn() 2 end)\n[self(), a, b]"
        ),
        "(0 1 2)"
    );
}

#[test]
fn a_function_is_refused_as_a_message_rather_than_delivered_as_nil() {
    let (mut root, _) = node(50);
    let out = show(&mut root, "send(self(), fn(x) x end)");
    assert!(
        out.contains("a message is copied to the receiver") && out.contains("not data"),
        "{out}"
    );
}

#[test]
fn maps_and_keywords_arrive_intact() {
    let (mut root, _) = node(50);
    assert_eq!(
        show(
            &mut root,
            "send(self(), {kind: :tick, n: 3})\nm = receive()\n[get(m, :kind), get(m, :n)]"
        ),
        "(:tick 3)"
    );
}

#[test]
fn selective_receive_takes_the_oldest_match_and_keeps_the_rest_in_order() {
    let (mut root, node) = node(50);
    let out = show(
        &mut root,
        "me = self()\n\
         send(me, :noise)\nsend(me, [:reply, 1])\nsend(me, :more)\nsend(me, [:reply, 2])\n\
         receive([:reply, :_])",
    );
    assert_eq!(out, "(:reply 1)");
    let left: Vec<String> = node
        .mailbox(blue_lang_proc::ROOT)
        .iter()
        .map(ToString::to_string)
        .collect();
    assert_eq!(left, [":noise", ":more", "(:reply 2)"]);
}

#[test]
fn a_child_waits_selectively_without_consuming_what_it_skips() {
    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        "me = self()\n\
         p = spawn(fn() \n\
           wanted = receive([:go, :_])\n\
           rest = receive()\n\
           send(me, [wanted, rest])\n\
         end)\n\
         send(p, :early)\nsend(p, [:go, 7])\n\
         receive()",
    );
    assert_eq!(out, "((:go 7) :early)");
}

#[test]
fn a_timeout_answers_on_timeout_at_the_virtual_deadline() {
    let (mut root, _) = node(50);
    assert_eq!(show(&mut root, "receive(:_, 500, :late)"), ":late");
    let out = show(
        &mut root,
        "me = self()\n\
         spawn(fn() send(me, receive(:never, 100, :child_timed_out)) end)\n\
         receive(:_, 1000, :root_timed_out)",
    );
    assert_eq!(out, ":child_timed_out");
}

#[test]
fn waiting_forever_with_no_sender_is_a_reported_deadlock_not_a_hang() {
    let (mut root, _) = node(50);
    let out = show(&mut root, "spawn(fn() receive() end)\nreceive()");
    assert!(
        out.contains("would wait forever") && out.contains("deadlock; waiting: 1"),
        "{out}"
    );
}

#[test]
fn a_linked_crash_ends_the_partner_unless_it_traps_exits() {
    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        "me = self()\n\
         a = spawn(fn() receive() end)\n\
         m = monitor(a)\n\
         b = spawn(fn() \n  link(a)\n  throw(error(:boom, \"b failed\"))\nend)\n\
         receive([:down, m, :_, :_])",
    );
    assert!(
        out.starts_with("(:down 1 1 (:crashed"),
        "a dies with b's reason: {out}"
    );

    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        "trap_exit(true)\n\
         spawn_link(fn() throw(error(:boom, \"child failed\")) end)\n\
         receive([:exit, :_, :_])",
    );
    assert!(out.starts_with("(:exit 1 (:crashed"), "{out}");
}

#[test]
fn an_untrapped_linked_crash_raises_in_the_program() {
    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        "spawn_link(fn() throw(error(:boom, \"x\")) end)\nreceive()",
    );
    assert!(out.contains("linked process 1 exited"), "{out}");
}

#[test]
fn a_monitor_hears_normal_exits_and_noproc_for_the_already_dead() {
    let (mut root, _) = node(50);
    assert_eq!(
        show(
            &mut root,
            "p = spawn(fn() 1 end)\nm = monitor(p)\nreceive([:down, m, :_, :_])"
        ),
        "(:down 1 1 :normal)"
    );
    assert_eq!(
        show(&mut root, "m = monitor(999)\nreceive()"),
        "(:down 2 999 :noproc)"
    );
}

#[test]
fn exit_signals_kill_and_trapped_ones_arrive_as_messages_except_kill() {
    let (mut root, _) = node(50);
    let out = show(
        &mut root,
        "me = self()\n\
         p = spawn(fn() \n  trap_exit(true)\n  send(me, :ready)\n  send(me, receive())\n  receive()\nend)\n\
         receive(:ready)\n\
         exit(p, :please)\n\
         first = receive([:exit, :_, :_])\n\
         m = monitor(p)\n\
         exit(p, :kill)\n\
         [first, receive([:down, m, :_, :_]), alive?(p)]",
    );
    assert_eq!(out, "((:exit 0 :please) (:down 1 1 :killed) #f)");
}

#[test]
fn one_for_one_restarts_the_crashed_child_with_an_empty_mailbox() {
    let (mut root, _) = node(50);
    // The child crashes on :poison. The message queued behind the poison was
    // addressed to the incarnation that died, so the restart must not see it.
    let out = show(
        &mut root,
        "me = self()\n\
         def child(parent)\n  send(parent, [:started, self()])\n  m = receive()\n  if m == :poison\n    throw(error(:poisoned, \"poison\"))\n  end\n  send(parent, [:got, m])\nend\n\
         sup = supervisor(:one_for_one, [[child, [me]]], 3)\n\
         first = receive([:started, :_])\n\
         pid = nth(1, first)\n\
         send(pid, :poison)\nsend(pid, :stale)\n\
         again = receive([:started, :_])\n\
         send(pid, :fresh)\n\
         [nth(1, again) == pid, receive([:got, :_])]",
    );
    assert_eq!(out, "(#t (:got :fresh))");
}

#[test]
fn a_supervisor_gives_up_past_its_intensity_and_its_monitor_hears_why() {
    let (mut root, node) = node(50);
    let out = show(
        &mut root,
        "sup = supervisor(:one_for_one, [fn() throw(error(:always, \"x\")) end], 2)\n\
         m = monitor(sup)\n\
         receive([:down, m, :_, :_])",
    );
    assert_eq!(out, "(:down 1 1 (:gave_up 2))");
    assert_eq!(
        node.traces().len(),
        3,
        "one trace per crash: the first run and two restarts"
    );
}

#[test]
fn a_supervisor_drops_a_breached_child_and_never_restarts_it() {
    let (mut root, _) = node_with(
        50,
        Arc::new(|| {
            let mut child = blue_lang_runtime::interpreter_hostless();
            child.register_fn("breach", Arity::Any, |_: &[Value], _: &mut (), at| {
                Err(tatara_lisp_eval::EvalError::fatal(
                    "capability-breach",
                    "`read_file` reaches the host (filesystem)",
                    at,
                ))
            });
            child
        }),
    );
    let out = show(
        &mut root,
        "me = self()\n\
         def bad(parent)\n  send(parent, :bad_started)\n  breach(1) rescue :swallowed\nend\n\
         def worker(parent)\n  send(parent, :w)\n  m = receive()\n  if m == :crash\n    throw(error(:asked, \"x\"))\n  end\nend\n\
         sup = supervisor(:one_for_all, [[bad, [me]], [worker, [me]]], 5)\n\
         starts = [receive(:bad_started), receive(:w)]\n\
         alive = children(sup)\n\
         send(first(alive), :crash)\n\
         def drain(acc)\n  m = receive(:_, 100, :none)\n  if m == :none\n    acc\n  else\n    drain(append(acc, [m]))\n  end\nend\n\
         [length(alive), drain([])]",
    );
    assert_eq!(out, "(1 (:w))");
}

#[test]
fn one_for_all_and_rest_for_one_sweep_their_siblings() {
    // Each child announces every start; the middle one is told to crash, and
    // the announcements after that are the strategy's sweep.
    for (strategy, expect) in [
        // The crashed child's restarted successors run on in the same round;
        // the ones before it start again in the next. Fixed, like every
        // schedule here.
        ("one_for_all", "(:a :b :c :c :a :b)"),
        ("rest_for_one", "(:a :b :c :c :b)"),
        ("one_for_one", "(:a :b :c :b)"),
    ] {
        let (mut root, _) = node(50);
        let src = format!(
            "me = self()\n\
             def worker(parent, tag)\n  send(parent, tag)\n  m = receive()\n  if m == :crash\n    throw(error(:asked, \"x\"))\n  end\nend\n\
             sup = supervisor(:{strategy}, [[worker, [me, :a]], [worker, [me, :b]], [worker, [me, :c]]], 5)\n\
             starts = [receive(:a), receive(:b), receive(:c)]\n\
             send(nth(1, children(sup)), :crash)\n\
             def drain(acc)\n  m = receive(:_, 100, :none)\n  if m == :none\n    acc\n  else\n    drain(append(acc, [m]))\n  end\nend\n\
             append(starts, drain([]))"
        );
        assert_eq!(show(&mut root, &src), expect, "{strategy}");
    }
}

#[test]
fn a_finished_process_is_reaped_so_memory_follows_live_processes() {
    let (mut root, node) = node(50);
    let out = show(
        &mut root,
        "me = self()\n\
         map(fn(i) spawn(fn() send(me, i) end) end, range(200))\n\
         length(map(fn(i) receive() end, range(200)))",
    );
    assert_eq!(out, "200");
    assert_eq!(
        node.process_count(),
        0,
        "every finished process was dropped"
    );
}

/// A restarted incarnation gives its memory back.
///
/// BLUE-MEMORY §I.3 measured ~832 B kept per dead incarnation, because a
/// top-level function definition closes a cycle through the frame it is
/// defined in. tatara-lisp-eval 0.3.45 releases an interpreter's own frames on
/// drop; this pins that a supervisor's restart is such a drop, so a crash loop
/// does not accrue the old incarnations. Each incarnation binds a sentinel
/// beside a recursive definition (the cycle's shape) and then crashes.
#[test]
fn a_restarted_incarnation_releases_its_frame() {
    static DROPPED: AtomicUsize = AtomicUsize::new(0);
    struct Sentinel;
    impl Drop for Sentinel {
        fn drop(&mut self) {
            DROPPED.fetch_add(1, Ordering::SeqCst);
        }
    }
    let child = Arc::new(|| {
        let mut i = blue_lang_runtime::interpreter_hostless();
        i.register_fn("sentinel", Arity::Exact(0), |_: &[Value], _: &mut (), _| {
            Ok(Value::Foreign(Arc::new(Sentinel)))
        });
        i
    });
    let (mut root, node) = node_with(50, child);
    let out = show(
        &mut root,
        "def incarnation()\n  kept = sentinel()\n  def again(n)\n    again(n)\n  end\n  throw(error(:crash, \"again\"))\nend\n\
         sup = supervisor(:one_for_one, [incarnation], 9)\n\
         m = monitor(sup)\n\
         receive([:down, m, :_, :_])",
    );
    assert!(out.starts_with("(:down"), "{out}");
    drop(root);
    drop(node);
    assert_eq!(
        DROPPED.load(Ordering::SeqCst),
        10,
        "every incarnation's sentinel is released: the first run and nine restarts"
    );
}

#[test]
fn a_bad_strategy_and_a_bad_child_are_refused_by_name() {
    let (mut root, _) = node(50);
    assert!(show(&mut root, "supervisor(:all_at_once, [])")
        .contains(":one_for_one, :one_for_all or :rest_for_one"));
    assert!(show(&mut root, "spawn(42)").contains("spawn takes a function"));
    let (mut root, _) = node(50);
    let out = run(&mut root, "spawn(fn() 1 end, 7)");
    assert!(out.is_err_and(|e| e.contains("the arguments are a list")));
}
