use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};

use blue_lang_host::{Canonical, Entry, MapKey, Program, Value};
use blue_lang_pkg::load_path::LoadPath;
use yaml_rust2::parser::{Event, MarkedEventReceiver, Parser, Tag};
use yaml_rust2::scanner::{Marker, TScalarStyle};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn fixtures() -> PathBuf {
    root().join("bidamas/deeta/fixtures")
}

#[derive(Debug, Clone)]
enum Node {
    Null,
    Bool(bool),
    Int(i64),
    Float(f64),
    Str(String),
    Seq(Vec<Node>),
    Map(BTreeMap<String, Node>),
}

impl PartialEq for Node {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Node::Null, Node::Null) => true,
            (Node::Bool(a), Node::Bool(b)) => a == b,
            (Node::Int(a), Node::Int(b)) => a == b,
            (Node::Float(a), Node::Float(b)) => a == b || (a.is_nan() && b.is_nan()),
            (Node::Str(a), Node::Str(b)) => a == b,
            (Node::Seq(a), Node::Seq(b)) => a == b,
            (Node::Map(a), Node::Map(b)) => a == b,
            _ => false,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
enum Outcome {
    Documents(Vec<Node>),
    Refused(String, String),
}

const CORE: &str = "tag:yaml.org,2002:";

fn digits(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
}

fn unsigned(s: &str) -> &str {
    s.strip_prefix(['-', '+']).unwrap_or(s)
}

fn core_int(t: &str) -> Option<i64> {
    if let Some(rest) = t.strip_prefix("0o") {
        if digits(rest) && rest.len() <= 20 {
            return i64::from_str_radix(rest, 8).ok();
        }
        return None;
    }
    if let Some(rest) = t.strip_prefix("0x") {
        if !rest.is_empty() && rest.len() <= 15 {
            return i64::from_str_radix(rest, 16).ok();
        }
        return None;
    }
    if digits(unsigned(t)) {
        return t.parse::<i64>().ok();
    }
    None
}

fn mantissa(m: &str) -> bool {
    match m.split_once('.') {
        None => digits(m),
        Some((a, b)) if !b.contains('.') => {
            (a.is_empty() && digits(b)) || (digits(a) && (b.is_empty() || digits(b)))
        }
        Some(_) => false,
    }
}

fn core_float(t: &str) -> Option<f64> {
    match t {
        ".inf" | ".Inf" | ".INF" | "+.inf" | "+.Inf" | "+.INF" => return Some(f64::INFINITY),
        "-.inf" | "-.Inf" | "-.INF" => return Some(f64::NEG_INFINITY),
        ".nan" | ".NaN" | ".NAN" => return Some(f64::NAN),
        _ => {}
    }
    let body = unsigned(t).replace('E', "e");
    let ok = match body.split_once('e') {
        None => mantissa(&body),
        Some((m, e)) => mantissa(m) && digits(unsigned(e)),
    };
    if ok {
        t.parse::<f64>().ok()
    } else {
        None
    }
}

fn core_value(t: &str) -> Node {
    match t {
        "" | "~" | "null" | "Null" | "NULL" => Node::Null,
        "true" | "True" | "TRUE" => Node::Bool(true),
        "false" | "False" | "FALSE" => Node::Bool(false),
        _ => match (core_int(t), core_float(t)) {
            (Some(i), _) => Node::Int(i),
            (None, Some(f)) => Node::Float(f),
            _ => Node::Str(t.to_owned()),
        },
    }
}

fn tagged(t: &str, tag: &str) -> Result<Node, String> {
    let bad = || Err(format!("{t:?} is not a {tag}"));
    match tag.strip_prefix(CORE) {
        Some("str") => Ok(Node::Str(t.to_owned())),
        Some("null") => match t {
            "" | "~" | "null" | "Null" | "NULL" => Ok(Node::Null),
            _ => bad(),
        },
        Some("bool") => match t {
            "true" | "True" | "TRUE" => Ok(Node::Bool(true)),
            "false" | "False" | "FALSE" => Ok(Node::Bool(false)),
            _ => bad(),
        },
        Some("int") => core_int(t).map(Node::Int).map_or_else(bad, Ok),
        Some("float") => core_int(t)
            .map(|i| i as f64)
            .or_else(|| core_float(t))
            .map(Node::Float)
            .map_or_else(bad, Ok),
        _ => Ok(Node::Str(t.to_owned())),
    }
}

