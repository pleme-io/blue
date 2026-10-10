//! The language server over the engine, request by request, through the
//! server's in-process transport (`Server::handle_value`) against the real
//! distribution in `bidamas/`.
//!
//! Each test names the red run that showed it fails without the code it
//! guards.

use std::path::PathBuf;

use blue_lang_lsp::{Response, Server};
use blue_lang_pkg::load_path::LoadPath;
use serde_json::{json, Value};

fn bidamas() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bidamas")
        .canonicalize()
        .expect("bidamas/")
}

fn server() -> Server {
    Server::with_loader(Box::new(LoadPath::new([bidamas()])))
}

fn uri_of(path: &std::path::Path) -> String {
    format!("file://{}", path.display())
}

fn junjo() -> (String, String) {
    let path = bidamas().join("junjo/junjo.b");
    let text = std::fs::read_to_string(&path).expect("junjo.b");
    (uri_of(&path), text)
}

fn open(s: &mut Server, uri: &str, text: &str) {
    s.handle_value(&json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": { "textDocument": { "uri": uri, "text": text } },
    }));
}

fn change(s: &mut Server, uri: &str, text: &str) -> Response {
    s.handle_value(&json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didChange",
        "params": { "textDocument": { "uri": uri }, "contentChanges": [{ "text": text }] },
    }))
}

fn request(s: &mut Server, method: &str, params: Value) -> Value {
    match s.handle_value(&json!({ "jsonrpc": "2.0", "id": 1, "method": method, "params": params }))
    {
        Response::Reply(r) => r,
        other => panic!("{method}: expected a reply, got {other:?}"),
    }
}

/// The line and character of byte `offset` in an ASCII text.
fn position(text: &str, offset: usize) -> Value {
    let line = text[..offset].matches('\n').count();
    let start = text[..offset].rfind('\n').map_or(0, |n| n + 1);
    json!({ "line": line, "character": offset - start })
}

fn at(uri: &str, text: &str, offset: usize) -> Value {
    json!({ "textDocument": { "uri": uri }, "position": position(text, offset) })
}

fn diagnostics(r: &Response) -> Vec<Value> {
    let Response::Messages(all) = r else {
        panic!("expected pushes, got {r:?}");
    };
    all.iter()
        .find(|m| m["method"] == json!("textDocument/publishDiagnostics"))
        .and_then(|m| m["params"]["diagnostics"].as_array().cloned())
        .expect("a diagnostics push")
}

fn completion_items(r: &Value) -> Vec<Value> {
    r["result"]["items"]
        .as_array()
        .cloned()
        .expect("completion items")
}

fn find<'a>(items: &'a [Value], label: &str) -> Option<&'a Value> {
    items.iter().find(|i| i["label"] == json!(label))
}

/// **E1 (b): in a real bidama, completion at a call to retsu's `first`
/// inside junjo offers `first` from retsu at the imports tier**, ahead of the
/// builtin it overrides there.
///
/// Red run (2026-10-10): the same session against the pre-engine server —
/// `first` is offered with no tier at all, `left: Null right:
/// String("imported")`.
#[test]
fn completion_inside_junjo_offers_retsus_first_at_the_imports_tier() {
    let mut s = server();
    let (uri, text) = junjo();
    open(&mut s, &uri, &text);
    let call = text.find("first(xs)").expect("junjo calls first") + 3;
    let r = request(&mut s, "textDocument/completion", at(&uri, &text, call));
    let items = completion_items(&r);
    let first = find(&items, "first").expect("first is offered");
    assert_eq!(first["detail"], json!("bidama `retsu`"));
    assert_eq!(first["labelDetails"]["description"], json!("imported"));
    let builtins: Vec<&Value> = items
        .iter()
        .filter(|i| i["labelDetails"]["description"] == json!("builtin"))
        .collect();
    for b in builtins {
        assert!(
            b["sortText"].as_str() > first["sortText"].as_str(),
            "a builtin ranks above the imported first: {b}"
        );
    }
}

/// Counts every load the server asks of the real loader: evidence read off
/// the loader, not off the engine's own bookkeeping.
struct Counting {
    inner: LoadPath,
    loads: std::rc::Rc<std::cell::RefCell<std::collections::BTreeMap<String, usize>>>,
}

