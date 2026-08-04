//! JSON — parse, stringify, and read back — as blue's own surface.
//!
//! Pure computation with no host imports, so this is part of the runtime
//! unconditionally (the `wasm32-unknown-unknown` consumer keeps it). The
//! semantics are the substrate's — `tatara-lisp-script`'s `json.rs` is the
//! reference, and these are deliberately the same shapes — adapted to what
//! blue can actually reach:
//!
//! ```text
//! json_parse(s)          → nil / bool / int / float / string / list / alist
//! json_stringify(v)      → string
//! json_get(doc, key)     → value at key, or nil   (doc = alist or Map)
//! json_get_or(doc, key, default) → value at key, or default
//! ```
//!
//! # Why objects are alists, not Maps
//!
//! `Value::Map` is the representation that round-trips `{}` exactly — the
//! substrate proved that fix, and it is kept for the empty case — but a Map
//! has **no reachable reader**: every map primitive blue's own surface could
//! spell is kebab-case (`hash-map-get`), and `-` is an operator in blue, so a
//! `json_parse` that produced Maps would hand blue a document it could not
//! open. Non-empty objects therefore parse to an association list of
//! `[key value]` 2-lists, which blue reads with `car`/`cdr`/`nth`. `json_get`
//! is the Rust-side reader, total over both shapes.
//!
//! The cost is the same ambiguity the substrate records: a JSON array whose
//! every element is a 2-list with a string first still stringifies as an
//! object. Round-trip is exact for the shapes the fleet emits; the Map/List
//! split is where a future migration lands if the map reader becomes
//! reachable.

use std::collections::HashMap;
use std::sync::Arc;

use serde_json::Value as JsonValue;
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, MapKey, Value};

/// Install blue's JSON surface.
pub fn install_json_stdlib<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "json_parse",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let s = as_str(&args[0], "json_parse", span)?;
            let parsed: JsonValue = serde_json::from_str(&s)
                .map_err(|e| EvalError::native_fn("json_parse", e.to_string(), span))?;
            Ok(json_to_value(&parsed))
        },
    );

    interp.register_fn(
        "json_stringify",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let s = serde_json::to_string(&value_to_json(&args[0]))
                .map_err(|e| EvalError::native_fn("json_stringify", e.to_string(), span))?;
            Ok(Value::Str(Arc::from(s)))
        },
    );

    interp.register_fn(
        "json_get",
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| {
            let doc = &args[0];
            let key = as_str(&args[1], "json_get", span)?;
            match json_lookup(doc, &key) {
                Some(v) => Ok(v),
                None if is_doc(doc) => Ok(Value::Nil),
                None => Err(EvalError::native_fn(
                    "json_get",
                    format!("cannot read a field from a {}", doc.type_name()),
                    span,
                )),
            }
        },
    );

    interp.register_fn(
        "json_get_or",
        Arity::Exact(3),
        |args: &[Value], _h: &mut H, span| {
            let doc = &args[0];
            let key = as_str(&args[1], "json_get_or", span)?;
            match json_lookup(doc, &key) {
                Some(v) => Ok(v),
                None if is_doc(doc) => Ok(args[2].clone()),
                None => Err(EvalError::native_fn(
                    "json_get_or",
                    format!("cannot read a field from a {}", doc.type_name()),
                    span,
                )),
            }
        },
    );
}

/// A document is an alist (non-empty object) or a Map (empty object). Anything
/// else — a string, a number — has no fields, and reading from it is an error
/// rather than a silent nil, which is the drift this crate exists to catch.
fn is_doc(v: &Value) -> bool {
    matches!(v, Value::List(_) | Value::Map(_))
}

fn as_str(v: &Value, fname: &'static str, span: tatara_lisp::Span) -> Result<String, EvalError> {
    match v {
        Value::Str(s) => Ok(s.to_string()),
        // A symbol/keyword is text the author wrote; `json_get` names a field
        // with `"outcome"` today, but `:outcome` should not surprise.
        Value::Symbol(s) | Value::Keyword(s) => Ok(s.to_string()),
        other => Err(EvalError::type_mismatch("a string", other.type_name(), span)
            .into_native(fname)),
    }
}

