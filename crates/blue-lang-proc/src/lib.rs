//! Processes and supervision — OTP's structure over blue's scheduler.
//!
//! This is the layer that makes *let it crash* a strategy rather than a
//! slogan, and it is only buildable because two things landed underneath it:
//!
//! - **bounded, catchable failure** — a runaway returns a typed
//!   `VmError::BudgetExhausted` instead of aborting the OS process, so a
//!   supervisor has something to catch;
//! - **preemption** — `Vm::step` parks at a quantum with the frame stack
//!   intact, so one process cannot starve its siblings.
//!
//! Both are the *same reduction counter*, read as a total ceiling and as a
//! per-slice ceiling.
//!
//! ## The isolation this does and does not provide
//!
//! **Stated first, because overstating it would be the easy mistake.** Each
//! process gets its **own `Vm`** — its own value stack, frame stack,
//! handlers and local cells. That is real isolation of *control state*: one
//! process's crash cannot corrupt another's stack, and a runaway is
//! contained.
//!
//! It is **not** BEAM's isolation. Processes share one `Interpreter`, so
//! they share **globals**. A process that mutates a global is visible to its
//! siblings. `theory/BLUE.md` §V records the destination — per-process heaps
//! (`sumika`) with copy-on-send — and that is unbuilt. Until it is, the
//! honest claim is **per-process control-state isolation, shared global
//! state** — which is enough for supervision and *not* enough for
//! let-it-crash to be a safety guarantee.
//!
//! ## Strategy names follow `caixa`, deliberately
//!
//! `caixa-core`'s `Supervisor` kind already carries `estrategia` with
//! `OneForOne` / `OneForAll` / `RestForOne` / `SimpleOneForOne`, plus
//! max-restarts and a restart window. The org rule is one vocabulary per
//! concept, so [`Strategy`] uses those names rather than inventing a second
//! set.

use std::sync::Arc;

use tatara_lisp_eval::vm::{Budget, Chunk, Progress, Vm, VmError};
use tatara_lisp_eval::{Interpreter, Value};

/// A process identifier.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Pid(pub u64);

/// Why a process stopped.
#[derive(Clone, Debug, PartialEq)]
pub enum ExitReason {
    /// Ran to completion.
    Normal,
    /// A typed runtime failure. Carries the rendered error.
    Crashed(String),
    /// The execution budget ran out — a runaway. **This is the case that
    /// was previously an OS-process abort**, and it is the reason
    /// supervision is possible at all.
    Runaway(String),
}

impl ExitReason {
    pub fn is_abnormal(&self) -> bool {
        !matches!(self, ExitReason::Normal)
    }
}

/// No `PartialEq`: `tatara_lisp_eval::Value` does not implement it, and
/// wrapping it in a comparable shim here would invent an equality the
/// runtime does not define. Callers ask the questions they actually mean —
/// [`ProcState::is_runnable`], [`ProcState::done_int`].
#[derive(Clone, Debug)]
pub enum ProcState {
    Runnable,
    Done(Value),
    Exited(ExitReason),
}

impl ProcState {
    pub fn is_runnable(&self) -> bool {
        matches!(self, ProcState::Runnable)
    }

    pub fn is_done(&self) -> bool {
        matches!(self, ProcState::Done(_))
    }

    /// The integer this process produced, if it finished with one.
    pub fn done_int(&self) -> Option<i64> {
        match self {
            ProcState::Done(Value::Int(v)) => Some(*v),
            _ => None,
        }
    }

    pub fn exit_reason(&self) -> Option<&ExitReason> {
        match self {
            ProcState::Exited(r) => Some(r),
            _ => None,
        }
    }
}

/// One process: a program plus its own VM.
pub struct Proc {
    pub pid: Pid,
    /// The code. Retained so a supervisor can restart from a clean VM.
    chunk: Arc<Chunk>,
    vm: Vm,
    budget: Budget,
    pub state: ProcState,
    /// How many times this process has been restarted.
    pub restarts: usize,
}

