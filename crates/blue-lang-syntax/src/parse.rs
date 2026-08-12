//! Precedence-climbing parser, lowering straight to the tatara-lisp
//! quoted form.
//!
//! **The load-bearing design decision, made here and once:** the parser's
//! output IS a `tatara_lisp::Sexp`. There is no private blue AST that later
//! gets converted. That is Tenet 1 — *blue source parses to tatara-lisp* —
//! and building it any other way would make homoiconicity a conversion step
//! rather than an identity, which is the difference between blue's macro
//! story working and merely being claimed.
//!
//! The consequence to keep in view: every surface construct must have a
//! well-defined s-expression it means. Where the mapping is not obvious it
//! is written down in the test module, because the tests are the
//! specification of the surface until the mechanized spec exists.
//!
//! ## Spans are built, not bolted on
//!
//! Every production returns a [`Spanned`] — tatara-lisp's parallel tree where
//! **each node** carries the byte range that produced it — and the spanless
//! [`parse_program`] is a projection of it via `Spanned::to_sexp`.
//!
//! That direction is deliberate and it is the second time this file has learned
//! the lesson: the spanless tree is derivable from the spanned one and the
//! reverse is not. When the parser produced `Sexp` and callers wanted positions,
//! the only answers available were *invent one* (a squiggle under unrelated
//! code) or *use nothing* — and the type checker took the second, so every type
//! error in the editor was reported at line 0, column 0 regardless of where it
//! was. A span discarded at the parser cannot be recovered by anything
//! downstream, exactly as [`crate::lex`] says of trivia.
//!
//! Two honest limits, both stated where they are caused rather than inferred:
//!
//! - A node blue **synthesizes** (the `define` a `def` lowers to, the `not` an
//!   `unless` lowers to, the `equal?` a `case` arm compares with) has no source
//!   text of its own. It is given the span of the token that *caused* it — the
//!   `def`, the `unless`, the `when` — which is where a reader looks when told
//!   something about it.
//! - An interpolation's inner expression is parsed from a **sub-source** (the
//!   text between `#{` and `}`), so its own offsets are relative to that
//!   substring and would point into the wrong buffer. Those nodes are stamped
//!   with the whole string literal's span instead. Sub-span accuracy inside an
//!   interpolation needs the lexer to record each part's offset in the outer
//!   source, which it does not.

use tatara_lisp::{Atom, Sexp, Spanned, SpannedForm};

use crate::lex::{lex, Span, Token, TokenKind};

#[derive(Clone, Debug, PartialEq)]
pub struct ParseError {
    pub message: String,
    pub span: Span,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{} at {}..{}",
            self.message, self.span.start, self.span.end
        )
    }
}

impl std::error::Error for ParseError {}

impl From<crate::lex::LexError> for ParseError {
    fn from(e: crate::lex::LexError) -> Self {
        Self {
            message: e.message,
            span: e.span,
        }
    }
}

/// Parse a blue program into a sequence of tatara-lisp forms.
pub fn parse_program(src: &str) -> Result<Vec<Sexp>, ParseError> {
    parse_program_with_depth(src, MAX_EXPR_DEPTH)
}

/// Parse a blue program keeping **every node's** source span.
///
/// This is the parser's real output; [`parse_program`] projects the spans away.
/// Reach for this one whenever a position is going to be shown to a human — an
/// editor squiggle, a `line:col` in a CLI error, a future debugger's breakpoint
/// table. Reach for [`parse_program`] only when the consumer genuinely does not
/// care where anything was.
pub fn parse_program_tree(src: &str) -> Result<Vec<Spanned>, ParseError> {
    parse_program_tree_with_depth(src, MAX_EXPR_DEPTH)
}

/// [`parse_program_tree`] with the nesting bound supplied by the caller.
pub fn parse_program_tree_with_depth(
    src: &str,
    max_depth: usize,
) -> Result<Vec<Spanned>, ParseError> {
    let toks: Vec<Token> = lex(src)?
        .into_iter()
        .filter(|t| !matches!(t.kind, TokenKind::Comment(_)))
        .collect();
    let mut p = Parser {
        toks,
        pos: 0,
        depth: 0,
        max_depth,
    };
    p.program()
}

/// Parse a program written in a [`Yakugo`](crate::yakugo::Yakugo) surface.
///
/// The pack is applied to the TOKEN STREAM, between lexing and parsing, so the
/// parser below is untouched and every keyword site works by construction.
/// What comes out is the same `Sexp` the English surface produces — that is
/// the invariant the pack tests assert, and the only thing that makes a
/// surface a surface rather than a dialect.
///
/// # Errors
///
/// Lex and parse errors propagate unchanged. A pack cannot repair source that
/// does not tokenize, and reporting otherwise would name the wrong problem.
pub fn parse_program_in(src: &str, pack: &crate::yakugo::Yakugo) -> Result<Vec<Sexp>, ParseError> {
    Ok(parse_program_tree_in(src, pack)?
        .iter()
        .map(Spanned::to_sexp)
        .collect())
}

/// [`parse_program_in`] keeping **every node's** source span.
///
/// The same relation [`parse_program_tree`] has to [`parse_program`], and it
/// exists for the same reason: a surface is a spelling, so a program written in
/// one has positions exactly as real as an English-surface program's. Without
/// this door, `pipeline::run_in_surface` would have to lift a spanless tree back
/// up and every type error in a `yakugo` program would report `<synthetic>` —
/// a position the parser HAD and threw away one line earlier, which is the
/// class `Diagnostic::span`'s own docs name.
///
/// [`parse_program_in`] is now its projection, so the two cannot drift.
///
/// # Errors
///
/// As [`parse_program_in`].
pub fn parse_program_tree_in(
    src: &str,
    pack: &crate::yakugo::Yakugo,
) -> Result<Vec<Spanned>, ParseError> {
    let toks: Vec<Token> = crate::yakugo::canonical_tokens(src, pack)?
        .into_iter()
        .filter(|t| !matches!(t.kind, TokenKind::Comment(_)))
        .collect();
    let mut p = Parser {
        toks,
        pos: 0,
        depth: 0,
        max_depth: MAX_EXPR_DEPTH,
    };
    p.program()
}

/// [`parse_program`] with the nesting bound supplied by the caller.
///
/// The bound is a **safety limit, not a dialect**: `max_depth` cannot change
/// what any program means, only whether a pathological one is refused before
/// the stack is at risk. That is why it is a parameter here and
/// [`MAX_EXPR_DEPTH`] is only the default — a knob that could alter meaning
/// would belong nowhere near a config file (see `blue-lang-cli`'s `config`
/// module for the rule this obeys).
pub fn parse_program_with_depth(src: &str, max_depth: usize) -> Result<Vec<Sexp>, ParseError> {
    Ok(parse_program_tree_with_depth(src, max_depth)?
        .iter()
        .map(Spanned::to_sexp)
        .collect())
}

/// Parse, keeping each top-level form's source span.
///
/// The spans are what let the formatter put comments back. A comment is not
/// part of a program's *meaning*, so it has no place in the `Sexp` tree —
/// putting it there would break canonicality, since two programs differing only
/// in a comment would stop formatting identically. Instead the formatter renders
/// the tree and re-interleaves comments by position, which needs to know where
/// each form started and ended.
///
/// A projection of [`parse_program_tree`], which carries a span on every node
/// rather than only the top-level ones. This entry point survives because the
/// formatter wants exactly the top-level pairing and nothing deeper.
pub fn parse_program_spanned(src: &str) -> Result<Vec<(Sexp, Span)>, ParseError> {
    parse_program_spanned_with_depth(src, MAX_EXPR_DEPTH)
}

/// [`parse_program_spanned`] with the nesting bound supplied by the caller.
pub fn parse_program_spanned_with_depth(
    src: &str,
    max_depth: usize,
) -> Result<Vec<(Sexp, Span)>, ParseError> {
    Ok(parse_program_tree_with_depth(src, max_depth)?
        .iter()
        .map(|f| (f.to_sexp(), f.span))
        .collect())
}

