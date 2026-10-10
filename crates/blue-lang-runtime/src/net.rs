//! Host-side network primitives — NATS and HTTP, over std TCP.
//!
//! Installed by [`crate::sys::install_sys_stdlib`], so they are host imports
//! like every other sys name: absent from the wasm build, and granted to a
//! frame only through `Capability::Network`.
//!
//! ```text
//! nats_connect(url[, timeout_ms])             → connection
//! nats_publish(conn, subject, payload)        → nil
//! nats_request(conn, subject, payload, ms)    → the reply's payload
//! nats_subscribe(conn, subject[, queue])      → subscription
//! nats_next_message(sub, ms)                  → {subject:, payload:, reply:} or nil
//! nats_unsubscribe(sub)                       → nil
//! nats_close(conn)                            → nil
//! http_request(method, url, headers, body, ms) → {status:, headers:, body:}
//! ```
//!
//! A connection and a subscription are opaque `Value::Foreign` handles. Every
//! failure raises, naming the primitive; the one absence that is an answer is
//! `nats_next_message`'s nil when nothing arrived in time.

pub mod http;
pub mod nats;

use std::net::{TcpStream, ToSocketAddrs};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Map, MapKey, Value};

use crate::sys::{arg_int, arg_str};

const DEFAULT_CONNECT_MS: i64 = 5_000;

/// `host`, `host:port`, `[v6]` or `[v6]:port`.
pub fn split_host_port(s: &str, default_port: u16) -> Result<(String, u16), String> {
    let (host, port) = if let Some(rest) = s.strip_prefix('[') {
        let (h, after) = rest.split_once(']').ok_or("unclosed [ in host")?;
        (h, after.strip_prefix(':'))
    } else {
        match s.rsplit_once(':') {
            Some((h, p)) => (h, Some(p)),
            None => (s, None),
        }
    };
    if host.is_empty() {
        return Err("no host".into());
    }
    let port = match port {
        Some(p) => p.parse().map_err(|_| format!("bad port {p:?}"))?,
        None => default_port,
    };
    Ok((host.to_string(), port))
}

pub fn dial(host: &str, port: u16, timeout: Duration) -> Result<TcpStream, String> {
    let addrs: Vec<_> = (host, port)
        .to_socket_addrs()
        .map_err(|e| format!("{host}:{port}: {e}"))?
        .collect();
    let mut last = format!("{host}:{port}: no address");
    for addr in addrs {
        match TcpStream::connect_timeout(&addr, timeout) {
            Ok(s) => {
                let _ = s.set_nodelay(true);
                return Ok(s);
            }
            Err(e) => last = format!("{host}:{port}: {e}"),
        }
    }
    Err(last)
}

struct NatsConnection(Mutex<nats::Client>);

struct NatsSubscription {
    conn: Arc<NatsConnection>,
    sid: u64,
}

type Span = tatara_lisp::Span;

fn connection(
    v: &Value,
    fname: &'static str,
    span: Span,
) -> Result<Arc<NatsConnection>, EvalError> {
    if let Value::Foreign(any) = v {
        if let Ok(conn) = Arc::downcast::<NatsConnection>(any.clone()) {
            return Ok(conn);
        }
    }
    Err(EvalError::native_fn(
        fname,
        format!(
            "expected a NATS connection from nats_connect, got {}",
            v.type_name()
        ),
        span,
    ))
}

fn subscription(
    v: &Value,
    fname: &'static str,
    span: Span,
) -> Result<Arc<NatsSubscription>, EvalError> {
    if let Value::Foreign(any) = v {
        if let Ok(sub) = Arc::downcast::<NatsSubscription>(any.clone()) {
            return Ok(sub);
        }
    }
    Err(EvalError::native_fn(
        fname,
        format!(
            "expected a subscription from nats_subscribe, got {}",
            v.type_name()
        ),
        span,
    ))
}

