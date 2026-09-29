//! Runtime errors in blue's words.
//!
//! tatara-lisp-eval reports a wrong argument count as
//! `` `<closure>` expected Exact(2), got 3 ``: the closure does not carry its
//! name, and the arity is Rust's `Debug`. Both are fixed here rather than
//! upstream because the missing fact is blue's to supply: the error's span is
//! the CALL, and the call's head is the name the author wrote. So
//! [`describe`] finds the call in the tree that ran and says
//! `` `add` expects 2 arguments, got 3 ``.

use tatara_lisp::{Span, Spanned, SpannedForm};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::EvalError;

/// `e` as a blue author should read it, without a position (the caller
/// supplies `file:line:col`). `forms` is the tree that was evaluated, so the
/// error's span can be matched to the call it came from.
#[must_use]
pub fn describe(e: &EvalError, forms: &[Spanned]) -> String {
    match e {
        EvalError::ArityMismatch {
            fn_name,
            expected,
            got,
            at,
        } => {
            let name = callee_at(forms, *at)
                .or_else(|| (!fn_name.starts_with('<')).then(|| fn_name.to_string()));
            let who = name.map_or_else(|| "this function".to_string(), |n| format!("`{n}`"));
            format!("{who} expects {}, got {got}", arguments(expected))
        }
        other => other.short_message(),
    }
}

/// "2 arguments", "1 argument", "at least 1 argument", …
#[must_use]
pub fn arguments(arity: &Arity) -> String {
    let n = |k: usize| {
        if k == 1 {
            "1 argument".to_string()
        } else {
            format!("{k} arguments")
        }
    };
    match *arity {
        Arity::Exact(k) => n(k),
        Arity::AtLeast(k) => format!("at least {}", n(k)),
        Arity::Range(lo, hi) => format!("{lo} to {}", n(hi)),
        Arity::Any => "any number of arguments".to_string(),
    }
}

/// The head symbol of the call whose span is exactly `at`.
fn callee_at(forms: &[Spanned], at: Span) -> Option<String> {
    if at.is_synthetic() {
        return None;
    }
    forms.iter().find_map(|f| find(f, at))
}

fn find(node: &Spanned, at: Span) -> Option<String> {
    if node.span.start > at.start || node.span.end < at.end {
        return None;
    }
    match &node.form {
        SpannedForm::List(items) => {
            if node.span == at {
                if let Some(h) = items.first().and_then(Spanned::as_symbol) {
                    return Some(h.to_string());
                }
            }
            items.iter().find_map(|i| find(i, at))
        }
        SpannedForm::Quote(i)
        | SpannedForm::Quasiquote(i)
        | SpannedForm::Unquote(i)
        | SpannedForm::UnquoteSplice(i) => find(i, at),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arity_reads_as_words() {
        assert_eq!(arguments(&Arity::Exact(2)), "2 arguments");
        assert_eq!(arguments(&Arity::Exact(1)), "1 argument");
        assert_eq!(arguments(&Arity::AtLeast(1)), "at least 1 argument");
        assert_eq!(arguments(&Arity::Range(1, 3)), "1 to 3 arguments");
    }

    /// Red run (2026-09-29): `pipeline::eval_prepared` rendering
    /// `short_message` again instead of `describe`:
    /// `left: "runtime error: <anonymous>:5:1: `<closure>` expected Exact(2), got 3"`.
    #[test]
    fn a_wrong_argument_count_names_the_function() {
        let err = crate::pipeline::run("def add(a, b)\n  a + b\nend\n\nadd(1, 2, 3)\n")
            .expect_err("three arguments to a two-parameter def");
        assert_eq!(
            err.to_string(),
            "runtime error: <anonymous>:5:1: `add` expects 2 arguments, got 3"
        );
    }

    #[test]
    fn a_lambda_bound_to_a_name_is_named_by_the_call() {
        let err = crate::pipeline::run("f = fn(a) a end\nf(1, 2)\n").expect_err("arity");
        assert_eq!(
            err.to_string(),
            "runtime error: <anonymous>:2:1: `f` expects 1 argument, got 2"
        );
    }
}