/// Every comment in `src`, with its byte span and whether it sits alone on its
/// line.
///
/// `own_line` is the distinction that decides placement: a comment alone on its
/// line belongs *before* the form that follows, while one after code on the same
/// line belongs *to* that line. Conflating them moves a trailing note onto the
/// wrong row.
pub fn comments(src: &str) -> Vec<Comment> {
    lex(src)
        .map(|toks| {
            toks.iter()
                .filter_map(|t| match &t.kind {
                    TokenKind::Comment(text) => Some(Comment {
                        text: text.clone(),
                        span: t.span,
                        own_line: line_before_is_blank(src, t.span.start),
                    }),
                    _ => None,
                })
                .collect()
        })
        .unwrap_or_default()
}

/// A comment, and where it sat.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Comment {
    /// The text, including the leading `#`.
    pub text: String,
    pub span: Span,
    /// Nothing but whitespace precedes it on its line.
    pub own_line: bool,
}

fn line_before_is_blank(src: &str, start: usize) -> bool {
    src[..start.min(src.len())]
        .rsplit('\n')
        .next()
        .is_some_and(|prefix| prefix.trim().is_empty())
}

/// Parse a single blue expression. Convenience for tests and the REPL.
pub fn parse_expr(src: &str) -> Result<Sexp, ParseError> {
    let forms = parse_program(src)?;
    match forms.len() {
        1 => Ok(forms.into_iter().next().expect("checked len")),
        n => Err(ParseError {
            message: format!("expected exactly one expression, found {n}"),
            span: Span::new(0, src.len()),
        }),
    }
}

/// What an infix operator binds like, and what it lowers to.
///
/// **One row per operator, carrying both facts.** Precedence and callee
/// used to live apart, and the cost was immediate: the surface spelling was
/// emitted verbatim, so `a == b` lowered to `(== a b)` — a symbol no
/// interpreter binds — and the program died at *runtime* with `unbound
/// symbol ==`. Splitting the two invites exactly that: add an operator to
/// the precedence table, forget the lowering, ship a parse that cannot run.
/// Joined here, "has a precedence" and "has a callee" are the same fact.
#[derive(Clone, Copy, Debug)]
pub struct Infix {
    /// Surface spelling.
    pub op: &'static str,
    /// Left and right binding power. Higher binds tighter.
    pub power: (u8, u8),
    /// The tatara-lisp callee this lowers to.
    pub callee: &'static str,
}

/// The complete infix table. Precedence follows Ruby's where Ruby has an
/// opinion; `|>` (below) sits under everything so `a |> f |> g` chains
/// without parentheses.
pub const INFIX: &[Infix] = &[
    Infix {
        op: "||",
        power: (1, 2),
        callee: "or",
    },
    Infix {
        op: "&&",
        power: (3, 4),
        callee: "and",
    },
    // `==` is STRUCTURAL equality, so it lowers to `equal?` and not to `=`.
    //
    // tatara's `=` is NUMERIC comparison: `"a" = "a"` is a type error, not
    // false. Lowering `==` to it meant every string, list or nil comparison
    // failed with "expected number, got string" — found by blue's own spec
    // suite the moment a test compared two strings, which is the first thing
    // anybody does.
    //
    // `equal?` is structural and total over the value domain: strings, lists
    // and nil all compare, and numbers still compare as numbers.
    Infix {
        op: "==",
        power: (5, 6),
        callee: "equal?",
    },
    Infix {
        op: "!=",
        power: (5, 6),
        callee: "not=",
    },
    Infix {
        op: "<",
        power: (5, 6),
        callee: "<",
    },
    Infix {
        op: "<=",
        power: (5, 6),
        callee: "<=",
    },
    Infix {
        op: ">",
        power: (5, 6),
        callee: ">",
    },
    Infix {
        op: ">=",
        power: (5, 6),
        callee: ">=",
    },
    Infix {
        op: "+",
        power: (7, 8),
        callee: "+",
    },
    Infix {
        op: "-",
        power: (7, 8),
        callee: "-",
    },
    Infix {
        op: "*",
        power: (9, 10),
        callee: "*",
    },
    Infix {
        op: "/",
        power: (9, 10),
        callee: "/",
    },
    Infix {
        op: "%",
        power: (9, 10),
        callee: "mod",
    },
];

/// Every surface keyword that BEGINS an expression.
///
/// Exists so the formatter's corpus can be checked against it. Three separate
/// times a form was added to this parser, the formatter was not extended, and
/// all three formatting laws still passed — because the corpus is
/// hand-maintained and contained no example of the new form. The annotated
/// `def` rendered as a method send; `defmacro` rendered as
/// `defmacro(double, x(), …)`, which does not re-parse at all.
///
/// A law cannot notice a case nobody wrote down. `blue-lang-fmt`'s
/// `every_surface_keyword_appears_in_the_corpus` closes that by making the
/// omission itself the failure, so adding a keyword here forces the corpus
/// entry that exercises the other three laws over it.
///
/// `do` and `end` are absent deliberately: they are block delimiters, not
/// expression heads, and have no standalone rendering to test.
/// The callee `assert e` lowers to.
///
/// **Owned here, by the lowering itself, and read by every consumer.** It was
/// briefly a literal here and a separate `const` in `blue-lang-test`, and the
/// shadowing gate then could not see a parser that lowered to the wrong name:
/// the gate checked its own copy. Same duplication class as the operator table.
pub const LOWERED_ASSERT: &str = "blue-assert";

/// The callee a `{...}` map literal lowers to.
///
/// **`hash-map`, not `map`.** tatara binds `map` to the higher-order function,
/// so a literal lowering to `(map …)` called the HOF with the key/value pairs
/// as arguments and failed with "expected list, got int". Same shadowing class
/// as [`LOWERED_ASSERT`], caught by the same gate once the name was listed
/// there — it was not, which is why this shipped.
pub const LOWERED_MAP: &str = "hash-map";

/// The callee string interpolation lowers to.
///
/// blue's own `concat`, which renders either side through `to_s` — that is what
/// lets `"n=#{42}"` interpolate a number. Not `+`, which is arithmetic.
pub const LOWERED_CONCAT: &str = "concat";

pub const SURFACE_KEYWORDS: &[&str] = &[
    "if",
    "unless",
    "def",
    "defmacro",
    "quote",
    "unquote",
    "unquote_splice",
    "test",
    "assert",
    "fn",
    "case",
];

/// The words that are reserved but are not heads of a `SURFACE_KEYWORDS` form
/// — block delimiters and the three literals.
///
/// Split out as data rather than inlined in a `matches!` because a reserved
/// word is not only the parser's business: a highlighter has to paint exactly
/// this set, and one that reads `SURFACE_KEYWORDS` alone silently under-paints
/// `do` / `end` / `else` / `elsif`. That was not hypothetical — escriba's
/// `escriba-render/src/langs.rs` hand-transcribed "SURFACE_KEYWORDS plus the
/// four block words `is_reserved_word` adds", because the union was
/// unreachable from outside this module. A transcription is a second
/// definition, and it drifts the first time this list changes.
pub const BLOCK_KEYWORDS: &[&str] = &["do", "end", "else", "elsif", "true", "false", "nil"];

/// A surface keyword may not be rebound. `if = 1` is a mistake, not a binding,
/// and letting it through would shadow the form for the rest of the file.
///
/// Public because it is the ONE answer to "is this identifier a keyword" —
/// the parser's rebinding check and every downstream highlighter read it here
/// rather than each carrying its own copy of the list.
pub fn is_reserved_word(name: &str) -> bool {
    SURFACE_KEYWORDS.contains(&name) || BLOCK_KEYWORDS.contains(&name)
}

