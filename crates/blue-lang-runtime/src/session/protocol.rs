//! `blue serve`: a [`Session`] spoken as JSON lines, one request per line in,
//! one response per line out (`theory/BLUE-TOOLING.md` §4).
//!
//! Requests run in order on one evaluation thread, so a session's state
//! changes one request at a time. `interrupt` is the exception: the reading
//! thread answers it at once, so it reaches an evaluation that is running —
//! or one still queued, which then answers `interrupted` without running.

use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};

use serde_json::{json, Map, Value as Json};

use super::{Config, Item, Load, Outcome, Session, Step, Stop};

/// Which requests are waiting and which one runs.
#[derive(Default)]
struct Queue {
    running: Option<Json>,
    waiting: Vec<Json>,
    cancelled: Vec<Json>,
}

/// Serve `config`'s session over `input` and `output` until `input` ends.
///
/// # Errors
///
/// Reading `input` failed.
pub fn serve<W: Write + Send + 'static>(
    config: Config,
    input: impl BufRead,
    output: W,
) -> std::io::Result<()> {
    let out = Arc::new(Mutex::new(output));
    let queue = Arc::new(Mutex::new(Queue::default()));
    let flag = Arc::clone(&config.interrupt);
    let (send, recv) = mpsc::channel::<(Json, Map<String, Json>)>();

    let worker = {
        let out = Arc::clone(&out);
        let queue = Arc::clone(&queue);
        let flag = Arc::clone(&flag);
        std::thread::spawn(move || {
            let mut session = Session::new(config);
            for (id, request) in recv {
                let cancelled = {
                    let mut q = lock(&queue);
                    q.waiting.retain(|w| *w != id);
                    let at = q.cancelled.iter().position(|c| *c == id);
                    if at.is_none() {
                        q.running = Some(id.clone());
                        flag.store(false, Ordering::SeqCst);
                    }
                    at.map(|i| q.cancelled.remove(i))
                };
                let reply = if cancelled.is_some() {
                    status::<()>(&Err(Stop::Interrupted))
                } else {
                    let reply = handle(&mut session, &request);
                    let mut q = lock(&queue);
                    q.running = None;
                    flag.store(false, Ordering::SeqCst);
                    reply
                };
                write(&out, &id, reply);
            }
        })
    };

    for line in input.lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        let request = match serde_json::from_str::<Json>(&line) {
            Ok(Json::Object(m)) => m,
            Ok(_) | Err(_) => {
                write(
                    &out,
                    &Json::Null,
                    failure("bad-request", "a request is one JSON object per line"),
                );
                continue;
            }
        };
        let id = request.get("id").cloned().unwrap_or(Json::Null);
        if request.get("op").and_then(Json::as_str) == Some("interrupt") {
            let reply = interrupt(&queue, &flag, request.get("target"));
            write(&out, &id, reply);
            continue;
        }
        lock(&queue).waiting.push(id.clone());
        if send.send((id, request)).is_err() {
            break;
        }
    }
    drop(send);
    let _ = worker.join();
    Ok(())
}

fn interrupt(queue: &Mutex<Queue>, flag: &AtomicBool, target: Option<&Json>) -> Map<String, Json> {
    let Some(target) = target else {
        return failure(
            "bad-request",
            "`interrupt` needs a `target`: the id to halt",
        );
    };
    let mut q = lock(queue);
    if q.running.as_ref() == Some(target) {
        flag.store(true, Ordering::SeqCst);
    } else if q.waiting.contains(target) {
        q.cancelled.push(target.clone());
    } else {
        return failure(
            "no-such-request",
            format!("no request with id {target} is running or waiting"),
        );
    }
    ok()
}

