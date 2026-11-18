//! The definition seam as a library (tier T3, in process): one compiled
//! definition the native tier loads once and calls as a function. A shallow
//! slice (no function recurses but in its tail, `program::shallow`) runs on
//! the caller's stack; one that recurses runs on a thread with the board's. It exports
//! `blue_def_entry(args, len, out)`: the definition on `len` Int arguments,
//! its result written to `out`. It answers 0 with the result, 1 when the
//! definition faulted or printed (the interpreter then runs the call, so
//! what it prints is printed once, in order), and 2 for a null pointer.

#![deny(unsafe_code)]

#[path = "../host_io.rs"]
#[allow(dead_code)]
mod host_io;

struct Quiet {
    printed: bool,
}

impl kiban_io::Io for Quiet {
    fn write8(&mut self, _addr: u32, _value: u32) {
        self.printed = true;
    }

    fn write32(&mut self, _addr: u32, _value: u32) {
        self.printed = true;
    }
}

fn quietly<T: Send + 'static>(run: impl FnOnce() -> Option<T> + Send + 'static) -> Option<T> {
    static SILENT: std::sync::Once = std::sync::Once::new();
    SILENT.call_once(|| std::panic::set_hook(Box::new(|_| {})));
    if program::shallow() {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(run))
            .ok()
            .flatten()
    } else {
        host_io::on_stack(run).flatten()
    }
}

fn answer(args: Vec<i64>) -> Option<i64> {
    quietly(move || {
        let mut io = Quiet { printed: false };
        let value = program::entry(&mut io, &kiban_io::Args(&args));
        (!io.printed).then_some(value)
    })
}

fn answer_tokens(input: String) -> Option<String> {
    quietly(move || {
        let args = input
            .split(' ')
            .filter(|t| !t.is_empty())
            .map(host_io::decode)
            .collect::<Option<Vec<kiban_heap::Value>>>()?;
        let mut io = Quiet { printed: false };
        let value = program::call(&mut io, &args);
        (!io.printed).then(|| host_io::encode(&value))
    })
}

#[no_mangle]
#[allow(unsafe_code)]
pub extern "C" fn blue_def_entry(args: *const i64, len: usize, out: *mut i64) -> i32 {
    if args.is_null() || out.is_null() {
        return 2;
    }
    let args = unsafe { std::slice::from_raw_parts(args, len) }.to_vec();
    match answer(args) {
        Some(value) => {
            unsafe { out.write(value) };
            0
        }
        None => 1,
    }
}

/// The definition on values of any type the seam carries: `input` is their
/// tokens (`host_io::decode`) separated by spaces, and the answer's token is
/// written to `out`, its length to `out_len`. Answers 0 with the result, 1
/// when the definition faulted or printed or an argument is no token, 2 for
/// a null pointer or input that is not UTF-8, and 3 when `cap` is too small,
/// `out_len` then holding the length needed.
#[no_mangle]
#[allow(unsafe_code)]
pub extern "C" fn blue_def_call(
    input: *const u8,
    len: usize,
    out: *mut u8,
    cap: usize,
    out_len: *mut usize,
) -> i32 {
    if input.is_null() || out.is_null() || out_len.is_null() {
        return 2;
    }
    let bytes = unsafe { std::slice::from_raw_parts(input, len) };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return 2;
    };
    let Some(token) = answer_tokens(text.to_string()) else {
        return 1;
    };
    unsafe { out_len.write(token.len()) };
    if token.len() > cap {
        return 3;
    }
    unsafe { std::ptr::copy_nonoverlapping(token.as_ptr(), out, token.len()) };
    0
}
