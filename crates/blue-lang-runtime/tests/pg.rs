#![cfg(feature = "sys")]

use std::net::TcpListener;
use std::path::PathBuf;
use std::process::Command;

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

fn bin_dir() -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("BLUE_POSTGRES_BIN") {
        return Some(PathBuf::from(p));
    }
    std::env::split_paths(&std::env::var_os("PATH")?).find(|d| d.join("initdb").is_file())
}

struct Server {
    dir: PathBuf,
    bin: PathBuf,
    port: u16,
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = Command::new(self.bin.join("pg_ctl"))
            .args(["-D"])
            .arg(self.dir.join("data"))
            .args(["-m", "immediate", "stop"])
            .output();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn server() -> Option<Server> {
    let Some(bin) = bin_dir() else {
        assert!(
            std::env::var_os("BLUE_REQUIRE_POSTGRES").is_none(),
            "BLUE_REQUIRE_POSTGRES is set and no initdb was found"
        );
        eprintln!("no PostgreSQL binaries (BLUE_POSTGRES_BIN or initdb on PATH): skipping");
        return None;
    };
    let dir =
        std::env::temp_dir().join(format!("blue-pg-{}-{}", std::process::id(), rand_suffix()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("pw"), "s3cret\n").unwrap();
    let init = Command::new(bin.join("initdb"))
        .arg("-D")
        .arg(dir.join("data"))
        .args([
            "-U",
            "blue",
            "--auth-host=scram-sha-256",
            "--auth-local=trust",
        ])
        .arg(format!("--pwfile={}", dir.join("pw").display()))
        .output()
        .unwrap();
    assert!(
        init.status.success(),
        "{}",
        String::from_utf8_lossy(&init.stderr)
    );
    let port = TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port();
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
    Some(Server { dir, bin, port })
}

fn url_of(password: &str, port: u16) -> String {
    [
        "postgres://blue",
        ":",
        password,
        "@127.0.0.1:",
        &port.to_string(),
        "/postgres",
    ]
    .concat()
}

fn rand_suffix() -> String {
    static NEXT: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
    let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    let t = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{t}-{n}")
}

#[test]
fn a_blue_program_writes_and_reads_rows_over_scram() {
    let Some(pg) = server() else { return };
    let url = url_of("s3cret", pg.port);
    let v = run(&format!(
        "c = pg_connect(\"{url}\")\n\
         pg_execute(c, \"CREATE TABLE greetings (id bigserial PRIMARY KEY, text text NOT NULL, loud boolean)\")\n\
         a = pg_query(c, \"INSERT INTO greetings (text, loud) VALUES ($1, $2) RETURNING id\", [\"olá\", true])\n\
         b = pg_query(c, \"INSERT INTO greetings (text, loud) VALUES ($1, $2) RETURNING id\", [\"it's\", nil])\n\
         r = pg_query(c, \"SELECT id, text, loud FROM greetings ORDER BY id\", [])\n\
         pg_close(c)\n\
         [get(a, :command), get(first(get(b, :rows)), \"id\"), get(r, :columns), map(fn(x) [get(x, \"id\"), get(x, \"text\"), get(x, \"loud\")] end, get(r, :rows))]"
    ));
    let text = format!("{v:?}");
    assert!(text.contains("INSERT 0 1"), "{text}");
    assert!(text.contains("Int(2)"), "{text}");
    assert!(text.contains("\"olá\""), "{text}");
    assert!(text.contains("\"it's\""), "{text}");
    assert!(text.contains("Bool(true)"), "{text}");
    assert!(text.contains("Nil"), "{text}");
    assert!(
        text.contains("[Int(1), Str(\"olá\"), Bool(true)]"),
        "{text}"
    );
    assert!(text.contains("[Int(2), Str(\"it's\"), Nil]"), "{text}");
}

#[test]
fn a_wrong_password_a_bad_statement_and_a_closed_connection_raise() {
    let Some(pg) = server() else { return };
    let bad = run_err(&format!("pg_connect(\"{}\")", url_of("nope", pg.port)));
    assert!(bad.contains("28P01"), "{bad}");
    let url = url_of("s3cret", pg.port);
    let missing = run_err(&format!(
        "c = pg_connect(\"{url}\")\npg_query(c, \"SELECT * FROM nope\", [])"
    ));
    assert!(missing.contains("42P01"), "{missing}");
    let after = run(&format!(
        "c = pg_connect(\"{url}\")\ntry(pg_query(c, \"SELECT 1/0\", []), catch(_e(), nil))\nget(first(get(pg_query(c, \"SELECT 1 AS one\", []), :rows)), \"one\")"
    ));
    assert_eq!(format!("{after:?}"), "Int(1)");
    let closed = run_err(&format!(
        "c = pg_connect(\"{url}\")\npg_close(c)\npg_query(c, \"SELECT 1\", [])"
    ));
    assert!(closed.contains("closed"), "{closed}");
}
