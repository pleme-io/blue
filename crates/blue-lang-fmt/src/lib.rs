//! blue's canonical formatter.
//!
//! **There is no configuration type in this crate, and that is the
//! feature.** `theory/BLUE.md` §0 makes FORM an axis with exactly one way
//! to write a thing; a single option would forfeit both that and the
//! text↔tree bijection §V.16.1's content-addressed identity rests on. So
//! `format_source` takes source and returns source, and there is nowhere
//! to put a knob. The width is a constant, not a parameter.
//!
//! Two laws hold, and they are property-tested rather than asserted:
//!
//! 1. **Idempotence** — `fmt(fmt(s)) == fmt(s)`.
//! 2. **Round-trip** — `parse(fmt(s)) == parse(s)`. Formatting never
//!    changes what a program means.
//!
//! The second is the one that matters. An idempotence test alone is
//! satisfied by a formatter that deletes the whole file, which is exactly
//! how `caixa-fmt` shipped comment loss its proptest structurally could
//! not see — it compared trees that had already dropped trivia.
//!
//! `tests/corpus.rs` holds both, plus comment preservation and the width, over
//! every `.b` file in the repository — the corpus a formatter is actually used
//! on. It exists because the snippet corpus in `tests/laws.rs` stayed green on
//! 2026-09-27 while this formatter refused 31 of blue's 52 files and changed
//! the tree of two more.
//!
//! **The rendering law** (§V.13): *spelling is not semantics*. Where two
//! spellings parse to the same tree, the minimal one is rendered. Where
//! they parse to different trees they are different programs and both
//! survive. So `{a: 1}` is always emitted for a symbol key, `=>` appears only
//! where it is the sole spelling of that tree, and an `else` whose whole body
//! is an `if` is written `elsif`.
//!
//! # The one layout
//!
//! Every rule below is the only behaviour; none is a default.
//!
//! - **Width 80, hard.** A line is longer only when one token cannot be
//!   broken: a string literal (never split), a comment (never rewrapped), or a
//!   trailing comment on code that itself fits. `tests/corpus.rs`'s
//!   `lawful_overflow` states the exception exactly.
//! - **Groups nest and decide independently.** A call, list, map, lambda or
//!   operator chain that fits on the rest of its line stays flat, even inside
//!   a parent that broke.
//! - **A broken call, list or map** puts one element per line, indented one
//!   level (two spaces), and its closer on its own line aligned with the line
//!   that opened it.
//! - **A lambda** is `fn(x) body end` when that fits and its body is one
//!   statement. Otherwise `fn(x)` ends its line, the body is indented one level
//!   from the line `fn` starts on, and `end` is aligned with that line.
//! - **`def`, `if`, `case`, `test`, `defmacro` and `quote` always break**: a
//!   block collapsed onto one line would be a second rendering of one tree.
//! - **A long operator chain** (`&&`, `||`, `+`, `==`, …, one precedence level
//!   at a time) breaks AFTER each operator, the continuation indented one
//!   level. After, not before, because blue ends a statement at a newline: a
//!   line that starts with `&& b` does not parse, and one that starts with
//!   `- b` parses as a new statement, so break-before could not be applied
//!   uniformly and break-after can.
//! - **Vertical rhythm.** Two top-level forms are separated by exactly one
//!   blank line when either spans more than one line; between two one-line
//!   forms (a run of `use(...)`, a run of bindings) the author's blank line is
//!   kept and none is added. Inside a body, a blank line the author left
//!   between statements is kept as exactly one, and never directly after a
//!   block opens or before it closes. A comment block directly above a form
//!   stays attached to it.
//! - **Comments** are placed where a sequence is laid out — top-level forms,
//!   block bodies, call arguments, list and map entries, operator chains: an
//!   own-line comment before the element it preceded, at that element's
//!   indentation; a trailing comment after the element (and its comma); a
//!   comment after the last element on its own line before the closer, at the
//!   inner indentation. One with no such line is refused, naming its line,
//!   rather than dropped.
//!
//! Blank lines and comments are trivia: they are not in the tree, so they
//! cannot change what a program means, and a given source still has exactly
//! one formatting.

pub mod doc;

use std::cell::RefCell;

use blue_lang_syntax::{Comment, ParseError, Span, Spanned, SpannedForm, Token, TokenKind};
use doc::{pretty, Doc};
use tatara_lisp::{Atom, Sexp};

/// The one line width. Not configurable — see the module docs.
///
/// 80, the operator's number (2026-09-27). It was 90, and at 90 the corpus
/// carried 44 formatted lines past 80, widest 211.
pub const WIDTH: usize = 80;

/// Format blue source into its canonical form, from the TREE alone.
///
/// No comments and no blank lines — this is the rendering of the program's
/// meaning, which is what the round-trip laws compare. A file a person reads
/// is formatted with [`format_source_lossless`].
pub fn format_source(src: &str) -> Result<String, ParseError> {
    let forms = blue_lang_syntax::parse_program(src)?;
    Ok(format_forms(&forms))
}

/// Why a lossless format could not be produced.
#[derive(Debug, thiserror::Error)]
pub enum FormatError {
    #[error("{0}")]
    Parse(#[from] ParseError),
    /// A comment sits where the one layout has no line to put it.
    ///
    /// Comments are not in the tree — they carry no meaning, and putting them
    /// there would break canonicality, since two programs differing only in a
    /// comment would stop formatting identically. They are placed by POSITION
    /// wherever a sequence is laid out (see the module docs). A comment
    /// anywhere else — between a binding's `=` and its value, inside a `when`
    /// pattern — has no line of its own once the code is re-laid out.
    ///
    /// Refusing is the honest answer for that case. `blue fmt --write` used to
    /// delete every comment silently, and a comment is the one part of a
    /// program a machine cannot reconstruct.
    #[error(
        "refusing to format: {count} comment(s) at line(s) {lines} sit where blue's one \
layout has no line to put them (comments go between the statements of a body, the \
arguments of a call, the entries of a list or map, or after an operator). Move each \
onto its own line above the nearest statement — dropping it silently would lose the \
only part of a program a machine cannot reconstruct."
    )]
    UnplaceableComments { count: usize, lines: String },
}

/// Format, preserving comments and the author's blank lines.
///
/// **This is what every caller that shows a user their own file uses** —
/// `blue fmt --write` and the LSP's `textDocument/formatting` reply alike.
/// [`format_source`] remains the plain tree rendering, and its only honest
/// callers are the ones comparing trees: the round-trip laws.
///
/// The distinction is not stylistic. The LSP used to reply with
/// [`format_forms`], so formatting `spec/bindings.b` in an editor returned 707
/// bytes for 1010 and deleted all six comments. Two doors to the formatter,
/// one of them fixed. If you are adding a third, it comes through here.
///
/// It renders from the SPANNED tree, which carries a span on every node, and
/// places each comment by where it sat between two nodes. It used to render
/// the comment-free tree and re-interleave comments only between top-level
/// forms, so every comment inside a `def` was refused: 31 of the repository's
/// 52 files on 2026-09-27.
pub fn format_source_lossless(src: &str) -> Result<String, FormatError> {
    let tree = blue_lang_syntax::parse_program_tree(src)?;
    let r = Renderer::lossless(src)?;
    let out = r.program(&tree);
    let unplaced = r.unplaced();
    if unplaced.is_empty() {
        return Ok(out);
    }
    Err(FormatError::UnplaceableComments {
        count: unplaced.len(),
        lines: unplaced
            .iter()
            .map(|c| line_of(src, c.span.start).to_string())
            .collect::<Vec<_>>()
            .join(", "),
    })
}

