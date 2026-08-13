//! `use("name")` — how a blue program consumes a bidama.
//!
//! ## The gap this closes
//!
//! Before this, blue's packaging had a manifest (`Bluefile`), a resolver
//! (`blue-lang-pkg`), a git registry and a nix derivation per package — and
//! **no way for a program to consume any of it**. `retsu/Bluefile` declared
//! `needs("kazu", "^0.1")` while `retsu`'s source never referenced a single
//! thing from kazu, because the language had no import form at all. The
//! dependency graph was described by four layers and traversed by none.
//!
//! That is the difference between packaging that exists and packaging that
//! works, and it is why this is a load-bearing addition rather than a
//! convenience: a distribution whose packages cannot see each other is a
//! directory of unrelated files wearing a distribution's name.
//!
//! ## Why a pipeline pass and not a builtin
//!
//! A `register_fn` native takes `(&[Value], &mut H, Span)`. It cannot define
//! anything, because it never sees the interpreter — so `use` implemented as a
//! builtin could load a package's text and would have nowhere to put its
//! definitions. Resolution therefore happens on the FORM tree, before
//! evaluation: a `use` is replaced by the forms of the package it names, and
//! the whole program is then checked and run as one unit.
//!
//! That ordering is deliberate and worth stating, because it decides a real
//! behaviour: the type checker sees the imported code, so a package that fails
//! `blue-lang-check` fails at the point its consumer imports it rather than at
//! whatever later moment its code first ran.
//!
//! ## Why the loader is a trait
//!
//! Loading a package means reading a filesystem, and this crate compiles to
//! `wasm32-unknown-unknown` with zero host imports (`blue-lang-wasm`). A
//! direct `std::fs` call here would break that target for every consumer,
//! including ones that never call `use`.
//!
//! So the capability is injected — [`Loader`] here, the real filesystem
//! implementation in `blue-lang-pkg`, which is native-only. This is the
//! fleet's mockable-`Environment` seam, and it buys the usual thing: every
//! test below drives the whole resolution pass against an in-memory loader,
//! with no temp directories and no fixture files on disk.
//!
//! ## Why this module also owns file identity
//!
//! Splicing several files into one program is exactly the act that destroys a
//! byte offset's meaning, so the record of where each form came from is kept by
//! the pass that does the splicing rather than reconstructed downstream by
//! something that no longer has the sources. [`ResolvedProgram`] is that
//! record, and [`ResolvedProgram::locate`] spends it.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use tatara_lisp::{Atom, Sexp, Span, Spanned, SpannedForm};

/// Supplies the source of a named bidama.
///
/// One method, because resolution needs exactly one thing: given a name, the
/// blue source that name refers to. *Where* it came from — a working tree, a
/// nix store path, a git object, memory — is the implementation's business and
/// deliberately invisible here.
pub trait Loader {
    /// The `.b` sources of `name`, as `(label, source)` pairs.
    ///
    /// The label is for diagnostics only; nothing keys on it. A package with
    /// several files returns several pairs, and their relative order is the
    /// implementation's to fix — [`FsLoader`](../../blue_lang_pkg/load_path/index.html)
    /// sorts by filename so a load is reproducible rather than
    /// directory-order-dependent.
    ///
    /// `Err` is a human-readable reason the package could not be loaded. It
    /// must name what was looked for, because "package not found" without a
    /// name sends the reader grepping a distribution to find which one.
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String>;
}

/// A loader that resolves nothing, and says so.
///
/// The default for [`run`](crate::pipeline::run), so a program using `use` in
/// a context with no packaging configured gets a typed error naming the
/// package — not a silently-undefined function that fails much later as an
/// unbound symbol pointing at innocent code.
pub struct NoLoader;

impl Loader for NoLoader {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        Err(format!(
            "cannot load bidama \"{name}\": no loader is installed. A program \
             that uses packages must run with one — `blue_lang_pkg::LoadPath` \
             reads BLUE_PATH, which `nix develop` and the bidama derivations \
             populate."
        ))
    }
}

