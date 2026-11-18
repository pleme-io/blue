//! The proxy pass-through: one upstream request whose body and reply are
//! files, never interpreter values.
//!
//! `http_request` buffers both directions in memory (64 MiB cap), which is
//! right for an API call and wrong for a registry blob: the interpreted
//! layer must not sit under the byte stream. `pipe` writes the request head,
//! streams a body file to the socket, reads the response head, and spools
//! the response body — content-length framed, chunked (decoded while
//! spooling), or to EOF — to a file it returns by path, for
//! `http_respond`'s `{file: …}` seam. Blue decides on the status and the
//! headers; the bytes stay host-side end to end.
//!
//! The spool file is blue's to remove (`rm_rf`) once the exchange is
//! answered, the same discipline `http_respond` applies to a request's own
//! spooled body.

use std::fs::File;
use std::io::{ErrorKind, Read, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use super::dial;
use super::http::{parse_url, HttpError, Target};
use super::tls::Conn;

const CHUNK: usize = 64 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Piped {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body_file: Option<PathBuf>,
}

fn malformed(why: impl Into<String>) -> HttpError {
    HttpError::Response(why.into())
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}

struct Head {
    status: u16,
    headers: Vec<(String, String)>,
    rest: Vec<u8>,
}

fn parse_head(buf: &[u8]) -> Result<Option<Head>, HttpError> {
    let mut start = 0;
    loop {
        let Some(end) = find(&buf[start..], b"\r\n\r\n").map(|i| start + i) else {
            return Ok(None);
        };
        let head = std::str::from_utf8(&buf[start..end])
            .map_err(|_| malformed("the response head is not UTF-8"))?;
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
        let rest = buf[end + 4..].to_vec();
        if (100..200).contains(&status) {
            start = end + 4;
            if start >= buf.len() {
                return Ok(None);
            }
            continue;
        }
        return Ok(Some(Head {
            status,
            headers,
            rest,
        }));
    }
}

fn header<'a>(headers: &'a [(String, String)], name: &str) -> Option<&'a str> {
    headers
        .iter()
        .find(|(k, _)| k == name)
        .map(|(_, v)| v.as_str())
}

fn spool_path() -> PathBuf {
    let n = SPOOL_N.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    spool_path_for(n)
}

static SPOOL_N: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

fn spool_path_for(n: u64) -> PathBuf {
    std::env::temp_dir().join(format!("blue-http-pipe-{}-{n}.resp", std::process::id()))
}

#[cfg(test)]
fn peek_spool_path() -> PathBuf {
    spool_path_for(SPOOL_N.load(std::sync::atomic::Ordering::Relaxed))
}

struct Deadline(Instant);

impl Deadline {
    fn left(&self, what: &str, method: &str, url: &str) -> Result<Duration, HttpError> {
        let d = self.0.saturating_duration_since(Instant::now());
        if d.is_zero() {
            Err(HttpError::Timeout(format!("{method} {url}: {what}")))
        } else {
            Ok(d)
        }
    }
}

fn timeout_err(method: &str, url: &str, what: &str) -> HttpError {
    HttpError::Timeout(format!("{method} {url}: {what}"))
}

fn io_err(method: &str, url: &str, e: &std::io::Error, what: &str) -> HttpError {
    match e.kind() {
        ErrorKind::WouldBlock | ErrorKind::TimedOut => timeout_err(method, url, what),
        _ => HttpError::Io(format!("{method} {url}: {e}")),
    }
}

fn encode_head(
    method: &str,
    target: &Target,
    headers: &[(String, String)],
    body_len: u64,
) -> Result<Vec<u8>, HttpError> {
    super::http::encode_request_head(method, target, headers, body_len)
}

