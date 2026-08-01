//! blue's language server.
//!
//! Two layers, deliberately separate:
//!
//! - [`analysis`] — **transport-free**. Source text in, diagnostics /
//!   formatting / hover out, as plain Rust types. Every behaviour is tested by
//!   direct function call.
//! - [`server`] — the JSON-RPC-over-stdio shim. Thin by construction: it
//!   decodes a request, calls into `analysis`, and encodes the reply.
//!
//! An analysis core reachable only through a protocol can be tested only by
//! speaking that protocol, so its tests become slow, awkward and few — and the
//! editor experience is exactly what nobody wants under-tested.
//!
//! ## What this supports
//!
//! `textDocument/didOpen`, `didChange`, `formatting`, `hover`, and push
//! diagnostics. **Not** completion, go-to-definition, rename, or references:
//! each needs a resolved name table blue does not build yet, and a completion
//! list assembled from a token scan is worse than no completion — it suggests
//! names that do not exist.

pub mod analysis;
pub mod server;

pub use analysis::{analyse, hover, Analysis, Declaration, Diagnostic, LineIndex, Position, Range, Severity};
pub use server::{handle, Response, Server};
