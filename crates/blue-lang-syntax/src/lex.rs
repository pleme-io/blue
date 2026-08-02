//! The blue lexer.
//!
//! Blue's surface is Ruby/Elixir-shaped, so the lexer's job is different
//! from an s-expression reader's: it must distinguish `foo` the send from
//! `foo(x)` the call, keep `:sym` distinct from `a ? b : c`, and record
//! enough position to point a diagnostic at the byte the human typed.
//!
//! Two decisions here are load-bearing downstream and are made once:
//!
//! 1. **Every token carries a byte span.** `theory/BLUE.md` §0 requires
//!    total provenance — every node in an expanded program traceable to the
//!    source that caused it — and provenance cannot be recovered later if
//!    the lexer drops it.
//! 2. **Trivia is a token, not a skip.** Comments and newlines are emitted
//!    rather than discarded, because a canonical formatter and an LSP both
//!    need a lossless stream. The measured failure this avoids is
//!    tatara-lisp's own reader, which discards trivia at tokenize time and
//!    thereby makes a comment-preserving formatter unbuildable on top of it.
//!    Callers that do not want trivia filter it; callers that need it
//!    cannot conjure it back.

use std::fmt;

/// A half-open byte range into the source.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

impl Span {
    pub fn new(start: usize, end: usize) -> Self {
        Self { start, end }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum TokenKind {
    // literals
    Int(i64),
    Float(f64),
    Str(String),
    /// An interpolated string: alternating literal and expression parts.
    ///
    /// `"a#{x}b"` lexes to `["a", "b"]` literals with `["x"]` between them —
    /// the expression is kept as SOURCE TEXT and parsed by the parser, which
    /// already knows how to parse an expression. Re-implementing expression
    /// lexing inside the string lexer would be a second parser, and the two
    /// would drift.
    InterpolatedStr {
        /// `parts.len() == exprs.len() + 1`, always — the literal before each
        /// expression, plus the tail. An empty literal is kept rather than
        /// dropped so that invariant holds for `"#{a}#{b}"` too.
        parts: Vec<String>,
        exprs: Vec<String>,
    },
    /// `:name` — a Ruby symbol, which lowers to a tatara-lisp keyword.
    Sym(String),
    True,
    False,
    Nil,

    /// An identifier, or a keyword-like head (`if`, `do`, `end`, …).
    /// The parser decides which; the lexer does not need to know.
    Ident(String),

    // punctuation
    LParen,
    RParen,
    LBracket,
    RBracket,
    LBrace,
    RBrace,
    Comma,
    Dot,
    /// `:` in a hash literal (`foo: 1`) is folded into `Label`; a bare
    /// colon is retained for anything else.
    Colon,
    /// `foo:` — a hash-literal label. Lexing this as one token is what
    /// makes `{foo: 1}` and `{:foo => 1}` distinguishable at the parser
    /// without lookahead games.
    Label(String),
    /// `=>` — the "rocket".
    Rocket,
    /// `|>` — the pipeline operator.
    Pipe,

    /// Any operator run: `+ - * / == != < <= > >= && || = ! %`.
    Op(String),

    // trivia — emitted, never skipped
    Comment(String),
    Newline,

    Eof,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Token {
    pub kind: TokenKind,
    pub span: Span,
}

impl Token {
    /// Is this token trivia (a comment or a newline)?
    pub fn is_trivia(&self) -> bool {
        matches!(self.kind, TokenKind::Comment(_) | TokenKind::Newline)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct LexError {
    pub message: String,
    pub span: Span,
}

impl fmt::Display for LexError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{} at {}..{}",
            self.message, self.span.start, self.span.end
        )
    }
}

impl std::error::Error for LexError {}

/// Characters that may begin or continue an operator run.
const OP_CHARS: &str = "+-*/=<>!%&|";

/// Tokenize `src`, including trivia.
pub fn lex(src: &str) -> Result<Vec<Token>, LexError> {
    Lexer::new(src).run()
}

struct Lexer<'a> {
    src: &'a str,
    bytes: &'a [u8],
    pos: usize,
    out: Vec<Token>,
}

impl<'a> Lexer<'a> {
    fn new(src: &'a str) -> Self {
        Self {
            src,
            bytes: src.as_bytes(),
            pos: 0,
            out: Vec::new(),
        }
    }

