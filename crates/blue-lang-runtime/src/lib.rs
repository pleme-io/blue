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
//! 2. **The Lisp stdlib** — everything tatara defines in tatara-lisp itself
//!    (`mod`, `rem`, `first`, `inc`, `even?`, the actor and transducer
//!    helpers, …). Loading it is not optional garnish: blue's own operator
//!    lowering depends on it.

use tatara_lisp_eval::{install_lisp_stdlib_with, install_primitives, Interpreter};

/// Build an interpreter with the complete blue runtime installed.
///
/// This is the *only* sanctioned way to obtain one. A caller that builds an
/// `Interpreter` directly gets a partial runtime, and the failure shows up as
/// an unbound symbol at the far end of a program.
pub fn interpreter<H: 'static>(host: &mut H) -> Interpreter<H> {
    let mut interp = Interpreter::new();
    install_primitives(&mut interp);
    install_lisp_stdlib_with(&mut interp, host);
    interp
}

/// The common host-free case.
pub fn interpreter_hostless() -> Interpreter<()> {
    interpreter(&mut ())
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
        install_primitives(&mut bare);
        assert!(
            bare.eval_program(&forms, &mut ()).is_err(),
            "if a bare interpreter already resolved `mod`, this crate would be measuring nothing"
        );
    }
}
