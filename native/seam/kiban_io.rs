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
/// so every `+`, `-` and `*` an emitted program performs arrives here as
/// `checked_*`; wrapping is a separate word a program asks for by name.
#[inline(always)]
pub fn checked(value: Option<u32>) -> u32 {
    match value {
        Some(v) => v,
        None => fault(),
    }
}

/// Stop at the board's fault handler.
#[inline(never)]
#[cold]
pub fn fault() -> ! {
    panic!()
}
