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
//!
//! ## Erasure carries spans, because it only ever DELETES
//!
//! This pass runs on [`Spanned`], not on the spanless [`Sexp`], and that is
//! not a convenience — it is the reason a runtime error can name a line.
//! Erasure used to hand the evaluator a spanless tree, which
//! `pipeline::run_in_surface` then lifted with
//! [`crate::lower_to_spanned`] — every node stamped `Span::synthetic()`. So
//! the evaluator's `EvalError` arrived carrying a span that indexed nothing,
//! and `blue run` could only print a bare message.
//!
//! Carrying spans through is cheap here for a structural reason worth
//! stating, because it is what makes the port total rather than a guess:
//! **erasure removes nodes and never invents structure.** The parameter walk
//! drops each `(name Type)` wrapper and keeps the *existing* `name` node,
//! annotations and all fall away, and exactly ONE node in the whole pass is
//! newly built — the `define` symbol that replaces `define-typed`. That one
//! has a natural home: the span of the `define-typed` symbol it stands in
//! for. **No node in an erased tree needs a synthetic span**, so nothing is
//! lost and nothing is fabricated.

use tatara_lisp::{Atom, Sexp, Spanned, SpannedForm};

/// Erase every type annotation in a program, leaving code the interpreter
/// can execute — **with every surviving node's source position intact**.
///
/// `(define-typed (name (p T) …) R body)` → `(define (name p …) body)`.
/// Everything else passes through untouched, recursively, so an annotated
/// `def` nested inside another form is erased too.
///
/// Takes and returns [`Spanned`]. A caller holding spanless [`Sexp`] projects
/// the result with [`Spanned::to_sexp`]; a caller that needs a position out
/// the far end must not, because that projection is where the position dies.
#[must_use]
pub fn erase_types(forms: &[Spanned]) -> Vec<Spanned> {
    forms.iter().map(erase_form).collect()
}

fn erase_form(s: &Spanned) -> Spanned {
    match &s.form {
        SpannedForm::List(items) if is_define_typed(items) => {
            // items = [define-typed, (name (p T)...), R, body]
            let SpannedForm::List(sig) = &items[1].form else {
                return s.clone();
            };
            let mut plain = Vec::with_capacity(sig.len());
            plain.push(sig[0].clone());
            for p in &sig[1..] {
                // A parameter is `(name Type)`; keep the name. A bare symbol
                // is already erased, so keep it as-is rather than dropping
                // it — losing a parameter would silently change arity.
                //
                // Both arms keep an EXISTING node, so both keep its span.
                match &p.form {
                    SpannedForm::List(pair) if !pair.is_empty() => plain.push(pair[0].clone()),
                    _ => plain.push(p.clone()),
                }
            }
            Spanned::new(
                s.span,
                SpannedForm::List(vec![
                    // The one and only node this pass invents. It stands in
                    // for `define-typed`, so it is given that symbol's span
                    // — the position a reader would point at if asked where
                    // this `define` came from. Nothing here is synthetic.
                    Spanned::new(
                        items[0].span,
                        SpannedForm::Atom(Atom::Symbol("define".into())),
                    ),
                    Spanned::new(items[1].span, SpannedForm::List(plain)),
                    erase_form(&items[3]),
                ]),
            )
        }
        SpannedForm::List(items) => Spanned::new(
            s.span,
            SpannedForm::List(items.iter().map(erase_form).collect()),
        ),
        _ => s.clone(),
    }
}

fn is_define_typed(items: &[Spanned]) -> bool {
    items.len() == 4
        && matches!(&items[0].form, SpannedForm::Atom(Atom::Symbol(n)) if &**n == "define-typed")
        && matches!(&items[1].form, SpannedForm::List(sig) if !sig.is_empty())
}

