use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::value::MapKey;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

fn entries<'a>(
    v: &'a Value,
    sp: tatara_lisp::Span,
) -> Result<Vec<(&'a MapKey, &'a Value)>, EvalError> {
    match v {
        Value::Nil => Ok(Vec::new()),
        Value::Map(m) => Ok(m.iter().collect()),
        other => Err(EvalError::type_mismatch(
            "a map to spread with `**`",
            other.type_name(),
            sp,
        )),
    }
}

pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        blue_lang_syntax::LOWERED_SPLICE,
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, sp| {
            entries(&a[0], sp)?;
            Ok(match &a[0] {
                Value::Nil => Value::map(std::iter::empty()),
                other => other.clone(),
            })
        },
    );
    for name in [
        blue_lang_syntax::LOWERED_MERGE,
        blue_lang_syntax::LOWERED_KWARGS,
    ] {
        interp.register_fn(name, Arity::AtLeast(1), |a: &[Value], _h: &mut H, sp| {
            let mut out: Vec<(MapKey, Value)> = Vec::new();
            for part in a {
                for (k, v) in entries(part, sp)? {
                    out.push((k.clone(), v.clone()));
                }
            }
            Ok(Value::map(out))
        });
    }
}
