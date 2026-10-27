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
use crate::spelling::{Note, Spelling};

/// Why a source did not parse, and where.
///
/// **Structured, and located at the boundary.** `message` says what was
/// expected and what was found, in blue's own words; `span` is the byte range
/// of the offending text; `line` and `col` are that range's start, 1-based,
/// with the column counted in characters. Every public entry point fills
/// `line`/`col` from the source it was given, so `Display` reads
/// `3:7: expected `)`, found `]`` and never a byte offset.
///
/// The byte offsets used to BE the display (`… at 10..11`), and a Rust
/// `Debug` rendering named the token (`found Ident("y")`). Both are facts
/// about the implementation; neither is something an author can act on.
/// The span stays, as data, for any consumer that needs to point into the
/// buffer — an editor squiggle, a diagnostic code attached downstream.
#[derive(Clone, Debug, PartialEq)]
pub struct ParseError {
    pub message: String,
    pub span: Span,
    /// 1-based line of `span.start`.
    pub line: usize,
    /// 1-based column of `span.start`, in characters.
    pub col: usize,
}

impl ParseError {
    /// An error at `span`, not yet located: the parser sees tokens, not text,
    /// so the line and column are filled by [`Self::located`] at the entry
    /// point that holds the source.
    pub(crate) fn new(message: impl Into<String>, span: Span) -> Self {
        Self {
            message: message.into(),
            span,
            line: 0,
            col: 0,
        }
    }

    /// Resolve `line`/`col` against the source this error's span indexes.
    pub(crate) fn located(mut self, src: &str) -> Self {
        let (line, col) = Span::line_col(src, self.span.start.min(src.len()));
        self.line = line;
        self.col = col;
        self
    }
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}: {}", self.line, self.col, self.message)
    }
}

impl std::error::Error for ParseError {}

impl From<crate::lex::LexError> for ParseError {
    fn from(e: crate::lex::LexError) -> Self {
        Self::new(e.message, e.span)
    }
}

thread_local! {
    static PARSES: std::cell::Cell<u64> = const { std::cell::Cell::new(0) };
}

/// How many programs this thread has parsed: an independent count for a
/// caller that promises to parse a text once, read off the parser itself
/// rather than off the caller's own bookkeeping.
#[must_use]
pub fn parses_on_this_thread() -> u64 {
    PARSES.with(std::cell::Cell::get)
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
    parse_program_documented_with_depth(src, max_depth).map(crate::doc::strip)
}

/// Parse keeping the documentation nodes `@doc` and `@moduledoc` lower to
/// ([`crate::doc`]). Every other `parse_program*` door strips them.
pub fn parse_program_documented(src: &str) -> Result<Vec<Spanned>, ParseError> {
    parse_program_documented_with_depth(src, MAX_EXPR_DEPTH)
}

/// [`parse_program_documented`] with the nesting bound supplied by the caller.
pub fn parse_program_documented_with_depth(
    src: &str,
    max_depth: usize,
) -> Result<Vec<Spanned>, ParseError> {
    if let Some(hit) = RECENT.with(|r| {
        r.borrow()
            .iter()
            .find(|(d, s, _)| *d == max_depth && s.as_str() == src)
            .map(|(_, _, t)| t.clone())
    }) {
        return hit;
    }
    PARSES.with(|n| n.set(n.get() + 1));
    let parsed = lex(src)
        .map_err(|e| ParseError::from(e).located(src))
        .and_then(|toks| {
            Parser::over(src, toks, max_depth)
                .program()
                .map_err(|e| e.located(src))
        });
    RECENT.with(|r| {
        let mut r = r.borrow_mut();
        if r.len() == RECENT_TEXTS {
            drop(r.remove(0));
        }
        r.push((max_depth, src.to_string(), parsed.clone()));
    });
    parsed
}

/// A doc example's expression or statement: part of its text's parse, so
/// neither counted nor kept apart from it.
pub(crate) fn parse_snippet(src: &str) -> Result<Vec<Spanned>, ParseError> {
    let toks = lex(src).map_err(|e| ParseError::from(e).located(src))?;
    Parser::over(src, toks, MAX_EXPR_DEPTH)
        .program()
        .map(crate::doc::strip)
        .map_err(|e| e.located(src))
}

/// How many recent texts each thread keeps the parse of. One text is read
/// by several views in one check (the stripped tree, its documentation, its
/// doctests, the doc rules); they share one parse.
const RECENT_TEXTS: usize = 4;

type Recent = Vec<(usize, String, Result<Vec<Spanned>, ParseError>)>;

thread_local! {
    static RECENT: std::cell::RefCell<Recent> = const { std::cell::RefCell::new(Vec::new()) };
}

/// The text a constant string form spells, for a reader that takes text from
/// a tree without evaluating it: a string, `line_break`, or `join_lines([…])` /
/// `unlines([…])` over constant texts, which is how the parser reads a string
/// holding a line break (B0065). `None` for anything computed.
#[must_use]
pub fn constant_text(s: &Sexp) -> Option<String> {
    match s {
        Sexp::Atom(Atom::Str(x)) => Some(x.to_string()),
        Sexp::Atom(Atom::Symbol(h)) if h.as_str() == "line_break" => Some("\n".to_string()),
        Sexp::List(items) => match items.as_slice() {
            [Sexp::Atom(Atom::Symbol(h)), Sexp::List(list)]
                if h.as_str() == "join_lines" || h.as_str() == "unlines" =>
            {
                let (Sexp::Atom(Atom::Symbol(l)), elems) = list.split_first()? else {
                    return None;
                };
                if l.as_str() != "list" {
                    return None;
                }
                let texts = elems.iter().map(constant_text).collect::<Option<Vec<_>>>()?;
                Some(if h.as_str() == "join_lines" {
                    texts.join("\n")
                } else {
                    texts.iter().map(|t| format!("{t}\n")).collect()
                })
            }
            _ => None,
        },
        _ => None,
    }
}

pub fn spelling_notes(src: &str) -> Result<Vec<Note>, ParseError> {
    let mut p = Parser::over(
        src,
        lex(src).map_err(|e| ParseError::from(e).located(src))?,
        MAX_EXPR_DEPTH,
    );
    p.program().map_err(|e| e.located(src))?;
    Ok(p.notes)
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
    let toks =
        crate::yakugo::canonical_tokens(src, pack).map_err(|e| ParseError::from(e).located(src))?;
    PARSES.with(|n| n.set(n.get() + 1));
    let mut p = Parser::over(src, toks, MAX_EXPR_DEPTH);
    p.program()
        .map(crate::doc::strip)
        .map_err(|e| e.located(src))
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
        .is_some_and(|prefix| {
            prefix
                .trim_matches(|c: char| c.is_whitespace() || c == '\u{feff}')
                .is_empty()
        })
}

