use std::io::Read as _;
use std::process::{Command, Output, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

#[derive(Debug, PartialEq, Eq)]
pub enum Unbounded {
    Spawn(String),
    Runaway(Duration),
    Wait(String),
    Signal(i32),
    HeldOpen(Duration),
}

fn drain(mut pipe: impl std::io::Read + Send + 'static) -> mpsc::Receiver<Vec<u8>> {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut b = Vec::new();
        let _ = pipe.read_to_end(&mut b);
        let _ = tx.send(b);
    });
    rx
}

pub fn output_within(
    cmd: &mut Command,
    limit: Duration,
    grace: Duration,
) -> Result<Output, Unbounded> {
    let mut child = cmd
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| Unbounded::Spawn(format!("cannot spawn {cmd:?}: {e}")))?;
    let out = drain(child.stdout.take().expect("piped stdout"));
    let err = drain(child.stderr.take().expect("piped stderr"));
    let start = Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s,
            Ok(None) if start.elapsed() > limit => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(Unbounded::Runaway(limit));
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(10)),
            Err(e) => return Err(Unbounded::Wait(e.to_string())),
        }
    };
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt as _;
        if let Some(sig) = status.signal() {
            return Err(Unbounded::Signal(sig));
        }
    }
    let until = Instant::now() + grace;
    let stdout = out
        .recv_timeout(until.saturating_duration_since(Instant::now()))
        .map_err(|_| Unbounded::HeldOpen(grace))?;
    let stderr = err
        .recv_timeout(until.saturating_duration_since(Instant::now()))
        .map_err(|_| Unbounded::HeldOpen(grace))?;
    Ok(Output {
        status,
        stdout,
        stderr,
    })
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    #[test]
    fn a_child_whose_descendant_holds_its_output_open_returns_within_the_grace() {
        let start = Instant::now();
        let got = output_within(
            Command::new("/bin/sh").args(["-c", "sleep 30 & echo started"]),
            Duration::from_secs(10),
            Duration::from_millis(500),
        );
        assert_eq!(got, Err(Unbounded::HeldOpen(Duration::from_millis(500))));
        assert!(
            start.elapsed() < Duration::from_secs(5),
            "{:?}",
            start.elapsed()
        );
    }

    #[test]
    fn a_child_that_reads_stdin_sees_its_end_rather_than_waiting() {
        let got = output_within(
            Command::new("/bin/sh").args(["-c", "cat; echo done"]),
            Duration::from_secs(10),
            Duration::from_secs(2),
        )
        .expect("cat ends at the null stdin");
        assert_eq!(String::from_utf8_lossy(&got.stdout), "done\n");
    }

    #[test]
    fn a_runaway_child_is_killed_at_the_limit() {
        let got = output_within(
            Command::new("/bin/sh").args(["-c", "exec sleep 30"]),
            Duration::from_millis(300),
            Duration::from_secs(1),
        );
        assert_eq!(got, Err(Unbounded::Runaway(Duration::from_millis(300))));
    }
}
