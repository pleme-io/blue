//! blue's string and number core.
//!
//! tatara-lisp ships arithmetic, comparison, list and trig primitives and
//! **no string operations at all** — no length, no concatenation, no case
//! conversion, no number parsing. For a language whose surface is Ruby's, that
//! is the largest parity gap there is: `String` is the most-used type in Ruby
//! by a wide margin.
//!
//! # Why these live in blue and not in tatara-lisp
//!
//! The fleet rule is to extend the substrate rather than re-implement, and
//! generic helpers belong upstream. These are not generic: the *semantics* are
//! blue's, and they are Ruby's semantics specifically.
//!
//! The clearest case is `length`. Ruby's `String#length` counts **characters**;
//! Rust's `str::len` counts **bytes**; Elixir's `String.length/1` counts
//! grapheme clusters. Three languages, three answers, all defensible. Blue owes
//! its users Ruby's answer, and encoding that choice into tatara-lisp would push
//! one language's convention onto every other consumer of the substrate.
//!
//! Promoting a genuinely encoding-neutral core upstream later stays open; the
//! character-counting ones are blue's by right.
//!
//! # Character, not byte, not grapheme
//!
//! Every index and length here is in **Unicode scalar values** (Rust `char`).
//! That matches Ruby for the overwhelming majority of text and is stated rather
//! than left to be discovered — a `length` that silently returns bytes is the
//! bug that only appears once a user types a non-ASCII character.
//!
//! Grapheme clusters (Elixir's choice) would need a segmentation table; where
//! the two differ — a family emoji, a combining accent — blue reports scalar
//! values. `a_combining_sequence_counts_scalars_not_graphemes` pins it.

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

fn as_str(v: &Value, span: tatara_lisp::Span) -> Result<String, EvalError> {
    match v {
        Value::Str(s) => Ok(s.to_string()),
        // A symbol is text the author wrote; accepting it makes `upcase(:ok)`
        // work the way a Ruby programmer expects of a symbol.
        Value::Symbol(s) | Value::Keyword(s) => Ok(s.to_string()),
        other => Err(EvalError::type_mismatch("a string", other.type_name(), span)),
    }
}

/// Render any value as text — blue's `to_s`.
fn render(v: &Value) -> String {
    match v {
        Value::Nil => String::new(),
        Value::Bool(b) => b.to_string(),
        Value::Int(n) => n.to_string(),
        Value::Float(x) => x.to_string(),
        Value::Str(s) | Value::Symbol(s) | Value::Keyword(s) => s.to_string(),
        Value::List(items) => items.iter().map(render).collect::<Vec<_>>().join(" "),
        other => other.type_name().to_string(),
    }
}

fn list(items: Vec<Value>) -> Value {
    Value::List(std::sync::Arc::new(items))
}

