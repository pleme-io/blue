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
//! tcp_connect_ms(host, port, ms)              → connect time in ms, or [:error, why, detail]
//! http_listen(addr)                           → listener
//! http_listener_port(listener)                → the bound port
//! http_next_request(listener, ms)             → {method:, path:, query:, headers:, body:, exchange:} or nil
//! http_respond(exchange, status, headers, body) → nil
//! pg_connect(url[, timeout_ms])               → connection
//! pg_query(conn, sql, params)                 → {columns:, rows:, command:}
//! pg_execute(conn, sql)                       → [command tag, …]
//! pg_close(conn)                              → nil
//! ```
//!
//! A connection and a subscription are opaque `Value::Foreign` handles. Every
//! failure raises, naming the primitive; the one absence that is an answer is
//! `nats_next_message`'s nil when nothing arrived in time.

pub mod http;
pub mod nats;
pub mod pg;
pub mod serve;

use std::net::{TcpStream, ToSocketAddrs};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DialFailure {
    Unresolved,
    Timeout,
    Refused,
    Unreachable,
    Failed,
}

impl DialFailure {
    pub fn keyword(self) -> &'static str {
        match self {
            DialFailure::Unresolved => "unresolved",
            DialFailure::Timeout => "timeout",
            DialFailure::Refused => "refused",
            DialFailure::Unreachable => "unreachable",
            DialFailure::Failed => "failed",
        }
    }

    fn of(e: &std::io::Error) -> Self {
        use std::io::ErrorKind;
        match e.kind() {
            ErrorKind::TimedOut | ErrorKind::WouldBlock => DialFailure::Timeout,
            ErrorKind::ConnectionRefused => DialFailure::Refused,
            ErrorKind::HostUnreachable
            | ErrorKind::NetworkUnreachable
            | ErrorKind::AddrNotAvailable
            | ErrorKind::NetworkDown => DialFailure::Unreachable,
            _ => DialFailure::Failed,
        }
    }
}

#[derive(Debug)]
pub struct Dialed {
    pub stream: TcpStream,
    pub elapsed: Duration,
}

pub fn dial_timed(
    host: &str,
    port: u16,
    timeout: Duration,
) -> Result<Dialed, (DialFailure, String)> {
    let addrs: Vec<_> = (host, port)
        .to_socket_addrs()
        .map_err(|e| (DialFailure::Unresolved, format!("{host}:{port}: {e}")))?
        .collect();
    let mut last = (
        DialFailure::Unresolved,
        format!("{host}:{port}: no address"),
    );
    let deadline = Instant::now() + timeout;
    for addr in addrs {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            last = (DialFailure::Timeout, format!("{host}:{port}: timed out"));
            break;
        }
        let start = Instant::now();
        match TcpStream::connect_timeout(&addr, left) {
            Ok(stream) => {
                let elapsed = start.elapsed();
                let _ = stream.set_nodelay(true);
                return Ok(Dialed { stream, elapsed });
            }
            Err(e) => last = (DialFailure::of(&e), format!("{host}:{port}: {e}")),
        }
    }
    Err(last)
}

pub fn dial(host: &str, port: u16, timeout: Duration) -> Result<TcpStream, String> {
    dial_timed(host, port, timeout)
        .map(|d| d.stream)
        .map_err(|(_, detail)| detail)
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
    install_tcp(interp);
    install_serve(interp);
    install_pg(interp);
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

fn install_tcp<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "tcp_connect_ms",
        Arity::Exact(3),
        |args: &[Value], _h: &mut H, span| {
            let host = arg_str(&args[0], "tcp_connect_ms", span)?;
            let port = arg_int(&args[1], "tcp_connect_ms", span)?;
            let port = u16::try_from(port)
                .ok()
                .filter(|p| *p != 0)
                .ok_or_else(|| {
                    EvalError::native_fn(
                        "tcp_connect_ms",
                        format!("port must be 1..=65535, got {port}"),
                        span,
                    )
                })?;
            let timeout = arg_ms(&args[2], "tcp_connect_ms", span, false)?;
            Ok(match dial_timed(&host, port, timeout) {
                Ok(d) => {
                    drop(d.stream);
                    Value::Int(i64::try_from(d.elapsed.as_millis()).unwrap_or(i64::MAX))
                }
                Err((why, detail)) => Value::list(vec![
                    Value::Keyword(Arc::from("error")),
                    Value::Keyword(Arc::from(why.keyword())),
                    Value::Str(Arc::from(detail)),
                ]),
            })
        },
    );
}

struct HttpListener(serve::Listener);

struct HttpExchange(Mutex<Option<TcpStream>>);

