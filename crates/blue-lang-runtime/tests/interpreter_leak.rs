//! A dead interpreter that defined a closure gives its memory back.
//!
//! This is the same species of problem as `interpreter_cost.rs` next door:
//! leaking is perfectly *correct* in the only sense the other 600 tests can
//! measure. Every value the program computed is right, every error is raised,
//! every process is supervised. Only a drop-sentinel can see whether the memory
//! behind it was handed back — so this file exists beside the ones that check
//! what the interpreter computes.
//!
//! ## What was leaked, and is not any more
//!
//! Until `tatara-lisp-eval` 0.3.45 this file was a **characterization** gate: it
//! asserted the leak rather than the guarantee, because blue cannot fix a cycle
//! it does not own and a permanently-red test is noise nobody reads. Upstream
//! landed the fix on 2026-08-13 and the inverted arm went red, which is exactly
//! what it was built to do; it is now flipped and reads as the ordinary
//! guarantee.
//!
//! What used to leak: the whole top frame of any interpreter that evaluated a
//! `define` of a function, plus everything bound in it — **~832 B per dead
//! incarnation**. This file never re-derived that byte figure; it observes the
//! *shape*, which is the part that has to hold for the number to mean anything.
//! `Interpreter::fork` multiplied it — `blue-lang-proc` forks per spawned
//! process and the test runner forks per test, so a supervisor restarting a
//! child in a loop leaked once per restart, forever.
//!
//! ## The cycle, and what breaks it
//!
//! The structure that made the cycle is unchanged, and is *supposed* to be —
//! it is what makes a closure a closure:
//!
//! | piece | where (0.3.45) |
//! |---|---|
//! | `Frame { bindings: Mutex<HashMap<Arc<str>, Value>> }` | `env.rs` |
//! | `Value::Closure(Arc<Closure>)` | `value.rs` |
//! | `Closure { captured_env: Env }` | `value.rs` |
//! | `Env { frames: Vec<Arc<Frame>> }` | `env.rs` |
//! | `sf_define` builds `Closure { captured_env: env.clone() }` then defines it INTO that same env | `eval.rs` |
//!
//! Frame → Value::Closure → Closure → Env → the same `Arc<Frame>`, and refcounts
//! alone can never reach zero on a ring. What changed is that teardown is no
//! longer passive: `impl<H> Drop for Interpreter<H>` (`eval.rs:102`) calls
//! `Env::release_own_frames` (`env.rs:289`), which clears the bindings the
//! interpreter owns and drops the closures out of the ring by hand. 0.3.44
//! contained **zero `Drop` impls**; 0.3.45 contains that one.
//!
//! So the gate now guards a real upstream guarantee rather than recording a
//! known defect. If it goes red again the cycle is back — see the failure
//! message on the second arm.
//!
//! ## What the fix does NOT cover, which matters most to blue
//!
//! `release_own_frames` walks only frames above the env's `write_floor`, and
//! releases one **only when `frame_is_exclusively_ours` can prove** nothing
//! outside this environment can still reach it. Clearing a frame a live closure
//! or a deeper fork is still resolving names through would silently unbind it,
//! which is worse than leaking — so the proof failing leaves the frame exactly
//! as it was. Upstream names the two shapes that fail it: a fork of a fork
//! holding an inherited frame below its own floor, and a closure returned to the
//! embedder that outlives the interpreter.
//!
//! blue is the fleet's heaviest `fork` consumer — `blue-lang-proc` forks per
//! spawned process, the test runner forks per test — so it sits closest to both.
//! This file measures the un-forked case only, which is the one the fix fully
//! covers. **A green run here is not evidence that a forked child reclaims**;
//! nothing in blue measures that yet.

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
/// RED RUN (2026-08-12): the lambda removed, leaving the control's program →
/// this test FAILED with the message below. So it is reading the closure's
/// effect, not merely asserting a flag that is always false.
#[test]
fn a_closure_defined_into_its_own_environment_is_reclaimed() {
    assert!(
        sentinel_reclaimed_after("(define s (sentinel))\n(define (f n) n)"),
        "a frame holding a `define`d function was NOT reclaimed — the closure \
         cycle is back. `Interpreter`'s `Drop` calls `Env::release_own_frames` \
         to break `Frame → Closure → Env → Frame` at teardown; if that impl \
         was removed, weakened, or is no longer reached for this shape, the \
         ~832 B-per-dead-incarnation leak has returned and `fork` multiplies \
         it once per spawned process and once per test."
    );
}
