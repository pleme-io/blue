//! The canonical encoding of a blue value: what a memo key is made of, and
//! what a memo entry stores.
//!
//! Canonical means one encoding per value, so two equal arguments make one
//! key: a map's entries are written in the order of their encoded keys, never
//! the order a hash map happens to iterate in. Structural, so the encoding is
//! injective where blue text is not (`theory/BLUE-ENGINE.md` §3.6): `1` and
//! `1.0`, a string and a symbol, never meet.
//!
//! Only data has an encoding. A closure, a native function, a promise, quoted
//! code and a host's foreign handle have none ([`encode`] answers `None`), so
//! a call taking or answering one is never cached: its identity is not its
//! content.
//!
//! [`decode`] is strict. Every length is bounded by the bytes left, every tag
//! is known, a map's keys are in order and distinct, and nothing trails: a
//! damaged store entry decodes to `None`, never to a different value.

use std::sync::Arc;

use tatara_lisp_eval::value::ErrorObj;
use tatara_lisp_eval::{List, Map, MapKey, Value};

mod tag {
    pub const NIL: u8 = 0;
    pub const FALSE: u8 = 1;
    pub const TRUE: u8 = 2;
    pub const INT: u8 = 3;
    pub const FLOAT: u8 = 4;
    pub const STR: u8 = 5;
    pub const SYMBOL: u8 = 6;
    pub const KEYWORD: u8 = 7;
    pub const LIST: u8 = 8;
    pub const MAP: u8 = 9;
    pub const ERROR: u8 = 10;
}

/// How deep a value may nest before it is refused rather than encoded: the
/// decoder recurses, and a store entry must not be able to overflow its stack.
pub const MAX_DEPTH: usize = 512;

/// Append the encoding of `v` to `out`; `false` (and `out` left partly
/// written) when some part of it has no encoding.
#[must_use]
pub fn encode_into(v: &Value, out: &mut Vec<u8>) -> bool {
    put(v, out, 0)
}

/// The encoding of `v`, if it has one.
#[must_use]
pub fn encode(v: &Value) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    put(v, &mut out, 0).then_some(out)
}

fn len(out: &mut Vec<u8>, mut n: usize) {
    loop {
        let byte = (n & 0x7f) as u8;
        n >>= 7;
        if n == 0 {
            out.push(byte);
            return;
        }
        out.push(byte | 0x80);
    }
}

fn text(out: &mut Vec<u8>, tag: u8, s: &str) {
    out.push(tag);
    len(out, s.len());
    out.extend_from_slice(s.as_bytes());
}

fn put(v: &Value, out: &mut Vec<u8>, depth: usize) -> bool {
    if depth > MAX_DEPTH {
        return false;
    }
    match v {
        Value::Nil => out.push(tag::NIL),
        Value::Bool(false) => out.push(tag::FALSE),
        Value::Bool(true) => out.push(tag::TRUE),
        Value::Int(n) => {
            out.push(tag::INT);
            out.extend_from_slice(&n.to_le_bytes());
        }
        Value::Float(x) => {
            out.push(tag::FLOAT);
            out.extend_from_slice(&x.to_bits().to_le_bytes());
        }
        Value::Str(s) => text(out, tag::STR, s),
        Value::Symbol(s) => text(out, tag::SYMBOL, s),
        Value::Keyword(s) => text(out, tag::KEYWORD, s),
        Value::List(items) => {
            out.push(tag::LIST);
            len(out, items.len());
            for i in items.iter() {
                if !put(i, out, depth + 1) {
                    return false;
                }
            }
        }
        Value::Map(m) => {
            let mut entries: Vec<(Vec<u8>, &Value)> = Vec::with_capacity(m.len());
            for (k, val) in m.iter() {
                let mut key = Vec::new();
                if !put(&k.to_value(), &mut key, depth + 1) {
                    return false;
                }
                entries.push((key, val));
            }
            entries.sort_by(|a, b| a.0.cmp(&b.0));
            out.push(tag::MAP);
            len(out, entries.len());
            for (key, val) in entries {
                out.extend_from_slice(&key);
                if !put(val, out, depth + 1) {
                    return false;
                }
            }
        }
        Value::Error(e) => {
            out.push(tag::ERROR);
            len(out, e.tag.len());
            out.extend_from_slice(e.tag.as_bytes());
            len(out, e.message.len());
            out.extend_from_slice(e.message.as_bytes());
            len(out, e.data.len());
            for (k, val) in &e.data {
                if !put(k, out, depth + 1) || !put(val, out, depth + 1) {
                    return false;
                }
            }
        }
        Value::Closure(_)
        | Value::NativeFn(_)
        | Value::Promise(_)
        | Value::Sexp(..)
        | Value::Foreign(_) => return false,
    }
    true
}