/// Install blue's string and number core.
pub fn install_blue_stdlib<H: 'static>(interp: &mut Interpreter<H>) {
    // ── text ──────────────────────────────────────────────────────────

    // `length` counts CHARACTERS, per Ruby. Also accepts a list, where it is
    // the element count — Ruby's `Array#length`.
    interp.register_fn(
        "length",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, span| match &a[0] {
            Value::List(items) => Ok(Value::Int(items.len() as i64)),
            other => Ok(Value::Int(as_str(other, span)?.chars().count() as i64)),
        },
    );

    interp.register_fn("to_s", Arity::Exact(1), |a: &[Value], _h: &mut H, _s| {
        Ok(Value::Str(render(&a[0]).into()))
    });

    interp.register_fn("upcase", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        Ok(Value::Str(as_str(&a[0], s)?.to_uppercase().into()))
    });

    interp.register_fn("downcase", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        Ok(Value::Str(as_str(&a[0], s)?.to_lowercase().into()))
    });

    interp.register_fn("trim", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        Ok(Value::Str(as_str(&a[0], s)?.trim().into()))
    });

    // `concat(a, b)` — two-arg so it composes; `+` stays arithmetic. Ruby
    // overloads `+` on String, but blue's `+` lowers to tatara's numeric `+`,
    // and silently making it polymorphic would make a type error at a seam
    // disappear into a string.
    interp.register_fn(
        "concat",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, _s| {
            let mut out = render(&a[0]);
            out.push_str(&render(&a[1]));
            Ok(Value::Str(out.into()))
        },
    );

    interp.register_fn("split", Arity::Exact(2), |a: &[Value], _h: &mut H, s| {
        let text = as_str(&a[0], s)?;
        let sep = as_str(&a[1], s)?;
        // An empty separator splits into characters, as Ruby's `split("")`
        // does. Rust's `split("")` yields leading/trailing empties instead,
        // which is the wrong answer here.
        let parts: Vec<Value> = if sep.is_empty() {
            text.chars().map(|c| Value::Str(c.to_string().into())).collect()
        } else {
            text.split(sep.as_str())
                .map(|p| Value::Str(p.into()))
                .collect()
        };
        Ok(list(parts))
    });

    interp.register_fn("join", Arity::Exact(2), |a: &[Value], _h: &mut H, s| {
        let sep = as_str(&a[1], s)?;
        match &a[0] {
            Value::List(items) => Ok(Value::Str(
                items.iter().map(render).collect::<Vec<_>>().join(&sep).into(),
            )),
            other => Err(EvalError::type_mismatch("a list", other.type_name(), s).into()),
        }
    });

    interp.register_fn("contains?", Arity::Exact(2), |a: &[Value], _h: &mut H, s| {
        Ok(Value::Bool(as_str(&a[0], s)?.contains(&as_str(&a[1], s)?)))
    });

    interp.register_fn(
        "starts_with?",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, s| {
            Ok(Value::Bool(as_str(&a[0], s)?.starts_with(&as_str(&a[1], s)?)))
        },
    );

    interp.register_fn("ends_with?", Arity::Exact(2), |a: &[Value], _h: &mut H, s| {
        Ok(Value::Bool(as_str(&a[0], s)?.ends_with(&as_str(&a[1], s)?)))
    });

    interp.register_fn("replace", Arity::Exact(3), |a: &[Value], _h: &mut H, s| {
        Ok(Value::Str(
            as_str(&a[0], s)?
                .replace(&as_str(&a[1], s)?, &as_str(&a[2], s)?)
                .into(),
        ))
    });

    interp.register_fn("reverse", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        match &a[0] {
            Value::List(items) => {
                let mut v = items.as_ref().clone();
                v.reverse();
                Ok(list(v))
            }
            // Reversed by CHARACTER, so a multi-byte character survives. A
            // byte-wise reverse produces invalid UTF-8.
            other => Ok(Value::Str(
                as_str(other, s)?.chars().rev().collect::<String>().into(),
            )),
        }
    });

    interp.register_fn("chars", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        Ok(list(
            as_str(&a[0], s)?
                .chars()
                .map(|c| Value::Str(c.to_string().into()))
                .collect(),
        ))
    });

    // ── numbers ───────────────────────────────────────────────────────

    // `to_int` RETURNS NIL on unparseable input rather than raising. Ruby's
    // `String#to_i` answers 0 for garbage, which silently turns a parse failure
    // into a plausible number; nil is falsy and cannot be mistaken for a
    // result. `to_int!` is the raising form for callers who want the failure.
    interp.register_fn("to_int", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        match &a[0] {
            Value::Int(n) => Ok(Value::Int(*n)),
            Value::Float(x) => Ok(Value::Int(*x as i64)),
            other => Ok(as_str(other, s)?
                .trim()
                .parse::<i64>()
                .map_or(Value::Nil, Value::Int)),
        }
    });

    interp.register_fn("to_int!", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        match &a[0] {
            Value::Int(n) => Ok(Value::Int(*n)),
            Value::Float(x) => Ok(Value::Int(*x as i64)),
            other => {
                let text = as_str(other, s)?;
                text.trim().parse::<i64>().map(Value::Int).map_err(|_| {
                    EvalError::native_fn(
                        "to_int!",
                        "`".to_string() + &text + "` is not an integer",
                        s,
                    )
                    .into()
                })
            }
        }
    });

    interp.register_fn("to_float", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        match &a[0] {
            Value::Float(x) => Ok(Value::Float(*x)),
            Value::Int(n) => Ok(Value::Float(*n as f64)),
            other => Ok(as_str(other, s)?
                .trim()
                .parse::<f64>()
                .map_or(Value::Nil, Value::Float)),
        }
    });

    interp.register_fn("abs", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        match &a[0] {
            Value::Int(n) => Ok(Value::Int(n.abs())),
            Value::Float(x) => Ok(Value::Float(x.abs())),
            other => Err(EvalError::type_mismatch("a number", other.type_name(), s).into()),
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(src: &str) -> Value {
        crate::run(src).unwrap_or_else(|e| panic!("{src:?}: {e}")).value
    }

    fn s(src: &str) -> String {
        match eval(src) {
            Value::Str(v) => v.to_string(),
            other => panic!("{src:?} produced {other:?}"),
        }
    }

    fn i(src: &str) -> i64 {
        match eval(src) {
            Value::Int(v) => v,
            other => panic!("{src:?} produced {other:?}"),
        }
    }

    /// **`length` counts CHARACTERS, as Ruby does — not bytes.** A `length`
    /// that returns bytes is the bug that only surfaces once a user types a
    /// non-ASCII character, which is exactly when it is hardest to trace.
    #[test]
    fn length_counts_characters_not_bytes() {
        assert_eq!(i("length(\"hello\")"), 5);
        // "héllo" is 6 bytes, 5 characters.
        assert_eq!(i("length(\"héllo\")"), 5, "must not be 6");
        // An emoji is 4 bytes, 1 character.
        assert_eq!(i("length(\"😀\")"), 1, "must not be 4");
    }

    /// blue reports **scalar values**, not grapheme clusters. Elixir would say
    /// 1 here; blue says 2. Stated and pinned rather than left to surprise.
    #[test]
    fn a_combining_sequence_counts_scalars_not_graphemes() {
        // "e" + U+0301 COMBINING ACUTE — one grapheme, two scalars.
        assert_eq!(
            i("length(\"e\\u{301}\")"),
            2,
            "blue counts scalar values; Elixir's String.length would say 1"
        );
    }

    #[test]
    fn length_also_works_on_a_list() {
        assert_eq!(i("length([1, 2, 3])"), 3);
    }

    #[test]
    fn case_and_trim() {
        assert_eq!(s("upcase(\"abc\")"), "ABC");
        assert_eq!(s("downcase(\"ABC\")"), "abc");
        assert_eq!(s("trim(\"  hi  \")"), "hi");
        // Non-ASCII case works, which a byte-wise implementation would botch.
        assert_eq!(s("upcase(\"é\")"), "É");
    }

    #[test]
    fn concat_and_to_s() {
        assert_eq!(s("concat(\"a\", \"b\")"), "ab");
        assert_eq!(s("concat(\"n=\", 42)"), "n=42");
        assert_eq!(s("to_s(42)"), "42");
        assert_eq!(s("to_s(true)"), "true");
    }

    /// **`+` stays arithmetic.** Ruby overloads it on String, but blue's `+`
    /// lowers to tatara's numeric `+`; making it polymorphic would let a type
    /// error at a seam disappear into a string.
    #[test]
    fn plus_is_not_string_concatenation() {
        assert!(
            crate::run("\"a\" + \"b\"").is_err(),
            "`+` must not silently concatenate — use concat"
        );
    }

    #[test]
    fn split_and_join() {
        assert_eq!(i("length(split(\"a,b,c\", \",\"))"), 3);
        assert_eq!(s("join(split(\"a,b,c\", \",\"), \"-\")"), "a-b-c");
        // Ruby's `split("")` yields characters.
        assert_eq!(i("length(split(\"abc\", \"\"))"), 3);
    }

    #[test]
    fn predicates() {
        assert!(matches!(eval("contains?(\"hello\", \"ell\")"), Value::Bool(true)));
        assert!(matches!(eval("contains?(\"hello\", \"xyz\")"), Value::Bool(false)));
        assert!(matches!(eval("starts_with?(\"hello\", \"he\")"), Value::Bool(true)));
        assert!(matches!(eval("ends_with?(\"hello\", \"lo\")"), Value::Bool(true)));
    }

    #[test]
    fn replace_and_chars() {
        assert_eq!(s("replace(\"a-b-c\", \"-\", \"+\")"), "a+b+c");
        assert_eq!(i("length(chars(\"abc\"))"), 3);
    }

    /// Reversed by character, so a multi-byte character survives. A byte-wise
    /// reverse produces invalid UTF-8.
    #[test]
    fn reverse_is_character_wise() {
        assert_eq!(s("reverse(\"abc\")"), "cba");
        assert_eq!(s("reverse(\"héllo\")"), "olléh", "must not corrupt the é");
    }

    #[test]
    fn reverse_also_works_on_a_list() {
        assert_eq!(s("join(reverse([1, 2, 3]), \",\")"), "3,2,1");
    }

    /// **`to_int` answers nil on garbage, not 0.** Ruby's `String#to_i` returns
    /// 0, which silently turns a parse failure into a plausible number — a
    /// deliberate divergence, and the reason `to_int!` exists for callers who
    /// want the failure loudly.
    #[test]
    fn to_int_is_nil_on_garbage_rather_than_zero() {
        assert_eq!(i("to_int(\"42\")"), 42);
        assert!(
            matches!(eval("to_int(\"banana\")"), Value::Nil),
            "Ruby would say 0 here; a falsy nil cannot be mistaken for a result"
        );
        assert!(
            matches!(eval("to_int(\"0\")"), Value::Int(0)),
            "and a real 0 is still a real 0 — the two must stay distinguishable"
        );
    }

    #[test]
    fn to_int_bang_raises_on_garbage() {
        assert_eq!(i("to_int!(\"42\")"), 42);
        let err = crate::run("to_int!(\"banana\")").expect_err("must raise");
        assert!(err.to_string().contains("banana"), "must name it: {err}");
    }

    #[test]
    fn numeric_conversions_and_abs() {
        assert_eq!(i("to_int(3.9)"), 3);
        assert_eq!(i("abs(0 - 5)"), 5);
        assert!(matches!(eval("to_float(\"1.5\")"), Value::Float(_)));
        assert!(matches!(eval("to_float(\"nope\")"), Value::Nil));
    }

    /// A wrong-typed argument is a typed error, not a silent coercion.
    #[test]
    fn a_non_string_argument_is_a_type_error() {
        assert!(crate::run("upcase([1, 2])").is_err());
        assert!(crate::run("join(\"not a list\", \",\")").is_err());
    }
}
