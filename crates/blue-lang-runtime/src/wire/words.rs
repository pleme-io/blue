//! The interpreter words of the wire — the host half behind the `sys`
//! feature. The frames, the Flash bucket and the transports are the pure
//! module beside this one; what lives here are the `flash_*`/`tide_*`
//! words, the loopback provider and the Nomad carrier, which bind those
//! shapes to an interpreter and its host imports.

use std::net::{SocketAddr, ToSocketAddrs};
use std::sync::Arc;

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, MapKey, Value};

use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::Duration;

use super::*;

pub struct WireHandle(Mutex<Option<Wire>>);

fn locked(h: &WireHandle) -> MutexGuard<'_, Option<Wire>> {
    h.0.lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

#[must_use]
pub fn host_clock() -> super::ClockRead {
    Arc::new(crate::sys::wall_ms)
}

use crate::net::{arg_ms, record};
use crate::provide::Key;
use crate::sys::{arg_int, arg_str};

type Span = tatara_lisp::Span;

#[derive(Clone)]
enum Transport {
    Host,
    Loopback(Arc<LoopbackNet>),
}

fn peer_of(text: &str, loopback: bool) -> Result<SocketAddr, String> {
    if let Ok(addr) = text.parse::<SocketAddr>() {
        return Ok(addr);
    }
    if loopback {
        return Err(format!(
            "{text} is not an ip:port; a loopback link resolves no name"
        ));
    }
    text.to_socket_addrs()
        .ok()
        .and_then(|mut addrs| addrs.next())
        .ok_or_else(|| format!("{text} is not a host:port this host resolves"))
}

impl Transport {
    fn peer(&self, v: &Value, fname: &'static str, span: Span) -> Result<SocketAddr, EvalError> {
        let text = arg_str(v, fname, span)?;
        peer_of(&text, matches!(self, Transport::Loopback(_)))
            .map_err(|why| EvalError::native_fn(fname, why, span))
    }

    fn bind(&self, addr: &str) -> Result<Wire, String> {
        match self {
            Transport::Host => Wire::bind(addr).map_err(|e| format!("{addr}: {e}")),
            Transport::Loopback(net) => {
                let at = addr.parse::<SocketAddr>().map_err(|_| {
                    format!("{addr} is not an ip:port; a loopback link resolves no name")
                })?;
                net.bind(at).map(Wire::on)
            }
        }
    }

    fn admits(&self, wire: &Wire) -> bool {
        match self {
            Transport::Host => true,
            Transport::Loopback(_) => wire.is_loopback(),
        }
    }
}

fn handle(v: &Value, fname: &'static str, span: Span) -> Result<Arc<WireHandle>, EvalError> {
    if let Value::Foreign(any) = v {
        if let Ok(h) = Arc::downcast::<WireHandle>(any.clone()) {
            return Ok(h);
        }
    }
    Err(EvalError::native_fn(
        fname,
        format!(
            "expected a wire from flash_open or tide_open, got {}",
            v.type_name()
        ),
        span,
    ))
}

fn native(fname: &'static str, span: Span) -> impl Fn(String) -> EvalError {
    move |e| EvalError::native_fn(fname, e, span)
}

fn host_socket(fname: &'static str, span: Span) -> EvalError {
    EvalError::native_fn(
        fname,
        "this wire is a host socket, and this channel is provided by the loopback, which reaches no socket",
        span,
    )
}

fn with_channel<T>(
    v: &Value,
    channel: Channel,
    transport: &Transport,
    fname: &'static str,
    span: Span,
    f: impl FnOnce(&mut Wire) -> Result<T, EvalError>,
) -> Result<T, EvalError> {
    let h = handle(v, fname, span)?;
    let mut guard = locked(&h);
    let wire = guard
        .as_mut()
        .filter(|w| w.is_open(channel))
        .ok_or_else(|| {
            EvalError::native_fn(
                fname,
                format!("this wire's {} channel is not open", channel.name()),
                span,
            )
        })?;
    if !transport.admits(wire) {
        return Err(host_socket(fname, span));
    }
    f(wire)
}

fn bounded(v: &Value, fname: &'static str, span: Span) -> Result<usize, EvalError> {
    let n = arg_int(v, fname, span)?;
    usize::try_from(n).map_err(|_| {
        EvalError::native_fn(fname, format!("a byte count is 0 or more, got {n}"), span)
    })
}

