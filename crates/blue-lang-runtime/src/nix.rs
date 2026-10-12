use std::fmt;
use std::sync::Arc;

use rnix::{NodeOrToken, ParseError, SyntaxKind, SyntaxNode, TextRange};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, MapKey, Value};

pub fn install_nix_stdlib<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "nix_parse",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| match &args[0] {
            Value::Str(s) => Ok(parse(s)),
            other => Err(EvalError::native_fn(
                "nix_parse",
                format!("expected a string of Nix source, got {}", other.type_name()),
                span,
            )),
        },
    );
}

pub fn parse(src: &str) -> Value {
    let offsets = CharOffsets::new(src);
    let parsed = rnix::Root::parse(src);
    let errors = parsed
        .errors()
        .iter()
        .map(|e| error_value(&Problem::from(e), &offsets, src))
        .collect::<Vec<_>>();
    record([
        ("root", node_value(&parsed.syntax(), &offsets)),
        ("errors", Value::list(errors)),
    ])
}

struct CharOffsets {
    by_byte: Vec<i64>,
}

impl CharOffsets {
    fn new(src: &str) -> Self {
        let mut by_byte = vec![0; src.len() + 1];
        let mut chars = 0i64;
        for (i, c) in src.char_indices() {
            for slot in &mut by_byte[i..i + c.len_utf8()] {
                *slot = chars;
            }
            chars += 1;
        }
        by_byte[src.len()] = chars;
        Self { by_byte }
    }

    fn at(&self, byte: usize) -> Value {
        Value::Int(self.by_byte[byte])
    }
}

fn key(name: &str) -> MapKey {
    MapKey::Keyword(Arc::from(name))
}

fn record<const N: usize>(fields: [(&str, Value); N]) -> Value {
    Value::map(fields.into_iter().map(|(k, v)| (key(k), v)))
}

fn kind_name(kind: SyntaxKind) -> Value {
    Value::Str(Arc::from(format!("{kind:?}")))
}

fn node_value(node: &SyntaxNode, offsets: &CharOffsets) -> Value {
    let range = node.text_range();
    let children = node
        .children_with_tokens()
        .map(|child| match child {
            NodeOrToken::Node(n) => node_value(&n, offsets),
            NodeOrToken::Token(t) => {
                let r = t.text_range();
                record([
                    ("kind", kind_name(t.kind())),
                    ("start", offsets.at(r.start().into())),
                    ("end", offsets.at(r.end().into())),
                    ("text", Value::Str(Arc::from(t.text()))),
                ])
            }
        })
        .collect::<Vec<_>>();
    record([
        ("kind", kind_name(node.kind())),
        ("start", offsets.at(range.start().into())),
        ("end", offsets.at(range.end().into())),
        ("children", Value::list(children)),
    ])
}

enum Problem {
    Unexpected(TextRange),
    Extra(TextRange),
    Wanted(SyntaxKind, TextRange, Vec<SyntaxKind>),
    DoubleBind(TextRange),
    Eof,
    EofWanted(Vec<SyntaxKind>),
    DuplicatedArgs(TextRange, String),
    TooDeep,
    Other(String),
}

impl From<&ParseError> for Problem {
    fn from(e: &ParseError) -> Self {
        match e {
            ParseError::Unexpected(r) => Problem::Unexpected(*r),
            ParseError::UnexpectedExtra(r) => Problem::Extra(*r),
            ParseError::UnexpectedWanted(got, r, want) => {
                Problem::Wanted(*got, *r, want.to_vec())
            }
            ParseError::UnexpectedDoubleBind(r) => Problem::DoubleBind(*r),
            ParseError::UnexpectedEOF => Problem::Eof,
            ParseError::UnexpectedEOFWanted(want) => Problem::EofWanted(want.to_vec()),
            ParseError::DuplicatedArgs(r, name) => Problem::DuplicatedArgs(*r, name.clone()),
            ParseError::RecursionLimitExceeded => Problem::TooDeep,
            other => Problem::Other(format!("{other:?}")),
        }
    }
}

impl Problem {
    fn range(&self) -> Option<TextRange> {
        match self {
            Problem::Unexpected(r)
            | Problem::Extra(r)
            | Problem::Wanted(_, r, _)
            | Problem::DoubleBind(r)
            | Problem::DuplicatedArgs(r, _) => Some(*r),
            Problem::Eof | Problem::EofWanted(_) | Problem::TooDeep | Problem::Other(_) => None,
        }
    }
}

struct Kinds<'a>(&'a [SyntaxKind]);

