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
//! | [`Tier::Imported`] | the names the file lists in its `use` forms (`use("retsu", [:first])`) | its own file's imports |
//! | [`Tier::Builtin`] | harness names, special forms, macros, runtime values | the interpreter |
//!
//! The first tier holding the name wins, deterministically: an own definition
//! beats a listed one, a listed one beats a builtin. **Two namespaces in the
//! SAME tier holding it is [`B0009`](crate::Code::B0009)**, an error: two `use`
//! forms listing one name. No tier holding it is
//! [`B0001`](crate::Code::B0001), with did-you-mean candidates that each name
//! their namespace — or [`B0012`](crate::Code::B0012) when a bidama the file's
//! imports loaded defines it. A qualified name (`retsu::first`, `blue::first`)
//! bypasses the tiers and is exact. A `use("x")` with no list makes only
//! `x::name` reachable; a transitive bidama is not visible at all.
//!
//! ## The runtime binds what the table resolved
//!
//! `pipeline::lower` evaluates the RESOLVED tree ([`Resolved::resolved_tree`]
//! under [`Rule::Namespaced`]): every definition runs under its [`key`]
//! (`retsu/first`, `%root/f`) and every reference to it as that key, and a
//! builtin stays bare. Keys cannot collide across namespaces, so a bidama's
//! `first` no longer replaces the builtin for files that did not list it, and
//! an importer's `helper` no longer replaces a bidama's own
//! (`blue-lang-runtime/tests/resolution_order.rs` pins both agreements; until
//! 2026-09-29 it pinned them as divergences of one global environment).
//!
//! ## Which arbiter a HEAD answers to
//!
//! A special form is in no tier and wins. A program definition the tiers reach
//! beats a builtin macro of the same name (it is keyed apart from it now, so it
//! can exist beside it); otherwise a macro beats a value, as the evaluator
//! consults them.
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
    /// Second names for definitions, from the bidama's `legacy_names`.
    aliases: BTreeMap<String, Alias>,
}

/// A second name for one definition (`legacy_names`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Alias {
    /// The definition it names.
    pub canonical: String,
    /// A bridge for callers still on the old, prefixed spelling (`lc_hours`
    /// for `hours`): open only inside its window, and reported (B0021) while
    /// it is. Otherwise the stripped name of a definition that keeps its
    /// prefix (`count` for `q_count`), valid for good.
    pub bridge: bool,
    /// Whether it resolves: a bridge outside its window does not, and is kept
    /// only as the ledger a late caller's fix is read from.
    pub open: bool,
    /// The `legacy_names` version it dates from.
    pub since: String,
}

impl Scope {
    #[must_use]
    pub fn new(namespace: Namespace) -> Self {
        Self {
            namespace,
            bindings: BTreeMap::new(),
            aliases: BTreeMap::new(),
        }
    }

    /// Give a definition a second name.
    pub fn alias(&mut self, name: String, alias: Alias) {
        self.aliases.entry(name).or_insert(alias);
    }

    /// The alias `name` is, open or not.
    #[must_use]
    pub fn alias_of(&self, name: &str) -> Option<&Alias> {
        self.aliases.get(name)
    }

    /// Bind a name. A second binding of the same name keeps the first: that
    /// is where a reader should be sent.
    pub fn bind(&mut self, binding: Binding) {
        self.bindings.entry(binding.name.clone()).or_insert(binding);
    }

    /// The binding `name` names: a definition, or the definition an open
    /// alias names (one definition, two names).
    #[must_use]
    pub fn get(&self, name: &str) -> Option<&Binding> {
        self.bindings.get(name).or_else(|| {
            self.aliases
                .get(name)
                .filter(|a| a.open)
                .and_then(|a| self.bindings.get(&a.canonical))
        })
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
    /// The bidamas each bidama's files `use`.
    pkg_uses: BTreeMap<String, BTreeSet<String>>,
    /// Each bidama's declared legacy prefix (`legacy_names`).
    legacy_prefix: BTreeMap<String, String>,
    /// Each file's path, and each bidama's distribution root: whether a
    /// reference is inside the distribution a bidama ships in (B0021).
    file_paths: BTreeMap<usize, String>,
    pkg_roots: BTreeMap<String, String>,
    /// B0022 findings from [`NameTable::apply_legacy`], reported by the check.
    legacy_findings: Vec<Diagnostic>,
}

/// `a.b.c` as numbers; `None` for anything else.
fn version(v: &str) -> Option<(u64, u64, u64)> {
    let mut parts = v.split('.').map(|p| p.parse::<u64>().ok());
    let t = (parts.next()??, parts.next()??, parts.next()??);
    parts.next().is_none().then_some(t)
}

/// What one file declares with `use`: every package it `use`s (so
/// `pkg::name` may be written), and the names it lists for bare use.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct FileImports {
    pub uses: BTreeSet<String>,
    /// A listed name, and every package that lists it.
    pub names: BTreeMap<String, Vec<String>>,
    /// A bidama reachable only through a facade the file uses, and that
    /// facade: `use("zenbu")` makes `toukei::` reachable.
    pub via: BTreeMap<String, String>,
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

