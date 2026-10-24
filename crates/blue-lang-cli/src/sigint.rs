#![deny(unsafe_code)]

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};

static FLAG: OnceLock<Arc<AtomicBool>> = OnceLock::new();

const STOPPED: &[u8] = b"\nblue: stopped (ctrl-c)\n";

#[cfg(unix)]
extern "C" fn on_interrupt(_: libc::c_int) {
    if let Some(flag) = FLAG.get() {
        flag.store(true, Ordering::SeqCst);
    }
}

#[cfg(unix)]
extern "C" fn on_stop(_: libc::c_int) {
    #[allow(unsafe_code)]
    unsafe {
        libc::write(2, STOPPED.as_ptr().cast(), STOPPED.len());
        libc::_exit(130);
    }
}

pub fn interrupt(flag: &Arc<AtomicBool>) {
    if FLAG.set(Arc::clone(flag)).is_err() {
        return;
    }
    #[cfg(unix)]
    handle(on_interrupt);
}

pub fn stop() {
    #[cfg(unix)]
    handle(on_stop);
}

#[cfg(unix)]
fn handle(handler: extern "C" fn(libc::c_int)) {
    #[allow(unsafe_code)]
    unsafe {
        let before = libc::signal(libc::SIGINT, handler as libc::sighandler_t);
        if before == libc::SIG_IGN {
            libc::signal(libc::SIGINT, libc::SIG_IGN);
        }
    }
}
