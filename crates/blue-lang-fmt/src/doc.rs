//! A Wadler/Oppen pretty-printing algebra.
//!
//! Measured absent fleet-wide before this landed: no `pretty` crate, no
//! `Doc::group`, no Oppen implementation anywhere in pleme-io. Every
//! emitter in the fleet either concatenates strings or hand-rolls a shape
//! classifier, which is why `caixa-fmt` grew six ad-hoc `FormShape`s and
//! still could not generalize.
//!
//! This is the standard algebra (Wadler, *A prettier printer*, JFP 1998;
//! Lindig, *Strictly Pretty*, 2000) in its strict, linear-time form:
//!
//! - `text` — an atom, never broken
//! - `line` — a space when flat, a newline + indent when broken
//! - `softline` — nothing when flat, a newline + indent when broken
//! - `concat` — sequence
//! - `nest` — increase indentation for everything inside
//! - `group` — **the only decision point**: render flat if it fits the
//!   remaining width, otherwise break every `line` directly inside it
//!
//! The grouping discipline is what makes formatting *deterministic*: given
//! a document and a width, exactly one output exists. That determinism is
//! not a nicety — §V.16.1's content-addressed identity requires text and
//! tree to be in bijection, and two renderings of one tree would collapse
//! it.

//! Three additions, each forced by a measured defect (2026-09-27):
//!
//! - `hardline` — a newline in every mode, which makes every group around it
//!   break. Block bodies used to be pre-rendered to a string with `\n` inside
//!   one `text`, and the printer cannot indent a newline it cannot see: a
//!   lambda inside a broken call lost its indentation (`fn(x)` and its body in
//!   one column, `end` two columns left of both), and `fits` counted the whole
//!   multi-line string as one line's width, so it broke a lambda that fit.
//! - `break_parent` — zero width, and the group around it cannot be flat. A
//!   trailing comment uses it: whatever follows a `# note` has to start a new
//!   line.
//! - `comment` — text that `fits` measures as zero wide. A comment's length
//!   must never change how the code beside it is laid out; otherwise a longer
//!   note would break a call that fits.

use std::rc::Rc;

#[derive(Clone, Debug)]
pub enum Doc {
    Nil,
    Text(Rc<str>),
    /// Break candidate. `flat` is what it renders as when the enclosing
    /// group fits on one line.
    Line {
        flat: &'static str,
    },
    /// A newline in every mode. Any group containing one breaks.
    HardLine,
    /// Nothing, but the group containing it cannot render flat.
    BreakParent,
    /// Printed like `Text`, measured by `fits` as zero wide.
    Comment(Rc<str>),
    Concat(Rc<Doc>, Rc<Doc>),
    Nest(isize, Rc<Doc>),
    Group(Rc<Doc>),
}

impl Doc {
    pub fn nil() -> Self {
        Doc::Nil
    }

    pub fn text(s: impl Into<Rc<str>>) -> Self {
        Doc::Text(s.into())
    }

    /// A space when flat; a newline when broken.
    pub fn line() -> Self {
        Doc::Line { flat: " " }
    }

    /// Nothing when flat; a newline when broken.
    pub fn softline() -> Self {
        Doc::Line { flat: "" }
    }

    /// A newline, always; forces every enclosing group to break.
    pub fn hardline() -> Self {
        Doc::HardLine
    }

    /// Forces the enclosing group to break, and prints nothing.
    pub fn break_parent() -> Self {
        Doc::BreakParent
    }

    /// A comment's text: printed verbatim, invisible to the width decision.
    pub fn comment(s: impl Into<Rc<str>>) -> Self {
        Doc::Comment(s.into())
    }

    pub fn concat(self, other: Doc) -> Self {
        match (&self, &other) {
            (Doc::Nil, _) => other,
            (_, Doc::Nil) => self,
            _ => Doc::Concat(Rc::new(self), Rc::new(other)),
        }
    }

    pub fn nest(self, indent: isize) -> Self {
        Doc::Nest(indent, Rc::new(self))
    }

    pub fn group(self) -> Self {
        Doc::Group(Rc::new(self))
    }

