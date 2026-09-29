//! Static name resolution: rules [`B0001`](crate::Code::B0001) (unbound name),
//! [`B0002`](crate::Code::B0002) (unused binding) and
//! [`B0009`](crate::Code::B0009) (ambiguous name).
//!
//! ## Why this exists
//!
//! Before it, a typo inside a function that did not run — `lenght(xs)` in an
//! error branch — passed `blue check`, `blue run` and `blue test`, and failed
//! only when that branch was finally taken, in production. The runtime does
//! resolve every name, but only the names on the path it executes.
//!
//! ## The table is scopes keyed (namespace, name), resolved by TIER
//!
//! [`NameTable`] is **not** one merged map. It is a list of [`Scope`]s, each
//! labelled with the [`Namespace`] its names belong to: the entry file's own
//! definitions, each imported bidama's (under the bidama's name), the test
//! harness's, then blue's builtins split by arbiter (special forms, macros,
//! values). Locals sit in front of all of it, on the walker's own stack.
//!
//! A reference resolves by [`RESOLUTION_ORDER`], the one place the priority is
//! written down:
//!
//! | tier | holds | relative to the referencing form |
//! |---|---|---|
//! | [`Tier::Local`] | parameters and local bindings, innermost first | its enclosing frames |
//! | [`Tier::Own`] | definitions in the same file (entry) or bidama | its own namespace |
//! | [`Tier::Imported`] | every other file's and bidama's definitions | all other program namespaces |
//! | [`Tier::Builtin`] | harness names, special forms, macros, runtime values | the interpreter |
//!
//! The first tier holding the name wins. **Two namespaces in the SAME tier
//! holding it is [`B0009`](crate::Code::B0009)**, an error: nothing in the
//! program says which was meant. No tier holding it is
//! [`B0001`](crate::Code::B0001), with did-you-mean candidates that each name
//! their namespace. Per-bidama namespaces will change which scopes a tier
//! contains and add qualified names that pick one; they re-point this list,
//! not the walker.
//!
//! ## What the RUNTIME does today, measured (2026-09-29)
//!
//! The list above is the check's contract, and it agrees with the runtime on
//! every program the check accepts — but the runtime does not implement it as
//! a list. `resolve_uses` splices every file into one program whose top-level
//! `define`s all land in ONE global environment, so at runtime the binding a
//! name has is whichever `define` of it ran LAST. Three consequences, each
//! pinned by a test in `blue-lang-runtime/tests/resolution_order.rs`:
//!
//! - **A bidama's definition replaces a builtin program-wide.** A bidama that
//!   defines `first` rebinds `first` for every file, the entry file and the
//!   builtins' other callers included. The check agrees for the importer
//!   (Imported beats Builtin). Measured over the whole distribution: 17 such
//!   definitions in 5 bidamas, pinned by name in `blue-lang-cli`'s
//!   `tests/check_corpus.rs`.
//! - **An importer's definition replaces a bidama's for the bidama too.** The
//!   entry file's `use` runs first, so an entry `def foo` evaluated after it
//!   overwrites the bidama's `foo`, and the bidama's OWN calls to `foo` then
//!   reach the importer's. The check says the bidama's reference resolves to
//!   its own `foo` (Own beats Imported). The check reports no diagnostic in
//!   either reading (both are bound), so no program's verdict changes; the
//!   divergence is in which definition runs, and it is the namespace track's
//!   to close.
//! - **A macro or special form beats every definition, for a head.** See
//!   below. A program `def while(…)` is never called by `while(…)`.//! ## Which arbiter a HEAD answers to
//!
//! For the head of a call, the evaluator does not consult scopes in order: a
//! special form wins over everything, then a macro wins over any binding of the
//! same name, and only then is the environment searched (`Interpreter::
//! resolve_head` documents the three arbiters). [`NameTable::head_kind`]
//! answers in that order, so the walker treats `if` as a special form even
//! where a local named `if` could exist, exactly as the evaluator would.
//!
//! ## What the walker knows about each form
//!
//! It walks the tree the parser produced (annotations intact), with the
//! binding rules of tatara-lisp's special forms: `lambda` and `define`
//! introduce parameters; `let`, `let*` and `letrec` their bindings; `try`'s
//! `catch` clause its variable; a `define` inside a body binds in that body's
//! frame, including through `if`, `cond` and `begin`, which open no frame of
//! their own. `quote` is data and is not walked; inside a quasiquote only the
//! `unquote`d parts are code.
//!
//! **A call to a macro is opaque.** Its arguments are syntax the macro may
//! rebind or never evaluate, so names inside them are marked as read (no
//! false "unused" on a variable a macro consumes) but never reported unbound.
//! This is a scoped leniency, not a hole in the rule: it covers only a
//! macro's argument forms, and blue's own lowering calls no macro.

use std::collections::{BTreeMap, BTreeSet};

use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::rules::Code;
use crate::suggest;
use crate::{Applicability, Diagnostic, Edit, Fix};

/// A resolution priority level. See [`RESOLUTION_ORDER`].
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Tier {
    /// A binding of an enclosing function, `let` or `catch`.
    Local,
    /// A definition in the referencing form's own file or bidama.
    Own,
    /// A definition in any other file or bidama of the program.
    Imported,
    /// What the interpreter binds before the program runs.
    Builtin,
}

