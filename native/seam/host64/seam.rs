//! The host seam: a native blue image as a process on the machine blue runs
//! on (kiban's `host64`). The program crate is the same `#![no_std]`,
//! `#![forbid(unsafe_code)]` crate a board image links; here its UART is
//! standard output, held to the bytes kiban's model prints (printable ASCII
//! and newline), and its finisher is the end of the run, as in the model.
//! A fault unwinds, so what was printed before it is flushed, and the
//! process exits non-zero as the interpreter does on a raised error. The
//! program runs on a thread whose stack holds the board's declared
//! recursion depth.

use kiban_io::Io;
use std::io::Write;

const UART0: u32 = 0x1000_0000;
const FINISHER: u32 = 0x0010_0000;
const STACK: usize = 1 << 30;

struct Host {
    out: std::io::BufWriter<std::io::Stdout>,
}

impl Io for Host {
    fn write8(&mut self, addr: u32, value: u32) {
        if addr == FINISHER {
            return;
        }
        if addr != UART0 {
            kiban_io::fault()
        }
        let Ok(byte) = u8::try_from(value) else {
            kiban_io::fault()
        };
        if byte != b'\n' && !(32..127).contains(&byte) {
            kiban_io::fault()
        }
        if self.out.write_all(&[byte]).is_err() {
            kiban_io::fault()
        }
    }

    fn write32(&mut self, addr: u32, value: u32) {
        self.write8(addr, value)
    }
}

fn main() {
    let ran = std::thread::Builder::new()
        .stack_size(STACK)
        .spawn(|| {
            let mut host = Host {
                out: std::io::BufWriter::with_capacity(1 << 16, std::io::stdout()),
            };
            program::main(&mut host);
            host.out.flush().is_ok()
        })
        .map(|t| t.join());
    if !matches!(ran, Ok(Ok(true))) {
        std::process::exit(1)
    }
}
