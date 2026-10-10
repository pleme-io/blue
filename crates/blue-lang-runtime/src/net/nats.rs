//! NATS, spoken directly over a `TcpStream`: the codec, then a client.
//!
//! The client protocol is a dozen line-oriented operations, so blue speaks it
//! rather than linking a client library (pleme-style, CONTAIN THE C: speak the
//! protocol in Rust). The [`Decoder`] is pure and owns every framing rule —
//! a frame split anywhere across reads, a payload carrying `\r\n`, `HMSG`'s
//! header block — and the [`Client`] owns the socket and nothing else.
//!
//! One thread, no background reader. The client answers the server's `PING`
//! whenever the program touches the connection (every publish drains what has
//! arrived without waiting), so a program that neither publishes nor reads for
//! the server's ping window is disconnected, and the next call says so.
//!
//! Plain TCP only: a server whose `INFO` requires TLS is refused by name.

use std::collections::{HashMap, HashSet, VecDeque};
use std::fmt;
use std::io::{ErrorKind, Read, Write};
use std::net::TcpStream;

use super::{dial, split_host_port};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub const DEFAULT_PORT: u16 = 4222;
const MAX_CONTROL_LINE: usize = 64 * 1024;
const MAX_FRAME_PAYLOAD: usize = 64 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Msg {
    pub subject: String,
    pub sid: u64,
    pub reply: Option<String>,
    pub headers: Option<Vec<u8>>,
    pub payload: Vec<u8>,
}

impl Msg {
    /// The status code an `HMSG` header block carries (`NATS/1.0 503`).
    #[must_use]
    pub fn status(&self) -> Option<u16> {
        let headers = self.headers.as_ref()?;
        let line = headers.split(|b| *b == b'\n').next()?;
        let line = std::str::from_utf8(line).ok()?.trim();
        line.strip_prefix("NATS/1.0")?
            .split_whitespace()
            .next()?
            .parse()
            .ok()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Frame {
    Info(String),
    Msg(Msg),
    Ping,
    Pong,
    Ok,
    Err(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NatsError {
    Url(String),
    Subject(String),
    Protocol(String),
    Io(String),
    Server(String),
    TlsRequired,
    PayloadTooLarge { size: usize, max: usize },
    Closed,
    Timeout(String),
    NoResponders(String),
}

impl fmt::Display for NatsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            NatsError::Url(why) => write!(f, "bad NATS url: {why}"),
            NatsError::Subject(why) => write!(f, "bad subject: {why}"),
            NatsError::Protocol(why) => write!(f, "protocol error: {why}"),
            NatsError::Io(why) => write!(f, "{why}"),
            NatsError::Server(why) => write!(f, "server error: {why}"),
            NatsError::TlsRequired => write!(
                f,
                "the server requires TLS; blue's NATS client speaks plain TCP only"
            ),
            NatsError::PayloadTooLarge { size, max } => {
                write!(
                    f,
                    "payload of {size} bytes exceeds the server's max_payload {max}"
                )
            }
            NatsError::Closed => write!(f, "the connection is closed"),
            NatsError::Timeout(what) => write!(f, "timed out: {what}"),
            NatsError::NoResponders(subject) => write!(f, "no responders on {subject}"),
        }
    }
}

impl std::error::Error for NatsError {}

fn io_err(e: &std::io::Error) -> NatsError {
    NatsError::Io(e.to_string())
}

// ── codec ────────────────────────────────────────────────────────────────

#[derive(Debug, Default)]
pub struct Decoder {
    buf: Vec<u8>,
}

impl Decoder {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    pub fn feed(&mut self, bytes: &[u8]) {
        self.buf.extend_from_slice(bytes);
    }

    #[must_use]
    pub fn buffered(&self) -> usize {
        self.buf.len()
    }

