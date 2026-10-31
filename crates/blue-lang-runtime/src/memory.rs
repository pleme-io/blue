//! The live-byte bound on one evaluation: `max_alloc_bytes` (`docs/SAFETY.md`
//! row 12).
//!
//! An evaluation is charged the bytes its thread allocates and has not freed
//! ([`crate::alloc::Account`]), and past its bound it is refused with a typed
//! `memory-exhausted` refusal, never an abort. Each door says how much it
//! holds an evaluation to ([`crate::ExecutionBounds`]):
//!
//! | door | bound |
//! |---|---|
//! | `blue run`, an appliance, `profile`, `trace`, `blue test` (each test) | `max_alloc_bytes`, unbounded by default |
//! | sessions (`eval`, `repl`, `serve`), live evaluation and the editor's test witness, project rules, a Bluefile | `guest_max_alloc_bytes`, [`GUEST_MAX_ALLOC_BYTES`] by default |
//!
//! The defaults differ for the reason the step bound's do: a run of code its
//! author wrote that holds a lot of memory worked before this bound existed,
//! so bounding it by default would remove working behaviour; a door that runs
//! code it did not write is where a runaway must not take the machine down.
//!
//! **How it refuses.** The root of an evaluation runs on the tree-walker,
//! which checks its interrupt flag at every step. The account is armed with
//! that flag ([`held`]): the allocation that passes the bound sets it, the
//! next step halts, and the door reads the halt as the refusal ([`named`]),
//! fatal so no `rescue` sees it. Each blue process has its own account,
//! inherited bound and all ([`METER`], `blue_lang_proc::Meter`); one that
//! passes it exits a runaway (`ExitReason::memory_exhausted`) at the end of
//! its slice, which its links, monitors and supervisor see.
//!
//! **What it does not bound.** A single native call that asks for more than
//! the machine has still aborts inside the allocator: the bound is checked
//! between steps and between slices, and a refused allocation is an abort
//! (`std::alloc::handle_alloc_error`). The tree-walker's own stack grows by
//! `mmap`, outside the allocator; `max_call_depth` bounds it. A binary that
//! does not install `alloc::Counting` counts nothing, so no bound applies.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use tatara_lisp_eval::{EvalError, Interpreter};

pub use blue_lang_proc::MEMORY_EXHAUSTED;

/// The live bytes a door that runs code it did not write holds one evaluation
/// to by default: 1 GiB, a runaway guard rather than a quota.
pub const GUEST_MAX_ALLOC_BYTES: u64 = 1 << 30;

/// The allocator meter every node holds its processes to their bounds
/// through.
pub const METER: blue_lang_proc::Meter = blue_lang_proc::Meter {
    bound: crate::alloc::bound,
    charged,
    charge: crate::alloc::charge_held,
};

fn charged(held: &mut i64, bound: Option<u64>, f: &mut dyn FnMut()) -> bool {
    let mut account = crate::alloc::Account {
        held: *held,
        bound,
        exhausted: false,
    };
    crate::alloc::charged_to(&mut account, None, f);
    *held = account.held;
    account.exhausted
}

/// `f`, held to `bound` live bytes through `halt`, the interrupt flag of the
/// interpreter it runs on; beside its answer, the bound when it passed it.
///
/// Past the bound the flag is set, so the tree-walker halts at its next step,
/// and cleared again once `f` returns, so the interpreter can run another
/// evaluation.
pub fn held<T>(bound: Option<u64>, halt: &AtomicBool, f: impl FnOnce() -> T) -> (T, Option<u64>) {
    let Some(limit) = bound else {
        return (f(), None);
    };
    let mut account = crate::alloc::Account::new(Some(limit));
    let value = crate::alloc::charged_to(&mut account, Some(halt), f);
    if !account.exhausted {
        return (value, None);
    }
    halt.store(false, Ordering::SeqCst);
    (value, Some(limit))
}

/// [`held`] on `interp`, under an interrupt flag of its own: a fork shares
/// its base's flag, and a refusal must halt this program and no other.
pub fn held_on<H: 'static, T>(
    interp: &mut Interpreter<H>,
    bound: Option<u64>,
    f: impl FnOnce(&mut Interpreter<H>) -> T,
) -> (T, Option<u64>) {
    if bound.is_none() {
        return (f(interp), None);
    }
    let halt = Arc::new(AtomicBool::new(false));
    interp.set_interrupt(Arc::clone(&halt));
    held(bound, &halt, || f(interp))
}

/// The refusal an evaluation past `bound` ends on. Fatal: no `rescue`
/// catches it, as no `rescue` can spend past exhausted fuel.
#[must_use]
pub fn refusal(bound: u64) -> EvalError {
    EvalError::fatal(
        MEMORY_EXHAUSTED,
        blue_lang_proc::memory_budget(bound),
        tatara_lisp::Span::synthetic(),
    )
}

/// `e`, read as the memory refusal when the evaluation running now has
/// passed its bound: whatever stopped it after that (the halt the bound set,
/// usually) is the refusal's doing.
#[must_use]
pub fn named(e: EvalError) -> EvalError {
    if !crate::alloc::exhausted() {
        return e;
    }
    crate::alloc::bound().map_or(e, refusal)
}

/// Is `e` the memory refusal?
#[must_use]
pub fn is_memory_exhausted(e: &EvalError) -> bool {
    matches!(e, EvalError::Fatal { kind, .. } if &**kind == MEMORY_EXHAUSTED)
}
