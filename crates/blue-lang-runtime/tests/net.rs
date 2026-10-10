//! The network primitives against real peers: a `nats-server` child process
//! and a std `TcpListener` playing an HTTP server, driven by blue programs
//! through the `blue run` pipeline.
//!
//! The NATS tests need a `nats-server` binary: `BLUE_NATS_SERVER`, else
//! `nats-server` on PATH. Without one they say so and pass, unless
//! `BLUE_REQUIRE_NATS_SERVER` is set, which the flake's `network` check sets,
//! so the gate cannot go green having started nothing.
//!
//! Red runs, 2026-10-10, each reverted: the client not answering `PING` failed
//! `the_client_answers_server_pings_while_it_waits` with `server error: Stale
//! Connection`; a chunked body read as raw bytes failed
//! `an_http_post_round_trips_through_a_listener`.

#![cfg(feature = "sys")]

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use blue_lang_runtime::net::nats;
use tatara_lisp_eval::Value;

fn run(src: &str) -> Value {
    blue_lang_runtime::run(src)
        .unwrap_or_else(|e| panic!("{src}\n{e}"))
        .value
}

fn run_err(src: &str) -> String {
    match blue_lang_runtime::run(src) {
        Ok(r) => panic!("{src}\nmust raise, answered {:?}", r.value),
        Err(e) => e.to_string(),
    }
}

fn s(v: &str) -> String {
    format!("{v:?}")
}

fn strs(v: &Value) -> Vec<String> {
    let Value::List(items) = v else {
        panic!("expected a list, got {v:?}");
    };
    items
        .iter()
        .map(|x| match x {
            Value::Str(t) => t.to_string(),
            Value::Nil => "nil".to_string(),
            Value::Int(n) => n.to_string(),
            other => format!("{other:?}"),
        })
        .collect()
}

// ── a nats-server child ──────────────────────────────────────────────────

struct Server {
    child: Child,
    port: u16,
    dir: PathBuf,
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

impl Server {
    fn url(&self) -> String {
        format!("nats://127.0.0.1:{}", self.port)
    }
}

fn nats_server_bin() -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("BLUE_NATS_SERVER") {
        return Some(PathBuf::from(p));
    }
    std::env::split_paths(&std::env::var_os("PATH")?)
        .map(|d| d.join("nats-server"))
        .find(|p| p.is_file())
}

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .and_then(|l| l.local_addr())
        .expect("a free port")
        .port()
}

