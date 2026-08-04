//! A real LSP session against the real `blue lsp` binary.
//!
//! `tests/cli.rs` checks that `lsp` appears in `--help`. That proves the
//! subcommand is *spelled*, not that an editor attaching to it gets anything —
//! and every other test of the server calls `Server::handle_value` in-process,
//! which cannot observe argument parsing, the stdio loop, or message framing.
//!
//! This file exists because the thing users actually run is a subprocess
//! speaking a framed protocol down a pipe. An editor's experience of blue is
//! entirely that subprocess. The measured lesson behind writing it: a config
//! or capability can be correct at every layer a unit test can see and still
//! never reach the consumer, so the last mile gets its own test against the
//! artifact that actually ships.

use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, Command, Stdio};

use serde_json::{json, Value};

const SOURCE: &str = "# a comment\ndef add(a, b)\n  a + b\nend\n";

/// Drive one whole session and return every message the server sent.
///
/// Every request is written up front and stdin is then closed. The server is
/// strictly sequential and its replies are small, so they fit the pipe buffer
/// and nothing deadlocks; `exit` makes it close stdout, which is what lets the
/// read below finish rather than block forever.
fn session(requests: &[Value]) -> Vec<Value> {
    let mut child: Child = Command::new(env!("CARGO_BIN_EXE_blue"))
        .arg("lsp")
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn `blue lsp`");

    {
        let stdin = child.stdin.as_mut().expect("stdin");
        for req in requests {
            let body = serde_json::to_vec(req).expect("encode");
            write!(stdin, "Content-Length: {}\r\n\r\n", body.len()).expect("write header");
            stdin.write_all(&body).expect("write body");
        }
        stdin.flush().expect("flush");
    }
    // Dropping stdin closes it — belt and braces alongside the `exit` above.
    drop(child.stdin.take());

    let mut out = Vec::new();
    child
        .stdout
        .as_mut()
        .expect("stdout")
        .read_to_end(&mut out)
        .expect("read stdout");

    let status = child.wait().expect("wait");
    let mut err = String::new();
    if let Some(mut e) = child.stderr.take() {
        let _ = e.read_to_string(&mut err);
    }
    assert!(
        status.success(),
        "`blue lsp` exited {status:?}; stderr: {err}"
    );

    decode_all(&out)
}

/// Split a stream of `Content-Length`-framed messages.
fn decode_all(bytes: &[u8]) -> Vec<Value> {
    let mut reader = BufReader::new(bytes);
    let mut messages = Vec::new();

    loop {
        let mut length: Option<usize> = None;
        loop {
            let mut line = String::new();
            match reader.read_line(&mut line) {
                Ok(0) => return messages, // EOF
                Ok(_) => {}
                Err(e) => panic!("read header: {e}"),
            }
            let trimmed = line.trim_end_matches(['\r', '\n']);
            if trimmed.is_empty() {
                break;
            }
            if let Some(rest) = trimmed.strip_prefix("Content-Length:") {
                length = rest.trim().parse().ok();
            }
        }
        let Some(length) = length else {
            return messages;
        };
        let mut buf = vec![0u8; length];
        reader.read_exact(&mut buf).expect("read body");
        messages.push(serde_json::from_slice(&buf).expect("decode body"));
    }
}

fn req(id: i64, method: &str, params: Value) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "method": method, "params": params })
}

fn notify(method: &str, params: Value) -> Value {
    json!({ "jsonrpc": "2.0", "method": method, "params": params })
}

fn reply_to<'a>(messages: &'a [Value], id: i64) -> &'a Value {
    messages
        .iter()
        .find(|m| m["id"] == json!(id))
        .unwrap_or_else(|| panic!("no reply with id {id}; got {messages:#?}"))
}

/// The whole point: attach, open a buffer, ask for colour, get it.
#[test]
fn a_real_session_returns_semantic_tokens_for_an_open_buffer() {
    let messages = session(&[
        req(1, "initialize", json!({})),
        notify("initialized", json!({})),
        notify(
            "textDocument/didOpen",
            json!({ "textDocument": { "uri": "file:///s.b", "text": SOURCE } }),
        ),
        req(
            2,
            "textDocument/semanticTokens/full",
            json!({ "textDocument": { "uri": "file:///s.b" } }),
        ),
        req(3, "shutdown", json!({})),
        notify("exit", json!({})),
    ]);

    // The capability has to survive the real `initialize`, not just a unit
    // test's direct call.
    let provider = &reply_to(&messages, 1)["result"]["capabilities"]["semanticTokensProvider"];
    assert_eq!(provider["full"], json!(true));
    let types = provider["legend"]["tokenTypes"]
        .as_array()
        .expect("a tokenTypes legend");
    assert!(
        types.contains(&json!("keyword")) && types.contains(&json!("function")),
        "legend looks wrong: {types:?}",
    );

    let data: Vec<u64> = reply_to(&messages, 2)["result"]["data"]
        .as_array()
        .expect("a data array")
        .iter()
        .map(|v| v.as_u64().expect("a non-negative integer"))
        .collect();

    assert!(!data.is_empty(), "an editor would paint nothing");
    assert_eq!(data.len() % 5, 0, "five integers per token");

    // Decode far enough to prove these are blue's tokens and not filler.
    // First token is the comment on line 0, column 0, `# a comment` = 11.
    let comment_index = types
        .iter()
        .position(|t| t == &json!("comment"))
        .expect("a comment type") as u64;
    assert_eq!(
        &data[..5],
        &[0, 0, 11, comment_index, 0],
        "expected the leading comment",
    );

    // `def` is a keyword on the next line, at column 0.
    let keyword_index = types
        .iter()
        .position(|t| t == &json!("keyword"))
        .expect("a keyword type") as u64;
    assert_eq!(&data[5..10], &[1, 0, 3, keyword_index, 0]);

    // Every token stays inside its line, which is the invariant the encoding
    // itself cannot express.
    let lines: Vec<&str> = SOURCE.lines().collect();
    let (mut line, mut start) = (0u64, 0u64);
    for tok in data.chunks(5) {
        let (dl, ds, len) = (tok[0], tok[1], tok[2]);
        line += dl;
        start = if dl == 0 { start + ds } else { ds };
        let width = lines[line as usize].chars().count() as u64;
        assert!(
            start + len <= width,
            "token at {line}:{start} (len {len}) runs past a {width}-wide line",
        );
    }
}

/// Diagnostics and colour are independent surfaces; a broken buffer must not
/// take the session down with it.
#[test]
fn a_buffer_that_does_not_parse_still_answers_a_token_request() {
    let messages = session(&[
        req(1, "initialize", json!({})),
        notify(
            "textDocument/didOpen",
            json!({ "textDocument": { "uri": "file:///bad.b", "text": "def (\n" } }),
        ),
        req(
            2,
            "textDocument/semanticTokens/full",
            json!({ "textDocument": { "uri": "file:///bad.b" } }),
        ),
        req(3, "shutdown", json!({})),
        notify("exit", json!({})),
    ]);

    // A reply, not a crash and not silence. Whether it carries tokens is
    // `tokens.rs`'s decision; that it *replies* is the protocol's.
    let result = &reply_to(&messages, 2)["result"];
    assert!(
        result.is_null() || result["data"].is_array(),
        "expected null or a data array, got {result}",
    );

    // And the server was still alive to answer shutdown afterwards.
    assert_eq!(reply_to(&messages, 3)["result"], Value::Null);
}
