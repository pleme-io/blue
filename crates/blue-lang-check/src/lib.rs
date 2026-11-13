//! The typing ladder — rung 0 and rung 1.
//!
//! §0's central claim, made mechanical:
//!
//! > **Declare nothing and get ZERO analysis. Declare, and get analysis on
//! > that structure only. Correctness never moves.**
//!
//! Two properties make that literal rather than aspirational, and both are
//! property-tested in this crate:
//!
//! 1. **Zero analysis at rung 0.** An unannotated program is not walked
//!    and waved through — it is *not walked*. [`check_program`] returns
//!    immediately on a form with no annotated head, and [`Stats::visited`]
//!    records zero nodes. A checker that must visit every node to discover
//!    there is nothing to check has already paid the cost the ladder
//!    exists to avoid.
//!
//! 2. **Never infer backward across an undeclared boundary.** When typed
//!    code calls something undeclared, the argument is `Dyn` and the
//!    obligation is discharged **at the seam** — a check recorded right
//!    there. The checker does not chase the callee to find out what it
//!    returns. This is the discipline that makes cost a function of
//!    *annotation density* rather than of the transitive call graph, and
//!    §0 states it as the thing that makes the ladder slide *exactly*
//!    rather than approximately.
//!
//! **Honest tier.** These are `checked-at-expansion` diagnostics over a
//! tree. Nothing here is unrepresentability: a type error is a reported
//! `Diagnostic`, not an absent code path. The docs say so because §V.24
//! caught this document rounding exactly this kind of tier up.

use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};

use tatara_lisp::{Atom, Sexp, Span, Spanned, SpannedForm};

pub mod chains;
pub mod contracts;
pub mod controls;
pub mod data_laws;
pub mod doc_rules;
pub mod evolution;
pub mod fixes;
pub mod form_rules;
pub mod laws;
pub mod lia;
pub mod names;
pub mod namespace_rules;
pub mod obligations;
mod package_moves;
pub mod points;
pub mod project;
pub mod properties;
pub mod records;
pub mod respell;
pub mod rules;
pub mod shape;
pub mod suggest;
pub mod unions;
pub mod waiver;
pub mod walk_cache;

pub use names::{check_names, Binding, NameTable, Namespace, Scope, ScopeKind};
pub use rules::{Code, Explain, FixKind, Rule, Severity, RULES};

/// A blue type at rung 1.
///
/// `Dyn` is the top and the default. Every rule below is written so that
/// `Dyn` on either side succeeds — the ladder's promise is that
/// unannotated code is *less analyzed*, never *less correct*.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Ty {
    Dyn,
    Int,
    Float,
    Str,
    Bool,
    Sym,
    Nil,
    List(Box<Ty>),
    Map(Box<Ty>, Box<Ty>),
    Record(String),
    Union(String, Vec<String>),
    /// A name the checker does not know. Treated as opaque and nominal.
    Named(String),
    Fragment(Box<data_laws::Selection>),
}

impl Ty {
    /// Parse a type expression as written in a signature.
    pub fn from_sexp(s: &Sexp) -> Ty {
        match s {
            Sexp::Atom(Atom::Symbol(n)) => match n.as_str() {
                "dyn" => Ty::Dyn,
                "Int" => Ty::Int,
                "Float" => Ty::Float,
                "Str" => Ty::Str,
                "Bool" => Ty::Bool,
                "Sym" => Ty::Sym,
                "Nil" => Ty::Nil,
                "List" => Ty::List(Box::new(Ty::Dyn)),
                "Map" => Ty::Map(Box::new(Ty::Dyn), Box::new(Ty::Dyn)),
                other => Ty::Named(other.to_string()),
            },
            Sexp::List(items) => match (items.first(), &items[1..]) {
                (Some(Sexp::Atom(Atom::Symbol(h))), [t]) if h == "List" => {
                    Ty::List(Box::new(Ty::from_sexp(t)))
                }
                (Some(Sexp::Atom(Atom::Symbol(h))), [k, v]) if h == "Map" => {
                    Ty::Map(Box::new(Ty::from_sexp(k)), Box::new(Ty::from_sexp(v)))
                }
                _ => Ty::Dyn,
            },
            _ => Ty::Dyn,
        }
    }

    /// Is a value of type `self` acceptable where `want` is expected?
    ///
    /// **`Dyn` is compatible in BOTH directions.** That is not laxness —
    /// it is the gradual guarantee's shape: adding an annotation may make
    /// a program *check*, and removing one may make it stop checking, but
    /// neither changes what the program means.
    pub fn accepts(&self, want: &Ty) -> bool {
        match (self, want) {
            (Ty::Dyn, _) | (_, Ty::Dyn) => true,
            (Ty::List(a), Ty::List(b)) => a.accepts(b),
            (Ty::Map(ka, va), Ty::Map(kb, vb)) => ka.accepts(kb) && va.accepts(vb),
            (Ty::Record(_), Ty::Map(k, _)) => Ty::Sym.accepts(k),
            (Ty::Record(r), Ty::Union(_, arms)) => arms.contains(r),
            (Ty::Union(a, _), Ty::Union(b, _)) => a == b,
            (Ty::Fragment(a), Ty::Fragment(b)) => a.fragment == b.fragment && a.path == b.path,
            (a, b) => a == b,
        }
    }

    pub fn name(&self) -> String {
        match self {
            Ty::Dyn => "dyn".into(),
            Ty::Int => "Int".into(),
            Ty::Float => "Float".into(),
            Ty::Str => "Str".into(),
            Ty::Bool => "Bool".into(),
            Ty::Sym => "Sym".into(),
            Ty::Nil => "Nil".into(),
            Ty::List(t) => format!("List({})", t.name()),
            Ty::Map(k, v) => format!("Map({}, {})", k.name(), v.name()),
            Ty::Record(n) | Ty::Union(n, _) | Ty::Named(n) => n.clone(),
            Ty::Fragment(sel) => sel.type_name(),
        }
    }

    #[must_use]
    pub fn opaque(&self) -> bool {
        match self {
            Ty::Named(_) => true,
            Ty::List(t) => t.opaque(),
            Ty::Map(k, v) => k.opaque() || v.opaque(),
            _ => false,
        }
    }

    #[must_use]
    pub fn join(&self, other: &Ty) -> Ty {
        if self == other {
            self.clone()
        } else {
            Ty::Dyn
        }
    }
}

#[must_use]
pub fn builtin_result(name: &str) -> Option<Ty> {
    Some(match name {
        "length" | "count" => Ty::Int,
        "to_s" | "upcase" | "downcase" | "trim" | "join" | "join_lines" | "unlines" | "replace" => {
            Ty::Str
        }
        "split" | "chars" => Ty::List(Box::new(Ty::Str)),
        "empty?" | "contains?" | "starts_with?" | "ends_with?" | "member?" | "even?" | "odd?"
        | "zero?" | "positive?" | "negative?" | "string?" | "number?" | "integer?" | "nil?"
        | "some?" | "list?" | "map?" | "keyword?" | "bool?" | "symbol?" => Ty::Bool,
        _ => return None,
    })
}

/// A reported problem: a registry [`Code`], a severity, a primary span, and
/// what a reader (or an agent) needs to act on it without guessing — related
/// places, a help line, and zero or more suggested fixes.
///
/// The shape is rustc's, deliberately: a stable code with a long explanation
/// behind `blue explain`, and fixes carrying an [`Applicability`] so a tool can
/// apply the safe ones unattended and must show the rest to someone.
#[derive(Clone, Debug, PartialEq)]
pub struct Diagnostic {
    /// Which rule this is. Its row in [`RULES`] is the explanation.
    pub code: Code,
    /// Copied from the code's row when built through [`Diagnostic::new`];
    /// a field rather than a lookup so a consumer never needs the registry.
    pub severity: Severity,
    pub message: String,
    /// The byte range in the source that caused it.
    ///
    /// **This field is why the checker walks [`Spanned`] and not `Sexp`.** It
    /// carried only `message` until 2026-08-12, and the consequence was visible
    /// in every editor: `blue-lang-lsp` had nowhere to get a range from, so it
    /// attached every type error to `Range::default()` — line 0, column 0 —
    /// while parse errors, which had a span, pointed at the right byte. A type
    /// error in a 300-line file was reported on its first character.
    ///
    /// Synthetic only for a node with no source origin at all. A checker fed a
    /// tree lifted with `Spanned::from_sexp_synthetic` reports synthetic spans
    /// throughout, which is honest and useless — see [`check_program`] on which
    /// door a consumer should be using.
    pub span: Span,
    /// Index of the TOP-LEVEL form this arose in, into the slice
    /// [`check_program`] was given.
    ///
    /// **The join key for a program assembled from more than one file.** A
    /// `Span` is a byte range and nothing else — its own upstream docs say
    /// spans "are not portable across source inputs … meaningful only relative
    /// to the string that produced them" — so in a program whose forms came
    /// from several files, `span` alone cannot say *which* string. The caller
    /// that concatenated the files knows, and it knows per top-level form,
    /// which is exactly as fine-grained as it needs to be: every node under a
    /// top-level form came from the file that top-level form came from.
    /// `blue_lang_runtime::uses::ResolvedProgram` is the table that resolves it.
    ///
    /// Every span in [`Self::related`] and [`Self::fixes`] is in the same file
    /// as [`Self::span`]: the same top-level form, so the same join key.
    ///
    /// A single-file consumer (the LSP, `blue check`) may ignore this — there
    /// is one file and it is the one it just read.
    pub top_level: usize,
    /// Other places that explain this one ("defined here").
    pub related: Vec<Related>,
    /// One line on what to do.
    pub help: Option<String>,
    /// Edits that would resolve it, best first.
    pub fixes: Vec<Fix>,
}