/// Identity of one source file inside a [`ResolvedProgram`].
///
/// Opaque on purpose. It means nothing outside the program that minted it, and
/// the only way to spend it is [`ResolvedProgram::file`] — a caller that could
/// compute a file index is a caller that can compute the *wrong* one, which is
/// the failure this whole type exists to make impossible.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct FileId(usize);

/// One file that contributed forms to a [`ResolvedProgram`].
#[derive(Clone, Debug)]
pub struct SourceFile {
    /// Its handle in the program that owns it.
    pub id: FileId,
    /// Where it came from.
    ///
    /// `None` only for an entry program handed to the pipeline as bare text —
    /// an embedder, a test, a WASM host. An imported file always has one,
    /// because a [`Loader`] cannot name a package without naming a place.
    pub path: Option<PathBuf>,
    /// The file's text.
    ///
    /// Kept, not dropped after parsing, because a [`Span`] is a byte range and
    /// nothing else: turning one into `line:col` needs the exact string it
    /// indexes. Before this, `resolve_uses` read a package's source and let it
    /// fall out of scope one line later, which is why an imported type error
    /// had no position to report.
    pub text: String,
}

/// The program the pipeline was handed, and what to call it.
///
/// The path travels *with* the text rather than beside it, so a caller cannot
/// name one file and hand over another's source — the pairing is what every
/// position in the entry file is resolved against.
#[derive(Clone, Copy, Debug)]
pub struct Entry<'a> {
    /// The file the text was read from, if it was read from one.
    pub path: Option<&'a Path>,
    /// The source itself.
    pub text: &'a str,
}

impl<'a> Entry<'a> {
    /// An entry program with no file behind it.
    #[must_use]
    pub fn anonymous(text: &'a str) -> Self {
        Self { path: None, text }
    }
}

/// A program with its imports spliced in, and the file each top-level form
/// came from.
///
/// ## Why file identity is per TOP-LEVEL FORM
///
/// [`resolve_uses`] splices whole files' worth of top-level forms: a `use` is
/// replaced by every form of the package it names, in order. So a boundary
/// between two files is always a boundary between two top-level forms, and
/// every node beneath a top-level form came from exactly one file — the one
/// that form came from. **A `FileId` per top-level form is therefore exactly as
/// precise as a `FileId` per node**, at a fraction of the cost and with nothing
/// upstream to change.
///
/// That last part is the point. `Span` lives in tatara-lisp and carries no file
/// identity by a documented decision — "Spans are not portable across source
/// inputs — they are meaningful only relative to the string that produced them,
/// which the caller is responsible for holding onto." blue is the caller. This
/// is blue holding onto them, beside the span rather than inside it.
///
/// ## Why the fields are private
///
/// `forms` and `owner` are parallel, and `files[i].id` is `FileId(i)`. Both
/// invariants are maintained by `push` and `intern`, the only places either
/// vector grows, and by [`retain`](Self::retain), the only place either
/// shrinks. Public fields would make `program.forms.retain(...)` — the exact
/// call `pipeline::run_in_surface` makes to drop `test` blocks — shift every
/// form off its owner by one and report every subsequent diagnostic against the
/// wrong file, silently.
#[derive(Debug)]
pub struct ResolvedProgram {
    forms: Vec<Spanned>,
    owner: Vec<FileId>,
    files: Vec<SourceFile>,
}

impl ResolvedProgram {
    /// The entry program's own file. Always present; always first.
    pub const ENTRY: FileId = FileId(0);

    fn new(entry: Entry<'_>) -> Self {
        let mut program = Self {
            forms: Vec::new(),
            owner: Vec::new(),
            files: Vec::new(),
        };
        let id = program.intern(entry.path.map(Path::to_path_buf), entry.text.to_owned());
        debug_assert_eq!(id, Self::ENTRY);
        program
    }

