#![cfg(unix)]
#![deny(unsafe_code)]

use std::io::Read;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

const BUDGET: Duration = Duration::from_secs(1);

#[allow(unsafe_code)]
mod sys {
    use std::os::unix::process::CommandExt;
    use std::process::Command;

    pub fn signal(target: libc::pid_t, sig: libc::c_int) -> bool {
        unsafe { libc::kill(target, sig) == 0 }
    }

    pub fn sigint_on_entry(command: &mut Command, disposition: libc::sighandler_t) {
        unsafe {
            command.pre_exec(move || {
                let mut action: libc::sigaction = std::mem::zeroed();
                action.sa_sigaction = disposition;
                if libc::sigaction(libc::SIGINT, &action, std::ptr::null_mut()) == 0 {
                    Ok(())
                } else {
                    Err(std::io::Error::last_os_error())
                }
            });
        }
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

struct Run {
    dir: PathBuf,
    blue: Child,
    group: libc::pid_t,
    child: Option<libc::pid_t>,
    stopped: bool,
}

impl Drop for Run {
    fn drop(&mut self) {
        if !self.stopped {
            sys::signal(self.group, libc::SIGKILL);
            if let Some(child) = self.child {
                sys::signal(child, libc::SIGKILL);
            }
        }
        let _ = self.blue.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn start(name: &str, sigint: libc::sighandler_t) -> Run {
    let dir = std::env::temp_dir().join(format!("blue-cli-stop-{}-{name}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("a scratch dir");
    let program = dir.join("wait.b");
    std::fs::write(
        &program,
        "exec_capture(\"sleep\", \"37\")\nwrite_stderr(\"the child finished\\n\")\n",
    )
    .expect("the program is written");
    let mut command = Command::new(env!("CARGO_BIN_EXE_blue"));
    command
        .args(["run", "--quiet"])
        .arg(&program)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0);
    sys::sigint_on_entry(&mut command, sigint);
    let blue = command.spawn().expect("blue starts");
    let group = -libc::pid_t::try_from(blue.id()).expect("a pid is a pid_t");
    let mut run = Run {
        dir,
        blue,
        group,
        child: None,
        stopped: false,
    };
    let started = Instant::now();
    while run.child.is_none() {
        run.child = child_named(run.blue.id(), "sleep");
        if let Some(status) = run.blue.try_wait().expect("blue can be waited on") {
            panic!("blue ended before its child started: {status}");
        }
        assert!(
            started.elapsed() < Duration::from_secs(20),
            "the child never started"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
    run
}

impl Run {
    fn child(&self) -> libc::pid_t {
        self.child.expect("the child started")
    }

    fn ctrl_c(&self) -> Instant {
        assert!(
            sys::signal(self.group, libc::SIGINT),
            "ctrl-c reaches blue's group"
        );
        Instant::now()
    }

    fn still_runs(&mut self, after: &str) {
        assert!(
            self.blue
                .try_wait()
                .expect("blue can be waited on")
                .is_none(),
            "blue stopped {after}"
        );
        assert!(sys::signal(self.child(), 0), "blue's child stopped {after}");
    }

    fn stop(&mut self) {
        let child = self.child();
        let sent = self.ctrl_c();
        let mut stopped = None;
        let mut survivors = true;
        let status = loop {
            let waited = sent.elapsed();
            if stopped.is_none() {
                stopped = self.blue.try_wait().expect("blue can be waited on");
            }
            survivors = survivors && (sys::signal(child, 0) || sys::signal(self.group, 0));
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
        self.stopped = true;
        let mut stderr = String::new();
        self.blue
            .stderr
            .take()
            .expect("blue's stderr is piped")
            .read_to_string(&mut stderr)
            .expect("blue's stderr");
        assert_eq!(status.code(), Some(130), "stderr: {stderr}");
        assert!(
            stderr.contains("blue: stopped (ctrl-c)"),
            "stderr: {stderr}"
        );
        assert!(!stderr.contains("the child finished"), "stderr: {stderr}");
    }
}

#[test]
fn ctrl_c_stops_blue_run_and_its_children_within_a_second() {
    start("alone", libc::SIG_DFL).stop();
}

#[test]
fn ctrl_c_stops_one_blue_run_within_a_second_while_others_run() {
    let mut runs: Vec<Run> = (0..4)
        .map(|n| start(&format!("concurrent-{n}"), libc::SIG_DFL))
        .collect();
    for n in 0..runs.len() {
        let (stopped, others) = runs[n..].split_first_mut().expect("a run is left");
        stopped.stop();
        for other in others {
            other.still_runs("when ctrl-c went to another blue run's group");
        }
    }
}

#[test]
fn a_blue_run_that_inherits_an_ignored_ctrl_c_keeps_running_with_its_children() {
    let mut run = start("ignored", libc::SIG_IGN);
    let sent = run.ctrl_c();
    while sent.elapsed() < BUDGET {
        run.still_runs("after a ctrl-c its parent told it to ignore");
        std::thread::sleep(Duration::from_millis(10));
    }
}
