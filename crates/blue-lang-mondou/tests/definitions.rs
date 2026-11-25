use std::path::{Path, PathBuf};

use blue_lang_mondou::{CompletionKind, Engine, Query, Tier};
use blue_lang_runtime::uses::Loader;

const KATACHI: &str = "@doc \"\"\"\nA point.\n\"\"\"\nrecord point(x, y)\n\nunion shape = circle(r) | square(s)\n\ntwice = (n) -> n * 2\n\nlimit = 3\n";

struct Mem;

impl Loader for Mem {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        match name {
            "katachi" => Ok(vec![(
                "/b/katachi/katachi.b".to_string(),
                KATACHI.to_string(),
            )]),
            _ => Err(format!("no bidama {name}")),
        }
    }

    fn entry_package(&self, path: &Path) -> Option<String> {
        path.starts_with("/b/katachi")
            .then(|| "katachi".to_string())
    }

    fn available(&self) -> Vec<String> {
        vec!["katachi".to_string()]
    }
}

fn engine(text: &str) -> Engine {
    let mut engine = Engine::new(Box::new(Mem));
    engine.set_document("e", Some(PathBuf::from("/b/katachi/katachi.b")), text);
    engine
}

fn names(engine: &Engine, query: &str) -> Vec<String> {
    let q = Query::parse(query).expect(query);
    engine
        .query("e", &q)
        .expect(query)
        .into_iter()
        .map(|h| h.definition)
        .collect()
}

#[test]
fn blue_query_reads_a_union_written_whole_as_its_lowered_forms() {
    let engine = engine(KATACHI);
    assert_eq!(
        names(&engine, "(kind record)"),
        ["point", "circle", "square"]
    );
    assert_eq!(names(&engine, "(kind union)"), ["shape"]);
    assert_eq!(names(&engine, "(kind function)"), ["twice"]);
    assert_eq!(names(&engine, "(kind value)"), ["limit"]);
    assert_eq!(
        names(&engine, "(match `(blue-record ,@_))"),
        ["point", "circle", "square"]
    );
    let q = Query::parse("(kind union)").expect("parses");
    let union = &engine.query("e", &q).expect("runs")[0];
    assert_eq!(union.key, "katachi/shape?");
    assert_eq!(union.json("katachi.b")["kind"], serde_json::json!("union"));
    assert_eq!(
        Query::parse("(kind thing)")
            .map(|_| ())
            .map_err(|e| e.to_string()),
        Err("`(kind thing)`: is function, macro, value, record, union".to_string())
    );
}

#[test]
fn completion_offers_what_a_record_and_a_union_bind() {
    let own = format!("{KATACHI}\ndef g(v)\n  sh\nend\n");
    let mut engine = engine(&own);
    let at = own.rfind("sh\n").expect("typed") + 2;
    let got: Vec<(String, CompletionKind)> = engine
        .completions("e", at)
        .into_iter()
        .filter(|c| c.tier == Tier::Own)
        .map(|c| (c.label, c.kind))
        .collect();
    assert_eq!(got, [("shape?".to_string(), CompletionKind::Function)]);

    let other = "def h(v)\n  poi\nend\n";
    engine.set_document("u", Some(PathBuf::from("/w/u.b")), other);
    let at = other.find("poi").expect("typed") + 3;
    let got: Vec<(String, CompletionKind, Option<String>)> = engine
        .completions("u", at)
        .into_iter()
        .filter(|c| c.tier == Tier::Reachable)
        .map(|c| (c.label, c.kind, c.signature))
        .collect();
    let record = Some("record point(x, y)".to_string());
    assert_eq!(
        got,
        [
            (
                "point".to_string(),
                CompletionKind::Function,
                record.clone()
            ),
            ("point?".to_string(), CompletionKind::Function, record),
        ]
    );
}
