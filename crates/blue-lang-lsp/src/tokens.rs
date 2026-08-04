//! Semantic tokens — **transport-free**.
//!
//! This is how a blue buffer gets colour, and the choice of mechanism is the
//! load-bearing part.
//!
//! ## Why semantic tokens and not a grammar
//!
//! `docs/NATURALIZE-TREESITTER.md` §2 refuses a hand-authored `grammar.js` as
//! an independent artifact: a second definition of blue's syntax beside
//! `blue-lang-syntax`'s parser diverges the first time either changes, and the
//! drift is invisible — the editor highlights one language while the compiler
//! compiles another. That document names the way out:
//!
//! > a third consumer of the grammar (an LSP semantic tokenizer, …) is then a
//! > new renderer, not a new parser.
//!
//! This module is that renderer. It classifies the token stream that
//! `blue_lang_syntax::lex` already produces — the same lexer the compiler runs
//! — so "the editor and the compiler disagree about blue" has no
//! representation here. Nothing below re-implements lexing, and the keyword
//! set is read from `blue_lang_syntax::is_reserved_word` rather than
//! transcribed.
//!
//! ## What this can and cannot know
//!
//! Every classification here is **syntactic**: it is a function of the token
//! stream, never of a resolved name table. blue does not build one yet, which
//! is the same reason [`crate::server`] advertises no completion or go-to
//! definition. So `def foo` is a function *because of the `def`*, and `foo(x)`
//! is a call *because of the adjacent paren* — not because anything looked
//! `foo` up. What that cannot see, and deliberately does not guess:
//!
//! - a local variable versus a zero-argument call (`foo` alone) — both paint
//!   as a variable, because distinguishing them needs scope resolution;
//! - a type versus a value;
//! - whether a name is defined anywhere at all.
//!
//! Painting a guess would be worse than painting nothing: colour that is
//! confidently wrong is read as fact.
//!
//! ## Interpolated strings
//!
//! `"n=#{x}"` paints as one string span. The lexer keeps the interpolated
//! expressions as source text (`TokenKind::InterpolatedStr::exprs`) without
//! per-expression spans, so their byte ranges are not recoverable here. Adding
//! spans to those parts is a lexer change; until then this is a known,
//! stated limit rather than a silent one.

use blue_lang_syntax::{is_reserved_word, lex, Span, Token, TokenKind};

use crate::analysis::LineIndex;

/// The token types blue emits, in **legend order**.
///
/// The discriminant IS the index a client resolves against the legend, so the
/// order of this enum is a wire format: reordering it repaints every buffer.
/// [`legend_types`] is derived from [`SemanticTokenType::ALL`] rather than
/// written out a second time, so the two cannot disagree.
///
/// Every name is one of LSP's standard `SemanticTokenTypes`. A non-standard
/// name is legal but is ignored by clients that do not know it, which is a
/// silent way to ship no colour.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum SemanticTokenType {
    Keyword = 0,
    Comment = 1,
    String = 2,
    Number = 3,
    Operator = 4,
    Variable = 5,
    Function = 6,
    Property = 7,
    EnumMember = 8,
}

impl SemanticTokenType {
    /// Every variant, in legend order. The one place the order is stated.
    pub const ALL: &'static [SemanticTokenType] = &[
        SemanticTokenType::Keyword,
        SemanticTokenType::Comment,
        SemanticTokenType::String,
        SemanticTokenType::Number,
        SemanticTokenType::Operator,
        SemanticTokenType::Variable,
        SemanticTokenType::Function,
        SemanticTokenType::Property,
        SemanticTokenType::EnumMember,
    ];

    /// The LSP spelling. Total over the enum — no wildcard arm — so adding a
    /// variant fails to compile here rather than shipping an unnamed type.
    pub fn lsp_name(self) -> &'static str {
        match self {
            SemanticTokenType::Keyword => "keyword",
            SemanticTokenType::Comment => "comment",
            SemanticTokenType::String => "string",
            SemanticTokenType::Number => "number",
            SemanticTokenType::Operator => "operator",
            SemanticTokenType::Variable => "variable",
            SemanticTokenType::Function => "function",
            SemanticTokenType::Property => "property",
            SemanticTokenType::EnumMember => "enumMember",
        }
    }

    /// Index into [`legend_types`].
    pub fn index(self) -> u32 {
        self as u32
    }
}

