//! The generators behind the property laws: programs built from every form the
//! parser can lower, in every position. Shared by every file that holds a law
//! over them.

use std::collections::BTreeSet;
use std::sync::OnceLock;

use blue_lang_syntax::{is_reserved_word, lex, parse_program, Sexp, TokenKind, INFIX};
use proptest::prelude::*;

/// Sources whose trees contain every lowering the parser performs.
pub const SEED: &[&str] = &[
    "x = 1",
    "def f(a)\n  a\nend",
    "def g(a: Int) -> Int\n  a\nend",
    "fn(x)\n  x\nend",
    "test \"t\"\n  assert 1\nend",
    "if a\n  1\n  2\nelse\n  3\nend",
    "unless a\n  1\nend",
    "case x\nwhen 1\n  2\nelse\n  3\nend",
    "[1]",
    "{a: 1}",
    "\"a#{x}b\"",
    "-x",
    "!x",
    "defmacro m(a)\n  quote\n    unquote(a)\n  end\nend",
];

fn heads(s: &Sexp, out: &mut BTreeSet<String>) {
    match s {
        Sexp::List(items) => {
            if let Some(Sexp::Atom(tatara_lisp::Atom::Symbol(h))) = items.first() {
                out.insert(h.to_string());
            }
            for i in items {
                heads(i, out);
            }
        }
        Sexp::Quote(i) | Sexp::Quasiquote(i) | Sexp::Unquote(i) | Sexp::UnquoteSplice(i) => {
            heads(i, out);
        }
        _ => {}
    }
}

/// Is `name` spellable as a call's head: one identifier token, not reserved?
fn callable(name: &str) -> bool {
    (!is_reserved_word(name) || blue_lang_syntax::OPERATOR_KEYWORDS.contains(&name))
        && matches!(
            lex(name).as_deref(),
            Ok([t, e]) if matches!(&t.kind, TokenKind::Ident(n) if n == name)
                && e.kind == TokenKind::Eof
        )
}

/// The printer's vocabulary, derived: every head the parser emits, and every
/// infix callee, that a plain call can also spell.
pub fn vocabulary() -> &'static Vec<String> {
    static V: OnceLock<Vec<String>> = OnceLock::new();
    V.get_or_init(|| {
        let mut all = BTreeSet::new();
        for src in SEED {
            for form in parse_program(src).expect("seed parses") {
                heads(&form, &mut all);
            }
        }
        all.extend(INFIX.iter().map(|i| i.callee.to_string()));
        all.into_iter().filter(|n| callable(n)).collect()
    })
}

/// Positive control: the vocabulary must hold the heads this file exists
/// for. If lowering renamed one, the generator would silently stop reaching it.
#[test]
fn the_vocabulary_reaches_the_printers_special_heads() {
    let v = vocabulary();
    for must in [
        "define", "lambda", "deftest", "list", "not", "concat", "equal?", "and", "or",
    ] {
        assert!(v.iter().any(|n| n == must), "{must} missing from {v:?}");
    }
}

pub fn ident() -> impl Strategy<Value = String> {
    "[a-z][a-z_]{0,6}".prop_filter("not reserved", |s| !is_reserved_word(s))
}

/// `pkg::name`: the qualifier in every position a name can take. The name
/// side may be a reserved word (`kueri::if`), which is a name only there.
fn qualified() -> impl Strategy<Value = String> {
    (
        ident(),
        prop_oneof![ident(), Just("if".to_string()), Just("def".to_string())],
    )
        .prop_map(|(p, n)| format!("{p}::{n}"))
}

pub fn head() -> impl Strategy<Value = String> {
    prop_oneof![
        3 => prop::sample::select(vocabulary().clone()),
        1 => ident(),
        1 => qualified(),
    ]
}

/// A string literal's source, including the characters the lexer treats
/// specially inside one: quotes, backslashes, `#`, braces, and an escaped
/// `{` that puts a literal `#{` into the string's value.
pub fn string() -> impl Strategy<Value = String> {
    prop::collection::vec(
        prop_oneof![
            "[a-z ]{1,4}",
            Just("\\\"".to_string()),
            Just("\\\\".to_string()),
            Just("\\n".to_string()),
            Just("#".to_string()),
            Just("{".to_string()),
            Just("}".to_string()),
            Just("#\\u{7b}".to_string()),
        ],
        0..5,
    )
    .prop_map(|parts| format!("\"{}\"", parts.concat()))
}

/// A type as the surface writes it: a name, or a constructor of any arity.
pub fn ty() -> impl Strategy<Value = String> {
    let name = prop_oneof![
        Just("Int".to_string()),
        Just("Str".to_string()),
        Just("dyn".to_string())
    ];
    name.prop_recursive(2, 6, 3, |inner| {
        (
            prop_oneof![Just("List"), Just("Map"), Just("Unit")],
            prop::collection::vec(inner, 0..3),
        )
            .prop_map(|(c, args)| format!("{c}({})", args.join(", ")))
    })
}

