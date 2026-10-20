use std::sync::Arc;

use tatara_lisp_eval::ffi::{Arity, Caller};
use tatara_lisp_eval::value::{ErrorObj, MapKey};
use tatara_lisp_eval::{EvalError, Interpreter, Value};

pub const RAISE_AT: &str = "blue-raise-at";

const DATA: &str = "data";
const CAUSE: &str = "cause";
const TRACE: &str = "trace";

fn keyword(s: &str) -> Value {
    Value::Keyword(Arc::from(s))
}

fn data_key(k: &Value) -> Option<&str> {
    match k {
        Value::Keyword(s) => Some(s),
        _ => None,
    }
}

fn raised_by_blue(e: &ErrorObj) -> bool {
    !e.data.is_empty()
        && e.data
            .iter()
            .all(|(k, _)| matches!(data_key(k), Some(DATA | CAUSE | TRACE)))
}

fn entry<'a>(e: &'a ErrorObj, name: &str) -> Option<&'a Value> {
    e.data
        .iter()
        .find(|(k, _)| data_key(k) == Some(name))
        .map(|(_, v)| v)
}

#[must_use]
pub fn error_data(e: &ErrorObj) -> Value {
    if raised_by_blue(e) {
        return entry(e, DATA).cloned().unwrap_or(Value::Nil);
    }
    if e.data.is_empty() {
        return Value::Nil;
    }
    Value::map(
        e.data
            .iter()
            .filter_map(|(k, v)| MapKey::from_value(k).map(|key| (key, v.clone()))),
    )
}

#[must_use]
pub fn error_cause(e: &ErrorObj) -> Value {
    if raised_by_blue(e) {
        return entry(e, CAUSE).cloned().unwrap_or(Value::Nil);
    }
    Value::Nil
}

