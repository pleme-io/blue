use std::sync::Arc;
use std::time::Duration;

use tatara_lisp_eval::Value;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Interest {
    Read,
    Write,
    Both,
}

impl Interest {
    #[must_use]
    pub fn named(word: &str) -> Option<Self> {
        match word {
            "read" => Some(Self::Read),
            "write" => Some(Self::Write),
            "both" => Some(Self::Both),
            _ => None,
        }
    }

    fn reads(self) -> bool {
        matches!(self, Self::Read | Self::Both)
    }

    fn writes(self) -> bool {
        matches!(self, Self::Write | Self::Both)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ready {
    Read,
    Write,
    Closed,
}

impl Ready {
    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            Self::Read => "read",
            Self::Write => "write",
            Self::Closed => "closed",
        }
    }
}

#[cfg(unix)]
pub type Pollable = Arc<dyn std::os::fd::AsFd + Send + Sync>;
#[cfg(not(unix))]
pub type Pollable = Arc<dyn std::any::Any + Send + Sync>;

pub type FdOf = fn(&Value) -> Option<Pollable>;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct Events {
    pub read: bool,
    pub write: bool,
    pub closed: bool,
}

pub(crate) fn readiness(interest: Interest, e: Events) -> Vec<Ready> {
    if e.closed {
        return vec![Ready::Closed];
    }
    let mut out = Vec::new();
    if interest.reads() && e.read {
        out.push(Ready::Read);
    }
    if interest.writes() && e.write {
        out.push(Ready::Write);
    }
    out
}

#[cfg(any(target_os = "linux", target_os = "android"))]
pub(crate) fn poll(
    fds: &[(Pollable, Interest)],
    timeout: Option<Duration>,
) -> Result<Vec<Events>, String> {
    use rustix::event::{PollFd, PollFlags, Timespec};
    let mut set: Vec<PollFd<'_>> = fds
        .iter()
        .map(|(fd, interest)| {
            let mut flags = PollFlags::empty();
            if interest.reads() {
                flags |= PollFlags::IN;
            }
            if interest.writes() {
                flags |= PollFlags::OUT;
            }
            PollFd::new(fd, flags)
        })
        .collect();
    let limit = timeout.map(|d| Timespec {
        tv_sec: i64::try_from(d.as_secs()).unwrap_or(i64::MAX),
        tv_nsec: i64::from(d.subsec_nanos()),
    });
    loop {
        match rustix::event::poll(&mut set, limit.as_ref()) {
            Ok(_) => break,
            Err(rustix::io::Errno::INTR) => continue,
            Err(e) => return Err(format!("poll(2): {e}")),
        }
    }
    Ok(set
        .iter()
        .map(|p| {
            let r = p.revents();
            Events {
                read: r.contains(PollFlags::IN),
                write: r.contains(PollFlags::OUT),
                closed: r.intersects(PollFlags::HUP | PollFlags::ERR | PollFlags::NVAL)
                    && !r.contains(PollFlags::IN),
            }
        })
        .collect())
}

#[cfg(target_vendor = "apple")]
pub(crate) fn poll(
    fds: &[(Pollable, Interest)],
    timeout: Option<Duration>,
) -> Result<Vec<Events>, String> {
    use std::os::fd::{AsFd, AsRawFd};
    let wanted: Vec<(i32, bool, bool)> = fds
        .iter()
        .map(|(fd, interest)| (fd.as_fd().as_raw_fd(), interest.reads(), interest.writes()))
        .collect();
    let ms = timeout.map_or(-1, |d| i32::try_from(d.as_millis()).unwrap_or(i32::MAX));
    crate::seam::poll(&wanted, ms)
}

#[cfg(not(any(target_os = "linux", target_os = "android", target_vendor = "apple")))]
pub(crate) fn poll(
    _fds: &[(Pollable, Interest)],
    _timeout: Option<Duration>,
) -> Result<Vec<Events>, String> {
    Err("this target has no readiness source (poll(2))".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_closed_handle_answers_closed_whatever_was_asked() {
        let e = Events {
            read: true,
            write: true,
            closed: true,
        };
        assert_eq!(readiness(Interest::Both, e), vec![Ready::Closed]);
    }

    #[test]
    fn readiness_answers_only_what_the_interest_asked() {
        let e = Events {
            read: true,
            write: true,
            closed: false,
        };
        assert_eq!(readiness(Interest::Read, e), vec![Ready::Read]);
        assert_eq!(readiness(Interest::Write, e), vec![Ready::Write]);
        assert_eq!(
            readiness(Interest::Both, e),
            vec![Ready::Read, Ready::Write]
        );
        assert!(readiness(Interest::Read, Events::default()).is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn a_pipe_is_readable_only_after_a_write_and_poll_waits_no_longer_than_asked() {
        use std::io::Write;
        let (a, mut b) = std::os::unix::net::UnixStream::pair().expect("pair");
        let fd: Pollable = Arc::new(a);
        let set = [(fd, Interest::Read)];
        let started = std::time::Instant::now();
        let idle = poll(&set, Some(Duration::from_millis(30))).expect("poll");
        assert!(!idle[0].read, "nothing was written");
        assert!(started.elapsed() >= Duration::from_millis(25));
        b.write_all(b"x").expect("write");
        let ready = poll(&set, None).expect("poll");
        assert!(ready[0].read);
        drop(b);
    }
}
