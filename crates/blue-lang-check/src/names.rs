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

use blue_lang_syntax::scope::{self, BinderKind, HeadKind, Scopes};
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

/// The qualifier that names a builtin: `blue::count` is the interpreter's
/// `count`, whatever a program defines.
pub const BUILTIN_QUALIFIER: &str = "blue";

/// Where a name lives. The unit a qualified name selects.
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

/// Which of the evaluator's three arbiters a name is bound by: the binder
/// grammar's own [`HeadKind`], so the walker and the table cannot disagree.
pub use blue_lang_syntax::scope::HeadKind as ScopeKind;

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
    /// For each program-defined name, the namespace of the definition that
    /// is evaluated LAST — the one today's single global environment binds.
    last_definer: BTreeMap<String, (usize, Namespace)>,
    /// The file each top-level form came from, and what each file imports.
    form_file: Vec<usize>,
    imports: BTreeMap<usize, FileImports>,
    /// Each bidama's declared `needs`, where its Bluefile was read.
    needs: BTreeMap<String, BTreeSet<String>>,
}

/// What one file declares with `use`: every package it `use`s (so
/// `pkg::name` may be written), and the names it lists for bare use.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct FileImports {
    pub uses: BTreeSet<String>,
    /// A listed name, and every package that lists it.
    pub names: BTreeMap<String, Vec<String>>,
}

