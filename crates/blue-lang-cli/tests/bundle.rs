use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use blue_lang_pkg::appliance;

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG");
    c
}

fn put(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).unwrap();
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

fn project(name: &str) -> PathBuf {
    let root = std::env::temp_dir().join(format!("blue-bundle-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dir = root.join("hello");
    put(
        &dir.join("Bluefile"),
        "package(\"hello\", \"0.1.0\")\nallow(%i[environment])\napp(\"hello\", \"main.b\")\n",
    );
    put(
        &dir.join("main.b"),
        "def main()\n  write_stdout(unlines([argv[0]]))\nend\n",
    );
    let dir = dir.canonicalize().unwrap();
    let o = blue().arg("lock").arg(&dir).output().unwrap();
    assert!(o.status.success(), "{}", err(&o));
    dir
}

fn opened(path: &Path) -> appliance::Payload {
    appliance::open(&mut std::fs::File::open(path).unwrap()).expect("opens")
}

#[test]
fn bundle_writes_a_sealed_payload_and_with_a_runner_the_executable() {
    use std::os::unix::fs::PermissionsExt;
    let dir = project("writes");
    let sealed = dir.join("hello.payload");
    let o = blue()
        .arg("bundle")
        .arg(dir.join("main.b"))
        .arg("-o")
        .arg(&sealed)
        .output()
        .unwrap();
    assert!(o.status.success(), "{}", err(&o));
    assert!(
        String::from_utf8_lossy(&o.stdout).contains("hello (1 forms, held to [environment])"),
        "{}",
        String::from_utf8_lossy(&o.stdout)
    );
    let payload = opened(&sealed);
    assert_eq!(payload.main.as_deref(), Some("hello/main"));
    assert_eq!(
        payload.policy.as_ref().and_then(|p| p.ceiling.clone()),
        Some(vec!["environment".to_string()])
    );

    let runner = dir.join("runner");
    put(&runner, "a runner's bytes");
    let exe = dir.join("hello-app");
    let o = blue()
        .arg("bundle")
        .arg(dir.join("main.b"))
        .arg("-o")
        .arg(&exe)
        .arg("--runner")
        .arg(&runner)
        .output()
        .unwrap();
    assert!(o.status.success(), "{}", err(&o));
    let bytes = std::fs::read(&exe).unwrap();
    assert!(bytes.starts_with(b"a runner's bytes"));
    assert_eq!(
        &bytes[b"a runner's bytes".len()..],
        std::fs::read(&sealed).unwrap()
    );
    assert_eq!(opened(&exe), payload);
    let mode = std::fs::metadata(&exe).unwrap().permissions().mode();
    assert_eq!(mode & 0o111, 0o111, "{mode:o}");
}

#[test]
fn bundle_refuses_a_stale_lock_and_writes_nothing() {
    let dir = project("stale");
    put(
        &dir.join("Bluefile"),
        "package(\"hello\", \"0.1.0\")\nallow(%i[environment clock])\napp(\"hello\", \"main.b\")\n",
    );
    let out = dir.join("hello.payload");
    let o = blue()
        .arg("bundle")
        .arg(dir.join("main.b"))
        .arg("-o")
        .arg(&out)
        .output()
        .unwrap();
    assert!(!o.status.success());
    assert!(err(&o).contains("run `blue lock"), "{}", err(&o));
    assert!(!out.exists(), "a refused bundle writes nothing");
}
