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

use std::rc::Rc;

#[derive(Clone, Debug)]
pub enum Doc {
    Nil,
    Text(Rc<str>),
    /// Break candidate. `flat` is what it renders as when the enclosing
    /// group fits on one line.
    Line { flat: &'static str },
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
pub fn pretty(doc: &Doc, width: usize) -> String {
    let mut out = String::new();
    // Work stack of (indent, mode, doc).
    let mut stack: Vec<(isize, Mode, Doc)> = vec![(0, Mode::Break, doc.clone())];
    let mut col: usize = 0;

    while let Some((indent, mode, d)) = stack.pop() {
        match d {
            Doc::Nil => {}
            Doc::Text(s) => {
                out.push_str(&s);
                col += s.chars().count();
            }
            Doc::Line { flat } => match mode {
                Mode::Flat => {
                    out.push_str(flat);
                    col += flat.chars().count();
                }
                Mode::Break => {
                    out.push('\n');
                    let pad = indent.max(0) as usize;
                    for _ in 0..pad {
                        out.push(' ');
                    }
                    col = pad;
                }
            },
            Doc::Concat(a, b) => {
                stack.push((indent, mode, (*b).clone()));
                stack.push((indent, mode, (*a).clone()));
            }
            Doc::Nest(n, inner) => {
                stack.push((indent + n, mode, (*inner).clone()));
            }
            Doc::Group(inner) => {
                // The single decision: does this group fit flat?
                let m = if fits(width.saturating_sub(col), &inner, &stack) {
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
            Doc::Nil => {}
            Doc::Text(s) => remaining -= s.chars().count() as isize,
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
        let d = tight("a")
            .concat(Doc::line())
            .concat(tight("b"))
            .group();
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
        let d = tight("aaaaaaaa")
            .concat(Doc::line())
            .concat(inner)
            .group();
        assert_eq!(pretty(&d, 10), "aaaaaaaa\nb c");
    }

    /// Determinism is the load-bearing property: one document plus one
    /// width yields exactly one string, always.
    #[test]
    fn rendering_is_deterministic() {
        let d = tight("x")
            .concat(Doc::line())
            .concat(tight("y"))
            .group();
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
        let d = tight("aaa").concat(Doc::line()).concat(tight("bbb")).group();
        assert_ne!(pretty(&d, 80), pretty(&d, 3));
    }
}