impl FileImports {
    /// Record one `use` declaration.
    pub fn add(&mut self, package: &str, names: impl IntoIterator<Item = String>) {
        self.uses.insert(package.to_string());
        for n in names {
            let pkgs = self.names.entry(n).or_default();
            if !pkgs.iter().any(|p| p == package) {
                pkgs.push(package.to_string());
            }
        }
    }
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
            for (name, span, kind) in scope::definitions_of(form) {
                self.define(
                    ns.clone(),
                    Binding {
                        name,
                        kind,
                        span: Some(span),
                        top_level: Some(i),
                    },
                );
            }
        }
    }

    /// Bind a program definition in `ns`, and note it for the flat rule if it
    /// is evaluated after every earlier definition of its name.
    pub fn define(&mut self, ns: Namespace, binding: Binding) {
        if let Some(i) = binding.top_level {
            let later = self
                .last_definer
                .get(&binding.name)
                .is_none_or(|(prev, _)| i >= *prev);
            if later {
                self.last_definer
                    .insert(binding.name.clone(), (i, ns.clone()));
            }
        }
        self.scope_mut(ns).bind(binding);
    }

    /// Say which file each top-level form came from (`form_file[i]`) and
    /// what each file imports. Without it, no file imports anything.
    pub fn attach_files(&mut self, form_file: Vec<usize>, imports: BTreeMap<usize, FileImports>) {
        self.form_file = form_file;
        self.imports = imports;
    }

    /// Record each bidama's Bluefile `needs`.
    pub fn attach_needs(&mut self, needs: BTreeMap<String, BTreeSet<String>>) {
        self.needs = needs;
    }

    /// Bidama `pkg`'s declared `needs`, if its Bluefile was read.
    #[must_use]
    pub fn needs_of(&self, pkg: &str) -> Option<&BTreeSet<String>> {
        self.needs.get(pkg)
    }

    /// The file top-level form `top_level` came from (`usize::MAX` when no
    /// file table was attached: one file).
    #[must_use]
    pub fn file_of(&self, top_level: usize) -> usize {
        self.form_file.get(top_level).copied().unwrap_or(usize::MAX)
    }

    /// What the file of top-level form `top_level` imports.
    #[must_use]
    pub fn imports_of(&self, top_level: usize) -> Option<&FileImports> {
        self.form_file
            .get(top_level)
            .and_then(|f| self.imports.get(f))
    }

    /// The program scope of bidama `pkg`, if it is loaded.
    #[must_use]
    pub fn bidama(&self, pkg: &str) -> Option<&Scope> {
        self.scopes
            .iter()
            .find(|s| matches!(&s.namespace, Namespace::Bidama(p) if p == pkg))
    }

    /// Is `name` bound by the interpreter itself?
    #[must_use]
    pub fn builtin(&self, name: &str) -> bool {
        self.scopes.iter().any(|s| {
            matches!(
                s.namespace,
                Namespace::Harness | Namespace::SpecialForm | Namespace::Macro | Namespace::Builtin
            ) && s.get(name).is_some()
        })
    }

    /// What today's runtime binds a non-local `name` to: the program
    /// definition evaluated last, else the builtin. A qualified name is
    /// lowered to its bare name first, as the flat runtime would see it.
    #[must_use]
    pub fn flat_target(&self, name: &str) -> Target {
        let bare = blue_lang_syntax::qualified(name).map_or(name, |(_, n)| n);
        if let Some((_, ns)) = self.last_definer.get(bare) {
            return Target::Def(ns.clone(), bare.to_string());
        }
        if self.builtin(bare) {
            return Target::Builtin(bare.to_string());
        }
        Target::Unbound
    }

    /// What per-bidama namespaces bind a non-local `name` to, referenced from
    /// `own`: [`RESOLUTION_ORDER`] over `own`'s definitions, the file's
    /// explicit imports, then builtins; a qualified name exactly.
    #[must_use]
    pub fn ns_target(&self, name: &str, own: &Namespace, top_level: usize) -> Target {
        if let Some((pkg, n)) = blue_lang_syntax::qualified(name) {
            if pkg == BUILTIN_QUALIFIER {
                return if self.builtin(n) {
                    Target::Builtin(n.to_string())
                } else {
                    Target::Unbound
                };
            }
            let ns = Namespace::Bidama(pkg.to_string());
            return match self.scopes.iter().find(|s| s.namespace == ns) {
                Some(s) if s.get(n).is_some() => Target::Def(ns, n.to_string()),
                _ => Target::Unbound,
            };
        }
        if let Some(s) = self.scopes.iter().find(|s| &s.namespace == own) {
            if s.get(name).is_some() {
                return Target::Def(own.clone(), name.to_string());
            }
        }
        if let Some(pkgs) = self.imports_of(top_level).and_then(|i| i.names.get(name)) {
            let found: Vec<Namespace> = pkgs
                .iter()
                .filter(|p| self.bidama(p).is_some_and(|s| s.get(name).is_some()))
                .map(|p| Namespace::Bidama(p.clone()))
                .collect();
            match found.as_slice() {
                [] => {}
                [one] => return Target::Def(one.clone(), name.to_string()),
                _ => return Target::Ambiguous(found),
            }
        }
        if self.builtin(name) {
            return Target::Builtin(name.to_string());
        }
        Target::Unbound
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

/// The names `form` defines into the frame it is evaluated in, with the
/// span of each name and whether it is a value or a macro — the binder
/// grammar's answer (`blue_lang_syntax::scope::definitions_of`). What
/// [`NameTable::add_program`] reads from each top-level form; public so a
/// caller that EXPANDS a form first (a top-level call to `defflow`, whose
/// expansion is a `define`) can bind what the expansion defines.
#[must_use]
pub fn definitions_of(form: &Spanned) -> Vec<(String, Span, ScopeKind)> {
    scope::definitions_of(form)
}

/// The unused-binding message's noun for what introduced a local.
fn noun(kind: BinderKind) -> &'static str {
    match kind {
        BinderKind::Parameter => "parameter",
        BinderKind::Assignment | BinderKind::Let => "binding",
        BinderKind::Function => "local function",
        BinderKind::Catch => "caught error",
    }
}

#[derive(Debug)]
struct Local {
    name: String,
    span: Span,
    kind: BinderKind,
    used: bool,
}

// ---- what a reference is bound to --------------------------------------

/// The qualifier a ROOT namespace's definitions are keyed under at run time:
/// a script's `def f` is the binding `%root/f`. Not a package name the
/// surface can spell (`%` starts no identifier), so no package can own it,
/// and a script's definition can never replace a builtin or a bidama's.
pub const ROOT_QUALIFIER: &str = "%root";

/// The runtime key of definition `name` in namespace `ns`: `retsu/first`,
/// or `%root/f` for a script. The one function that says how a definition
/// is keyed, so the resolved tree and every reader of it agree.
#[must_use]
pub fn key(ns: &Namespace, name: &str) -> String {
    match ns {
        Namespace::Bidama(p) => blue_lang_syntax::qualify(p, name),
        _ => format!("{ROOT_QUALIFIER}{}{name}", blue_lang_syntax::QUALIFIER),
    }
}