/// The token modifiers blue emits, in legend order. A modifier is a **bit
/// position**, not an index.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum SemanticTokenModifier {
    Declaration = 0,
}

impl SemanticTokenModifier {
    pub const ALL: &'static [SemanticTokenModifier] = &[SemanticTokenModifier::Declaration];

    pub fn lsp_name(self) -> &'static str {
        match self {
            SemanticTokenModifier::Declaration => "declaration",
        }
    }

    /// The bit this modifier occupies in a token's modifier bitset.
    pub fn bit(self) -> u32 {
        1 << (self as u32)
    }
}

/// The `tokenTypes` legend, derived from [`SemanticTokenType::ALL`].
pub fn legend_types() -> Vec<&'static str> {
    SemanticTokenType::ALL
        .iter()
        .map(|t| t.lsp_name())
        .collect()
}

/// The `tokenModifiers` legend, derived from [`SemanticTokenModifier::ALL`].
pub fn legend_modifiers() -> Vec<&'static str> {
    SemanticTokenModifier::ALL
        .iter()
        .map(|m| m.lsp_name())
        .collect()
}

/// One token, in absolute coordinates.
///
/// LSP transmits these delta-encoded ([`encode`]), but deltas are a wire
/// concern: an absolute token is what a test can read, and a bug in the
/// encoder should not be indistinguishable from a bug in the classifier.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SemanticToken {
    /// Zero-based line.
    pub line: u32,
    /// Zero-based start, in UTF-16 code units within the line.
    pub start_char: u32,
    /// Length, in UTF-16 code units. Never spans a line break.
    pub length: u32,
    pub token_type: SemanticTokenType,
    /// Bitset over [`SemanticTokenModifier`].
    pub modifiers: u32,
}

/// Classify `src` into semantic tokens, ordered by position.
///
/// A lex error yields an empty vec rather than a partial paint: the buffer is
/// mid-edit constantly, and a half-classified stream flickers colour onto text
/// whose meaning is not yet known. Diagnostics are the surface that reports a
/// broken buffer; this one stays quiet and lets the client keep the previous
/// colouring.
pub fn semantic_tokens(src: &str) -> Vec<SemanticToken> {
    let Ok(tokens) = lex(src) else {
        return Vec::new();
    };
    let index = LineIndex::new(src);
    let mut out = Vec::new();

    for (i, token) in tokens.iter().enumerate() {
        let Some((token_type, modifiers)) = classify(&tokens, i) else {
            continue;
        };
        push_span(&mut out, src, &index, token.span, token_type, modifiers);
    }

    out
}

/// Classify the token at `i`, using its neighbours for the two syntactic
/// refinements this module allows itself.
///
/// Returns `None` for anything that should carry no colour of its own:
/// trivia that is not a comment, brackets, and separators. Leaving those
/// unpainted is deliberate — a client paints them with the buffer's default
/// foreground, which is what every tree-sitter theme does with
/// `punctuation.bracket`. Claiming them as `operator` would make `(` louder
/// than the call it wraps.
fn classify(tokens: &[Token], i: usize) -> Option<(SemanticTokenType, u32)> {
    use SemanticTokenType as T;

    // Total over TokenKind — no wildcard arm. A new token kind fails to
    // compile here rather than silently arriving unpainted.
    let ty = match &tokens[i].kind {
        TokenKind::Int(_) | TokenKind::Float(_) => T::Number,
        TokenKind::Str(_) | TokenKind::InterpolatedStr { .. } => T::String,
        TokenKind::Sym(_) => T::EnumMember,

        // `true` / `false` / `nil` are reserved words (`BLOCK_KEYWORDS`), so
        // they paint as keywords for the same reason `end` does. The lexer
        // gives them their own kinds; that is a parsing convenience, not a
        // different lexical class.
        TokenKind::True | TokenKind::False | TokenKind::Nil => T::Keyword,

        TokenKind::Ident(name) => {
            if is_reserved_word(name) {
                T::Keyword
            } else if follows_def(tokens, i) {
                // A declaration: `def foo`. Syntactic — the `def` is right
                // there — so this is not a guess about what `foo` means.
                return Some((T::Function, SemanticTokenModifier::Declaration.bit()));
            } else if is_call_head(tokens, i) {
                T::Function
            } else {
                T::Variable
            }
        }

        // `foo:` in a hash literal. The lexer folds the colon in, so the
        // span covers `foo:` and the label paints as one thing.
        TokenKind::Label(_) => T::Property,

        TokenKind::Op(_) | TokenKind::Rocket | TokenKind::Pipe => T::Operator,

        TokenKind::LParen
        | TokenKind::RParen
        | TokenKind::LBracket
        | TokenKind::RBracket
        | TokenKind::LBrace
        | TokenKind::RBrace
        | TokenKind::Comma
        | TokenKind::Dot
        | TokenKind::Colon => return None,

        TokenKind::Comment(_) => T::Comment,
        TokenKind::Newline | TokenKind::Eof => return None,
    };

    Some((ty, 0))
}