fn ring_opts(
    v: Option<&Value>,
    fname: &'static str,
    span: Span,
) -> Result<(usize, usize), EvalError> {
    let Some(Value::Map(m)) = v else {
        return match v {
            None | Some(Value::Nil) => Ok((RING_FRAMES, RING_BYTES)),
            Some(other) => Err(EvalError::native_fn(
                fname,
                format!(
                    "options are a map of ring_frames: and ring_bytes:, got {}",
                    other.type_name()
                ),
                span,
            )),
        };
    };
    let mut frames = RING_FRAMES;
    let mut bytes = RING_BYTES;
    for (k, val) in m.iter() {
        let key = match k {
            MapKey::Keyword(s) | MapKey::Str(s) | MapKey::Symbol(s) => s.to_string(),
            other => {
                return Err(EvalError::native_fn(
                    fname,
                    format!("an option is named by a keyword, got {other:?}"),
                    span,
                ))
            }
        };
        let n = arg_int(val, fname, span)?;
        match key.trim_start_matches(':') {
            "ring_frames" if usize::try_from(n).is_ok_and(|n| n >= 1) => {
                frames = usize::try_from(n).unwrap_or(usize::MAX);
            }
            "ring_bytes" if usize::try_from(n).is_ok_and(|n| n >= MTU) => {
                bytes = usize::try_from(n).unwrap_or(usize::MAX);
            }
            "ring_frames" => {
                return Err(EvalError::native_fn(
                    fname,
                    format!("ring_frames holds at least one frame, got {n}"),
                    span,
                ))
            }
            "ring_bytes" => {
                return Err(EvalError::native_fn(
                    fname,
                    format!("ring_bytes holds at least one {MTU}-byte frame, got {n}"),
                    span,
                ))
            }
            other => {
                return Err(EvalError::native_fn(
                    fname,
                    format!("{other} is no option; tide_open takes ring_frames: and ring_bytes:"),
                    span,
                ))
            }
        }
    }
    Ok((frames, bytes))
}

fn open(
    target: &Value,
    channel: Channel,
    ring: (usize, usize),
    transport: &Transport,
    fname: &'static str,
    span: Span,
) -> Result<Value, EvalError> {
    if let Value::Str(addr) = target {
        let mut wire = transport.bind(addr).map_err(native(fname, span))?;
        wire.open(channel, ring);
        return Ok(Value::Foreign(Arc::new(WireHandle(Mutex::new(Some(wire))))));
    }
    let h = handle(target, fname, span).map_err(|_| {
        EvalError::native_fn(
            fname,
            format!(
                "expected an address to bind or a wire to join, got {}",
                target.type_name()
            ),
            span,
        )
    })?;
    {
        let mut guard = locked(&h);
        let wire = guard
            .as_mut()
            .ok_or_else(|| EvalError::native_fn(fname, "this wire is closed", span))?;
        if wire.is_open(channel) {
            return Err(EvalError::native_fn(
                fname,
                format!("this wire's {} channel is already open", channel.name()),
                span,
            ));
        }
        if !transport.admits(wire) {
            return Err(host_socket(fname, span));
        }
        wire.open(channel, ring);
    }
    Ok(target.clone())
}

fn close(v: &Value, channel: Channel, fname: &'static str, span: Span) -> Result<Value, EvalError> {
    let h = handle(v, fname, span)?;
    let mut guard = locked(&h);
    if let Some(wire) = guard.as_mut() {
        if !wire.close(channel) {
            *guard = None;
        }
    }
    Ok(Value::Nil)
}

fn int(n: impl TryInto<i64>) -> Value {
    Value::Int(n.try_into().unwrap_or(i64::MAX))
}

fn text(s: impl Into<String>) -> Value {
    Value::Str(Arc::from(s.into()))
}

fn received(r: Option<Received>) -> Value {
    r.map_or(Value::Nil, |r| {
        let mut fields = vec![
            ("from", text(r.from.to_string())),
            ("payload", text(r.payload)),
            ("bytes", int(r.bytes)),
        ];
        if let Some(stamp) = r.stamp_ms {
            fields.push(("sent_ms", Value::Int(stamp)));
        }
        record(fields)
    })
}

fn rate_limited(refusal: RateRefusal, span: Span) -> EvalError {
    crate::errors::raise_kind_with(
        RATE_LIMITED,
        refusal.to_string(),
        record(vec![
            ("bytes", int(refusal.bytes)),
            ("rate", int(refusal.rate)),
            ("burst", int(refusal.burst)),
            ("wait_ms", refusal.wait_ms.map_or(Value::Nil, int)),
        ]),
        span,
    )
}