fn listener(v: &Value, fname: &'static str, span: Span) -> Result<Arc<HttpListener>, EvalError> {
    if let Value::Foreign(any) = v {
        if let Ok(l) = Arc::downcast::<HttpListener>(any.clone()) {
            return Ok(l);
        }
    }
    Err(EvalError::native_fn(
        fname,
        format!(
            "expected a listener from http_listen, got {}",
            v.type_name()
        ),
        span,
    ))
}

fn exchange(v: &Value, fname: &'static str, span: Span) -> Result<Arc<HttpExchange>, EvalError> {
    let inner = match v {
        Value::Map(m) => m.get(&MapKey::Keyword(Arc::from("exchange"))).cloned(),
        other => Some(other.clone()),
    };
    if let Some(Value::Foreign(any)) = inner {
        if let Ok(x) = Arc::downcast::<HttpExchange>(any) {
            return Ok(x);
        }
    }
    Err(EvalError::native_fn(
        fname,
        format!(
            "expected a request from http_next_request, got {}",
            v.type_name()
        ),
        span,
    ))
}

fn pairs(headers: Vec<(String, String)>) -> Value {
    Value::list(
        headers
            .into_iter()
            .map(|(k, v)| Value::list(vec![Value::Str(Arc::from(k)), Value::Str(Arc::from(v))]))
            .collect::<Vec<_>>(),
    )
}

fn install_serve<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "http_listen",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let addr = arg_str(&args[0], "http_listen", span)?;
            let l = serve::Listener::bind(&addr)
                .map_err(|e| EvalError::native_fn("http_listen", e.to_string(), span))?;
            Ok(Value::Foreign(Arc::new(HttpListener(l))))
        },
    );

    interp.register_fn(
        "http_listener_port",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let l = listener(&args[0], "http_listener_port", span)?;
            let addr =
                l.0.local_addr()
                    .map_err(|e| EvalError::native_fn("http_listener_port", e.to_string(), span))?;
            Ok(Value::Int(i64::from(addr.port())))
        },
    );

    interp.register_fn(
        "http_next_request",
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| {
            let l = listener(&args[0], "http_next_request", span)?;
            let timeout = arg_ms(&args[1], "http_next_request", span, true)?;
            let next =
                l.0.next(timeout)
                    .map_err(|e| EvalError::native_fn("http_next_request", e.to_string(), span))?;
            Ok(next.map_or(Value::Nil, |(req, stream)| {
                record(vec![
                    ("method", Value::Str(Arc::from(req.method))),
                    ("path", Value::Str(Arc::from(req.path))),
                    ("query", Value::Str(Arc::from(req.query))),
                    ("headers", pairs(req.headers)),
                    ("body", text(&req.body)),
                    (
                        "exchange",
                        Value::Foreign(Arc::new(HttpExchange(Mutex::new(Some(stream))))),
                    ),
                ])
            }))
        },
    );

    interp.register_fn(
        "http_respond",
        Arity::Exact(4),
        |args: &[Value], _h: &mut H, span| {
            let x = exchange(&args[0], "http_respond", span)?;
            let status = arg_int(&args[1], "http_respond", span)?;
            let status = u16::try_from(status).map_err(|_| {
                EvalError::native_fn("http_respond", format!("{status} is not a status"), span)
            })?;
            let headers = headers_arg(&args[2], "http_respond", span)?;
            let body = match &args[3] {
                Value::Nil => String::new(),
                other => arg_str(other, "http_respond", span)?.to_string(),
            };
            let stream = x
                .0
                .lock()
                .map_err(|_| {
                    EvalError::native_fn("http_respond", "the exchange's lock is poisoned", span)
                })?
                .take()
                .ok_or_else(|| {
                    EvalError::native_fn("http_respond", "this request was already answered", span)
                })?;
            serve::respond(&stream, status, &headers, body.as_bytes())
                .map_err(|e| EvalError::native_fn("http_respond", e.to_string(), span))?;
            Ok(Value::Nil)
        },
    );
}

struct PgConnection(Mutex<Option<pg::Conn>>);

fn pg_conn(v: &Value, fname: &'static str, span: Span) -> Result<Arc<PgConnection>, EvalError> {
    if let Value::Foreign(any) = v {
        if let Ok(c) = Arc::downcast::<PgConnection>(any.clone()) {
            return Ok(c);
        }
    }
    Err(EvalError::native_fn(
        fname,
        format!(
            "expected a Postgres connection from pg_connect, got {}",
            v.type_name()
        ),
        span,
    ))
}

fn with_pg<T>(
    conn: &PgConnection,
    fname: &'static str,
    span: Span,
    f: impl FnOnce(&mut pg::Conn) -> Result<T, pg::PgError>,
) -> Result<T, EvalError> {
    let mut guard = conn
        .0
        .lock()
        .map_err(|_| EvalError::native_fn(fname, "the connection's lock is poisoned", span))?;
    let c = guard
        .as_mut()
        .ok_or_else(|| EvalError::native_fn(fname, "the connection is closed", span))?;
    f(c).map_err(|e| EvalError::native_fn(fname, e.to_string(), span))
}