/// **The resolution priority, as data.** The first tier that holds a name
/// wins; two namespaces in one tier is an ambiguity. The namespace track
/// re-points this list and [`Namespace::tier`], not the walker.
pub const RESOLUTION_ORDER: [Tier; 4] = [Tier::Local, Tier::Own, Tier::Imported, Tier::Builtin];

/// Where a name lives. The unit a future qualified name will select.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Namespace {
    /// A parameter or binding of an enclosing function, `let`, or `catch`.
    Local,
    /// The file being checked, by the label it is reported under.
    File(String),
    /// An imported bidama, by the name `use` was given.
    Bidama(String),
    /// Names only the test harness binds (`blue-assert`).
    Harness,
    /// tatara-lisp's special forms: `if`, `lambda`, `define`, …
    SpecialForm,
    /// Macros the runtime registers.
    Macro,
    /// Every value the runtime binds: primitives, the stdlib, blue's core.
    Builtin,
}

impl std::fmt::Display for Namespace {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Namespace::Local => f.write_str("local"),
            Namespace::File(_) => f.write_str("this file"),
            Namespace::Bidama(b) => write!(f, "bidama `{b}`"),
            Namespace::Harness => f.write_str("test harness"),
            Namespace::SpecialForm => f.write_str("special form"),
            Namespace::Macro => f.write_str("builtin macro"),
            Namespace::Builtin => f.write_str("builtin"),
        }
    }
}

impl Namespace {
    /// The tier this namespace sits in for a reference made from `own`.
    #[must_use]
    pub fn tier(&self, own: &Namespace) -> Tier {
        match self {
            Namespace::Local => Tier::Local,
            Namespace::File(_) | Namespace::Bidama(_) if self == own => Tier::Own,
            Namespace::File(_) | Namespace::Bidama(_) => Tier::Imported,
            Namespace::Harness | Namespace::SpecialForm | Namespace::Macro | Namespace::Builtin => {
                Tier::Builtin
            }
        }
    }
}

/// What a reference resolved to.
#[derive(Debug)]
pub enum Resolution<'t> {
    Found {
        tier: Tier,
        scope: &'t Scope,
        binding: &'t Binding,
    },
    /// More than one namespace in the first tier that holds the name.
    Ambiguous {
        tier: Tier,
        namespaces: Vec<&'t Namespace>,
    },
    Unbound,
}

/// Which of the evaluator's three arbiters a name is bound by.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScopeKind {
    SpecialForm,
    Macro,
    Value,
}

/// One bound name.
#[derive(Clone, Debug, PartialEq)]
pub struct Binding {
    pub name: String,
    pub kind: ScopeKind,
    /// Where it is defined, when it is defined in source.
    pub span: Option<Span>,
    /// The top-level form that defines it, when it is defined in source.
    pub top_level: Option<usize>,
}

/// One namespace's names.
#[derive(Clone, Debug)]
pub struct Scope {
    pub namespace: Namespace,
    bindings: BTreeMap<String, Binding>,
}

impl Scope {
    #[must_use]
    pub fn new(namespace: Namespace) -> Self {
        Self {
            namespace,
            bindings: BTreeMap::new(),
        }
    }

    /// Bind a name. A second binding of the same name keeps the first: that
    /// is where a reader should be sent.
    pub fn bind(&mut self, binding: Binding) {
        self.bindings.entry(binding.name.clone()).or_insert(binding);
    }

    #[must_use]
    pub fn get(&self, name: &str) -> Option<&Binding> {
        self.bindings.get(name)
    }

    pub fn bindings(&self) -> impl Iterator<Item = &Binding> {
        self.bindings.values()
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.bindings.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.bindings.is_empty()
    }
}

/// Every non-local scope, in resolution order.
#[derive(Clone, Debug, Default)]
pub struct NameTable {
    scopes: Vec<Scope>,
}

/// A "did you mean" candidate: a name, the namespace it lives in, and how far
/// it is from what was written.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Candidate {
    pub name: String,
    pub namespace: Namespace,
    pub distance: usize,
}

impl NameTable {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Append a scope; it resolves after every scope already present.
    pub fn push(&mut self, scope: Scope) {
        self.scopes.push(scope);
    }

    /// The scope for `namespace`, created at the end of the order if absent.
    pub fn scope_mut(&mut self, namespace: Namespace) -> &mut Scope {
        if let Some(i) = self.scopes.iter().position(|s| s.namespace == namespace) {
            return &mut self.scopes[i];
        }
        self.scopes.push(Scope::new(namespace));
        self.scopes.last_mut().expect("just pushed")
    }

    #[must_use]
    pub fn scopes(&self) -> &[Scope] {
        &self.scopes
    }

    /// Bind every top-level definition in `forms` into the namespace
    /// `namespace_of(i)` names for form `i`.
    pub fn add_program(&mut self, forms: &[Spanned], namespace_of: impl Fn(usize) -> Namespace) {
        for (i, form) in forms.iter().enumerate() {
            let ns = namespace_of(i);
            let mut found = Vec::new();
            definitions_in(form, &mut found);
            let scope = self.scope_mut(ns);
            for (name, span, kind) in found {
                scope.bind(Binding {
                    name,
                    kind,
                    span: Some(span),
                    top_level: Some(i),
                });
            }
        }
    }