    /// Record each file's path and each bidama's distribution root.
    pub fn attach_paths(
        &mut self,
        file_paths: BTreeMap<usize, String>,
        pkg_roots: BTreeMap<String, String>,
    ) {
        self.file_paths = file_paths;
        self.pkg_roots = pkg_roots;
    }

    /// Is the file of form `top_level` inside the distribution bidama `pkg`
    /// ships in? Unknown paths count as inside: the error is the safe side.
    #[must_use]
    pub fn inside_distribution(&self, top_level: usize, pkg: &str) -> bool {
        match (
            self.file_paths.get(&self.file_of(top_level)),
            self.pkg_roots.get(pkg),
        ) {
            (Some(file), Some(root)) => file.starts_with(root.as_str()),
            _ => true,
        }
    }

    /// Bidama `pkg`'s declared legacy prefix.
    #[must_use]
    pub fn legacy_prefix(&self, pkg: &str) -> Option<&str> {
        self.legacy_prefix.get(pkg).map(String::as_str)
    }

    /// Read every `legacy_names(since, prefix)` declaration in `forms` into
    /// aliases: a bridge `prefix_x` for each definition `x` (open while the
    /// bidama's version is at least `since` and below the next minor), and
    /// the stripped name `y` for each definition that keeps its prefix
    /// (`prefix_y`), for good. Returns B0022 for each declaration that cannot
    /// mean one thing. `version_of` is a bidama's Bluefile version.
    pub fn apply_legacy(
        &mut self,
        forms: &[Spanned],
        namespace_of: &dyn Fn(usize) -> Namespace,
        version_of: &dyn Fn(&str) -> Option<String>,
    ) -> Vec<Diagnostic> {
        let mut out = Vec::new();
        for (i, form) in forms.iter().enumerate() {
            let Some(decl) = scope::legacy_target(form) else {
                continue;
            };
            let bad = |msg: String| Diagnostic::new(Code::B0022, msg, decl.span).at_top_level(i);
            let Namespace::Bidama(pkg) = namespace_of(i) else {
                out.push(bad("`legacy_names` declares a bidama's old names, and this file is not in a bidama".into()));
                continue;
            };
            if self.legacy_prefix.contains_key(&pkg) {
                out.push(bad(format!("bidama `{pkg}` declares `legacy_names` twice")));
                continue;
            }
            let (Some(since), Some(now)) = (
                version(&decl.since),
                version_of(&pkg).as_deref().and_then(version),
            ) else {
                out.push(bad(format!(
                    "`legacy_names(\"{}\", …)`: `since` must be a version `a.b.c`, and {pkg}'s Bluefile must state one",
                    decl.since
                )));
                continue;
            };
            if since > now {
                out.push(bad(format!(
                    "`legacy_names` dates the rename from {}, and bidama `{pkg}` is at {}.{}.{}",
                    decl.since, now.0, now.1, now.2
                )));
                continue;
            }
            if decl.prefix.is_empty() || decl.prefix.contains('_') {
                out.push(bad("the legacy prefix is the letters before the `_`: `legacy_names(\"0.1.1\", \"lc\")`".into()));
                continue;
            }
            let open = now < (since.0, since.1 + 1, 0);
            self.legacy_prefix.insert(pkg.clone(), decl.prefix.clone());
            let Some(scope) = self.bidama(&pkg) else {
                continue;
            };
            let names: Vec<String> = scope.bindings().map(|b| b.name.clone()).collect();
            let prefix = format!("{}_", decl.prefix);
            let mut aliases = Vec::new();
            for name in &names {
                let (alias, bridge) = match name.strip_prefix(&prefix) {
                    Some(stripped) if !stripped.is_empty() => (stripped.to_string(), false),
                    _ => (format!("{prefix}{name}"), true),
                };
                if names.contains(&alias) {
                    out.push(bad(format!(
                        "`{alias}` and `{name}` are both defined in `{pkg}`, so `{alias}` cannot also be a second name of `{name}`"
                    )));
                    continue;
                }
                aliases.push((
                    alias,
                    Alias {
                        canonical: name.clone(),
                        bridge,
                        open: open || !bridge,
                        since: decl.since.clone(),
                    },
                ));
            }
            let scope = self.scope_mut(Namespace::Bidama(pkg));
            for (a, al) in aliases {
                scope.alias(a, al);
            }
        }
        self.legacy_findings.clone_from(&out);
        out
    }