/// 1-based line number of a byte offset, for error messages.
fn line_of(src: &str, offset: usize) -> usize {
    src.as_bytes()[..offset.min(src.len())]
        .iter()
        .filter(|b| **b == b'\n')
        .count()
        + 1
}

/// How many comments the source carries.
///
/// Counted from the LEXER, not by scanning for `#`: a `#` inside a string
/// literal is not a comment, and a scanner that thought so would refuse to
/// format a perfectly good file.
pub fn comment_count(src: &str) -> usize {
    blue_lang_syntax::comments(src).len()
}

/// Render already-parsed forms. Exposed so a caller holding a tree does
/// not have to round-trip through text to print it.
pub fn format_forms(forms: &[Sexp]) -> String {
    let tree: Vec<Spanned> = forms.iter().map(Spanned::from_sexp_synthetic).collect();
    Renderer::tree_only().program(&tree)
}

// ---------------------------------------------------------------------------
// The renderer
// ---------------------------------------------------------------------------

/// The source's trivia, and which of it has been placed.
///
/// A tree-only renderer has none: empty source, no comments, no tokens, and
/// every position question answers "nothing here".
struct Renderer<'s> {
    src: &'s str,
    comments: Vec<Comment>,
    /// One flag per comment. Each placement marks its comment; anything left
    /// unmarked after rendering had no line and is refused. Placement is
    /// counted, not assumed — that is what makes "no comment is lost" a fact
    /// the formatter checks rather than a property it hopes for.
    used: RefCell<Vec<bool>>,
    /// Every non-trivia token, in order: what "the keyword after this body"
    /// and "the token before this statement" are measured against.
    toks: Vec<Token>,
}

/// One line-shaped thing in a laid-out sequence: an own-line comment, or an
/// element with the trailing comment on its last line.
struct Unit {
    kind: UnitKind,
    start: usize,
    end: usize,
    trailing: Option<usize>,
}

enum UnitKind {
    Comment(usize),
    Item(usize),
}

/// A sequence's comments distributed onto its elements.
struct Units {
    /// A trailing comment on the line that OPENS the sequence — `def f(x) # …`,
    /// `[ # …`, `else # …`.
    head_trailing: Option<usize>,
    units: Vec<Unit>,
}

