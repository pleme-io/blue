use std::fmt;
use std::io::{ErrorKind, Read, Write};
use std::net::TcpStream;
use std::time::Duration;

use sha2::{Digest, Sha256};

use super::{dial, split_host_port};

const PROTOCOL_V3: i32 = 196_608;
const MAX_MESSAGE: usize = 256 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PgError {
    Url(String),
    Io(String),
    Protocol(String),
    Auth(String),
    Unsupported(String),
    Server { code: String, message: String },
}

impl fmt::Display for PgError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PgError::Url(why) => write!(f, "bad url: {why}"),
            PgError::Io(why) => write!(f, "{why}"),
            PgError::Protocol(why) => write!(f, "protocol: {why}"),
            PgError::Auth(why) => write!(f, "authentication: {why}"),
            PgError::Unsupported(why) => write!(f, "unsupported: {why}"),
            PgError::Server { code, message } => write!(f, "{code}: {message}"),
        }
    }
}

impl std::error::Error for PgError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Target {
    pub host: String,
    pub port: u16,
    pub user: String,
    pub password: Option<String>,
    pub database: String,
}

fn unescape(s: &str) -> Result<String, PgError> {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = s
                .get(i + 1..i + 3)
                .and_then(|h| u8::from_str_radix(h, 16).ok())
                .ok_or_else(|| PgError::Url(format!("bad percent escape in {s:?}")))?;
            out.push(hex);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).map_err(|_| PgError::Url(format!("{s:?} is not UTF-8")))
}

pub fn parse_url(url: &str) -> Result<Target, PgError> {
    let rest = url
        .strip_prefix("postgres://")
        .or_else(|| url.strip_prefix("postgresql://"))
        .ok_or_else(|| PgError::Url(format!("{url}: the scheme is postgres://")))?;
    let (rest, query) = match rest.split_once('?') {
        Some((r, q)) => (r, q),
        None => (rest, ""),
    };
    for pair in query.split('&').filter(|p| !p.is_empty()) {
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        if k == "sslmode" && !matches!(v, "disable" | "allow" | "prefer") {
            return Err(PgError::Unsupported(format!(
                "sslmode={v}: this client speaks plain TCP and has no TLS"
            )));
        }
    }
    let (auth, hostdb) = match rest.rsplit_once('@') {
        Some((a, h)) => (Some(a), h),
        None => (None, rest),
    };
    let (hostport, database) = match hostdb.split_once('/') {
        Some((h, d)) => (h, unescape(d)?),
        None => (hostdb, String::new()),
    };
    let (host, port) =
        split_host_port(hostport, 5432).map_err(|why| PgError::Url(format!("{url}: {why}")))?;
    let (user, password) = match auth {
        Some(a) => match a.split_once(':') {
            Some((u, p)) => (unescape(u)?, Some(unescape(p)?)),
            None => (unescape(a)?, None),
        },
        None => (String::new(), None),
    };
    if user.is_empty() {
        return Err(PgError::Url(format!(
            "{url}: no user (postgres://user@host/db)"
        )));
    }
    let database = if database.is_empty() {
        user.clone()
    } else {
        database
    };
    Ok(Target {
        host,
        port,
        user,
        password,
        database,
    })
}

fn put_cstr(out: &mut Vec<u8>, s: &str) {
    out.extend_from_slice(s.as_bytes());
    out.push(0);
}

fn message(tag: u8, body: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(body.len() + 5);
    out.push(tag);
    out.extend_from_slice(
        &i32::try_from(body.len() + 4)
            .unwrap_or(i32::MAX)
            .to_be_bytes(),
    );
    out.extend_from_slice(body);
    out
}

pub fn startup(target: &Target) -> Vec<u8> {
    let mut body = Vec::new();
    body.extend_from_slice(&PROTOCOL_V3.to_be_bytes());
    put_cstr(&mut body, "user");
    put_cstr(&mut body, &target.user);
    put_cstr(&mut body, "database");
    put_cstr(&mut body, &target.database);
    put_cstr(&mut body, "client_encoding");
    put_cstr(&mut body, "UTF8");
    body.push(0);
    let mut out = Vec::with_capacity(body.len() + 4);
    out.extend_from_slice(
        &i32::try_from(body.len() + 4)
            .unwrap_or(i32::MAX)
            .to_be_bytes(),
    );
    out.extend_from_slice(&body);
    out
}

