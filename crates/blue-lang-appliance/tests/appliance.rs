use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use blue_lang_pkg::appliance::{self, Payload};

struct NoSources;

impl blue_lang_pkg::lock::Prefetch for NoSources {
    fn prefetch(&self, url: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        Err(format!("a fixture declares no source, and {url} was asked for").into())
    }
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-appliance-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir.canonicalize().unwrap()
}

fn put(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).unwrap();
}

const MAIN: &str =
    "use(\"greet\", [:greeting])\n\ndef main()\n  write_stdout(unlines([greeting(argv[0])]))\nend\n";

fn project(name: &str) -> PathBuf {
    let dir = scratch(name).join("hello");
    put(
        &dir.join("Bluefile"),
        "package(\"hello\", \"0.1.0\")\npackages(\"bidamas\")\nallow(%i[environment])\napp(\"hello\", \"main.b\")\n",
    );
    put(&dir.join("main.b"), MAIN);
    put(
        &dir.join("bidamas/greet/Bluefile"),
        "package(\"greet\", \"0.1.0\")\n",
    );
    put(
        &dir.join("bidamas/greet/greet.b"),
        "def greeting(who)\n  \"hello, #{who}\"\nend\n",
    );
    lock(&dir);
    dir
}

fn lock(dir: &Path) {
    let lock = blue_lang_pkg::lock::lock_dir(dir, &NoSources).expect("the fixture locks");
    put(
        &dir.join("Bluefile.lock"),
        &blue_lang_pkg::lock::render(&lock).unwrap(),
    );
}

fn executable(at: &Path, payload: &Payload) -> PathBuf {
    let runner = std::fs::read(env!("CARGO_BIN_EXE_blue-appliance")).unwrap();
    write_executable(at, &appliance::appended(runner, payload).unwrap());
    at.to_path_buf()
}

fn write_executable(at: &Path, bytes: &[u8]) {
    use std::os::unix::fs::PermissionsExt;
    std::fs::write(at, bytes).unwrap();
    std::fs::set_permissions(at, std::fs::Permissions::from_mode(0o755)).unwrap();
}

