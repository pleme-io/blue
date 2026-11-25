use std::collections::BTreeSet;

use blue_lang_lsp::{Response, Server};
use blue_lang_mondou::{Engine, Query};
use blue_lang_runtime::uses::NoLoader;
use serde_json::{json, Value};

const SOURCE: &str = r#"@doc """
A point on the plane.
"""
record point(x, y)

union shape = circle(r) | square(s)

LIMIT = 3

twice = (n) -> n * 2

def f(xs)
  xs
end

def typed(n: Int) -> Int
  n
end

defmacro both(x)
  quote
    unquote(x)
  end
end

def g(v)
  if point?(v) or shape?(v) or circle?(v) or square?(v)
    circle(1)
  else
    point(1, 2)
  end
end

test "g reads every shape"
  assert g(point(1, 2)) == circle(1)
end
"#;

const URI: &str = "file:///shapes.b";

struct Shape {
    name: &'static str,
    kind: &'static str,
    binds: &'static [&'static str],
    runtime: (&'static str, &'static str),
    symbol: i64,
    signature: &'static str,
}

const SHAPES: &[Shape] = &[
    Shape {
        name: "point",
        kind: "record",
        binds: &["point", "point?"],
        runtime: ("point", "Value"),
        symbol: 23,
        signature: "record point(x, y)",
    },
    Shape {
        name: "shape",
        kind: "union",
        binds: &["shape?"],
        runtime: ("shape?", "Value"),
        symbol: 10,
        signature: "union shape = circle(r) | square(s)",
    },
    Shape {
        name: "circle",
        kind: "record",
        binds: &["circle", "circle?"],
        runtime: ("circle", "Value"),
        symbol: 23,
        signature: "record circle(r)",
    },
    Shape {
        name: "square",
        kind: "record",
        binds: &["square", "square?"],
        runtime: ("square", "Value"),
        symbol: 23,
        signature: "record square(s)",
    },
    Shape {
        name: "LIMIT",
        kind: "value",
        binds: &["LIMIT"],
        runtime: ("LIMIT", "Value"),
        symbol: 13,
        signature: "LIMIT = 3",
    },
    Shape {
        name: "twice",
        kind: "function",
        binds: &["twice"],
        runtime: ("twice", "Function"),
        symbol: 12,
        signature: "twice = (n) -> n * 2",
    },
    Shape {
        name: "f",
        kind: "function",
        binds: &["f"],
        runtime: ("f", "Function"),
        symbol: 12,
        signature: "def f(xs)",
    },
    Shape {
        name: "typed",
        kind: "function",
        binds: &["typed"],
        runtime: ("typed", "Function"),
        symbol: 12,
        signature: "def typed(n: Int) -> Int",
    },
    Shape {
        name: "both",
        kind: "macro",
        binds: &["both"],
        runtime: ("both", "Macro"),
        symbol: 12,
        signature: "defmacro both(x)",
    },
    Shape {
        name: "g",
        kind: "function",
        binds: &["g"],
        runtime: ("g", "Function"),
        symbol: 12,
        signature: "def g(v)",
    },
];

const KINDS: &[&str] = &["function", "value", "macro", "record", "union"];

fn shape_of(bound: &str) -> &'static Shape {
    SHAPES
        .iter()
        .find(|s| s.binds.contains(&bound))
        .unwrap_or_else(|| panic!("no shape binds {bound}"))
}

fn bound() -> BTreeSet<String> {
    SHAPES
        .iter()
        .flat_map(|s| s.binds.iter().map(|b| (*b).to_string()))
        .collect()
}

fn check(face: &str, got: impl std::fmt::Debug, want: impl std::fmt::Debug, out: &mut Vec<String>) {
    let (got, want) = (format!("{got:?}"), format!("{want:?}"));
    if got != want {
        out.push(format!("{face}\n    got:  {got}\n    want: {want}"));
    }
}

fn resolver_names(forms: &[blue_lang_syntax::Spanned]) -> BTreeSet<String> {
    forms
        .iter()
        .flat_map(blue_lang_syntax::scope::definitions_of)
        .map(|(name, _, _)| name)
        .collect()
}

fn line_col(offset: usize) -> (usize, usize) {
    let line = SOURCE[..offset].matches('\n').count();
    let start = SOURCE[..offset].rfind('\n').map_or(0, |n| n + 1);
    (line, offset - start)
}

fn position(offset: usize) -> Value {
    let (line, character) = line_col(offset);
    json!({ "line": line, "character": character })
}

fn request(s: &mut Server, method: &str, params: Value) -> Value {
    match s.handle_value(&json!({ "jsonrpc": "2.0", "id": 1, "method": method, "params": params }))
    {
        Response::Reply(r) => r,
        other => panic!("{method}: expected a reply, got {other:?}"),
    }
}

fn at(offset: usize) -> Value {
    json!({ "textDocument": { "uri": URI }, "position": position(offset) })
}

fn uses_in_g() -> Vec<(&'static str, usize)> {
    let body = SOURCE.find("def g(v)").expect("g");
    [
        "point?",
        "shape?",
        "circle?",
        "square?",
        "circle(1)",
        "point(1, 2)",
    ]
    .into_iter()
    .map(|written| {
        let name = written.split('(').next().unwrap_or(written);
        let name: &'static str = SHAPES
            .iter()
            .flat_map(|s| s.binds.iter().copied())
            .find(|b| *b == name)
            .expect("a bound name");
        (
            name,
            body + SOURCE[body..].find(written).expect("g writes it"),
        )
    })
    .collect()
}

#[test]
fn every_definition_shape_reads_alike_through_every_face() {
    let mut out = Vec::new();

    let cli = blue_lang_syntax::parse_program_tree(SOURCE).expect("parses");
    check(
        "the resolver over the tree `blue check` reads",
        resolver_names(&cli),
        bound(),
        &mut out,
    );

    let mut engine = Engine::new(Box::new(NoLoader));
    engine.set_document("shapes", None, SOURCE);
    let analysis = engine.analysis("shapes").expect("analysed");
    let editor = analysis.parsed.as_ref().as_ref().expect("parses");
    check(
        "the resolver over the tree the editor checks",
        resolver_names(editor),
        bound(),
        &mut out,
    );

    let mut runtime: Vec<(String, String)> = cli
        .iter()
        .filter_map(blue_lang_runtime::def_hash::defined)
        .map(|(key, kind)| (key.to_string(), format!("{kind:?}")))
        .collect();
    runtime.sort();
    let mut want: Vec<(String, String)> = SHAPES
        .iter()
        .map(|s| (s.runtime.0.to_string(), s.runtime.1.to_string()))
        .collect();
    want.sort();
    check(
        "def_hash::defined, the facts' keys",
        runtime,
        want,
        &mut out,
    );

    let documented = blue_lang_syntax::parse_program_documented(SOURCE).expect("parses");
    let documented_names: Vec<&str> = documented
        .iter()
        .filter_map(|f| match blue_lang_syntax::doc::documented(f) {
            Some((_, def)) => blue_lang_syntax::doc::defined_name(def),
            None => blue_lang_syntax::doc::defined_name(f),
        })
        .collect();
    check(
        "doc::defined_name, the documentation rules' names",
        documented_names,
        [
            "point", "shape", "LIMIT", "twice", "f", "typed", "both", "g",
        ],
        &mut out,
    );

    for kind in KINDS {
        let want: Vec<(&str, &str)> = SHAPES
            .iter()
            .filter(|s| s.kind == *kind)
            .map(|s| (s.name, s.kind))
            .collect();
        let got: Result<Vec<(String, String)>, String> = Query::parse(&format!("(kind {kind})"))
            .map_err(|e| e.to_string())
            .and_then(|q| engine.query("shapes", &q).map_err(|e| e.to_string()))
            .map(|hits| {
                let mut hits: Vec<(String, String)> = hits
                    .iter()
                    .map(|h| {
                        (
                            h.definition.clone(),
                            h.json("shapes.b")["kind"]
                                .as_str()
                                .unwrap_or("")
                                .to_string(),
                        )
                    })
                    .collect();
                hits.sort_by_key(|(name, _)| SHAPES.iter().position(|s| *name == s.name));
                hits
            });
        check(
            &format!("blue query (kind {kind})"),
            got,
            Ok::<_, String>(want),
            &mut out,
        );
    }

    let mut server = Server::with_loader(Box::new(NoLoader));
    let opened = server.handle_value(&json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": { "textDocument": { "uri": URI, "text": SOURCE } },
    }));
    let unbound: Vec<String> = match &opened {
        Response::Messages(all) => all
            .iter()
            .filter(|m| m["method"] == json!("textDocument/publishDiagnostics"))
            .flat_map(|m| {
                m["params"]["diagnostics"]
                    .as_array()
                    .cloned()
                    .unwrap_or_default()
            })
            .filter(|d| d["code"] == json!("B0001"))
            .map(|d| d["message"].as_str().unwrap_or("").to_string())
            .collect(),
        other => vec![format!("no diagnostics push: {other:?}")],
    };
    check(
        "the editor's B0001 findings",
        unbound,
        Vec::<String>::new(),
        &mut out,
    );

    let symbols = request(
        &mut server,
        "textDocument/documentSymbol",
        json!({ "textDocument": { "uri": URI } }),
    );
    let outline: Vec<(String, i64, String)> = symbols["result"]
        .as_array()
        .cloned()
        .unwrap_or_default()
        .iter()
        .filter(|s| s["kind"] != json!(24))
        .map(|s| {
            (
                s["name"].as_str().unwrap_or("").to_string(),
                s["kind"].as_i64().unwrap_or(0),
                s["detail"].as_str().unwrap_or("").to_string(),
            )
        })
        .collect();
    let want: Vec<(&str, i64, &str)> = SHAPES
        .iter()
        .map(|s| (s.name, s.symbol, s.signature))
        .collect();
    check("the language server's outline", outline, want, &mut out);

    for (name, offset) in uses_in_g() {
        let shape = shape_of(name);
        let hover = request(&mut server, "textDocument/hover", at(offset));
        let text = hover["result"]["contents"]["value"].as_str().unwrap_or("");
        check(
            &format!("hover on `{name}` in g names its definition"),
            text.contains(shape.signature),
            true,
            &mut out,
        );
        let to = request(&mut server, "textDocument/definition", at(offset));
        let named = SOURCE
            .find(&format!("{} {}", shape.kind, shape.name))
            .map(|k| k + shape.kind.len() + 1)
            .or_else(|| SOURCE.find(&format!("| {}(", shape.name)).map(|k| k + 2))
            .or_else(|| SOURCE.find(&format!("= {}(", shape.name)).map(|k| k + 2))
            .expect("the source names it");
        let start = &to["result"][0]["range"]["start"];
        check(
            &format!("definition of `{name}` in g"),
            (start["line"].as_u64(), start["character"].as_u64()),
            {
                let (line, character) = line_col(named);
                (Some(line as u64), Some(character as u64))
            },
            &mut out,
        );
    }

    let record = SOURCE.find("record point").expect("record") + "record ".len();
    let hover = request(&mut server, "textDocument/hover", at(record));
    let text = hover["result"]["contents"]["value"].as_str().unwrap_or("");
    check(
        "hover on a documented record shows its doc",
        text.contains("A point on the plane."),
        true,
        &mut out,
    );

    assert!(out.is_empty(), "faces disagree:\n  {}", out.join("\n  "));
}
