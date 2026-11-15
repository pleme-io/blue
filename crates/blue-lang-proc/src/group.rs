pub fn end(leader: u32) -> Result<(), String> {
    os::end(leader)
}

#[cfg(any(target_os = "linux", target_os = "android"))]
mod os {
    pub fn end(leader: u32) -> Result<(), String> {
        let raw = i32::try_from(leader).map_err(|_| format!("{leader} is not a process id"))?;
        let pid = rustix::process::Pid::from_raw(raw)
            .ok_or_else(|| format!("{leader} is not a process id"))?;
        rustix::process::kill_process_group(pid, rustix::process::Signal::KILL)
            .map_err(|e| format!("kill process group {leader}: {e}"))
    }
}

#[cfg(target_vendor = "apple")]
mod os {
    pub use crate::seam::end_group as end;
}

#[cfg(not(any(target_os = "linux", target_os = "android", target_vendor = "apple")))]
mod os {
    pub fn end(_leader: u32) -> Result<(), String> {
        Err(crate::scheduling::Refusal::Absent.to_string())
    }
}