#[derive(Debug, Clone, PartialEq)]
pub enum Param {
    Null,
    Text(String),
}

pub fn extended_query(sql: &str, params: &[Param]) -> Vec<u8> {
    let mut parse = Vec::new();
    put_cstr(&mut parse, "");
    put_cstr(&mut parse, sql);
    parse.extend_from_slice(&0i16.to_be_bytes());
    let mut bind = Vec::new();
    put_cstr(&mut bind, "");
    put_cstr(&mut bind, "");
    bind.extend_from_slice(&0i16.to_be_bytes());
    bind.extend_from_slice(
        &i16::try_from(params.len())
            .unwrap_or(i16::MAX)
            .to_be_bytes(),
    );
    for p in params {
        match p {
            Param::Null => bind.extend_from_slice(&(-1i32).to_be_bytes()),
            Param::Text(t) => {
                bind.extend_from_slice(&i32::try_from(t.len()).unwrap_or(i32::MAX).to_be_bytes());
                bind.extend_from_slice(t.as_bytes());
            }
        }
    }
    bind.extend_from_slice(&0i16.to_be_bytes());
    let mut describe = vec![b'P'];
    describe.push(0);
    let mut execute = Vec::new();
    put_cstr(&mut execute, "");
    execute.extend_from_slice(&0i32.to_be_bytes());
    let mut out = message(b'P', &parse);
    out.extend(message(b'B', &bind));
    out.extend(message(b'D', &describe));
    out.extend(message(b'E', &execute));
    out.extend(message(b'S', &[]));
    out
}

pub fn simple_query(sql: &str) -> Vec<u8> {
    let mut body = Vec::new();
    put_cstr(&mut body, sql);
    message(b'Q', &body)
}

struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Reader { bytes, at: 0 }
    }

    fn take(&mut self, n: usize) -> Result<&'a [u8], PgError> {
        let end = self.at.checked_add(n).filter(|e| *e <= self.bytes.len());
        let end = end.ok_or_else(|| PgError::Protocol("a message ended early".into()))?;
        let out = &self.bytes[self.at..end];
        self.at = end;
        Ok(out)
    }

    fn i16(&mut self) -> Result<i16, PgError> {
        let b = self.take(2)?;
        Ok(i16::from_be_bytes([b[0], b[1]]))
    }

    fn i32(&mut self) -> Result<i32, PgError> {
        let b = self.take(4)?;
        Ok(i32::from_be_bytes([b[0], b[1], b[2], b[3]]))
    }

    fn cstr(&mut self) -> Result<String, PgError> {
        let rest = &self.bytes[self.at..];
        let n = rest
            .iter()
            .position(|b| *b == 0)
            .ok_or_else(|| PgError::Protocol("an unterminated string".into()))?;
        let s = String::from_utf8_lossy(&rest[..n]).into_owned();
        self.at += n + 1;
        Ok(s)
    }

    fn rest(&self) -> &'a [u8] {
        &self.bytes[self.at..]
    }
}

