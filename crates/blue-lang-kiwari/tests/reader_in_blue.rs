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

/// One node of `parse_program_tree`'s tree as `blue ast --tree-json` writes
/// it, `[start,end,kind,payload]`, a synthetic span `null` and a float by its bits.
fn rust_node(n: &tatara_lisp::Spanned) -> String {
    use tatara_lisp::{Atom, SpannedForm};
    let at = |x: usize| {
        if x == usize::MAX {
            "null".to_string()
        } else {
            x.to_string()
        }
    };
    let (kind, payload) = match &n.form {
        SpannedForm::Nil => ("nil", String::new()),
        SpannedForm::Atom(Atom::Symbol(x)) => ("sym", format!("{x:?}")),
        SpannedForm::Atom(Atom::Keyword(x)) => ("kw", format!("{x:?}")),
        SpannedForm::Atom(Atom::Str(x)) => ("str", format!("{x:?}")),
        SpannedForm::Atom(Atom::Int(x)) => ("int", x.to_string()),
        SpannedForm::Atom(Atom::Float(x)) => ("float", format!("{:x}", x.to_bits())),
        SpannedForm::Atom(Atom::Bool(x)) => ("bool", x.to_string()),
        SpannedForm::List(items) => (
            "list",
            items.iter().map(rust_node).collect::<Vec<_>>().join(","),
        ),
        SpannedForm::Quote(c) => ("quote", rust_node(c)),
        SpannedForm::Quasiquote(c) => ("quasiquote", rust_node(c)),
        SpannedForm::Unquote(c) => ("unquote", rust_node(c)),
        SpannedForm::UnquoteSplice(c) => ("unquote_splice", rust_node(c)),
    };
    format!("[{},{},{kind},{payload}]", at(n.span.start), at(n.span.end))
}

/// One node of `yomi::parse`'s tree in [`rust_node`]'s spelling.
fn blue_node(v: &Value) -> String {
    let Value::List(n) = v else {
        panic!("a node is not a list: {v:?}")
    };
    let at = |x: &Value| match x {
        Value::Nil => "null".to_string(),
        other => int(other).to_string(),
    };
    let kind = text(&n[2]);
    let payload = match (kind.as_str(), &n[3]) {
        ("nil", Value::Nil) => String::new(),
        ("sym" | "kw" | "str", p) => format!("{:?}", text(p)),
        ("int", p) => int(p).to_string(),
        ("float", Value::Float(f)) => format!("{:x}", f.to_bits()),
        ("bool", Value::Bool(b)) => b.to_string(),
        ("quote" | "quasiquote" | "unquote" | "unquote_splice", p) => blue_node(p),
        ("list", Value::List(items)) => items.iter().map(blue_node).collect::<Vec<_>>().join(","),
        (k, p) => panic!("node {k} carries {p:?}"),
    };
    format!("[{},{},{kind},{payload}]", at(&n[0]), at(&n[1]))
}

fn reader() -> Program<()> {
    let program_text = "use(\"yomi\", [:parse])\n\ndef forms(src)\n  parse(src)\nend\n";
    let loader = LoadPath::new([root().join("bidamas")]);
    Program::<()>::builder(Entry::anonymous(program_text))
        .loader(Box::leak(Box::new(loader)))
        .canonical(Canonical::Required)
        .load(&mut ())
        .expect("the probe loads with yomi")
}

/// The two readings of `src`: `parse_program_tree`'s and `yomi::parse`'s,
/// each a node per top-level form or the refusal's text.
fn readings(
    program: &mut Program<()>,
    src: &str,
) -> (Result<Vec<String>, String>, Result<Vec<String>, String>) {
    let rust = blue_lang_syntax::parse::parse_program_tree(src)
        .map(|fs| fs.iter().map(rust_node).collect::<Vec<_>>())
        .map_err(|e| e.to_string());
    let blue = program
        .call::<Value>("forms", (src.to_string(),), &mut ())
        .map(|v| match v {
            Value::List(fs) => fs.iter().map(blue_node).collect::<Vec<_>>(),
            other => panic!("parse gave {other:?}"),
        })
        .map_err(|e| e.to_string());
    (rust, blue)
}