fn with_client<T>(
    conn: &NatsConnection,
    fname: &'static str,
    span: Span,
    f: impl FnOnce(&mut nats::Client) -> Result<T, nats::NatsError>,
) -> Result<T, EvalError> {
    let mut client = conn
        .0
        .lock()
        .map_err(|_| EvalError::native_fn(fname, "the connection's lock is poisoned", span))?;
    f(&mut client).map_err(|e| EvalError::native_fn(fname, e.to_string(), span))
}

fn arg_ms(
    v: &Value,
    fname: &'static str,
    span: Span,
    zero_ok: bool,
) -> Result<Duration, EvalError> {
    let ms = arg_int(v, fname, span)?;
    if ms < 0 || (ms == 0 && !zero_ok) {
        return Err(EvalError::native_fn(
            fname,
            format!(
                "timeout must be {} milliseconds, got {ms}",
                if zero_ok { ">= 0" } else { "> 0" }
            ),
            span,
        ));
    }
    Ok(Duration::from_millis(ms as u64))
}

fn text(bytes: &[u8]) -> Value {
    Value::Str(Arc::from(String::from_utf8_lossy(bytes).as_ref()))
}

fn record(fields: Vec<(&str, Value)>) -> Value {
    let mut m = Map::new();
    for (k, v) in fields {
        m.insert(MapKey::Keyword(Arc::from(k)), v);
    }
    Value::Map(Arc::new(m))
}

fn header_text(v: &Value, fname: &'static str, span: Span) -> Result<String, EvalError> {
    match v {
        Value::Str(s) | Value::Keyword(s) | Value::Symbol(s) => Ok(s.to_string()),
        Value::Int(n) => Ok(n.to_string()),
        other => Err(EvalError::native_fn(
            fname,
            format!(
                "a header name or value must be a string, got {}",
                other.type_name()
            ),
            span,
        )),
    }
}

/// nil, a map, or a list of `[name, value]` pairs. A malformed entry raises
/// rather than being skipped: a dropped `Authorization` would send the
/// request unauthenticated.
fn headers_arg(
    v: &Value,
    fname: &'static str,
    span: Span,
) -> Result<Vec<(String, String)>, EvalError> {
    match v {
        Value::Nil => Ok(Vec::new()),
        Value::Map(m) => {
            let mut out = Vec::with_capacity(m.len());
            for (k, val) in m.iter() {
                let name = match k {
                    MapKey::Str(s) | MapKey::Keyword(s) | MapKey::Symbol(s) => s.to_string(),
                    other => {
                        return Err(EvalError::native_fn(
                            fname,
                            format!("a header name must be a string, got {other:?}"),
                            span,
                        ));
                    }
                };
                out.push((name, header_text(val, fname, span)?));
            }
            out.sort();
            Ok(out)
        }
        Value::List(items) => items
            .iter()
            .map(|it| match it {
                Value::List(kv) if kv.len() == 2 => Ok((
                    header_text(&kv[0], fname, span)?,
                    header_text(&kv[1], fname, span)?,
                )),
                _ => Err(EvalError::native_fn(
                    fname,
                    "each header must be a [name, value] pair",
                    span,
                )),
            })
            .collect(),
        other => Err(EvalError::native_fn(
            fname,
            format!(
                "headers must be nil, a map or [[name, value], …], got {}",
                other.type_name()
            ),
            span,
        )),
    }
}

pub fn install_net<H: 'static>(interp: &mut Interpreter<H>) {
    install_nats(interp);
    install_http(interp);
}

