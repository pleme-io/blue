use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH").env_remove("BLUE_DIST");
    c
}

fn tree(name: &str, files: &[(&str, &str)]) -> PathBuf {
    let root = std::env::temp_dir().join(format!("blue-doors-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    for (rel, text) in files {
        let p = root.join(rel);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, text).unwrap();
    }
    root.canonicalize().unwrap()
}

const USER: &str = "use(\"onlyhere\", [:marker])\n\ndef shown()\n  marker\nend\n\ntest \"marker\"\n  assert shown == 42\nend\n\nshown\n";

fn project(name: &str) -> PathBuf {
    tree(
        name,
        &[
            (
                "proj/Bluefile",
                "package(\"doors-proj\", \"0.1.0\")\npackages(\"bidamas\")\n",
            ),
            (
                "proj/bidamas/onlyhere/Bluefile",
                "package(\"onlyhere\", \"0.1.0\")\n",
            ),
            (
                "proj/bidamas/onlyhere/onlyhere.b",
                "def marker()\n  42\nend\n",
            ),
            ("proj/main.b", USER),
            (
                "stale/onlyhere/Bluefile",
                "package(\"onlyhere\", \"0.0.9\")\n",
            ),
            ("stale/onlyhere/onlyhere.b", "def other()\n  1\nend\n"),
            ("older/kazoe2/Bluefile", "package(\"kazoe2\", \"0.1.0\")\n"),
            ("older/kazoe2/kazoe2.b", "def k()\n  1\nend\n"),
        ],
    )
}

fn frame(v: &serde_json::Value) -> Vec<u8> {
    let body = v.to_string();
    format!("Content-Length: {}\r\n\r\n{body}", body.len()).into_bytes()
}

