//! kiban_heap: the heap an emitted blue program uses on a board that has
//! one (the host). Two reclamation strategies, chosen per definition by the
//! program (`kiban::reclaim`), live side by side:
//!
//! - **refcount** ([`List`]): a list is an `Rc<Vec<i64>>`. Appending to a
//!   list nothing else holds extends it in place (`Rc::make_mut`); a shared
//!   one is copied first. A list is freed when its last holder drops it.
//! - **region** ([`Region`], [`Span`]): a list is a `Copy` span of one
//!   region's cells. Appending to the newest list extends it in place; any
//!   other is copied to the end. Nothing is freed until the region is,
//!   which is when the definition that opened it returns.
//!
//! A list crosses between the two by copy ([`Region::from_rc`],
//! [`Region::to_rc`]), so neither strategy ever holds the other's memory.
//! Safe code only; a bad index is a fault, as in `kiban_io`.
#![no_std]
#![forbid(unsafe_code)]

extern crate alloc;

use alloc::rc::Rc;
use alloc::vec::Vec;

/// A refcounted list of board words.
pub type List = Rc<Vec<i64>>;

/// An empty list's storage with room for `n` words.
#[must_use]
pub fn vec_with(n: usize) -> Vec<i64> {
    Vec::with_capacity(n)
}

/// A built list, now refcounted.
#[must_use]
pub fn rc_of(v: Vec<i64>) -> List {
    Rc::new(v)
}

/// `a` then `b`: in place when `a` is held nowhere else.
#[must_use]
pub fn rc_append(mut a: List, b: &List) -> List {
    Rc::make_mut(&mut a).extend_from_slice(b);
    a
}

/// `a` with `v` at its end: in place when `a` is held nowhere else, so a
/// list built by appending one word at a time costs no copy per word.
#[must_use]
pub fn rc_push(mut a: List, v: i64) -> List {
    Rc::make_mut(&mut a).push(v);
    a
}

/// The word at `i`, or a fault past either end.
#[must_use]
pub fn rc_nth(l: &List, i: i64) -> i64 {
    match usize::try_from(i).ok().and_then(|i| l.get(i)) {
        Some(v) => *v,
        None => kiban_io::fault(),
    }
}

/// How many words `l` holds.
#[must_use]
pub fn rc_count(l: &List) -> i64 {
    i64::try_from(l.len()).unwrap_or_else(|_| kiban_io::fault())
}

/// A list in a region: where its words start and how many there are.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Span {
    start: usize,
    len: usize,
}

/// The cells every list of one region lives in, freed together.
#[derive(Debug, Default)]
pub struct Region {
    cells: Vec<i64>,
}

impl Region {
    /// An empty region.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Where the next list starts.
    #[must_use]
    pub fn begin(&self) -> usize {
        self.cells.len()
    }

    /// One more word of the list being built.
    pub fn push(&mut self, v: i64) {
        self.cells.push(v);
    }

    /// The list built since `start`.
    #[must_use]
    pub fn end(&self, start: usize) -> Span {
        Span {
            start,
            len: self.cells.len() - start,
        }
    }

    /// `a` then `b`: no copy when `b` already follows `a` (a list built
    /// right after the one it is appended to), in place when `a` is the
    /// newest list, else copied to the end.
    pub fn append(&mut self, a: Span, b: Span) -> Span {
        if a.start + a.len == b.start {
            return Span {
                start: a.start,
                len: a.len + b.len,
            };
        }
        let start = if a.start + a.len == self.cells.len() {
            a.start
        } else {
            let s = self.cells.len();
            self.cells.extend_from_within(a.start..a.start + a.len);
            s
        };
        self.cells.extend_from_within(b.start..b.start + b.len);
        self.end(start)
    }

    /// `a` with `v` at its end: in place when `a` is the newest list,
    /// else `a` is copied to the end first.
    pub fn push_onto(&mut self, a: Span, v: i64) -> Span {
        let start = if a.start + a.len == self.cells.len() {
            a.start
        } else {
            let s = self.cells.len();
            self.cells.extend_from_within(a.start..a.start + a.len);
            s
        };
        self.cells.push(v);
        self.end(start)
    }

    /// The word at `i` of `l`, or a fault past either end.
    #[must_use]
    pub fn nth(&self, l: Span, i: i64) -> i64 {
        match usize::try_from(i) {
            Ok(i) if i < l.len => self.cells[l.start + i],
            _ => kiban_io::fault(),
        }
    }

    /// How many words `l` holds.
    #[must_use]
    pub fn count(l: Span) -> i64 {
        i64::try_from(l.len).unwrap_or_else(|_| kiban_io::fault())
    }

    /// A refcounted list copied into this region.
    pub fn from_rc(&mut self, l: &List) -> Span {
        let start = self.begin();
        self.cells.extend_from_slice(l);
        self.end(start)
    }

    /// A list of this region copied out, refcounted, to outlive it.
    #[must_use]
    pub fn to_rc(&self, l: Span) -> List {
        Rc::new(self.cells[l.start..l.start + l.len].to_vec())
    }
}