/// Project an erased program back to spanless forms.
///
/// The adapter for the consumers that genuinely do not report positions —
/// the Bluefile manifest's reach check, `blue erase`'s printer, the test
/// harness. Written once here rather than as three `map(Spanned::to_sexp)`
/// chains, so the sites that throw a position away are countable.
#[must_use]
pub fn to_sexps(forms: &[Spanned]) -> Vec<Sexp> {
    forms.iter().map(Spanned::to_sexp).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tree(src: &str) -> Vec<Spanned> {
        blue_lang_syntax::parse_program_tree(src).expect("parse")
    }

    fn erased(src: &str) -> String {
        to_sexps(&erase_types(&tree(src)))
            .iter()
            .map(ToString::to_string)
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
    ///
    /// Stronger than it was: `Spanned`'s `PartialEq` compares the span too, so
    /// this now also says erasure moved no position on the untouched path.
    #[test]
    fn erasure_leaves_untyped_code_untouched() {
        for src in ["1 + 2", "def f(x)\n  x\nend", "[1, 2, 3]", "a.b(c)"] {
            let forms = tree(src);
            assert_eq!(
                erase_types(&forms),
                forms,
                "erasure changed untyped source {src:?}"
            );
        }
    }

    /// **No node in an erased tree is synthetic** — the property the whole
    /// spanned port rests on, asserted over the tree rather than argued from
    /// the code.
    ///
    /// The independent evidence is the source text itself: every surviving
    /// node's span is sliced out of the file it came from and asserted
    /// non-empty and in range. A pass that stamped `Span::synthetic()`
    /// anywhere — which is exactly what `lower_to_spanned` did to the whole
    /// tree — fails at the first annotated node.
    ///
    /// **Red run** (2026-08-12), the invented `define` symbol built with
    /// `Span::synthetic()` instead of `items[0].span`:
    /// ```text
    /// a synthetic span survived erasure of "def add(a: Int, b: Int) -> Int\n  a + b\nend"
    /// ```
    /// Note the mutation is confined to the ONE invented node — everything
    /// else in the tree still carries a real span — so this gate is measuring
    /// that node and not the port as a whole.
    #[test]
    fn erasure_leaves_no_synthetic_span_behind() {
        fn walk(node: &Spanned, src: &str, seen: &mut usize) {
            assert!(
                !node.span.is_synthetic(),
                "a synthetic span survived erasure of {src:?}"
            );
            assert!(
                src.get(node.span.start..node.span.end).is_some(),
                "span {:?} is not a range in {src:?}",
                node.span
            );
            *seen += 1;
            match &node.form {
                SpannedForm::List(xs) => {
                    for x in xs {
                        walk(x, src, seen);
                    }
                }
                SpannedForm::Quote(x)
                | SpannedForm::Quasiquote(x)
                | SpannedForm::Unquote(x)
                | SpannedForm::UnquoteSplice(x) => walk(x, src, seen),
                SpannedForm::Nil | SpannedForm::Atom(_) => {}
            }
        }

        for src in [
            "def add(a: Int, b: Int) -> Int\n  a + b\nend",
            "def three(a: Int, b, c: Str) -> dyn\n  a\nend",
            "def outer(x: Int) -> Int\n  def inner(y: Int) -> Int\n    y\n  end\nend",
            "def f(x)\n  x\nend\nf(1)",
        ] {
            let mut seen = 0;
            for form in &erase_types(&tree(src)) {
                walk(form, src, &mut seen);
            }
            // Anti-vacuity: an empty tree passes the walk above.
            assert!(seen >= 4, "{src:?} walked only {seen} nodes");
        }
    }

    /// The invented `define` sits where `define-typed` sat.
    ///
    /// Pinned as a position, not as an existence claim: "it has a span" is
    /// satisfied by any span at all, including a wrong one inherited from the
    /// enclosing form. This says *which*.
    ///
    /// **Red run** (2026-08-12), the invented symbol given `s.span` — the
    /// enclosing form's span — which is the plausible lazy choice and survives
    /// the synthetic gate above untouched:
    /// ```text
    /// assertion `left == right` failed: the invented `define` must stand
    /// where the annotated `def` stood
    ///   left: "def add(a: Int) -> Int\n  a\nend"
    ///  right: "def"
    /// ```
    #[test]
    fn the_invented_define_carries_the_annotations_own_position() {
        let src = "x = 1\ndef add(a: Int) -> Int\n  a\nend";
        let erased = erase_types(&tree(src));
        let head = erased[1].as_list().expect("a list")[0].clone();
        assert_eq!(head.as_symbol(), Some("define"));
        assert_eq!(
            src.get(head.span.start..head.span.end),
            Some("def"),
            "the invented `define` must stand where the annotated `def` stood"
        );
    }
}