impl<'s> Renderer<'s> {
    fn tree_only() -> Renderer<'static> {
        Renderer {
            src: "",
            comments: Vec::new(),
            used: RefCell::new(Vec::new()),
            toks: Vec::new(),
        }
    }

    fn lossless(src: &'s str) -> Result<Self, ParseError> {
        let toks = blue_lang_syntax::lex(src)?
            .into_iter()
            .filter(|t| !t.is_trivia() && t.kind != TokenKind::Eof)
            .collect();
        let comments = blue_lang_syntax::comments(src);
        Ok(Renderer {
            src,
            used: RefCell::new(vec![false; comments.len()]),
            comments,
            toks,
        })
    }

    fn unplaced(&self) -> Vec<&Comment> {
        let used = self.used.borrow();
        self.comments
            .iter()
            .zip(used.iter())
            .filter(|(_, u)| !**u)
            .map(|(c, _)| c)
            .collect()
    }

    /// Does this span point into the source being formatted?
    fn real(&self, sp: Span) -> bool {
        !self.src.is_empty() && !sp.is_synthetic() && sp.end <= self.src.len()
    }

    /// Claim every unplaced comment starting in `[lo, hi)`, in order.
    fn take(&self, lo: usize, hi: usize) -> Vec<usize> {
        if lo >= hi {
            return Vec::new();
        }
        let mut used = self.used.borrow_mut();
        let mut out = Vec::new();
        for (i, c) in self.comments.iter().enumerate() {
            if !used[i] && c.span.start >= lo && c.span.start < hi {
                used[i] = true;
                out.push(i);
            }
        }
        out
    }

    fn has_comments(&self, lo: usize, hi: usize) -> bool {
        let used = self.used.borrow();
        self.comments
            .iter()
            .enumerate()
            .any(|(i, c)| !used[i] && c.span.start >= lo && c.span.start < hi)
    }

    /// End of the last token that ends at or before `pos`, an opening `(`
    /// skipped — the header a body follows. A statement written `(a + b)` has
    /// the span of `a + b`; its `(` is not the header.
    fn prev_end(&self, pos: usize) -> usize {
        self.toks
            .iter()
            .rev()
            .find(|t| t.span.end <= pos && t.kind != TokenKind::LParen)
            .map_or(0, |t| t.span.end)
    }

    /// Start of the first token at or after `pos`, a closing `)` skipped — the
    /// keyword (`end`, `else`, `when`) a body runs up to.
    fn next_start(&self, pos: usize) -> usize {
        self.toks
            .iter()
            .find(|t| t.span.start >= pos && t.kind != TokenKind::RParen)
            .map_or(self.src.len(), |t| t.span.start)
    }

    /// Did the author leave a blank line between `a` and `b`?
    fn blank_between(&self, a: usize, b: usize) -> bool {
        a < b
            && self
                .src
                .get(a..b)
                .is_some_and(|s| s.bytes().filter(|c| *c == b'\n').count() > 1)
    }

    fn byte_at(&self, i: usize) -> Option<u8> {
        self.src.as_bytes().get(i).copied()
    }

    /// Where the `end` closing `s` starts, when `s`'s source ends with one.
    fn closer(&self, s: &Spanned) -> Option<usize> {
        if !self.real(s.span) || s.span.end < 3 {
            return None;
        }
        let at = s.span.end - 3;
        (self.src.get(at..s.span.end) == Some("end")).then_some(at)
    }

    /// The inside of a bracketed node: after its opener, before its closer.
    fn inside(&self, s: &Spanned, open: u8, close: u8) -> (usize, usize) {
        if !self.real(s.span) || s.span.end == 0 {
            return (0, 0);
        }
        let lo = if self.byte_at(s.span.start) == Some(open) {
            s.span.start + 1
        } else {
            s.span.start
        };
        let hi = if self.byte_at(s.span.end - 1) == Some(close) {
            s.span.end - 1
        } else {
            s.span.end
        };
        (lo, hi)
    }

    fn comment_text(&self, i: usize) -> String {
        self.comments[i].text.trim_end().to_string()
    }

    /// An own-line comment. The group around it cannot be flat.
    fn own_line(&self, i: usize) -> Doc {
        Doc::comment(self.comment_text(i)).concat(Doc::break_parent())
    }

    /// A trailing comment. Whatever follows it must start a new line, or the
    /// comment would swallow it.
    fn trailing(&self, i: usize) -> Doc {
        let mut t = String::from(" ");
        t.push_str(&self.comment_text(i));
        Doc::comment(t).concat(Doc::break_parent())
    }

    /// Distribute the comments of `[lo, hi)` onto the elements at `spans`.
    ///
    /// Each gap between two elements is claimed here; the inside of an element
    /// is left to the element's own rendering. A comment with code before it on
    /// its line trails the element before it (or the line that opened the
    /// sequence); one alone on its line becomes its own unit.
    fn units(&self, lo: usize, hi: usize, spans: &[Span]) -> Units {
        let mut out = Units {
            head_trailing: None,
            units: Vec::with_capacity(spans.len()),
        };
        let mut prev = lo;
        for (k, sp) in spans.iter().enumerate() {
            if self.real(*sp) {
                let gap = self.take(prev, sp.start);
                self.place(gap, &mut out);
                out.units.push(Unit {
                    kind: UnitKind::Item(k),
                    start: sp.start,
                    end: sp.end,
                    trailing: None,
                });
                prev = prev.max(sp.end);
            } else {
                out.units.push(Unit {
                    kind: UnitKind::Item(k),
                    start: prev,
                    end: prev,
                    trailing: None,
                });
            }
        }
        let gap = self.take(prev, hi);
        self.place(gap, &mut out);
        out
    }

    fn place(&self, gap: Vec<usize>, out: &mut Units) {
        for ci in gap {
            let c = &self.comments[ci];
            if !c.own_line {
                match out.units.last_mut() {
                    Some(u) if u.trailing.is_none() && matches!(u.kind, UnitKind::Item(_)) => {
                        u.trailing = Some(ci);
                        u.end = c.span.end;
                        continue;
                    }
                    None if out.head_trailing.is_none() => {
                        out.head_trailing = Some(ci);
                        continue;
                    }
                    // A second trailing comment for one line has nowhere to
                    // trail; it becomes its own line, which is stable.
                    _ => {}
                }
            }
            out.units.push(Unit {
                kind: UnitKind::Comment(ci),
                start: c.span.start,
                end: c.span.end,
                trailing: None,
            });
        }
    }

    // ---- top level ------------------------------------------------------

    fn program(&self, forms: &[Spanned]) -> String {
        let spans: Vec<Span> = forms.iter().map(|f| f.span).collect();
        let mut u = self.units(0, self.src.len(), &spans);
        // Nothing precedes the first form, so a "head" comment is just a line.
        if let Some(c) = u.head_trailing.take() {
            u.units.insert(
                0,
                Unit {
                    kind: UnitKind::Comment(c),
                    start: self.comments[c].span.start,
                    end: self.comments[c].span.end,
                    trailing: None,
                },
            );
        }

        // Each unit rendered alone, at column 0, so that "spans more than one
        // line" is a fact about the output rather than a guess.
        let rendered: Vec<(String, bool)> = u
            .units
            .iter()
            .map(|unit| match unit.kind {
                UnitKind::Comment(c) => (self.comment_text(c), false),
                UnitKind::Item(k) => {
                    let body = pretty(&self.expr(&forms[k], 0), WIDTH);
                    let multi = body.contains('\n');
                    let text = match unit.trailing {
                        Some(c) => {
                            let mut t = body;
                            t.push(' ');
                            t.push_str(&self.comment_text(c));
                            t
                        }
                        None => body,
                    };
                    (text, multi)
                }
            })
            .collect();

        let mut out = String::new();
        for (i, unit) in u.units.iter().enumerate() {
            if i > 0 {
                let prev = &u.units[i - 1];
                let author = self.blank_between(prev.end, unit.start);
                let blank = match prev.kind {
                    UnitKind::Comment(_) => author,
                    UnitKind::Item(_) => {
                        // The form this unit leads: itself, or the form below
                        // the comment block it opens.
                        let next_multi = u.units[i..]
                            .iter()
                            .zip(&rendered[i..])
                            .find(|(x, _)| matches!(x.kind, UnitKind::Item(_)))
                            .is_some_and(|(_, (_, m))| *m);
                        author || rendered[i - 1].1 || next_multi
                    }
                };
                out.push('\n');
                if blank {
                    out.push('\n');
                }
            }
            out.push_str(&rendered[i].0);
        }
        if !out.is_empty() {
            out.push('\n');
        }
        out
    }

    // ---- block bodies ---------------------------------------------------

    /// The statements of a body. `(begin a b …)` is how the parser spells two
    /// or more; a one-element `begin` did not come from a body (the parser
    /// never makes one), so it stays a single statement.
    fn statements<'t>(&self, b: &'t Spanned) -> Vec<&'t Spanned> {
        match &b.form {
            SpannedForm::List(items)
                if items.len() >= 3 && items[0].as_symbol() == Some("begin") =>
            {
                items[1..].iter().collect()
            }
            _ => vec![b],
        }
    }

    /// A block body: the header's trailing comment, then `lead` and the
    /// statements, nested one level. `lead` is a hard line for a block, and a
    /// soft `line` for a lambda, which may stay on one line.
    fn body(&self, b: &Spanned, hi: Option<usize>, lead: Doc) -> Doc {
        let stmts = self.statements(b);
        let (lo, hi) = if self.real(b.span) {
            let lo = self.prev_end(b.span.start);
            let last = stmts.last().map_or(b.span.start, |s| s.span.end);
            (lo, hi.unwrap_or_else(|| self.next_start(last)))
        } else {
            (0, 0)
        };
        // An empty body is `nil`, placed after any comments the body holds —
        // the parser gave it a zero-width span where the body began.
        let spans: Vec<Span> = if matches!(b.form, SpannedForm::Nil) && b.span.start == b.span.end {
            vec![if self.real(b.span) {
                Span::new(hi, hi)
            } else {
                b.span
            }]
        } else {
            stmts.iter().map(|s| s.span).collect()
        };
        let u = self.units(lo, hi, &spans);
        let docs: Vec<Doc> = stmts.iter().map(|s| self.expr(s, 0)).collect();
        let mut head = Doc::nil();
        if let Some(c) = u.head_trailing {
            head = self.trailing(c);
        }
        head.concat(lead.concat(self.lines(&u, &docs)).nest(2))
    }

    /// Statements one per line, the author's blank lines kept as one.
    fn lines(&self, u: &Units, docs: &[Doc]) -> Doc {
        let mut out = Doc::nil();
        for (i, unit) in u.units.iter().enumerate() {
            if i > 0 {
                out = out.concat(Doc::hardline());
                if self.blank_between(u.units[i - 1].end, unit.start) {
                    out = out.concat(Doc::hardline());
                }
            }
            out = out.concat(match unit.kind {
                UnitKind::Comment(c) => self.own_line(c),
                UnitKind::Item(k) => {
                    let d = docs[k].clone();
                    match unit.trailing {
                        Some(c) => d.concat(self.trailing(c)),
                        None => d,
                    }
                }
            });
        }
        out
    }

    // ---- bracketed sequences --------------------------------------------

    /// `open a, b, c close`: flat if it fits, else one element per line with
    /// the closer on its own line.
    fn seq(&self, open: &str, close: &str, u: &Units, docs: Vec<Doc>) -> Doc {
        if u.units.is_empty() && u.head_trailing.is_none() {
            let mut t = String::from(open);
            t.push_str(close);
            return Doc::text(t);
        }
        let total = docs.len();
        let mut inner = Doc::nil();
        let mut seen = 0;
        let mut sep: Option<Doc> = None;
        for unit in &u.units {
            if let Some(s) = sep.take() {
                inner = inner.concat(s);
            }
            match unit.kind {
                UnitKind::Comment(c) => {
                    inner = inner.concat(self.own_line(c));
                    sep = Some(Doc::hardline());
                }
                UnitKind::Item(k) => {
                    seen += 1;
                    inner = inner.concat(docs[k].clone());
                    if seen < total {
                        inner = inner.concat(Doc::text(","));
                    }
                    sep = Some(match unit.trailing {
                        Some(c) => {
                            inner = inner.concat(self.trailing(c));
                            Doc::hardline()
                        }
                        None => Doc::line(),
                    });
                }
            }
        }
        let mut d = Doc::text(open.to_string());
        if let Some(c) = u.head_trailing {
            d = d.concat(self.trailing(c));
        }
        d.concat(Doc::softline().concat(inner).nest(2))
            .concat(Doc::softline())
            .concat(Doc::text(close.to_string()))
            .group()
    }

    fn seq_of(&self, open: &str, close: &str, items: &[Spanned], lo: usize, hi: usize) -> Doc {
        let spans: Vec<Span> = items.iter().map(|i| i.span).collect();
        let u = self.units(lo, hi, &spans);
        let docs = items.iter().map(|i| self.expr(i, 0)).collect();
        self.seq(open, close, &u, docs)
    }

    // ---- expressions ----------------------------------------------------

    /// Render `s`, parenthesizing if its precedence is below `min_prec`.
    fn expr(&self, s: &Spanned, min_prec: u8) -> Doc {
        match &s.form {
            SpannedForm::Nil => Doc::text("nil"),
            SpannedForm::Atom(a) => atom(a),
            SpannedForm::List(items) if items.is_empty() => Doc::text("()"),

            // The quasiquote family. These are STRUCTURAL variants, not
            // lists, and the formatter used to have no arm for them at all —
            // they fell through the catch-all and rendered as nothing.
            SpannedForm::Quasiquote(inner) => Doc::text("quote")
                .concat(self.body(inner, self.closer(s), Doc::hardline()))
                .concat(Doc::hardline())
                .concat(Doc::text("end")),
            SpannedForm::Unquote(inner) => Doc::text("unquote(")
                .concat(self.expr(inner, 0))
                .concat(Doc::text(")")),
            SpannedForm::UnquoteSplice(inner) => Doc::text("unquote_splice(")
                .concat(self.expr(inner, 0))
                .concat(Doc::text(")")),
            // `'x` has no blue surface syntax yet; render the tatara form so it
            // is visible rather than silently dropped.
            SpannedForm::Quote(inner) => Doc::text("'").concat(self.expr(inner, 0)),

            SpannedForm::List(items) => self.list(s, items, min_prec),
        }
    }

    fn list(&self, s: &Spanned, items: &[Spanned], min_prec: u8) -> Doc {
        let head = items[0].as_symbol();
        match head {
            // (if c t [e])
            Some("if") if items.len() == 3 || items.len() == 4 => {
                return self
                    .if_parts(s, "if")
                    .concat(Doc::hardline())
                    .concat(Doc::text("end"))
            }
            // (define (name params...) body)
            Some("define") if items.len() == 3 && items[1].is_list() => return self.def_form(s),
            // (define name value) — a BINDING, rendered `name = value`.
            //
            // Without this arm it fell through to the plain-call path and
            // printed `define(x, 5)`. That re-parses to the same tree, so
            // every round-trip law passed — and `fmt --write` silently
            // rewrote every binding in the spec files. Third time a green
            // law has coexisted with unreadable output; the tree is not the
            // thing being checked here.
            Some("define") if items.len() == 3 && items[1].as_symbol().is_some() => {
                return Doc::text(items[1].as_symbol().unwrap_or("_").to_string())
                    .concat(Doc::text(" = "))
                    .concat(self.expr(&items[2], 0))
            }
            // (deftest "name" body)
            Some("deftest") if items.len() == 3 && items[1].as_string().is_some() => {
                let mut head = String::from("test ");
                head.push_str(&render_string(items[1].as_string().unwrap_or("")));
                return self.block(s, Doc::text(head), &items[2]);
            }
            // (blue-assert 'expr expr) — print the expression ONCE.
            //
            // The lowering carries it twice (as data and as value) so a
            // failure can name itself. Printing both would be a second
            // rendering of one thing, and would not re-parse.
            Some(n) if n == blue_lang_syntax::LOWERED_ASSERT && items.len() == 3 => {
                return Doc::text("assert ").concat(self.expr(&items[2], 0))
            }
            // (let ((case-subject S)) (cond …)) — a lowered `case`.
            Some("let") if is_case(&s.to_sexp()) => return self.case_form(s),
            // A `concat` chain from string interpolation, rendered back as
            // `"a#{x}b"`.
            //
            // Without this it printed `concat(concat("value: ", x), "")` —
            // correct, re-parses to the same tree, and nothing a person
            // would write. Same trap as the binding: the round-trip laws
            // cannot see it, so the arm has to exist before `fmt --write`
            // touches a file with interpolation in it.
            Some(n) if n == blue_lang_syntax::LOWERED_CONCAT && items.len() == 3 => {
                if let Some(rendered) = interpolation(&s.to_sexp()) {
                    return Doc::text(rendered);
                }
                // A hand-written `concat(a, b)` is not interpolation and
                // stays a call.
            }
            // (lambda (params) body)
            Some("lambda") if items.len() == 3 && items[1].is_list() => {
                return self.lambda_form(s, items)
            }
            // (defmacro name (params) body)
            //
            // Note the shape differs from `define`: the name is a bare
            // symbol at index 1 and the params are a list at index 2,
            // because that is tatara-lisp's own `defmacro` shape and blue
            // registers into the SAME expander rather than a parallel one.
            Some("defmacro") if items.len() == 4 && items[2].is_list() => {
                let mut head = String::from("defmacro ");
                head.push_str(items[1].as_symbol().unwrap_or("_"));
                let params = items[2].as_list().unwrap_or(&[]);
                let header = Doc::text(head).concat(self.params(params, None));
                return self.block(s, header, &items[3]);
            }
            // (define-typed (name (p T)...) R body) — the annotated def.
            // Rendered back to `def name(p: T) -> R`, because a tree the
            // formatter cannot print is a tree the round-trip law cannot
            // hold for: an annotated def previously printed as a method
            // send and did not re-parse at all.
            Some("define-typed") if items.len() == 4 && items[1].is_list() => {
                return self.typed_def_form(s, items)
            }
            Some("list") => {
                let (lo, hi) = self.inside(s, b'[', b']');
                return self.seq_of("[", "]", &items[1..], lo, hi);
            }
            Some(n) if n == blue_lang_syntax::LOWERED_MAP => return self.map_form(s, &items[1..]),
            Some("not") if items.len() == 2 => {
                return Doc::text("!").concat(self.expr(&items[1], 11))
            }
            // (- 0 x) is unary minus — the shape the parser emits.
            Some("-") if items.len() == 3 && is_zero(&items[1]) => {
                return Doc::text("-").concat(self.expr(&items[2], 11))
            }
            _ => {}
        }

        // Infix operators.
        if let Some((_, prec)) = head.and_then(infix_render) {
            if items.len() == 3 {
                let chain = self.chain(s, prec);
                return if prec < min_prec {
                    Doc::text("(").concat(chain).concat(Doc::text(")"))
                } else {
                    chain
                };
            }
        }

        // Call form: (f a b) renders `f(a, b)`.
        //
        // ## Why not the send form, given uniform access
        //
        // §V.13's uniform access means `f(x)` and `x.f` are the SAME
        // program: both lower to `(f x)`. Canonicality (law 3 — equal
        // trees format to equal text) therefore forces one rendering for
        // both spellings, and the choice is a pure readability question
        // with no semantic content.
        //
        // It used to choose the send form, and the result was systematic:
        // `fact(n - 1)` rendered `(n - 1).fact`, `sum(10, 0)` rendered
        // `10.sum(0)`, and a recursive call read backwards. It satisfied
        // all three laws while making every ordinary call worse — longer,
        // parenthesised, and inverted. A round-trip law cannot catch that;
        // only reading the output can.
        //
        // The call form is chosen because it is never actively confusing.
        // The cost is narrow and named: attribute-style access
        // (`person.age`) also renders `age(person)`. Recovering that needs
        // the AST metadata slot §V.6.3 already flags as owed — a way for
        // the tree to remember which surface was written — not a second
        // rendering rule here.
        //
        // `x.f` still PARSES. It formats to `f(x)`, which is "one way to
        // format" doing exactly what it says.
        //
        // A hand-written `begin(a, b)` lands here too, and must: rendering it
        // as two statements outside a body would re-parse as two forms.
        let callee = self.expr(&items[0], 12);
        let (lo, hi) = if self.real(s.span) && self.real(items[0].span) {
            let (_, hi) = self.inside(s, b'(', b')');
            (items[0].span.end, hi)
        } else {
            (0, 0)
        };
        callee.concat(self.seq_of("(", ")", &items[1..], lo, hi))
    }

    /// A left-leaning chain of one precedence level, `a + b - c`, broken after
    /// each operator when it does not fit, continuations indented one level.
    fn chain(&self, s: &Spanned, prec: u8) -> Doc {
        // Walk down the left spine while it stays at this precedence.
        let mut links: Vec<(&str, &Spanned)> = Vec::new();
        let mut node = s;
        let first = loop {
            let Some(items) = node.as_list() else {
                break node;
            };
            let op = items[0]
                .as_symbol()
                .and_then(infix_render)
                .map_or("?", |(op, _)| op);
            links.push((op, &items[2]));
            let left = &items[1];
            if is_link(left, prec) {
                node = left;
            } else {
                break left;
            }
        };
        links.reverse();

        let mut tail = Doc::nil();
        let mut prev_end = first.span.end;
        for (op, rhs) in links {
            let mut t = String::from(" ");
            t.push_str(op);
            tail = tail.concat(Doc::text(t));
            let gap = if self.real(first.span) && self.real(rhs.span) {
                self.take(prev_end, rhs.span.start)
            } else {
                Vec::new()
            };
            let mut leading = Doc::nil();
            let mut trailed = false;
            for c in gap {
                if !self.comments[c].own_line && !trailed {
                    tail = tail.concat(self.trailing(c));
                    trailed = true;
                } else {
                    leading = leading.concat(self.own_line(c)).concat(Doc::hardline());
                }
            }
            tail = tail
                .concat(Doc::line())
                .concat(leading)
                .concat(self.expr(rhs, prec + 1));
            if self.real(rhs.span) {
                prev_end = rhs.span.end;
            }
        }
        self.expr(first, prec).concat(tail.nest(2)).group()
    }

    /// `{a: 1, "k" => v}` — **the minimal-spelling law in one function.**
    ///
    /// A keyword key has a shorthand, so the shorthand is always emitted. Any
    /// other key has no shorthand, so the rocket appears — because it is the
    /// only spelling of that tree, never as a style choice.
    fn map_form(&self, s: &Spanned, kvs: &[Spanned]) -> Doc {
        let mut spans = Vec::new();
        let mut docs = Vec::new();
        for pair in kvs.chunks(2) {
            let (sp, d) = match pair {
                [k, v] => {
                    let d = match k.as_keyword() {
                        Some(name) => {
                            let mut t = String::from(name);
                            t.push_str(": ");
                            Doc::text(t).concat(self.expr(v, 0))
                        }
                        None => self
                            .expr(k, 0)
                            .concat(Doc::text(" => "))
                            .concat(self.expr(v, 0)),
                    };
                    let sp = if k.span.is_synthetic() {
                        v.span
                    } else {
                        k.span.merge(v.span)
                    };
                    (sp, d)
                }
                // Odd trailing key — render it rather than silently dropping.
                [k] => (k.span, self.expr(k, 0)),
                _ => continue,
            };
            spans.push(sp);
            docs.push(d);
        }
        let (lo, hi) = self.inside(s, b'{', b'}');
        let u = self.units(lo, hi, &spans);
        self.seq("{", "}", &u, docs)
    }

    /// `header`, the body, `end` — the shape of every block but `if`/`case`.
    fn block(&self, s: &Spanned, header: Doc, body: &Spanned) -> Doc {
        header
            .concat(self.body(body, self.closer(s), Doc::hardline()))
            .concat(Doc::hardline())
            .concat(Doc::text("end"))
    }

    /// A parameter list `(a, b)`, broken one per line when it is too long.
    /// `region` is the inside of the parentheses when the source has them.
    fn params(&self, params: &[Spanned], region: Option<(usize, usize)>) -> Doc {
        let spans: Vec<Span> = params.iter().map(|p| p.span).collect();
        let (lo, hi) = region.unwrap_or_else(|| match (spans.first(), spans.last()) {
            (Some(a), Some(b)) if self.real(*a) && self.real(*b) => (a.start, b.end),
            _ => (0, 0),
        });
        let u = self.units(lo, hi, &spans);
        let docs = params.iter().map(|p| self.param(p)).collect();
        self.seq("(", ")", &u, docs)
    }

    /// One parameter: `p`, or `p: T` for an annotated one (`(p T)`).
    ///
    /// A `dyn` annotation is *omitted* rather than printed. `dyn` is what the
    /// parser fills in for an unannotated parameter, so printing it would turn
    /// every plain `def` into an annotated one on the first format — the scale
    /// would slide by itself, in the direction nobody asked for.
    fn param(&self, p: &Spanned) -> Doc {
        match p.as_list() {
            Some([name, ty]) => {
                let mut t = String::from(name.as_symbol().unwrap_or("_"));
                if let Some(ty) = render_ty(&ty.to_sexp()) {
                    t.push_str(": ");
                    t.push_str(&ty);
                }
                Doc::text(t)
            }
            _ => Doc::text(p.as_symbol().unwrap_or("_").to_string()),
        }
    }

    fn def_form(&self, s: &Spanned) -> Doc {
        let Some(items) = s.as_list() else {
            return Doc::text(s.to_sexp().to_string());
        };
        let Some(sig) = items[1].as_list() else {
            return Doc::text(items[1].to_sexp().to_string());
        };
        let header = self.signature(&items[1], sig);
        self.block(s, header, &items[2])
    }

    /// `def name(params…)` from a signature node `(name p…)`.
    fn signature(&self, node: &Spanned, sig: &[Spanned]) -> Doc {
        let mut head = String::from("def ");
        head.push_str(sig[0].as_symbol().unwrap_or("_"));
        let region = if self.real(node.span) && self.real(sig[0].span) {
            let (_, hi) = self.inside(node, b'(', b')');
            Some((sig[0].span.end, hi))
        } else {
            None
        };
        Doc::text(head).concat(self.params(&sig[1..], region))
    }

    /// `(define-typed (name (p T) ...) R body)` → `def name(p: T, ...) -> R`.
    fn typed_def_form(&self, s: &Spanned, items: &[Spanned]) -> Doc {
        let Some(sig) = items[1].as_list() else {
            return Doc::text(items[1].to_sexp().to_string());
        };
        let mut header = self.signature(&items[1], sig);
        if let Some(r) = render_ty(&items[2].to_sexp()) {
            let mut t = String::from(" -> ");
            t.push_str(&r);
            header = header.concat(Doc::text(t));
        }
        self.block(s, header, &items[3])
    }

    /// `(lambda (a b) body)` → `fn(a, b) body end`, on one line when it fits.
    fn lambda_form(&self, s: &Spanned, items: &[Spanned]) -> Doc {
        let params = items[1].as_list().unwrap_or(&[]);
        Doc::text("fn")
            .concat(self.params(params, None))
            .concat(self.body(&items[2], self.closer(s), Doc::line()))
            .concat(Doc::line())
            .concat(Doc::text("end"))
            .group()
    }

    /// `if c … [elsif … | else …]`, without the closing `end`, so an `elsif`
    /// arm can share its parent's.
    fn if_parts(&self, s: &Spanned, kw: &str) -> Doc {
        let items = s.as_list().unwrap_or(&[]);
        let mut head = String::from(kw);
        head.push(' ');
        let mut d = Doc::text(head)
            .concat(self.expr(&items[1], 0))
            .concat(self.body(&items[2], None, Doc::hardline()));
        let Some(els) = items.get(3) else { return d };
        // Where the `else` / `elsif` keyword starts.
        let then_end = self
            .statements(&items[2])
            .last()
            .map_or(items[2].span.end, |x| x.span.end);
        let kw_at = if self.real(items[2].span) {
            self.next_start(then_end)
        } else {
            0
        };
        // An `else` whose whole body is one `if` IS an `elsif` — the same
        // tree, so the shorter spelling is the one rendered. Unless a comment
        // sits beside that inner `if`, where `elsif` would leave it no line.
        let elsif = is_if(els)
            && !(self.real(els.span)
                && (self.has_comments(kw_at, els.span.start)
                    || self.has_comments(els.span.end, s.span.end)));
        d = d.concat(Doc::hardline());
        if elsif {
            d.concat(self.if_parts(els, "elsif"))
        } else {
            d.concat(Doc::text("else"))
                .concat(self.body(els, self.closer(s), Doc::hardline()))
        }
    }

    /// `(let ((case-subject S)) (cond ((equal? case-subject P) B) … (else E)))`
    /// → `case S / when P / B / … / else / E / end`.
    fn case_form(&self, s: &Spanned) -> Doc {
        let items = s.as_list().unwrap_or(&[]);
        let subject = items[1]
            .as_list()
            .and_then(|b| b.first())
            .and_then(|pair| pair.as_list())
            .and_then(|pair| pair.get(1));
        let Some(subject) = subject else {
            return Doc::text(s.to_sexp().to_string());
        };
        let Some(cond) = items[2].as_list() else {
            return Doc::text(s.to_sexp().to_string());
        };
        let clauses = &cond[1..];

        let mut doc = Doc::text("case ").concat(self.expr(subject, 0));

        // Comments between the subject and the first clause: trailing on the
        // `case` line, or their own lines at the `when`s' indentation.
        if let Some(first) = clauses.first() {
            if self.real(subject.span) && self.real(first.span) {
                let lo = self.prev_end(first.span.start);
                let mut trailed = false;
                for c in self.take(lo, first.span.start) {
                    if !self.comments[c].own_line && !trailed {
                        doc = doc.concat(self.trailing(c));
                        trailed = true;
                    } else {
                        doc = doc.concat(Doc::hardline()).concat(self.own_line(c));
                    }
                }
            }
        }

        for clause in clauses {
            let Some([test, body]) = clause.as_list() else {
                continue;
            };
            if test.as_symbol() == Some("else") {
                // A `case` with no author-written else lowers to `(else nil)`
                // at the `case` keyword's span; printing it back would add an
                // else nobody wrote. An author's `else nil` is the same tree,
                // so it is omitted too — unless it holds a comment.
                let synthesized = self.real(test.span) && test.span == items[0].span;
                let empty = matches!(body.form, SpannedForm::Nil)
                    && (!self.real(test.span) || !self.has_comments(test.span.end, s.span.end));
                if synthesized || empty {
                    continue;
                }
                doc = doc
                    .concat(Doc::hardline())
                    .concat(Doc::text("else"))
                    .concat(self.body(body, self.closer(s), Doc::hardline()));
                continue;
            }
            // The test is `(equal? case-subject PATTERN)`; print the pattern.
            let pattern = match test.as_list() {
                Some([_, _, p]) => p,
                _ => test,
            };
            doc = doc
                .concat(Doc::hardline())
                .concat(Doc::text("when "))
                .concat(self.expr(pattern, 0))
                .concat(self.body(body, None, Doc::hardline()));
        }
        doc.concat(Doc::hardline()).concat(Doc::text("end"))
    }
}

