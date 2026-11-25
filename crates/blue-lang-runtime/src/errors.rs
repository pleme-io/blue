use std::borrow::Cow;
use std::sync::Arc;

use tatara_lisp_eval::ffi::{Arity, Caller};
use tatara_lisp_eval::value::{ErrorObj, MapKey};
use tatara_lisp_eval::{EvalError, Interpreter, Value};

pub const RAISE_AT: &str = "blue-raise-at";

const DATA: &str = "data";
const CAUSE: &str = "cause";
const TRACE: &str = "trace";

const WORDING: &[(&str, &str, &str)] = &[
    ("car", "car of empty list", "the list is too short"),
    ("cdr", "cdr of empty list", "the list is too short"),
];

#[must_use]
pub fn kind_word(tag: &str) -> Cow<'_, str> {
    if tag.contains('-') {
        Cow::Owned(tag.replace('-', "_"))
    } else {
        Cow::Borrowed(tag)
    }
}

#[must_use]
pub fn native_words(name: &str, reason: &str) -> Option<&'static str> {
    WORDING
        .iter()
        .find(|(n, r, _)| *n == name && *r == reason)
        .map(|(_, _, words)| *words)
}

fn message_words(message: &str) -> Option<&'static str> {
    let rest = message.strip_prefix("in native `")?;
    WORDING
        .iter()
        .find(|(n, r, _)| {
            rest.strip_prefix(n)
                .and_then(|m| m.strip_prefix("`: "))
                .is_some_and(|m| m == *r)
        })
        .map(|(_, _, words)| *words)
}

#[must_use]
pub fn kind_of(e: &ErrorObj) -> Arc<str> {
    match kind_word(&e.tag) {
        Cow::Borrowed(_) => e.tag.clone(),
        Cow::Owned(k) => Arc::from(k),
    }
}

#[must_use]
pub fn message_of(e: &ErrorObj) -> Arc<str> {
    message_words(&e.message).map_or_else(|| e.message.clone(), Arc::from)
}

