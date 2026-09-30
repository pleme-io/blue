//! The blue runtime — **one** definition of what a blue program runs against.
//!
//! Before this crate existed, every consumer hand-rolled its own
//! `Interpreter::new()` + `install_primitives(...)` pair — three of them, in
//! three crates — and they had silently drifted: none of them loaded the Lisp
//! stdlib. So `6 % 3` lowered correctly to `(mod 6 3)`, `mod` was genuinely
//! defined, and the program still died with `unbound symbol: mod`, because
//! the definition lived in a stdlib nobody loaded.
//!
//! That is the duplication tax in its usual shape: the bug is not in any one
//! copy, it is in there *being* copies. One function now owns the answer.
//!
//! ## Layers
//!
//! A blue interpreter is built in two layers, and both are required:
//!
//! 1. **Rust primitives** — arithmetic, comparison, list ops, I/O.
//! 2. **The full tatara stdlib** — primitives, higher-order functions
//!    (`map`/`filter`/`fold`), maps, channels, fibers, type-check, and
//!    everything tatara defines in tatara-lisp itself
//!    (`mod`, `rem`, `first`, `inc`, `even?`, the actor and transducer
//!    helpers, …). Loading it is not optional garnish: blue's own operator
//!    lowering depends on it.
//! 3. **blue's own core** ([`stdlib`]) — strings and number conversion, which
//!    tatara-lisp does not have in any form. A Ruby-surface language without
//!    `length` or `upcase` is not usable, and the semantics are Ruby's
//!    (characters, not bytes), which is why they are blue's and not the
//!    substrate's.
//! 4. **JSON** ([`json`]) and **cryptography** ([`crypto`]) — pure
//!    computation, installed unconditionally, so the wasm consumer keeps them.
//! 5. **The host layer** (`sys`, behind the `sys` feature) — every name in it
//!    is a host import.

pub mod crypto;
pub mod docs;
pub mod domain;
pub mod erase;
pub mod hosted;
pub mod inputs;
pub mod json;
pub mod messages;
pub mod pipeline;
pub mod stdlib;
#[cfg(feature = "sys")]
pub mod sys;
pub mod uses;

pub use erase::{erase_types, to_sexps};
pub use inputs::{declarations, install_input_primitives, Declaration, InputError, Inputs};
pub use pipeline::{
    parse, parse_tree_with_depth, parse_with_depth, run, run_with_inputs, Run, RunError,
};
pub use stdlib::install_blue_stdlib;

use tatara_lisp_eval::{install_full_stdlib_with, Interpreter};

/// Build an interpreter with the complete blue runtime installed.
///
/// This is the *only* sanctioned way to obtain one. A caller that builds an
/// `Interpreter` directly gets a partial runtime, and the failure shows up as
/// an unbound symbol at the far end of a program.
pub fn interpreter<H: 'static>(host: &mut H) -> Interpreter<H> {
    let mut interp = Interpreter::new();
    // The FULL substrate, not just `install_primitives`.
    //
    // blue called `install_primitives` + `install_lisp_stdlib_with` and got
    // neither `install_hof` nor `install_map` — so `map`, `filter`, `fold` and
    // every map literal were UNBOUND SYMBOLS. A language with no higher-order
    // functions, in a workspace whose whole surface is Ruby's.
    //
    // Same shape as the stdlib gap this crate was created to fix: the substrate
    // has layers, and naming them one at a time is how one gets missed. Call
    // the composed installer.
    install_full_stdlib_with(&mut interp, host);
    // Layer 3: blue's own core — strings and number conversion, which
    // tatara-lisp does not carry at all. See `stdlib` for why the
    // character-counting semantics are blue's rather than the substrate's.
    stdlib::install_blue_stdlib(&mut interp);
    // Layer 4: blue's JSON surface — parse, stringify, read. Pure
    // computation, no host imports, so it is installed unconditionally; the
    // `wasm32-unknown-unknown` consumer keeps it. See `json` for why objects
    // arrive as alists rather than Maps.
    json::install_json_stdlib(&mut interp);
    // Layer 4b: cryptography — BLAKE3 and Ed25519. Pure for the same reason
    // JSON is: a deterministic function of its arguments, with the keypair's
    // seed supplied by the caller rather than drawn from an entropy source,
    // so it lowers to no import and the wasm consumer keeps it. See `crypto`.
    crypto::install_crypto_stdlib(&mut interp);
    // Layer 5: the host-side system surface — process, filesystem, env,
    // clock. Feature-gated: every sys primitive is a host import, so the
    // wasm consumer (which builds with `sys` OFF) keeps its zero-host-import
    // surface by construction. Only the CLI turns it on.
    #[cfg(feature = "sys")]
    sys::install_sys_stdlib(&mut interp);
    // Last, so installing the stdlib is not metered against the program.
    apply_execution_bounds(&mut interp);
    interp
}

