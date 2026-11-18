//! The host seam: a native blue image as a process on the machine blue runs
//! on (kiban's `host64`). The program crate is the same `#![no_std]`,
//! `#![forbid(unsafe_code)]` crate a board image links; the board is
//! `host_io`'s, and a fault exits non-zero as the interpreter does on a
//! raised error.

#[path = "../host_io.rs"]
#[allow(dead_code)]
mod host_io;

fn main() {
    if !host_io::run(|host| {
        program::main(host);
        true
    }) {
        std::process::exit(1)
    }
}