    /// Decode the whole UTF-8 character at the cursor, with its byte width.
    ///
    /// The lexer scans bytes because that is right for ASCII, which is all of
    /// blue's structure. This is the seam where it stops being right: a
    /// character outside ASCII has to be decoded before anything can classify
    /// it, and the previous approach — treating every byte >= 0x80 as a letter
    /// — could not tell `≠` from `文`, so an operator was unreachable and a
    /// malformed sequence became a silent identifier.
    fn decode_char(&self) -> Option<(char, usize)> {
        let rest = self.src.get(self.pos..)?;
        let ch = rest.chars().next()?;
        Some((ch, ch.len_utf8()))
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }

    fn peek_at(&self, n: usize) -> Option<u8> {
        self.bytes.get(self.pos + n).copied()
    }

    fn push(&mut self, kind: TokenKind, start: usize) {
        self.out.push(Token {
            kind,
            span: Span::new(start, self.pos),
        });
    }

    fn err(&self, message: impl Into<String>, start: usize) -> LexError {
        LexError {
            message: message.into(),
            span: Span::new(start, self.pos.max(start + 1)),
        }
    }

    fn run(mut self) -> Result<Vec<Token>, LexError> {
        while let Some(c) = self.peek() {
            let start = self.pos;
            match c {
                b'\n' => {
                    self.pos += 1;
                    self.push(TokenKind::Newline, start);
                }
                // Horizontal whitespace carries no meaning in blue and is
                // reconstructed by the formatter, so it is the one thing
                // dropped. Newlines are kept: they are statement separators.
                b' ' | b'\t' | b'\r' => {
                    self.pos += 1;
                }
                b'#' => {
                    while let Some(c) = self.peek() {
                        if c == b'\n' {
                            break;
                        }
                        self.pos += 1;
                    }
                    let text = self.src[start..self.pos].to_string();
                    self.push(TokenKind::Comment(text), start);
                }
                b'"' => self.lex_string(start)?,
                b'0'..=b'9' => self.lex_number(start)?,
                b':' => self.lex_colon(start),
                b'(' => self.one(TokenKind::LParen, start),
                b')' => self.one(TokenKind::RParen, start),
                b'[' => self.one(TokenKind::LBracket, start),
                b']' => self.one(TokenKind::RBracket, start),
                b'{' => self.one(TokenKind::LBrace, start),
                b'}' => self.one(TokenKind::RBrace, start),
                b',' => self.one(TokenKind::Comma, start),
                b'.' => self.one(TokenKind::Dot, start),
                // Non-ASCII goes through the UTF-8 layer, which decodes a
                // whole CHARACTER and asks `kigou` what it means. This must
                // precede the ident branch: a symbol like `≠` is an operator,
                // not the first letter of a name.
                c if c >= 0x80 => {
                    let Some((ch, width)) = self.decode_char() else {
                        self.pos += 1;
                        return Err(self.err("invalid UTF-8 in source", start));
                    };
                    match crate::kigou::classify(ch) {
                        crate::kigou::Class::Operator(op) => {
                            self.pos += width;
                            self.push(TokenKind::Op(op.to_owned()), start);
                        }
                        crate::kigou::Class::Word => self.lex_ident(start),
                        crate::kigou::Class::Reject => {
                            self.pos += width;
                            return Err(self.err(
                                format!(
                                    "the character {ch:?} (U+{:04X}) is not legal in blue source \
                                     outside a string — invisible and control characters are \
                                     rejected because source that looks correct and is not costs \
                                     far more than a clear error here",
                                    ch as u32
                                ),
                                start,
                            ));
                        }
                    }
                }
                c if is_ident_start(c) => self.lex_ident(start),
                c if OP_CHARS.as_bytes().contains(&c) => self.lex_op(start),
                _ => {
                    self.pos += 1;
                    return Err(self.err(format!("unexpected character {:?}", c as char), start));
                }
            }
        }
        let end = self.pos;
        self.out.push(Token {
            kind: TokenKind::Eof,
            span: Span::new(end, end),
        });
        Ok(self.out)
    }

