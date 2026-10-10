//! The JSON-RPC shim.
//!
//! Thin by construction: decode, ask the engine ([`blue_lang_mondou`]) or
//! [`crate::analysis`], encode. Every decision worth testing lives below the
//! shim, so this file's tests are about the *protocol* — that a reply carries
//! the request's id, that an unknown method is an error rather than silence,
//! that a notification gets no reply — and about each request reaching the
//! engine query it names.
//!
//! ## `handle` is a pure function
//!
//! [`handle`] takes a request and returns a reply. No sockets, no stdin, no
//! spawning. That is what makes the protocol testable at all: a server whose
//! only entry point is a read loop can only be tested by running it.
//!
//! [`Server::serve`] wraps it in the actual stdio loop, and is the only part
//! that touches I/O.
//!
//! ## One analysis per revision
//!
//! The server holds one [`Engine`] for the session. A document is parsed and
//! checked once per revision, whatever is asked of it, and the bidamas its
//! imports name are loaded once per session.

use std::io::{BufRead, Write};
use std::path::PathBuf;

use blue_lang_mondou::{Engine, FileRef, Located};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::analysis::{diagnostics, hover_of, LineIndex, Position};
use crate::tokens;

/// What the server produced for one incoming message.
#[derive(Clone, Debug, PartialEq)]
pub enum Response {
    /// A reply to a request, to be sent back.
    Reply(Value),
    /// A notification to push (diagnostics).
    Notify(Value),
    /// Nothing to send — the correct answer to a notification.
    None,
    /// A reply and a push, in that order.
    ReplyAndNotify(Value, Value),
    /// Several messages, in order. Used when one event produces more than one
    /// PUSH — `didOpen` emits both diagnostics and the shift reading. Distinct
    /// from `ReplyAndNotify`, which pairs a *reply* with a push; conflating
    /// them would make the variant name lie about what is being sent.
    Messages(Vec<Value>),
}

/// The session: the engine, holding every open document.
pub struct Server {
    engine: Engine,
    /// Set by `shutdown`, so `serve` can stop cleanly rather than on EOF alone.
    shutting_down: bool,
}

impl Default for Server {
    fn default() -> Self {
        Self::with_loader(Box::new(blue_lang_runtime::uses::NoLoader))
    }
}

impl std::fmt::Debug for Server {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Server")
            .field("documents", &self.engine.document_ids())
            .field("shutting_down", &self.shutting_down)
            .finish_non_exhaustive()
    }
}

#[derive(Deserialize)]
struct Incoming {
    #[serde(default)]
    id: Option<Value>,
    method: String,
    #[serde(default)]
    params: Value,
}

#[derive(Serialize)]
struct Error<'a> {
    code: i64,
    message: &'a str,
}

/// JSON-RPC's code for a request the server understood and could not carry
/// out (LSP `RequestFailed`).
const REQUEST_FAILED: i64 = -32803;

impl Server {
    pub fn new() -> Self {
        Self::default()
    }

    /// A server whose documents resolve `use(...)` through `loader`.
    #[must_use]
    pub fn with_loader(loader: Box<dyn blue_lang_runtime::uses::Loader>) -> Self {
        Self {
            engine: Engine::new(loader),
            shutting_down: false,
        }
    }

    pub fn is_shutting_down(&self) -> bool {
        self.shutting_down
    }

    pub fn document(&self, uri: &str) -> Option<String> {
        self.engine.document_text(uri).map(|t| t.to_string())
    }

    /// The engine, for a test or a host that asks it directly.
    #[must_use]
    pub fn engine(&self) -> &Engine {
        &self.engine
    }

