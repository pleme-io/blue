#![deny(unsafe_code)]

pub mod draw;
pub mod program;

#[cfg(target_os = "ios")]
#[allow(unsafe_code)]
mod shell;

#[cfg(target_os = "ios")]
pub use shell::run;

pub const PROGRAM_FILE: &str = "app.b";
