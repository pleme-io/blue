//! Message passing, end to end: blue source → tatara-lisp → the VM → the
//! scheduler → a mailbox and back.
//!
//! The claim under test is not "a queue works". It is that a process can
//! **wait for a message without burning fuel**, be woken when one arrives,
//! and that a system with nothing left to deliver says so instead of
//! spinning. Those three together are what a telephony switch or an order
//! router is built out of.

use std::sync::Arc;

use blue_lang_proc::{
    install_process_primitives, Event, Pid, ProcState, Readiness, Strategy, Supervisor, System,
};
use tatara_lisp_eval::vm::{compile_program, Budget, Chunk};
use tatara_lisp_eval::{install_lisp_stdlib_with, install_primitives, Interpreter, Value};

/// A process interpreter: the blue runtime plus the three primitives that need
/// a scheduler. **Built per process**, which is what makes globals private.
///
/// The stdlib needs a host to evaluate against; a throwaway `System` is used
/// for that one step, because the stdlib's definitions do not touch mailboxes
/// and the real `System` is owned by the caller.
fn system_interp() -> Interpreter<System> {
    let mut i = Interpreter::new();
    install_primitives(&mut i);
    install_lisp_stdlib_with(&mut i, &mut System::new());
    install_process_primitives(&mut i);
    i
}

fn blue(src: &str) -> Arc<Chunk> {
    let forms = blue_lang_syntax::parse_program(src).expect("parse blue");
    let text = forms
        .iter()
        .map(|f| f.to_string())
        .collect::<Vec<_>>()
        .join("\n");
    let spanned = tatara_lisp::read_spanned(&text).expect("read");
    Arc::new(compile_program(&spanned).expect("compile"))
}

fn quantum(q: usize) -> Budget {
    Budget::preemptive(q)
}

/// Spawn with a mailbox. Registering it on the system is what makes the pid
/// addressable; a pid with no mailbox is `undeliverable`, not a silent drop.
fn spawn(sup: &mut Supervisor<System>, sys: &mut System, chunk: Arc<Chunk>, b: Budget) -> Pid {
    let pid = sup.spawn(chunk, b, system_interp);
    sys.register(pid);
    pid
}

// ---------------------------------------------------------------------------
// The core claim
// ---------------------------------------------------------------------------

/// **A process blocks on an empty mailbox and is woken by a message.**
///
/// The receiver runs first and finds nothing, so it must park. The sender
/// then runs and delivers. The receiver must resume *and return the message*.
#[test]
fn a_receiver_blocks_then_wakes_with_the_message() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 3);

    let receiver = spawn(&mut sup, &mut sys, blue("receive()"), quantum(50));
    // The sender is declared second, so on the first round the receiver
    // genuinely finds an empty mailbox.
    let sender = spawn(
        &mut sup,
        &mut sys,
        blue(&format!("send({}, 99)", receiver.0)),
        quantum(50),
    );
    sup.run_to_quiescence(&mut sys, 100);

    assert!(
        sup.events.iter().any(|e| matches!(e, Event::Blocked { pid } if *pid == receiver)),
        "the receiver must have parked on an empty mailbox: {:?}",
        sup.events
    );
    assert!(
        sup.events.iter().any(|e| matches!(e, Event::Woke { pid } if *pid == receiver)),
        "and been woken by the message: {:?}",
        sup.events
    );
    assert_eq!(
        sup.state_of(receiver).and_then(ProcState::done_int),
        Some(99),
        "receive() must return what was sent"
    );
    assert!(sup.state_of(sender).is_some_and(ProcState::is_done));
}

/// **Waiting costs no fuel.** This is the reason parking exists rather than
/// polling: a receiver with a fuel budget far too small to spin must still
/// survive an arbitrarily long wait.
///
/// The receiver gets 40 instructions of fuel total. The sender is made slow
/// enough that the receiver would spin for thousands of instructions if
/// waiting cost anything at all.
#[test]
fn waiting_costs_no_fuel() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 0);

    let receiver = spawn(
        &mut sup,
        &mut sys,
        blue("receive()"),
        Budget {
            fuel: Some(40),
            max_depth: None,
            quantum: Some(20),
        },
    );
    let sender = spawn(
        &mut sup,
        &mut sys,
        blue(&format!(
            "def spin(n)\n  if n == 0\n    send({}, 7)\n  else\n    spin(n - 1)\n  end\nend\nspin(300)",
            receiver.0
        )),
        quantum(20),
    );
    sup.run_to_quiescence(&mut sys, 2000);

    assert!(
        sup.state_of(sender).is_some_and(ProcState::is_done),
        "the slow sender must finish: {:?}",
        sup.state_of(sender)
    );
    assert_eq!(
        sup.state_of(receiver).and_then(ProcState::done_int),
        Some(7),
        "the receiver survived a long wait on 40 instructions of fuel, so \
         parking cost it nothing — state: {:?}",
        sup.state_of(receiver)
    );
}

/// **Nothing left to deliver is a reported deadlock, not a spin.**
///
/// A receiver with no sender must be named as stuck. Silently settling would
/// make a deadlocked switch read as a finished one.
#[test]
fn a_receiver_with_no_sender_is_a_reported_deadlock() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 3);
    let lonely = spawn(&mut sup, &mut sys, blue("receive()"), quantum(50));
    let rounds = sup.run_to_quiescence(&mut sys, 500);

    assert!(
        rounds < 500,
        "the scheduler must stop rather than spin on a deadlock (ran {rounds} rounds)"
    );
    assert!(
        sup.events
            .iter()
            .any(|e| matches!(e, Event::Deadlocked { blocked } if blocked.contains(&lonely))),
        "the deadlock must be reported and name the stuck process: {:?}",
        sup.events
    );
    assert!(sup.state_of(lonely).is_some_and(ProcState::is_blocked));
}

