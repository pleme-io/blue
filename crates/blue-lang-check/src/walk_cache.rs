use std::collections::HashMap;

use tatara_lisp::{Span, Spanned, SpannedForm};

use crate::names::{Namespace, Position, Reference, Target, Tier};

const VERSION: u8 = 1;

pub trait WalkMemo {
    fn recall(&mut self, top_level: usize) -> Option<Vec<u8>>;
    fn keep(&mut self, top_level: usize, value: Vec<u8>);
    fn walked(&mut self, top_level: usize);
}

pub(crate) struct Walked {
    pub references: Vec<Reference>,
    pub resolved: usize,
}

fn children(form: &Spanned) -> Vec<&Spanned> {
    match &form.form {
        SpannedForm::List(items) => items.iter().collect(),
        SpannedForm::Quote(i)
        | SpannedForm::Quasiquote(i)
        | SpannedForm::Unquote(i)
        | SpannedForm::UnquoteSplice(i) => vec![i.as_ref()],
        SpannedForm::Nil | SpannedForm::Atom(_) => Vec::new(),
    }
}

fn paths(form: &Spanned, path: &mut Vec<u32>, out: &mut HashMap<usize, Vec<u32>>) {
    out.entry(std::ptr::from_ref(form) as usize)
        .or_insert_with(|| path.clone());
    for (i, c) in children(form).into_iter().enumerate() {
        path.push(u32::try_from(i).unwrap_or(u32::MAX));
        paths(c, path, out);
        path.pop();
    }
}

fn node_at<'a>(form: &'a Spanned, path: &[u32]) -> Option<&'a Spanned> {
    let Some((first, rest)) = path.split_first() else {
        return Some(form);
    };
    node_at(*children(form).get(*first as usize)?, rest)
}

struct Out(Vec<u8>);

impl Out {
    fn n(&mut self, mut v: u64) {
        loop {
            let byte = u8::try_from(v & 0x7f).unwrap_or(0);
            v >>= 7;
            if v == 0 {
                self.0.push(byte);
                return;
            }
            self.0.push(byte | 0x80);
        }
    }

    fn u(&mut self, v: usize) {
        self.n(v as u64);
    }

    fn b(&mut self, v: bool) {
        self.0.push(u8::from(v));
    }

    fn s(&mut self, v: &str) {
        self.u(v.len());
        self.0.extend_from_slice(v.as_bytes());
    }

    fn span(&mut self, span: Span, base: Span) -> Option<()> {
        if span == Span::synthetic() {
            self.0.push(0);
            return Some(());
        }
        if span.start < base.start || span.end < span.start || span.end > base.end {
            return None;
        }
        self.0.push(1);
        self.u(span.start - base.start);
        self.u(span.end - span.start);
        Some(())
    }

    fn namespace(&mut self, ns: &Namespace) {
        match ns {
            Namespace::Local => self.0.push(0),
            Namespace::File(f) => {
                self.0.push(1);
                self.s(f);
            }
            Namespace::Bidama(b) => {
                self.0.push(2);
                self.s(b);
            }
            Namespace::Harness => self.0.push(3),
            Namespace::SpecialForm => self.0.push(4),
            Namespace::Macro => self.0.push(5),
            Namespace::Builtin => self.0.push(6),
        }
    }

    fn target(&mut self, t: &Target) {
        match t {
            Target::Local => self.0.push(0),
            Target::Def(ns, name) => {
                self.0.push(1);
                self.namespace(ns);
                self.s(name);
            }
            Target::Builtin(name) => {
                self.0.push(2);
                self.s(name);
            }
            Target::Ambiguous(all) => {
                self.0.push(3);
                self.u(all.len());
                for ns in all {
                    self.namespace(ns);
                }
            }
            Target::Unbound => self.0.push(4),
        }
    }
}

