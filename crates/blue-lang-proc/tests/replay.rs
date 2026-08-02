//! **The schedule is replayable.** The claim, tested against a recorded trace.
//!
//! This is the one dimension where blue's runtime is not merely a rearrangement
//! of the BEAM's choices but a place the BEAM cannot go. Erlang's SMP schedulers
//! interleave by wall clock across OS threads, so the same inputs on the same
//! machine produce different interleavings run to run — which is why replaying a
//! distributed Erlang bug has been an open want for decades and why tools like
//! Concuerror have to *simulate* a scheduler rather than record the real one.
//!
//! blue's scheduler has none of the ingredients that cost the BEAM this: one
//! thread, a `Vec` walked by index, a fixed reduction quantum, no clock and no
//! randomness. So determinism is true by construction — and "true by
//! construction" is an argument, not a proof, which is what this file is for.
//!
//! `blue-lang-bidama`'s `Model::BLUE_TODAY` records `Interleaving` as
//! `Replayable` on the strength of this suite, and the last test here asserts
//! that field — so the ledger and the scheduler cannot drift apart in either
//! direction. Rounding *down* is not the safe option: it would hide the one
//! dimension where blue is ahead of the BEAM rather than merely different.

use std::sync::{Arc, Mutex};

use blue_lang_proc::{forking, install_process_primitives, Pid, Strategy, Supervisor, System};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::vm::{compile_program, Budget, Chunk};
use tatara_lisp_eval::{install_full_stdlib_with, Interpreter, Value};

/// The interleaving, as the processes themselves observed it: one entry per
/// `mark(tag)` call, in the order the scheduler actually ran them.
type Trace = Arc<Mutex<Vec<i64>>>;

/// Note the composed installer. Naming the layers one at a time is how this
/// workspace lost `map`, `filter` and `fold`; the repo's CLAUDE.md records it
/// as a defect, not a style note.
fn interp_writing_to(trace: &Trace) -> Interpreter<System> {
    let mut i = Interpreter::new();
    let mut sys = System::new();
    install_full_stdlib_with(&mut i, &mut sys);
    install_process_primitives(&mut i);

    let sink = Arc::clone(trace);
    i.register_fn(
        "mark",
        Arity::Exact(1),
        move |args: &[Value], _h: &mut System, _span| {
            if let Value::Int(tag) = args[0] {
                sink.lock().unwrap().push(tag);
            }
            Ok(Value::Nil)
        },
    );
    i
}

fn chunk(src: &str) -> Arc<Chunk> {
    let forms = blue_lang_syntax::parse_program(src).expect("parse blue");
    let text = forms
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join("\n");
    let spanned = tatara_lisp::read_spanned(&text).expect("read");
    Arc::new(compile_program(&spanned).expect("compile"))
}

/// `marks` straight-line calls, each tagged with this process's identity, so
/// the recorded sequence says which process held the CPU at each step.
fn marker_body(tag: i64, marks: usize) -> String {
    let mut src = String::new();
    for _ in 0..marks {
        src.push_str("mark(");
        src.push_str(&tag.to_string());
        src.push_str(")\n");
    }
    src
}

/// Run a fixed three-process system to quiescence and return what happened.
///
/// Spawns through [`forking`], so this suite exercises the supervisor path
/// blue actually recommends rather than a per-process rebuild the docs steer
/// away from.
fn run(quantum: usize) -> Vec<i64> {
    let trace: Trace = Arc::new(Mutex::new(Vec::new()));
    let mut sys = System::new();
    let mut sup = Supervisor::new(Strategy::OneForOne, 3);
    let prototype = Arc::new(interp_writing_to(&trace));

    for tag in 1..=3i64 {
        let pid: Pid = sup.spawn(
            chunk(&marker_body(tag, 6)),
            Budget::preemptive(quantum),
            forking(&prototype),
        );
        sys.register(pid);
    }

    sup.run_to_quiescence(&mut sys, 500);
    let out = trace.lock().unwrap().clone();
    assert!(!out.is_empty(), "the fixture recorded nothing to compare");
    out
}

// ── the proof ──────────────────────────────────────────────────────────────

/// Same program, same scheduler, same interleaving — every run.
///
/// Not "the same results": the same *order*, including where each process was
/// preempted. That is the property the BEAM cannot offer.
#[test]
fn the_same_program_interleaves_identically_on_every_run() {
    let first = run(2);
    for attempt in 1..8 {
        assert_eq!(
            run(2),
            first,
            "run {attempt} interleaved differently — the schedule is not replayable"
        );
    }
}

