//! blue's string and number core.
//!
//! tatara-lisp ships arithmetic, comparison, list and trig primitives and
//! **no string operations at all** — no length, no concatenation, no case
//! conversion, no number parsing. For a language whose surface is Ruby's, that
//! is the largest parity gap there is: `String` is the most-used type in Ruby
//! by a wide margin.
//!
//! # Why these live in blue and not in tatara-lisp
//!
//! The fleet rule is to extend the substrate rather than re-implement, and
//! generic helpers belong upstream. These are not generic: the *semantics* are
//! blue's, and they are Ruby's semantics specifically.
//!
//! The clearest case is `length`. Ruby's `String#length` counts **characters**;
//! Rust's `str::len` counts **bytes**; Elixir's `String.length/1` counts
//! grapheme clusters. Three languages, three answers, all defensible. Blue owes
//! its users Ruby's answer, and encoding that choice into tatara-lisp would push
//! one language's convention onto every other consumer of the substrate.
//!
//! Promoting a genuinely encoding-neutral core upstream later stays open; the
//! character-counting ones are blue's by right.
//!
//! # Character, not byte, not grapheme
//!
//! Every index and length here is in **Unicode scalar values** (Rust `char`).
//! That matches Ruby for the overwhelming majority of text and is stated rather
//! than left to be discovered — a `length` that silently returns bytes is the
//! bug that only appears once a user types a non-ASCII character.
//!
//! Grapheme clusters (Elixir's choice) would need a segmentation table; where
//! the two differ — a family emoji, a combining accent — blue reports scalar
//! values. `a_combining_sequence_counts_scalars_not_graphemes` pins it.

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

const TRIM_OPTIONS: &[&str] = &["side", "chars"];

fn trim_with(text: &str, opts: &Value, s: tatara_lisp::Span) -> Result<Value, EvalError> {
    let bad = |message: String| crate::errors::raise_kind("bad_option", message, s);
    let mut side = "both".to_string();
    let mut chars: Option<Vec<char>> = None;
    match opts {
        Value::Nil => {}
        Value::Map(m) => {
            for (k, v) in m.iter() {
                let key = match k {
                    tatara_lisp_eval::MapKey::Keyword(n)
                    | tatara_lisp_eval::MapKey::Symbol(n)
                    | tatara_lisp_eval::MapKey::Str(n) => n.to_string(),
                    _ => String::new(),
                };
                match (key.as_str(), v) {
                    ("side", Value::Keyword(k)) if matches!(&**k, "both" | "start" | "end") => {
                        side = k.to_string();
                    }
                    ("side", _) => return Err(bad("side must be :both, :start or :end".into())),
                    ("chars", Value::Str(c)) => chars = Some(c.chars().collect()),
                    ("chars", _) => return Err(bad("chars must be text".into())),
                    _ => {
                        return Err(bad(format!(
                            "unknown option {key}; this verb takes {}",
                            TRIM_OPTIONS.join(", ")
                        )))
                    }
                }
            }
        }
        other => {
            return Err(bad(format!(
                "options must be a map, got {}",
                other.type_name()
            )))
        }
    }
    let out = match (&chars, side.as_str()) {
        (None, "both") => text.trim(),
        (None, "start") => text.trim_start(),
        (None, _) => text.trim_end(),
        (Some(set), "both") => text.trim_matches(|c| set.contains(&c)),
        (Some(set), "start") => text.trim_start_matches(|c| set.contains(&c)),
        (Some(set), _) => text.trim_end_matches(|c| set.contains(&c)),
    };
    Ok(Value::Str(out.into()))
}

fn as_str(v: &Value, span: tatara_lisp::Span) -> Result<String, EvalError> {
    match v {
        Value::Str(s) => Ok(s.to_string()),
        // A symbol is text the author wrote; accepting it makes `upcase(:ok)`
        // work the way a Ruby programmer expects of a symbol.
        Value::Symbol(s) | Value::Keyword(s) => Ok(s.to_string()),
        other => Err(EvalError::type_mismatch(
            "a string",
            other.type_name(),
            span,
        )),
    }
}

/// blue's one equality — what `==`, `!=`, `contains`, `index_of`, `count_of`
/// and `distinct` all mean (okite D0001–D0003).
///
/// Ruby's answer: numbers compare by value across Int and Float (`4 == 4.0`),
/// strings, symbols and keywords by text (each only with its own kind), lists
/// element by element, maps by their entries whatever order they were built in,
/// nil only with nil (not with `[]`, D0004), functions by identity. Until
/// 2026-09-27 `==` was tatara's Scheme `equal?`, under which `4 == 4.0` was
/// false and two equal maps were unequal unless they were the same object.
/// tatara keeps Scheme's `equal?` for its own programs; blue redefines the
/// name in its interpreter, and tatara's own `member?`, `position` and
/// `distinct` call `equal?` by name, so they follow.
pub fn blue_equal(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Nil, Value::Nil) => true,
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::Int(x), Value::Int(y)) => x == y,
        (Value::Float(x), Value::Float(y)) => x == y,
        (Value::Int(x), Value::Float(y)) | (Value::Float(y), Value::Int(x)) => (*x as f64) == *y,
        (Value::Str(x), Value::Str(y))
        | (Value::Symbol(x), Value::Symbol(y))
        | (Value::Keyword(x), Value::Keyword(y)) => x == y,
        (Value::List(x), Value::List(y)) => {
            x.len() == y.len() && x.iter().zip(y.iter()).all(|(p, q)| blue_equal(p, q))
        }
        (Value::Map(x), Value::Map(y)) => {
            x.len() == y.len()
                && x.iter()
                    .all(|(k, v)| y.get(k).is_some_and(|w| blue_equal(v, w)))
        }
        (Value::Closure(x), Value::Closure(y)) => std::sync::Arc::ptr_eq(x, y),
        (Value::NativeFn(x), Value::NativeFn(y)) => x.name == y.name,
        (Value::Sexp(x, _), Value::Sexp(y, _)) => x == y,
        _ => false,
    }
}

#[derive(PartialEq, Eq, Hash)]
enum EqualKey<'a> {
    Nil,
    Bool(bool),
    Number(u64),
    Str(&'a str),
    Symbol(&'a str),
    Keyword(&'a str),
}

fn number_key(n: f64) -> Option<EqualKey<'static>> {
    (!n.is_nan()).then(|| EqualKey::Number(if n == 0.0 { 0 } else { n.to_bits() }))
}

fn equal_key(v: &Value) -> Option<EqualKey<'_>> {
    match v {
        Value::Nil => Some(EqualKey::Nil),
        Value::Bool(b) => Some(EqualKey::Bool(*b)),
        Value::Int(i) => number_key(*i as f64),
        Value::Float(f) => number_key(*f),
        Value::Str(s) => Some(EqualKey::Str(s)),
        Value::Symbol(s) => Some(EqualKey::Symbol(s)),
        Value::Keyword(s) => Some(EqualKey::Keyword(s)),
        _ => None,
    }
}