    /// The next complete frame, `None` until one has fully arrived.
    pub fn next_frame(&mut self) -> Result<Option<Frame>, NatsError> {
        let Some(eol) = find_crlf(&self.buf) else {
            if self.buf.len() > MAX_CONTROL_LINE {
                return Err(NatsError::Protocol(format!(
                    "control line longer than {MAX_CONTROL_LINE} bytes"
                )));
            }
            return Ok(None);
        };
        let line = std::str::from_utf8(&self.buf[..eol])
            .map_err(|_| NatsError::Protocol("control line is not UTF-8".into()))?
            .to_string();
        let (op, rest) = match line.find([' ', '\t']) {
            Some(i) => (&line[..i], line[i..].trim()),
            None => (line.as_str(), ""),
        };
        let head = eol + 2;
        let frame = match op.to_ascii_uppercase().as_str() {
            "PING" => Frame::Ping,
            "PONG" => Frame::Pong,
            "+OK" => Frame::Ok,
            "-ERR" => Frame::Err(rest.trim_matches('\'').to_string()),
            "INFO" => Frame::Info(rest.to_string()),
            "MSG" => return self.take_msg(rest, head, false),
            "HMSG" => return self.take_msg(rest, head, true),
            other => {
                return Err(NatsError::Protocol(format!("unknown operation {other:?}")));
            }
        };
        self.buf.drain(..head);
        Ok(Some(frame))
    }

