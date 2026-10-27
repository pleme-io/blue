#![allow(dead_code)]

use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

pub struct Peer {
    pub child: Option<Child>,
    pub port: u16,
    pub dir: PathBuf,
    pub stop: Option<Box<dyn Fn(&Path)>>,
}

impl Drop for Peer {
    fn drop(&mut self) {
        if let Some(stop) = &self.stop {
            stop(&self.dir);
        }
        if let Some(c) = self.child.as_mut() {
            let _ = c.kill();
            let _ = c.wait();
        }
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

pub fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .and_then(|l| l.local_addr())
        .expect("a free port")
        .port()
}

pub fn scratch(name: &str) -> PathBuf {
    static NEXT: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
    let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    let dir = std::env::temp_dir().join(format!("blue-{name}-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir
}

pub fn binary(env: &str, require: &str, file: &str) -> Option<PathBuf> {
    let found = std::env::var_os(env).map(PathBuf::from).or_else(|| {
        std::env::split_paths(&std::env::var_os("PATH")?)
            .map(|d| d.join(file))
            .find(|p| p.is_file())
    });
    if found.is_none() {
        assert!(
            std::env::var_os(require).is_none(),
            "{require} is set and no {file} was found"
        );
        eprintln!("SKIPPED: no {file} (set {env} or put it on PATH)");
    }
    found
}

pub fn listening(port: u16) {
    let deadline = Instant::now() + Duration::from_secs(15);
    while TcpStream::connect(("127.0.0.1", port)).is_err() {
        assert!(Instant::now() < deadline, "nothing listened on {port}");
        std::thread::sleep(Duration::from_millis(20));
    }
}

pub fn spawn(bin: &Path, args: &[String], port: u16, dir: PathBuf) -> Peer {
    let child = Command::new(bin)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap_or_else(|e| panic!("{}: {e}", bin.display()));
    listening(port);
    Peer {
        child: Some(child),
        port,
        dir,
        stop: None,
    }
}

pub fn valkey(password: Option<&str>) -> Option<Peer> {
    let bin = binary("BLUE_VALKEY_SERVER", "BLUE_REQUIRE_VALKEY", "valkey-server")?;
    let port = free_port();
    let dir = scratch("valkey");
    let mut args = vec![
        "--port".to_string(),
        port.to_string(),
        "--bind".to_string(),
        "127.0.0.1".to_string(),
        "--save".to_string(),
        String::new(),
        "--appendonly".to_string(),
        "no".to_string(),
        "--dir".to_string(),
        dir.display().to_string(),
    ];
    if let Some(pw) = password {
        args.push("--requirepass".to_string());
        args.push(pw.to_string());
    }
    Some(spawn(&bin, &args, port, dir))
}

pub fn nats(jetstream: bool) -> Option<Peer> {
    let bin = binary(
        "BLUE_NATS_SERVER",
        "BLUE_REQUIRE_NATS_SERVER",
        "nats-server",
    )?;
    let port = free_port();
    let dir = scratch("nats");
    let conf = dir.join("nats.conf");
    let js = if jetstream {
        format!(
            "jetstream {{ store_dir: \"{}\" }}\n",
            dir.join("js").display()
        )
    } else {
        String::new()
    };
    std::fs::write(&conf, format!("host: 127.0.0.1\nport: {port}\n{js}")).expect("config");
    Some(spawn(
        &bin,
        &["-c".to_string(), conf.display().to_string()],
        port,
        dir,
    ))
}

pub fn postgres() -> Option<Peer> {
    let bin = binary("BLUE_POSTGRES_BIN", "BLUE_REQUIRE_POSTGRES", "initdb").map(|p| {
        if p.is_dir() {
            p
        } else {
            p.parent().unwrap().to_path_buf()
        }
    })?;
    let dir = scratch("pg");
    let init = Command::new(bin.join("initdb"))
        .arg("-D")
        .arg(dir.join("data"))
        .args(["-U", "blue", "--auth=trust"])
        .output()
        .unwrap();
    assert!(
        init.status.success(),
        "{}",
        String::from_utf8_lossy(&init.stderr)
    );
    let port = free_port();
    let start = Command::new(bin.join("pg_ctl"))
        .arg("-D")
        .arg(dir.join("data"))
        .arg("-o")
        .arg(format!(
            "-p {port} -k {} -c listen_addresses=127.0.0.1",
            dir.display()
        ))
        .args(["-w", "start", "-l"])
        .arg(dir.join("log"))
        .output()
        .unwrap();
    assert!(
        start.status.success(),
        "{}",
        String::from_utf8_lossy(&start.stderr)
    );
    let ctl = bin.join("pg_ctl");
    Some(Peer {
        child: None,
        port,
        dir,
        stop: Some(Box::new(move |d: &Path| {
            let _ = Command::new(&ctl)
                .arg("-D")
                .arg(d.join("data"))
                .args(["-m", "immediate", "stop"])
                .output();
        })),
    })
}

pub fn run_bidamas(src: &str) -> Result<tatara_lisp_eval::Value, String> {
    let lp = blue_lang_pkg::load_path::LoadPath::new([PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("bidamas")]);
    blue_lang_runtime::pipeline::run_with_loader(src, blue_lang_runtime::inputs::Inputs::new(), &lp)
        .map(|r| r.value)
        .map_err(|e| e.to_string())
}