fn handle(session: &mut Session, request: &Map<String, Json>) -> Map<String, Json> {
    let text = |k: &str| request.get(k).and_then(Json::as_str);
    let file = text("file").map(PathBuf::from);
    let file = file.as_deref();
    match text("op") {
        Some("eval") => {
            let Some(code) = text("code") else {
                return failure("bad-request", "`eval` needs `code`");
            };
            let budget = request
                .get("budget")
                .and_then(Json::as_u64)
                .and_then(|b| usize::try_from(b).ok());
            reply(session.eval(code, file, budget), "value", Json::from)
        }
        Some("load") => match file {
            Some(f) => reply(
                session.load(f, text("code"), Load::Whole),
                "defined",
                Json::from,
            ),
            None => failure("bad-request", "`load` needs `file`"),
        },
        Some("expand") => {
            let Some(code) = text("code") else {
                return failure("bad-request", "`expand` needs `code`");
            };
            let step = match text("step") {
                Some("one") => Step::One,
                Some("all") | None => Step::All,
                Some(other) => {
                    return failure(
                        "bad-request",
                        format!("`step` is `one` or `all`, not `{other}`"),
                    )
                }
            };
            reply(session.expand(code, file, step), "form", Json::from)
        }
        Some("complete") => {
            let items: Vec<Json> = session
                .complete(text("prefix").unwrap_or_default(), file)
                .into_iter()
                .map(item)
                .collect();
            let mut m = ok();
            m.insert("items".into(), Json::from(items));
            m
        }
        Some("doc") => match text("name") {
            Some(name) => match session.doc(name, file) {
                Some(found) => {
                    let mut m = ok();
                    if let Json::Object(fields) = item(found) {
                        m.extend(fields);
                    }
                    m
                }
                None => failure("not-found", format!("nothing named `{name}` here")),
            },
            None => failure("bad-request", "`doc` needs `name`"),
        },
        Some("reset") => {
            session.reset();
            ok()
        }
        Some(other) => failure(
            "unknown-op",
            format!(
                "no op `{other}`; the ops are eval, load, expand, complete, doc, interrupt, reset"
            ),
        ),
        None => failure("bad-request", "a request needs `op`"),
    }
}

fn reply<T>(outcome: Outcome<T>, field: &str, to_json: impl Fn(T) -> Json) -> Map<String, Json> {
    let Outcome { result, out } = outcome;
    let (mut m, value) = match result {
        Ok(v) => (ok(), Some(to_json(v))),
        Err(stop) => (status(&Err::<(), _>(stop)), None),
    };
    if let Some(v) = value {
        m.insert(field.into(), v);
    }
    m.insert("out".into(), Json::from(out));
    m
}

/// The status fields of a result: `status`, and what a stop carries.
fn status<T>(result: &Result<T, Stop>) -> Map<String, Json> {
    match result {
        Ok(_) => ok(),
        Err(Stop::Error(f)) => failure(&f.code, &f.message),
        Err(Stop::Volatile { reach, name }) => object(json!({
            "status": "volatile",
            "reach": reach.label(),
            "name": name,
        })),
        Err(Stop::Exhausted { limit }) => object(json!({"status": "exhausted", "limit": limit})),
        Err(Stop::Interrupted) => object(json!({"status": "interrupted"})),
    }
}

fn item(i: Item) -> Json {
    json!({
        "name": i.name,
        "namespace": i.namespace,
        "signature": i.signature,
        "doc": i.doc,
    })
}

fn ok() -> Map<String, Json> {
    object(json!({"status": "ok"}))
}

fn failure(code: &str, message: impl Into<String>) -> Map<String, Json> {
    object(json!({
        "status": "error",
        "error": {"code": code, "message": message.into()},
    }))
}

fn object(v: Json) -> Map<String, Json> {
    match v {
        Json::Object(m) => m,
        _ => Map::new(),
    }
}

fn write<W: Write>(out: &Mutex<W>, id: &Json, fields: Map<String, Json>) {
    let mut line = Map::new();
    line.insert("id".into(), id.clone());
    line.extend(fields);
    let mut w = lock(out);
    let _ = serde_json::to_writer(&mut *w, &Json::Object(line));
    let _ = w.write_all(b"\n").and_then(|()| w.flush());
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}
