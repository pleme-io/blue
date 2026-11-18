//! R13 of the default cascade (W2 of docs/FACTS.md): a string built by
//! appends in a loop is built once. `reduce((s, x) -> "#{s}…", init, xs)`
//! copies the whole string at every step, so it costs the square of its
//! length; this pass rewrites it to the string `init` starts as, followed by
//! the `join` of each step's appended parts, which costs the length.
//!
//! A site is a `reduce` whose callback takes `(s, x)` and whose body is a
//! `concat` chain with `s` at its left end and nowhere else: what each step
//! appends never reads what came before, so the parts can be made apart and
//! joined. The rewrite keeps the order every part is evaluated in, and runs
//! the `reduce` as written when the list is empty (it answers `init`
//! untouched) or is not a list (it raises as written). It stands down where
//! the fold does (a step bound, a hosted embedder), and when the program
//! defines `reduce`, `map`, `join` or `concat` itself. `BLUE_BUILDER=off`
//! (the switch the `kitei` registry names for R13) turns it off.

use blue_lang_syntax::{Atom, Span, Spanned, SpannedForm};
use tatara_lisp_eval::{Arity, Interpreter, Value};

/// The words a site is made of; a program that defines one keeps its loops.
pub const WORDS: &[&str] = &["reduce", "map", "join", "concat"];

const READY: &str = "blue-builder-ready?";

/// Whether the rewrite runs: on unless the switch the `kitei` registry names
/// for R13 is off, or [`crate::fuse::hold_off`] was called.
#[must_use]
pub fn enabled() -> bool {
    !crate::fuse::held_off() && !crate::kitei::switched_off("R13")
}

/// Bind the word a rewritten site asks before it builds: whether the list is
/// a list with an element, where the `reduce` as written would step at least
/// once.
pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(READY, Arity::Exact(1), |a: &[Value], _: &mut H, _| {
        Ok(Value::Bool(
            matches!(&a[0], Value::List(xs) if !xs.is_empty()),
        ))
    });
}

/// An erased program with its string-append loops built once.
#[derive(Clone, Debug)]
pub struct Built {
    pub forms: Vec<Spanned>,
    /// Each rewritten loop by its accumulator's name, with the index of the
    /// top-level form it is in.
    pub sites: Vec<(usize, String)>,
}

/// Rewrite every string-append loop of `erased`. `defined` is the tree
/// `erased` was erased from.
#[must_use]
pub fn build(erased: Vec<Spanned>, defined: &[Spanned]) -> Built {
    let own = defined
        .iter()
        .filter_map(crate::def_hash::defined)
        .any(|(k, _)| WORDS.contains(&k) || k == READY);
    if own {
        return Built {
            forms: erased,
            sites: Vec::new(),
        };
    }
    let mut sites = Vec::new();
    let mut next = 0usize;
    let forms = erased
        .into_iter()
        .enumerate()
        .map(|(i, form)| {
            let mut names = Vec::new();
            let out = rewrite(&form, &mut next, &mut names);
            sites.extend(names.into_iter().map(|n| (i, n)));
            out
        })
        .collect();
    Built { forms, sites }
}

fn sym(at: Span, name: &str) -> Spanned {
    Spanned::new(at, SpannedForm::Atom(Atom::Symbol(name.into())))
}

fn text(at: Span, s: &str) -> Spanned {
    Spanned::new(at, SpannedForm::Atom(Atom::Str(s.into())))
}

fn list(at: Span, items: Vec<Spanned>) -> Spanned {
    Spanned::new(at, SpannedForm::List(items))
}

fn is_text(s: &Spanned, want: &str) -> bool {
    matches!(&s.form, SpannedForm::Atom(Atom::Str(t)) if &**t == want)
}

fn mentions(s: &Spanned, name: &str) -> bool {
    match &s.form {
        SpannedForm::List(items) => items.iter().any(|i| mentions(i, name)),
        _ => s.as_symbol() == Some(name),
    }
}

/// The parts a step appends, when `body` is a `concat` chain with `acc` at
/// its left end: `(concat (concat "" acc) p1 …)` or `(concat acc p1 …)`,
/// nested to the left.
fn parts(body: &Spanned, acc: &str) -> Option<Vec<Spanned>> {
    let items = body.as_list()?;
    if items.first()?.as_symbol() != Some("concat") || items.len() < 2 {
        return None;
    }
    let left = &items[1];
    let rest = items[2..].to_vec();
    let mut out = if left.as_symbol() == Some(acc) {
        Vec::new()
    } else if left.as_list().is_some_and(|l| {
        l.len() == 3
            && l[0].as_symbol() == Some("concat")
            && is_text(&l[1], "")
            && l[2].as_symbol() == Some(acc)
    }) {
        Vec::new()
    } else {
        parts(left, acc)?
    };
    out.extend(rest);
    Some(out)
}

