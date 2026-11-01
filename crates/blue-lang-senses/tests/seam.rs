use std::path::Path;

#[test]
fn exactly_one_module_may_use_unsafe_and_it_is_the_device_seam() {
    let src = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut allowed = Vec::new();
    for e in std::fs::read_dir(&src).expect("src").flatten() {
        let text = std::fs::read_to_string(e.path()).expect("a source file");
        if text.contains("allow(unsafe_code)") {
            allowed.push(e.file_name().to_string_lossy().into_owned());
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
    assert_eq!(
        seam.matches("unsafe {").count(),
        39,
        "the seam's audited calls: dlopen, dlsym, dlerror, AudioQueue, AudioObject and snd_pcm"
    );
    assert!(
        !seam.contains("bindgen") && !seam.contains("_sys::"),
        "the seam speaks the ABI itself, through dlopen"
    );
    let manifest =
        std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml"))
            .expect("Cargo.toml");
    for linked in ["-sys", "bindgen", "cpal", "coreaudio", "alsa", "cc ="] {
        assert!(!manifest.contains(linked), "the crate depends on {linked}");
    }
}
