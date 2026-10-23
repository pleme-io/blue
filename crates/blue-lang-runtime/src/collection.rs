use tatara_lisp::Span;
use tatara_lisp_eval::ffi::{Arity, Caller};
use tatara_lisp_eval::value::MapKey;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

fn is_callable(v: &Value) -> bool {
    matches!(
        v,
        Value::Closure(_) | Value::NativeFn(_) | Value::Foreign(_)
    )
}

fn items(verb: &'static str, v: &Value, sp: Span) -> Result<Vec<Value>, EvalError> {
    match v {
        Value::Nil => Ok(Vec::new()),
        Value::List(xs) => Ok(xs.to_vec()),
        callable if is_callable(callable) => Err(EvalError::native_fn(
            verb,
            format!("takes the collection first: {verb}(xs, f)"),
            sp,
        )),
        other => Err(EvalError::type_mismatch("a list", other.type_name(), sp)),
    }
}

fn function<'a>(verb: &'static str, v: &'a Value, sp: Span) -> Result<&'a Value, EvalError> {
    if is_callable(v) {
        Ok(v)
    } else {
        Err(EvalError::native_fn(
            verb,
            format!(
                "{verb}(xs, f) takes a function second, got {}",
                v.type_name()
            ),
            sp,
        ))
    }
}

pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_higher_order_fn(
        "find",
        Arity::Exact(2),
        |a: &[Value], host: &mut H, caller: &Caller<H>, sp| {
            let legacy = is_callable(&a[0]) && matches!(a[1], Value::List(_) | Value::Nil);
            let (subject, query) = if legacy {
                (&a[1], &a[0])
            } else {
                (&a[0], &a[1])
            };
            let xs = items("find", subject, sp)?;
            let f = function("find", query, sp)?;
            for x in xs {
                if caller
                    .apply_value(f, vec![x.clone()], host, sp)?
                    .is_truthy()
                {
                    return Ok(x);
                }
            }
            Ok(Value::Nil)
        },
    );

    interp.register_higher_order_fn(
        "flat_map",
        Arity::Exact(2),
        |a: &[Value], host: &mut H, caller: &Caller<H>, sp| {
            let xs = items("flat_map", &a[0], sp)?;
            let f = function("flat_map", &a[1], sp)?;
            let mut out = Vec::new();
            for x in xs {
                match caller.apply_value(f, vec![x], host, sp)? {
                    Value::Nil => {}
                    Value::List(ys) => out.extend(ys.iter().cloned()),
                    other => {
                        return Err(EvalError::type_mismatch(
                            "a list from f",
                            other.type_name(),
                            sp,
                        ));
                    }
                }
            }
            Ok(Value::list(out))
        },
    );

    interp.register_higher_order_fn(
        "group_by",
        Arity::Exact(2),
        |a: &[Value], host: &mut H, caller: &Caller<H>, sp| {
            let xs = items("group_by", &a[0], sp)?;
            let f = function("group_by", &a[1], sp)?;
            let mut groups: std::collections::HashMap<MapKey, Vec<Value>> =
                std::collections::HashMap::new();
            for x in xs {
                let k = caller.apply_value(f, vec![x.clone()], host, sp)?;
                let key = MapKey::from_value(&k).ok_or_else(|| {
                    EvalError::native_fn(
                        "group_by",
                        format!("a group key must be a scalar, got {}", k.type_name()),
                        sp,
                    )
                })?;
                groups.entry(key).or_default().push(x);
            }
            Ok(Value::map(
                groups.into_iter().map(|(k, v)| (k, Value::list(v))),
            ))
        },
    );
}