pub fn server_error(body: &[u8]) -> PgError {
    let mut r = Reader::new(body);
    let mut code = String::new();
    let mut message = String::new();
    while let Ok(kind) = r.take(1) {
        if kind[0] == 0 {
            break;
        }
        let value = r.cstr().unwrap_or_default();
        match kind[0] {
            b'C' => code = value,
            b'M' => message = value,
            _ => {}
        }
    }
    PgError::Server { code, message }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Column {
    pub name: String,
    pub type_oid: i32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Cell {
    Null,
    Text(String),
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Outcome {
    pub columns: Vec<Column>,
    pub rows: Vec<Vec<Cell>>,
    pub commands: Vec<String>,
}

pub fn row_description(body: &[u8]) -> Result<Vec<Column>, PgError> {
    let mut r = Reader::new(body);
    let n = r.i16()?;
    (0..n)
        .map(|_| {
            let name = r.cstr()?;
            r.i32()?;
            r.i16()?;
            let type_oid = r.i32()?;
            r.i16()?;
            r.i32()?;
            r.i16()?;
            Ok(Column { name, type_oid })
        })
        .collect()
}

pub fn data_row(body: &[u8]) -> Result<Vec<Cell>, PgError> {
    let mut r = Reader::new(body);
    let n = r.i16()?;
    (0..n)
        .map(|_| {
            let len = r.i32()?;
            if len < 0 {
                Ok(Cell::Null)
            } else {
                let bytes = r.take(usize::try_from(len).unwrap_or(0))?;
                Ok(Cell::Text(String::from_utf8_lossy(bytes).into_owned()))
            }
        })
        .collect()
}

fn hmac(key: &[u8], data: &[u8]) -> [u8; 32] {
    let mut k = [0u8; 64];
    if key.len() > 64 {
        k[..32].copy_from_slice(&Sha256::digest(key));
    } else {
        k[..key.len()].copy_from_slice(key);
    }
    let mut inner = Sha256::new();
    inner.update(k.map(|b| b ^ 0x36));
    inner.update(data);
    let inner = inner.finalize();
    let mut outer = Sha256::new();
    outer.update(k.map(|b| b ^ 0x5c));
    outer.update(inner);
    outer.finalize().into()
}

fn pbkdf2(password: &[u8], salt: &[u8], iterations: u32) -> [u8; 32] {
    let mut block = salt.to_vec();
    block.extend_from_slice(&1u32.to_be_bytes());
    let mut u = hmac(password, &block);
    let mut out = u;
    for _ in 1..iterations {
        u = hmac(password, &u);
        for (o, b) in out.iter_mut().zip(u.iter()) {
            *o ^= b;
        }
    }
    out
}

const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn base64(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = chunk.len();
        let v = u32::from(chunk[0]) << 16
            | u32::from(*chunk.get(1).unwrap_or(&0)) << 8
            | u32::from(*chunk.get(2).unwrap_or(&0));
        for i in 0..4 {
            if i <= n {
                out.push(char::from(B64[((v >> (18 - 6 * i)) & 63) as usize]));
            } else {
                out.push('=');
            }
        }
    }
    out
}

pub fn unbase64(s: &str) -> Result<Vec<u8>, PgError> {
    let mut out = Vec::new();
    let mut acc = 0u32;
    let mut bits = 0;
    for c in s.bytes().filter(|c| *c != b'=') {
        let v = B64
            .iter()
            .position(|b| *b == c)
            .ok_or_else(|| PgError::Auth(format!("{s:?} is not base64")))?;
        acc = acc << 6 | u32::try_from(v).unwrap_or(0);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(u8::try_from((acc >> bits) & 0xff).unwrap_or(0));
        }
    }
    Ok(out)
}

pub struct Scram {
    nonce: String,
    first_bare: String,
    server_signature: Option<[u8; 32]>,
}

impl Scram {
    pub fn new(nonce: String) -> Self {
        let first_bare = format!("n=,r={nonce}");
        Scram {
            nonce,
            first_bare,
            server_signature: None,
        }
    }

    pub fn client_first(&self) -> String {
        format!("n,,{}", self.first_bare)
    }

    pub fn client_final(&mut self, password: &str, server_first: &str) -> Result<String, PgError> {
        let mut nonce = None;
        let mut salt = None;
        let mut iterations = None;
        for part in server_first.split(',') {
            match part.split_once('=') {
                Some(("r", v)) => nonce = Some(v.to_string()),
                Some(("s", v)) => salt = Some(unbase64(v)?),
                Some(("i", v)) => iterations = v.parse::<u32>().ok(),
                _ => {}
            }
        }
        let (Some(nonce), Some(salt), Some(iterations)) = (nonce, salt, iterations) else {
            return Err(PgError::Auth(format!(
                "server-first message {server_first:?}"
            )));
        };
        if !nonce.starts_with(&self.nonce) || iterations == 0 {
            return Err(PgError::Auth(
                "the server's nonce does not extend ours".into(),
            ));
        }
        let salted = pbkdf2(password.as_bytes(), &salt, iterations);
        let client_key = hmac(&salted, b"Client Key");
        let stored_key: [u8; 32] = Sha256::digest(client_key).into();
        let without_proof = format!("c=biws,r={nonce}");
        let auth_message = format!("{},{server_first},{without_proof}", self.first_bare);
        let signature = hmac(&stored_key, auth_message.as_bytes());
        let proof: Vec<u8> = client_key
            .iter()
            .zip(signature.iter())
            .map(|(a, b)| a ^ b)
            .collect();
        let server_key = hmac(&salted, b"Server Key");
        self.server_signature = Some(hmac(&server_key, auth_message.as_bytes()));
        Ok(format!("{without_proof},p={}", base64(&proof)))
    }

    pub fn verify(&self, server_final: &str) -> Result<(), PgError> {
        let v = server_final
            .strip_prefix("v=")
            .ok_or_else(|| PgError::Auth(format!("server-final message {server_final:?}")))?;
        match self.server_signature {
            Some(sig) if unbase64(v)? == sig => Ok(()),
            _ => Err(PgError::Auth(
                "the server's signature does not verify".into(),
            )),
        }
    }
}

fn nonce() -> String {
    let mut bytes = [0u8; 18];
    if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut bytes);
    }
    base64(&bytes)
}