fn infix(op: &str) -> Option<&'static Infix> {
    INFIX.iter().find(|i| i.op == op)
}

const PIPE_POWER: (u8, u8) = (0, 1);

struct Parser {
    toks: Vec<Token>,
    pos: usize,
    /// Current expression-nesting depth, bounded by [`Self::max_depth`].
    ///
    /// Without this the parser does not fail on deep input — it **aborts the
    /// process** with a stack overflow (SIGABRT), which `catch_unwind` cannot
    /// catch. Measured 2026-08-01: `"(".repeat(2_000)` killed the test runner
    /// outright. Every consumer inherited it — an LSP parsing a half-typed
    /// line, a formatter, and shikumi loading a `.b` config off disk.
    depth: usize,
    /// The bound [`Self::depth`] is checked against.
    ///
    /// Defaults to [`MAX_EXPR_DEPTH`] on every entry point that does not name
    /// one; `parse_program_with_depth` exists so an operator can raise it
    /// without recompiling. It is a **bound**, so raising it changes no
    /// program's meaning — only which pathological inputs are refused.
    max_depth: usize,
}

/// Maximum expression nesting before the parser refuses.
///
/// Chosen well above anything human-written (blue's own `spec/*.b` peaks in
/// single digits) and far below the measured overflow point, so the bound is
/// hit as a typed `Err` long before the stack is at risk. A limit that is
/// merely *near* the crash point is not a safety bound; it is a race.
pub const MAX_EXPR_DEPTH: usize = 256;

impl Parser {
    fn peek(&self) -> &TokenKind {
        &self.toks[self.pos.min(self.toks.len() - 1)].kind
    }

    fn peek_span(&self) -> Span {
        self.toks[self.pos.min(self.toks.len() - 1)].span
    }

    fn bump(&mut self) -> TokenKind {
        let k = self.toks[self.pos.min(self.toks.len() - 1)].kind.clone();
        if self.pos < self.toks.len() {
            self.pos += 1;
        }
        k
    }

    fn at(&self, k: &TokenKind) -> bool {
        self.peek() == k
    }

    fn eat(&mut self, k: &TokenKind) -> bool {
        if self.at(k) {
            self.bump();
            true
        } else {
            false
        }
    }

    fn expect(&mut self, k: &TokenKind, what: &str) -> Result<(), ParseError> {
        if self.eat(k) {
            Ok(())
        } else {
            Err(self.error(format!("expected {what}, found {:?}", self.peek())))
        }
    }

    fn error(&self, message: impl Into<String>) -> ParseError {
        ParseError {
            message: message.into(),
            span: self.peek_span(),
        }
    }

    /// Skip statement separators (newlines and semicolon-free layout).
    fn skip_newlines(&mut self) {
        while matches!(self.peek(), TokenKind::Newline) {
            self.bump();
        }
    }

    fn at_ident(&self, name: &str) -> bool {
        matches!(self.peek(), TokenKind::Ident(n) if n == name)
    }

    /// Byte offset where the next token begins — the anchor a production spans
    /// *from*. Paired with [`Self::span_since`].
    fn mark(&self) -> usize {
        self.peek_span().start
    }

    /// The span from `start` to the end of the **last consumed** token.
    ///
    /// `pos` has already advanced past that token, so this looks one back. Call
    /// it after a production has consumed everything it owns; calling it early
    /// yields a span that stops short of the node it describes.
    fn span_since(&self, start: usize) -> Span {
        let end = self
            .toks
            .get(self.pos.saturating_sub(1))
            .map_or(start, |t| t.span.end);
        Span::new(start, end.max(start))
    }

    fn program(&mut self) -> Result<Vec<Spanned>, ParseError> {
        let mut out = Vec::new();
        loop {
            self.skip_newlines();
            if matches!(self.peek(), TokenKind::Eof) {
                break;
            }
            out.push(self.statement()?);
        }
        Ok(out)
    }

    /// A statement: either a binding or an expression.
    ///
    /// `x = 5` lowers to `(define x 5)`. Blue had NO way to name a value — a
    /// capability probe found `x = 5` was a parse error, which makes every
    /// program a single expression. That is more fundamental than anything else
    /// the probe found.
    ///
    /// Only at STATEMENT position, never inside an expression, so `f(x = 1)` is
    /// still an error rather than a silent binding. Ruby allows assignment as an
    /// expression and it is a well-known footgun — `if x = 1` where `==` was
    /// meant. Blue declines it, and the cost is only that a walrus-style idiom
    /// has to be two lines.
    fn statement(&mut self) -> Result<Spanned, ParseError> {
        // The SECOND recursion cycle, and it needs the same guard as `expr`.
        //
        // Guarding `expr` alone was not enough — measured 2026-08-01: with the
        // expression bound in place, `"def a\n".repeat(2_000)` STILL aborted
        // the process. Block nesting (`def` opening a body that contains more
        // statements) recurses through here, not through `expr`, so a fix
        // applied to one cycle silently left the other reachable. Two paths to
        // the same crash; one guard covered one of them.
        //
        // Shares `self.depth` with `expr` on purpose: what the stack cares
        // about is TOTAL nesting, not which grammar production produced it, so
        // two independent counters would each permit their own full budget and
        // together exceed what the stack can hold.
        let max = self.max_depth;
        if self.depth >= max {
            return Err(self.error(format!(
                "statement nests deeper than {max}; refusing to \
                 recurse further (this is a limit, not a syntax error)"
            )));
        }
        self.depth += 1;
        let r = self.statement_inner();
        self.depth -= 1;
        r
    }

    fn statement_inner(&mut self) -> Result<Spanned, ParseError> {
        if let TokenKind::Ident(name) = self.peek().clone() {
            if self.peek_at(1) == "=" && !is_reserved_word(&name) {
                let name_span = self.peek_span();
                self.bump(); // name
                self.bump(); // =
                self.skip_newlines();
                let value = self.expr(0)?;
                // `define` is synthesized — `x = 5` contains no such word — so
                // it takes the span of the name being bound, which is what a
                // reader looks at when told something about the binding.
                return Ok(list_at(
                    self.span_since(name_span.start),
                    vec![sym_at(name_span, "define"), sym_at(name_span, &name), value],
                ));
            }
        }
        self.expr(0)
    }

    /// The token `n` positions ahead, for the two-token lookahead a binding
    /// needs. Returns `Eof` past the end rather than panicking.
    fn peek_at(&self, n: usize) -> String {
        match self.toks.get(self.pos + n).map(|t| &t.kind) {
            Some(TokenKind::Op(o)) => o.clone(),
            _ => String::new(),
        }
    }

    /// Pratt loop.
    fn expr(&mut self, min_bp: u8) -> Result<Spanned, ParseError> {
        // Depth guard at the single recursion cycle (`expr` -> `prefix` ->
        // `expr`). Returning an Err here converts an UNRECOVERABLE abort into
        // an ordinary parse failure a caller can render — the difference
        // between an LSP showing a squiggle and an LSP being gone.
        //
        // The decrement is deliberately not RAII: every exit from this
        // function is via `?` or a normal return, and both are covered by the
        // explicit decrements below. A guard object would be tidier but would
        // also hide the invariant this comment is here to state.
        let max = self.max_depth;
        if self.depth >= max {
            return Err(self.error(format!(
                "expression nests deeper than {max}; refusing to \
                 recurse further (this is a limit, not a syntax error)"
            )));
        }
        self.depth += 1;
        let r = self.expr_inner(min_bp);
        self.depth -= 1;
        r
    }

