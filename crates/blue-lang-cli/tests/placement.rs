use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

#[path = "../../blue-lang-wasm/tests/harness/mod.rs"]
mod harness;

const PROGRAM: &str = "crates/blue-lang-wasm/page/app.b";
const SERVICE: &str = "crates/blue-lang-wasm/page/serve.b";

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("repo root")
}

fn scratch() -> PathBuf {
    let dir = std::env::temp_dir()
        .canonicalize()
        .expect("temp dir")
        .join(format!("blue-placement-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch");
    dir
}

fn blue(args: &[&str]) -> std::process::Output {
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .current_dir(repo())
        .args(args)
        .output()
        .expect("spawn blue");
    assert!(
        out.status.success(),
        "blue {args:?}:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    out
}

struct Served(Child);

impl Drop for Served {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn serve(wasm: &Path, bundle: &Path) -> (Served, u16) {
    let port = TcpListener::bind("127.0.0.1:0")
        .and_then(|l| l.local_addr())
        .expect("a free port")
        .port();
    let child = Command::new(env!("CARGO_BIN_EXE_blue"))
        .current_dir(repo())
        .args(["run", SERVICE])
        .env("BLUE_PAGE_SITE", format!("127.0.0.1:{port}"))
        .env("BLUE_PAGE_WASM", wasm)
        .env("BLUE_PAGE_BUNDLE", bundle)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn the page service");
    let served = Served(child);
    let deadline = Instant::now() + Duration::from_secs(120);
    while TcpStream::connect(("127.0.0.1", port)).is_err() {
        assert!(Instant::now() < deadline, "the page service never listened");
        std::thread::sleep(Duration::from_millis(50));
    }
    (served, port)
}

fn in_the_page(port: u16) -> serde_json::Value {
    let driver = repo().join("crates/blue-lang-wasm/host/page.mjs");
    let out = Command::new("node")
        .arg(driver)
        .arg(format!("http://127.0.0.1:{port}/"))
        .output()
        .expect("spawn node, the engine the page runs in");
    assert!(
        out.status.success(),
        "the page run failed:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    serde_json::from_slice(&out.stdout).expect("the page reports JSON")
}

fn only_receipt(dir: &Path) -> (String, String) {
    let files: Vec<_> = std::fs::read_dir(dir)
        .expect("receipts")
        .map(|e| e.expect("entry").path())
        .collect();
    assert_eq!(files.len(), 1, "one run, one receipt: {files:?}");
    let name = files[0]
        .file_name()
        .and_then(|n| n.to_str())
        .expect("name")
        .to_string();
    (name, std::fs::read_to_string(&files[0]).expect("receipt"))
}

#[test]
fn one_program_in_the_cli_and_in_a_page_served_by_blue_gives_one_receipt() {
    let wasm = harness::build_wasm();
    let dir = scratch();
    let bundle = dir.join("app.json");
    let receipts = dir.join("receipts");

    blue(&[
        "bundle",
        "--sources",
        "-o",
        bundle.to_str().expect("utf-8"),
        PROGRAM,
    ]);
    let cli = blue(&[
        "run",
        "--allow",
        "none",
        "--receipts",
        receipts.to_str().expect("utf-8"),
        PROGRAM,
    ]);
    let printed = String::from_utf8(cli.stdout).expect("utf-8");
    let (name, cli_receipt) = only_receipt(&receipts);

    let (served, port) = serve(&wasm, &bundle);
    let page = in_the_page(port);
    drop(served);

    assert_eq!(page["state"], "ran", "{page}");
    assert_eq!(page["imports"], 0, "the engine in the page imports nothing");
    assert_eq!(page["scripts"], serde_json::json!(["/engine.js"]));
    assert_eq!(
        page["fetched"],
        serde_json::json!(["/blue.wasm", "/app.json"])
    );
    assert!(page["csp"]
        .as_str()
        .is_some_and(|c| c.contains("script-src 'self' 'wasm-unsafe-eval'")));

    let rendered = page["value"].as_str().expect("the page rendered");
    assert!(
        rendered.starts_with("<section><h1>one program"),
        "{rendered}"
    );
    assert_eq!(format!("{rendered}\n"), printed, "the same bytes");

    let page_receipt = page["receipt"].as_str().expect("the page's receipt");
    assert_eq!(page_receipt, cli_receipt, "the same receipt");
    assert_eq!(
        blue_lang_runtime::receipt::name_of(page_receipt.as_bytes()),
        name,
        "the page's receipt has the name the cli filed it under"
    );

    let other = std::fs::read_to_string(&bundle)
        .expect("bundle")
        .replace("sum_of_squares(5)", "sum_of_squares(6)");
    let moved = blue_lang_wasm::page::answer(&other);
    assert_eq!(moved["state"], "ran", "{moved}");
    assert_ne!(
        moved["receipt"].as_str(),
        Some(cli_receipt.as_str()),
        "another program has another receipt, so equal receipts mean the same run"
    );
    let _ = std::fs::remove_dir_all(dir);
}