/// Is the token at `i` the name in a `def` / `defmacro` form?
fn follows_def(tokens: &[Token], i: usize) -> bool {
    matches!(
        prev_significant(tokens, i).map(|t| &t.kind),
        Some(TokenKind::Ident(prev)) if prev == "def" || prev == "defmacro"
    )
}

/// Is the token at `i` the head of a call — an identifier with `(` glued to
/// it?
///
/// Adjacency is required, not just "the next token is a paren": blue
/// distinguishes `foo(x)` the call from `foo (x)` — and more to the point,
/// from `foo` a send followed by a parenthesised expression. Comparing spans
/// is how that distinction is read off the stream without re-lexing.
fn is_call_head(tokens: &[Token], i: usize) -> bool {
    let end = tokens[i].span.end;
    matches!(
        tokens.get(i + 1),
        Some(Token { kind: TokenKind::LParen, span }) if span.start == end
    )
}

/// The previous token that is not trivia.
fn prev_significant(tokens: &[Token], i: usize) -> Option<&Token> {
    tokens[..i].iter().rev().find(|t| !t.is_trivia())
}

/// Push `span` as one or more tokens, splitting at line breaks.
///
/// **A semantic token may not span a line.** The LSP encoding has no way to
/// express one — a token is `(deltaLine, deltaStart, length)` where `length`
/// is measured within a single line — so a client given a multi-line token
/// either drops it or paints a wrong-length run on the first line.
///
/// blue can produce one: `lex_string` consumes bytes until the closing quote
/// without rejecting newlines, so a string literal spanning lines is a normal
/// program, not a malformed one. Splitting here is what keeps that from
/// becoming a client-side artefact.
fn push_span(
    out: &mut Vec<SemanticToken>,
    src: &str,
    index: &LineIndex,
    span: Span,
    token_type: SemanticTokenType,
    modifiers: u32,
) {
    let end = span.end.min(src.len());
    let mut start = span.start.min(end);

    while start < end {
        // The piece runs to the next newline inside the span, or to its end.
        let piece_end = src[start..end].find('\n').map(|n| start + n).unwrap_or(end);

        if piece_end > start {
            let pos = index.position(start);
            out.push(SemanticToken {
                line: pos.line,
                start_char: pos.character,
                length: utf16_len(&src[start..piece_end]),
                token_type,
                modifiers,
            });
        }

        // Step past the newline itself; it carries no colour.
        start = piece_end + 1;
    }
}

fn utf16_len(s: &str) -> u32 {
    s.chars().map(|c| c.len_utf16() as u32).sum()
}