    fn expr_inner(&mut self, min_bp: u8) -> Result<Spanned, ParseError> {
        let start = self.mark();
        let mut lhs = self.prefix()?;

        loop {
            // Postfix: `.name`, `.name(args)`, `(args)`
            match self.peek() {
                TokenKind::Dot => {
                    self.bump();
                    lhs = self.finish_send(start, lhs)?;
                    continue;
                }
                TokenKind::LParen => {
                    // A call on an expression already parsed: `f(x)`.
                    let args = self.paren_args()?;
                    let mut list = vec![lhs];
                    list.extend(args);
                    lhs = list_at(self.span_since(start), list);
                    continue;
                }
                _ => {}
            }

            // Infix
            // `callee == None` marks the pipeline, which is a rewrite rather
            // than a call.
            let op_span = self.peek_span();
            let (callee, (lbp, rbp)) = match self.peek() {
                TokenKind::Pipe => (None, PIPE_POWER),
                TokenKind::Op(o) => match infix(o) {
                    Some(i) => (Some(i.callee), i.power),
                    None => break,
                },
                _ => break,
            };
            if lbp < min_bp {
                break;
            }
            self.bump();
            self.skip_newlines();
            let rhs = self.expr(rbp)?;

            lhs = if callee.is_none() {
                // `x |> f`      => (f x)
                // `x |> f(a)`   => (f x a)   — the pipeline threads into
                //                  the FIRST argument position, as Elixir's
                //                  does; that is what makes it composable.
                let rhs_span = rhs.span;
                match rhs.form {
                    SpannedForm::List(mut items) if !items.is_empty() => {
                        items.insert(1, lhs);
                        list_at(self.span_since(start), items)
                    }
                    callee => list_at(
                        self.span_since(start),
                        vec![Spanned::new(rhs_span, callee), lhs],
                    ),
                }
            } else {
                // The callee symbol takes the OPERATOR's span, not the whole
                // expression's: `a + b` lowers to `(+ a b)` and the `+` node is
                // the one byte-range in the source that means it. Handing it the
                // whole expression's span would make a diagnostic about the
                // operator underline both operands too.
                list_at(
                    self.span_since(start),
                    vec![sym_at(op_span, callee.unwrap()), lhs, rhs],
                )
            };
        }

        Ok(lhs)
    }

    fn prefix(&mut self) -> Result<Spanned, ParseError> {
        let span = self.peek_span();
        match self.bump() {
            TokenKind::Int(v) => Ok(atom_at(span, Atom::Int(v))),
            TokenKind::Float(v) => Ok(atom_at(span, Atom::Float(v))),
            TokenKind::Str(s) => Ok(atom_at(span, Atom::Str(s))),

            // `"a#{x}b"` → `(concat (concat "a" x) "b")`.
            //
            // Lowered to `concat`, not to `+`: blue's `+` is arithmetic (see
            // the INFIX table), and interpolation must render a value of ANY
            // type — `concat` goes through `to_s`, which is what makes
            // `"n=#{42}"` work.
            //
            // The expression source is parsed HERE with the ordinary parser
            // rather than lexed inside the string, so an interpolation can hold
            // anything an expression can and the two can never drift.
            TokenKind::InterpolatedStr { parts, exprs } => {
                // Every node here carries the WHOLE string literal's span.
                //
                // The inner expression is parsed from `raw` — a substring — so
                // its own offsets index that substring, not `src`. Carrying them
                // through would produce spans that look real and point into a
                // buffer nobody has: for `"a#{x}"` at offset 40, `x`'s span
                // would be 0..1, i.e. the start of the file. The lexer does not
                // record where each part sat in the outer source, so the string
                // literal is the most precise honest answer available.
                let mut acc = atom_at(span, Atom::Str(parts[0].clone()));
                for (i, raw) in exprs.iter().enumerate() {
                    let inner = parse_expr(raw).map_err(|e| ParseError {
                        message: format!("in interpolation `#{{{raw}}}`: {}", e.message),
                        span,
                    })?;
                    let inner = Spanned::from_sexp_at(&inner, span);
                    acc = list_at(span, vec![sym_at(span, LOWERED_CONCAT), acc, inner]);
                    // `parts.len() == exprs.len() + 1` by construction, so this
                    // index is always in range.
                    acc = list_at(
                        span,
                        vec![
                            sym_at(span, LOWERED_CONCAT),
                            acc,
                            atom_at(span, Atom::Str(parts[i + 1].clone())),
                        ],
                    );
                }
                Ok(acc)
            }
            TokenKind::Sym(s) => Ok(atom_at(span, Atom::Keyword(s))),
            TokenKind::True => Ok(atom_at(span, Atom::Bool(true))),
            TokenKind::False => Ok(atom_at(span, Atom::Bool(false))),
            TokenKind::Nil => Ok(Spanned::new(span, SpannedForm::Nil)),

            TokenKind::Op(o) if o == "-" => {
                let rhs = self.expr(11)?; // binds tighter than `*`
                Ok(list_at(
                    self.span_since(span.start),
                    vec![sym_at(span, "-"), atom_at(span, Atom::Int(0)), rhs],
                ))
            }
            TokenKind::Op(o) if o == "!" => {
                let rhs = self.expr(11)?;
                Ok(list_at(
                    self.span_since(span.start),
                    vec![sym_at(span, "not"), rhs],
                ))
            }

            TokenKind::LParen => {
                self.skip_newlines();
                let inner = self.expr(0)?;
                self.skip_newlines();
                self.expect(&TokenKind::RParen, "`)`")?;
                // The inner expression's own span, NOT one widened to include
                // the parentheses: grouping is not part of the expression's
                // meaning, and `(a + b)` should underline `a + b`.
                Ok(inner)
            }

            TokenKind::LBracket => self.list_literal(span),
            TokenKind::LBrace => self.map_literal(span),

            TokenKind::Ident(name) => match name.as_str() {
                "if" => self.if_form(span, false),
                "unless" => self.if_form(span, true),
                "def" => self.def_form(span),
                "defmacro" => self.defmacro_form(span),
                "case" => self.case_form(span),
                "fn" => self.lambda_form(span),
                "test" => self.test_form(span),
                "assert" => self.assert_form(span),
                "quote" => self.quote_form(span),
                "unquote" => self.unquote_form(span, false),
                "unquote_splice" => self.unquote_form(span, true),
                "do" => Err(ParseError {
                    message: "`do` without a preceding call".into(),
                    span,
                }),
                "end" => Err(ParseError {
                    message: "unexpected `end`".into(),
                    span,
                }),
                _ => Ok(sym_at(span, &name)),
            },

            other => Err(ParseError {
                message: format!("expected an expression, found {other:?}"),
                span,
            }),
        }
    }

    /// After a `.`: `recv.name` or `recv.name(args)`.
    ///
    /// **A bare `recv.name` is a SEND, not a field read.** Blue commits to
    /// the uniform access principle here: a structure exposes no public
    /// fields, so a field can later become a computed method without
    /// breaking a caller.
    fn finish_send(&mut self, start: usize, recv: Spanned) -> Result<Spanned, ParseError> {
        let name_span = self.peek_span();
        let name = match self.bump() {
            // A RESERVED WORD is not a method name.
            //
            // Found by the formatter property suite, minimal input `1.def`.
            // The send parsed happily into `(def 1)` — `def` is just an
            // identifier to the lexer — and the formatter then rendered that
            // as `def(1)`, which the parser rejects. So `format` turned valid
            // source into source that does not parse: corruption, not a style
            // choice, and silent until a round-trip property looked.
            //
            // Rejecting here rather than teaching the formatter to quote it
            // fixes the class instead of the symptom: `x.if`, `x.end` and
            // `x.case` all lower onto special forms the same way, and none of
            // them is a method anyone meant to call.
            TokenKind::Ident(n) if is_reserved_word(&n) => {
                return Err(self.error(format!(
                    "`{n}` is a reserved word and cannot be a method name — \
                     `recv.{n}` would lower onto the `{n}` form itself"
                )))
            }
            TokenKind::Ident(n) => n,
            other => {
                return Err(self.error(format!("expected a method name after `.`, found {other:?}")))
            }
        };
        let mut list = vec![sym_at(name_span, &name), recv];
        if self.at(&TokenKind::LParen) {
            list.extend(self.paren_args()?);
        }
        Ok(list_at(self.span_since(start), list))
    }

