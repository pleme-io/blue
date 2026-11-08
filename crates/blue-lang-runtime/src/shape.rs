use std::sync::Arc;

use blue_lang_syntax::pattern::{SHAPE_AT, SHAPE_FROM, SHAPE_KEY, SHAPE_LIST, SHAPE_REFUSE};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::value::MapKey;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::errors::raise_kind_with;

fn index(v: &Value) -> Option<usize> {
    match v {
        Value::Int(i) => usize::try_from(*i).ok(),
        _ => None,
    }
}

fn key_of(v: &Value) -> Option<MapKey> {
    match v {
        Value::Keyword(k) => Some(MapKey::Keyword(k.clone())),
        _ => None,
    }
}

fn holds_key(v: &Value, k: &Value) -> bool {
    match (v, key_of(k)) {
        (Value::Map(m), Some(key)) => m.get(&key).is_some(),
        _ => false,
    }
}

fn list_shape(v: &Value, n: &Value, open: &Value) -> bool {
    let (Value::List(xs), Some(n)) = (v, index(n)) else {
        return false;
    };
    match open {
        Value::Bool(true) => xs.len() >= n,
        _ => xs.len() == n,
    }
}

fn at(v: &Value, k: &Value) -> Value {
    match (v, k) {
        (Value::List(xs), k) => index(k)
            .and_then(|i| xs.get(i).cloned())
            .unwrap_or(Value::Nil),
        (Value::Map(m), k) => key_of(k)
            .and_then(|key| m.get(&key).cloned())
            .unwrap_or(Value::Nil),
        _ => Value::Nil,
    }
}

fn from(v: &Value, i: &Value) -> Value {
    match (v, index(i)) {
        (Value::List(xs), Some(i)) => Value::list(xs.iter().skip(i).cloned()),
        _ => Value::list(std::iter::empty()),
    }
}

fn shown(v: &Value) -> String {
    match v {
        Value::List(xs) => format!("a list of {}", xs.len()),
        Value::Map(_) => crate::record::name_of(v).map_or_else(
            || "a map without those keys".to_string(),
            |n| format!("a `{n}` record"),
        ),
        other => other.type_name().to_string(),
    }
}

pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(SHAPE_LIST, Arity::Exact(3), |a: &[Value], _: &mut H, _| {
        Ok(Value::Bool(list_shape(&a[0], &a[1], &a[2])))
    });
    interp.register_fn(SHAPE_KEY, Arity::Exact(2), |a: &[Value], _: &mut H, _| {
        Ok(Value::Bool(holds_key(&a[0], &a[1])))
    });
    interp.register_fn(SHAPE_AT, Arity::Exact(2), |a: &[Value], _: &mut H, _| {
        Ok(at(&a[0], &a[1]))
    });
    interp.register_fn(SHAPE_FROM, Arity::Exact(2), |a: &[Value], _: &mut H, _| {
        Ok(from(&a[0], &a[1]))
    });
    interp.register_fn(
        SHAPE_REFUSE,
        Arity::Exact(2),
        |a: &[Value], _: &mut H, sp| -> Result<Value, EvalError> {
            let pattern = match &a[0] {
                Value::Str(s) => s.to_string(),
                other => other.type_name().to_string(),
            };
            let data = Value::map([
                (
                    MapKey::Keyword(Arc::from("pattern")),
                    Value::Str(Arc::from(pattern.as_str())),
                ),
                (MapKey::Keyword(Arc::from("value")), a[1].clone()),
            ]);
            Err(raise_kind_with(
                "pattern",
                format!("`{pattern}` does not match {}", shown(&a[1])),
                data,
                sp,
            ))
        },
    );
}
