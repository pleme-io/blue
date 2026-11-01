#![cfg(unix)]
#![deny(unsafe_code)]

use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const BUDGET: Duration = Duration::from_secs(1);

fn signal(target: libc::pid_t, sig: libc::c_int) -> bool {
    #[allow(unsafe_code)]
    unsafe {
        libc::kill(target, sig) == 0
    }
}

fn child_named(parent: u32, name: &str) -> Option<libc::pid_t> {
    let out = Command::new("pgrep")
        .args(["-P", &parent.to_string(), "-x", name])
        .output()
        .ok()?;
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .next()?
        .trim()
        .parse()
        .ok()
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
    let mut blue = Command::new(env!("CARGO_BIN_EXE_blue"))
        .args(["run", "--quiet"])
        .arg(&program)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0)
        .spawn()
        .expect("blue starts");
    let group = -libc::pid_t::try_from(blue.id()).expect("a pid is a pid_t");
    let started = Instant::now();
    let sleeper = loop {
        if let Some(pid) = child_named(blue.id(), "sleep") {
            break pid;
        }
        if let Some(status) = blue.try_wait().expect("blue can be waited on") {
            panic!("blue ended before its child started: {status}");
        }
        assert!(
            started.elapsed() < Duration::from_secs(20),
            "the child never started"
        );
        std::thread::sleep(Duration::from_millis(10));
    };
    assert!(signal(group, libc::SIGINT), "ctrl-c reaches blue's group");
    let sent = Instant::now();
    let mut stopped = None;
    let mut survivors = true;
    let status = loop {
        let waited = sent.elapsed();
        if stopped.is_none() {
            stopped = blue.try_wait().expect("blue can be waited on");
        }
        survivors = survivors && (signal(sleeper, 0) || signal(group, 0));
        if let (Some(status), false) = (stopped, survivors) {
            break status;
        }
        assert!(
            stopped.is_some() || waited < BUDGET,
            "blue still runs {waited:?} after ctrl-c"
        );
        assert!(
            !survivors || waited < BUDGET,
            "a child of blue still runs {waited:?} after ctrl-c"
        );
        std::thread::sleep(Duration::from_millis(1));
    };
    let out = blue.wait_with_output().expect("blue's output");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert_eq!(status.code(), Some(130), "stderr: {stderr}");
    assert!(
        stderr.contains("blue: stopped (ctrl-c)"),
        "stderr: {stderr}"
    );
    assert!(!stderr.contains("the child finished"), "stderr: {stderr}");
    std::fs::remove_dir_all(&dir).expect("the scratch dir is removed");
}