pub struct Conn {
    stream: TcpStream,
    buf: Vec<u8>,
}

impl Conn {
    pub fn connect(target: &Target, timeout: Duration) -> Result<Conn, PgError> {
        let stream = dial(&target.host, target.port, timeout).map_err(PgError::Io)?;
        stream
            .set_read_timeout(Some(timeout))
            .and_then(|()| stream.set_write_timeout(Some(timeout)))
            .map_err(|e| PgError::Io(e.to_string()))?;
        let mut c = Conn {
            stream,
            buf: Vec::new(),
        };
        c.send(&startup(target))?;
        let mut scram: Option<Scram> = None;
        loop {
            let (tag, body) = c.next()?;
            match tag {
                b'R' => {
                    let mut r = Reader::new(&body);
                    match r.i32()? {
                        0 => {}
                        3 => {
                            let pw = target.password.as_deref().ok_or_else(|| {
                                PgError::Auth(
                                    "the server asks for a password and the url has none".into(),
                                )
                            })?;
                            let mut b = Vec::new();
                            put_cstr(&mut b, pw);
                            c.send(&message(b'p', &b))?;
                        }
                        5 => {
                            return Err(PgError::Unsupported(
                                "md5 password authentication; use scram-sha-256 or trust".into(),
                            ))
                        }
                        10 => {
                            let mut mechanisms = Vec::new();
                            loop {
                                let m = r.cstr()?;
                                if m.is_empty() {
                                    break;
                                }
                                mechanisms.push(m);
                            }
                            if !mechanisms.iter().any(|m| m == "SCRAM-SHA-256") {
                                return Err(PgError::Unsupported(format!(
                                    "SASL mechanisms {mechanisms:?}; this client speaks SCRAM-SHA-256"
                                )));
                            }
                            if target.password.is_none() {
                                return Err(PgError::Auth(
                                    "the server asks for a password and the url has none".into(),
                                ));
                            }
                            let s = Scram::new(nonce());
                            let first = s.client_first();
                            let mut b = Vec::new();
                            put_cstr(&mut b, "SCRAM-SHA-256");
                            b.extend_from_slice(
                                &i32::try_from(first.len()).unwrap_or(0).to_be_bytes(),
                            );
                            b.extend_from_slice(first.as_bytes());
                            c.send(&message(b'p', &b))?;
                            scram = Some(s);
                        }
                        11 => {
                            let s = scram.as_mut().ok_or_else(|| {
                                PgError::Protocol("SASL continue before SASL".into())
                            })?;
                            let server_first = String::from_utf8_lossy(r.rest()).into_owned();
                            let fin = s.client_final(
                                target.password.as_deref().unwrap_or(""),
                                &server_first,
                            )?;
                            c.send(&message(b'p', fin.as_bytes()))?;
                        }
                        12 => {
                            let s = scram.as_ref().ok_or_else(|| {
                                PgError::Protocol("SASL final before SASL".into())
                            })?;
                            s.verify(&String::from_utf8_lossy(r.rest()))?;
                        }
                        other => {
                            return Err(PgError::Unsupported(format!(
                                "authentication method {other}"
                            )))
                        }
                    }
                }
                b'E' => return Err(server_error(&body)),
                b'Z' => return Ok(c),
                _ => {}
            }
        }
    }