/// The recorder can tell schedules apart.
///
/// Without this, `the_same_program_interleaves_identically_on_every_run` proves
/// nothing: a trace that always came back `[]`, or that recorded only per-
/// process totals, would compare equal under every scheduler. Changing the
/// quantum changes where preemption falls, so a sensitive recorder must show a
/// different order — and the multiset must be identical, because the same work
/// was done either way.
#[test]
fn a_different_quantum_produces_a_different_interleaving() {
    let fine = run(2);
    let coarse = run(64);

    assert_ne!(
        fine, coarse,
        "the trace cannot distinguish two schedules, so equality proves nothing"
    );

    let mut a = fine.clone();
    let mut b = coarse.clone();
    a.sort_unstable();
    b.sort_unstable();
    assert_eq!(
        a, b,
        "the same work must be done either way — only the order may differ"
    );
}

/// A coarse quantum runs each process to completion in turn; a fine one
/// interleaves them. Pins *how* the schedule responds, so a change that
/// accidentally disabled preemption would fail here rather than quietly make
/// both traces equal.
#[test]
fn a_coarse_quantum_does_not_interleave_and_a_fine_one_does() {
    let coarse = run(64);
    let runs: Vec<i64> = coarse
        .chunks(6)
        .map(|c| {
            assert!(
                c.iter().all(|t| *t == c[0]),
                "a 64-reduction quantum should finish a 6-mark process without \
                 preemption, got {c:?}"
            );
            c[0]
        })
        .collect();
    assert_eq!(runs, vec![1, 2, 3], "and in spawn order");

    let fine = run(2);
    assert!(
        fine.windows(2).any(|w| w[0] != w[1]),
        "a 2-reduction quantum must preempt between marks, got {fine:?}"
    );
}

/// Replay survives a crash and a restart.
///
/// A supervisor that restarts a child is where nondeterminism usually enters —
/// the restart is a new incarnation with a new interpreter, and anything
/// carried over from the dead one (an address, an allocation order, a clock
/// reading) would show up here as a differing trace.
#[test]
fn a_crash_and_restart_replays_identically_too() {
    fn run_with_a_crasher() -> Vec<i64> {
        let trace: Trace = Arc::new(Mutex::new(Vec::new()));
        let mut sys = System::new();
        let mut sup = Supervisor::new(Strategy::OneForOne, 2);
        let prototype = Arc::new(interp_writing_to(&trace));

        for (tag, src) in [
            (1i64, marker_body(1, 4)),
            // Marks, then divides by zero. The supervisor restarts it, and the
            // restart marks again — so the trace spans the failure.
            (2i64, marker_body(2, 2) + "1 / 0\n"),
            (3i64, marker_body(3, 4)),
        ] {
            let _ = tag;
            let pid = sup.spawn(chunk(&src), Budget::preemptive(2), forking(&prototype));
            sys.register(pid);
        }

        sup.run_to_quiescence(&mut sys, 500);
        let out = trace.lock().unwrap().clone();
        assert!(
            out.contains(&2),
            "the crashing process must have run at all"
        );
        out
    }

    let first = run_with_a_crasher();
    for attempt in 1..5 {
        assert_eq!(
            run_with_a_crasher(),
            first,
            "run {attempt} diverged across a restart"
        );
    }
}

// ── the ledger ─────────────────────────────────────────────────────────────

/// The bīdama ledger must agree with what this file proves.
///
/// `Model::BLUE_TODAY` claims `Nondeterministic`. The tests above show the
/// scheduler *is* replayable, so that entry is now a round-DOWN — which the org
/// doctrine treats as the same defect as a round-up, because it discards true
/// signal. This test fails until the ledger is corrected, so the two cannot
/// drift apart in either direction.
#[test]
fn the_bidama_ledger_records_the_interleaving_this_file_demonstrates() {
    use blue_lang_bidama::{Interleaving, Model};

    assert_eq!(
        Model::BLUE_TODAY.interleaving,
        Interleaving::Replayable,
        "the tests in this file demonstrate a replayable schedule; the ledger \
         must say so. Rounding down is not the safe direction — it hides the \
         one dimension where blue is ahead of the BEAM."
    );
}