struct In<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl In<'_> {
    fn byte(&mut self) -> Option<u8> {
        let b = *self.bytes.get(self.at)?;
        self.at += 1;
        Some(b)
    }

    fn n(&mut self) -> Option<u64> {
        let mut v = 0u64;
        for shift in (0..64).step_by(7) {
            let b = self.byte()?;
            v |= u64::from(b & 0x7f) << shift;
            if b & 0x80 == 0 {
                return Some(v);
            }
        }
        None
    }

    fn u(&mut self) -> Option<usize> {
        usize::try_from(self.n()?).ok()
    }

    fn b(&mut self) -> Option<bool> {
        match self.byte()? {
            0 => Some(false),
            1 => Some(true),
            _ => None,
        }
    }

    fn s(&mut self) -> Option<String> {
        let len = self.u()?;
        let end = self.at.checked_add(len)?;
        let text = std::str::from_utf8(self.bytes.get(self.at..end)?).ok()?;
        self.at = end;
        Some(text.to_string())
    }

    fn span(&mut self, base: Span) -> Option<Span> {
        match self.byte()? {
            0 => Some(Span::synthetic()),
            1 => {
                let start = base.start.checked_add(self.u()?)?;
                Some(Span::new(start, start.checked_add(self.u()?)?))
            }
            _ => None,
        }
    }

    fn namespace(&mut self) -> Option<Namespace> {
        Some(match self.byte()? {
            0 => Namespace::Local,
            1 => Namespace::File(self.s()?),
            2 => Namespace::Bidama(self.s()?),
            3 => Namespace::Harness,
            4 => Namespace::SpecialForm,
            5 => Namespace::Macro,
            6 => Namespace::Builtin,
            _ => return None,
        })
    }

    fn target(&mut self) -> Option<Target> {
        Some(match self.byte()? {
            0 => Target::Local,
            1 => Target::Def(self.namespace()?, self.s()?),
            2 => Target::Builtin(self.s()?),
            3 => {
                let n = self.u()?;
                let mut all = Vec::with_capacity(n.min(64));
                for _ in 0..n {
                    all.push(self.namespace()?);
                }
                Target::Ambiguous(all)
            }
            4 => Target::Unbound,
            _ => return None,
        })
    }
}

fn tier_tag(t: Tier) -> u8 {
    match t {
        Tier::Local => 0,
        Tier::Own => 1,
        Tier::Imported => 2,
        Tier::Builtin => 3,
    }
}

fn tier_of(b: u8) -> Option<Tier> {
    Some(match b {
        0 => Tier::Local,
        1 => Tier::Own,
        2 => Tier::Imported,
        3 => Tier::Builtin,
        _ => return None,
    })
}

pub(crate) fn encode(form: &Spanned, references: &[Reference], resolved: usize) -> Option<Vec<u8>> {
    let mut at = HashMap::new();
    paths(form, &mut Vec::new(), &mut at);
    let mut out = Out(vec![VERSION]);
    out.u(resolved);
    out.u(references.len());
    for r in references {
        out.span(r.span, form.span)?;
        out.s(&r.written);
        out.b(r.opaque);
        out.target(&r.flat);
        out.target(&r.ns);
        out.u(r.shadowed.len());
        for (tier, ns) in &r.shadowed {
            out.0.push(tier_tag(*tier));
            out.namespace(ns);
        }
        out.u(r.locals.len());
        for l in &r.locals {
            out.s(l);
        }
        match r.position {
            Position::Value => out.0.push(0),
            Position::Call(n) => {
                out.0.push(1);
                out.u(n);
            }
            Position::Place => out.0.push(2),
            Position::Syntax => out.0.push(3),
        }
        out.b(r.nullary_flat);
        out.b(r.nullary_ns);
        out.b(r.canonically_bare);
        let path = at.get(&r.node)?;
        out.u(path.len());
        for p in path {
            out.n(u64::from(*p));
        }
    }
    Some(out.0)
}

pub(crate) fn decode(form: &Spanned, top_level: usize, bytes: &[u8]) -> Option<Walked> {
    let mut r = In { bytes, at: 0 };
    if r.byte()? != VERSION {
        return None;
    }
    let resolved = r.u()?;
    let n = r.u()?;
    let mut references = Vec::with_capacity(n.min(4096));
    for _ in 0..n {
        let span = r.span(form.span)?;
        let written = r.s()?;
        let opaque = r.b()?;
        let flat = r.target()?;
        let ns = r.target()?;
        let shadowed_len = r.u()?;
        let mut shadowed = Vec::with_capacity(shadowed_len.min(64));
        for _ in 0..shadowed_len {
            shadowed.push((tier_of(r.byte()?)?, r.namespace()?));
        }
        let locals_len = r.u()?;
        let mut locals = Vec::with_capacity(locals_len.min(256));
        for _ in 0..locals_len {
            locals.push(r.s()?);
        }
        let position = match r.byte()? {
            0 => Position::Value,
            1 => Position::Call(r.u()?),
            2 => Position::Place,
            3 => Position::Syntax,
            _ => return None,
        };
        let nullary_flat = r.b()?;
        let nullary_ns = r.b()?;
        let canonically_bare = r.b()?;
        let depth = r.u()?;
        let mut path = Vec::with_capacity(depth.min(256));
        for _ in 0..depth {
            path.push(u32::try_from(r.n()?).ok()?);
        }
        let node = std::ptr::from_ref(node_at(form, &path)?) as usize;
        references.push(Reference {
            top_level,
            span,
            written,
            opaque,
            flat,
            ns,
            shadowed,
            locals,
            position,
            nullary_flat,
            nullary_ns,
            canonically_bare,
            node,
        });
    }
    (r.at == bytes.len()).then_some(Walked {
        references,
        resolved,
    })
}