fn float_text(f: f64) -> String {
    if f.is_nan() {
        return "NaN".to_owned();
    }
    if f == 0.0 {
        return "0.0".to_owned();
    }
    let s = format!("{f}");
    if f.is_finite() && f.fract() == 0.0 && f.abs() < 1e16 && !s.contains('e') {
        format!("{s}.0")
    } else {
        s
    }
}

fn key_text(n: &Node) -> Result<String, String> {
    match n {
        Node::Str(s) => Ok(s.clone()),
        Node::Null => Ok("null".to_owned()),
        Node::Bool(b) => Ok(b.to_string()),
        Node::Int(i) => Ok(i.to_string()),
        Node::Float(f) => Ok(float_text(*f)),
        _ => Err("a mapping key is a collection".to_owned()),
    }
}

enum Frame {
    Seq(Vec<Node>, usize),
    Map(BTreeMap<String, Node>, Option<Node>, usize),
}

#[derive(Default)]
struct Reference {
    docs: Vec<Node>,
    stack: Vec<Frame>,
    root: Option<Node>,
    anchors: HashMap<usize, Node>,
    refused: Option<(String, String)>,
}

impl Reference {
    fn refuse(&mut self, kind: &str, message: String) {
        if self.refused.is_none() {
            self.refused = Some((kind.to_owned(), message));
        }
    }

    fn insert(&mut self, node: Node, anchor: usize) {
        if anchor > 0 {
            self.anchors.insert(anchor, node.clone());
        }
        match self.stack.last_mut() {
            None => self.root = Some(node),
            Some(Frame::Seq(items, _)) => items.push(node),
            Some(Frame::Map(entries, pending, _)) => match pending.take() {
                None => *pending = Some(node),
                Some(key) => match key_text(&key) {
                    Err(e) => self.refuse("complex_key", e),
                    Ok(k) => {
                        if entries.insert(k.clone(), node).is_some() {
                            self.refuse("duplicate_key", format!("{k:?} appears twice"));
                        }
                    }
                },
            },
        }
    }
}

fn tag_text(tag: &Option<Tag>) -> Option<String> {
    tag.as_ref().map(|t| format!("{}{}", t.handle, t.suffix))
}

impl MarkedEventReceiver for Reference {
    fn on_event(&mut self, ev: Event, _mark: Marker) {
        if self.refused.is_some() {
            return;
        }
        match ev {
            Event::DocumentStart => self.root = None,
            Event::DocumentEnd => {
                let root = self.root.take().unwrap_or(Node::Null);
                self.docs.push(root);
            }
            Event::SequenceStart(anchor, _) => self.stack.push(Frame::Seq(Vec::new(), anchor)),
            Event::MappingStart(anchor, _) => {
                self.stack.push(Frame::Map(BTreeMap::new(), None, anchor))
            }
            Event::SequenceEnd | Event::MappingEnd => match self.stack.pop() {
                Some(Frame::Seq(items, anchor)) => self.insert(Node::Seq(items), anchor),
                Some(Frame::Map(entries, _, anchor)) => self.insert(Node::Map(entries), anchor),
                None => self.refuse("parse", "unbalanced collection events".to_owned()),
            },
            Event::Scalar(text, style, anchor, tag) => {
                let resolved = match tag_text(&tag) {
                    None if style == TScalarStyle::Plain => Ok(core_value(&text)),
                    None => Ok(Node::Str(text)),
                    Some(t) if t == "!" => Ok(Node::Str(text)),
                    Some(t) => tagged(&text, &t),
                };
                match resolved {
                    Ok(node) => self.insert(node, anchor),
                    Err(e) => self.refuse("bad_value", e),
                }
            }
            Event::Alias(id) => match self.anchors.get(&id).cloned() {
                Some(node) => self.insert(node, 0),
                None => self.refuse("parse", format!("alias {id} names no anchor")),
            },
            Event::Nothing | Event::StreamStart | Event::StreamEnd => {}
        }
    }
}

