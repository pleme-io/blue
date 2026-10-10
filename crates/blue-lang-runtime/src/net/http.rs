//! HTTP/1.1 over a `TcpStream`, one request per connection.
//!
//! Plain `http://` only. The workspace carries no TLS implementation, and
//! adding one is a dependency decision this module does not make; an
//! `https://` URL is refused by name rather than sent in the clear.
//!
//! The request closes its connection (`Connection: close`), so a response
//! ends at its `Content-Length`, at the last chunk of a chunked body, or at
//! EOF. [`parse_response`] decides which from bytes alone, so it is tested
//! without a socket.

use std::fmt;
use std::io::{ErrorKind, Read, Write};
use std::time::{Duration, Instant};

use super::{dial, split_host_port};

const MAX_RESPONSE: usize = 64 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HttpError {
    Url(String),
    Request(String),
    Io(String),
    Timeout(String),
    Response(String),
}

impl fmt::Display for HttpError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            HttpError::Url(why) => write!(f, "bad url: {why}"),
            HttpError::Request(why) => write!(f, "bad request: {why}"),
            HttpError::Io(why) => write!(f, "{why}"),
            HttpError::Timeout(why) => write!(f, "timed out: {why}"),
            HttpError::Response(why) => write!(f, "malformed response: {why}"),
        }
    }
}

impl std::error::Error for HttpError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Target {
    pub host: String,
    pub port: u16,
    pub path: String,
}

pub fn parse_url(url: &str) -> Result<Target, HttpError> {
    let rest = match url.split_once("://") {
        Some(("http", rest)) => rest,
        Some(("https", _)) => {
            return Err(HttpError::Url(format!(
                "{url}: https is not supported; blue's HTTP client speaks plain http only"
            )));
        }
        Some((scheme, _)) => {
            return Err(HttpError::Url(format!(
                "{url}: scheme {scheme:?} is not http"
            )));
        }
        None => return Err(HttpError::Url(format!("{url}: no scheme (http://…)"))),
    };
    let (authority, path) = match rest.find(['/', '?']) {
        Some(i) if rest.as_bytes()[i] == b'/' => (&rest[..i], rest[i..].to_string()),
        Some(i) => (&rest[..i], format!("/{}", &rest[i..])),
        None => (rest, "/".to_string()),
    };
    let path = path.split('#').next().unwrap_or("/").to_string();
    if authority.contains('@') {
        return Err(HttpError::Url(format!(
            "{url}: credentials in the url are not sent; pass an authorization header"
        )));
    }
    if path.bytes().any(|b| b <= b' ' || b == 0x7f) {
        return Err(HttpError::Url(format!(
            "{url}: the path has whitespace or control characters; percent-encode them"
        )));
    }
    let (host, port) =
        split_host_port(authority, 80).map_err(|why| HttpError::Url(format!("{url}: {why}")))?;
    Ok(Target { host, port, path })
}

fn is_token(s: &str) -> bool {
    !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"!#$%&'*+-.^_`|~".contains(&b))
}

const MANAGED: &[&str] = &["content-length", "transfer-encoding", "connection"];