/// A map from each element to how many times it occurs, keyed as tatara's
/// `hash-map` keys (an Int and a Float are two keys): the meaning of tatara's
/// `frequencies`, built in one native pass.
///
/// # Errors
///
/// An element that cannot be a map key, as `hash-map` refuses it.
pub fn frequencies<'a>(
    xs: impl Iterator<Item = &'a Value>,
    span: tatara_lisp::Span,
) -> Result<Value, EvalError> {
    let mut counts = tatara_lisp_eval::Map::new();
    for x in xs {
        let key = tatara_lisp_eval::value::MapKey::from_value(x).ok_or_else(|| {
            EvalError::native_fn(
                "hash-map",
                format!("non-hashable key kind: {}", x.type_name()),
                span,
            )
        })?;
        let n = match counts.get(&key) {
            Some(Value::Int(n)) => n + 1,
            _ => 1,
        };
        counts.insert(key, Value::Int(n));
    }
    Ok(Value::Map(std::sync::Arc::new(counts)))
}

/// The elements with repeats removed under [`blue_equal`], first occurrence
/// kept: the meaning of tatara's `distinct`, in linear time for the scalars.
///
/// Two values `blue_equal` calls equal always share a key, so a value is
/// compared only with the kept values of its own key; values with no key
/// (lists, maps, functions, NaN) are compared with every kept keyless value.
pub fn distinct<'a>(xs: impl Iterator<Item = &'a Value>) -> Vec<Value> {
    let mut kept: Vec<Value> = Vec::new();
    let mut buckets: std::collections::HashMap<EqualKey<'a>, Vec<usize>> =
        std::collections::HashMap::new();
    let mut keyless: Vec<usize> = Vec::new();
    for x in xs {
        let seen = match equal_key(x) {
            Some(k) => buckets.entry(k).or_default(),
            None => &mut keyless,
        };
        if !seen.iter().any(|&i| blue_equal(&kept[i], x)) {
            seen.push(kept.len());
            kept.push(x.clone());
        }
    }
    kept
}

/// `to_s` (okite D0005, D0006): text for a person. A string, symbol or keyword
/// is its own text and nil is empty, as in Ruby; every other value is its blue
/// literal. Until 2026-09-27 a map rendered as the word `map`, a list lost its
/// brackets (`[1, {a: 2}]` came out `1 map`) and `1.0` came out `1`.
fn chain_rules_value() -> Value {
    use blue_lang_check::chains::{cases, Case, Kind, RULES};
    let sym = |s: &str| Value::Symbol(std::sync::Arc::from(s));
    let text = |s: &str| Value::Str(std::sync::Arc::from(s));
    let hole = |n: usize| (0..n).map(|_| sym("x")).collect::<Vec<_>>();
    let lambda = |body: Value| Value::list([sym("lambda"), Value::list([sym("x")]), body]);
    let call = |name: &str, args: Vec<Value>| Value::list(std::iter::once(sym(name)).chain(args));
    Value::list(RULES.iter().map(|rule| {
        let rows = cases(rule).into_iter().map(|case| match case {
            Case::Call { inner, argc } => {
                let inner_call = call(inner, hole(argc));
                Value::list([
                    text(&format!("{}({}(x))", rule.outer, inner)),
                    Value::Nil,
                    lambda(call(rule.outer, vec![inner_call.clone()])),
                    lambda(inner_call),
                ])
            }
            Case::Literal(kind) => Value::list([
                text(&format!("{}(<literal>)", rule.outer)),
                Value::Keyword(std::sync::Arc::from(match kind {
                    Kind::Text => "text",
                    Kind::Int => "int",
                    Kind::Float => "float",
                })),
                lambda(call(rule.outer, vec![sym("x")])),
                lambda(sym("x")),
            ]),
        });
        Value::list([
            text(rule.id),
            text(rule.slug),
            text(rule.outer),
            text(rule.soundness),
            Value::list(rows),
        ])
    }))
}

fn render(v: &Value) -> String {
    match v {
        Value::Nil => String::new(),
        Value::Str(s) | Value::Symbol(s) | Value::Keyword(s) => s.to_string(),
        Value::Error(e) => crate::errors::describe(e),
        other => literal(other),
    }
}

/// A value as blue source writes it: `[1, "a", nil]`, `{a: 1, b: 2.0}`.
/// Map entries are sorted by key, since a map has no order of its own and the
/// text must be the same for equal maps (D0006).
fn literal(v: &Value) -> String {
    match v {
        Value::Nil => "nil".into(),
        Value::Bool(b) => b.to_string(),
        Value::Int(n) => n.to_string(),
        Value::Float(x) => float_text(*x),
        Value::Str(s) => quoted(s),
        Value::Symbol(s) => s.to_string(),
        Value::Keyword(s) => format!(":{s}"),
        Value::List(items) => {
            let parts: Vec<String> = items.iter().map(literal).collect();
            format!("[{}]", parts.join(", "))
        }
        Value::Map(m) => {
            let mut entries: Vec<String> = m
                .iter()
                .map(|(k, v)| format!("{} {}", key_text(k), literal(v)))
                .collect();
            entries.sort();
            format!("{{{}}}", entries.join(", "))
        }
        other => other.type_name().to_string(),
    }
}

/// A map key as it is written before its value: `a:` for a keyword or symbol,
/// `"a" =>` / `1 =>` for anything else.
fn key_text(k: &tatara_lisp_eval::value::MapKey) -> String {
    use tatara_lisp_eval::value::MapKey;
    match k {
        MapKey::Keyword(s) | MapKey::Symbol(s) => format!("{s}:"),
        MapKey::Str(s) => format!("{} =>", quoted(s)),
        MapKey::Int(n) => format!("{n} =>"),
        MapKey::Float(bits) => format!("{} =>", float_text(f64::from_bits(*bits))),
        MapKey::Bool(b) => format!("{b} =>"),
        MapKey::Nil => "nil =>".into(),
    }
}

/// A float keeps its point, as in Ruby: `1.0`, `2.5`.
fn float_text(x: f64) -> String {
    if x.is_finite() && x.fract() == 0.0 && x.abs() < 1e16 {
        format!("{x:.1}")
    } else {
        format!("{x}")
    }
}