/// The execution bounds every interpreter this crate builds runs under.
static EXECUTION_BOUNDS: std::sync::OnceLock<ExecutionBounds> = std::sync::OnceLock::new();

/// How much a blue program may do before it is refused: nested calls and
/// evaluation steps.
///
/// Both are BOUNDS in the sense `blue-lang-cli`'s `config` module admits: a
/// terminating program under bounds above its cost returns the same value, and
/// one that exceeds either is refused with a catchable `depth-exceeded` or
/// `fuel-exhausted` error naming the limit and the function — never a process
/// abort, which is what exceeding the host stack was before tatara-lisp-eval
/// 0.3.63. The walker and the VM run under the same bounds and refuse with the
/// same message.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ExecutionBounds {
    /// Nested (non-tail) calls alive at once. Tail calls do not count.
    pub max_call_depth: usize,
    /// Evaluation steps per run; `None` is unbounded.
    pub max_steps: Option<usize>,
}

impl ExecutionBounds {
    /// tatara-lisp-eval's VM defaults, by name, for both executors: depth at
    /// `DEFAULT_MAX_DEPTH`, steps at `DEFAULT_FUEL`. A run that needs more
    /// says so through `BlueConfig`; `max_steps: nil` lifts the step bound.
    pub const DEFAULT: Self = Self {
        max_call_depth: tatara_lisp_eval::vm::DEFAULT_MAX_DEPTH,
        max_steps: Some(tatara_lisp_eval::vm::DEFAULT_FUEL),
    };
}

/// Name the bounds for this process. The CLI calls this once with the resolved
/// `BlueConfig`, before any interpreter is built; an embedder that never calls
/// it runs under [`ExecutionBounds::DEFAULT`]. Only the first call counts,
/// like `sys::set_program_args`.
pub fn set_execution_bounds(bounds: ExecutionBounds) {
    let _ = EXECUTION_BOUNDS.set(bounds);
}

/// The bounds interpreters are built with.
#[must_use]
pub fn execution_bounds() -> ExecutionBounds {
    EXECUTION_BOUNDS
        .get()
        .copied()
        .unwrap_or(ExecutionBounds::DEFAULT)
}

fn apply_execution_bounds<H: 'static>(interp: &mut Interpreter<H>) {
    let b = execution_bounds();
    // No quantum, so the tree-walker refuses nothing of this budget.
    let _ = interp.set_budget(tatara_lisp_eval::vm::Budget {
        fuel: b.max_steps,
        max_depth: Some(b.max_call_depth),
        quantum: None,
    });
}

/// The prebuilt hostless substrate, built once per process.
///
/// **Measured 2026-08-01, and this is the entire reason the fork exists.**
/// Profiling a trivial blue program found the run dominated by ONE thing:
///
/// ```text
/// parse                     9.6 µs
/// check                     1.6 µs
/// interpreter_hostless()  5 820 µs   <- 98.4% of the run
/// ```
///
/// Splitting that further: `Interpreter::new()` is 24 µs and
/// `install_full_stdlib_with` is the rest — the stdlib was being rebuilt from
/// scratch on every single `run()`, and blue's whole surface (`map`, `filter`,
/// string ops) lives in it, so no program could avoid the cost.
///
/// `fork` already existed upstream for exactly this, and blue simply was not
/// using it. tatara-lisp-eval's own `fork_cost.rs` opens with *"cheapness is
/// the entire reason it exists"* — the capability was built, documented and
/// guarded, and the consumer kept paying full price beside it.
///
/// | | per call |
/// |---|---|
/// | rebuild (`Interpreter::new` + `install_full_stdlib_with`) | **9.03 ms** |
/// | `fork()` of a prebuilt base | **0.102 ms** |
///
/// **88× on the dominant cost.** This is purgatory's computation-layer clause
/// made real: the stdlib is the most-reused computation in the language, and
/// it was being discarded and recomputed rather than resurrected.
///
/// Isolation is `fork`'s contract, not an assumption made here — its
/// correctness gates live upstream in `fork.rs`, and `fork_cost.rs` guards
/// against a future change that deep-copies (which would keep every
/// correctness test green while silently restoring the cost this removes).
static HOSTLESS_BASE: std::sync::LazyLock<std::sync::Mutex<Interpreter<()>>> =
    std::sync::LazyLock::new(|| std::sync::Mutex::new(interpreter(&mut ())));

/// The common host-free case.
///
/// Forks the process-wide base rather than rebuilding the stdlib. Falls back to
/// a full build if the lock is poisoned: a poisoned lock means another thread
/// panicked mid-fork, and answering a correct-but-slow interpreter beats
/// propagating someone else's panic into an unrelated caller.
pub fn interpreter_hostless() -> Interpreter<()> {
    let mut interp = match HOSTLESS_BASE.lock() {
        Ok(base) => base.fork(),
        Err(_) => interpreter(&mut ()),
    };
    // Again after the fork: the base may have been built before the bounds
    // were named, and a fork inherits whatever its base had.
    apply_execution_bounds(&mut interp);
    interp
}

