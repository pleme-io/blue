use std::path::Path;

#[test]
fn exactly_one_module_may_use_unsafe_and_it_is_the_kernel_seam() {
    let src = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut allowed = Vec::new();
    for entry in std::fs::read_dir(&src).expect("src") {
        let path = entry.expect("entry").path();
        let text = std::fs::read_to_string(&path).expect("source");
        if text.contains("allow(unsafe_code)") {
            allowed.push(path.file_name().unwrap().to_string_lossy().into_owned());
        }
    }
    assert_eq!(allowed, ["seam.rs"], "unsafe is allowed outside the seam");
    let lib = std::fs::read_to_string(src.join("lib.rs")).expect("lib.rs");
    assert!(
        lib.contains("#![deny(unsafe_code)]"),
        "the crate root no longer denies unsafe code"
    );
    let seam = std::fs::read_to_string(src.join("seam.rs")).expect("seam.rs");
    assert_eq!(
        seam.matches("allow(unsafe_code)").count(),
        1,
        "the seam allows unsafe once, at its top"
    );
}
