#![cfg(unix)]

use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

fn group_alive(pgid: u32) -> bool {
    Command::new("pgrep")
        .args(["-g", &pgid.to_string()])
        .output()
        .is_ok_and(|o| !o.stdout.is_empty())
}

#[test]
fn ctrl_c_stops_blue_run_and_its_children_within_a_second() {
    let dir = std::env::temp_dir().join(format!("blue-cli-stop-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("a scratch dir");
    let program = dir.join("wait.b");
    std::fs::write(
        &program,
        "exec_capture(\"sleep\", \"37\")\nwrite_stderr(\"the child finished\\n\")\n",
    )
    .expect("the program is written");
    let mut child = Command::new(env!("CARGO_BIN_EXE_blue"))
        .args(["run", "--quiet"])
        .arg(&program)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0)
        .spawn()
        .expect("blue starts");
    let pgid = child.id();
    let started = Instant::now();
    while !Command::new("pgrep")
        .args(["-g", &pgid.to_string(), "-x", "sleep"])
        .output()
        .is_ok_and(|o| !o.stdout.is_empty())
    {
        assert!(
            started.elapsed() < Duration::from_secs(20),
            "the child never started"
        );
        std::thread::sleep(Duration::from_millis(20));
    }
    let sent = Instant::now();
    let kill = Command::new("kill")
        .args(["-INT", &format!("-{pgid}")])
        .status()
        .expect("kill runs");
    assert!(kill.success());
    let status = loop {
        if let Some(s) = child.try_wait().expect("blue can be waited on") {
            break s;
        }
        assert!(
            sent.elapsed() < Duration::from_secs(1),
            "blue still runs a second after ctrl-c"
        );
        std::thread::sleep(Duration::from_millis(10));
    };
    let out = child.wait_with_output().expect("blue's output");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert_eq!(status.code(), Some(130), "stderr: {stderr}");
    assert!(
        stderr.contains("blue: stopped (ctrl-c)"),
        "stderr: {stderr}"
    );
    assert!(!stderr.contains("the child finished"), "stderr: {stderr}");
    std::thread::sleep(Duration::from_millis(100));
    assert!(!group_alive(pgid), "a child of blue survived the ctrl-c");
}
