use std::fmt;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Scheduling {
    #[default]
    Normal,
    Idle,
}

pub const PRIVILEGED: &str = "realtime";

pub const OPTION: &str = "scheduling";

pub const LANE_STACK: usize = 64 << 20;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Refusal {
    Privileged,
    Unknown(String),
    Absent,
}

impl Refusal {
    #[must_use]
    pub fn kind(&self) -> &'static str {
        match self {
            Refusal::Privileged => "permission_denied",
            Refusal::Unknown(_) => "bad_option",
            Refusal::Absent => "unsupported",
        }
    }
}

impl fmt::Display for Refusal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Refusal::Privileged => write!(
                f,
                "scheduling: :{PRIVILEGED} is the class the OS never preempts, and it gives it only to a privileged process; blue runs unprivileged, so a process is :normal or :idle"
            ),
            Refusal::Unknown(got) => write!(
                f,
                "scheduling is :normal or :idle (:{PRIVILEGED} needs a privileged process), got {got}"
            ),
            Refusal::Absent => write!(
                f,
                "scheduling: this host ({}) gives a thread no lowest priority blue can ask for; spawn it :normal",
                std::env::consts::OS
            ),
        }
    }
}

impl Scheduling {
    pub const ALL: [Scheduling; 2] = [Scheduling::Normal, Scheduling::Idle];

    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            Scheduling::Normal => "normal",
            Scheduling::Idle => "idle",
        }
    }

    pub fn named(word: &str) -> Result<Self, Refusal> {
        match word.trim_start_matches(':') {
            "normal" => Ok(Scheduling::Normal),
            "idle" if os::HOSTED => Ok(Scheduling::Idle),
            "idle" => Err(Refusal::Absent),
            PRIVILEGED => Err(Refusal::Privileged),
            other => Err(Refusal::Unknown(format!(":{other}"))),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Priority {
    pub value: i32,
    pub lowest: bool,
}

pub fn lower() -> Result<(), String> {
    os::lower()
}

pub fn current() -> Result<Priority, String> {
    os::current()
}

#[cfg(any(target_os = "linux", target_os = "android"))]
mod os {
    use super::Priority;

    pub const HOSTED: bool = true;

    const LOWEST: i32 = 19;

    pub fn lower() -> Result<(), String> {
        rustix::process::setpriority_process(Some(rustix::thread::gettid()), LOWEST)
            .map_err(|e| format!("setpriority to nice {LOWEST}: {e}"))
    }

    pub fn current() -> Result<Priority, String> {
        let nice = rustix::process::getpriority_process(Some(rustix::thread::gettid()))
            .map_err(|e| format!("getpriority: {e}"))?;
        Ok(Priority {
            value: nice,
            lowest: nice >= LOWEST,
        })
    }
}

#[cfg(target_vendor = "apple")]
mod os {
    pub const HOSTED: bool = true;

    pub use crate::seam::{current, lower};
}

#[cfg(not(any(target_os = "linux", target_os = "android", target_vendor = "apple")))]
mod os {
    use super::{Priority, Refusal};

    pub const HOSTED: bool = false;

    pub fn lower() -> Result<(), String> {
        Err(Refusal::Absent.to_string())
    }

    pub fn current() -> Result<Priority, String> {
        Err(Refusal::Absent.to_string())
    }
}