/// The value `bytes` encodes, when they are exactly one canonical encoding.
#[must_use]
pub fn decode(bytes: &[u8]) -> Option<Value> {
    let mut r = Reader { bytes, at: 0 };
    let v = r.value(0)?;
    (r.at == bytes.len()).then_some(v)
}

struct Reader<'b> {
    bytes: &'b [u8],
    at: usize,
}

impl Reader<'_> {
    fn byte(&mut self) -> Option<u8> {
        let b = *self.bytes.get(self.at)?;
        self.at += 1;
        Some(b)
    }

    fn take(&mut self, n: usize) -> Option<&[u8]> {
        let end = self.at.checked_add(n)?;
        let s = self.bytes.get(self.at..end)?;
        self.at = end;
        Some(s)
    }

    fn len(&mut self) -> Option<usize> {
        let mut n: usize = 0;
        for shift in (0..64).step_by(7) {
            let b = self.byte()?;
            n |= usize::from(b & 0x7f).checked_shl(shift)?;
            if b & 0x80 == 0 {
                // Canonical: no trailing zero groups, and never more than
                // the bytes left could hold.
                if b == 0 && shift > 0 {
                    return None;
                }
                return (n <= self.bytes.len() - self.at).then_some(n);
            }
        }
        None
    }

    fn text(&mut self) -> Option<Arc<str>> {
        let n = self.len()?;
        let s = std::str::from_utf8(self.take(n)?).ok()?;
        Some(Arc::from(s))
    }

    fn word(&mut self) -> Option<[u8; 8]> {
        self.take(8)?.try_into().ok()
    }

    fn value(&mut self, depth: usize) -> Option<Value> {
        if depth > MAX_DEPTH {
            return None;
        }
        Some(match self.byte()? {
            tag::NIL => Value::Nil,
            tag::FALSE => Value::Bool(false),
            tag::TRUE => Value::Bool(true),
            tag::INT => Value::Int(i64::from_le_bytes(self.word()?)),
            tag::FLOAT => Value::Float(f64::from_bits(u64::from_le_bytes(self.word()?))),
            tag::STR => Value::Str(self.text()?),
            tag::SYMBOL => Value::Symbol(self.text()?),
            tag::KEYWORD => Value::Keyword(self.text()?),
            tag::LIST => {
                let n = self.len()?;
                let mut items = Vec::with_capacity(n);
                for _ in 0..n {
                    items.push(self.value(depth + 1)?);
                }
                Value::List(Arc::new(List::from(items)))
            }
            tag::MAP => {
                let n = self.len()?;
                let mut map = Map::new();
                let mut last: Option<&[u8]> = None;
                for _ in 0..n {
                    let start = self.at;
                    let key = MapKey::from_value(&self.value(depth + 1)?)?;
                    let written = &self.bytes[start..self.at];
                    if last.is_some_and(|l| l >= written) {
                        return None;
                    }
                    last = Some(written);
                    let val = self.value(depth + 1)?;
                    map.insert(key, val);
                }
                Value::Map(Arc::new(map))
            }
            tag::ERROR => {
                let tag = self.text()?;
                let message = self.text()?;
                let n = self.len()?;
                let mut data = Vec::with_capacity(n);
                for _ in 0..n {
                    let k = self.value(depth + 1)?;
                    let v = self.value(depth + 1)?;
                    data.push((k, v));
                }
                Value::Error(Arc::new(ErrorObj { tag, message, data }))
            }
            _ => return None,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(src: &str) -> Value {
        blue_lang_runtime::pipeline::run(src).expect("runs").value
    }

    fn same(a: &Value, b: &Value) -> bool {
        blue_lang_runtime::literal::render_value(a) == blue_lang_runtime::literal::render_value(b)
            && encode(a) == encode(b)
    }

    #[test]
    fn every_data_value_round_trips() {
        for src in [
            "nil",
            "true",
            "false",
            "-42",
            "1.5",
            "0.0 * -1.0",
            "\"héllo\"",
            ":kw",
            "[1, [2, \"x\"], [], nil]",
            "{a: 1, b: [2, 3], c: {d: \"e\"}}",
            "error(:oops, \"bad\", [:k, 1])",
        ] {
            let value = v(src);
            let bytes = encode(&value).unwrap_or_else(|| panic!("{src} encodes"));
            let back = decode(&bytes).unwrap_or_else(|| panic!("{src} decodes"));
            assert!(same(&value, &back), "{src}");
        }
    }

    #[test]
    fn equal_maps_encode_alike_whatever_order_they_were_built_in() {
        let a = v("{a: 1, b: 2, c: 3, d: 4, e: 5}");
        let b = v("{e: 5, d: 4, c: 3, b: 2, a: 1}");
        assert_eq!(encode(&a), encode(&b));
    }

    #[test]
    fn values_that_print_alike_but_differ_encode_apart() {
        for (x, y) in [
            ("1", "1.0"),
            ("\"a\"", ":a"),
            ("[1]", "[[1]]"),
            ("0.0", "0.0 * -1.0"),
        ] {
            assert_ne!(encode(&v(x)), encode(&v(y)), "{x} vs {y}");
        }
    }

    #[test]
    fn functions_and_foreign_values_have_no_encoding() {
        assert!(encode(&v("fn(x) x end")).is_none());
        assert!(encode(&v("[1, fn(x) x end]")).is_none());
        assert!(encode(&v("{f: fn(x) x end}")).is_none());
        assert!(encode(&v("first")).is_none());
    }

    #[test]
    fn a_damaged_encoding_decodes_to_nothing_rather_than_something_else() {
        let bytes = encode(&v("{a: [1, \"two\"], b: 3.5}")).expect("encodes");
        assert!(decode(&bytes).is_some());
        // Every truncation, and every trailing byte, is refused.
        for cut in 0..bytes.len() {
            assert!(decode(&bytes[..cut]).is_none(), "cut at {cut}");
        }
        let mut longer = bytes.clone();
        longer.push(0);
        assert!(decode(&longer).is_none());
        // An unknown tag is refused.
        let mut bad = bytes.clone();
        bad[0] = 0xff;
        assert!(decode(&bad).is_none());
        // Map keys out of order are refused: the encoding is not canonical.
        let swapped = [
            tag::MAP,
            2,
            tag::KEYWORD,
            1,
            b'b',
            tag::NIL,
            tag::KEYWORD,
            1,
            b'a',
            tag::NIL,
        ];
        assert!(decode(&swapped).is_none());
    }

    #[test]
    fn a_deep_value_is_refused_not_overflowed() {
        let mut nested = Value::Nil;
        for _ in 0..(MAX_DEPTH + 10) {
            nested = Value::List(Arc::new(List::from(vec![nested])));
        }
        assert!(encode(&nested).is_none());
        let mut bytes = Vec::new();
        for _ in 0..100_000 {
            bytes.extend_from_slice(&[tag::LIST, 1]);
        }
        bytes.push(tag::NIL);
        assert!(decode(&bytes).is_none());
    }
}