fn run(exe: &Path, args: &[&str]) -> Output {
    Command::new(exe)
        .args(args)
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_DIST")
        .env_remove("BLUE_CONFIG")
        .current_dir(std::env::temp_dir())
        .output()
        .unwrap()
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

fn compiled(entry: &Path) -> blue_lang_runtime::pipeline::Compiled {
    let src = std::fs::read_to_string(entry).unwrap();
    blue_lang_runtime::pipeline::compile(
        blue_lang_runtime::uses::Entry {
            path: Some(entry),
            text: &src,
        },
        &blue_lang_pkg::load_path::LoadPath::for_entry(entry),
        None,
        None,
    )
    .expect("compiles")
}

#[test]
fn a_bundled_project_runs_as_one_executable_with_its_project_gone() {
    let dir = project("runs");
    let payload = appliance::bundle(&dir.join("main.b"), None).expect("bundles");
    let policy = payload
        .policy
        .as_ref()
        .expect("the lock's record is sealed in");
    assert_eq!(policy.ceiling, Some(vec!["environment".to_string()]));
    assert_eq!(payload.name, "hello");
    assert_eq!(payload.main.as_deref(), Some("%root/main"));

    let exe = executable(&dir.parent().unwrap().join("hello-app"), &payload);
    std::fs::remove_dir_all(&dir).unwrap();
    let out = run(&exe, &["world"]);
    assert_eq!(out.status.code(), Some(0), "{}", text(&out.stderr));
    assert_eq!(text(&out.stdout), "hello, world\n");
}

#[test]
fn a_breach_under_the_sealed_policy_exits_77() {
    let dir = project("breach");
    put(
        &dir.join("clock.b"),
        "write_stdout(unlines([\"before\"]))\nnow_ms\n",
    );
    let lock: blue_lang_pkg::lock::Lock =
        serde_json::from_str(&std::fs::read_to_string(dir.join("Bluefile.lock")).unwrap()).unwrap();
    let refused = appliance::bundle(&dir.join("clock.b"), None).expect_err("the clock is withheld");
    assert!(refused.to_string().contains("`now_ms`"), "{refused}");

    let payload =
        Payload::of("hello", &compiled(&dir.join("clock.b")), lock.capabilities).expect("encodes");
    let exe = executable(&dir.join("clock-app"), &payload);
    let out = run(&exe, &[]);
    assert_eq!(out.status.code(), Some(77), "{}", text(&out.stderr));
    assert_eq!(text(&out.stdout), "before\n");
    assert!(
        text(&out.stderr).contains("capability breach: `now_ms` reaches the host (clock), which this appliance's policy does not grant"),
        "{}",
        text(&out.stderr)
    );
}

#[test]
fn a_tampered_payload_is_refused_before_anything_runs() {
    let dir = project("tampered");
    let payload = appliance::bundle(&dir.join("main.b"), None).unwrap();
    let exe = executable(&dir.join("hello-app"), &payload);
    let mut bytes = std::fs::read(&exe).unwrap();
    let body = bytes.len() - appliance::TRAILER;
    let needle = b"hello, ";
    let at = bytes[..body]
        .windows(needle.len())
        .rposition(|w| w == needle)
        .expect("the greeting is in the payload");
    bytes[at] = b'j';
    write_executable(&exe, &bytes);
    let out = run(&exe, &["world"]);
    assert_eq!(
        out.status.code(),
        Some(i32::from(appliance::EX_DATAERR)),
        "{}",
        text(&out.stderr)
    );
    assert!(out.stdout.is_empty(), "{}", text(&out.stdout));
    assert!(
        text(&out.stderr).contains("does not match its BLAKE3 seal"),
        "{}",
        text(&out.stderr)
    );
}

#[test]
fn a_policy_less_payload_cannot_reach_the_host_and_no_argument_widens_it() {
    let dir = scratch("pure");
    for (name, call, cap) in [
        ("read", "read_file(\"/etc/hosts\")", "filesystem"),
        ("clock", "now_ms", "clock"),
        ("env", "getenv(\"HOME\")", "environment"),
        ("exec", "exec_capture(\"true\")", "process"),
    ] {
        let entry = dir.join(format!("{name}.b"));
        put(
            &entry,
            &format!("write_stdout(unlines([\"before\"]))\n{call}\n"),
        );
        let refused =
            appliance::bundle(&entry, None).expect_err("a pure bundle names no host call");
        assert!(refused.to_string().contains(cap), "{name}: {refused}");

        let payload = Payload::of(name, &compiled(&entry), None).unwrap();
        assert!(payload.policy.is_none());
        let exe = executable(&dir.join(format!("{name}-app")), &payload);
        let out = run(&exe, &["--allow", "host"]);
        assert_eq!(out.status.code(), Some(77), "{name}: {}", text(&out.stderr));
        assert_eq!(text(&out.stdout), "before\n", "{name}");
        assert!(
            text(&out.stderr).contains(&format!(
                "({cap}), which this appliance's policy does not grant"
            )),
            "{name}: {}",
            text(&out.stderr)
        );
    }
}

#[test]
fn a_stale_lock_is_refused_and_nothing_is_bundled() {
    let dir = project("stale");
    put(
        &dir.join("Bluefile"),
        "package(\"hello\", \"0.1.0\")\npackages(\"bidamas\")\nallow(%i[environment clock])\napp(\"hello\", \"main.b\")\n",
    );
    let refused = appliance::bundle(&dir.join("main.b"), None).expect_err("the lock is stale");
    assert!(refused.to_string().contains("run `blue lock"), "{refused}");
}

#[test]
fn a_runner_with_no_payload_says_so() {
    let out = run(Path::new(env!("CARGO_BIN_EXE_blue-appliance")), &[]);
    assert_eq!(
        out.status.code(),
        Some(i32::from(appliance::EX_NOINPUT)),
        "{}",
        text(&out.stderr)
    );
    assert!(
        text(&out.stderr).contains("carries no payload"),
        "{}",
        text(&out.stderr)
    );
}