impl blue_lang_runtime::uses::Loader for Counting {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        *self.loads.borrow_mut().entry(name.to_string()).or_default() += 1;
        self.inner.load(name)
    }
    fn entry_package(&self, path: &std::path::Path) -> Option<String> {
        self.inner.entry_package(path)
    }
    fn needs(
        &self,
        package: &str,
        entry_dir: Option<&std::path::Path>,
    ) -> Option<std::collections::BTreeSet<String>> {
        self.inner.needs(package, entry_dir)
    }
    fn version(&self, package: &str, entry_dir: Option<&std::path::Path>) -> Option<String> {
        self.inner.version(package, entry_dir)
    }
    fn available(&self) -> Vec<String> {
        self.inner.available()
    }
}

/// **E1 (c): each bidama is loaded once per session**: two completion
/// requests with an edit between them load retsu, kazu and ronri once each,
/// and so every other bidama the second request offers behind a `use`.
///
/// Red runs (2026-10-10): the same session against the pre-engine server —
/// `retsu loaded Some(4) times: {"kansuu": 4, "kazu": 4, "retsu": 4,
/// "ronri": 4}`, a load per analysis; and the engine's package memo
/// bypassed — `left: Some(4) right: Some(1)`.
#[test]
fn each_bidama_loads_once_per_session() {
    let loads = std::rc::Rc::default();
    let mut s = Server::with_loader(Box::new(Counting {
        inner: LoadPath::new([bidamas()]),
        loads: std::rc::Rc::clone(&loads),
    }));
    let (uri, text) = junjo();
    open(&mut s, &uri, &text);
    let call = text.find("first(xs)").expect("first") + 3;
    request(&mut s, "textDocument/completion", at(&uri, &text, call));
    let edited = format!("{text}\n# an edit\n");
    change(&mut s, &uri, &edited);
    request(&mut s, "textDocument/completion", at(&uri, &edited, call));
    let loads = loads.borrow();
    for pkg in ["retsu", "kazu", "ronri"] {
        assert_eq!(
            loads.get(pkg),
            Some(&1),
            "{pkg} loaded {:?} times: {loads:?}",
            loads.get(pkg)
        );
    }
    assert!(
        loads.len() > 10,
        "the reachable tier loads the distribution: {loads:?}"
    );
    assert!(loads.values().all(|n| *n == 1), "{loads:?}");
}

/// **E2: one parse per revision.** A `didChange` and a hover against it
/// parse the new text once — counted by the parser itself, not by the
/// engine — and the bidamas it imports not at all.
///
/// Red runs (2026-10-10): the same session against the pre-engine server
/// (`analyse_with`, `shift_of` and `hover` each parsing for themselves, and
/// every check re-parsing every import) — `left: 28 right: 1`, and `left: 8
/// right: 1` for a file with no imports; and the engine's parse memo missing
/// on every lookup — `left: 7 right: 1`.
#[test]
fn one_parse_per_revision() {
    let mut s = server();
    let (uri, text) = junjo();
    open(&mut s, &uri, &text);
    let edited = format!("{text}\n# an edit\n");
    let before = blue_lang_syntax::parses_on_this_thread();
    change(&mut s, &uri, &edited);
    let call = edited.find("first(xs)").expect("first") + 1;
    let r = request(&mut s, "textDocument/hover", at(&uri, &edited, call));
    assert!(r["result"]["contents"]["value"].is_string(), "{r}");
    assert_eq!(blue_lang_syntax::parses_on_this_thread() - before, 1);

    let plain = "def add(a, b)\n  a + b\nend\nadd(1, 2)\n";
    open(&mut s, "file:///plain.b", plain);
    let before = blue_lang_syntax::parses_on_this_thread();
    change(&mut s, "file:///plain.b", &format!("{plain}\n"));
    request(
        &mut s,
        "textDocument/hover",
        at("file:///plain.b", plain, 5),
    );
    assert_eq!(blue_lang_syntax::parses_on_this_thread() - before, 1);
}

const TIERS: &str =
    "use(\"retsu\", [:size])\n\ndef sizable(xs)\n  xs\nend\n\ndef f(sizes)\n  si\nend\n";

