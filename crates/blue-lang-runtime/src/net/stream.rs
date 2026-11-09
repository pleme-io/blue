use std::io::{ErrorKind, Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use tatara_lisp::Span;
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::sys::{arg_int, arg_str};

pub struct Listener {
    socket: TcpListener,
    closed: AtomicBool,
}

pub struct Conn {
    socket: TcpStream,
    closed: AtomicBool,
}

#[cfg(unix)]
impl std::os::fd::AsFd for Listener {
    fn as_fd(&self) -> std::os::fd::BorrowedFd<'_> {
        self.socket.as_fd()
    }
}

#[cfg(unix)]
impl std::os::fd::AsFd for Conn {
    fn as_fd(&self) -> std::os::fd::BorrowedFd<'_> {
        self.socket.as_fd()
    }
}

#[cfg(unix)]
#[must_use]
pub fn fd_of(v: &Value) -> Option<blue_lang_proc::readiness::Pollable> {
    let Value::Foreign(any) = v else { return None };
    if let Ok(l) = Arc::downcast::<Listener>(any.clone()) {
        return (!l.closed.load(Ordering::Relaxed))
            .then(|| l as blue_lang_proc::readiness::Pollable);
    }
    if let Ok(c) = Arc::downcast::<Conn>(any.clone()) {
        return (!c.closed.load(Ordering::Relaxed))
            .then(|| c as blue_lang_proc::readiness::Pollable);
    }
    None
}

fn fail(name: &'static str, why: impl std::fmt::Display, span: Span) -> EvalError {
    EvalError::native_fn(name, why.to_string(), span)
}

fn listener_of(v: &Value, name: &'static str, span: Span) -> Result<Arc<Listener>, EvalError> {
    match v {
        Value::Foreign(any) => Arc::downcast::<Listener>(any.clone()).ok(),
        _ => None,
    }
    .ok_or_else(|| {
        fail(
            name,
            format!("expected a listener from tcp_listen, got {}", v.type_name()),
            span,
        )
    })
}

fn conn_of(v: &Value, name: &'static str, span: Span) -> Result<Arc<Conn>, EvalError> {
    match v {
        Value::Foreign(any) => Arc::downcast::<Conn>(any.clone()).ok(),
        _ => None,
    }
    .ok_or_else(|| {
        fail(
            name,
            format!(
                "expected a connection from tcp_connect or tcp_accept, got {}",
                v.type_name()
            ),
            span,
        )
    })
}

fn open(socket: TcpStream, name: &'static str, span: Span) -> Result<Value, EvalError> {
    socket
        .set_nonblocking(true)
        .map_err(|e| fail(name, e, span))?;
    let _ = socket.set_nodelay(true);
    Ok(Value::Foreign(Arc::new(Conn {
        socket,
        closed: AtomicBool::new(false),
    })))
}

fn bytes_of(v: &Value, name: &'static str, span: Span) -> Result<Vec<u8>, EvalError> {
    match v {
        Value::Str(s) => Ok(s.as_bytes().to_vec()),
        Value::List(items) => items
            .iter()
            .map(|b| match b {
                Value::Int(n) => u8::try_from(*n).ok(),
                _ => None,
            })
            .collect::<Option<Vec<u8>>>()
            .ok_or_else(|| fail(name, "bytes are a list of Ints 0 to 255", span)),
        other => Err(fail(
            name,
            format!(
                "bytes are a list of Ints or a string, got {}",
                other.type_name()
            ),
            span,
        )),
    }
}

fn byte_list(bytes: &[u8]) -> Value {
    Value::list(bytes.iter().map(|b| Value::Int(i64::from(*b))))
}

pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "net_wait",
        Arity::Range(1, 2),
        |_: &[Value], _h: &mut H, span| {
            Err(fail(
                "net_wait",
                "this interpreter runs no node with a readiness source, so nothing can wait here",
                span,
            ))
        },
    );
    interp.register_fn(
        "tcp_listen",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let addr = arg_str(&args[0], "tcp_listen", span)?;
            let socket =
                TcpListener::bind(addr.as_ref()).map_err(|e| fail("tcp_listen", e, span))?;
            socket
                .set_nonblocking(true)
                .map_err(|e| fail("tcp_listen", e, span))?;
            Ok(Value::Foreign(Arc::new(Listener {
                socket,
                closed: AtomicBool::new(false),
            })))
        },
    );
    interp.register_fn(
        "tcp_port",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let l = listener_of(&args[0], "tcp_port", span)?;
            let addr = l
                .socket
                .local_addr()
                .map_err(|e| fail("tcp_port", e, span))?;
            Ok(Value::Int(i64::from(addr.port())))
        },
    );
    interp.register_fn(
        "tcp_accept",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let l = listener_of(&args[0], "tcp_accept", span)?;
            match l.socket.accept() {
                Ok((socket, _)) => open(socket, "tcp_accept", span),
                Err(e) if e.kind() == ErrorKind::WouldBlock => Ok(Value::Nil),
                Err(e) => Err(fail("tcp_accept", e, span)),
            }
        },
    );
    interp.register_fn(
        "tcp_connect",
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| {
            let addr = arg_str(&args[0], "tcp_connect", span)?;
            let ms = arg_int(&args[1], "tcp_connect", span)?;
            let ms = u64::try_from(ms)
                .map_err(|_| fail("tcp_connect", "the timeout is milliseconds >= 0", span))?;
            let target = addr
                .as_ref()
                .to_socket_addrs()
                .map_err(|e| fail("tcp_connect", e, span))?
                .next()
                .ok_or_else(|| {
                    fail(
                        "tcp_connect",
                        format!("{addr} resolves to no address"),
                        span,
                    )
                })?;
            let socket = TcpStream::connect_timeout(&target, Duration::from_millis(ms.max(1)))
                .map_err(|e| fail("tcp_connect", e, span))?;
            open(socket, "tcp_connect", span)
        },
    );
    interp.register_fn(
        "tcp_read",
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| {
            let c = conn_of(&args[0], "tcp_read", span)?;
            let max = arg_int(&args[1], "tcp_read", span)?;
            let max = usize::try_from(max)
                .ok()
                .filter(|n| *n > 0)
                .ok_or_else(|| fail("tcp_read", "max is a count > 0", span))?;
            if c.closed.load(Ordering::Relaxed) {
                return Ok(Value::Nil);
            }
            let mut buf = vec![0u8; max.min(1 << 20)];
            match (&c.socket).read(&mut buf) {
                Ok(0) => Ok(Value::Nil),
                Ok(n) => Ok(byte_list(&buf[..n])),
                Err(e) if e.kind() == ErrorKind::WouldBlock => Ok(Value::list(Vec::<Value>::new())),
                Err(e) if e.kind() == ErrorKind::ConnectionReset => Ok(Value::Nil),
                Err(e) => Err(fail("tcp_read", e, span)),
            }
        },
    );
    interp.register_fn(
        "tcp_write",
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| {
            let c = conn_of(&args[0], "tcp_write", span)?;
            let bytes = bytes_of(&args[1], "tcp_write", span)?;
            if c.closed.load(Ordering::Relaxed) {
                return Err(fail("tcp_write", "the connection is closed", span));
            }
            match (&c.socket).write(&bytes) {
                Ok(n) => Ok(Value::Int(i64::try_from(n).unwrap_or(i64::MAX))),
                Err(e) if e.kind() == ErrorKind::WouldBlock => Ok(Value::Int(0)),
                Err(e) => Err(fail("tcp_write", e, span)),
            }
        },
    );
    interp.register_fn(
        "tcp_close",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            if let Ok(c) = conn_of(&args[0], "tcp_close", span) {
                if !c.closed.swap(true, Ordering::Relaxed) {
                    let _ = c.socket.shutdown(Shutdown::Both);
                }
                return Ok(Value::Nil);
            }
            let l = listener_of(&args[0], "tcp_close", span)?;
            l.closed.store(true, Ordering::Relaxed);
            Ok(Value::Nil)
        },
    );
}
