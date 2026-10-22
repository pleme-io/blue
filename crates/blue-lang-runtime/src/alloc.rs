//! How many allocations a stretch of a blue program made, and how many bytes.
//!
//! `blue profile` reports time per definition; this is the other half of what
//! a definition costs (`theory/BLUE-MEMORY.md` §VI M0: you cannot configure
//! what you cannot account for). One counter, read at two points: a caller
//! snapshots [`allocations`] when an activation enters and again when it
//! leaves, and the difference is what that activation allocated, everything it
//! called included. Subtracting what its callees allocated gives the
//! exclusive figure, exactly as the profiler does with time.
//!
//! [`Counting`] is a `GlobalAlloc` over `System` that counts each allocation
//! on the thread that made it. A binary opts in with one line:
//!
//! ```ignore
//! #[global_allocator]
//! static ALLOC: blue_lang_runtime::alloc::Counting = blue_lang_runtime::alloc::Counting;
//! ```
//!
//! The count is per thread so a profile of one interpreter is not charged for
//! another thread's work, and it costs two thread-local additions per
//! allocation and one per free (so a room can say what it left live). Until a binary installs [`Counting`],
//! [`allocations`] answers `None`: a program that was never counted reads as
//! unmeasured, never as having allocated nothing.

use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::sync::atomic::{AtomicBool, Ordering};

/// Allocations made and bytes requested on one thread, from its start.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Allocations {
    /// Allocation calls. A `realloc` that grows counts as one.
    pub count: u64,
    /// Bytes requested. A growing `realloc` counts the bytes it added.
    pub bytes: u64,
    /// Bytes returned. A shrinking `realloc` counts the bytes it gave back.
    /// Charged to the thread that frees, which for blue's single-threaded
    /// interpreters is the thread that allocated.
    pub freed: u64,
}

impl Allocations {
    /// What was allocated between `earlier` and `self`, on one thread.
    #[must_use]
    pub fn since(self, earlier: Self) -> Self {
        Self {
            count: self.count.saturating_sub(earlier.count),
            bytes: self.bytes.saturating_sub(earlier.bytes),
            freed: self.freed.saturating_sub(earlier.freed),
        }
    }

    /// Bytes allocated and not yet returned over the stretch this measures:
    /// what it left live. Negative when it freed more than it allocated
    /// (memory from before the stretch was released inside it).
    #[must_use]
    pub fn retained(self) -> i64 {
        i64::try_from(self.bytes).unwrap_or(i64::MAX)
            - i64::try_from(self.freed).unwrap_or(i64::MAX)
    }
}

impl std::ops::AddAssign for Allocations {
    fn add_assign(&mut self, other: Self) {
        self.count += other.count;
        self.bytes += other.bytes;
        self.freed += other.freed;
    }
}

/// Set by the first allocation [`Counting`] serves, so [`allocations`] can tell
/// "not counted" from "counted zero".
static INSTALLED: AtomicBool = AtomicBool::new(false);
thread_local! {
    // `const` initialisation: no lazy init, so no allocation from inside the
    // allocator, and no destructor to run during thread teardown.
    static COUNT: Cell<u64> = const { Cell::new(0) };
    static BYTES: Cell<u64> = const { Cell::new(0) };
    static FREED: Cell<u64> = const { Cell::new(0) };
}

/// This thread's running totals, or `None` when [`Counting`] is not the global
/// allocator of this binary.
#[must_use]
pub fn allocations() -> Option<Allocations> {
    if !INSTALLED.load(Ordering::Relaxed) {
        return None;
    }
    Some(Allocations {
        count: COUNT.try_with(Cell::get).unwrap_or(0),
        bytes: BYTES.try_with(Cell::get).unwrap_or(0),
        freed: FREED.try_with(Cell::get).unwrap_or(0),
    })
}

fn charge(bytes: usize) {
    // `try_with`: an allocation made while this thread's locals are being torn
    // down is served and simply not counted.
    let _ = COUNT.try_with(|c| c.set(c.get() + 1));
    let _ = BYTES.try_with(|b| b.set(b.get() + bytes as u64));
}

fn credit(bytes: usize) {
    let _ = FREED.try_with(|f| f.set(f.get() + bytes as u64));
}

/// The system allocator, counting what each thread allocates. See the module
/// documentation for how a binary installs it.
pub struct Counting;

// SAFETY: every method forwards to `System` with the caller's arguments
// unchanged; the counting touches only `Cell`s and an atomic flag, neither of
// which allocates.
unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        INSTALLED.store(true, Ordering::Relaxed);
        charge(layout.size());
        unsafe { System.alloc(layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        INSTALLED.store(true, Ordering::Relaxed);
        charge(layout.size());
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        credit(layout.size());
        unsafe { System.dealloc(ptr, layout) }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        if new_size > layout.size() {
            charge(new_size - layout.size());
        } else {
            credit(layout.size() - new_size);
        }
        unsafe { System.realloc(ptr, layout, new_size) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// This crate's own test binary does not install [`Counting`], so the
    /// answer must be "unmeasured", not a zero that reads as "allocated
    /// nothing". `tests/alloc_count.rs` installs it and measures.
    #[test]
    fn an_uncounted_binary_reads_as_unmeasured() {
        let _ = vec![1u8; 64];
        assert_eq!(allocations(), None);
    }

    #[test]
    fn since_is_the_difference_and_never_underflows() {
        let a = Allocations {
            count: 3,
            bytes: 100,
            freed: 40,
        };
        let b = Allocations {
            count: 5,
            bytes: 160,
            freed: 50,
        };
        assert_eq!(
            b.since(a),
            Allocations {
                count: 2,
                bytes: 60,
                freed: 10
            }
        );
        assert_eq!(a.since(b), Allocations::default());
    }
}
