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

pub(crate) fn poll(
    wanted: &[(i32, bool, bool)],
    timeout_ms: i32,
) -> Result<Vec<crate::readiness::Events>, String> {
    let mut set: Vec<libc::pollfd> = wanted
        .iter()
        .map(|&(fd, read, write)| libc::pollfd {
            fd,
            events: (if read { libc::POLLIN } else { 0 }) | (if write { libc::POLLOUT } else { 0 }),
            revents: 0,
        })
        .collect();
    let count =
        libc::nfds_t::try_from(set.len()).map_err(|_| "too many handles to poll".to_string())?;
    loop {
        let status = unsafe { libc::poll(set.as_mut_ptr(), count, timeout_ms) };
        if status >= 0 {
            break;
        }
        let e = std::io::Error::last_os_error();
        if e.kind() != std::io::ErrorKind::Interrupted {
            return Err(format!("poll(2): {e}"));
        }
    }
    Ok(set
        .iter()
        .map(|p| crate::readiness::Events {
            read: p.revents & libc::POLLIN != 0,
            write: p.revents & libc::POLLOUT != 0,
            closed: p.revents & (libc::POLLHUP | libc::POLLERR | libc::POLLNVAL) != 0
                && p.revents & libc::POLLIN == 0,
        })
        .collect())
}