    /// Record a file's text and hand back its handle.
    fn intern(&mut self, path: Option<PathBuf>, text: String) -> FileId {
        let id = FileId(self.files.len());
        self.files.push(SourceFile { id, path, text });
        id
    }

    /// Append a top-level form together with the file it came from.
    ///
    /// The ONE place `forms` and `owner` grow, so they cannot grow apart.
    fn push(&mut self, form: Spanned, owner: FileId) {
        self.forms.push(form);
        self.owner.push(owner);
    }

    /// Every top-level form, in evaluation order.
    #[must_use]
    pub fn forms(&self) -> &[Spanned] {
        &self.forms
    }

    /// The same forms with their spans projected away, for the stages that do
    /// not report positions — erasure, evaluation, the test harness.
    #[must_use]
    pub fn sexps(&self) -> Vec<Sexp> {
        self.forms.iter().map(Spanned::to_sexp).collect()
    }

    /// Every file that contributed, entry first.
    #[must_use]
    pub fn files(&self) -> &[SourceFile] {
        &self.files
    }

    /// Which file the `top_level`-th form came from.
    #[must_use]
    pub fn owner_of(&self, top_level: usize) -> Option<FileId> {
        self.owner.get(top_level).copied()
    }

    /// A file by its handle.
    #[must_use]
    pub fn file(&self, id: FileId) -> Option<&SourceFile> {
        self.files.get(id.0)
    }

    /// Drop the top-level forms `keep` rejects, taking their owners with them.
    ///
    /// The lockstep is the whole reason this method exists rather than a public
    /// `forms` field: `Vec::retain` on one of two parallel vectors is a silent
    /// mis-attribution, not a compile error.
    pub fn retain(&mut self, keep: impl Fn(&Spanned) -> bool) {
        // Zipped rather than two `Vec::retain` calls over the same predicate:
        // this way the pairing is carried by the iterator instead of by two
        // traversals agreeing, and there is no order assumption to be wrong
        // about.
        let paired = std::mem::take(&mut self.forms)
            .into_iter()
            .zip(std::mem::take(&mut self.owner));
        for (form, owner) in paired {
            if keep(&form) {
                self.push(form, owner);
            }
        }
    }

    /// Resolve a diagnostic's position against the file it actually came from.
    ///
    /// `top_level` is `blue_lang_check::Diagnostic::top_level` — the join key.
    /// An index with no owner (a diagnostic that escaped stamping) renders
    /// without a position rather than borrowing the entry file's: a missing
    /// position costs the reader a search, a wrong one sends them to innocent
    /// code and is believed.
    #[must_use]
    pub fn locate<'a>(&'a self, top_level: usize, span: Span, message: &'a str) -> Located<'a> {
        let Some(file) = self.owner_of(top_level).and_then(|id| self.file(id)) else {
            return Located {
                origin: Origin::Unresolved,
                line_col: None,
                message,
            };
        };
        Located {
            origin: file.path.as_deref().map_or(Origin::Anonymous, Origin::File),
            // A synthetic span indexes nothing, so it resolves to no line —
            // `Span::line_col` would happily answer for `usize::MAX` by walking
            // off the end and returning the last position in the file.
            //
            // **And so would a span that is real but belongs to a DIFFERENT
            // file**, which is the case a runtime error can reach and a check
            // error cannot: a check diagnostic's span is a node inside the very
            // top-level form it is stamped with, so it is in range by
            // construction, while a raise inside a callee carries the callee's
            // offsets and the executing top-level form may be someone else's.
            // An out-of-range offset is proof the span is not this file's, and
            // `line_col` answers it anyway with the file's last position — a
            // fabricated `path:line:col` a reader has every reason to believe.
            // Refuse instead, which is `EvalError::render`'s own rule
            // (`span.end > src.len()` → no source context) applied at the one
            // place blue owns the file table.
            //
            // In range is NECESSARY, not sufficient: two files long enough to
            // share an offset can still trade a plausible number. That residue
            // is `RunError::Eval`'s stated limit and wants a call stack, not a
            // wider guard here.
            line_col: (!span.is_synthetic() && span.end <= file.text.len())
                .then(|| Span::line_col(&file.text, span.start)),
            message,
        }
    }
}