    /// Resolve `name` for a reference made from namespace `own`, by
    /// [`RESOLUTION_ORDER`]. Locals are the walker's; this starts at
    /// [`Tier::Own`].
    #[must_use]
    pub fn resolve_from(&self, name: &str, own: &Namespace) -> Resolution<'_> {
        for tier in RESOLUTION_ORDER {
            let hits: Vec<(&Scope, &Binding)> = self
                .scopes
                .iter()
                .filter(|s| s.namespace.tier(own) == tier)
                .filter_map(|s| s.get(name).map(|b| (s, b)))
                .collect();
            match hits.as_slice() {
                [] => {}
                [(scope, binding)] => {
                    return Resolution::Found {
                        tier,
                        scope,
                        binding,
                    }
                }
                many => {
                    // The builtin tier's scopes are split by ARBITER, and a
                    // name has one arbiter (`builtin_names` sorts each name
                    // into the scope `resolve_head` names), so several hits
                    // there are the evaluator's head order, not ambiguity.
                    if tier == Tier::Builtin {
                        let (scope, binding) = many[0];
                        return Resolution::Found {
                            tier,
                            scope,
                            binding,
                        };
                    }
                    return Resolution::Ambiguous {
                        tier,
                        namespaces: many.iter().map(|(s, _)| &s.namespace).collect(),
                    };
                }
            }
        }
        Resolution::Unbound
    }

    /// Which arbiter claims `name` in HEAD position, in the evaluator's order:
    /// special form, then macro, then value.
    #[must_use]
    pub fn head_kind(&self, name: &str) -> Option<ScopeKind> {
        let kinds: Vec<ScopeKind> = self
            .scopes
            .iter()
            .filter_map(|s| s.get(name).map(|b| b.kind))
            .collect();
        [ScopeKind::SpecialForm, ScopeKind::Macro, ScopeKind::Value]
            .into_iter()
            .find(|k| kinds.contains(k))
    }

    /// Every name in every scope, with its namespace.
    pub fn all(&self) -> impl Iterator<Item = (&Namespace, &Binding)> {
        self.scopes
            .iter()
            .flat_map(|s| s.bindings().map(move |b| (&s.namespace, b)))
    }

    /// The nearest names to `wanted`, best first, at most `limit`, drawn from
    /// `locals` and every scope. Ties break on resolution order, then name.
    #[must_use]
    pub fn candidates(&self, wanted: &str, locals: &[&str], limit: usize) -> Vec<Candidate> {
        let mut seen = BTreeSet::new();
        let mut out: Vec<(usize, usize, Candidate)> = Vec::new();
        let scoped = locals
            .iter()
            .map(|n| (Namespace::Local, *n))
            .chain(self.all().map(|(ns, b)| (ns.clone(), b.name.as_str())));
        for (order, (namespace, name)) in scoped.enumerate() {
            if !seen.insert(name.to_string()) {
                continue;
            }
            // A name the surface cannot spell is no suggestion: `hash-map` is
            // bound, and nobody can type it.
            if !spellable(name) {
                continue;
            }
            if let Some(distance) = suggest::closeness(wanted, name) {
                out.push((
                    distance,
                    order,
                    Candidate {
                        name: name.to_string(),
                        namespace,
                        distance,
                    },
                ));
            }
        }
        out.sort_by_key(|a| (a.0, a.1));
        out.into_iter().take(limit).map(|(_, _, c)| c).collect()
    }
}

/// Can a blue author write this name as an identifier?
fn spellable(name: &str) -> bool {
    let mut chars = name.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_alphabetic() || c == '_')
        && chars
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '?' || c == '!' || !c.is_ascii())
}

/// The names a form defines into the frame it is evaluated in.
///
/// A `define` binds in the environment it is EVALUATED in, and every part of
/// a form is evaluated in the enclosing environment except the parts of a
/// frame-opening form (`lambda`, a function `define`, `let`, a `catch`
/// clause, a test body) and quoted data. So this descends into every
/// sub-form but those: `x = if c … else y = 1 … end` binds `y` in the
/// function's frame, which is where a later `fn(s) … y … end` reads it.
fn definitions_in(form: &Spanned, out: &mut Vec<(String, Span, ScopeKind)>) {
    let Some(items) = form.as_list() else { return };
    let head = items.first().and_then(Spanned::as_symbol);
    match head {
        Some("defmacro") => {
            if let Some(n) = items.get(1).filter(|n| n.as_symbol().is_some()) {
                out.push((
                    n.as_symbol().expect("filtered").to_string(),
                    n.span,
                    ScopeKind::Macro,
                ));
            }
        }
        Some("define" | "define-typed") => {
            if let Some((name, span)) = defined_name(items) {
                out.push((name, span, ScopeKind::Value));
            }
            // `(define x e)`: `e` is evaluated right here, so its defines are
            // this frame's too. A function define opens a frame; stop.
            if items.get(1).is_some_and(|t| t.as_symbol().is_some()) {
                for item in &items[2..] {
                    definitions_in(item, out);
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
                    definitions_in(item, out);
                }
            }
        }
        _ => {
            for item in items {
                definitions_in(item, out);
            }
        }
    }
}