impl Proc {
    fn new(pid: Pid, chunk: Arc<Chunk>, budget: Budget) -> Self {
        Self {
            pid,
            chunk,
            vm: Vm::with_budget(budget),
            budget,
            state: ProcState::Runnable,
            restarts: 0,
        }
    }

    /// Discard all control state and start over from the same code.
    ///
    /// A fresh `Vm` is the whole restart: there is nothing to unwind,
    /// because the crashed process's stack was never shared.
    fn restart(&mut self) {
        self.vm = Vm::with_budget(self.budget);
        self.state = ProcState::Runnable;
        self.restarts += 1;
    }

    fn is_runnable(&self) -> bool {
        self.state.is_runnable()
    }
}

/// Restart strategy. Names follow `caixa-core`'s `estrategia`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Strategy {
    /// Restart only the process that exited.
    OneForOne,
    /// Restart every child.
    OneForAll,
    /// Restart the exited child and every child declared after it.
    RestForOne,
}

/// A record of what the supervisor did, so a caller can assert on
/// behaviour rather than infer it from final state.
#[derive(Clone, Debug, PartialEq)]
pub enum Event {
    Exited { pid: Pid, reason: ExitReason },
    Restarted { pid: Pid },
    /// Restart intensity exceeded: the supervisor gave up rather than
    /// restarting in a tight loop forever.
    GaveUp { pid: Pid, restarts: usize },
}

/// A supervisor over an ordered set of children.
pub struct Supervisor {
    procs: Vec<Proc>,
    strategy: Strategy,
    /// Maximum restarts of any single child before the supervisor gives up.
    ///
    /// Without this a crash-on-start child restarts forever, which is a
    /// busy loop wearing a supervision tree's clothes.
    max_restarts: usize,
    next_pid: u64,
    pub events: Vec<Event>,
}

impl Supervisor {
    pub fn new(strategy: Strategy, max_restarts: usize) -> Self {
        Self {
            procs: Vec::new(),
            strategy,
            max_restarts,
            next_pid: 1,
            events: Vec::new(),
        }
    }

    /// Add a child. Order matters for [`Strategy::RestForOne`].
    pub fn spawn(&mut self, chunk: Arc<Chunk>, budget: Budget) -> Pid {
        let pid = Pid(self.next_pid);
        self.next_pid += 1;
        self.procs.push(Proc::new(pid, chunk, budget));
        pid
    }

    pub fn state_of(&self, pid: Pid) -> Option<&ProcState> {
        self.procs.iter().find(|p| p.pid == pid).map(|p| &p.state)
    }

    pub fn restarts_of(&self, pid: Pid) -> Option<usize> {
        self.procs.iter().find(|p| p.pid == pid).map(|p| p.restarts)
    }

    /// Is anything still runnable?
    pub fn has_work(&self) -> bool {
        self.procs.iter().any(Proc::is_runnable)
    }

    /// Run one scheduling round: give every runnable process one quantum,
    /// then apply the restart strategy to anything that exited abnormally.
    ///
    /// Round-robin, so a long-running child cannot starve a short one —
    /// that is preemption's contribution, and it holds without any child
    /// cooperating.
    pub fn round<H: 'static>(&mut self, interp: &mut Interpreter<H>, host: &mut H) {
        let mut exited: Vec<(usize, ExitReason)> = Vec::new();

        for idx in 0..self.procs.len() {
            if !self.procs[idx].is_runnable() {
                continue;
            }
            let chunk = self.procs[idx].chunk.clone();
            match self.procs[idx].vm.step(chunk, interp, host) {
                Ok(Progress::Yielded) => {}
                Ok(Progress::Done(v)) => {
                    self.procs[idx].state = ProcState::Done(v);
                    let pid = self.procs[idx].pid;
                    self.events.push(Event::Exited {
                        pid,
                        reason: ExitReason::Normal,
                    });
                }
                Err(e) => {
                    let reason = classify(&e);
                    self.procs[idx].state = ProcState::Exited(reason.clone());
                    let pid = self.procs[idx].pid;
                    self.events.push(Event::Exited {
                        pid,
                        reason: reason.clone(),
                    });
                    exited.push((idx, reason));
                }
            }
        }