fn next(
    args: &[Value],
    channel: Channel,
    transport: &Transport,
    fname: &'static str,
    span: Span,
) -> Result<Value, EvalError> {
    let timeout = arg_ms(&args[1], fname, span, true)?;
    with_channel(&args[0], channel, transport, fname, span, |w| {
        w.next(channel, timeout)
            .map_err(|e| native(fname, span)(e.to_string()))
    })
    .map(received)
}

fn stats(
    v: &Value,
    channel: Channel,
    transport: &Transport,
    fname: &'static str,
    span: Span,
) -> Result<Value, EvalError> {
    with_channel(v, channel, transport, fname, span, |w| {
        let address = w
            .address()
            .map_err(|e| native(fname, span)(e.to_string()))?;
        let c = w.counts(channel);
        let mut fields = vec![
            ("address", text(address.to_string())),
            ("port", int(address.port())),
            ("sent", int(c.sent)),
            ("received", int(c.received)),
            ("dropped", int(c.dropped)),
            ("malformed", int(w.malformed())),
        ];
        match channel {
            Channel::Flash => fields.extend([
                ("refused", int(c.refused)),
                ("rate", int(w.flash_bucket().rate())),
            ]),
            Channel::Tide => {
                let (queued, queued_bytes) = w.queued();
                let (evicted_out, evicted_in) = w.evicted();
                let (ring_frames, ring_bytes) = w.tide_out.bounds();
                fields.extend([
                    ("queued", int(queued)),
                    ("queued_bytes", int(queued_bytes)),
                    ("evicted", int(evicted_out)),
                    ("evicted_in", int(evicted_in)),
                    ("ring_frames", int(ring_frames)),
                    ("ring_bytes", int(ring_bytes)),
                ]);
            }
        }
        Ok(record(fields))
    })
}

fn carried<T>(
    wire: &Value,
    loopback: bool,
    f: impl FnOnce(&mut Wire) -> Result<T, String>,
) -> Result<T, String> {
    let Value::Foreign(any) = wire else {
        return Err(format!(
            "expected a wire from tide_open, got {}",
            wire.type_name()
        ));
    };
    let h = Arc::downcast::<WireHandle>(any.clone())
        .map_err(|_| "expected a wire from tide_open, got another handle".to_string())?;
    let mut guard = locked(&h);
    let w = guard
        .as_mut()
        .filter(|w| w.is_open(Channel::Tide))
        .ok_or_else(|| "this wire's Tide channel is not open".to_string())?;
    if loopback && !w.is_loopback() {
        return Err(
            "this wire is a host socket, and this channel is provided by the loopback, which reaches no socket"
                .to_string(),
        );
    }
    f(w)
}

fn carry_queue(
    wire: &Value,
    peer: &Value,
    frames: &[String],
    loopback: bool,
) -> Result<usize, String> {
    let Value::Str(text) = peer else {
        return Err(format!("the peer is a host:port, got {}", peer.type_name()));
    };
    carried(wire, loopback, |w| {
        let to = peer_of(text, w.is_loopback())?;
        w.tide_queue_all(to, frames)
    })
}

fn carry_take(
    wire: &Value,
    prefix: &str,
    timeout: Duration,
    loopback: bool,
) -> Result<Vec<String>, String> {
    carried(wire, loopback, |w| {
        w.tide_take(prefix, timeout)
            .map(|got| got.into_iter().map(|r| r.payload).collect())
            .map_err(|e| e.to_string())
    })
}

pub const CARRIER: blue_lang_proc::Carrier = blue_lang_proc::Carrier {
    room: Channel::Tide.room(),
    queue: carry_queue,
    take: carry_take,
};

pub fn install_wire<H: 'static>(interp: &mut Interpreter<H>) {
    install_flash(interp, String::from, &Transport::Host, host_clock());
    install_tide(interp, String::from, &Transport::Host);
}

pub fn host_flash_on<H: 'static>(interp: &mut Interpreter<H>, clock: ClockRead) {
    install_flash(interp, String::from, &Transport::Host, clock);
}

pub fn provide_loopback<H: 'static>(
    interp: &mut Interpreter<H>,
    key: Key,
    channel: blue_lang_waku::Channel,
    net: &Arc<LoopbackNet>,
    clock: ClockRead,
) {
    let transport = Transport::Loopback(Arc::clone(net));
    match channel {
        blue_lang_waku::Channel::Flash => install_flash(interp, key, &transport, clock),
        blue_lang_waku::Channel::Tide => install_tide(interp, key, &transport),
    }
}