fn start_server(name: &str, config: &str) -> Option<Server> {
    let Some(bin) = nats_server_bin() else {
        assert!(
            std::env::var_os("BLUE_REQUIRE_NATS_SERVER").is_none(),
            "BLUE_REQUIRE_NATS_SERVER is set and no nats-server was found"
        );
        eprintln!("SKIPPED {name}: no nats-server (set BLUE_NATS_SERVER or put it on PATH)");
        return None;
    };
    let port = free_port();
    let dir = std::env::temp_dir().join(format!("blue-net-{name}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("scratch dir");
    let conf = dir.join("nats.conf");
    std::fs::write(&conf, format!("host: 127.0.0.1\nport: {port}\n{config}")).expect("config");
    let child = Command::new(&bin)
        .arg("-c")
        .arg(&conf)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap_or_else(|e| panic!("{}: {e}", bin.display()));
    let server = Server { child, port, dir };
    let deadline = Instant::now() + Duration::from_secs(10);
    while TcpStream::connect(("127.0.0.1", port)).is_err() {
        assert!(
            Instant::now() < deadline,
            "nats-server never listened on {port}"
        );
        std::thread::sleep(Duration::from_millis(20));
    }
    Some(server)
}

#[test]
fn a_published_message_reaches_a_wildcard_subscriber() {
    let Some(server) = start_server("pubsub", "") else {
        return;
    };
    let v = run(&format!(
        "c = nats_connect({url})\n\
         sub = nats_subscribe(c, \"home.light.*\")\n\
         nats_publish(c, \"home.light.kitchen\", \"on\")\n\
         nats_publish(c, \"home.door.front\", \"open\")\n\
         m = nats_next_message(sub, 2000)\n\
         none = nats_next_message(sub, 100)\n\
         nats_close(c)\n\
         [get(m, :subject), get(m, :payload), get(m, :reply), none]",
        url = s(&server.url())
    ));
    assert_eq!(strs(&v), ["home.light.kitchen", "on", "nil", "nil"]);
}

#[test]
fn a_request_gets_the_responders_reply() {
    let Some(server) = start_server("request", "") else {
        return;
    };
    let mut responder =
        nats::Client::connect(&server.url(), Duration::from_secs(5)).expect("responder connects");
    let sid = responder.subscribe("svc.upper", None).expect("subscribe");
    let worker = std::thread::spawn(move || {
        let m = responder
            .next_message(sid, Duration::from_secs(5))
            .expect("read")
            .expect("a request arrives");
        let reply = m.reply.expect("a request carries a reply subject");
        let upper = String::from_utf8(m.payload).unwrap().to_uppercase();
        responder
            .publish(&reply, None, upper.as_bytes())
            .expect("reply");
        responder.next_message(sid, Duration::from_millis(200)).ok();
    });
    let v = run(&format!(
        "c = nats_connect({url})\nr = nats_request(c, \"svc.upper\", \"lights on\", 3000)\nnats_close(c)\nr",
        url = s(&server.url())
    ));
    worker.join().expect("responder");
    assert!(matches!(&v, Value::Str(t) if &**t == "LIGHTS ON"), "{v:?}");
}

#[test]
fn a_request_nobody_serves_raises_no_responders() {
    let Some(server) = start_server("noresp", "") else {
        return;
    };
    let err = run_err(&format!(
        "c = nats_connect({url})\nnats_request(c, \"nobody.home\", \"\", 3000)",
        url = s(&server.url())
    ));
    assert!(
        err.contains("nats_request") && err.contains("no responders on nobody.home"),
        "{err}"
    );
}

#[test]
fn the_client_answers_server_pings_while_it_waits() {
    let Some(server) = start_server("ping", "ping_interval: \"100ms\"\nping_max: 1\n") else {
        return;
    };
    let v = run(&format!(
        "c = nats_connect({url})\n\
         sub = nats_subscribe(c, \"tick\")\n\
         idle = nats_next_message(sub, 1500)\n\
         nats_publish(c, \"tick\", \"still here\")\n\
         m = nats_next_message(sub, 2000)\n\
         [idle, get(m, :payload)]",
        url = s(&server.url())
    ));
    assert_eq!(strs(&v), ["nil", "still here"]);
}

#[test]
fn a_queue_group_subscription_and_unsubscribe() {
    let Some(server) = start_server("queue", "") else {
        return;
    };
    let url = s(&server.url());
    let v = run(&format!(
        "c = nats_connect({url})\n\
         a = nats_subscribe(c, \"jobs\", \"workers\")\n\
         b = nats_subscribe(c, \"jobs\", \"workers\")\n\
         nats_publish(c, \"jobs\", \"one\")\n\
         got = [nats_next_message(a, 300), nats_next_message(b, 300)]\n\
         count(filter(fn(m) m != nil end, got))"
    ));
    assert!(
        matches!(v, Value::Int(1)),
        "one member of the group gets the message: {v:?}"
    );
    let err = run_err(&format!(
        "c = nats_connect({url})\nsub = nats_subscribe(c, \"jobs\")\nnats_unsubscribe(sub)\nnats_next_message(sub, 10)"
    ));
    assert!(
        err.contains("nats_next_message") && err.contains("closed"),
        "{err}"
    );
}

#[test]
fn a_closed_connection_raises_on_use() {
    let Some(server) = start_server("closed", "") else {
        return;
    };
    let err = run_err(&format!(
        "c = nats_connect({url})\nnats_close(c)\nnats_publish(c, \"a\", \"b\")",
        url = s(&server.url())
    ));
    assert!(
        err.contains("nats_publish") && err.contains("closed"),
        "{err}"
    );
}

#[test]
fn connecting_to_nothing_raises_naming_the_url() {
    let port = free_port();
    let err = run_err(&format!("nats_connect(\"nats://127.0.0.1:{port}\", 500)"));
    assert!(
        err.contains("nats_connect") && err.contains(&port.to_string()),
        "{err}"
    );
}

#[test]
fn a_handle_of_the_wrong_kind_is_refused() {
    let err = run_err("nats_publish(\"not a connection\", \"a\", \"b\")");
    assert!(err.contains("expected a NATS connection"), "{err}");
}

// ── HTTP against a std listener ──────────────────────────────────────────

fn read_request(stream: &mut TcpStream) -> String {
    let mut buf = Vec::new();
    let mut chunk = [0u8; 4096];
    loop {
        let n = stream.read(&mut chunk).expect("read request");
        buf.extend_from_slice(&chunk[..n]);
        let text = String::from_utf8_lossy(&buf).to_string();
        if let Some(end) = text.find("\r\n\r\n") {
            let len = text[..end]
                .lines()
                .find_map(|l| {
                    l.to_ascii_lowercase()
                        .strip_prefix("content-length:")
                        .map(|v| v.trim().parse::<usize>().unwrap())
                })
                .unwrap_or(0);
            if buf.len() >= end + 4 + len {
                return text;
            }
        }
        assert!(n > 0, "the client closed before sending a whole request");
    }
}

#[test]
fn an_http_post_round_trips_through_a_listener() {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let port = listener.local_addr().unwrap().port();
    let server = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        let request = read_request(&mut stream);
        stream
            .write_all(
                b"HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n\
                  7\r\n[{\"ok\":\r\n5\r\ntrue}\r\n1\r\n]\r\n0\r\n\r\n",
            )
            .expect("respond");
        request
    });
    let v = run(&format!(
        "r = http_request(\"POST\", \"http://127.0.0.1:{port}/api/services/light/turn_on\", \
         [[\"Authorization\", \"Bearer t0k\"], [\"Content-Type\", \"application/json\"]], \
         \"{{\\\"entity_id\\\":\\\"light.kitchen\\\"}}\", 3000)\n\
         [get(r, :status), get(r, :body), json_get(get(r, :headers), \"content-type\")]"
    ));
    let request = server.join().expect("server");
    assert_eq!(strs(&v), ["201", "[{\"ok\":true}]", "application/json"]);
    assert!(
        request.starts_with("POST /api/services/light/turn_on HTTP/1.1\r\n"),
        "{request}"
    );
    assert!(
        request.contains("\r\nAuthorization: Bearer t0k\r\n"),
        "{request}"
    );
    assert!(
        request.contains(&format!("\r\nHost: 127.0.0.1:{port}\r\n")),
        "{request}"
    );
    assert!(request.contains("\r\nContent-Length: 29\r\n"), "{request}");
    assert!(
        request.ends_with("\r\n\r\n{\"entity_id\":\"light.kitchen\"}"),
        "{request}"
    );
}