#[must_use]
pub fn error_trace(e: &ErrorObj) -> Vec<String> {
    if !raised_by_blue(e) {
        return Vec::new();
    }
    match entry(e, TRACE) {
        Some(Value::List(xs)) => xs
            .iter()
            .filter_map(|x| match x {
                Value::Str(s) => Some(s.to_string()),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

#[must_use]
pub fn describe(e: &ErrorObj) -> String {
    let mut out = format!("{}: {}", e.tag, e.message);
    if let Some(at) = error_trace(e).first() {
        out.push_str(&format!(" (at {at})"));
    }
    out
}

#[must_use]
pub fn chain(value: &Value) -> Vec<String> {
    let mut out = Vec::new();
    let mut at = value.clone();
    while let Value::Error(e) = at {
        out.push(describe(&e));
        if out.len() > 64 {
            break;
        }
        at = error_cause(&e);
    }
    out
}

fn build(
    kind: &Value,
    message: &Value,
    opts: Option<&Value>,
    trace: Option<String>,
    sp: tatara_lisp::Span,
) -> Result<Value, EvalError> {
    let tag: Arc<str> = match kind {
        Value::Keyword(s) | Value::Symbol(s) => s.clone(),
        other => {
            return Err(EvalError::type_mismatch(
                "an error kind such as :not_found",
                other.type_name(),
                sp,
            ))
        }
    };
    let message: Arc<str> = match message {
        Value::Str(s) => s.clone(),
        other => {
            return Err(EvalError::type_mismatch(
                "a message string",
                other.type_name(),
                sp,
            ))
        }
    };
    let mut data = Vec::new();
    match opts {
        None | Some(Value::Nil) => {}
        Some(Value::Map(m)) => {
            for (k, v) in m.iter() {
                match k {
                    MapKey::Keyword(name) | MapKey::Symbol(name)
                        if matches!(&**name, DATA | CAUSE) =>
                    {
                        data.push((keyword(name), v.clone()));
                    }
                    other => {
                        return Err(EvalError::native_fn(
                            "raise",
                            format!(
                                "its options are {{data: …, cause: …}}, and `{}` is neither",
                                crate::literal::render_value(&other.to_value())
                            ),
                            sp,
                        ))
                    }
                }
            }
        }
        Some(other) => {
            return Err(EvalError::type_mismatch(
                "raise's options {data: …, cause: …}",
                other.type_name(),
                sp,
            ))
        }
    }
    if let Some(at) = trace {
        data.push((keyword(TRACE), Value::list(vec![Value::Str(Arc::from(at))])));
    }
    if data.is_empty() {
        data.push((keyword(DATA), Value::Nil));
    }
    Ok(Value::Error(Arc::new(ErrorObj { tag, message, data })))
}

fn raise_with(
    args: &[Value],
    trace: Option<String>,
    sp: tatara_lisp::Span,
) -> Result<Value, EvalError> {
    let value = match args {
        [single] => single.clone(),
        [kind, message] => build(kind, message, None, trace, sp)?,
        [kind, message, opts] => build(kind, message, Some(opts), trace, sp)?,
        _ => {
            return Err(EvalError::native_fn(
                "raise",
                "write raise(:kind, \"message\"), raise(:kind, \"message\", {data: …, cause: e}) or raise(e)",
                sp,
            ))
        }
    };
    Err(EvalError::User { value, at: sp })
}

fn field(v: &Value, name: &str, sp: tatara_lisp::Span) -> Result<Value, EvalError> {
    let missing = |what: String| Err(EvalError::native_fn(format!(".{name}"), what, sp));
    match v {
        Value::Map(m) => {
            let found = m
                .iter()
                .find(|(k, _)| matches!(k, MapKey::Keyword(s) | MapKey::Str(s) if &**s == name))
                .map(|(_, v)| v.clone());
            match found {
                Some(x) => Ok(x),
                None => {
                    let mut fields: Vec<String> = m
                        .iter()
                        .filter_map(|(k, _)| match k {
                            MapKey::Keyword(s) | MapKey::Str(s) => Some(s.to_string()),
                            _ => None,
                        })
                        .collect();
                    fields.sort();
                    missing(format!(
                        "the record has no field `{name}` (its fields: {}); get(m, :{name}) reads a field that may be absent",
                        if fields.is_empty() { "none".to_string() } else { fields.join(", ") }
                    ))
                }
            }
        }
        Value::Error(e) => Ok(match name {
            "kind" => Value::Keyword(e.tag.clone()),
            "message" => Value::Str(e.message.clone()),
            DATA => error_data(e),
            CAUSE => error_cause(e),
            TRACE => Value::list(
                error_trace(e)
                    .into_iter()
                    .map(|s| Value::Str(Arc::from(s))),
            ),
            other => {
                return missing(format!(
                    "an error's fields are kind, message, data, cause and trace, not `{other}`"
                ))
            }
        }),
        Value::List(items) => {
            let pairs = !items.is_empty()
                && items.iter().all(|i| {
                    matches!(i, Value::List(p) if p.len() == 2 && matches!(p[0], Value::Keyword(_) | Value::Str(_)))
                });
            if pairs {
                for i in items.iter() {
                    if let Value::List(p) = i {
                        if matches!(&p[0], Value::Keyword(k) | Value::Str(k) if &**k == name) {
                            return Ok(p[1].clone());
                        }
                    }
                }
                return missing(format!("the record has no field `{name}`"));
            }
            missing(format!(
                "`.{name}` reads a record's field, and a list has none: to call `{name}` on it, write `{name}(xs)`"
            ))
        }
        other => missing(format!(
            "`.{name}` reads a record's field, and {} has none: to call `{name}` on it, write `{name}(x)`",
            other.type_name()
        )),
    }
}

fn kind_matches(v: &Value, kinds: &[Value]) -> bool {
    let tag: Option<&str> = match v {
        Value::Error(e) => Some(&e.tag),
        _ => None,
    };
    kinds.iter().any(|k| match (k, tag) {
        (Value::Keyword(k), Some(t)) => &**k == t,
        _ => false,
    })
}

pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn("raise", Arity::Range(1, 3), |a: &[Value], _h: &mut H, s| {
        raise_with(a, None, s)
    });
    interp.register_fn(
        RAISE_AT,
        Arity::Range(2, 4),
        |a: &[Value], _h: &mut H, s| {
            let at = match &a[0] {
                Value::Str(x) => Some(x.to_string()),
                _ => None,
            };
            raise_with(&a[1..], at, s)
        },
    );
    interp.register_fn(
        blue_lang_syntax::LOWERED_RERAISE,
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| {
            Err(EvalError::User {
                value: a[0].clone(),
                at: s,
            })
        },
    );
    interp.register_fn(
        blue_lang_syntax::LOWERED_ERROR_MATCH,
        Arity::AtLeast(2),
        |a: &[Value], _h: &mut H, _s| Ok(Value::Bool(kind_matches(&a[0], &a[1..]))),
    );
    interp.register_fn(
        blue_lang_syntax::LOWERED_FIELD,
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, s| match &a[1] {
            Value::Keyword(k) => field(&a[0], k, s),
            other => Err(EvalError::type_mismatch(
                "a field name",
                other.type_name(),
                s,
            )),
        },
    );
    interp.register_fn(
        blue_lang_syntax::LOWERED_ATTEMPTED,
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, _s| Ok(Value::list(vec![keyword("ok"), a[0].clone()])),
    );
    interp.register_fn(
        blue_lang_syntax::LOWERED_FAILED,
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, _s| Ok(Value::list(vec![keyword("raised"), a[0].clone()])),
    );
    interp.register_higher_order_fn(
        blue_lang_syntax::LOWERED_ENSURE,
        Arity::Exact(2),
        |a: &[Value], host: &mut H, caller: &Caller<H>, s| {
            caller.apply_value(&a[1], Vec::new(), host, s)?;
            match &a[0] {
                Value::List(p) if p.len() == 2 => match &p[0] {
                    Value::Keyword(k) if &**k == "raised" => Err(EvalError::User {
                        value: p[1].clone(),
                        at: s,
                    }),
                    _ => Ok(p[1].clone()),
                },
                other => Ok(other.clone()),
            }
        },
    );
}
