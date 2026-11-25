use std::cmp::Ordering;

use tatara_lisp_eval::persist::Map;
use tatara_lisp_eval::{MapKey, Value};

fn key_rank(k: &MapKey) -> u8 {
    match k {
        MapKey::Nil => 0,
        MapKey::Bool(_) => 1,
        MapKey::Int(_) | MapKey::Float(_) => 2,
        MapKey::Str(_) => 3,
        MapKey::Symbol(_) => 4,
        MapKey::Keyword(_) => 5,
    }
}

fn number_order(a: &MapKey, b: &MapKey) -> Ordering {
    let as_f64 = |k: &MapKey| match k {
        MapKey::Int(n) => *n as f64,
        MapKey::Float(bits) => f64::from_bits(*bits),
        _ => 0.0,
    };
    let (x, y) = (as_f64(a), as_f64(b));
    x.is_nan()
        .cmp(&y.is_nan())
        .then_with(|| match (a, b) {
            (MapKey::Int(m), MapKey::Int(n)) => m.cmp(n),
            _ => x.partial_cmp(&y).unwrap_or(Ordering::Equal),
        })
        .then_with(|| matches!(a, MapKey::Float(_)).cmp(&matches!(b, MapKey::Float(_))))
        .then_with(|| match (a, b) {
            (MapKey::Float(p), MapKey::Float(q)) => p.cmp(q),
            _ => Ordering::Equal,
        })
}

#[must_use]
pub fn key_order(a: &MapKey, b: &MapKey) -> Ordering {
    key_rank(a).cmp(&key_rank(b)).then_with(|| match (a, b) {
        (MapKey::Bool(x), MapKey::Bool(y)) => x.cmp(y),
        (MapKey::Str(x), MapKey::Str(y))
        | (MapKey::Symbol(x), MapKey::Symbol(y))
        | (MapKey::Keyword(x), MapKey::Keyword(y)) => x.as_ref().cmp(y.as_ref()),
        (MapKey::Nil, MapKey::Nil) => Ordering::Equal,
        _ => number_order(a, b),
    })
}

#[must_use]
pub fn sorted_entries(m: &Map) -> Vec<(&MapKey, &Value)> {
    let mut entries: Vec<(&MapKey, &Value)> = m.iter().collect();
    entries.sort_unstable_by(|a, b| key_order(a.0, b.0));
    entries
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;

    fn keys() -> Vec<MapKey> {
        vec![
            MapKey::Keyword(Arc::from("b")),
            MapKey::Float(f64::NAN.to_bits()),
            MapKey::Symbol(Arc::from("a")),
            MapKey::Float((-0.0f64).to_bits()),
            MapKey::Int(10),
            MapKey::Str(Arc::from("a1")),
            MapKey::Float(0.0f64.to_bits()),
            MapKey::Keyword(Arc::from("a!")),
            MapKey::Int(9_007_199_254_740_993),
            MapKey::Bool(true),
            MapKey::Float(9_007_199_254_740_992.0f64.to_bits()),
            MapKey::Int(9),
            MapKey::Nil,
            MapKey::Int(0),
            MapKey::Str(Arc::from("a")),
            MapKey::Bool(false),
            MapKey::Float(f64::NEG_INFINITY.to_bits()),
            MapKey::Keyword(Arc::from("a")),
            MapKey::Int(i64::MIN),
        ]
    }

    #[test]
    fn the_key_order_is_total_and_agrees_with_equality() {
        let ks = keys();
        for a in &ks {
            for b in &ks {
                assert_eq!(key_order(a, b) == Ordering::Equal, a == b, "{a:?} {b:?}");
                assert_eq!(key_order(a, b), key_order(b, a).reverse(), "{a:?} {b:?}");
                for c in &ks {
                    if key_order(a, b).is_lt() && key_order(b, c).is_lt() {
                        assert!(key_order(a, c).is_lt(), "{a:?} {b:?} {c:?}");
                    }
                }
            }
        }
    }

    #[test]
    fn nil_bools_numbers_strings_symbols_keywords() {
        let mut ks = keys();
        ks.sort_by(key_order);
        let shown: Vec<String> = ks.iter().map(|k| format!("{k:?}")).collect();
        assert_eq!(
            shown,
            [
                "Nil".to_string(),
                "Bool(false)".to_string(),
                "Bool(true)".to_string(),
                format!("Float({})", f64::NEG_INFINITY.to_bits()),
                "Int(-9223372036854775808)".to_string(),
                "Int(0)".to_string(),
                format!("Float({})", 0.0f64.to_bits()),
                format!("Float({})", (-0.0f64).to_bits()),
                "Int(9)".to_string(),
                "Int(10)".to_string(),
                "Int(9007199254740993)".to_string(),
                format!("Float({})", 9_007_199_254_740_992.0f64.to_bits()),
                format!("Float({})", f64::NAN.to_bits()),
                "Str(\"a\")".to_string(),
                "Str(\"a1\")".to_string(),
                "Symbol(\"a\")".to_string(),
                "Keyword(\"a\")".to_string(),
                "Keyword(\"a!\")".to_string(),
                "Keyword(\"b\")".to_string(),
            ]
        );
    }
}