        for (idx, reason) in exited {
            if reason.is_abnormal() {
                self.apply_strategy(idx);
            }
        }
    }

    /// Drive rounds until nothing is runnable, or `max_rounds` elapse.
    ///
    /// The bound is a test-and-operator safety net, not a semantic: a
    /// supervision tree that cannot settle should say so rather than spin.
    pub fn run_to_quiescence<H: 'static>(
        &mut self,
        interp: &mut Interpreter<H>,
        host: &mut H,
        max_rounds: usize,
    ) -> usize {
        let mut rounds = 0;
        while self.has_work() && rounds < max_rounds {
            self.round(interp, host);
            rounds += 1;
        }
        rounds
    }

    fn apply_strategy(&mut self, exited_idx: usize) {
        let targets: Vec<usize> = match self.strategy {
            Strategy::OneForOne => vec![exited_idx],
            Strategy::OneForAll => (0..self.procs.len()).collect(),
            Strategy::RestForOne => (exited_idx..self.procs.len()).collect(),
        };

        // Intensity is checked on the CHILD THAT EXITED, not on the
        // siblings a strategy sweeps up: a sibling restarted as collateral
        // has not itself misbehaved.
        if self.procs[exited_idx].restarts >= self.max_restarts {
            let pid = self.procs[exited_idx].pid;
            let restarts = self.procs[exited_idx].restarts;
            self.events.push(Event::GaveUp { pid, restarts });
            return;
        }

        for idx in targets {
            self.procs[idx].restart();
            let pid = self.procs[idx].pid;
            self.events.push(Event::Restarted { pid });
        }
    }
}