#[test]
fn an_error_status_is_an_answer_not_a_raise() {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let port = listener.local_addr().unwrap().port();
    let server = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        read_request(&mut stream);
        stream
            .write_all(b"HTTP/1.1 401 Unauthorized\r\nContent-Length: 12\r\n\r\nunauthorized")
            .expect("respond");
    });
    let v = run(&format!(
        "r = http_request(\"GET\", \"http://127.0.0.1:{port}/api/\", {{}}, nil, 3000)\n[get(r, :status), get(r, :body)]"
    ));
    server.join().expect("server");
    assert_eq!(strs(&v), ["401", "unauthorized"]);
}

#[test]
fn a_silent_server_times_out() {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let port = listener.local_addr().unwrap().port();
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().expect("accept");
        std::thread::sleep(Duration::from_millis(1500));
        drop(stream);
    });
    let start = Instant::now();
    let err = run_err(&format!(
        "http_request(\"GET\", \"http://127.0.0.1:{port}/\", nil, nil, 200)"
    ));
    assert!(
        start.elapsed() < Duration::from_millis(1200),
        "took {:?}",
        start.elapsed()
    );
    assert!(
        err.contains("http_request") && err.contains("timed out"),
        "{err}"
    );
    server.join().expect("server");
}

#[test]
fn https_and_unreachable_hosts_raise() {
    let err = run_err("http_request(\"GET\", \"https://example.invalid/\", nil, nil, 500)");
    assert!(err.contains("https is not supported"), "{err}");
    let port = free_port();
    let err = run_err(&format!(
        "http_request(\"GET\", \"http://127.0.0.1:{port}/\", nil, nil, 500)"
    ));
    assert!(
        err.contains("http_request") && err.contains(&port.to_string()),
        "{err}"
    );
}