fn quoted(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn list(items: Vec<Value>) -> Value {
    Value::list(items)
}

/// Install blue's string and number core.
pub fn install_blue_stdlib<H: 'static>(interp: &mut Interpreter<H>) {
    crate::errors::install(interp);
    crate::paths::install(interp);
    crate::spread::install(interp);
    crate::collection::install(interp);
    // ── text ──────────────────────────────────────────────────────────

    // `length` counts CHARACTERS, per Ruby. Also accepts a list, where it is
    // the element count — Ruby's `Array#length`.
    interp.register_fn(
        "length",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, span| match &a[0] {
            Value::List(items) => Ok(Value::Int(items.len() as i64)),
            other => Ok(Value::Int(as_str(other, span)?.chars().count() as i64)),
        },
    );

    // The documented builtins, for a program that reasons about names (the
    // catalogue's "shares a builtin's name" column).
    interp.register_fn(
        "builtin_names",
        Arity::Exact(0),
        |_a: &[Value], _h: &mut H, _s| {
            Ok(Value::list(
                crate::docs::NAMES
                    .iter()
                    .map(|n| Value::Str(std::sync::Arc::from(n.name))),
            ))
        },
    );
    interp.register_fn(
        "chain_rules",
        Arity::Exact(0),
        |_a: &[Value], _h: &mut H, _s| Ok(chain_rules_value()),
    );
    interp.register_fn(
        "volatile",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::Closure(_) | Value::NativeFn(_) | Value::Foreign(_) => Ok(Value::Nil),
            other => Err(EvalError::type_mismatch("function", other.type_name(), s)),
        },
    );
    interp.register_fn("to_s", Arity::Exact(1), |a: &[Value], _h: &mut H, _s| {
        Ok(Value::Str(render(&a[0]).into()))
    });

    interp.register_fn("upcase", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        Ok(Value::Str(as_str(&a[0], s)?.to_uppercase().into()))
    });

    interp.register_fn("downcase", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        Ok(Value::Str(as_str(&a[0], s)?.to_lowercase().into()))
    });

    interp.register_fn("trim", Arity::Range(1, 2), |a: &[Value], _h: &mut H, s| {
        let text = as_str(&a[0], s)?;
        trim_with(&text, a.get(1).unwrap_or(&Value::Nil), s)
    });

    interp.register_fn(
        blue_lang_syntax::LOWERED_OPTIONAL_ARITY,
        Arity::Exact(4),
        |a: &[Value], _h: &mut H, s| {
            let name = as_str(&a[0], s)?;
            let (Value::List(rest), Value::Int(required), Value::Int(most)) = (&a[1], &a[2], &a[3])
            else {
                return Err(EvalError::native_fn(
                    blue_lang_syntax::LOWERED_OPTIONAL_ARITY,
                    "expects a name, the rest list and two counts",
                    s,
                ));
            };
            if rest.len() as i64 > *most {
                let want = Arity::Range(*required as usize, (*required + *most) as usize);
                return Err(EvalError::native_fn(
                    name.as_str(),
                    format!(
                        "takes {}, got {}",
                        crate::messages::arguments(&want),
                        *required as usize + rest.len()
                    ),
                    s,
                ));
            }
            Ok(Value::Nil)
        },
    );

    interp.register_fn(
        blue_lang_syntax::LOWERED_OPTIONAL_ARG,
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, s| match (&a[0], &a[1]) {
            (Value::List(rest), Value::Int(i)) => {
                Ok(rest.get(*i as usize).cloned().unwrap_or(Value::Nil))
            }
            _ => Err(EvalError::native_fn(
                blue_lang_syntax::LOWERED_OPTIONAL_ARG,
                "expects the rest list and an index",
                s,
            )),
        },
    );

    // `concat(a, …)` joins the text of one or more arguments, left to right
    // (okite D0007; Ruby's String#concat takes many). Two-only until
    // 2026-09-27, which made `concat(a, b, c)` an arity error. `+` stays
    // arithmetic: Ruby overloads `+` on String, but blue's `+` lowers to
    // tatara's numeric `+`, and making it polymorphic would make a type error
    // at a seam disappear into a string.
    interp.register_fn(
        "concat",
        Arity::AtLeast(1),
        |a: &[Value], _h: &mut H, _s| {
            Ok(Value::Str(a.iter().map(render).collect::<String>().into()))
        },
    );

    // ── equality and kinds (okite D0001–D0004, D0010) ─────────────────────
    //
    // `==` lowers to `equal?` and `!=` to `not=`; both are redefined here so
    // blue's interpreter has one equality. See `blue_equal`.
    interp.register_fn("equal?", Arity::Exact(2), |a: &[Value], _h: &mut H, _s| {
        Ok(Value::Bool(blue_equal(&a[0], &a[1])))
    });
    interp.register_fn("not=", Arity::Exact(2), |a: &[Value], _h: &mut H, _s| {
        Ok(Value::Bool(!blue_equal(&a[0], &a[1])))
    });
    interp.register_fn(
        "distinct",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, span| match &a[0] {
            Value::Nil => Ok(Value::list(std::iter::empty())),
            Value::List(xs) => Ok(Value::list(distinct(xs.iter()))),
            other => Err(EvalError::type_mismatch("a list", other.type_name(), span)),
        },
    );
    interp.register_fn(
        "frequencies",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, span| match &a[0] {
            Value::Nil => Ok(frequencies(std::iter::empty(), span)?),
            Value::List(xs) => Ok(frequencies(xs.iter(), span)?),
            other => Err(EvalError::type_mismatch("a list", other.type_name(), span)),
        },
    );

    // One predicate per kind, and exactly one holds of any value (D0010).
    // tatara's `nil?` is its Scheme alias for `null?`, true of `[]` as well,
    // and its `list?` is true of nil; blue's nil is absent and `[]` is an empty
    // list (D0004), so blue redefines both. tatara's own library ends its
    // recursion with `null?`, which is untouched.
    interp.register_fn("nil?", Arity::Exact(1), |a: &[Value], _h: &mut H, _s| {
        Ok(Value::Bool(matches!(a[0], Value::Nil)))
    });
    interp.register_fn("list?", Arity::Exact(1), |a: &[Value], _h: &mut H, _s| {
        Ok(Value::Bool(matches!(a[0], Value::List(_))))
    });
    interp.register_fn("map?", Arity::Exact(1), |a: &[Value], _h: &mut H, _s| {
        Ok(Value::Bool(matches!(a[0], Value::Map(_))))
    });
    interp.register_fn("float?", Arity::Exact(1), |a: &[Value], _h: &mut H, _s| {
        Ok(Value::Bool(matches!(a[0], Value::Float(_))))
    });
    interp.register_fn("bool?", Arity::Exact(1), |a: &[Value], _h: &mut H, _s| {
        Ok(Value::Bool(matches!(a[0], Value::Bool(_))))
    });

    // The empty list is always `[]`, never nil (D0011). tatara's `cdr` (and so
    // `rest`, which is `cdr`) and `append` returned nil for an empty result,
    // Scheme's convention, which under D0004 made `rest([1]) == []` false.
    // Same contracts otherwise: `cdr` of an empty list is still an error.
    interp.register_fn("cdr", Arity::Exact(1), |a: &[Value], _h: &mut H, span| {
        match &a[0] {
            // Shares the tail's structure: O(log n), not a copy of it.
            Value::List(xs) if !xs.is_empty() => Ok(Value::List(std::sync::Arc::new(xs.skip(1)))),
            Value::Nil | Value::List(_) => Err(EvalError::native_fn(
                std::sync::Arc::<str>::from("cdr"),
                "cdr of empty list",
                span,
            )),
            other => Err(EvalError::type_mismatch("pair", other.type_name(), span)),
        }
    });
    interp.register_owned_fn("append", Arity::Any, |a: Vec<Value>, _h: &mut H, span| {
        // Persistent concatenation: each operand's structure is shared, so
        // building a list by `append(acc, [x])` is linear overall, not
        // quadratic (G7). The arguments arrive by value, so an accumulator
        // the caller holds alone (tatara-lisp-eval runs a tail call to an
        // owned primitive after releasing the caller's frame) is extended in
        // its own allocation by `Arc::make_mut` instead of copied at the tail.
        let mut lists = Vec::with_capacity(a.len());
        for v in a {
            match v {
                Value::Nil => {}
                Value::List(xs) => lists.push(xs),
                other => return Err(EvalError::type_mismatch("list", other.type_name(), span)),
            }
        }
        let mut lists = lists.into_iter();
        let Some(mut out) = lists.next() else {
            return Ok(Value::List(std::sync::Arc::new(
                tatara_lisp_eval::List::new(),
            )));
        };
        let acc = std::sync::Arc::make_mut(&mut out);
        for xs in lists {
            acc.append(
                std::sync::Arc::try_unwrap(xs)
                    .unwrap_or_else(|shared| tatara_lisp_eval::List::clone(&shared)),
            );
        }
        Ok(Value::List(out))
    });

    interp.register_fn("split", Arity::Exact(2), |a: &[Value], _h: &mut H, s| {
        let text = as_str(&a[0], s)?;
        let sep = as_str(&a[1], s)?;
        // An empty separator splits into characters, as Ruby's `split("")`
        // does. Rust's `split("")` yields leading/trailing empties instead,
        // which is the wrong answer here.
        // Every field is kept: n separators give n + 1 fields, so `join` undoes
        // `split` exactly (okite D0012). A deliberate deviation from Ruby, which
        // drops trailing empty fields: tried on 2026-09-27, it broke nisshi's
        // hash chain, kueri's scripts and moji's `lines`, because a parser whose
        // split loses a field loses data and still reports success.
        let parts: Vec<Value> = if sep.is_empty() {
            text.chars()
                .map(|c| Value::Str(c.to_string().into()))
                .collect()
        } else {
            text.split(sep.as_str())
                .map(|p| Value::Str(p.into()))
                .collect()
        };
        Ok(list(parts))
    });

    interp.register_fn("join", Arity::Exact(2), |a: &[Value], _h: &mut H, s| {
        let sep = as_str(&a[1], s)?;
        match &a[0] {
            Value::List(items) => Ok(Value::Str(
                items
                    .iter()
                    .map(render)
                    .collect::<Vec<_>>()
                    .join(&sep)
                    .into(),
            )),
            other => Err(EvalError::type_mismatch("a list", other.type_name(), s).into()),
        }
    });

    interp.register_fn(
        "join_lines",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::List(items) => Ok(Value::Str(
                items
                    .iter()
                    .map(render)
                    .collect::<Vec<_>>()
                    .join("\n")
                    .into(),
            )),
            other => Err(EvalError::type_mismatch("a list", other.type_name(), s).into()),
        },
    );

    interp.register_fn(
        "unlines",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::List(items) => Ok(Value::Str(
                items
                    .iter()
                    .map(|v| render(v) + "\n")
                    .collect::<String>()
                    .into(),
            )),
            other => Err(EvalError::type_mismatch("a list", other.type_name(), s).into()),
        },
    );

    interp.register_fn(
        "line_break",
        Arity::Exact(0),
        |_a: &[Value], _h: &mut H, _s| Ok(Value::Str("\n".into())),
    );

    interp.register_fn(
        "contains?",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, s| {
            Ok(Value::Bool(as_str(&a[0], s)?.contains(&as_str(&a[1], s)?)))
        },
    );

    interp.register_fn(
        "starts_with?",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, s| {
            Ok(Value::Bool(
                as_str(&a[0], s)?.starts_with(&as_str(&a[1], s)?),
            ))
        },
    );

    interp.register_fn(
        "ends_with?",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, s| {
            Ok(Value::Bool(as_str(&a[0], s)?.ends_with(&as_str(&a[1], s)?)))
        },
    );

    interp.register_fn(
        "text_index",
        Arity::Exact(3),
        |a: &[Value], _h: &mut H, s| {
            Ok(Value::Int(text_index(
                &as_str(&a[0], s)?,
                &as_str(&a[1], s)?,
                as_index(&a[2], s)?,
            )))
        },
    );

    interp.register_fn(
        "text_last_index",
        Arity::Exact(3),
        |a: &[Value], _h: &mut H, s| {
            Ok(Value::Int(text_last_index(
                &as_str(&a[0], s)?,
                &as_str(&a[1], s)?,
                as_index(&a[2], s)?,
            )))
        },
    );

    interp.register_fn("replace", Arity::Exact(3), |a: &[Value], _h: &mut H, s| {
        Ok(Value::Str(
            as_str(&a[0], s)?
                .replace(&as_str(&a[1], s)?, &as_str(&a[2], s)?)
                .into(),
        ))
    });

    interp.register_fn("reverse", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        match &a[0] {
            Value::List(items) => Ok(Value::list(items.iter().rev().cloned())),
            // Reversed by CHARACTER, so a multi-byte character survives. A
            // byte-wise reverse produces invalid UTF-8.
            other => Ok(Value::Str(
                as_str(other, s)?.chars().rev().collect::<String>().into(),
            )),
        }
    });

    interp.register_fn("chars", Arity::Exact(1), |a: &[Value], _h: &mut H, s| {
        Ok(list(
            as_str(&a[0], s)?
                .chars()
                .map(|c| Value::Str(c.to_string().into()))
                .collect(),
        ))
    });

    interp.register_fn(
        "text_bytes",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| {
            Ok(list(
                as_str(&a[0], s)?
                    .as_bytes()
                    .iter()
                    .map(|b| Value::Int(i64::from(*b)))
                    .collect(),
            ))
        },
    );

    interp.register_fn(
        "bytes_text",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| {
            let bytes = crate::crypto::message_bytes(&a[0])
                .map_err(|e| EvalError::native_fn("bytes_text", e.to_string(), s))?;
            Ok(match String::from_utf8(bytes) {
                Ok(text) => Value::Str(text.into()),
                Err(_) => Value::Nil,
            })
        },
    );

    // ── numbers ───────────────────────────────────────────────────────

    // `to_int` RETURNS NIL on unparseable input rather than raising. Ruby's
    // `String#to_i` answers 0 for garbage, which silently turns a parse failure
    // into a plausible number; nil is falsy and cannot be mistaken for a
    // result. `to_int!` is the raising form for callers who want the failure.
    interp.register_fn(
        "to_int",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::Int(n) => Ok(Value::Int(*n)),
            // A float with no Int (non-finite, or past i64) is nil like any
            // other unconvertible input; `as i64` saturated it to a plausible
            // wrong number.
            Value::Float(x) => Ok(float_to_int(*x).map_or(Value::Nil, Value::Int)),
            other => Ok(as_str(other, s)?
                .trim()
                .parse::<i64>()
                .map_or(Value::Nil, Value::Int)),
        },
    );

    interp.register_fn(
        "to_int!",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::Int(n) => Ok(Value::Int(*n)),
            Value::Float(x) => float_to_int(*x)
                .map(Value::Int)
                .ok_or(EvalError::IntegerOverflow {
                    op: "to_int!",
                    at: s,
                }),
            other => {
                let text = as_str(other, s)?;
                text.trim().parse::<i64>().map(Value::Int).map_err(|_| {
                    EvalError::native_fn(
                        "to_int!",
                        "`".to_string() + &text + "` is not an integer",
                        s,
                    )
                    .into()
                })
            }
        },
    );

    interp.register_fn(
        "to_float",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::Float(x) => Ok(Value::Float(*x)),
            Value::Int(n) => Ok(Value::Float(*n as f64)),
            other => Ok(as_str(other, s)?
                .trim()
                .parse::<f64>()
                .map_or(Value::Nil, Value::Float)),
        },
    );

    interp.register_fn(
        "abs",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            // Checked, as tatara's `abs` is (G5): |i64::MIN| does not fit, and
            // `n.abs()` wrapped in release and panicked in debug.
            Value::Int(n) => n
                .checked_abs()
                .map(Value::Int)
                .ok_or(EvalError::IntegerOverflow { op: "abs", at: s }),
            Value::Float(x) => Ok(Value::Float(x.abs())),
            other => Err(EvalError::type_mismatch("a number", other.type_name(), s).into()),
        },
    );

    // ── ranges ────────────────────────────────────────────────────────

    // `range` is a LOOP here, not a recursion. tatara-lisp's stdlib defines it
    // in Lisp (`lisp_stdlib.tlisp`, where `range-impl` conses one frame per
    // element), so `range(0, 5000)` overflowed the 8 MiB main stack and
    // aborted the process. Everything built on it inherited the ceiling:
    // retsu's `indexes`, `zip_with` and `enumerate`, and shomei's
    // `chain_first_break`, which could not verify a 5,000-entry chain
    // (measured 2026-09-24: 4,000 elements fine, 5,000 aborted).
    //
    // Same arities and answers as the Lisp definition: (end), (start, end),
    // (start, end, step), ascending for a positive step, descending for a
    // negative one, and each next element is the previous plus the step under
    // the ordinary number rules (Int + Int is Int; a Float anywhere makes the
    // rest Float). Two refusals the Lisp version lacked: a zero step, which
    // recursed forever, and a wrong arity, which printed a message and
    // returned nil.
    //
    // The destination is upstream: when tatara-lisp's own `range` is a loop,
    // this registration is deleted.
    interp.register_fn("range", Arity::Range(1, 3), |a: &[Value], _h: &mut H, s| {
        let (start, end, step) = match a.len() {
            1 => (Value::Int(0), a[0].clone(), Value::Int(1)),
            2 => (a[0].clone(), a[1].clone(), Value::Int(1)),
            _ => (a[0].clone(), a[1].clone(), a[2].clone()),
        };
        range_list(start, &end, &step, s)
    });

    // `write_stdout(s)` / `write_stderr(s)`: the text exactly, no quotes, no
    // newline added. `print`, `println` and `display` all render a string
    // with its quotes (a value printer, right for a REPL and wrong for a
    // command's output), so until these a blue command-line tool could not
    // print plain text. Output only, like `println`; anything else is not a
    // string and is refused.
    interp.register_fn(
        "write_stdout",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| {
            use std::io::Write;
            let text = as_str(&a[0], s)?;
            let mut out = std::io::stdout().lock();
            out.write_all(text.as_bytes())
                .and_then(|()| out.flush())
                .map_err(|e| EvalError::native_fn("write_stdout", e.to_string(), s))?;
            Ok(Value::Nil)
        },
    );
    interp.register_fn(
        "write_stderr",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| {
            use std::io::Write;
            let text = as_str(&a[0], s)?;
            let mut err = std::io::stderr().lock();
            err.write_all(text.as_bytes())
                .and_then(|()| err.flush())
                .map_err(|e| EvalError::native_fn("write_stderr", e.to_string(), s))?;
            Ok(Value::Nil)
        },
    );

    // `sort_keyed(key, xs)`: xs ordered by key(x), stably, in O(n log n),
    // under `compare`'s rules. Every sort written in blue (junjo's) recurses
    // per element and aborts the process near 600 elements; this is
    // tatara-lisp's `sort-by-key` (0.3.60), which blue cannot name because
    // it is kebab-case, bound to a name blue can. The engine is upstream,
    // `hof::sort_keyed_values`; only the spelling lives here.
    interp.register_higher_order_fn(
        "sort_keyed",
        Arity::Exact(2),
        |a: &[Value], host: &mut H, caller: &tatara_lisp_eval::ffi::Caller<H>, s| {
            let xs = match &a[1] {
                Value::List(xs) => xs.to_vec(),
                Value::Nil => Vec::new(),
                other => {
                    return Err(EvalError::type_mismatch("a list", other.type_name(), s));
                }
            };
            let mut keyed = Vec::with_capacity(xs.len());
            for x in xs {
                keyed.push((caller.apply_value(&a[0], vec![x.clone()], host, s)?, x));
            }
            Ok(list(tatara_lisp_eval::hof::sort_keyed_values(keyed, s)?))
        },
    );

    interp.register_fn(
        "error_message",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::Error(e) => Ok(Value::Str(e.message.clone())),
            other => Err(EvalError::type_mismatch("an error", other.type_name(), s)),
        },
    );

    interp.register_fn(
        "error_kind",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::Error(e) => Ok(Value::Keyword(e.tag.clone())),
            other => Err(EvalError::type_mismatch("an error", other.type_name(), s)),
        },
    );

    interp.register_fn(
        "map_entries",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, s| match &a[0] {
            Value::Map(m) => {
                let keyed = m
                    .iter()
                    .map(|(k, v)| (k.to_value(), list(vec![k.to_value(), v.clone()])))
                    .collect();
                Ok(list(tatara_lisp_eval::hof::sort_keyed_values(keyed, s)?))
            }
            Value::Nil => Ok(list(Vec::new())),
            other => Err(EvalError::type_mismatch("a map", other.type_name(), s)),
        },
    );
}