fn classify(e: &VmError) -> ExitReason {
    match e {
        VmError::BudgetExhausted { .. } => ExitReason::Runaway(e.to_string()),
        other => ExitReason::Crashed(other.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tatara_lisp_eval::vm::compile_program;

    fn compile(src: &str) -> Arc<Chunk> {
        let forms = tatara_lisp::read_spanned(src).expect("parse");
        Arc::new(compile_program(&forms).expect("compile"))
    }

    fn blue(src: &str) -> Arc<Chunk> {
        let forms = blue_lang_syntax::parse_program(src).expect("parse blue");
        let text = forms.iter().map(|f| f.to_string()).collect::<Vec<_>>().join("\n");
        compile(&text)
    }

    fn interp() -> Interpreter<()> {
        blue_lang_runtime::interpreter_hostless()
    }

    fn preemptive(q: usize) -> Budget {
        Budget::preemptive(q)
    }

    // ---- the payoff: a runaway is contained and restarted -------------

    /// **This is what was impossible before.** A runaway previously aborted
    /// the OS process, so there was nothing to supervise. Now it exits with
    /// a typed reason and the supervisor restarts it.
    #[test]
    fn a_runaway_is_contained_and_restarted() {
        let mut sup = Supervisor::new(Strategy::OneForOne, 3);
        let spin = compile("(define (spin n) (spin (+ n 1))) (spin 0)");
        let pid = sup.spawn(
            spin,
            Budget {
                fuel: Some(2_000),
                max_depth: None,
                quantum: Some(200),
            },
        );
        let mut i = interp();
        sup.run_to_quiescence(&mut i, &mut (), 200);

        assert!(
            sup.events
                .iter()
                .any(|e| matches!(e, Event::Exited { reason: ExitReason::Runaway(_), .. })),
            "the runaway must exit with a Runaway reason: {:?}",
            sup.events
        );
        assert!(
            sup.events.iter().any(|e| matches!(e, Event::Restarted { .. })),
            "the supervisor must have restarted it"
        );
        assert!(sup.restarts_of(pid).unwrap() > 0);
    }

    /// And it must eventually GIVE UP rather than restart forever — a
    /// crash-on-start child otherwise becomes a busy loop in a supervision
    /// tree's clothes.
    #[test]
    fn restart_intensity_stops_an_unfixable_child() {
        let mut sup = Supervisor::new(Strategy::OneForOne, 2);
        let spin = compile("(define (spin n) (spin (+ n 1))) (spin 0)");
        sup.spawn(
            spin,
            Budget {
                fuel: Some(500),
                max_depth: None,
                quantum: Some(100),
            },
        );
        let mut i = interp();
        sup.run_to_quiescence(&mut i, &mut (), 500);

        assert!(
            sup.events.iter().any(|e| matches!(e, Event::GaveUp { .. })),
            "the supervisor must give up: {:?}",
            sup.events
        );
        assert!(!sup.has_work(), "nothing should still be runnable");
    }

    // ---- normal completion -------------------------------------------

    #[test]
    fn a_healthy_process_finishes_and_is_not_restarted() {
        let mut sup = Supervisor::new(Strategy::OneForOne, 3);
        let pid = sup.spawn(blue("1 + 2"), preemptive(50));
        let mut i = interp();
        sup.run_to_quiescence(&mut i, &mut (), 100);

        assert_eq!(sup.state_of(pid).and_then(ProcState::done_int), Some(3));
        assert_eq!(sup.restarts_of(pid), Some(0), "a healthy child must not restart");
    }

    /// Round-robin fairness at the supervisor level: a long child must not
    /// prevent a short one from finishing.
    #[test]
    fn a_long_child_does_not_starve_a_short_one() {
        let mut sup = Supervisor::new(Strategy::OneForOne, 3);
        let long = sup.spawn(
            blue("def loop(n)\n  if n == 0\n    1\n  else\n    loop(n - 1)\n  end\nend\nloop(400)"),
            preemptive(20),
        );
        let short = sup.spawn(blue("2 + 3"), preemptive(20));
        let mut i = interp();

        // One round is enough for the SHORT child; the long one is still going.
        sup.round(&mut i, &mut ());
        assert_eq!(sup.state_of(short).and_then(ProcState::done_int), Some(5));
        assert!(
            sup.state_of(long).is_some_and(ProcState::is_runnable),
            "the long child should still be running"
        );

        sup.run_to_quiescence(&mut i, &mut (), 1000);
        assert_eq!(sup.state_of(long).and_then(ProcState::done_int), Some(1));
    }

    // ---- the three strategies ------------------------------------------

    fn crashing() -> Arc<Chunk> {
        compile("(define (spin n) (spin (+ n 1))) (spin 0)")
    }

    /// Fuel BELOW the quantum, so the crasher exhausts *inside* its first
    /// slice. With fuel above the quantum it merely yields, and a
    /// single-round strategy test would see no exit at all.
    fn tiny_budget() -> Budget {
        Budget {
            fuel: Some(60),
            max_depth: None,
            quantum: Some(1_000),
        }
    }

    #[test]
    fn one_for_one_restarts_only_the_child_that_exited() {
        let mut sup = Supervisor::new(Strategy::OneForOne, 5);
        let a = sup.spawn(blue("1"), preemptive(50));
        let bad = sup.spawn(crashing(), tiny_budget());
        let c = sup.spawn(blue("2"), preemptive(50));
        let mut i = interp();
        sup.round(&mut i, &mut ());

        assert_eq!(sup.restarts_of(bad), Some(1), "the crasher must restart");
        assert_eq!(sup.restarts_of(a), Some(0), "a sibling must NOT restart");
        assert_eq!(sup.restarts_of(c), Some(0), "a sibling must NOT restart");
    }

    #[test]
    fn one_for_all_restarts_every_child() {
        let mut sup = Supervisor::new(Strategy::OneForAll, 5);
        let a = sup.spawn(crashing(), tiny_budget());
        let b = sup.spawn(blue("1"), preemptive(50));
        let c = sup.spawn(blue("2"), preemptive(50));
        let mut i = interp();
        sup.round(&mut i, &mut ());

        assert_eq!(sup.restarts_of(a), Some(1));
        assert_eq!(sup.restarts_of(b), Some(1), "one_for_all must restart siblings");
        assert_eq!(sup.restarts_of(c), Some(1), "one_for_all must restart siblings");
    }

    /// `rest_for_one` restarts the exited child and everything declared
    /// AFTER it — the ones that may depend on it — and leaves the earlier
    /// ones alone.
    #[test]
    fn rest_for_one_restarts_the_child_and_its_successors_only() {
        let mut sup = Supervisor::new(Strategy::RestForOne, 5);
        let before = sup.spawn(blue("1"), preemptive(50));
        let bad = sup.spawn(crashing(), tiny_budget());
        let after = sup.spawn(blue("2"), preemptive(50));
        let mut i = interp();
        sup.round(&mut i, &mut ());

        assert_eq!(sup.restarts_of(before), Some(0), "a predecessor must not restart");
        assert_eq!(sup.restarts_of(bad), Some(1));
        assert_eq!(sup.restarts_of(after), Some(1), "a successor must restart");
    }

    // ---- anti-vacuity --------------------------------------------------

    /// The supervisor must be able to observe a normal exit as normal. If
    /// everything looked abnormal, the restart tests would pass by always
    /// restarting.
    #[test]
    fn a_normal_exit_is_not_treated_as_a_crash() {
        let mut sup = Supervisor::new(Strategy::OneForAll, 5);
        let a = sup.spawn(blue("1"), preemptive(50));
        let b = sup.spawn(blue("2"), preemptive(50));
        let mut i = interp();
        sup.run_to_quiescence(&mut i, &mut (), 100);

        assert!(
            !sup.events.iter().any(|e| matches!(e, Event::Restarted { .. })),
            "a normal exit must not trigger one_for_all: {:?}",
            sup.events
        );
        assert_eq!(sup.restarts_of(a), Some(0));
        assert_eq!(sup.restarts_of(b), Some(0));
    }

    /// One process's crash must not corrupt another's control state — the
    /// isolation claim, tested directly.
    #[test]
    fn a_crash_does_not_disturb_a_siblings_result() {
        let mut sup = Supervisor::new(Strategy::OneForOne, 1);
        let _bad = sup.spawn(crashing(), tiny_budget());
        let good = sup.spawn(
            blue("def sum(n, acc)\n  if n == 0\n    acc\n  else\n    sum(n - 1, acc + n)\n  end\nend\nsum(10, 0)"),
            preemptive(15),
        );
        let mut i = interp();
        sup.run_to_quiescence(&mut i, &mut (), 500);

        assert_eq!(
            sup.state_of(good).and_then(ProcState::done_int),
            Some(55),
            "the healthy child's answer must survive a sibling's crash"
        );
    }

    /// And blue source really does run under supervision — not just
    /// hand-written tatara-lisp.
    #[test]
    fn blue_source_runs_under_supervision() {
        let mut sup = Supervisor::new(Strategy::OneForOne, 3);
        let pid = sup.spawn(
            blue("def fact(n)\n  if n < 2\n    1\n  else\n    n * fact(n - 1)\n  end\nend\nfact(6)"),
            preemptive(30),
        );
        let mut i = interp();
        sup.run_to_quiescence(&mut i, &mut (), 1000);
        assert_eq!(sup.state_of(pid).and_then(ProcState::done_int), Some(720));
    }
}
