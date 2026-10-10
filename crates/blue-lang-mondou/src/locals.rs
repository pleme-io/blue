//! Bindings below the top level, from the binder grammar's own walker
//! (`blue_lang_syntax::scope`): where each local is bound, every place it is
//! read, and the form whose frame holds it — what the check stage's name
//! table, which holds top-level names only, cannot answer.

use blue_lang_check::names::Target;
use blue_lang_check::{NameTable, Namespace, ScopeKind};
use blue_lang_syntax::scope::{BinderKind, Scopes};
use blue_lang_syntax::{Span, Spanned, SpannedForm};

use crate::Analysis;

/// One local binding.
#[derive(Clone, Debug)]
pub struct LocalBinding {
    pub name: String,
    pub kind: BinderKind,
    /// Where it is first bound.
    pub span: Span,
    /// Every place it is bound or read, its own binding included.
    pub occurrences: Vec<Span>,
    frame: usize,
}

#[derive(Clone, Debug)]
struct Frame {
    /// The form that opens the frame, once known.
    extent: Option<Span>,
    seen: Option<Span>,
    top_level: usize,
}

/// Every local of one document.
#[derive(Clone, Debug, Default)]
pub struct Locals {
    pub bindings: Vec<LocalBinding>,
    frames: Vec<Frame>,
}

impl Locals {
    /// The binding a local name at `offset` is, if one is.
    #[must_use]
    pub fn at(&self, offset: usize) -> Option<(usize, Span)> {
        self.bindings
            .iter()
            .enumerate()
            .flat_map(|(i, b)| b.occurrences.iter().map(move |s| (i, *s)))
            .filter(|(_, s)| s.start <= offset && offset <= s.end)
            .min_by_key(|(_, s)| s.end - s.start)
    }

    /// The locals in scope at `offset`, innermost frame first.
    #[must_use]
    pub fn in_scope(&self, offset: usize) -> Vec<&LocalBinding> {
        let mut frames: Vec<(usize, Span)> = self
            .frames
            .iter()
            .enumerate()
            .filter_map(|(i, f)| f.extent.map(|e| (i, e)))
            .filter(|(_, e)| e.start < offset && offset <= e.end)
            .collect();
        frames.sort_by_key(|(_, e)| e.end - e.start);
        let mut out = Vec::new();
        for (f, _) in frames {
            for b in self.bindings.iter().filter(|b| b.frame == f) {
                if !out.iter().any(|o: &&LocalBinding| o.name == b.name) {
                    out.push(b);
                }
            }
        }
        out
    }
}

/// Synthesized by the parser, never written by an author.
const SYNTHESIZED: &[&str] = &["case-subject"];

pub(crate) fn index(a: &Analysis, builtins: &NameTable) -> Locals {
    let own = a.own_namespace();
    let table = a.checked().map_or(builtins, |c| &c.names);
    let mut out = Locals::default();
    for (top_level, form) in a.entry_forms() {
        let mut w = Walker {
            table,
            own: &own,
            top_level,
            stack: Vec::new(),
            out: &mut out,
        };
        blue_lang_syntax::scope::walk_top(form, &mut w);
        for f in out.frames.iter_mut().filter(|f| f.top_level == top_level) {
            if let Some(seen) = f.seen {
                f.extent = opener_around(form, seen);
            }
        }
    }
    out
}

struct Walker<'a> {
    table: &'a NameTable,
    own: &'a Namespace,
    top_level: usize,
    stack: Vec<usize>,
    out: &'a mut Locals,
}

impl Walker<'_> {
    fn see(&mut self, span: Span) {
        let Some(&f) = self.stack.last() else { return };
        let frame = &mut self.out.frames[f];
        frame.seen = Some(match frame.seen {
            Some(s) => Span::new(s.start.min(span.start), s.end.max(span.end)),
            None => span,
        });
    }
}

impl Scopes for Walker<'_> {
    fn head_kind(&self, name: &str) -> Option<ScopeKind> {
        let kind = self.table.head_kind(name);
        if kind == Some(ScopeKind::Macro)
            && matches!(
                self.table.ns_target(name, self.own, self.top_level),
                Target::Def(..)
            )
        {
            return Some(ScopeKind::Value);
        }
        kind
    }

    fn open(&mut self) {
        self.out.frames.push(Frame {
            extent: None,
            seen: None,
            top_level: self.top_level,
        });
        self.stack.push(self.out.frames.len() - 1);
    }

    fn bind(&mut self, name: &str, span: Span, kind: BinderKind) {
        self.see(span);
        let Some(&frame) = self.stack.last() else {
            return;
        };
        if SYNTHESIZED.contains(&name) {
            return;
        }
        if let Some(b) = self
            .out
            .bindings
            .iter_mut()
            .find(|b| b.frame == frame && b.name == name)
        {
            if !b.occurrences.contains(&span) {
                b.occurrences.push(span);
            }
            return;
        }
        self.out.bindings.push(LocalBinding {
            name: name.to_string(),
            kind,
            span,
            occurrences: vec![span],
            frame,
        });
    }

    fn close(&mut self) {
        self.stack.pop();
    }

    fn reference(&mut self, node: &Spanned, name: &str, _opaque: bool) {
        self.see(node.span);
        for f in self.stack.iter().rev() {
            if let Some(b) = self
                .out
                .bindings
                .iter_mut()
                .rev()
                .find(|b| b.frame == *f && b.name == name)
            {
                if !b.occurrences.contains(&node.span) {
                    b.occurrences.push(node.span);
                }
                return;
            }
        }
    }
}

/// The innermost frame-opening form of `top` holding all of `range`: a
/// function `def`, `fn`, `defmacro`, a `let`, a `catch` clause or a test.
fn opener_around(top: &Spanned, range: Span) -> Option<Span> {
    let mut best = None;
    visit(top, &mut |node| {
        let inside = node.span.start <= range.start && range.end <= node.span.end;
        if inside && opens_a_frame(node) {
            best = Some(node.span);
        }
    });
    best
}

fn visit(node: &Spanned, f: &mut dyn FnMut(&Spanned)) {
    f(node);
    if let SpannedForm::List(items) = &node.form {
        for i in items {
            visit(i, f);
        }
    }
}

fn opens_a_frame(node: &Spanned) -> bool {
    let Some(items) = node.as_list() else {
        return false;
    };
    match items.first().and_then(Spanned::as_symbol) {
        Some("define" | "define-typed") => items.get(1).is_some_and(|t| t.as_list().is_some()),
        Some("lambda" | "defmacro" | "let" | "let*" | "letrec" | "catch" | "deftest") => true,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use crate::Engine;

    #[test]
    fn locals_in_scope_are_the_enclosing_frames_innermost_first() {
        let text = "def f(a, b)\n  g = fn(a, c) a + c end\n  g(b, 1)\nend\n";
        let mut engine = Engine::new(Box::new(blue_lang_runtime::uses::NoLoader));
        engine.set_document("t", None, text);
        let a = engine.analysis("t").expect("analysis");
        let inner = text.find("a + c").expect("inner");
        let names: Vec<&str> = a
            .locals(&engine)
            .in_scope(inner)
            .iter()
            .map(|b| b.name.as_str())
            .collect();
        assert_eq!(names, vec!["a", "c", "b", "g"]);
        let outer = text.find("g(b").expect("outer");
        let names: Vec<&str> = a
            .locals(&engine)
            .in_scope(outer)
            .iter()
            .map(|b| b.name.as_str())
            .collect();
        assert_eq!(names, vec!["a", "b", "g"]);
        assert!(a.locals(&engine).in_scope(text.len()).is_empty());
    }
}
