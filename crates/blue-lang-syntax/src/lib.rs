//! blue's surface syntax.
//!
//! Blue is a general-purpose language whose surface is Ruby/Elixir-shaped
//! and whose **program is a tatara-lisp value**. This crate is the join:
//! it lexes blue source and parses it directly into `tatara_lisp::Sexp`.
//!
//! There is deliberately no private blue AST in between. Tenet 1 of
//! `theory/BLUE.md` is that blue source parses *to tatara-lisp*, and an
//! intermediate tree would make homoiconicity a conversion step rather
//! than an identity — the difference between blue's macro story working
//! and merely being asserted.
//!
//! ```
//! use blue_lang_syntax::parse_expr;
//! let form = parse_expr("user.greet(1)").unwrap();
//! assert_eq!(form.to_string(), "(greet user 1)");
//! ```

pub mod lex;
pub mod parse;

pub use lex::{lex, LexError, Span, Token, TokenKind};
pub use parse::{parse_expr, parse_program, Infix, ParseError, INFIX};