/// The slice of F1's reader: each snippet is read by `parse_program_tree`
/// and by `yomi::parse` to the same tree, spans included.
const SNIPPETS: &[&str] = &[
    "x = f(1, a + b * 2)",
    ":k\n\"s\"\n1.5\n1e5\n2_000\nnil\ntrue\nfalse",
    "%w[a b]\n%i[c d]",
    "[1, x]\n[]\n[\n  1,\n  2,\n]",
    "{a: 1, \"b\" => 2}\n{}\n{a:, b: 2,}\n{**m}\n{a: 1, **m, b: 2}\n{a: 1, **(m)}",
    "-x\nnot y\n!z\n−w\n¬v\nnot(a)\nnot(a, b)\nnot (a == b)\nnot(a != nil)",
    "a - b - c\na or b and c\na ≠ b ≤ c\na && b || c\na == nil\nnil == a\nnil == nil\na % b / c",
    "retsu::first\na::b::c\nk::true\nretsu::first(xs)",
    "f(a, *b)\nf()\nf(\n  a,\n  b,\n)\nf(a, **m, k: 1)\nf(**m)\nf(k: 1, **m)\nf (x)\nequal?(a, nil)\nand(a, b)\nbegin(x)",
    "x.y\nx.y(1)\nx.y(*z)\nx.y.z(1)(2)\n(a + b).c",
    "x[0]\nx[:k]\nx[\"k\"]\nx[i + 1]\nm[:a][:b]",
    "x |> f\nx |> f(1)\nx |> not()\nx |> equal?(nil)\nx |> f |> g(1)",
    "(a + b) * c\n(\n  a\n)",
    "\"a#{x}b\"\n\"#{f(1)}\"\n\"a\\nb\"\n\"a\\n\"\n\"\\n\"\n\"#{x}\\n#{y}z\\n\"",
    "(x) -> x + 1\n() -> 1\n(a, b) -> a\nfn(x)\n  x\nend\nfn end\nfn(a,\n  b) a end",
    "if a\n  b\nend\nif a\n  b\nelse\n  c\nend\nif a\nelsif b\n  c\nelse\nend\nunless a == b\n  c\nend\nif a\n  b\nelse\n  # kept\nend",
    "if x\n  a\n  b\nend",
    "def f(a, b)\n  a + b\nend\ndef g\nend\ndef h(a, b?, c?)\n  a\nend",
    "def t(a: Int, b) -> List(Int)\n  [a]\nend\ndef u(a: kazu::Num, b?: Map(Str, Int)) nil end",
    "# a comment\nx = 1 # trailing\n\ny = x",
    "x = 1 # c\n:k\n\"s\"\n1.5\nnil\ntrue\nfalse\n%w[a b]\n%i[c]",
    "a::b::c\nk::true\nk::false\nk::nil",
    "(a)\n(x) -> x\n() -> 1\n(a, b) -> a\n(a + b)",
    "fn(a,\n  b) a end\nfn end",
    "-x\n!y\nnot z\nnot(a)\nnot(a, b)\nnot(*xs)\nand(a, b)\nbegin(x)",
    "f(*a)\nf()\nf(a,\n)\nf(a, b)\nf(**m, k: 1)",
    "{a: 1, **m, b:, \"c\" => 2,}\n{}\n{**m}\n[1,\n]\n[]\n[1, 2]",
    "x[:k]\nx[0]\nx.y\nx.y(1)\nx.y(*z)",
    "x |> f\nx |> f(1)\nx |> not()\nx |> equal?(nil)\nx |> g(if a\n  1\nend)",
    "a == nil\nnil == a\nnil == nil\nequal?(a, nil)\nnot (a == b)\nnot (a != b)\nnot (a != nil)\nnot (f(a, b, c))",
    "if a\n  b\nelsif c\n  d\nelse\n  e\nend\nif a\nelse\nend\nif a\nelse\n  # kept\nend\nunless a == b\n  c\nend",
    "def f(a, c: Int, b?, d?: m::T) -> List(Int, Str)\n  if a\n    nil\n  else\n    b\n    c\n  end\n  d\nend\ndef g\nend\ndef h() -> T() 1 end",
    "\"a#{x}b\"\n\"\\n\"\n\"a\\n\"\n\"a\\nb#{x}\\n#{y}\"",
    "a + b * c\na |> b\na or b",
    "(1)\nx |> if a\nend",
    "test \"a\", {kind: :unit}\n  assert f(1) == 2\n  x = 1\nend\ntest \"b\"\nend\ntest \"c\" end",
    "test \"d\", {\n  fakes: [:v, :a],\n  allow: %i[process network],\n  kind: :integration,\n  target: m::f,\n  satisfies: %i[nist_b nist_a]\n}\n  assert x\n  assert_panics f(1)\nend",
    "x = f(a) rescue nil\ny = a |> g rescue\n  1\nz = a rescue b |> c",
    "def f(a)\n  g(a)\nrescue :x, :y as e\n  h(e)\nrescue :z\nrescue other\n  2\nensure\n  done()\nend\ndef k\n  1\nensure\n  2\nend",
    "z = begin\n  w()\nrescue e\n  e\nend\ndef m\n  a\n  b\nrescue :q\n  c\nend\nv = begin\n  1\nrescue :a\nend\ndef n\nrescue _\nend",
    "def g -> Int\n  1\nrescue :a,\n  :b\n  2\nend\nbegin\n  x\nensure\nend",
    "record point(x, y)\nrecord t(n: Int, m: dyn, k: List(a::B),\n)\nunion shape = circle(r: Float)\n  | rect(w, h)\n@doc \"\"\"\nd\n\"\"\"\nrecord q(a)\n@doc \"\"\"\nd\n\"\"\"\nunion r = yes(v) | no(e)",
    "x = case a\nwhen 1\n  :one\nwhen nil\n  2\nelse\n  b\n  c\nend\ny = case f(a)\nwhen :k\nend\ncase a\nelse\nend",
    "def f(a)\n  case a\n  when 1\n    x = 2\n    x\n  when 2\n  else\n    if b\n    end\n  end\nend",
    "record point(x, y)\ndef f(v)\n  case v\n  when point(a, _)\n    a\n  when [1, b, *rest]\n    rest\n  when {name:, n: 2, k: [c]}\n    name\n  when [1, 2]\n    :lit\n  when point(1, 2)\n    :p\n  when x\n    x\n  end\nend",
    "def f(a)\n  if a\n    return 1\n  end\n  x = 2\n  x\nend\ndef g(a)\n  case a\n  when 1\n    return\n  when 2\n    b\n  else\n    return 3\n  end\n  c\nend\ndef h(a)\n  if a\n    return\n  else\n    y\n  end\n  z\nend\nreturn 4",
    "defmacro double(x)\n  quote\n    unquote(x) + unquote(x)\n  end\nend\ndefmacro m\nend\ndefmacro n()\n  quote\n    f(unquote_splice(xs))\n    \"a\\nb\"\n  end\nend",
    "def f(a)\n  x = g(a)?\n  h(x)?\n  y = k(x)\n  y\nend\ndef g(a)\n  [p, q] = f(a)?\n  if a\n    m(a)?\n  end\n  n(a)?\nend\ndef h(a)\n  case a\n  when 1\n    f(a)?\n  else\n    g(a)?\n  end\nend",
    "record p(x)\ndef g(m)\n  {x:} = m\n  x\nend\ncase q\nwhen {1 => b}\n  1\nwhen p(1, 2)\n  2\nwhen [[c]]\n  c\nwhen y\n  y\nend\ndef h(m)\n  {x:} = m\nend\n[[d]] = e",
    "def f(*a)\n  a\nend\ndef g(a, *b) -> Int\n  1\nend\nx = fn(a, *b) b end\ny = (*xs) -> xs\nz = (a, *xs) -> xs",
    "[a, *r] = xs\n{name:, k: [b, _]} = m\ndef g(m)\n  {x:} = m\n  [p, q] = f()\n  x\nend\ntest \"t\"\n  [u] = [1]\n  assert u == 1\nend",
];