pub fn leaf() -> impl Strategy<Value = String> {
    prop_oneof![
        ident(),
        qualified(),
        (0i64..1000).prop_map(|n| n.to_string()),
        (0u32..100, 0u32..100).prop_map(|(a, b)| format!("{a}.{b}")),
        string(),
        ident().prop_map(|s| format!(":{s}")),
        Just("true".to_string()),
        Just("nil".to_string()),
    ]
}

fn args(inner: BoxedStrategy<String>) -> impl Strategy<Value = String> {
    prop::collection::vec(inner, 0..4).prop_map(|a| a.join(", "))
}

/// A body: one or more statements, one per line.
fn body(inner: BoxedStrategy<String>) -> impl Strategy<Value = String> {
    prop::collection::vec(statement(inner), 1..3).prop_map(|s| s.join("\n"))
}

pub fn statement(inner: BoxedStrategy<String>) -> impl Strategy<Value = String> {
    prop_oneof![
        2 => inner.clone(),
        1 => (ident(), inner).prop_map(|(x, e)| format!("{x} = {e}")),
    ]
}

pub fn expr() -> impl Strategy<Value = String> {
    leaf().prop_recursive(4, 40, 4, |inner| {
        let e = inner.clone().boxed();
        let ops: Vec<&'static str> = INFIX.iter().map(|i| i.op).collect();
        prop_oneof![
            (head(), args(e.clone())).prop_map(|(f, a)| format!("{f}({a})")),
            (head(), args(e.clone()), args(e.clone()))
                .prop_map(|(f, a, b)| format!("{f}({a})({b})")),
            args(e.clone()).prop_map(|a| format!("[{a}]")),
            prop::collection::vec((ident(), e.clone()), 0..3).prop_map(|kv| {
                let kv: Vec<String> = kv.into_iter().map(|(k, v)| format!("{k}: {v}")).collect();
                format!("{{{}}}", kv.join(", "))
            }),
            (e.clone(), e.clone()).prop_map(|(k, v)| format!("{{{k} => {v}}}")),
            (e.clone(), prop::sample::select(ops), e.clone())
                .prop_map(|(a, op, b)| format!("{a} {op} {b}")),
            (e.clone(), prop::sample::select(vec!["-", "!"]))
                .prop_map(|(a, op)| format!("{op}{a}")),
            (prop::collection::vec(ident(), 0..3), body(e.clone()))
                .prop_map(|(p, b)| format!("fn({})\n{b}\nend", p.join(", "))),
            (e.clone(), body(e.clone())).prop_map(|(c, b)| format!("if {c}\n{b}\nend")),
            (e.clone(), body(e.clone()), body(e.clone()))
                .prop_map(|(c, t, f)| format!("if {c}\n{t}\nelse\n{f}\nend")),
            (e.clone(), e.clone(), body(e.clone()))
                .prop_map(|(s, p, b)| format!("case {s}\nwhen {p}\n{b}\nend")),
            (
                ident(),
                prop::collection::vec(ident(), 0..3),
                body(e.clone())
            )
                .prop_map(|(n, p, b)| format!("def {n}({})\n{b}\nend", p.join(", "))),
            (ident(), body(e.clone()))
                .prop_map(|(n, b)| format!("def {n}(a: Int) -> Int\n{b}\nend")),
            (string(), body(e.clone())).prop_map(|(n, b)| format!("test {n}\n{b}\nend")),
            e.clone().prop_map(|x| format!("assert {x}")),
            body(e.clone()).prop_map(|b| format!("quote\n{b}\nend")),
            e.clone().prop_map(|x| format!("unquote({x})")),
            e.clone().prop_map(|x| format!("\"a#{{{x}}}b\"")),
            (e.clone(), ident(), args(e.clone())).prop_map(|(r, m, a)| format!("{r}.{m}({a})")),
            (e.clone(), head(), args(e.clone())).prop_map(|(x, f, a)| format!("{x} |> {f}({a})")),
            // A pipeline into ANY expression, not only a call: the parser
            // threads the left side into an operator or a block just the same,
            // and builds a tree no call can spell.
            (e.clone(), e.clone()).prop_map(|(x, y)| format!("{x} |> {y}")),
            e.clone().prop_map(|x| format!("({x})")),
            (e.clone(), e.clone()).prop_map(|(a, b)| format!("({a}) rescue ({b})")),
            (body(e.clone()), ident(), body(e.clone()))
                .prop_map(|(b, v, h)| format!("begin\n{b}\nrescue {v}\n{h}\nend")),
            (body(e.clone()), body(e.clone()))
                .prop_map(|(b, c)| format!("begin\n{b}\nensure\n{c}\nend")),
            (ident(), ty(), ty(), body(e.clone()))
                .prop_map(|(n, p, r, b)| format!("def {n}(a: {p}) -> {r}\n{b}\nend")),
            (head(), args(e.clone()), e.clone()).prop_map(|(f, a, s)| format!("{f}({a}, *{s})")),
            (prop::collection::vec(ident(), 0..3), e.clone())
                .prop_map(|(p, b)| format!("({}) -> {b}", p.join(", "))),
        ]
    })
}

pub fn program() -> impl Strategy<Value = String> {
    prop::collection::vec(statement(expr().boxed()), 1..4).prop_map(|s| s.join("\n"))
}