    /// Join `docs` with `sep` between each pair.
    pub fn join(docs: impl IntoIterator<Item = Doc>, sep: Doc) -> Doc {
        let mut out = Doc::Nil;
        let mut first = true;
        for d in docs {
            if !first {
                out = out.concat(sep.clone());
            }
            out = out.concat(d);
            first = false;
        }
        out
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    Flat,
    Break,
}

/// Render `doc` at `width` columns.
///
/// Linear in the size of the document: `fits` scans only far enough to
/// decide the current group, and never re-walks a decided one.
///
/// No line ends in whitespace: a newline first trims the spaces the line
/// ended with, so a blank line (two hard lines in a row) is empty rather than
/// carrying the indentation of the line after it.
pub fn pretty(doc: &Doc, width: usize) -> String {
    let mut out = String::new();
    // Work stack of (indent, mode, doc).
    let mut stack: Vec<(isize, Mode, Doc)> = vec![(0, Mode::Break, doc.clone())];
    let mut col: usize = 0;

    while let Some((indent, mode, d)) = stack.pop() {
        match d {
            Doc::Nil => {}
            Doc::Text(s) | Doc::Comment(s) => {
                out.push_str(&s);
                col += s.chars().count();
            }
            Doc::BreakParent => {}
            Doc::Line { flat } if mode == Mode::Flat => {
                out.push_str(flat);
                col += flat.chars().count();
            }
            Doc::Line { .. } | Doc::HardLine => {
                while out.ends_with(' ') {
                    out.pop();
                }
                out.push('\n');
                let pad = indent.max(0) as usize;
                for _ in 0..pad {
                    out.push(' ');
                }
                col = pad;
            }
            Doc::Concat(a, b) => {
                stack.push((indent, mode, (*b).clone()));
                stack.push((indent, mode, (*a).clone()));
            }
            Doc::Nest(n, inner) => {
                stack.push((indent + n, mode, (*inner).clone()));
            }
            Doc::Group(inner) => {
                // The single decision: does this group fit flat? A group
                // inside a flat group is flat already — its parent fit, and
                // it is part of its parent.
                let m = if mode == Mode::Flat || fits(width.saturating_sub(col), &inner, &stack) {
                    Mode::Flat
                } else {
                    Mode::Break
                };
                stack.push((indent, m, (*inner).clone()));
            }
        }
    }
    out
}

/// Would `doc`, rendered flat, fit in `space` columns — accounting for
/// whatever already-queued work follows it up to the next break?
fn fits(space: usize, doc: &Doc, rest: &[(isize, Mode, Doc)]) -> bool {
    let mut remaining = space as isize;
    let mut local: Vec<(Mode, Doc)> = vec![(Mode::Flat, doc.clone())];
    // Trailing work, innermost first.
    let mut tail_idx = rest.len();

    loop {
        let (mode, d) = match local.pop() {
            Some(x) => x,
            None => {
                // Exit paths must re-check the budget: the last item
                // popped may have overrun it, and returning `true` here
                // without checking was a real bug the group tests caught.
                if tail_idx == 0 {
                    return remaining >= 0;
                }
                tail_idx -= 1;
                let (_, m, d) = &rest[tail_idx];
                (*m, d.clone())
            }
        };
        if remaining < 0 {
            return false;
        }
        match d {
            Doc::Nil | Doc::Comment(_) => {}
            Doc::Text(s) => remaining -= s.chars().count() as isize,
            // A forced break cannot be flat; in a broken context it ends the
            // line like any other break.
            Doc::HardLine => return mode == Mode::Break && remaining >= 0,
            Doc::BreakParent => {
                if mode == Mode::Flat {
                    return false;
                }
            }
            Doc::Line { flat } => match mode {
                // A break in the trailing context ends the line, so
                // everything up to here fits — provided it actually did.
                Mode::Break => return remaining >= 0,
                Mode::Flat => remaining -= flat.chars().count() as isize,
            },
            Doc::Concat(a, b) => {
                local.push((mode, (*b).clone()));
                local.push((mode, (*a).clone()));
            }
            Doc::Nest(_, inner) => local.push((mode, (*inner).clone())),
            // A nested group is measured flat, which is what makes this
            // Oppen's linear algorithm rather than Wadler's exponential one.
            Doc::Group(inner) => local.push((Mode::Flat, (*inner).clone())),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tight(s: &str) -> Doc {
        Doc::text(s.to_string())
    }

    #[test]
    fn text_renders_verbatim() {
        assert_eq!(pretty(&tight("hello"), 80), "hello");
    }

    #[test]
    fn a_group_that_fits_stays_flat() {
        let d = tight("a").concat(Doc::line()).concat(tight("b")).group();
        assert_eq!(pretty(&d, 80), "a b");
    }

    #[test]
    fn a_group_that_does_not_fit_breaks_every_line_inside_it() {
        let d = tight("aaaa")
            .concat(Doc::line())
            .concat(tight("bbbb"))
            .group();
        assert_eq!(pretty(&d, 5), "aaaa\nbbbb");
    }

    #[test]
    fn nest_indents_the_broken_lines() {
        let d = tight("f(")
            .concat(
                Doc::softline()
                    .concat(tight("x"))
                    .concat(Doc::text(","))
                    .concat(Doc::line())
                    .concat(tight("y"))
                    .nest(2),
            )
            .concat(Doc::softline())
            .concat(tight(")"))
            .group();
        assert_eq!(pretty(&d, 4), "f(\n  x,\n  y\n)");
    }

    /// Inner groups decide independently: an outer break does not force
    /// every inner group to break. This is the property that makes the
    /// output readable rather than maximally exploded.
    #[test]
    fn inner_groups_decide_independently() {
        let inner = tight("b").concat(Doc::line()).concat(tight("c")).group();
        let d = tight("aaaaaaaa").concat(Doc::line()).concat(inner).group();
        assert_eq!(pretty(&d, 10), "aaaaaaaa\nb c");
    }

    /// A hard line breaks the group around it even when the text is short,
    /// and the lines it opens take the nest's indentation — the defect where a
    /// lambda body pre-rendered as one string sat in the wrong column.
    #[test]
    fn a_hard_line_breaks_its_group_and_is_indented() {
        let d = tight("f(")
            .concat(
                Doc::softline()
                    .concat(tight("a"))
                    .concat(Doc::hardline())
                    .concat(tight("b"))
                    .nest(2),
            )
            .concat(Doc::softline())
            .concat(tight(")"))
            .group();
        assert_eq!(pretty(&d, 80), "f(\n  a\n  b\n)");
    }

    /// A comment never changes the layout of the code beside it.
    #[test]
    fn a_comment_is_zero_wide_to_the_width_decision() {
        let d = tight("a")
            .concat(Doc::line())
            .concat(tight("b"))
            .group()
            .concat(Doc::comment(" # a note far longer than the width"));
        assert_eq!(pretty(&d, 5), "a b # a note far longer than the width");
    }

    #[test]
    fn a_break_parent_breaks_only_its_own_group() {
        let inner = tight("x").concat(Doc::line()).concat(tight("y")).group();
        let d = inner
            .concat(Doc::line())
            .concat(tight("z"))
            .concat(Doc::break_parent())
            .group();
        assert_eq!(pretty(&d, 80), "x y\nz");
    }

    #[test]
    fn no_line_ends_in_whitespace() {
        let d = tight("a").concat(
            Doc::hardline()
                .concat(Doc::hardline())
                .concat(tight("b"))
                .nest(4),
        );
        assert_eq!(pretty(&d, 80), "a\n\n    b");
    }

    /// Determinism is the load-bearing property: one document plus one
    /// width yields exactly one string, always.
    #[test]
    fn rendering_is_deterministic() {
        let d = tight("x").concat(Doc::line()).concat(tight("y")).group();
        let a = pretty(&d, 3);
        for _ in 0..100 {
            assert_eq!(pretty(&d, 3), a);
        }
    }

    /// Anti-vacuity: width must actually matter. If every document
    /// rendered the same at every width, the tests above would be
    /// measuring nothing.
    #[test]
    fn width_changes_the_output() {
        let d = tight("aaa")
            .concat(Doc::line())
            .concat(tight("bbb"))
            .group();
        assert_ne!(pretty(&d, 80), pretty(&d, 3));
    }
}
