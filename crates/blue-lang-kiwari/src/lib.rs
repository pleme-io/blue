//! `kiwari` (木割) on the Rust side.
//!
//! 木割 is the proportioning rule-book of Japanese carpentry: every member's
//! dimensions derive from one base module, so no two pieces of the house can
//! disagree. kiwari is blue's ONE grammar spec, authored in blue
//! (`bidamas/kiwari`), from which the tree-sitter grammar and its queries are
//! emitted (`tree-sitter-blue/`). Until blue's own parser is emitted from it
//! too (`docs/NATURALIZE-TREESITTER.md` M3), two parsers exist, and this crate
//! is what holds them equal:
//!
//! - [`spec`] reads the part of the spec Rust needs, rendered beside this crate;
//! - [`lower`] turns any concrete syntax tree into blue's tree by the spec's
//!   templates;
//! - [`ts`] is the one seam over tree-sitter's C runtime, loaded at run time;
//! - [`agree`] defines agreement on a source and on every prefix of it, and
//!   runs it over a corpus.

#![deny(unsafe_code)]

pub mod agree;
pub mod lower;
pub mod spec;
pub mod ts;
