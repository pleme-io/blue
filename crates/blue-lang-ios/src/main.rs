#![deny(unsafe_code)]

#[cfg(target_os = "ios")]
fn main() {
    blue_lang_ios::run();
}

#[cfg(not(target_os = "ios"))]
fn main() {
    eprintln!(
        "blue-ios runs on iOS; build it with --target aarch64-apple-ios-sim or aarch64-apple-ios"
    );
    std::process::exit(2);
}