    fn one(&mut self, kind: TokenKind, start: usize) {
        self.pos += 1;
        self.push(kind, start);
    }

    fn lex_string(&mut self, start: usize) -> Result<(), LexError> {
        self.pos += 1; // opening quote
        let mut buf = String::new();
        // Interpolation state. `parts` collects the literal run before each
        // `#{…}`; `exprs` collects the raw source between the braces.
        let mut parts: Vec<String> = Vec::new();
        let mut exprs: Vec<String> = Vec::new();
        loop {
            // `#{` opens an interpolation. A bare `#` is just a character — a
            // string full of `#` comments would otherwise be unwritable.
            if self.peek() == Some(b'#') && self.src.as_bytes().get(self.pos + 1) == Some(&b'{') {
                self.pos += 2;
                let expr_start = self.pos;
                // Track nesting so `"#{ {a: 1} }"` closes on the right brace.
                let mut depth = 1usize;
                while let Some(c) = self.peek() {
                    match c {
                        b'{' => depth += 1,
                        b'}' => {
                            depth -= 1;
                            if depth == 0 {
                                break;
                            }
                        }
                        _ => {}
                    }
                    self.pos += 1;
                }
                if self.peek() != Some(b'}') {
                    return Err(self.err("unterminated `#{` interpolation", start));
                }
                exprs.push(self.src[expr_start..self.pos].to_string());
                self.pos += 1; // past '}'
                parts.push(std::mem::take(&mut buf));
                continue;
            }
            match self.peek() {
                None => return Err(self.err("unterminated string literal", start)),
                Some(b'"') => {
                    self.pos += 1;
                    break;
                }
                Some(b'\\') => {
                    self.pos += 1;
                    let esc = self
                        .peek()
                        .ok_or_else(|| self.err("unterminated escape", start))?;
                    let ch = match esc {
                        b'n' => '\n',
                        b't' => '\t',
                        b'r' => '\r',
                        b'\\' => '\\',
                        b'"' => '"',
                        b'0' => '\0',
                        // `\u{...}` — a Unicode scalar by codepoint. Ruby and
                        // Elixir both have it, and without it a blue source
                        // file can only carry a non-ASCII character literally,
                        // which is exactly the case where an explicit escape
                        // matters most (combining marks, zero-width joiners,
                        // anything invisible in an editor).
                        b'u' => {
                            self.pos += 1; // past 'u'
                            if self.peek() != Some(b'{') {
                                return Err(self.err("expected `{` after \\u", start));
                            }
                            self.pos += 1; // past '{'
                            let hex_start = self.pos;
                            while self.peek().is_some_and(|c| c != b'}') {
                                self.pos += 1;
                            }
                            if self.peek() != Some(b'}') {
                                return Err(self.err("unterminated \\u{...} escape", start));
                            }
                            let hex = &self.src[hex_start..self.pos];
                            let code = u32::from_str_radix(hex, 16).map_err(|_| {
                                self.err(format!("`{hex}` is not hexadecimal"), start)
                            })?;
                            // A surrogate or out-of-range value is REJECTED, not
                            // replaced with U+FFFD: silently substituting a
                            // different character is how a codepoint typo
                            // becomes a rendering mystery.
                            let ch = char::from_u32(code).ok_or_else(|| {
                                self.err(format!("`{hex}` is not a Unicode scalar value"), start)
                            })?;
                            buf.push(ch);
                            self.pos += 1; // past '}'
                            continue;
                        }
                        other => {
                            return Err(
                                self.err(format!("unknown escape \\{}", other as char), start)
                            )
                        }
                    };
                    buf.push(ch);
                    self.pos += 1;
                }
                Some(_) => {
                    let ch = self.src[self.pos..]
                        .chars()
                        .next()
                        .expect("peek said there is a byte");
                    buf.push(ch);
                    self.pos += ch.len_utf8();
                }
            }
        }
        if exprs.is_empty() {
            self.push(TokenKind::Str(buf), start);
        } else {
            parts.push(buf);
            self.push(TokenKind::InterpolatedStr { parts, exprs }, start);
        }
        Ok(())
    }