/// What one reference is bound to, under one resolution rule.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Target {
    /// A parameter or local binding.
    Local,
    /// A program definition: the namespace that defines it, and its name.
    Def(Namespace, String),
    /// A name the interpreter binds before the program runs.
    Builtin(String),
    /// Two namespaces in the tier that holds it.
    Ambiguous(Vec<Namespace>),
    /// Nothing binds it.
    Unbound,
}

impl Target {
    /// The symbol this reference is written as in the RESOLVED tree: a
    /// definition's [`key`], a builtin's bare name. `None` leaves the symbol
    /// as written (a local, or nothing).
    #[must_use]
    pub fn resolved_symbol(&self) -> Option<String> {
        match self {
            Target::Def(ns, name) => Some(key(ns, name)),
            Target::Builtin(name) => Some(name.clone()),
            Target::Local | Target::Ambiguous(_) | Target::Unbound => None,
        }
    }
}

impl std::fmt::Display for Target {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Target::Local => f.write_str("local"),
            Target::Def(ns, name) => write!(f, "{name} ({ns})"),
            Target::Builtin(name) => write!(f, "{name} (builtin)"),
            Target::Ambiguous(nss) => write!(
                f,
                "ambiguous ({})",
                nss.iter().map(ToString::to_string).collect::<Vec<_>>().join(", ")
            ),
            Target::Unbound => f.write_str("unbound"),
        }
    }
}

/// One non-local reference in a program, and what it binds to under both
/// resolution rules.
///
/// **Both rules, side by side, is what the migration is proven on.** `flat`
/// is what the runtime does today: one global environment, the definition
/// evaluated last wins, a builtin only when no program form defines the
/// name. `ns` is per-bidama namespaces: [`RESOLUTION_ORDER`] over this file's
/// own namespace and its explicit imports, with a qualified name exact. A
/// program whose every reference has `flat == ns` means the same thing under
/// either rule.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Reference {
    /// The top-level form it is in.
    pub top_level: usize,
    pub span: Span,
    /// The symbol as the tree has it: `first`, or `retsu/first` for
    /// `retsu::first`.
    pub written: String,
    /// Inside a macro call's arguments.
    pub opaque: bool,
    pub flat: Target,
    pub ns: Target,
    /// The node's address in the forms it was resolved over: the join key
    /// [`resolved_tree`] rewrites by, since spans are not unique (every node
    /// of an interpolation carries the string's span).
    node: usize,
}

/// A top-level definition's name node, keyed.
#[derive(Clone, Debug)]
struct DefSite {
    node: usize,
    key: String,
}

/// Every non-local reference in `forms`, resolved both ways, and every
/// top-level definition site. `namespace_of(i)` is top-level form `i`'s
/// namespace, as for [`check_names`].
#[must_use]
pub fn resolve_program(
    forms: &[Spanned],
    table: &NameTable,
    namespace_of: &dyn Fn(usize) -> Namespace,
) -> Resolved {
    let mut w = Walker::new(table, &|_| false);
    let mut defs = Vec::new();
    for (i, form) in forms.iter().enumerate() {
        let ns = namespace_of(i);
        w.enter(i, ns.clone(), form);
        scope::walk_top(form, &mut w);
        scope::definition_nodes(form, &mut |node, _| {
            if let Some(n) = node.as_symbol() {
                defs.push(DefSite {
                    node: std::ptr::from_ref(node) as usize,
                    key: key(&ns, n),
                });
            }
        });
    }
    Resolved {
        references: w.references,
        defs,
    }
}

/// [`resolve_program`]'s result.
#[derive(Clone, Debug)]
pub struct Resolved {
    pub references: Vec<Reference>,
    defs: Vec<DefSite>,
}

/// Which resolution rule a resolved tree is built under.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Rule {
    /// Today's runtime: last definition wins.
    Flat,
    /// Per-bidama namespaces.
    Namespaced,
}

impl Resolved {
    /// The references whose two rules disagree: the program means something
    /// different once namespaces resolve it.
    pub fn divergent(&self) -> impl Iterator<Item = &Reference> {
        self.references.iter().filter(|r| r.flat != r.ns)
    }

