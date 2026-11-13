use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-terminal-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir
}

fn run_with_stdin(program: &str, name: &str, stdin: &str) -> Output {
    let dir = scratch(name);
    let file = dir.join("main.b");
    std::fs::write(&file, program).expect("program");
    let mut child = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_DIST")
        .env("BLUE_PATH", repo().join("bidamas"))
        .current_dir(&dir)
        .args(["run", "main.b"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn blue");
    child
        .stdin
        .take()
        .expect("stdin")
        .write_all(stdin.as_bytes())
        .expect("write stdin");
    let out = child.wait_with_output().expect("wait");
    let _ = std::fs::remove_dir_all(&dir);
    out
}

fn stdout(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

#[test]
fn read_line_reads_each_line_without_its_break_and_nil_at_the_end_of_input() {
    let program = "a = read_line()\nb = read_line()\nc = read_line()\nwrite_stdout(\"#{a}|#{b}|#{c.nil?}|#{is_terminal(0)}|#{is_terminal(7)}\\n\")\n";
    let o = run_with_stdin(program, "lines", "one\r\ntwo\n");
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    assert_eq!(stdout(&o), "one|two|true|false|false\nnil\n");
}

#[test]
fn a_settings_form_on_standard_input_refuses_a_bad_edit_and_applies_a_good_one() {
    let program = "\
use(\"settei\", %i[form form_run knob no_env settle])
model = {port: knob(8080, {min: 1, max: 65535, doc: \"the port\"})}
f = form(\"app\", model, settle(\"app\", model, nil, no_env))
applied = form_run(f, (_i) -> read_line(), (t) -> write_stdout(t))
write_stdout(\"applied #{applied}\\n\")
";
    let o = run_with_stdin(program, "form", "port=70000\nport=9000\napply\n");
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    let form = |value: &str, error: Option<&str>, footer: &str| {
        let mut lines = vec![
            "app settings".to_string(),
            format!("  port  {value}  (1..65535, default)"),
        ];
        lines.extend(error.map(|e| format!("    ! {e}")));
        lines.push(footer.to_string());
        format!("{}\n\n> ", lines.join("\n"))
    };
    let expected = [
        form("8080", None, "no changes"),
        "port: must be in 1..65535, got 70000\n".to_string(),
        form("8080", Some("must be in 1..65535, got 70000"), "no changes"),
        "port -> 9000\n".to_string(),
        form("8080 -> 9000", None, "1 change(s) to apply"),
        "port: 8080 -> 9000\napplied {port: 9000}\nnil\n".to_string(),
    ]
    .concat();
    assert_eq!(stdout(&o), expected);
}

#[test]
fn a_program_whose_ceiling_lacks_the_terminal_may_not_read_a_line() {
    let program = "write_stdout(read_line())\n";
    let dir = scratch("ceiling");
    std::fs::write(dir.join("main.b"), program).expect("program");
    let o = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .current_dir(&dir)
        .args(["run", "--allow", "environment", "main.b"])
        .stdin(Stdio::null())
        .output()
        .expect("spawn blue");
    let _ = std::fs::remove_dir_all(&dir);
    assert!(!o.status.success(), "a read_line outside the ceiling ran");
    let err = String::from_utf8_lossy(&o.stderr);
    assert!(
        err.contains("`read_line` reaches the host (terminal)"),
        "{err}"
    );
    assert!(err.contains("--allow terminal"), "{err}");
}