    /// Handle one decoded message.
    pub fn handle_value(&mut self, msg: &Value) -> Response {
        let Ok(req) = serde_json::from_value::<Incoming>(msg.clone()) else {
            return Response::Reply(error_reply(&Value::Null, -32700, "malformed message"));
        };
        let id = req.id.clone();
        let uri = str_at(&req.params, &["textDocument", "uri"]).unwrap_or_default();

        match req.method.as_str() {
            "initialize" => reply(&id, capabilities()),

            "initialized" => Response::None,

            "shutdown" => {
                self.shutting_down = true;
                reply(&id, Value::Null)
            }

            "exit" => Response::None,

            "textDocument/didOpen" => {
                let text = str_at(&req.params, &["textDocument", "text"]).unwrap_or_default();
                self.engine.set_document(&uri, path_of(&uri), &text);
                Response::Messages(vec![
                    self.diagnostics_notification(&uri),
                    self.shift_notification(&uri),
                ])
            }

            "textDocument/didChange" => {
                // Full-document sync only — `capabilities()` advertises
                // TextDocumentSyncKind::Full (1), so a client never sends
                // incremental edits. Advertising incremental and then applying
                // only the last change is how a server drifts out of sync with
                // the buffer and reports diagnostics for text nobody has.
                let text = req
                    .params
                    .get("contentChanges")
                    .and_then(Value::as_array)
                    .and_then(|c| c.last())
                    .and_then(|c| c.get("text"))
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string();
                self.engine.set_document(&uri, path_of(&uri), &text);
                // The reading is pushed on EVERY edit, so it tracks the author
                // as they type rather than when they remember to ask.
                Response::Messages(vec![
                    self.diagnostics_notification(&uri),
                    self.shift_notification(&uri),
                ])
            }

            "textDocument/didClose" => {
                if self.engine.document_text(&uri).is_some() {
                    self.engine.close_document(&uri);
                    // Clear the client's squiggles; a closed file's diagnostics
                    // otherwise persist in the problems panel forever.
                    return Response::Notify(publish(&uri, Vec::new()));
                }
                Response::None
            }

            // A file changed on disk: a bidama holding it is loaded again on
            // its next use.
            "workspace/didChangeWatchedFiles" => {
                let changes = req
                    .params
                    .get("changes")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();
                for c in changes {
                    if let Some(p) = c.get("uri").and_then(Value::as_str).and_then(path_of) {
                        self.engine.invalidate_path(&p);
                    }
                }
                Response::None
            }

            "textDocument/formatting" => {
                let Some(text) = self.engine.document_text(&uri) else {
                    return reply(&id, Value::Null);
                };
                match self.engine.formatted(&uri) {
                    // `null`, not an empty edit list: an unformattable document
                    // must not look like one that was already canonical.
                    None => reply(&id, Value::Null),
                    Some(formatted) => {
                        let whole = LineIndex::new(&text).whole_document();
                        reply(
                            &id,
                            json!([{ "range": range_json(whole), "newText": formatted }]),
                        )
                    }
                }
            }

            "textDocument/semanticTokens/full" => {
                // An unknown document replies null, not an empty token list.
                // Empty `data` is a positive claim — "this buffer has no
                // colour" — and a client caches it; null says "no answer",
                // which is the truth when the document was never opened.
                let Some(text) = self.engine.document_text(&uri) else {
                    return reply(&id, Value::Null);
                };
                let data = tokens::encode(&tokens::semantic_tokens(&text));
                reply(&id, json!({ "data": data }))
            }

            "textDocument/hover" => {
                let Some(offset) = self.offset_of(&uri, &req.params) else {
                    return reply(&id, Value::Null);
                };
                match hover_of(&self.engine, &uri, offset) {
                    None => reply(&id, Value::Null),
                    Some(h) => reply(
                        &id,
                        json!({ "contents": { "kind": "markdown", "value": self.hover_markdown(&uri, &h) } }),
                    ),
                }
            }

            // Quick fixes: the check stage's own suggested repairs for every
            // diagnostic touching the requested range, and `source.fixAll`,
            // which applies exactly what `blue check --fix` would.
            "textDocument/codeAction" => {
                if self.engine.document_text(&uri).is_none() {
                    return reply(&id, json!([]));
                }
                let at = |k: &str| Position {
                    line: u32_at(&req.params, &["range", k, "line"]).unwrap_or(0),
                    character: u32_at(&req.params, &["range", k, "character"]).unwrap_or(0),
                };
                let (start, end) = (at("start"), at("end"));
                let only: Vec<String> = req
                    .params
                    .get("context")
                    .and_then(|c| c.get("only"))
                    .and_then(Value::as_array)
                    .map(|a| {
                        a.iter()
                            .filter_map(Value::as_str)
                            .map(str::to_string)
                            .collect()
                    })
                    .unwrap_or_default();
                let wants = |kind: &str| {
                    only.is_empty()
                        || only
                            .iter()
                            .any(|o| kind == o || kind.starts_with(&format!("{o}.")))
                };
                let mut actions = Vec::new();
                if wants("quickfix") {
                    for d in diagnostics(&self.engine, &uri) {
                        if d.range.end < start || end < d.range.start {
                            continue;
                        }
                        for fix in &d.fixes {
                            let edits: Vec<Value> = fix
                                .edits
                                .iter()
                                .map(|e| json!({ "range": range_json(e.range), "newText": e.new_text }))
                                .collect();
                            actions.push(json!({
                                "title": fix.title,
                                "kind": "quickfix",
                                "isPreferred": fix.preferred,
                                "diagnostics": [diagnostic_json(&d)],
                                "edit": { "changes": { uri.clone(): edits } },
                            }));
                        }
                    }
                }
                if wants("source.fixAll") {
                    if let (Some(fixed), Some(text)) =
                        (self.engine.fix_all(&uri), self.engine.document_text(&uri))
                    {
                        let whole = LineIndex::new(&text).whole_document();
                        actions.push(json!({
                            "title": "apply every machine-applicable fix (blue check --fix)",
                            "kind": "source.fixAll",
                            "edit": { "changes": { uri.clone(): [{ "range": range_json(whole), "newText": fixed }] } },
                        }));
                    }
                }
                reply(&id, Value::Array(actions))
            }

            // Ranked by the resolution tiers: locals, this file, its `use`
            // lists, builtins — then names one `use` away, each with the edit
            // that adds it.
            "textDocument/completion" => {
                let Some(offset) = self.offset_of(&uri, &req.params) else {
                    return reply(&id, Value::Null);
                };
                let text = self.engine.document_text(&uri).unwrap_or_default();
                let index = LineIndex::new(&text);
                let items: Vec<Value> = self
                    .engine
                    .completions(&uri, offset)
                    .into_iter()
                    .enumerate()
                    .map(|(rank, c)| completion_json(rank, c, &index))
                    .collect();
                reply(&id, json!({ "isIncomplete": false, "items": items }))
            }

            "textDocument/definition" => {
                let Some(offset) = self.offset_of(&uri, &req.params) else {
                    return reply(&id, Value::Null);
                };
                let Some(a) = self.engine.analysis(&uri) else {
                    return reply(&id, Value::Null);
                };
                let found = a.definition(&self.engine, offset);
                let locations: Vec<Value> = found
                    .iter()
                    .filter_map(|l| self.location_json(&uri, l))
                    .collect();
                reply(&id, Value::Array(locations))
            }

            "textDocument/references" => {
                let Some(offset) = self.offset_of(&uri, &req.params) else {
                    return reply(&id, Value::Null);
                };
                let declarations = req
                    .params
                    .get("context")
                    .and_then(|c| c.get("includeDeclaration"))
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                let locations: Vec<Value> = self
                    .engine
                    .references(&uri, offset, declarations)
                    .iter()
                    .filter_map(|l| self.location_json(&uri, l))
                    .collect();
                reply(&id, Value::Array(locations))
            }

            "textDocument/prepareRename" => {
                let Some(offset) = self.offset_of(&uri, &req.params) else {
                    return reply(&id, Value::Null);
                };
                let text = self.engine.document_text(&uri).unwrap_or_default();
                match self.engine.prepare_rename(&uri, offset) {
                    Ok((span, placeholder)) => reply(
                        &id,
                        json!({ "range": range_json(LineIndex::new(&text).range(span)), "placeholder": placeholder }),
                    ),
                    Err(refusal) => failed(&id, &refusal.to_string()),
                }
            }

            // Refused, with the reason, when the new name would change what
            // any reference means.
            "textDocument/rename" => {
                let Some(offset) = self.offset_of(&uri, &req.params) else {
                    return reply(&id, Value::Null);
                };
                let new_name = str_at(&req.params, &["newName"]).unwrap_or_default();
                match self.engine.rename(&uri, offset, &new_name) {
                    Ok(per_document) => {
                        let mut changes = serde_json::Map::new();
                        for (doc, edits) in per_document {
                            let text = self.engine.document_text(&doc).unwrap_or_default();
                            let index = LineIndex::new(&text);
                            let list: Vec<Value> = edits
                                .iter()
                                .map(|(s, t)| json!({ "range": range_json(index.range(*s)), "newText": t }))
                                .collect();
                            changes.insert(doc, Value::Array(list));
                        }
                        reply(&id, json!({ "changes": changes }))
                    }
                    Err(refusal) => failed(&id, &refusal.to_string()),
                }
            }

            "textDocument/documentSymbol" => {
                let Some(a) = self.engine.analysis(&uri) else {
                    return reply(&id, Value::Null);
                };
                let index = LineIndex::new(&a.text);
                let symbols: Vec<Value> = a
                    .items()
                    .iter()
                    .map(|i| {
                        json!({
                            "name": i.name,
                            "detail": i.signature,
                            "kind": symbol_kind(i.kind),
                            "range": range_json(index.range(i.span)),
                            "selectionRange": range_json(index.range(i.name_span)),
                        })
                    })
                    .collect();
                reply(&id, Value::Array(symbols))
            }

            "workspace/symbol" => {
                let query = str_at(&req.params, &["query"]).unwrap_or_default();
                let mut out = Vec::new();
                for s in self.engine.workspace_symbols(&query) {
                    let Some(location) = self.location_json("", &s.at) else {
                        continue;
                    };
                    out.push(json!({
                        "name": s.item.name,
                        "kind": symbol_kind(s.item.kind),
                        "containerName": s.container,
                        "location": location,
                    }));
                }
                reply(&id, Value::Array(out))
            }

            "textDocument/signatureHelp" => {
                let Some(offset) = self.offset_of(&uri, &req.params) else {
                    return reply(&id, Value::Null);
                };
                match self.engine.signature_at(&uri, offset) {
                    None => reply(&id, Value::Null),
                    Some(s) => reply(
                        &id,
                        json!({
                            "signatures": [{
                                "label": s.label,
                                "documentation": s.doc,
                                "parameters": s.parameters.iter().map(|p| json!({ "label": p })).collect::<Vec<_>>(),
                            }],
                            "activeSignature": 0,
                            "activeParameter": s.active,
                        }),
                    ),
                }
            }

            // `blue/shift` — the reading. A custom method because LSP has no
            // standard "where am I on this language's own continuum", which is
            // the point: no other language has one to report.
            "blue/shift" => match self.shift(&uri) {
                Some(s) => reply(&id, shift_json(&s)),
                None => reply(&id, Value::Null),
            },

            // An unknown METHOD with an id is an error reply; an unknown
            // NOTIFICATION is silence, per the JSON-RPC spec. Replying to a
            // notification is a protocol violation some clients treat as fatal.
            _ => match id {
                Some(id) => Response::Reply(error_reply(&id, -32601, "method not found")),
                None => Response::None,
            },
        }
    }

