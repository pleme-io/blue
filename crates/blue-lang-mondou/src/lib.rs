//! `mondou` (問答, *question and answer*): blue's query engine.
//!
//! Every tool that needs to know something about a blue program — the
//! language server, `blue check`, a REPL, an agent — asks this crate, and
//! each answer is computed once from the same queries
//! (`theory/BLUE-ENGINE.md` §3). Today that is milestones E1 and E2:
//!
//! | query | key | memo |
//! |---|---|---|
//! | [`Engine::parse`] | the text (SipHash, verified on a hit) | a document's revisions are bounded; a package's files are kept |
//! | [`Engine::package`] | the bidama's name | loaded once per session: a bidama is durable until a document overlaying one of its files changes |
//! | [`items`] | a parse | per analysis |
//! | scope and resolve ([`Analysis`]) | a document revision | one per revision, shared by every request against it |
//!
//! The check stage is the pipeline's (`blue_lang_runtime::pipeline::
//! check_entry`), handed a [`Loader`] that answers from these memos, so the
//! engine adds no second checker: what `blue check FILE` reports is what an
//! editor shows.
//!
//! The views an editor asks for — completion, definition, references,
//! rename, symbols, signatures — are computed from those queries in byte
//! offsets ([`Span`]); a transport converts positions.

mod complete;
mod items;
mod locals;
mod memo;
mod navigate;
mod signature;

use std::cell::{OnceCell, RefCell};
use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::rc::Rc;

use blue_lang_check::names::Resolved;
use blue_lang_check::{NameTable, Namespace};
use blue_lang_runtime::pipeline::{check_entry, Checked, Checking};
use blue_lang_runtime::uses::{Entry, Loader, ResolvedProgram};
use blue_lang_syntax::{ParseError, Span, Spanned};

pub use complete::{Completion, CompletionKind, Tier};
pub use items::{Item, ItemKind};
pub use locals::{LocalBinding, Locals};
pub use memo::Stats;
pub use navigate::{Located, Refusal, Symbol, WorkspaceSymbol};
pub use signature::Signature;

/// A parse: the spanned tree, or why there is none.
pub type Parsed = Result<Vec<Spanned>, ParseError>;

/// Which file a [`Span`] indexes.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum FileRef {
    /// An open document, by its id.
    Document(String),
    /// A file the loader read.
    Path(PathBuf),
}

/// A bidama as the loader handed it over, with each file's text.
#[derive(Debug)]
pub struct Package {
    pub name: String,
    pub files: Vec<(String, Rc<str>)>,
    canonical: Vec<PathBuf>,
}

struct Document {
    text: Rc<str>,
    path: Option<PathBuf>,
    canonical: Option<PathBuf>,
    revision: u64,
}

/// The engine: the open documents, the loader, and the memo every query
/// reads through.
pub struct Engine {
    loader: Box<dyn Loader>,
    memo: memo::Memo,
    documents: BTreeMap<String, Document>,
    revision: u64,
    generation: std::cell::Cell<u64>,
    analyses: RefCell<HashMap<String, Rc<Analysis>>>,
    last_good: RefCell<HashMap<String, Rc<Analysis>>>,
    builtins: OnceCell<NameTable>,
    overlay: RefCell<BTreeMap<PathBuf, Rc<str>>>,
}

impl Engine {
    #[must_use]
    pub fn new(loader: Box<dyn Loader>) -> Self {
        Self {
            loader,
            memo: memo::Memo::default(),
            documents: BTreeMap::new(),
            revision: 0,
            generation: std::cell::Cell::new(0),
            analyses: RefCell::new(HashMap::new()),
            last_good: RefCell::new(HashMap::new()),
            builtins: OnceCell::new(),
            overlay: RefCell::new(BTreeMap::new()),
        }
    }

    /// Open or replace a document. `path` is the file it is a buffer of, when
    /// it is one: it decides the document's bidama and where its relative
    /// paths resolve, exactly as for `blue check FILE`.
    pub fn set_document(&mut self, id: &str, path: Option<PathBuf>, text: &str) {
        self.revision += 1;
        let canonical = path.as_deref().map(canonical);
        if let Some(c) = &canonical {
            self.invalidate_path(c);
        }
        self.documents.insert(
            id.to_string(),
            Document {
                text: Rc::from(text),
                path,
                canonical,
                revision: self.revision,
            },
        );
    }