    fn lex_number(&mut self, start: usize) -> Result<(), LexError> {
        while matches!(self.peek(), Some(b'0'..=b'9' | b'_')) {
            self.pos += 1;
        }
        // A `.` is a decimal point only when a digit follows; otherwise it
        // is the method-call dot and belongs to the next token. This is why
        // `1.foo` sends `foo` to `1` rather than failing to lex.
        let is_float = self.peek() == Some(b'.') && matches!(self.peek_at(1), Some(b'0'..=b'9'));
        if is_float {
            self.pos += 1;
            while matches!(self.peek(), Some(b'0'..=b'9' | b'_')) {
                self.pos += 1;
            }
        }
        let text: String = self.src[start..self.pos]
            .chars()
            .filter(|c| *c != '_')
            .collect();
        if is_float {
            let v: f64 = text
                .parse()
                .map_err(|_| self.err(format!("invalid float literal {text:?}"), start))?;
            self.push(TokenKind::Float(v), start);
        } else {
            let v: i64 = text
                .parse()
                .map_err(|_| self.err(format!("integer literal out of range: {text:?}"), start))?;
            self.push(TokenKind::Int(v), start);
        }
        Ok(())
    }

    fn lex_colon(&mut self, start: usize) {
        // `:name` is a symbol; a bare `:` is punctuation.
        if matches!(self.peek_at(1), Some(c) if is_ident_start(c)) {
            self.pos += 1;
            let s = self.pos;
            while matches!(self.peek(), Some(c) if is_ident_continue(c)) {
                self.pos += 1;
            }
            let name = self.src[s..self.pos].to_string();
            self.push(TokenKind::Sym(name), start);
        } else {
            self.one(TokenKind::Colon, start);
        }
    }

    fn lex_ident(&mut self, start: usize) {
        while matches!(self.peek(), Some(c) if is_ident_continue(c)) {
            self.pos += 1;
        }

        // A TRAILING `?` or `!` is part of the name, as in Ruby.
        //
        // Without this, four builtins the runtime registers — `contains?`,
        // `starts_with?`, `ends_with?` and `to_int!` — were unreachable from
        // every blue program ever written: dead code in the runtime and a
        // silent capability gap that made `moji` reimplement three of them by
        // hand.
        //
        // The `=` guard is what keeps `!=` working. `a != b` is safe either way
        // (the `!` follows a space), but `a!=b` is not: without the lookahead
        // the `!` would be eaten into the identifier and the comparison would
        // vanish. So a trailing `!` joins the name only when what follows is
        // NOT `=`.
        if matches!(self.peek(), Some(b'?'))
            || (matches!(self.peek(), Some(b'!')) && !matches!(self.peek_at(1), Some(b'=')))
        {
            self.pos += 1;
        }
        // Ruby's trailing `?` and `!` are part of the name.
        if matches!(self.peek(), Some(b'?') | Some(b'!')) {
            self.pos += 1;
        }
        let name = self.src[start..self.pos].to_string();

        // `foo:` is a hash label — one token, so `{foo: 1}` needs no
        // lookahead in the parser. Not folded when followed by `:`, which
        // would be `foo::bar`.
        if self.peek() == Some(b':') && self.peek_at(1) != Some(b':') {
            self.pos += 1;
            self.push(TokenKind::Label(name), start);
            return;
        }

        let kind = match name.as_str() {
            "true" => TokenKind::True,
            "false" => TokenKind::False,
            "nil" => TokenKind::Nil,
            _ => TokenKind::Ident(name),
        };
        self.push(kind, start);
    }