fn lsp(root: &Path, file: &Path, env: &[(&str, PathBuf)]) -> String {
    let mut c = blue();
    for (k, v) in env {
        c.env(k, v);
    }
    let mut child = c
        .arg("lsp")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let uri = format!("file://{}", file.display());
    let text = std::fs::read_to_string(file).unwrap();
    let mut stdin = child.stdin.take().unwrap();
    for m in [
        serde_json::json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootUri": format!("file://{}", root.display())}}),
        serde_json::json!({"jsonrpc":"2.0","method":"initialized","params":{}}),
        serde_json::json!({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":uri,"languageId":"blue","version":1,"text":text}}}),
        serde_json::json!({"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}),
        serde_json::json!({"jsonrpc":"2.0","method":"exit","params":null}),
    ] {
        stdin.write_all(&frame(&m)).unwrap();
    }
    drop(stdin);
    let out = child.wait_with_output().unwrap();
    String::from_utf8_lossy(&out.stdout).to_string()
}

fn door(args: &[&str], env: &[(&str, PathBuf)], cwd: &Path) -> (bool, String) {
    let mut c = blue();
    for (k, v) in env {
        c.env(k, v);
    }
    let out = c.args(args).current_dir(cwd).output().unwrap();
    (
        out.status.success(),
        format!(
            "{}{}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        ),
    )
}

#[test]
fn the_editor_resolves_a_bidama_only_the_documents_project_has() {
    let root = project("lsp-project");
    let file = root.join("proj/main.b");
    let out = lsp(&root, &file, &[("BLUE_PATH", root.join("older"))]);
    assert!(out.contains("\"diagnostics\":[]"), "{out}");
    let control = root.join("proj/control.b");
    std::fs::write(&control, "use(\"nosuch\", [:marker])\n\nmarker\n").unwrap();
    let out = lsp(&root, &control, &[("BLUE_PATH", root.join("older"))]);
    assert!(out.contains("no bidama named \\\"nosuch\\\""), "{out}");
}

#[test]
fn the_editor_resolves_a_project_bidama_from_a_file_inside_another_bidama() {
    let root = project("lsp-inner");
    let file = root.join("proj/bidamas/user/user.b");
    std::fs::create_dir_all(file.parent().unwrap()).unwrap();
    std::fs::write(
        root.join("proj/bidamas/user/Bluefile"),
        "package(\"user\", \"0.1.0\")\nneeds(\"onlyhere\", \"^0.1\")\n",
    )
    .unwrap();
    std::fs::write(
        &file,
        "use(\"onlyhere\", [:marker])\n\ndef shown()\n  marker\nend\n",
    )
    .unwrap();
    let out = lsp(
        Path::new("/"),
        &file,
        &[
            ("BLUE_PATH", root.join("older")),
            ("BLUE_DIST", root.join("stale")),
        ],
    );
    assert!(out.contains("\"diagnostics\":[]"), "{out}");
}

#[test]
fn no_installed_copy_shadows_the_projects_own_bidama_at_any_door() {
    let root = project("shadow");
    let main = root.join("proj/main.b");
    let m = main.display().to_string();
    let at = format!("{m}:4");
    for env in [
        vec![("BLUE_PATH", root.join("stale"))],
        vec![("BLUE_DIST", root.join("stale"))],
        vec![
            ("BLUE_PATH", root.join("stale")),
            ("BLUE_DIST", root.join("stale")),
        ],
    ] {
        for args in [
            vec!["check", m.as_str()],
            vec!["run", m.as_str()],
            vec!["test", m.as_str()],
            vec!["ast", "--resolved", m.as_str()],
            vec!["explain-name", "marker", at.as_str()],
        ] {
            let (ok, out) = door(&args, &env, &root);
            assert!(ok, "{args:?} under {env:?}: {out}");
            assert!(!out.contains("no bidama named"), "{args:?}: {out}");
        }
        let (_, ran) = door(&["run", m.as_str()], &env, &root);
        assert!(ran.contains("42"), "{env:?}: {ran}");
        let out = lsp(&root, &main, &env);
        assert!(
            out.contains("\"diagnostics\":[]"),
            "lsp under {env:?}: {out}"
        );
    }
}

#[test]
fn a_bidama_off_the_path_is_refused_with_the_bluefile_line_that_fixes_it() {
    let root = tree(
        "nearby",
        &[
            ("proj/Bluefile", "package(\"doors-near\", \"0.1.0\")\n"),
            (
                "proj/libs/onlyhere/Bluefile",
                "package(\"onlyhere\", \"0.1.0\")\n",
            ),
            ("proj/libs/onlyhere/onlyhere.b", "def marker()\n  42\nend\n"),
            ("proj/libs/main.b", USER),
        ],
    );
    let m = root.join("proj/libs/main.b").display().to_string();
    let (ok, out) = door(&["check", m.as_str()], &[], &root);
    assert!(!ok, "{out}");
    assert!(out.contains("no bidama named \"onlyhere\""), "{out}");
    assert!(out.contains("the project"), "{out}");
    assert!(
        out.contains("add `packages(\\\"libs\\\")`") || out.contains("add `packages(\"libs\")`"),
        "{out}"
    );
}

#[test]
fn every_door_takes_its_loader_from_the_one_constructor() {
    let src = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut offenders = Vec::new();
    for entry in std::fs::read_dir(&src).unwrap().filter_map(Result::ok) {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("rs") {
            continue;
        }
        let text = std::fs::read_to_string(&path).unwrap();
        let lines: Vec<&str> = text.lines().collect();
        for (n, line) in lines.iter().enumerate() {
            let embedded = lines[n.saturating_sub(12)..n]
                .iter()
                .any(|l| l.contains("\"crates/blue-lang-cli/blue/"));
            let without_file = line.contains("load_path(None)") || line.contains("NoLoader");
            if (without_file && !embedded) || line.contains("Server::with_loader") {
                offenders.push(format!("{}:{}: {}", path.display(), n + 1, line.trim()));
            }
        }
    }
    assert!(offenders.is_empty(), "{offenders:#?}");
}

#[test]
fn check_fix_derives_a_bidamas_needs_from_its_uses_and_relocks() {
    let root = tree(
        "needs-fix",
        &[
            (
                "proj/Bluefile",
                "package(\"doors-needs\", \"0.1.0\")\npackages(\"bidamas\")\n",
            ),
            (
                "proj/bidamas/onlyhere/Bluefile",
                "package(\"onlyhere\", \"0.4.1\")\n",
            ),
            (
                "proj/bidamas/onlyhere/onlyhere.b",
                "def marker()\n  42\nend\n",
            ),
            (
                "proj/bidamas/user/Bluefile",
                "package(\"user\", \"0.1.0\")\nneeds(\"unused\", \"^0.1\")\n",
            ),
            (
                "proj/bidamas/user/user.b",
                "use(\"onlyhere\", [:marker])\n\ndef shown()\n  marker\nend\n",
            ),
        ],
    );
    let file = root.join("proj/bidamas/user/user.b");
    let f = file.display().to_string();
    let (ok, before) = door(&["check", f.as_str()], &[], &root);
    assert!(!ok && before.contains("B0019"), "{before}");
    let (ok, fixed) = door(&["check", "--fix", f.as_str()], &[], &root);
    assert!(ok, "{fixed}");
    let bluefile = std::fs::read_to_string(root.join("proj/bidamas/user/Bluefile")).unwrap();
    assert_eq!(
        bluefile,
        "package(\"user\", \"0.1.0\")\nneeds(\"onlyhere\", \"^0.4\")\n"
    );
    let lock = std::fs::read_to_string(root.join("proj/bidamas/user/Bluefile.lock")).unwrap();
    assert!(lock.contains("\"onlyhere\": \"^0.4"), "{lock}");
    let (ok, after) = door(&["check", f.as_str()], &[], &root);
    assert!(ok, "{after}");
}