/// **Completion is ranked by the resolution tiers**: the local, then the
/// file's own definition, then the listed import, then builtins, then names
/// one `use` away.
///
/// Red run (2026-10-10): the tier dropped from the ranking (`finish` sorting
/// by label, `sortText` the rank alone) — `tiers out of order: ["needs a
/// use", …, "builtin", "own", "imported", …, "local"]`.
#[test]
fn completion_ranks_by_the_resolution_tiers() {
    let mut s = server();
    let uri = "file:///tiers.b";
    open(&mut s, uri, TIERS);
    let offset = TIERS.find("  si\n").expect("si") + 4;
    let r = request(&mut s, "textDocument/completion", at(uri, TIERS, offset));
    let items = completion_items(&r);
    let mut ranked = items.clone();
    ranked.sort_by(|a, b| a["sortText"].as_str().cmp(&b["sortText"].as_str()));
    let tiers: Vec<&str> = ranked
        .iter()
        .map(|i| i["labelDetails"]["description"].as_str().unwrap_or(""))
        .collect();
    let order = ["local", "own", "imported", "builtin", "needs a use"];
    let rank = |t: &str| order.iter().position(|o| *o == t).expect("a known tier");
    assert!(
        tiers.windows(2).all(|w| rank(w[0]) <= rank(w[1])),
        "tiers out of order: {tiers:?}"
    );
    let labels: Vec<&str> = ranked
        .iter()
        .map(|i| i["label"].as_str().unwrap_or(""))
        .collect();
    assert_eq!(&labels[..3], &["sizes", "sizable", "size"], "{labels:?}");
    assert_eq!(tiers[..3], ["local", "own", "imported"]);
}

/// **A name one `use` away carries the edit that reaches it**, and applying
/// the completion leaves a file with no diagnostics: the edit is the one that
/// makes the name resolve, not a guess at it.
///
/// Red run (2026-10-10): a name with no `use` offered with no edit —
/// `left: Null right: String("use(\"kazu\", [:clamp])\n")`. The first
/// version of `list_edit` appended to the list and this test's second half
/// caught it: the result was B0015, `use("retsu")`'s list unsorted.
#[test]
fn a_name_one_use_away_carries_its_use() {
    let mut s = server();
    let uri = "file:///reach.b";
    let text = "use(\"retsu\", [:size])\n\ndef f(xs)\n  size(xs) + clam\nend\n";
    open(&mut s, uri, text);
    let offset = text.find("clam\n").expect("clam") + 4;
    let r = request(&mut s, "textDocument/completion", at(uri, text, offset));
    let items = completion_items(&r);
    let clamp = find(&items, "clamp").expect("kazu's clamp is offered");
    assert_eq!(clamp["detail"], json!("bidama `kazu`"));
    assert_eq!(clamp["labelDetails"]["description"], json!("needs a use"));
    let edit = clamp["additionalTextEdits"][0].clone();
    assert_eq!(
        edit["newText"],
        json!("use(\"kazu\", [:clamp])\n"),
        "clamp offered with no additionalTextEdits: {clamp}"
    );
    assert_eq!(edit["range"]["start"], json!({ "line": 0, "character": 0 }));

    let fixed = format!(
        "use(\"kazu\", [:clamp])\n{}",
        text.replace("clam\n", "clamp(1, 0, 2)\n")
    );
    let d = diagnostics(&change(&mut s, uri, &fixed));
    assert!(d.is_empty(), "the completion's file does not check: {d:?}");

    let listed = "use(\"retsu\", [:size])\n\ndef f(xs)\n  size(xs) + fir\nend\n";
    change(&mut s, uri, listed);
    let offset = listed.find("fir\n").expect("fir") + 3;
    let r = request(&mut s, "textDocument/completion", at(uri, listed, offset));
    let items = completion_items(&r);
    let first = items
        .iter()
        .find(|i| i["label"] == json!("first") && i["detail"] == json!("bidama `retsu`"))
        .expect("retsu's first, one list entry away");
    assert_eq!(
        first["additionalTextEdits"][0]["newText"],
        json!(":first, ")
    );
    assert_eq!(
        first["additionalTextEdits"][0]["range"]["start"],
        json!({ "line": 0, "character": 14 })
    );
    let fixed = "use(\"retsu\", [:first, :size])\n\ndef f(xs)\n  size(xs) + first(xs)\nend\n";
    let d = diagnostics(&change(&mut s, uri, fixed));
    assert!(d.is_empty(), "{d:?}");
}

