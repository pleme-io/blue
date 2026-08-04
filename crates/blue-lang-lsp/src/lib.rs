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
//! `textDocument/didOpen`, `didChange`, `formatting`, `hover`,
//! `semanticTokens/full`, and push diagnostics — plus **`blue/shift`**, a
//! custom request answering "how far is this shifted, and what is shifting it"
//! ([`shift`]). Blueshift is blue's central model; a model that governs the
//! language and is invisible while you use it is one the author has to hold in
//! their head.
//!
//! **Semantic tokens are how a blue buffer gets colour** ([`tokens`]), and
//! they are the *only* way it does: `docs/NATURALIZE-TREESITTER.md` §2 refuses
//! a hand-authored tree-sitter grammar as a second definition of blue's
//! syntax, so the editor reads the same lexer the compiler does. An editor
//! needs no per-language configuration to consume them.
//!
//! **Not** completion, go-to-definition, rename, or references: each needs a
//! resolved name table blue does not build yet, and a completion list
//! assembled from a token scan is worse than no completion — it suggests names
//! that do not exist. Semantic tokens are not an exception to that rule; they
//! classify only what the token stream states outright, and [`tokens`] lists
//! what it therefore declines to guess.

pub mod analysis;
pub mod server;
pub mod shift;
pub mod tokens;

pub use analysis::{
    analyse, hover, Analysis, Declaration, Diagnostic, LineIndex, Position, Range, Severity,
};
pub use server::{handle, Response, Server};
pub use shift::{shift_of, Factor, FactorKind, Rung, Shift};
pub use tokens::{
    encode, legend_modifiers, legend_types, semantic_tokens, SemanticToken, SemanticTokenModifier,
    SemanticTokenType,
};
