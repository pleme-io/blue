use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::errors::raise_kind;

type Span = tatara_lisp::Span;

fn int(v: &Value, word: &'static str, span: Span) -> Result<i64, EvalError> {
    match v {
        Value::Int(n) => Ok(*n),
        other => Err(raise_kind(
            "type_error",
            format!("{word}: an Int, got {}", other.type_name()),
            span,
        )),
    }
}

fn distance(v: &Value, word: &'static str, span: Span) -> Result<u32, EvalError> {
    let n = int(v, word, span)?;
    u32::try_from(n).ok().filter(|d| *d < 64).ok_or_else(|| {
        raise_kind(
            "out_of_range",
            format!("{word}: a distance is 0..=63, got {n}"),
            span,
        )
    })
}

fn nonzero(v: &Value, word: &'static str, span: Span) -> Result<u64, EvalError> {
    let n = int(v, word, span)?;
    if n == 0 {
        return Err(raise_kind(
            "zero_division",
            format!("{word}: division by zero"),
            span,
        ));
    }
    Ok(n.cast_unsigned())
}

fn binary<H: 'static>(interp: &mut Interpreter<H>, word: &'static str, op: fn(i64, i64) -> i64) {
    interp.register_fn(word, Arity::Exact(2), move |a: &[Value], _: &mut H, s| {
        Ok(Value::Int(op(int(&a[0], word, s)?, int(&a[1], word, s)?)))
    });
}

fn shift<H: 'static>(interp: &mut Interpreter<H>, word: &'static str, op: fn(i64, u32) -> i64) {
    interp.register_fn(word, Arity::Exact(2), move |a: &[Value], _: &mut H, s| {
        Ok(Value::Int(op(
            int(&a[0], word, s)?,
            distance(&a[1], word, s)?,
        )))
    });
}

fn dividing<H: 'static>(interp: &mut Interpreter<H>, word: &'static str, op: fn(u64, u64) -> u64) {
    interp.register_fn(word, Arity::Exact(2), move |a: &[Value], _: &mut H, s| {
        let top = int(&a[0], word, s)?.cast_unsigned();
        Ok(Value::Int(op(top, nonzero(&a[1], word, s)?).cast_signed()))
    });
}

pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    binary(interp, "bit_and", |a, b| a & b);
    binary(interp, "bit_or", |a, b| a | b);
    binary(interp, "bit_xor", |a, b| a ^ b);
    interp.register_fn("bit_not", Arity::Exact(1), |a: &[Value], _: &mut H, s| {
        Ok(Value::Int(!int(&a[0], "bit_not", s)?))
    });
    shift(interp, "shift_left", |a, d| a << d);
    shift(interp, "shift_right", |a, d| a >> d);
    shift(interp, "shift_right_logical", |a, d| {
        (a.cast_unsigned() >> d).cast_signed()
    });
    binary(interp, "wrapping_add", i64::wrapping_add);
    binary(interp, "wrapping_sub", i64::wrapping_sub);
    binary(interp, "wrapping_mul", i64::wrapping_mul);
    interp.register_fn(
        "unsigned_less?",
        Arity::Exact(2),
        |a: &[Value], _: &mut H, s| {
            const W: &str = "unsigned_less?";
            Ok(Value::Bool(
                int(&a[0], W, s)?.cast_unsigned() < int(&a[1], W, s)?.cast_unsigned(),
            ))
        },
    );
    dividing(interp, "unsigned_div", |a, b| a / b);
    dividing(interp, "unsigned_mod", |a, b| a % b);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(src: &str) -> Result<Value, EvalError> {
        let mut interp = crate::interpreter_hostless();
        let forms = tatara_lisp::read_spanned(src).expect("reads");
        interp.eval_program(&forms, &mut ())
    }

    fn int_of(src: &str) -> i64 {
        match eval(src).unwrap_or_else(|e| panic!("{src}: {e}")) {
            Value::Int(n) => n,
            other => panic!("{src}: {other:?}"),
        }
    }

    fn kind(src: &str) -> String {
        match eval(src) {
            Err(EvalError::User {
                value: Value::Error(e),
                ..
            }) => e.tag.to_string(),
            other => panic!("{src}: {other:?}"),
        }
    }

    #[test]
    fn the_words_act_on_all_sixty_four_bits_in_twos_complement() {
        assert_eq!(int_of("(bit_and 12 10)"), 8);
        assert_eq!(int_of("(bit_or 12 10)"), 14);
        assert_eq!(int_of("(bit_xor 12 10)"), 6);
        assert_eq!(int_of("(bit_not 0)"), -1);
        assert_eq!(int_of("(shift_left 1 63)"), i64::MIN);
        assert_eq!(int_of("(shift_right -8 1)"), -4);
        assert_eq!(int_of("(shift_right_logical -1 60)"), 15);
    }

    #[test]
    fn wrapping_words_wrap_where_plus_raises() {
        assert_eq!(int_of("(wrapping_add 9223372036854775807 1)"), i64::MIN);
        assert_eq!(int_of("(wrapping_sub -9223372036854775807 2)"), i64::MAX);
        assert_eq!(int_of("(wrapping_mul 4294967296 4294967296)"), 0);
        assert!(eval("(+ 9223372036854775807 1)").is_err());
    }

    #[test]
    fn the_unsigned_words_read_the_top_bit_as_magnitude() {
        assert!(matches!(
            eval("(unsigned_less? 1 -1)"),
            Ok(Value::Bool(true))
        ));
        assert!(matches!(
            eval("(unsigned_less? -1 1)"),
            Ok(Value::Bool(false))
        ));
        assert_eq!(int_of("(unsigned_div -1 2)"), i64::MAX);
        assert_eq!(int_of("(unsigned_mod -1 16)"), 15);
    }

    #[test]
    fn a_bad_distance_a_zero_divisor_and_a_non_int_each_raise_by_name() {
        assert_eq!(kind("(shift_left 1 64)"), "out_of_range");
        assert_eq!(kind("(shift_right 1 -1)"), "out_of_range");
        assert_eq!(kind("(unsigned_div 1 0)"), "zero_division");
        assert_eq!(kind("(unsigned_mod 1 0)"), "zero_division");
        assert_eq!(kind("(bit_and 1.5 1)"), "type_error");
    }
}