/// **Go to definition reaches into a bidama**, and to a local's binding and
/// an own definition in the file.
///
/// Red run (2026-10-10): the `textDocument/definition` arm removed —
/// `{"error":{"code":-32601,"message":"method not found"},…}`.
#[test]
fn definition_reaches_into_a_bidama_and_to_locals() {
    let mut s = server();
    let (uri, text) = junjo();
    open(&mut s, &uri, &text);
    let call = text.find("first(xs)").expect("first") + 1;
    let r = request(&mut s, "textDocument/definition", at(&uri, &text, call));
    assert!(r["error"].is_null(), "{r}");
    let to = &r["result"][0];
    let retsu = bidamas().join("retsu/retsu.b");
    assert_eq!(to["uri"], json!(uri_of(&retsu)));
    let source = std::fs::read_to_string(&retsu).expect("retsu.b");
    let def = source.find("def first(").expect("retsu defines first") + 4;
    assert_eq!(to["range"]["start"], position(&source, def));

    let local = "def f(a, b)\n  a + b\nend\n\nf(1, 2)\n";
    open(&mut s, "file:///local.b", local);
    let use_of_b = local.find("+ b").expect("b") + 2;
    let r = request(
        &mut s,
        "textDocument/definition",
        at("file:///local.b", local, use_of_b),
    );
    assert_eq!(r["result"][0]["uri"], json!("file:///local.b"));
    assert_eq!(
        r["result"][0]["range"]["start"],
        json!({ "line": 0, "character": 9 })
    );
    let call_of_f = local.rfind("f(1").expect("call");
    let r = request(
        &mut s,
        "textDocument/definition",
        at("file:///local.b", local, call_of_f),
    );
    assert_eq!(
        r["result"][0]["range"]["start"],
        json!({ "line": 0, "character": 4 })
    );
}

const HELPER: &str = "def helper(n)\n  n + 1\nend\n\ndef g(x)\n  helper(x) + helper(1)\nend\n";

/// **References**: every use of a definition, with and without its
/// declaration, and every read of a local.
///
/// Red run (2026-10-10): the `textDocument/references` arm removed —
/// `{"error":{"code":-32601,"message":"method not found"},…}`.
#[test]
fn references_find_every_use() {
    let mut s = server();
    let uri = "file:///helper.b";
    open(&mut s, uri, HELPER);
    let call = HELPER.find("helper(x)").expect("call");
    let mut params = at(uri, HELPER, call);
    params["context"] = json!({ "includeDeclaration": true });
    let r = request(&mut s, "textDocument/references", params.clone());
    assert!(r["error"].is_null(), "{r}");
    let lines: Vec<(u64, u64)> = r["result"]
        .as_array()
        .expect("locations")
        .iter()
        .map(|l| {
            (
                l["range"]["start"]["line"].as_u64().unwrap_or(99),
                l["range"]["start"]["character"].as_u64().unwrap_or(99),
            )
        })
        .collect();
    assert_eq!(lines, vec![(0, 4), (5, 2), (5, 14)]);
    params["context"] = json!({ "includeDeclaration": false });
    let r = request(&mut s, "textDocument/references", params);
    assert_eq!(r["result"].as_array().map(Vec::len), Some(2));

    let param = HELPER.find("(n)").expect("n") + 1;
    let r = request(&mut s, "textDocument/references", at(uri, HELPER, param));
    assert_eq!(r["result"].as_array().map(Vec::len), Some(2), "{r}");
}

/// **Rename edits every use, and is refused when the new name would change
/// what a reference means**: `helper` renamed to `x` would turn `helper(x)`
/// inside `g` into a call of `g`'s parameter.
///
/// Red run (2026-10-10): `verify` returning `Ok(())` unconditionally — the
/// capturing rename came back as edits instead of an error, `left: Null
/// right: Number(-32803)`.
#[test]
fn rename_edits_every_use_and_refuses_a_capture() {
    let mut s = server();
    let uri = "file:///helper.b";
    open(&mut s, uri, HELPER);
    let call = HELPER.find("helper(1)").expect("call");
    let mut params = at(uri, HELPER, call);
    let prepared = request(&mut s, "textDocument/prepareRename", params.clone());
    assert_eq!(prepared["result"]["placeholder"], json!("helper"));

    params["newName"] = json!("assist");
    let r = request(&mut s, "textDocument/rename", params.clone());
    let edits = r["result"]["changes"][uri]
        .as_array()
        .expect("edits")
        .clone();
    assert_eq!(edits.len(), 3, "{r}");
    assert!(edits.iter().all(|e| e["newText"] == json!("assist")));

    params["newName"] = json!("x");
    let r = request(&mut s, "textDocument/rename", params.clone());
    assert_eq!(r["error"]["code"], json!(-32803), "{r}");
    let why = r["error"]["message"].as_str().unwrap_or("");
    assert!(why.contains("would change what"), "{why}");
    assert!(why.contains("line 6"), "{why}");

    let local = HELPER.find("n + 1").expect("n");
    let mut params = at(uri, HELPER, local);
    params["newName"] = json!("count");
    let r = request(&mut s, "textDocument/rename", params);
    assert_eq!(
        r["result"]["changes"][uri].as_array().map(Vec::len),
        Some(2),
        "{r}"
    );

    let builtin = "def f(xs)\n  length(xs)\nend\n";
    open(&mut s, "file:///b.b", builtin);
    let mut params = at(
        "file:///b.b",
        builtin,
        builtin.find("length").expect("length"),
    );
    params["newName"] = json!("size");
    let r = request(&mut s, "textDocument/rename", params);
    assert!(
        r["error"]["message"]
            .as_str()
            .is_some_and(|m| m.contains("builtin")),
        "{r}"
    );
}

