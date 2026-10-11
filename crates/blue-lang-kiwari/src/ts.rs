//! The one seam over tree-sitter's C runtime.
//!
//! The runtime and the parser kiwari emits are both C, and both are facts about
//! the world here: the editors that read blue load exactly these. So they are
//! contained rather than reimplemented — loaded with `dlopen` at run time from
//! paths the caller supplies (nix builds both), spoken to through the thinnest
//! ABI (`api.h`, by value), and never compiled or linked into this crate.
//!
//! This module is the crate's only `#[allow(unsafe_code)]`; `tests/seam.rs`
//! fails when a second one appears. Everything it exports is safe: a [`Tree`]
//! owns its `TSTree*` and frees it on drop, and a [`Node`] borrows its tree.

#![allow(unsafe_code)]

use std::ffi::{c_char, c_void, CStr, CString};
use std::marker::PhantomData;
use std::path::{Path, PathBuf};

/// Why the runtime or a grammar could not be loaded.
#[derive(Debug, thiserror::Error)]
pub enum LoadError {
    #[error("{path}: {reason}")]
    Open { path: PathBuf, reason: String },
    #[error("{path} does not export `{symbol}`")]
    Symbol { path: PathBuf, symbol: String },
    #[error(
        "the runtime refused the grammar in {path}: its ABI is outside what this runtime reads"
    )]
    Abi { path: PathBuf },
}

#[repr(C)]
#[derive(Clone, Copy)]
struct RawNode {
    context: [u32; 4],
    id: *const c_void,
    tree: *const c_void,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct RawCursor {
    tree: *const c_void,
    id: *const c_void,
    context: [u32; 3],
}

#[repr(C)]
#[derive(Clone, Copy)]
struct Point {
    row: u32,
    column: u32,
}

#[repr(C)]
struct InputEdit {
    start_byte: u32,
    old_end_byte: u32,
    new_end_byte: u32,
    start_point: Point,
    old_end_point: Point,
    new_end_point: Point,
}

struct Api {
    parser_new: unsafe extern "C" fn() -> *mut c_void,
    parser_delete: unsafe extern "C" fn(*mut c_void),
    parser_set_language: unsafe extern "C" fn(*mut c_void, *const c_void) -> bool,
    parser_parse_string:
        unsafe extern "C" fn(*mut c_void, *const c_void, *const c_char, u32) -> *mut c_void,
    tree_delete: unsafe extern "C" fn(*mut c_void),
    tree_edit: unsafe extern "C" fn(*mut c_void, *const InputEdit),
    tree_root_node: unsafe extern "C" fn(*const c_void) -> RawNode,
    node_type: unsafe extern "C" fn(RawNode) -> *const c_char,
    node_start_byte: unsafe extern "C" fn(RawNode) -> u32,
    node_end_byte: unsafe extern "C" fn(RawNode) -> u32,
    node_is_named: unsafe extern "C" fn(RawNode) -> bool,
    node_is_missing: unsafe extern "C" fn(RawNode) -> bool,
    node_is_extra: unsafe extern "C" fn(RawNode) -> bool,
    node_is_error: unsafe extern "C" fn(RawNode) -> bool,
    node_has_error: unsafe extern "C" fn(RawNode) -> bool,
    cursor_new: unsafe extern "C" fn(RawNode) -> RawCursor,
    cursor_delete: unsafe extern "C" fn(*mut RawCursor),
    cursor_first_child: unsafe extern "C" fn(*mut RawCursor) -> bool,
    cursor_next_sibling: unsafe extern "C" fn(*mut RawCursor) -> bool,
    cursor_node: unsafe extern "C" fn(*const RawCursor) -> RawNode,
    cursor_field_name: unsafe extern "C" fn(*const RawCursor) -> *const c_char,
}

struct Library {
    handle: *mut c_void,
    path: PathBuf,
}

impl Library {
    fn open(path: &Path) -> Result<Self, LoadError> {
        let c = CString::new(path.as_os_str().to_string_lossy().as_bytes()).map_err(|_| {
            LoadError::Open {
                path: path.to_path_buf(),
                reason: "the path contains a NUL byte".into(),
            }
        })?;
        let handle = unsafe { libc::dlopen(c.as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL) };
        if handle.is_null() {
            let reason = unsafe {
                let e = libc::dlerror();
                if e.is_null() {
                    "dlopen failed".to_string()
                } else {
                    CStr::from_ptr(e).to_string_lossy().into_owned()
                }
            };
            return Err(LoadError::Open {
                path: path.to_path_buf(),
                reason,
            });
        }
        Ok(Self {
            handle,
            path: path.to_path_buf(),
        })
    }