    fn take_msg(
        &mut self,
        args: &str,
        head: usize,
        with_headers: bool,
    ) -> Result<Option<Frame>, NatsError> {
        let parts: Vec<&str> = args.split_whitespace().collect();
        let sizes = if with_headers { 2 } else { 1 };
        if parts.len() != 2 + sizes && parts.len() != 3 + sizes {
            return Err(NatsError::Protocol(format!(
                "malformed message line: {args:?}"
            )));
        }
        let number = |s: &str| -> Result<usize, NatsError> {
            s.parse()
                .map_err(|_| NatsError::Protocol(format!("not a size: {s:?}")))
        };
        let subject = parts[0].to_string();
        let sid: u64 = parts[1]
            .parse()
            .map_err(|_| NatsError::Protocol(format!("not a sid: {:?}", parts[1])))?;
        let reply = (parts.len() == 3 + sizes).then(|| parts[2].to_string());
        let total = number(parts[parts.len() - 1])?;
        let header_len = if with_headers {
            number(parts[parts.len() - 2])?
        } else {
            0
        };
        if total > MAX_FRAME_PAYLOAD || header_len > total {
            return Err(NatsError::Protocol(format!(
                "message sizes out of range: header {header_len}, total {total}"
            )));
        }
        let end = head + total;
        if self.buf.len() < end + 2 {
            return Ok(None);
        }
        if &self.buf[end..end + 2] != b"\r\n" {
            return Err(NatsError::Protocol(
                "message payload is not followed by CRLF".into(),
            ));
        }
        let body = &self.buf[head..end];
        let headers = with_headers.then(|| body[..header_len].to_vec());
        let payload = body[header_len..].to_vec();
        self.buf.drain(..end + 2);
        Ok(Some(Frame::Msg(Msg {
            subject,
            sid,
            reply,
            headers,
            payload,
        })))
    }
}

fn find_crlf(buf: &[u8]) -> Option<usize> {
    buf.windows(2).position(|w| w == b"\r\n")
}

/// A subject is dot-separated tokens with no whitespace; publishing to a
/// wildcard is refused.
pub fn check_subject(subject: &str, wildcards: bool) -> Result<(), NatsError> {
    if subject.is_empty() {
        return Err(NatsError::Subject("empty".into()));
    }
    if subject.chars().any(|c| c.is_whitespace() || c.is_control()) {
        return Err(NatsError::Subject(format!(
            "{subject:?} contains whitespace"
        )));
    }
    for token in subject.split('.') {
        if token.is_empty() {
            return Err(NatsError::Subject(format!(
                "{subject:?} has an empty token"
            )));
        }
        if !wildcards && (token == "*" || token == ">") {
            return Err(NatsError::Subject(format!(
                "{subject:?} is a wildcard; a message is published to one subject"
            )));
        }
    }
    Ok(())
}

pub fn encode_pub(
    subject: &str,
    reply: Option<&str>,
    payload: &[u8],
) -> Result<Vec<u8>, NatsError> {
    check_subject(subject, false)?;
    let mut out = match reply {
        Some(r) => {
            check_subject(r, false)?;
            format!("PUB {subject} {r} {}\r\n", payload.len())
        }
        None => format!("PUB {subject} {}\r\n", payload.len()),
    }
    .into_bytes();
    out.extend_from_slice(payload);
    out.extend_from_slice(b"\r\n");
    Ok(out)
}

pub fn encode_sub(subject: &str, queue: Option<&str>, sid: u64) -> Result<Vec<u8>, NatsError> {
    check_subject(subject, true)?;
    Ok(match queue {
        Some(q) => {
            if q.is_empty() || q.chars().any(|c| c.is_whitespace() || c.is_control()) {
                return Err(NatsError::Subject(format!("bad queue group {q:?}")));
            }
            format!("SUB {subject} {q} {sid}\r\n")
        }
        None => format!("SUB {subject} {sid}\r\n"),
    }
    .into_bytes())
}

#[must_use]
pub fn encode_unsub(sid: u64, max: Option<u64>) -> Vec<u8> {
    match max {
        Some(n) => format!("UNSUB {sid} {n}\r\n"),
        None => format!("UNSUB {sid}\r\n"),
    }
    .into_bytes()
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Auth {
    pub user: Option<String>,
    pub pass: Option<String>,
    pub token: Option<String>,
}

#[must_use]
pub fn encode_connect(auth: &Auth) -> Vec<u8> {
    let mut opts = serde_json::json!({
        "verbose": false,
        "pedantic": false,
        "lang": "blue",
        "version": env!("CARGO_PKG_VERSION"),
        "protocol": 1,
        "headers": true,
        "no_responders": true,
    });
    if let Some(u) = &auth.user {
        opts["user"] = serde_json::Value::from(u.as_str());
    }
    if let Some(p) = &auth.pass {
        opts["pass"] = serde_json::Value::from(p.as_str());
    }
    if let Some(t) = &auth.token {
        opts["auth_token"] = serde_json::Value::from(t.as_str());
    }
    format!("CONNECT {opts}\r\n").into_bytes()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    pub host: String,
    pub port: u16,
    pub auth: Auth,
}

/// `nats://[user:pass@|token@]host[:port]`; the scheme may be omitted.
pub fn parse_url(url: &str) -> Result<Endpoint, NatsError> {
    let rest = match url.split_once("://") {
        Some(("nats" | "tcp", rest)) => rest,
        Some(("tls", _)) => return Err(NatsError::TlsRequired),
        Some((scheme, _)) => {
            return Err(NatsError::Url(format!(
                "{url}: scheme {scheme:?} is not nats"
            )));
        }
        None => url,
    };
    let rest = rest.trim_end_matches('/');
    let (userinfo, hostport) = match rest.rsplit_once('@') {
        Some((u, h)) => (Some(u), h),
        None => (None, rest),
    };
    let auth = match userinfo {
        None => Auth::default(),
        Some(u) => match u.split_once(':') {
            Some((user, pass)) => Auth {
                user: Some(user.to_string()),
                pass: Some(pass.to_string()),
                token: None,
            },
            None => Auth {
                token: Some(u.to_string()),
                ..Auth::default()
            },
        },
    };
    let (host, port) = split_host_port(hostport, DEFAULT_PORT)
        .map_err(|why| NatsError::Url(format!("{url}: {why}")))?;
    Ok(Endpoint { host, port, auth })
}

// ── client ───────────────────────────────────────────────────────────────

pub struct Client {
    stream: TcpStream,
    decoder: Decoder,
    pending: HashMap<u64, VecDeque<Msg>>,
    live: HashSet<u64>,
    next_sid: u64,
    max_payload: usize,
    inbox_prefix: String,
    next_inbox: u64,
    pongs: u64,
    closed: bool,
}

impl Client {
    pub fn connect(url: &str, timeout: Duration) -> Result<Self, NatsError> {
        let endpoint = parse_url(url)?;
        let stream = dial(&endpoint.host, endpoint.port, timeout).map_err(NatsError::Io)?;
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let mut client = Client {
            stream,
            decoder: Decoder::new(),
            pending: HashMap::new(),
            live: HashSet::new(),
            next_sid: 1,
            max_payload: 1024 * 1024,
            inbox_prefix: format!("{:x}{nonce:x}", std::process::id()),
            next_inbox: 0,
            pongs: 0,
            closed: false,
        };
        let deadline = Instant::now() + timeout;
        let info = client.await_info(deadline)?;
        client.apply_info(&info)?;
        client.write(&encode_connect(&endpoint.auth))?;
        client.write(b"PING\r\n")?;
        let before = client.pongs;
        if !client.pump_until(Some(deadline), |c| c.pongs > before)? {
            return Err(NatsError::Timeout(format!(
                "the server at {}:{} did not confirm the connection",
                endpoint.host, endpoint.port
            )));
        }
        Ok(client)
    }

    fn await_info(&mut self, deadline: Instant) -> Result<String, NatsError> {
        loop {
            if let Some(frame) = self.decoder.next_frame()? {
                return match frame {
                    Frame::Info(json) => Ok(json),
                    Frame::Err(why) => Err(NatsError::Server(why)),
                    other => Err(NatsError::Protocol(format!(
                        "expected INFO first, got {other:?}"
                    ))),
                };
            }
            if !self.read_some(Some(deadline))? {
                return Err(NatsError::Timeout("waiting for the server's INFO".into()));
            }
        }
    }

    fn apply_info(&mut self, json: &str) -> Result<(), NatsError> {
        let info: serde_json::Value = serde_json::from_str(json)
            .map_err(|e| NatsError::Protocol(format!("INFO is not JSON: {e}")))?;
        if info
            .get("tls_required")
            .and_then(serde_json::Value::as_bool)
            == Some(true)
        {
            return Err(NatsError::TlsRequired);
        }
        if let Some(max) = info.get("max_payload").and_then(serde_json::Value::as_u64) {
            self.max_payload = max as usize;
        }
        Ok(())
    }

    #[must_use]
    pub fn is_closed(&self) -> bool {
        self.closed
    }

    #[must_use]
    pub fn max_payload(&self) -> usize {
        self.max_payload
    }

    fn write(&mut self, bytes: &[u8]) -> Result<(), NatsError> {
        if self.closed {
            return Err(NatsError::Closed);
        }
        self.stream.write_all(bytes).map_err(|e| {
            self.closed = true;
            io_err(&e)
        })
    }

    /// Read what the socket has, waiting until `deadline` (`None`: do not
    /// wait). `Ok(false)` when nothing arrived in time.
    fn read_some(&mut self, deadline: Option<Instant>) -> Result<bool, NatsError> {
        if self.closed {
            return Err(NatsError::Closed);
        }
        match deadline {
            None => self.stream.set_nonblocking(true).map_err(|e| io_err(&e))?,
            Some(d) => {
                let left = d.saturating_duration_since(Instant::now());
                if left.is_zero() {
                    return Ok(false);
                }
                self.stream.set_nonblocking(false).map_err(|e| io_err(&e))?;
                self.stream
                    .set_read_timeout(Some(left.max(Duration::from_millis(1))))
                    .map_err(|e| io_err(&e))?;
            }
        }
        let mut chunk = [0u8; 16 * 1024];
        let got = self.stream.read(&mut chunk);
        if deadline.is_none() {
            let _ = self.stream.set_nonblocking(false);
        }
        match got {
            Ok(0) => {
                self.closed = true;
                Err(NatsError::Io("the server closed the connection".into()))
            }
            Ok(n) => {
                self.decoder.feed(&chunk[..n]);
                Ok(true)
            }
            Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => Ok(false),
            Err(e) if e.kind() == ErrorKind::Interrupted => Ok(true),
            Err(e) => {
                self.closed = true;
                Err(io_err(&e))
            }
        }
    }

    fn handle(&mut self, frame: Frame) -> Result<(), NatsError> {
        match frame {
            Frame::Ping => self.write(b"PONG\r\n"),
            Frame::Pong => {
                self.pongs += 1;
                Ok(())
            }
            Frame::Ok => Ok(()),
            Frame::Info(json) => self.apply_info(&json),
            Frame::Err(why) => Err(NatsError::Server(why)),
            Frame::Msg(m) => {
                if self.live.contains(&m.sid) {
                    self.pending.entry(m.sid).or_default().push_back(m);
                }
                Ok(())
            }
        }
    }

    fn drain_decoded(&mut self) -> Result<(), NatsError> {
        while let Some(frame) = self.decoder.next_frame()? {
            self.handle(frame)?;
        }
        Ok(())
    }

    /// Process frames until `done` holds or `deadline` passes. `None` reads
    /// only what has already arrived.
    fn pump_until(
        &mut self,
        deadline: Option<Instant>,
        done: impl Fn(&Self) -> bool,
    ) -> Result<bool, NatsError> {
        loop {
            self.drain_decoded()?;
            if done(self) {
                return Ok(true);
            }
            if !self.read_some(deadline)? && deadline.is_none_or(|d| Instant::now() >= d) {
                self.drain_decoded()?;
                return Ok(done(self));
            }
        }
    }

    pub fn publish(
        &mut self,
        subject: &str,
        reply: Option<&str>,
        payload: &[u8],
    ) -> Result<(), NatsError> {
        if payload.len() > self.max_payload {
            return Err(NatsError::PayloadTooLarge {
                size: payload.len(),
                max: self.max_payload,
            });
        }
        let frame = encode_pub(subject, reply, payload)?;
        self.write(&frame)?;
        self.pump_until(None, |_| false).map(|_| ())
    }

    pub fn subscribe(&mut self, subject: &str, queue: Option<&str>) -> Result<u64, NatsError> {
        let sid = self.next_sid;
        let frame = encode_sub(subject, queue, sid)?;
        self.write(&frame)?;
        self.next_sid += 1;
        self.live.insert(sid);
        Ok(sid)
    }

    pub fn unsubscribe(&mut self, sid: u64) -> Result<(), NatsError> {
        if self.live.remove(&sid) {
            self.pending.remove(&sid);
            if !self.closed {
                self.write(&encode_unsub(sid, None))?;
            }
        }
        Ok(())
    }

    /// The next message on `sid`, or `None` when none arrives within `timeout`.
    pub fn next_message(&mut self, sid: u64, timeout: Duration) -> Result<Option<Msg>, NatsError> {
        if !self.live.contains(&sid) {
            return Err(NatsError::Protocol(format!("subscription {sid} is closed")));
        }
        let has = |c: &Self| c.pending.get(&sid).is_some_and(|q| !q.is_empty());
        if !has(self) {
            self.pump_until(Some(Instant::now() + timeout), has)?;
        }
        Ok(self.pending.get_mut(&sid).and_then(VecDeque::pop_front))
    }

    pub fn request(
        &mut self,
        subject: &str,
        payload: &[u8],
        timeout: Duration,
    ) -> Result<Msg, NatsError> {
        check_subject(subject, false)?;
        self.next_inbox += 1;
        let inbox = format!("_INBOX.{}.{}", self.inbox_prefix, self.next_inbox);
        let sid = self.subscribe(&inbox, None)?;
        let outcome = self
            .write(&encode_unsub(sid, Some(1)))
            .and_then(|()| self.publish(subject, Some(&inbox), payload))
            .and_then(|()| self.next_message(sid, timeout));
        self.live.remove(&sid);
        self.pending.remove(&sid);
        match outcome? {
            Some(m) if m.status() == Some(503) => Err(NatsError::NoResponders(subject.to_string())),
            Some(m) => Ok(m),
            None => Err(NatsError::Timeout(format!(
                "no reply on {subject} within {} ms",
                timeout.as_millis()
            ))),
        }
    }

    pub fn close(&mut self) {
        if !self.closed {
            let _ = self.stream.flush();
            let _ = self.stream.shutdown(std::net::Shutdown::Both);
            self.closed = true;
        }
        self.live.clear();
        self.pending.clear();
    }
}

impl Drop for Client {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frames(dec: &mut Decoder) -> Vec<Frame> {
        let mut out = Vec::new();
        while let Some(f) = dec.next_frame().expect("well-formed") {
            out.push(f);
        }
        out
    }

    fn msg(subject: &str, sid: u64, reply: Option<&str>, payload: &[u8]) -> Frame {
        Frame::Msg(Msg {
            subject: subject.into(),
            sid,
            reply: reply.map(Into::into),
            headers: None,
            payload: payload.to_vec(),
        })
    }

    #[test]
    fn control_frames_decode() {
        let mut d = Decoder::new();
        d.feed(b"INFO {\"max_payload\":1048576}\r\nPING\r\npong\r\n+OK\r\n-ERR 'Unknown Protocol Operation'\r\n");
        assert_eq!(
            frames(&mut d),
            vec![
                Frame::Info("{\"max_payload\":1048576}".into()),
                Frame::Ping,
                Frame::Pong,
                Frame::Ok,
                Frame::Err("Unknown Protocol Operation".into()),
            ]
        );
        assert_eq!(d.buffered(), 0);
    }

    #[test]
    fn a_message_with_and_without_reply() {
        let mut d = Decoder::new();
        d.feed(b"MSG lights.kitchen 3 5\r\nhello\r\nMSG svc.echo 9 _INBOX.a.1 2\r\nhi\r\n");
        assert_eq!(
            frames(&mut d),
            vec![
                msg("lights.kitchen", 3, None, b"hello"),
                msg("svc.echo", 9, Some("_INBOX.a.1"), b"hi"),
            ]
        );
    }

    #[test]
    fn a_payload_may_carry_crlf_and_be_empty() {
        let mut d = Decoder::new();
        d.feed(b"MSG a 1 4\r\n\r\n\r\n\r\nMSG b 2 0\r\n\r\n");
        assert_eq!(
            frames(&mut d),
            vec![msg("a", 1, None, b"\r\n\r\n"), msg("b", 2, None, b"")]
        );
    }

    #[test]
    fn a_frame_split_at_every_byte_decodes_once() {
        let wire: &[u8] = b"PING\r\nMSG s.x 7 r.y 11\r\nhello world\r\nHMSG h 2 18 23\r\nNATS/1.0\r\nK: v\r\n\r\nbody!\r\nPONG\r\n";
        let mut d = Decoder::new();
        let mut got = Vec::new();
        for b in wire {
            d.feed(std::slice::from_ref(b));
            got.extend(frames(&mut d));
        }
        assert_eq!(got.len(), 4, "{got:?}");
        assert_eq!(got[0], Frame::Ping);
        assert_eq!(got[1], msg("s.x", 7, Some("r.y"), b"hello world"));
        let Frame::Msg(h) = &got[2] else {
            panic!("expected HMSG, got {:?}", got[2]);
        };
        assert_eq!(h.headers.as_deref(), Some(&b"NATS/1.0\r\nK: v\r\n\r\n"[..]));
        assert_eq!(h.payload, b"body!");
        assert_eq!(got[3], Frame::Pong);
    }

    #[test]
    fn a_partial_message_waits_for_its_payload() {
        let mut d = Decoder::new();
        d.feed(b"MSG a 1 5\r\nhel");
        assert_eq!(d.next_frame(), Ok(None));
        d.feed(b"lo\r");
        assert_eq!(d.next_frame(), Ok(None));
        d.feed(b"\n");
        assert_eq!(d.next_frame(), Ok(Some(msg("a", 1, None, b"hello"))));
    }

    #[test]
    fn a_no_responders_status_is_read_from_hmsg() {
        let mut d = Decoder::new();
        d.feed(b"HMSG _INBOX.x 4 16 16\r\nNATS/1.0 503\r\n\r\n\r\n");
        let Some(Frame::Msg(m)) = d.next_frame().unwrap() else {
            panic!("expected a message");
        };
        assert_eq!(m.status(), Some(503));
        assert!(m.payload.is_empty());
    }

    #[test]
    fn malformed_frames_are_refused() {
        for wire in [
            &b"BOGUS\r\n"[..],
            b"MSG a 1\r\n",
            b"MSG a x 1\r\nh\r\n",
            b"MSG a 1 1\r\nhXX",
            b"HMSG a 1 9 3\r\nabc\r\n",
        ] {
            let mut d = Decoder::new();
            d.feed(wire);
            assert!(
                matches!(d.next_frame(), Err(NatsError::Protocol(_))),
                "{:?} must be refused",
                String::from_utf8_lossy(wire)
            );
        }
    }

    #[test]
    fn an_endless_control_line_is_refused() {
        let mut d = Decoder::new();
        d.feed(&vec![b'A'; MAX_CONTROL_LINE + 1]);
        assert!(matches!(d.next_frame(), Err(NatsError::Protocol(_))));
    }

    #[test]
    fn encoders_write_the_wire_form() {
        assert_eq!(
            encode_pub("a.b", None, b"xy").unwrap(),
            b"PUB a.b 2\r\nxy\r\n"
        );
        assert_eq!(
            encode_pub("a.b", Some("_INBOX.1"), b"").unwrap(),
            b"PUB a.b _INBOX.1 0\r\n\r\n"
        );
        assert_eq!(encode_sub("a.*", None, 3).unwrap(), b"SUB a.* 3\r\n");
        assert_eq!(
            encode_sub("a.>", Some("workers"), 4).unwrap(),
            b"SUB a.> workers 4\r\n"
        );
        assert_eq!(encode_unsub(4, Some(1)), b"UNSUB 4 1\r\n");
        assert_eq!(encode_unsub(4, None), b"UNSUB 4\r\n");
        let connect = String::from_utf8(encode_connect(&Auth::default())).unwrap();
        assert!(
            connect.starts_with("CONNECT {") && connect.ends_with("}\r\n"),
            "{connect}"
        );
        assert!(connect.contains("\"no_responders\":true"), "{connect}");
    }

    #[test]
    fn subjects_are_checked() {
        assert!(check_subject("home.light.on", false).is_ok());
        assert!(check_subject("home.*.on", true).is_ok());
        for bad in ["", "a b", "a..b", ".a", "a.", "a\r\nPUB x 1"] {
            assert!(check_subject(bad, true).is_err(), "{bad:?}");
        }
        assert!(encode_pub("home.>", None, b"").is_err());
        assert!(encode_sub("a", Some("bad group"), 1).is_err());
    }

    #[test]
    fn urls_parse_with_auth_and_defaults() {
        assert_eq!(
            parse_url("nats://127.0.0.1").unwrap(),
            Endpoint {
                host: "127.0.0.1".into(),
                port: 4222,
                auth: Auth::default()
            }
        );
        let e = parse_url("nats://u:p@bus.local:4333").unwrap();
        assert_eq!((e.host.as_str(), e.port), ("bus.local", 4333));
        assert_eq!(
            (e.auth.user.as_deref(), e.auth.pass.as_deref()),
            (Some("u"), Some("p"))
        );
        assert_eq!(
            parse_url("s3cret@h").unwrap().auth.token.as_deref(),
            Some("s3cret")
        );
        assert_eq!(parse_url("[::1]:5000").unwrap().host, "::1");
        assert_eq!(parse_url("tls://h"), Err(NatsError::TlsRequired));
        assert!(matches!(parse_url("http://h"), Err(NatsError::Url(_))));
        assert!(matches!(
            parse_url("nats://h:notaport"),
            Err(NatsError::Url(_))
        ));
    }
}