    /// Record which bidamas each bidama `use`s.
    pub fn attach_package_uses(&mut self, uses: BTreeMap<String, BTreeSet<String>>) {
        self.pkg_uses = uses;
    }

    /// Every bidama the file of form `top_level` reaches through its `use`
    /// forms, transitively: what its imports loaded, and nothing any other
    /// file of the program did.
    #[must_use]
    pub fn use_closure(&self, top_level: usize) -> BTreeSet<String> {
        let mut out = BTreeSet::new();
        let mut todo: Vec<String> = self
            .imports_of(top_level)
            .map(|i| i.uses.iter().cloned().collect())
            .unwrap_or_default();
        while let Some(p) = todo.pop() {
            if out.insert(p.clone()) {
                todo.extend(self.pkg_uses.get(&p).into_iter().flatten().cloned());
            }
        }
        out
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
        // An open alias is a second name of a definition the program has.
        for s in &self.scopes {
            if let (Namespace::Bidama(_), Some(b)) = (&s.namespace, s.get(bare)) {
                return Target::Def(s.namespace.clone(), b.name.clone());
            }
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
            return match self
                .scopes
                .iter()
                .find(|s| s.namespace == ns)
                .and_then(|s| s.get(n))
            {
                Some(b) => Target::Def(ns, b.name.clone()),
                None => Target::Unbound,
            };
        }
        match self.resolve_from(name, own, top_level) {
            Resolution::Found {
                tier: Tier::Builtin,
                ..
            } => Target::Builtin(name.to_string()),
            Resolution::Found { scope, binding, .. } => {
                Target::Def(scope.namespace.clone(), binding.name.clone())
            }
            Resolution::Ambiguous { namespaces, .. } => {
                Target::Ambiguous(namespaces.into_iter().cloned().collect())
            }
            Resolution::Unbound => Target::Unbound,
        }
    }

    /// Every non-local tier's candidates for bare `name`, in
    /// [`RESOLUTION_ORDER`]: the path `blue explain-name` prints, and the data
    /// an override is recorded from.
    #[must_use]
    pub fn tiers_of(
        &self,
        name: &str,
        own: &Namespace,
        top_level: usize,
    ) -> Vec<(Tier, Vec<Namespace>)> {
        let mut out = Vec::new();
        for tier in RESOLUTION_ORDER {
            let nss: Vec<Namespace> = match tier {
                Tier::Local => continue,
                Tier::Own => self
                    .scopes
                    .iter()
                    .filter(|s| &s.namespace == own && s.get(name).is_some())
                    .map(|s| s.namespace.clone())
                    .collect(),
                Tier::Imported => self
                    .imports_of(top_level)
                    .and_then(|i| i.names.get(name))
                    .map(|pkgs| {
                        pkgs.iter()
                            .filter(|p| self.bidama(p).is_some_and(|s| s.get(name).is_some()))
                            .map(|p| Namespace::Bidama(p.clone()))
                            .collect()
                    })
                    .unwrap_or_default(),
                Tier::Builtin => {
                    if self.builtin(name) {
                        vec![Namespace::Builtin]
                    } else {
                        vec![]
                    }
                }
            };
            out.push((tier, nss));
        }
        out
    }

