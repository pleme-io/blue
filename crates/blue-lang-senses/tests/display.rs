#![cfg(unix)]

use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixListener;

use blue_lang_senses::canvas::Canvas;
use blue_lang_senses::display::{self, Screen, PROTOCOL};
use serde_json::{json, Value};

fn serve(
    listener: UnixListener,
    refuse_present: bool,
) -> std::thread::JoinHandle<Vec<(Value, Vec<u8>)>> {
    std::thread::spawn(move || {
        let (stream, _) = listener.accept().expect("a canvas client");
        let mut reader = BufReader::new(stream.try_clone().expect("clone"));
        let mut writer = stream;
        let mut seen = Vec::new();
        loop {
            let mut line = String::new();
            if reader.read_line(&mut line).expect("a header") == 0 {
                break;
            }
            let header: Value = serde_json::from_str(line.trim_end()).expect("a JSON header");
            let mut payload = vec![0u8; header["bytes"].as_u64().unwrap_or(0) as usize];
            reader.read_exact(&mut payload).expect("the payload");
            let op = header["op"].as_str().unwrap_or("").to_string();
            let reply = if op == "present" && refuse_present {
                json!({"ok": false, "error": "no surface"})
            } else {
                json!({"ok": true})
            };
            writer
                .write_all(format!("{reply}\n").as_bytes())
                .expect("a reply");
            seen.push((header, payload));
            if op == "close" {
                break;
            }
        }
        seen
    })
}

#[test]
fn a_canvas_speaks_open_present_and_close_to_the_canvas_server_and_sends_the_presented_pixels() {
    let dir = std::env::temp_dir().join(format!("blue-senses-canvas-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("canvas.sock");
    std::env::set_var(display::SOCKET_VARIABLE, &path);
    assert_eq!(display::socket(), path);

    let server = serve(UnixListener::bind(&path).unwrap(), false);
    let mut canvas = Canvas::new(3, 2).unwrap();
    let mut screen = Screen::open(&canvas, "probe").expect("the server is listening");
    canvas.clear(0x00_00FF);
    canvas.fill_rect(1, 0, 1, 1, 0xFF_0000);
    canvas.present();
    screen.present(&canvas).expect("present");
    screen.close().expect("close");
    let seen = server.join().expect("the server");
    let ops: Vec<&str> = seen
        .iter()
        .map(|(h, _)| h["op"].as_str().unwrap())
        .collect();
    assert_eq!(ops, ["open", "present", "close"]);
    assert_eq!(seen[0].0["protocol"], json!(PROTOCOL));
    assert_eq!(seen[0].0["width"], json!(3));
    assert_eq!(seen[0].0["height"], json!(2));
    assert_eq!(seen[0].0["title"], json!("probe"));
    assert_eq!(seen[1].0["format"], json!("rgb8"));
    assert_eq!(seen[1].0["bytes"], json!(18));
    assert_eq!(
        seen[1].1,
        vec![0, 0, 255, 255, 0, 0, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 255]
    );

    std::fs::remove_file(&path).unwrap();
    let server = serve(UnixListener::bind(&path).unwrap(), true);
    let mut screen = Screen::open(&canvas, "refusing").expect("open");
    let refusal = screen.present(&canvas).expect_err("the server refuses");
    assert_eq!(refusal.kind(), "refused");
    assert!(refusal.message().contains("no surface"), "{refusal}");
    screen.close().expect("close");
    server.join().expect("the server");
    let _ = std::fs::remove_dir_all(dir);
}
