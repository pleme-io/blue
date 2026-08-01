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

use tatara_lisp::{Atom, Sexp};

use crate::lex::{lex, Span, Token, TokenKind};

#[derive(Clone, Debug, PartialEq)]
pub struct ParseError {
    pub message: String,
    pub span: Span,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} at {}..{}", self.message, self.span.start, self.span.end)
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
    Ok(parse_program_spanned(src)?
        .into_iter()
        .map(|(form, _)| form)
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
pub fn parse_program_spanned(src: &str) -> Result<Vec<(Sexp, Span)>, ParseError> {
    let toks: Vec<Token> = lex(src)?
        .into_iter()
        .filter(|t| !matches!(t.kind, TokenKind::Comment(_)))
        .collect();
    let mut p = Parser { toks, pos: 0 };
    p.program_spanned()
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
    Infix { op: "||", power: (1, 2), callee: "or" },
    Infix { op: "&&", power: (3, 4), callee: "and" },
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
    Infix { op: "==", power: (5, 6), callee: "equal?" },
    Infix { op: "!=", power: (5, 6), callee: "not=" },
    Infix { op: "<", power: (5, 6), callee: "<" },
    Infix { op: "<=", power: (5, 6), callee: "<=" },
    Infix { op: ">", power: (5, 6), callee: ">" },
    Infix { op: ">=", power: (5, 6), callee: ">=" },
    Infix { op: "+", power: (7, 8), callee: "+" },
    Infix { op: "-", power: (7, 8), callee: "-" },
    Infix { op: "*", power: (9, 10), callee: "*" },
    Infix { op: "/", power: (9, 10), callee: "/" },
    Infix { op: "%", power: (9, 10), callee: "mod" },
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

/// A surface keyword may not be rebound. `if = 1` is a mistake, not a binding,
/// and letting it through would shadow the form for the rest of the file.
fn is_reserved_word(name: &str) -> bool {
    SURFACE_KEYWORDS.contains(&name) || matches!(name, "do" | "end" | "else" | "true" | "false" | "nil")
}

fn infix(op: &str) -> Option<&'static Infix> {
    INFIX.iter().find(|i| i.op == op)
}

const PIPE_POWER: (u8, u8) = (0, 1);

struct Parser {
    toks: Vec<Token>,
    pos: usize,
}

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

    fn program_spanned(&mut self) -> Result<Vec<(Sexp, Span)>, ParseError> {
        let mut out = Vec::new();
        loop {
            self.skip_newlines();
            if matches!(self.peek(), TokenKind::Eof) {
                break;
            }
            let start = self.peek_span().start;
            let form = self.statement()?;
            // The last token consumed ends the form. `pos` has already advanced
            // past it, so look one back.
            let end = self
                .toks
                .get(self.pos.saturating_sub(1))
                .map_or(start, |t| t.span.end);
            out.push((form, Span::new(start, end)));
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
    fn statement(&mut self) -> Result<Sexp, ParseError> {
        if let TokenKind::Ident(name) = self.peek().clone() {
            if self.peek_at(1) == "=" && !is_reserved_word(&name) {
                self.bump(); // name
                self.bump(); // =
                self.skip_newlines();
                let value = self.expr(0)?;
                return Ok(Sexp::List(vec![sym("define"), sym(&name), value]));
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
    fn expr(&mut self, min_bp: u8) -> Result<Sexp, ParseError> {
        let mut lhs = self.prefix()?;

        loop {
            // Postfix: `.name`, `.name(args)`, `(args)`
            match self.peek() {
                TokenKind::Dot => {
                    self.bump();
                    lhs = self.finish_send(lhs)?;
                    continue;
                }
                TokenKind::LParen => {
                    // A call on an expression already parsed: `f(x)`.
                    let args = self.paren_args()?;
                    let mut list = vec![lhs];
                    list.extend(args);
                    lhs = Sexp::List(list);
                    continue;
                }
                _ => {}
            }

            // Infix
            // `callee == None` marks the pipeline, which is a rewrite rather
            // than a call.
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
                match rhs {
                    Sexp::List(mut items) if !items.is_empty() => {
                        items.insert(1, lhs);
                        Sexp::List(items)
                    }
                    callee => Sexp::List(vec![callee, lhs]),
                }
            } else {
                Sexp::List(vec![sym(callee.unwrap()), lhs, rhs])
            };
        }

        Ok(lhs)
    }

    fn prefix(&mut self) -> Result<Sexp, ParseError> {
        let span = self.peek_span();
        match self.bump() {
            TokenKind::Int(v) => Ok(Sexp::Atom(Atom::Int(v))),
            TokenKind::Float(v) => Ok(Sexp::Atom(Atom::Float(v))),
            TokenKind::Str(s) => Ok(Sexp::Atom(Atom::Str(s))),

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
                let mut acc = Sexp::Atom(Atom::Str(parts[0].clone()));
                for (i, raw) in exprs.iter().enumerate() {
                    let inner = parse_expr(raw).map_err(|e| ParseError {
                        message: format!("in interpolation `#{{{raw}}}`: {}", e.message),
                        span,
                    })?;
                    acc = Sexp::List(vec![sym(LOWERED_CONCAT), acc, inner]);
                    // `parts.len() == exprs.len() + 1` by construction, so this
                    // index is always in range.
                    acc = Sexp::List(vec![
                        sym(LOWERED_CONCAT),
                        acc,
                        Sexp::Atom(Atom::Str(parts[i + 1].clone())),
                    ]);
                }
                Ok(acc)
            }
            TokenKind::Sym(s) => Ok(Sexp::Atom(Atom::Keyword(s))),
            TokenKind::True => Ok(Sexp::Atom(Atom::Bool(true))),
            TokenKind::False => Ok(Sexp::Atom(Atom::Bool(false))),
            TokenKind::Nil => Ok(Sexp::Nil),

            TokenKind::Op(o) if o == "-" => {
                let rhs = self.expr(11)?; // binds tighter than `*`
                Ok(Sexp::List(vec![sym("-"), Sexp::Atom(Atom::Int(0)), rhs]))
            }
            TokenKind::Op(o) if o == "!" => {
                let rhs = self.expr(11)?;
                Ok(Sexp::List(vec![sym("not"), rhs]))
            }

            TokenKind::LParen => {
                self.skip_newlines();
                let inner = self.expr(0)?;
                self.skip_newlines();
                self.expect(&TokenKind::RParen, "`)`")?;
                Ok(inner)
            }

            TokenKind::LBracket => self.list_literal(),
            TokenKind::LBrace => self.map_literal(),

            TokenKind::Ident(name) => match name.as_str() {
                "if" => self.if_form(false),
                "unless" => self.if_form(true),
                "def" => self.def_form(),
                "defmacro" => self.defmacro_form(),
                "case" => self.case_form(),
                "fn" => self.lambda_form(),
                "test" => self.test_form(),
                "assert" => self.assert_form(),
                "quote" => self.quote_form(),
                "unquote" => self.unquote_form(false),
                "unquote_splice" => self.unquote_form(true),
                "do" => Err(ParseError {
                    message: "`do` without a preceding call".into(),
                    span,
                }),
                "end" => Err(ParseError {
                    message: "unexpected `end`".into(),
                    span,
                }),
                _ => Ok(sym(&name)),
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
    fn finish_send(&mut self, recv: Sexp) -> Result<Sexp, ParseError> {
        let name = match self.bump() {
            TokenKind::Ident(n) => n,
            other => {
                return Err(self.error(format!("expected a method name after `.`, found {other:?}")))
            }
        };
        let mut list = vec![sym(&name), recv];
        if self.at(&TokenKind::LParen) {
            list.extend(self.paren_args()?);
        }
        Ok(Sexp::List(list))
    }

    fn paren_args(&mut self) -> Result<Vec<Sexp>, ParseError> {
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

    fn list_literal(&mut self) -> Result<Sexp, ParseError> {
        let mut items = vec![sym("list")];
        self.skip_newlines();
        if self.eat(&TokenKind::RBracket) {
            return Ok(Sexp::List(items));
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
        Ok(Sexp::List(items))
    }

    /// `{a: 1, "k" => v}` — both spellings, one tree.
    ///
    /// This is §V.13's rendering law at the parser: `a: 1` and `:a => 1`
    /// produce the *same* s-expression, which is precisely why the
    /// formatter may always choose the shorthand. The rocket survives only
    /// where the key is not a plain symbol.
    fn map_literal(&mut self) -> Result<Sexp, ParseError> {
        let mut items = vec![sym(LOWERED_MAP)];
        self.skip_newlines();
        if self.eat(&TokenKind::RBrace) {
            return Ok(Sexp::List(items));
        }
        loop {
            self.skip_newlines();
            match self.peek().clone() {
                TokenKind::Label(name) => {
                    self.bump();
                    self.skip_newlines();
                    items.push(Sexp::Atom(Atom::Keyword(name)));
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
        Ok(Sexp::List(items))
    }

    /// `if c ... [else ...] end`, and `unless` as its negation.
    ///
    /// `unless` lowers to `(if (not c) ...)` rather than to a distinct
    /// form: one tree per meaning, so the formatter and every downstream
    /// tool see exactly one shape.
    fn if_form(&mut self, negate: bool) -> Result<Sexp, ParseError> {
        let cond = self.expr(0)?;
        let cond = if negate {
            Sexp::List(vec![sym("not"), cond])
        } else {
            cond
        };
        let then = self.body(&["else", "end"])?;
        let els = if self.at_ident("else") {
            self.bump();
            let e = self.body(&["end"])?;
            self.expect_ident("end")?;
            Some(e)
        } else {
            self.expect_ident("end")?;
            None
        };
        let mut out = vec![sym("if"), cond, then];
        if let Some(e) = els {
            out.push(e);
        }
        Ok(Sexp::List(out))
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
    fn case_form(&mut self) -> Result<Sexp, ParseError> {
        let subject = self.expr(0)?;
        self.skip_newlines();

        // A fresh name the surface cannot spell, so it cannot capture a user
        // binding of the same name.
        let subject_var = "case-subject";
        let mut arms: Vec<Sexp> = Vec::new();
        let mut otherwise: Option<Sexp> = None;

        loop {
            self.skip_newlines();
            if self.at_ident("end") {
                break;
            }
            if self.eat_ident("else") {
                otherwise = Some(self.body(&["end"])?);
                continue;
            }
            if !self.eat_ident("when") {
                return Err(self.error(format!(
                    "expected `when`, `else` or `end` in a case, found {:?}",
                    self.peek()
                )));
            }
            self.skip_newlines();
            let pattern = self.expr(0)?;
            let body = self.body(&["when", "else", "end"])?;
            arms.push(Sexp::List(vec![
                Sexp::List(vec![
                    sym("equal?"),
                    sym(subject_var),
                    pattern,
                ]),
                body,
            ]));
        }
        self.expect_ident("end")?;

        if arms.is_empty() && otherwise.is_none() {
            return Err(self.error("a case needs at least one `when` or an `else`".to_string()));
        }

        // A case with no matching arm and no else is NIL, matching Ruby. Elixir
        // raises CaseClauseError; blue follows Ruby because its `if` without an
        // else is already nil, and having two different answers to "no branch
        // taken" in one language is the inconsistency.
        let mut cond = vec![sym("cond")];
        cond.extend(arms);
        cond.push(Sexp::List(vec![
            sym("else"),
            otherwise.unwrap_or(Sexp::Nil),
        ]));

        Ok(Sexp::List(vec![
            sym("let"),
            Sexp::List(vec![Sexp::List(vec![sym(subject_var), subject])]),
            Sexp::List(cond),
        ]))
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
    fn lambda_form(&mut self) -> Result<Sexp, ParseError> {
        let mut params: Vec<String> = Vec::new();
        if self.at(&TokenKind::LParen) {
            self.bump();
            self.skip_newlines();
            if !self.eat(&TokenKind::RParen) {
                loop {
                    self.skip_newlines();
                    match self.bump() {
                        TokenKind::Ident(p) => params.push(p),
                        other => {
                            return Err(self
                                .error(format!("expected a parameter name, found {other:?}")))
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
        let body = self.body(&["end"])?;
        self.expect_ident("end")?;
        Ok(Sexp::List(vec![
            sym("lambda"),
            Sexp::List(params.iter().map(|p| sym(p)).collect()),
            body,
        ]))
    }

    /// `test "name" ... end` => `(deftest "name" body)`
    ///
    /// A string, not an identifier: a test name is prose for a human report,
    /// and forcing it into an identifier is how test names become
    /// `test_adds_two_numbers_correctly`.
    fn test_form(&mut self) -> Result<Sexp, ParseError> {
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
        Ok(Sexp::List(vec![
            sym("deftest"),
            Sexp::Atom(Atom::Str(name)),
            body,
        ]))
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
    fn assert_form(&mut self) -> Result<Sexp, ParseError> {
        let e = self.expr(0)?;
        Ok(Sexp::List(vec![
            sym(LOWERED_ASSERT),
            Sexp::Quote(Box::new(e.clone())),
            e,
        ]))
    }

    /// `defmacro name(a, b) ... end` => `(defmacro name (a b) body)`
    ///
    /// **Deliberately untyped.** A macro's parameters are *source forms*, not
    /// values, so `a: Int` would be a category error: the argument at expansion
    /// time is a fragment of syntax. §IV's ladder types values; macro
    /// parameters are not on it. Annotating one is rejected rather than
    /// silently ignored — an ignored annotation is how an author comes to
    /// believe a check is running.
    fn defmacro_form(&mut self) -> Result<Sexp, ParseError> {
        let name = match self.bump() {
            TokenKind::Ident(n) => n,
            other => {
                return Err(self.error(format!(
                    "expected a name after `defmacro`, found {other:?}"
                )))
            }
        };
        let mut params: Vec<String> = Vec::new();
        if self.at(&TokenKind::LParen) {
            self.bump();
            self.skip_newlines();
            if !self.eat(&TokenKind::RParen) {
                loop {
                    self.skip_newlines();
                    match self.bump() {
                        TokenKind::Ident(p) => params.push(p),
                        TokenKind::Label(p) => {
                            return Err(self.error(format!(
                                "macro parameter `{p}` cannot be typed: a macro receives \
                                 source forms, not values"
                            )))
                        }
                        other => {
                            return Err(self
                                .error(format!("expected a parameter name, found {other:?}")))
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

        let body = self.body(&["end"])?;
        self.expect_ident("end")?;

        // `(defmacro name (params) body)` — tatara-lisp's own shape, so blue
        // registers into the SAME expander rather than a parallel one.
        Ok(Sexp::List(vec![
            sym("defmacro"),
            sym(&name),
            Sexp::List(params.iter().map(|p| sym(p)).collect()),
            body,
        ]))
    }

    /// `quote ... end` => `` `body `` (a quasiquote).
    ///
    /// Quasiquote rather than plain quote, because a macro body that could not
    /// splice its arguments in would be useless — this is Elixir's `quote do`,
    /// which is likewise a template and not inert data.
    fn quote_form(&mut self) -> Result<Sexp, ParseError> {
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
        Ok(Sexp::Quasiquote(Box::new(body)))
    }

    /// `unquote(expr)` => `,expr`; `unquote_splice(expr)` => `,@expr`.
    fn unquote_form(&mut self, splice: bool) -> Result<Sexp, ParseError> {
        self.expect(&TokenKind::LParen, "`(` after unquote")?;
        self.skip_newlines();
        let inner = self.expr(0)?;
        self.skip_newlines();
        self.expect(&TokenKind::RParen, "`)`")?;
        Ok(if splice {
            Sexp::UnquoteSplice(Box::new(inner))
        } else {
            Sexp::Unquote(Box::new(inner))
        })
    }

    fn def_form(&mut self) -> Result<Sexp, ParseError> {
        let name = match self.bump() {
            TokenKind::Ident(n) => n,
            other => return Err(self.error(format!("expected a name after `def`, found {other:?}"))),
        };
        let mut params: Vec<(String, Option<Sexp>)> = Vec::new();
        if self.at(&TokenKind::LParen) {
            self.bump();
            self.skip_newlines();
            if !self.eat(&TokenKind::RParen) {
                loop {
                    self.skip_newlines();
                    match self.bump() {
                        // `a` — unannotated
                        TokenKind::Ident(p) => params.push((p, None)),
                        // `a:` came through as one token, so a type follows
                        TokenKind::Label(p) => {
                            self.skip_newlines();
                            let ty = self.type_expr()?;
                            params.push((p, Some(ty)));
                        }
                        other => {
                            return Err(self.error(format!(
                                "expected a parameter name, found {other:?}"
                            )))
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

        let annotated = ret.is_some() || params.iter().any(|(_, t)| t.is_some());
        if !annotated {
            let mut sig = vec![sym(&name)];
            sig.extend(params.into_iter().map(|(p, _)| sym(&p)));
            return Ok(Sexp::List(vec![sym("define"), Sexp::List(sig), body]));
        }

        // Typed shape. An un-annotated parameter in an otherwise annotated
        // signature is written `(p dyn)` so the checker sees the ladder
        // position explicitly rather than inferring it from absence.
        let mut sig = vec![sym(&name)];
        for (p, t) in params {
            let ty = t.unwrap_or_else(|| sym("dyn"));
            sig.push(Sexp::List(vec![sym(&p), ty]));
        }
        Ok(Sexp::List(vec![
            sym("define-typed"),
            Sexp::List(sig),
            ret.unwrap_or_else(|| sym("dyn")),
            body,
        ]))
    }

    /// A type expression. Currently a bare name (`Int`, `Str`, `dyn`) or a
    /// one-argument constructor (`List(Int)`).
    fn type_expr(&mut self) -> Result<Sexp, ParseError> {
        let name = match self.bump() {
            TokenKind::Ident(n) => n,
            other => return Err(self.error(format!("expected a type name, found {other:?}"))),
        };
        if self.at(&TokenKind::LParen) {
            let args = self.paren_args()?;
            let mut list = vec![sym(&name)];
            list.extend(args);
            return Ok(Sexp::List(list));
        }
        Ok(sym(&name))
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
    fn body(&mut self, terminators: &[&str]) -> Result<Sexp, ParseError> {
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
            0 => Sexp::Nil,
            1 => forms.into_iter().next().expect("checked len"),
            _ => {
                let mut list = vec![sym("begin")];
                list.extend(forms);
                Sexp::List(list)
            }
        })
    }
}

fn sym(s: &str) -> Sexp {
    Sexp::Atom(Atom::Symbol(s.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Render an `Sexp` to canonical text so tests can state the expected
    /// quoted form as a string. This is `Display`, which tatara-lisp owns —
    /// blue does not build Lisp syntax by concatenation.
    fn q(src: &str) -> String {
        parse_expr(src).map(|s| s.to_string()).unwrap_or_else(|e| panic!("{src:?}: {e}"))
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