    fn paren_args(&mut self) -> Result<Vec<Spanned>, ParseError> {
        self.expect(&TokenKind::LParen, "`(`")?;
        let mut args = Vec::new();
        self.skip_newlines();
        if self.eat(&TokenKind::RParen) {
            return Ok(args);
        }
        loop {
            self.skip_newlines();
            args.push(self.expr(0)?);
            self.skip_newlines();
            if self.eat(&TokenKind::Comma) {
                continue;
            }
            self.expect(&TokenKind::RParen, "`,` or `)`")?;
            break;
        }
        Ok(args)
    }

    fn list_literal(&mut self, open: Span) -> Result<Spanned, ParseError> {
        let mut items = vec![sym_at(open, "list")];
        self.skip_newlines();
        if self.eat(&TokenKind::RBracket) {
            return Ok(list_at(self.span_since(open.start), items));
        }
        loop {
            self.skip_newlines();
            items.push(self.expr(0)?);
            self.skip_newlines();
            if self.eat(&TokenKind::Comma) {
                continue;
            }
            self.expect(&TokenKind::RBracket, "`,` or `]`")?;
            break;
        }
        Ok(list_at(self.span_since(open.start), items))
    }

    /// `{a: 1, "k" => v}` — both spellings, one tree.
    ///
    /// This is §V.13's rendering law at the parser: `a: 1` and `:a => 1`
    /// produce the *same* s-expression, which is precisely why the
    /// formatter may always choose the shorthand. The rocket survives only
    /// where the key is not a plain symbol.
    fn map_literal(&mut self, open: Span) -> Result<Spanned, ParseError> {
        let mut items = vec![sym_at(open, LOWERED_MAP)];
        self.skip_newlines();
        if self.eat(&TokenKind::RBrace) {
            return Ok(list_at(self.span_since(open.start), items));
        }
        loop {
            self.skip_newlines();
            match self.peek().clone() {
                TokenKind::Label(name) => {
                    let label_span = self.peek_span();
                    self.bump();
                    self.skip_newlines();
                    items.push(atom_at(label_span, Atom::Keyword(name)));
                    items.push(self.expr(0)?);
                }
                _ => {
                    let k = self.expr(0)?;
                    self.skip_newlines();
                    self.expect(&TokenKind::Rocket, "`=>` in a map literal")?;
                    self.skip_newlines();
                    items.push(k);
                    items.push(self.expr(0)?);
                }
            }
            self.skip_newlines();
            if self.eat(&TokenKind::Comma) {
                continue;
            }
            self.expect(&TokenKind::RBrace, "`,` or `}`")?;
            break;
        }
        Ok(list_at(self.span_since(open.start), items))
    }

    /// `if c ... [else ...] end`, and `unless` as its negation.
    ///
    /// `unless` lowers to `(if (not c) ...)` rather than to a distinct
    /// form: one tree per meaning, so the formatter and every downstream
    /// tool see exactly one shape.
    /// An `elsif` arm: an `if` that does NOT consume the closing `end`.
    ///
    /// `if / elsif / elsif / else / end` is one `end` for the whole chain, so
    /// every arm but the first must leave it for its parent.
    fn if_chain(&mut self, head: Span) -> Result<Spanned, ParseError> {
        let cond = self.expr(0)?;
        let then = self.body(&["elsif", "else", "end"])?;
        let els = if self.at_ident("elsif") {
            let elsif = self.peek_span();
            self.bump();
            Some(self.if_chain(elsif)?)
        } else if self.at_ident("else") {
            self.bump();
            let e = self.body(&["end"])?;
            self.expect_ident("end")?;
            Some(e)
        } else {
            self.expect_ident("end")?;
            None
        };
        let mut out = vec![sym_at(head, "if"), cond, then];
        if let Some(e) = els {
            out.push(e);
        }
        Ok(list_at(self.span_since(head.start), out))
    }

    fn if_form(&mut self, head: Span, negate: bool) -> Result<Spanned, ParseError> {
        let cond = self.expr(0)?;
        let cond = if negate {
            // `unless c` lowers to `(if (not c) …)`. The synthesized `not` takes
            // the `unless` keyword's span — that word is what put it there.
            let inner = cond.span;
            list_at(head.merge(inner), vec![sym_at(head, "not"), cond])
        } else {
            cond
        };
        // `elsif` terminates the then-body too, or the chain is swallowed.
        //
        // It used to be absent entirely — not a keyword, not reserved, nowhere
        // in this file — so `elsif cond` parsed as a stray expression inside
        // the then-body and the branch it guarded VANISHED. No error: the
        // program ran and returned the `else` value. Measured:
        //
        //   if a < 1 then 1 elsif a < 5 then 2 else 3 end   with a = 3
        //     wanted 2, returned 3
        //
        // A silent wrong answer in the most-used control form in the language,
        // reachable by writing the Ruby every blue user already knows.
        let then = self.body(&["elsif", "else", "end"])?;
        let els = if self.at_ident("elsif") {
            let elsif = self.peek_span();
            self.bump();
            // The chain shares ONE `end`, so recurse without consuming it and
            // let the outermost `if` close the whole thing.
            Some(self.if_chain(elsif)?)
        } else if self.at_ident("else") {
            self.bump();
            let e = self.body(&["end"])?;
            self.expect_ident("end")?;
            Some(e)
        } else {
            self.expect_ident("end")?;
            None
        };
        let mut out = vec![sym_at(head, "if"), cond, then];
        if let Some(e) = els {
            out.push(e);
        }
        Ok(list_at(self.span_since(head.start), out))
    }

