#![deny(unsafe_code)]

pub mod child;
pub mod once;
pub mod pool;
pub mod wire;

pub use blue_lang_host::Hosted;
pub use once::{run_once, within, OnceRun};
pub use pool::{Event, Overdue, Pool, Prepare, Sink, WorkerSpec};
pub use wire::{Refusal, Reply, Request};