/// Anti-vacuity for the test above: the SAME program with a sender must NOT
/// report a deadlock. Otherwise the deadlock check could be firing
/// unconditionally.
#[test]
fn a_receiver_with_a_sender_is_not_reported_as_deadlocked() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 3);
    let r = spawn(&mut sup, &mut sys, blue("receive()"), quantum(50));
    spawn(
        &mut sup,
        &mut sys,
        blue(&format!("send({}, 1)", r.0)),
        quantum(50),
    );
    sup.run_to_quiescence(&mut sys, 200);

    assert!(
        !sup.events.iter().any(|e| matches!(e, Event::Deadlocked { .. })),
        "a satisfiable wait must not be reported as a deadlock: {:?}",
        sup.events
    );
}

// ---------------------------------------------------------------------------
// Ordering, identity, and restart
// ---------------------------------------------------------------------------

/// Messages arrive in send order. A router that reorders is a router that
/// delivers a call teardown before the call setup.
#[test]
fn messages_arrive_in_send_order() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 3);

    // `receive() * 10 + receive()` reads two messages; with FIFO the first
    // received is the tens digit. 1 then 2 gives 12, reordering gives 21.
    let receiver = spawn(
        &mut sup,
        &mut sys,
        blue("receive() * 10 + receive()"),
        quantum(50),
    );
    spawn(
        &mut sup,
        &mut sys,
        blue(&format!("send({p}, 1)\nsend({p}, 2)", p = receiver.0)),
        quantum(50),
    );
    sup.run_to_quiescence(&mut sys, 200);

    assert_eq!(
        sup.state_of(receiver).and_then(ProcState::done_int),
        Some(12),
        "FIFO: 1 then 2. A 21 here means the mailbox reordered."
    );
}

/// `self()` is the running process, which is what lets a request carry a
/// reply address — the whole basis of a call/response protocol.
#[test]
fn self_is_the_running_process() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 3);
    let a = spawn(&mut sup, &mut sys, blue("self()"), quantum(50));
    let b = spawn(&mut sup, &mut sys, blue("self()"), quantum(50));
    sup.run_to_quiescence(&mut sys, 100);

    assert_eq!(sup.state_of(a).and_then(ProcState::done_int), Some(a.0 as i64));
    assert_eq!(sup.state_of(b).and_then(ProcState::done_int), Some(b.0 as i64));
    assert_ne!(a.0, b.0, "two processes must not share a pid");
}

/// A request/reply round trip: the client sends its own pid, the server
/// replies to it. This is the shape every telephony and trading protocol is
/// assembled from, and it needs `self`, `send`, `receive` and blocking to all
/// be correct at once.
#[test]
fn a_request_reply_round_trip_completes() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 3);

    // Reserve the server's pid by spawning it first.
    let server = spawn(
        &mut sup,
        &mut sys,
        blue("send(receive(), 42)"),
        quantum(50),
    );
    let client = spawn(
        &mut sup,
        &mut sys,
        blue(&format!("send({}, self())\nreceive()", server.0)),
        quantum(50),
    );
    sup.run_to_quiescence(&mut sys, 300);

    assert_eq!(
        sup.state_of(client).and_then(ProcState::done_int),
        Some(42),
        "the client must receive the server's reply; events: {:?}",
        sup.events
    );
}

/// **A restarted process starts with an empty mailbox.** The messages in
/// flight were addressed to the incarnation that died; replaying them into
/// the fresh one is how a poison message kills a process forever.
#[test]
fn a_restart_clears_the_mailbox() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 5);

    let crasher = spawn(
        &mut sup,
        &mut sys,
        blue("def spin(n)\n  spin(n + 1)\nend\nspin(0)"),
        Budget {
            fuel: Some(60),
            max_depth: None,
            quantum: Some(1_000),
        },
    );
    // Post mail BEFORE it crashes.
    sys.send(crasher, Value::Int(1));
    sys.send(crasher, Value::Int(2));
    assert_eq!(sys.mail_count(crasher), 2, "precondition: mail is queued");
    sup.round(&mut sys);

    assert!(sup.restarts_of(crasher).is_some_and(|n| n > 0), "it must have restarted");
    assert_eq!(
        sys.mail_count(crasher),
        0,
        "the restarted incarnation must not inherit the dead one's mail"
    );
}

/// A send to an unregistered pid is *recorded*, not dropped. A message that
/// vanishes silently is the hardest class of bug in a distributed system.
#[test]
fn a_send_to_an_unknown_pid_is_recorded_not_dropped() {
    let mut sys = System::new();
    sys.send(Pid(9999), Value::Int(5));
    assert_eq!(sys.undeliverable.len(), 1);
    assert_eq!(sys.undeliverable[0].0, Pid(9999));
}

/// Anti-vacuity for `Readiness`: the trait must actually distinguish ready
/// from not-ready, or every wake test above would pass by always waking.
#[test]
fn readiness_distinguishes_a_pending_message_from_none() {
    let mut sys = System::new();
    sys.register(Pid(1));
    assert!(!sys.is_ready(Pid(1)), "an empty mailbox is not ready");
    assert!(!sys.any_pending(), "nothing pending yet");
    sys.send(Pid(1), Value::Int(1));
    assert!(sys.is_ready(Pid(1)), "a queued message makes it ready");
    assert!(sys.any_pending());
}