    /// The stdio loop. The only part of this crate that does I/O.
    pub fn serve<R: BufRead, W: Write>(
        &mut self,
        mut input: R,
        mut output: W,
    ) -> std::io::Result<()> {
        while let Some(msg) = read_message(&mut input)? {
            match self.handle_value(&msg) {
                Response::None => {}
                Response::Reply(v) | Response::Notify(v) => write_message(&mut output, &v)?,
                Response::ReplyAndNotify(a, b) => {
                    write_message(&mut output, &a)?;
                    write_message(&mut output, &b)?;
                }
                Response::Messages(all) => {
                    for m in all {
                        write_message(&mut output, &m)?;
                    }
                }
            }
            if self.shutting_down {
                break;
            }
        }
        Ok(())
    }

    /// The byte offset a request's `position` names in its document.
    fn offset_of(&self, uri: &str, params: &Value) -> Option<usize> {
        let text = self.engine.document_text(uri)?;
        let pos = Position {
            line: u32_at(params, &["position", "line"]).unwrap_or(0),
            character: u32_at(params, &["position", "character"]).unwrap_or(0),
        };
        Some(LineIndex::new(&text).offset(pos))
    }

    fn diagnostics_notification(&self, uri: &str) -> Value {
        let diags = diagnostics(&self.engine, uri)
            .iter()
            .map(diagnostic_json)
            .collect();
        publish(uri, diags)
    }

    /// The reading, from the tree the engine parsed this revision into.
    fn shift(&self, uri: &str) -> Option<crate::Shift> {
        let a = self.engine.analysis(uri)?;
        let forms = a.parsed.as_ref().as_ref().ok().map(Vec::as_slice);
        Some(crate::shift::shift_of_tree(&a.text, forms))
    }

    /// A `blue/shift` notification, pushed on open and on every change.
    fn shift_notification(&self, uri: &str) -> Value {
        let mut params = self.shift(uri).map_or(Value::Null, |s| shift_json(&s));
        if let Some(obj) = params.as_object_mut() {
            obj.insert("uri".to_string(), json!(uri));
        }
        json!({ "jsonrpc": "2.0", "method": "blue/shift", "params": params })
    }

    /// Hover: the signature, where it resolved, its doc line, and under it
    /// the document's shift reading. A custom request only helps a client
    /// that knows to ask; hover works in every editor today, which is what
    /// makes the shift *always visible* rather than opt-in.
    fn hover_markdown(&self, uri: &str, h: &crate::analysis::Hover) -> String {
        let mut md = format_code(&h.signature);
        md.push_str("\n\n");
        md.push_str(&h.namespace);
        if let Some(doc) = &h.doc {
            md.push_str("\n\n");
            md.push_str(doc);
        }
        if let Some(reading) = self.shift(uri) {
            md.push_str("\n\n---\n\n");
            md.push_str(&reading.summary());
            if let Some(rung) = reading.rung {
                md.push_str("\n\n");
                md.push_str(rung.meaning());
            }
            // Name what is holding it back — the actionable half.
            let held = reading.holding_back();
            if !held.is_empty() {
                md.push_str("\n\nshifting further:");
                for f in held.iter().take(3) {
                    md.push_str("\n- ");
                    md.push_str(&f.detail);
                }
            }
        }
        md
    }

    /// A located span as an LSP `Location`: an open document by its uri,
    /// any other file by a `file://` uri of its path.
    fn location_json(&self, from: &str, l: &Located) -> Option<Value> {
        let (uri, text) = match &l.file {
            FileRef::Document(doc) => (doc.clone(), self.engine.document_text(doc)?.to_string()),
            FileRef::Path(p) => {
                let text = match self.engine.analysis(from) {
                    Some(a) => a.file_text(&l.file).map(str::to_string),
                    None => None,
                }
                .or_else(|| std::fs::read_to_string(p).ok())?;
                (uri_of(p), text)
            }
        };
        Some(json!({ "uri": uri, "range": range_json(LineIndex::new(&text).range(l.span)) }))
    }
}

/// Handle one message against a fresh server. For callers that do not need
/// document state to persist.
pub fn handle(msg: &Value) -> Response {
    Server::new().handle_value(msg)
}