#[test]
fn yomi_parse_agrees_with_the_rust_parser_on_every_snippet_of_the_slice() {
    let mut program = reader();
    let mut differs = Vec::new();
    for src in SNIPPETS {
        match readings(&mut program, src) {
            (Ok(r), Ok(b)) if r == b => {}
            (r, b) => differs.push(format!("{src:?}\n  rust {r:?}\n  blue {b:?}")),
        }
    }
    assert!(
        differs.is_empty(),
        "yomi::parse differs:\n{}",
        differs.join("\n")
    );
}

/// Sources both readers refuse: yomi's refusals of the forms past the first
/// slice are blue's own.
const REFUSED: &[&str] = &[
    "(a",
    "def f\n  x\nrescue\nend",
    "a b",
    "f(x) = 1",
    "f(x)?",
    "def f\n  g(h(x)?)\nend",
    ")",
    "begin (x)",
    "begin\n  x\nend",
    "begin\nrescue e\nrescue :a\nend",
    "begin\nrescue :a as 1\nend",
    "begin\nrescue :a, 1\nend",
    "begin\nrescue 1\nend",
    "begin\nensure\nrescue e\nend",
    "case x",
    "case x\nend",
    "case x\ny\nend",
    "(*a, b) -> a",
    "fn(*a, b) end",
    "+x",
    "[*a]",
    "[*1]",
    "[a, *r, b] = x",
    "[a, a] = x",
    "[1] + [2] = x",
    "{**m} = x",
    "def f(*1) end",
    "def f(a?, *b) end",
    "def f(*a, b) end",
    "def f(a?, b) end",
    "def f(1) end",
    "def f\n  return 1\n  2\nend",
    "test x end",
    "test \"a\", 1\nend",
    "test \"a\", {}\nend",
    "test \"a\", {**m}\nend",
    "test \"a\", {k: 1}\nend",
    "test \"a\", {kind: :unit, kind: :unit}\nend",
    "test \"a\", {target: 1}\nend",
    "test \"a\", {kind: :x}\nend",
    "test \"a\", {allow: 1}\nend",
    "test \"a\", {allow: []}\nend",
    "test \"a\", {allow: [1]}\nend",
    "test \"a\", {allow: %i[a a]}\nend",
    "record p?(x)",
    "record p()",
    "record p(x, x)",
    "record p(a?)",
    "record p(1)",
    "record p(x y)",
    "union u? = a(x)",
    "union u = u(x)",
    "union u = a(x) | a(y)",
    "union u = 1",
    "defmacro 1 end",
    "defmacro m(a: Int) end",
    "defmacro m(*a) end",
    "defmacro m -> T end",
    "unquote x",
    "do",
];