    pub fn close_document(&mut self, id: &str) {
        if let Some(doc) = self.documents.remove(id) {
            if let Some(c) = &doc.canonical {
                self.invalidate_path(c);
            }
        }
        self.analyses.borrow_mut().remove(id);
        self.last_good.borrow_mut().remove(id);
    }

    #[must_use]
    pub fn document_text(&self, id: &str) -> Option<Rc<str>> {
        self.documents.get(id).map(|d| d.text.clone())
    }

    #[must_use]
    pub fn document_ids(&self) -> Vec<String> {
        self.documents.keys().cloned().collect()
    }

    /// The document whose file is `path`, if one is open.
    #[must_use]
    pub fn document_at(&self, path: &Path) -> Option<String> {
        let c = canonical(path);
        self.documents
            .iter()
            .find(|(_, d)| d.canonical.as_deref() == Some(c.as_path()))
            .map(|(id, _)| id.clone())
    }

    /// Forget every loaded bidama holding the file at `path`: it changed on
    /// disk or in a buffer, so its next load reads it again.
    pub fn invalidate_path(&mut self, path: &Path) {
        if self.memo.drop_packages_holding(path) {
            self.generation.set(self.generation.get() + 1);
        }
    }

    /// Every count the memo keeps: what was computed, not what was asked.
    #[must_use]
    pub fn stats(&self) -> Stats {
        self.memo.stats()
    }

    /// `parse(text)`: one parse per distinct text.
    #[must_use]
    pub fn parse(&self, text: &str) -> Rc<Parsed> {
        self.memo.parse(text, false)
    }

    /// `package(name)`: the bidama's files, loaded once per session.
    ///
    /// # Errors
    ///
    /// The loader's reason it could not be loaded.
    pub fn package(&self, name: &str) -> Result<Rc<Package>, String> {
        let overlay = |path: &Path| {
            let c = canonical(path);
            if let Some(text) = self.overlay.borrow().get(&c) {
                return Some((c, text.clone()));
            }
            self.documents
                .values()
                .find(|d| d.canonical.as_deref() == Some(c.as_path()))
                .map(|d| (c.clone(), d.text.clone()))
        };
        self.memo.package(self.loader.as_ref(), name, &overlay)
    }

    /// The bidamas the loader can enumerate.
    #[must_use]
    pub fn available(&self) -> Vec<String> {
        self.memo.available(self.loader.as_ref())
    }

    /// The analysis of document `id` at its current revision: computed once,
    /// then shared by every request until the document or a bidama it loads
    /// changes.
    #[must_use]
    pub fn analysis(&self, id: &str) -> Option<Rc<Analysis>> {
        let doc = self.documents.get(id)?;
        if let Some(a) = self.analyses.borrow().get(id) {
            if a.revision == doc.revision && a.generation == self.generation.get() {
                return Some(a.clone());
            }
        }
        let mut a = self.analyse(Some(id), doc.path.clone(), doc.text.clone());
        a.revision = doc.revision;
        let a = Rc::new(a);
        self.analyses.borrow_mut().insert(id.to_string(), a.clone());
        if matches!(a.checked, Some(Ok(_))) {
            self.last_good
                .borrow_mut()
                .insert(id.to_string(), a.clone());
        }
        Some(a)
    }

    /// The newest analysis of `id` that parsed and checked, for a request
    /// made while the buffer is mid-edit.
    #[must_use]
    pub fn last_good(&self, id: &str) -> Option<Rc<Analysis>> {
        let current = self.analysis(id)?;
        if matches!(current.checked, Some(Ok(_))) {
            return Some(current);
        }
        self.last_good.borrow().get(id).cloned()
    }

    /// Run `f` as if each file of `texts` held its text: a bidama holding one
    /// is loaded with it, and loaded again from the documents afterwards.
    fn with_overlay<T>(&self, texts: &[(PathBuf, Rc<str>)], f: impl FnOnce() -> T) -> T {
        for (path, text) in texts {
            let c = canonical(path);
            self.memo.drop_packages_holding(&c);
            self.overlay.borrow_mut().insert(c, text.clone());
        }
        let out = f();
        let overlaid: Vec<PathBuf> = std::mem::take(&mut *self.overlay.borrow_mut())
            .into_keys()
            .collect();
        for c in overlaid {
            self.memo.drop_packages_holding(&c);
        }
        out
    }