    /// `forms` with every definition renamed to its [`key`] and every
    /// reference to what `rule` binds it to. **Must be given the same forms
    /// [`resolve_program`] walked**: the rewrite joins on node identity.
    #[must_use]
    pub fn resolved_tree(&self, forms: &[Spanned], rule: Rule) -> Vec<Spanned> {
        let mut map: std::collections::HashMap<usize, String> = std::collections::HashMap::new();
        for d in &self.defs {
            map.insert(d.node, d.key.clone());
        }
        for r in &self.references {
            let target = match rule {
                Rule::Flat => &r.flat,
                Rule::Namespaced => &r.ns,
            };
            if let Some(sym) = target.resolved_symbol() {
                map.insert(r.node, sym);
            }
        }
        forms.iter().map(|f| rewrite(f, &map)).collect()
    }
}

fn rewrite(form: &Spanned, map: &std::collections::HashMap<usize, String>) -> Spanned {
    let at = std::ptr::from_ref(form) as usize;
    let inner = match &form.form {
        SpannedForm::Atom(Atom::Symbol(s)) => {
            let s = map.get(&at).cloned().unwrap_or_else(|| s.clone());
            SpannedForm::Atom(Atom::Symbol(s))
        }
        SpannedForm::List(items) => SpannedForm::List(items.iter().map(|i| rewrite(i, map)).collect()),
        SpannedForm::Quote(i) => SpannedForm::Quote(Box::new(rewrite(i, map))),
        SpannedForm::Quasiquote(i) => SpannedForm::Quasiquote(Box::new(rewrite(i, map))),
        SpannedForm::Unquote(i) => SpannedForm::Unquote(Box::new(rewrite(i, map))),
        SpannedForm::UnquoteSplice(i) => SpannedForm::UnquoteSplice(Box::new(rewrite(i, map))),
        other => other.clone(),
    };
    Spanned::new(form.span, inner)
}

// ---- the walker ----------------------------------------------------------

/// What the walker reports into.
struct Walker<'t> {
    table: &'t NameTable,
    /// The namespace of the top-level form being walked: its [`Tier::Own`].
    own: Namespace,
    frames: Vec<Vec<Local>>,
    top_level: usize,
    report_unused: bool,
    unused_for: &'t dyn Fn(usize) -> bool,
    /// Every symbol written in the current top-level form, so a rename fix
    /// can prove its new name is not already in use there.
    symbols: BTreeSet<String>,
    diagnostics: Vec<Diagnostic>,
    /// Names resolved, for the report.
    resolved: usize,
    references: Vec<Reference>,
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
    let mut w = Walker::new(table, report_unused);
    for (i, form) in forms.iter().enumerate() {
        w.enter(i, namespace_of(i), form);
        w.check_import_list(form);
        // A top-level form's own defines are globals, already in `table`.
        scope::walk_top(form, &mut w);
    }
    let file_rules = crate::namespace_rules::check(forms, table, namespace_of, &w.references);
    w.diagnostics.extend(file_rules);
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

impl<'t> Walker<'t> {
    fn new(table: &'t NameTable, unused_for: &'t dyn Fn(usize) -> bool) -> Self {
        Walker {
            table,
            own: Namespace::Local,
            frames: Vec::new(),
            top_level: 0,
            report_unused: false,
            unused_for,
            symbols: BTreeSet::new(),
            diagnostics: Vec::new(),
            resolved: 0,
            references: Vec::new(),
        }
    }

    /// Start top-level form `i`.
    fn enter(&mut self, i: usize, own: Namespace, form: &Spanned) {
        self.top_level = i;
        self.own = own;
        self.report_unused = (self.unused_for)(i);
        self.symbols.clear();
        collect_symbols(form, &mut self.symbols);
    }

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