fn install_nats<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "nats_connect",
        Arity::Range(1, 2),
        |args: &[Value], _h: &mut H, span| {
            let url = arg_str(&args[0], "nats_connect", span)?;
            let timeout = match args.get(1) {
                Some(v) => arg_ms(v, "nats_connect", span, false)?,
                None => Duration::from_millis(DEFAULT_CONNECT_MS as u64),
            };
            let client = nats::Client::connect(&url, timeout)
                .map_err(|e| EvalError::native_fn("nats_connect", format!("{url}: {e}"), span))?;
            Ok(Value::Foreign(Arc::new(NatsConnection(Mutex::new(client)))))
        },
    );

    interp.register_fn(
        "nats_publish",
        Arity::Exact(3),
        |args: &[Value], _h: &mut H, span| {
            let conn = connection(&args[0], "nats_publish", span)?;
            let subject = arg_str(&args[1], "nats_publish", span)?;
            let payload = arg_str(&args[2], "nats_publish", span)?;
            with_client(&conn, "nats_publish", span, |c| {
                c.publish(&subject, None, payload.as_bytes())
            })?;
            Ok(Value::Nil)
        },
    );

    interp.register_fn(
        "nats_request",
        Arity::Exact(4),
        |args: &[Value], _h: &mut H, span| {
            let conn = connection(&args[0], "nats_request", span)?;
            let subject = arg_str(&args[1], "nats_request", span)?;
            let payload = arg_str(&args[2], "nats_request", span)?;
            let timeout = arg_ms(&args[3], "nats_request", span, false)?;
            let reply = with_client(&conn, "nats_request", span, |c| {
                c.request(&subject, payload.as_bytes(), timeout)
            })?;
            Ok(text(&reply.payload))
        },
    );

    interp.register_fn(
        "nats_subscribe",
        Arity::Range(2, 3),
        |args: &[Value], _h: &mut H, span| {
            let conn = connection(&args[0], "nats_subscribe", span)?;
            let subject = arg_str(&args[1], "nats_subscribe", span)?;
            let queue = match args.get(2) {
                Some(v) => Some(arg_str(v, "nats_subscribe", span)?),
                None => None,
            };
            let sid = with_client(&conn, "nats_subscribe", span, |c| {
                c.subscribe(&subject, queue.as_deref())
            })?;
            Ok(Value::Foreign(Arc::new(NatsSubscription { conn, sid })))
        },
    );

    interp.register_fn(
        "nats_next_message",
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| {
            let sub = subscription(&args[0], "nats_next_message", span)?;
            let timeout = arg_ms(&args[1], "nats_next_message", span, true)?;
            let next = with_client(&sub.conn, "nats_next_message", span, |c| {
                c.next_message(sub.sid, timeout)
            })?;
            Ok(next.map_or(Value::Nil, |m| {
                record(vec![
                    ("subject", Value::Str(Arc::from(m.subject))),
                    ("payload", text(&m.payload)),
                    (
                        "reply",
                        m.reply.map_or(Value::Nil, |r| Value::Str(Arc::from(r))),
                    ),
                ])
            }))
        },
    );

    interp.register_fn(
        "nats_unsubscribe",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let sub = subscription(&args[0], "nats_unsubscribe", span)?;
            with_client(&sub.conn, "nats_unsubscribe", span, |c| {
                c.unsubscribe(sub.sid)
            })?;
            Ok(Value::Nil)
        },
    );

    interp.register_fn(
        "nats_close",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let conn = connection(&args[0], "nats_close", span)?;
            with_client(&conn, "nats_close", span, |c| {
                c.close();
                Ok(())
            })?;
            Ok(Value::Nil)
        },
    );
}

fn install_http<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "http_request",
        Arity::Exact(5),
        |args: &[Value], _h: &mut H, span| {
            let method = arg_str(&args[0], "http_request", span)?;
            let url = arg_str(&args[1], "http_request", span)?;
            let headers = headers_arg(&args[2], "http_request", span)?;
            let body = match &args[3] {
                Value::Nil => None,
                other => Some(arg_str(other, "http_request", span)?),
            };
            let timeout = arg_ms(&args[4], "http_request", span, false)?;
            let resp = http::request(
                &method,
                &url,
                &headers,
                body.as_deref().map(str::as_bytes),
                timeout,
            )
            .map_err(|e| EvalError::native_fn("http_request", e.to_string(), span))?;
            Ok(record(vec![
                ("status", Value::Int(i64::from(resp.status))),
                (
                    "headers",
                    Value::list(
                        resp.headers
                            .into_iter()
                            .map(|(k, v)| {
                                Value::list(vec![
                                    Value::Str(Arc::from(k)),
                                    Value::Str(Arc::from(v)),
                                ])
                            })
                            .collect::<Vec<_>>(),
                    ),
                ),
                ("body", text(&resp.body)),
            ]))
        },
    );
}
