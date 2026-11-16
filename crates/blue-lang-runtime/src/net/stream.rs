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

/// The wire a [`Conn`] reads: a TCP stream, or a serial port opened by
/// `serial_open` (a USB CDC-ACM modem in raw mode). One Conn type, so
/// every word — `tcp_read`, `tcp_write`, `tcp_close`, `net_wait` — drives
/// a serial port unchanged.
pub enum Stream {
    Tcp(TcpStream),
    #[cfg(unix)]
    Serial(std::fs::File),
}

impl std::io::Read for &Stream {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match **self {
            Stream::Tcp(ref s) => {
                let mut shared = s;
                std::io::Read::read(&mut shared, buf)
            }
            #[cfg(unix)]
            Stream::Serial(ref f) => {
                let mut shared = f;
                std::io::Read::read(&mut shared, buf)
            }
        }
    }
}

impl std::io::Write for &Stream {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        match **self {
            Stream::Tcp(ref s) => {
                let mut shared = s;
                std::io::Write::write(&mut shared, buf)
            }
            #[cfg(unix)]
            Stream::Serial(ref f) => {
                let mut shared = f;
                std::io::Write::write(&mut shared, buf)
            }
        }
    }
    fn flush(&mut self) -> std::io::Result<()> {
        match **self {
            Stream::Tcp(ref s) => {
                let mut shared = s;
                std::io::Write::flush(&mut shared)
            }
            #[cfg(unix)]
            Stream::Serial(ref f) => {
                let mut shared = f;
                std::io::Write::flush(&mut shared)
            }
        }
    }
}

impl std::io::Read for Stream {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match self {
            Stream::Tcp(s) => s.read(buf),
            #[cfg(unix)]
            Stream::Serial(f) => f.read(buf),
        }
    }
}

impl std::io::Write for Stream {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        match self {
            Stream::Tcp(s) => s.write(buf),
            #[cfg(unix)]
            Stream::Serial(f) => f.write(buf),
        }
    }
    fn flush(&mut self) -> std::io::Result<()> {
        match self {
            Stream::Tcp(s) => s.flush(),
            #[cfg(unix)]
            Stream::Serial(f) => f.flush(),
        }
    }
}

pub struct Conn {
    socket: Stream,
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
        match &self.socket {
            Stream::Tcp(s) => s.as_fd(),
            #[cfg(unix)]
            Stream::Serial(f) => f.as_fd(),
        }
    }
}

#[cfg(not(unix))]
#[must_use]
pub fn fd_of(_: &Value) -> Option<blue_lang_proc::readiness::Pollable> {
    None
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
        socket: Stream::Tcp(socket),
        closed: AtomicBool::new(false),
    })))
}

/// Open a serial port in raw mode — `serial_open(path)`. On a USB
/// CDC-ACM device (/dev/cu.usbmodem*, the shape an MTK preloader and
/// BootROM enumerate as) the baud rate is carried by the USB side, so
/// the port is opened raw with no line discipline and no baud change.
/// The handle is a Conn: the tcp_* words and net_wait drive it.
#[cfg(unix)]
fn serial_open(path: &str, name: &'static str, span: Span) -> Result<Value, EvalError> {
    use std::fs::OpenOptions;
    use std::os::fd::AsRawFd;
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .open(path)
        .map_err(|e| fail(name, format!("{path}: {e}"), span))?;
    let fd = file.as_raw_fd();
    // Raw mode: no echo, no line buffering, no signals, no CR/LF cooking,
    // no flow control — the protocol on the wire is bytes and waits for
    // no one. CLOCAL keeps a missing carrier from blocking the open read.
    unsafe {
        let mut tio: libc::termios = std::mem::zeroed();
        if libc::tcgetattr(fd, &mut tio) != 0 {
            return Err(fail(name, format!("{path}: not a serial device"), span));
        }
        libc::cfmakeraw(&mut tio);
        // macOS termios has no B921600 constant; cfsetspeed takes the raw
        // rate and the CDC driver carries it to SET_LINE_CODING.
        libc::cfsetspeed(&mut tio, 921_600);
        tio.c_cflag |= libc::CLOCAL | libc::CREAD;
        tio.c_cc[libc::VMIN] = 0;
        tio.c_cc[libc::VTIME] = 0;
        if libc::tcsetattr(fd, libc::TCSANOW, &tio) != 0 {
            return Err(fail(name, format!("{path}: tcsetattr failed"), span));
        }
    }
    let _ = fd;
    Ok(Value::Foreign(Arc::new(Conn {
        socket: Stream::Serial(file),
        closed: AtomicBool::new(false),
    })))
}