fn as_index(v: &Value, span: tatara_lisp::Span) -> Result<i64, EvalError> {
    match v {
        Value::Int(n) => Ok(*n),
        other => Err(EvalError::type_mismatch(
            "an integer",
            other.type_name(),
            span,
        )),
    }
}

fn text_index(text: &str, sub: &str, from: i64) -> i64 {
    let from = usize::try_from(from.max(0)).unwrap_or(usize::MAX);
    let start = match text.char_indices().nth(from) {
        Some((b, _)) => b,
        None if text.chars().count() == from => text.len(),
        None => return -1,
    };
    text[start..].find(sub).map_or(-1, |b| {
        i64::try_from(from + text[start..start + b].chars().count()).unwrap_or(i64::MAX)
    })
}

fn text_last_index(text: &str, sub: &str, from: i64) -> i64 {
    let Ok(from) = usize::try_from(from) else {
        return -1;
    };
    let total = text.chars().count();
    let width = sub.chars().count();
    if width > total {
        return -1;
    }
    let limit = from.min(total - width);
    let end = text
        .char_indices()
        .nth(limit + width)
        .map_or(text.len(), |(b, _)| b);
    text[..end].rfind(sub).map_or(-1, |b| {
        i64::try_from(text[..b].chars().count()).unwrap_or(i64::MAX)
    })
}