/// Is `s` a link in a chain at `prec` — an infix node of that precedence that
/// is not the unary-minus shape `(- 0 x)`?
fn is_link(s: &Spanned, prec: u8) -> bool {
    let Some(items) = s.as_list() else {
        return false;
    };
    if items.len() != 3 {
        return false;
    }
    let Some(head) = items[0].as_symbol() else {
        return false;
    };
    if head == "-" && is_zero(&items[1]) {
        return false;
    }
    infix_render(head).is_some_and(|(_, p)| p == prec)
}

fn is_if(s: &Spanned) -> bool {
    s.as_list().is_some_and(|items| {
        (items.len() == 3 || items.len() == 4) && items[0].as_symbol() == Some("if")
    })
}

fn is_zero(s: &Spanned) -> bool {
    s.as_int() == Some(0)
}

/// Given the tatara-lisp callee of an infix form, the surface spelling to
/// print and the precedence to print it at.
///
/// **This reads the parser's own table — it is not a second copy of it.**
/// The previous version was a duplicate with a comment saying "must agree
/// with the parser's table", and it did not: when the parser began lowering
/// `==` to `=`, this table still knew only `==`, so `(= a b)` fell through
/// the infix branch and printed as `a.=(b)`, which does not re-parse. A
/// comment cannot hold two tables in agreement; sharing one can.
///
/// Formatting is the INVERSE direction, so the lookup is keyed by callee.
/// [`callees_are_unique`] proves that inverse is a function.
fn infix_render(callee: &str) -> Option<(&'static str, u8)> {
    blue_lang_syntax::INFIX
        .iter()
        .find(|i| i.callee == callee)
        .map(|i| (i.op, i.power.0))
}