    fn symbol(&self, name: &str) -> Result<*mut c_void, LoadError> {
        let c = CString::new(name).expect("symbol names carry no NUL");
        let p = unsafe { libc::dlsym(self.handle, c.as_ptr()) };
        if p.is_null() {
            Err(LoadError::Symbol {
                path: self.path.clone(),
                symbol: name.to_string(),
            })
        } else {
            Ok(p)
        }
    }
}

macro_rules! load {
    ($lib:expr, $name:literal) => {
        unsafe { std::mem::transmute::<*mut c_void, _>($lib.symbol($name)?) }
    };
}

/// The tree-sitter runtime and one grammar, loaded.
///
/// Both libraries stay open for the life of the value; dropping it never
/// unloads them, since a `TSLanguage` is static data other threads may still
/// be reading.
pub struct Runtime {
    api: Api,
    language: *const c_void,
    _runtime: Library,
    _grammar: Library,
}

// The function table is immutable code pointers and the language is static,
// read-only data; tree-sitter documents a `TSLanguage` as shareable across
// threads. Parsers and trees are NOT shared: each thread makes its own.
unsafe impl Send for Runtime {}
unsafe impl Sync for Runtime {}

impl Runtime {
    /// Load `libtree-sitter` from `runtime` and the grammar whose language
    /// function is `tree_sitter_<language>` from `grammar`.
    pub fn load(runtime: &Path, grammar: &Path, language: &str) -> Result<Self, LoadError> {
        let rt = Library::open(runtime)?;
        let api = Api {
            parser_new: load!(rt, "ts_parser_new"),
            parser_delete: load!(rt, "ts_parser_delete"),
            parser_set_language: load!(rt, "ts_parser_set_language"),
            parser_parse_string: load!(rt, "ts_parser_parse_string"),
            tree_delete: load!(rt, "ts_tree_delete"),
            tree_edit: load!(rt, "ts_tree_edit"),
            tree_root_node: load!(rt, "ts_tree_root_node"),
            node_type: load!(rt, "ts_node_type"),
            node_start_byte: load!(rt, "ts_node_start_byte"),
            node_end_byte: load!(rt, "ts_node_end_byte"),
            node_is_named: load!(rt, "ts_node_is_named"),
            node_is_missing: load!(rt, "ts_node_is_missing"),
            node_is_extra: load!(rt, "ts_node_is_extra"),
            node_is_error: load!(rt, "ts_node_is_error"),
            node_has_error: load!(rt, "ts_node_has_error"),
            cursor_new: load!(rt, "ts_tree_cursor_new"),
            cursor_delete: load!(rt, "ts_tree_cursor_delete"),
            cursor_first_child: load!(rt, "ts_tree_cursor_goto_first_child"),
            cursor_next_sibling: load!(rt, "ts_tree_cursor_goto_next_sibling"),
            cursor_node: load!(rt, "ts_tree_cursor_current_node"),
            cursor_field_name: load!(rt, "ts_tree_cursor_current_field_name"),
        };
        let gr = Library::open(grammar)?;
        let entry: unsafe extern "C" fn() -> *const c_void = {
            let name = format!("tree_sitter_{language}");
            unsafe { std::mem::transmute::<*mut c_void, _>(gr.symbol(&name)?) }
        };
        let language = unsafe { entry() };
        let probe = unsafe { (api.parser_new)() };
        let accepted = unsafe { (api.parser_set_language)(probe, language) };
        unsafe { (api.parser_delete)(probe) };
        if !accepted {
            return Err(LoadError::Abi {
                path: grammar.to_path_buf(),
            });
        }
        Ok(Self {
            api,
            language,
            _runtime: rt,
            _grammar: gr,
        })
    }

    /// A parser for this grammar. One per thread.
    pub fn parser(&self) -> Parser<'_> {
        let raw = unsafe { (self.api.parser_new)() };
        let set = unsafe { (self.api.parser_set_language)(raw, self.language) };
        assert!(set, "the language was accepted when the runtime loaded it");
        Parser { rt: self, raw }
    }
}

pub struct Parser<'r> {
    rt: &'r Runtime,
    raw: *mut c_void,
}

