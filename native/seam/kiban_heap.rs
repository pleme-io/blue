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

use alloc::collections::BTreeMap;
use alloc::rc::Rc;
use alloc::string::String;
use alloc::vec::Vec;
use core::fmt::Write;

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

/// No fields yet: where [`field_push`] starts a record that holds a string.
#[must_use]
pub fn no_fields() -> Vec<Value> {
    Vec::new()
}

/// `vs` with `v` at its end: a record that holds a string, built one field
/// at a time in declared order.
#[must_use]
pub fn field_push(mut vs: Vec<Value>, v: Value) -> Vec<Value> {
    vs.push(v);
    vs
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

/// A refcounted list of records, each the record's own struct.
pub type Items<T> = Rc<Vec<T>>;

/// An empty list of records with room for `n`.
#[must_use]
pub fn items_with<T>(n: usize) -> Vec<T> {
    Vec::with_capacity(n)
}

/// A built list of records, now refcounted.
#[must_use]
pub fn items_of<T>(v: Vec<T>) -> Items<T> {
    Rc::new(v)
}

/// `a` then `b`: in place when `a` is held nowhere else.
#[must_use]
pub fn items_append<T: Clone>(mut a: Items<T>, b: &Items<T>) -> Items<T> {
    Rc::make_mut(&mut a).extend_from_slice(b);
    a
}

/// `a` with `v` at its end: in place when `a` is held nowhere else.
#[must_use]
pub fn items_push<T: Clone>(mut a: Items<T>, v: T) -> Items<T> {
    Rc::make_mut(&mut a).push(v);
    a
}

/// The record at `i`, a clone, or a fault past either end.
#[must_use]
pub fn items_nth<T: Clone>(l: &Items<T>, i: i64) -> T {
    match usize::try_from(i).ok().and_then(|i| l.get(i)) {
        Some(v) => v.clone(),
        None => kiban_io::fault(),
    }
}

/// How many records `l` holds.
#[must_use]
pub fn items_count<T>(l: &Items<T>) -> i64 {
    i64::try_from(l.len()).unwrap_or_else(|_| kiban_io::fault())
}

/// The list of records a seam value is, each element read by `read`, or a
/// fault when it is not a list of records.
#[must_use]
pub fn items_in<T>(v: &Value, read: fn(&Value) -> T) -> Items<T> {
    match v {
        Value::Items(vs) => Rc::new(vs.iter().map(read).collect()),
        _ => kiban_io::fault(),
    }
}

/// A list of records as a seam value, each element written by `write`.
#[must_use]
pub fn items_out<T>(l: &Items<T>, write: fn(&T) -> Value) -> Value {
    Value::Items(l.iter().map(write).collect())
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

/// A list only tested for membership, held as a set (W2.1): built once,
/// before the loop that tests it, so each test is a lookup, not a scan.
pub type Set = alloc::collections::BTreeSet<i64>;

/// `l` as a set.
#[must_use]
pub fn set_of(l: &List) -> Set {
    l.iter().copied().collect()
}

/// `member?(v, l)` on the set `l` became.
#[must_use]
pub fn set_has(s: &Set, v: i64) -> bool {
    s.contains(&v)
}

/// `member?(v, l)`: whether `l` holds `v`, a scan.
#[must_use]
pub fn rc_member(l: &List, v: i64) -> bool {
    l.contains(&v)
}

/// A list only read at its front and passed on as its `rest` (W2.1): the
/// list and where its front is, so `rest` moves the front and copies
/// nothing.
#[derive(Clone, Debug)]
pub struct Queue {
    l: List,
    at: usize,
}

/// `l` as a queue whose front is its first word.
#[must_use]
pub fn queue_of(l: List) -> Queue {
    Queue { l, at: 0 }
}

/// `first(q)`, or a fault when it is empty, as the interpreter raises.
#[must_use]
pub fn q_first(q: &Queue) -> i64 {
    match q.l.get(q.at) {
        Some(v) => *v,
        None => kiban_io::fault(),
    }
}

/// `rest(q)`: the front moved one on, or a fault when it is empty.
#[must_use]
pub fn q_rest(q: &Queue) -> Queue {
    if q.at >= q.l.len() {
        kiban_io::fault()
    }
    Queue {
        l: q.l.clone(),
        at: q.at + 1,
    }
}

/// `count(q)`: the words from the front on.
#[must_use]
pub fn q_count(q: &Queue) -> i64 {
    i64::try_from(q.l.len() - q.at).unwrap_or_else(|_| kiban_io::fault())
}

/// A refcounted string: immutable, so a copy is a count.
pub type Str = Rc<str>;

/// A string from its text.
#[must_use]
pub fn text(s: &str) -> Str {
    Rc::from(s)
}

/// A refcounted map of strings to board words, ordered by key as the
/// interpreter orders a map's entries.
pub type Map = Rc<BTreeMap<Str, i64>>;

/// `{}`: the empty map.
#[must_use]
pub fn map_empty() -> Map {
    Rc::new(BTreeMap::new())
}

/// `assoc(m, k, v)`: `m` with `k` set to `v`, in place when nothing else
/// holds `m`.
#[must_use]
pub fn map_put(mut m: Map, k: Str, v: i64) -> Map {
    Rc::make_mut(&mut m).insert(k, v);
    m
}

/// `get(m, k)`: the word at `k`, or a fault when `m` has none, so the call
/// runs in the interpreter, which answers nil.
#[must_use]
pub fn map_get(m: &Map, k: &Str) -> i64 {
    match m.get(k) {
        Some(v) => *v,
        None => kiban_io::fault(),
    }
}

/// `count(m)`: its entries.
#[must_use]
pub fn map_count(m: &Map) -> i64 {
    i64::try_from(m.len()).unwrap_or_else(|_| kiban_io::fault())
}

/// A value as `concat` and interpolation write it: a string as it is, an Int
/// in decimal, a Bool as `true` or `false`, as the interpreter writes them.
pub trait Piece {
    fn piece(&self, out: &mut String);
}

impl Piece for Str {
    fn piece(&self, out: &mut String) {
        out.push_str(self);
    }
}

impl Piece for i64 {
    fn piece(&self, out: &mut String) {
        let _ = write!(out, "{self}");
    }
}

impl Piece for bool {
    fn piece(&self, out: &mut String) {
        out.push_str(if *self { "true" } else { "false" });
    }
}

/// `concat(a, b)`: a new string, `a` then `b`.
#[must_use]
pub fn cat<A: Piece, B: Piece>(a: &A, b: &B) -> Str {
    let mut out = String::new();
    a.piece(&mut out);
    b.piece(&mut out);
    Rc::from(out)
}

/// `length(s)`: its characters, as the interpreter counts them.
#[must_use]
pub fn text_len(s: &Str) -> i64 {
    i64::try_from(s.chars().count()).unwrap_or_else(|_| kiban_io::fault())
}

/// A value crossing the definition seam: what a definition that takes or
/// answers a string is called with and answers.
#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Int(i64),
    Bool(bool),
    Float(f64),
    Str(Str),
    List(List),
    Record(List),
    Fields(Vec<Value>),
    Map(Map),
    Items(Vec<Value>),
}

impl Value {
    /// The Int this is, or a fault: an argument of another type is refused.
    #[must_use]
    pub fn int(&self) -> i64 {
        match self {
            Self::Int(n) => *n,
            _ => kiban_io::fault(),
        }
    }

    /// The Bool this is, or a fault.
    #[must_use]
    pub fn bool(&self) -> bool {
        match self {
            Self::Bool(b) => *b,
            _ => kiban_io::fault(),
        }
    }

    /// The Float this is, or a fault.
    #[must_use]
    pub fn float(&self) -> f64 {
        match self {
            Self::Float(x) => *x,
            _ => kiban_io::fault(),
        }
    }

    /// The list of Ints this is, or a fault.
    #[must_use]
    pub fn list(&self) -> List {
        match self {
            Self::List(l) => l.clone(),
            _ => kiban_io::fault(),
        }
    }

    /// A record's fields in declared order, or a fault.
    #[must_use]
    pub fn fields(&self) -> List {
        match self {
            Self::Record(l) => l.clone(),
            _ => kiban_io::fault(),
        }
    }

    /// The `i`th field of a record that holds a string, or a fault.
    #[must_use]
    pub fn field(&self, i: usize) -> &Value {
        match self {
            Self::Fields(vs) => vs.get(i).unwrap_or_else(|| kiban_io::fault()),
            _ => kiban_io::fault(),
        }
    }

    /// The map of strings to Ints this is, or a fault.
    #[must_use]
    pub fn map(&self) -> Map {
        match self {
            Self::Map(m) => m.clone(),
            _ => kiban_io::fault(),
        }
    }

    /// The string this is, or a fault.
    #[must_use]
    pub fn str(&self) -> Str {
        match self {
            Self::Str(s) => s.clone(),
            _ => kiban_io::fault(),
        }
    }
}

/// The arguments of a valued call.
pub type Values = [Value];

/// The `i`th argument, or a fault.
#[must_use]
pub fn arg(args: &[Value], i: u32) -> &Value {
    match args.get(i as usize) {
        Some(v) => v,
        None => kiban_io::fault(),
    }
}

/// Exactly `n` arguments, or a fault, as the interpreter refuses a call of
/// the wrong arity.
pub fn need(args: &[Value], n: u32) {
    if args.len() != n as usize {
        kiban_io::fault()
    }
}
