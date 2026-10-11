//! The C stays behind one seam: `#![deny(unsafe_code)]` makes an `unsafe`
//! block outside an allowed module a compile error, and this makes a second
//! allowed module a test failure, the half the lint cannot see.

use std::path::Path;

#[test]
fn exactly_one_module_may_use_unsafe_and_it_is_the_tree_sitter_seam() {
    let src = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut allowed = Vec::new();
    for e in std::fs::read_dir(&src).expect("src").flatten() {
        let text = std::fs::read_to_string(e.path()).expect("a source file");
        if text.contains("allow(unsafe_code)") {
            allowed.push(e.file_name().to_string_lossy().into_owned());
        }
    }
    assert_eq!(allowed, ["ts.rs"], "unsafe is allowed outside the seam");
    let lib = std::fs::read_to_string(src.join("lib.rs")).expect("lib.rs");
    assert!(
        lib.contains("#![deny(unsafe_code)]"),
        "the crate root no longer denies unsafe code"
    );
}