    /// Analyse `text` as if it were the file at `path`, without opening it:
    /// what a rename is verified against.
    #[must_use]
    pub fn analyse_text(&self, path: Option<PathBuf>, text: &str) -> Analysis {
        self.analyse(None, path, Rc::from(text))
    }

    fn analyse(&self, id: Option<&str>, path: Option<PathBuf>, text: Rc<str>) -> Analysis {
        self.memo.count_analysis();
        let parsed = self.memo.parse(&text, false);
        let checked = parsed.as_ref().as_ref().ok().map(|_| {
            let loader = memo::MemoLoader {
                engine: self,
                entry: &text,
            };
            check_entry(
                Entry {
                    path: path.as_deref(),
                    text: &text,
                },
                &loader,
                None,
                Checking::WithTests,
            )
            .map_err(|e| e.to_string())
        });
        Analysis {
            id: id.map(str::to_string),
            revision: 0,
            generation: self.generation.get(),
            text,
            path,
            parsed,
            checked,
            resolved: OnceCell::new(),
            locals: OnceCell::new(),
            items: OnceCell::new(),
        }
    }

    /// The interpreter's own names, for a document whose imports did not
    /// load: the builtins need no program.
    #[must_use]
    pub fn builtins(&self) -> &NameTable {
        self.builtins.get_or_init(|| {
            let mut interp = blue_lang_runtime::interpreter_hostless();
            blue_lang_runtime::inputs::install_input_primitives(
                &mut interp,
                blue_lang_runtime::Inputs::new(),
            );
            blue_lang_runtime::pipeline::builtin_names(&interp)
        })
    }

    /// The canonical text of document `id`, from the tree its revision was
    /// parsed into: `None` when it does not parse or cannot be formatted
    /// without losing a comment.
    #[must_use]
    pub fn formatted(&self, id: &str) -> Option<String> {
        let a = self.analysis(id)?;
        let tree = a.parsed.as_ref().as_ref().ok()?;
        blue_lang_fmt::format_tree_lossless(&a.text, tree).ok()
    }

    /// `blue check --fix` on document `id`: every machine-applicable fix,
    /// then the one formatting, repeated while a fix exposes another, as the
    /// CLI does. `None` when nothing applies.
    #[must_use]
    pub fn fix_all(&self, id: &str) -> Option<String> {
        let a = self.analysis(id)?;
        let original = a.text.to_string();
        let mut text = original.clone();
        let mut current = a;
        for _ in 0..4 {
            let Some(Ok(checked)) = &current.checked else {
                break;
            };
            let (fixed, applied) = blue_lang_check::fixes::apply_machine_fixes(
                &checked.outcome.diagnostics,
                &|i| checked.program.owner_of(i) == Some(ResolvedProgram::ENTRY),
                &text,
            );
            if applied == 0 {
                break;
            }
            text = blue_lang_fmt::format_source_lossless(&fixed).unwrap_or(fixed);
            current = Rc::new(self.analyse_text(current.path.clone(), &text));
        }
        (text != original).then_some(text)
    }

    fn analyses_of_open_documents(&self) -> Vec<Rc<Analysis>> {
        self.documents
            .keys()
            .filter_map(|id| self.analysis(id))
            .collect()
    }

    /// A file as the engine names it: an open document when one is a buffer
    /// of `path`, else the path.
    fn file_ref(&self, path: &Path) -> FileRef {
        self.document_at(path)
            .map_or_else(|| FileRef::Path(path.to_path_buf()), FileRef::Document)
    }
}

/// One document revision, through every query: the parse, the program its
/// imports resolve to, the check stage's findings and name table, and the
/// views read off them.
pub struct Analysis {
    id: Option<String>,
    revision: u64,
    generation: u64,
    pub text: Rc<str>,
    pub path: Option<PathBuf>,
    pub parsed: Rc<Parsed>,
    /// `None` when the text does not parse; `Some(Err)` when its imports do
    /// not load.
    pub checked: Option<Result<Checked, String>>,
    resolved: OnceCell<Option<Resolved>>,
    locals: OnceCell<Locals>,
    items: OnceCell<Vec<Item>>,
}

