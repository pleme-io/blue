//! A dead interpreter that defined a closure never gives its memory back.
//!
//! This is a **characterization** gate, not a correctness one, and it is the
//! same species of problem as `interpreter_cost.rs` next door: leaking is
//! perfectly *correct* in the only sense the other 600 tests can measure.
//! Every value the program computed is right, every error is raised, every
//! process is supervised. Only a drop-sentinel can see that the memory behind
//! it was never handed back — so this file exists beside the ones that check
//! what the interpreter computes.
//!
//! ## What is leaked (measured 2026-08-12)
//!
//! The whole top frame of any interpreter that evaluated a `define` of a
//! function, plus everything bound in it. The diagnosis put that at **~832 B
//! per dead incarnation**; this file does not re-derive the byte figure — it
//! observes the *shape*, which is the part that has to hold for the number to
//! mean anything. `Interpreter::fork` multiplies it: `blue-lang-proc` forks
//! per spawned process and the test runner forks per test, so a supervisor
//! restarting a child in a loop leaks once per restart, forever.
//!
//! ## Why (the cause is entirely upstream)
//!
//! An unbreakable `Arc` cycle in `tatara-lisp-eval`, confirmed structurally in
//! the pinned 0.3.27 source and byte-identical in the 0.3.44 development tree,
//! so no fix has started:
//!
//! | piece | where |
//! |---|---|
//! | `Frame { bindings: Mutex<HashMap<Arc<str>, Value>> }` | `env.rs:62-64` |
//! | `Value::Closure(Arc<Closure>)` | `value.rs:33` |
//! | `Closure { captured_env: Env }` | `value.rs:148` |
//! | `Env { frames: Vec<Arc<Frame>> }` | `env.rs:84-108` |
//! | `sf_define` builds `Closure { captured_env: env.clone() }` then defines it INTO that same env | `eval.rs:2051-2058` |
//!
//! Frame → Value::Closure → Closure → Env → the same Arc<Frame>. The crate
//! contains **zero `Weak` and zero `Drop` impls**, so there is nothing that
//! could break the cycle at teardown even in principle. Every actual fix is
//! upstream; blue's only leverage is this gate.
//!
//! ## The second assertion is deliberately INVERTED
//!
//! `a_closure_defined_into_its_own_environment_is_never_reclaimed` asserts the
//! leak **as it currently is** — that the sentinel did *not* drop. That is why
//! this file is green rather than red: a red test in the tree is noise nobody
//! reads, and blue cannot fix a cycle it does not own.
//!
//! **When upstream breaks the cycle, THIS TEST WILL FAIL.** That is the point
//! of it. The correct response is to **flip the assertion to `assert!(…)` and
//! delete this paragraph** — turning the tripwire into the ordinary guarantee.
//! The incorrect response is to weaken it: deleting the test, `#[ignore]`-ing
//! it, or relaxing it to "either outcome is fine" throws away the only thing
//! in the fleet that will notice the day the fix lands.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::Value;

/// Flips its flag when reclaimed. The whole probe.
///
/// Deliberately not a `#[global_allocator]`: that is process-wide per test
/// binary while cargo runs tests on parallel threads, so an allocation counter
/// would measure every *other* test in this file too. A drop sentinel measures
/// exactly one object and needs no global state.
struct Sentinel(Arc<AtomicBool>);

impl Drop for Sentinel {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
    }
}

/// Run `src` in a real blue interpreter that can mint one `Sentinel`, drop the
/// interpreter, and report whether the sentinel came back.
///
/// The closure captures only the `Arc<AtomicBool>`, never a `Sentinel`, so the
/// registry surviving in a fork cannot itself hold the probe alive — the only
/// strong reference is the one the program binds.
fn sentinel_reclaimed_after(src: &str) -> bool {
    let flag = Arc::new(AtomicBool::new(false));
    {
        let mut interp = blue_lang_runtime::interpreter_hostless();
        let f = Arc::clone(&flag);
        interp.register_fn(
            "sentinel",
            Arity::Exact(0),
            move |_args: &[Value], _h: &mut (), _span| {
                Ok(Value::Foreign(Arc::new(Sentinel(Arc::clone(&f)))))
            },
        );

        let forms = tatara_lisp::read_spanned(src).expect("read");
        let last = interp.eval_program(&forms, &mut ()).expect("eval");
        drop(last);
    }
    flag.load(Ordering::SeqCst)
}

/// CONTROL — an interpreter holding a plain value DOES give it back.
///
/// Without this arm the characterization below is vacuous: a probe that could
/// never observe reclamation at all — a sentinel held by the closure, a flag
/// read before the drop — would report "leaked" just as happily for a fixed
/// runtime as for a broken one. This arm is what makes the other one evidence.
///
/// RED RUN (2026-08-12): `std::mem::forget(interp)` added to the helper, so
/// nothing is ever reclaimed →
/// `a_dead_interpreter_reclaims_a_value_it_alone_holds` FAILED with the message
/// below, while the characterization arm stayed green. Reverted; both green.
#[test]
fn a_dead_interpreter_reclaims_a_value_it_alone_holds() {
    assert!(
        sentinel_reclaimed_after("(define s (sentinel))"),
        "a value bound in a dead interpreter's own frame was not dropped, and \
         that frame holds no closure — so this is not the upstream cycle. \
         Either the probe stopped observing reclamation (in which case the \
         leak test below proves nothing) or something new retains the whole \
         environment."
    );
}

/// CHARACTERIZATION — one `define` of a function and the frame never dies.
///
/// The only difference from the control is `(define (f n) n)`, which nothing
/// else in the program refers to. Binding it is enough: `sf_define` captures
/// the environment into the closure and then stores the closure back into that
/// environment, and `s` is collateral — it happens to live in the frame the
/// cycle pins.
///
/// **Inverted on purpose. See the module header before touching it.**
///
/// RED RUN (2026-08-12): the lambda removed, leaving the control's program →
/// this test FAILED with the message below. So it is reading the closure's
/// effect, not merely asserting a flag that is always false.
#[test]
fn a_closure_defined_into_its_own_environment_is_never_reclaimed() {
    assert!(
        !sentinel_reclaimed_after("(define s (sentinel))\n(define (f n) n)"),
        "the closure cycle appears to be broken — a frame holding a `define`d \
         function was reclaimed. If tatara-lisp-eval landed the fix, this is \
         GOOD NEWS: flip this to `assert!(…)`, drop the `!`, and delete the \
         inverted-assertion paragraph from the module header. Do not delete or \
         ignore the test."
    );
}