    /// Record a non-local reference under both rules.
    fn record(&mut self, node: &Spanned, name: &str, opaque: bool) {
        let flat = self.table.flat_target(name);
        let ns = self.table.ns_target(name, &self.own, self.top_level);
        // B0012: another bidama's definition, reached bare only because the
        // one global environment holds it.
        if let Target::Def(Namespace::Bidama(owner), n) = &flat {
            let foreign = &Namespace::Bidama(owner.clone()) != &self.own;
            if foreign
                && blue_lang_syntax::qualified(name).is_none()
                && matches!(ns, Target::Builtin(_) | Target::Unbound)
            {
                let uses = self
                    .table
                    .imports_of(self.top_level)
                    .is_some_and(|i| i.uses.contains(owner));
                let mut d = Diagnostic::new(
                    Code::B0012,
                    format!(
                        "`{n}` is bidama `{owner}`'s, and this file reaches it only because something loaded `{owner}`"
                    ),
                    node.span,
                )
                .at_top_level(self.top_level)
                .with_help(format!(
                    "list it, `use(\"{owner}\", [:{n}])`, or write `{owner}::{n}`{}",
                    if uses {
                        String::new()
                    } else {
                        format!("; the file must `use(\"{owner}\")` (and, in a bidama, `needs` it)")
                    }
                ));
                if uses {
                    d = d.with_fix(Fix {
                        message: format!("write `{owner}::{n}`"),
                        edits: vec![Edit {
                            span: node.span,
                            original: name.to_string(),
                            replacement: format!("{owner}::{n}"),
                        }],
                        applicability: Applicability::MachineApplicable,
                    });
                }
                self.diagnostics.push(d);
            }
        }
        self.references.push(Reference {
            top_level: self.top_level,
            span: node.span,
            written: name.to_string(),
            opaque,
            flat,
            ns,
            node: std::ptr::from_ref(node) as usize,
        });
    }

