use std::fmt;
use std::io::{ErrorKind, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::time::{Duration, Instant};

const MAX_REQUEST: usize = 1024 * 1024;
const READ_MS: u64 = 5_000;
const ACCEPT_POLL_MS: u64 = 5;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ServeError {
    Bind(String),
    Io(String),
    Request(String),
    Response(String),
}

impl fmt::Display for ServeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ServeError::Bind(why) => write!(f, "cannot listen: {why}"),
            ServeError::Io(why) => write!(f, "{why}"),
            ServeError::Request(why) => write!(f, "malformed request: {why}"),
            ServeError::Response(why) => write!(f, "bad response: {why}"),
        }
    }
}

impl std::error::Error for ServeError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Request {
    pub method: String,
    pub path: String,
    pub query: String,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}

fn bad(why: impl Into<String>) -> ServeError {
    ServeError::Request(why.into())
}

fn is_token(s: &str) -> bool {
    !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"!#$%&'*+-.^_`|~".contains(&b))
}

pub fn parse_request(buf: &[u8]) -> Result<Option<Request>, ServeError> {
    let Some(end) = find(buf, b"\r\n\r\n") else {
        return Ok(None);
    };
    let head = std::str::from_utf8(&buf[..end]).map_err(|_| bad("headers are not UTF-8"))?;
    let mut lines = head.split("\r\n");
    let line = lines.next().unwrap_or_default();
    let mut parts = line.split(' ');
    let (Some(method), Some(target), Some(version), None) =
        (parts.next(), parts.next(), parts.next(), parts.next())
    else {
        return Err(bad(format!("request line {line:?}")));
    };
    if !is_token(method) || !version.starts_with("HTTP/1.") || !target.starts_with('/') {
        return Err(bad(format!("request line {line:?}")));
    }
    let (path, query) = match target.split_once('?') {
        Some((p, q)) => (p.to_string(), q.to_string()),
        None => (target.to_string(), String::new()),
    };
    let mut headers = Vec::new();
    for l in lines {
        let (name, value) = l
            .split_once(':')
            .ok_or_else(|| bad(format!("header line {l:?}")))?;
        if !is_token(name.trim()) {
            return Err(bad(format!("header line {l:?}")));
        }
        headers.push((name.trim().to_ascii_lowercase(), value.trim().to_string()));
    }
    if headers
        .iter()
        .any(|(k, v)| k == "transfer-encoding" && !v.eq_ignore_ascii_case("identity"))
    {
        return Err(bad("a chunked request body is not accepted"));
    }
    let len = match headers.iter().find(|(k, _)| k == "content-length") {
        Some((_, v)) => v
            .parse::<usize>()
            .map_err(|_| bad(format!("content-length {v:?}")))?,
        None => 0,
    };
    let rest = &buf[end + 4..];
    if rest.len() < len {
        return Ok(None);
    }
    Ok(Some(Request {
        method: method.to_string(),
        path,
        query,
        headers,
        body: rest[..len].to_vec(),
    }))
}

fn reason(status: u16) -> &'static str {
    match status {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        301 => "Moved Permanently",
        302 => "Found",
        304 => "Not Modified",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        500 => "Internal Server Error",
        503 => "Service Unavailable",
        _ => "Status",
    }
}

const MANAGED: &[&str] = &["content-length", "transfer-encoding", "connection"];