/// A number's value as a float, or a type error naming `range`.
fn range_num(v: &Value, s: tatara_lisp::Span) -> Result<f64, EvalError> {
    match v {
        Value::Int(n) => Ok(*n as f64),
        Value::Float(x) => Ok(*x),
        other => Err(EvalError::native_fn(
            "range",
            "expected a number, got ".to_string() + other.type_name(),
            s,
        )),
    }
}

/// A float's integer part as an `i64`, or `None` when it is not finite or
/// does not fit. `as i64` saturates instead.
fn float_to_int(x: f64) -> Option<i64> {
    const LIMIT: f64 = 9_223_372_036_854_775_808.0;
    let t = x.trunc();
    #[allow(clippy::cast_possible_truncation)]
    (t.is_finite() && (-LIMIT..LIMIT).contains(&t)).then(|| t as i64)
}

/// `a + b` under the number rules the Lisp `range` used: Int + Int stays Int,
/// anything with a Float is Float.
fn range_add(a: &Value, b: &Value, s: tatara_lisp::Span) -> Result<Value, EvalError> {
    match (a, b) {
        (Value::Int(x), Value::Int(y)) => x.checked_add(*y).map(Value::Int).ok_or_else(|| {
            EvalError::native_fn("range", "an element overflowed a 64-bit integer", s)
        }),
        _ => Ok(Value::Float(range_num(a, s)? + range_num(b, s)?)),
    }
}