/// Parse a single blue expression. Convenience for tests and the REPL.
pub fn parse_expr(src: &str) -> Result<Sexp, ParseError> {
    let forms = parse_program(src)?;
    match forms.len() {
        1 => Ok(forms.into_iter().next().expect("checked len")),
        n => Err(ParseError::new(
            format!("expected exactly one expression, found {n}"),
            Span::new(0, src.len()),
        )
        .located(src)),
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
    /// One line for a reader: what the operator computes, and the trap in it
    /// when there is one. `blue reference` prints it; a row without one fails
    /// `every_operator_and_keyword_is_described`.
    pub doc: &'static str,
}

/// The complete infix table. Precedence follows Ruby's where Ruby has an
/// opinion; `|>` (below) sits under everything so `a |> f |> g` chains
/// without parentheses.
pub const INFIX: &[Infix] = &[
    Infix {
        op: "or",
        power: (1, 2),
        callee: "or",
        doc: "Logical or: the left value if truthy, otherwise the right; the right is evaluated only when needed. `||` is read as `or` and written `or` (B0025).",
    },
    Infix {
        op: "and",
        power: (3, 4),
        callee: "and",
        doc: "Logical and: the right value if the left is truthy, otherwise the left; short-circuits. `&&` is read as `and` and written `and` (B0025).",
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
        doc: "Structural equality over every value (okite D0001): 4 == 4.0, lists and maps by content, nil only equals nil.",
    },
    Infix {
        op: "!=",
        power: (5, 6),
        callee: "not=",
        doc: "Exactly not(a == b) (okite D0002).",
    },
    Infix {
        op: "<",
        power: (5, 6),
        callee: "<",
        doc: "Numeric less-than. A string operand is a type error: order text with compare(a, b).",
    },
    Infix {
        op: "<=",
        power: (5, 6),
        callee: "<=",
        doc: "Numeric less-than-or-equal. Numbers only, like <.",
    },
    Infix {
        op: ">",
        power: (5, 6),
        callee: ">",
        doc: "Numeric greater-than. Numbers only, like <.",
    },
    Infix {
        op: ">=",
        power: (5, 6),
        callee: ">=",
        doc: "Numeric greater-than-or-equal. Numbers only, like <.",
    },
    Infix {
        op: "+",
        power: (7, 8),
        callee: "+",
        doc: "Numeric addition; an Int and a Float give a Float. Not string concatenation: interpolate instead.",
    },
    Infix {
        op: "-",
        power: (7, 8),
        callee: "-",
        doc: "Numeric subtraction. Written before an operand with nothing on its left, it is unary minus: -n.",
    },
    Infix {
        op: "*",
        power: (9, 10),
        callee: "*",
        doc: "Numeric multiplication.",
    },
    Infix {
        op: "/",
        power: (9, 10),
        callee: "/",
        doc: "Division that never truncates (okite D0008): 7 / 2 is 3.5, while 6 / 2 stays the Int 3. Integer division is floor(a / b).",
    },
    Infix {
        op: "%",
        power: (9, 10),
        callee: "mod",
        doc: "Euclidean remainder: never negative, so (0 - 7) % 3 is 2, not -1. A zero divisor is a runtime error.",
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
/// The master verbs a bare call dispatches on the subject's space.
pub const MASTER_VERBS: &[&str] = &[
    "read", "need", "has?", "put", "update", "delete", "create", "diff", "info", "exists?",
];

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

pub const OPTIONAL_MARKER: &str = "&optional";

pub const LOWERED_OPTIONAL_ARITY: &str = "blue-optional-arity";

pub const LOWERED_OPTIONAL_ARG: &str = "blue-optional-arg";

pub const LOWERED_FIELD: &str = "blue-field";

pub const LOWERED_MERGE: &str = "blue-merge";

pub const LOWERED_SPLICE: &str = "blue-splice";

pub const LOWERED_KWARGS: &str = "blue-kwargs";

pub const LOWERED_ERROR_MATCH: &str = "blue-rescues?";

pub const LOWERED_ENSURE: &str = "blue-ensure";

pub const LOWERED_RERAISE: &str = "blue-reraise";

pub const LOWERED_ATTEMPTED: &str = "blue-attempted";

pub const LOWERED_FAILED: &str = "blue-failed";

pub const LOWERED_HEADS: &[&str] = &[
    "list", "concat", "not", "apply", "equal?", "not=", "and", "or", "mod", "join_lines", "unlines",
    "line_break",
];

pub const RESCUED: &str = "rescued-error";

pub const SURFACE_KEYWORDS: &[&str] = &[
    "if",
    "begin",
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
pub const BLOCK_KEYWORDS: &[&str] = &[
    "do", "end", "else", "elsif", "rescue", "ensure", "true", "false", "nil",
];

pub const OPERATOR_KEYWORDS: &[&str] = &["and", "or", "not"];

/// A surface keyword may not be rebound. `if = 1` is a mistake, not a binding,
/// and letting it through would shadow the form for the rest of the file.
///
/// Public because it is the ONE answer to "is this identifier a keyword" —
/// the parser's rebinding check and every downstream highlighter read it here
/// rather than each carrying its own copy of the list.
pub fn is_reserved_word(name: &str) -> bool {
    SURFACE_KEYWORDS.contains(&name)
        || BLOCK_KEYWORDS.contains(&name)
        || OPERATOR_KEYWORDS.contains(&name)
}

/// Can `name` be written as the head of a call — `name(…)`?
///
/// True exactly when the lexer reads `name` as one identifier and it is not
/// reserved. Answered BY the lexer rather than by a character class copied
/// from it, so the two cannot disagree: the formatter asks this before
/// printing a tree as `name(args)`, and a head such as `hash-map`, `not=` or
/// `if` — which a tree can carry and a call cannot spell — must get a
/// different rendering or none.
pub fn is_callable_name(name: &str) -> bool {
    // `retsu/first` is written `retsu::first(…)`.
    if qualified(name).is_some() {
        return true;
    }
    !is_reserved_word(name)
        && matches!(
            lex(name).as_deref(),
            Ok([t, e]) if matches!(&t.kind, TokenKind::Ident(n) if n == name)
                && e.kind == TokenKind::Eof
        )
}

/// The character a qualified name's AST symbol joins its two halves with:
/// `retsu::first` is the symbol `retsu/first`. The surface never writes it
/// (`/` is division, and no identifier can contain it), which is what makes
/// a symbol with text on both sides of one `/` unambiguously qualified.
pub const QUALIFIER: char = '/';

/// The qualifier that names a builtin: `blue::count` is the interpreter's
/// `count`, whatever a program defines. No package may be named it.
pub const BUILTIN_QUALIFIER: &str = "blue";

/// The AST symbol for `pkg::name`.
#[must_use]
pub fn qualify(pkg: &str, name: &str) -> String {
    format!("{pkg}{QUALIFIER}{name}")
}

/// `retsu/first` → `Some(("retsu", "first"))`: the package and the name of a
/// qualified symbol. `None` for every other symbol, `/` (division) included.
///
/// The ONE reader of the shape, so the formatter, the name table and the
/// runtime's renderer cannot disagree about what counts as qualified.
#[must_use]
pub fn qualified(sym: &str) -> Option<(&str, &str)> {
    let (pkg, name) = sym.split_once(QUALIFIER)?;
    let ident = |s: &str| {
        matches!(
            lex(s).as_deref(),
            Ok([t, e]) if matches!(&t.kind, TokenKind::Ident(n) if n == s) && e.kind == TokenKind::Eof
        )
    };
    let named = |s: &str| ident(s) || matches!(s, "true" | "false" | "nil");
    (ident(pkg) && !is_reserved_word(pkg) && named(name)).then_some((pkg, name))
}

/// One line for a reader on each reserved word: what it writes, and the shape.
///
/// Beside the two tables rather than inside them, because both are `&[&str]`
/// read by the formatter's corpus gate and by highlighters outside this repo;
/// changing their type would break every one of those readers.
/// `every_operator_and_keyword_is_described` makes a word without a line here a
/// red build, so the omission cannot ship. `blue reference` prints these.
#[must_use]
pub fn keyword_doc(word: &str) -> &'static str {
    match word {
        "if" => "`if c … elsif d … else … end`: an expression; its value is the branch taken, nil when none is. An `else` that is empty or `nil` is dropped (B0035).",
        "unless" => "`unless c … end` is read as `if not c` and written that way (B0026).",
        "begin" => "`begin … rescue :kind as e … rescue e … ensure … end`: run the statements; a `rescue` clause catches an error by kind, binding it with `as`, and `rescue e` catches every error; `ensure` always runs. A def body takes the same clauses without `begin`.",
        "rescue" => "A clause of `begin` or `def`: `rescue :a, :b as e`, `rescue e` (every error, last). Inline, `x rescue fallback` is fallback when x raises; it binds loosest, below `|>`.",
        "ensure" => "The last clause of `begin` or `def`: statements that run whether the block returned or raised; the block's value or error is kept.",
        "and" => "`a and b`: logical and; `&&` is read as `and` and written `and` (B0025).",
        "or" => "`a or b`: logical or; `||` is read as `or` and written `or` (B0025).",
        "not" => "`not x`: true when x is false or nil; `!x` is read as `not x` and written `not x` (B0025). `not (a == b)` is written `a != b` (B0034).",
        "def" => "`def name(a, b) … end`: a named function; its value is the last expression. Parameters may be typed: `def f(n: Int) -> Int`.",
        "defmacro" => "`defmacro name(x) quote … unquote(x) … end end`: a macro, a rewrite of the unevaluated form.",
        "quote" => "`quote … end`: the form itself as data, not its value. Used inside `defmacro`.",
        "unquote" => "`unquote(x)`: inside `quote`, splice in the value of `x`.",
        "unquote_splice" => "`unquote_splice(xs)`: inside `quote`, splice the items of the form `xs` in place, not the form itself.",
        "test" => "`test \"what must hold\" … end`: a test block, run by `blue test` and ignored by `blue run`.",
        "assert" => "`assert expr`: inside a test, fail it unless `expr` is truthy; the failure quotes the expression.",
        "fn" => "`fn(x) x * 2 end`: an anonymous function, a value. Blue has no brace or do blocks.",
        "case" => "`case v when 1 … when 2 … else … end`: compares with `==`; it does not destructure.",
        "do" => "Reserved and refused: blue has no do-blocks. Pass `fn(x) … end` instead.",
        "end" => "Closes `def`, `defmacro`, `if`, `case`, `fn`, `test` and `quote`.",
        "else" => "The branch of `if` or `case` taken when nothing before it matched.",
        "elsif" => "A further condition in an `if` chain; an `else` holding only an `if` is written `elsif` (B0027).",
        "true" => "The boolean true.",
        "false" => "The boolean false. Only `false` and `nil` are falsy; 0, \"\" and [] are truthy.",
        "nil" => "The absent value. It is not `[]` (okite D0004), and only `nil == nil`.",
        _ => "",
    }
}

fn infix(op: &str) -> Option<&'static Infix> {
    INFIX.iter().find(|i| i.op == op)
}

pub const SYMBOL_SPELLINGS: &[(&str, &str)] = &[("&&", "and"), ("||", "or"), ("!", "not")];

fn word_for(op: &str) -> &str {
    SYMBOL_SPELLINGS
        .iter()
        .find(|(sym, _)| *sym == op)
        .map_or(op, |(_, word)| word)
}

fn infix_of(kind: &TokenKind) -> Option<&'static Infix> {
    match kind {
        TokenKind::Op(o) => infix(word_for(o)),
        TokenKind::Ident(w) if w == "and" || w == "or" => infix(w),
        _ => None,
    }
}

const PIPE_POWER: (u8, u8) = (0, 1);
const RESCUE_POWER: (u8, u8) = (0, 1);

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
    src: String,
    comment_spans: Vec<Span>,
    notes: Vec<Note>,
    /// How many `quote` bodies enclose the parser: a string inside one is
    /// data, so its `\n` is kept as written rather than lowered (B0065).
    quoting: usize,
}

/// Maximum expression nesting before the parser refuses.
///
/// Chosen well above anything human-written (blue's own `spec/*.b` peaks in
/// single digits) and far below the measured overflow point, so the bound is
/// hit as a typed `Err` long before the stack is at risk. A limit that is
/// merely *near* the crash point is not a safety bound; it is a race.
pub const MAX_EXPR_DEPTH: usize = 256;

/// The parser's internal error: a [`ParseError`] behind a pointer.
///
/// Every production returns a `Result`, and a debug build keeps several per
/// frame down the recursion, so the error's size is paid at every level of
/// nesting whether or not anything fails. Measured 2026-09-29 on a 2 MiB
/// debug thread, parsing `(((…1…)))` with no bound: the unboxed 40-byte error
/// overflowed between 255 and 260 levels, barely past [`MAX_EXPR_DEPTH`];
/// adding `line`/`col` unboxed moved it to 240–250, under the bound, and
/// `depth_beyond_the_limit_is_an_err_not_an_abort` aborted. Boxed, the
/// overflow is between 300 and 310. The error path is cold; the pointer is
/// what keeps the bound a bound.
type Fail = Box<ParseError>;

fn fail(message: impl Into<String>, span: Span) -> Fail {
    Box::new(ParseError::new(message, span))
}

impl Parser {
    fn over(src: &str, all: Vec<Token>, max_depth: usize) -> Self {
        let comment_spans = all
            .iter()
            .filter(|t| matches!(t.kind, TokenKind::Comment(_)))
            .map(|t| t.span)
            .collect();
        let toks = all
            .into_iter()
            .filter(|t| !matches!(t.kind, TokenKind::Comment(_)))
            .collect();
        Parser {
            toks,
            pos: 0,
            depth: 0,
            max_depth,
            src: src.to_string(),
            comment_spans,
            notes: Vec::new(),
            quoting: 0,
        }
    }

    fn note(&mut self, spelling: Spelling, span: Span, written: &str, canonical: &str) {
        self.notes.push(Note {
            spelling,
            span,
            written: written.to_string(),
            canonical: canonical.to_string(),
        });
    }

    fn text(&self, span: Span) -> &str {
        self.src.get(span.start..span.end).unwrap_or("")
    }

    fn comment_within(&self, lo: usize, hi: usize) -> bool {
        self.comment_spans
            .iter()
            .any(|c| c.start >= lo && c.start < hi)
    }

    fn touches_previous(&self) -> bool {
        let here = self.peek_span();
        self.toks
            .get(self.pos.wrapping_sub(1))
            .is_some_and(|prev| prev.span.end == here.start)
    }

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

    fn expect(&mut self, k: &TokenKind, what: &str) -> Result<(), Fail> {
        if self.eat(k) {
            Ok(())
        } else {
            Err(self.error(format!("expected {what}, found {}", self.peek())))
        }
    }