impl Analysis {
    #[must_use]
    pub fn revision(&self) -> u64 {
        self.revision
    }

    /// The program through the check stage, when it got there.
    #[must_use]
    pub fn checked(&self) -> Option<&Checked> {
        self.checked.as_ref()?.as_ref().ok()
    }

    /// Every non-local reference of the program, resolved: computed on the
    /// first request that needs it.
    #[must_use]
    pub fn resolved(&self) -> Option<&Resolved> {
        self.resolved
            .get_or_init(|| self.checked().map(Checked::resolve))
            .as_ref()
    }

    /// The document's own top-level forms with their index in the program.
    fn entry_forms(&self) -> Vec<(usize, &Spanned)> {
        match self.checked() {
            Some(c) => c
                .program
                .forms()
                .iter()
                .enumerate()
                .filter(|(i, _)| c.program.owner_of(*i) == Some(ResolvedProgram::ENTRY))
                .collect(),
            None => match self.parsed.as_ref() {
                Ok(forms) => forms.iter().enumerate().collect(),
                Err(_) => Vec::new(),
            },
        }
    }

    /// The namespace the document's own definitions live in.
    #[must_use]
    pub fn own_namespace(&self) -> Namespace {
        match self.checked() {
            Some(c) => {
                let first = (0..c.program.forms().len())
                    .find(|i| c.program.owner_of(*i) == Some(ResolvedProgram::ENTRY));
                match first {
                    Some(i) => blue_lang_runtime::pipeline::namespace_of(&c.program, i),
                    None => match c
                        .program
                        .file(ResolvedProgram::ENTRY)
                        .and_then(|f| f.package.clone())
                    {
                        Some(p) => Namespace::Bidama(p),
                        None => Namespace::File(String::new()),
                    },
                }
            }
            None => Namespace::File(String::new()),
        }
    }

    /// Bindings below the top level: parameters, `let`s, locals.
    #[must_use]
    pub fn locals(&self, engine: &Engine) -> &Locals {
        self.locals
            .get_or_init(|| locals::index(self, engine.builtins()))
    }

    /// The document's top-level items.
    #[must_use]
    pub fn items(&self) -> &[Item] {
        self.items.get_or_init(|| match self.parsed.as_ref() {
            Ok(forms) => items::of(forms, &self.text),
            Err(_) => Vec::new(),
        })
    }

    /// The text of a file this analysis read.
    #[must_use]
    pub fn file_text(&self, file: &FileRef) -> Option<&str> {
        let path = match file {
            FileRef::Document(id) if Some(id) == self.id.as_ref() => return Some(&self.text),
            FileRef::Document(_) => return None,
            FileRef::Path(p) => p,
        };
        self.checked()?
            .program
            .files()
            .iter()
            .find(|f| f.path.as_deref() == Some(path.as_path()))
            .map(|f| f.text.as_str())
    }

    /// Which file top-level form `top_level` of the program came from.
    fn file_of(&self, engine: &Engine, top_level: usize) -> Option<FileRef> {
        let c = self.checked()?;
        let id = c.program.owner_of(top_level)?;
        if id == ResolvedProgram::ENTRY {
            return Some(match &self.id {
                Some(doc) => FileRef::Document(doc.clone()),
                None => FileRef::Path(self.path.clone().unwrap_or_default()),
            });
        }
        let path = c.program.file(id)?.path.clone()?;
        Some(engine.file_ref(&path))
    }

    /// The packages the document's `use` forms name, with each `use`.
    fn imports(&self) -> Vec<blue_lang_syntax::scope::Import> {
        match self.parsed.as_ref() {
            Ok(forms) => forms
                .iter()
                .filter_map(blue_lang_syntax::scope::use_target)
                .collect(),
            Err(_) => Vec::new(),
        }
    }
}

fn canonical(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

/// The span `node` names `name` at: a qualified reference (`retsu::first`)
/// is renamed or pointed at by its last part.
fn name_span(text: &str, span: Span, name: &str) -> Span {
    let part = blue_lang_syntax::qualified(name).map_or(name, |(_, n)| n);
    match text.get(span.start..span.end) {
        Some(written) if written.ends_with(part) => Span::new(span.end - part.len(), span.end),
        _ => span,
    }
}