/// A secondary location attached to a [`Diagnostic`].
#[derive(Clone, Debug, PartialEq)]
pub struct Related {
    pub span: Span,
    pub message: String,
}

/// How safe a [`Fix`] is to apply without a person reading it.
///
/// rustc's two ends of its scale: a fix is either known to preserve meaning, or
/// it is a guess. `blue check --fix` applies only the first.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Applicability {
    MachineApplicable,
    MaybeIncorrect,
}

impl Applicability {
    /// The kebab-case word `--format json` uses.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Applicability::MachineApplicable => "machine-applicable",
            Applicability::MaybeIncorrect => "maybe-incorrect",
        }
    }
}

/// A suggested repair: one or more byte-range replacements, applied together.
#[derive(Clone, Debug, PartialEq)]
pub struct Fix {
    /// What the fix does, e.g. "replace with `length`".
    pub message: String,
    pub edits: Vec<Edit>,
    pub applicability: Applicability,
}

/// Replace the bytes at `span` with `replacement`.
///
/// `original` is what the span must contain for the edit to apply. An applier
/// compares it before writing, so an edit computed against one version of a
/// file cannot land on another (an editor buffer that moved on, a file
/// reformatted since) and corrupt it.
#[derive(Clone, Debug, PartialEq)]
pub struct Edit {
    pub span: Span,
    pub original: String,
    pub replacement: String,
}

impl Diagnostic {
    /// `top_level` before the stamping loop in [`check_program`] assigns it.
    ///
    /// A sentinel rather than `0`, because `0` is a REAL index: a diagnostic
    /// that escaped stamping would silently claim to come from the first
    /// top-level form — in a multi-file program, from the entry file — which is
    /// precisely the confident-wrong position this field exists to end. Out of
    /// range resolves to no file at all, which renders as a position-free
    /// message: less information, no lie. `no_diagnostic_escapes_unstamped`
    /// gates it.
    pub const UNSTAMPED: usize = usize::MAX;

    /// A diagnostic with `code`'s registry severity, unstamped, with no
    /// related spans, help or fixes.
    #[must_use]
    pub fn new(code: Code, message: impl Into<String>, span: Span) -> Self {
        Self {
            code,
            severity: code.severity(),
            message: message.into(),
            span,
            top_level: Self::UNSTAMPED,
            related: Vec::new(),
            help: None,
            fixes: Vec::new(),
        }
    }

    #[must_use]
    pub fn at_top_level(mut self, top_level: usize) -> Self {
        self.top_level = top_level;
        self
    }

    #[must_use]
    pub fn with_help(mut self, help: impl Into<String>) -> Self {
        self.help = Some(help.into());
        self
    }

    #[must_use]
    pub fn with_fix(mut self, fix: Fix) -> Self {
        self.fixes.push(fix);
        self
    }

    #[must_use]
    pub fn with_related(mut self, span: Span, message: impl Into<String>) -> Self {
        self.related.push(Related {
            span,
            message: message.into(),
        });
        self
    }

    /// Does this diagnostic stop the pipeline?
    #[must_use]
    pub fn is_error(&self) -> bool {
        self.severity == Severity::Error
    }
}

/// A diagnostic renders itself. Per ★★ TYPED EMISSION the only sanctioned
/// ways to produce a string are a `Display`-family `write!`, a typed log or
/// error macro, and a typed AST builder — so a consumer that needed the text
/// was a missing `Display`, not a licence to `format!` at the call site.
impl std::fmt::Display for Diagnostic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}[{}]: {}", self.severity, self.code, self.message)
    }
}

/// A runtime check the compiler must insert because a static one was not
/// available — a **seam**.
///
/// Seams are recorded rather than silently emitted, because §0's rule is
/// that an invisible cost is the one unacceptable outcome. `blue check`
/// can show exactly where the boundary work lands.
#[derive(Clone, Debug, PartialEq)]
pub struct Seam {
    /// The type the typed side requires.
    pub expected: Ty,
    /// Where the check sits, for the report.
    pub at: String,
    /// The byte range of the argument the check guards.
    ///
    /// Spanned for the same reason a diagnostic is: §0's rule is that an
    /// invisible cost is the one unacceptable outcome, and "argument 1 of `add`"
    /// is only half a location — it does not say *which* call. A seam is also
    /// the place a debugger will want to break, since it is exactly where the
    /// compiler inserts work the source does not show.
    pub span: Span,
}

/// What the checker did, so the claim "zero analysis" can be *measured*
/// rather than asserted.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Stats {
    /// Nodes actually visited by the type walk.
    pub visited: usize,
    /// Declarations that carried an annotation.
    pub typed_decls: usize,
    /// Name references resolved by [`check_names`]. Zero until that pass runs;
    /// a corpus gate reads it to prove the pass looked at something.
    pub names_resolved: usize,
    pub boundary_visited: usize,
}

#[derive(Clone, Debug, Default)]
pub struct Outcome {
    pub diagnostics: Vec<Diagnostic>,
    pub seams: Vec<Seam>,
    pub stats: Stats,
    /// Diagnostics an in-source waiver suppressed, with the waiver that did
    /// it. Reported, never silently dropped: see [`waiver`].
    pub waived: Vec<waiver::Waived>,
    /// Findings of rules whose census has not reached zero: computed,
    /// counted by `blue census`, and not enforced. See [`Rule::active`].
    pub census: Vec<Diagnostic>,
}

impl Outcome {
    /// No ERROR-severity diagnostic. Warnings do not stop a program.
    pub fn ok(&self) -> bool {
        !self.diagnostics.iter().any(Diagnostic::is_error)
    }

    /// The error-severity diagnostics, the ones that stop the pipeline.
    pub fn errors(&self) -> impl Iterator<Item = &Diagnostic> {
        self.diagnostics.iter().filter(|d| d.is_error())
    }
}

/// A function's declared signature.
#[derive(Clone, Debug)]
struct Sig {
    params: Vec<Ty>,
    ret: Ty,
}

/// Check a program.
///
/// **Takes the SPANNED tree, which is the parser's real output.** Reach for
/// `blue_lang_syntax::parse_program_tree`, not `parse_program` — a caller that
/// lifts a spanless tree with `Spanned::from_sexp_synthetic` gets an `Outcome`
/// whose every diagnostic says `<synthetic>` where a position should be, and an
/// editor given that has nothing to underline. That is not a hypothetical: it is
/// exactly the state this function replaced.
pub fn check_program(forms: &[Spanned]) -> Outcome {
    check_program_in(forms, &|_, _| true)
}

pub fn check_program_in(forms: &[Spanned], same_file: &dyn Fn(usize, usize) -> bool) -> Outcome {
    check_program_with(forms, same_file, &|_| None)
}

pub fn check_program_with(
    forms: &[Spanned],
    same_file: &dyn Fn(usize, usize) -> bool,
    package_of: &dyn Fn(usize) -> Option<String>,
) -> Outcome {
    let decls = Decls::collect(forms, package_of);
    let mut out = walk(forms, &decls, same_file, &|_| true, &mut BTreeMap::new());
    boundary(forms, &decls, same_file, &mut out);
    strict(forms, same_file, &mut out);
    out
}

pub(crate) fn typed_bindings(
    forms: &[Spanned],
    wanted: &dyn Fn(usize) -> bool,
) -> BTreeMap<usize, BTreeMap<String, Ty>> {
    let mut bindings = BTreeMap::new();
    let decls = Decls::collect(forms, &|_| None);
    walk(forms, &decls, &|_, _| true, wanted, &mut bindings);
    bindings
}

#[derive(Default)]
struct Types {
    records: BTreeMap<String, Vec<(String, Ty)>>,
    unions: BTreeMap<String, Vec<String>>,
}