fn pg_param(v: &Value, span: Span) -> Result<pg::Param, EvalError> {
    Ok(match v {
        Value::Nil => pg::Param::Null,
        Value::Bool(b) => pg::Param::Text(if *b { "t" } else { "f" }.to_string()),
        Value::Int(n) => pg::Param::Text(n.to_string()),
        Value::Float(x) => pg::Param::Text(x.to_string()),
        Value::Str(s) | Value::Keyword(s) => pg::Param::Text(s.to_string()),
        other => {
            return Err(EvalError::native_fn(
                "pg_query",
                format!(
                    "a parameter is nil, true/false, a number or text, got {}",
                    other.type_name()
                ),
                span,
            ))
        }
    })
}

fn pg_cell(type_oid: i32, cell: pg::Cell) -> Value {
    match cell {
        pg::Cell::Null => Value::Nil,
        pg::Cell::Text(t) => match type_oid {
            16 => Value::Bool(t == "t"),
            20 | 21 | 23 | 26 => t
                .parse()
                .map_or(Value::Str(Arc::from(t.as_str())), Value::Int),
            700 | 701 => t
                .parse()
                .map_or(Value::Str(Arc::from(t.as_str())), Value::Float),
            _ => Value::Str(Arc::from(t)),
        },
    }
}

fn install_pg<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "pg_connect",
        Arity::Range(1, 2),
        |args: &[Value], _h: &mut H, span| {
            let url = arg_str(&args[0], "pg_connect", span)?;
            let timeout = match args.get(1) {
                Some(v) => arg_ms(v, "pg_connect", span, false)?,
                None => Duration::from_millis(DEFAULT_CONNECT_MS as u64),
            };
            let target = pg::parse_url(&url)
                .map_err(|e| EvalError::native_fn("pg_connect", e.to_string(), span))?;
            let conn = pg::Conn::connect(&target, timeout).map_err(|e| {
                EvalError::native_fn(
                    "pg_connect",
                    format!("{}:{}/{}: {e}", target.host, target.port, target.database),
                    span,
                )
            })?;
            Ok(Value::Foreign(Arc::new(PgConnection(Mutex::new(Some(
                conn,
            ))))))
        },
    );

    interp.register_fn(
        "pg_query",
        Arity::Exact(3),
        |args: &[Value], _h: &mut H, span| {
            let conn = pg_conn(&args[0], "pg_query", span)?;
            let sql = arg_str(&args[1], "pg_query", span)?;
            let params = match &args[2] {
                Value::Nil => Vec::new(),
                Value::List(xs) => xs
                    .iter()
                    .map(|v| pg_param(v, span))
                    .collect::<Result<Vec<_>, _>>()?,
                other => {
                    return Err(EvalError::native_fn(
                        "pg_query",
                        format!("params must be a list, got {}", other.type_name()),
                        span,
                    ))
                }
            };
            let out = with_pg(&conn, "pg_query", span, |c| c.query(&sql, &params))?;
            let names: Vec<Value> = out
                .columns
                .iter()
                .map(|c| Value::Str(Arc::from(c.name.as_str())))
                .collect();
            let rows: Vec<Value> = out
                .rows
                .into_iter()
                .map(|row| {
                    Value::map(out.columns.iter().zip(row).map(|(col, cell)| {
                        (
                            MapKey::Str(Arc::from(col.name.as_str())),
                            pg_cell(col.type_oid, cell),
                        )
                    }))
                })
                .collect();
            Ok(record(vec![
                ("columns", Value::list(names)),
                ("rows", Value::list(rows)),
                (
                    "command",
                    out.commands
                        .last()
                        .map_or(Value::Nil, |c| Value::Str(Arc::from(c.as_str()))),
                ),
            ]))
        },
    );

    interp.register_fn(
        "pg_execute",
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| {
            let conn = pg_conn(&args[0], "pg_execute", span)?;
            let sql = arg_str(&args[1], "pg_execute", span)?;
            let out = with_pg(&conn, "pg_execute", span, |c| c.execute(&sql))?;
            Ok(Value::list(
                out.commands
                    .into_iter()
                    .map(|c| Value::Str(Arc::from(c)))
                    .collect::<Vec<_>>(),
            ))
        },
    );

    interp.register_fn(
        "pg_close",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let conn = pg_conn(&args[0], "pg_close", span)?;
            let mut guard = conn.0.lock().map_err(|_| {
                EvalError::native_fn("pg_close", "the connection's lock is poisoned", span)
            })?;
            if let Some(mut c) = guard.take() {
                c.close();
            }
            Ok(Value::Nil)
        },
    );
}