    /// A reference to `name` at `span`. `opaque`: inside a macro's arguments,
    /// where an unresolved name is not reported.
    fn reference_at(&mut self, node: &Spanned, name: &str, opaque: bool) {
        let span = node.span;
        if self.read_local(name) {
            self.resolved += 1;
            return;
        }
        self.record(node, name, opaque);
        if let Some((pkg, n)) = blue_lang_syntax::qualified(name) {
            self.qualified_reference(span, pkg, n);
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
        if self.table.bidama(name).is_some() {
            let d = Diagnostic::new(
                Code::B0020,
                format!("`{name}` is a bidama, not a value"),
                span,
            )
            .at_top_level(self.top_level)
            .with_help(format!(
                "blue qualifies with `::`: `{name}.f(x)` and `{name}/f` are calls on a value named `{name}`; write `{name}::f(x)`"
            ));
            self.diagnostics.push(d);
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
}

impl Walker<'_> {
    /// `pkg::n`: exact, and checked to be what it says. The package must be
    /// one this file `use`s (B0010) and must define `n` (B0011); `blue::n`
    /// must name a builtin.
    fn qualified_reference(&mut self, span: Span, pkg: &str, n: &str) {
        if pkg == BUILTIN_QUALIFIER {
            if self.table.builtin(n) {
                self.resolved += 1;
                if self.table.ns_target(n, &self.own, self.top_level) == Target::Builtin(n.to_string()) {
                    self.redundant(span, pkg, n, "the bare name is the builtin here");
                }
                return;
            }
            let d = Diagnostic::new(Code::B0011, format!("`blue::{n}` names no builtin"), span)
                .at_top_level(self.top_level)
                .with_help(
                    "`blue::` qualifies the interpreter's own names; drop the qualifier to name a program definition",
                );
            self.diagnostics.push(d);
            return;
        }
        let uses = self
            .table
            .imports_of(self.top_level)
            .is_some_and(|i| i.uses.contains(pkg));
        if !uses {
            let d = Diagnostic::new(
                Code::B0010,
                format!("`{pkg}::{n}` is qualified by `{pkg}`, which this file does not `use`"),
                span,
            )
            .at_top_level(self.top_level)
            .with_help(format!(
                "add `use(\"{pkg}\")` to the file's imports (and `needs(\"{pkg}\", …)` to its Bluefile, inside a bidama)"
            ));
            self.diagnostics.push(d);
            return;
        }
        if self.table.bidama(pkg).is_some_and(|s| s.get(n).is_some()) {
            self.resolved += 1;
            if self.own == Namespace::Bidama(pkg.to_string()) {
                self.redundant(span, pkg, n, "it is this bidama's own definition");
            } else if self
                .table
                .imports_of(self.top_level)
                .and_then(|i| i.names.get(n))
                .is_some_and(|ps| ps.len() == 1 && ps[0] == pkg)
            {
                self.redundant(span, pkg, n, "the file lists it from that bidama");
            }
            return;
        }
        let d = self.no_such_definition(span, pkg, n, true);
        self.diagnostics.push(d);
    }

    /// B0018: a qualifier that changes nothing.
    fn redundant(&mut self, span: Span, pkg: &str, n: &str, why: &str) {
        let d = Diagnostic::new(
            Code::B0018,
            format!("`{pkg}::{n}` needs no qualifier: {why}"),
            span,
        )
        .at_top_level(self.top_level)
        .with_fix(Fix {
            message: format!("write `{n}`"),
            edits: vec![Edit {
                span,
                original: format!("{pkg}::{n}"),
                replacement: n.to_string(),
            }],
            applicability: Applicability::MachineApplicable,
        });
        self.diagnostics.push(d);
    }

    /// B0011: `pkg` defines no `n`. Suggests the package that does, and the
    /// nearest names `pkg` has.
    fn no_such_definition(&self, span: Span, pkg: &str, n: &str, qualified: bool) -> Diagnostic {
        let owners: Vec<&str> = self
            .table
            .scopes()
            .iter()
            .filter_map(|s| match &s.namespace {
                Namespace::Bidama(p) if p != pkg && s.get(n).is_some() => Some(p.as_str()),
                _ => None,
            })
            .collect();
        let mut near: Vec<(usize, String)> = self
            .table
            .bidama(pkg)
            .map(|s| {
                s.bindings()
                    .filter_map(|b| suggest::closeness(n, &b.name).map(|d| (d, b.name.clone())))
                    .collect()
            })
            .unwrap_or_default();
        near.sort();
        near.truncate(3);
        let mut d = Diagnostic::new(Code::B0011, format!("bidama `{pkg}` defines no `{n}`"), span)
            .at_top_level(self.top_level);
        let mut offers: Vec<String> = owners.iter().map(|o| format!("{o}::{n}")).collect();
        offers.extend(near.iter().map(|(_, c)| format!("{pkg}::{c}")));
        d = match (owners.as_slice(), offers.as_slice()) {
            ([owner, ..], _) => d.with_help(format!("`{n}` is defined in bidama `{owner}`")),
            (_, []) => d.with_help(format!("nothing in `{pkg}` is close to `{n}`")),
            (_, many) => d.with_help(format!(
                "did you mean {}?",
                many.iter().map(|c| format!("`{c}`")).collect::<Vec<_>>().join(", ")
            )),
        };
        if qualified {
            for offer in offers {
                d = d.with_fix(Fix {
                    message: format!("replace with `{offer}`"),
                    edits: vec![Edit {
                        span,
                        original: format!("{pkg}::{n}"),
                        replacement: offer,
                    }],
                    applicability: Applicability::MaybeIncorrect,
                });
            }
        }
        d
    }

    /// The names a `use` lists must be the package's.
    fn check_import_list(&mut self, form: &Spanned) {
        let Some(import) = scope::use_target(form) else {
            return;
        };
        for (n, span) in &import.names {
            if self
                .table
                .bidama(&import.package)
                .is_some_and(|s| s.get(n).is_some())
            {
                continue;
            }
            let d = self.no_such_definition(*span, &import.package, n, false);
            self.diagnostics.push(d);
        }
    }
}

impl Scopes for Walker<'_> {
    fn head_kind(&self, name: &str) -> Option<HeadKind> {
        self.table.head_kind(name)
    }

    fn open(&mut self) {
        self.frames.push(Vec::new());
    }

    fn bind(&mut self, name: &str, span: Span, kind: BinderKind) {
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

    fn close(&mut self) {
        let frame = self.frames.pop().expect("close with a frame open");
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
                format!("{} `{}` is never read", noun(l.kind), l.name),
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

    fn reference(&mut self, node: &Spanned, name: &str, opaque: bool) {
        self.reference_at(node, name, opaque);
    }

    fn head(&mut self, node: &Spanned, name: &str, kind: HeadKind) {
        match kind {
            // A macro head is a reference to the macro: a program's own
            // `defmacro` is keyed like any definition.
            HeadKind::Macro => {
                self.resolved += 1;
                if !self.frames.iter().any(|f| f.iter().any(|l| l.name == name)) {
                    self.record(node, name, false);
                }
            }
            HeadKind::SpecialForm
                if !matches!(name, "define" | "define-typed" | "defmacro" | "use") =>
            {
                self.resolved += 1;
            }
            _ => {}
        }
    }
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