    fn send(&mut self, bytes: &[u8]) -> Result<(), PgError> {
        self.stream
            .write_all(bytes)
            .map_err(|e| PgError::Io(format!("sending: {e}")))
    }

    fn next(&mut self) -> Result<(u8, Vec<u8>), PgError> {
        loop {
            if self.buf.len() >= 5 {
                let len = i32::from_be_bytes([self.buf[1], self.buf[2], self.buf[3], self.buf[4]]);
                let len = usize::try_from(len)
                    .map_err(|_| PgError::Protocol("a negative length".into()))?;
                if len > MAX_MESSAGE {
                    return Err(PgError::Protocol(format!("a {len}-byte message")));
                }
                if self.buf.len() > len {
                    let tag = self.buf[0];
                    let body = self.buf[5..=len].to_vec();
                    self.buf.drain(..=len);
                    return Ok((tag, body));
                }
            }
            let mut chunk = [0u8; 16 * 1024];
            match self.stream.read(&mut chunk) {
                Ok(0) => return Err(PgError::Io("the server closed the connection".into())),
                Ok(n) => self.buf.extend_from_slice(&chunk[..n]),
                Err(e) if e.kind() == ErrorKind::Interrupted => {}
                Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
                    return Err(PgError::Io("timed out waiting for the server".into()))
                }
                Err(e) => return Err(PgError::Io(e.to_string())),
            }
        }
    }

    fn collect(&mut self) -> Result<Outcome, PgError> {
        let mut out = Outcome::default();
        let mut failure = None;
        loop {
            let (tag, body) = self.next()?;
            match tag {
                b'T' => out.columns = row_description(&body)?,
                b'D' => out.rows.push(data_row(&body)?),
                b'C' => out.commands.push(Reader::new(&body).cstr()?),
                b'E' => failure = Some(server_error(&body)),
                b'Z' => {
                    return match failure {
                        Some(e) => Err(e),
                        None => Ok(out),
                    }
                }
                _ => {}
            }
        }
    }

    pub fn query(&mut self, sql: &str, params: &[Param]) -> Result<Outcome, PgError> {
        self.send(&extended_query(sql, params))?;
        self.collect()
    }

    pub fn execute(&mut self, sql: &str) -> Result<Outcome, PgError> {
        self.send(&simple_query(sql))?;
        self.collect()
    }

    pub fn close(&mut self) {
        let _ = self.send(&message(b'X', &[]));
        let _ = self.stream.shutdown(std::net::Shutdown::Both);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn urls_parse_with_defaults_escapes_and_refusals() {
        let t = parse_url("postgres://pangea@127.0.0.1/pangea_state").unwrap();
        assert_eq!(
            (
                t.host.as_str(),
                t.port,
                t.user.as_str(),
                t.database.as_str()
            ),
            ("127.0.0.1", 5432, "pangea", "pangea_state")
        );
        assert_eq!(t.password, None);
        let t = parse_url(&["postgresql://u", ":", "p%40ss", "@db:6543"].concat()).unwrap();
        assert_eq!(
            (t.port, t.password.as_deref(), t.database.as_str()),
            (6543, Some("p@ss"), "u")
        );
        assert!(parse_url("mysql://u@h/d").is_err());
        assert!(parse_url("postgres://h/d").is_err());
        let tls = parse_url("postgres://u@h/d?sslmode=require")
            .unwrap_err()
            .to_string();
        assert!(tls.contains("no TLS"), "{tls}");
        assert!(parse_url("postgres://u@h/d?sslmode=disable").is_ok());
    }

    #[test]
    fn the_startup_and_extended_messages_have_the_wire_shape() {
        let t = parse_url("postgres://ana@h/db").unwrap();
        let s = startup(&t);
        assert_eq!(&s[4..8], &PROTOCOL_V3.to_be_bytes());
        assert_eq!(
            i32::from_be_bytes([s[0], s[1], s[2], s[3]]) as usize,
            s.len()
        );
        assert!(s.windows(4).any(|w| w == b"ana\0"));
        let q = extended_query("select $1", &[Param::Text("x".into()), Param::Null]);
        let tags: Vec<u8> = {
            let mut tags = Vec::new();
            let mut at = 0;
            while at < q.len() {
                tags.push(q[at]);
                let len = i32::from_be_bytes([q[at + 1], q[at + 2], q[at + 3], q[at + 4]]) as usize;
                at += len + 1;
            }
            tags
        };
        assert_eq!(tags, b"PBDES");
        assert!(q.windows(4).any(|w| w == (-1i32).to_be_bytes()));
    }

    #[test]
    fn rows_errors_and_descriptions_decode() {
        let mut desc = 2i16.to_be_bytes().to_vec();
        for (name, oid) in [("id", 20i32), ("text", 25)] {
            put_cstr(&mut desc, name);
            desc.extend_from_slice(&0i32.to_be_bytes());
            desc.extend_from_slice(&0i16.to_be_bytes());
            desc.extend_from_slice(&oid.to_be_bytes());
            desc.extend_from_slice(&8i16.to_be_bytes());
            desc.extend_from_slice(&(-1i32).to_be_bytes());
            desc.extend_from_slice(&0i16.to_be_bytes());
        }
        let cols = row_description(&desc).unwrap();
        assert_eq!(
            cols[1],
            Column {
                name: "text".into(),
                type_oid: 25
            }
        );
        let mut row = 2i16.to_be_bytes().to_vec();
        row.extend_from_slice(&1i32.to_be_bytes());
        row.push(b'7');
        row.extend_from_slice(&(-1i32).to_be_bytes());
        assert_eq!(
            data_row(&row).unwrap(),
            vec![Cell::Text("7".into()), Cell::Null]
        );
        assert!(data_row(&2i16.to_be_bytes()).is_err());
        let mut err = Vec::new();
        for (k, v) in [
            (b'S', "ERROR"),
            (b'C', "42P01"),
            (b'M', "relation \"x\" does not exist"),
        ] {
            err.push(k);
            put_cstr(&mut err, v);
        }
        err.push(0);
        assert_eq!(
            server_error(&err).to_string(),
            "42P01: relation \"x\" does not exist"
        );
    }

    #[test]
    fn base64_round_trips_and_refuses_garbage() {
        for bytes in [&b""[..], b"f", b"fo", b"foo", b"foob", &[0xff, 0, 0x7f]] {
            assert_eq!(unbase64(&base64(bytes)).unwrap(), bytes);
        }
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
        assert!(unbase64("a$b").is_err());
    }

    #[test]
    fn hmac_and_pbkdf2_match_their_published_vectors() {
        let h = hmac(b"key", b"The quick brown fox jumps over the lazy dog");
        assert_eq!(
            h.iter().map(|b| format!("{b:02x}")).collect::<String>(),
            "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
        );
        let k = pbkdf2(b"password", b"salt", 2);
        assert_eq!(
            k.iter().map(|b| format!("{b:02x}")).collect::<String>(),
            "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"
        );
    }

    #[test]
    fn scram_follows_rfc7677s_exchange() {
        let mut s = Scram::new("rOprNGfwEbeRWgbNEkqO".into());
        assert_eq!(s.client_first(), "n,,n=,r=rOprNGfwEbeRWgbNEkqO");
        let server_first = "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096";
        let fin = s.client_final("pencil", server_first).unwrap();
        assert!(
            fin.starts_with("c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p="),
            "{fin}"
        );
        assert!(s.verify("v=AAAA").is_err());
        assert!(Scram::new("abc".into())
            .client_final("x", "r=zzz,s=AAAA,i=1")
            .is_err());
    }
}
