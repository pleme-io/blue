//! blue as a WebAssembly module.
//!
//! The whole blue pipeline — parse, check, erase, run — compiled to
//! `wasm32-unknown-unknown` with no host imports at all. That is what makes it
//! usable as an *embedded* language: a browser, an edge worker, a plugin host,
//! or a sandbox inside another blue program.
//!
//! ## No WASI, deliberately
//!
//! This module imports **nothing**. Not a clock, not a random source, not a
//! file descriptor. A blue program running here cannot reach outside, because
//! there is no outside to reach: capability restriction is the absence of an
//! import, not a policy consulted at call time.
//!
//! That is the same argument `waku`'s `Reach` makes at the language level, and
//! it lands here for free — which is the point §V.17 makes about blue's WASM
//! story being cheaper than a general sandbox. It also means no `println`: a
//! program's *value* comes back, its output does not.
//!
//! ## The ABI
//!
//! Linear-memory in, tagged integer out. Four exports:
//!
//! ```text
//! alloc(len: usize) -> *mut u8      reserve `len` bytes for source
//! dealloc(ptr, len)                 release them
//! blue_eval(ptr, len) -> i64        run; see the tag encoding below
//! blue_last_error_len() -> usize    length of the pending error, if any
//! blue_last_error(ptr)              copy the pending error into `ptr`
//! ```
//!
//! `blue_eval` returns a **tagged** result rather than a bare integer, because
//! a bare integer cannot distinguish `0` from failure. The tag is the low two
//! bits:
//!
//! - `(v << 2) | 0` — an integer result `v`
//! - `1` — a non-integer result (the program ran; its value is not an int)
//! - `2` — an error; fetch it with `blue_last_error*`
//!
//! Shifting loses the top two bits of a 64-bit result. That is a real limit and
//! it is stated rather than hidden: values outside ±2^61 report as
//! non-integer rather than silently truncating. A truncating ABI is how a
//! sandbox returns a plausible wrong number.

#![allow(clippy::missing_safety_doc)]

use std::cell::RefCell;

thread_local! {
    /// The most recent error, held so the host can fetch it after a `2` tag.
    /// Thread-local rather than a global `static mut`: a wasm module may be
    /// instantiated more than once in a host that uses threads, and a shared
    /// slot would let one instance read another's error.
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
}

/// Tag values. Exposed so a host binding does not hard-code them.
pub const TAG_INT: i64 = 0;
pub const TAG_NON_INT: i64 = 1;
pub const TAG_ERROR: i64 = 2;

/// The widest integer `blue_eval` can return without losing information.
pub const MAX_TAGGED: i64 = i64::MAX >> 2;
pub const MIN_TAGGED: i64 = i64::MIN >> 2;

/// Reserve `len` bytes the host can write source into.
#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let mut buf = Vec::<u8>::with_capacity(len);
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

#[no_mangle]
pub unsafe extern "C" fn dealloc(ptr: *mut u8, len: usize) {
    if !ptr.is_null() && len > 0 {
        drop(Vec::from_raw_parts(ptr, 0, len));
    }
}

/// Run blue source. See the module docs for the tag encoding.
#[no_mangle]
pub unsafe extern "C" fn blue_eval(ptr: *const u8, len: usize) -> i64 {
    let bytes = std::slice::from_raw_parts(ptr, len);
    let src = match std::str::from_utf8(bytes) {
        Ok(s) => s,
        Err(e) => return fail(&e.to_string()),
    };
    eval_tagged(src)
}

/// The tagging logic, separated from the pointer handling so it is testable on
/// the host as well as in wasm.
pub fn eval_tagged(src: &str) -> i64 {
    match blue_lang_runtime::run(src) {
        Err(e) => fail(&e.to_string()),
        Ok(run) => match run.value {
            tatara_lisp_eval::Value::Int(v) if (MIN_TAGGED..=MAX_TAGGED).contains(&v) => v << 2,
            // Out of tagging range. Reported as non-integer rather than
            // truncated: a sandbox that returns a plausible wrong number is
            // worse than one that says it cannot represent the answer.
            tatara_lisp_eval::Value::Int(_) => TAG_NON_INT,
            _ => TAG_NON_INT,
        },
    }
}

