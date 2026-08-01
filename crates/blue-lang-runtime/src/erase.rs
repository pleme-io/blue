//! Type erasure — the step that makes the sliding scale actually slide.
//!
//! Blue's central promise is that **adding a type annotation buys analysis
//! and changes nothing else**. An annotated function must compute exactly
//! what the unannotated one computed, at exactly the same speed, or the scale
//! does not slide — it forks into two languages.
//!
//! That promise was broken in the most basic way possible. The parser emits
//! `(define-typed (add (a Int) (b Int)) Int body)` for an annotated `def`,
//! tatara-lisp has no such form, and so *every annotated blue program failed
//! with `unbound symbol: define-typed`.* The headline feature produced code
//! that would not run.
//!
//! Erasure is the fix, and it is the standard one: annotations are consumed
//! by [`blue_lang_check`](https://docs.rs/blue-lang-check) at build time and
//! **erased before execution**, so the runtime never sees a type. This is
//! gradual typing's erasure discipline, and it is what makes the annotated
//! and unannotated forms compile to the same code rather than to two
//! dialects.
//!
//! ## Erasure runs after checking, never instead of it
//!
//! Erasing types is not ignoring them. The pipeline is *parse → check →
//! erase → run*: the annotation has already done its work by the time it is
//! dropped. Erasing before checking would silently discard every declared
//! type, which is why [`crate::pipeline`] owns the order rather than leaving
//! it to each caller.

use tatara_lisp::{Atom, Sexp};

/// Erase every type annotation in a program, leaving code the interpreter
/// can execute.
///
/// `(define-typed (name (p T) …) R body)` → `(define (name p …) body)`.
/// Everything else passes through untouched, recursively, so an annotated
/// `def` nested inside another form is erased too.
pub fn erase_types(forms: &[Sexp]) -> Vec<Sexp> {
    forms.iter().map(erase_form).collect()
}

fn erase_form(s: &Sexp) -> Sexp {
    match s {
        Sexp::List(items) if is_define_typed(items) => {
            // items = [define-typed, (name (p T)...), R, body]
            let Sexp::List(sig) = &items[1] else {
                return s.clone();
            };
            let mut plain = Vec::with_capacity(sig.len());
            plain.push(sig[0].clone());
            for p in &sig[1..] {
                // A parameter is `(name Type)`; keep the name. A bare symbol
                // is already erased, so keep it as-is rather than dropping
                // it — losing a parameter would silently change arity.
                match p {
                    Sexp::List(pair) if !pair.is_empty() => plain.push(pair[0].clone()),
                    other => plain.push(other.clone()),
                }
            }
            Sexp::List(vec![
                Sexp::Atom(Atom::Symbol("define".into())),
                Sexp::List(plain),
                erase_form(&items[3]),
            ])
        }
        Sexp::List(items) => Sexp::List(items.iter().map(erase_form).collect()),
        other => other.clone(),
    }
}

fn is_define_typed(items: &[Sexp]) -> bool {
    items.len() == 4
        && matches!(&items[0], Sexp::Atom(Atom::Symbol(n)) if &**n == "define-typed")
        && matches!(&items[1], Sexp::List(sig) if !sig.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn erased(src: &str) -> String {
        let forms = blue_lang_syntax::parse_program(src).expect("parse");
        erase_types(&forms)
            .iter()
            .map(|f| f.to_string())
            .collect::<Vec<_>>()
            .join("\n")
    }

    /// The shape of the erasure, spelled out.
    #[test]
    fn an_annotated_def_erases_to_a_plain_def() {
        assert_eq!(
            erased("def add(a: Int, b: Int) -> Int\n  a + b\nend"),
            "(define (add a b) (+ a b))"
        );
    }

    /// **The load-bearing property: erasure is a no-op on the annotated
    /// program's meaning.** The annotated and unannotated forms must erase to
    /// the *same tree*, because that is what "annotating changes nothing
    /// else" means operationally.
    #[test]
    fn annotating_does_not_change_the_erased_program() {
        assert_eq!(
            erased("def add(a: Int, b: Int) -> Int\n  a + b\nend"),
            erased("def add(a, b)\n  a + b\nend"),
            "an annotation must not survive into the code that runs"
        );
    }

    /// Arity is preserved. Dropping a parameter along with its type would be
    /// a silent arity change — the erasure bug that is hardest to see,
    /// because the program still parses and still runs.
    #[test]
    fn erasure_preserves_arity() {
        assert_eq!(
            erased("def three(a: Int, b, c: Str) -> dyn\n  a\nend"),
            "(define (three a b c) a)"
        );
    }

    /// Nested annotated defs are erased too, so a helper defined inside a
    /// body does not survive as an unbound `define-typed`.
    #[test]
    fn a_nested_annotated_def_is_erased() {
        let out = erased("def outer(x: Int) -> Int\n  def inner(y: Int) -> Int\n    y\n  end\nend");
        assert!(
            !out.contains("define-typed"),
            "no annotation may survive anywhere in the tree: {out}"
        );
    }

    /// Anti-vacuity: erasure must leave an already-plain program completely
    /// alone. A pass that rewrote everything would satisfy the tests above
    /// while corrupting untyped code.
    #[test]
    fn erasure_leaves_untyped_code_untouched() {
        for src in ["1 + 2", "def f(x)\n  x\nend", "[1, 2, 3]", "a.b(c)"] {
            let forms = blue_lang_syntax::parse_program(src).expect("parse");
            assert_eq!(
                erase_types(&forms),
                forms,
                "erasure changed untyped source {src:?}"
            );
        }
    }
}