    /// `def name(a, b) ... end`            => `(define (name a b) body)`
    /// `def name(a: T, b: T) -> R ... end`  => `(define-typed (name (a T) (b T)) R body)`
    ///
    /// **The two shapes are deliberately different heads.** §0 says an
    /// unannotated program gets ZERO analysis, and the cleanest way to
    /// mean that is for untyped code not to reach the typing machinery at
    /// all — not to reach it and be waved through. A checker that must
    /// walk every node to discover there is nothing to check has already
    /// paid the cost the ladder exists to avoid.
    ///
    /// Annotations are per-parameter, so a signature may be partially
    /// annotated. That is the ladder at its finest grain: `a: Int` is
    /// checked and a bare `b` stays `dyn`, in the same signature.
    /// `case subject / when a / … / else / … / end` => a `cond` over equality.
    ///
    /// **Value matching, not destructuring.** Elixir's `case` binds pattern
    /// variables; blue's compares with the same `equal?` the `==` operator uses,
    /// so `when [1, 2]` matches a list by value. Destructuring needs a pattern
    /// language and a binder, which blue does not have — and a `case` that
    /// *looked* like Elixir's while silently only comparing would be worse than
    /// one that plainly compares.
    ///
    /// The subject is evaluated ONCE, into a binding, so `case expensive()` does
    /// not re-run per arm. That is a correctness property, not an optimisation:
    /// a subject with a side effect would fire once per `when`.
    fn case_form(&mut self, head: Span) -> Result<Spanned, ParseError> {
        let subject = self.expr(0)?;
        self.skip_newlines();

        // A fresh name the surface cannot spell, so it cannot capture a user
        // binding of the same name.
        let subject_var = "case-subject";
        let mut arms: Vec<Spanned> = Vec::new();
        let mut otherwise: Option<Spanned> = None;
        // The `else` keyword's own span, so the synthesized `(else body)` clause
        // sits where the author wrote it rather than back at `case`.
        let mut else_kw: Option<Span> = None;

        loop {
            self.skip_newlines();
            if self.at_ident("end") {
                break;
            }
            let maybe_else = self.peek_span();
            if self.eat_ident("else") {
                else_kw = Some(maybe_else);
                otherwise = Some(self.body(&["end"])?);
                continue;
            }
            let when = self.peek_span();
            if !self.eat_ident("when") {
                return Err(self.error(format!(
                    "expected `when`, `else` or `end` in a case, found {:?}",
                    self.peek()
                )));
            }
            self.skip_newlines();
            let pattern = self.expr(0)?;
            let body = self.body(&["when", "else", "end"])?;
            // The synthesized comparison takes the arm's `when` span: that word
            // is what put an `equal?` there, and it is where a reader looks when
            // told an arm cannot match.
            let test = list_at(
                when.merge(pattern.span),
                vec![sym_at(when, "equal?"), sym_at(when, subject_var), pattern],
            );
            arms.push(list_at(when.merge(body.span), vec![test, body]));
        }
        self.expect_ident("end")?;

        if arms.is_empty() && otherwise.is_none() {
            return Err(self.error("a case needs at least one `when` or an `else`".to_string()));
        }

        // A case with no matching arm and no else is NIL, matching Ruby. Elixir
        // raises CaseClauseError; blue follows Ruby because its `if` without an
        // else is already nil, and having two different answers to "no branch
        // taken" in one language is the inconsistency.
        let mut cond = vec![sym_at(head, "cond")];
        cond.extend(arms);
        // The `else` clause spans its own keyword through its body. Anchoring it
        // at `head` — the `case` keyword — put a node whose subtree sits at the
        // END of the form at a span near its START, so the else body escaped its
        // parent's range entirely. `every_node_sits_inside_its_parents_span`
        // caught that; it is the kind of mistake no output-shape test can see,
        // because the tree is correct and only the positions are wrong.
        let else_span = else_kw.unwrap_or(head);
        let else_body = otherwise.unwrap_or_else(|| Spanned::new(else_span, SpannedForm::Nil));
        cond.push(list_at(
            else_span.merge(else_body.span),
            vec![sym_at(else_span, "else"), else_body],
        ));

        let whole = self.span_since(head.start);
        let binding = list_at(
            head.merge(subject.span),
            vec![sym_at(head, subject_var), subject],
        );
        Ok(list_at(
            whole,
            vec![
                sym_at(head, "let"),
                list_at(binding.span, vec![binding]),
                list_at(whole, cond),
            ],
        ))
    }

    /// `fn(a, b) ... end` => `(lambda (a b) body)`
    ///
    /// Without this the higher-order functions are unreachable in practice:
    /// `map(inc, xs)` works only because `inc` happens to be a named stdlib
    /// function, and there was no way to write the one-off the call site
    /// actually wants.
    ///
    /// `fn` rather than Ruby's `->` or `lambda`: `->` collides with the return-
    /// type arrow the typed `def` already uses, and reusing one glyph for two
    /// unrelated things is the ambiguity the FORM axis exists to prevent.
    fn lambda_form(&mut self, head: Span) -> Result<Spanned, ParseError> {
        let mut params: Vec<Spanned> = Vec::new();
        if self.at(&TokenKind::LParen) {
            self.bump();
            self.skip_newlines();
            if !self.eat(&TokenKind::RParen) {
                loop {
                    self.skip_newlines();
                    let p_span = self.peek_span();
                    match self.bump() {
                        TokenKind::Ident(p) => params.push(sym_at(p_span, &p)),
                        other => {
                            return Err(
                                self.error(format!("expected a parameter name, found {other:?}"))
                            )
                        }
                    }
                    self.skip_newlines();
                    if self.eat(&TokenKind::Comma) {
                        continue;
                    }
                    self.expect(&TokenKind::RParen, "`,` or `)`")?;
                    break;
                }
            }
        }
        let params_span = cover(&params, head);
        let body = self.body(&["end"])?;
        self.expect_ident("end")?;
        Ok(list_at(
            self.span_since(head.start),
            vec![sym_at(head, "lambda"), list_at(params_span, params), body],
        ))
    }

    /// `test "name" ... end` => `(deftest "name" body)`
    ///
    /// A string, not an identifier: a test name is prose for a human report,
    /// and forcing it into an identifier is how test names become
    /// `test_adds_two_numbers_correctly`.
    fn test_form(&mut self, head: Span) -> Result<Spanned, ParseError> {
        let name_span = self.peek_span();
        let name = match self.bump() {
            TokenKind::Str(s) => s,
            other => {
                return Err(self.error(format!(
                    "expected a string name after `test`, found {other:?}"
                )))
            }
        };
        let body = self.body(&["end"])?;
        self.expect_ident("end")?;
        Ok(list_at(
            self.span_since(head.start),
            vec![
                sym_at(head, "deftest"),
                atom_at(name_span, Atom::Str(name)),
                body,
            ],
        ))
    }

    /// `assert expr` => `(blue-assert 'expr expr)`
    ///
    /// **`blue-assert`, not `assert`.** tatara-lisp's stdlib already defines
    /// `assert` as a macro — `(defmacro assert (pred message) …)` — and a macro
    /// in the expander is consulted before any primitive in the registry. So
    /// lowering to `assert` bound `pred` to the *quoted form*, which is
    /// truthy, and **every assertion silently passed**. A test framework whose
    /// assertions always pass is the worst defect it can have: every test in
    /// the suite goes green.
    ///
    /// The lesson generalizes: any name blue lowers to that tatara already
    /// binds is silently captured. `blue_lang_test`'s
    /// `no_lowered_name_is_shadowed_by_the_runtime` gates the whole class.
    ///
    /// **Both the form and the value.** A test framework whose failure says
    /// only "assertion failed" makes the author re-derive what they were
    /// checking; one that shows the expression does not. The quoted form is
    /// the expression as DATA, so the runner can render it — and it renders it
    /// through `blue-lang-fmt`, meaning the failure message is in canonical
    /// blue syntax rather than the underlying tatara-lisp.
    ///
    /// This is homoiconicity paying for itself: the capture needs no source
    /// map, no macro hygiene, and no string of the original text.
    fn assert_form(&mut self, head: Span) -> Result<Spanned, ParseError> {
        let e = self.expr(0)?;
        let quoted = Spanned::new(e.span, SpannedForm::Quote(Box::new(e.clone())));
        Ok(list_at(
            self.span_since(head.start),
            vec![sym_at(head, LOWERED_ASSERT), quoted, e],
        ))
    }

    /// `defmacro name(a, b) ... end` => `(defmacro name (a b) body)`
    ///
    /// **Deliberately untyped.** A macro's parameters are *source forms*, not
    /// values, so `a: Int` would be a category error: the argument at expansion
    /// time is a fragment of syntax. §IV's ladder types values; macro
    /// parameters are not on it. Annotating one is rejected rather than
    /// silently ignored — an ignored annotation is how an author comes to
    /// believe a check is running.
    fn defmacro_form(&mut self, head: Span) -> Result<Spanned, ParseError> {
        let name_span = self.peek_span();
        let name = match self.bump() {
            TokenKind::Ident(n) => n,
            other => {
                return Err(self.error(format!("expected a name after `defmacro`, found {other:?}")))
            }
        };
        let mut params: Vec<Spanned> = Vec::new();
        if self.at(&TokenKind::LParen) {
            self.bump();
            self.skip_newlines();
            if !self.eat(&TokenKind::RParen) {
                loop {
                    self.skip_newlines();
                    let p_span = self.peek_span();
                    match self.bump() {
                        TokenKind::Ident(p) => params.push(sym_at(p_span, &p)),
                        TokenKind::Label(p) => {
                            return Err(self.error(format!(
                                "macro parameter `{p}` cannot be typed: a macro receives \
                                 source forms, not values"
                            )))
                        }
                        other => {
                            return Err(
                                self.error(format!("expected a parameter name, found {other:?}"))
                            )
                        }
                    }
                    self.skip_newlines();
                    if self.eat(&TokenKind::Comma) {
                        continue;
                    }
                    self.expect(&TokenKind::RParen, "`,` or `)`")?;
                    break;
                }
            }
        }
        if matches!(self.peek(), TokenKind::Op(o) if o == "->") {
            return Err(self.error(
                "a macro has no return type: it produces source forms, not values".to_string(),
            ));
        }

        let params_span = cover(&params, name_span);
        let body = self.body(&["end"])?;
        self.expect_ident("end")?;

        // `(defmacro name (params) body)` — tatara-lisp's own shape, so blue
        // registers into the SAME expander rather than a parallel one.
        Ok(list_at(
            self.span_since(head.start),
            vec![
                sym_at(head, "defmacro"),
                sym_at(name_span, &name),
                list_at(params_span, params),
                body,
            ],
        ))
    }