/// Attach the primitive's name to a type error so the raised message names the
/// offender, matching the style of the named parse/serialise errors.
trait NameError {
    fn into_native(self, fname: &'static str) -> EvalError;
}

impl NameError for EvalError {
    fn into_native(self, fname: &'static str) -> EvalError {
        match self {
            EvalError::TypeMismatch { expected, got, at } => EvalError::native_fn(
                fname,
                format!("expected {expected}, got {got}"),
                at,
            ),
            other => other,
        }
    }
}

/// Convert a `serde_json::Value` into a `Value`. Objects become association
/// lists of `[key value]` 2-lists; the EMPTY object is `Value::Map`, the one
/// representation that can say "object with no entries" and round-trip.
pub fn json_to_value(j: &JsonValue) -> Value {
    match j {
        JsonValue::Null => Value::Nil,
        JsonValue::Bool(b) => Value::Bool(*b),
        JsonValue::Number(n) => {
            if let Some(i) = n.as_i64() {
                Value::Int(i)
            } else {
                Value::Float(n.as_f64().unwrap_or(0.0))
            }
        }
        JsonValue::String(s) => Value::Str(Arc::from(s.as_str())),
        JsonValue::Array(xs) => Value::List(Arc::new(xs.iter().map(json_to_value).collect())),
        JsonValue::Object(m) if m.is_empty() => Value::Map(Arc::new(HashMap::new())),
        JsonValue::Object(m) => Value::List(Arc::new(
            m.iter()
                .map(|(k, v)| {
                    Value::List(Arc::new(vec![Value::Str(Arc::from(k.as_str())), json_to_value(v)]))
                })
                .collect(),
        )),
    }
}

/// Convert a `Value` back into a `serde_json::Value`. Closures and native
/// functions collapse to `null`.
pub fn value_to_json(v: &Value) -> JsonValue {
    match v {
        Value::Nil => JsonValue::Null,
        Value::Bool(b) => JsonValue::Bool(*b),
        Value::Int(n) => JsonValue::Number((*n).into()),
        Value::Float(n) => serde_json::Number::from_f64(*n)
            .map(JsonValue::Number)
            .unwrap_or(JsonValue::Null),
        Value::Str(s) | Value::Symbol(s) | Value::Keyword(s) => {
            JsonValue::String(s.as_ref().to_owned())
        }
        // A list that is entirely `[string, anything]` pairs IS an object —
        // that is what `json_to_value` produced, so the round-trip is exact
        // for documents blue parsed. A genuine array of such pairs is the
        // ambiguity recorded at the top of this module.
        Value::List(xs) => {
            let looks_like_object = !xs.is_empty()
                && xs.iter().all(|entry| {
                    if let Value::List(pair) = entry {
                        pair.len() == 2
                            && matches!(pair[0], Value::Str(_) | Value::Symbol(_) | Value::Keyword(_))
                    } else {
                        false
                    }
                });
            if looks_like_object {
                let mut m = serde_json::Map::with_capacity(xs.len());
                for entry in xs.iter() {
                    if let Value::List(pair) = entry {
                        let k = match &pair[0] {
                            Value::Str(s) | Value::Symbol(s) | Value::Keyword(s) => {
                                s.as_ref().to_owned()
                            }
                            _ => unreachable!(),
                        };
                        m.insert(k, value_to_json(&pair[1]));
                    }
                }
                JsonValue::Object(m)
            } else {
                JsonValue::Array(xs.iter().map(value_to_json).collect())
            }
        }
        // A Map is unambiguously an object — the only Value that is. Keys
        // render through their scalar spelling rather than being dropped: a
        // silently vanished entry is worse than one findable under "1" or
        // "true".
        Value::Map(m) => JsonValue::Object(
            m.iter()
                .map(|(k, v)| (map_key_to_json_key(k), value_to_json(v)))
                .collect(),
        ),
        _ => JsonValue::Null,
    }
}

fn map_key_to_json_key(k: &MapKey) -> String {
    match k {
        MapKey::Str(s) | MapKey::Symbol(s) | MapKey::Keyword(s) => s.as_ref().to_owned(),
        MapKey::Nil => "null".to_owned(),
        MapKey::Bool(b) => b.to_string(),
        MapKey::Int(n) => n.to_string(),
        MapKey::Float(bits) => f64::from_bits(*bits).to_string(),
    }
}

/// Read `key` from a parsed JSON document, in either representation —
/// an association list of `[key value]` pairs or a `Value::Map`.
fn json_lookup(doc: &Value, key: &str) -> Option<Value> {
    match doc {
        Value::List(entries) => entries.iter().find_map(|entry| {
            let Value::List(pair) = entry else { return None };
            if pair.len() != 2 {
                return None;
            }
            let matches = match &pair[0] {
                Value::Str(s) | Value::Symbol(s) | Value::Keyword(s) => s.as_ref() == key,
                _ => false,
            };
            matches.then(|| pair[1].clone())
        }),
        Value::Map(m) => {
            let k = MapKey::Str(Arc::from(key));
            m.get(&k).cloned()
        }
        _ => None,
    }
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

    /// Round-trip is identity on the parsed value — the property the
    /// read-a-doc / touch-one-leaf / write-it-back idiom rests on. Compared as
    /// parsed JSON so key order is not asserted.
    fn assert_round_trips(src: &str) {
        let parsed: JsonValue = serde_json::from_str(src).expect("fixture is valid JSON");
        let out = value_to_json(&json_to_value(&parsed));
        assert_eq!(out, parsed, "round-trip changed the document\nin:  {src}");
    }

    #[test]
    fn parse_and_get_an_object_field() {
        let v = eval(r#"json_get(json_parse("{\"outcome\":\"ok\"}"), "outcome")"#);
        assert!(
            matches!(v, Value::Str(ref x) if &**x == "ok"),
            "got {v:?}"
        );
    }

    #[test]
    fn a_missing_field_is_nil_not_an_error() {
        assert!(matches!(
            eval(r#"json_get(json_parse("{\"a\":1}"), "nope")"#),
            Value::Nil
        ));
    }

    #[test]
    fn json_get_or_returns_the_default() {
        assert!(matches!(
            eval(r#"json_get_or(json_parse("{}"), "nope", 42)"#),
            Value::Int(42)
        ));
    }

    #[test]
    fn nested_objects_read_by_walking_alists() {
        let src = r#"json_get(
          json_get(json_parse("{\"outer\":{\"inner\":7}}"), "outer"),
          "inner")"#;
        assert!(matches!(eval(src), Value::Int(7)));
    }

    #[test]
    fn numbers_and_bools_keep_their_kinds() {
        assert!(matches!(
            eval(r#"json_get(json_parse("{\"n\":1,\"b\":true}"), "n")"#),
            Value::Int(1)
        ));
        assert!(matches!(
            eval(r#"json_get(json_parse("{\"b\":true}"), "b")"#),
            Value::Bool(true)
        ));
    }

    #[test]
    fn null_is_nil() {
        assert!(matches!(
            eval(r#"json_get(json_parse("{\"x\":null}"), "x")"#),
            Value::Nil
        ));
    }

    #[test]
    fn stringify_reaches_the_parser_shape_back() {
        assert_eq!(
            s(r#"json_stringify(json_parse("{\"a\":1,\"b\":[1,2]}"))"#),
            r#"{"a":1,"b":[1,2]}"#
        );
    }

    #[test]
    fn empty_object_round_trips() {
        assert_round_trips("{}");
        assert_round_trips(r#"{"a":{}}"#);
        assert_round_trips(r#"{"a":{"b":{}}}"#);
        assert_round_trips(r#"[{},{}]"#);
    }

    #[test]
    fn empty_array_is_not_confused_for_an_object() {
        assert_round_trips("[]");
        assert_round_trips(r#"{"a":[]}"#);
        assert_round_trips(r#"{"obj":{},"arr":[]}"#);
    }

    #[test]
    fn non_empty_objects_parse_to_alists() {
        let v = eval(r#"json_parse("{\"a\":1}")"#);
        assert!(matches!(v, Value::List(_)), "non-empty object must be an alist");
    }

    #[test]
    fn a_parsed_empty_object_is_a_map_and_reads_as_nil() {
        let v = eval(r#"json_parse("{}")"#);
        assert!(matches!(v, Value::Map(_)), "an empty object must be a Map so it round-trips");
        assert!(
            matches!(
                eval(r#"json_get(json_parse("{}"), "anything")"#),
                Value::Nil
            ),
            "an empty object has no fields to read"
        );
    }

    #[test]
    fn unparseable_json_is_a_named_error() {
        let err = crate::run(r#"json_parse("{not json")"#).expect_err("must raise");
        assert!(
            err.to_string().contains("json_parse"),
            "the error must name the primitive: {err}"
        );
    }

    #[test]
    fn a_wrong_typed_argument_is_a_type_error() {
        assert!(crate::run(r#"json_parse(42)"#).is_err());
        assert!(crate::run(r#"json_get("not a doc", "k")"#).is_err());
    }
}
