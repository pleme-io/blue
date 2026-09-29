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
//! **Diagnostics, quick fixes and completion come from the pipeline's check
//! stage** — the same rules, codes, waivers and name table as `blue check`.
//! Completion offers every top-level name in scope with its namespace; it does
//! not yet offer locals (that needs the walker to report the frame at a
//! position). **Not** go-to-definition, rename, or references: the name table
//! records where each top-level name is defined, but no request is wired to
//! it yet. A completion list assembled from a token scan would be worse than
//! none — it suggests names that do not exist — which is why this one reads
//! the checker's table. Semantic tokens classify only what the token stream
//! states outright, and [`tokens`] lists what it therefore declines to guess.

pub mod analysis;
pub mod server;
pub mod shift;
pub mod tokens;

pub use analysis::{
    analyse, analyse_with, complete, hover, Analysis, Completion, CompletionKind, Declaration,
    Diagnostic, LineIndex, Position, QuickFix, Range, Severity, TextEdit,
};
pub use server::{handle, Response, Server};
pub use shift::{shift_of, Factor, FactorKind, Rung, Shift};
pub use tokens::{
    encode, legend_modifiers, legend_types, semantic_tokens, SemanticToken, SemanticTokenModifier,
    SemanticTokenType,
};