    /// Resolve a bare `name` referenced from top-level form `top_level` in
    /// namespace `own`, by [`RESOLUTION_ORDER`]: `own`'s definitions, then
    /// the names that form's file lists in its `use` forms, then builtins.
    /// Locals are the walker's; this starts at [`Tier::Own`]. The first tier
    /// holding the name wins, deterministically; two namespaces in one tier
    /// is [`Resolution::Ambiguous`].
    #[must_use]
    pub fn resolve_from(&self, name: &str, own: &Namespace, top_level: usize) -> Resolution<'_> {
        for tier in RESOLUTION_ORDER {
            let hits: Vec<(&Scope, &Binding)> = match tier {
                Tier::Local => continue,
                Tier::Own => self
                    .scopes
                    .iter()
                    .filter(|s| &s.namespace == own)
                    .filter_map(|s| s.get(name).map(|b| (s, b)))
                    .collect(),
                Tier::Imported => self
                    .imports_of(top_level)
                    .and_then(|i| i.names.get(name))
                    .map(|pkgs| {
                        pkgs.iter()
                            .filter_map(|p| self.bidama(p))
                            .filter_map(|s| s.get(name).map(|b| (s, b)))
                            .collect()
                    })
                    .unwrap_or_default(),
                Tier::Builtin => self
                    .scopes
                    .iter()
                    .filter(|s| s.namespace.tier(own) == Tier::Builtin)
                    .filter_map(|s| s.get(name).map(|b| (s, b)))
                    .collect(),
            };
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
                nss.iter()
                    .map(ToString::to_string)
                    .collect::<Vec<_>>()
                    .join(", ")
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
    /// For a bare name the namespaced rule bound, every candidate in a
    /// LOWER tier it won over: a cross-tier override (an own `count` over the
    /// builtin, a listed `first` over the builtin). Recorded, never an error:
    /// each tier is something the author wrote.
    pub shadowed: Vec<(Tier, Namespace)>,
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
        SpannedForm::List(items) => {
            SpannedForm::List(items.iter().map(|i| rewrite(i, map)).collect())
        }
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
    check_names_whole(forms, table, namespace_of, report_unused, report_unused)
}

/// [`check_names`], saying separately which forms belong to a file checked
/// WHOLE — its test blocks included — which is the only kind of file that can
/// say a name it lists is never read (B0016). `blue run` drops the entry's
/// tests before checking; `blue check` and `blue test` keep them.
#[must_use]
pub fn check_names_whole(
    forms: &[Spanned],
    table: &NameTable,
    namespace_of: &dyn Fn(usize) -> Namespace,
    report_unused: &dyn Fn(usize) -> bool,
    whole_file: &dyn Fn(usize) -> bool,
) -> (Vec<Diagnostic>, usize) {
    let mut w = Walker::new(table, report_unused);
    for (i, form) in forms.iter().enumerate() {
        w.enter(i, namespace_of(i), form);
        w.check_import_list(form);
        // A top-level form's own defines are globals, already in `table`.
        scope::walk_top(form, &mut w);
    }
    let file_rules =
        crate::namespace_rules::check(forms, table, namespace_of, &w.references, whole_file);
    w.diagnostics.extend(file_rules);
    w.diagnostics.extend(table.legacy_findings.iter().cloned());
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
            // Only a bidama this file's own imports loaded: a definition some
            // OTHER file of the program brought in says nothing about what
            // this file meant, and must not make its builtin call an error.
            let foreign = &Namespace::Bidama(owner.clone()) != &self.own
                && self.table.use_closure(self.top_level).contains(owner);
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
        self.legacy_reference(node.span, name, &ns);
        self.references.push(Reference {
            top_level: self.top_level,
            span: node.span,
            written: name.to_string(),
            opaque,
            shadowed: self.shadowed(name, &ns),
            flat,
            ns,
            node: std::ptr::from_ref(node) as usize,
        });
    }