pub fn encode_response(
    status: u16,
    headers: &[(String, String)],
    body: &[u8],
) -> Result<Vec<u8>, ServeError> {
    if !(100..1000).contains(&status) {
        return Err(ServeError::Response(format!("{status} is not a status")));
    }
    let mut head = format!("HTTP/1.1 {status} {}\r\n", reason(status));
    for (name, value) in headers {
        if !is_token(name) {
            return Err(ServeError::Response(format!(
                "{name:?} is not a header name"
            )));
        }
        if value.bytes().any(|b| b == b'\r' || b == b'\n' || b == 0) {
            return Err(ServeError::Response(format!(
                "the value of header {name} contains a line break"
            )));
        }
        if MANAGED.contains(&name.to_ascii_lowercase().as_str()) {
            return Err(ServeError::Response(format!(
                "header {name} is set by http_respond itself"
            )));
        }
        head.push_str(&format!("{name}: {value}\r\n"));
    }
    head.push_str(&format!(
        "Content-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    ));
    let mut out = head.into_bytes();
    out.extend_from_slice(body);
    Ok(out)
}

pub struct Listener {
    inner: TcpListener,
}

impl Listener {
    pub fn bind(addr: &str) -> Result<Listener, ServeError> {
        let inner = TcpListener::bind(addr).map_err(|e| ServeError::Bind(format!("{addr}: {e}")))?;
        inner
            .set_nonblocking(true)
            .map_err(|e| ServeError::Bind(format!("{addr}: {e}")))?;
        Ok(Listener { inner })
    }

    pub fn local_addr(&self) -> Result<SocketAddr, ServeError> {
        self.inner
            .local_addr()
            .map_err(|e| ServeError::Io(e.to_string()))
    }

    pub fn next(&self, timeout: Duration) -> Result<Option<(Request, TcpStream)>, ServeError> {
        let deadline = Instant::now() + timeout;
        loop {
            match self.inner.accept() {
                Ok((stream, _)) => {
                    if let Some(req) = read_request(&stream)? {
                        return Ok(Some((req, stream)));
                    }
                }
                Err(e) if e.kind() == ErrorKind::WouldBlock => {}
                Err(e) if e.kind() == ErrorKind::Interrupted => {}
                Err(e) => return Err(ServeError::Io(format!("accept: {e}"))),
            }
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return Ok(None);
            }
            std::thread::sleep(left.min(Duration::from_millis(ACCEPT_POLL_MS)));
        }
    }
}

fn read_request(stream: &TcpStream) -> Result<Option<Request>, ServeError> {
    let mut s = stream;
    s.set_nonblocking(false)
        .and_then(|()| s.set_read_timeout(Some(Duration::from_millis(READ_MS))))
        .map_err(|e| ServeError::Io(e.to_string()))?;
    let mut buf = Vec::new();
    let mut chunk = [0u8; 16 * 1024];
    loop {
        let n = match s.read(&mut chunk) {
            Ok(n) => n,
            Err(e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(_) => return Ok(None),
        };
        if n == 0 {
            return Ok(None);
        }
        buf.extend_from_slice(&chunk[..n]);
        if buf.len() > MAX_REQUEST {
            let _ = respond(stream, 400, &[], b"request too large");
            return Ok(None);
        }
        match parse_request(&buf) {
            Ok(Some(req)) => return Ok(Some(req)),
            Ok(None) => {}
            Err(e) => {
                let _ = respond(stream, 400, &[], e.to_string().as_bytes());
                return Ok(None);
            }
        }
    }
}

pub fn respond(
    stream: &TcpStream,
    status: u16,
    headers: &[(String, String)],
    body: &[u8],
) -> Result<(), ServeError> {
    let wire = encode_response(status, headers, body)?;
    let mut s = stream;
    s.write_all(&wire)
        .and_then(|()| s.flush())
        .map_err(|e| ServeError::Io(format!("responding: {e}")))?;
    let _ = stream.shutdown(std::net::Shutdown::Both);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_request_parses_once_its_body_is_complete() {
        let wire = b"POST /greet?name=x HTTP/1.1\r\nHost: h\r\nContent-Length: 2\r\n\r\nhi";
        for cut in 0..wire.len() {
            assert_eq!(parse_request(&wire[..cut]), Ok(None), "cut at {cut}");
        }
        let r = parse_request(wire).unwrap().unwrap();
        assert_eq!(r.method, "POST");
        assert_eq!(r.path, "/greet");
        assert_eq!(r.query, "name=x");
        assert_eq!(r.headers[0], ("host".into(), "h".into()));
        assert_eq!(r.body, b"hi");
    }

    #[test]
    fn malformed_requests_are_refused() {
        for wire in [
            &b"GET\r\n\r\n"[..],
            b"GET / HTTP/1.1 extra\r\n\r\n",
            b"GET nope HTTP/1.1\r\n\r\n",
            b"GET / SSH-2.0\r\n\r\n",
            b"GET / HTTP/1.1\r\nno colon\r\n\r\n",
            b"POST / HTTP/1.1\r\nContent-Length: x\r\n\r\n",
            b"POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n",
        ] {
            assert!(parse_request(wire).is_err(), "{:?}", String::from_utf8_lossy(wire));
        }
    }

    #[test]
    fn a_response_carries_its_length_and_closes() {
        let wire = encode_response(200, &[("Content-Type".into(), "text/plain".into())], b"hello")
            .unwrap();
        assert_eq!(
            String::from_utf8(wire).unwrap(),
            "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello"
        );
        assert!(encode_response(99, &[], b"").is_err());
        assert!(encode_response(200, &[("X".into(), "a\r\nb".into())], b"").is_err());
        assert!(encode_response(200, &[("content-length".into(), "1".into())], b"").is_err());
    }

    #[test]
    fn a_listener_answers_a_real_client_and_times_out_when_idle() {
        let l = Listener::bind("127.0.0.1:0").unwrap();
        let addr = l.local_addr().unwrap();
        assert!(l.next(Duration::from_millis(20)).unwrap().is_none());
        let client = std::thread::spawn(move || {
            super::super::http::request(
                "GET",
                &format!("http://{addr}/healthz"),
                &[],
                None,
                Duration::from_secs(5),
            )
            .unwrap()
        });
        let (req, stream) = l.next(Duration::from_secs(5)).unwrap().unwrap();
        assert_eq!(req.path, "/healthz");
        respond(&stream, 200, &[], b"ok").unwrap();
        let resp = client.join().unwrap();
        assert_eq!((resp.status, resp.body.as_slice()), (200, &b"ok"[..]));
    }
}
