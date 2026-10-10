//! The in-process memo, and the [`Loader`] the check stage reads it through.

use std::cell::{OnceCell, RefCell};
use std::collections::hash_map::DefaultHasher;
use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::rc::Rc;

use blue_lang_runtime::uses::Loader;
use blue_lang_syntax::{ParseError, Spanned};

use crate::{Engine, Package, Parsed};

/// How many document texts keep their parse. A package file's parse is kept
/// for the session; a buffer's revisions are not, beyond the last few.
const LIVE_PARSES: usize = 32;

/// What the memo computed, as opposed to what it was asked.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Stats {
    /// Texts parsed.
    pub parses: usize,
    /// Loads of each bidama through the loader.
    pub package_loads: BTreeMap<String, usize>,
    /// Document analyses: a parse, a resolution and a check each.
    pub analyses: usize,
}

#[derive(Default)]
pub(crate) struct Memo {
    parses: RefCell<HashMap<u64, Vec<(Rc<str>, Rc<Parsed>)>>>,
    live: RefCell<VecDeque<(u64, Rc<str>)>>,
    packages: RefCell<BTreeMap<String, Rc<Package>>>,
    needs: RefCell<BTreeMap<(String, Option<PathBuf>), Option<BTreeSet<String>>>>,
    versions: RefCell<BTreeMap<(String, Option<PathBuf>), Option<String>>>,
    entry_packages: RefCell<BTreeMap<PathBuf, Option<String>>>,
    available: OnceCell<Vec<String>>,
    items: RefCell<HashMap<u64, Vec<(Rc<str>, Rc<Vec<crate::Item>>)>>>,
    stats: RefCell<Stats>,
}

fn key(text: &str) -> u64 {
    let mut h = DefaultHasher::new();
    text.hash(&mut h);
    h.finish()
}

impl Memo {
    pub(crate) fn stats(&self) -> Stats {
        self.stats.borrow().clone()
    }

    pub(crate) fn count_analysis(&self) {
        self.stats.borrow_mut().analyses += 1;
    }

    /// The parse of `text`, verified on a hit by comparing the text itself:
    /// a 64-bit key alone would let a collision serve another file's tree.
    pub(crate) fn parse(&self, text: &str, durable: bool) -> Rc<Parsed> {
        let k = key(text);
        if let Some(hit) = self
            .parses
            .borrow()
            .get(&k)
            .and_then(|bucket| bucket.iter().find(|(t, _)| &**t == text))
        {
            return hit.1.clone();
        }
        self.stats.borrow_mut().parses += 1;
        let parsed = Rc::new(blue_lang_syntax::parse_program_tree(text));
        let owned: Rc<str> = Rc::from(text);
        self.parses
            .borrow_mut()
            .entry(k)
            .or_default()
            .push((owned.clone(), parsed.clone()));
        if !durable {
            let mut live = self.live.borrow_mut();
            live.push_back((k, owned));
            while live.len() > LIVE_PARSES {
                let Some((old, text)) = live.pop_front() else {
                    break;
                };
                if live.iter().any(|(_, t)| *t == text) {
                    continue;
                }
                let mut parses = self.parses.borrow_mut();
                if let Some(bucket) = parses.get_mut(&old) {
                    bucket.retain(|(t, _)| *t != text);
                    if bucket.is_empty() {
                        parses.remove(&old);
                    }
                }
            }
        }
        parsed
    }

    /// The items of a package file's text, kept for the session.
    pub(crate) fn items(&self, text: &str) -> Rc<Vec<crate::Item>> {
        let k = key(text);
        if let Some(hit) = self
            .items
            .borrow()
            .get(&k)
            .and_then(|bucket| bucket.iter().find(|(t, _)| &**t == text))
        {
            return hit.1.clone();
        }
        let parsed = self.parse(text, true);
        let items = Rc::new(match parsed.as_ref() {
            Ok(forms) => crate::items::of(forms, text),
            Err(_) => Vec::new(),
        });
        self.items
            .borrow_mut()
            .entry(k)
            .or_default()
            .push((Rc::from(text), items.clone()));
        items
    }