/// **A rename reaches every open document that uses the definition**, and
/// each is verified with the others' edits in place: retsu's `size`, renamed
/// in retsu's own buffer, is renamed in a script's `use` list and call too.
///
/// Red run (2026-10-10): `verify` analysing each document alone, without
/// the overlay — the script, still importing retsu as it is on disk, lost
/// its `size`: `renaming to `length_of` would change what `size` on line 4
/// means: size (bidama `retsu`) now, unbound after`.
#[test]
fn rename_reaches_every_open_document() {
    let mut s = server();
    let retsu = bidamas().join("retsu/retsu.b");
    let retsu_uri = uri_of(&retsu);
    let retsu_text = std::fs::read_to_string(&retsu).expect("retsu.b");
    open(&mut s, &retsu_uri, &retsu_text);
    let script = "file:///uses-size.b";
    let text = "use(\"retsu\", [:size])\n\ndef f(xs)\n  size(xs)\nend\n";
    open(&mut s, script, text);
    let mut params = at(script, text, text.find("size(xs)").expect("call"));
    params["newName"] = json!("length_of");
    let r = request(&mut s, "textDocument/rename", params);
    assert!(r["error"].is_null(), "{r}");
    let changes = &r["result"]["changes"];
    assert_eq!(changes[script].as_array().map(Vec::len), Some(2), "{r}");
    let in_retsu = changes[retsu_uri.as_str()]
        .as_array()
        .expect("edits in retsu.b");
    let calls_in_retsu = retsu_text.matches("size(").count();
    assert_eq!(in_retsu.len(), calls_in_retsu, "{in_retsu:?}");
}

/// **Document symbols** are the file's items, each with its own range and
/// the name's selection range.
///
/// Red run (2026-10-10): the `textDocument/documentSymbol` arm removed —
/// method not found, so no `symbols` array.
#[test]
fn document_symbols_list_the_files_items() {
    let mut s = server();
    let uri = "file:///symbols.b";
    let text = "use(\"retsu\", [:size])\n\nlimit = 3\n\ndef f(xs)\n  size(xs)\nend\n\ntest \"f counts\"\n  assert f([1]) == 1\nend\n";
    open(&mut s, uri, text);
    let r = request(
        &mut s,
        "textDocument/documentSymbol",
        json!({ "textDocument": { "uri": uri } }),
    );
    let got: Vec<(String, i64)> = r["result"]
        .as_array()
        .expect("symbols")
        .iter()
        .map(|s| {
            (
                s["name"].as_str().unwrap_or("").to_string(),
                s["kind"].as_i64().unwrap_or(0),
            )
        })
        .collect();
    assert_eq!(
        got,
        vec![
            ("retsu".to_string(), 2),
            ("limit".to_string(), 13),
            ("f".to_string(), 12),
            ("f counts".to_string(), 24)
        ]
    );
    let f = &r["result"][2];
    assert_eq!(
        f["selectionRange"]["start"],
        json!({ "line": 4, "character": 4 })
    );
    assert_eq!(f["range"]["end"], json!({ "line": 6, "character": 3 }));
}