fn sym_name(s: &Sexp) -> Option<&str> {
    match s {
        Sexp::Atom(Atom::Symbol(n)) => Some(n),
        _ => None,
    }
}

fn atom(a: &Atom) -> Doc {
    match a {
        Atom::Symbol(s) => Doc::text(s.clone()),
        Atom::Keyword(k) => Doc::text(format!(":{k}")),
        Atom::Str(s) => Doc::text(render_string(s)),
        Atom::Int(i) => Doc::text(i.to_string()),
        Atom::Float(f) => Doc::text(render_float(*f)),
        Atom::Bool(b) => Doc::text(if *b { "true" } else { "false" }),
    }
}

fn render_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// A float must render so it lexes back as a float — `1.0`, never `1`.
fn render_float(f: f64) -> String {
    let s = format!("{f}");
    if s.contains('.') || s.contains('e') || s.contains("inf") || s.contains("NaN") {
        s
    } else {
        format!("{s}.0")
    }
}

/// A type as source text, or `None` for `dyn` — the absence of an annotation.
fn render_ty(t: &Sexp) -> Option<String> {
    match t {
        Sexp::Atom(Atom::Symbol(n)) if &**n == "dyn" => None,
        Sexp::Atom(Atom::Symbol(n)) => Some(n.to_string()),
        // A constructor: (List Int) -> List(Int)
        Sexp::List(items) if items.len() == 2 => {
            let head = sym_name(&items[0])?;
            let arg = render_ty(&items[1]).unwrap_or_else(|| "dyn".to_string());
            let mut out = String::with_capacity(head.len() + arg.len() + 2);
            out.push_str(head);
            out.push('(');
            out.push_str(&arg);
            out.push(')');
            Some(out)
        }
        other => Some(other.to_string()),
    }
}

