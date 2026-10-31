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
//! another thread's work, and it costs one thread-local access per allocation
//! and per free (so a room can say what it left live). Until a binary installs [`Counting`],
//! [`allocations`] answers `None`: a program that was never counted reads as
//! unmeasured, never as having allocated nothing.
//!
//! The same access charges an [`Account`]: the live bytes one evaluation, or
//! one blue process, holds, against the bound `max_alloc_bytes` sets
//! (`crate::memory`). [`charged_to`] makes an account the one running on this
//! thread for a scope, so the tree-walker's root, each process slice and each
//! message in transit are charged to whoever owns them.

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

/// One thread's counters, and the account its allocations are charged to.
///
/// One `const`-initialised thread-local: no lazy init, so no allocation from
/// inside the allocator, and no destructor to run during thread teardown. An
/// allocation made while the thread's locals are torn down is served and not
/// counted (`try_with`).
struct Tally {
    count: Cell<u64>,
    bytes: Cell<u64>,
    freed: Cell<u64>,
    held: Cell<i64>,
    bound: Cell<i64>,
    exhausted: Cell<bool>,
    wire: Cell<*const AtomicBool>,
}

/// The account a [`charged_to`] scope set aside, put back when it ends.
#[derive(Clone, Copy)]
struct Charge {
    held: i64,
    bound: i64,
    exhausted: bool,
    wire: *const AtomicBool,
}

impl Tally {
    const fn new() -> Self {
        Self {
            count: Cell::new(0),
            bytes: Cell::new(0),
            freed: Cell::new(0),
            held: Cell::new(0),
            bound: Cell::new(i64::MAX),
            exhausted: Cell::new(false),
            wire: Cell::new(std::ptr::null()),
        }
    }

    fn charge(&self, bytes: usize) {
        self.count.set(self.count.get() + 1);
        self.bytes.set(self.bytes.get() + bytes as u64);
        self.hold(i64::try_from(bytes).unwrap_or(i64::MAX));
    }

    fn credit(&self, bytes: usize) {
        self.freed.set(self.freed.get() + bytes as u64);
        self.hold(-i64::try_from(bytes).unwrap_or(i64::MAX));
    }

    fn hold(&self, bytes: i64) {
        let held = self.held.get().saturating_add(bytes);
        self.held.set(held);
        if held > self.bound.get() && !self.exhausted.get() {
            self.trip();
        }
    }

    /// Mark the account exhausted and store `true` through its wire.
    ///
    /// The wire is only ever a pointer [`charged_to`] took from a reference
    /// that outlives its scope, set on entry and put back on every way out of
    /// the scope (the guard's `Drop`), and the thread-local is read by its own
    /// thread only: while the pointer is set, what it points at is alive.
    fn trip(&self) {
        self.exhausted.set(true);
        let wire = self.wire.get();
        if !wire.is_null() {
            unsafe { (*wire).store(true, Ordering::Relaxed) };
        }
    }

    fn swap(&self, next: Charge) -> Charge {
        let outer = Charge {
            held: self.held.replace(next.held),
            bound: self.bound.replace(next.bound),
            exhausted: self.exhausted.replace(next.exhausted),
            wire: self.wire.replace(next.wire),
        };
        if next.held > next.bound && !next.exhausted {
            self.trip();
        }
        outer
    }
}

thread_local! {
    static TALLY: Tally = const { Tally::new() };
}

/// This thread's running totals, or `None` when [`Counting`] is not the global
/// allocator of this binary.
#[must_use]
pub fn allocations() -> Option<Allocations> {
    if !INSTALLED.load(Ordering::Relaxed) {
        return None;
    }
    TALLY
        .try_with(|t| Allocations {
            count: t.count.get(),
            bytes: t.bytes.get(),
            freed: t.freed.get(),
        })
        .ok()
}

fn charge(bytes: usize) {
    let _ = TALLY.try_with(|t| t.charge(bytes));
}

fn credit(bytes: usize) {
    let _ = TALLY.try_with(|t| t.credit(bytes));
}

/// The live bytes one account holds, and the bound it is held to.
///
/// An evaluation is charged what its own thread allocates and frees while the
/// account is [`charged_to`]: `held` is the net, so a value built and dropped
/// costs nothing once dropped, and a value still reachable when the scope ends
/// stays on the account. One account per evaluation and one per blue process
/// (a process is share-nothing, so what it holds is its own).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Account {
    /// Bytes allocated and not returned while charged. Negative when the
    /// account returned more than it took (it freed what was there before).
    pub held: i64,
    /// The most `held` may reach; `None` is unbounded.
    pub bound: Option<u64>,
    /// `held` passed `bound` while charged. Stays set.
    pub exhausted: bool,
}

impl Account {
    /// An account holding nothing, held to `bound`.
    #[must_use]
    pub const fn new(bound: Option<u64>) -> Self {
        Self {
            held: 0,
            bound,
            exhausted: false,
        }
    }
}

struct Charged<'a> {
    account: &'a mut Account,
    outer: Charge,
}

impl Drop for Charged<'_> {
    fn drop(&mut self) {
        let _ = TALLY.try_with(|t| {
            let inner = t.swap(self.outer);
            self.account.held = inner.held;
            self.account.exhausted = inner.exhausted;
        });
    }
}

/// Run `f` with every allocation and free this thread makes charged to
/// `account` instead of the account running now, which is set aside and put
/// back unchanged when `f` returns or unwinds.
///
/// The moment `held` passes `bound` the account is exhausted, and `wire` (an
/// interpreter's interrupt flag, `Interpreter::set_interrupt`) is set, so the
/// tree-walker's next step halts. That is the only refusal the allocator
/// makes: it never fails an allocation, since a failed allocation aborts the
/// process. With [`Counting`] not installed nothing is charged and nothing is
/// refused.
pub fn charged_to<R>(account: &mut Account, wire: Option<&AtomicBool>, f: impl FnOnce() -> R) -> R {
    let next = Charge {
        held: account.held,
        bound: account
            .bound
            .map_or(i64::MAX, |b| i64::try_from(b).unwrap_or(i64::MAX)),
        exhausted: account.exhausted,
        wire: wire.map_or(std::ptr::null(), |w| w as *const AtomicBool),
    };
    let Ok(outer) = TALLY.try_with(|t| t.swap(next)) else {
        return f();
    };
    let _scope = Charged { account, outer };
    f()
}

/// Run `f` charged to no evaluation, and answer the bytes it left live.
#[must_use]
pub fn apart<R>(f: impl FnOnce() -> R) -> (R, i64) {
    let mut account = Account::new(None);
    let value = charged_to(&mut account, None, f);
    (value, account.held)
}

/// Charge `bytes` to the account running now, as if it had allocated them.
pub fn charge_held(bytes: i64) {
    let _ = TALLY.try_with(|t| t.hold(bytes));
}

/// The bound of the account running now: `None` when it has none, or when
/// [`Counting`] is not installed and no bound could be enforced.
#[must_use]
pub fn bound() -> Option<u64> {
    if !INSTALLED.load(Ordering::Relaxed) {
        return None;
    }
    TALLY
        .try_with(|t| t.bound.get())
        .ok()
        .filter(|b| *b != i64::MAX)
        .and_then(|b| u64::try_from(b).ok())
}

/// Whether the account running now has passed its bound.
#[must_use]
pub fn exhausted() -> bool {
    TALLY.try_with(|t| t.exhausted.get()).unwrap_or(false)
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
