//! kiban_io: the one interface between an emitted blue program and a board.
//!
//! An emitted program is compiled as its own crate under
//! `#![forbid(unsafe_code)]` (BLUE-NATIVE.md, Review §2), so it cannot touch a
//! register. It reaches the board only through this trait, which the board's
//! seam implements; every emitted function takes the board as `io`. This
//! crate is safe too, so the seam crate is the only place in an image where
//! `unsafe` compiles.
//!
//! A fault (an overflow, a value too wide for its register) panics; the
//! seam's panic handler is the board's `on_fault`, and it formats nothing.
#![no_std]
#![forbid(unsafe_code)]

/// A board's registers, as the program sees them.
pub trait Io {
    /// Store the low 8 bits of `value` at `addr`. A value wider than 8 bits
    /// is a fault, not a truncation.
    fn write8(&mut self, addr: u32, value: u32);
    /// Store `value` at `addr`, 32 bits.
    fn write32(&mut self, addr: u32, value: u32);
}

/// The value of a checked operation, or a fault. Integer overflow is an
/// error by default (the operator's decision, BLUE-NATIVE.md status line),
/// so every `+`, `-`, `*` and `%` an emitted program performs arrives here as
/// `checked_*`, in the board's word; wrapping is a separate word a program
/// asks for by name. A `const fn`, so a top-level binding computed from
/// constants is a Rust constant and its overflow a build error.
#[inline(always)]
pub const fn checked<T: Copy>(value: Option<T>) -> T {
    match value {
        Some(v) => v,
        None => fault(),
    }
}

/// A word as a register value: a value that does not fit 32 bits (a
/// negative one on the 64-bit host word) is a fault, never a truncation.
#[inline(always)]
pub fn reg<T: TryInto<u32>>(value: T) -> u32 {
    match value.try_into() {
        Ok(v) => v,
        Err(_) => fault(),
    }
}

/// `floor(a / b)` in the signed host word: the quotient rounded toward
/// negative infinity, as the interpreter's `floor` of its `/`. A zero
/// divisor and `i64::MIN / -1` are faults.
#[inline(always)]
pub const fn floor_div(a: i64, b: i64) -> i64 {
    let q = checked(a.checked_div(b));
    if a % b != 0 && ((a < 0) != (b < 0)) {
        q - 1
    } else {
        q
    }
}

/// One more frame of a recursive definition: the depth it runs at, or a
/// fault past the board's declared bound, as the interpreter refuses a call
/// past its depth.
#[inline(always)]
pub fn deeper(depth: u32, bound: u32) -> u32 {
    if depth >= bound {
        fault()
    }
    depth + 1
}

/// `n` in decimal to the UART at `uart`, a minus sign first when it is
/// negative, byte by byte through the board's own store; answers `n`. The
/// digits are built in a fixed buffer, so nothing is formatted or allocated.
pub fn put_int<I: Io, W: Copy + Into<i64>>(io: &mut I, uart: u32, n: W) -> W {
    let v: i64 = n.into();
    let mut digits = [0u8; 20];
    let mut len = 0;
    let mut m = v.unsigned_abs();
    loop {
        digits[len] = b'0' + (m % 10) as u8;
        len += 1;
        m /= 10;
        if m == 0 {
            break;
        }
    }
    if v < 0 {
        io.write8(uart, u32::from(b'-'));
    }
    while len > 0 {
        len -= 1;
        io.write8(uart, u32::from(digits[len]));
    }
    n
}

/// Stop at the board's fault handler.
#[inline(never)]
#[cold]
pub const fn fault() -> ! {
    panic!()
}