/// Lift spanless forms into what the evaluator eats.
///
/// **No longer on the `blue run` path, and that is the point.**
/// [`erase::erase_types`] now takes and returns `Spanned`, so
/// `pipeline::run_in_surface` hands the evaluator the *parser's own* tree with
/// the author's positions on it — there is nothing left to lift. This
/// function survives for a caller that genuinely holds spanless `Sexp` and
/// has no position to preserve, and as the subject of the two tests below
/// that pin why the hop it replaced was unsafe.
///
/// `Interpreter::eval_program` takes `&[Spanned]`; blue's stages produced
/// `Sexp`. Two callers bridged that gap by *printing the tree and reading it
/// back* — `forms.map(ToString::to_string).join("\n")` into
/// `tatara_lisp::read_spanned`. Both stopped, and the round trip is gone from
/// the pipeline.
///
/// **Why it had to go.** Printing a tree we already hold and re-parsing it puts
/// the reader's lexer between blue and its own output, for nothing — and the
/// printer and the reader are **not inverses**. `Atom::Str`'s `Display` escapes
/// its payload and its own docs explain at length why; the `Atom::Symbol` arm
/// is a bare `write_str`. So a symbol whose text carries a separator prints as
/// several tokens and reads back as several symbols: a well-formed tree with a
/// different meaning, no error raised. Measured 2026-08-02 —
/// `pipeline::tests::the_round_trip_is_not_the_identity_in_general` pins which
/// separators are silent and which are loud. The only thing that kept this from
/// biting was blue happening not to emit those bytes. A stage that never
/// serialises cannot be mis-read.
///
/// **What is given up: spans.** The old path's spans pointed into the
/// re-printed lisp text, a buffer no human ever wrote and no diagnostic could
/// usefully cite — they were positions in blue's own output, not in the
/// author's source. `Span::synthetic` says the same thing honestly.
///
/// **Carrying real blue-source spans through erasure was the separate piece of
/// work, and it is done — but NOT the way this doc predicted.** It said the
/// work "would start from `Spanned::from_sexp_at`". It did not, and could not:
/// `from_sexp_at` is a *lift*, stamping ONE span across a whole subtree, so
/// starting there would have replaced a tree of synthetic spans with a tree of
/// identical wrong ones. The actual shape was to stop projecting in the first
/// place — erasure walks `Spanned` and keeps each node's own span, because it
/// only ever deletes (see [`erase`]). **A pointer at the nearest-looking API is
/// how a reader is sent to the wrong starting point**; the note is corrected
/// here rather than deleted, because the wrong lead was load-bearing enough to
/// be worth naming.
#[must_use]
pub fn lower_to_spanned(forms: &[tatara_lisp::Sexp]) -> Vec<tatara_lisp::Spanned> {
    forms
        .iter()
        .map(tatara_lisp::Spanned::from_sexp_synthetic)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tatara_lisp_eval::Value;

    fn eval(src: &str) -> Value {
        let forms = tatara_lisp::read_spanned(src).expect("read");
        let mut interp = interpreter_hostless();
        interp.eval_program(&forms, &mut ()).expect("eval")
    }

    /// Every layer is present. A test that only checked layer 1 is exactly
    /// what let the stdlib gap survive.
    #[test]
    fn both_layers_are_installed() {
        // Layer 1: a Rust primitive.
        assert!(matches!(eval("(+ 1 2)"), Value::Int(3)));
        // Layer 2: a stdlib definition, which is the layer that was missing.
        assert!(matches!(eval("(mod 7 3)"), Value::Int(1)));
        assert!(matches!(eval("(inc 41)"), Value::Int(42)));
        assert!(matches!(eval("(first (list 9 8))"), Value::Int(9)));
        // Layer 3: blue's own core — string and number conversion.
        assert!(matches!(eval(r#"(length "héllo")"#), Value::Int(5)));
        // Layer 4: the JSON surface.
        assert!(matches!(
            eval(r#"(json_parse "{\"outcome\":\"ok\"}")"#),
            Value::List(_)
        ));
        // Layer 4b: cryptography.
        assert!(matches!(eval(r#"(blake3_hex "")"#), Value::Str(_)));
    }

    /// Anti-vacuity: a bare interpreter really does LACK layer 2, so the test
    /// above is measuring the runtime's contribution and not a property the
    /// interpreter has for free.
    #[test]
    fn a_bare_interpreter_lacks_the_stdlib() {
        let forms = tatara_lisp::read_spanned("(mod 7 3)").expect("read");
        let mut bare = Interpreter::new();
        tatara_lisp_eval::install_primitives(&mut bare);
        assert!(
            bare.eval_program(&forms, &mut ()).is_err(),
            "if a bare interpreter already resolved `mod`, this crate would be measuring nothing"
        );
    }
}
