//! **Processes share nothing.** The claim, tested directly.
//!
//! Supervision keeps a system up; isolation is what makes *let it crash* a
//! guarantee rather than a hope. Without it a crashed process restarts into the
//! globals that killed it, and a sibling's mutation is visible across what is
//! supposed to be a process boundary.
//!
//! Two mechanisms, one test each: a private interpreter per process, and a deep
//! copy at every send.

use std::sync::Arc;

use blue_lang_proc::{
    deep_copy, install_process_primitives, Pid, ProcState, Strategy, Supervisor, System,
};
use tatara_lisp_eval::vm::{compile_program, Budget, Chunk};
use tatara_lisp_eval::{install_lisp_stdlib_with, install_primitives, Interpreter, Value};

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

fn spawn(sup: &mut Supervisor<System>, sys: &mut System, chunk: Arc<Chunk>, b: Budget) -> Pid {
    let pid = sup.spawn(chunk, b, system_interp);
    sys.register(pid);
    pid
}

fn quantum(q: usize) -> Budget {
    Budget::preemptive(q)
}

/// **A definition in one process is invisible to another.**
///
/// Both processes define `secret`, with different values, and each must see its
/// own. A shared interpreter would make the second definition overwrite the
/// first and one of these would read the other's value.
#[test]
fn a_definition_in_one_process_is_invisible_to_another() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 3);

    let a = spawn(
        &mut sup,
        &mut sys,
        blue("def secret()\n  111\nend\nsecret()"),
        quantum(50),
    );
    let b = spawn(
        &mut sup,
        &mut sys,
        blue("def secret()\n  222\nend\nsecret()"),
        quantum(50),
    );
    sup.run_to_quiescence(&mut sys, 200);

    assert_eq!(
        sup.state_of(a).and_then(ProcState::done_int),
        Some(111),
        "process a must see its OWN definition"
    );
    assert_eq!(
        sup.state_of(b).and_then(ProcState::done_int),
        Some(222),
        "process b must see its own"
    );
}

/// **A process cannot see a name another process defined.** The stronger form:
/// not merely "does not overwrite" but "is not visible at all".
///
/// `a` defines `only_in_a`; `b` calls it and must fail with an unbound symbol.
#[test]
fn a_process_cannot_reach_a_name_defined_in_another() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 0);

    let a = spawn(
        &mut sup,
        &mut sys,
        blue("def only_in_a()\n  1\nend\nonly_in_a()"),
        quantum(50),
    );
    let b = spawn(&mut sup, &mut sys, blue("only_in_a()"), quantum(50));
    sup.run_to_quiescence(&mut sys, 200);

    assert_eq!(
        sup.state_of(a).and_then(ProcState::done_int),
        Some(1),
        "a must succeed"
    );
    let state = sup.state_of(b).expect("b exists");
    assert!(
        state.exit_reason().is_some(),
        "b must FAIL — the name is not in its environment. Got {state:?}"
    );
}

/// **A restart discards the process's globals.** This is what makes
/// let-it-crash a guarantee: the restarted process cannot inherit the state
/// that killed it.
///
/// Asserted on the BINDING, not on a counter. The first version of this test
/// checked `interpreters_built`, which is incremented next to the rebuild
/// rather than by it — so removing the rebuild left the test green. A counter
/// proves a rebuild was *requested*; only the absent binding proves the old
/// environment is gone.
#[test]
fn a_restart_discards_the_processs_bindings() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 2);

    // Defines `poisoned`, then runs away. The budget is set so the crash lands
    // AFTER the definition.
    let pid = spawn(
        &mut sup,
        &mut sys,
        blue("def poisoned()\n  1\nend\ndef spin(n)\n  spin(n + 1)\nend\nspin(0)"),
        Budget {
            fuel: Some(120),
            max_depth: None,
            quantum: Some(1_000),
        },
    );
    sup.round(&mut sys);

    assert!(
        sup.restarts_of(pid).is_some_and(|n| n > 0),
        "it must have restarted"
    );
    assert_eq!(
        sup.proc_binds(pid, "poisoned"),
        Some(false),
        "the restarted incarnation must NOT inherit the crashed one's bindings"
    );
}

/// Anti-vacuity for the test above: the binding really is present before the
/// crash, so its absence afterwards is the restart's doing and not a program
/// that never defined it.
#[test]
fn the_binding_is_present_before_the_crash() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 0);
    let pid = spawn(
        &mut sup,
        &mut sys,
        blue("def poisoned()\n  1\nend\npoisoned()"),
        quantum(50),
    );
    sup.run_to_quiescence(&mut sys, 100);
    assert_eq!(
        sup.proc_binds(pid, "poisoned"),
        Some(true),
        "a completed process DOES hold its own definition — so the absence in \
         the restart test measures the restart"
    );
}

