//! A kernel file descriptor is a host handle like a socket: it counts in
//! `blue_lang_runtime::handles::open` from the word that opens it until
//! `fd_close` closes it or its run ends, so `closes_at(:end)` covers it
//! (I2 of docs/PURE-BLUE.md). The kernel surface runs on Linux only.

#![cfg(all(target_os = "linux", feature = "kernel"))]

fn run(src: &str) {
    blue_lang_runtime::run(src).unwrap_or_else(|e| panic!("{src}\n{e}"));
}

#[test]
fn a_kernel_fd_counts_until_closed_or_its_run_ends() {
    let at = blue_lang_runtime::handles::open();
    run("f = fd_open(\"/dev/null\")\nfd_close(f)\ntrue");
    assert_eq!(blue_lang_runtime::handles::open(), at, "closed by hand");
    run("f = fd_open(\"/dev/null\")\nfd_number(f) != nil");
    assert_eq!(blue_lang_runtime::handles::open(), at, "left open");
}

#[test]
fn an_open_kernel_fd_is_counted_while_it_is_held() {
    let at = blue_lang_runtime::handles::open();
    let held = blue_lang_kernel::open_read("/dev/null").expect("opens /dev/null");
    assert_eq!(blue_lang_runtime::handles::open(), at + 1);
    held.close();
    held.close();
    assert_eq!(blue_lang_runtime::handles::open(), at);
}