impl Types {
    fn collect(forms: &[Spanned]) -> Types {
        let mut out = Types::default();
        let mut by_predicate = BTreeMap::new();
        for form in forms {
            let Some(r) = blue_lang_syntax::record::record_parts(form) else {
                continue;
            };
            let (Some(name), Some(predicate)) = (r.name.as_symbol(), r.predicate.as_symbol())
            else {
                continue;
            };
            by_predicate.insert(predicate.to_string(), name.to_string());
            let fields = r
                .fields
                .iter()
                .map(|f| {
                    let ty = f.ty.map_or(Ty::Dyn, |t| Ty::from_sexp(&t.to_sexp()));
                    (f.name.to_string(), ty)
                })
                .collect();
            out.records.insert(name.to_string(), fields);
        }
        for form in forms {
            let Some(u) = blue_lang_syntax::union::declared(form) else {
                continue;
            };
            let Some(name) = u.name.as_symbol() else {
                continue;
            };
            let arms = u
                .arms
                .iter()
                .filter_map(|a| a.as_symbol().and_then(|p| by_predicate.get(p)).cloned())
                .collect();
            out.unions.insert(name.to_string(), arms);
        }
        out
    }

    fn resolve(&self, t: Ty) -> Ty {
        match t {
            Ty::Named(n) => match self.unions.get(&n) {
                Some(arms) => Ty::Union(n, arms.clone()),
                None if self.records.contains_key(&n) => Ty::Record(n),
                None => Ty::Named(n),
            },
            Ty::List(t) => Ty::List(Box::new(self.resolve(*t))),
            Ty::Map(k, v) => Ty::Map(Box::new(self.resolve(*k)), Box::new(self.resolve(*v))),
            t => t,
        }
    }

    fn field(&self, record: &str, key: &str) -> Option<Option<Ty>> {
        let fields = self.records.get(record)?;
        Some(
            fields
                .iter()
                .find(|(n, _)| n == key)
                .map(|(_, t)| self.resolve(t.clone())),
        )
    }
}

struct Decls {
    sigs: BTreeMap<String, Sig>,
    qualified: BTreeMap<String, Sig>,
    frags: data_laws::Fragments,
    types: Types,
    counts: BTreeMap<String, usize>,
    defined: BTreeSet<String>,
    typed_decls: usize,
}

impl Decls {
    fn collect(forms: &[Spanned], package_of: &dyn Fn(usize) -> Option<String>) -> Decls {
        let frags = data_laws::Fragments::collect(forms);
        let mut raw = Vec::new();
        for (i, form) in forms.iter().enumerate() {
            if let Some(decl) = read_typed_decl(form) {
                raw.push((i, decl));
            }
        }
        let types = if raw.is_empty() {
            Types::default()
        } else {
            Types::collect(forms)
        };
        let mut sigs = BTreeMap::new();
        let mut qualified = BTreeMap::new();
        let typed_decls = raw.len();
        for (i, (name, mut sig)) in raw {
            for p in &mut sig.params {
                let t = std::mem::replace(p, Ty::Dyn);
                *p = match &t {
                    Ty::Named(n) => match frags.by_type(n) {
                        Some(f) => Ty::Fragment(Box::new(f.selection.clone())),
                        None => types.resolve(t),
                    },
                    _ => types.resolve(t),
                };
            }
            sig.ret = types.resolve(std::mem::replace(&mut sig.ret, Ty::Dyn));
            if let Some(package) = package_of(i) {
                qualified.insert(
                    format!("{package}{}{name}", blue_lang_syntax::QUALIFIER),
                    sig.clone(),
                );
            }
            sigs.insert(name, sig);
        }
        let counts = if sigs.is_empty() {
            BTreeMap::new()
        } else {
            top_level_counts(forms)
        };
        let defined = counts.keys().cloned().collect();
        Decls {
            sigs,
            qualified,
            frags,
            types,
            counts,
            defined,
            typed_decls,
        }
    }

    fn at_boundary(&self, head: &str) -> Option<&Sig> {
        if head.contains(blue_lang_syntax::QUALIFIER) {
            return self.qualified.get(head);
        }
        if self.counts.get(head) == Some(&1) {
            return self.sigs.get(head);
        }
        None
    }
}

fn walk(
    forms: &[Spanned],
    decls: &Decls,
    same_file: &dyn Fn(usize, usize) -> bool,
    wanted: &dyn Fn(usize) -> bool,
    bindings: &mut BTreeMap<usize, BTreeMap<String, Ty>>,
) -> Outcome {
    let mut out = Outcome::default();
    out.stats.typed_decls = decls.typed_decls;
    let sigs = &decls.sigs;
    let none = BTreeSet::new();

    // Pass 2: walk ONLY the typed declarations' bodies.
    //
    // This is the mechanical form of "zero analysis at rung 0": an
    // unannotated program never enters the loop body.
    for (top_level, form) in forms.iter().enumerate() {
        if !wanted(top_level) {
            continue;
        }
        if let Some((name, _)) = read_typed_decl(form) {
            let Some(items) = form.as_list() else {
                continue;
            };
            let sig = sigs.get(&name).expect("just inserted");
            let body = &items[3];
            let mut shadowed = decls.defined.clone();
            contracts::binders_of(std::slice::from_ref(body), true, &mut shadowed);
            let mut unsettled = BTreeSet::new();
            nested_defines(body, true, &mut unsettled);
            let mut env: BTreeMap<String, Ty> = BTreeMap::new();
            let bound = RefCell::new(BTreeMap::new());
            if let Some(params) = items[1].as_list() {
                for (i, p) in params[1..].iter().filter(|p| !is_marker(p)).enumerate() {
                    if let Some(pair) = p.as_list() {
                        if let Some(pn) = pair[0].as_symbol() {
                            env.insert(pn.to_string(), sig.params[i].clone());
                            settle(&bound, pn, &sig.params[i]);
                        }
                    }
                }
            }
            // Stamp the file-identity key ONCE, here, over whatever `infer`
            // pushed while walking this declaration's body.
            //
            // The alternative was threading `top_level` through `infer` and its
            // eight recursive call sites — eight chances to pass the wrong one,
            // to buy a value that is constant for the whole walk. It is a
            // property of WHICH top-level form is being walked, and only this
            // loop knows that, so it is recorded where it is known.
            let before = out.diagnostics.len();
            let cx = Cx {
                decls,
                top: top_level,
                same_file,
                shadowed: &shadowed,
                unsettled: &unsettled,
                bound: &bound,
                locals: &none,
                boundary: false,
            };
            let body_ty = infer(body, &env, &cx, &mut out);
            let mut rebound = BTreeSet::new();
            contracts::binders_of(std::slice::from_ref(body), false, &mut rebound);
            for n in rebound.iter().chain(&unsettled) {
                bound.borrow_mut().insert(n.clone(), None);
            }
            bindings.insert(
                top_level,
                bound
                    .into_inner()
                    .into_iter()
                    .filter_map(|(n, t)| t.map(|t| (n, t)))
                    .collect(),
            );
            for d in &mut out.diagnostics[before..] {
                d.top_level = top_level;
            }
            if !body_ty.accepts(&sig.ret) {
                out.diagnostics.push(
                    Diagnostic::new(
                        Code::B0003,
                        format!(
                            "`{name}` declares it returns {}, but its body produces {}",
                            sig.ret.name(),
                            body_ty.name()
                        ),
                        // The BODY, not the return annotation and not the whole
                        // `def`. The annotation is a statement of intent the author
                        // meant; the body is the thing that disagrees with it, and
                        // rustc points at the tail expression for the same reason.
                        // Pointing at the whole declaration would underline a
                        // twenty-line function to report one wrong line.
                        body.span,
                    )
                    .at_top_level(top_level)
                    .with_help(format!(
                        "change the body to produce {}, or change the declared return type",
                        sig.ret.name()
                    )),
                );
            }
        }
    }

    out
}

fn boundary(
    forms: &[Spanned],
    decls: &Decls,
    same_file: &dyn Fn(usize, usize) -> bool,
    out: &mut Outcome,
) {
    if decls.sigs.is_empty() {
        return;
    }
    for (top_level, form) in forms.iter().enumerate() {
        if read_typed_decl(form).is_some()
            || blue_lang_syntax::scope::is_file_declaration(form)
            || blue_lang_syntax::record::record_parts(form).is_some()
            || blue_lang_syntax::union::declared(form).is_some()
        {
            continue;
        }
        let Some(items) = form.as_list() else {
            continue;
        };
        if matches!(
            items.first().and_then(Spanned::as_symbol),
            Some("defmacro" | "quote" | "quasiquote")
        ) {
            continue;
        }
        let mut locals = BTreeSet::new();
        contracts::binders_of(std::slice::from_ref(form), true, &mut locals);
        let mut shadowed = decls.defined.clone();
        shadowed.extend(locals.iter().cloned());
        let body: &[Spanned] = match items {
            [head, sig, rest @ ..]
                if head.as_symbol() == Some("define") && sig.as_list().is_some() =>
            {
                rest
            }
            _ => std::slice::from_ref(form),
        };
        let mut unsettled = BTreeSet::new();
        for b in body {
            nested_defines(b, true, &mut unsettled);
        }
        let bound = RefCell::new(BTreeMap::new());
        let cx = Cx {
            decls,
            top: top_level,
            same_file,
            shadowed: &shadowed,
            unsettled: &unsettled,
            bound: &bound,
            locals: &locals,
            boundary: true,
        };
        let mut scratch = Outcome::default();
        for b in body {
            infer(b, &BTreeMap::new(), &cx, &mut scratch);
        }
        out.stats.boundary_visited += scratch.stats.visited;
        out.diagnostics.extend(
            scratch
                .diagnostics
                .into_iter()
                .filter(|d| d.code == Code::B0005)
                .map(|d| d.at_top_level(top_level)),
        );
    }
}

