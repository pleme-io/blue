//! The one seam where blue loads a native library: libc's `dlopen` and
//! `dlsym`, the lowest ABI, with no binding crate. A native artifact's
//! library (`native/seam/def64/lib.rs`) exports `blue_def_entry`, the
//! definition on Int words, and `blue_def_call`, the definition on value
//! tokens (a Str, which no word holds); this module opens a library once,
//! finds them and calls them. Everything unsafe in it is in [`seam`].

#![deny(unsafe_code)]

/// A definition loaded in process: `blue_def_entry` of its library, and
/// `blue_def_call` when the library is one that exports it.
#[derive(Clone, Copy)]
pub(crate) struct Entry(seam::Raw, Option<seam::RawCall>);

/// Open the library at `path` and find its entry; `None` when the file does
/// not load or exports no entry. A library stays loaded for the process.
pub(crate) fn open(path: &std::path::Path) -> Option<Entry> {
    use std::os::unix::ffi::OsStrExt;
    let path = std::ffi::CString::new(path.as_os_str().as_bytes()).ok()?;
    let (words, tokens) = seam::open(&path)?;
    Some(Entry(words, tokens))
}

/// The definition on value tokens (`native/seam/host_io.rs`, `decode`),
/// separated by spaces: its answer's token, or `None` when the library has no
/// `blue_def_call` or the definition faulted, printed or refused them.
pub(crate) fn call_tokens(entry: Entry, input: &str) -> Option<String> {
    let call = entry.1?;
    let mut cap = 64usize;
    loop {
        let mut out = vec![0u8; cap];
        let mut len = 0usize;
        match seam::call_tokens(call, input.as_bytes(), &mut out, &mut len) {
            0 => {
                out.truncate(len);
                return String::from_utf8(out).ok();
            }
            3 if len > cap => cap = len,
            _ => return None,
        }
    }
}

/// The definition on `args`: its result, or `None` when it faulted, printed,
/// or refused its arguments, so the interpreter runs the call.
pub(crate) fn call(entry: Entry, args: &[i64]) -> Option<i64> {
    let mut out = 0i64;
    (seam::call(entry.0, args, &mut out) == 0).then_some(out)
}

#[allow(unsafe_code)]
mod seam {
    use std::ffi::{c_char, c_int, c_void, CStr};

    pub(super) type Raw = extern "C" fn(*const i64, usize, *mut i64) -> i32;
    pub(super) type RawCall = extern "C" fn(*const u8, usize, *mut u8, usize, *mut usize) -> i32;

    const RTLD_NOW: c_int = 2;
    #[cfg(target_os = "macos")]
    const RTLD_LOCAL: c_int = 4;
    #[cfg(not(target_os = "macos"))]
    const RTLD_LOCAL: c_int = 0;

    extern "C" {
        fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void;
        fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
    }

    pub(super) fn open(path: &CStr) -> Option<(Raw, Option<RawCall>)> {
        let handle = unsafe { dlopen(path.as_ptr(), RTLD_NOW | RTLD_LOCAL) };
        if handle.is_null() {
            return None;
        }
        let symbol = unsafe { dlsym(handle, c"blue_def_entry".as_ptr()) };
        if symbol.is_null() {
            return None;
        }
        let words = unsafe { std::mem::transmute::<*mut c_void, Raw>(symbol) };
        let symbol = unsafe { dlsym(handle, c"blue_def_call".as_ptr()) };
        let tokens = (!symbol.is_null())
            .then(|| unsafe { std::mem::transmute::<*mut c_void, RawCall>(symbol) });
        Some((words, tokens))
    }

    pub(super) fn call_tokens(call: RawCall, input: &[u8], out: &mut [u8], len: &mut usize) -> i32 {
        call(
            input.as_ptr(),
            input.len(),
            out.as_mut_ptr(),
            out.len(),
            len,
        )
    }

    pub(super) fn call(entry: Raw, args: &[i64], out: &mut i64) -> i32 {
        entry(args.as_ptr(), args.len(), out)
    }
}
