//! The definition seam (tier T3): one compiled definition as a process on
//! the host board. Each argument is one value's token (`host_io::decode`:
//! `i42`, `b1`, `f<bits>`, `s<hex>`, or a bare decimal Int); the
//! definition's answer is printed as its token on its own line after
//! anything it printed. A fault exits 1 and an argument that is no token
//! exits 2, so the caller runs the definition in the interpreter instead.

#[path = "../host_io.rs"]
mod host_io;

use std::io::Write;

fn main() {
    let tokens: Vec<String> = std::env::args().skip(1).collect();
    if tokens.iter().any(|t| host_io::decode(t).is_none()) {
        std::process::exit(2)
    }
    if !host_io::run(move |host| {
        let args: Vec<kiban_heap::Value> = tokens.iter().filter_map(|t| host_io::decode(t)).collect();
        let value = program::call(host, &args);
        writeln!(host.out, "{}", host_io::encode(&value)).is_ok()
    }) {
        std::process::exit(1)
    }
}