    pub(crate) fn package(
        &self,
        loader: &dyn Loader,
        name: &str,
        overlay: &dyn Fn(&Path) -> Option<(PathBuf, Rc<str>)>,
    ) -> Result<Rc<Package>, String> {
        if let Some(p) = self.packages.borrow().get(name) {
            return Ok(p.clone());
        }
        *self
            .stats
            .borrow_mut()
            .package_loads
            .entry(name.to_string())
            .or_default() += 1;
        let sources = loader.load(name)?;
        let mut files = Vec::with_capacity(sources.len());
        let mut paths = Vec::with_capacity(sources.len());
        for (label, src) in sources {
            let path = PathBuf::from(&label);
            match overlay(&path) {
                Some((c, buffer)) => {
                    paths.push(c);
                    files.push((label, buffer));
                }
                None => {
                    paths.push(crate::canonical(&path));
                    files.push((label, Rc::from(src)));
                }
            }
        }
        let package = Rc::new(Package {
            name: name.to_string(),
            files,
            canonical: paths,
        });
        self.packages
            .borrow_mut()
            .insert(name.to_string(), package.clone());
        Ok(package)
    }

    pub(crate) fn loaded(&self) -> Vec<Rc<Package>> {
        self.packages.borrow().values().cloned().collect()
    }

    pub(crate) fn drop_packages_holding(&self, path: &Path) -> bool {
        let mut packages = self.packages.borrow_mut();
        let before = packages.len();
        packages.retain(|_, p| !p.canonical.iter().any(|c| c == path));
        packages.len() != before
    }

    pub(crate) fn available(&self, loader: &dyn Loader) -> Vec<String> {
        self.available.get_or_init(|| loader.available()).clone()
    }
}

/// The loader the check stage is handed: every answer from the memo, every
/// miss through the engine's own loader, once.
pub(crate) struct MemoLoader<'e> {
    pub(crate) engine: &'e Engine,
    pub(crate) entry: &'e str,
}

impl Loader for MemoLoader<'_> {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        let package = self.engine.package(name)?;
        Ok(package
            .files
            .iter()
            .map(|(label, text)| (label.clone(), text.to_string()))
            .collect())
    }

    fn parse(&self, src: &str) -> Result<Vec<Spanned>, ParseError> {
        self.engine
            .memo
            .parse(src, src != self.entry)
            .as_ref()
            .clone()
    }

    fn entry_package(&self, path: &Path) -> Option<String> {
        let dir = path.parent().unwrap_or(Path::new("")).to_path_buf();
        if let Some(hit) = self.engine.memo.entry_packages.borrow().get(&dir) {
            return hit.clone();
        }
        let found = self.engine.loader.entry_package(path);
        self.engine
            .memo
            .entry_packages
            .borrow_mut()
            .insert(dir, found.clone());
        found
    }

    fn needs(&self, package: &str, entry_dir: Option<&Path>) -> Option<BTreeSet<String>> {
        let k = (package.to_string(), entry_dir.map(Path::to_path_buf));
        if let Some(hit) = self.engine.memo.needs.borrow().get(&k) {
            return hit.clone();
        }
        let found = self.engine.loader.needs(package, entry_dir);
        self.engine.memo.needs.borrow_mut().insert(k, found.clone());
        found
    }

    fn version(&self, package: &str, entry_dir: Option<&Path>) -> Option<String> {
        let k = (package.to_string(), entry_dir.map(Path::to_path_buf));
        if let Some(hit) = self.engine.memo.versions.borrow().get(&k) {
            return hit.clone();
        }
        let found = self.engine.loader.version(package, entry_dir);
        self.engine
            .memo
            .versions
            .borrow_mut()
            .insert(k, found.clone());
        found
    }

    fn available(&self) -> Vec<String> {
        self.engine.available()
    }
}