    /// `quote ... end` => `` `body `` (a quasiquote).
    ///
    /// Quasiquote rather than plain quote, because a macro body that could not
    /// splice its arguments in would be useless — this is Elixir's `quote do`,
    /// which is likewise a template and not inert data.
    fn quote_form(&mut self, head: Span) -> Result<Spanned, ParseError> {
        let body = self.body(&["end"])?;
        self.expect_ident("end")?;
        // `Sexp::Quasiquote`, NOT `(quasiquote body)` as a list.
        //
        // The list form Displays as the text `(quasiquote …)`, which the
        // tatara-lisp reader reads back as an ordinary list whose head happens
        // to be the symbol `quasiquote` — losing the structure. The evaluator
        // then reached the inner `,x` with no enclosing quasiquote and rejected
        // it: "unquote outside of quasiquote". Building the real variant makes
        // it Display as `` ` `` and survive the round trip.
        Ok(Spanned::new(
            self.span_since(head.start),
            SpannedForm::Quasiquote(Box::new(body)),
        ))
    }

    /// `unquote(expr)` => `,expr`; `unquote_splice(expr)` => `,@expr`.
    fn unquote_form(&mut self, head: Span, splice: bool) -> Result<Spanned, ParseError> {
        self.expect(&TokenKind::LParen, "`(` after unquote")?;
        self.skip_newlines();
        let inner = self.expr(0)?;
        self.skip_newlines();
        self.expect(&TokenKind::RParen, "`)`")?;
        let span = self.span_since(head.start);
        Ok(Spanned::new(
            span,
            if splice {
                SpannedForm::UnquoteSplice(Box::new(inner))
            } else {
                SpannedForm::Unquote(Box::new(inner))
            },
        ))
    }

    fn def_form(&mut self, head: Span) -> Result<Spanned, ParseError> {
        let name_span = self.peek_span();
        let name = match self.bump() {
            TokenKind::Ident(n) => n,
            other => {
                return Err(self.error(format!("expected a name after `def`, found {other:?}")))
            }
        };
        let mut params: Vec<(String, Span, Option<Spanned>)> = Vec::new();
        if self.at(&TokenKind::LParen) {
            self.bump();
            self.skip_newlines();
            if !self.eat(&TokenKind::RParen) {
                loop {
                    self.skip_newlines();
                    let p_span = self.peek_span();
                    match self.bump() {
                        // `a` — unannotated
                        TokenKind::Ident(p) => params.push((p, p_span, None)),
                        // `a:` came through as one token, so a type follows
                        TokenKind::Label(p) => {
                            self.skip_newlines();
                            let ty = self.type_expr()?;
                            params.push((p, p_span, Some(ty)));
                        }
                        other => {
                            return Err(
                                self.error(format!("expected a parameter name, found {other:?}"))
                            )
                        }
                    }
                    self.skip_newlines();
                    if self.eat(&TokenKind::Comma) {
                        continue;
                    }
                    self.expect(&TokenKind::RParen, "`,` or `)`")?;
                    break;
                }
            }
        }
        // The signature list spans the name through the closing `)`.
        let sig_span = self.span_since(name_span.start);

        // Optional `-> R`
        let ret = if matches!(self.peek(), TokenKind::Op(o) if o == "->") {
            self.bump();
            self.skip_newlines();
            Some(self.type_expr()?)
        } else {
            None
        };

        let body = self.body(&["end"])?;
        self.expect_ident("end")?;
        let whole = self.span_since(head.start);

        let annotated = ret.is_some() || params.iter().any(|(_, _, t)| t.is_some());
        if !annotated {
            let mut sig = vec![sym_at(name_span, &name)];
            sig.extend(params.into_iter().map(|(p, s, _)| sym_at(s, &p)));
            return Ok(list_at(
                whole,
                vec![sym_at(head, "define"), list_at(sig_span, sig), body],
            ));
        }

        // Typed shape. An un-annotated parameter in an otherwise annotated
        // signature is written `(p dyn)` so the checker sees the ladder
        // position explicitly rather than inferring it from absence.
        //
        // A `dyn` written by the parser rather than the author takes the
        // parameter's own span, so a diagnostic about it points at the
        // parameter — the only thing in the source it could mean.
        let mut sig = vec![sym_at(name_span, &name)];
        for (p, s, t) in params {
            let ty = t.unwrap_or_else(|| sym_at(s, "dyn"));
            sig.push(list_at(s.merge(ty.span), vec![sym_at(s, &p), ty]));
        }
        Ok(list_at(
            whole,
            vec![
                sym_at(head, "define-typed"),
                list_at(sig_span, sig),
                ret.unwrap_or_else(|| sym_at(head, "dyn")),
                body,
            ],
        ))
    }

    /// A type expression. Currently a bare name (`Int`, `Str`, `dyn`) or a
    /// one-argument constructor (`List(Int)`).
    fn type_expr(&mut self) -> Result<Spanned, ParseError> {
        let name_span = self.peek_span();
        let name = match self.bump() {
            TokenKind::Ident(n) => n,
            other => return Err(self.error(format!("expected a type name, found {other:?}"))),
        };
        if self.at(&TokenKind::LParen) {
            let args = self.paren_args()?;
            let mut list = vec![sym_at(name_span, &name)];
            list.extend(args);
            return Ok(list_at(self.span_since(name_span.start), list));
        }
        Ok(sym_at(name_span, &name))
    }

    /// Consume `name` if it is the next token, else leave the position alone.
    fn eat_ident(&mut self, name: &str) -> bool {
        if self.at_ident(name) {
            self.bump();
            true
        } else {
            false
        }
    }

    fn expect_ident(&mut self, name: &str) -> Result<(), ParseError> {
        if self.at_ident(name) {
            self.bump();
            Ok(())
        } else {
            Err(self.error(format!("expected `{name}`, found {:?}", self.peek())))
        }
    }

    /// A sequence of expressions up to one of `terminators`, wrapped in
    /// `(begin ...)` when there is more than one.
    fn body(&mut self, terminators: &[&str]) -> Result<Spanned, ParseError> {
        // Anchored BEFORE the leading newlines are skipped, so an empty body's
        // span sits where the body would have started.
        let start = self.mark();
        let mut forms = Vec::new();
        loop {
            self.skip_newlines();
            if matches!(self.peek(), TokenKind::Eof) {
                return Err(self.error(format!(
                    "unterminated block: expected one of {terminators:?}"
                )));
            }
            if terminators.iter().any(|t| self.at_ident(t)) {
                break;
            }
            forms.push(self.statement()?);
        }
        Ok(match forms.len() {
            0 => Spanned::new(Span::new(start, start), SpannedForm::Nil),
            1 => forms.into_iter().next().expect("checked len"),
            _ => {
                // `cover`, NOT `span_since`: the loop breaks *before* consuming
                // the terminator but *after* `skip_newlines`, so the last token
                // behind `pos` can be a newline and `span_since` would stretch
                // the body across trailing blank lines. The forms know exactly
                // where they are.
                let span = cover(&forms, Span::new(start, start));
                // The synthesized `begin` is zero-width at the FIRST FORM's
                // start, not at `start`. `start` is anchored before the leading
                // newlines are skipped, so it sits earlier than the body itself
                // — and a head node outside its own list's span is a span bug
                // that `every_node_sits_inside_its_parents_span` reports.
                let head = Span::new(span.start, span.start);
                let mut list = vec![sym_at(head, "begin")];
                list.extend(forms);
                list_at(span, list)
            }
        })
    }
}

