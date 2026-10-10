//! `blue workload render`, `blue diff` and `blue image build` as a user runs
//! them: the binary, real files, and the exit code.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn blue(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .args(args)
        .output()
        .expect("spawn blue")
}

/// A project directory holding a Bluefile and its lock, unique per test.
fn project(test: &str, bluefile: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(["blue-deploy-test-", test].concat());
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("mkdir");
    std::fs::write(dir.join("Bluefile"), bluefile).expect("write Bluefile");
    let out = blue(&["lock", dir.to_str().expect("utf-8")]);
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    dir
}

const SERVICE: &str = "package(\"svc\", \"0.2.0\")\n\
    image(\"svc\", {program: \"svc.b\", repository: \"ghcr.io/pleme-io/svc\"})\n\
    workload(\"svc\", {image: \"svc\", namespace: \"svc\", ports: {http: 8080}, probe: :tcp})\n";

fn lock_of(dir: &Path) -> String {
    dir.join("Bluefile.lock").display().to_string()
}

fn stderr(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

/// `--write` writes exactly what a plain render prints, at the workload's
/// `output`, which is what nix's freshness gate compares.
#[test]
fn render_write_writes_what_render_prints() {
    let dir = project("render", SERVICE);
    let printed = blue(&["workload", "render", "svc", "--lock", &lock_of(&dir)]);
    assert!(printed.status.success(), "{}", stderr(&printed));
    let wrote = blue(&["workload", "render", "--write", "--lock", &lock_of(&dir)]);
    assert!(wrote.status.success(), "{}", stderr(&wrote));
    let file = std::fs::read(dir.join("deploy/svc.yaml")).expect("written");
    assert_eq!(file, printed.stdout);
    let v: serde_json::Value = serde_json::from_slice(&file).expect("JSON");
    assert_eq!(v["items"][0]["spec"]["template"]["spec"]["containers"][0]["image"], "ghcr.io/pleme-io/svc:0.2.0");
}

/// **`blue diff` names its cluster or does nothing.** Without `--context` it
/// exits 2 before reading the lock or starting kubectl.
///
/// The positive control is the same call WITH a context: it gets as far as
/// starting the (missing) kubectl, so the refusal above is the context's
/// absence and not some earlier failure. Red run, 2026-10-10: with the
/// `NoContext` arm removed from `run_diff`, this failed at "pass --context":
/// the call went on to read the lock.
#[test]
fn diff_without_a_context_is_refused_before_touching_anything() {
    let dir = project("diff", SERVICE);
    let render = blue(&["workload", "render", "--write", "--lock", &lock_of(&dir)]);
    assert!(render.status.success(), "{}", stderr(&render));
    let missing = "/nonexistent/kubectl";
    for args in [
        vec!["diff", "--lock", "/nonexistent/Bluefile.lock", "--kubectl", missing],
        vec!["diff", "--context", " ", "--lock", "/nonexistent/Bluefile.lock", "--kubectl", missing],
    ] {
        let out = blue(&args);
        assert_eq!(out.status.code(), Some(2), "{args:?}");
        let err = stderr(&out);
        assert!(err.contains("pass --context"), "{err}");
        assert!(!err.contains("could not start"), "{err}");
    }
    let lock = lock_of(&dir);
    let out = blue(&["diff", "--context", "dev", "--lock", &lock, "--kubectl", missing]);
    assert_eq!(out.status.code(), Some(2));
    assert!(stderr(&out).contains("could not start `/nonexistent/kubectl`"), "{}", stderr(&out));
}

/// A refused Bluefile does not lock, and every refused entry is named.
#[test]
fn lock_refuses_every_bad_entry_by_name() {
    let dir = std::env::temp_dir().join("blue-deploy-test-refused");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("mkdir");
    std::fs::write(
        dir.join("Bluefile"),
        "package(\"p\", \"0.1.0\")\n\
         image(\"a\", {program: \"a.b\", repository: \"ghcr.io/x/a\", tools: [\"jq\"]})\n\
         workload(\"b\", {image: \"ghcr.io/x/b:latest\", namespace: \"n\"})\n",
    )
    .expect("write");
    let out = blue(&["lock", dir.to_str().expect("utf-8")]);
    assert!(!out.status.success());
    let err = stderr(&out);
    assert!(err.contains("`image(\"a\", …)`: `tools` leaves distroless"), "{err}");
    assert!(err.contains("`workload(\"b\", …)`"), "{err}");
    assert!(!dir.join("Bluefile.lock").exists());
}

/// `blue image build` names what it would build from the lock, so a typo is
/// refused before nix starts.
#[test]
fn image_build_refuses_an_undeclared_image_before_nix() {
    let dir = project("image", SERVICE);
    let out = blue(&["image", "build", "nope", "--dir", dir.to_str().expect("utf-8")]);
    assert!(!out.status.success());
    assert!(stderr(&out).contains("no image `nope`; the Bluefile declares svc"), "{}", stderr(&out));
}