/// The site a `(reduce (lambda (s x) body) init xs)` is: its accumulator, the
/// element's name and what each step appends.
fn site(items: &[Spanned]) -> Option<(String, Spanned, Vec<Spanned>)> {
    if items.len() != 4 || items[0].as_symbol() != Some("reduce") {
        return None;
    }
    let lambda = items[1].as_list()?;
    if lambda.len() != 3 || lambda[0].as_symbol() != Some("lambda") {
        return None;
    }
    let params = lambda[1].as_list()?;
    if params.len() != 2 {
        return None;
    }
    let acc = params[0].as_symbol()?;
    params[1].as_symbol()?;
    let appended = parts(&lambda[2], acc)?;
    if appended.is_empty() || appended.iter().any(|p| mentions(p, acc)) {
        return None;
    }
    Some((acc.to_string(), params[1].clone(), appended))
}

fn rewrite(s: &Spanned, next: &mut usize, names: &mut Vec<String>) -> Spanned {
    let SpannedForm::List(items) = &s.form else {
        return s.clone();
    };
    let items: Vec<Spanned> = items.iter().map(|i| rewrite(i, next, names)).collect();
    let Some((acc, element, appended)) = site(&items) else {
        return list(s.span, items);
    };
    let at = s.span;
    let init = format!("%builder_init{next}");
    let xs = format!("%builder_list{next}");
    *next += 1;
    names.push(acc);
    let step = appended.into_iter().fold(text(at, ""), |made, p| {
        list(at, vec![sym(at, "concat"), made, p])
    });
    let joined = list(
        at,
        vec![
            sym(at, "join"),
            list(
                at,
                vec![
                    sym(at, "map"),
                    list(at, vec![sym(at, "lambda"), list(at, vec![element]), step]),
                    sym(at, &xs),
                ],
            ),
            text(at, ""),
        ],
    );
    let built = list(
        at,
        vec![
            sym(at, "concat"),
            list(at, vec![sym(at, "concat"), text(at, ""), sym(at, &init)]),
            joined,
        ],
    );
    let as_written = list(
        at,
        vec![
            sym(at, "reduce"),
            items[1].clone(),
            sym(at, &init),
            sym(at, &xs),
        ],
    );
    list(
        Span::synthetic(),
        vec![
            sym(Span::synthetic(), "let*"),
            list(
                at,
                vec![
                    list(at, vec![sym(at, &init), items[2].clone()]),
                    list(at, vec![sym(at, &xs), items[3].clone()]),
                ],
            ),
            list(
                at,
                vec![
                    sym(at, "if"),
                    list(at, vec![sym(at, READY), sym(at, &xs)]),
                    built,
                    as_written,
                ],
            ),
        ],
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn built(src: &str) -> Built {
        let forms = tatara_lisp::read_spanned(src).expect("forms");
        build(forms.clone(), &forms)
    }

    #[test]
    fn an_append_loop_is_a_site_and_its_accumulator_is_named() {
        let b = built(
            r#"(define (f n) (reduce (lambda (s i) (concat (concat "" s) "ab")) "" (range n)))"#,
        );
        assert_eq!(b.sites, [(0, "s".to_string())]);
        let text = b.forms[0].to_sexp().to_string();
        assert!(
            text.contains("blue-builder-ready?") && text.contains("join"),
            "{text}"
        );
    }

    #[test]
    fn a_loop_that_reads_its_accumulator_is_left_as_written() {
        for src in [
            r#"(define (f n) (reduce (lambda (s i) (concat (concat "" s) (length s))) "" (range n)))"#,
            r#"(define (f n) (reduce (lambda (s i) (concat "x" s)) "" (range n)))"#,
            r#"(define (f n) (reduce (lambda (s i) (+ s i)) 0 (range n)))"#,
            r#"(define (f n) (reduce (lambda (s i) (concat (concat "" s))) "" (range n)))"#,
        ] {
            assert!(built(src).sites.is_empty(), "{src}");
        }
    }

    #[test]
    fn a_program_that_defines_a_word_of_the_site_keeps_its_loops() {
        let b = built(
            r#"(define (join xs sep) xs) (define (f n) (reduce (lambda (s i) (concat s "ab")) "" (range n)))"#,
        );
        assert!(b.sites.is_empty());
    }
}
