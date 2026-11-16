//! The definition seam (tier T3): one compiled definition as a process on
//! the host board. Each argument is one Int in decimal; the definition's
//! result is printed on its own line after anything it printed. A fault
//! exits 1 and an argument that is not an Int exits 2, so the caller runs
//! the definition in the interpreter instead.

#[path = "../host_io.rs"]
mod host_io;

use std::io::Write;

fn main() {
    let parsed: Option<Vec<i64>> = std::env::args().skip(1).map(|a| a.parse().ok()).collect();
    let Some(args) = parsed else {
        std::process::exit(2)
    };
    if !host_io::run(move |host| {
        let value = program::entry(host, &kiban_io::Args(&args));
        writeln!(host.out, "{value}").is_ok()
    }) {
        std::process::exit(1)
    }
}