    /// B0021: a reference through a bridge alias — an old, prefixed name of a
    /// renamed definition. Its severity is derived: an error inside the
    /// distribution the bidama ships in, a warning for any other caller.
    fn legacy_reference(&mut self, span: Span, name: &str, ns: &Target) {
        let (qualifier, part) = match blue_lang_syntax::qualified(name) {
            Some((p, n)) => (Some(p), n),
            None => (None, name),
        };
        let Target::Def(Namespace::Bidama(pkg), canonical) = ns else {
            return;
        };
        if canonical == part {
            return;
        }
        let Some(alias) = self.table.bidama(pkg).and_then(|s| s.alias_of(part)) else {
            return;
        };
        if !alias.bridge {
            return;
        }
        let (original, replacement) = match qualifier {
            Some(q) => (format!("{q}::{part}"), format!("{q}::{canonical}")),
            None => (part.to_string(), canonical.clone()),
        };
        let d = self.legacy_diagnostic(
            span,
            pkg,
            part,
            canonical,
            &alias.since,
            original,
            replacement,
        );
        self.diagnostics.push(d);
    }

    #[allow(clippy::too_many_arguments)]
    fn legacy_diagnostic(
        &self,
        span: Span,
        pkg: &str,
        old: &str,
        new: &str,
        since: &str,
        original: String,
        replacement: String,
    ) -> Diagnostic {
        let mut d = Diagnostic::new(
            Code::B0021,
            format!("`{old}` is the old name of bidama `{pkg}`'s `{new}` (renamed in {since})"),
            span,
        )
        .at_top_level(self.top_level)
        .with_help(format!(
            "write `{replacement}`; the old name resolves only until `{pkg}`'s next minor version"
        ))
        .with_fix(Fix {
            message: format!("write `{replacement}`"),
            edits: vec![Edit {
                span,
                original,
                replacement,
            }],
            applicability: Applicability::MachineApplicable,
        });
        if !self.table.inside_distribution(self.top_level, pkg) {
            d.severity = crate::Severity::Warning;
        }
        d
    }