    fn lex_op(&mut self, start: usize) {
        while matches!(self.peek(), Some(c) if OP_CHARS.as_bytes().contains(&c)) {
            self.pos += 1;
        }
        let text = self.src[start..self.pos].to_string();
        let kind = match text.as_str() {
            "=>" => TokenKind::Rocket,
            "|>" => TokenKind::Pipe,
            _ => TokenKind::Op(text),
        };
        self.push(kind, start);
    }
}

// An identifier may be written in ANY script, not only Latin.
//
// The lexer works on bytes, and the rule that makes that safe is a property of
// UTF-8 rather than a trick: every byte of a multi-byte character is >= 0x80,
// and every character blue gives structural meaning — operators, delimiters,
// quotes, `#` — is ASCII, hence < 0x80. So "byte >= 0x80 is part of an
// identifier" consumes each multi-byte character whole, leaves every ASCII
// decision untouched, and keeps `src[start..pos]` on a char boundary.
//
// Without this the `yakugo` language packs cannot exist at all: `définir` died
// on 'Ã' and `定義` on 'å' — a UTF-8 continuation byte reported as a character,
// which is the diagnostic a byte-oriented lexer gives for text it was never
// built to read.
//
// PERMISSIVE, deliberately and worth stating: this admits any non-ASCII byte,
// so an emoji or a lone combining mark is a legal identifier. Enforcing
// XID_Start/XID_Continue would need real char decoding through the whole
// lexer. Accepting too much is a surface question; rejecting every non-Latin
// script was a correctness one.
fn is_ident_start(c: u8) -> bool {
    c.is_ascii_alphabetic() || c == b'_'
}

fn is_ident_continue(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_' || c >= 0x80
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(src: &str) -> Vec<TokenKind> {
        lex(src)
            .expect("lex")
            .into_iter()
            .filter(|t| !t.is_trivia() && t.kind != TokenKind::Eof)
            .map(|t| t.kind)
            .collect()
    }

    #[test]
    fn lexes_integers_and_floats() {
        assert_eq!(
            kinds("1 2.5 1_000"),
            vec![
                TokenKind::Int(1),
                TokenKind::Float(2.5),
                TokenKind::Int(1000),
            ]
        );
    }

    /// `1.foo` is a send, not a malformed float. The decimal point is a
    /// decimal point only when a digit follows it.
    #[test]
    fn a_dot_after_a_digit_is_a_send_unless_a_digit_follows() {
        assert_eq!(
            kinds("1.foo"),
            vec![
                TokenKind::Int(1),
                TokenKind::Dot,
                TokenKind::Ident("foo".into()),
            ]
        );
    }

    #[test]
    fn lexes_symbols_and_labels_distinctly() {
        assert_eq!(kinds(":foo"), vec![TokenKind::Sym("foo".into())]);
        assert_eq!(kinds("foo:"), vec![TokenKind::Label("foo".into())]);
    }

    #[test]
    fn ruby_predicate_and_bang_suffixes_are_part_of_the_name() {
        assert_eq!(
            kinds("empty? save!"),
            vec![
                TokenKind::Ident("empty?".into()),
                TokenKind::Ident("save!".into()),
            ]
        );
    }

    #[test]
    fn lexes_strings_with_escapes() {
        assert_eq!(kinds(r#""a\nb""#), vec![TokenKind::Str("a\nb".into())]);
    }

    #[test]
    fn unterminated_string_is_an_error_with_a_span() {
        let e = lex("\"oops").expect_err("must fail");
        assert!(e.message.contains("unterminated"), "{}", e.message);
        assert_eq!(e.span.start, 0);
    }

    /// Trivia is EMITTED, not skipped. A formatter and an LSP both need a
    /// lossless stream, and neither can recover what the lexer discarded.
    #[test]
    fn comments_and_newlines_are_emitted_as_trivia() {
        let toks = lex("1 # hi\n2").expect("lex");
        assert!(
            toks.iter()
                .any(|t| matches!(&t.kind, TokenKind::Comment(c) if c == "# hi")),
            "comment was dropped: {toks:?}"
        );
        assert!(
            toks.iter().any(|t| t.kind == TokenKind::Newline),
            "newline was dropped"
        );
    }

    /// Anti-vacuity for the span claim: spans must be real byte offsets
    /// into the source, not placeholders.
    #[test]
    fn spans_point_at_the_actual_bytes() {
        let src = "foo + 1";
        let toks = lex(src).expect("lex");
        let first = &toks[0];
        assert_eq!(&src[first.span.start..first.span.end], "foo");
        let last_int = toks
            .iter()
            .find(|t| matches!(t.kind, TokenKind::Int(_)))
            .expect("an int token");
        assert_eq!(&src[last_int.span.start..last_int.span.end], "1");
    }

    #[test]
    fn lexes_pipeline_and_rocket() {
        assert_eq!(kinds("|> =>"), vec![TokenKind::Pipe, TokenKind::Rocket]);
    }
}