fn send_body(
    stream: &mut Conn,
    file: &Path,
    len: u64,
    deadline: &Deadline,
    method: &str,
    url: &str,
) -> Result<(), HttpError> {
    let mut file =
        File::open(file).map_err(|e| HttpError::Request(format!("{}: {e}", file.display())))?;
    let mut sent = 0u64;
    let mut chunk = vec![0u8; CHUNK];
    while sent < len {
        let want = ((len - sent) as usize).min(CHUNK);
        let n = file
            .read(&mut chunk[..want])
            .map_err(|e| io_err(method, url, &e, "reading the body file"))?;
        if n == 0 {
            return Err(HttpError::Request(format!(
                "the body file ended at {sent} of {len} bytes"
            )));
        }
        stream
            .sock()
            .set_write_timeout(Some(deadline.left("sending the body", method, url)?))
            .map_err(|e| HttpError::Io(e.to_string()))?;
        stream
            .write_all(&chunk[..n])
            .map_err(|e| io_err(method, url, &e, "sending the body"))?;
        sent += n as u64;
    }
    Ok(())
}

fn read_head(
    stream: &mut Conn,
    deadline: &Deadline,
    method: &str,
    url: &str,
) -> Result<Head, HttpError> {
    let mut buf = Vec::new();
    let mut chunk = [0u8; CHUNK];
    loop {
        stream
            .sock()
            .set_read_timeout(Some(deadline.left(
                "waiting for the response head",
                method,
                url,
            )?))
            .map_err(|e| HttpError::Io(e.to_string()))?;
        let eof = match stream.read(&mut chunk) {
            Ok(0) => true,
            Ok(n) => {
                buf.extend_from_slice(&chunk[..n]);
                false
            }
            Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
                return Err(timeout_err(
                    method,
                    url,
                    "no response head within the timeout",
                ));
            }
            Err(e) if e.kind() == ErrorKind::Interrupted => false,
            Err(e) => return Err(io_err(method, url, &e, "reading the response head")),
        };
        if buf.len() > 1024 * 1024 {
            return Err(malformed("the response head is larger than 1 MiB"));
        }
        if let Some(head) = parse_head(&buf)? {
            return Ok(head);
        }
        if eof {
            return Err(malformed("the connection closed inside the response head"));
        }
    }
}

fn read_exact_to(
    stream: &mut Conn,
    out: &mut File,
    mut len: u64,
    rest: &mut Vec<u8>,
    deadline: &Deadline,
    method: &str,
    url: &str,
) -> Result<(), HttpError> {
    if len == 0 {
        return Ok(());
    }
    let take = (rest.len() as u64).min(len) as usize;
    out.write_all(&rest[..take])
        .map_err(|e| io_err(method, url, &e, "spooling the body"))?;
    len -= take as u64;
    rest.drain(..take);
    let mut chunk = vec![0u8; CHUNK];
    while len > 0 {
        stream
            .sock()
            .set_read_timeout(Some(deadline.left("reading the body", method, url)?))
            .map_err(|e| HttpError::Io(e.to_string()))?;
        let want = (len as usize).min(CHUNK);
        let n = match stream.read(&mut chunk[..want]) {
            Ok(n) => n,
            Err(e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(e) => return Err(io_err(method, url, &e, "reading the body")),
        };
        if n == 0 {
            return Err(malformed(format!(
                "the body ended {} bytes short",
                len - n as u64
            )));
        }
        out.write_all(&chunk[..n])
            .map_err(|e| io_err(method, url, &e, "spooling the body"))?;
        len -= n as u64;
    }
    Ok(())
}

fn dechunk_to(
    stream: &mut Conn,
    out: &mut File,
    mut rest: Vec<u8>,
    deadline: &Deadline,
    method: &str,
    url: &str,
) -> Result<(), HttpError> {
    let mut chunk = vec![0u8; CHUNK];
    loop {
        let Some(eol) = find(&rest, b"\r\n") else {
            stream
                .sock()
                .set_read_timeout(Some(deadline.left("reading a chunk size", method, url)?))
                .map_err(|e| HttpError::Io(e.to_string()))?;
            let n = match stream.read(&mut chunk) {
                Ok(n) => n,
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
                    return Err(timeout_err(
                        method,
                        url,
                        "no complete chunk within the timeout",
                    ));
                }
                Err(e) => return Err(io_err(method, url, &e, "reading a chunk")),
            };
            if n == 0 {
                return Err(malformed("the connection closed inside the chunked body"));
            }
            rest.extend_from_slice(&chunk[..n]);
            continue;
        };
        let size_line = std::str::from_utf8(&rest[..eol]).map_err(|_| malformed("a chunk size"))?;
        let size_hex = size_line.split(';').next().unwrap_or_default().trim();
        let size = usize::from_str_radix(size_hex, 16)
            .map_err(|_| malformed(format!("chunk size {size_hex:?}")))?;
        rest.drain(..eol + 2);
        if size == 0 {
            return Ok(());
        }
        let mut left = size;
        while left > 0 {
            let take = left.min(rest.len());
            out.write_all(&rest[..take])
                .map_err(|e| io_err(method, url, &e, "spooling a chunk"))?;
            left -= take;
            rest.drain(..take);
            if left == 0 {
                break;
            }
            stream
                .sock()
                .set_read_timeout(Some(deadline.left("reading a chunk", method, url)?))
                .map_err(|e| HttpError::Io(e.to_string()))?;
            let want = left.min(CHUNK);
            let n = match stream.read(&mut chunk[..want]) {
                Ok(n) => n,
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(e) => return Err(io_err(method, url, &e, "reading a chunk")),
            };
            if n == 0 {
                return Err(malformed("the connection closed inside a chunk"));
            }
            rest.extend_from_slice(&chunk[..n]);
        }
        while rest.len() < 2 {
            stream
                .sock()
                .set_read_timeout(Some(deadline.left(
                    "reading a chunk's CRLF",
                    method,
                    url,
                )?))
                .map_err(|e| HttpError::Io(e.to_string()))?;
            let n = match stream.read(&mut chunk) {
                Ok(n) => n,
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(e) => return Err(io_err(method, url, &e, "reading a chunk's CRLF")),
            };
            if n == 0 {
                return Err(malformed("the connection closed before a chunk's CRLF"));
            }
            rest.extend_from_slice(&chunk[..n]);
        }
        if &rest[..2] != b"\r\n" {
            return Err(malformed("a chunk is not followed by CRLF"));
        }
        rest.drain(..2);
    }
}

