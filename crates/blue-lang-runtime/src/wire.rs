use std::collections::VecDeque;
use std::io::ErrorKind;
use std::net::{SocketAddr, ToSocketAddrs, UdpSocket};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, MapKey, Value};

use crate::net::{arg_ms, record};
use crate::sys::{arg_int, arg_str};

pub const MTU: usize = 1280;
pub const TIDE_BYTE: u8 = 0x01;
pub const FLASH_BYTE: u8 = 0x02;
pub const STAMP_BYTES: usize = 8;
pub const FLASH_INBOX: usize = 256;
pub const RING_FRAMES: usize = 64;
pub const RING_BYTES: usize = 64 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Channel {
    Tide,
    Flash,
}

impl Channel {
    #[must_use]
    pub fn byte(self) -> u8 {
        match self {
            Channel::Tide => TIDE_BYTE,
            Channel::Flash => FLASH_BYTE,
        }
    }

    #[must_use]
    pub fn of(byte: u8) -> Option<Channel> {
        match byte {
            TIDE_BYTE => Some(Channel::Tide),
            FLASH_BYTE => Some(Channel::Flash),
            _ => None,
        }
    }

    #[must_use]
    pub fn header(self) -> usize {
        match self {
            Channel::Tide => 1 + STAMP_BYTES,
            Channel::Flash => 1,
        }
    }