/// Is this the exact shape `case_form` lowers to?
///
/// Narrow on purpose: a hand-written `let` binding something called
/// `case-subject` is vanishingly unlikely, but the check still requires the
/// full shape — one binding, that name, and a `cond` body — so an ordinary
/// `let` can never be printed as a `case`.
fn is_case(s: &Sexp) -> bool {
    let Sexp::List(items) = s else { return false };
    if items.len() != 3 || sym_name(&items[0]) != Some("let") {
        return false;
    }
    let Sexp::List(binds) = &items[1] else {
        return false;
    };
    if binds.len() != 1 {
        return false;
    }
    let Sexp::List(pair) = &binds[0] else {
        return false;
    };
    pair.len() == 2
        && sym_name(&pair[0]) == Some("case-subject")
        && matches!(&items[2], Sexp::List(c) if !c.is_empty() && sym_name(&c[0]) == Some("cond"))
}

/// Render a `concat` chain back as an interpolated string, if it is one.
///
/// `None` when the chain is not interpolation-shaped — a hand-written
/// `concat(a, b)` must stay a call. The shape is EXACTLY what the parser
/// emits for `"a#{x}b"`: a left-leaning spine of `concat` over a string
/// leaf, whose right-hand sides alternate expression, literal, expression,
/// literal — ending on a literal.
///
/// The check used to be looser (any alternation), and a hand-written
/// `concat("a", x)` — one concat, no closing literal — printed as `"a#{x}"`,
/// which parses to a DIFFERENT tree: `(concat (concat "a" x) "")`. Two files
/// in the repository had their meaning changed by `blue fmt` that way; the
/// corpus round-trip law found them on 2026-09-27.
fn interpolation(s: &Sexp) -> Option<String> {
    let mut rights: Vec<&Sexp> = Vec::new();
    let mut node = s;
    let leaf = loop {
        match node {
            Sexp::List(items)
                if items.len() == 3
                    && sym_name(&items[0]) == Some(blue_lang_syntax::LOWERED_CONCAT) =>
            {
                rights.push(&items[2]);
                node = &items[1];
            }
            Sexp::Atom(Atom::Str(lit)) => break lit,
            _ => return None,
        }
    };
    rights.reverse();
    if rights.is_empty() || rights.len() % 2 != 0 {
        return None;
    }
    let tree = Renderer::tree_only();
    let mut out = String::from("\"");
    out.push_str(unquoted(leaf).as_str());
    for pair in rights.chunks(2) {
        let (e, lit) = (pair[0], pair[1]);
        let Sexp::Atom(Atom::Str(lit)) = lit else {
            return None;
        };
        // An interpolated literal would merge into its neighbours and lex back
        // as plain text: not this shape.
        if matches!(e, Sexp::Atom(Atom::Str(_))) {
            return None;
        }
        out.push_str("#{");
        out.push_str(&pretty(
            &tree.expr(&Spanned::from_sexp_synthetic(e), 0),
            1 << 20,
        ));
        out.push('}');
        out.push_str(unquoted(lit).as_str());
    }
    out.push('"');
    Some(out)
}