fn read_to_eof(
    stream: &mut Conn,
    out: &mut File,
    rest: Vec<u8>,
    deadline: &Deadline,
    method: &str,
    url: &str,
) -> Result<(), HttpError> {
    out.write_all(&rest)
        .map_err(|e| io_err(method, url, &e, "spooling the body"))?;
    let mut chunk = vec![0u8; CHUNK];
    loop {
        stream
            .sock()
            .set_read_timeout(Some(deadline.left("reading the body", method, url)?))
            .map_err(|e| HttpError::Io(e.to_string()))?;
        let n = match stream.read(&mut chunk) {
            Ok(0) => return Ok(()),
            Ok(n) => n,
            Err(e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
                return Err(timeout_err(
                    method,
                    url,
                    "the body did not end within the timeout",
                ));
            }
            Err(e) => return Err(io_err(method, url, &e, "reading the body")),
        };
        out.write_all(&chunk[..n])
            .map_err(|e| io_err(method, url, &e, "spooling the body"))?;
    }
}

pub fn pipe(
    method: &str,
    url: &str,
    headers: &[(String, String)],
    body_file: Option<&Path>,
    timeout: Duration,
) -> Result<Piped, HttpError> {
    let target = parse_url(url)?;
    let body_len = match body_file {
        Some(path) => std::fs::metadata(path)
            .map_err(|e| HttpError::Request(format!("{}: {e}", path.display())))?
            .len(),
        None => 0,
    };
    let wire = encode_head(method, &target, headers, body_len)?;
    let deadline = Deadline(Instant::now() + timeout);
    let stream = dial(&target.host, target.port, timeout).map_err(HttpError::Io)?;
    let mut stream = if target.tls {
        Conn::tls(stream, &target.host).map_err(|why| HttpError::Tls(format!("{url}: {why}")))?
    } else {
        Conn::plain(stream)
    };
    stream
        .sock()
        .set_write_timeout(Some(deadline.left("sending the head", method, url)?))
        .map_err(|e| HttpError::Io(e.to_string()))?;
    stream
        .write_all(&wire)
        .map_err(|e| io_err(method, url, &e, "sending the head"))?;
    if let Some(path) = body_file {
        send_body(&mut stream, path, body_len, &deadline, method, url)?;
    }
    let head = read_head(&mut stream, &deadline, method, url)?;
    let head_only = method.eq_ignore_ascii_case("HEAD");
    let body = !(head_only || head.status == 204 || head.status == 304);
    if !body {
        return Ok(Piped {
            status: head.status,
            headers: head.headers,
            body_file: None,
        });
    }
    let path = spool_path();
    let mut out = File::create(&path).map_err(|e| {
        HttpError::Io(format!(
            "{method} {url}: spooling to {}: {e}",
            path.display()
        ))
    })?;
    let framed = if header(&head.headers, "transfer-encoding")
        .is_some_and(|v| v.to_ascii_lowercase().contains("chunked"))
    {
        dechunk_to(&mut stream, &mut out, head.rest, &deadline, method, url)
    } else if let Some(len) = header(&head.headers, "content-length") {
        let len: u64 = len
            .parse()
            .map_err(|_| malformed(format!("content-length {len:?}")))?;
        read_exact_to(
            &mut stream,
            &mut out,
            len,
            &mut head.rest.clone(),
            &deadline,
            method,
            url,
        )
    } else {
        read_to_eof(&mut stream, &mut out, head.rest, &deadline, method, url)
    };
    if let Err(e) = framed {
        let _ = std::fs::remove_file(&path);
        return Err(e);
    }
    out.flush()
        .map_err(|e| io_err(method, url, &e, "spooling the body"))?;
    Ok(Piped {
        status: head.status,
        headers: head.headers,
        body_file: Some(path),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read as _;
    use std::net::{TcpListener, TcpStream};
    use std::sync::Mutex;

    static SERIAL: Mutex<()> = Mutex::new(());

    fn echo_server(
        reply: impl FnOnce(TcpStream) + Send + 'static,
    ) -> (std::net::SocketAddr, std::thread::JoinHandle<()>) {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = l.local_addr().unwrap();
        let h = std::thread::spawn(move || {
            let (s, _) = l.accept().unwrap();
            reply(s);
        });
        (addr, h)
    }

    fn read_request_bytes(s: &mut TcpStream) -> Vec<u8> {
        let mut buf = Vec::new();
        let mut chunk = [0u8; 16 * 1024];
        s.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
        loop {
            let n = s.read(&mut chunk).unwrap();
            if n == 0 {
                break;
            }
            buf.extend_from_slice(&chunk[..n]);
            if let Some(head_end) = find(&buf, b"\r\n\r\n") {
                let head = String::from_utf8_lossy(&buf[..head_end]).to_ascii_lowercase();
                let len: usize = head
                    .lines()
                    .find_map(|l| l.strip_prefix("content-length: "))
                    .and_then(|v| v.trim().parse().ok())
                    .unwrap_or(0);
                if buf.len() >= head_end + 4 + len {
                    break;
                }
            }
        }
        buf
    }

    fn scratch(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("blue-pipe-{}-{name}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn pattern(len: usize) -> Vec<u8> {
        (0..len).map(|i| (i % 251) as u8 | 0x80).collect()
    }

    #[test]
    fn a_five_mib_body_round_trips_byte_identical() {
        let _spool_turn = SERIAL.lock().unwrap();
        let body = pattern(5 * 1024 * 1024);
        let dir = scratch("roundtrip");
        let up = dir.join("up.bin");
        std::fs::write(&up, &body).unwrap();
        let (addr, server) = echo_server(move |mut s| {
            let req = read_request_bytes(&mut s);
            let head_end = find(&req, b"\r\n\r\n").unwrap() + 4;
            let echoed = req[head_end..].to_vec();
            let head = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                echoed.len()
            );
            s.write_all(head.as_bytes()).unwrap();
            s.write_all(&echoed).unwrap();
        });
        let p = pipe(
            "POST",
            &format!("http://{addr}/v2/test/manifests/sha:abc"),
            &[(
                "Content-Type".into(),
                "application/vnd.oci.image.manifest.v1+json".into(),
            )],
            Some(&up),
            Duration::from_secs(30),
        )
        .unwrap();
        assert_eq!(p.status, 200);
        let back = std::fs::read(p.body_file.as_ref().unwrap()).unwrap();
        assert_eq!(back, body);
        std::fs::remove_file(p.body_file.unwrap()).unwrap();
        server.join().unwrap();
    }

    #[test]
    fn a_chunked_upstream_response_spools_decoded() {
        let _spool_turn = SERIAL.lock().unwrap();
        let (addr, server) = echo_server(move |mut s| {
            let _ = read_request_bytes(&mut s);
            s.write_all(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
                .unwrap();
            let body = pattern(100_000);
            for piece in body.chunks(7777) {
                s.write_all(format!("{:x}\r\n", piece.len()).as_bytes())
                    .unwrap();
                s.write_all(piece).unwrap();
                s.write_all(b"\r\n").unwrap();
            }
            s.write_all(b"0\r\n\r\n").unwrap();
        });
        let p = pipe(
            "GET",
            &format!("http://{addr}/blob"),
            &[],
            None,
            Duration::from_secs(30),
        )
        .unwrap();
        assert_eq!(p.status, 200);
        assert_eq!(
            std::fs::read(p.body_file.unwrap().clone()).unwrap(),
            pattern(100_000)
        );
        server.join().unwrap();
    }

    #[test]
    fn a_body_head_answer_and_head_request_have_no_spool() {
        let (addr, server) = echo_server(move |mut s| {
            let _ = read_request_bytes(&mut s);
            s.write_all(b"HTTP/1.1 204 No Content\r\n\r\n").unwrap();
        });
        let p = pipe(
            "DELETE",
            &format!("http://{addr}/v2/test/manifests/sha:abc"),
            &[],
            None,
            Duration::from_secs(30),
        )
        .unwrap();
        assert_eq!((p.status, p.body_file), (204, None));
        server.join().unwrap();
    }

    #[test]
    fn fifty_mib_completes_within_the_host_band() {
        let _spool_turn = SERIAL.lock().unwrap();
        let body = pattern(50 * 1024 * 1024);
        let dir = scratch("band");
        let up = dir.join("up.bin");
        std::fs::write(&up, &body).unwrap();
        let (addr, server) = echo_server(move |mut s| {
            let req = read_request_bytes(&mut s);
            let head_end = find(&req, b"\r\n\r\n").unwrap() + 4;
            let echoed = req[head_end..].to_vec();
            let head = format!(
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                echoed.len()
            );
            s.write_all(head.as_bytes()).unwrap();
            s.write_all(&echoed).unwrap();
        });
        let start = Instant::now();
        let p = pipe(
            "POST",
            &format!("http://{addr}/big"),
            &[],
            Some(&up),
            Duration::from_secs(60),
        )
        .unwrap();
        let elapsed = start.elapsed();
        assert_eq!(p.status, 200);
        assert_eq!(
            std::fs::read(p.body_file.as_ref().unwrap()).unwrap().len(),
            body.len()
        );
        assert!(elapsed < Duration::from_secs(30), "50 MiB took {elapsed:?}");
        server.join().unwrap();
    }

    #[test]
    fn a_refused_upstream_is_an_error_not_a_panic() {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = l.local_addr().unwrap();
        drop(l);
        let err = pipe(
            "GET",
            &format!("http://{addr}/x"),
            &[],
            None,
            Duration::from_secs(5),
        )
        .unwrap_err();
        assert!(err.to_string().contains("refused"), "{err}");
    }

    #[test]
    fn a_truncated_body_is_refused_and_leaves_no_spool() {
        let _spool_turn = SERIAL.lock().unwrap();
        let expected = peek_spool_path();
        let (addr, server) = echo_server(move |mut s| {
            let _ = read_request_bytes(&mut s);
            s.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\nshort")
                .unwrap();
        });
        let err = pipe(
            "GET",
            &format!("http://{addr}/x"),
            &[],
            None,
            Duration::from_secs(10),
        )
        .unwrap_err();
        assert!(matches!(err, HttpError::Response(_)), "{err}");
        assert!(
            !expected.exists(),
            "the failed pipe left {expected:?} behind"
        );
        server.join().unwrap();
    }
}