/// What a position is being reported against.
#[derive(Clone, Copy, Debug)]
enum Origin<'a> {
    File(&'a Path),
    /// Source handed over as text, with no file behind it.
    Anonymous,
    /// No owning file could be found. Distinct from [`Origin::Anonymous`] on
    /// purpose: "you gave me unnamed text" and "I lost track of where this came
    /// from" are different admissions, and collapsing them would hide the
    /// second inside the first.
    Unresolved,
}

/// A diagnostic rendered against the file it came from: `path:line:col: text`.
///
/// A typed `Display` rather than a `format!` at the call site, per ★★ TYPED
/// EMISSION — the shape every editor and every `cc` already knows how to jump
/// to, produced by exactly one `write!`.
#[derive(Clone, Copy, Debug)]
pub struct Located<'a> {
    origin: Origin<'a>,
    line_col: Option<(usize, usize)>,
    message: &'a str,
}

impl std::fmt::Display for Located<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self.origin {
            Origin::File(p) => write!(f, "{}", p.display())?,
            Origin::Anonymous => f.write_str("<anonymous>")?,
            Origin::Unresolved => f.write_str("<unknown file>")?,
        }
        if let Some((line, col)) = self.line_col {
            write!(f, ":{line}:{col}")?;
        }
        write!(f, ": {}", self.message)
    }
}

/// Is this form a `use("name")` call? If so, the name.
///
/// Matches the *call* form only. `use "kazu"` without parentheses parses as
/// two unrelated top-level atoms (blue has no paren-less call syntax), which
/// would silently do nothing — so it is not treated as an import, and the
/// bare symbol `use` then fails as an unbound name rather than being quietly
/// ignored.
fn use_target(form: &Spanned) -> Option<String> {
    let [head, arg] = form.as_list()? else {
        return None;
    };
    match (&head.form, &arg.form) {
        (SpannedForm::Atom(Atom::Symbol(s)), SpannedForm::Atom(Atom::Str(name))) if s == "use" => {
            Some(name.clone())
        }
        _ => None,
    }
}

/// Is this form a lowered `test` block?
///
/// `test "…" … end` lowers to `(deftest …)`, which only the test harness
/// binds. Public because two callers need it and for opposite reasons: the
/// resolver drops IMPORTED tests (a dependency's tests are not the importer's
/// to run), and `pipeline::run` drops ALL of them (a `test` block is a
/// declaration for the harness, not code to execute — without this,
/// `blue run` on any file that contains its own tests dies on an unbound
/// `deftest`, which is every package in this distribution).
pub fn is_test_form(form: &Spanned) -> bool {
    let Some(items) = form.as_list() else {
        return false;
    };
    matches!(items.first().and_then(Spanned::as_symbol), Some("deftest"))
}

/// Replace every `use(...)` with the forms of the package it names.
///
/// Transitive by construction: a loaded package's own `use` calls are resolved
/// the same way, depth-first, so a consumer names its direct dependency and
/// gets the closure.
///
/// **A package is loaded at most once.** Two importers of one package must
/// share its definitions — loading twice would re-evaluate them, which is at
/// best wasted work and at worst two distinct copies of anything stateful.
/// That same visited-set is what makes a dependency CYCLE terminate: the
/// second visit is a no-op rather than infinite recursion, so a cyclic
/// distribution loads and runs instead of hanging.
///
/// The result carries **which file each top-level form came from** — see
/// [`ResolvedProgram`] for why that is per top-level form and not per node.
///
/// # Errors
///
/// Returns the loader's message, prefixed with the import chain that reached
/// it, when a package cannot be loaded or its source cannot be parsed.
pub fn resolve_uses(
    forms: Vec<Spanned>,
    entry: Entry<'_>,
    loader: &dyn Loader,
) -> Result<ResolvedProgram, String> {
    let mut out = ResolvedProgram::new(entry);
    let mut seen = BTreeSet::new();
    expand(
        forms,
        ResolvedProgram::ENTRY,
        loader,
        &mut out,
        &mut seen,
        &[],
    )?;
    Ok(out)
}

