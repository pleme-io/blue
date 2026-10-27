use std::fmt;
use std::io::{ErrorKind, Read, Write};
use std::net::TcpStream;
use std::time::{Duration, Instant};

use super::dial;

pub const DEFAULT_PORT: u16 = 6379;
const MAX_LINE: usize = 64 * 1024;
const MAX_BULK: usize = 512 * 1024 * 1024;
const MAX_DEPTH: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RespError {
    Refused(String),
    Io(String),
    Protocol(String),
    Server(String),
    Closed,
}

impl fmt::Display for RespError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RespError::Refused(why) => write!(f, "refused: {why}"),
            RespError::Io(why) => write!(f, "{why}"),
            RespError::Protocol(why) => write!(f, "protocol error: {why}"),
            RespError::Server(why) => write!(f, "server error: {why}"),
            RespError::Closed => write!(f, "the connection is closed"),
        }
    }
}

impl std::error::Error for RespError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Reply {
    Simple(String),
    Error(String),
    Int(i64),
    Bulk(Vec<u8>),
    Nil,
    Array(Vec<Reply>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Target {
    pub host: String,
    pub port: u16,
    pub password: Option<String>,
    pub tls: bool,
}

pub fn admit(target: &Target) -> Result<(), RespError> {
    if target.tls {
        return Err(RespError::Refused(format!(
            "{}:{} asks for TLS, and blue's runtime has no TLS transport yet (docs/HTTP2.md P4)",
            target.host, target.port
        )));
    }
    if target.host != "127.0.0.1" {
        return Err(RespError::Refused(format!(
            "TLS off is allowed only for 127.0.0.1, not {}",
            target.host
        )));
    }
    Ok(())
}

#[must_use]
pub fn encode(args: &[Vec<u8>]) -> Vec<u8> {
    let mut out = format!("*{}\r\n", args.len()).into_bytes();
    for a in args {
        out.extend_from_slice(format!("${}\r\n", a.len()).as_bytes());
        out.extend_from_slice(a);
        out.extend_from_slice(b"\r\n");
    }
    out
}

#[derive(Debug, Default)]
pub struct Decoder {
    buf: Vec<u8>,
}

fn line_at(buf: &[u8], at: usize) -> Result<Option<(&[u8], usize)>, RespError> {
    let rest = buf.get(at..).unwrap_or_default();
    match rest.windows(2).position(|w| w == b"\r\n") {
        Some(i) => Ok(Some((&rest[..i], at + i + 2))),
        None if rest.len() > MAX_LINE => Err(RespError::Protocol(format!(
            "a line longer than {MAX_LINE} bytes"
        ))),
        None => Ok(None),
    }
}

fn number(line: &[u8]) -> Result<i64, RespError> {
    std::str::from_utf8(line)
        .ok()
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| {
            RespError::Protocol(format!(
                "{:?} is not a number",
                String::from_utf8_lossy(line)
            ))
        })
}

fn parse(buf: &[u8], at: usize, depth: usize) -> Result<Option<(Reply, usize)>, RespError> {
    if depth > MAX_DEPTH {
        return Err(RespError::Protocol(format!(
            "arrays nested deeper than {MAX_DEPTH}"
        )));
    }
    let Some(&tag) = buf.get(at) else {
        return Ok(None);
    };
    let Some((line, next)) = line_at(buf, at + 1)? else {
        return Ok(None);
    };
    let text = || String::from_utf8_lossy(line).into_owned();
    match tag {
        b'+' => Ok(Some((Reply::Simple(text()), next))),
        b'-' => Ok(Some((Reply::Error(text()), next))),
        b':' => Ok(Some((Reply::Int(number(line)?), next))),
        b'$' => {
            let n = number(line)?;
            if n < 0 {
                return Ok(Some((Reply::Nil, next)));
            }
            let n = usize::try_from(n).unwrap_or(usize::MAX);
            if n > MAX_BULK {
                return Err(RespError::Protocol(format!(
                    "a bulk string of {n} bytes exceeds {MAX_BULK}"
                )));
            }
            if buf.len() < next + n + 2 {
                return Ok(None);
            }
            if &buf[next + n..next + n + 2] != b"\r\n" {
                return Err(RespError::Protocol(
                    "a bulk string not ended by CRLF".into(),
                ));
            }
            Ok(Some((
                Reply::Bulk(buf[next..next + n].to_vec()),
                next + n + 2,
            )))
        }
        b'*' => {
            let n = number(line)?;
            if n < 0 {
                return Ok(Some((Reply::Nil, next)));
            }
            let mut items = Vec::new();
            let mut pos = next;
            for _ in 0..n {
                match parse(buf, pos, depth + 1)? {
                    Some((item, after)) => {
                        items.push(item);
                        pos = after;
                    }
                    None => return Ok(None),
                }
            }
            Ok(Some((Reply::Array(items), pos)))
        }
        other => Err(RespError::Protocol(format!(
            "unknown reply type {:?}",
            char::from(other)
        ))),
    }
}

impl Decoder {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    pub fn feed(&mut self, bytes: &[u8]) {
        self.buf.extend_from_slice(bytes);
    }