fn range_list(
    start: Value,
    end: &Value,
    step: &Value,
    s: tatara_lisp::Span,
) -> Result<Value, EvalError> {
    let end_f = range_num(end, s)?;
    let step_f = range_num(step, s)?;
    range_num(&start, s)?;
    if step_f == 0.0 {
        return Err(EvalError::native_fn(
            "range",
            "a step of zero never reaches the end",
            s,
        ));
    }
    let mut out = Vec::new();
    let mut cur = start;
    loop {
        let c = range_num(&cur, s)?;
        if (step_f > 0.0 && c >= end_f) || (step_f < 0.0 && c <= end_f) {
            break;
        }
        let next = range_add(&cur, step, s)?;
        out.push(cur);
        cur = next;
    }
    Ok(list(out))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sort_keyed_is_stable_keyed_and_deep() {
        // Ties keep input order; the key is computed per element.
        assert_eq!(
            ints("map(fn(p) last(p) end, sort_keyed(fn(p) first(p) end, [[2, 1], [1, 2], [2, 3], [1, 4]]))"),
            vec![2, 4, 1, 3]
        );
        // 20,000 in reverse: every blue-written sort aborts far below this.
        assert_eq!(
            i("first(sort_keyed(fn(x) x end, reverse(range(0, 20000))))"),
            0
        );
        assert_eq!(i("last(sort_keyed(fn(x) 0 - x end, range(0, 20000)))"), 0);
        // The empty case, and a refusal for keys that cannot be ordered.
        assert_eq!(ints("sort_keyed(fn(x) x end, [])"), Vec::<i64>::new());
        assert!(crate::run("sort_keyed(fn(x) x end, [1, \"a\"])").is_err());
    }

    #[test]
    fn distinct_is_native_and_keeps_tataras_meaning() {
        assert!(matches!(
            crate::interpreter_hostless().lookup_global("distinct"),
            Some(Value::NativeFn(_))
        ));
        let corpus = eval(
            "[1, 1.0, 0, -0.0, 0.0, 9007199254740993, 9007199254740992, 9007199254740992.0, \
             \"a\", :a, \"a\", nil, nil, true, false, true, [1, 2], [1, 2.0], [2], \
             {a: 1}, {a: 1.0}, 2.5, 2.5, -1, -1.0, \"\", \"\"]",
        );
        let Value::List(xs) = &corpus else {
            panic!("{corpus:?}")
        };
        let mut naive: Vec<Value> = Vec::new();
        for x in xs.iter() {
            if !naive.iter().any(|k| blue_equal(k, x)) {
                naive.push(x.clone());
            }
        }
        let fast = distinct(xs.iter());
        assert_eq!(fast.len(), naive.len());
        assert!(fast.iter().zip(&naive).all(|(a, b)| blue_equal(a, b)));
        assert_eq!(
            i("length(distinct(map((x) -> x % 997, range(300000))))"),
            997
        );
        assert_eq!(i("length(distinct(nil))"), 0);
    }

    #[test]
    fn frequencies_is_native_and_counts_as_tatara_does() {
        assert!(matches!(
            crate::interpreter_hostless().lookup_global("frequencies"),
            Some(Value::NativeFn(_))
        ));
        let corpus = "(list 1 1.0 1 \"a\" 'a :a \"a\" #t #f #t 2.5 2.5 -0.0 0.0 0)";
        let mut upstream = tatara_lisp_eval::Interpreter::<()>::new();
        tatara_lisp_eval::install_full_stdlib_with(&mut upstream, &mut ());
        let forms = tatara_lisp::read_spanned(&format!("(frequencies {corpus})")).expect("reads");
        let expected = upstream
            .eval_program(&forms, &mut ())
            .expect("upstream counts");
        let Value::List(xs) = upstream
            .eval_program(&tatara_lisp::read_spanned(corpus).expect("reads"), &mut ())
            .expect("corpus")
        else {
            panic!("a list")
        };
        let ours = frequencies(xs.iter(), tatara_lisp::Span::synthetic()).expect("counts");
        assert!(blue_equal(&ours, &expected), "{ours:?} vs {expected:?}");
        assert!(crate::run("frequencies([[1]])").is_err());
        assert_eq!(
            i("get(frequencies(map((x) -> x % 7, range(70000))), 3)"),
            10000
        );
    }

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

    fn i(src: &str) -> i64 {
        match eval(src) {
            Value::Int(v) => v,
            other => panic!("{src:?} produced {other:?}"),
        }
    }

    fn ints(src: &str) -> Vec<i64> {
        match eval(src) {
            Value::List(xs) => xs
                .iter()
                .map(|v| match v {
                    Value::Int(n) => *n,
                    other => panic!("{src:?} produced a non-Int element {other:?}"),
                })
                .collect(),
            other => panic!("{src:?} produced {other:?}"),
        }
    }

    /// **`range` gives the Lisp definition's answers**, arity by arity,
    /// including the descending form and the empty cases.
    #[test]
    fn range_answers_as_the_lisp_definition_did() {
        assert_eq!(ints("range(5)"), vec![0, 1, 2, 3, 4]);
        assert_eq!(ints("range(2, 6)"), vec![2, 3, 4, 5]);
        assert_eq!(ints("range(0, 10, 2)"), vec![0, 2, 4, 6, 8]);
        assert_eq!(ints("range(10, 0, 0 - 2)"), vec![10, 8, 6, 4, 2]);
        assert!(ints("range(5, 5)").is_empty());
        assert!(ints("range(5, 2)").is_empty());
        assert!(ints("range(0)").is_empty());
        // A float step makes the elements after the first floats, as `+` did.
        match eval("range(0, 1, 0.5)") {
            Value::List(xs) => {
                assert!(matches!(xs[0], Value::Int(0)), "{xs:?}");
                assert!(matches!(xs[1], Value::Float(x) if x == 0.5), "{xs:?}");
                assert_eq!(xs.len(), 2);
            }
            other => panic!("{other:?}"),
        }
    }

    /// **`range` is a loop, not a recursion.** The Lisp definition consed one
    /// stack frame per element and aborted the process near 5,000 elements on
    /// an 8 MiB stack. This runs on the test harness's 2 MiB thread, where the
    /// Lisp one died sooner still. Red run, 2026-09-24: with the registration
    /// removed, this test aborted the test binary with a stack overflow.
    #[test]
    fn range_builds_long_lists_without_recursing() {
        assert_eq!(i("length(range(0, 200000))"), 200_000);
        assert_eq!(i("nth(199999, range(0, 200000))"), 199_999);
    }

    /// A zero step never reaches the end: refused, where the Lisp definition
    /// recursed until the stack gave out. A non-number is a named error.
    #[test]
    fn range_refuses_a_zero_step_and_a_non_number() {
        assert!(crate::run("range(0, 5, 0)").is_err());
        assert!(crate::run("range(0, \"x\")").is_err());
    }

    /// **`length` counts CHARACTERS, as Ruby does — not bytes.** A `length`
    /// that returns bytes is the bug that only surfaces once a user types a
    /// non-ASCII character, which is exactly when it is hardest to trace.
    #[test]
    fn length_counts_characters_not_bytes() {
        assert_eq!(i("length(\"hello\")"), 5);
        // "héllo" is 6 bytes, 5 characters.
        assert_eq!(i("length(\"héllo\")"), 5, "must not be 6");
        // An emoji is 4 bytes, 1 character.
        assert_eq!(i("length(\"😀\")"), 1, "must not be 4");
    }

    /// blue reports **scalar values**, not grapheme clusters. Elixir would say
    /// 1 here; blue says 2. Stated and pinned rather than left to surprise.
    #[test]
    fn a_combining_sequence_counts_scalars_not_graphemes() {
        // "e" + U+0301 COMBINING ACUTE — one grapheme, two scalars.
        assert_eq!(
            i("length(\"e\\u{301}\")"),
            2,
            "blue counts scalar values; Elixir's String.length would say 1"
        );
    }

    #[test]
    fn length_also_works_on_a_list() {
        assert_eq!(i("length([1, 2, 3])"), 3);
    }

    #[test]
    fn case_and_trim() {
        assert_eq!(s("upcase(\"abc\")"), "ABC");
        assert_eq!(s("downcase(\"ABC\")"), "abc");
        assert_eq!(s("trim(\"  hi  \")"), "hi");
        // Non-ASCII case works, which a byte-wise implementation would botch.
        assert_eq!(s("upcase(\"é\")"), "É");
    }

    #[test]
    fn concat_and_to_s() {
        assert_eq!(s("concat(\"a\", \"b\")"), "ab");
        assert_eq!(s("concat(\"n=\", 42)"), "n=42");
        assert_eq!(s("to_s(42)"), "42");
        assert_eq!(s("to_s(true)"), "true");
    }

    /// **`+` stays arithmetic.** Ruby overloads it on String, but blue's `+`
    /// lowers to tatara's numeric `+`; making it polymorphic would let a type
    /// error at a seam disappear into a string.
    #[test]
    fn plus_is_not_string_concatenation() {
        assert!(
            crate::run("\"a\" + \"b\"").is_err(),
            "`+` must not silently concatenate — use concat"
        );
    }

    #[test]
    fn split_and_join() {
        assert_eq!(i("length(split(\"a,b,c\", \",\"))"), 3);
        assert_eq!(s("join(split(\"a,b,c\", \",\"), \"-\")"), "a-b-c");
        // Ruby's `split("")` yields characters.
        assert_eq!(i("length(split(\"abc\", \"\"))"), 3);
    }

    #[test]
    fn predicates() {
        assert!(matches!(
            eval("contains?(\"hello\", \"ell\")"),
            Value::Bool(true)
        ));
        assert!(matches!(
            eval("contains?(\"hello\", \"xyz\")"),
            Value::Bool(false)
        ));
        assert!(matches!(
            eval("starts_with?(\"hello\", \"he\")"),
            Value::Bool(true)
        ));
        assert!(matches!(
            eval("ends_with?(\"hello\", \"lo\")"),
            Value::Bool(true)
        ));
    }

    fn refused(src: &str) -> String {
        match crate::run(src) {
            Ok(v) => panic!("{src:?} should fail, produced {:?}", v.value),
            Err(e) => e.to_string(),
        }
    }

    #[test]
    fn text_bytes_and_bytes_text_are_utf8_both_ways() {
        assert_eq!(ints("text_bytes(\"abc\")"), vec![97, 98, 99]);
        assert_eq!(ints("text_bytes(\"é\")"), vec![195, 169]);
        assert!(ints("text_bytes(\"\")").is_empty());
        assert_eq!(s("bytes_text([104, 195, 169])"), "hé");
        assert_eq!(s("bytes_text(text_bytes(\"€ x\"))"), "€ x");
        assert_eq!(s("bytes_text([])"), "");
        assert!(matches!(eval("bytes_text([195])"), Value::Nil));
        assert!(matches!(eval("bytes_text([255, 97])"), Value::Nil));
        assert!(refused("bytes_text([256])").contains("outside 0..=255"));
        assert!(refused("bytes_text(nil)").contains("string or a list of bytes"));
        assert!(refused("text_bytes(5)").contains("string"));
    }

    #[test]
    fn trim_without_options_cuts_whitespace_at_both_ends() {
        assert_eq!(s("trim(\"  a b \\n\")"), "a b");
        assert_eq!(s("trim(\"  a \", nil)"), "a");
        assert_eq!(s("trim(\"  a \", {})"), "a");
        assert_eq!(s("trim(\"\")"), "");
        assert_eq!(s("trim(\"   \")"), "");
        assert_eq!(s("trim(\"\", {side: :start})"), "");
    }

    #[test]
    fn trim_side_keeps_the_other_end() {
        assert_eq!(s("trim(\"  a  \", {side: :both})"), "a");
        assert_eq!(s("trim(\"  a  \", {side: :start})"), "a  ");
        assert_eq!(s("trim(\"  a  \", {side: :end})"), "  a");
    }

    #[test]
    fn trim_chars_replaces_whitespace_as_the_set_to_cut() {
        assert_eq!(s("trim(\"--a-b--\", {chars: \"-\"})"), "a-b");
        assert_eq!(s("trim(\"-+a+-\", {chars: \"-+\", side: :start})"), "a+-");
        assert_eq!(s("trim(\"-+a+-\", {chars: \"-+\", side: :end})"), "-+a");
        assert_eq!(s("trim(\" a \", {chars: \"-\"})"), " a ");
        assert_eq!(s("trim(\"aaa\", {chars: \"a\"})"), "");
        assert_eq!(s("trim(\"héé\", {chars: \"é\", side: :end})"), "h");
        assert_eq!(s("trim(\"  a  \", {chars: \"\"})"), "  a  ");
    }

    #[test]
    fn trim_refuses_what_it_does_not_take() {
        assert!(refused("trim(\"a\", {sid: :end})").contains("bad_option"));
        assert!(refused("trim(\"a\", {sid: :end})").contains("side, chars"));
        assert!(refused("trim(\"a\", {side: :middle})").contains("side must be"));
        assert!(refused("trim(\"a\", {side: \"end\"})").contains("bad_option"));
        assert!(refused("trim(\"a\", {chars: 1})").contains("chars must be text"));
        assert!(refused("trim(\"a\", 5)").contains("options must be a map"));
        assert!(refused("trim(\"a\", {}, {})").contains("1 to 2"));
        assert!(refused("trim()").contains("1 to 2"));
        assert!(refused("trim(5)").contains("string"));
    }

    #[test]
    fn trim_is_still_a_value_other_functions_take() {
        assert_eq!(s("join(map(trim, [\" a\", \"b \"]), \",\")"), "a,b");
    }

    #[test]
    fn text_index_answers_character_positions() {
        assert_eq!(i("text_index(\"héllo héllo\", \"llo\", 0)"), 2);
        assert_eq!(i("text_index(\"héllo héllo\", \"llo\", 3)"), 8);
        assert_eq!(i("text_index(\"héllo\", \"x\", 0)"), -1);
        assert_eq!(i("text_index(\"abc\", \"\", 3)"), 3);
        assert_eq!(i("text_index(\"abc\", \"\", 4)"), -1);
        assert_eq!(i("text_index(\"abc\", \"a\", -5)"), 0);
        assert_eq!(i("text_index(\"\", \"a\", 0)"), -1);
    }

    #[test]
    fn text_last_index_finds_the_last_start_at_or_before_from() {
        assert_eq!(i("text_last_index(\"héllo héllo\", \"llo\", 99)"), 8);
        assert_eq!(i("text_last_index(\"héllo héllo\", \"llo\", 7)"), 2);
        assert_eq!(i("text_last_index(\"aaa\", \"aa\", 1)"), 1);
        assert_eq!(i("text_last_index(\"aaa\", \"aa\", 0)"), 0);
        assert_eq!(i("text_last_index(\"abc\", \"x\", 2)"), -1);
        assert_eq!(i("text_last_index(\"abc\", \"a\", -1)"), -1);
        assert_eq!(i("text_last_index(\"ab\", \"abc\", 0)"), -1);
        assert_eq!(i("text_last_index(\"abc\", \"\", 9)"), 3);
    }

    #[test]
    fn replace_and_chars() {
        assert_eq!(s("replace(\"a-b-c\", \"-\", \"+\")"), "a+b+c");
        assert_eq!(i("length(chars(\"abc\"))"), 3);
    }

    /// Reversed by character, so a multi-byte character survives. A byte-wise
    /// reverse produces invalid UTF-8.
    #[test]
    fn reverse_is_character_wise() {
        assert_eq!(s("reverse(\"abc\")"), "cba");
        assert_eq!(s("reverse(\"héllo\")"), "olléh", "must not corrupt the é");
    }

    #[test]
    fn reverse_also_works_on_a_list() {
        assert_eq!(s("join(reverse([1, 2, 3]), \",\")"), "3,2,1");
    }

    /// **`to_int` answers nil on garbage, not 0.** Ruby's `String#to_i` returns
    /// 0, which silently turns a parse failure into a plausible number — a
    /// deliberate divergence, and the reason `to_int!` exists for callers who
    /// want the failure loudly.
    #[test]
    fn to_int_is_nil_on_garbage_rather_than_zero() {
        assert_eq!(i("to_int(\"42\")"), 42);
        assert!(
            matches!(eval("to_int(\"banana\")"), Value::Nil),
            "Ruby would say 0 here; a falsy nil cannot be mistaken for a result"
        );
        assert!(
            matches!(eval("to_int(\"0\")"), Value::Int(0)),
            "and a real 0 is still a real 0 — the two must stay distinguishable"
        );
    }

    #[test]
    fn to_int_bang_raises_on_garbage() {
        assert_eq!(i("to_int!(\"42\")"), 42);
        let err = crate::run("to_int!(\"banana\")").expect_err("must raise");
        assert!(err.to_string().contains("banana"), "must name it: {err}");
    }

    #[test]
    fn numeric_conversions_and_abs() {
        assert_eq!(i("to_int(3.9)"), 3);
        assert_eq!(i("abs(0 - 5)"), 5);
        assert!(matches!(eval("to_float(\"1.5\")"), Value::Float(_)));
        assert!(matches!(eval("to_float(\"nope\")"), Value::Nil));
    }

    /// A wrong-typed argument is a typed error, not a silent coercion.
    #[test]
    fn a_non_string_argument_is_a_type_error() {
        assert!(crate::run("upcase([1, 2])").is_err());
        assert!(crate::run("join(\"not a list\", \",\")").is_err());
    }
}