/// The cost of isolation is reported, not hidden: one interpreter per process.
#[test]
fn the_cost_of_isolation_is_counted() {
    let mut sys = System::new();
    let mut sup: Supervisor<System> = Supervisor::new(Strategy::OneForOne, 3);
    assert_eq!(sup.interpreters_built, 0);
    for _ in 0..4 {
        spawn(&mut sup, &mut sys, blue("1"), quantum(50));
    }
    assert_eq!(
        sup.interpreters_built, 4,
        "one per process — the same trade the test framework makes, and visible"
    );
}

// ---------------------------------------------------------------------------
// deep copy on send
// ---------------------------------------------------------------------------

/// A copied list must not share its allocation with the original.
#[test]
fn a_copied_list_shares_no_allocation_with_the_original() {
    let inner = Value::List(Arc::new(vec![Value::Int(1), Value::Int(2)]));
    let original = Value::List(Arc::new(vec![inner, Value::Int(3)]));
    let copy = deep_copy(&original);

    let (Value::List(a), Value::List(b)) = (&original, &copy) else {
        panic!("both must be lists");
    };
    assert!(
        !Arc::ptr_eq(a, b),
        "the outer allocation must be fresh, or the two processes share it"
    );
    let (Value::List(ai), Value::List(bi)) = (&a[0], &b[0]) else {
        panic!("both must nest a list");
    };
    assert!(
        !Arc::ptr_eq(ai, bi),
        "the NESTED allocation must be fresh too — a shallow copy shares it"
    );
}

/// The copy preserves the value. An isolating copy that changed the data would
/// be worse than sharing.
#[test]
fn a_deep_copy_preserves_the_value() {
    let v = Value::List(Arc::new(vec![
        Value::Int(7),
        Value::Str("hi".into()),
        Value::Bool(true),
        Value::List(Arc::new(vec![Value::Int(8)])),
    ]));
    let copy = deep_copy(&v);
    // Compared by rendering, since `Value` has no PartialEq.
    assert_eq!(format!("{copy:?}"), format!("{v:?}"));
}

/// **A closure is refused rather than shared.** A closure captures its defining
/// environment, so sending one would hand a second process a live reference
/// into the first's globals — exactly the leak separate interpreters removed.
#[test]
fn a_closure_is_refused_rather_than_shared() {
    let mut sys = System::new();
    // max_restarts = 0: the crash must be TERMINAL, or the supervisor revives
    // the receiver and the final state is `Blocked` rather than the crash.
    let mut sup = Supervisor::new(Strategy::OneForOne, 0);

    // The receiver CALLS whatever it is handed. If a closure crossed the
    // boundary the call succeeds and returns 1 — which would mean process b is
    // executing code closed over process a's environment.
    //
    // The first version of this test only checked that the result was not an
    // integer, which a shared closure also satisfies: the test was green either
    // way. Calling it is what distinguishes.
    let receiver = spawn(
        &mut sup,
        &mut sys,
        blue("def call_it(f)\n  f()\nend\ncall_it(receive())"),
        quantum(50),
    );
    spawn(
        &mut sup,
        &mut sys,
        blue(&format!("def make()\n  1\nend\nsend({}, make)", receiver.0)),
        quantum(50),
    );
    sup.run_to_quiescence(&mut sys, 300);

    let state = sup.state_of(receiver).expect("receiver exists");
    assert!(
        state.exit_reason().is_some(),
        "calling the received value must FAIL — a closure must not cross the \
         boundary. Got {state:?}"
    );
    assert_ne!(
        state.done_int(),
        Some(1),
        "if this were 1, process b ran a closure over process a's environment"
    );
}

/// Sending still works for ordinary data, so the refusal above is narrow.
#[test]
fn ordinary_data_still_crosses_the_boundary() {
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 3);
    let receiver = spawn(&mut sup, &mut sys, blue("receive()"), quantum(50));
    spawn(
        &mut sup,
        &mut sys,
        blue(&format!("send({}, 5 * 9)", receiver.0)),
        quantum(50),
    );
    sup.run_to_quiescence(&mut sys, 200);
    assert_eq!(
        sup.state_of(receiver).and_then(ProcState::done_int),
        Some(45)
    );
}