fn expand(
    forms: Vec<Spanned>,
    owner: FileId,
    loader: &dyn Loader,
    out: &mut ResolvedProgram,
    seen: &mut BTreeSet<String>,
    chain: &[String],
) -> Result<(), String> {
    for form in forms {
        let Some(name) = use_target(&form) else {
            // The file boundary is erased HERE — this is the append that used
            // to make every form indistinguishable from every other. Each one
            // now carries the file it came from, which is the whole fix.
            out.push(form, owner);
            continue;
        };
        if !seen.insert(name.clone()) {
            continue;
        }

        let sources = loader.load(&name).map_err(|e| describe(chain, &name, &e))?;
        let mut inner_chain = chain.to_vec();
        inner_chain.push(name.clone());

        for (label, src) in sources {
            // `parse_program_tree`, not `parse_program`. The spanless door
            // discarded every imported position one line after the text
            // arrived, so an imported type error had nothing to report but a
            // message — see `ResolvedProgram`.
            let parsed = blue_lang_syntax::parse_program_tree(&src)
                .map_err(|e| describe(chain, &name, &format!("{label}: {e}")))?;
            // An imported package's TEST blocks do not come along.
            //
            // A dependency's tests are not the importer's to run, and trying
            // is not merely untidy — it is a hard failure. `test` lowers to
            // `deftest`, which only the test harness binds, so the ordinary
            // evaluator sees an unbound symbol. Measured, the moment kazu
            // gained test blocks: every program importing it died with
            // `unbound symbol: deftest`, pointing at a line the importer never
            // wrote.
            //
            // Dropping them here also makes the distribution gate honest for
            // free: `blue test kikagaku.b` now reports kikagaku's tests
            // rather than kikagaku's plus everything it transitively imports.
            let parsed: Vec<Spanned> = parsed.into_iter().filter(|f| !is_test_form(f)).collect();
            // Interned AFTER parsing, so a package that does not parse never
            // becomes a file in the table — and BEFORE the recursion, because
            // every form below belongs to this file, not to the importer's.
            let id = out.intern(Some(PathBuf::from(label)), src);
            expand(parsed, id, loader, out, seen, &inner_chain)?;
        }
    }
    Ok(())
}