fn install_flash<H: 'static>(
    interp: &mut Interpreter<H>,
    key: Key,
    transport: &Transport,
    clock: ClockRead,
) {
    let t = transport.clone();
    interp.register_fn(
        key("flash_open"),
        Arity::Exact(1),
        move |args: &[Value], _h: &mut H, span| {
            open(
                &args[0],
                Channel::Flash,
                (RING_FRAMES, RING_BYTES),
                &t,
                "flash_open",
                span,
            )
        },
    );
    let t = transport.clone();
    interp.register_fn(
        key("flash_put"),
        Arity::Exact(3),
        move |args: &[Value], _h: &mut H, span| {
            let peer = t.peer(&args[1], "flash_put", span)?;
            let payload = arg_str(&args[2], "flash_put", span)?;
            with_channel(&args[0], Channel::Flash, &t, "flash_put", span, |w| {
                w.flash_put(peer, payload.as_bytes(), clock())
                    .map_err(|e| match e {
                        SendError::Rate(refusal) => rate_limited(refusal, span),
                        SendError::Frame(why) => native("flash_put", span)(why),
                    })
            })
            .map(int)
        },
    );
    let t = transport.clone();
    interp.register_fn(
        key("flash_next"),
        Arity::Exact(2),
        move |args: &[Value], _h: &mut H, span| next(args, Channel::Flash, &t, "flash_next", span),
    );
    let t = transport.clone();
    interp.register_fn(
        key("flash_stats"),
        Arity::Exact(1),
        move |args: &[Value], _h: &mut H, span| {
            stats(&args[0], Channel::Flash, &t, "flash_stats", span)
        },
    );
    interp.register_fn(
        key("flash_close"),
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| close(&args[0], Channel::Flash, "flash_close", span),
    );
}

fn install_tide<H: 'static>(interp: &mut Interpreter<H>, key: Key, transport: &Transport) {
    let t = transport.clone();
    interp.register_fn(
        key("tide_open"),
        Arity::Range(1, 2),
        move |args: &[Value], _h: &mut H, span| {
            let ring = ring_opts(args.get(1), "tide_open", span)?;
            open(&args[0], Channel::Tide, ring, &t, "tide_open", span)
        },
    );
    let t = transport.clone();
    interp.register_fn(
        key("tide_put"),
        Arity::Exact(3),
        move |args: &[Value], _h: &mut H, span| {
            let peer = t.peer(&args[1], "tide_put", span)?;
            let payload = arg_str(&args[2], "tide_put", span)?;
            with_channel(&args[0], Channel::Tide, &t, "tide_put", span, |w| {
                w.tide_put(peer, payload.as_bytes())
                    .map_err(native("tide_put", span))
            })
            .map(int)
        },
    );
    let t = transport.clone();
    interp.register_fn(
        key("tide_release"),
        Arity::Exact(3),
        move |args: &[Value], _h: &mut H, span| {
            let room = bounded(&args[1], "tide_release", span)?;
            let stamp = arg_int(&args[2], "tide_release", span)?;
            with_channel(&args[0], Channel::Tide, &t, "tide_release", span, |w| {
                w.tide_release(room, stamp)
                    .map_err(native("tide_release", span))
            })
            .map(int)
        },
    );
    let t = transport.clone();
    interp.register_fn(
        key("tide_send"),
        Arity::Exact(4),
        move |args: &[Value], _h: &mut H, span| {
            let peer = t.peer(&args[1], "tide_send", span)?;
            let payload = arg_str(&args[2], "tide_send", span)?;
            let stamp = arg_int(&args[3], "tide_send", span)?;
            with_channel(&args[0], Channel::Tide, &t, "tide_send", span, |w| {
                w.tide_send(peer, payload.as_bytes(), stamp)
                    .map_err(native("tide_send", span))
            })
            .map(int)
        },
    );
    let t = transport.clone();
    interp.register_fn(
        key("tide_next"),
        Arity::Exact(2),
        move |args: &[Value], _h: &mut H, span| next(args, Channel::Tide, &t, "tide_next", span),
    );
    let t = transport.clone();
    interp.register_fn(
        key("tide_stats"),
        Arity::Exact(1),
        move |args: &[Value], _h: &mut H, span| {
            stats(&args[0], Channel::Tide, &t, "tide_stats", span)
        },
    );
    interp.register_fn(
        key("tide_close"),
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| close(&args[0], Channel::Tide, "tide_close", span),
    );
}