#[test]
fn yomi_parse_refuses_what_the_rust_parser_refuses() {
    let mut program = reader();
    let mut differs = Vec::new();
    for src in REFUSED {
        match readings(&mut program, src) {
            (Err(_), Err(b)) if b.contains(":parse") => {}
            (r, b) => differs.push(format!("{src:?}\n  rust {r:?}\n  blue {b:?}")),
        }
    }
    assert!(
        differs.is_empty(),
        "yomi::parse and blue's parser disagree on a refusal:\n{}",
        differs.join("\n")
    );
}

/// Over every `.b` file: a file yomi reads is read to the same tree as
/// blue's parser; the rest it refuses with `:parse` (outside the slice). The
/// count read identically end to end may only grow.
#[test]
fn yomi_parse_reads_a_corpus_file_identically_or_refuses_it() {
    let mut program = reader();
    let mut files = Vec::new();
    for dir in ["spec", "bidamas", "gen", "crates"] {
        blue_files(&root().join(dir), &mut files);
    }
    let mut files: Vec<PathBuf> = files
        .into_iter()
        .map(|f| f.canonicalize().expect("a corpus path"))
        .collect();
    files.sort();
    files.dedup();
    let mut same = 0usize;
    let mut differs = Vec::new();
    for f in &files {
        let src = std::fs::read_to_string(f).expect("a corpus file");
        match readings(&mut program, &src) {
            (Ok(r), Ok(b)) if r == b => same += 1,
            (Ok(r), Ok(b)) => {
                let i = (0..r.len().max(b.len()))
                    .find(|&i| r.get(i) != b.get(i))
                    .unwrap_or(0);
                differs.push(format!(
                    "{}: form {i}:\n  rust {:?}\n  blue {:?}",
                    f.display(),
                    r.get(i),
                    b.get(i)
                ));
            }
            (Err(_), Ok(_)) => {
                differs.push(format!("{}: blue reads what rust refuses", f.display()))
            }
            (_, Err(_)) => {}
        }
    }
    eprintln!(
        "yomi::parse reads {same} of {} .b files identically",
        files.len()
    );
    assert!(
        differs.is_empty(),
        "yomi::parse differs:\n{}",
        differs.join("\n")
    );
    assert!(
        same >= READ_IDENTICALLY,
        "{same} files read identically, the floor is {READ_IDENTICALLY}"
    );
}

const READ_IDENTICALLY: usize = 457;