pub fn encode_request(
    method: &str,
    target: &Target,
    headers: &[(String, String)],
    body: Option<&[u8]>,
) -> Result<Vec<u8>, HttpError> {
    if !is_token(method) {
        return Err(HttpError::Request(format!("{method:?} is not a method")));
    }
    let mut head = format!("{method} {} HTTP/1.1\r\n", target.path);
    let mut has_host = false;
    for (name, value) in headers {
        if !is_token(name) {
            return Err(HttpError::Request(format!("{name:?} is not a header name")));
        }
        if value.bytes().any(|b| b == b'\r' || b == b'\n' || b == 0) {
            return Err(HttpError::Request(format!(
                "the value of header {name} contains a line break"
            )));
        }
        let lower = name.to_ascii_lowercase();
        if MANAGED.contains(&lower.as_str()) {
            return Err(HttpError::Request(format!(
                "header {name} is set by http_request itself"
            )));
        }
        has_host |= lower == "host";
        head.push_str(&format!("{name}: {value}\r\n"));
    }
    if !has_host {
        let host = if target.host.contains(':') {
            format!("[{}]", target.host)
        } else {
            target.host.clone()
        };
        if target.port == 80 {
            head.push_str(&format!("Host: {host}\r\n"));
        } else {
            head.push_str(&format!("Host: {host}:{}\r\n", target.port));
        }
    }
    let body = body.unwrap_or_default();
    if !body.is_empty() || matches!(method, "POST" | "PUT" | "PATCH") {
        head.push_str(&format!("Content-Length: {}\r\n", body.len()));
    }
    head.push_str("Connection: close\r\n\r\n");
    let mut out = head.into_bytes();
    out.extend_from_slice(body);
    Ok(out)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Response {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}

fn malformed(why: impl Into<String>) -> HttpError {
    HttpError::Response(why.into())
}

/// The response in `buf`, `None` while more bytes are needed. `eof` says the
/// peer has closed, which is what ends a body with no length. A `1xx` interim
/// response is skipped.
pub fn parse_response(
    buf: &[u8],
    eof: bool,
    head_only: bool,
) -> Result<Option<Response>, HttpError> {
    let mut start = 0;
    loop {
        let Some(end) = find(&buf[start..], b"\r\n\r\n").map(|i| start + i) else {
            return if eof {
                Err(malformed("the connection closed inside the headers"))
            } else {
                Ok(None)
            };
        };
        let head = std::str::from_utf8(&buf[start..end])
            .map_err(|_| malformed("headers are not UTF-8"))?;
        let mut lines = head.split("\r\n");
        let status_line = lines.next().unwrap_or_default();
        let mut parts = status_line.splitn(3, ' ');
        let version = parts.next().unwrap_or_default();
        if !version.starts_with("HTTP/1.") {
            return Err(malformed(format!("status line {status_line:?}")));
        }
        let status: u16 = parts
            .next()
            .and_then(|s| s.parse().ok())
            .filter(|s| (100..1000).contains(s))
            .ok_or_else(|| malformed(format!("status line {status_line:?}")))?;
        let mut headers = Vec::new();
        for line in lines {
            let (name, value) = line
                .split_once(':')
                .ok_or_else(|| malformed(format!("header line {line:?}")))?;
            headers.push((name.trim().to_ascii_lowercase(), value.trim().to_string()));
        }
        let body_start = end + 4;
        if (100..200).contains(&status) {
            start = body_start;
            continue;
        }
        let rest = &buf[body_start..];
        let header = |n: &str| {
            headers
                .iter()
                .find(|(k, _)| k == n)
                .map(|(_, v)| v.as_str())
        };
        let body = if head_only || status == 204 || status == 304 {
            Some(Vec::new())
        } else if header("transfer-encoding")
            .is_some_and(|v| v.to_ascii_lowercase().contains("chunked"))
        {
            dechunk(rest)?
        } else if let Some(len) = header("content-length") {
            let len: usize = len
                .parse()
                .map_err(|_| malformed(format!("content-length {len:?}")))?;
            if rest.len() >= len {
                Some(rest[..len].to_vec())
            } else if eof {
                return Err(malformed(format!(
                    "the body ended at {} of {len} bytes",
                    rest.len()
                )));
            } else {
                None
            }
        } else if eof {
            Some(rest.to_vec())
        } else {
            None
        };
        return match body {
            Some(body) => Ok(Some(Response {
                status,
                headers,
                body,
            })),
            None if eof => Err(malformed("the connection closed inside the body")),
            None => Ok(None),
        };
    }
}

fn dechunk(mut rest: &[u8]) -> Result<Option<Vec<u8>>, HttpError> {
    let mut body = Vec::new();
    loop {
        let Some(eol) = find(rest, b"\r\n") else {
            return Ok(None);
        };
        let size_line = std::str::from_utf8(&rest[..eol]).map_err(|_| malformed("chunk size"))?;
        let size_hex = size_line.split(';').next().unwrap_or_default().trim();
        let size = usize::from_str_radix(size_hex, 16)
            .map_err(|_| malformed(format!("chunk size {size_hex:?}")))?;
        rest = &rest[eol + 2..];
        if size == 0 {
            return Ok(find(rest, b"\r\n")
                .filter(|&i| i == 0 || find(rest, b"\r\n\r\n").is_some())
                .map(|_| body));
        }
        if rest.len() < size + 2 {
            return Ok(None);
        }
        if &rest[size..size + 2] != b"\r\n" {
            return Err(malformed("a chunk is not followed by CRLF"));
        }
        body.extend_from_slice(&rest[..size]);
        rest = &rest[size + 2..];
    }
}

pub fn request(
    method: &str,
    url: &str,
    headers: &[(String, String)],
    body: Option<&[u8]>,
    timeout: Duration,
) -> Result<Response, HttpError> {
    let target = parse_url(url)?;
    let wire = encode_request(method, &target, headers, body)?;
    let deadline = Instant::now() + timeout;
    let mut stream = dial(&target.host, target.port, timeout).map_err(HttpError::Io)?;
    let left = |what: &str| {
        let d = deadline.saturating_duration_since(Instant::now());
        if d.is_zero() {
            Err(HttpError::Timeout(format!("{method} {url}: {what}")))
        } else {
            Ok(d)
        }
    };
    stream
        .set_write_timeout(Some(left("sending")?))
        .map_err(|e| HttpError::Io(e.to_string()))?;
    stream.write_all(&wire).map_err(|e| match e.kind() {
        ErrorKind::WouldBlock | ErrorKind::TimedOut => {
            HttpError::Timeout(format!("{method} {url}: sending"))
        }
        _ => HttpError::Io(format!("{method} {url}: {e}")),
    })?;
    let head_only = method.eq_ignore_ascii_case("HEAD");
    let mut buf = Vec::new();
    let mut chunk = [0u8; 16 * 1024];
    loop {
        stream
            .set_read_timeout(Some(left("waiting for the response")?))
            .map_err(|e| HttpError::Io(e.to_string()))?;
        let eof = match stream.read(&mut chunk) {
            Ok(0) => true,
            Ok(n) => {
                buf.extend_from_slice(&chunk[..n]);
                false
            }
            Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
                return Err(HttpError::Timeout(format!(
                    "{method} {url}: no complete response within {} ms",
                    timeout.as_millis()
                )));
            }
            Err(e) if e.kind() == ErrorKind::Interrupted => false,
            Err(e) => return Err(HttpError::Io(format!("{method} {url}: {e}"))),
        };
        if buf.len() > MAX_RESPONSE {
            return Err(malformed(format!("larger than {MAX_RESPONSE} bytes")));
        }
        if let Some(resp) = parse_response(&buf, eof, head_only)? {
            return Ok(resp);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn target(path: &str) -> Target {
        Target {
            host: "127.0.0.1".into(),
            port: 8123,
            path: path.into(),
        }
    }

    #[test]
    fn urls_parse_and_https_is_refused() {
        assert_eq!(
            parse_url("http://127.0.0.1:8123/api/states?x=1#frag").unwrap(),
            target("/api/states?x=1")
        );
        assert_eq!(parse_url("http://h").unwrap().path, "/");
        assert_eq!(parse_url("http://h?q").unwrap().path, "/?q");
        assert_eq!(parse_url("http://h").unwrap().port, 80);
        let https = parse_url("https://h/").unwrap_err().to_string();
        assert!(https.contains("https is not supported"), "{https}");
        assert!(parse_url("h/x").is_err());
        assert!(parse_url("http://u:p@h/").is_err());
        assert!(parse_url("http://h/a b").is_err());
    }

    #[test]
    fn a_request_is_written_with_host_length_and_close() {
        let wire = encode_request(
            "POST",
            &target("/api/services/light/turn_on"),
            &[("Authorization".into(), "Bearer t".into())],
            Some(b"{}"),
        )
        .unwrap();
        assert_eq!(
            String::from_utf8(wire).unwrap(),
            "POST /api/services/light/turn_on HTTP/1.1\r\nAuthorization: Bearer t\r\nHost: 127.0.0.1:8123\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
        );
        let get =
            String::from_utf8(encode_request("GET", &target("/"), &[], None).unwrap()).unwrap();
        assert!(!get.contains("Content-Length"), "{get}");
    }

    #[test]
    fn header_injection_and_managed_headers_are_refused() {
        for (name, value) in [
            ("X", "a\r\nEvil: 1"),
            ("Bad Name", "v"),
            ("Content-Length", "3"),
            ("connection", "keep-alive"),
        ] {
            assert!(
                encode_request("GET", &target("/"), &[(name.into(), value.into())], None).is_err(),
                "{name}: {value:?}"
            );
        }
        assert!(encode_request("GE T", &target("/"), &[], None).is_err());
    }

    #[test]
    fn a_length_framed_response_waits_for_its_body() {
        let wire = b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 11\r\n\r\n{\"ok\":true}";
        for cut in 0..wire.len() {
            assert_eq!(
                parse_response(&wire[..cut], false, false),
                Ok(None),
                "cut at {cut}"
            );
        }
        let r = parse_response(wire, false, false).unwrap().unwrap();
        assert_eq!(r.status, 200);
        assert_eq!(
            r.headers[0],
            ("content-type".into(), "application/json".into())
        );
        assert_eq!(r.body, b"{\"ok\":true}");
    }

    #[test]
    fn a_chunked_response_decodes() {
        let wire = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n6;x=y\r\npedia \r\n0\r\n\r\n";
        for cut in 0..wire.len() {
            assert_eq!(
                parse_response(&wire[..cut], false, false),
                Ok(None),
                "cut at {cut}"
            );
        }
        assert_eq!(
            parse_response(wire, false, false).unwrap().unwrap().body,
            b"Wikipedia "
        );
    }

    #[test]
    fn an_unframed_body_ends_at_eof_and_interim_responses_are_skipped() {
        let wire = b"HTTP/1.1 100 Continue\r\n\r\nHTTP/1.0 404 Not Found\r\n\r\nnope";
        assert_eq!(parse_response(wire, false, false), Ok(None));
        let r = parse_response(wire, true, false).unwrap().unwrap();
        assert_eq!((r.status, r.body.as_slice()), (404, &b"nope"[..]));
    }

    #[test]
    fn truncated_and_garbage_responses_are_refused() {
        assert!(parse_response(
            b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nab",
            true,
            false
        )
        .is_err());
        assert!(parse_response(b"HTTP/1.1 200 OK\r\nX", true, false).is_err());
        assert!(parse_response(b"SSH-2.0-OpenSSH\r\n\r\n", false, false).is_err());
        assert!(parse_response(b"HTTP/1.1 abc OK\r\n\r\n", false, false).is_err());
    }

    #[test]
    fn head_and_no_content_have_no_body() {
        let r = parse_response(
            b"HTTP/1.1 200 OK\r\nContent-Length: 50\r\n\r\n",
            false,
            true,
        )
        .unwrap()
        .unwrap();
        assert!(r.body.is_empty());
        let r = parse_response(b"HTTP/1.1 204 No Content\r\n\r\n", false, false)
            .unwrap()
            .unwrap();
        assert_eq!(r.status, 204);
    }
}
