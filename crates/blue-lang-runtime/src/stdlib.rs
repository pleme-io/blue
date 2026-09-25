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
        other => Err(EvalError::type_mismatch(
            "a string",
            other.type_name(),
            span,
        )),
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
    interp.register_fn("concat", Arity::Exact(2), |a: &[Value], _h: &mut H, _s| {
        let mut out = render(&a[0]);
        out.push_str(&render(&a[1]));
        Ok(Value::Str(out.into()))
    });

    interp.register_fn("split", Arity::Exact(2), |a: &[Value], _h: &mut H, s| {
        let text = as_str(&a[0], s)?;
        let sep = as_str(&a[1], s)?;
        // An empty separator splits into characters, as Ruby's `split("")`
        // does. Rust's `split("")` yields leading/trailing empties instead,
        // which is the wrong answer here.
        let parts: Vec<Value> = if sep.is_empty() {
            text.chars()
                .map(|c| Value::Str(c.to_string().into()))
                .collect()
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
                items
                    .iter()
                    .map(render)
                    .collect::<Vec<_>>()
                    .join(&sep)
                    .into(),
            )),
            other => Err(EvalError::type_mismatch("a list", other.type_name(), s).into()),
        }
    });

    interp.register_fn(
        "contains?",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, s| {
            Ok(Value::Bool(as_str(&a[0], s)?.contains(&as_str(&a[1], s)?)))
        },
    );

    interp.register_fn(
        "starts_with?",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, s| {
            Ok(Value::Bool(
                as_str(&a[0], s)?.starts_with(&as_str(&a[1], s)?),
            ))
        },
    );

    interp.register_fn(
        "ends_with?",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, s| {
            Ok(Value::Bool(as_str(&a[0], s)?.ends_with(&as_str(&a[1], s)?)))
        },
    );

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
    interp.register_fn(
        "to_int",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::Int(n) => Ok(Value::Int(*n)),
            Value::Float(x) => Ok(Value::Int(*x as i64)),
            other => Ok(as_str(other, s)?
                .trim()
                .parse::<i64>()
                .map_or(Value::Nil, Value::Int)),
        },
    );

    interp.register_fn(
        "to_int!",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
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
        },
    );

    interp.register_fn(
        "to_float",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::Float(x) => Ok(Value::Float(*x)),
            Value::Int(n) => Ok(Value::Float(*n as f64)),
            other => Ok(as_str(other, s)?
                .trim()
                .parse::<f64>()
                .map_or(Value::Nil, Value::Float)),
        },
    );

    interp.register_fn(
        "abs",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::Int(n) => Ok(Value::Int(n.abs())),
            Value::Float(x) => Ok(Value::Float(x.abs())),
            other => Err(EvalError::type_mismatch("a number", other.type_name(), s).into()),
        },
    );

    // ── ranges ────────────────────────────────────────────────────────

    // `range` is a LOOP here, not a recursion. tatara-lisp's stdlib defines it
    // in Lisp (`lisp_stdlib.tlisp`, where `range-impl` conses one frame per
    // element), so `range(0, 5000)` overflowed the 8 MiB main stack and
    // aborted the process. Everything built on it inherited the ceiling:
    // retsu's `indexes`, `zip_with` and `enumerate`, and shomei's
    // `chain_first_break`, which could not verify a 5,000-entry chain
    // (measured 2026-09-24: 4,000 elements fine, 5,000 aborted).
    //
    // Same arities and answers as the Lisp definition: (end), (start, end),
    // (start, end, step), ascending for a positive step, descending for a
    // negative one, and each next element is the previous plus the step under
    // the ordinary number rules (Int + Int is Int; a Float anywhere makes the
    // rest Float). Two refusals the Lisp version lacked: a zero step, which
    // recursed forever, and a wrong arity, which printed a message and
    // returned nil.
    //
    // The destination is upstream: when tatara-lisp's own `range` is a loop,
    // this registration is deleted.
    interp.register_fn(
        "range",
        Arity::Range(1, 3),
        |a: &[Value], _h: &mut H, s| {
            let (start, end, step) = match a.len() {
                1 => (Value::Int(0), a[0].clone(), Value::Int(1)),
                2 => (a[0].clone(), a[1].clone(), Value::Int(1)),
                _ => (a[0].clone(), a[1].clone(), a[2].clone()),
            };
            range_list(start, &end, &step, s)
        },
    );
}

/// A number's value as a float, or a type error naming `range`.
fn range_num(v: &Value, s: tatara_lisp::Span) -> Result<f64, EvalError> {
    match v {
        Value::Int(n) => Ok(*n as f64),
        Value::Float(x) => Ok(*x),
        other => Err(EvalError::native_fn(
            "range",
            "expected a number, got ".to_string() + other.type_name(),
            s,
        )),
    }
}