/// Prefix a failure with the import chain that reached it.
///
/// A transitive failure otherwise names only the leaf, and the reader has no
/// way to tell which of their own imports pulled it in — the exact question
/// they need answered to fix it.
fn describe(chain: &[String], name: &str, reason: &str) -> String {
    if chain.is_empty() {
        return reason.to_owned();
    }
    format!("while loading {} -> {name}: {reason}", chain.join(" -> "))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    /// An in-memory distribution — the whole pass runs with no filesystem.
    struct MemLoader(BTreeMap<&'static str, &'static str>);

    impl Loader for MemLoader {
        fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
            self.0
                .get(name)
                .map(|s| vec![(format!("{name}.b"), (*s).to_owned())])
                .ok_or_else(|| format!("no bidama named \"{name}\""))
        }
    }

    fn parse(src: &str) -> Vec<Spanned> {
        blue_lang_syntax::parse_program_tree(src).expect("test source must parse")
    }

    /// Resolve a program that came from nowhere in particular.
    fn resolve(src: &str, loader: &dyn Loader) -> Result<ResolvedProgram, String> {
        resolve_uses(parse(src), Entry::anonymous(src), loader)
    }

    #[test]
    fn a_use_is_replaced_by_the_packages_forms() {
        let loader = MemLoader(BTreeMap::from([("kazu", "def double(n)\n  n * 2\nend")]));
        let out = resolve("use(\"kazu\")\ndouble(21)", &loader).expect("resolves");
        // The `use` itself is GONE — it is not a call that survives to the
        // evaluator, where `use` is not a defined function.
        assert!(
            out.forms().iter().all(|f| super::use_target(f).is_none()),
            "a use form survived resolution and would reach the evaluator as \
             an unbound function: {:?}",
            out.forms()
        );
        assert!(
            out.forms().len() > 1,
            "the package's definitions must be spliced in, not dropped: {:?}",
            out.forms()
        );
    }

    #[test]
    fn imports_are_transitive() {
        let loader = MemLoader(BTreeMap::from([
            ("retsu", "use(\"kazu\")\ndef sum2(a, b)\n  a + b\nend"),
            ("kazu", "def double(n)\n  n * 2\nend"),
        ]));
        let out = resolve("use(\"retsu\")", &loader).expect("resolves");
        // A consumer names retsu only; kazu arrives because retsu needs it.
        assert!(
            out.forms().len() >= 2,
            "the transitive dependency did not arrive: {:?}",
            out.forms()
        );
    }

    #[test]
    fn a_package_is_loaded_at_most_once() {
        let loader = MemLoader(BTreeMap::from([("kazu", "def double(n)\n  n * 2\nend")]));
        let once = resolve("use(\"kazu\")", &loader).expect("resolves");
        let twice = resolve("use(\"kazu\")\nuse(\"kazu\")", &loader).expect("resolves");
        assert_eq!(
            once.forms().len(),
            twice.forms().len(),
            "importing a package twice duplicated its definitions; two \
             importers of one package must share it"
        );
        assert_eq!(
            once.files().len(),
            twice.files().len(),
            "importing a package twice interned its source twice; the file \
             table must have one entry per file, not one per import"
        );
    }

    /// The property that keeps a cyclic distribution from hanging.
    #[test]
    fn a_dependency_cycle_terminates() {
        let loader = MemLoader(BTreeMap::from([
            ("a", "use(\"b\")\ndef fa()\n  1\nend"),
            ("b", "use(\"a\")\ndef fb()\n  2\nend"),
        ]));
        let out = resolve("use(\"a\")", &loader).expect("a cycle must resolve");
        assert!(
            !out.forms().is_empty(),
            "a cycle resolved to nothing: {:?}",
            out.forms()
        );
    }

    #[test]
    fn a_missing_package_names_itself_and_the_chain() {
        let loader = MemLoader(BTreeMap::from([("retsu", "use(\"nowhere\")")]));
        let err = resolve("use(\"retsu\")", &loader).expect_err("must fail");
        assert!(
            err.contains("nowhere"),
            "the error must name the missing package: {err}"
        );
        assert!(
            err.contains("retsu"),
            "the error must name the import that pulled it in, or the reader \
             cannot tell which of their own imports is at fault: {err}"
        );
    }

    #[test]
    fn the_default_loader_refuses_by_name() {
        let err = resolve("use(\"kazu\")", &NoLoader).expect_err("must fail");
        assert!(
            err.contains("kazu"),
            "NoLoader must name what was asked for: {err}"
        );
    }

    /// A non-`use` program must come out byte-identical.
    ///
    /// This pass runs on EVERY program, so a bug here would corrupt source
    /// that never mentions a package.
    /// An imported package's tests must NOT come along.
    ///
    /// Not a tidiness point: `deftest` is unbound outside the test harness, so
    /// an inherited test block kills any program that imports a tested
    /// package — which is every package in a distribution worth having.
    #[test]
    fn an_imported_packages_tests_are_not_inherited() {
        let loader = MemLoader(BTreeMap::from([(
            "kazu",
            "def double(n)\n  n * 2\nend\n\ntest \"doubles\"\n  assert double(2) == 4\nend",
        )]));
        let out = resolve("use(\"kazu\")\ndouble(21)", &loader).expect("resolves");
        assert!(
            out.forms().iter().all(|f| !super::is_test_form(f)),
            "an imported test block survived and would reach the evaluator as \
             an unbound `deftest`: {:?}",
            out.forms()
        );
        // The DEFINITIONS still arrive — dropping tests must not drop code.
        assert!(
            out.forms().len() >= 2,
            "filtering tests also removed the package's definitions: {:?}",
            out.forms()
        );
    }

    /// But the ENTRY program keeps its own tests.
    #[test]
    fn the_entry_programs_own_tests_survive() {
        let loader = MemLoader(BTreeMap::new());
        let src = "def f(n)\n  n\nend\n\ntest \"t\"\n  assert f(1) == 1\nend";
        let out = resolve(src, &loader).expect("resolves");
        assert!(
            out.forms().iter().any(super::is_test_form),
            "the file's OWN tests were dropped; only imported ones should be: {:?}",
            out.forms()
        );
    }

    #[test]
    fn a_program_without_imports_is_unchanged() {
        let loader = MemLoader(BTreeMap::new());
        let src = "def f(n)\n  n + 1\nend\nf(1)";
        let before: Vec<Sexp> = parse(src).iter().map(Spanned::to_sexp).collect();
        let out = resolve(src, &loader).expect("resolves");
        assert_eq!(format!("{before:?}"), format!("{:?}", out.sexps()));
    }

    // ---- file identity ---------------------------------------------------

    /// **Every form's span indexes ITS OWN file, and the text proves it.**
    ///
    /// The independent evidence is the source itself: slice each top-level
    /// form's span out of the file its owner names and re-parse the slice. If
    /// the owner is wrong the bytes are some other file's, and the re-parsed
    /// tree does not match — checked against the tree, which the file table had
    /// no hand in producing.
    ///
    /// This is the contract `Span`'s own docs put on the caller — spans "are
    /// meaningful only relative to the string that produced them" — asserted
    /// rather than assumed.
    ///
    /// **Red run** (2026-08-12), `expand` pushing `ResolvedProgram::ENTRY` as
    /// every form's owner instead of `owner`:
    /// ```text
    /// form 0: its own source does not re-parse: expected an expression, found
    /// Eof at 25..25
    /// ```
    /// It trips at the re-parse rather than the comparison, because kazu's
    /// byte range cut against the entry file's text lands mid-token — which is
    /// the mis-attribution stated in bytes.
    ///
    /// **Second red run**, the ORIGINAL spanless `parse_program` restored in
    /// `expand` (the bug this change fixes):
    /// ```text
    /// form 0 has no position at all — its file was parsed through the
    /// spanless door
    /// ```
    #[test]
    fn every_forms_span_indexes_the_file_it_came_from() {
        let loader = MemLoader(BTreeMap::from([
            ("retsu", "use(\"kazu\")\ndef sum2(a, b)\n  a + b\nend"),
            ("kazu", "def double(n)\n  n * 2\nend"),
        ]));
        let out = resolve("use(\"retsu\")\nsum2(double(1), 2)", &loader).expect("resolves");
        assert_eq!(
            out.files().len(),
            3,
            "expected the entry plus retsu plus kazu: {:?}",
            out.files()
        );
        for (i, form) in out.forms().iter().enumerate() {
            let file = out
                .owner_of(i)
                .and_then(|id| out.file(id))
                .unwrap_or_else(|| panic!("form {i} has no owning file"));
            assert!(
                !form.span.is_synthetic(),
                "form {i} has no position at all — its file was parsed through \
                 the spanless door"
            );
            let slice = file
                .text
                .get(form.span.start..form.span.end)
                .unwrap_or_else(|| {
                    panic!(
                        "form {i}'s span {:?} is not a range in its owner ({} bytes)",
                        form.span,
                        file.text.len()
                    )
                });
            let reparsed = blue_lang_syntax::parse_program_tree(slice)
                .unwrap_or_else(|e| panic!("form {i}: its own source does not re-parse: {e}"));
            assert_eq!(
                reparsed.iter().map(Spanned::to_sexp).collect::<Vec<_>>(),
                vec![form.to_sexp()],
                "form {i} sliced out of its owner ({}) re-parses to a different \
                 tree; slice was {slice:?}",
                file.path
                    .as_deref()
                    .map_or_else(|| "<anonymous>".to_string(), |p| p.display().to_string())
            );
        }
        // Anti-vacuity: an empty program passes the loop above.
        assert!(out.forms().len() >= 3, "{:?}", out.forms());
    }

    /// Dropping a form takes its owner with it.
    ///
    /// The parallel-vector failure, asserted directly: after `retain` removes
    /// the entry file's `test` block, every surviving form must still resolve
    /// to the file it came from. Checked through the same slice-and-re-parse
    /// evidence, because "the lengths still match" would pass on a program
    /// where every owner shifted by one.
    ///
    /// **Red run** (2026-08-12), `retain` filtering `self.forms` only and
    /// leaving `self.owner` whole:
    /// ```text
    /// after retain, form 0 does not belong to the file it is attributed to:
    /// slice "test \"t\"\n  assert 1 == 1\n" of <anonymous>
    ///   left: []
    ///  right: [List([Atom(Symbol("define")), …double…])]
    /// ```
    /// The surviving forms kept the DROPPED form's owner, so kazu's `double`
    /// was attributed to the entry file and sliced out of it.
    #[test]
    fn retain_drops_a_forms_owner_with_it() {
        let loader = MemLoader(BTreeMap::from([("kazu", "def double(n)\n  n * 2\nend")]));
        let src = "test \"t\"\n  assert 1 == 1\nend\nuse(\"kazu\")\ndouble(21)";
        let mut out = resolve(src, &loader).expect("resolves");
        assert!(
            out.forms().iter().any(super::is_test_form),
            "the fixture must contain the test block this drops"
        );
        out.retain(|f| !super::is_test_form(f));
        assert!(!out.forms().iter().any(super::is_test_form));
        for (i, form) in out.forms().iter().enumerate() {
            let file = out
                .owner_of(i)
                .and_then(|id| out.file(id))
                .unwrap_or_else(|| panic!("form {i} lost its owner"));
            let slice = &file.text[form.span.start..form.span.end];
            let reparsed = blue_lang_syntax::parse_program_tree(slice)
                .map(|f| f.iter().map(Spanned::to_sexp).collect::<Vec<_>>())
                .unwrap_or_default();
            assert_eq!(
                reparsed,
                vec![form.to_sexp()],
                "after retain, form {i} does not belong to the file it is \
                 attributed to: slice {slice:?} of {}",
                file.path
                    .as_deref()
                    .map_or_else(|| "<anonymous>".to_string(), |p| p.display().to_string())
            );
        }
        assert_eq!(out.forms().len(), 2, "{:?}", out.forms());
    }

    /// An unresolvable index reports no position rather than the entry file's.
    #[test]
    fn an_unstamped_diagnostic_gets_no_position_rather_than_a_wrong_one() {
        let loader = MemLoader(BTreeMap::new());
        let out = resolve("def f(n)\n  n\nend", &loader).expect("resolves");
        let rendered = out
            .locate(
                blue_lang_check::Diagnostic::UNSTAMPED,
                tatara_lisp::Span::new(0, 1),
                "something went wrong",
            )
            .to_string();
        assert_eq!(rendered, "<unknown file>: something went wrong");
        assert!(
            !rendered.contains(":1:1"),
            "an unowned diagnostic borrowed a position from somewhere: {rendered}"
        );
    }
}