    #[must_use]
    pub fn room(self) -> usize {
        MTU - self.header()
    }

    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Channel::Tide => "Tide",
            Channel::Flash => "Flash",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Frame {
    pub channel: Channel,
    pub stamp_ms: Option<i64>,
    pub payload: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum WireError {
    #[error("a {channel} frame is at most {MTU} bytes with its header; this payload of {payload} bytes makes {len}")]
    PastMtu {
        channel: &'static str,
        payload: usize,
        len: usize,
    },
    #[error("an empty datagram is no frame")]
    Empty,
    #[error("the framing byte {0:#04x} names no channel; 0x01 is Tide, 0x02 is Flash")]
    UnknownChannel(u8),
    #[error("a Tide frame carries an {STAMP_BYTES}-byte stamp after its framing byte; this datagram has {0} bytes")]
    ShortStamp(usize),
    #[error("a datagram of {0} bytes is past the {MTU}-byte MTU")]
    PastMtuReceived(usize),
}

pub fn encode(channel: Channel, stamp_ms: i64, payload: &[u8]) -> Result<Vec<u8>, WireError> {
    let len = channel.header() + payload.len();
    if len > MTU {
        return Err(WireError::PastMtu {
            channel: channel.name(),
            payload: payload.len(),
            len,
        });
    }
    let mut out = Vec::with_capacity(len);
    out.push(channel.byte());
    if channel == Channel::Tide {
        out.extend_from_slice(&stamp_ms.to_be_bytes());
    }
    out.extend_from_slice(payload);
    Ok(out)
}

pub fn decode(datagram: &[u8]) -> Result<Frame, WireError> {
    if datagram.len() > MTU {
        return Err(WireError::PastMtuReceived(datagram.len()));
    }
    let (&first, rest) = datagram.split_first().ok_or(WireError::Empty)?;
    let channel = Channel::of(first).ok_or(WireError::UnknownChannel(first))?;
    match channel {
        Channel::Flash => Ok(Frame {
            channel,
            stamp_ms: None,
            payload: rest.to_vec(),
        }),
        Channel::Tide => {
            if rest.len() < STAMP_BYTES {
                return Err(WireError::ShortStamp(datagram.len()));
            }
            let (stamp, payload) = rest.split_at(STAMP_BYTES);
            let mut be = [0u8; STAMP_BYTES];
            be.copy_from_slice(stamp);
            Ok(Frame {
                channel,
                stamp_ms: Some(i64::from_be_bytes(be)),
                payload: payload.to_vec(),
            })
        }
    }
}

#[derive(Clone, Debug)]
pub struct Ring<T> {
    items: VecDeque<(T, usize)>,
    bytes: usize,
    max_frames: usize,
    max_bytes: usize,
    evicted: u64,
}

impl<T> Ring<T> {
    #[must_use]
    pub fn new(max_frames: usize, max_bytes: usize) -> Self {
        Self {
            items: VecDeque::new(),
            bytes: 0,
            max_frames: max_frames.max(1),
            max_bytes: max_bytes.max(MTU),
            evicted: 0,
        }
    }

    pub fn push(&mut self, item: T, len: usize) -> usize {
        let mut evicted = 0;
        while !self.items.is_empty()
            && (self.items.len() >= self.max_frames || self.bytes + len > self.max_bytes)
        {
            self.pop();
            evicted += 1;
        }
        self.items.push_back((item, len));
        self.bytes += len;
        self.evicted += evicted as u64;
        evicted
    }

    pub fn pop(&mut self) -> Option<T> {
        self.items.pop_front().map(|(item, len)| {
            self.bytes -= len;
            item
        })
    }

    #[must_use]
    pub fn front_len(&self) -> Option<usize> {
        self.items.front().map(|(_, len)| *len)
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.items.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }

    #[must_use]
    pub fn bytes(&self) -> usize {
        self.bytes
    }

    #[must_use]
    pub fn evicted(&self) -> u64 {
        self.evicted
    }

    #[must_use]
    pub fn bounds(&self) -> (usize, usize) {
        (self.max_frames, self.max_bytes)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Received {
    pub from: SocketAddr,
    pub stamp_ms: Option<i64>,
    pub payload: String,
    pub bytes: usize,
}

#[derive(Clone, Debug)]
struct Outgoing {
    peer: SocketAddr,
    payload: Vec<u8>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Counts {
    pub sent: u64,
    pub received: u64,
    pub dropped: u64,
}

pub struct Wire {
    socket: UdpSocket,
    flash: bool,
    tide: bool,
    flash_in: VecDeque<Received>,
    tide_in: Ring<Received>,
    tide_out: Ring<Outgoing>,
    flash_counts: Counts,
    tide_counts: Counts,
    malformed: u64,
}

impl Wire {
    pub fn bind(addr: &str) -> std::io::Result<Self> {
        Ok(Self {
            socket: UdpSocket::bind(addr)?,
            flash: false,
            tide: false,
            flash_in: VecDeque::new(),
            tide_in: Ring::new(RING_FRAMES, RING_BYTES),
            tide_out: Ring::new(RING_FRAMES, RING_BYTES),
            flash_counts: Counts::default(),
            tide_counts: Counts::default(),
            malformed: 0,
        })
    }

    pub fn open(&mut self, channel: Channel, ring: (usize, usize)) {
        match channel {
            Channel::Flash => self.flash = true,
            Channel::Tide => {
                self.tide = true;
                self.tide_in = Ring::new(ring.0, ring.1);
                self.tide_out = Ring::new(ring.0, ring.1);
            }
        }
    }

    #[must_use]
    pub fn is_open(&self, channel: Channel) -> bool {
        match channel {
            Channel::Flash => self.flash,
            Channel::Tide => self.tide,
        }
    }

    pub fn close(&mut self, channel: Channel) -> bool {
        match channel {
            Channel::Flash => {
                self.flash = false;
                self.flash_in.clear();
            }
            Channel::Tide => {
                self.tide = false;
                self.tide_in = Ring::new(RING_FRAMES, RING_BYTES);
                self.tide_out = Ring::new(RING_FRAMES, RING_BYTES);
            }
        }
        self.flash || self.tide
    }

    pub fn address(&self) -> std::io::Result<SocketAddr> {
        self.socket.local_addr()
    }

    pub fn flash_put(&mut self, peer: SocketAddr, payload: &[u8]) -> Result<usize, String> {
        let datagram = encode(Channel::Flash, 0, payload).map_err(|e| e.to_string())?;
        self.transmit(Channel::Flash, peer, &datagram)
    }

    pub fn tide_put(&mut self, peer: SocketAddr, payload: &[u8]) -> Result<usize, String> {
        let len = encode(Channel::Tide, 0, payload)
            .map_err(|e| e.to_string())?
            .len();
        Ok(self.tide_out.push(
            Outgoing {
                peer,
                payload: payload.to_vec(),
            },
            len,
        ))
    }

    pub fn tide_release(&mut self, max_bytes: usize, stamp_ms: i64) -> Result<usize, String> {
        let mut sent = 0;
        while let Some(len) = self.tide_out.front_len() {
            if sent + len > max_bytes {
                break;
            }
            let Some(out) = self.tide_out.pop() else {
                break;
            };
            let datagram =
                encode(Channel::Tide, stamp_ms, &out.payload).map_err(|e| e.to_string())?;
            sent += self.transmit(Channel::Tide, out.peer, &datagram)?;
        }
        Ok(sent)
    }

    pub fn tide_send(
        &mut self,
        peer: SocketAddr,
        payload: &[u8],
        stamp_ms: i64,
    ) -> Result<usize, String> {
        let datagram = encode(Channel::Tide, stamp_ms, payload).map_err(|e| e.to_string())?;
        self.transmit(Channel::Tide, peer, &datagram)
    }

    fn transmit(
        &mut self,
        channel: Channel,
        peer: SocketAddr,
        datagram: &[u8],
    ) -> Result<usize, String> {
        let n = self
            .socket
            .send_to(datagram, peer)
            .map_err(|e| format!("{peer}: {e}"))?;
        match channel {
            Channel::Flash => self.flash_counts.sent += 1,
            Channel::Tide => self.tide_counts.sent += 1,
        }
        Ok(n)
    }

    fn file(&mut self, datagram: &[u8], from: SocketAddr) {
        let Ok(frame) = decode(datagram) else {
            self.malformed += 1;
            return;
        };
        let Ok(payload) = String::from_utf8(frame.payload) else {
            self.malformed += 1;
            return;
        };
        let received = Received {
            from,
            stamp_ms: frame.stamp_ms,
            payload,
            bytes: datagram.len(),
        };
        match frame.channel {
            Channel::Flash if self.flash && self.flash_in.len() < FLASH_INBOX => {
                self.flash_counts.received += 1;
                self.flash_in.push_back(received);
            }
            Channel::Flash => self.flash_counts.dropped += 1,
            Channel::Tide if self.tide => {
                self.tide_counts.received += 1;
                self.tide_in.push(received, datagram.len());
            }
            Channel::Tide => self.tide_counts.dropped += 1,
        }
    }

    fn waiting(&mut self, channel: Channel) -> Option<Received> {
        match channel {
            Channel::Flash => self.flash_in.pop_front(),
            Channel::Tide => self.tide_in.pop(),
        }
    }

    fn drain(&mut self) -> std::io::Result<()> {
        let mut buf = [0u8; MTU + 1];
        self.socket.set_nonblocking(true)?;
        let outcome = loop {
            match self.socket.recv_from(&mut buf) {
                Ok((n, from)) => self.file(&buf[..n], from),
                Err(e) if e.kind() == ErrorKind::WouldBlock => break Ok(()),
                Err(e) if e.kind() == ErrorKind::ConnectionRefused => {}
                Err(e) => break Err(e),
            }
        };
        self.socket.set_nonblocking(false)?;
        outcome
    }

    pub fn next(
        &mut self,
        channel: Channel,
        timeout: Duration,
    ) -> std::io::Result<Option<Received>> {
        let deadline = Instant::now() + timeout;
        let mut buf = [0u8; MTU + 1];
        loop {
            self.drain()?;
            if let Some(r) = self.waiting(channel) {
                return Ok(Some(r));
            }
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return Ok(None);
            }
            self.socket.set_read_timeout(Some(left))?;
            match self.socket.recv_from(&mut buf) {
                Ok((n, from)) => self.file(&buf[..n], from),
                Err(e)
                    if matches!(
                        e.kind(),
                        ErrorKind::WouldBlock | ErrorKind::TimedOut | ErrorKind::ConnectionRefused
                    ) => {}
                Err(e) => return Err(e),
            }
        }
    }

    #[must_use]
    pub fn counts(&self, channel: Channel) -> Counts {
        match channel {
            Channel::Flash => self.flash_counts,
            Channel::Tide => self.tide_counts,
        }
    }

    #[must_use]
    pub fn queued(&self) -> (usize, usize) {
        (self.tide_out.len(), self.tide_out.bytes())
    }

    #[must_use]
    pub fn evicted(&self) -> (u64, u64) {
        (self.tide_out.evicted(), self.tide_in.evicted())
    }

    #[must_use]
    pub fn malformed(&self) -> u64 {
        self.malformed
    }
}

pub struct WireHandle(Mutex<Option<Wire>>);

fn locked(h: &WireHandle) -> MutexGuard<'_, Option<Wire>> {
    h.0.lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

type Span = tatara_lisp::Span;

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

fn with_channel<T>(
    v: &Value,
    channel: Channel,
    fname: &'static str,
    span: Span,
    f: impl FnOnce(&mut Wire) -> Result<T, String>,
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
    f(wire).map_err(|e| EvalError::native_fn(fname, e, span))
}

fn peer_of(v: &Value, fname: &'static str, span: Span) -> Result<SocketAddr, EvalError> {
    let text = arg_str(v, fname, span)?;
    if let Ok(addr) = text.parse::<SocketAddr>() {
        return Ok(addr);
    }
    text.to_socket_addrs()
        .ok()
        .and_then(|mut addrs| addrs.next())
        .ok_or_else(|| {
            EvalError::native_fn(
                fname,
                format!("{text} is not a host:port this host resolves"),
                span,
            )
        })
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
    fname: &'static str,
    span: Span,
) -> Result<Value, EvalError> {
    if let Value::Str(addr) = target {
        let mut wire = Wire::bind(addr)
            .map_err(|e| EvalError::native_fn(fname, format!("{addr}: {e}"), span))?;
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

fn next(
    args: &[Value],
    channel: Channel,
    fname: &'static str,
    span: Span,
) -> Result<Value, EvalError> {
    let timeout = arg_ms(&args[1], fname, span, true)?;
    with_channel(&args[0], channel, fname, span, |w| {
        w.next(channel, timeout).map_err(|e| e.to_string())
    })
    .map(received)
}

fn stats(v: &Value, channel: Channel, fname: &'static str, span: Span) -> Result<Value, EvalError> {
    with_channel(v, channel, fname, span, |w| {
        let address = w.address().map_err(|e| e.to_string())?;
        let c = w.counts(channel);
        let mut fields = vec![
            ("address", text(address.to_string())),
            ("port", int(address.port())),
            ("sent", int(c.sent)),
            ("received", int(c.received)),
            ("dropped", int(c.dropped)),
            ("malformed", int(w.malformed())),
        ];
        if channel == Channel::Tide {
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
        Ok(record(fields))
    })
}

pub fn install_wire<H: 'static>(interp: &mut Interpreter<H>) {
    install_flash(interp);
    install_tide(interp);
}

fn install_flash<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "flash_open",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            open(
                &args[0],
                Channel::Flash,
                (RING_FRAMES, RING_BYTES),
                "flash_open",
                span,
            )
        },
    );
    interp.register_fn(
        "flash_put",
        Arity::Exact(3),
        |args: &[Value], _h: &mut H, span| {
            let peer = peer_of(&args[1], "flash_put", span)?;
            let payload = arg_str(&args[2], "flash_put", span)?;
            with_channel(&args[0], Channel::Flash, "flash_put", span, |w| {
                w.flash_put(peer, payload.as_bytes())
            })
            .map(int)
        },
    );
    interp.register_fn(
        "flash_next",
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| next(args, Channel::Flash, "flash_next", span),
    );
    interp.register_fn(
        "flash_stats",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| stats(&args[0], Channel::Flash, "flash_stats", span),
    );
    interp.register_fn(
        "flash_close",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| close(&args[0], Channel::Flash, "flash_close", span),
    );
}

fn install_tide<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "tide_open",
        Arity::Range(1, 2),
        |args: &[Value], _h: &mut H, span| {
            let ring = ring_opts(args.get(1), "tide_open", span)?;
            open(&args[0], Channel::Tide, ring, "tide_open", span)
        },
    );
    interp.register_fn(
        "tide_put",
        Arity::Exact(3),
        |args: &[Value], _h: &mut H, span| {
            let peer = peer_of(&args[1], "tide_put", span)?;
            let payload = arg_str(&args[2], "tide_put", span)?;
            with_channel(&args[0], Channel::Tide, "tide_put", span, |w| {
                w.tide_put(peer, payload.as_bytes())
            })
            .map(int)
        },
    );
    interp.register_fn(
        "tide_release",
        Arity::Exact(3),
        |args: &[Value], _h: &mut H, span| {
            let room = bounded(&args[1], "tide_release", span)?;
            let stamp = arg_int(&args[2], "tide_release", span)?;
            with_channel(&args[0], Channel::Tide, "tide_release", span, |w| {
                w.tide_release(room, stamp)
            })
            .map(int)
        },
    );
    interp.register_fn(
        "tide_send",
        Arity::Exact(4),
        |args: &[Value], _h: &mut H, span| {
            let peer = peer_of(&args[1], "tide_send", span)?;
            let payload = arg_str(&args[2], "tide_send", span)?;
            let stamp = arg_int(&args[3], "tide_send", span)?;
            with_channel(&args[0], Channel::Tide, "tide_send", span, |w| {
                w.tide_send(peer, payload.as_bytes(), stamp)
            })
            .map(int)
        },
    );
    interp.register_fn(
        "tide_next",
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| next(args, Channel::Tide, "tide_next", span),
    );
    interp.register_fn(
        "tide_stats",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| stats(&args[0], Channel::Tide, "tide_stats", span),
    );
    interp.register_fn(
        "tide_close",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| close(&args[0], Channel::Tide, "tide_close", span),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pair() -> (Wire, Wire, SocketAddr, SocketAddr) {
        let mut a = Wire::bind("127.0.0.1:0").expect("bind a");
        let mut b = Wire::bind("127.0.0.1:0").expect("bind b");
        for w in [&mut a, &mut b] {
            w.open(Channel::Flash, (RING_FRAMES, RING_BYTES));
            w.open(Channel::Tide, (RING_FRAMES, RING_BYTES));
        }
        let (aa, ba) = (a.address().unwrap(), b.address().unwrap());
        (a, b, aa, ba)
    }

    #[test]
    fn a_flash_frame_is_its_framing_byte_and_its_payload_up_to_the_mtu() {
        let full = vec![b'x'; Channel::Flash.room()];
        let datagram = encode(Channel::Flash, 99, &full).expect("a full Flash frame");
        assert_eq!(datagram.len(), MTU);
        assert_eq!(datagram[0], 0x02);
        assert_eq!(
            decode(&datagram).unwrap(),
            Frame {
                channel: Channel::Flash,
                stamp_ms: None,
                payload: full.clone()
            }
        );
        let over = vec![b'x'; Channel::Flash.room() + 1];
        assert_eq!(
            encode(Channel::Flash, 0, &over),
            Err(WireError::PastMtu {
                channel: "Flash",
                payload: 1280,
                len: 1281
            })
        );
    }

    #[test]
    fn a_tide_frame_carries_its_send_stamp_after_its_framing_byte() {
        let datagram = encode(Channel::Tide, -5, b"bulk").unwrap();
        assert_eq!(datagram[0], 0x01);
        assert_eq!(datagram.len(), 1 + 8 + 4);
        let frame = decode(&datagram).unwrap();
        assert_eq!(frame.stamp_ms, Some(-5));
        assert_eq!(frame.payload, b"bulk");
        assert_eq!(Channel::Tide.room(), 1271);
        assert!(encode(Channel::Tide, 0, &vec![0u8; 1272]).is_err());
        assert!(encode(Channel::Tide, 0, &vec![0u8; 1271]).is_ok());
    }

    #[test]
    fn a_datagram_that_is_no_frame_is_refused_by_name() {
        assert_eq!(decode(&[]), Err(WireError::Empty));
        assert_eq!(decode(&[0x03, 1]), Err(WireError::UnknownChannel(0x03)));
        assert_eq!(decode(&[0x01, 0, 0]), Err(WireError::ShortStamp(3)));
        assert_eq!(
            decode(&vec![0x02; MTU + 1]),
            Err(WireError::PastMtuReceived(1281))
        );
    }

    #[test]
    fn the_ring_evicts_its_oldest_frame_and_never_holds_past_its_bounds() {
        let mut r: Ring<u32> = Ring::new(3, 3000);
        assert_eq!(r.push(1, 1000), 0);
        assert_eq!(r.push(2, 1000), 0);
        assert_eq!(r.push(3, 1000), 0);
        assert_eq!(r.push(4, 1000), 1);
        assert_eq!((r.len(), r.bytes(), r.evicted()), (3, 3000, 1));
        assert_eq!(r.push(5, 1280), 2);
        assert_eq!((r.len(), r.bytes()), (2, 2280));
        assert_eq!(r.push(6, 1280), 1);
        assert!(r.len() <= 3 && r.bytes() <= 3000);
        assert_eq!(r.pop(), Some(5));
        assert_eq!(r.pop(), Some(6));
        assert_eq!(r.pop(), None);
        assert_eq!(r.evicted(), 4);
        let mut held: Ring<usize> = Ring::new(64, 64 * 1024);
        for i in 0..500 {
            held.push(i, 1 + (i * 7919) % MTU);
            assert!(held.len() <= 64 && held.bytes() <= 64 * 1024);
        }
        assert_eq!(Ring::<u8>::new(0, 0).bounds(), (1, MTU));
    }

    #[test]
    fn a_flash_frame_crosses_loopback_whole_and_lands_only_in_the_flash_inbox() {
        let (mut a, mut b, aa, ba) = pair();
        assert_eq!(a.flash_put(ba, b"alert").unwrap(), 6);
        let got = b
            .next(Channel::Flash, Duration::from_secs(2))
            .unwrap()
            .expect("the frame arrives");
        assert_eq!(got.payload, "alert");
        assert_eq!(got.from, aa);
        assert_eq!(got.bytes, 6);
        assert_eq!(got.stamp_ms, None);
        assert_eq!(b.next(Channel::Tide, Duration::ZERO).unwrap(), None);
        assert_eq!(a.counts(Channel::Flash).sent, 1);
        assert_eq!(b.counts(Channel::Flash).received, 1);
        assert!(a.flash_put(ba, &vec![0u8; 1280]).is_err());
        assert_eq!(a.counts(Channel::Flash).sent, 1);
    }

    #[test]
    fn tide_frames_wait_in_the_ring_until_released_and_flash_preempts_them() {
        let (mut a, _, _, _) = pair();
        let raw = UdpSocket::bind("127.0.0.1:0").unwrap();
        let ra = raw.local_addr().unwrap();
        for i in 0..3 {
            assert_eq!(a.tide_put(ra, format!("bulk {i}").as_bytes()).unwrap(), 0);
        }
        assert_eq!(a.queued(), (3, 3 * (9 + 6)));
        a.flash_put(ra, b"urgent").unwrap();
        assert_eq!(a.tide_release(29, 7).unwrap(), 15);
        assert_eq!(a.queued(), (2, 30));
        assert_eq!(a.tide_release(1_000_000, 8).unwrap(), 30);
        raw.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
        let mut buf = [0u8; 2048];
        let order: Vec<Frame> = (0..4)
            .map(|_| {
                let (n, _) = raw.recv_from(&mut buf).unwrap();
                decode(&buf[..n]).unwrap()
            })
            .collect();
        assert_eq!(order[0].channel, Channel::Flash);
        assert_eq!(order[0].payload, b"urgent");
        assert_eq!(
            order[1..].iter().map(|f| f.stamp_ms).collect::<Vec<_>>(),
            vec![Some(7), Some(8), Some(8)]
        );
        assert_eq!(order[3].payload, b"bulk 2");
    }

    #[test]
    fn a_tide_inbox_past_its_bound_evicts_its_oldest_frame() {
        let mut a = Wire::bind("127.0.0.1:0").unwrap();
        let mut b = Wire::bind("127.0.0.1:0").unwrap();
        a.open(Channel::Tide, (RING_FRAMES, RING_BYTES));
        b.open(Channel::Tide, (2, MTU * 2));
        let ba = b.address().unwrap();
        for i in 0..5 {
            a.tide_send(ba, format!("t{i}").as_bytes(), i).unwrap();
        }
        std::thread::sleep(Duration::from_millis(50));
        let first = b
            .next(Channel::Tide, Duration::from_secs(2))
            .unwrap()
            .unwrap();
        let second = b.next(Channel::Tide, Duration::ZERO).unwrap().unwrap();
        assert_eq!(
            (first.payload.as_str(), second.payload.as_str()),
            ("t3", "t4")
        );
        assert_eq!(b.evicted().1, 3);
        assert_eq!(b.counts(Channel::Tide).received, 5);
    }

    #[test]
    fn a_frame_for_a_closed_channel_is_dropped_not_kept() {
        let (mut a, mut b, _, ba) = pair();
        b.close(Channel::Flash);
        a.flash_put(ba, b"nobody listens").unwrap();
        a.tide_send(ba, b"heard", 1).unwrap();
        let got = b
            .next(Channel::Tide, Duration::from_secs(2))
            .unwrap()
            .unwrap();
        assert_eq!(got.payload, "heard");
        b.drain().unwrap();
        assert_eq!(b.counts(Channel::Flash).dropped, 1);
        assert_eq!(b.counts(Channel::Flash).received, 0);
        assert!(!b.close(Channel::Tide));
    }
}
