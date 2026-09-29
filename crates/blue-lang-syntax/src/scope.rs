//! The binder grammar: which forms open a scope, which names they bind, and
//! which symbols are references. **One walker, and every pass that needs
//! scopes drives it** — the check stage's name table
//! (`blue_lang_check::names`) and the capability frame's reach walk
//! (`blue_lang_waku::check_reach_program`). Two hand-written walkers used to
//! answer this question, and they disagreed: waku bound a `define` only at the
//! level of a `begin`, so a name assigned inside an `if` branch and read after
//! it was reported as an escape, and it knew no `let*`, `letrec` or `catch`.
//!
//! The walker knows the SHAPES of tatara-lisp's binding forms, as blue lowers
//! them: `lambda` and a function `define` introduce parameters; `let`, `let*`
//! and `letrec` their bindings (a named `let` its name); `try`'s `catch` clause
//! its variable; a `define` inside a body binds in that body's frame,
//! including through `if`, `cond` and `begin`, which open no frame of their
//! own. `quote` is data; inside a quasiquote only the `unquote`d parts are
//! code, and the rest is handed to [`Scopes::template_symbol`].
//!
//! What a pass DOES with a binding or a reference is the [`Scopes`]
//! implementation's business — the checker tracks reads for its unused
//! warning, the reach walk tests each free name against a frame — and which
//! head is a special form or a macro is the implementation's oracle
//! ([`Scopes::head_kind`]), since only the pass knows which interpreter it
//! answers to.

use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

/// Which of the evaluator's three arbiters claims a name in head position.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HeadKind {
    SpecialForm,
    Macro,
    Value,
}

/// What introduced a local binding.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BinderKind {
    Parameter,
    /// `x = e` inside a body.
    Assignment,
    /// `def f(…)` inside a body, or a named `let`.
    Function,
    Let,
    Catch,
}

/// One `use` form, as the file that wrote it declared it.
///
/// `use("moji")` makes `moji::split` reachable; `use("retsu", [:first,
/// :size])` also makes `first` and `size` reachable bare. The form stays in
/// the program (after the package's spliced forms) so the check stage can
/// point at it, and evaluates to nothing (`blue_lang_runtime::uses::ResolvedProgram::sexps`).
#[derive(Clone, Debug, PartialEq)]
pub struct Import {
    pub package: String,
    /// The names listed for bare use, each with its `:name` span. Empty for
    /// `use("moji")`.
    pub names: Vec<(String, Span)>,
    /// Whether a list was written at all: `use("x", [])` lists nothing.
    pub listed: bool,
    /// The whole `use(...)` form.
    pub span: Span,
    /// The span of the package-name string.
    pub package_span: Span,
}


/// Is this form a `use` declaration? If so, what it declares.
///
/// `use("name")` or `use("name", [:a, :b])`, the call form only. `use "kazu"`
/// without parentheses parses as two unrelated top-level atoms (blue has no
/// paren-less call syntax), which would silently do nothing — so it is not
/// treated as an import, and the bare symbol `use` then fails as an unbound
/// name rather than being quietly ignored. A list that holds anything but
/// `:name` symbols is not a declaration either, for the same reason.
#[must_use]
pub fn use_target(form: &Spanned) -> Option<Import> {
    let items = form.as_list()?;
    let (head, arg, list) = match items {
        [head, arg] => (head, arg, None),
        [head, arg, list] => (head, arg, Some(list)),
        _ => return None,
    };
    let (SpannedForm::Atom(Atom::Symbol(s)), SpannedForm::Atom(Atom::Str(name))) =
        (&head.form, &arg.form)
    else {
        return None;
    };
    if s != "use" {
        return None;
    }
    let mut names = Vec::new();
    if let Some(list) = list {
        let parts = list.as_list()?;
        if parts.first().and_then(Spanned::as_symbol) != Some("list") {
            return None;
        }
        for p in &parts[1..] {
            match &p.form {
                SpannedForm::Atom(Atom::Keyword(k)) => names.push((k.clone(), p.span)),
                _ => return None,
            }
        }
    }
    Some(Import {
        package: name.clone(),
        names,
        listed: list.is_some(),
        span: form.span,
        package_span: arg.span,
    })
}