    fn error(&self, message: impl Into<String>) -> Fail {
        fail(message, self.peek_span())
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

    fn program(&mut self) -> Result<Vec<Spanned>, Fail> {
        let mut out = Vec::new();
        loop {
            self.skip_newlines();
            if matches!(self.peek(), TokenKind::Eof) {
                break;
            }
            if let TokenKind::Doc { module, text } = self.peek().clone() {
                out.push(self.documentation(module, text, out.is_empty())?);
                continue;
            }
            out.push(self.statement()?);
            self.end_of_statement(&[])?;
        }
        Ok(out)
    }

    /// `@moduledoc """…"""` as the first form, or `@doc """…"""` over the
    /// definition it documents ([`crate::doc`]).
    fn documentation(&mut self, module: bool, text: String, first: bool) -> Result<Spanned, Fail> {
        let span = self.peek_span();
        self.bump();
        let word = if module { "@moduledoc" } else { "@doc" };
        let head = sym_at(
            Span::new(span.start, span.start + word.len()),
            if module {
                crate::doc::MODULEDOC_HEAD
            } else {
                crate::doc::DOC_HEAD
            },
        );
        let text = crate::doc::text_node(span, text);
        self.end_of_statement(&[])?;
        if module {
            if !first {
                return Err(fail(
                    "`@moduledoc` is the first form of a file: it documents the whole file",
                    span,
                ));
            }
            return Ok(list_at(span, vec![head, text]));
        }
        self.skip_newlines();
        if matches!(self.peek(), TokenKind::Doc { .. } | TokenKind::Eof) {
            return Err(fail(
                "`@doc` documents the definition below it, and none follows",
                span,
            ));
        }
        let def = self.statement()?;
        self.end_of_statement(&[])?;
        if !crate::doc::is_definition(&def) {
            return Err(fail(
                "`@doc` documents the definition below it: a `def`, a `defmacro` or a \
                 top-level `name = value`",
                span,
            ));
        }
        Ok(list_at(
            Span::new(span.start, def.span.end),
            vec![head, text, def],
        ))
    }

    /// **A statement ends at the end of its line.** Refuse anything else.
    ///
    /// The lexer has always said newlines "are statement separators", and the
    /// parser never asked for one: `program` and `body` looped over
    /// `statement()` and started the next one wherever the last stopped. So a
    /// form blue does not have became two forms it does, silently —
    /// `y = xs[0]` parsed as `y = xs` then the list `[0]`, and Ruby's
    /// `a = f x` as `a = f` then `x`. Both ran; both bound the wrong value.
    ///
    /// **Refused rather than given a meaning**, because each would be a second
    /// spelling of a tree blue already spells one way (§0's FORM axis):
    /// indexing is the call `nth(i, xs)`, and a call has parentheses. `;` is
    /// refused by the lexer for the same reason — one separator, the newline.
    ///
    /// What may follow a statement: a newline, the end of the file, or — in a
    /// body — the keyword that closes it, which is what keeps
    /// `fn(x) x + 1 end` a one-line lambda.
    fn end_of_statement(&self, terminators: &[&str]) -> Result<(), Fail> {
        let next = self.peek();
        if matches!(next, TokenKind::Newline | TokenKind::Eof)
            || terminators.iter().any(|t| self.at_ident(t))
        {
            return Ok(());
        }
        let prev = self.toks.get(self.pos.wrapping_sub(1)).map(|t| &t.kind);
        let prev_name = match prev {
            Some(TokenKind::Ident(n)) => Some(n.as_str()),
            _ => None,
        };
        let callee = prev_name.unwrap_or("f");
        let why = match (prev, next) {
            (Some(TokenKind::Ident(t)), _) if t == "then" => {
                "blue's `if` has no `then`: put the branch on the next line".to_string()
            }
            (_, TokenKind::Ident(d)) if d == "do" => "blue has no `do` blocks: pass a function \
                 as an argument, `f(xs, fn(x) … end)`"
                .to_string(),
            (_, TokenKind::LBracket) => {
                let index = match (self.toks.get(self.pos + 1), self.toks.get(self.pos + 2)) {
                    (Some(i), Some(close)) if close.kind == TokenKind::RBracket => match &i.kind {
                        TokenKind::Int(n) => n.to_string(),
                        TokenKind::Ident(n) => n.clone(),
                        _ => "i".to_string(),
                    },
                    _ => "i".to_string(),
                };
                let list = prev_name.unwrap_or("xs");
                format!(
                    "blue has no `xs[i]` indexing: write `nth({index}, {list})` \
                     (or `first({list})`, `last({list})`)"
                )
            }
            (_, TokenKind::LBrace) => "blue has no brace blocks: pass a function as an \
                 argument, `map(xs, fn(x) … end)`"
                .to_string(),
            (
                Some(TokenKind::Ident(_)),
                TokenKind::Ident(_)
                | TokenKind::Int(_)
                | TokenKind::Float(_)
                | TokenKind::Str(_)
                | TokenKind::InterpolatedStr { .. }
                | TokenKind::Sym(_)
                | TokenKind::True
                | TokenKind::False
                | TokenKind::Nil,
            ) => {
                let arg = match next {
                    TokenKind::Ident(a) => a.clone(),
                    _ => "x".to_string(),
                };
                format!("a call needs parentheses: write `{callee}({arg})`")
            }
            _ => "put each statement on its own line".to_string(),
        };
        Err(self.error(format!("expected the end of the line, found {next}: {why}")))
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
    fn statement(&mut self) -> Result<Spanned, Fail> {
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

    fn statement_inner(&mut self) -> Result<Spanned, Fail> {
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
        let e = self.expr(0)?;
        if let SpannedForm::List(items) = &e.form {
            if items.len() == 3
                && items[0].as_symbol() == Some("define")
                && items[1].as_symbol().is_some()
                && self.text(items[0].span) == "define"
            {
                self.note(Spelling::OperatorSpelling, e.span, "define(x, v)", "x = v");
            }
        }
        Ok(e)
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
    fn expr(&mut self, min_bp: u8) -> Result<Spanned, Fail> {
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

    #[inline(never)]
    fn rescue_node(&self, start: usize, op_span: Span, lhs: Spanned, fallback: Spanned) -> Spanned {
        list_at(
            self.span_since(start),
            vec![
                sym_at(op_span, "try"),
                lhs,
                list_at(
                    op_span.merge(fallback.span),
                    vec![
                        sym_at(op_span, "catch"),
                        list_at(op_span, vec![sym_at(op_span, "_")]),
                        fallback,
                    ],
                ),
            ],
        )
    }

    #[inline(never)]
    fn infix_spelling(&mut self, callee: Option<&str>, op_span: Span) {
        let written = self.text(op_span).to_string();
        match (callee, self.peek().clone()) {
            (None, _) => self.note(Spelling::CallForm, op_span, "|>", "a call"),
            (Some(c), TokenKind::Op(o)) if word_for(&o) != o => {
                self.note(Spelling::LogicalSymbol, op_span, &written, c);
            }
            (Some(_), TokenKind::Op(o)) if written != o => {
                self.note(Spelling::OperatorSpelling, op_span, &written, &o);
            }
            _ => {}
        }
    }

    #[inline(never)]
    fn nil_test(
        &mut self,
        start: usize,
        op_span: Span,
        lhs: &Spanned,
        rhs: &Spanned,
    ) -> Option<Spanned> {
        let (subject, written) = match (&lhs.form, &rhs.form) {
            (_, SpannedForm::Nil) if !matches!(lhs.form, SpannedForm::Nil) => (lhs, "x == nil"),
            (SpannedForm::Nil, _) if !matches!(rhs.form, SpannedForm::Nil) => (rhs, "nil == x"),
            _ => return None,
        };
        let span = self.span_since(start);
        self.note(Spelling::NilTest, span, written, "x.nil?");
        Some(list_at(
            span,
            vec![
                sym_at(op_span, LOWERED_FIELD),
                subject.clone(),
                atom_at(op_span, Atom::Keyword("nil?".to_string())),
            ],
        ))
    }

    #[inline(never)]
    fn infix_node(
        &mut self,
        start: usize,
        callee: Option<&str>,
        op_span: Span,
        lhs: Spanned,
        rhs: Spanned,
    ) -> Spanned {
        if callee == Some("-") && matches!(lhs.form, SpannedForm::Atom(Atom::Int(0))) {
            self.note(
                Spelling::OperatorSpelling,
                lhs.span.merge(op_span),
                "0 - x",
                "-x",
            );
        }

        if callee == Some("equal?") {
            if let Some(test) = self.nil_test(start, op_span, &lhs, &rhs) {
                return test;
            }
        }

        if callee.is_none() {
            // `x |> f`      => (f x)
            // `x |> f(a)`   => (f x a)   — the pipeline threads into
            //                  the FIRST argument position, as Elixir's
            //                  does; that is what makes it composable.
            let rhs_span = rhs.span;
            let threaded = match rhs.form {
                SpannedForm::List(mut items) if !items.is_empty() => {
                    items.insert(1, lhs);
                    list_at(self.span_since(start), items)
                }
                callee => list_at(
                    self.span_since(start),
                    vec![Spanned::new(rhs_span, callee), lhs],
                ),
            };
            match &threaded.form {
                SpannedForm::List(items)
                    if items.len() == 2 && items[0].as_symbol() == Some("not") =>
                {
                    let (head, operand) = (items[0].span, items[1].clone());
                    self.negation(head, threaded.span, operand)
                }
                SpannedForm::List(items)
                    if items.len() == 4
                        && items[0].as_symbol() == Some("if")
                        && matches!(items[3].form, SpannedForm::Nil) =>
                {
                    list_at(threaded.span, items[..3].to_vec())
                }
                SpannedForm::List(items)
                    if items.len() == 3 && items[0].as_symbol() == Some("equal?") =>
                {
                    let (op, a, b) = (items[0].span, items[1].clone(), items[2].clone());
                    match self.nil_test(start, op, &a, &b) {
                        Some(test) => test,
                        None => threaded,
                    }
                }
                _ => threaded,
            }
        } else {
            // The callee symbol takes the OPERATOR's span, not the whole
            // expression's: `a + b` lowers to `(+ a b)` and the `+` node is
            // the one byte-range in the source that means it. Handing it the
            // whole expression's span would make a diagnostic about the
            // operator underline both operands too.
            list_at(
                self.span_since(start),
                vec![sym_at(op_span, callee.unwrap_or_default()), lhs, rhs],
            )
        }
    }

    fn expr_inner(&mut self, min_bp: u8) -> Result<Spanned, Fail> {
        let start = self.mark();
        let mut lhs = self.prefix()?;

        loop {
            // Postfix: `.name`, `.name(args)`, `(args)`
            match self.peek() {
                TokenKind::Dot => {
                    let dot = self.peek_span();
                    self.bump();
                    lhs = self.finish_send(start, lhs, dot)?;
                    continue;
                }
                TokenKind::LParen => {
                    let (args, splat) = self.call_args()?;
                    let call = self.call_node(self.span_since(start), vec![lhs], args, splat);
                    lhs = self.call_spelling(call);
                    continue;
                }
                _ => {}
            }

            // Infix
            // `callee == None` marks the pipeline, which is a rewrite rather
            // than a call.
            let op_span = self.peek_span();
            if self.at_ident("rescue") {
                if RESCUE_POWER.0 < min_bp {
                    break;
                }
                self.bump();
                self.skip_newlines();
                let fallback = self.expr(RESCUE_POWER.1)?;
                lhs = self.rescue_node(start, op_span, lhs, fallback);
                continue;
            }
            let (callee, (lbp, rbp)) = match self.peek() {
                TokenKind::Pipe => (None, PIPE_POWER),
                other => match infix_of(other) {
                    Some(i) => (Some(i.callee), i.power),
                    None => break,
                },
            };
            if lbp < min_bp {
                break;
            }
            self.infix_spelling(callee, op_span);
            self.bump();
            self.skip_newlines();
            let rhs = self.expr(rbp)?;
            lhs = self.infix_node(start, callee, op_span, lhs, rhs);
        }

        Ok(lhs)
    }

    #[inline(never)]
    fn interpolation(span: Span, parts: &[String], exprs: &[String]) -> Result<Spanned, Fail> {
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
            let inner = parse_expr(raw).map_err(|e| {
                fail(
                    format!("in interpolation `#{{{raw}}}`: {}", e.message),
                    span,
                )
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

    /// A string literal holding a `\n` is read as the lines it spells
    /// (B0065): `"a\nb"` is `join_lines(["a", "b"])`, text ending in a newline
    /// is `unlines([…])` without the empty last line, and `"\n"` alone is
    /// `line_break`. A line that is one interpolation, `#{x}`, is `x` itself:
    /// `join_lines` renders each element as interpolation does. So the escape
    /// and the call are one tree, and `blue fmt` writes the call.
    fn lines_literal(
        &mut self,
        span: Span,
        parts: Vec<String>,
        exprs: Vec<String>,
    ) -> Result<Spanned, Fail> {
        let mut lines: Vec<(Vec<String>, Vec<String>)> = vec![(vec![String::new()], Vec::new())];
        for (i, part) in parts.iter().enumerate() {
            let mut pieces = part.split('\n');
            if let Some(head) = pieces.next() {
                if let Some(last) = lines.last_mut().and_then(|l| l.0.last_mut()) {
                    last.push_str(head);
                }
            }
            for piece in pieces {
                lines.push((vec![piece.to_string()], Vec::new()));
            }
            if let Some(raw) = exprs.get(i) {
                if let Some(line) = lines.last_mut() {
                    line.1.push(raw.clone());
                    line.0.push(String::new());
                }
            }
        }
        let empty = |l: &(Vec<String>, Vec<String>)| l.1.is_empty() && l.0 == [""];
        if lines.len() == 2 && lines.iter().all(empty) {
            self.note(Spelling::NewlineEscape, span, "\"\\n\"", "line_break");
            return Ok(sym_at(span, "line_break"));
        }
        let trailing = lines.last().is_some_and(empty);
        if trailing {
            lines.pop();
        }
        let head = if trailing { "unlines" } else { "join_lines" };
        let mut items = vec![sym_at(span, "list")];
        for (lits, raws) in &lines {
            let item = if raws.is_empty() {
                atom_at(span, Atom::Str(lits[0].clone()))
            } else if raws.len() == 1 && lits.iter().all(String::is_empty) {
                let inner = parse_expr(&raws[0]).map_err(|e| {
                    fail(
                        format!("in interpolation `#{{{}}}`: {}", raws[0], e.message),
                        span,
                    )
                })?;
                Spanned::from_sexp_at(&inner, span)
            } else {
                Self::interpolation(span, lits, raws)?
            };
            items.push(item);
        }
        self.note(
            Spelling::NewlineEscape,
            span,
            "\"…\\n…\"",
            &format!("{head}([…])"),
        );
        Ok(list_at(span, vec![sym_at(span, head), list_at(span, items)]))
    }

    #[inline(never)]
    fn not_prefix(&mut self, span: Span) -> Result<Spanned, Fail> {
        if self.at(&TokenKind::LParen) && self.touches_previous() {
            self.note(Spelling::OperatorSpelling, span, "not(x)", "not x");
            let (args, splat) = self.call_args()?;
            if args.len() != 1 || splat.is_some() {
                let call = self.call_node(
                    self.span_since(span.start),
                    vec![sym_at(span, "not")],
                    args,
                    splat,
                );
                return Ok(call);
            }
            let operand = args.into_iter().next().expect("one argument");
            return Ok(self.negation(span, self.span_since(span.start), operand));
        }
        let rhs = self.expr(11)?;
        Ok(self.negation(span, self.span_since(span.start), rhs))
    }

    fn prefix(&mut self) -> Result<Spanned, Fail> {
        if self.at(&TokenKind::LParen) {
            let span = self.peek_span();
            self.bump();
            if self.arrow_lambda_ahead() {
                return self.arrow_lambda(span);
            }
            return self.group();
        }
        self.prefix_token()
    }

    fn group(&mut self) -> Result<Spanned, Fail> {
        self.skip_newlines();
        let inner = self.expr(0)?;
        self.skip_newlines();
        self.expect(&TokenKind::RParen, "`)`")?;
        Ok(inner)
    }

    #[inline(never)]
    fn prefix_token(&mut self) -> Result<Spanned, Fail> {
        let span = self.peek_span();
        match self.bump() {
            TokenKind::Int(v) => Ok(atom_at(span, Atom::Int(v))),
            TokenKind::Float(v) => Ok(atom_at(span, Atom::Float(v))),
            TokenKind::Str(s) if self.quoting == 0 && s.contains('\n') => {
                self.lines_literal(span, vec![s], Vec::new())
            }
            TokenKind::Str(s) => Ok(atom_at(span, Atom::Str(s))),
            TokenKind::Doc { module, .. } => Err(fail(
                format!(
                    "`{}` sits at the top level, above the definition it documents, never \
                     inside a form",
                    if module { "@moduledoc" } else { "@doc" }
                ),
                span,
            )),

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
            TokenKind::InterpolatedStr { parts, exprs }
                if self.quoting == 0 && parts.iter().any(|p| p.contains('\n')) =>
            {
                self.lines_literal(span, parts, exprs)
            }
            TokenKind::InterpolatedStr { parts, exprs } => Self::interpolation(span, &parts, &exprs),
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
                let written = self.text(span).to_string();
                self.note(Spelling::LogicalSymbol, span, &written, "not");
                let rhs = self.expr(11)?;
                Ok(self.negation(span, self.span_since(span.start), rhs))
            }
            TokenKind::Ident(w) if w == "not" => self.not_prefix(span),
            TokenKind::Ident(w) if (w == "and" || w == "or") && self.at(&TokenKind::LParen) => {
                Ok(sym_at(span, &w))
            }
            TokenKind::Ident(w) if w == "and" || w == "or" => Err(fail(
                format!("`{w}` joins two expressions: `a {w} b`"),
                span,
            )),

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

            TokenKind::Ident(name) if self.at(&TokenKind::PathSep) => {
                self.qualified_name(span, &name)
            }
            TokenKind::PathSep => Err(fail(
                "a qualified name is `package::name`, with the package written before `::`",
                span,
            )),
            TokenKind::Ident(name) => match name.as_str() {
                "if" => self.if_form(span, false),
                "begin" if !(self.at(&TokenKind::LParen) && self.touches_previous()) => {
                    self.begin_form(span)
                }
                "rescue" | "ensure" => Err(fail(
                    format!("`{name}` belongs to a `begin … end` block or a `def` body, after the statements it protects"),
                    span,
                )),
                "unless" => {
                    self.note(Spelling::Unless, span, "unless", "if not");
                    self.if_form(span, true)
                }
                "def" => self.def_form(span),
                "defmacro" => self.defmacro_form(span),
                "case" => self.case_form(span),
                "fn" => self.lambda_form(span),
                "test" => self.test_form(span),
                "assert" => self.assert_form(span),
                "quote" => self.quote_form(span),
                "unquote" => self.unquote_form(span, false),
                "unquote_splice" => self.unquote_form(span, true),
                "do" => Err(fail(
                    "blue has no `do` blocks: pass a function as an argument, \
                     `f(xs, fn(x) … end)`",
                    span,
                )),
                "end" => Err(fail(
                    "unexpected `end`: nothing open here for it to close",
                    span,
                )),
                _ => Ok(sym_at(span, &name)),
            },

            other => Err(fail(format!("expected an expression, found {other}"), span)),
        }
    }

    /// After `package`, at `::`: `retsu::first` lowers to the ONE symbol
    /// `retsu/first` — tatara's `require` shape, so a qualified name means the
    /// same thing in both lisps.
    ///
    /// After `::` any identifier is a name, reserved words included:
    /// `kueri::if` names kueri's definition, never the `if` form, because a
    /// reserved word is reserved only where it could start a form. The
    /// package side is never a reserved word, and a name has exactly one
    /// qualifier (`a::b::c` is refused), since a package is one level deep.
    fn qualified_name(&mut self, pkg_span: Span, pkg: &str) -> Result<Spanned, Fail> {
        if is_reserved_word(pkg) {
            return Err(fail(
                format!("`{pkg}` is a reserved word and cannot name a package"),
                pkg_span,
            ));
        }
        self.bump(); // ::
        let name_span = self.peek_span();
        let name = match self.bump() {
            TokenKind::Ident(n) => n,
            // `true`, `false` and `nil` lex as their own tokens.
            TokenKind::True => "true".to_string(),
            TokenKind::False => "false".to_string(),
            TokenKind::Nil => "nil".to_string(),
            other => {
                return Err(fail(
                    format!("expected a name after `{pkg}::`, found {other}"),
                    name_span,
                ))
            }
        };
        if self.at(&TokenKind::PathSep) {
            return Err(self.error(format!(
                "a qualified name has one qualifier: `package::name`, and `{pkg}::{name}::…` has two"
            )));
        }
        Ok(sym_at(
            self.span_since(pkg_span.start),
            &qualify(pkg, &name),
        ))
    }

    /// After a `.`: `recv.name` or `recv.name(args)`.
    ///
    /// **A bare `recv.name` is a SEND, not a field read.** Blue commits to
    /// the uniform access principle here: a structure exposes no public
    /// fields, so a field can later become a computed method without
    /// breaking a caller.
    #[inline(never)]
    fn negation(&mut self, head: Span, whole: Span, operand: Spanned) -> Spanned {
        if let SpannedForm::List(items) = &operand.form {
            let flipped = match items.first().and_then(Spanned::as_symbol) {
                Some("equal?") => Some("not="),
                Some("not=") => Some("equal?"),
                _ => None,
            };
            if let (Some(to), 3) = (flipped, items.len()) {
                let (written, canonical) = if to == "not=" {
                    ("not (a == b)", "a != b")
                } else {
                    ("not (a != b)", "a == b")
                };
                self.note(Spelling::NegatedComparison, whole, written, canonical);
                let mut out = items.clone();
                out[0] = sym_at(items[0].span, to);
                if to == "equal?" {
                    if let Some(test) =
                        self.nil_test(whole.start, items[0].span, &items[1], &items[2])
                    {
                        return test;
                    }
                }
                return list_at(whole, out);
            }
        }
        list_at(whole, vec![sym_at(head, "not"), operand])
    }

    #[inline(never)]
    fn call_spelling(&mut self, call: Spanned) -> Spanned {
        let SpannedForm::List(items) = &call.form else {
            return call;
        };
        let Some(head) = items.first().and_then(Spanned::as_symbol) else {
            return call;
        };
        let argc = items.len() - 1;
        if head == "equal?" && argc == 2 {
            let (op_span, start) = (items[0].span, call.span.start);
            if let Some(test) = self.nil_test(start, op_span, &items[1], &items[2]) {
                return test;
            }
        }
        let operator = match (head, argc) {
            ("and" | "or" | "mod" | "equal?", 2) => Some(head),
            ("list", _) => Some("list"),
            _ => None,
        };
        if let Some(op) = operator {
            let canonical = match op {
                "list" => "[…]".to_string(),
                "mod" => "a % b".to_string(),
                "equal?" => "a == b".to_string(),
                other => format!("a {other} b"),
            };
            self.note(
                Spelling::OperatorSpelling,
                call.span,
                &format!("{head}(…)"),
                &canonical,
            );
            return call;
        }
        if head == "apply"
            && self.text(items[0].span) == "apply"
            && argc >= 2
            && items[1].as_symbol().is_some_and(is_callable_name)
        {
            self.note(Spelling::Apply, call.span, "apply(f, …, xs)", "f(…, *xs)");
            return call;
        }
        if head == "try" {
            return self.try_spelling(call);
        }
        call
    }

    fn try_spelling(&mut self, call: Spanned) -> Spanned {
        let SpannedForm::List(items) = &call.form else {
            return call;
        };
        let Some((catch, body)) = items[1..].split_last() else {
            return call;
        };
        let Some(clause) = catch.as_list() else {
            return call;
        };
        let binder = match clause {
            [head, binding, handler @ ..]
                if head.as_symbol() == Some("catch") && !handler.is_empty() =>
            {
                match binding.as_list() {
                    Some([b]) => b.as_symbol().map(|n| (n.to_string(), b.span)),
                    _ => None,
                }
            }
            _ => None,
        };
        let Some((name, binder_span)) = binder else {
            return call;
        };
        if body.is_empty() {
            return call;
        }
        self.note(Spelling::TryCatch, call.span, "try(…, catch(…))", "rescue");
        let handler = &clause[2..];
        let rename =
            name.starts_with('_') && name != "_" && !handler.iter().any(|h| mentions(h, &name));
        let body = if body.len() == 1 {
            body[0].clone()
        } else {
            let span = cover(body, call.span);
            let mut list = vec![sym_at(Span::new(span.start, span.start), "begin")];
            list.extend(body.iter().cloned());
            list_at(span, list)
        };
        let handler = if handler.len() == 1 {
            handler[0].clone()
        } else {
            let span = cover(handler, catch.span);
            let mut list = vec![sym_at(Span::new(span.start, span.start), "begin")];
            list.extend(handler.iter().cloned());
            list_at(span, list)
        };
        let binder = sym_at(binder_span, if rename { "_" } else { &name });
        list_at(
            call.span,
            vec![
                items[0].clone(),
                body,
                list_at(
                    catch.span,
                    vec![
                        clause[0].clone(),
                        list_at(clause[1].span, vec![binder]),
                        handler,
                    ],
                ),
            ],
        )
    }

    fn finish_send(&mut self, start: usize, recv: Spanned, dot: Span) -> Result<Spanned, Fail> {
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
                return Err(fail(
                    format!("expected a method name after `.`, found {other}"),
                    name_span,
                ))
            }
        };
        if !self.at(&TokenKind::LParen) {
            return Ok(list_at(
                self.span_since(start),
                vec![
                    sym_at(dot, LOWERED_FIELD),
                    recv,
                    atom_at(name_span, Atom::Keyword(name)),
                ],
            ));
        }
        self.note(
            Spelling::CallForm,
            dot.merge(name_span),
            &format!("x.{name}(…)"),
            &format!("{name}(x, …)"),
        );
        let (args, splat) = self.call_args()?;
        Ok(self.call_node(
            self.span_since(start),
            vec![sym_at(name_span, &name), recv],
            args,
            splat,
        ))
    }

    fn call_node(
        &self,
        span: Span,
        head: Vec<Spanned>,
        args: Vec<Spanned>,
        splat: Option<Span>,
    ) -> Spanned {
        let mut list = Vec::with_capacity(head.len() + args.len() + 1);
        if let Some(at) = splat {
            list.push(sym_at(at, "apply"));
        }
        list.extend(head);
        list.extend(args);
        list_at(span, list)
    }

    fn call_args(&mut self) -> Result<(Vec<Spanned>, Option<Span>), Fail> {
        self.expect(&TokenKind::LParen, "`(`")?;
        let mut args = Vec::new();
        let mut splat = None;
        self.skip_newlines();
        if self.eat(&TokenKind::RParen) {
            return Ok((args, splat));
        }
        loop {
            self.skip_newlines();
            if splat.is_some() {
                return Err(
                    self.error("a splat `*xs` passes a list as the LAST arguments: write it last")
                );
            }
            if self.at_spread() || matches!(self.peek(), TokenKind::Label(_)) {
                let open = self.peek_span();
                let (segments, spread) = self.map_entries(open, &TokenKind::RParen)?;
                if !spread {
                    return Err(fail(
                        "a keyword entry in a call needs a `**` spread: pass a map, f({a: 1})",
                        open,
                    ));
                }
                args.push(self.merged(open, LOWERED_KWARGS, segments));
                return Ok((args, splat));
            }
            if matches!(self.peek(), TokenKind::Op(o) if o == "*") {
                splat = Some(self.peek_span());
                self.bump();
            }
            args.push(self.expr(0)?);
            self.skip_newlines();
            if self.eat(&TokenKind::Comma) {
                if self.trailing_comma(&TokenKind::RParen) {
                    break;
                }
                continue;
            }
            self.expect(&TokenKind::RParen, "`,` or `)`")?;
            break;
        }
        Ok((args, splat))
    }

    fn trailing_comma(&mut self, closer: &TokenKind) -> bool {
        let comma = self
            .toks
            .get(self.pos.wrapping_sub(1))
            .map_or(self.peek_span(), |t| t.span);
        self.skip_newlines();
        if self.at(closer) {
            self.note(Spelling::TrailingComma, comma, ",", "");
            self.bump();
            return true;
        }
        false
    }

    fn list_literal(&mut self, open: Span) -> Result<Spanned, Fail> {
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
                if self.trailing_comma(&TokenKind::RBracket) {
                    break;
                }
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
    fn map_literal(&mut self, open: Span) -> Result<Spanned, Fail> {
        self.skip_newlines();
        if self.eat(&TokenKind::RBrace) {
            return Ok(list_at(
                self.span_since(open.start),
                vec![sym_at(open, LOWERED_MAP)],
            ));
        }
        let (mut segments, spread) = self.map_entries(open, &TokenKind::RBrace)?;
        if !spread {
            return Ok(segments.remove(0));
        }
        Ok(self.merged(open, LOWERED_MERGE, segments))
    }

    fn merged(&self, open: Span, head: &str, segments: Vec<Spanned>) -> Spanned {
        let mut items = vec![sym_at(open, head)];
        items.extend(segments);
        list_at(self.span_since(open.start), items)
    }

    fn at_spread(&self) -> bool {
        matches!(self.peek(), TokenKind::Op(o) if o == "**")
    }

    fn map_entries(
        &mut self,
        open: Span,
        closer: &TokenKind,
    ) -> Result<(Vec<Spanned>, bool), Fail> {
        let mut segments = Vec::new();
        let mut items = vec![sym_at(open, LOWERED_MAP)];
        let mut spread = false;
        loop {
            self.skip_newlines();
            if self.at_spread() {
                let star = self.peek_span();
                self.bump();
                let value = self.expr(0)?;
                if items.len() > 1 {
                    let span = items[1].span.merge(items[items.len() - 1].span);
                    items[0] = sym_at(items[1].span, LOWERED_MAP);
                    segments.push(list_at(span, std::mem::take(&mut items)));
                    items = vec![sym_at(open, LOWERED_MAP)];
                }
                segments.push(list_at(
                    star.merge(value.span),
                    vec![sym_at(star, LOWERED_SPLICE), value],
                ));
                spread = true;
            } else {
                self.map_entry(&mut items, closer)?;
            }
            self.skip_newlines();
            if self.eat(&TokenKind::Comma) {
                if self.trailing_comma(closer) {
                    break;
                }
                continue;
            }
            self.expect(closer, "`,` or the end of the entries")?;
            break;
        }
        if items.len() > 1 || !spread {
            let whole = self.span_since(open.start);
            segments.push(list_at(whole, items));
        }
        Ok((segments, spread))
    }

    fn map_entry(&mut self, items: &mut Vec<Spanned>, closer: &TokenKind) -> Result<(), Fail> {
        match self.peek().clone() {
            TokenKind::Label(name) => {
                let label_span = self.peek_span();
                self.bump();
                self.skip_newlines();
                items.push(atom_at(label_span, Atom::Keyword(name.clone())));
                if matches!(self.peek(), TokenKind::Comma) || self.at(closer) {
                    items.push(sym_at(label_span, &name));
                } else {
                    let value = self.expr(0)?;
                    if matches!(&value.form, SpannedForm::Atom(Atom::Symbol(s)) if *s == name)
                        && label_name(&name)
                    {
                        let written = format!("{name}: {name}");
                        let canonical = format!("{name}:");
                        self.note(
                            Spelling::MapPun,
                            label_span.merge(value.span),
                            &written,
                            &canonical,
                        );
                    }
                    items.push(value);
                }
            }
            _ => {
                let k = self.expr(0)?;
                self.skip_newlines();
                if let SpannedForm::Atom(Atom::Keyword(name)) = &k.form {
                    if blue_lang_name(name) {
                        let written = format!(":{name} =>");
                        let canonical = format!("{name}:");
                        self.note(Spelling::KeywordRocket, k.span, &written, &canonical);
                    }
                }
                self.expect(&TokenKind::Rocket, "`=>` in a map literal")?;
                self.skip_newlines();
                items.push(k);
                items.push(self.expr(0)?);
            }
        }
        Ok(())
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
    fn if_chain(&mut self, head: Span) -> Result<Spanned, Fail> {
        let cond = self.expr(0)?;
        let then = self.body(&["elsif", "else", "end"])?;
        let els = self.else_part()?;
        let mut out = vec![sym_at(head, "if"), cond, then];
        if let Some(e) = els {
            out.push(e);
        }
        Ok(list_at(self.span_since(head.start), out))
    }

    fn else_part(&mut self) -> Result<Option<Spanned>, Fail> {
        if self.at_ident("elsif") {
            let elsif = self.peek_span();
            self.bump();
            return Ok(Some(self.if_chain(elsif)?));
        }
        if !self.at_ident("else") {
            self.expect_ident("end")?;
            return Ok(None);
        }
        let else_span = self.peek_span();
        self.bump();
        let save = self.pos;
        self.skip_newlines();
        let leads_with_if = self.at_ident("if") || self.at_ident("unless");
        self.pos = save;
        let e = self.body(&["end"])?;
        let end_at = self.peek_span().start;
        self.expect_ident("end")?;
        if matches!(e.form, SpannedForm::Nil) && !self.comment_within(else_span.start, end_at) {
            self.note(Spelling::ElseNil, else_span, "else nil", "no else");
            return Ok(None);
        }
        let single_if = matches!(&e.form, SpannedForm::List(items)
            if (items.len() == 3 || items.len() == 4) && items[0].as_symbol() == Some("if"));
        if leads_with_if && single_if {
            self.note(Spelling::ElseIf, else_span, "else if", "elsif");
        }
        Ok(Some(e))
    }

    fn if_form(&mut self, head: Span, negate: bool) -> Result<Spanned, Fail> {
        let cond = self.expr(0)?;
        let cond = if negate {
            // `unless c` lowers to `(if (not c) …)`. The synthesized `not` takes
            // the `unless` keyword's span — that word is what put it there.
            let inner = cond.span;
            self.negation(head, head.merge(inner), cond)
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
        let els = self.else_part()?;
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
    fn case_form(&mut self, head: Span) -> Result<Spanned, Fail> {
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
                    "expected `when`, `else` or `end` in a case, found {}",
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

    /// Is the `(` just consumed the head of `(a, b) -> expr`? Only bare names
    /// and commas between the parens, then `->`, all on one line.
    fn arrow_lambda_ahead(&self) -> bool {
        let mut i = self.pos;
        let kind = |i: usize| self.toks.get(i).map(|t| &t.kind);
        if !matches!(kind(i), Some(TokenKind::RParen)) {
            loop {
                if matches!(kind(i), Some(TokenKind::Op(o)) if o == "*") {
                    i += 1;
                }
                if !matches!(kind(i), Some(TokenKind::Ident(_))) {
                    return false;
                }
                i += 1;
                match kind(i) {
                    Some(TokenKind::Comma) => i += 1,
                    Some(TokenKind::RParen) => break,
                    _ => return false,
                }
            }
        }
        matches!(kind(i + 1), Some(TokenKind::Op(o)) if o == "->")
    }

    /// `(a, b) -> expr` => `(lambda (a b) expr)`: the inline spelling of a
    /// one-expression `fn`. `->` is unambiguous here: the return-type arrow
    /// only follows a `def` header, never a parenthesised name list in
    /// expression position. The formatter spells a lambda this way exactly
    /// when its body is one expression that fits the line, and as a broken
    /// `fn … end` otherwise.
    fn arrow_lambda(&mut self, head: Span) -> Result<Spanned, Fail> {
        let mut params: Vec<Spanned> = Vec::new();
        while !self.at(&TokenKind::RParen) {
            let p_span = self.peek_span();
            if self.at_star() {
                params.extend(self.rest_parameter()?);
                break;
            }
            match self.bump() {
                TokenKind::Ident(p) => params.push(sym_at(p_span, &p)),
                other => {
                    return Err(fail(
                        format!("expected a parameter name, found {other}"),
                        p_span,
                    ))
                }
            }
            self.eat(&TokenKind::Comma);
        }
        self.bump();
        self.bump();
        self.skip_newlines();
        let params_span = cover(&params, head);
        let body = self.expr(0)?;
        Ok(list_at(
            self.span_since(head.start),
            vec![sym_at(head, "lambda"), list_at(params_span, params), body],
        ))
    }

    fn rest_parameter(&mut self) -> Result<[Spanned; 2], Fail> {
        let star = self.peek_span();
        self.bump();
        let name_span = self.peek_span();
        match self.bump() {
            TokenKind::Ident(p) => {
                let whole = star.merge(name_span);
                Ok([sym_at(whole, "&rest"), sym_at(whole, &p)])
            }
            other => Err(fail(
                format!("expected a parameter name after `*`, found {other}"),
                name_span,
            )),
        }
    }

    fn at_star(&self) -> bool {
        matches!(self.peek(), TokenKind::Op(o) if o == "*")
    }

    fn optional_mark(
        &self,
        name: String,
        span: Span,
        optional_from: &mut Option<usize>,
        index: usize,
    ) -> Result<String, Fail> {
        match name.strip_suffix('?').filter(|n| !n.is_empty()) {
            Some(bare) => {
                optional_from.get_or_insert(index);
                Ok(bare.to_string())
            }
            None if optional_from.is_some() => Err(fail(
                format!("the required parameter `{name}` cannot follow an optional one"),
                span,
            )),
            None => Ok(name),
        }
    }

    fn rest_is_last(&mut self) -> Result<(), Fail> {
        self.skip_newlines();
        if self.at(&TokenKind::Comma) {
            return Err(self.error("a rest parameter `*name` comes last".to_string()));
        }
        Ok(())
    }

    /// `fn(a, b) ... end` => `(lambda (a b) body)`
    ///
    /// Without this the higher-order functions are unreachable in practice:
    /// `map(inc, xs)` works only because `inc` happens to be a named stdlib
    /// function, and there was no way to write the one-off the call site
    /// actually wants.
    ///
    /// `fn … end` is the block spelling and always breaks over lines; the
    /// inline spelling is `(x) -> expr` ([`Self::arrow_lambda`]).
    fn lambda_form(&mut self, head: Span) -> Result<Spanned, Fail> {
        let mut params: Vec<Spanned> = Vec::new();
        if !self.at(&TokenKind::LParen) {
            self.note(Spelling::ParameterList, head, "fn", "fn()");
        }
        if self.at(&TokenKind::LParen) {
            self.bump();
            self.skip_newlines();
            if !self.eat(&TokenKind::RParen) {
                loop {
                    self.skip_newlines();
                    let p_span = self.peek_span();
                    if self.at_star() {
                        params.extend(self.rest_parameter()?);
                        self.rest_is_last()?;
                        self.expect(&TokenKind::RParen, "`)` after the rest parameter")?;
                        break;
                    }
                    match self.bump() {
                        TokenKind::Ident(p) => params.push(sym_at(p_span, &p)),
                        other => {
                            return Err(fail(
                                format!("expected a parameter name, found {other}"),
                                p_span,
                            ))
                        }
                    }
                    self.skip_newlines();
                    if self.eat(&TokenKind::Comma) {
                        if self.trailing_comma(&TokenKind::RParen) {
                            break;
                        }
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
    fn test_form(&mut self, head: Span) -> Result<Spanned, Fail> {
        let name_span = self.peek_span();
        let name = match self.bump() {
            TokenKind::Str(s) => s,
            other => {
                return Err(fail(
                    format!("expected a string name after `test`, found {other}"),
                    name_span,
                ))
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
    fn assert_form(&mut self, head: Span) -> Result<Spanned, Fail> {
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
    fn defmacro_form(&mut self, head: Span) -> Result<Spanned, Fail> {
        let name_span = self.peek_span();
        let name = match self.bump() {
            TokenKind::Ident(n) => n,
            other => {
                return Err(fail(
                    format!("expected a name after `defmacro`, found {other}"),
                    name_span,
                ))
            }
        };
        self.not_reserved(&name, name_span, "a `defmacro` name")?;
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
                            return Err(fail(
                                format!("expected a parameter name, found {other}"),
                                p_span,
                            ))
                        }
                    }
                    self.skip_newlines();
                    if self.eat(&TokenKind::Comma) {
                        if self.trailing_comma(&TokenKind::RParen) {
                            break;
                        }
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
    fn quote_form(&mut self, head: Span) -> Result<Spanned, Fail> {
        self.quoting += 1;
        let body = self.body(&["end"]);
        self.quoting -= 1;
        let body = body?;
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
    fn unquote_form(&mut self, head: Span, splice: bool) -> Result<Spanned, Fail> {
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

    fn protected_body(&mut self, head: Span) -> Result<Spanned, Fail> {
        let body = self.body(&["rescue", "ensure", "end"])?;
        if self.at_ident("rescue") || self.at_ident("ensure") {
            return self.rescue_tail(head, body);
        }
        Ok(body)
    }

    fn begin_form(&mut self, head: Span) -> Result<Spanned, Fail> {
        let body = self.body(&["rescue", "ensure", "end"])?;
        if !(self.at_ident("rescue") || self.at_ident("ensure")) {
            return Err(self.error(
                "a `begin` block protects its statements with `rescue` or `ensure`; without either, write the statements directly",
            ));
        }
        let tree = self.rescue_tail(head, body)?;
        self.expect_ident("end")?;
        Ok(Spanned::new(self.span_since(head.start), tree.form))
    }

    fn rescue_tail(&mut self, head: Span, body: Spanned) -> Result<Spanned, Fail> {
        let mut clauses: Vec<Spanned> = Vec::new();
        let mut catch_all: Option<(Spanned, Spanned, Span)> = None;
        while self.at_ident("rescue") {
            let kw = self.peek_span();
            self.bump();
            if catch_all.is_some() {
                return Err(fail(
                    "a `rescue NAME` catches every error, so it is the last `rescue`; put the kinds it would shadow above it",
                    kw,
                ));
            }
            match self.peek().clone() {
                TokenKind::Sym(_) => {
                    let mut kinds = Vec::new();
                    loop {
                        let k_span = self.peek_span();
                        match self.bump() {
                            TokenKind::Sym(k) => kinds.push(atom_at(k_span, Atom::Keyword(k))),
                            other => {
                                return Err(fail(
                                    format!("expected an error kind such as `:not_found`, found {other}"),
                                    k_span,
                                ))
                            }
                        }
                        if self.eat(&TokenKind::Comma) {
                            self.skip_newlines();
                            continue;
                        }
                        break;
                    }
                    let binder = if self.eat_ident("as") {
                        let b_span = self.peek_span();
                        match self.bump() {
                            TokenKind::Ident(b) if !is_reserved_word(&b) => Some(sym_at(b_span, &b)),
                            other => {
                                return Err(fail(
                                    format!("expected the name the error is bound to after `as`, found {other}"),
                                    b_span,
                                ))
                            }
                        }
                    } else {
                        None
                    };
                    let handler = self.body(&["rescue", "ensure", "end"])?;
                    let mut test = vec![sym_at(kw, LOWERED_ERROR_MATCH), sym_at(kw, RESCUED)];
                    test.extend(kinds);
                    let test = list_at(cover(&test, kw), test);
                    let handler = match binder {
                        Some(b) => let_bound(b, handler, kw),
                        None => handler,
                    };
                    clauses.push(list_at(kw.merge(handler.span), vec![test, handler]));
                }
                TokenKind::Ident(b) if !is_reserved_word(&b) => {
                    let b_span = self.peek_span();
                    self.bump();
                    let handler = self.body(&["rescue", "ensure", "end"])?;
                    catch_all = Some((sym_at(b_span, &b), handler, kw));
                }
                _ => {
                    return Err(fail(
                        "`rescue` names what it catches: `rescue :kind`, `rescue :a, :b as e`, or `rescue e` for every error (`rescue _` discards it)",
                        kw,
                    ))
                }
            }
        }
        let ensure = if self.at_ident("ensure") {
            self.bump();
            let cleanup = self.body(&["rescue", "end"])?;
            if self.at_ident("rescue") {
                return Err(self.error("`ensure` comes after every `rescue` of its block"));
            }
            Some(cleanup)
        } else {
            None
        };
        let whole = self.span_since(head.start);
        let protected = if clauses.is_empty() {
            match catch_all {
                None => body,
                Some((binder, handler, kw)) => list_at(
                    whole,
                    vec![
                        sym_at(head, "try"),
                        body,
                        list_at(
                            kw.merge(handler.span),
                            vec![
                                sym_at(kw, "catch"),
                                list_at(binder.span, vec![binder]),
                                handler,
                            ],
                        ),
                    ],
                ),
            }
        } else {
            let first_kw = clauses[0].span;
            let otherwise = match catch_all {
                Some((binder, handler, kw)) => {
                    let bound = let_bound(binder, handler, kw);
                    list_at(kw.merge(bound.span), vec![sym_at(kw, "else"), bound])
                }
                None => list_at(
                    head,
                    vec![
                        sym_at(head, "else"),
                        list_at(
                            head,
                            vec![sym_at(head, LOWERED_RERAISE), sym_at(head, RESCUED)],
                        ),
                    ],
                ),
            };
            let mut cond = vec![sym_at(first_kw, "cond")];
            cond.extend(clauses);
            cond.push(otherwise);
            let cond_span = cover(&cond, first_kw);
            list_at(
                whole,
                vec![
                    sym_at(head, "try"),
                    body,
                    list_at(
                        cond_span,
                        vec![
                            sym_at(first_kw, "catch"),
                            list_at(first_kw, vec![sym_at(first_kw, RESCUED)]),
                            list_at(cond_span, cond),
                        ],
                    ),
                ],
            )
        };
        Ok(match ensure {
            None => protected,
            Some(cleanup) => {
                let attempted = list_at(
                    protected.span,
                    vec![sym_at(head, LOWERED_ATTEMPTED), protected],
                );
                let failed = list_at(
                    head,
                    vec![sym_at(head, LOWERED_FAILED), sym_at(head, RESCUED)],
                );
                let caught = list_at(
                    whole,
                    vec![
                        sym_at(head, "try"),
                        attempted,
                        list_at(
                            head,
                            vec![
                                sym_at(head, "catch"),
                                list_at(head, vec![sym_at(head, RESCUED)]),
                                failed,
                            ],
                        ),
                    ],
                );
                list_at(
                    whole,
                    vec![sym_at(head, LOWERED_ENSURE), caught, thunk(cleanup, head)],
                )
            }
        })
    }

    fn def_form(&mut self, head: Span) -> Result<Spanned, Fail> {
        let name_span = self.peek_span();
        let name = match self.bump() {
            TokenKind::Ident(n) => n,
            other => {
                return Err(fail(
                    format!("expected a name after `def`, found {other}"),
                    name_span,
                ))
            }
        };
        self.not_reserved(&name, name_span, "a `def` name")?;
        let mut params: Vec<(String, Span, Option<Spanned>)> = Vec::new();
        let mut optional_from: Option<usize> = None;
        let mut rest: Vec<Spanned> = Vec::new();
        if !self.at(&TokenKind::LParen) {
            self.note(
                Spelling::ParameterList,
                name_span,
                &format!("def {name}"),
                &format!("def {name}()"),
            );
        }
        if self.at(&TokenKind::LParen) {
            self.bump();
            self.skip_newlines();
            if !self.eat(&TokenKind::RParen) {
                loop {
                    self.skip_newlines();
                    let p_span = self.peek_span();
                    if self.at_star() {
                        if optional_from.is_some() {
                            return Err(fail(
                                "a rest parameter cannot follow an optional one",
                                p_span,
                            ));
                        }
                        rest = self.rest_parameter()?.to_vec();
                        self.rest_is_last()?;
                        self.expect(&TokenKind::RParen, "`)` after the rest parameter")?;
                        break;
                    }
                    match self.bump() {
                        // `a` — unannotated
                        TokenKind::Ident(p) => {
                            self.not_reserved(&p, p_span, "a parameter name")?;
                            let p =
                                self.optional_mark(p, p_span, &mut optional_from, params.len())?;
                            params.push((p, p_span, None));
                        }
                        // `a:` came through as one token, so a type follows
                        TokenKind::Label(p) => {
                            self.not_reserved(&p, p_span, "a parameter name")?;
                            let p =
                                self.optional_mark(p, p_span, &mut optional_from, params.len())?;
                            self.skip_newlines();
                            let ty = self.type_expr()?;
                            params.push((p, p_span, Some(ty)));
                        }
                        other => {
                            return Err(fail(
                                format!("expected a parameter name, found {other}"),
                                p_span,
                            ))
                        }
                    }
                    self.skip_newlines();
                    if self.eat(&TokenKind::Comma) {
                        if self.trailing_comma(&TokenKind::RParen) {
                            break;
                        }
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

        let begins = {
            let save = self.pos;
            self.skip_newlines();
            let at = self.at_ident("begin").then(|| self.peek_span());
            self.pos = save;
            at
        };
        let body = self.protected_body(head)?;
        if let Some(b) = begins {
            let protects = matches!(&body.form, SpannedForm::List(items)
                if matches!(items.first().and_then(Spanned::as_symbol), Some("try") | Some(LOWERED_ENSURE)));
            if protects && body.span.start == b.start {
                self.note(
                    Spelling::TryCatch,
                    b,
                    "begin … end as a whole def body",
                    "the clauses on the def itself",
                );
            }
        }
        self.expect_ident("end")?;
        let whole = self.span_since(head.start);

        let annotated = ret.is_some() || params.iter().any(|(_, _, t)| t.is_some());
        if !annotated {
            let mut sig = vec![sym_at(name_span, &name)];
            for (i, (p, s, _)) in params.into_iter().enumerate() {
                if optional_from == Some(i) {
                    sig.push(sym_at(s, OPTIONAL_MARKER));
                }
                sig.push(sym_at(s, &p));
            }
            sig.extend(rest);
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
        for (i, (p, s, t)) in params.into_iter().enumerate() {
            if optional_from == Some(i) {
                sig.push(sym_at(s, OPTIONAL_MARKER));
            }
            let ty = t.unwrap_or_else(|| sym_at(s, "dyn"));
            sig.push(list_at(s.merge(ty.span), vec![sym_at(s, &p), ty]));
        }
        sig.extend(rest);
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

    /// A type expression: a name, or a constructor over types of any arity.
    fn type_expr(&mut self) -> Result<Spanned, Fail> {
        let name_span = self.peek_span();
        let name = match self.bump() {
            TokenKind::Ident(n) => n,
            other => {
                return Err(fail(
                    format!("expected a type name, found {other}"),
                    name_span,
                ))
            }
        };
        self.not_reserved(&name, name_span, "a type name")?;
        if self.at(&TokenKind::LParen) {
            self.bump();
            self.skip_newlines();
            let mut list = vec![sym_at(name_span, &name)];
            if !self.eat(&TokenKind::RParen) {
                loop {
                    self.skip_newlines();
                    list.push(self.type_expr()?);
                    self.skip_newlines();
                    if self.eat(&TokenKind::Comma) {
                        if self.trailing_comma(&TokenKind::RParen) {
                            break;
                        }
                        continue;
                    }
                    self.expect(&TokenKind::RParen, "`,` or `)`")?;
                    break;
                }
            }
            return Ok(list_at(self.span_since(name_span.start), list));
        }
        Ok(sym_at(name_span, &name))
    }

    fn not_reserved(&self, name: &str, at: Span, what: &str) -> Result<(), Fail> {
        if is_reserved_word(name) {
            return Err(fail(
                format!("`{name}` is a reserved word and cannot be {what}"),
                at,
            ));
        }
        Ok(())
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

    fn expect_ident(&mut self, name: &str) -> Result<(), Fail> {
        if self.at_ident(name) {
            self.bump();
            Ok(())
        } else {
            Err(self.error(format!("expected `{name}`, found {}", self.peek())))
        }
    }

    /// A sequence of expressions up to one of `terminators`, wrapped in
    /// `(begin ...)` when there is more than one.
    fn body(&mut self, terminators: &[&str]) -> Result<Spanned, Fail> {
        // Anchored BEFORE the leading newlines are skipped, so an empty body's
        // span sits where the body would have started.
        let start = self.mark();
        let mut forms = Vec::new();
        loop {
            self.skip_newlines();
            if matches!(self.peek(), TokenKind::Eof) {
                return Err(self.error(format!(
                    "unterminated block: expected {} before the end of the file",
                    one_of(terminators)
                )));
            }
            if terminators.iter().any(|t| self.at_ident(t)) {
                break;
            }
            forms.push(self.statement()?);
            self.end_of_statement(terminators)?;
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

/// `` `a` ``, `` `a` or `b` ``, `` `a`, `b` or `c` `` — a list of keywords as
/// a sentence says it.
fn one_of(words: &[&str]) -> String {
    let quoted: Vec<String> = words.iter().map(|w| format!("`{w}`")).collect();
    match quoted.split_last() {
        None => String::new(),
        Some((last, [])) => last.clone(),
        Some((last, rest)) => format!("{} or {last}", rest.join(", ")),
    }
}

fn let_bound(binder: Spanned, body: Spanned, at: Span) -> Spanned {
    let span = at.merge(body.span);
    let pair = list_at(binder.span, vec![binder, sym_at(at, RESCUED)]);
    list_at(
        span,
        vec![sym_at(at, "let"), list_at(pair.span, vec![pair]), body],
    )
}

fn thunk(body: Spanned, at: Span) -> Spanned {
    let span = at.merge(body.span);
    list_at(
        span,
        vec![sym_at(at, "lambda"), list_at(at, Vec::new()), body],
    )
}

/// Whether `name:` lexes as exactly one label spelling `name`: the parser's and
/// the formatter's shared test for a key that can be punned (`{name:}`). It asks
/// the lexer, so a name ending in `?` or `!` puns too and no second list of
/// "plain names" can drift from what a label is.
#[must_use]
pub fn label_name(name: &str) -> bool {
    matches!(
        lex(&format!("{name}:")).as_deref(),
        Ok([t, e]) if matches!(&t.kind, TokenKind::Label(n) if n == name) && e.kind == TokenKind::Eof
    )
}

fn blue_lang_name(name: &str) -> bool {
    matches!(
        lex(name).as_deref(),
        Ok([t, e]) if matches!(&t.kind, TokenKind::Ident(n) if n == name) && e.kind == TokenKind::Eof
    ) && !name.ends_with(['?', '!'])
}

fn mentions(form: &Spanned, name: &str) -> bool {
    match &form.form {
        SpannedForm::Atom(Atom::Symbol(s)) => s == name,
        SpannedForm::List(items) => items.iter().any(|i| mentions(i, name)),
        SpannedForm::Quote(i)
        | SpannedForm::Quasiquote(i)
        | SpannedForm::Unquote(i)
        | SpannedForm::UnquoteSplice(i) => mentions(i, name),
        _ => false,
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

    #[test]
    fn a_reserved_word_is_not_a_def_name_a_parameter_or_a_type() {
        for src in [
            "def def a(x)\n  x\nend",
            "def end()\n  1\nend",
            "def f(end)\n  1\nend",
            "def f(a: not)\n  1\nend",
            "def f(a) -> not a\n  a\nend",
            "def f(a: List(1 + 2))\n  a\nend",
            "defmacro defmacro m(a)\n  quote\n    a\n  end\nend",
        ] {
            assert!(parse_program(src).is_err(), "{src:?} parsed");
        }
    }

    #[test]
    fn a_type_application_takes_types_of_any_arity() {
        assert_eq!(
            q("def f(a: Map(Str, List(Int))) -> Unit()\n  a\nend"),
            "(define-typed (f (a (Map Str (List Int)))) (Unit) a)"
        );
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

    #[test]
    fn a_dot_without_parentheses_reads_a_field() {
        assert_eq!(q("user.name"), "(blue-field user :name)");
    }

    #[test]
    fn method_call_with_args() {
        assert_eq!(q("user.greet(1, 2)"), "(greet user 1 2)");
    }

    #[test]
    fn chained_fields_read_left_to_right() {
        assert_eq!(q("a.b.c"), "(blue-field (blue-field a :b) :c)");
        assert_eq!(q("a.b(1).c"), "(blue-field (b a 1) :c)");
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
    fn a_newline_escape_and_its_lines_are_one_tree() {
        for (escaped, lines) in [
            (r#""a\nb""#, r#"join_lines(["a", "b"])"#),
            (r##""#{m}\n#{h}""##, "join_lines([m, h])"),
            (r##""n=#{n}\ndone\n""##, r##"unlines(["n=#{n}", "done"])"##),
            (r#""\n""#, "line_break"),
            (r#""a\n\n\tb\n""#, r#"unlines(["a", "", "\tb"])"#),
            (r#""\na""#, r#"join_lines(["", "a"])"#),
            (r#""\n\n""#, r#"unlines(["", ""])"#),
        ] {
            assert_eq!(q(escaped), q(lines), "{escaped}");
        }
        assert_eq!(q(r#""a\tb""#), q(r#""a\tb""#));
        assert!(!q(r#""a\tb""#).contains("join_lines"));
    }

    #[test]
    fn a_newline_escape_is_noted_and_a_quoted_one_is_data() {
        let notes = spelling_notes(r#""a\nb""#).unwrap();
        assert_eq!(notes.len(), 1);
        assert_eq!(notes[0].spelling, Spelling::NewlineEscape);
        assert!(spelling_notes(r#""a\tb""#).unwrap().is_empty());
        let quoted = q("def f()\n  quote\n    \"x\\ny\"\n  end\nend\n");
        assert!(!quoted.contains("join_lines"), "{quoted}");
        assert!(spelling_notes("def f()\n  quote\n    \"x\\ny\"\n  end\nend\n")
            .unwrap()
            .is_empty());
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

    fn refused(src: &str) -> String {
        match parse_expr(src) {
            Ok(s) => panic!("{src:?} should be refused, parsed to {s}"),
            Err(e) => e.to_string(),
        }
    }

    #[test]
    fn a_question_mark_parameter_is_optional() {
        assert_eq!(q("def f(a, b?)\n  b\nend"), "(define (f a &optional b) b)");
        assert_eq!(q("def f(a?, b?)\n  a\nend"), "(define (f &optional a b) a)");
        assert_eq!(q("def f(a?)\n  a\nend"), "(define (f &optional a) a)");
    }

    #[test]
    fn an_annotated_optional_parameter_keeps_its_type_after_the_marker() {
        assert_eq!(
            q("def f(a: Int, b?: Str) -> Int\n  a\nend"),
            "(define-typed (f (a Int) &optional (b Str)) Int a)"
        );
        assert_eq!(
            q("def f(a, b?: Str)\n  a\nend"),
            "(define-typed (f (a dyn) &optional (b Str)) dyn a)"
        );
    }

    #[test]
    fn a_def_without_question_marks_carries_no_marker() {
        assert_eq!(q("def f(a, b)\n  a\nend"), "(define (f a b) a)");
        assert_eq!(q("def f(a, *r)\n  a\nend"), "(define (f a &rest r) a)");
    }

    #[test]
    fn a_required_parameter_cannot_follow_an_optional_one() {
        assert!(refused("def f(a?, b)\n  a\nend").contains("`b` cannot follow an optional"));
        assert!(refused("def f(a, b?, c: Int)\n  a\nend").contains("`c` cannot follow"));
    }

    #[test]
    fn a_rest_parameter_cannot_follow_an_optional_one() {
        assert!(refused("def f(a, b?, *r)\n  a\nend").contains("rest parameter cannot follow"));
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

    // ---- one statement per line -------------------------------------

    /// `y = xs[0]` was TWO statements, `(define y xs)` and `(list 0)`: nothing
    /// required a separator between statements, so the parser finished `xs`,
    /// saw a list literal and started a new statement on the same line. The
    /// program ran and `y` was the whole list. Found by the 2026-09-29 audit.
    #[test]
    fn postfix_indexing_is_refused_naming_nth() {
        let e = parse_program("y = xs[0]").expect_err("must not split into two statements");
        assert!(e.message.contains("`nth(0, xs)`"), "{}", e.message);
        assert_eq!((e.line, e.col), (1, 7), "{e}");
    }

    /// `a = f x` — Ruby's command call — parsed as `a = f` and then `x`.
    #[test]
    fn a_call_without_parentheses_is_refused_naming_the_call() {
        let e = parse_program("a = f x").expect_err("must not split into two statements");
        assert!(e.message.contains("`f(x)`"), "{}", e.message);
        assert_eq!((e.line, e.col), (1, 7), "{e}");
    }

    /// The same rule inside a block body, and in every body shape.
    #[test]
    fn two_statements_on_one_line_are_refused_in_a_body() {
        for src in [
            "def f(xs)\n  xs[0]\nend",
            "if a\n  f x\nend",
            "fn(x) x 1 end",
            "test \"t\"\n  assert a b\nend",
            "1 2",
        ] {
            assert!(parse_program(src).is_err(), "{src:?} must not parse");
        }
    }

    /// `(x) -> e` is the inline spelling of `fn(x) e end`: one tree.
    #[test]
    fn an_arrow_lambda_lowers_to_the_same_tree_as_fn() {
        for (arrow, block) in [
            ("(x) -> x * 2", "fn(x) x * 2 end"),
            ("(a, b) -> a + b", "fn(a, b) a + b end"),
            ("() -> 1", "fn() 1 end"),
            ("map(xs, (x) -> x + 1)", "map(xs, fn(x) x + 1 end)"),
        ] {
            let a = parse_program(arrow).expect(arrow);
            let b = parse_program(block).expect(block);
            assert_eq!(format!("{a:?}"), format!("{b:?}"), "{arrow}");
        }
        assert_eq!(
            parse_program("(x)").map(|p| p.len()).ok(),
            Some(1),
            "a parenthesised name is still a group"
        );
    }

    /// The controls: every place a statement legitimately ends on its line.
    /// A block keyword closing the body on the same line is one of them, which
    /// is what keeps a one-line lambda one line.
    #[test]
    fn a_statement_may_end_at_a_newline_the_end_or_a_closing_keyword() {
        for src in [
            "fn(x) x + 1 end",
            "map(fn(x) x end, xs)",
            "if a\n  1\nelse\n  2\nend",
            "if a 1 else 2 end",
            "case x\nwhen 1 :a\nwhen 2 :b\nelse :c\nend",
            "x = 1\ny = 2",
            "x = 1",
        ] {
            assert!(
                parse_program(src).is_ok(),
                "{src:?}: {:?}",
                parse_program(src)
            );
        }
    }

    /// `if c then a else b end` read `then` as a statement and `a` as another.
    #[test]
    fn then_is_refused_by_name() {
        let e = parse_program("x = if c then 1 else 2 end").expect_err("then is not a keyword");
        assert!(e.message.contains("`then`"), "{}", e.message);
    }

    /// A brace block after a send is not a map literal the author meant.
    #[test]
    fn a_brace_block_is_refused_naming_fn() {
        let e = parse_program("xs.map { |x| x }").expect_err("no brace blocks");
        assert!(e.message.contains("fn(x)"), "{}", e.message);
    }

    // ---- qualified names ------------------------------------------------

    /// `retsu::first(xs)` is one symbol, tatara's `require` shape.
    ///
    /// Red run (2026-09-29), before the `::` token: `expected an expression,
    /// found `:``.
    #[test]
    fn a_qualified_name_is_one_symbol() {
        assert_eq!(q("retsu::first(xs)"), "(retsu/first xs)");
        assert_eq!(q("retsu::first"), "retsu/first");
        assert_eq!(q("xs |> retsu::first"), "(retsu/first xs)");
        assert_eq!(q("blue::length(xs)"), "(blue/length xs)");
    }

    /// Whitespace around `::` is layout, not meaning.
    #[test]
    fn whitespace_around_the_qualifier_is_accepted() {
        assert_eq!(q("retsu :: first(xs)"), "(retsu/first xs)");
    }

    /// After `::` a reserved word is a name: `kueri::if` is kueri's
    /// definition, not the `if` form.
    #[test]
    fn a_reserved_word_after_the_qualifier_is_a_name() {
        assert_eq!(q("kueri::if(a, b)"), "(kueri/if a b)");
        assert_eq!(q("heni::test(x)"), "(heni/test x)");
        assert_eq!(q("sabi::fn"), "sabi/fn");
    }

    #[test]
    fn a_qualified_name_has_exactly_one_qualifier() {
        for (src, says) in [
            ("::first(xs)", "`package::name`"),
            ("a::b::c", "one qualifier"),
            ("if::x", "reserved word"),
            ("retsu::1", "expected a name after `retsu::`"),
        ] {
            let e = parse_program(src).expect_err(src);
            assert!(e.message.contains(says), "{src}: {}", e.message);
        }
    }

    /// The one reader of the shape: division is not qualified, and neither
    /// is anything the surface could not have written.
    #[test]
    fn qualified_reads_only_the_package_name_shape() {
        assert_eq!(qualified("retsu/first"), Some(("retsu", "first")));
        assert_eq!(qualified("kueri/if"), Some(("kueri", "if")));
        assert_eq!(qualified("nisshi/pair?"), Some(("nisshi", "pair?")));
        for not in ["/", "a/", "/a", "a/b/c", "if/x", "hash-map", "a"] {
            assert_eq!(qualified(not), None, "{not}");
        }
        assert!(is_callable_name("kueri/if"));
    }

    /// `:pair?` is the symbol `pair?`: an import list can name a predicate.
    ///
    /// Red run (2026-09-29), before: `unexpected character `?``, found by
    /// `blue migrate` listing nisshi's `pair?`.
    #[test]
    fn a_symbol_may_end_in_a_question_or_bang() {
        assert_eq!(q("[:pair?, :set!]"), "(list :pair? :set!)");
        assert_eq!(q("use(\"n\", [:empty?])"), "(use \"n\" (list :empty?))");
        assert_eq!(q(":a != :b"), "(not= :a :b)");
    }

    // ---- errors a person can read -------------------------------------

    /// `line:col` and blue's words, never `at 10..11` and `Ident("y")`.
    #[test]
    fn a_parse_error_displays_line_col_and_the_source_text() {
        let e = parse_program("x = 1\ny = [1, 2 y]").expect_err("must fail");
        assert_eq!(e.to_string(), "2:11: expected `,` or `]`, found `y`");
        assert_eq!(e.span, Span::new(16, 17), "the span stays, as data");
    }

    /// Every token kind renders without Rust's `Debug` shape.
    #[test]
    fn no_error_message_names_a_rust_variant() {
        for src in [
            "f(1 2)",
            "{a: 1 b}",
            "def 1\nend",
            "x.1",
            "if a\n",
            "fn(1) 2 end",
            "[1 :b]",
            "1 +",
            "(1",
        ] {
            let e = parse_program(src).expect_err(src);
            let shown = e.to_string();
            for tell in [
                "Ident(", "Int(", "Op(", "Label(", "Sym(", "Str(", "LParen", "RBracket", "Eof",
                "Newline", "..",
            ] {
                assert!(!shown.contains(tell), "{src:?} -> {shown}");
            }
            assert!(e.line >= 1 && e.col >= 1, "{src:?} not located: {shown}");
        }
    }

    /// A lex error reaches the author through the same door, located.
    #[test]
    fn a_lex_error_is_located_too() {
        let e = parse_program("x = 1\ny = 2; z = 3").expect_err("no semicolons");
        assert_eq!((e.line, e.col), (2, 6), "{e}");
        assert!(e.message.contains("new line"), "{e}");
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