fn capabilities() -> Value {
    json!({
        "capabilities": {
            // 1 = Full. Incremental sync is NOT advertised, because this server
            // does not apply incremental edits; advertising it and then using
            // only the last change would silently desynchronise the buffer.
            "textDocumentSync": 1,
            "documentFormattingProvider": true,
            "hoverProvider": true,
            "codeActionProvider": { "codeActionKinds": ["quickfix", "source.fixAll"] },
            // `:` completes after a qualifier (`kueri::`); a send's method
            // name is any function in scope anyway, so `.` is not one.
            "completionProvider": { "resolveProvider": false, "triggerCharacters": [":"] },
            "definitionProvider": true,
            "referencesProvider": true,
            "renameProvider": { "prepareProvider": true },
            "documentSymbolProvider": true,
            "workspaceSymbolProvider": true,
            "signatureHelpProvider": { "triggerCharacters": ["(", ","] },
            // Colour. The legend is derived from `tokens::SemanticTokenType`,
            // never written out here — the enum's order IS the wire format,
            // and a second spelling of it is a way to repaint every buffer
            // wrongly with a one-line edit.
            //
            // `range` is deliberately absent: blue lexes a whole document
            // fast enough that a range request would add a second code path
            // for no measured gain, and a client falls back to `full`.
            "semanticTokensProvider": {
                "legend": {
                    "tokenTypes": tokens::legend_types(),
                    "tokenModifiers": tokens::legend_modifiers(),
                },
                "full": true,
            },
        },
        "serverInfo": { "name": "blue-lsp", "version": env!("CARGO_PKG_VERSION") },
    })
}

fn reply(id: &Option<Value>, result: Value) -> Response {
    match id {
        Some(id) => Response::Reply(json!({ "jsonrpc": "2.0", "id": id, "result": result })),
        // A request with no id is a notification; a reply would be a protocol
        // violation.
        None => Response::None,
    }
}

/// A request understood and refused, with the reason a person reads.
fn failed(id: &Option<Value>, message: &str) -> Response {
    match id {
        Some(id) => Response::Reply(error_reply(id, REQUEST_FAILED, message)),
        None => Response::None,
    }
}

fn error_reply(id: &Value, code: i64, message: &str) -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": serde_json::to_value(Error { code, message }).unwrap_or(Value::Null),
    })
}

/// A completion as LSP JSON: ranked by tier through `sortText`, its
/// namespace and tier in `labelDetails`, and the `use` it needs, if any, as
/// an additional edit.
fn completion_json(rank: usize, c: blue_lang_mondou::Completion, index: &LineIndex) -> Value {
    let kind = match c.kind {
        blue_lang_mondou::CompletionKind::Function => 3,
        blue_lang_mondou::CompletionKind::Value => 6,
        blue_lang_mondou::CompletionKind::Keyword => 14,
    };
    let mut v = json!({
        "label": c.label,
        "kind": kind,
        "detail": c.namespace,
        "labelDetails": { "description": c.tier.label() },
        "sortText": format!("{}{rank:05}", c.tier as u8),
    });
    let Some(obj) = v.as_object_mut() else {
        return v;
    };
    if let Some(insert) = c.insert {
        obj.insert("insertText".to_string(), json!(insert));
    }
    let documentation = match (c.signature, c.doc) {
        (Some(s), Some(d)) => Some(format!("{}\n\n{d}", format_code(&s))),
        (Some(s), None) => Some(format_code(&s)),
        (None, Some(d)) => Some(d),
        (None, None) => None,
    };
    if let Some(d) = documentation {
        obj.insert(
            "documentation".to_string(),
            json!({ "kind": "markdown", "value": d }),
        );
    }
    if let Some((span, text)) = c.edit {
        obj.insert(
            "additionalTextEdits".to_string(),
            json!([{ "range": range_json(index.range(span)), "newText": text }]),
        );
    }
    v
}

/// LSP `SymbolKind`.
fn symbol_kind(kind: blue_lang_mondou::ItemKind) -> i64 {
    use blue_lang_mondou::ItemKind;
    match kind {
        ItemKind::Function | ItemKind::Macro => 12,
        ItemKind::Value => 13,
        ItemKind::Test => 24,
        ItemKind::Use => 2,
    }
}

/// A diagnostic as LSP JSON: the registry code in `code`, the help line
/// appended to the message.
fn diagnostic_json(d: &crate::Diagnostic) -> Value {
    let mut message = d.message.clone();
    if let Some(help) = &d.help {
        message.push_str("\nhelp: ");
        message.push_str(help);
    }
    let mut v = json!({
        "range": range_json(d.range),
        "severity": d.severity as i64,
        "source": d.source,
        "message": message,
    });
    if let (Some(code), Some(obj)) = (d.code, v.as_object_mut()) {
        obj.insert("code".to_string(), json!(code));
    }
    v
}

fn publish(uri: &str, diagnostics: Vec<Value>) -> Value {
    json!({
        "jsonrpc": "2.0",
        "method": "textDocument/publishDiagnostics",
        "params": { "uri": uri, "diagnostics": diagnostics },
    })
}

/// The reading as JSON.
fn shift_json(s: &crate::Shift) -> Value {
    json!({
        "rung": s.rung.map(|r| r.label()),
        "ramp": s.rung.map(crate::Rung::ramp),
        "meaning": s.rung.map(crate::Rung::meaning),
        "summary": s.summary(),
        "analysedNodes": s.analysed_nodes,
        "typedDeclarations": s.typed_declarations,
        "totalDeclarations": s.total_declarations,
        "factors": s.factors.iter().map(|f| json!({
            "kind": f.kind.label(),
            "subject": f.subject,
            "shiftsForward": f.kind.shifts_forward(),
            "range": range_json(f.range),
            "detail": f.detail,
        })).collect::<Vec<_>>(),
    })
}

fn range_json(r: crate::Range) -> Value {
    json!({
        "start": { "line": r.start.line, "character": r.start.character },
        "end": { "line": r.end.line, "character": r.end.character },
    })
}

/// A signature as a markdown code block. Built by concatenation rather than
/// `format!` of arbitrary structure — see the fleet's typed-emission rule.
fn format_code(sig: &str) -> String {
    let mut out = String::with_capacity(sig.len() + 16);
    out.push_str("```blue\n");
    out.push_str(sig);
    out.push_str("\n```");
    out
}