/// **Workspace symbols** search the open documents and every bidama the
/// session loaded.
///
/// Red run (2026-10-10): the `workspace/symbol` arm removed — method not
/// found, so no `symbols` array.
#[test]
fn workspace_symbols_search_open_files_and_loaded_bidamas() {
    let mut s = server();
    let (uri, text) = junjo();
    open(&mut s, &uri, &text);
    let r = request(&mut s, "workspace/symbol", json!({ "query": "is_emp" }));
    let found = r["result"].as_array().expect("symbols");
    let retsu = found
        .iter()
        .find(|s| s["containerName"] == json!("bidama `retsu`"))
        .expect("retsu's is_empty");
    assert_eq!(retsu["name"], json!("is_empty"));
    assert!(retsu["location"]["uri"]
        .as_str()
        .is_some_and(|u| u.ends_with("retsu/retsu.b")));
    let r = request(
        &mut s,
        "workspace/symbol",
        json!({ "query": "insert_ordered" }),
    );
    assert!(r["result"]
        .as_array()
        .expect("symbols")
        .iter()
        .any(|s| s["location"]["uri"] == json!(uri) && s["containerName"] == json!("this file")));
}

/// **`source.fixAll` is `blue check --fix`**: every machine-applicable fix,
/// then the one formatting, as one whole-document edit.
///
/// Red run (2026-10-10): the `source.fixAll` branch removed — no action of
/// that kind, `expected a fixAll action: []`.
#[test]
fn fix_all_applies_what_blue_check_fix_applies() {
    let mut s = server();
    let uri = "file:///fix.b";
    let text = "def g(x, y)\n  x\nend\n\ndef h(a, b)\n  a\nend\n";
    open(&mut s, uri, text);
    let r = request(
        &mut s,
        "textDocument/codeAction",
        json!({
            "textDocument": { "uri": uri },
            "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
            "context": { "diagnostics": [], "only": ["source.fixAll"] },
        }),
    );
    let actions = r["result"].as_array().expect("actions");
    let fix = actions
        .iter()
        .find(|a| a["kind"] == json!("source.fixAll"))
        .unwrap_or_else(|| panic!("expected a fixAll action: {actions:?}"));
    let edit = &fix["edit"]["changes"][uri][0];
    assert_eq!(
        edit["newText"],
        json!("def g(x, _y)\n  x\nend\n\ndef h(a, _b)\n  a\nend\n")
    );
    let d = diagnostics(&change(&mut s, uri, edit["newText"].as_str().unwrap_or("")));
    assert!(d.is_empty(), "{d:?}");
}

/// **Signature help** names the call the cursor is inside and which
/// argument, while the buffer is mid-call and does not parse.
///
/// Red run (2026-10-10): the `textDocument/signatureHelp` arm removed —
/// `left: Null right: String("def add(a, b)")`.
#[test]
fn signature_help_reads_the_open_call() {
    let mut s = server();
    let uri = "file:///sig.b";
    let good = "def add(a, b)\n  a + b\nend\n\nadd(1, 2)\n";
    open(&mut s, uri, good);
    let typing = "def add(a, b)\n  a + b\nend\n\nadd(1, ";
    change(&mut s, uri, typing);
    let r = request(
        &mut s,
        "textDocument/signatureHelp",
        at(uri, typing, typing.len()),
    );
    assert_eq!(
        r["result"]["signatures"][0]["label"],
        json!("def add(a, b)"),
        "{r}"
    );
    assert_eq!(r["result"]["activeParameter"], json!(1));
    let typing = "def add(a, b)\n  a + b\nend\n\nlength(";
    change(&mut s, uri, typing);
    let r = request(
        &mut s,
        "textDocument/signatureHelp",
        at(uri, typing, typing.len()),
    );
    assert_eq!(r["result"]["activeParameter"], json!(0));
    assert!(
        r["result"]["signatures"][0]["label"]
            .as_str()
            .is_some_and(|l| l.starts_with("length(")),
        "{r}"
    );
}

/// **Hover names where a name resolved and carries its doc line**, for a
/// definition in a bidama.
///
/// Red run (2026-10-10): the same session against the pre-engine server,
/// whose hover read the buffer's own declarations only —
/// `{"id":1,"jsonrpc":"2.0","result":null}`.
#[test]
fn hover_reads_a_bidamas_definition() {
    let mut s = server();
    let uri = "file:///hover.b";
    let text = "use(\"retsu\", [:size])\n\nsize([1, 2])\n";
    open(&mut s, uri, text);
    let r = request(
        &mut s,
        "textDocument/hover",
        at(uri, text, text.rfind("size").expect("size") + 1),
    );
    let md = r["result"]["contents"]["value"]
        .as_str()
        .unwrap_or_else(|| panic!("{r}"));
    assert!(md.contains("def size(xs)"), "{md}");
    assert!(md.contains("bidama `retsu`"), "{md}");
    assert!(md.contains("Total length"), "{md}");
}