/// The name a `define`/`define-typed` form binds, and the span of the name.
fn defined_name(items: &[Spanned]) -> Option<(String, Span)> {
    let head = items.first()?.as_symbol()?;
    if head != "define" && head != "define-typed" {
        return None;
    }
    let target = items.get(1)?;
    if let Some(n) = target.as_symbol() {
        return Some((n.to_string(), target.span));
    }
    let sig = target.as_list()?;
    let name = sig.first()?;
    Some((name.as_symbol()?.to_string(), name.span))
}

/// What a local was introduced by — for the unused-binding message.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum LocalKind {
    Parameter,
    Assignment,
    Function,
    Let,
    Catch,
}

impl LocalKind {
    fn noun(self) -> &'static str {
        match self {
            LocalKind::Parameter => "parameter",
            LocalKind::Assignment => "binding",
            LocalKind::Function => "local function",
            LocalKind::Let => "binding",
            LocalKind::Catch => "caught error",
        }
    }
}

#[derive(Debug)]
struct Local {
    name: String,
    span: Span,
    kind: LocalKind,
    used: bool,
}

/// What the walker reports into.
struct Walker<'t> {
    table: &'t NameTable,
    /// The namespace of the top-level form being walked: its [`Tier::Own`].
    own: Namespace,
    frames: Vec<Vec<Local>>,
    top_level: usize,
    report_unused: bool,
    /// Every symbol written in the current top-level form, so a rename fix
    /// can prove its new name is not already in use there.
    symbols: BTreeSet<String>,
    diagnostics: Vec<Diagnostic>,
    /// Names resolved, for the report.
    resolved: usize,
}

/// Names the parser synthesizes. Never reported unused: the author did not
/// write them.
const SYNTHESIZED: &[&str] = &["case-subject"];

/// Resolve every name in `forms` against `table`.
///
/// `namespace_of(i)` is the namespace top-level form `i` was defined in — the
/// same function [`NameTable::add_program`] was given — which decides what is
/// [`Tier::Own`] for it. `report_unused(i)` says whether top-level form `i` gets unused-binding
/// warnings — the caller's entry file does, an imported package does not
/// (its warnings are its own author's). Unbound names are reported
/// everywhere: an imported package with one is broken for its importer.
///
/// Returns the diagnostics (stamped with their top-level index) and the count
/// of names resolved.
#[must_use]
pub fn check_names(
    forms: &[Spanned],
    table: &NameTable,
    namespace_of: &dyn Fn(usize) -> Namespace,
    report_unused: &dyn Fn(usize) -> bool,
) -> (Vec<Diagnostic>, usize) {
    let mut w = Walker {
        table,
        own: Namespace::Local,
        frames: Vec::new(),
        top_level: 0,
        report_unused: false,
        symbols: BTreeSet::new(),
        diagnostics: Vec::new(),
        resolved: 0,
    };
    for (i, form) in forms.iter().enumerate() {
        w.top_level = i;
        w.own = namespace_of(i);
        w.report_unused = report_unused(i);
        w.symbols.clear();
        collect_symbols(form, &mut w.symbols);
        // A top-level form's own defines are globals, already in `table`.
        w.walk(form, false);
    }
    (w.diagnostics, w.resolved)
}

fn collect_symbols(form: &Spanned, out: &mut BTreeSet<String>) {
    match &form.form {
        SpannedForm::Atom(Atom::Symbol(s)) => {
            out.insert(s.clone());
        }
        SpannedForm::List(items) => items.iter().for_each(|i| collect_symbols(i, out)),
        SpannedForm::Quote(i)
        | SpannedForm::Quasiquote(i)
        | SpannedForm::Unquote(i)
        | SpannedForm::UnquoteSplice(i) => collect_symbols(i, out),
        _ => {}
    }
}

