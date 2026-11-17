//! The one seam where blue loads a native library: libc's `dlopen` and
//! `dlsym`, the lowest ABI, with no binding crate. A native artifact's
//! library (`native/seam/def64/lib.rs`) exports one symbol,
//! `blue_def_entry`; this module opens a library once, finds that symbol and
//! calls it. Everything unsafe in it is in [`seam`].

#![deny(unsafe_code)]

/// A definition loaded in process: `blue_def_entry` of its library.
#[derive(Clone, Copy)]
pub(crate) struct Entry(seam::Raw);

/// Open the library at `path` and find its entry; `None` when the file does
/// not load or exports no entry. A library stays loaded for the process.
pub(crate) fn open(path: &std::path::Path) -> Option<Entry> {
    use std::os::unix::ffi::OsStrExt;
    let path = std::ffi::CString::new(path.as_os_str().as_bytes()).ok()?;
    seam::open(&path).map(Entry)
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

    const RTLD_NOW: c_int = 2;
    #[cfg(target_os = "macos")]
    const RTLD_LOCAL: c_int = 4;
    #[cfg(not(target_os = "macos"))]
    const RTLD_LOCAL: c_int = 0;

    extern "C" {
        fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void;
        fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
    }

    pub(super) fn open(path: &CStr) -> Option<Raw> {
        let handle = unsafe { dlopen(path.as_ptr(), RTLD_NOW | RTLD_LOCAL) };
        if handle.is_null() {
            return None;
        }
        let symbol = unsafe { dlsym(handle, c"blue_def_entry".as_ptr()) };
        if symbol.is_null() {
            return None;
        }
        Some(unsafe { std::mem::transmute::<*mut c_void, Raw>(symbol) })
    }

    pub(super) fn call(entry: Raw, args: &[i64], out: &mut i64) -> i32 {
        entry(args.as_ptr(), args.len(), out)
    }
}