#[must_use]
pub fn in_blue_words(v: &Value) -> Value {
    let Value::Error(e) = v else {
        return v.clone();
    };
    let respelled = matches!(kind_word(&e.tag), Cow::Owned(_));
    let reworded = message_words(&e.message).is_some();
    if !respelled && !reworded {
        return v.clone();
    }
    Value::Error(Arc::new(ErrorObj {
        tag: kind_of(e),
        message: message_of(e),
        data: e.data.clone(),
    }))
}

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
    let mut out = format!("{}: {}", kind_word(&e.tag), message_of(e));
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
            for (k, v) in blue_lang_proc::order::sorted_entries(m) {
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

pub fn raise_kind(kind: &str, message: String, sp: tatara_lisp::Span) -> EvalError {
    raise_kind_with(kind, message, Value::Nil, sp)
}

pub fn raise_kind_with(
    kind: &str,
    message: String,
    data: Value,
    sp: tatara_lisp::Span,
) -> EvalError {
    blue_lang_proc::raised(kind, message, data, sp)
}

fn field(v: &Value, name: &str, sp: tatara_lisp::Span) -> Result<Value, EvalError> {
    let missing = |what: String| Err(EvalError::native_fn(format!(".{name}"), what, sp));
    if name == blue_lang_syntax::NIL_TEST {
        return Ok(Value::Bool(matches!(v, Value::Nil)));
    }
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
                            MapKey::Keyword(s) if &**s == blue_lang_syntax::record::RECORD_TAG => {
                                None
                            }
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
            "kind" => Value::Keyword(kind_of(e)),
            "message" => Value::Str(message_of(e)),
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
    let kind = match v {
        Value::Error(e) => Some(kind_word(&e.tag)),
        _ => None,
    };
    kinds.iter().any(|k| match (k, &kind) {
        (Value::Keyword(k), Some(t)) => **k == **t,
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
        blue_lang_syntax::LOWERED_CAUGHT,
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, _s| Ok(in_blue_words(&a[0])),
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

#[cfg(test)]
mod tests {
    use super::*;
    use tatara_lisp::Span;
    use tatara_lisp_eval::error::BudgetDimension;
    use tatara_lisp_eval::Seal;

    fn every_error() -> Vec<EvalError> {
        let at = Span::synthetic();
        let every = vec![
            EvalError::UnboundSymbol {
                name: Arc::from("x"),
                at,
            },
            EvalError::ArityMismatch {
                fn_name: Arc::from("f"),
                expected: Arity::Exact(1),
                got: 2,
                at,
            },
            EvalError::TypeMismatch {
                expected: "map",
                got: "nil",
                at,
            },
            EvalError::DivisionByZero { at },
            EvalError::IntegerOverflow { op: "+", at },
            EvalError::MacroExpansionLimit {
                macro_name: Arc::from("m"),
                limit: 1,
                at,
            },
            EvalError::NotCallable {
                value_kind: "int",
                at,
            },
            EvalError::SetSealed {
                name: Arc::from("x"),
                seal: Seal::Fork,
                at,
            },
            EvalError::BadSpecialForm {
                form: Arc::from("if"),
                reason: "r".to_string(),
                at,
            },
            EvalError::NativeFn {
                name: Arc::from("car"),
                reason: "car of empty list".to_string(),
                at,
            },
            EvalError::from(tatara_lisp::read_spanned("(").expect_err("an open list")),
            EvalError::Halted,
            EvalError::Fatal {
                kind: Arc::from("k"),
                message: Arc::from("m"),
                at,
            },
            EvalError::BudgetExceeded {
                dimension: BudgetDimension::Depth,
                limit: 1,
                function: None,
                at,
            },
            EvalError::BudgetExceeded {
                dimension: BudgetDimension::Fuel,
                limit: 1,
                function: None,
                at,
            },
            EvalError::NotImplemented("x"),
            EvalError::User {
                value: Value::Nil,
                at,
            },
        ];
        for e in &every {
            match e {
                EvalError::UnboundSymbol { .. }
                | EvalError::ArityMismatch { .. }
                | EvalError::TypeMismatch { .. }
                | EvalError::DivisionByZero { .. }
                | EvalError::IntegerOverflow { .. }
                | EvalError::MacroExpansionLimit { .. }
                | EvalError::NotCallable { .. }
                | EvalError::SetSealed { .. }
                | EvalError::BadSpecialForm { .. }
                | EvalError::NativeFn { .. }
                | EvalError::Reader(_)
                | EvalError::Halted
                | EvalError::Fatal { .. }
                | EvalError::BudgetExceeded { .. }
                | EvalError::NotImplemented(_)
                | EvalError::User { .. } => {}
            }
        }
        every
    }

    fn raw(tag: &str, message: &str) -> Value {
        Value::Error(Arc::new(ErrorObj {
            tag: Arc::from(tag),
            message: Arc::from(message),
            data: Vec::new(),
        }))
    }

    #[test]
    fn every_runtime_kind_is_a_keyword_a_rescue_can_name() {
        for e in every_error() {
            let tag = e.tag();
            let kind = kind_word(tag);
            let src = format!("begin\n  1\nrescue :{kind}\n  2\nend\n");
            let tree = blue_lang_syntax::parse_program(&src).expect("a rescue parses");
            let lowered = tree[0].to_string();
            assert!(
                lowered.contains(&format!("(blue-rescues? rescued-error :{kind})")),
                "`{tag}` reads as `:{kind}`, which a rescue does not name: {lowered}"
            );
            assert!(
                blue_lang_syntax::spelling_notes(&src)
                    .expect("a rescue parses")
                    .is_empty(),
                "`:{kind}` is not the one spelling of `{tag}`"
            );
            assert!(
                kind_matches(&raw(tag, "m"), &[Value::Keyword(Arc::from(&*kind))]),
                "`rescue :{kind}` does not catch an error tatara tags `{tag}`"
            );
        }
    }

    #[test]
    fn a_caught_list_fault_names_no_lisp_word() {
        for message in [
            "in native `car`: car of empty list",
            "in native `cdr`: cdr of empty list",
        ] {
            let Value::Error(e) = in_blue_words(&raw("native-fn", message)) else {
                panic!("an error stays an error");
            };
            assert_eq!(
                (&*e.tag, &*e.message),
                ("native_fn", "the list is too short")
            );
        }
        let Value::Error(e) = in_blue_words(&raw(
            "native-fn",
            "in native `to_int!`: `x` is not an integer",
        )) else {
            panic!("an error stays an error");
        };
        assert_eq!(&*e.message, "in native `to_int!`: `x` is not an integer");
    }

    #[test]
    fn an_error_already_in_blue_words_passes_the_seam_unchanged() {
        let v = raw("not_found", "no repo");
        let (Value::Error(before), Value::Error(after)) = (&v, in_blue_words(&v)) else {
            panic!("an error stays an error");
        };
        assert!(Arc::ptr_eq(before, &after));
        assert!(matches!(in_blue_words(&Value::Int(1)), Value::Int(1)));
    }
}
