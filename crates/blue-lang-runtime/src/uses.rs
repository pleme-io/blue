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

use tatara_lisp::{Sexp, Span, Spanned};

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

    /// The bidama an ENTRY file at `path` belongs to, if it belongs to one:
    /// the `package(name, …)` of the Bluefile beside it. `blue test
    /// bidamas/retsu/retsu.b` checks and runs retsu's own definitions, under
    /// retsu's namespace, exactly as an importer sees them.
    ///
    /// A file with no bidama around it (a script, `spec/*.b`) is in the root
    /// namespace, and so is every entry a loader without a filesystem is
    /// handed, which is this default.
    fn entry_package(&self, _path: &Path) -> Option<String> {
        None
    }

    /// The bidamas `package`'s Bluefile.lock records as `needs` (with no lock,
    /// its Bluefile's rows), when the loader can read it.
    /// `None` when it cannot, and the check stage then has nothing to compare
    /// the package's `use` forms against (B0019).
    ///
    /// `entry_dir` is the directory of the entry file, for the entry's own
    /// bidama, which a loader may not find under its roots.
    fn needs(&self, _package: &str, _entry_dir: Option<&Path>) -> Option<BTreeSet<String>> {
        None
    }

    /// Bidama `package`'s Bluefile version, when the loader can read it —
    /// what a `legacy_names` window is measured against.
    fn version(&self, _package: &str, _entry_dir: Option<&Path>) -> Option<String> {
        None
    }

    /// The spanned tree of one source this loader handed out, or of the entry.
    /// Resolution parses through here, so a loader that has seen a text
    /// before (an editor's session) can answer without parsing it again.
    ///
    /// # Errors
    ///
    /// The parser's, unchanged.
    fn parse(&self, src: &str) -> Result<Vec<Spanned>, blue_lang_syntax::ParseError> {
        blue_lang_syntax::parse_program_tree(src)
    }

    /// Every bidama this loader could load, by name, when it can enumerate
    /// them: what an editor offers behind a `use` the file does not have yet.
    fn available(&self) -> Vec<String> {
        Vec::new()
    }

    fn frontend(&self, _entry: &Path) -> Option<Frontend> {
        None
    }

    /// What the entry file is to the project above it: the program of a
    /// `generate` row, of a `service` row, and the service's bindings. Each
    /// is an integration point the file owes a test of its kind.
    fn roles(&self, _entry: &Path) -> Vec<Role> {
        Vec::new()
    }

    /// The levels one step below `name`, by their full paths, sorted: what a
    /// `use` of `name` brings into reach with it. A bidama with no levels has
    /// none, which is this default.
    fn children(&self, _name: &str) -> Vec<String> {
        Vec::new()
    }

    /// Where bidama `name` moved, when it no longer loads under that name and
    /// the root it moved into declares the move in its Bluefile
    /// (`legacy_packages(since, [["bpf", "kaaneru/bpf"]])`). A `use` of the old
    /// name then loads the new path, and the check stage reports B0074 with
    /// the fix. A loader that cannot enumerate Bluefiles knows of no move,
    /// which is this default.
    fn moved(&self, _name: &str) -> Option<PackageMove> {
        None
    }
}

/// A bidama that moved into another bidama's tree, as the root it moved into
/// declares it: `old` was a bidama of its own, `new` is the level it is now
/// (`kaaneru/bpf`), from the root's version `since`. `version` is the root's
/// version now, when the loader can read it; the bridge is open while it is
/// at least `since` and below the next minor, and kept open when unknown.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PackageMove {
    pub old: String,
    pub new: String,
    pub since: String,
    pub version: Option<String>,
}

/// One `use` the resolver loaded through a [`PackageMove`]: the import at
/// `import` in [`ResolvedProgram::imports`], which the file wrote as
/// `written` and which now names the moved level.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Bridged {
    pub import: usize,
    pub written: String,
    pub moved: PackageMove,
}