/// A literal's escaped body, without the quotes `render_string` adds.
fn unquoted(s: &str) -> String {
    let quoted = render_string(s);
    quoted[1..quoted.len() - 1].to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn f(src: &str) -> String {
        format_source(src).unwrap_or_else(|e| panic!("{src:?}: {e}"))
    }

    fn l(src: &str) -> String {
        format_source_lossless(src).unwrap_or_else(|e| panic!("{src:?}: {e}"))
    }

    // ---- the minimal-spelling law (§V.13) ---------------------------

    /// Both spellings parse to one tree, so both format to the SHORTER
    /// one. That is the law: spelling is not semantics.
    #[test]
    fn a_symbol_key_always_renders_as_the_shorthand() {
        assert_eq!(f("{a: 1}").trim(), "{a: 1}");
        assert_eq!(f("{:a => 1}").trim(), "{a: 1}");
    }

    /// And the rocket survives exactly where it is the only spelling of
    /// that tree — never as a style choice.
    #[test]
    fn a_non_symbol_key_keeps_the_rocket_because_it_must() {
        assert_eq!(f(r#"{"k" => 1}"#).trim(), r#"{"k" => 1}"#);
    }

    #[test]
    fn unary_forms_render_back_to_their_surface() {
        assert_eq!(f("-x").trim(), "-x");
        assert_eq!(f("!x").trim(), "!x");
    }

    /// `else if … end end` and `elsif` are one tree; the shorter is rendered.
    #[test]
    fn an_else_holding_only_an_if_renders_as_elsif() {
        let nested = "if a\n  1\nelse\n  if b\n    2\n  else\n    3\n  end\nend";
        let chained = "if a\n  1\nelsif b\n  2\nelse\n  3\nend";
        assert_eq!(f(nested).trim(), chained);
        assert_eq!(f(chained).trim(), chained);
    }

    // ---- structure ---------------------------------------------------

    #[test]
    fn precedence_is_preserved_without_redundant_parens() {
        assert_eq!(f("1 + 2 * 3").trim(), "1 + 2 * 3");
    }

    #[test]
    fn parens_are_emitted_only_where_precedence_requires_them() {
        assert_eq!(f("(1 + 2) * 3").trim(), "(1 + 2) * 3");
    }

    #[test]
    fn left_associativity_survives_the_round_trip() {
        assert_eq!(f("1 - 2 - 3").trim(), "1 - 2 - 3");
    }

    /// **An ordinary call renders as a call.**
    ///
    /// This is the assertion that was missing while the formatter turned
    /// every call into a send. `fact(n - 1)` became `(n - 1).fact` and all
    /// three formatting laws still passed, because a round-trip law cares
    /// about the tree and not about whether the text is readable.
    #[test]
    fn an_ordinary_call_renders_as_a_call() {
        assert_eq!(f("fact(6)").trim(), "fact(6)");
        assert_eq!(f("sum(10, 0)").trim(), "sum(10, 0)");
        assert_eq!(f("fact(n - 1)").trim(), "fact(n - 1)");
        assert_eq!(f("g(f(x))").trim(), "g(f(x))");
    }

    /// **The named cost of the choice above.** Uniform access makes `x.f` and
    /// `f(x)` the same tree, so canonicality forces one rendering — and
    /// attribute-style access converges on the call form too.
    ///
    /// This is asserted rather than left implicit so the trade is visible in
    /// the test list. Recovering `person.age` needs the AST metadata slot
    /// (§V.6.3), not a second rendering rule.
    #[test]
    fn send_syntax_parses_and_converges_on_the_call_form() {
        assert_eq!(f("user.name").trim(), "name(user)");
        assert_eq!(f("a.b.c").trim(), "c(b(a))");
        assert_eq!(f("user.greet(1, 2)").trim(), "greet(user, 1, 2)");
    }

    /// And the convergence is real: both spellings format to the same text,
    /// which is what "one way to format" means operationally.
    #[test]
    fn both_spellings_of_one_call_format_identically() {
        assert_eq!(f("user.greet(1, 2)"), f("greet(user, 1, 2)"));
        assert_eq!(f("x.f"), f("f(x)"));
    }

    #[test]
    fn def_and_if_render_as_blocks() {
        let out = f("def add(a,b)\n a+b\nend");
        assert_eq!(out.trim(), "def add(a, b)\n  a + b\nend");
    }

    #[test]
    fn if_else_renders_as_a_block() {
        let out = f("if a\n1\nelse\n2\nend");
        assert_eq!(out.trim(), "if a\n  1\nelse\n  2\nend");
    }

    #[test]
    fn nested_blocks_indent_cumulatively() {
        let out = f("def f(n)\nif n\n1\nend\nend");
        assert_eq!(out.trim(), "def f(n)\n  if n\n    1\n  end\nend");
    }

    #[test]
    fn floats_render_so_they_lex_back_as_floats() {
        assert_eq!(f("1.0").trim(), "1.0");
    }

    #[test]
    fn strings_are_re_escaped() {
        assert_eq!(f(r#""a\nb""#).trim(), r#""a\nb""#);
    }

    // ---- the one layout (2026-09-27) --------------------------------

    /// Defects 1 and 2 of the operator's sample: a lambda that fits stays on
    /// one line inside a call that breaks, and one that breaks keeps its body
    /// indented one level under the line `fn` is on, `end` aligned with it.
    #[test]
    fn a_lambda_is_its_own_group() {
        let src = "another = map(fn(x) x * 2 end, [alpha_value, beta_value, alpha_value, beta_value, alpha_value, beta_value])";
        assert_eq!(
            f(src).trim(),
            "another = map(\n  fn(x) x * 2 end,\n  \
[alpha_value, beta_value, alpha_value, beta_value, alpha_value, beta_value]\n)"
        );
        let multi = "each(xs, fn(x)\n  a(x)\n  b(x)\nend)";
        assert_eq!(
            f(multi).trim(),
            "each(\n  xs,\n  fn(x)\n    a(x)\n    b(x)\n  end\n)"
        );
    }

    /// Defect 3: a blank line between top-level forms that span lines; and
    /// the refinement — a run of one-line forms is not spread apart.
    #[test]
    fn top_level_rhythm() {
        assert_eq!(
            l("def a()\n  1\nend\ndef b()\n  2\nend\n"),
            "def a()\n  1\nend\n\ndef b()\n  2\nend\n"
        );
        assert_eq!(l("use(\"a\")\nuse(\"b\")\n"), "use(\"a\")\nuse(\"b\")\n");
        assert_eq!(l("x = 1\n\n\n\ny = 2\n"), "x = 1\n\ny = 2\n");
    }

    /// Defect 4: the author's blank line inside a body survives, collapsed to
    /// one, and none appears at a block's edges.
    #[test]
    fn a_blank_line_in_a_body_is_kept_as_one() {
        assert_eq!(
            l("def f()\n\n  a = 1\n\n\n  b = 2\n\nend\n"),
            "def f()\n  a = 1\n\n  b = 2\nend\n"
        );
    }

    /// Defect 5: the width is 80 and a map that does not fit breaks.
    #[test]
    fn a_long_map_breaks_one_entry_per_line() {
        let src =
            "{name: \"big\", value: total, alpha: alpha_value, beta: beta_value, doubled: another}";
        assert_eq!(
            f(src).trim(),
            "{\n  name: \"big\",\n  value: total,\n  alpha: alpha_value,\n  beta: beta_value,\n  doubled: another\n}"
        );
    }

    #[test]
    fn a_long_chain_breaks_after_each_operator() {
        let src =
            "ok = aaaaaaaaaaaaaaaa(x) && bbbbbbbbbbbbbbbbbbbbb(y) && cccccccccccccccccccc(z) && d";
        assert_eq!(
            f(src).trim(),
            "ok = aaaaaaaaaaaaaaaa(x) &&\n  bbbbbbbbbbbbbbbbbbbbb(y) &&\n  cccccccccccccccccccc(z) &&\n  d"
        );
    }

    // ---- comments inside forms ---------------------------------------

    #[test]
    fn comments_inside_a_body_are_placed() {
        let src =
            "def f(x) # why f\n  # first\n  a = 1 # the a\n\n  # then\n  a + x\n  # after\nend\n";
        assert_eq!(l(src), src);
    }

    #[test]
    fn comments_inside_a_call_and_a_list_are_placed() {
        let src = "f(\n  # lead\n  a, # trail\n  b\n  # tail\n)\n";
        assert_eq!(l(src), src);
        let list = "[\n  1, # one\n  2\n]\n";
        assert_eq!(l(list), list);
    }

    #[test]
    fn a_comment_after_an_operator_is_placed() {
        let src = "ok = a && # the a\n  b\n";
        assert_eq!(l(src), src);
    }

    /// The refusal is narrow and names its line.
    #[test]
    fn a_comment_between_a_binding_and_its_value_is_refused_by_line() {
        let src = "x = # no line for me\n  5\n";
        match format_source_lossless(src) {
            Err(FormatError::UnplaceableComments { count, lines }) => {
                assert_eq!((count, lines.as_str()), (1, "1"));
            }
            other => panic!("expected a refusal, got {other:?}"),
        }
    }
}
