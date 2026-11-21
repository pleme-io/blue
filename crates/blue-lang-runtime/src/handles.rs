//! The host handles a thread holds open: TCP connections, listeners and
//! serial ports opened by the network words. A handle counts from the word
//! that opens it until `tcp_close` closes it or its last reference is dropped,
//! whichever comes first, so a run that closes everything it opened, by hand or
//! by ending, returns the count to where it began. The conformance suite's
//! `closes_at(:end)` reads it before and after a row (I2 of docs/PURE-BLUE.md).

use std::cell::Cell;
use std::sync::atomic::{AtomicBool, Ordering};

thread_local! {
    static OPEN: Cell<i64> = const { Cell::new(0) };
}

/// How many handles this thread has opened and not yet closed.
#[must_use]
pub fn open() -> i64 {
    OPEN.with(Cell::get)
}

/// One handle's place in the count: opened when made, closed once.
#[derive(Debug)]
pub struct Counted(AtomicBool);

impl Counted {
    /// Count a handle just opened.
    #[must_use]
    pub fn opened() -> Counted {
        OPEN.with(|c| c.set(c.get() + 1));
        Counted(AtomicBool::new(false))
    }

    /// Take the handle out of the count, once however often it is called.
    pub fn close(&self) {
        if !self.0.swap(true, Ordering::Relaxed) {
            OPEN.with(|c| c.set(c.get() - 1));
        }
    }
}

impl Drop for Counted {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_handle_counts_until_it_is_closed_or_dropped_and_closes_once() {
        let at = open();
        let a = Counted::opened();
        let b = Counted::opened();
        assert_eq!(open(), at + 2);
        a.close();
        a.close();
        assert_eq!(open(), at + 1);
        drop(a);
        assert_eq!(open(), at + 1);
        drop(b);
        assert_eq!(open(), at);
    }
}