fn strict(forms: &[Spanned], same_file: &dyn Fn(usize, usize) -> bool, out: &mut Outcome) {
    let markers: Vec<usize> = forms
        .iter()
        .enumerate()
        .filter(|(_, f)| blue_lang_syntax::scope::is_strict_marker(f))
        .map(|(i, _)| i)
        .collect();
    if markers.is_empty() {
        return;
    }
    for (top_level, form) in forms.iter().enumerate() {
        if !markers.iter().any(|m| same_file(*m, top_level)) {
            continue;
        }
        let Some([head, sig, ..]) = form.as_list() else {
            continue;
        };
        if head.as_symbol() != Some("define") {
            continue;
        }
        let Some(name_node) = sig.as_list().and_then(|s| s.first()) else {
            continue;
        };
        let name = name_node.as_symbol().unwrap_or("_");
        out.diagnostics.push(
            Diagnostic::new(
                Code::B0082,
                format!("`{name}` is untyped in a `blueshift(:strict)` file"),
                name_node.span,
            )
            .at_top_level(top_level)
            .with_help(
                "annotate a parameter or the return; `-> dyn` says the function returns any value",
            ),
        );
    }
}

fn is_marker(p: &Spanned) -> bool {
    p.as_symbol().is_some_and(|n| n.starts_with('&'))
}

/// Read `(define-typed (name (p T) ...) R body)`.
fn read_typed_decl(form: &Spanned) -> Option<(String, Sig)> {
    let items = form.as_list()?;
    if items.len() != 4 {
        return None;
    }
    if items[0].as_symbol()? != "define-typed" {
        return None;
    }
    let sig = items[1].as_list()?;
    let name = sig[0].as_symbol()?;
    let params = sig[1..]
        .iter()
        .filter(|p| !is_marker(p))
        .map(|p| match p.as_list() {
            Some(pair) if pair.len() == 2 => Ty::from_sexp(&pair[1].to_sexp()),
            _ => Ty::Dyn,
        })
        .collect();
    Some((
        name.to_string(),
        Sig {
            params,
            ret: Ty::from_sexp(&items[2].to_sexp()),
        },
    ))
}

/// Arithmetic and comparison shapes, so operators can be checked without
/// a full trait system at this rung.
fn op_sig(op: &str) -> Option<(Ty, Ty)> {
    Some(match op {
        "+" | "-" | "*" | "/" | "%" => (Ty::Int, Ty::Int),
        "<" | "<=" | ">" | ">=" => (Ty::Int, Ty::Bool),
        "==" | "!=" => (Ty::Dyn, Ty::Bool),
        "&&" | "||" => (Ty::Bool, Ty::Bool),
        _ => return None,
    })
}

struct Cx<'a> {
    decls: &'a Decls,
    top: usize,
    same_file: &'a dyn Fn(usize, usize) -> bool,
    shadowed: &'a BTreeSet<String>,
    unsettled: &'a BTreeSet<String>,
    bound: &'a RefCell<BTreeMap<String, Option<Ty>>>,
    locals: &'a BTreeSet<String>,
    boundary: bool,
}

impl Cx<'_> {
    fn sig(&self, head: &str) -> Option<&Sig> {
        if self.boundary {
            if self.locals.contains(head) {
                return None;
            }
            return self.decls.at_boundary(head);
        }
        self.decls.sigs.get(head)
    }

    fn builtin(&self, head: &str, env: &BTreeMap<String, Ty>) -> bool {
        !env.contains_key(head) && !self.shadowed.contains(head)
    }
}

fn settle(bound: &RefCell<BTreeMap<String, Option<Ty>>>, name: &str, t: &Ty) {
    let t = (*t != Ty::Dyn).then(|| t.clone());
    bound
        .borrow_mut()
        .entry(name.to_string())
        .and_modify(|v| {
            if *v != t {
                *v = None;
            }
        })
        .or_insert(t);
}

fn top_level_counts(forms: &[Spanned]) -> BTreeMap<String, usize> {
    let mut out = BTreeMap::new();
    for form in forms {
        let Some(items) = form.as_list() else {
            continue;
        };
        let Some(head) = items.first().and_then(Spanned::as_symbol) else {
            continue;
        };
        if !head.starts_with("def") {
            continue;
        }
        let name = items.get(1).and_then(|n| {
            n.as_symbol().or_else(|| {
                n.as_list()
                    .and_then(|l| l.first())
                    .and_then(Spanned::as_symbol)
            })
        });
        if let Some(n) = name {
            *out.entry(n.to_string()).or_insert(0) += 1;
        }
    }
    out
}

fn nested_defines(s: &Spanned, root: bool, out: &mut BTreeSet<String>) {
    let Some(items) = s.as_list() else { return };
    let head = items.first().and_then(Spanned::as_symbol);
    match head {
        Some("quote" | "quasiquote") => return,
        Some("set!") => {
            if let Some(n) = items.get(1).and_then(Spanned::as_symbol) {
                out.insert(n.to_string());
            }
        }
        Some("define") if !root => {
            if let Some(n) = items.get(1).and_then(Spanned::as_symbol) {
                out.insert(n.to_string());
            }
        }
        _ => {}
    }
    if root && head == Some("begin") {
        for i in &items[1..] {
            let direct = i
                .as_list()
                .and_then(|l| l.first())
                .and_then(Spanned::as_symbol)
                == Some("define");
            match i.as_list() {
                Some(d) if direct => {
                    for v in &d[2..] {
                        nested_defines(v, false, out);
                    }
                }
                _ => nested_defines(i, false, out),
            }
        }
        return;
    }
    for i in items {
        nested_defines(i, false, out);
    }
}

fn literal_key(s: &Spanned) -> Option<&str> {
    s.as_keyword().or_else(|| s.as_string())
}

fn read_field(
    sel: &data_laws::Selection,
    key: &str,
    at: Span,
    cx: &Cx<'_>,
    out: &mut Outcome,
) -> Ty {
    if let Some(f) = sel.field(key) {
        return f
            .sub
            .clone()
            .map_or(Ty::Dyn, |sub| Ty::Fragment(Box::new(sub)));
    }
    if key == "__typename" {
        return Ty::Dyn;
    }
    let owner = cx.decls.frags.get(&sel.fragment).map(|f| f.top_level);
    let editable = owner.is_some_and(|o| (cx.same_file)(o, cx.top));
    let d = match cx.decls.frags.declaring(sel, key) {
        Some(child) => Diagnostic::new(
            Code::B0048,
            format!(
                "`{key}` is declared by fragment `{child}`, not by {}: a parent cannot read a child's field",
                sel.place()
            ),
            at,
        )
        .with_help(format!(
            "pass the value to the component whose parameter is `{}`, or declare `{key}` here as well",
            data_laws::type_name(&child)
        )),
        None => {
            let d = Diagnostic::new(
                Code::B0048,
                format!("`{key}` is not declared by {}", sel.place()),
                at,
            )
            .with_help(format!("declare `{key}` in the fragment's fields, or stop reading it"));
            match sel.add_field(key).filter(|_| editable) {
                Some(edit) => d.with_fix(Fix {
                    message: format!("declare `{key}` in {}", sel.place()),
                    edits: vec![edit],
                    applicability: Applicability::MaybeIncorrect,
                }),
                None => d,
            }
        }
    };
    out.diagnostics.push(d);
    Ty::Dyn
}

fn record_field(record: &str, key: &str, at: Span, cx: &Cx<'_>, out: &mut Outcome) -> Ty {
    match cx.decls.types.field(record, key) {
        Some(Some(t)) => t,
        Some(None) => {
            let fields: Vec<String> = cx.decls.types.records[record]
                .iter()
                .map(|(n, _)| format!("`{n}`"))
                .collect();
            out.diagnostics.push(
                Diagnostic::new(Code::B0079, format!("`{record}` has no field `{key}`"), at)
                    .with_help(format!("its fields are {}", fields.join(", "))),
            );
            Ty::Dyn
        }
        None => Ty::Dyn,
    }
}

