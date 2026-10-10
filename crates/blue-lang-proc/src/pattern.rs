//! Selective receive: a pattern is data, matched without running blue code.
//!
//! blue has no destructuring `case` yet, so the matcher a selective `receive`
//! needs cannot be a blue pattern. It is a VALUE instead: `:_` matches
//! anything, a list matches a list of the same length element by element, a
//! map matches a map holding at least its keys, and anything else matches a
//! value equal to it under blue's `==` (so `4` matches `4.0`).
//!
//! ```text
//! receive([:reply, ref, :_])     the first reply carrying this ref
//! receive({kind: :tick})          the first map whose kind is :tick
//! ```
//!
//! Being data rather than a function is what lets the readiness phase of
//! `receive` ask "is there a match?" holding only `&` access to the mailbox:
//! calling a blue predicate there would need the evaluator, and the two-phase
//! split exists so that phase cannot consume anything.

use std::collections::VecDeque;

use tatara_lisp_eval::{MapKey, Value};

/// The wildcard keyword's name.
pub const WILDCARD: &str = "_";

/// Does `value` match `pattern`?
#[must_use]
pub fn matches(pattern: &Value, value: &Value) -> bool {
    match (pattern, value) {
        (Value::Keyword(k), _) if k.trim_start_matches(':') == WILDCARD => true,
        (Value::List(p), Value::List(v)) => {
            p.len() == v.len() && p.iter().zip(v.iter()).all(|(p, v)| matches(p, v))
        }
        (Value::Map(p), Value::Map(v)) => p
            .iter()
            .all(|(k, pv)| v.get(k).is_some_and(|vv| matches(pv, vv))),
        _ => data_eq(pattern, value),
    }
}

/// The index of the oldest message in `mailbox` that `pattern` matches.
///
/// Takes the mailbox by shared reference on purpose: this is what a waiting
/// `receive` asks in its readiness phase, where nothing may be taken.
#[must_use]
pub fn first_match(mailbox: &VecDeque<Value>, pattern: &Value) -> Option<usize> {
    mailbox.iter().position(|m| matches(pattern, m))
}

/// Structural equality over data, with blue's numeric rule (`4 == 4.0`).
///
/// Non-data values (functions, handles) are equal to nothing, which is the
/// honest answer for a value that can never arrive in a mailbox.
#[must_use]
pub fn data_eq(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Nil, Value::Nil) => true,
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::Int(x), Value::Int(y)) => x == y,
        (Value::Float(x), Value::Float(y)) => x == y,
        #[allow(clippy::cast_precision_loss)]
        (Value::Int(x), Value::Float(y)) | (Value::Float(y), Value::Int(x)) => (*x as f64) == *y,
        (Value::Str(x), Value::Str(y))
        | (Value::Symbol(x), Value::Symbol(y))
        | (Value::Keyword(x), Value::Keyword(y)) => x == y,
        (Value::List(x), Value::List(y)) => {
            x.len() == y.len() && x.iter().zip(y.iter()).all(|(a, b)| data_eq(a, b))
        }
        (Value::Map(x), Value::Map(y)) => {
            x.len() == y.len()
                && x.iter()
                    .all(|(k, v): (&MapKey, &Value)| y.get(k).is_some_and(|w| data_eq(v, w)))
        }
        (Value::Error(x), Value::Error(y)) => x.tag == y.tag && x.message == y.message,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    fn kw(s: &str) -> Value {
        Value::Keyword(Arc::from(s))
    }

    fn list(items: Vec<Value>) -> Value {
        Value::list(items)
    }

    #[test]
    fn the_wildcard_matches_anything() {
        assert!(matches(&kw("_"), &Value::Int(1)));
        assert!(matches(&kw("_"), &list(vec![])));
        assert!(matches(&kw("_"), &Value::Nil));
    }

    #[test]
    fn a_list_pattern_matches_by_position_and_length() {
        let p = list(vec![kw("reply"), Value::Int(7), kw("_")]);
        assert!(matches(
            &p,
            &list(vec![kw("reply"), Value::Int(7), Value::Int(1)])
        ));
        assert!(!matches(
            &p,
            &list(vec![kw("reply"), Value::Int(8), Value::Int(1)])
        ));
        assert!(!matches(&p, &list(vec![kw("reply"), Value::Int(7)])));
    }

    #[test]
    fn numbers_compare_the_way_blue_does() {
        assert!(matches(&Value::Int(4), &Value::Float(4.0)));
        assert!(!matches(&Value::Int(4), &Value::Str(Arc::from("4"))));
    }

    #[test]
    fn the_oldest_match_wins_and_non_matches_are_skipped_not_taken() {
        let mut mb = VecDeque::new();
        mb.push_back(kw("noise"));
        mb.push_back(list(vec![kw("ok"), Value::Int(1)]));
        mb.push_back(list(vec![kw("ok"), Value::Int(2)]));
        let p = list(vec![kw("ok"), kw("_")]);
        assert_eq!(first_match(&mb, &p), Some(1));
        assert_eq!(mb.len(), 3, "matching must not consume");
        assert_eq!(first_match(&mb, &kw("absent")), None);
    }
}