/// The path `package` names after a move of its root: `bpf/sub` is
/// `kaaneru/bpf/sub` once `bpf` is `kaaneru/bpf`.
#[must_use]
pub fn moved_path(package: &str, moved: &PackageMove) -> String {
    match package.strip_prefix(moved.old.as_str()) {
        Some("") => moved.new.clone(),
        Some(rest) if rest.starts_with(blue_lang_syntax::QUALIFIER) => {
            format!("{}{rest}", moved.new)
        }
        _ => package.to_string(),
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Frontend {
    pub table: Option<(String, String)>,
    pub view: bool,
}

/// The entry file's role in its project: a point of the project that the
/// file declares, by the Bluefile row that names it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Role {
    /// The program of `generate(name, …)`: it owes a `kind: :rendering` test.
    Generator(String),
    /// The program of `service(name, …)`: it owes a `kind: :e2e` test.
    Service(String),
    /// A binding of a service (`cache`, `schema`): it owes a `kind:
    /// :contract` test.
    Binding(String, String),
    /// The program of `check(name, …)`, with the stage its row declares: a
    /// row that declares none is B0092.
    Gate(String, Option<String>),
}

impl Role {
    /// The roles a witness or a conformance row names by one word, for a row
    /// called `name`: `generator`, `service`, `binding` (a service that binds
    /// a cache), `gate` (a check row with no stage) and `staged-gate` (one
    /// with `stage: :push`).
    #[must_use]
    pub fn named(word: &str, name: &str) -> Vec<Role> {
        match word {
            "generator" => vec![Role::Generator(name.into())],
            "service" => vec![Role::Service(name.into())],
            "binding" => vec![
                Role::Service(name.into()),
                Role::Binding(name.into(), "cache".into()),
            ],
            "gate" => vec![Role::Gate(name.into(), None)],
            "staged-gate" => vec![Role::Gate(name.into(), Some("push".into()))],
            _ => Vec::new(),
        }
    }
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

pub trait Scopes {
    fn scope(&self, entry: Option<&Path>) -> Vec<PathBuf>;
    fn loader(&self, scope: &[PathBuf]) -> std::rc::Rc<dyn Loader>;
    fn set_workspace(&mut self, _folders: Vec<PathBuf>) {}
}

pub struct OneScope(pub std::rc::Rc<dyn Loader>);

impl Scopes for OneScope {
    fn scope(&self, _entry: Option<&Path>) -> Vec<PathBuf> {
        Vec::new()
    }

    fn loader(&self, _scope: &[PathBuf]) -> std::rc::Rc<dyn Loader> {
        self.0.clone()
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

impl FileId {
    /// The file's position in its program's file table: a key, never an
    /// index a caller may compute.
    #[must_use]
    pub fn index(self) -> usize {
        self.0
    }
}

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
    /// The bidama this file belongs to — the name `use` was given, or for the
    /// entry file its [`Loader::entry_package`] — or `None` for a file in the
    /// root namespace. The namespace its definitions are resolved under
    /// (`blue_lang_check::Namespace::Bidama`).
    pub package: Option<String>,
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
    imports: Vec<(FileId, Import)>,
    needs: std::collections::BTreeMap<String, BTreeSet<String>>,
    versions: std::collections::BTreeMap<String, String>,
    frontend: Option<Frontend>,
    roles: Vec<Role>,
    bridged: Vec<Bridged>,
}

impl ResolvedProgram {
    /// The entry program's own file. Always present; always first.
    pub const ENTRY: FileId = FileId(0);

    fn new(entry: Entry<'_>, package: Option<String>) -> Self {
        let mut program = Self {
            forms: Vec::new(),
            owner: Vec::new(),
            files: Vec::new(),
            imports: Vec::new(),
            needs: std::collections::BTreeMap::new(),
            versions: std::collections::BTreeMap::new(),
            frontend: None,
            roles: Vec::new(),
            bridged: Vec::new(),
        };
        let id = program.intern(
            entry.path.map(Path::to_path_buf),
            package,
            entry.text.to_owned(),
        );
        debug_assert_eq!(id, Self::ENTRY);
        program
    }

    /// Record a file's text and hand back its handle.
    fn intern(&mut self, path: Option<PathBuf>, package: Option<String>, text: String) -> FileId {
        let id = FileId(self.files.len());
        self.files.push(SourceFile {
            id,
            path,
            package,
            text,
        });
        id
    }

    fn foreign_shapes(&self, file: FileId) -> Vec<blue_lang_syntax::pattern::ForeignShape> {
        use blue_lang_syntax::pattern::{declared_shapes, ForeignShape};
        let here = self.files[file.0].package.as_deref();
        let listed: Vec<&Import> = self
            .imports
            .iter()
            .filter(|(owner, _)| *owner == file)
            .map(|(_, i)| i)
            .collect();
        let mut out = Vec::new();
        for (form, owner) in self.forms.iter().zip(&self.owner) {
            let Some(package) = self.files[owner.0].package.as_deref() else {
                continue;
            };
            if Some(package) == here {
                continue;
            }
            for shape in declared_shapes(form) {
                let named = |n: &str| {
                    listed
                        .iter()
                        .any(|i| i.package == package && i.names.iter().any(|(m, _)| m == n))
                };
                let qualified_predicate = blue_lang_syntax::qualify(package, &shape.predicate);
                if named(&shape.name) {
                    out.push(ForeignShape {
                        name: shape.name.clone(),
                        predicate: if named(&shape.predicate) {
                            shape.predicate.clone()
                        } else {
                            qualified_predicate.clone()
                        },
                        fields: shape.fields.clone(),
                    });
                }
                out.push(ForeignShape {
                    name: blue_lang_syntax::qualify(package, &shape.name),
                    predicate: qualified_predicate,
                    fields: shape.fields,
                });
            }
        }
        out
    }

    fn lower_foreign_patterns(&mut self) -> Result<(), String> {
        let mut by_file: std::collections::BTreeMap<
            usize,
            Vec<blue_lang_syntax::pattern::ForeignShape>,
        > = std::collections::BTreeMap::new();
        for i in 0..self.forms.len() {
            let file = self.owner[i];
            let shapes = by_file
                .entry(file.0)
                .or_insert_with(|| self.foreign_shapes(file));
            if shapes.is_empty() {
                continue;
            }
            let form = std::mem::replace(
                &mut self.forms[i],
                Spanned::new(
                    tatara_lisp::Span::synthetic(),
                    tatara_lisp::SpannedForm::Nil,
                ),
            );
            self.forms[i] = blue_lang_syntax::pattern::lower_foreign(form, shapes)
                .map_err(|e| e.located(&self.files[file.0].text).to_string())?;
        }
        Ok(())
    }

    /// Append a top-level form together with the file it came from.
    ///
    /// The ONE place `forms` and `owner` grow, so they cannot grow apart.
    fn push(&mut self, form: Spanned, owner: FileId) {
        self.forms.push(form);
        self.owner.push(owner);
    }

    #[must_use]
    pub fn frontend(&self) -> Option<&Frontend> {
        self.frontend.as_ref()
    }

    #[must_use]
    pub fn roles(&self) -> &[Role] {
        &self.roles
    }

    /// Every top-level form, in evaluation order.
    #[must_use]
    pub fn forms(&self) -> &[Spanned] {
        &self.forms
    }

    /// The same forms with their spans projected away, for the stages that do
    /// not report positions — erasure, evaluation, the test harness. A `use`
    /// form is a declaration the resolver consumed, and projects to `nil`, so
    /// every index still names its top-level form.
    #[must_use]
    pub fn sexps(&self) -> Vec<Sexp> {
        self.forms
            .iter()
            .map(|f| {
                if blue_lang_syntax::scope::is_file_declaration(f) {
                    Sexp::Nil
                } else {
                    f.to_sexp()
                }
            })
            .collect()
    }

    /// Each loaded bidama's Bluefile `needs`, where the loader read one.
    #[must_use]
    pub fn needs(&self) -> &std::collections::BTreeMap<String, BTreeSet<String>> {
        &self.needs
    }

    /// Each loaded bidama's Bluefile version, where the loader read one.
    #[must_use]
    pub fn versions(&self) -> &std::collections::BTreeMap<String, String> {
        &self.versions
    }

    /// Every `use` form, with the file that wrote it.
    #[must_use]
    pub fn imports(&self) -> &[(FileId, Import)] {
        &self.imports
    }

    /// Every import the resolver loaded through a moved bidama's bridge
    /// ([`Loader::moved`]). Its entry in [`Self::imports`] names the new path.
    #[must_use]
    pub fn bridged(&self) -> &[Bridged] {
        &self.bridged
    }

    /// `named` and every bidama a file of theirs reaches through `use`,
    /// transitively, with every level below each that this program loaded.
    #[must_use]
    pub fn reached_from(&self, named: &BTreeSet<String>) -> BTreeSet<String> {
        let mut out = named.clone();
        let mut pending: Vec<String> = named.iter().cloned().collect();
        while let Some(at) = pending.pop() {
            let below = format!("{at}{}", blue_lang_syntax::QUALIFIER);
            for f in &self.files {
                if let Some(p) = f.package.as_ref().filter(|p| p.starts_with(&below)) {
                    if out.insert(p.clone()) {
                        pending.push(p.clone());
                    }
                }
            }
            for (owner, import) in &self.imports {
                let from = self.file(*owner).and_then(|f| f.package.as_deref());
                if from == Some(at.as_str()) && out.insert(import.package.clone()) {
                    pending.push(import.package.clone());
                }
            }
        }
        out
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
            // share an offset can still trade a plausible number. A runtime
            // error now avoids that by locating against the innermost frame's
            // definition (`observe::Fault`), so the residue is a frame with no
            // named definition, not a wider guard here.
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

impl Located<'_> {
    /// The file it names, as [`std::fmt::Display`] prints it: a path,
    /// `<anonymous>`, or `None` when no owning file could be found.
    #[must_use]
    pub fn file_name(&self) -> Option<String> {
        match self.origin {
            Origin::File(p) => Some(p.display().to_string()),
            Origin::Anonymous => Some("<anonymous>".to_string()),
            Origin::Unresolved => None,
        }
    }

    /// The 1-based line and column, when the span is a real range in that file.
    #[must_use]
    pub fn line_col(&self) -> Option<(usize, usize)> {
        self.line_col
    }
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

pub use blue_lang_syntax::scope::{use_target, use_targets, Import};

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
/// distribution loads and runs instead of hanging. A cycle through a level
/// below a bidama is refused instead, with its path: a `use` of a level
/// brings everything below it, so a level that imports its own ancestor has
/// no order to load in.
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
    let package = entry.path.and_then(|p| loader.entry_package(p));
    let mut seen = BTreeSet::new();
    // The entry's own bidama is already loaded: it IS the entry. A cycle back
    // to it must not splice a second copy of its definitions in.
    if let Some(p) = &package {
        seen.insert(p.clone());
    }
    let mut out = ResolvedProgram::new(entry, package.clone());
    out.frontend = entry.path.and_then(|p| loader.frontend(p));
    out.roles = entry.path.map(|p| loader.roles(p)).unwrap_or_default();
    if let Some(p) = &package {
        if let Some(n) = loader.needs(p, entry.path.and_then(Path::parent)) {
            out.needs.insert(p.clone(), n);
        }
        if let Some(v) = loader.version(p, entry.path.and_then(Path::parent)) {
            out.versions.insert(p.clone(), v);
        }
    }
    if let Some(p) = &package {
        for child in loader.children(p) {
            load_level(&child, loader, &mut out, &mut seen, &[])?;
        }
    }
    expand(
        forms,
        ResolvedProgram::ENTRY,
        loader,
        &mut out,
        &mut seen,
        &[],
    )?;
    out.lower_foreign_patterns()?;
    Ok(out)
}

/// The path of the cycle a `use` of `name` would close, when one level of it
/// lies below a bidama. A cycle among whole bidamas stays a no-op.
fn level_cycle(name: &str, out: &ResolvedProgram, chain: &[String]) -> Option<String> {
    let stack: Vec<&str> = out.files[ResolvedProgram::ENTRY.0]
        .package
        .iter()
        .map(String::as_str)
        .chain(chain.iter().map(String::as_str))
        .collect();
    let at = stack.iter().position(|s| *s == name)?;
    let cycle = &stack[at..];
    cycle
        .iter()
        .any(|l| blue_lang_syntax::is_nested(l))
        .then(|| {
            let path: Vec<String> = cycle
                .iter()
                .chain(std::iter::once(&name))
                .map(|l| blue_lang_syntax::spell_level(l))
                .collect();
            format!(
                "a cycle between levels: {}. A `use` of a level brings every level below it, so a level never imports its ancestor; move what they share to a level both can `use`",
                path.join(" -> ")
            )
        })
}

fn load_level(
    name: &str,
    loader: &dyn Loader,
    out: &mut ResolvedProgram,
    seen: &mut BTreeSet<String>,
    chain: &[String],
) -> Result<(), String> {
    if let Some(cycle) = level_cycle(name, out, chain) {
        return Err(cycle);
    }
    if !seen.insert(name.to_owned()) {
        return Ok(());
    }
    let sources = loader.load(name).map_err(|e| describe(chain, name, &e))?;
    if let Some(n) = loader.needs(name, None) {
        out.needs.insert(name.to_owned(), n);
    }
    if let Some(v) = loader.version(name, None) {
        out.versions.insert(name.to_owned(), v);
    }
    let mut inner_chain = chain.to_vec();
    inner_chain.push(name.to_owned());

    for (label, src) in sources {
        // `parse_program_tree`, not `parse_program`. The spanless door
        // discarded every imported position one line after the text
        // arrived, so an imported type error had nothing to report but a
        // message — see `ResolvedProgram`.
        let parsed = loader
            .parse(&src)
            .map_err(|e| describe(chain, name, &format!("{label}: {e}")))?;
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
        let id = out.intern(Some(PathBuf::from(label)), Some(name.to_owned()), src);
        expand(parsed, id, loader, out, seen, &inner_chain)?;
    }
    for child in loader.children(name) {
        load_level(&child, loader, out, seen, &inner_chain)?;
    }
    Ok(())
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
        let Some(imports) = use_targets(&form) else {
            // The file boundary is erased HERE — this is the append that used
            // to make every form indistinguishable from every other. Each one
            // now carries the file it came from, which is the whole fix.
            out.push(form, owner);
            continue;
        };
        for mut import in imports {
            let root = blue_lang_syntax::root_of(&import.package);
            if let Some(moved) = loader.moved(root) {
                let to = moved_path(&import.package, &moved);
                let written = std::mem::replace(&mut import.package, to);
                out.bridged.push(Bridged {
                    import: out.imports.len(),
                    written,
                    moved,
                });
            }
            let name = import.package.clone();
            out.imports.push((owner, import));
            // Loaded already, it is a no-op, and the declaration stays for
            // the check stage.
            load_level(&name, loader, out, seen, chain)?;
        }
        // The declaration itself, after the forms it brought in.
        out.push(form, owner);
    }
    Ok(())
}

/// Rename the symbols each file of `program` wrote in `forms`, its evaluated
/// tree top-level form for top-level form: `rename(package, name)` answers
/// the new name for a symbol a file of `package` (`None` for the root
/// namespace) wrote, or `None` to keep it. Quoted data is not code and keeps
/// its symbols; inside a quasiquote only what is unquoted is renamed.
pub fn rename_written(
    program: &ResolvedProgram,
    forms: &mut [Spanned],
    rename: &dyn Fn(Option<&str>, &str) -> Option<String>,
) {
    for (i, form) in forms.iter_mut().enumerate() {
        let package = program
            .owner_of(i)
            .and_then(|id| program.file(id))
            .and_then(|f| f.package.as_deref());
        rename_symbols(form, &|name| rename(package, name), false);
    }
}

fn rename_symbols(form: &mut Spanned, rename: &dyn Fn(&str) -> Option<String>, template: bool) {
    use tatara_lisp::{Atom, SpannedForm};
    match &mut form.form {
        SpannedForm::Atom(Atom::Symbol(s)) if !template => {
            if let Some(to) = rename(s) {
                *s = to;
            }
        }
        SpannedForm::List(items) => {
            let head = items
                .first()
                .and_then(Spanned::as_symbol)
                .map(str::to_owned);
            match (head.as_deref(), template) {
                (Some("quote"), false) => {}
                (Some("quasiquote"), false) => {
                    for item in items.iter_mut().skip(1) {
                        rename_symbols(item, rename, true);
                    }
                }
                (Some("unquote" | "unquote-splicing"), true) => {
                    for item in items.iter_mut().skip(1) {
                        rename_symbols(item, rename, false);
                    }
                }
                _ => {
                    for item in items.iter_mut() {
                        rename_symbols(item, rename, template);
                    }
                }
            }
        }
        SpannedForm::Quasiquote(inner) if !template => rename_symbols(inner, rename, true),
        SpannedForm::Unquote(inner) | SpannedForm::UnquoteSplice(inner) if template => {
            rename_symbols(inner, rename, false);
        }
        _ => {}
    }
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
pub(crate) mod tests {
    use super::*;
    use std::collections::BTreeMap;

    /// An in-memory distribution — the whole pass runs with no filesystem.
    pub(crate) struct MemLoader(pub(crate) BTreeMap<&'static str, &'static str>);

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
        // The `use` itself stays, for the check stage to point at, and never
        // reaches the evaluator, where `use` is not a defined function: the
        // evaluated projection has it as `nil`.
        assert_eq!(
            out.forms()
                .iter()
                .filter(|f| super::use_target(f).is_some())
                .count(),
            1
        );
        assert!(
            !out.sexps().iter().any(|f| f.to_string().contains("use")),
            "a use form would reach the evaluator as an unbound function: {:?}",
            out.sexps()
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
        let definitions = |p: &ResolvedProgram| {
            p.forms()
                .iter()
                .filter(|f| super::use_target(f).is_none())
                .count()
        };
        assert_eq!(
            definitions(&once),
            definitions(&twice),
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
        // `double`, the `use` declaration, and the call.
        assert_eq!(out.forms().len(), 3, "{:?}", out.forms());
    }

    #[test]
    fn a_package_reaches_what_it_uses_transitively_and_nothing_its_importer_uses() {
        let loader = MemLoader(BTreeMap::from([
            ("retsu", "use(\"kazu\")\ndef sum2(a, b)\n  a + b\nend"),
            ("kazu", "def double(n)\n  n * 2\nend"),
            ("other", "def one()\n  1\nend"),
        ]));
        let out = resolve("use(\"retsu\")\nuse(\"other\")", &loader).expect("resolves");
        let named = BTreeSet::from(["retsu".to_string()]);
        assert_eq!(
            out.reached_from(&named),
            BTreeSet::from(["kazu".to_string(), "retsu".to_string()])
        );
        assert_eq!(
            out.reached_from(&BTreeSet::from(["kazu".to_string()])),
            BTreeSet::from(["kazu".to_string()])
        );
    }

    #[test]
    fn renaming_reaches_only_the_files_of_the_named_package() {
        let loader = MemLoader(BTreeMap::from([("rede", "def get()\n  now_ms\nend")]));
        let out = resolve("use(\"rede\")\nnow_ms", &loader).expect("resolves");
        let mut forms: Vec<Spanned> = out.forms().to_vec();
        rename_written(&out, &mut forms, &|package, name| {
            (package == Some("rede") && name == "now_ms").then(|| "%moved".to_string())
        });
        let shown: Vec<(Option<String>, String)> = forms
            .iter()
            .enumerate()
            .map(|(i, f)| {
                let package = out
                    .owner_of(i)
                    .and_then(|id| out.file(id))
                    .and_then(|f| f.package.clone());
                (package, f.to_sexp().to_string())
            })
            .collect();
        assert!(
            shown
                .iter()
                .any(|(p, s)| p.as_deref() == Some("rede") && s.contains("%moved")),
            "{shown:?}"
        );
        assert!(
            shown
                .iter()
                .all(|(p, s)| p.is_some() || !s.contains("%moved")),
            "{shown:?}"
        );
        assert!(
            shown.iter().any(|(p, s)| p.is_none() && s == "now_ms"),
            "{shown:?}"
        );
    }

    #[test]
    fn quoted_data_keeps_its_symbols_and_an_unquote_is_code() {
        let mut forms = tatara_lisp::read_spanned(
            "(list now_ms 'now_ms (quote now_ms) `(now_ms ,now_ms) (quasiquote (now_ms (unquote now_ms))))",
        )
        .expect("reads");
        super::rename_symbols(
            &mut forms[0],
            &|name| (name == "now_ms").then(|| "%moved".to_string()),
            false,
        );
        assert_eq!(
            forms[0].to_sexp().to_string(),
            tatara_lisp::read_spanned(
                "(list %moved 'now_ms (quote now_ms) `(now_ms ,%moved) (quasiquote (now_ms (unquote %moved))))"
            )
            .unwrap()[0]
                .to_sexp()
                .to_string()
        );
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

    /// A distribution where `bpf` moved into `kaaneru` as `kaaneru/bpf`.
    struct Moved(MemLoader);

    impl Loader for Moved {
        fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
            self.0.load(name)
        }

        fn moved(&self, name: &str) -> Option<PackageMove> {
            (name == "bpf").then(|| PackageMove {
                old: "bpf".into(),
                new: "kaaneru/bpf".into(),
                since: "0.2.0".into(),
                version: Some("0.2.0".into()),
            })
        }
    }

    /// **A `use` of a moved bidama loads where it moved.** The import names
    /// the new path, and the bridge records what the file wrote, so the
    /// check stage can say so and rewrite it.
    ///
    /// Red run (2026-11-05), the `loader.moved` lookup in `expand` removed:
    /// `no bidama named "bpf"`.
    #[test]
    fn a_use_of_a_moved_bidama_loads_its_new_path_and_records_the_bridge() {
        let loader = Moved(MemLoader(BTreeMap::from([
            ("kaaneru/bpf", "def compile()\n  1\nend"),
            ("kaaneru/bpf/asm", "def op()\n  2\nend"),
        ])));
        let out = resolve("use(\"bpf\")\nuse(\"bpf/asm\")\n\nbpf::compile", &loader)
            .expect("the bridge resolves");
        let packages: Vec<&str> = out
            .imports()
            .iter()
            .map(|(_, i)| i.package.as_str())
            .collect();
        assert_eq!(packages, ["kaaneru/bpf", "kaaneru/bpf/asm"]);
        let written: Vec<(usize, &str)> = out
            .bridged()
            .iter()
            .map(|b| (b.import, b.written.as_str()))
            .collect();
        assert_eq!(written, [(0, "bpf"), (1, "bpf/asm")]);
        let unmoved = resolve("use(\"kaaneru/bpf\")", &loader).expect("resolves");
        assert!(unmoved.bridged().is_empty());
        assert_eq!(
            moved_path("bpfx", &out.bridged()[0].moved),
            "bpfx",
            "only the whole segment moves"
        );
    }
}