/// Delta-encode tokens into LSP's flat `data` array.
///
/// Five integers per token: `deltaLine`, `deltaStartChar`, `length`,
/// `tokenType`, `tokenModifiers`. `deltaStartChar` is relative to the previous
/// token when both are on the same line, and absolute otherwise — the one rule
/// in this encoding that is easy to get wrong and produces a plausible-looking
/// but progressively-shifted paint when you do.
///
/// The input must be sorted by position; [`semantic_tokens`] emits it that way
/// because it walks the lexer's output in order.
pub fn encode(tokens: &[SemanticToken]) -> Vec<u32> {
    let mut data = Vec::with_capacity(tokens.len() * 5);
    let mut prev_line = 0u32;
    let mut prev_start = 0u32;

    for t in tokens {
        let delta_line = t.line - prev_line;
        let delta_start = if delta_line == 0 {
            t.start_char - prev_start
        } else {
            t.start_char
        };

        data.extend_from_slice(&[
            delta_line,
            delta_start,
            t.length,
            t.token_type.index(),
            t.modifiers,
        ]);

        prev_line = t.line;
        prev_start = t.start_char;
    }

    data
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every token of `src`, as `(text, type, modifiers)`.
    fn classified(src: &str) -> Vec<(String, SemanticTokenType, u32)> {
        let index = LineIndex::new(src);
        semantic_tokens(src)
            .into_iter()
            .map(|t| {
                let start = index.offset(crate::analysis::Position {
                    line: t.line,
                    character: t.start_char,
                });
                let end = index.offset(crate::analysis::Position {
                    line: t.line,
                    character: t.start_char + t.length,
                });
                (src[start..end].to_string(), t.token_type, t.modifiers)
            })
            .collect()
    }

    fn types_of(src: &str, text: &str) -> Vec<SemanticTokenType> {
        classified(src)
            .into_iter()
            .filter(|(t, _, _)| t == text)
            .map(|(_, ty, _)| ty)
            .collect()
    }

    #[test]
    fn legend_order_matches_discriminants() {
        // The legend is a wire format; this pins the two representations of
        // its order together.
        for (i, ty) in SemanticTokenType::ALL.iter().enumerate() {
            assert_eq!(ty.index(), i as u32, "{ty:?} is out of legend order");
            assert_eq!(legend_types()[i], ty.lsp_name());
        }
        assert_eq!(legend_types().len(), SemanticTokenType::ALL.len());
    }

    #[test]
    fn modifier_bits_are_distinct_powers_of_two() {
        for (i, m) in SemanticTokenModifier::ALL.iter().enumerate() {
            assert_eq!(m.bit(), 1 << i);
        }
    }

    #[test]
    fn keywords_come_from_blue_not_from_a_transcription() {
        // Both halves of the reserved set: a SURFACE_KEYWORDS head and a
        // BLOCK_KEYWORDS delimiter. The second half is the one a highlighter
        // reading SURFACE_KEYWORDS alone would miss.
        let src = "if x\n  1\nelse\n  2\nend\n";
        assert_eq!(types_of(src, "if"), vec![SemanticTokenType::Keyword]);
        assert_eq!(types_of(src, "else"), vec![SemanticTokenType::Keyword]);
        assert_eq!(types_of(src, "end"), vec![SemanticTokenType::Keyword]);

        for word in blue_lang_syntax::SURFACE_KEYWORDS
            .iter()
            .chain(blue_lang_syntax::BLOCK_KEYWORDS)
        {
            let src = format!("{word}\n");
            let got = semantic_tokens(&src);
            assert_eq!(
                got.first().map(|t| t.token_type),
                Some(SemanticTokenType::Keyword),
                "reserved word {word} did not paint as a keyword",
            );
        }
    }

    #[test]
    fn def_name_is_a_function_declaration() {
        let src = "def add(a, b)\n  a + b\nend\n";
        let got = classified(src);

        let add = got.iter().find(|(t, _, _)| t == "add").expect("no `add`");
        assert_eq!(add.1, SemanticTokenType::Function);
        assert_eq!(add.2, SemanticTokenModifier::Declaration.bit());

        // Parameters are not resolved, so they are variables, not parameters.
        assert_eq!(types_of(src, "a"), vec![SemanticTokenType::Variable; 2]);
    }

    #[test]
    fn adjacent_paren_makes_a_call_head_and_a_space_does_not() {
        assert_eq!(types_of("f(1)\n", "f"), vec![SemanticTokenType::Function]);
        assert_eq!(types_of("f (1)\n", "f"), vec![SemanticTokenType::Variable]);
    }

    #[test]
    fn literals_and_trivia() {
        let src = "# note\nx = 1 + 2.5\ns = \"hi\"\nk = :name\n";
        assert_eq!(types_of(src, "# note"), vec![SemanticTokenType::Comment]);
        assert_eq!(types_of(src, "1"), vec![SemanticTokenType::Number]);
        assert_eq!(types_of(src, "2.5"), vec![SemanticTokenType::Number]);
        assert_eq!(types_of(src, "\"hi\""), vec![SemanticTokenType::String]);
        assert_eq!(types_of(src, ":name"), vec![SemanticTokenType::EnumMember]);
        assert_eq!(types_of(src, "="), vec![SemanticTokenType::Operator; 3]);
    }

    #[test]
    fn hash_label_is_a_property() {
        // The lexer folds the colon into the label, so the span is `name:`.
        assert_eq!(
            types_of("{name: 1}\n", "name:"),
            vec![SemanticTokenType::Property]
        );
    }

    #[test]
    fn brackets_and_separators_carry_no_token() {
        let src = "[1, 2].f\n";
        for punct in ["[", "]", ",", "."] {
            assert!(
                types_of(src, punct).is_empty(),
                "{punct} should carry no semantic token",
            );
        }
    }

    #[test]
    fn no_token_ever_spans_a_line() {
        // A string literal may contain a newline — `lex_string` does not
        // reject one — and LSP cannot encode a multi-line token.
        let src = "s = \"one\ntwo\nthree\"\n";
        let got = semantic_tokens(src);

        let strings: Vec<_> = got
            .iter()
            .filter(|t| t.token_type == SemanticTokenType::String)
            .collect();
        assert_eq!(strings.len(), 3, "the string should split into three lines");
        assert_eq!((strings[0].line, strings[0].start_char), (0, 4));
        assert_eq!(strings[0].length, 4); // `"one`
        assert_eq!((strings[1].line, strings[1].start_char), (1, 0));
        assert_eq!(strings[1].length, 3); // `two`
        assert_eq!((strings[2].line, strings[2].start_char), (2, 0));
        assert_eq!(strings[2].length, 6); // `three"`

        let index = LineIndex::new(src);
        for t in &got {
            let line_text = src.lines().nth(t.line as usize).unwrap_or("");
            assert!(
                t.start_char + t.length <= utf16_len(line_text),
                "token {t:?} runs past the end of its line",
            );
            // And the round-trip through LineIndex stays on one line.
            let end = index.offset(crate::analysis::Position {
                line: t.line,
                character: t.start_char + t.length,
            });
            assert!(!src[..end].ends_with('\n'));
        }
    }

    #[test]
    fn positions_are_utf16_code_units() {
        // `🔥` is two UTF-16 code units and four bytes. A byte-offset
        // implementation puts `x` at character 6 instead of 4, and every
        // token after it drifts.
        let src = "# 🔥\nx = 1\n";
        let got = semantic_tokens(src);
        let comment = got
            .iter()
            .find(|t| t.token_type == SemanticTokenType::Comment)
            .expect("no comment");
        assert_eq!(comment.line, 0);
        assert_eq!(comment.start_char, 0);
        assert_eq!(comment.length, 4, "`# ` plus a 2-unit emoji");
    }

    #[test]
    fn a_broken_buffer_paints_nothing_rather_than_half() {
        // An unterminated string is a normal mid-edit state.
        assert!(semantic_tokens("s = \"unterminated\n").is_empty());
    }

    #[test]
    fn encoding_is_delta_on_the_same_line_and_absolute_across_lines() {
        let tokens = vec![
            SemanticToken {
                line: 0,
                start_char: 0,
                length: 3,
                token_type: SemanticTokenType::Keyword,
                modifiers: 0,
            },
            SemanticToken {
                line: 0,
                start_char: 4,
                length: 3,
                token_type: SemanticTokenType::Function,
                modifiers: SemanticTokenModifier::Declaration.bit(),
            },
            SemanticToken {
                line: 2,
                start_char: 2,
                length: 1,
                token_type: SemanticTokenType::Variable,
                modifiers: 0,
            },
        ];

        // One row per token: [deltaLine, deltaStart, length, type, modifiers].
        // Kept as rows rather than a flat list so the grouping the encoding
        // depends on stays visible.
        let expected: Vec<u32> = [
            // line 0, col 0, len 3, keyword, no modifiers
            [0, 0, 3, SemanticTokenType::Keyword.index(), 0],
            // same line, so deltaStart is relative: 4 - 0
            [0, 4, 3, SemanticTokenType::Function.index(), 1],
            // new line, so deltaStart is ABSOLUTE — 2, not 2 - 4, which would
            // underflow and panic in debug
            [2, 2, 1, SemanticTokenType::Variable.index(), 0],
        ]
        .concat();

        assert_eq!(encode(&tokens), expected);
    }

    #[test]
    fn encoding_a_real_program_never_underflows() {
        // The absolute-vs-delta rule above is the one that panics in debug
        // when got wrong, so exercise it over something with backward jumps.
        let src = "def f(x)\n  longer_name = x + 1\n  f\nend\n";
        let tokens = semantic_tokens(src);
        assert!(!tokens.is_empty());
        let data = encode(&tokens);
        assert_eq!(data.len(), tokens.len() * 5);
    }
}