/// The special forms whose SHAPE the walker knows — the heads a pass without
/// an interpreter to ask (the reach walk) answers [`HeadKind::SpecialForm`]
/// for, so their binders bind. Every other special form is walked as an
/// ordinary application, which is what it is for scoping purposes.
pub const SHAPED_FORMS: &[&str] = &[
    "lambda",
    "let",
    "let*",
    "letrec",
    "try",
    "cond",
    "quote",
    "quasiquote",
    "provide",
    "require",
];

/// A pass over the binder grammar. The walker calls these in source order.
pub trait Scopes {
    /// Which arbiter claims `name` as a head, if any. `None` walks the call
    /// as an ordinary application.
    fn head_kind(&self, name: &str) -> Option<HeadKind>;
    /// A frame opens: a function body, a `let`, a `catch`, a test body.
    fn open(&mut self);
    /// `name` is bound in the innermost open frame.
    fn bind(&mut self, name: &str, span: Span, kind: BinderKind);
    /// The innermost frame closes.
    fn close(&mut self);
    /// A symbol in code position. `opaque`: inside a macro call's arguments,
    /// which are syntax the macro may never evaluate.
    fn reference(&mut self, node: &Spanned, name: &str, opaque: bool);
    /// The head of a special form or a macro call — not a reference to a
    /// binding, but still a name the program writes.
    fn head(&mut self, _node: &Spanned, _name: &str, _kind: HeadKind) {}
    /// A symbol inside a quasiquoted template, outside any `unquote`: data at
    /// expansion, code once the expansion runs.
    fn template_symbol(&mut self, _node: &Spanned, _name: &str) {}
}

/// Walk a whole program. Top-level definitions are the pass's to know (they
/// are globals, see [`definitions_of`]); the walker opens frames only below
/// them.
pub fn walk_program(forms: &[Spanned], pass: &mut dyn Scopes) {
    for form in forms {
        walk_top(form, pass);
    }
}

/// Walk one top-level form.
pub fn walk_top(form: &Spanned, pass: &mut dyn Scopes) {
    Walker { pass, depth: 0 }.walk(form, false);
}

/// The names `form` defines into the frame it is evaluated in, with the
/// span of each name and whether it is a value or a macro.
///
/// A `define` binds in the environment it is EVALUATED in, and every part of
/// a form is evaluated in the enclosing environment except the parts of a
/// frame-opening form (`lambda`, a function `define`, `let`, a `catch`
/// clause, a test body) and quoted data. So this descends into every
/// sub-form but those: `x = if c … else y = 1 … end` binds `y` in the
/// function's frame, which is where a later `fn(s) … y … end` reads it.
#[must_use]
pub fn definitions_of(form: &Spanned) -> Vec<(String, Span, HeadKind)> {
    let mut out = Vec::new();
    definition_nodes(form, &mut |node, kind| {
        if let Some(n) = node.as_symbol() {
            out.push((n.to_string(), node.span, kind));
        }
    });
    out
}

/// [`definitions_of`], handing over the NAME NODE of each definition, so a
/// pass that rewrites definitions can find the symbol it renames.
pub fn definition_nodes<'a>(form: &'a Spanned, out: &mut dyn FnMut(&'a Spanned, HeadKind)) {
    let Some(items) = form.as_list() else { return };
    let head = items.first().and_then(Spanned::as_symbol);
    match head {
        Some("defmacro") => {
            if let Some(n) = items.get(1).filter(|n| n.as_symbol().is_some()) {
                out(n, HeadKind::Macro);
            }
        }
        Some("define" | "define-typed") => {
            if let Some(n) = defined_name_node(items) {
                out(n, HeadKind::Value);
            }
            // `(define x e)`: `e` is evaluated right here, so its defines are
            // this frame's too. A function define opens a frame; stop.
            if items.get(1).is_some_and(|t| t.as_symbol().is_some()) {
                for item in &items[2..] {
                    definition_nodes(item, out);
                }
            }
        }
        Some("lambda" | "let" | "let*" | "letrec" | "deftest" | "quote" | "quasiquote") => {}
        Some("try") => {
            // The body shares the frame; a `catch` clause opens its own.
            for item in &items[1..] {
                let is_clause = item
                    .as_list()
                    .and_then(|c| c.first())
                    .and_then(Spanned::as_symbol)
                    .is_some_and(|h| h == "catch" || h == "finally");
                if !is_clause {
                    definition_nodes(item, out);
                }
            }
        }
        _ => {
            for item in items {
                definition_nodes(item, out);
            }
        }
    }
}