fn composed(
    want: &data_laws::Selection,
    got: &data_laws::Selection,
    head: &str,
    i: usize,
    at: Span,
    cx: &Cx<'_>,
    out: &mut Outcome,
) {
    if (got.fragment == want.fragment && got.path == want.path) || got.spreads(&want.fragment) {
        return;
    }
    let owner = cx.decls.frags.get(&got.fragment).map(|f| f.top_level);
    let editable = owner.is_some_and(|o| (cx.same_file)(o, cx.top));
    let d = Diagnostic::new(
        Code::B0049,
        format!(
            "`{head}` argument {} is a `{}` ref, and {} does not spread `...{}`: the operation is the union of the fragments of the components it renders",
            i + 1,
            want.type_name(),
            got.place(),
            want.fragment
        ),
        at,
    )
    .with_help(format!("spread `...{}` where the value is selected", want.fragment));
    let d = match got.add_spread(&want.fragment).filter(|_| editable) {
        Some(edit) => d.with_fix(Fix {
            message: format!("spread `...{}` in {}", want.fragment, got.place()),
            edits: vec![edit],
            applicability: Applicability::MachineApplicable,
        }),
        None => d,
    };
    out.diagnostics.push(d);
}

fn joined<'a>(
    items: impl Iterator<Item = &'a Spanned>,
    env: &BTreeMap<String, Ty>,
    cx: &Cx<'_>,
    out: &mut Outcome,
) -> Ty {
    let mut at: Option<Ty> = None;
    for i in items {
        let t = infer(i, env, cx, out);
        at = Some(match at {
            None => t,
            Some(a) => a.join(&t),
        });
    }
    at.unwrap_or(Ty::Dyn)
}

