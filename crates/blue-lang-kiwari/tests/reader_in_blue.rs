//! F1 of docs/pure-blue/front-tower-conformance.md, first commit: `yomi::lex`,
//! blue's lexer written in blue, gives the tokens and byte spans
//! `blue_lang_syntax::lex::lex` gives over every `.b` file under `spec/`, `bidamas/`, `gen/` and `crates/`, and
//! refuses what it refuses. Both sides are written as one canonical line per
//! token, so a difference names the file, the token and both readings.

use std::path::PathBuf;

use blue_lang_host::{Canonical, Entry, Program, Value};
use blue_lang_pkg::load_path::LoadPath;
use blue_lang_syntax::lex::{lex, Token, TokenKind};
use blue_lang_syntax::words::Flavor;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn blue_files(dir: &std::path::Path, out: &mut Vec<PathBuf>) {
    for entry in std::fs::read_dir(dir)
        .expect("a corpus directory")
        .flatten()
    {
        let path = entry.path();
        if path.is_dir() && !path.ends_with("target") {
            blue_files(&path, out);
        } else if path.extension().is_some_and(|x| x == "b") {
            out.push(path);
        }
    }
}

fn rust_line(t: &Token) -> String {
    let (kind, payload) = match &t.kind {
        TokenKind::Int(v) => ("int", v.to_string()),
        TokenKind::Float(v) => ("float", format!("{:x}", v.to_bits())),
        TokenKind::Str(s) => ("str", format!("{s:?}")),
        TokenKind::InterpolatedStr { parts, exprs } => ("interp", format!("{parts:?} {exprs:?}")),
        TokenKind::Sym(s) => ("sym", format!("{s:?}")),
        TokenKind::Words { flavor, words } => {
            let flavor = match flavor {
                Flavor::Strings => "strings",
                Flavor::Keywords => "keywords",
            };
            let words: Vec<String> = words
                .iter()
                .map(|(w, s)| format!("{w:?}@{}..{}", s.start, s.end))
                .collect();
            ("words", format!("{flavor} {words:?}"))
        }
        TokenKind::True => ("true", String::new()),
        TokenKind::False => ("false", String::new()),
        TokenKind::Nil => ("nil", String::new()),
        TokenKind::Ident(s) => ("ident", format!("{s:?}")),
        TokenKind::LParen => ("lparen", String::new()),
        TokenKind::RParen => ("rparen", String::new()),
        TokenKind::LBracket => ("lbracket", String::new()),
        TokenKind::RBracket => ("rbracket", String::new()),
        TokenKind::LBrace => ("lbrace", String::new()),
        TokenKind::RBrace => ("rbrace", String::new()),
        TokenKind::Comma => ("comma", String::new()),
        TokenKind::Dot => ("dot", String::new()),
        TokenKind::Colon => ("colon", String::new()),
        TokenKind::PathSep => ("path_sep", String::new()),
        TokenKind::Label(s) => ("label", format!("{s:?}")),
        TokenKind::Rocket => ("rocket", String::new()),
        TokenKind::Pipe => ("pipe", String::new()),
        TokenKind::Op(s) => ("op", format!("{s:?}")),
        TokenKind::Doc { module, text } => ("doc", format!("{module} {text:?}")),
        TokenKind::Comment(s) => ("comment", format!("{s:?}")),
        TokenKind::Newline => ("newline", String::new()),
        TokenKind::Eof => ("eof", String::new()),
    };
    format!("{kind} {}..{} {payload}", t.span.start, t.span.end)
}

fn text(v: &Value) -> String {
    match v {
        Value::Str(s) | Value::Keyword(s) | Value::Symbol(s) => s.to_string(),
        other => format!("{other:?}"),
    }
}

fn texts(v: &Value) -> Vec<String> {
    match v {
        Value::List(xs) => xs.iter().map(text).collect(),
        other => vec![format!("{other:?}")],
    }
}

fn int(v: &Value) -> i64 {
    match v {
        Value::Int(i) => *i,
        other => panic!("not an Int: {other:?}"),
    }
}

fn blue_line(v: &Value) -> String {
    let Value::List(t) = v else {
        panic!("a token is not a list: {v:?}")
    };
    let kind = text(&t[0]);
    let payload = match (kind.as_str(), &t[3]) {
        ("int", p) => int(p).to_string(),
        ("float", Value::Float(f)) => format!("{:x}", f.to_bits()),
        ("str" | "sym" | "ident" | "label" | "op" | "comment", p) => format!("{:?}", text(p)),
        ("interp", Value::List(pe)) => format!("{:?} {:?}", texts(&pe[0]), texts(&pe[1])),
        ("words", Value::List(fw)) => {
            let Value::List(ws) = &fw[1] else {
                panic!("words without a list: {fw:?}")
            };
            let words: Vec<String> = ws
                .iter()
                .map(|w| {
                    let Value::List(w) = w else {
                        panic!("a word is not a list: {w:?}")
                    };
                    format!("{:?}@{}..{}", text(&w[0]), int(&w[1]), int(&w[2]))
                })
                .collect();
            format!("{} {words:?}", text(&fw[0]))
        }
        ("doc", Value::List(md)) => {
            format!("{} {:?}", matches!(md[0], Value::Bool(true)), text(&md[1]))
        }
        (_, Value::Nil) => String::new(),
        (k, p) => panic!("token {k} carries {p:?}"),
    };
    format!("{kind} {}..{} {payload}", int(&t[1]), int(&t[2]))
}

#[test]
fn yomi_lex_agrees_with_the_rust_lexer_over_every_blue_file() {
    let program_text = "use(\"yomi\", [:lex])\n\ndef lines(src)\n  lex(src)\nend\n";
    let loader = LoadPath::new([root().join("bidamas")]);
    let mut program = Program::<()>::builder(Entry::anonymous(program_text))
        .loader(Box::leak(Box::new(loader)))
        .canonical(Canonical::Required)
        .load(&mut ())
        .expect("the probe loads with yomi");
    let mut files = Vec::new();
    for dir in ["spec", "bidamas", "gen", "crates"] {
        blue_files(&root().join(dir), &mut files);
    }
    files.sort();
    let mut differs = Vec::new();
    let mut tokens = 0usize;
    for f in &files {
        let src = std::fs::read_to_string(f).expect("a row file");
        let rust = lex(&src).map(|ts| ts.iter().map(rust_line).collect::<Vec<_>>());
        let blue = program
            .call::<Value>("lines", (src.clone(),), &mut ())
            .map(|v| match v {
                Value::List(ts) => ts.iter().map(blue_line).collect::<Vec<_>>(),
                other => panic!("lex gave {other:?}"),
            });
        match (rust, blue) {
            (Ok(r), Ok(b)) => {
                tokens += r.len();
                if let Some(i) = (0..r.len().max(b.len())).find(|&i| r.get(i) != b.get(i)) {
                    differs.push(format!(
                        "{}: token {i}: rust {:?}, blue {:?}",
                        f.display(),
                        r.get(i),
                        b.get(i)
                    ));
                }
            }
            (Err(_), Err(_)) => {}
            (r, b) => differs.push(format!(
                "{}: rust {}, blue {}",
                f.display(),
                if r.is_ok() { "reads it" } else { "refuses it" },
                if b.is_ok() { "reads it" } else { "refuses it" }
            )),
        }
    }
    assert!(
        differs.is_empty(),
        "yomi::lex differs:\n{}",
        differs.join("\n")
    );
    assert!(
        files.len() >= 500 && tokens >= 500_000,
        "{} files, {tokens} tokens",
        files.len()
    );
}
