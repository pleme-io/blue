use std::io::Read;
use std::process::{Command, Stdio};
use std::sync::{mpsc, Arc, Condvar, Mutex, PoisonError};
use std::time::Duration;

#[derive(Debug)]
pub enum OnceRun {
    Finished { stdout: Vec<u8> },
    TimedOut,
    Failed(std::io::Error),
}

pub fn run_once(mut command: Command, limit: Duration) -> OnceRun {
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(e) => return OnceRun::Failed(e),
    };
    let Some(mut stdout) = child.stdout.take() else {
        let _ = child.kill();
        let _ = child.wait();
        return OnceRun::Failed(std::io::Error::other("the child has no stdout"));
    };
    let (tx, rx) = mpsc::channel();
    let reader = std::thread::Builder::new()
        .name("blue-worker-once".to_owned())
        .spawn(move || {
            let mut out = Vec::new();
            let read = stdout.read_to_end(&mut out).map(|_| out);
            let _ = tx.send(read);
        });
    if let Err(e) = reader {
        let _ = child.kill();
        let _ = child.wait();
        return OnceRun::Failed(e);
    }
    let run = match rx.recv_timeout(limit) {
        Ok(Ok(stdout)) => OnceRun::Finished { stdout },
        Ok(Err(e)) => OnceRun::Failed(e),
        Err(_) => OnceRun::TimedOut,
    };
    let _ = child.kill();
    let _ = child.wait();
    run
}

enum Waiting<T> {
    Nothing,
    Finished(T),
    GaveUp,
}

pub fn within<T: Send + 'static>(
    patience: Duration,
    work: impl FnOnce() -> T + Send + 'static,
    late: impl FnOnce(T) + Send + 'static,
) -> Option<T> {
    let slot = Arc::new((Mutex::new(Waiting::Nothing), Condvar::new()));
    let worker_slot = Arc::clone(&slot);
    let spawned = std::thread::Builder::new()
        .name("blue-worker-within".to_owned())
        .spawn(move || {
            let value = work();
            let (state, finished) = &*worker_slot;
            let mut state = state.lock().unwrap_or_else(PoisonError::into_inner);
            if matches!(*state, Waiting::GaveUp) {
                drop(state);
                late(value);
            } else {
                *state = Waiting::Finished(value);
                finished.notify_all();
            }
        });
    if spawned.is_err() {
        return None;
    }
    let (state, finished) = &*slot;
    let guard = state.lock().unwrap_or_else(PoisonError::into_inner);
    let (mut guard, _) = finished
        .wait_timeout_while(guard, patience, |state| matches!(state, Waiting::Nothing))
        .unwrap_or_else(PoisonError::into_inner);
    match std::mem::replace(&mut *guard, Waiting::GaveUp) {
        Waiting::Finished(value) => Some(value),
        Waiting::Nothing | Waiting::GaveUp => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn work_done_in_time_comes_back_and_nothing_arrives_late() {
        let (tx, rx) = mpsc::channel();
        let got = within(Duration::from_secs(30), || 7, move |v| tx.send(v).unwrap());
        assert_eq!(got, Some(7));
        assert!(rx.recv_timeout(Duration::from_millis(100)).is_err());
    }

    #[test]
    fn work_past_the_patience_arrives_late_and_only_late() {
        let (tx, rx) = mpsc::channel();
        let got = within(
            Duration::from_millis(20),
            || {
                std::thread::sleep(Duration::from_millis(300));
                7
            },
            move |v| tx.send(v).unwrap(),
        );
        assert_eq!(got, None);
        assert_eq!(rx.recv_timeout(Duration::from_secs(10)), Ok(7));
    }

    #[test]
    fn a_finished_child_gives_its_stdout() {
        let mut c = Command::new("/bin/sh");
        c.args(["-c", "printf hello"]);
        match run_once(c, Duration::from_secs(30)) {
            OnceRun::Finished { stdout } => assert_eq!(stdout, b"hello"),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn a_child_past_the_limit_is_killed_and_says_so() {
        let mut c = Command::new("/bin/sh");
        c.args(["-c", "exec sleep 30"]);
        let started = std::time::Instant::now();
        assert!(matches!(
            run_once(c, Duration::from_millis(50)),
            OnceRun::TimedOut
        ));
        assert!(started.elapsed() < Duration::from_secs(10));
    }

    #[test]
    fn a_missing_program_is_a_failure_not_a_panic() {
        let c = Command::new("/nonexistent/program");
        assert!(matches!(
            run_once(c, Duration::from_secs(1)),
            OnceRun::Failed(_)
        ));
    }
}