/// The file a `file://` uri names; `None` for any other scheme.
fn path_of(uri: &str) -> Option<PathBuf> {
    let rest = uri.strip_prefix("file://")?;
    let bytes = rest.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(b) = u8::from_str_radix(&rest[i + 1..i + 3], 16) {
                out.push(b);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8(out).ok().map(PathBuf::from)
}

/// A `file://` uri for `path`, escaping what a uri cannot hold.
fn uri_of(path: &std::path::Path) -> String {
    let mut out = String::from("file://");
    for b in path.display().to_string().bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'/' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn str_at(v: &Value, path: &[&str]) -> Option<String> {
    let mut cur = v;
    for key in path {
        cur = cur.get(key)?;
    }
    cur.as_str().map(str::to_string)
}

fn u32_at(v: &Value, path: &[&str]) -> Option<u32> {
    let mut cur = v;
    for key in path {
        cur = cur.get(key)?;
    }
    cur.as_u64().map(|n| n as u32)
}

/// Read one LSP message: `Content-Length` header, blank line, then that many
/// bytes.
fn read_message<R: BufRead>(input: &mut R) -> std::io::Result<Option<Value>> {
    let mut length: Option<usize> = None;
    loop {
        let mut line = String::new();
        if input.read_line(&mut line)? == 0 {
            return Ok(None); // EOF
        }
        let trimmed = line.trim_end();
        if trimmed.is_empty() {
            break; // End of headers.
        }
        if let Some(rest) = trimmed
            .strip_prefix("Content-Length:")
            .or_else(|| trimmed.strip_prefix("content-length:"))
        {
            length = rest.trim().parse().ok();
        }
    }
    // A message with no Content-Length cannot be framed, and guessing a length
    // would desynchronise the stream for every message after it.
    let Some(length) = length else {
        return Ok(None);
    };
    let mut buf = vec![0u8; length];
    input.read_exact(&mut buf)?;
    Ok(serde_json::from_slice(&buf).ok())
}

fn write_message<W: Write>(output: &mut W, value: &Value) -> std::io::Result<()> {
    let body = serde_json::to_vec(value)?;
    write!(output, "Content-Length: {}\r\n\r\n", body.len())?;
    output.write_all(&body)?;
    output.flush()
}

#[cfg(test)]
mod tests {
    use super::*;
    // Only the tests assert on severity codes, so this is imported here rather
    // than at module scope where it would be dead in a normal build.
    use crate::Severity;

    const PROGRAM: &str = "def add(a: Int, b: Int) -> Int\n  a + b\nend";

    fn open(server: &mut Server, uri: &str, text: &str) -> Response {
        server.handle_value(&json!({
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": { "textDocument": { "uri": uri, "text": text } },
        }))
    }

    /// The diagnostics push from an open/change, which now also carries a
    /// `blue/shift` push alongside it.
    fn diagnostics_of(r: &Response) -> Value {
        match r {
            Response::Notify(v) => v.clone(),
            Response::Messages(all) => all
                .iter()
                .find(|m| m["method"] == json!("textDocument/publishDiagnostics"))
                .cloned()
                .expect("a diagnostics push"),
            other => panic!("expected a push, got {other:?}"),
        }
    }

    fn req(id: i64, method: &str, params: Value) -> Value {
        json!({ "jsonrpc": "2.0", "id": id, "method": method, "params": params })
    }

    /// Each advertised provider and the request it promises an answer to.
    const ADVERTISED: &[(&str, &str)] = &[
        ("documentFormattingProvider", "textDocument/formatting"),
        ("hoverProvider", "textDocument/hover"),
        ("codeActionProvider", "textDocument/codeAction"),
        ("completionProvider", "textDocument/completion"),
        ("definitionProvider", "textDocument/definition"),
        ("referencesProvider", "textDocument/references"),
        ("renameProvider", "textDocument/rename"),
        ("documentSymbolProvider", "textDocument/documentSymbol"),
        ("workspaceSymbolProvider", "workspace/symbol"),
        ("signatureHelpProvider", "textDocument/signatureHelp"),
        ("semanticTokensProvider", "textDocument/semanticTokens/full"),
    ];

    /// Requests a client may send that this server does not answer, so it
    /// must not claim them.
    const NOT_IMPLEMENTED: &[(&str, &str)] = &[
        ("typeDefinitionProvider", "textDocument/typeDefinition"),
        ("implementationProvider", "textDocument/implementation"),
        ("declarationProvider", "textDocument/declaration"),
        (
            "documentHighlightProvider",
            "textDocument/documentHighlight",
        ),
        (
            "documentRangeFormattingProvider",
            "textDocument/rangeFormatting",
        ),
        (
            "documentOnTypeFormattingProvider",
            "textDocument/onTypeFormatting",
        ),
        ("foldingRangeProvider", "textDocument/foldingRange"),
        ("selectionRangeProvider", "textDocument/selectionRange"),
        ("inlayHintProvider", "textDocument/inlayHint"),
        ("codeLensProvider", "textDocument/codeLens"),
        ("documentLinkProvider", "textDocument/documentLink"),
        ("callHierarchyProvider", "textDocument/prepareCallHierarchy"),
    ];

    /// **`initialize` advertises exactly what is implemented**, in both
    /// directions: every capability it lists has a request arm that answers
    /// (not `method not found`), every capability key is one this test knows,
    /// and every request it does not answer is absent. A capability claimed
    /// and not delivered is worse than one absent: the client stops offering
    /// its own fallback.
    ///
    /// Red run (2026-10-10): `definitionProvider` advertised with the
    /// `textDocument/definition` arm removed — `definitionProvider is
    /// advertised and textDocument/definition answers method not found`.
    #[test]
    fn initialize_advertises_only_what_is_implemented() {
        let Response::Reply(r) = handle(&req(1, "initialize", json!({}))) else {
            panic!("expected a reply");
        };
        let caps = r["result"]["capabilities"]
            .as_object()
            .expect("capabilities");
        let mut known: Vec<&str> = ADVERTISED.iter().map(|(c, _)| *c).collect();
        known.push("textDocumentSync");
        for key in caps.keys() {
            assert!(
                known.contains(&key.as_str()),
                "`{key}` is advertised and nothing here says it is implemented"
            );
        }
        let answers = |method: &str| {
            let mut s = Server::new();
            open(&mut s, "file:///caps.b", PROGRAM);
            let params = json!({
                "textDocument": { "uri": "file:///caps.b" },
                "position": { "line": 0, "character": 5 },
                "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
                "context": { "includeDeclaration": true, "diagnostics": [] },
                "newName": "plus",
                "query": "",
            });
            match s.handle_value(&req(2, method, params)) {
                Response::Reply(r) => r["error"]["code"] != json!(-32601),
                _ => false,
            }
        };
        for (cap, method) in ADVERTISED {
            assert!(
                caps.contains_key(*cap),
                "`{cap}` is implemented and not advertised"
            );
            assert!(
                answers(method),
                "{cap} is advertised and {method} answers method not found"
            );
        }
        for (cap, method) in NOT_IMPLEMENTED {
            assert!(
                !caps.contains_key(*cap),
                "`{cap}` is advertised and not implemented"
            );
            assert!(
                !answers(method),
                "{method} answers and `{cap}` is not advertised"
            );
        }
        assert_eq!(
            caps["codeActionProvider"]["codeActionKinds"],
            json!(["quickfix", "source.fixAll"])
        );
        assert_eq!(caps["renameProvider"]["prepareProvider"], json!(true));
    }

    const TYPO: &str = "def f(xs)\n  lenght(xs)\nend\n\ndef g(x, y)\n  x\nend\n";

    /// **A published diagnostic carries its registry code**, and its help
    /// line. Red run (2026-09-29): `diagnostic_json` without the `code`
    /// insert — `left: Null, right: String("B0001")`.
    #[test]
    fn diagnostics_carry_their_code() {
        let mut s = Server::new();
        let r = open(&mut s, "file:///t.b", TYPO);
        let d = diagnostics_of(&r);
        let items = d["params"]["diagnostics"].as_array().expect("array");
        assert_eq!(items.len(), 2, "{items:?}");
        assert_eq!(items[0]["code"], json!("B0001"));
        assert_eq!(items[0]["severity"], json!(1));
        assert!(
            items[0]["message"]
                .as_str()
                .is_some_and(|m| m.contains("help: did you mean `length` (builtin)?")),
            "{}",
            items[0]["message"]
        );
        assert_eq!(items[1]["code"], json!("B0002"));
        assert_eq!(items[1]["severity"], json!(2), "unused is a warning");
    }

    /// **A code action applies the check stage's fix.** The suggestion is
    /// offered and not preferred; the machine-applicable rename is preferred.
    /// Red run (2026-09-29): the `codeAction` arm removed — the request falls
    /// to `method not found`, and `r["result"]` is `Null`.
    #[test]
    fn code_actions_offer_the_fixes() {
        let mut s = Server::new();
        open(&mut s, "file:///t.b", TYPO);
        let whole =
            json!({ "start": { "line": 0, "character": 0 }, "end": { "line": 9, "character": 0 } });
        let Response::Reply(r) = s.handle_value(&req(
            7,
            "textDocument/codeAction",
            json!({ "textDocument": { "uri": "file:///t.b" }, "range": whole, "context": { "diagnostics": [], "only": ["quickfix"] } }),
        )) else {
            panic!("expected a reply");
        };
        let actions = r["result"].as_array().expect("an array of actions");
        let titles: Vec<(&str, bool)> = actions
            .iter()
            .map(|a| {
                (
                    a["title"].as_str().unwrap_or(""),
                    a["isPreferred"] == json!(true),
                )
            })
            .collect();
        assert_eq!(
            titles,
            vec![
                ("replace with `length` (builtin)", false),
                ("rename to `_y`", true)
            ]
        );
        let edit = &actions[0]["edit"]["changes"]["file:///t.b"][0];
        assert_eq!(edit["newText"], json!("length"));
        assert_eq!(edit["range"]["start"], json!({ "line": 1, "character": 2 }));
        assert_eq!(edit["range"]["end"], json!({ "line": 1, "character": 8 }));
    }

    /// **Completion is the check stage's name table**, prefix-filtered, each
    /// item naming its namespace.
    #[test]
    fn completion_offers_names_in_scope() {
        let mut s = Server::new();
        let text = "def lengthy(x)\n  x\nend\n\nlen\n";
        open(&mut s, "file:///c.b", text);
        let Response::Reply(r) = s.handle_value(&req(
            8,
            "textDocument/completion",
            json!({ "textDocument": { "uri": "file:///c.b" }, "position": { "line": 4, "character": 3 } }),
        )) else {
            panic!("expected a reply");
        };
        let items = r["result"]["items"].as_array().expect("items");
        let got: Vec<(&str, &str)> = items
            .iter()
            .map(|i| {
                (
                    i["label"].as_str().unwrap_or(""),
                    i["detail"].as_str().unwrap_or(""),
                )
            })
            .collect();
        assert!(got.contains(&("lengthy", "this file")), "{got:?}");
        assert!(got.contains(&("length", "builtin")), "{got:?}");
        assert!(got.iter().all(|(l, _)| l.starts_with("len")), "{got:?}");
    }

    #[test]
    fn initialize_advertises_semantic_tokens_with_a_derived_legend() {
        let Response::Reply(r) = handle(&req(1, "initialize", json!({}))) else {
            panic!("expected a reply");
        };
        let provider = &r["result"]["capabilities"]["semanticTokensProvider"];

        assert_eq!(provider["full"], json!(true));
        // `range` is not implemented, so it is not claimed.
        assert!(provider.get("range").is_none());

        // The legend must BE the enum's order. A client resolves a token's
        // type by indexing this array, so a legend that disagrees with
        // `SemanticTokenType::index()` paints every token as the wrong thing
        // while looking entirely well-formed on the wire.
        let types: Vec<&str> = provider["legend"]["tokenTypes"]
            .as_array()
            .expect("tokenTypes")
            .iter()
            .map(|v| v.as_str().expect("a string"))
            .collect();
        assert_eq!(types, tokens::legend_types());
        for ty in tokens::SemanticTokenType::ALL {
            assert_eq!(types[ty.index() as usize], ty.lsp_name());
        }

        let mods: Vec<&str> = provider["legend"]["tokenModifiers"]
            .as_array()
            .expect("tokenModifiers")
            .iter()
            .map(|v| v.as_str().expect("a string"))
            .collect();
        assert_eq!(mods, tokens::legend_modifiers());
    }

    #[test]
    fn semantic_tokens_full_paints_an_open_document() {
        let mut s = Server::new();
        s.handle_value(&req(
            0,
            "textDocument/didOpen",
            json!({ "textDocument": { "uri": "file:///a.b", "text": "def add(a, b)\n  a + b\nend\n" } }),
        ));

        let Response::Reply(r) = s.handle_value(&req(
            1,
            "textDocument/semanticTokens/full",
            json!({ "textDocument": { "uri": "file:///a.b" } }),
        )) else {
            panic!("expected a reply");
        };

        let data: Vec<u32> = r["result"]["data"]
            .as_array()
            .expect("data")
            .iter()
            .map(|v| v.as_u64().expect("a u32") as u32)
            .collect();

        assert!(!data.is_empty());
        assert_eq!(data.len() % 5, 0, "five integers per token");

        // First token is `def` at 0:0, length 3, a keyword, no modifiers.
        assert_eq!(
            data[..5],
            [0, 0, 3, tokens::SemanticTokenType::Keyword.index(), 0]
        );
        // Second is `add` — same line, delta 4 — a function DECLARATION.
        assert_eq!(
            data[5..10],
            [
                0,
                4,
                3,
                tokens::SemanticTokenType::Function.index(),
                tokens::SemanticTokenModifier::Declaration.bit(),
            ]
        );

        // And it agrees with the analysis core, so the shim really is a shim.
        assert_eq!(
            data,
            tokens::encode(&tokens::semantic_tokens("def add(a, b)\n  a + b\nend\n"))
        );
    }

    #[test]
    fn semantic_tokens_for_an_unopened_document_is_null_not_empty() {
        // Empty `data` claims "this buffer has no colour" and gets cached.
        let Response::Reply(r) = Server::new().handle_value(&req(
            1,
            "textDocument/semanticTokens/full",
            json!({ "textDocument": { "uri": "file:///never-opened.b" } }),
        )) else {
            panic!("expected a reply");
        };
        assert_eq!(r["result"], Value::Null);
    }

    /// **Full sync only, and advertised as such.** Advertising incremental and
    /// then applying only the last change silently desynchronises the buffer.
    #[test]
    fn sync_is_advertised_as_full_because_that_is_what_is_implemented() {
        let Response::Reply(r) = handle(&req(1, "initialize", json!({}))) else {
            panic!()
        };
        assert_eq!(r["result"]["capabilities"]["textDocumentSync"], json!(1));
    }

    #[test]
    fn a_reply_carries_the_requests_id() {
        let Response::Reply(r) = handle(&req(42, "initialize", json!({}))) else {
            panic!()
        };
        assert_eq!(r["id"], json!(42));
        assert_eq!(r["jsonrpc"], json!("2.0"));
    }

    #[test]
    fn opening_a_document_pushes_diagnostics() {
        let mut s = Server::new();
        let n = diagnostics_of(&open(&mut s, "file:///a.b", "def add("));
        assert_eq!(n["method"], json!("textDocument/publishDiagnostics"));
        let diags = n["params"]["diagnostics"].as_array().expect("array");
        assert_eq!(diags.len(), 1);
        assert_eq!(diags[0]["source"], json!("parse"));
        assert_eq!(diags[0]["severity"], json!(Severity::Error as i64));
    }

    /// A clean document pushes an EMPTY list, not nothing. Pushing nothing
    /// leaves the previous squiggles on screen after the author fixes the file.
    #[test]
    fn a_clean_document_pushes_an_empty_diagnostic_list() {
        let mut s = Server::new();
        let n = diagnostics_of(&open(&mut s, "file:///a.b", PROGRAM));
        assert_eq!(n["params"]["diagnostics"], json!([]));
    }

    /// Closing clears them, for the same reason.
    #[test]
    fn closing_a_document_clears_its_diagnostics() {
        let mut s = Server::new();
        open(&mut s, "file:///a.b", "def add(");
        let Response::Notify(n) = s.handle_value(&json!({
            "jsonrpc": "2.0",
            "method": "textDocument/didClose",
            "params": { "textDocument": { "uri": "file:///a.b" } },
        })) else {
            panic!("expected a clearing push")
        };
        assert_eq!(n["params"]["diagnostics"], json!([]));
        assert!(s.document("file:///a.b").is_none(), "and forgets the text");
    }

    #[test]
    fn a_change_replaces_the_document_and_re_publishes() {
        let mut s = Server::new();
        open(&mut s, "file:///a.b", "def add(");
        let n = diagnostics_of(&s.handle_value(&json!({
            "jsonrpc": "2.0",
            "method": "textDocument/didChange",
            "params": {
                "textDocument": { "uri": "file:///a.b" },
                "contentChanges": [{ "text": PROGRAM }],
            },
        })));
        assert_eq!(
            n["params"]["diagnostics"],
            json!([]),
            "the fixed document must clear its errors"
        );
        assert_eq!(s.document("file:///a.b").as_deref(), Some(PROGRAM));
    }

    #[test]
    fn formatting_returns_a_whole_document_edit() {
        let mut s = Server::new();
        open(&mut s, "file:///a.b", "1   +   2");
        let Response::Reply(r) = s.handle_value(&req(
            7,
            "textDocument/formatting",
            json!({ "textDocument": { "uri": "file:///a.b" } }),
        )) else {
            panic!()
        };
        let edits = r["result"].as_array().expect("edits");
        assert_eq!(edits.len(), 1);
        assert_eq!(edits[0]["newText"].as_str().unwrap().trim(), "1 + 2");
    }

    /// **An unformattable document returns `null`, not an empty edit list.** An
    /// empty list means "already canonical", which is a different and false
    /// claim.
    #[test]
    fn formatting_an_unparseable_document_returns_null_not_an_empty_edit() {
        let mut s = Server::new();
        open(&mut s, "file:///a.b", "def add(");
        let Response::Reply(r) = s.handle_value(&req(
            8,
            "textDocument/formatting",
            json!({ "textDocument": { "uri": "file:///a.b" } }),
        )) else {
            panic!()
        };
        assert_eq!(r["result"], Value::Null);
    }

    #[test]
    fn hover_returns_the_signature() {
        let mut s = Server::new();
        open(&mut s, "file:///a.b", PROGRAM);
        let Response::Reply(r) = s.handle_value(&req(
            9,
            "textDocument/hover",
            json!({
                "textDocument": { "uri": "file:///a.b" },
                "position": { "line": 0, "character": 5 },
            }),
        )) else {
            panic!()
        };
        let value = r["result"]["contents"]["value"].as_str().expect("markdown");
        assert!(
            value.contains("def add(a: Int, b: Int) -> Int"),
            "got {value}"
        );
        assert!(value.starts_with("```blue"), "fenced as blue: {value}");
    }

    #[test]
    fn hover_on_a_document_the_server_does_not_have_is_null() {
        let mut s = Server::new();
        let Response::Reply(r) = s.handle_value(&req(
            10,
            "textDocument/hover",
            json!({
                "textDocument": { "uri": "file:///missing.b" },
                "position": { "line": 0, "character": 0 },
            }),
        )) else {
            panic!()
        };
        assert_eq!(r["result"], Value::Null);
    }

    /// **An unknown request is an error; an unknown notification is silence.**
    /// Replying to a notification is a protocol violation some clients treat as
    /// fatal.
    #[test]
    fn an_unknown_request_errors_and_an_unknown_notification_is_silent() {
        let Response::Reply(r) = handle(&req(11, "textDocument/typeDefinition", json!({}))) else {
            panic!("a request must get an error reply")
        };
        assert_eq!(r["error"]["code"], json!(-32601));

        assert_eq!(
            handle(&json!({ "jsonrpc": "2.0", "method": "$/setTrace", "params": {} })),
            Response::None,
            "a notification must get no reply at all"
        );
    }

    #[test]
    fn shutdown_is_acknowledged_and_recorded() {
        let mut s = Server::new();
        let Response::Reply(r) = s.handle_value(&req(12, "shutdown", json!({}))) else {
            panic!()
        };
        assert_eq!(r["result"], Value::Null);
        assert!(s.is_shutting_down());
    }

    // ---- the shift reading, where an author actually sees it -----------

    /// **Every hover carries the reading.** A custom request only helps a
    /// client that knows to ask; hover works in every editor today, which is
    /// what makes the shift always-visible rather than opt-in.
    #[test]
    fn hover_carries_the_shift_reading() {
        let mut s = Server::new();
        open(&mut s, "file:///a.b", PROGRAM);
        let Response::Reply(r) = s.handle_value(&req(
            20,
            "textDocument/hover",
            json!({
                "textDocument": { "uri": "file:///a.b" },
                "position": { "line": 0, "character": 5 },
            }),
        )) else {
            panic!()
        };
        let md = r["result"]["contents"]["value"].as_str().expect("markdown");
        assert!(md.contains("def add("), "the signature: {md}");
        assert!(md.contains("checked"), "and the rung: {md}");
        assert!(md.contains("nodes analysed"), "and its cost: {md}");
    }

    /// And it names what is HOLDING IT BACK, which is the actionable half.
    #[test]
    fn hover_names_what_is_holding_the_shift_back() {
        let mut s = Server::new();
        open(
            &mut s,
            "file:///a.b",
            "def typed(a: Int) -> Int\n  a\nend\ndef loose(x)\n  x\nend",
        );
        let Response::Reply(r) = s.handle_value(&req(
            21,
            "textDocument/hover",
            json!({
                "textDocument": { "uri": "file:///a.b" },
                "position": { "line": 0, "character": 5 },
            }),
        )) else {
            panic!()
        };
        let md = r["result"]["contents"]["value"].as_str().expect("markdown");
        assert!(md.contains("annotated"), "the mixed rung: {md}");
        assert!(md.contains("loose"), "must name the untyped decl: {md}");
    }

    /// **The reading is PUSHED on every edit**, so it tracks the author as they
    /// type rather than when they remember to ask.
    #[test]
    fn every_edit_pushes_a_shift_reading() {
        let mut s = Server::new();
        let opened = open(&mut s, "file:///a.b", PROGRAM);
        let Response::Messages(all) = &opened else {
            panic!("didOpen must push more than diagnostics: {opened:?}")
        };
        let shift = all
            .iter()
            .find(|m| m["method"] == json!("blue/shift"))
            .expect("a blue/shift push");
        assert_eq!(shift["params"]["rung"], json!("checked"));
        assert_eq!(shift["params"]["uri"], json!("file:///a.b"));
    }

    /// The custom request answers on demand, with every factor located.
    #[test]
    fn the_shift_request_returns_located_factors() {
        let mut s = Server::new();
        open(
            &mut s,
            "file:///a.b",
            "def typed(a: Int) -> Int\n  a\nend\ndef loose(x)\n  x\nend",
        );
        let Response::Reply(r) = s.handle_value(&req(
            22,
            "blue/shift",
            json!({ "textDocument": { "uri": "file:///a.b" } }),
        )) else {
            panic!()
        };
        let res = &r["result"];
        assert_eq!(res["rung"], json!("annotated"));
        assert_eq!(res["typedDeclarations"], json!(1));
        assert_eq!(res["totalDeclarations"], json!(2));
        let factors = res["factors"].as_array().expect("factors");
        assert!(!factors.is_empty());
        for f in factors {
            assert!(f["range"].is_object(), "every factor must be LOCATED: {f}");
            assert!(f["detail"].as_str().is_some_and(|d| !d.is_empty()));
        }
        assert!(
            factors
                .iter()
                .any(|f| f["shiftsForward"] == json!(false) && f["subject"] == json!("loose")),
            "must mark what holds it back: {factors:?}"
        );
    }

    /// Anti-vacuity: the pushed rung MOVES with the document. A constant would
    /// satisfy the assertions above.
    #[test]
    fn the_pushed_reading_moves_with_the_document() {
        let mut s = Server::new();
        let loose = open(&mut s, "file:///a.b", "def f(x)\n  x\nend");
        let tight = open(&mut s, "file:///b.b", PROGRAM);
        let rung = |r: &Response| match r {
            Response::Messages(all) => all
                .iter()
                .find(|m| m["method"] == json!("blue/shift"))
                .map(|m| m["params"]["rung"].clone())
                .expect("shift"),
            other => panic!("{other:?}"),
        };
        assert_eq!(rung(&loose), json!("dynamic"));
        assert_eq!(rung(&tight), json!("checked"));
    }

    // ---- framing --------------------------------------------------------

    fn framed(body: &str) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(format!("Content-Length: {}\r\n\r\n", body.len()).as_bytes());
        out.extend_from_slice(body.as_bytes());
        out
    }

    #[test]
    fn the_stdio_loop_frames_a_reply() {
        let mut input = framed(r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#);
        input.extend_from_slice(&framed(r#"{"jsonrpc":"2.0","id":2,"method":"shutdown"}"#));
        let mut out = Vec::new();
        Server::new()
            .serve(std::io::BufReader::new(&input[..]), &mut out)
            .expect("serve");
        let text = String::from_utf8(out).expect("utf8");
        assert!(text.starts_with("Content-Length: "), "must frame: {text}");
        assert!(text.contains("\r\n\r\n"), "header/body separator: {text}");
        assert!(text.contains("blue-lsp"), "the initialize reply: {text}");
    }

    /// **A message with no `Content-Length` stops the loop rather than being
    /// guessed at.** Guessing a length desynchronises the stream for every
    /// message after it, which surfaces as the server appearing to hang.
    #[test]
    fn an_unframed_message_does_not_desynchronise_the_stream() {
        let input = b"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}\n";
        let mut out = Vec::new();
        Server::new()
            .serve(std::io::BufReader::new(&input[..]), &mut out)
            .expect("serve must not error");
        assert!(
            out.is_empty(),
            "nothing should be replied to an unframed message"
        );
    }

    #[test]
    fn the_loop_ends_at_eof() {
        let mut out = Vec::new();
        Server::new()
            .serve(std::io::BufReader::new(&b""[..]), &mut out)
            .expect("clean EOF");
        assert!(out.is_empty());
    }
}