impl<'r> Parser<'r> {
    /// A fresh parse of `src`, with no previous tree.
    pub fn parse(&mut self, src: &str) -> Tree<'r> {
        let len = u32::try_from(src.len()).expect("a blue source fits in 4 GiB");
        let raw = unsafe {
            (self.rt.api.parser_parse_string)(self.raw, std::ptr::null(), src.as_ptr().cast(), len)
        };
        assert!(
            !raw.is_null(),
            "tree-sitter returns no tree only on cancellation, which is never set here"
        );
        Tree { rt: self.rt, raw }
    }

    /// `src` parsed incrementally from `old`, the tree of `src`'s first
    /// `old_len` bytes, as an editor does after text is typed at the end:
    /// `old` is edited in place and every subtree the edit did not reach is
    /// reused, keeping its identity ([`Node::id`]).
    pub fn reparse_appended(&mut self, old: &mut Tree<'r>, src: &str, old_len: usize) -> Tree<'r> {
        let point = |at: usize| {
            let before = &src[..at];
            let row = before.matches('\n').count();
            let column = before.rfind('\n').map_or(at, |i| at - i - 1);
            Point {
                row: row as u32,
                column: column as u32,
            }
        };
        let edit = InputEdit {
            start_byte: old_len as u32,
            old_end_byte: old_len as u32,
            new_end_byte: src.len() as u32,
            start_point: point(old_len),
            old_end_point: point(old_len),
            new_end_point: point(src.len()),
        };
        unsafe { (self.rt.api.tree_edit)(old.raw, &edit) };
        let len = u32::try_from(src.len()).expect("a blue source fits in 4 GiB");
        let raw = unsafe {
            (self.rt.api.parser_parse_string)(self.raw, old.raw, src.as_ptr().cast(), len)
        };
        assert!(
            !raw.is_null(),
            "tree-sitter returns no tree only on cancellation, which is never set here"
        );
        Tree { rt: self.rt, raw }
    }
}

impl Drop for Parser<'_> {
    fn drop(&mut self) {
        unsafe { (self.rt.api.parser_delete)(self.raw) }
    }
}

pub struct Tree<'r> {
    rt: &'r Runtime,
    raw: *mut c_void,
}

impl<'r> Tree<'r> {
    pub fn root(&self) -> Node<'_> {
        Node {
            rt: self.rt,
            raw: unsafe { (self.rt.api.tree_root_node)(self.raw) },
            _tree: PhantomData,
        }
    }
}

impl Drop for Tree<'_> {
    fn drop(&mut self) {
        unsafe { (self.rt.api.tree_delete)(self.raw) }
    }
}

/// A node of a [`Tree`], valid while the tree is.
#[derive(Clone, Copy)]
pub struct Node<'t> {
    rt: &'t Runtime,
    raw: RawNode,
    _tree: PhantomData<&'t Tree<'t>>,
}

/// A child as the cursor reports it: the node and the field it fills, if any.
#[derive(Clone, Copy)]
pub struct Child<'t> {
    pub field: Option<&'static str>,
    pub node: Node<'t>,
}

fn static_str(p: *const c_char) -> Option<&'static str> {
    if p.is_null() {
        None
    } else {
        // Node kinds and field names are string literals in the grammar's
        // static tables, alive for as long as the library is loaded, and the
        // runtime never unloads it.
        unsafe { CStr::from_ptr(p) }.to_str().ok()
    }
}

impl<'t> Node<'t> {
    /// The subtree's identity: equal for the same subtree reused by an
    /// incremental parse, while the trees holding it are alive.
    pub fn id(&self) -> usize {
        self.raw.id as usize
    }
    pub fn kind(&self) -> &'static str {
        static_str(unsafe { (self.rt.api.node_type)(self.raw) }).unwrap_or("")
    }
    pub fn start(&self) -> usize {
        unsafe { (self.rt.api.node_start_byte)(self.raw) as usize }
    }
    pub fn end(&self) -> usize {
        unsafe { (self.rt.api.node_end_byte)(self.raw) as usize }
    }
    pub fn is_named(&self) -> bool {
        unsafe { (self.rt.api.node_is_named)(self.raw) }
    }
    pub fn is_missing(&self) -> bool {
        unsafe { (self.rt.api.node_is_missing)(self.raw) }
    }
    pub fn is_extra(&self) -> bool {
        unsafe { (self.rt.api.node_is_extra)(self.raw) }
    }
    pub fn is_error(&self) -> bool {
        unsafe { (self.rt.api.node_is_error)(self.raw) }
    }
    /// The node is, or contains, an `ERROR` or a `MISSING` node.
    pub fn has_error(&self) -> bool {
        unsafe { (self.rt.api.node_has_error)(self.raw) }
    }

    /// Every child, named or not, in order, with its field.
    pub fn children(&self) -> Vec<Child<'t>> {
        let mut out = Vec::new();
        let mut c = unsafe { (self.rt.api.cursor_new)(self.raw) };
        if unsafe { (self.rt.api.cursor_first_child)(&mut c) } {
            loop {
                let node = unsafe { (self.rt.api.cursor_node)(&c) };
                let field = static_str(unsafe { (self.rt.api.cursor_field_name)(&c) });
                out.push(Child {
                    field,
                    node: Node {
                        rt: self.rt,
                        raw: node,
                        _tree: PhantomData,
                    },
                });
                if !unsafe { (self.rt.api.cursor_next_sibling)(&mut c) } {
                    break;
                }
            }
        }
        unsafe { (self.rt.api.cursor_delete)(&mut c) };
        out
    }
}
