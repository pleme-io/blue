//! The QEMU `virt` riscv32 seam: startup, the one unsafe module of a native
//! blue image on this board, and its fault handler.
//!
//! Hand-written at N0 (BLUE-NATIVE.md §7): the startup code, the MMIO stores
//! and the fault path, and nothing else. The program is a separate crate
//! compiled under `#![forbid(unsafe_code)]` and reaches the registers only
//! through `kiban_io::Io`, which this crate implements with volatile stores.
//! The addresses are the board spec's (native/bidamas/kiban, kb_qemu_virt32);
//! the finisher is the SiFive test device QEMU's virt machine maps.
#![no_std]
#![no_main]

use kiban_io::Io;

const FINISHER: usize = 0x0010_0000;
const FINISHER_PASS: u32 = 0x5555;
/// `(1 << 16) | 0x3333`: QEMU exits with status 1.
const FINISHER_FAIL: u32 = 0x0001_3333;

// Entry: a stack at the top of RAM (the linker script's `__stack_top`, from the
// board spec's memory), then Rust. RAM is loaded by QEMU from the ELF and
// `.bss` starts zeroed on a fresh machine, so there is no copy or zero loop.
core::arch::global_asm!(
    ".section .text.start",
    ".globl _start",
    "_start:",
    "  la sp, __stack_top",
    "  call {entry}",
    "1: j 1b",
    entry = sym start,
);

struct Board;

impl Io for Board {
    fn write8(&mut self, addr: u32, value: u32) {
        let Ok(byte) = u8::try_from(value) else {
            kiban_io::fault()
        };
        // SAFETY: `addr` is a board register named by an emitted program; the
        // store has no effect on Rust-visible memory.
        unsafe { core::ptr::write_volatile(addr as usize as *mut u8, byte) }
    }

    fn write32(&mut self, addr: u32, value: u32) {
        // SAFETY: as above.
        unsafe { core::ptr::write_volatile(addr as usize as *mut u32, value) }
    }
}

fn finish(code: u32) -> ! {
    // SAFETY: the finisher register; QEMU stops the machine on this store.
    unsafe { core::ptr::write_volatile(FINISHER as *mut u32, code) }
    loop {}
}

extern "C" fn start() -> ! {
    program::main(&mut Board);
    finish(FINISHER_PASS)
}

/// `on_fault`: no message, no formatting, a failing exit.
#[panic_handler]
fn on_fault(_: &core::panic::PanicInfo<'_>) -> ! {
    finish(FINISHER_FAIL)
}