impl fmt::Display for Kinds<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for (i, k) in self.0.iter().enumerate() {
            if i > 0 {
                write!(f, ", ")?;
            }
            write!(f, "{k:?}")?;
        }
        Ok(())
    }
}

impl fmt::Display for Problem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Problem::Unexpected(_) => write!(f, "unexpected input"),
            Problem::Extra(_) => write!(f, "unexpected input after the expression"),
            Problem::Wanted(got, _, want) => {
                write!(f, "unexpected {got:?}, wanted one of {}", Kinds(want))
            }
            Problem::DoubleBind(_) => write!(f, "a pattern bound twice"),
            Problem::Eof => write!(f, "unexpected end of input"),
            Problem::EofWanted(want) => {
                write!(f, "unexpected end of input, wanted one of {}", Kinds(want))
            }
            Problem::DuplicatedArgs(_, name) => write!(f, "argument {name} given twice"),
            Problem::TooDeep => write!(f, "nested too deeply to parse"),
            Problem::Other(raw) => write!(f, "{raw}"),
        }
    }
}

fn error_value(p: &Problem, offsets: &CharOffsets, src: &str) -> Value {
    let (start, end) = match p.range() {
        Some(r) => (offsets.at(r.start().into()), offsets.at(r.end().into())),
        None => (offsets.at(src.len()), offsets.at(src.len())),
    };
    record([
        ("message", Value::Str(Arc::from(p.to_string()))),
        ("start", start),
        ("end", end),
    ])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn field<'a>(v: &'a Value, name: &str) -> &'a Value {
        match v {
            Value::Map(m) => m.get(&key(name)).expect("field present"),
            other => panic!("expected a map, got {}", other.type_name()),
        }
    }

    fn text_of(v: &Value) -> String {
        match v {
            Value::Map(m) => match (m.get(&key("text")), m.get(&key("children"))) {
                (Some(Value::Str(s)), _) => s.to_string(),
                (_, Some(Value::List(xs))) => xs.iter().map(text_of).collect(),
                _ => panic!("neither a token nor a node"),
            },
            other => panic!("expected a map, got {}", other.type_name()),
        }
    }

    fn kind(v: &Value) -> String {
        match field(v, "kind") {
            Value::Str(s) => s.to_string(),
            _ => unreachable!(),
        }
    }

    fn int(v: &Value) -> i64 {
        match v {
            Value::Int(n) => *n,
            _ => panic!("expected an int"),
        }
    }

    fn errors(v: &Value) -> usize {
        match field(v, "errors") {
            Value::List(xs) => xs.len(),
            _ => unreachable!(),
        }
    }

    #[test]
    fn the_tree_is_lossless() {
        let src = "# a comment\n{ a.b = 1; /* x */ c = \"é ${d}\"; }\n";
        let v = parse(src);
        assert_eq!(text_of(field(&v, "root")), src);
        assert_eq!(errors(&v), 0);
    }

    #[test]
    fn the_empty_source_is_an_empty_root_with_an_error() {
        let v = parse("");
        let root = field(&v, "root");
        assert_eq!(kind(root), "NODE_ROOT");
        assert_eq!(int(field(root, "end")), 0);
        assert_eq!(errors(&v), 1);
    }

    #[test]
    fn offsets_count_characters_not_bytes() {
        let src = "\"éé\" + x";
        let v = parse(src);
        let root = field(&v, "root");
        assert_eq!(int(field(root, "end")), src.chars().count() as i64);
        assert_ne!(src.len(), src.chars().count());
    }

    #[test]
    fn kinds_are_rnix_names() {
        let v = parse("{ a = 1; }");
        let root = field(&v, "root");
        let Value::List(xs) = field(root, "children") else { unreachable!() };
        assert_eq!(kind(&xs[0]), "NODE_ATTR_SET");
    }

    #[test]
    fn a_parse_error_names_where_it_is() {
        let v = parse("{ a = ; }");
        assert!(errors(&v) >= 1);
        let Value::List(es) = field(&v, "errors") else { unreachable!() };
        let start = int(field(&es[0], "start"));
        assert!((0..=9).contains(&start));
        let Value::Str(m) = field(&es[0], "message") else { unreachable!() };
        assert!(!m.is_empty());
        assert_eq!(text_of(field(&v, "root")), "{ a = ; }");
    }

    #[test]
    fn the_primitive_is_reachable_from_blue() {
        let v = crate::run(r#"get(get(nix_parse("x: x"), :root), :kind)"#).expect("runs");
        assert!(matches!(v.value, Value::Str(ref s) if s.as_ref() == "NODE_ROOT"));
        assert!(crate::run("nix_parse(1)").is_err());
    }
}
