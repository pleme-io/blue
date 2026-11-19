use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

struct Held {
    port: u16,
    most: Arc<AtomicUsize>,
}

fn holding_server() -> Held {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let port = listener.local_addr().expect("addr").port();
    let active = Arc::new(AtomicUsize::new(0));
    let most = Arc::new(AtomicUsize::new(0));
    let seen = most.clone();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let active = active.clone();
            let most = seen.clone();
            std::thread::spawn(move || {
                let mut got = Vec::new();
                let mut buf = [0u8; 1024];
                while !got.windows(4).any(|w| w == b"\r\n\r\n") {
                    match stream.read(&mut buf) {
                        Ok(0) | Err(_) => return,
                        Ok(n) => got.extend_from_slice(&buf[..n]),
                    }
                }
                let now = active.fetch_add(1, Ordering::SeqCst) + 1;
                most.fetch_max(now, Ordering::SeqCst);
                std::thread::sleep(Duration::from_millis(300));
                active.fetch_sub(1, Ordering::SeqCst);
                let _ = stream.write_all(
                    b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
                );
            });
        }
    });
    Held { port, most }
}

fn program(port: u16) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-batch-{port}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("dir");
    let file = dir.join("two.b");
    std::fs::write(
        &file,
        format!(
            "def two()\n  a = http_request(\"GET\", \"http://127.0.0.1:{port}/a\", nil, nil, 5000)\n  b = http_request(\"GET\", \"http://127.0.0.1:{port}/b\", nil, nil, 5000)\n  [a.status, b.status, a.body, b.body]\nend\n\ndef main()\n  write_stdout(to_s(two))\nend\n"
        ),
    )
    .expect("write");
    file
}

fn ran(file: &PathBuf, env: &[(&str, &str)]) -> (String, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env("BLUE_MEMO", "off")
        .envs(env.iter().copied())
        .args(["run", "--quiet", "--timings"])
        .arg(file)
        .output()
        .expect("spawn blue");
    let err = String::from_utf8_lossy(&out.stderr).into_owned();
    assert!(out.status.success(), "{err}");
    (String::from_utf8_lossy(&out.stdout).into_owned(), err)
}

fn batched(timings: &str) -> bool {
    timings
        .lines()
        .any(|l| l.starts_with("batched") && !l.trim_end().ends_with(" 0"))
}

#[test]
fn rule_r18_sends_two_independent_reads_at_once_and_its_switch_sends_them_in_turn() {
    let together = holding_server();
    let file = program(together.port);
    let (answer, timings) = ran(&file, &[]);
    assert_eq!(answer, "[200, 200, \"ok\", \"ok\"]");
    assert!(batched(&timings), "{timings}");
    assert_eq!(
        together.most.load(Ordering::SeqCst),
        2,
        "both requests were held open at once"
    );

    let in_turn = holding_server();
    let file = program(in_turn.port);
    let (answer_off, timings_off) = ran(&file, &[("BLUE_BATCH", "off")]);
    assert_eq!(answer_off, answer, "the switch changes no answer");
    assert!(!batched(&timings_off), "{timings_off}");
    assert_eq!(
        in_turn.most.load(Ordering::SeqCst),
        1,
        "BLUE_BATCH=off sends one, then the other"
    );
}

#[test]
fn reads_behind_a_request_helper_are_sent_at_once_too() {
    let held = holding_server();
    let dir = std::env::temp_dir().join(format!("blue-batch-helper-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("dir");
    let file = dir.join("helper.b");
    std::fs::write(
        &file,
        format!(
            "def page(name)\n  http_request(\"GET\", \"http://127.0.0.1:{}/#{{name}}\", nil, nil, 5000)\nend\n\ndef two()\n  a = page(\"a\")\n  b = page(\"b\")\n  [a.status, b.status]\nend\n\ndef main()\n  write_stdout(to_s(two))\nend\n",
            held.port
        ),
    )
    .expect("write");
    let (answer, timings) = ran(&file, &[]);
    assert_eq!(answer, "[200, 200]");
    assert!(batched(&timings), "{timings}");
    assert_eq!(held.most.load(Ordering::SeqCst), 2);
}
