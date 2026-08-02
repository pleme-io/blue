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

pub mod erase;
pub mod inputs;
pub mod pipeline;
pub mod stdlib;
pub mod uses;

pub use erase::erase_types;
pub use inputs::{declarations, install_input_primitives, Declaration, InputError, Inputs};
pub use pipeline::{parse, parse_with_depth, run, run_with_inputs, Run, RunError};
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
    interp
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
    match HOSTLESS_BASE.lock() {
        Ok(base) => base.fork(),
        Err(_) => interpreter(&mut ()),
    }
}

/// Lift blue's emitted forms into what the evaluator eats. **The one door.**
///
/// `Interpreter::eval_program` takes `&[Spanned]`; blue's stages produce
/// `Sexp`. Two callers bridged that gap by *printing the tree and reading it
/// back* — `forms.map(ToString::to_string).join("\n")` into
/// `tatara_lisp::read_spanned`. Both now call this instead, and the round trip
/// is gone.
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
/// author's source. `Span::synthetic` says the same thing honestly. Carrying
/// real blue-source spans through erasure is a separate piece of work and
/// would start from `Spanned::from_sexp_at`, not from a printer.
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

    /// Both layers are present. A test that only checked layer 1 is exactly
    /// what let the stdlib gap survive.
    #[test]
    fn both_layers_are_installed() {
        // Layer 1: a Rust primitive.
        assert!(matches!(eval("(+ 1 2)"), Value::Int(3)));
        // Layer 2: a stdlib definition, which is the layer that was missing.
        assert!(matches!(eval("(mod 7 3)"), Value::Int(1)));
        assert!(matches!(eval("(inc 41)"), Value::Int(42)));
        assert!(matches!(eval("(first (list 9 8))"), Value::Int(9)));
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