/// `a + b` under the number rules the Lisp `range` used: Int + Int stays Int,
/// anything with a Float is Float.
fn range_add(a: &Value, b: &Value, s: tatara_lisp::Span) -> Result<Value, EvalError> {
    match (a, b) {
        (Value::Int(x), Value::Int(y)) => x.checked_add(*y).map(Value::Int).ok_or_else(|| {
            EvalError::native_fn("range", "an element overflowed a 64-bit integer", s)
        }),
        _ => Ok(Value::Float(range_num(a, s)? + range_num(b, s)?)),
    }
}

fn range_list(
    start: Value,
    end: &Value,
    step: &Value,
    s: tatara_lisp::Span,
) -> Result<Value, EvalError> {
    let end_f = range_num(end, s)?;
    let step_f = range_num(step, s)?;
    range_num(&start, s)?;
    if step_f == 0.0 {
        return Err(EvalError::native_fn(
            "range",
            "a step of zero never reaches the end",
            s,
        ));
    }
    let mut out = Vec::new();
    let mut cur = start;
    loop {
        let c = range_num(&cur, s)?;
        if (step_f > 0.0 && c >= end_f) || (step_f < 0.0 && c <= end_f) {
            break;
        }
        let next = range_add(&cur, step, s)?;
        out.push(cur);
        cur = next;
    }
    Ok(list(out))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(src: &str) -> Value {
        crate::run(src)
            .unwrap_or_else(|e| panic!("{src:?}: {e}"))
            .value
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

    fn ints(src: &str) -> Vec<i64> {
        match eval(src) {
            Value::List(xs) => xs
                .iter()
                .map(|v| match v {
                    Value::Int(n) => *n,
                    other => panic!("{src:?} produced a non-Int element {other:?}"),
                })
                .collect(),
            other => panic!("{src:?} produced {other:?}"),
        }
    }

    /// **`range` gives the Lisp definition's answers**, arity by arity,
    /// including the descending form and the empty cases.
    #[test]
    fn range_answers_as_the_lisp_definition_did() {
        assert_eq!(ints("range(5)"), vec![0, 1, 2, 3, 4]);
        assert_eq!(ints("range(2, 6)"), vec![2, 3, 4, 5]);
        assert_eq!(ints("range(0, 10, 2)"), vec![0, 2, 4, 6, 8]);
        assert_eq!(ints("range(10, 0, 0 - 2)"), vec![10, 8, 6, 4, 2]);
        assert!(ints("range(5, 5)").is_empty());
        assert!(ints("range(5, 2)").is_empty());
        assert!(ints("range(0)").is_empty());
        // A float step makes the elements after the first floats, as `+` did.
        match eval("range(0, 1, 0.5)") {
            Value::List(xs) => {
                assert!(matches!(xs[0], Value::Int(0)), "{xs:?}");
                assert!(matches!(xs[1], Value::Float(x) if x == 0.5), "{xs:?}");
                assert_eq!(xs.len(), 2);
            }
            other => panic!("{other:?}"),
        }
    }

    /// **`range` is a loop, not a recursion.** The Lisp definition consed one
    /// stack frame per element and aborted the process near 5,000 elements on
    /// an 8 MiB stack. This runs on the test harness's 2 MiB thread, where the
    /// Lisp one died sooner still. Red run, 2026-09-24: with the registration
    /// removed, this test aborted the test binary with a stack overflow.
    #[test]
    fn range_builds_long_lists_without_recursing() {
        assert_eq!(i("length(range(0, 200000))"), 200_000);
        assert_eq!(i("nth(199999, range(0, 200000))"), 199_999);
    }

    /// A zero step never reaches the end: refused, where the Lisp definition
    /// recursed until the stack gave out. A non-number is a named error.
    #[test]
    fn range_refuses_a_zero_step_and_a_non_number() {
        assert!(crate::run("range(0, 5, 0)").is_err());
        assert!(crate::run("range(0, \"x\")").is_err());
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
        assert!(matches!(
            eval("contains?(\"hello\", \"ell\")"),
            Value::Bool(true)
        ));
        assert!(matches!(
            eval("contains?(\"hello\", \"xyz\")"),
            Value::Bool(false)
        ));
        assert!(matches!(
            eval("starts_with?(\"hello\", \"he\")"),
            Value::Bool(true)
        ));
        assert!(matches!(
            eval("ends_with?(\"hello\", \"lo\")"),
            Value::Bool(true)
        ));
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