fn reference(text: &str) -> Outcome {
    let mut parser = Parser::new_from_str(text);
    let mut r = Reference::default();
    let loaded = parser.load(&mut r, true);
    match (loaded, r.refused) {
        (Err(e), _) => Outcome::Refused("parse".to_owned(), e.to_string()),
        (Ok(()), Some((kind, message))) => Outcome::Refused(kind, message),
        (Ok(()), None) => Outcome::Documents(r.docs),
    }
}

fn from_blue(v: &Value) -> Node {
    match v {
        Value::Nil => Node::Null,
        Value::Bool(b) => Node::Bool(*b),
        Value::Int(i) => Node::Int(*i),
        Value::Float(f) => Node::Float(*f),
        Value::Str(s) => Node::Str(s.to_string()),
        Value::List(xs) => Node::Seq(xs.iter().map(from_blue).collect()),
        Value::Map(m) => Node::Map(
            m.iter()
                .map(|(k, v)| match k {
                    MapKey::Str(s) => (s.to_string(), from_blue(v)),
                    other => panic!("blue gave a map key that is not text: {other:?}"),
                })
                .collect(),
        ),
        other => panic!("blue gave a value YAML does not make: {other:?}"),
    }
}

struct Blue {
    program: Program<()>,
}

impl Blue {
    fn load() -> Self {
        let text = std::fs::read_to_string(root().join("crates/blue-lang-yaml-diff/tests/agree.b"))
            .unwrap();
        let loader = LoadPath::new([root().join("bidamas")]);
        let program = Program::<()>::builder(Entry::anonymous(Box::leak(text.into_boxed_str())))
            .loader(Box::leak(Box::new(loader)))
            .canonical(Canonical::Required)
            .load(&mut ())
            .expect("agree.b loads with deeta");
        Self { program }
    }