/// The name node a `define`/`define-typed` form binds.
#[must_use]
pub fn defined_name_node(items: &[Spanned]) -> Option<&Spanned> {
    let head = items.first()?.as_symbol()?;
    if head != "define" && head != "define-typed" {
        return None;
    }
    let target = items.get(1)?;
    if target.as_symbol().is_some() {
        return Some(target);
    }
    let name = target.as_list()?.first()?;
    name.as_symbol().map(|_| name)
}

/// A lambda parameter list: symbols, skipping `&rest`/`&optional`/`.`
/// markers; a bare symbol is a variadic parameter.
#[must_use]
pub fn params_of(list: &Spanned) -> Vec<(String, Span)> {
    if let Some(n) = list.as_symbol() {
        return vec![(n.to_string(), list.span)];
    }
    list.as_list()
        .map(|ps| ps.iter().filter_map(param).collect())
        .unwrap_or_default()
}

fn param(p: &Spanned) -> Option<(String, Span)> {
    let n = p.as_symbol()?;
    if n.starts_with('&') || n == "." {
        return None;
    }
    Some((n.to_string(), p.span))
}

struct Walker<'p> {
    pass: &'p mut dyn Scopes,
    /// Open frames. Zero at the top level of a form.
    depth: usize,
}

impl Walker<'_> {
    fn open(&mut self) {
        self.depth += 1;
        self.pass.open();
    }

    fn close(&mut self) {
        self.depth -= 1;
        self.pass.close();
    }

    /// Bind, in the current frame, every `define` a body reaches without
    /// crossing a frame boundary — so a body can read a local defined later in
    /// it, as a closure over the frame can at runtime.
    fn hoist(&mut self, body: &[Spanned]) {
        for f in body {
            let function = f.as_list().is_some_and(|items| {
                items.first().and_then(Spanned::as_symbol) == Some("define")
                    && items.get(1).is_some_and(|t| t.as_list().is_some())
            });
            let pass = &mut *self.pass;
            definition_nodes(f, &mut |node, kind| {
                let Some(name) = node.as_symbol() else { return };
                let bk = match kind {
                    HeadKind::Value if !function => BinderKind::Assignment,
                    _ => BinderKind::Function,
                };
                pass.bind(name, node.span, bk);
            });
        }
    }

    /// Walk a body: a new frame, its parameters bound, its defines hoisted,
    /// each form walked.
    fn body(&mut self, params: &[(String, Span)], forms: &[Spanned], opaque: bool) {
        self.open();
        for (p, s) in params {
            self.pass.bind(p, *s, BinderKind::Parameter);
        }
        self.hoist(forms);
        for f in forms {
            self.walk(f, opaque);
        }
        self.close();
    }

    fn walk(&mut self, form: &Spanned, opaque: bool) {
        match &form.form {
            SpannedForm::Atom(Atom::Symbol(n)) => self.pass.reference(form, n, opaque),
            SpannedForm::Quote(_) => {}
            SpannedForm::Quasiquote(inner) => self.walk_template(inner, opaque),
            SpannedForm::Unquote(inner) | SpannedForm::UnquoteSplice(inner) => {
                self.walk(inner, opaque);
            }
            SpannedForm::List(items) if !items.is_empty() => self.walk_list(items, opaque),
            _ => {}
        }
    }

    /// Inside a quasiquote only the unquoted parts are code.
    fn walk_template(&mut self, form: &Spanned, opaque: bool) {
        match &form.form {
            SpannedForm::Atom(Atom::Symbol(n)) => self.pass.template_symbol(form, n),
            SpannedForm::Unquote(inner) | SpannedForm::UnquoteSplice(inner) => {
                self.walk(inner, opaque);
            }
            SpannedForm::List(items) => {
                for i in items {
                    self.walk_template(i, opaque);
                }
            }
            SpannedForm::Quasiquote(inner) => self.walk_template(inner, opaque),
            _ => {}
        }
    }

    fn walk_all(&mut self, items: &[Spanned], opaque: bool) {
        for i in items {
            self.walk(i, opaque);
        }
    }

    fn walk_list(&mut self, items: &[Spanned], opaque: bool) {
        let Some(head) = items[0].as_symbol() else {
            self.walk_all(items, opaque);
            return;
        };
        // `deftest` is the test harness's declaration, not a special form: a
        // body, run in a frame of its own.
        if head == "deftest" && self.depth == 0 {
            if let Some(body) = items.get(2) {
                self.body(&[], std::slice::from_ref(body), opaque);
            }
            return;
        }
        // `use("x", [:a])` at the top level is a declaration the resolver
        // consumed, not a call: nothing in it is a reference.
        if head == "use" && self.depth == 0 {
            self.pass.head(&items[0], head, HeadKind::SpecialForm);
            return;
        }
        // `define-typed` is erased before evaluation; its shape is `define`'s
        // with each parameter written `(name Type)`.
        if head == "define" || head == "define-typed" {
            self.pass.head(&items[0], head, HeadKind::SpecialForm);
            self.walk_define(head, items, opaque);
            return;
        }
        // `defmacro` is registered by the expander before evaluation, not
        // dispatched as a special form, so no arbiter claims it as a head.
        // `(defmacro name (params) body…)`.
        if head == "defmacro" && self.depth == 0 {
            self.pass.head(&items[0], head, HeadKind::SpecialForm);
            let params = items.get(2).map(params_of).unwrap_or_default();
            self.body(&params, items.get(3..).unwrap_or(&[]), opaque);
            return;
        }
        match self.pass.head_kind(head) {
            Some(HeadKind::SpecialForm) => {
                self.pass.head(&items[0], head, HeadKind::SpecialForm);
                self.walk_special(head, items, opaque);
            }
            Some(HeadKind::Macro) => {
                // Opaque: a macro's arguments are syntax.
                self.pass.head(&items[0], head, HeadKind::Macro);
                for i in &items[1..] {
                    self.walk(i, true);
                }
            }
            Some(HeadKind::Value) | None => {
                self.walk(&items[0], opaque);
                self.walk_all(&items[1..], opaque);
            }
        }
    }

    fn walk_define(&mut self, head: &str, items: &[Spanned], opaque: bool) {
        let Some(target) = items.get(1) else { return };
        if target.as_symbol().is_some() {
            // `(define x e)`: `x` is already bound (hoisted, or a global).
            self.walk_all(&items[2..], opaque);
            return;
        }
        let Some(sig) = target.as_list() else {
            self.walk_all(&items[1..], opaque);
            return;
        };
        let params: Vec<(String, Span)> = sig
            .iter()
            .skip(1)
            .filter_map(|p| {
                if head == "define-typed" {
                    let pair = p.as_list()?;
                    let n = pair.first()?;
                    Some((n.as_symbol()?.to_string(), n.span))
                } else {
                    param(p)
                }
            })
            .collect();
        // `(define-typed sig R body)`: the return type is not code.
        let body_from = if head == "define-typed" { 3 } else { 2 };
        self.body(&params, items.get(body_from..).unwrap_or(&[]), opaque);
    }

    fn walk_special(&mut self, head: &str, items: &[Spanned], opaque: bool) {
        let args = &items[1..];
        match head {
            "quote" | "provide" | "require" => {}
            "quasiquote" => {
                for a in args {
                    self.walk_template(a, opaque);
                }
            }
            "lambda" => {
                let params = args.first().map(params_of).unwrap_or_default();
                self.body(&params, args.get(1..).unwrap_or(&[]), opaque);
            }
            "cond" => {
                for clause in args {
                    match clause.as_list() {
                        Some(parts) => {
                            let rest = match parts.first().and_then(Spanned::as_symbol) {
                                Some("else") => &parts[1..],
                                _ => parts,
                            };
                            for p in rest {
                                if p.as_symbol() != Some("=>") {
                                    self.walk(p, opaque);
                                }
                            }
                        }
                        None => self.walk(clause, opaque),
                    }
                }
            }
            "let" | "let*" | "letrec" => self.walk_let(head, args, opaque),
            "try" => {
                for a in args {
                    let clause = a.as_list();
                    match clause.and_then(|c| c.first()).and_then(Spanned::as_symbol) {
                        Some("catch") => {
                            let c = clause.expect("matched");
                            let var = c.get(1).and_then(|v| {
                                v.as_list()
                                    .and_then(|l| l.first())
                                    .and_then(|s| s.as_symbol().map(|n| (n.to_string(), s.span)))
                                    .or_else(|| v.as_symbol().map(|n| (n.to_string(), v.span)))
                            });
                            self.open();
                            if let Some((n, s)) = var {
                                self.pass.bind(&n, s, BinderKind::Catch);
                            }
                            self.walk_all(c.get(2..).unwrap_or(&[]), opaque);
                            self.close();
                        }
                        Some("finally") => {
                            let c = clause.expect("matched");
                            self.walk_all(&c[1..], opaque);
                        }
                        _ => self.walk(a, opaque),
                    }
                }
            }
            // if, when, unless, and, or, not, begin, set!, delay, eval,
            // macroexpand, macroexpand-1: every part is an expression.
            _ => self.walk_all(args, opaque),
        }
    }

    fn walk_let(&mut self, head: &str, args: &[Spanned], opaque: bool) {
        // Named let: `(let name ((a e) …) body…)`.
        let (name, rest) = match args.first() {
            Some(n) if n.as_symbol().is_some() && head == "let" => (Some(n), &args[1..]),
            _ => (None, args),
        };
        let Some(bindings) = rest.first().and_then(Spanned::as_list) else {
            self.walk_all(rest, opaque);
            return;
        };
        let pairs: Vec<(String, Span, Option<&Spanned>)> = bindings
            .iter()
            .filter_map(|b| match b.as_list() {
                Some(pair) => {
                    let n = pair.first()?;
                    Some((n.as_symbol()?.to_string(), n.span, pair.get(1)))
                }
                None => b.as_symbol().map(|n| (n.to_string(), b.span, None)),
            })
            .collect();
        let body = rest.get(1..).unwrap_or(&[]);
        if head == "let" {
            // Inits see the OUTER scope: walk them before the frame opens.
            for (_, _, init) in &pairs {
                if let Some(e) = init {
                    self.walk(e, opaque);
                }
            }
        }
        self.open();
        match head {
            "let" => {
                if let Some(n) = name {
                    self.pass
                        .bind(n.as_symbol().expect("matched"), n.span, BinderKind::Function);
                }
                for (n, s, _) in &pairs {
                    self.pass.bind(n, *s, BinderKind::Let);
                }
            }
            "let*" => {
                for (n, s, init) in &pairs {
                    if let Some(e) = init {
                        self.walk(e, opaque);
                    }
                    self.pass.bind(n, *s, BinderKind::Let);
                }
            }
            _ => {
                for (n, s, _) in &pairs {
                    self.pass.bind(n, *s, BinderKind::Let);
                }
                for (_, _, init) in &pairs {
                    if let Some(e) = init {
                        self.walk(e, opaque);
                    }
                }
            }
        }
        self.hoist(body);
        self.walk_all(body, opaque);
        self.close();
    }
}