    pub fn next_reply(&mut self) -> Result<Option<Reply>, RespError> {
        match parse(&self.buf, 0, 0)? {
            Some((reply, used)) => {
                self.buf.drain(..used);
                Ok(Some(reply))
            }
            None => Ok(None),
        }
    }
}

pub struct Client {
    stream: TcpStream,
    decoder: Decoder,
    closed: bool,
}

impl Client {
    pub fn connect(target: &Target, timeout: Duration) -> Result<Self, RespError> {
        admit(target)?;
        let stream = dial(&target.host, target.port, timeout).map_err(RespError::Io)?;
        let mut client = Client {
            stream,
            decoder: Decoder::new(),
            closed: false,
        };
        if let Some(pw) = &target.password {
            client.command(&[b"AUTH".to_vec(), pw.as_bytes().to_vec()], timeout)?;
        }
        match client.command(&[b"PING".to_vec()], timeout)? {
            Reply::Simple(s) if s == "PONG" => Ok(client),
            other => Err(RespError::Protocol(format!("PING answered {other:?}"))),
        }
    }

    fn write(&mut self, bytes: &[u8]) -> Result<(), RespError> {
        if self.closed {
            return Err(RespError::Closed);
        }
        self.stream.write_all(bytes).map_err(|e| {
            self.closed = true;
            RespError::Io(e.to_string())
        })
    }