/// A symbol node at `span`.
fn sym_at(span: Span, s: &str) -> Spanned {
    Spanned::new(span, SpannedForm::Atom(Atom::Symbol(s.to_string())))
}

/// An atom node at `span`.
fn atom_at(span: Span, a: Atom) -> Spanned {
    Spanned::new(span, SpannedForm::Atom(a))
}

/// A list node at `span`.
fn list_at(span: Span, items: Vec<Spanned>) -> Spanned {
    Spanned::new(span, SpannedForm::List(items))
}

/// The smallest span covering every node in `items`, or `fallback` when there
/// are none.
///
/// The fallback is a parameter rather than `Span::synthetic()` because a
/// synthetic span is a claim that a node has no source origin at all — and an
/// empty parameter list in `def f()` very much has one. Defaulting to synthetic
/// here is how "no span" leaks into a tree where every node does have a place.
fn cover(items: &[Spanned], fallback: Span) -> Span {
    let merged = items
        .iter()
        .fold(Span::synthetic(), |acc, s| acc.merge(s.span));
    if merged.is_synthetic() {
        fallback
    } else {
        merged
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Render an `Sexp` to canonical text so tests can state the expected
    /// quoted form as a string. This is `Display`, which tatara-lisp owns —
    /// blue does not build Lisp syntax by concatenation.
    fn q(src: &str) -> String {
        parse_expr(src)
            .map(|s| s.to_string())
            .unwrap_or_else(|e| panic!("{src:?}: {e}"))
    }

    // ---- the thesis: Ruby-shaped source becomes tatara-lisp ----------

    #[test]
    fn arithmetic_respects_precedence() {
        assert_eq!(q("1 + 2 * 3"), "(+ 1 (* 2 3))");
        assert_eq!(q("(1 + 2) * 3"), "(* (+ 1 2) 3)");
    }

    #[test]
    fn comparison_binds_looser_than_arithmetic() {
        assert_eq!(q("a + 1 < b"), "(< (+ a 1) b)");
    }

    /// The expected tree names `or`/`and`, not `||`/`&&`: the surface
    /// spelling is the SURFACE's, and lowering renames it to the form
    /// tatara-lisp actually has. This test previously asserted the verbatim
    /// spelling, which is how `(== a b)` — a symbol nothing binds — shipped.
    #[test]
    fn logical_operators_bind_loosest_and_lower_to_tataras_names() {
        assert_eq!(q("a && b || c"), "(or (and a b) c)");
    }

    #[test]
    fn left_associativity() {
        assert_eq!(q("1 - 2 - 3"), "(- (- 1 2) 3)");
    }

    /// A bare `recv.name` is a SEND. Blue commits to uniform access here,
    /// so a field can later become a computed method without breaking
    /// callers.
    #[test]
    fn method_call_without_parens_is_a_send() {
        assert_eq!(q("user.name"), "(name user)");
    }

    #[test]
    fn method_call_with_args() {
        assert_eq!(q("user.greet(1, 2)"), "(greet user 1 2)");
    }

    #[test]
    fn chained_sends_read_left_to_right() {
        assert_eq!(q("a.b.c"), "(c (b a))");
    }

    #[test]
    fn plain_call() {
        assert_eq!(q("f(1, 2)"), "(f 1 2)");
    }

    /// The pipeline threads into the FIRST argument, as Elixir's does —
    /// that is what makes `|>` composable rather than decorative.
    #[test]
    fn pipeline_threads_into_first_argument() {
        assert_eq!(q("x |> f"), "(f x)");
        assert_eq!(q("x |> f(1)"), "(f x 1)");
        assert_eq!(q("x |> f |> g"), "(g (f x))");
    }

    #[test]
    fn pipeline_binds_looser_than_arithmetic() {
        assert_eq!(q("1 + 2 |> f"), "(f (+ 1 2))");
    }

    // ---- §V.13's rendering law, enforced at the parser ---------------

    /// `a: 1` and `:a => 1` are the SAME TREE. That is exactly why the
    /// formatter may always render the shorthand: they are not two
    /// spellings of two things, they are two spellings of one thing.
    #[test]
    fn label_and_rocket_produce_the_same_tree_for_a_symbol_key() {
        assert_eq!(q("{a: 1}"), q("{:a => 1}"));
        assert_eq!(q("{a: 1}"), "(hash-map :a 1)");
    }

    /// And where the key is NOT a plain symbol, the rocket is the only
    /// spelling — so it survives because it must, never as a style choice.
    #[test]
    fn a_string_key_has_no_shorthand() {
        assert_eq!(q(r#"{"k" => 1}"#), r#"(hash-map "k" 1)"#);
    }

    #[test]
    fn list_literal() {
        assert_eq!(q("[1, 2, 3]"), "(list 1 2 3)");
        assert_eq!(q("[]"), "(list)");
    }

    // ---- blocks ------------------------------------------------------

    #[test]
    fn if_else_end() {
        assert_eq!(q("if a\n  1\nelse\n  2\nend"), "(if a 1 2)");
    }

    #[test]
    fn if_without_else() {
        assert_eq!(q("if a\n  1\nend"), "(if a 1)");
    }

    /// `unless` lowers to `(if (not c) …)` — one tree per meaning, so
    /// every downstream tool sees exactly one shape.
    #[test]
    fn unless_is_a_negated_if() {
        assert_eq!(q("unless a\n  1\nend"), "(if (not a) 1)");
    }

    #[test]
    fn multi_statement_body_becomes_begin() {
        assert_eq!(q("if a\n  1\n  2\nend"), "(if a (begin 1 2))");
    }

    #[test]
    fn def_lowers_to_define() {
        assert_eq!(
            q("def add(a, b)\n  a + b\nend"),
            "(define (add a b) (+ a b))"
        );
    }

    #[test]
    fn def_with_no_params() {
        assert_eq!(q("def zero()\n  0\nend"), "(define (zero) 0)");
    }

    // ---- literals ----------------------------------------------------

    #[test]
    fn literals_lower_to_atoms() {
        assert_eq!(q("42"), "42");
        assert_eq!(q("true"), "#t");
        assert_eq!(q(":ok"), ":ok");
        assert_eq!(q(r#""hi""#), r#""hi""#);
    }

    #[test]
    fn unary_minus_and_not() {
        assert_eq!(q("-x"), "(- 0 x)");
        assert_eq!(q("!x"), "(not x)");
    }

    // ---- programs and errors -----------------------------------------

    #[test]
    fn a_program_is_a_sequence_of_forms() {
        let forms = parse_program("def f()\n  1\nend\nf()").expect("parse");
        assert_eq!(forms.len(), 2);
        assert_eq!(forms[1].to_string(), "(f)");
    }

    #[test]
    fn unterminated_block_is_an_error_naming_what_was_expected() {
        let e = parse_program("if a\n  1").expect_err("must fail");
        assert!(e.message.contains("unterminated"), "{}", e.message);
    }

    #[test]
    fn a_parse_error_carries_a_span_into_the_source() {
        let src = "1 + )";
        let e = parse_program(src).expect_err("must fail");
        assert!(e.span.start < src.len(), "span {:?} outside source", e.span);
    }

    /// Anti-vacuity: `q` must be able to FAIL. If every input parsed, the
    /// assertions above would be worthless.
    #[test]
    fn the_parser_rejects_garbage() {
        assert!(parse_program("def").is_err());
        assert!(parse_program("(1").is_err());
        assert!(parse_program("end").is_err());
    }
}
