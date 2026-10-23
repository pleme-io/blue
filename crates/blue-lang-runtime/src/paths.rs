use std::sync::Arc;

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::value::{ErrorObj, MapKey};
use tatara_lisp_eval::{EvalError, Interpreter, Value};

const BAD_PATH: &str = "bad_path";

fn slot(items: usize, key: &Value) -> Option<usize> {
    match key {
        Value::Int(n) if *n >= 0 => usize::try_from(*n).ok().filter(|i| *i < items),
        Value::Int(n) => usize::try_from(n.unsigned_abs())
            .ok()
            .and_then(|back| items.checked_sub(back)),
        _ => None,
    }
}

#[must_use]
pub fn dig(tree: &Value, path: &[Value]) -> Value {
    let Some((key, rest)) = path.split_first() else {
        return tree.clone();
    };
    let child = match tree {
        Value::Map(m) => MapKey::from_value(key).and_then(|k| m.get(&k).cloned()),
        Value::List(xs) => slot(xs.len(), key).and_then(|i| xs.get(i).cloned()),
        _ => None,
    };
    match child {
        Some(c) => dig(&c, rest),
        None => Value::Nil,
    }
}

fn refusal(message: String, path: &[Value], at: usize, sp: tatara_lisp::Span) -> EvalError {
    let data = Value::map([
        (
            MapKey::Keyword(Arc::from("path")),
            Value::list(path.iter().cloned()),
        ),
        (MapKey::Keyword(Arc::from("at")), Value::Int(at as i64)),
    ]);
    EvalError::User {
        value: Value::Error(Arc::new(ErrorObj {
            tag: Arc::from(BAD_PATH),
            message: Arc::from(message),
            data: vec![(Value::Keyword(Arc::from("data")), data)],
        })),
        at: sp,
    }
}

fn bury(
    node: &Value,
    path: &[Value],
    depth: usize,
    value: &Value,
    whole: &[Value],
    sp: tatara_lisp::Span,
) -> Result<Value, EvalError> {
    let Some((key, rest)) = path.split_first() else {
        return Ok(value.clone());
    };
    let render = |v: &Value| crate::literal::render_value(v);
    match node {
        Value::Nil => {
            let Some(k) = MapKey::from_value(key) else {
                return Err(refusal(
                    format!("{} cannot be a key", render(key)),
                    whole,
                    depth,
                    sp,
                ));
            };
            let below = bury(&Value::Nil, rest, depth + 1, value, whole, sp)?;
            Ok(Value::map([(k, below)]))
        }
        Value::Map(m) => {
            let Some(k) = MapKey::from_value(key) else {
                return Err(refusal(
                    format!("{} cannot be a key", render(key)),
                    whole,
                    depth,
                    sp,
                ));
            };
            let current = m.get(&k).cloned().unwrap_or(Value::Nil);
            let below = bury(&current, rest, depth + 1, value, whole, sp)?;
            let mut out = (**m).clone();
            out.insert(k, below);
            Ok(Value::Map(Arc::new(out)))
        }
        Value::List(xs) => {
            let append = matches!(key, Value::Int(n) if usize::try_from(*n).is_ok_and(|i| i == xs.len()));
            let Some(i) = slot(xs.len(), key).or(append.then_some(xs.len())) else {
                return Err(refusal(
                    format!(
                        "{} is not an index of a list of {} elements",
                        render(key),
                        xs.len()
                    ),
                    whole,
                    depth,
                    sp,
                ));
            };
            let current = xs.get(i).cloned().unwrap_or(Value::Nil);
            let below = bury(&current, rest, depth + 1, value, whole, sp)?;
            let mut items = xs.to_vec();
            if i == items.len() {
                items.push(below);
            } else {
                items[i] = below;
            }
            Ok(Value::list(items))
        }
        other => Err(refusal(
            format!(
                "the value at step {depth} is {}, not a map or a list, so nothing can be buried under {}",
                other.type_name(),
                render(key)
            ),
            whole,
            depth,
            sp,
        )),
    }
}

pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn("dig", Arity::AtLeast(1), |a: &[Value], _h: &mut H, _s| {
        Ok(dig(&a[0], &a[1..]))
    });
    interp.register_fn("bury", Arity::AtLeast(2), |a: &[Value], _h: &mut H, s| {
        let (value, path) = a[1..].split_last().unwrap_or((&Value::Nil, &[]));
        bury(&a[0], path, 0, value, path, s)
    });
}