fn fail(message: &str) -> i64 {
    LAST_ERROR.with(|slot| *slot.borrow_mut() = Some(message.to_string()));
    TAG_ERROR
}

/// Length in bytes of the pending error, or 0.
#[no_mangle]
pub extern "C" fn blue_last_error_len() -> usize {
    LAST_ERROR.with(|slot| slot.borrow().as_ref().map_or(0, String::len))
}

/// Copy the pending error into `ptr`, which must have at least
/// `blue_last_error_len()` bytes.
#[no_mangle]
pub unsafe extern "C" fn blue_last_error(ptr: *mut u8) {
    LAST_ERROR.with(|slot| {
        if let Some(msg) = slot.borrow().as_ref() {
            std::ptr::copy_nonoverlapping(msg.as_ptr(), ptr, msg.len());
        }
    });
}

/// Decode a `blue_eval` result. Provided so a Rust host — and the tests — do
/// not each re-derive the shift.
pub fn decode(tagged: i64) -> Decoded {
    match tagged & 0b11 {
        0 => Decoded::Int(tagged >> 2),
        1 => Decoded::NonInt,
        _ => Decoded::Error,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Decoded {
    Int(i64),
    NonInt,
    Error,
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The tagging round-trips on the host, so the wasm tests below are
    /// checking the *engine*, not the encoding.
    #[test]
    fn an_integer_result_round_trips_through_the_tag() {
        assert_eq!(decode(eval_tagged("1 + 2")), Decoded::Int(3));
        assert_eq!(decode(eval_tagged("0")), Decoded::Int(0));
        assert_eq!(decode(eval_tagged("0 - 7")), Decoded::Int(-7));
    }

    /// **`0` must be distinguishable from failure.** This is why the result is
    /// tagged rather than a bare integer.
    #[test]
    fn zero_is_distinguishable_from_an_error() {
        assert_eq!(decode(eval_tagged("0")), Decoded::Int(0));
        assert_eq!(decode(eval_tagged("no_such_fn()")), Decoded::Error);
        assert_ne!(decode(eval_tagged("0")), decode(eval_tagged("no_such_fn()")));
    }

    #[test]
    fn a_non_integer_result_is_reported_as_such() {
        assert_eq!(decode(eval_tagged("true")), Decoded::NonInt);
        assert_eq!(decode(eval_tagged("\"hi\"")), Decoded::NonInt);
    }

    /// **A value too wide to tag reports as non-integer rather than
    /// truncating.** A sandbox that returns a plausible wrong number is worse
    /// than one that admits it cannot represent the answer.
    #[test]
    fn an_untaggable_integer_is_not_truncated() {
        // MAX_TAGGED is representable; one past it is not.
        let ok = format!("{MAX_TAGGED}");
        assert_eq!(decode(eval_tagged(&ok)), Decoded::Int(MAX_TAGGED));

        let too_big = format!("{MAX_TAGGED} + 1");
        assert_eq!(
            decode(eval_tagged(&too_big)),
            Decoded::NonInt,
            "must refuse rather than wrap"
        );
    }

    #[test]
    fn an_error_message_is_retrievable() {
        assert_eq!(decode(eval_tagged("no_such_fn()")), Decoded::Error);
        assert!(blue_last_error_len() > 0, "the message must be fetchable");
    }

    /// A type error is reported through the same channel — the wasm surface
    /// runs the whole pipeline, not just the evaluator.
    #[test]
    fn the_wasm_surface_runs_the_whole_pipeline_including_the_checker() {
        assert_eq!(
            decode(eval_tagged("def bad(a: Int) -> Str\n  a\nend\nbad(1)")),
            Decoded::Error,
            "the type checker must run here too"
        );
    }

    /// Macros work, so the embedded surface is the whole language rather than a
    /// subset.
    #[test]
    fn macros_work_in_the_wasm_surface() {
        assert_eq!(
            decode(eval_tagged(
                "defmacro double(x)\n  quote\n    unquote(x) + unquote(x)\n  end\nend\ndouble(21)"
            )),
            Decoded::Int(42)
        );
    }
}