impl Walker<'_> {
    fn locals_in_scope(&self) -> Vec<&str> {
        self.frames
            .iter()
            .rev()
            .flat_map(|f| f.iter().map(|l| l.name.as_str()))
            .collect()
    }

    /// Resolve a local by name, innermost first, marking it read.
    fn read_local(&mut self, name: &str) -> bool {
        for frame in self.frames.iter_mut().rev() {
            if let Some(l) = frame.iter_mut().rev().find(|l| l.name == name) {
                l.used = true;
                return true;
            }
        }
        false
    }

    /// A reference to `name` at `span`. `opaque`: inside a macro's arguments,
    /// where an unresolved name is not reported.
    fn reference(&mut self, name: &str, span: Span, opaque: bool) {
        if self.read_local(name) {
            self.resolved += 1;
            return;
        }
        match self.table.resolve_from(name, &self.own) {
            Resolution::Found { .. } => {
                self.resolved += 1;
                return;
            }
            Resolution::Ambiguous { tier, namespaces } => {
                let list = namespaces
                    .iter()
                    .map(ToString::to_string)
                    .collect::<Vec<_>>()
                    .join(" and ");
                let mut d = Diagnostic::new(
                    Code::B0009,
                    format!("`{name}` is defined in both {list}"),
                    span,
                )
                .at_top_level(self.top_level)
                .with_help(format!(
                    "both are {tier:?}-tier definitions, so nothing says which is meant; rename one of them"
                ));
                for ns in &namespaces {
                    if let Some(b) = self
                        .table
                        .scopes()
                        .iter()
                        .find(|s| &&s.namespace == ns)
                        .and_then(|s| s.get(name))
                    {
                        // Related spans must be in THIS form's file; a
                        // definition elsewhere is named in the message only.
                        if b.top_level == Some(self.top_level) {
                            if let Some(sp) = b.span {
                                d = d.with_related(sp, format!("defined in {ns}"));
                            }
                        }
                    }
                }
                self.diagnostics.push(d);
                return;
            }
            Resolution::Unbound => {}
        }
        // Names blue cannot spell and no program binds (`a/b` module paths
        // from `require`) are the module system's, not this pass's.
        if name.contains('/') || opaque {
            return;
        }
        let locals = self.locals_in_scope();
        let candidates = self.table.candidates(name, &locals, 3);
        let mut d = Diagnostic::new(Code::B0001, format!("unbound name `{name}`"), span)
            .at_top_level(self.top_level);
        d = match candidates.as_slice() {
            [] => d.with_help(
                "no name in scope is close to it; define it, or `use` the bidama that defines it",
            ),
            [one] => d.with_help(format!("did you mean `{}` ({})?", one.name, one.namespace)),
            many => d.with_help(format!(
                "did you mean {}?",
                many.iter()
                    .map(|c| format!("`{}` ({})", c.name, c.namespace))
                    .collect::<Vec<_>>()
                    .join(", ")
            )),
        };
        for c in &candidates {
            d = d.with_fix(Fix {
                message: format!("replace with `{}` ({})", c.name, c.namespace),
                edits: vec![Edit {
                    span,
                    original: name.to_string(),
                    replacement: c.name.clone(),
                }],
                applicability: Applicability::MaybeIncorrect,
            });
        }
        self.diagnostics.push(d);
    }

    fn push_frame(&mut self) {
        self.frames.push(Vec::new());
    }

    fn bind(&mut self, name: &str, span: Span, kind: LocalKind) {
        let frame = self.frames.last_mut().expect("bind with a frame open");
        // A second `define` of a name already in THIS frame (`x = x + 1`) is a
        // write to the same binding, not a new one.
        if frame.iter().any(|l| l.name == name) {
            return;
        }
        frame.push(Local {
            name: name.to_string(),
            span,
            kind,
            used: false,
        });
    }

    fn pop_frame(&mut self) {
        let frame = self.frames.pop().expect("pop with a frame open");
        if !self.report_unused {
            return;
        }
        for l in frame {
            if l.used || l.name.starts_with('_') || SYNTHESIZED.contains(&l.name.as_str()) {
                continue;
            }
            let renamed = format!("_{}", l.name);
            let mut d = Diagnostic::new(
                Code::B0002,
                format!("{} `{}` is never read", l.kind.noun(), l.name),
                l.span,
            )
            .at_top_level(self.top_level)
            .with_help(format!(
                "rename it `{renamed}` to say it is deliberately unused, or remove it"
            ));
            // Machine-applicable only when the new name appears nowhere in the
            // definition: then no reference can be captured by the rename.
            if !self.symbols.contains(&renamed) {
                d = d.with_fix(Fix {
                    message: format!("rename to `{renamed}`"),
                    edits: vec![Edit {
                        span: l.span,
                        original: l.name.clone(),
                        replacement: renamed,
                    }],
                    applicability: Applicability::MachineApplicable,
                });
            }
            self.diagnostics.push(d);
        }
    }

    /// Bind, in the current frame, every `define` a body reaches without
    /// crossing a frame boundary — so a body can read a local defined later in
    /// it, as a closure over the frame can at runtime.
    fn hoist(&mut self, body: &[Spanned]) {
        let mut found = Vec::new();
        for f in body {
            definitions_in(f, &mut found);
        }
        for (name, span, kind) in found {
            let lk = match kind {
                ScopeKind::Value => LocalKind::Assignment,
                _ => LocalKind::Function,
            };
            self.bind(&name, span, lk);
        }
        // A `(define (f …) …)` is a local FUNCTION, which reads better in the
        // warning than "binding".
        for f in body {
            if let Some(items) = f.as_list() {
                if items.first().and_then(Spanned::as_symbol) == Some("define")
                    && items.get(1).is_some_and(|t| t.as_list().is_some())
                {
                    if let Some((name, _)) = defined_name(items) {
                        if let Some(l) = self
                            .frames
                            .last_mut()
                            .and_then(|fr| fr.iter_mut().find(|l| l.name == name))
                        {
                            l.kind = LocalKind::Function;
                        }
                    }
                }
            }
        }
    }

    /// Walk a body: a new frame, its defines hoisted, each form walked.
    fn body(&mut self, params: &[(String, Span)], forms: &[Spanned], opaque: bool) {
        self.push_frame();
        for (p, s) in params {
            self.bind(p, *s, LocalKind::Parameter);
        }
        self.hoist(forms);
        for f in forms {
            self.walk(f, opaque);
        }
        self.pop_frame();
    }

    fn walk(&mut self, form: &Spanned, opaque: bool) {
        match &form.form {
            SpannedForm::Atom(Atom::Symbol(n)) => self.reference(n, form.span, opaque),
            SpannedForm::Quote(_) => {}
            SpannedForm::Quasiquote(inner) => self.walk_template(inner, opaque),
            SpannedForm::Unquote(inner) | SpannedForm::UnquoteSplice(inner) => {
                self.walk(inner, opaque);
            }
            SpannedForm::List(items) if !items.is_empty() => self.walk_list(form, items, opaque),
            _ => {}
        }
    }

    /// Inside a quasiquote only the unquoted parts are code.
    fn walk_template(&mut self, form: &Spanned, opaque: bool) {
        match &form.form {
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

    #[allow(clippy::too_many_lines)]
    fn walk_list(&mut self, form: &Spanned, items: &[Spanned], opaque: bool) {
        let Some(head) = items[0].as_symbol() else {
            self.walk_all(items, opaque);
            return;
        };
        let _ = form;
        // `deftest` is the test harness's declaration, not a special form: a
        // body, run in a frame of its own.
        if head == "deftest" && self.frames.is_empty() {
            if let Some(body) = items.get(2) {
                self.body(&[], std::slice::from_ref(body), opaque);
            }
            return;
        }
        // `define-typed` is erased before evaluation; its shape is `define`'s
        // with each parameter written `(name Type)`.
        if head == "define" || head == "define-typed" {
            self.walk_define(head, items, opaque);
            return;
        }
        // `defmacro` is registered by the expander before evaluation, not
        // dispatched as a special form, so no arbiter claims it as a head.
        // `(defmacro name (params) body…)`.
        if head == "defmacro" && self.frames.is_empty() {
            let params = items.get(2).map(params_of).unwrap_or_default();
            self.body(&params, items.get(3..).unwrap_or(&[]), opaque);
            return;
        }
        match self.table.head_kind(head) {
            Some(ScopeKind::SpecialForm) => self.walk_special(head, items, opaque),
            Some(ScopeKind::Macro) => {
                // Opaque: a macro's arguments are syntax. See the module docs.
                self.resolved += 1;
                for i in &items[1..] {
                    self.walk(i, true);
                }
            }
            Some(ScopeKind::Value) | None => {
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

    #[allow(clippy::too_many_lines)]
    fn walk_special(&mut self, head: &str, items: &[Spanned], opaque: bool) {
        self.resolved += 1;
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
                            self.push_frame();
                            if let Some((n, s)) = var {
                                self.bind(&n, s, LocalKind::Catch);
                            }
                            self.walk_all(c.get(2..).unwrap_or(&[]), opaque);
                            self.pop_frame();
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
        self.push_frame();
        match head {
            "let" => {
                if let Some(n) = name {
                    self.bind(n.as_symbol().expect("matched"), n.span, LocalKind::Function);
                }
                for (n, s, _) in &pairs {
                    self.bind(n, *s, LocalKind::Let);
                }
            }
            "let*" => {
                for (n, s, init) in &pairs {
                    if let Some(e) = init {
                        self.walk(e, opaque);
                    }
                    self.bind(n, *s, LocalKind::Let);
                }
            }
            _ => {
                for (n, s, _) in &pairs {
                    self.bind(n, *s, LocalKind::Let);
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
        self.pop_frame();
    }
}

/// A lambda parameter list: symbols, skipping `&rest`/`&optional`/`.`
/// markers; a bare symbol is a variadic parameter.
fn params_of(list: &Spanned) -> Vec<(String, Span)> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use blue_lang_syntax::parse_program_tree;

    /// A table with a handful of builtins, standing in for the runtime's.
    fn table(forms: &[Spanned]) -> NameTable {
        let mut t = NameTable::new();
        t.add_program(forms, |_| Namespace::File("t.b".into()));
        let mut sf = Scope::new(Namespace::SpecialForm);
        for n in [
            "if", "lambda", "define", "begin", "let", "cond", "quote", "not", "set!", "try",
        ] {
            sf.bind(Binding {
                name: n.into(),
                kind: ScopeKind::SpecialForm,
                span: None,
                top_level: None,
            });
        }
        t.push(sf);
        let mut m = Scope::new(Namespace::Macro);
        m.bind(Binding {
            name: "while".into(),
            kind: ScopeKind::Macro,
            span: None,
            top_level: None,
        });
        t.push(m);
        let mut b = Scope::new(Namespace::Builtin);
        for n in [
            "+", "-", "*", "<", "length", "first", "map", "equal?", "list",
        ] {
            b.bind(Binding {
                name: n.into(),
                kind: ScopeKind::Value,
                span: None,
                top_level: None,
            });
        }
        t.push(b);
        t
    }

    fn check(src: &str) -> Vec<Diagnostic> {
        let forms = parse_program_tree(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
        let t = table(&forms);
        check_names(&forms, &t, &|_| Namespace::File("t.b".into()), &|_| true).0
    }

    fn codes(src: &str) -> Vec<(Code, String)> {
        check(src)
            .into_iter()
            .map(|d| (d.code, d.message))
            .collect()
    }

    fn text(src: &str, span: Span) -> &str {
        &src[span.start..span.end]
    }

    /// The motivating case: a typo in a function nothing calls.
    ///
    /// Red run (2026-09-29): `reference` made to return before reporting an
    /// unbound name: `assertion left == right failed: [] left: 0 right: 1`.
    #[test]
    fn a_typo_in_an_uncalled_function_is_unbound() {
        let src = "def f(xs)\n  lenght(xs)\nend\n";
        let ds = check(src);
        assert_eq!(ds.len(), 1, "{ds:?}");
        let d = &ds[0];
        assert_eq!(d.code, Code::B0001);
        assert_eq!(text(src, d.span), "lenght");
        assert_eq!(d.help.as_deref(), Some("did you mean `length` (builtin)?"));
        assert_eq!(d.fixes.len(), 1);
        assert_eq!(d.fixes[0].edits[0].replacement, "length");
        assert_eq!(d.fixes[0].applicability, Applicability::MaybeIncorrect);
    }

    #[test]
    fn parameters_locals_and_globals_resolve() {
        assert!(codes("def f(a)\n  b = a + 1\n  g(b)\nend\n\ndef g(x)\n  x\nend\n").is_empty());
    }

    /// A body can read a local defined later in it: a closure over the frame
    /// can at runtime, so rejecting it would be a false positive.
    #[test]
    fn a_define_is_hoisted_through_if_to_its_frame() {
        let src = "def f(c)\n  if c\n    y = 1\n  else\n    y = 2\n  end\n  y\nend\n";
        assert!(codes(src).is_empty(), "{:?}", codes(src));
    }

    #[test]
    fn a_lambda_parameter_does_not_escape() {
        let src = "def f(xs)\n  map(xs, fn(x) x + 1 end)\n  x\nend\n";
        let c = codes(src);
        assert_eq!(c.len(), 1, "{c:?}");
        assert_eq!(c[0].0, Code::B0001);
    }

    #[test]
    fn case_binds_its_subject_and_else_is_not_a_name() {
        let src = "def f(n)\n  case n\n  when 1\n    :one\n  else\n    :many\n  end\nend\n";
        assert!(codes(src).is_empty(), "{:?}", codes(src));
    }

    #[test]
    fn quoted_code_is_data_and_unquoted_code_is_code() {
        let src = "defmacro twice(e)\n  quote\n    unquote(e) + unquote(e) + nope\n  end\nend\n";
        assert!(
            codes(src).is_empty(),
            "`nope` is inside the template, not code: {:?}",
            codes(src)
        );
        let src = "defmacro twice(e)\n  quote\n    unquote(ee) + 1\n  end\nend\n";
        let c = codes(src);
        assert_eq!(c.len(), 2, "unbound `ee` and unused `e`: {c:?}");
    }

    /// A macro's arguments are syntax: never reported unbound, still counted
    /// as reads.
    #[test]
    fn a_macro_call_is_opaque_but_reads_its_locals() {
        let src = "def f(x)\n  while(x < 3, whatever)\nend\n";
        assert!(codes(src).is_empty(), "{:?}", codes(src));
    }

    #[test]
    fn an_unused_local_is_a_warning_with_a_machine_fix() {
        let src = "def f(x)\n  y = x + 1\n  x\nend\n";
        let ds = check(src);
        assert_eq!(ds.len(), 1, "{ds:?}");
        let d = &ds[0];
        assert_eq!(d.code, Code::B0002);
        assert_eq!(d.severity, crate::Severity::Warning);
        assert_eq!(text(src, d.span), "y");
        assert_eq!(d.fixes[0].applicability, Applicability::MachineApplicable);
        assert_eq!(d.fixes[0].edits[0].replacement, "_y");
    }

    #[test]
    fn an_underscore_name_is_deliberately_unused() {
        assert!(codes("def f(_x)\n  1\nend\n").is_empty());
    }

    #[test]
    fn the_rename_is_not_machine_applicable_when_the_new_name_is_taken() {
        let src = "def f(x, _x)\n  _x\nend\n";
        let ds = check(src);
        assert_eq!(ds.len(), 1, "{ds:?}");
        assert!(ds[0].fixes.is_empty(), "renaming `x` to `_x` would collide");
    }

    #[test]
    fn unused_warnings_are_only_for_the_forms_asked_about() {
        let forms = parse_program_tree("def f(x)\n  1\nend\n").expect("parse");
        let t = table(&forms);
        assert!(
            check_names(&forms, &t, &|_| Namespace::File("t.b".into()), &|_| false)
                .0
                .is_empty()
        );
    }

    /// Candidates carry their namespace and rank by distance, then order.
    #[test]
    fn candidates_are_ranked_and_carry_their_namespace() {
        let forms = parse_program_tree("def lenth(x)\n  x\nend\n").expect("parse");
        let t = table(&forms);
        let c = t.candidates("lenght", &["lengt"], 3);
        let names: Vec<(&str, String)> = c
            .iter()
            .map(|c| (c.name.as_str(), c.namespace.to_string()))
            .collect();
        assert_eq!(
            names,
            vec![
                // distance 1, and locals rank first among equals
                ("lengt", "local".to_string()),
                ("length", "builtin".to_string()),
                // distance 2: `lenght` -> `lenht` -> `lenth`
                ("lenth", "this file".to_string()),
            ]
        );
    }

    // ---- the tier list, one test per boundary --------------------------

    fn bound(ns: Namespace, names: &[&str]) -> Scope {
        let mut s = Scope::new(ns);
        for n in names {
            s.bind(Binding {
                name: (*n).into(),
                kind: ScopeKind::Value,
                span: None,
                top_level: None,
            });
        }
        s
    }

    fn tiered() -> NameTable {
        let mut t = NameTable::new();
        t.push(bound(Namespace::File("main.b".into()), &["dup", "mine"]));
        t.push(bound(
            Namespace::Bidama("a".into()),
            &["dup", "first", "twice"],
        ));
        t.push(bound(Namespace::Bidama("b".into()), &["twice"]));
        t.push(bound(Namespace::Builtin, &["first", "size"]));
        t
    }

    fn tier_of(t: &NameTable, name: &str, own: &Namespace) -> Option<(Tier, String)> {
        match t.resolve_from(name, own) {
            Resolution::Found { tier, scope, .. } => Some((tier, scope.namespace.to_string())),
            _ => None,
        }
    }

    /// The order is data, and this is it. Moving a tier is a deliberate edit
    /// here, not a side effect somewhere in the walker.
    ///
    /// Red run (2026-09-29): `Own` and `Imported` swapped in
    /// `RESOLUTION_ORDER` — this test, `own_beats_imported` (`left: Some((Imported,
    /// "bidama `a`"))`) and `two_namespaces_in_one_tier_are_ambiguous` go red.
    #[test]
    fn the_resolution_order_is_local_own_imported_builtin() {
        assert_eq!(
            RESOLUTION_ORDER,
            [Tier::Local, Tier::Own, Tier::Imported, Tier::Builtin]
        );
    }

    #[test]
    fn a_local_beats_every_definition() {
        let forms = parse_program_tree("def f(first)\n  first\nend\n").expect("parse");
        let mut t = tiered();
        t.add_program(&forms, |_| Namespace::File("main.b".into()));
        let (ds, _) = check_names(&forms, &t, &|_| Namespace::File("main.b".into()), &|_| true);
        assert!(
            ds.is_empty(),
            "the parameter is read, so it is not unused: {ds:?}"
        );
    }

    #[test]
    fn own_beats_imported() {
        let t = tiered();
        let main = Namespace::File("main.b".into());
        let a = Namespace::Bidama("a".into());
        assert_eq!(
            tier_of(&t, "dup", &main),
            Some((Tier::Own, "this file".into()))
        );
        assert_eq!(
            tier_of(&t, "dup", &a),
            Some((Tier::Own, "bidama `a`".into()))
        );
    }

    #[test]
    fn imported_beats_builtin() {
        let t = tiered();
        let main = Namespace::File("main.b".into());
        assert_eq!(
            tier_of(&t, "first", &main),
            Some((Tier::Imported, "bidama `a`".into()))
        );
        assert_eq!(
            tier_of(&t, "size", &main),
            Some((Tier::Builtin, "builtin".into()))
        );
    }

    /// Two namespaces in the first tier holding the name is an ambiguity —
    /// but not when one of them is the referencing form's own.
    #[test]
    fn two_namespaces_in_one_tier_are_ambiguous() {
        let t = tiered();
        let main = Namespace::File("main.b".into());
        match t.resolve_from("twice", &main) {
            Resolution::Ambiguous { tier, namespaces } => {
                assert_eq!(tier, Tier::Imported);
                assert_eq!(namespaces.len(), 2);
            }
            other => panic!("{other:?}"),
        }
        // From bidama `a`, its own `twice` is Own, and nothing is ambiguous.
        assert_eq!(
            tier_of(&t, "twice", &Namespace::Bidama("a".into())),
            Some((Tier::Own, "bidama `a`".into()))
        );
    }

    #[test]
    fn unbound_is_no_tier_at_all() {
        let t = tiered();
        assert!(matches!(
            t.resolve_from("nowhere", &Namespace::File("main.b".into())),
            Resolution::Unbound
        ));
    }

    #[test]
    fn head_kind_follows_the_evaluators_order() {
        let mut t = NameTable::new();
        let mut v = Scope::new(Namespace::File("f".into()));
        v.bind(Binding {
            name: "while".into(),
            kind: ScopeKind::Value,
            span: None,
            top_level: None,
        });
        t.push(v);
        let mut m = Scope::new(Namespace::Macro);
        m.bind(Binding {
            name: "while".into(),
            kind: ScopeKind::Macro,
            span: None,
            top_level: None,
        });
        t.push(m);
        assert_eq!(
            t.head_kind("while"),
            Some(ScopeKind::Macro),
            "a macro beats a binding"
        );
    }
}