    fn outcome(&mut self, text: &str) -> Outcome {
        let v = self
            .program
            .call::<Value>("outcome", (text.to_owned(),), &mut ())
            .expect("outcome answers");
        let Value::List(parts) = v else {
            panic!("outcome gave {v:?}")
        };
        let part = |i: usize| parts.get(i).cloned().unwrap_or(Value::Nil);
        match part(0) {
            Value::Str(s) if &*s == "ok" => match from_blue(&part(1)) {
                Node::Seq(docs) => Outcome::Documents(docs),
                other => panic!("blue's documents are not a list: {other:?}"),
            },
            _ => {
                let text = |v: Value| match v {
                    Value::Str(s) => s.to_string(),
                    other => format!("{other:?}"),
                };
                Outcome::Refused(text(part(1)), text(part(2)))
            }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Verdict {
    Agree,
    Divergent,
}

fn verdict(theirs: &Outcome, ours: &Outcome) -> Verdict {
    match (theirs, ours) {
        (Outcome::Documents(a), Outcome::Documents(b)) if a == b => Verdict::Agree,
        (Outcome::Refused(k, _), Outcome::Refused(_, _)) if k == "parse" => Verdict::Agree,
        (Outcome::Refused(k, _), Outcome::Refused(j, _)) if k == j => Verdict::Agree,
        _ => Verdict::Divergent,
    }
}

fn files_under(dir: &Path, name: &dyn Fn(&Path) -> bool, out: &mut Vec<PathBuf>) {
    let mut entries: Vec<PathBuf> = std::fs::read_dir(dir)
        .unwrap_or_else(|e| panic!("{}: {e}", dir.display()))
        .map(|e| e.unwrap().path())
        .collect();
    entries.sort();
    for p in entries {
        if p.is_dir() {
            files_under(&p, name, out);
        } else if name(&p) {
            out.push(p);
        }
    }
}

fn corpus() -> Vec<PathBuf> {
    let mut files = Vec::new();
    files_under(
        &fixtures().join("yaml-test-suite"),
        &|p| p.file_name().is_some_and(|n| n == "in.yaml"),
        &mut files,
    );
    files_under(
        &fixtures().join("fleet"),
        &|p| p.extension().is_some_and(|x| x == "yaml" || x == "yml"),
        &mut files,
    );
    if let Ok(extra) = std::env::var("BLUE_YAML_DIFF_EXTRA") {
        files.extend(
            extra
                .split(':')
                .filter(|s| !s.is_empty())
                .map(PathBuf::from),
        );
    }
    files
}

fn case_name(path: &Path) -> String {
    let rel = path.strip_prefix(fixtures()).unwrap_or(path);
    rel.display()
        .to_string()
        .trim_end_matches("/in.yaml")
        .to_owned()
}

fn refusals() -> BTreeMap<&'static str, &'static str> {
    BTreeMap::from([])
}

#[test]
fn blue_and_yaml_rust2_agree_on_every_document() {
    let mut blue = Blue::load();
    let known = refusals();
    let mut agreed = 0;
    let mut both_refuse = 0;
    let mut waived = Vec::new();
    let mut faults = Vec::new();
    let mut stale = Vec::new();
    let files = corpus();
    for path in &files {
        let text = std::fs::read_to_string(path).unwrap();
        let name = case_name(path);
        let theirs = reference(&text);
        let ours = blue.outcome(&text);
        match (verdict(&theirs, &ours), known.get(name.as_str())) {
            (Verdict::Agree, None) => {
                agreed += 1;
                if matches!(ours, Outcome::Refused(..)) {
                    both_refuse += 1;
                }
            }
            (Verdict::Agree, Some(_)) => stale.push(name),
            (Verdict::Divergent, Some(why)) => waived.push(format!("{name}: {why}")),
            (Verdict::Divergent, None) => faults.push(format!(
                "{name}\n--- yaml-rust2\n{theirs:?}\n--- blue\n{ours:?}\n--- input\n{text}"
            )),
        }
    }
    eprintln!(
        "yaml agreement: {} documents, {} agree ({} read alike, {} refused by both), {} typed refusals",
        files.len(),
        agreed,
        agreed - both_refuse,
        both_refuse,
        waived.len()
    );
    for w in &waived {
        eprintln!("  refused: {w}");
    }
    assert!(
        files.len() >= 500,
        "the corpus shrank to {} files",
        files.len()
    );
    assert!(
        stale.is_empty(),
        "these refusals now agree; remove them: {stale:?}"
    );
    assert!(
        faults.is_empty(),
        "{} fault(s):\n{}",
        faults.len(),
        faults.join("\n\n")
    );
}

fn from_json(v: &serde_json::Value) -> Node {
    match v {
        serde_json::Value::Null => Node::Null,
        serde_json::Value::Bool(b) => Node::Bool(*b),
        serde_json::Value::Number(n) => match n.as_i64() {
            Some(i) => Node::Int(i),
            None => Node::Float(n.as_f64().unwrap_or(f64::NAN)),
        },
        serde_json::Value::String(s) => Node::Str(s.clone()),
        serde_json::Value::Array(xs) => Node::Seq(xs.iter().map(from_json).collect()),
        serde_json::Value::Object(m) => {
            Node::Map(m.iter().map(|(k, v)| (k.clone(), from_json(v))).collect())
        }
    }
}

fn same_data(a: &Node, b: &Node) -> bool {
    match (a, b) {
        (Node::Int(x), Node::Float(y)) | (Node::Float(y), Node::Int(x)) => (*x as f64) == *y,
        (Node::Seq(xs), Node::Seq(ys)) => {
            xs.len() == ys.len() && xs.iter().zip(ys).all(|(x, y)| same_data(x, y))
        }
        (Node::Map(xs), Node::Map(ys)) => {
            xs.len() == ys.len()
                && xs
                    .iter()
                    .zip(ys)
                    .all(|((k, x), (j, y))| k == j && same_data(x, y))
        }
        _ => a == b,
    }
}

fn suite_json(dir: &Path) -> Option<Vec<Node>> {
    let text = std::fs::read_to_string(dir.join("in.json")).ok()?;
    let docs: Result<Vec<serde_json::Value>, _> = serde_json::Deserializer::from_str(&text)
        .into_iter()
        .collect();
    Some(docs.ok()?.iter().map(from_json).collect())
}

const COMPLEX_KEY: &str =
    "a collection as a mapping key: blue keys a map by text, so deeta refuses it as :complex_key";

fn suite_gaps() -> BTreeMap<&'static str, &'static str> {
    BTreeMap::from([
        (
            "yaml-test-suite/2JQS",
            "two empty keys are one key twice: deeta refuses it as :duplicate_key",
        ),
        ("yaml-test-suite/4FJ6", COMPLEX_KEY),
        ("yaml-test-suite/6BFJ", COMPLEX_KEY),
        ("yaml-test-suite/6PBE", COMPLEX_KEY),
        ("yaml-test-suite/9MMW", COMPLEX_KEY),
        ("yaml-test-suite/KK5P", COMPLEX_KEY),
        ("yaml-test-suite/LX3P", COMPLEX_KEY),
        ("yaml-test-suite/M2N8/00", COMPLEX_KEY),
        ("yaml-test-suite/M2N8/01", COMPLEX_KEY),
        ("yaml-test-suite/M5DY", COMPLEX_KEY),
        ("yaml-test-suite/Q9WF", COMPLEX_KEY),
        ("yaml-test-suite/RZP5", COMPLEX_KEY),
        ("yaml-test-suite/SBG9", COMPLEX_KEY),
        ("yaml-test-suite/V9D5", COMPLEX_KEY),
        ("yaml-test-suite/X38W", COMPLEX_KEY),
        ("yaml-test-suite/XW4D", COMPLEX_KEY),
    ])
}

#[test]
fn blue_meets_the_suites_own_verdicts() {
    let mut blue = Blue::load();
    let gaps = suite_gaps();
    let mut cases = 0;
    let mut met = 0;
    let mut faults = Vec::new();
    let mut stale = Vec::new();
    let mut files = Vec::new();
    files_under(
        &fixtures().join("yaml-test-suite"),
        &|p| p.file_name().is_some_and(|n| n == "in.yaml"),
        &mut files,
    );
    for path in &files {
        let dir = path.parent().unwrap();
        let name = case_name(path);
        let text = std::fs::read_to_string(path).unwrap();
        let ours = blue.outcome(&text);
        let refused = matches!(ours, Outcome::Refused(..));
        let fault = if dir.join("error").exists() {
            (!refused).then(|| "the suite refuses it and blue reads it".to_owned())
        } else {
            match (&ours, suite_json(dir)) {
                (Outcome::Refused(k, m), _) => {
                    Some(format!("blue refuses a valid stream: {k}: {m}"))
                }
                (Outcome::Documents(docs), Some(json)) => (docs.len() != json.len()
                    || !docs.iter().zip(&json).all(|(a, b)| same_data(a, b)))
                .then(|| format!("blue reads {docs:?}, the suite's JSON is {json:?}")),
                (Outcome::Documents(_), None) => None,
            }
        };
        cases += 1;
        match (fault, gaps.get(name.as_str())) {
            (None, None) => met += 1,
            (None, Some(_)) => stale.push(name),
            (Some(_), Some(_)) => {}
            (Some(f), None) => faults.push(format!("{name}: {f}")),
        }
    }
    eprintln!(
        "yaml-test-suite: {cases} cases, blue meets {met}, {} named gaps",
        gaps.len()
    );
    assert!(
        stale.is_empty(),
        "these gaps are closed; remove them: {stale:?}"
    );
    assert!(
        faults.is_empty(),
        "{} fault(s):\n{}",
        faults.len(),
        faults.join("\n")
    );
}