fn infer(s: &Spanned, env: &BTreeMap<String, Ty>, cx: &Cx<'_>, out: &mut Outcome) -> Ty {
    out.stats.visited += 1;
    match &s.form {
        SpannedForm::Nil => Ty::Nil,
        SpannedForm::Atom(Atom::Int(_)) => Ty::Int,
        SpannedForm::Atom(Atom::Float(_)) => Ty::Float,
        SpannedForm::Atom(Atom::Str(_)) => Ty::Str,
        SpannedForm::Atom(Atom::Bool(_)) => Ty::Bool,
        SpannedForm::Atom(Atom::Keyword(_)) => Ty::Sym,
        SpannedForm::Atom(Atom::Symbol(n)) => env.get(n).cloned().unwrap_or(Ty::Dyn),

        SpannedForm::List(items) if items.is_empty() => Ty::Nil,

        SpannedForm::List(items) => {
            let head = match items[0].as_symbol() {
                Some(h) => h,
                None => {
                    for i in items {
                        infer(i, env, cx, out);
                    }
                    return Ty::Dyn;
                }
            };

            // `if`
            if head == "if" && items.len() >= 3 {
                infer(&items[1], env, cx, out);
                let t = infer(&items[2], env, cx, out);
                if let Some(e) = items.get(3) {
                    let f = infer(e, env, cx, out);
                    return t.join(&f);
                }
                return Ty::Dyn;
            }

            if head == "begin" {
                let mut local = env.clone();
                let mut last = Ty::Nil;
                for i in &items[1..] {
                    let bound = i.as_list().and_then(|d| match d {
                        [h, name, value] if h.as_symbol() == Some("define") => {
                            name.as_symbol().map(|n| (n, value))
                        }
                        _ => None,
                    });
                    last = match bound {
                        Some((n, value)) => {
                            let t = infer(value, &local, cx, out);
                            let t = if cx.unsettled.contains(n) { Ty::Dyn } else { t };
                            settle(cx.bound, n, &t);
                            local.insert(n.to_string(), t);
                            Ty::Nil
                        }
                        None => infer(i, &local, cx, out),
                    };
                }
                return last;
            }

            if matches!(head, "lambda" | "fn") && items.len() >= 3 {
                let mut local = env.clone();
                if let Some(params) = items[1].as_list() {
                    for p in params {
                        if let Some(n) = p.as_symbol() {
                            local.insert(n.to_string(), Ty::Dyn);
                        }
                    }
                }
                for b in &items[2..] {
                    infer(b, &local, cx, out);
                }
                return Ty::Dyn;
            }

            if (head == "blue-field" || head == "get") && items.len() == 3 {
                let base = infer(&items[1], env, cx, out);
                if let (Ty::Fragment(sel), Some(key)) = (&base, literal_key(&items[2])) {
                    return read_field(sel, key, s.span, cx, out);
                }
                if let (Ty::Record(r), Some(key)) = (&base, literal_key(&items[2])) {
                    return record_field(r, key, items[2].span, cx, out);
                }
                infer(&items[2], env, cx, out);
                return Ty::Dyn;
            }

            // Operators
            if let Some((arg, ret)) = op_sig(head) {
                for a in &items[1..] {
                    let got = infer(a, env, cx, out);
                    if !got.accepts(&arg) {
                        out.diagnostics.push(Diagnostic::new(
                            Code::B0004,
                            format!("`{head}` expects {}, got {}", arg.name(), got.name()),
                            // The OFFENDING OPERAND, not the whole operator
                            // expression. `s + 1` where `s: Str` is a complaint
                            // about `s`; underlining `s + 1` would leave the
                            // reader to work out which half is wrong, and in
                            // `a + b + c` it would underline all of it.
                            //
                            // Unstamped: `check_program`'s pass-2 loop is the
                            // only place the top-level index is known.
                            a.span,
                        ));
                    }
                }
                return ret;
            }

            if head == "list" && cx.builtin(head, env) {
                return Ty::List(Box::new(joined(items[1..].iter(), env, cx, out)));
            }

            if head == blue_lang_syntax::LOWERED_MAP && cx.builtin(head, env) {
                let keys = joined(items[1..].iter().step_by(2), env, cx, out);
                let values = joined(items[1..].iter().skip(1).step_by(2), env, cx, out);
                return Ty::Map(Box::new(keys), Box::new(values));
            }

            if cx.decls.types.records.contains_key(head)
                && !env.contains_key(head)
                && !cx.locals.contains(head)
                && cx.sig(head).is_none()
            {
                for a in &items[1..] {
                    infer(a, env, cx, out);
                }
                return Ty::Record(head.to_string());
            }

            // A call to a DECLARED function: check the arguments.
            if let Some(sig) = cx.sig(head) {
                for (i, a) in items[1..].iter().enumerate() {
                    let got = infer(a, env, cx, out);
                    let Some(want) = sig.params.get(i) else {
                        continue;
                    };
                    if let (Ty::Fragment(w), Ty::Fragment(g)) = (want, &got) {
                        composed(w, g, head, i, a.span, cx, out);
                    } else if got == Ty::Dyn && *want != Ty::Dyn {
                        // THE SEAM. The argument is undeclared and the
                        // callee is not. The obligation is discharged HERE
                        // with a runtime check — the checker does NOT walk
                        // into the caller to find out what it produces.
                        out.seams.push(Seam {
                            expected: want.clone(),
                            at: format!("argument {} of `{head}`", i + 1),
                            span: a.span,
                        });
                    } else if !got.accepts(want)
                        && !(cx.boundary && (got.opaque() || want.opaque()))
                    {
                        out.diagnostics.push(Diagnostic::new(
                            Code::B0005,
                            format!(
                                "`{head}` argument {} expects {}, got {}",
                                i + 1,
                                want.name(),
                                got.name()
                            ),
                            a.span,
                        ));
                    }
                }
                return sig.ret.clone();
            }

            if cx.builtin(head, env) {
                if let Some(t) = builtin_result(head) {
                    for a in &items[1..] {
                        infer(a, env, cx, out);
                    }
                    return t;
                }
            }

            // A call to something UNDECLARED. Walk the arguments (they may
            // contain typed sub-expressions) and yield Dyn. **We do not go
            // looking for the callee's definition** — that is the backward
            // inference the ladder forbids.
            for a in &items[1..] {
                infer(a, env, cx, out);
            }
            Ty::Dyn
        }

        _ => Ty::Dyn,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use blue_lang_syntax::parse_program_tree;

    fn check(src: &str) -> Outcome {
        let forms = parse_program_tree(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
        check_program(&forms)
    }

    fn msgs(o: &Outcome) -> Vec<String> {
        o.diagnostics.iter().map(|d| d.message.clone()).collect()
    }

    /// The `(line, column)` a span's start resolves to in `src`, ZERO-based —
    /// what an editor would show, and what a fixture can state by hand.
    fn line_col(src: &str, span: Span) -> (usize, usize) {
        let (l, c) = Span::line_col(src, span.start);
        (l - 1, c - 1)
    }

    /// The exact source text a span covers. Independent evidence: it is a slice
    /// of the input, computed by nothing the checker owns.
    fn text(src: &str, span: Span) -> &str {
        &src[span.start..span.end]
    }

    // ---- rung 0: ZERO analysis, measured ------------------------------

    /// §0's claim taken literally. An unannotated program is not walked
    /// and waved through — it is not walked.
    #[test]
    fn unannotated_code_is_not_analyzed_at_all() {
        let o = check("def add(a, b)\n  a + b\nend\nadd(1, \"nope\")");
        assert!(o.ok(), "rung 0 produced diagnostics: {:?}", msgs(&o));
        assert_eq!(
            o.stats.visited, 0,
            "rung 0 visited {} nodes — zero analysis means zero",
            o.stats.visited
        );
        assert_eq!(o.stats.typed_decls, 0);
    }

    #[test]
    fn a_big_unannotated_program_still_visits_nothing() {
        let src = (0..50)
            .map(|i| format!("def f{i}(a, b)\n  a + b * {i}\nend"))
            .collect::<Vec<_>>()
            .join("\n");
        let o = check(&src);
        assert_eq!(o.stats.visited, 0);
    }

    // ---- rung 1: checked, and only where declared ---------------------

    #[test]
    fn an_annotated_function_is_checked() {
        let o = check("def add(a: Int, b: Int) -> Int\n  a + b\nend");
        assert!(o.ok(), "{:?}", msgs(&o));
        assert_eq!(o.stats.typed_decls, 1);
        assert!(o.stats.visited > 0, "a typed decl must actually be walked");
    }

    #[test]
    fn an_optional_parameter_keeps_its_own_declared_type() {
        let ok = check(
            "def f(a: Int, b?: Str) -> Str\n  b\nend\n\
             def g() -> Str\n  f(1, \"x\")\nend\n\
             def h() -> Str\n  f(1)\nend",
        );
        assert!(ok.ok(), "{:?}", msgs(&ok));
        let bad = check(
            "def f(a: Int, b?: Str) -> Str\n  b\nend\n\
             def g() -> Str\n  f(1, 2)\nend",
        );
        assert!(
            msgs(&bad)
                .iter()
                .any(|m| m.contains("argument 2 expects Str")),
            "{:?}",
            msgs(&bad)
        );
    }

    #[test]
    fn an_optional_parameter_does_not_shift_the_types_around_it() {
        let bad = check(
            "def f(a: Int, b?: Int, c?: Str) -> Int\n  a + b\nend\n\
             def g() -> Int\n  f(1, 2, 3)\nend",
        );
        assert!(
            msgs(&bad)
                .iter()
                .any(|m| m.contains("argument 3 expects Str")),
            "{:?}",
            msgs(&bad)
        );
        assert_eq!(bad.diagnostics.len(), 1, "{:?}", msgs(&bad));
    }

    #[test]
    fn a_wrong_return_type_is_reported() {
        let o = check("def f(a: Int) -> Str\n  a + 1\nend");
        assert!(!o.ok());
        assert!(msgs(&o)[0].contains("returns Str"), "{:?}", msgs(&o));
    }

    #[test]
    fn a_wrong_argument_type_is_reported() {
        let o = check(
            "def add(a: Int, b: Int) -> Int\n  a + b\nend\n\
             def g() -> Int\n  add(1, \"two\")\nend",
        );
        assert!(!o.ok());
        assert!(
            msgs(&o).iter().any(|m| m.contains("argument 2")),
            "{:?}",
            msgs(&o)
        );
    }

    #[test]
    fn an_operator_misuse_inside_a_typed_body_is_reported() {
        let o = check("def f(s: Str) -> Int\n  s + 1\nend");
        assert!(!o.ok());
        assert!(
            msgs(&o).iter().any(|m| m.contains("expects Int")),
            "{:?}",
            msgs(&o)
        );
    }

    // ---- the seam discipline ------------------------------------------

    /// The load-bearing rule: when typed code receives something
    /// undeclared, the obligation is discharged AT THE SEAM. The checker
    /// does not chase the callee.
    #[test]
    fn an_undeclared_argument_produces_a_seam_not_an_error() {
        let o = check(
            "def add(a: Int, b: Int) -> Int\n  a + b\nend\n\
             def g() -> Int\n  add(mystery(), 2)\nend",
        );
        assert!(
            o.ok(),
            "a dyn argument must not be an error: {:?}",
            msgs(&o)
        );
        assert_eq!(o.seams.len(), 1, "expected exactly one seam: {:?}", o.seams);
        assert_eq!(o.seams[0].expected, Ty::Int);
        assert!(o.seams[0].at.contains("argument 1"));
    }

    /// **Cost is a function of annotation density, not of the call graph.**
    /// Adding fifty unannotated functions around a typed one must not
    /// increase the work done — if it did, the ladder would not slide.
    #[test]
    fn cost_does_not_grow_with_untyped_code_around_it() {
        let typed = "def add(a: Int, b: Int) -> Int\n  a + b\nend";
        let small = check(typed);

        let noise = (0..50)
            .map(|i| format!("def n{i}(x, y)\n  x * y + {i}\nend"))
            .collect::<Vec<_>>()
            .join("\n");
        let big = check(&format!("{noise}\n{typed}\n{noise}"));

        assert_eq!(
            small.stats.visited, big.stats.visited,
            "analysis cost grew with surrounding untyped code: {} -> {}",
            small.stats.visited, big.stats.visited
        );
    }

    /// Dyn is compatible in both directions, so annotating never makes a
    /// working program stop working — the gradual guarantee's shape.
    #[test]
    fn dyn_is_compatible_in_both_directions() {
        assert!(Ty::Dyn.accepts(&Ty::Int));
        assert!(Ty::Int.accepts(&Ty::Dyn));
        let o = check("def f(a) -> Int\n  a\nend");
        assert!(o.ok(), "{:?}", msgs(&o));
    }

    /// Partial annotation is the ladder at its finest grain: one parameter
    /// checked, another left dyn, in the same signature.
    #[test]
    fn a_signature_can_be_partially_annotated() {
        let o = check(
            "def f(a: Int, b) -> Int\n  a\nend\n\
             def g() -> Int\n  f(\"bad\", 1)\nend",
        );
        assert!(
            msgs(&o).iter().any(|m| m.contains("argument 1")),
            "the annotated parameter should be checked: {:?}",
            msgs(&o)
        );
        assert!(
            !msgs(&o).iter().any(|m| m.contains("argument 2")),
            "the unannotated parameter must NOT be checked: {:?}",
            msgs(&o)
        );
    }

    // ---- anti-vacuity --------------------------------------------------

    /// The checker must be able to FAIL. If it never reported anything,
    /// every "ok" assertion above would be worthless.
    #[test]
    fn the_checker_actually_reports_errors() {
        assert!(!check("def f() -> Int\n  \"s\"\nend").ok());
        assert!(!check("def f(a: Str) -> Str\n  a + 1\nend").ok());
    }

    /// And it must be able to record a seam. A checker that produced none
    /// would pass the seam test by doing nothing.
    #[test]
    fn seams_are_actually_recorded() {
        let o = check("def f(a: Int) -> Int\n  a\nend\ndef g() -> Int\n  f(unknown())\nend");
        assert!(!o.seams.is_empty());
    }

    // ---- spans ----------------------------------------------------------
    //
    // Every assertion below states a position as a LITERAL line and column,
    // hand-counted from the fixture above it, and separately asserts the exact
    // source text the span slices out. Neither number comes from the checker, so
    // neither can agree with a wrong answer: a span off by one byte fails the
    // text assertion, and a span pointing at the wrong node fails both.
    //
    // Every fixture deliberately puts its error somewhere OTHER than line 0,
    // column 0. That was the value the LSP reported for every type error before
    // this field existed, so a gate whose fixture happens to have its error on
    // the first byte would pass against the exact bug being fixed.

    /// A return-type mismatch points at the BODY that disagrees.
    ///
    /// RED RUN (2026-08-12): `span: body.span` in `check_program` changed to
    /// `span: form.span` — the whole declaration, which is the plausible wrong
    /// answer rather than a nonsense one:
    ///
    ///   assertion `left == right` failed: the diagnostic must point at the body
    ///     left: (4, 0)
    ///    right: (5, 2)
    ///
    /// It reported the `def` keyword on line 4 instead of the body on line 5.
    #[test]
    fn a_return_type_mismatch_points_at_the_body() {
        // line 0: def ok(a: Int) -> Int
        // line 1:   a
        // line 2: end
        // line 3:
        // line 4: def bad(a: Int) -> Str
        // line 5:   a + 1        <- the body that produces Int
        // line 6: end
        let src = "def ok(a: Int) -> Int\n  a\nend\n\ndef bad(a: Int) -> Str\n  a + 1\nend\n";
        let o = check(src);
        assert_eq!(o.diagnostics.len(), 1, "{:?}", msgs(&o));

        let d = &o.diagnostics[0];
        assert_eq!(
            line_col(src, d.span),
            (5, 2),
            "the diagnostic must point at the body, got {:?} for {}",
            d.span,
            d.message
        );
        assert_eq!(
            text(src, d.span),
            "a + 1",
            "the span must cover exactly the body expression"
        );
    }

    /// An operator misuse points at the OFFENDING OPERAND, not the expression.
    ///
    /// RED RUN (2026-08-12): `span: a.span` in the `op_sig` arm changed to
    /// `span: s.span` — the enclosing operator expression, which is what a
    /// coarser implementation would report:
    ///
    ///   assertion `left == right` failed: the span must cover exactly the bad
    ///   operand
    ///     left: "s + 1"
    ///    right: "s"
    ///
    /// The line and column happened to still match, because `s` starts the
    /// expression — which is why the text assertion is here and not optional.
    #[test]
    fn an_operator_misuse_points_at_the_offending_operand() {
        // line 0: # a comment, so nothing lands on line 0 by accident
        // line 1: def wrong(s: Str) -> Int
        // line 2:   s + 1     <- `s` at column 2 is the Str where Int was wanted
        // line 3: end
        let src = "# a comment, so nothing lands on line 0 by accident\n\
                   def wrong(s: Str) -> Int\n\
                   \x20 s + 1\n\
                   end\n";
        let o = check(src);
        assert_eq!(o.diagnostics.len(), 1, "{:?}", msgs(&o));

        let d = &o.diagnostics[0];
        assert!(d.message.contains("expects Int"), "{}", d.message);
        assert_eq!(line_col(src, d.span), (2, 2), "span {:?}", d.span);
        assert_eq!(
            text(src, d.span),
            "s",
            "the span must cover exactly the bad operand"
        );
    }

    /// A wrong call argument points at THAT argument.
    #[test]
    fn a_wrong_argument_points_at_the_argument() {
        // line 0: def add(a: Int, b: Int) -> Int
        // line 1:   a + b
        // line 2: end
        // line 3:
        // line 4: def g() -> Int
        // line 5:   add(1, "two")   <- `"two"` starts at column 9
        // line 6: end
        let src = "def add(a: Int, b: Int) -> Int\n  a + b\nend\n\n\
                   def g() -> Int\n  add(1, \"two\")\nend\n";
        let o = check(src);
        let d = o
            .diagnostics
            .iter()
            .find(|d| d.message.contains("argument 2"))
            .unwrap_or_else(|| panic!("expected an argument-2 diagnostic: {:?}", msgs(&o)));

        assert_eq!(line_col(src, d.span), (5, 9), "span {:?}", d.span);
        assert_eq!(text(src, d.span), "\"two\"");
    }

    /// A seam records WHERE the inserted check sits, not just which argument
    /// slot it guards. "argument 1 of `add`" does not say which call.
    #[test]
    fn a_seam_carries_the_span_of_the_argument_it_guards() {
        // line 0: def add(a: Int, b: Int) -> Int
        // line 1:   a + b
        // line 2: end
        // line 3:
        // line 4: def g() -> Int
        // line 5:   add(mystery(), 2)   <- `mystery()` starts at column 6
        // line 6: end
        let src = "def add(a: Int, b: Int) -> Int\n  a + b\nend\n\n\
                   def g() -> Int\n  add(mystery(), 2)\nend\n";
        let o = check(src);
        assert!(
            o.ok(),
            "a dyn argument is a seam, not an error: {:?}",
            msgs(&o)
        );
        assert_eq!(o.seams.len(), 1, "{:?}", o.seams);

        let seam = &o.seams[0];
        assert_eq!(line_col(src, seam.span), (5, 6), "span {:?}", seam.span);
        assert_eq!(text(src, seam.span), "mystery()");
    }

    /// **No reported position is synthetic.** A synthetic span is the sentinel
    /// for "this node has no source origin", and a checker that emitted them for
    /// ordinary user code would be reporting positions no editor can use — which
    /// is the whole failure mode `Diagnostic::span` exists to close, wearing a
    /// different mask.
    ///
    /// The corpus is every diagnostic shape the checker can produce, so a new
    /// construction site that forgets its span is caught here rather than in an
    /// editor.
    ///
    /// RED RUN (2026-08-12): the corpus fed through
    /// `Spanned::from_sexp_synthetic(&parse_program(src))` instead of
    /// `parse_program_tree` — the lift a caller reaching for the spanless parse
    /// would perform:
    ///
    ///   thread 'tests::no_reported_position_is_synthetic' panicked:
    ///   `def f(a: Int) -> Str\n  a\nend` reported a synthetic span for
    ///   ``f` declares it returns Str, but its body produces Int`
    ///
    /// It trips on the first corpus entry and panics there, so the run proves
    /// the gate fires — not that every entry independently would. This is also
    /// the gate that proves the spans survive the PARSER, not merely that the
    /// field exists to be filled in.
    #[test]
    fn no_reported_position_is_synthetic() {
        let corpus = [
            "def f(a: Int) -> Str\n  a\nend",
            "def f(s: Str) -> Int\n  s + 1\nend",
            "def add(a: Int, b: Int) -> Int\n  a + b\nend\ndef g() -> Int\n  add(1, \"x\")\nend",
            "def f(a: Int) -> Int\n  a\nend\ndef g() -> Int\n  f(unknown())\nend",
            "def f(a: Int, b) -> Int\n  a\nend\ndef g() -> Int\n  f(\"bad\", 1)\nend",
        ];
        let mut diagnostics = 0;
        let mut seams = 0;
        for src in corpus {
            let o = check(src);
            for d in &o.diagnostics {
                assert!(
                    !d.span.is_synthetic(),
                    "{src:?} reported a synthetic span for `{}`",
                    d.message
                );
                assert!(
                    d.span.end <= src.len(),
                    "{src:?}: span {:?} runs past the source ({} bytes)",
                    d.span,
                    src.len()
                );
                diagnostics += 1;
            }
            for s in &o.seams {
                assert!(
                    !s.span.is_synthetic(),
                    "{src:?} seam at {} is synthetic",
                    s.at
                );
                seams += 1;
            }
        }
        // Anti-vacuity: the loop above proves nothing if the corpus reported
        // nothing. Counted, not asserted non-empty, so a corpus that silently
        // stopped producing three of four findings still fails. The count is 4
        // and not 5 because the fourth entry's `unknown()` argument is a SEAM
        // rather than an error — the count caught that when it was first written
        // as 5, which is the kind of mistake `assert!(!is_empty())` hides.
        assert_eq!(diagnostics, 4, "the corpus stopped reporting diagnostics");
        assert_eq!(seams, 1, "the corpus stopped reporting seams");
    }

    /// **Every diagnostic leaves here knowing which top-level form it came
    /// from.** In a program assembled from several files that index is the only
    /// key to file identity, so one that escapes unstamped is a diagnostic whose
    /// position cannot be resolved at all.
    ///
    /// The corpus deliberately puts the error in the SECOND declaration as well
    /// as the first: a stamp that happened to be right only for index 0 is the
    /// mistake this catches, and `UNSTAMPED` alone would not — `0` would look
    /// correct half the time.
    ///
    /// **Red run** (2026-08-12), stamping loop deleted from `check_program`:
    /// ```text
    /// assertion `left != right` failed: diagnostic ``+` expects Int, got Str`
    /// escaped check_program unstamped
    /// ```
    /// It fires on the operator diagnostic, which is the one `infer` pushes —
    /// the return-mismatch arm builds its own `top_level` and would pass a
    /// vacuous version of this gate on its own.
    #[test]
    fn no_diagnostic_escapes_unstamped() {
        // Both arms that push a diagnostic, each at index 0 and at index 1: the
        // operator misuse comes out of `infer` and is stamped by the loop, the
        // return mismatch is built by the loop itself.
        let corpus = [
            ("def f(s: Str) -> Int\n  s + 1\nend", 0usize),
            (
                "def ok(a: Int) -> Int\n  a\nend\ndef f(s: Str) -> Int\n  s + 1\nend",
                1usize,
            ),
            ("def g(a: Int) -> Str\n  a\nend", 0usize),
            (
                "def ok(a: Int) -> Int\n  a\nend\ndef g(a: Int) -> Str\n  a\nend",
                1usize,
            ),
        ];
        let mut seen = 0;
        for (src, want) in corpus {
            let o = check(src);
            for d in &o.diagnostics {
                assert_ne!(
                    d.top_level,
                    Diagnostic::UNSTAMPED,
                    "diagnostic `{}` escaped check_program unstamped",
                    d.message
                );
                assert_eq!(
                    d.top_level, want,
                    "{src:?}: `{}` was stamped with top-level form {} — the \
                     declaration it came from is {want}",
                    d.message, d.top_level
                );
                seen += 1;
            }
        }
        // Anti-vacuity: an empty corpus passes the loop above trivially. One
        // finding per entry — written as 8 first, on the assumption each entry
        // reported both arms, and the count said 2. A `+` on a `Str` yields the
        // operator's declared `Int` return, so the body still satisfies `-> Int`
        // and the second arm never fires. Four entries were added to cover what
        // the first two were assumed to.
        assert_eq!(seen, 4, "the corpus stopped reporting diagnostics");
    }

    /// Correctness never moves: a program that runs must still run whether
    /// or not it is annotated. Same tree, both spellings.
    #[test]
    fn annotation_does_not_change_the_body() {
        use blue_lang_syntax::parse_program;
        let untyped = parse_program("def add(a, b)\n  a + b\nend").expect("parse");
        let typed = parse_program("def add(a: Int, b: Int) -> Int\n  a + b\nend").expect("parse");
        let body_of = |f: &Sexp| match f {
            Sexp::List(items) => items.last().cloned(),
            _ => None,
        };
        assert_eq!(
            body_of(&untyped[0]),
            body_of(&typed[0]),
            "annotating changed the body"
        );
    }

    fn codes(o: &Outcome) -> Vec<Code> {
        o.diagnostics.iter().map(|d| d.code).collect()
    }

    #[test]
    fn a_map_signature_checks_its_values() {
        let head = "def total(m: Map(Sym, Int)) -> Int\n  get(m, :a)\nend\n";
        let bad = check(&format!(
            "{head}def g(a: Int) -> Int\n  total({{a: \"x\"}}) + a\nend"
        ));
        assert_eq!(codes(&bad), [Code::B0005], "{:?}", msgs(&bad));
        assert!(
            msgs(&bad)[0].contains("expects Map(Sym, Int), got Map(Sym, Str)"),
            "{:?}",
            msgs(&bad)
        );
        let good = check(&format!(
            "{head}def g(a: Int) -> Int\n  total({{a: 1}}) + a\nend"
        ));
        assert!(good.diagnostics.is_empty(), "{:?}", msgs(&good));
    }

    #[test]
    fn a_list_and_a_map_literal_have_their_types() {
        assert_eq!(
            codes(&check("def f(a: Int) -> Int\n  [a]\nend")),
            [Code::B0003]
        );
        assert_eq!(
            codes(&check("def f(a: Int) -> Str\n  {a: a}\nend")),
            [Code::B0003]
        );
        assert!(check("def f(a: Int) -> List(Int)\n  [a, 2]\nend")
            .diagnostics
            .is_empty());
        assert!(check("def f(a: Int) -> Map\n  {a: a}\nend")
            .diagnostics
            .is_empty());
    }

    #[test]
    fn a_record_parameter_types_its_fields() {
        let rec = "record point(x, y: Int)\n";
        let o = check(&format!("{rec}def label(p: point) -> Str\n  p.y\nend"));
        assert_eq!(codes(&o), [Code::B0003], "{:?}", msgs(&o));
        let o = check(&format!("{rec}def depth(p: point) -> Int\n  p.z\nend"));
        assert_eq!(codes(&o), [Code::B0079], "{:?}", msgs(&o));
        assert!(
            msgs(&o)[0].contains("`point` has no field `z`"),
            "{:?}",
            msgs(&o)
        );
        let o = check(&format!(
            "{rec}def height(p: point) -> Int\n  p.y\nend\ndef g(a: Int) -> Int\n  height({{x: a, y: a}})\nend"
        ));
        assert_eq!(codes(&o), [Code::B0005], "{:?}", msgs(&o));
        let o = check(&format!(
            "{rec}def origin(a: Int) -> point\n  point(a, a)\nend\ndef height(p: point) -> Int\n  p.y\nend\ndef g(a: Int) -> Int\n  height(origin(a))\nend"
        ));
        assert!(o.diagnostics.is_empty(), "{:?}", msgs(&o));
    }

    #[test]
    fn a_union_parameter_takes_its_arms_and_nothing_else() {
        let decl = "union shape = circle(r: Int) | rect(w: Int, h: Int)\nrecord point(x, y)\ndef area(s: shape) -> Int\n  1\nend\n";
        let o = check(&format!(
            "{decl}def g(a: Int) -> Int\n  area(circle(a)) + area(rect(a, a))\nend"
        ));
        assert!(o.diagnostics.is_empty(), "{:?}", msgs(&o));
        let o = check(&format!(
            "{decl}def g(a: Int) -> Int\n  area(point(a, a))\nend"
        ));
        assert_eq!(codes(&o), [Code::B0005], "{:?}", msgs(&o));
        assert!(
            msgs(&o)[0].contains("expects shape, got point"),
            "{:?}",
            msgs(&o)
        );
    }

    #[test]
    fn an_untyped_caller_is_checked_where_the_value_is_known() {
        let typed = "def inc(n: Int) -> Int\n  n + 1\nend\n";
        let o = check(&format!("{typed}inc(\"a\")"));
        assert_eq!(codes(&o), [Code::B0005], "{:?}", msgs(&o));
        assert_eq!(o.diagnostics[0].top_level, 1);
        let o = check(&format!(
            "{typed}def loose(xs)\n  label = \"n\"\n  [inc(label), xs]\nend"
        ));
        assert_eq!(codes(&o), [Code::B0005], "{:?}", msgs(&o));
        let o = check(&format!("{typed}def loose(x)\n  inc(x)\nend\ninc(1)"));
        assert!(o.diagnostics.is_empty(), "{:?}", msgs(&o));
        assert!(o.seams.is_empty(), "{:?}", o.seams);
    }

    #[test]
    fn the_boundary_leaves_a_local_name_and_untyped_misuse_alone() {
        let typed = "def inc(n: Int) -> Int\n  n + 1\nend\n";
        let o = check(&format!("{typed}def loose(inc)\n  inc(\"a\")\nend"));
        assert!(o.diagnostics.is_empty(), "{:?}", msgs(&o));
        let o = check(&format!("{typed}def loose(x)\n  \"a\" + x\nend"));
        assert!(o.diagnostics.is_empty(), "{:?}", msgs(&o));
        let o = check(&format!("{typed}def inc(s)\n  s\nend\ninc(\"a\")"));
        assert!(o.diagnostics.is_empty(), "{:?}", msgs(&o));
        let o = check("def shout(w: String) -> String\n  w\nend\nshout(\"a\")");
        assert!(o.diagnostics.is_empty(), "{:?}", msgs(&o));
    }

    #[test]
    fn the_boundary_costs_nothing_without_a_typed_definition() {
        let o = check("def add(a, b)\n  a + b\nend\nadd(1, \"nope\")");
        assert_eq!((o.stats.visited, o.stats.boundary_visited), (0, 0));
        let o = check("def inc(n: Int) -> Int\n  n + 1\nend\ninc(\"a\")");
        assert!(o.stats.boundary_visited > 0);
    }

    #[test]
    fn a_qualified_call_is_checked_against_its_package() {
        let src = "def scale(n: Int) -> Int\n  n\nend\nkit::scale(\"x\")\nscale(\"x\")";
        let forms = parse_program_tree(src).unwrap();
        let o = check_program_with(&forms, &|a, b| (a == 0) == (b == 0), &|i| {
            (i == 0).then(|| "kit".to_string())
        });
        assert_eq!(codes(&o), [Code::B0005, Code::B0005], "{:?}", msgs(&o));
        let o = check_program_with(&forms, &|a, b| (a == 0) == (b == 0), &|i| {
            (i == 0).then(|| "other".to_string())
        });
        assert_eq!(codes(&o), [Code::B0005], "{:?}", msgs(&o));
        assert_eq!(o.diagnostics[0].top_level, 2);
    }

    #[test]
    fn a_strict_file_types_every_function() {
        let o = check("blueshift(:strict)\ndef twice(n)\n  n * 2\nend\ndef one()\n  1\nend");
        assert_eq!(codes(&o), [Code::B0082, Code::B0082], "{:?}", msgs(&o));
        assert!(msgs(&o)[0].contains("`twice` is untyped"), "{:?}", msgs(&o));
        let o = check(
            "blueshift(:strict)\ndef scale(n: Int, k)\n  n * k\nend\ndef show(x) -> dyn\n  x\nend\nlimit = 3",
        );
        assert!(o.diagnostics.is_empty(), "{:?}", msgs(&o));
        let o = check("blueshift(:loose)\ndef twice(n)\n  n * 2\nend");
        assert!(o.diagnostics.is_empty(), "{:?}", msgs(&o));
        let o = check("def twice(n)\n  n * 2\nend");
        assert!(o.diagnostics.is_empty(), "{:?}", msgs(&o));
    }

    #[test]
    fn a_strict_position_binds_only_its_own_file() {
        let src = "blueshift(:strict)\ndef scale(n: Int) -> Int\n  n\nend\ndef loose(x)\n  x\nend";
        let forms = parse_program_tree(src).unwrap();
        let o = check_program_in(&forms, &|a, b| (a < 2) == (b < 2));
        assert!(o.diagnostics.is_empty(), "{:?}", msgs(&o));
        let o = check_program_in(&forms, &|_, _| true);
        assert_eq!(codes(&o), [Code::B0082], "{:?}", msgs(&o));
        assert_eq!(o.diagnostics[0].top_level, 2);
    }
}
