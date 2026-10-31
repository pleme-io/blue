#![allow(unsafe_code)]

use crate::scheduling::Priority;

pub fn lower() -> Result<(), String> {
    let status = unsafe { libc::setpriority(libc::PRIO_DARWIN_THREAD, 0, libc::PRIO_DARWIN_BG) };
    if status == 0 {
        Ok(())
    } else {
        Err(format!(
            "setpriority to the background band: {}",
            std::io::Error::last_os_error()
        ))
    }
}

pub fn current() -> Result<Priority, String> {
    let band = unsafe { libc::getpriority(libc::PRIO_DARWIN_THREAD, 0) };
    if band < 0 {
        return Err(format!(
            "getpriority of this thread's band: {}",
            std::io::Error::last_os_error()
        ));
    }
    Ok(Priority {
        value: band,
        lowest: band > 0,
    })
}