    fn read_reply(&mut self, deadline: Instant) -> Result<Option<Reply>, RespError> {
        loop {
            if let Some(r) = self.decoder.next_reply()? {
                return Ok(Some(r));
            }
            if self.closed {
                return Err(RespError::Closed);
            }
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return Ok(None);
            }
            self.stream
                .set_read_timeout(Some(left.max(Duration::from_millis(1))))
                .map_err(|e| RespError::Io(e.to_string()))?;
            let mut chunk = [0u8; 16 * 1024];
            match self.stream.read(&mut chunk) {
                Ok(0) => {
                    self.closed = true;
                    return Err(RespError::Io("the server closed the connection".into()));
                }
                Ok(n) => self.decoder.feed(&chunk[..n]),
                Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
                    return Ok(None)
                }
                Err(e) if e.kind() == ErrorKind::Interrupted => {}
                Err(e) => {
                    self.closed = true;
                    return Err(RespError::Io(e.to_string()));
                }
            }
        }
    }

    fn answered(&mut self, deadline: Instant) -> Result<Reply, RespError> {
        match self.read_reply(deadline)? {
            Some(r) => Ok(r),
            None => {
                self.closed = true;
                Err(RespError::Io("timed out waiting for a reply".into()))
            }
        }
    }

    pub fn command(&mut self, args: &[Vec<u8>], timeout: Duration) -> Result<Reply, RespError> {
        self.write(&encode(args))?;
        match self.answered(Instant::now() + timeout)? {
            Reply::Error(e) => Err(RespError::Server(e)),
            r => Ok(r),
        }
    }

    pub fn pipeline(
        &mut self,
        commands: &[Vec<Vec<u8>>],
        timeout: Duration,
    ) -> Result<Vec<Reply>, RespError> {
        let mut out = Vec::new();
        for c in commands {
            out.extend_from_slice(&encode(c));
        }
        self.write(&out)?;
        let deadline = Instant::now() + timeout;
        let mut replies = Vec::with_capacity(commands.len());
        for _ in commands {
            replies.push(self.answered(deadline)?);
        }
        Ok(replies)
    }

    pub fn next(&mut self, timeout: Duration) -> Result<Option<Reply>, RespError> {
        self.read_reply(Instant::now() + timeout)
    }

    pub fn close(&mut self) {
        if !self.closed {
            let _ = self.stream.shutdown(std::net::Shutdown::Both);
            self.closed = true;
        }
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

    fn all(bytes: &[u8]) -> Vec<Reply> {
        let mut d = Decoder::new();
        d.feed(bytes);
        let mut out = Vec::new();
        while let Some(r) = d.next_reply().unwrap() {
            out.push(r);
        }
        out
    }

    #[test]
    fn commands_encode_as_arrays_of_bulk_strings() {
        assert_eq!(
            encode(&[b"SET".to_vec(), b"k".to_vec(), b"a\r\nb".to_vec()]),
            b"*3\r\n$3\r\nSET\r\n$1\r\nk\r\n$4\r\na\r\nb\r\n".to_vec()
        );
        assert_eq!(encode(&[]), b"*0\r\n".to_vec());
    }

    #[test]
    fn every_reply_type_decodes() {
        assert_eq!(
            all(b"+OK\r\n-ERR no\r\n:42\r\n$3\r\nabc\r\n$-1\r\n*-1\r\n$0\r\n\r\n"),
            vec![
                Reply::Simple("OK".into()),
                Reply::Error("ERR no".into()),
                Reply::Int(42),
                Reply::Bulk(b"abc".to_vec()),
                Reply::Nil,
                Reply::Nil,
                Reply::Bulk(Vec::new()),
            ]
        );
        assert_eq!(
            all(b"*2\r\n$1\r\n0\r\n*2\r\n$1\r\na\r\n:7\r\n"),
            vec![Reply::Array(vec![
                Reply::Bulk(b"0".to_vec()),
                Reply::Array(vec![Reply::Bulk(b"a".to_vec()), Reply::Int(7)]),
            ])]
        );
    }

    #[test]
    fn a_reply_split_at_every_byte_decodes_once() {
        let wire = b"*3\r\n$7\r\nmessage\r\n$2\r\nch\r\n$5\r\nhe\r\nl\r\n";
        for cut in 0..wire.len() {
            let mut d = Decoder::new();
            d.feed(&wire[..cut]);
            assert_eq!(d.next_reply().unwrap(), None, "cut at {cut}");
            d.feed(&wire[cut..]);
            assert_eq!(
                d.next_reply().unwrap(),
                Some(Reply::Array(vec![
                    Reply::Bulk(b"message".to_vec()),
                    Reply::Bulk(b"ch".to_vec()),
                    Reply::Bulk(b"he\r\nl".to_vec()),
                ]))
            );
            assert_eq!(d.next_reply().unwrap(), None);
        }
    }

    #[test]
    fn malformed_replies_are_refused() {
        let mut d = Decoder::new();
        d.feed(b"?x\r\n");
        assert!(d.next_reply().is_err());
        let mut d = Decoder::new();
        d.feed(b":x\r\n");
        assert!(d.next_reply().is_err());
        let mut d = Decoder::new();
        d.feed(b"$1\r\nab\r\n");
        assert!(d.next_reply().is_err());
        let mut d = Decoder::new();
        d.feed(&vec![b'+'; MAX_LINE + 2]);
        assert!(d.next_reply().is_err());
    }

    #[test]
    fn tls_is_on_by_default_and_off_only_on_loopback() {
        let t = |host: &str, tls| Target {
            host: host.into(),
            port: 6379,
            password: None,
            tls,
        };
        let on = admit(&t("cache", true)).unwrap_err().to_string();
        assert!(on.contains("no TLS transport"), "{on}");
        let off = admit(&t("10.0.0.5", false)).unwrap_err().to_string();
        assert!(off.contains("only for 127.0.0.1"), "{off}");
        assert!(admit(&t("localhost", false)).is_err());
        assert!(admit(&t("127.0.0.1", false)).is_ok());
    }
}