/// One raw USB control transfer, device-to-host — `usb_control_in`. The
/// BootRom protocols speak SETUP packets a CDC serial channel cannot carry
/// (a class-IN request that reaches the ROM's own handler), so the net
/// surface holds the raw reach: the device is found by vendor and product
/// id, opened, and one IN control request is put to its default endpoint.
/// The `request_type` is the whole bmRequestType byte (0xA1 is class-IN to
/// an interface); the answer is the bytes the device returned.
fn usb_control_in(
    vid: u16,
    pid: u16,
    request_type: u8,
    request: u8,
    value: u16,
    index: u16,
    length: u16,
    timeout_ms: u64,
    name: &'static str,
    span: Span,
) -> Result<Value, EvalError> {
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (
            vid,
            pid,
            request_type,
            request,
            value,
            index,
            length,
            timeout_ms,
        );
        Err(fail(
            name,
            "usb_control_in is absent on this target (no USB host under wasm)",
            span,
        ))
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        usb_control_in_native(
            vid,
            pid,
            request_type,
            request,
            value,
            index,
            length,
            timeout_ms,
            name,
            span,
        )
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn usb_control_in_native(
    vid: u16,
    pid: u16,
    request_type: u8,
    request: u8,
    value: u16,
    index: u16,
    length: u16,
    timeout_ms: u64,
    name: &'static str,
    span: Span,
) -> Result<Value, EvalError> {
    use nusb::transfer::{Control, ControlType, Recipient};
    let control_type = match (request_type >> 5) & 0b11 {
        0 => ControlType::Standard,
        1 => ControlType::Class,
        _ => ControlType::Vendor,
    };
    let recipient = match request_type & 0b11 {
        0 => Recipient::Device,
        1 => Recipient::Interface,
        2 => Recipient::Endpoint,
        _ => Recipient::Other,
    };
    // A bus that cannot be listed is a bus with nothing on it: the same
    // answer as an empty one, never the enumerator's errno (a sandboxed
    // runner has no usbfs and its "No such file or directory" is not a
    // fact about the device we asked for).
    let found = match nusb::list_devices() {
        Ok(mut list) => list.find(|d| d.vendor_id() == vid && d.product_id() == pid),
        Err(_) => None,
    };
    let device = found
        .ok_or_else(|| {
            fail(
                name,
                format!("no USB device {:04x}:{:04x} is attached", vid, pid),
                span,
            )
        })?
        .open()
        .map_err(|e| fail(name, e, span))?;
    let mut buf = vec![0u8; length as usize];
    let n = device
        .control_in_blocking(
            Control {
                control_type,
                recipient,
                request,
                value,
                index,
            },
            &mut buf,
            std::time::Duration::from_millis(timeout_ms),
        )
        .map_err(|e| fail(name, e, span))?;
    buf.truncate(n);
    Ok(byte_list(&buf))
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
        |args: &[Value], _h: &mut H, span| {
            blue_lang_proc::net_args(fd_of, args, span)?;
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
        "serial_open",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            #[cfg(unix)]
            {
                let path = arg_str(&args[0], "serial_open", span)?;
                serial_open(path.as_ref(), "serial_open", span)
            }
            #[cfg(not(unix))]
            {
                let _ = &args;
                Err(fail(
                    "serial_open",
                    "this platform has no serial port surface",
                    span,
                ))
            }
        },
    );
    interp.register_fn(
        "usb_control_in",
        Arity::Exact(8),
        |args: &[Value], _h: &mut H, span| {
            let name: &'static str = "usb_control_in";
            let vid = u16::try_from(arg_int(&args[0], name, span)?)
                .map_err(|_| fail(name, "vid is 0 to 65535", span))?;
            let pid = u16::try_from(arg_int(&args[1], name, span)?)
                .map_err(|_| fail(name, "pid is 0 to 65535", span))?;
            let request_type = u8::try_from(arg_int(&args[2], name, span)?)
                .map_err(|_| fail(name, "request_type is 0 to 255", span))?;
            let request = u8::try_from(arg_int(&args[3], name, span)?)
                .map_err(|_| fail(name, "request is 0 to 255", span))?;
            let value = u16::try_from(arg_int(&args[4], name, span)?)
                .map_err(|_| fail(name, "value is 0 to 65535", span))?;
            let index = u16::try_from(arg_int(&args[5], name, span)?)
                .map_err(|_| fail(name, "index is 0 to 65535", span))?;
            let length = u16::try_from(arg_int(&args[6], name, span)?)
                .map_err(|_| fail(name, "length is 0 to 65535", span))?;
            let timeout_ms = u64::try_from(arg_int(&args[7], name, span)?)
                .map_err(|_| fail(name, "timeout_ms is a millisecond count", span))?;
            usb_control_in(
                vid,
                pid,
                request_type,
                request,
                value,
                index,
                length,
                timeout_ms,
                name,
                span,
            )
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
                    if let Stream::Tcp(s) = &c.socket {
                        let _ = s.shutdown(Shutdown::Both);
                    }
                }
                return Ok(Value::Nil);
            }
            let l = listener_of(&args[0], "tcp_close", span)?;
            l.closed.store(true, Ordering::Relaxed);
            Ok(Value::Nil)
        },
    );
}