    /// The candidates `ns` won over, for a bare name.
    fn shadowed(&self, name: &str, ns: &Target) -> Vec<(Tier, Namespace)> {
        if blue_lang_syntax::qualified(name).is_some()
            || !matches!(ns, Target::Def(..) | Target::Builtin(_))
        {
            return Vec::new();
        }
        let tiers = self.table.tiers_of(name, &self.own, self.top_level);
        let Some(win) = tiers.iter().position(|(_, nss)| !nss.is_empty()) else {
            return Vec::new();
        };
        tiers[win + 1..]
            .iter()
            .flat_map(|(t, nss)| nss.iter().map(move |n| (*t, n.clone())))
            .collect()
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
        match self.table.resolve_from(name, &self.own, self.top_level) {
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
        // Another bidama defines it, and the file neither lists nor
        // qualifies it: that is B0012's, reported with its fix in `record`.
        if let Target::Def(Namespace::Bidama(owner), _) = self.table.flat_target(name) {
            if self.table.use_closure(self.top_level).contains(&owner) {
                return;
            }
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
        let renamed: Vec<(String, String, String)> = self
            .table
            .use_closure(self.top_level)
            .iter()
            .filter_map(|p| {
                let a = self.table.bidama(p)?.alias_of(name)?;
                Some((p.clone(), a.canonical.clone(), a.since.clone()))
            })
            .collect();
        if let [(pkg, canonical, since)] = renamed.as_slice() {
            let replacement = format!("{pkg}::{canonical}");
            let d = Diagnostic::new(Code::B0001, format!("unbound name `{name}`"), span)
                .at_top_level(self.top_level)
                .with_help(format!(
                    "`{name}` was bidama `{pkg}`'s, renamed `{canonical}` in {since}, and the bridge has closed"
                ))
                .with_fix(Fix {
                    message: format!("write `{replacement}`"),
                    edits: vec![Edit {
                        span,
                        original: name.to_string(),
                        replacement,
                    }],
                    applicability: Applicability::MachineApplicable,
                });
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
                let builtin = Target::Builtin(n.to_string());
                if self.table.ns_target(n, &self.own, self.top_level) == builtin
                    && self.table.flat_target(n) == builtin
                {
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
        let mut d = Diagnostic::new(
            Code::B0011,
            format!("bidama `{pkg}` defines no `{n}`"),
            span,
        )
        .at_top_level(self.top_level);
        // A closed bridge: the ledger still says what it was renamed to.
        if let Some(a) = self.table.bidama(pkg).and_then(|s| s.alias_of(n)) {
            let (original, replacement) = if qualified {
                (format!("{pkg}::{n}"), format!("{pkg}::{}", a.canonical))
            } else {
                (format!(":{n}"), format!(":{}", a.canonical))
            };
            return d
                .with_help(format!(
                    "`{n}` was renamed `{}` in {} (`legacy_names`), and the bridge has closed",
                    a.canonical, a.since
                ))
                .with_fix(Fix {
                    message: format!("write `{replacement}`"),
                    edits: vec![Edit {
                        span,
                        original,
                        replacement,
                    }],
                    applicability: Applicability::MachineApplicable,
                });
        }
        let mut offers: Vec<String> = owners.iter().map(|o| format!("{o}::{n}")).collect();
        offers.extend(near.iter().map(|(_, c)| format!("{pkg}::{c}")));
        d = match (owners.as_slice(), offers.as_slice()) {
            ([owner, ..], _) => d.with_help(format!("`{n}` is defined in bidama `{owner}`")),
            (_, []) => d.with_help(format!("nothing in `{pkg}` is close to `{n}`")),
            (_, many) => d.with_help(format!(
                "did you mean {}?",
                many.iter()
                    .map(|c| format!("`{c}`"))
                    .collect::<Vec<_>>()
                    .join(", ")
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
            if let Some(b) = self.table.bidama(&import.package).and_then(|s| s.get(n)) {
                let alias = self
                    .table
                    .bidama(&import.package)
                    .and_then(|s| s.alias_of(n))
                    .filter(|a| a.bridge && &b.name != n);
                if let Some(a) = alias {
                    let d = self.legacy_diagnostic(
                        *span,
                        &import.package,
                        n,
                        &b.name,
                        &a.since,
                        format!(":{n}"),
                        format!(":{}", b.name),
                    );
                    self.diagnostics.push(d);
                }
                continue;
            }
            let d = self.no_such_definition(*span, &import.package, n, false);
            self.diagnostics.push(d);
        }
    }
}

impl Scopes for Walker<'_> {
    /// A special form is in no tier and wins. Otherwise a program definition
    /// the tier order reaches (own, or listed) beats a builtin macro of the
    /// same name, for a head as for any reference: keyed per namespace, the
    /// definition can exist beside the macro, and the runtime calls it.
    fn head_kind(&self, name: &str) -> Option<HeadKind> {
        let kind = self.table.head_kind(name);
        if kind == Some(HeadKind::Macro)
            && matches!(
                self.table.ns_target(name, &self.own, self.top_level),
                Target::Def(..)
            )
        {
            return Some(HeadKind::Value);
        }
        kind
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

    /// A free symbol of a macro's template is qualified to the DEFINER's
    /// namespace (Clojure's syntax-quote rule), so the expansion means the
    /// same thing in every caller: a template naming its own bidama's `helper`
    /// expands to `pkg/helper` wherever it is used. Anything the definer's
    /// namespace does not bind stays as written — a builtin, or a name the
    /// expansion itself binds.
    fn template_symbol(&mut self, node: &Spanned, name: &str) {
        if self.frames.iter().any(|f| f.iter().any(|l| l.name == name)) {
            return;
        }
        let ns = self.table.ns_target(name, &self.own, self.top_level);
        if matches!(ns, Target::Def(..)) {
            self.references.push(Reference {
                top_level: self.top_level,
                span: node.span,
                written: name.to_string(),
                opaque: true,
                flat: self.table.flat_target(name),
                ns,
                shadowed: Vec::new(),
                node: std::ptr::from_ref(node) as usize,
            });
        }
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
                if !matches!(
                    name,
                    "define" | "define-typed" | "defmacro" | "use" | "legacy_names"
                ) =>
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
        // main.b (form 0) lists `first` from a and `twice` from a and b.
        let mut main = FileImports::default();
        main.add("a", ["first".to_string(), "twice".to_string()]);
        main.add("b", ["twice".to_string()]);
        t.attach_files(vec![0], BTreeMap::from([(0, main)]));
        t
    }

    fn tier_of(t: &NameTable, name: &str, own: &Namespace) -> Option<(Tier, String)> {
        match t.resolve_from(name, own, 0) {
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
        match t.resolve_from("twice", &main, 0) {
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
            t.resolve_from("nowhere", &Namespace::File("main.b".into()), 0),
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
