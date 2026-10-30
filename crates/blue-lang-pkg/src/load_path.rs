//! `BLUE_PATH` — where a bidama is found, and the seam nix plugs into.
//!
//! ## The layout is the contract
//!
//! A *root* is a directory whose immediate children are packages:
//!
//! ```text
//! <root>/kazu/kazu.b
//! <root>/retsu/retsu.b
//! ```
//!
//! `BLUE_PATH` is a `:`-separated list of roots, searched left to right, first
//! match wins — the same shape as `PATH`, chosen because it is the one search
//! convention every operator already knows, and because "first match wins" is
//! what makes a local override possible without a flag.
//!
//! **That layout is not a coincidence — it is exactly what `bidamas/` is on
//! disk and exactly what `bidamas/mk-bidama.nix` builds.** A bidama derivation
//! produces `$out/<name>/`, so a store path IS a valid root with no adapter,
//! no manifest translation and no install step:
//!
//! ```text
//! BLUE_PATH=$(nix build --no-link --print-out-paths .#retsu)
//! ```
//!
//! That is the whole of "nix is blue's packaging system". Nix builds the
//! package, its output layout is the load layout, and the runtime finds it by
//! looking. Nothing here knows it is talking to a store path, which is the
//! point: the same loader reads a working tree during development and a
//! content-addressed store path in a build, so what runs in CI is what ran on
//! the laptop.
//!
//! ## Where a program looks, in order
//!
//! [`Environment::load_path`] is the one constructor of a load path. Every
//! door that runs, checks or reads a file (`blue FILE`, `run`, `test`,
//! `check`, `ast`, `explain-name`, `lsp`, `repl`) gets its loader from it,
//! through [`LoadPath::for_entry`] or, in the editor, per document through
//! the [`Scopes`] it implements:
//!
//! 1. **`BLUE_PATH`**, left to right: the caller's explicit override.
//! 2. **The project the file sits in**: walking up from the file, the first
//!    Bluefile that is a project's contributes its `packages(dir)` roots; a
//!    bidama's own Bluefile on the way contributes the directory that holds
//!    it (its distribution) and the walk goes on. In the editor, a document
//!    outside every project takes the projects of the workspace folders.
//! 3. **`BLUE_DIST`**, left to right: the installed distribution, which the
//!    fleet's wrapper (`mkBlueWithBidamas`) sets. It is not a caller's
//!    choice, so it never shadows the project: a bidama newer than the pin
//!    resolves in the repository that defines it.
//! 4. **The standard distribution compiled into the binary**
//!    ([`crate::embedded`], feature `embedded`, which the `blue` CLI turns
//!    on), so a bare script with no Bluefile and no `BLUE_PATH` can
//!    `use("retsu")`.
//!
//! First match wins, so a checkout on `BLUE_PATH` still overrides a project's
//! package, the project overrides the installed distribution, and every root
//! overrides the compiled-in copy. A wrapper built before `BLUE_DIST` existed
//! appended the distribution to `BLUE_PATH`; that form is still read, with
//! its old meaning (an override).
//!
//! A bidama that is not found names every root searched, in order and by
//! channel, and when a directory near the file holds it off the path, says
//! which Bluefile line puts it there.
//!
//! ## What this deliberately does NOT do
//!
//! It does not resolve versions. A root holds one directory per name, so the
//! *choice* of which version to expose is made when the root is built — by
//! nix, from a flake input, with a lock. Selection only refuses: outside the
//! project, a copy whose version falls outside the range the file's
//! `Bluefile.lock` records is skipped with a note, never chosen silently. Putting a solver here as well would
//! be a second resolution mechanism disagreeing with the first, which is the
//! failure mode `docs/COMPETING-LANGUAGES.md` §1 takes from Go: resolve in one
//! place, pin in another, never both in both.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::rc::Rc;

use blue_lang_runtime::uses::{Loader, Scopes};

use crate::version::{Range, Version};

/// The environment variable that names the caller's override roots.
pub const BLUE_PATH: &str = "BLUE_PATH";

/// The environment variable that names the installed distribution's roots.
pub const BLUE_DIST: &str = "BLUE_DIST";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Channel {
    Project,
    Override,
    Distribution,
    Given,
}

impl Channel {
    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            Self::Project => "the project",
            Self::Override => BLUE_PATH,
            Self::Distribution => BLUE_DIST,
            Self::Given => "roots",
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct Environment {
    overrides: Vec<PathBuf>,
    distribution: Vec<PathBuf>,
    workspace: Vec<PathBuf>,
}

fn split_roots(var: &std::ffi::OsStr) -> Vec<PathBuf> {
    var.to_string_lossy()
        .split(':')
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .collect()
}

fn dir_of(entry: &Path) -> PathBuf {
    let dir = entry
        .parent()
        .filter(|d| !d.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    dir.canonicalize().unwrap_or_else(|_| dir.to_path_buf())
}

fn manifest_dir(entry: &Path) -> PathBuf {
    let dir = dir_of(entry);
    dir.ancestors()
        .find(|at| at.join(crate::MANIFEST_FILE).is_file())
        .map_or(dir.clone(), Path::to_path_buf)
}

impl Environment {
    #[must_use]
    pub fn from_env() -> Self {
        Self::from_vars(
            std::env::var_os(BLUE_PATH).unwrap_or_default().as_os_str(),
            std::env::var_os(BLUE_DIST).unwrap_or_default().as_os_str(),
        )
    }

    #[must_use]
    pub fn from_vars(blue_path: &std::ffi::OsStr, blue_dist: &std::ffi::OsStr) -> Self {
        Self {
            overrides: split_roots(blue_path),
            distribution: split_roots(blue_dist),
            workspace: Vec::new(),
        }
    }

    #[must_use]
    pub fn with_workspace(mut self, folders: Vec<PathBuf>) -> Self {
        self.workspace = folders;
        self
    }

    #[must_use]
    pub fn installed_roots(&self) -> Vec<PathBuf> {
        self.overrides
            .iter()
            .chain(&self.distribution)
            .cloned()
            .collect()
    }

    #[must_use]
    pub fn project(&self, entry: Option<&Path>) -> Vec<PathBuf> {
        let own = entry.map(project_roots).unwrap_or_default();
        if !own.is_empty() {
            return own;
        }
        let mut roots: Vec<PathBuf> = Vec::new();
        for folder in &self.workspace {
            for r in project_roots(&folder.join(crate::MANIFEST_FILE)) {
                if !roots.contains(&r) {
                    roots.push(r);
                }
            }
        }
        roots
    }

    #[must_use]
    pub fn load_path(&self, entry: Option<&Path>) -> LoadPath {
        let mut lp = LoadPath::default();
        lp.push(Channel::Project, &self.project(entry));
        lp.push(Channel::Override, &self.overrides);
        lp.push(Channel::Distribution, &self.distribution);
        match entry {
            Some(e) => {
                lp.origin = vec![dir_of(e)];
                lp.required = required_by(&manifest_dir(e));
            }
            None => lp.origin = lp.roots_of(Channel::Project),
        }
        lp.standard = true;
        lp
    }
}

impl Scopes for Environment {
    fn scope(&self, entry: Option<&Path>) -> Vec<PathBuf> {
        entry.map(|e| vec![manifest_dir(e)]).unwrap_or_default()
    }

    fn loader(&self, scope: &[PathBuf]) -> Rc<dyn Loader> {
        let entry = scope.first().map(|d| d.join(crate::MANIFEST_FILE));
        Rc::new(self.load_path(entry.as_deref()))
    }

    fn set_workspace(&mut self, folders: Vec<PathBuf>) {
        self.workspace = folders;
    }
}

fn required_by(dir: &Path) -> BTreeMap<String, Range> {
    crate::lock::locked_needs(dir)
        .or_else(|| {
            std::fs::read_to_string(dir.join(crate::MANIFEST_FILE))
                .ok()
                .and_then(|t| crate::bluefile::read_bluefile(&t).ok())
                .map(|bf| bf.manifest.needs)
        })
        .unwrap_or_default()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Found {
    Dir(PathBuf),
    Standard,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Selection {
    pub found: Option<Found>,
    pub skipped: Vec<String>,
}

/// An ordered list of directories to find bidamas in, with where each came
/// from. Built by [`Environment::load_path`]; a fixed list of roots is a
/// test fixture (feature `fixture`).
#[derive(Debug, Clone, Default)]
pub struct LoadPath {
    roots: Vec<PathBuf>,
    channels: Vec<Channel>,
    standard: bool,
    origin: Vec<PathBuf>,
    required: BTreeMap<String, Range>,
}

impl LoadPath {
    pub(crate) fn over(roots: impl IntoIterator<Item = PathBuf>) -> Self {
        let mut lp = Self::default();
        lp.push(Channel::Given, &roots.into_iter().collect::<Vec<_>>());
        lp
    }

    #[cfg(any(test, feature = "fixture"))]
    #[must_use]
    pub fn new(roots: impl IntoIterator<Item = PathBuf>) -> Self {
        Self::over(roots)
    }

    #[cfg(any(test, feature = "fixture"))]
    #[must_use]
    pub fn from_var(var: &std::ffi::OsStr) -> Self {
        Self::over(split_roots(var))
    }

    #[cfg(any(test, feature = "fixture"))]
    #[must_use]
    pub fn with_standard(mut self) -> Self {
        self.standard = true;
        self
    }

    #[must_use]
    pub fn unpinned(mut self) -> Self {
        self.required.clear();
        self
    }

    #[cfg(any(test, feature = "fixture"))]
    #[must_use]
    pub fn requiring(mut self, name: &str, range: &str) -> Self {
        if let Ok(r) = Range::parse(range) {
            self.required.insert(name.to_string(), r);
        }
        self
    }

    fn push(&mut self, channel: Channel, roots: &[PathBuf]) {
        for r in roots {
            if !self.roots.contains(r) {
                self.roots.push(r.clone());
                self.channels.push(channel);
            }
        }
    }

    fn roots_of(&self, channel: Channel) -> Vec<PathBuf> {
        self.roots
            .iter()
            .zip(&self.channels)
            .filter(|(_, c)| **c == channel)
            .map(|(r, _)| r.clone())
            .collect()
    }

    /// The load path of a program at `entry`, from [`Environment::load_path`].
    /// The module docs state the order.
    #[must_use]
    pub fn for_entry(entry: &Path) -> Self {
        Environment::from_env().load_path(Some(entry))
    }

    #[must_use]
    pub fn for_dir(dir: &Path) -> Self {
        Self::for_entry(&dir.join(crate::MANIFEST_FILE))
    }

    /// The roots, in search order.
    #[must_use]
    pub fn roots(&self) -> &[PathBuf] {
        &self.roots
    }

    #[must_use]
    pub fn channels(&self) -> &[Channel] {
        &self.channels
    }

    #[must_use]
    pub fn select(&self, name: &str) -> Selection {
        let mut skipped = Vec::new();
        let range = self.required.get(name);
        for (root, channel) in self.roots.iter().zip(&self.channels) {
            let dir = root.join(name);
            if !dir.is_dir() {
                continue;
            }
            if *channel == Channel::Project {
                return Selection {
                    found: Some(Found::Dir(dir)),
                    skipped,
                };
            }
            match (range, version_at(&dir)) {
                (Some(r), Some(v)) if !r.contains(v) => skipped.push(format!(
                    "{} is {name} {v}, outside the lock's {r}",
                    dir.display()
                )),
                _ => {
                    return Selection {
                        found: Some(Found::Dir(dir)),
                        skipped,
                    }
                }
            }
        }
        let s = crate::embedded::Standard;
        if self.standard && s.has(name) {
            let v = s.version(name, None).and_then(|v| Version::parse(&v).ok());
            match (range, v) {
                (Some(r), Some(v)) if !r.contains(v) => skipped.push(format!(
                    "the standard distribution compiled into blue has {name} {v}, outside the lock's {r}"
                )),
                _ => {
                    return Selection {
                        found: Some(Found::Standard),
                        skipped,
                    }
                }
            }
        }
        Selection {
            found: None,
            skipped,
        }
    }

    /// The directory holding `name`, or `None` (also when the compiled-in
    /// standard answers).
    #[must_use]
    pub fn resolve(&self, name: &str) -> Option<PathBuf> {
        match self.select(name).found {
            Some(Found::Dir(d)) => Some(d),
            _ => None,
        }
    }

    fn not_found(&self, name: &str, skipped: &[String]) -> String {
        let mut where_looked = if self.roots.is_empty() {
            format!("the project, {BLUE_PATH} and {BLUE_DIST} name no root")
        } else {
            let mut parts: Vec<String> = Vec::new();
            let mut i = 0;
            while i < self.roots.len() {
                let channel = self.channels[i];
                let mut group = Vec::new();
                while i < self.roots.len() && self.channels[i] == channel {
                    group.push(self.roots[i].display().to_string());
                    i += 1;
                }
                parts.push(format!("{} {}", channel.label(), group.join(", ")));
            }
            format!("searched: {}", parts.join(", then "))
        };
        if self.standard {
            where_looked.push_str(", then the standard distribution compiled into blue");
        }
        let mut msg = format!("no bidama named \"{name}\" ({where_looked})");
        for note in skipped {
            msg.push_str("; skipped ");
            msg.push_str(note);
        }
        if let Some(fix) = self.nearby(name) {
            msg.push_str(". ");
            msg.push_str(&fix);
        }
        msg
    }

    fn nearby(&self, name: &str) -> Option<String> {
        let mut seen = BTreeSet::new();
        for origin in &self.origin {
            let origin = origin.canonicalize().unwrap_or_else(|_| origin.clone());
            for at in origin.ancestors() {
                for root in [at.to_path_buf(), at.join("bidamas")] {
                    let dir = root.join(name);
                    if !seen.insert(dir.clone()) || !dir.join(crate::MANIFEST_FILE).is_file() {
                        continue;
                    }
                    return Some(match project_of(&origin) {
                        Some(project) => format!(
                            "fix: {} holds it and is not on this path; add `packages(\"{}\")` to {}",
                            dir.display(),
                            relative(&root, &project),
                            project.join(crate::MANIFEST_FILE).display()
                        ),
                        None => format!(
                            "fix: {} holds it and no project Bluefile around the file names it; add a Bluefile with `packages(\"{}\")` above the file, or put {} on {BLUE_PATH}",
                            dir.display(),
                            root.display(),
                            root.display()
                        ),
                    });
                }
                if at.join(".git").exists() {
                    break;
                }
            }
        }
        None
    }
}

fn version_at(dir: &Path) -> Option<Version> {
    let text = std::fs::read_to_string(dir.join(crate::MANIFEST_FILE)).ok()?;
    Some(crate::bluefile::read_bluefile(&text).ok()?.version)
}

pub(crate) fn project_of(dir: &Path) -> Option<PathBuf> {
    dir.ancestors()
        .find(|at| {
            std::fs::read_to_string(at.join(crate::MANIFEST_FILE))
                .ok()
                .and_then(|t| crate::bluefile::read_bluefile(&t).ok())
                .is_some_and(|bf| bidama_of(&bf).is_none())
        })
        .map(Path::to_path_buf)
}

fn relative(root: &Path, project: &Path) -> String {
    let mut up = PathBuf::new();
    for at in project.ancestors() {
        if let Ok(rest) = root.strip_prefix(at) {
            let rel = up.join(rest);
            return if rel.as_os_str().is_empty() {
                ".".to_string()
            } else {
                rel.display().to_string()
            };
        }
        up.push("..");
    }
    root.display().to_string()
}

/// The bidama a Bluefile declares, if it declares one: its name is one
/// identifier (so `name::x` is a qualified name; a project's, like
/// `blue-repository`, is not) and it holds no `packages` roots, which only a
/// project does. A project may be named like a bidama (`nupastel`); its
/// `packages` still say it is the project.
pub(crate) fn bidama_of(bf: &crate::Bluefile) -> Option<&str> {
    let one_identifier =
        blue_lang_syntax::qualified(&blue_lang_syntax::qualify(&bf.name, "x")).is_some();
    (one_identifier && bf.project.packages.is_empty()).then_some(bf.name.as_str())
}

/// The package roots of the project a file at `entry` belongs to.
///
/// Walking up from the file's directory, each `Bluefile` is read:
///
/// - a bidama's ([`bidama_of`]) adds the directory holding the bidama, the
///   distribution it sits in, and the walk goes on, since a package inside a
///   project resolves its siblings through the project;
/// - a project's adds its `packages(dir)` roots, relative to it, in
///   declaration order, and ends the walk. A project without `packages` ends
///   it too: the nearest project owns the file, never one further out.
///
/// A Bluefile that does not evaluate ends the walk adding nothing; `blue
/// bluefile --json` reports why. `source(...)` roots are not here: they are
/// fetched by nix, and reach a run through the project's runner or
/// `BLUE_PATH`.
#[must_use]
pub fn project_roots(entry: &Path) -> Vec<PathBuf> {
    let dir = entry
        .parent()
        .filter(|d| !d.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let dir = dir.canonicalize().unwrap_or_else(|_| dir.to_path_buf());
    let mut roots: Vec<PathBuf> = Vec::new();
    for at in dir.ancestors() {
        let Ok(text) = std::fs::read_to_string(at.join(crate::MANIFEST_FILE)) else {
            continue;
        };
        let Ok(bf) = crate::bluefile::read_bluefile(&text) else {
            break;
        };
        if bidama_of(&bf).is_some() {
            if let Some(parent) = at.parent() {
                roots.push(parent.to_path_buf());
            }
            continue;
        }
        roots.extend(bf.project.packages.iter().map(|p| at.join(p)));
        break;
    }
    let mut seen = std::collections::BTreeSet::new();
    roots.retain(|r| seen.insert(r.canonicalize().unwrap_or_else(|_| r.clone())));
    roots
}

/// Read every `.b` file in a package directory, sorted by filename.
///
/// Sorted because `read_dir` order is filesystem-dependent, and a package
/// whose definitions load in a different order on a different machine is the
/// kind of difference that shows up once, in production, on the machine you do
/// not have. Sorting costs nothing and removes the class.
fn read_sources(dir: &Path) -> Result<Vec<(String, String)>, String> {
    let mut out = Vec::new();
    let entries =
        std::fs::read_dir(dir).map_err(|e| format!("cannot read {}: {e}", dir.display()))?;
    for entry in entries.filter_map(Result::ok) {
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("b") {
            continue;
        }
        let src = std::fs::read_to_string(&path)
            .map_err(|e| format!("cannot read {}: {e}", path.display()))?;
        // A dependency compiles as written: its form is its producer's, and
        // the loader never writes. `crate::canonical` holds the rule.
        let src = crate::canonical::admit_dependency(&path, src).map_err(|e| e.to_string())?;
        out.push((path.display().to_string(), src));
    }
    out.sort();
    Ok(out)
}

impl Loader for LoadPath {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        let selection = self.select(name);
        let dir = match selection.found {
            Some(Found::Standard) => return crate::embedded::Standard.load(name),
            Some(Found::Dir(d)) => d,
            None => return Err(self.not_found(name, &selection.skipped)),
        };

        // A package is what its Bluefile says it is: `use("x")` loading a
        // directory whose Bluefile declares `package("y")` would put y's
        // definitions under x's name. And `blue` names the builtins.
        if name == blue_lang_syntax::BUILTIN_QUALIFIER {
            return Err(format!(
                "no bidama may be named \"{name}\": `{name}::` names the builtins"
            ));
        }
        if let Ok(text) = std::fs::read_to_string(dir.join("Bluefile")) {
            if let Ok(bf) = crate::bluefile::read_bluefile(&text) {
                if bf.name != name {
                    return Err(format!(
                        "bidama \"{name}\" at {} declares package(\"{}\"): a package's directory and its Bluefile name it the same",
                        dir.display(),
                        bf.name
                    ));
                }
            }
        }
        let sources = read_sources(&dir)?;
        if sources.is_empty() {
            // A directory with no `.b` files resolves happily and contributes
            // nothing, so the importer fails later with an unbound symbol
            // pointing at their own code. Fail here, where the cause is.
            return Err(format!(
                "bidama \"{name}\" at {} contains no .b source",
                dir.display()
            ));
        }
        Ok(sources)
    }

    fn needs(&self, package: &str, entry_dir: Option<&Path>) -> Option<BTreeSet<String>> {
        let dir = match (entry_dir, self.select(package).found) {
            (Some(d), _) => d.to_path_buf(),
            (None, Some(Found::Standard)) => return crate::embedded::Standard.needs(package, None),
            (None, Some(Found::Dir(d))) => d,
            (None, None) => return None,
        };
        if let Some(locked) = crate::lock::locked_needs(&dir) {
            return Some(locked.into_keys().collect());
        }
        let text = std::fs::read_to_string(dir.join("Bluefile")).ok()?;
        let bf = crate::bluefile::read_bluefile(&text).ok()?;
        Some(bf.manifest.needs.keys().cloned().collect())
    }

    fn version(&self, package: &str, entry_dir: Option<&Path>) -> Option<String> {
        let dir = match (entry_dir, self.select(package).found) {
            (Some(d), _) => d.to_path_buf(),
            (None, Some(Found::Standard)) => {
                return crate::embedded::Standard.version(package, None)
            }
            (None, Some(Found::Dir(d))) => d,
            (None, None) => return None,
        };
        version_at(&dir).map(|v| v.to_string())
    }

    /// Every bidama a root holds (a directory with a Bluefile), then, when
    /// the standard distribution answers after the roots, every one of its.
    fn available(&self) -> Vec<String> {
        let mut out = BTreeSet::new();
        for root in &self.roots {
            let Ok(entries) = std::fs::read_dir(root) else {
                continue;
            };
            for entry in entries.filter_map(Result::ok) {
                let dir = entry.path();
                let Some(name) = dir.file_name().and_then(|n| n.to_str()) else {
                    continue;
                };
                if dir.join("Bluefile").is_file() && name != blue_lang_syntax::BUILTIN_QUALIFIER {
                    out.insert(name.to_string());
                }
            }
        }
        if self.standard {
            out.extend(
                crate::embedded::Standard
                    .names()
                    .into_iter()
                    .map(str::to_string),
            );
        }
        out.into_iter().collect()
    }

    /// The `package(name, …)` of the Bluefile beside `path`, when it
    /// declares a bidama ([`bidama_of`]). A file beside a project's Bluefile
    /// is in the root namespace.
    fn frontend(&self, entry: &Path) -> Option<blue_lang_runtime::uses::Frontend> {
        crate::lock::frontend_of(entry)
    }

    fn entry_package(&self, path: &Path) -> Option<String> {
        let dir = path
            .parent()
            .filter(|d| !d.as_os_str().is_empty())
            .unwrap_or(Path::new("."));
        let text = std::fs::read_to_string(dir.join("Bluefile")).ok()?;
        let bf = crate::bluefile::read_bluefile(&text).ok()?;
        bidama_of(&bf).map(str::to_string)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The real distribution in this repo — not a fixture.
    fn dist() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("bidamas")
    }

    #[test]
    fn the_repos_own_distribution_is_a_valid_root() {
        let lp = LoadPath::new([dist()]);
        for pkg in ["kazu", "moji", "retsu"] {
            assert!(
                lp.resolve(pkg).is_some(),
                "{pkg} is in bidamas/ but the load path cannot find it — the \
                 directory layout and the loader's expectation have diverged"
            );
            let sources = lp.load(pkg).unwrap_or_else(|e| panic!("{pkg}: {e}"));
            assert!(!sources.is_empty(), "{pkg} loaded zero sources");
        }
    }

    #[test]
    fn a_missing_package_names_itself_and_where_we_looked() {
        let lp = LoadPath::new([dist()]);
        let err = lp.load("definitely-not-a-bidama").expect_err("must fail");
        assert!(err.contains("definitely-not-a-bidama"), "{err}");
        assert!(
            err.contains("bidamas"),
            "the error must say which roots were searched, or an empty \
             BLUE_PATH is indistinguishable from a typo: {err}"
        );
    }

    #[test]
    fn an_empty_path_says_so_rather_than_blaming_the_name() {
        let err = LoadPath::default().load("kazu").expect_err("must fail");
        assert!(
            err.contains(BLUE_PATH),
            "with no roots the error must name BLUE_PATH, since that is what \
             the operator has to fix: {err}"
        );
    }

    #[test]
    fn roots_are_searched_in_order_so_a_local_root_can_override() {
        // A root that does not hold the package must not stop the search.
        let lp = LoadPath::new([PathBuf::from("/nonexistent-root"), dist()]);
        assert!(
            lp.resolve("kazu").is_some(),
            "a non-matching first root ended the search; overriding by \
             prepending a root would be impossible"
        );
    }

    /// Every directory of the distribution with a Bluefile is a bidama the
    /// path can offer, counted against the directory itself, and a root that
    /// does not exist offers nothing rather than failing.
    #[test]
    fn available_lists_every_bidama_on_the_path() {
        let lp = LoadPath::new([PathBuf::from("/nonexistent-root"), dist()]);
        let listed = lp.available();
        let on_disk: Vec<String> = std::fs::read_dir(dist())
            .expect("bidamas/")
            .filter_map(Result::ok)
            .filter(|e| e.path().join("Bluefile").is_file())
            .filter_map(|e| e.file_name().to_str().map(str::to_string))
            .collect();
        assert!(on_disk.len() > 10, "{on_disk:?}");
        assert_eq!(listed.len(), on_disk.len(), "{listed:?}");
        for name in ["kazu", "retsu", "junjo"] {
            assert!(listed.iter().any(|n| n == name), "{name}: {listed:?}");
        }
        assert!(LoadPath::default().available().is_empty());
    }

    #[test]
    fn empty_segments_are_dropped_rather_than_meaning_the_cwd() {
        let lp = LoadPath::from_var(std::ffi::OsStr::new("/a::/b:"));
        assert_eq!(lp.roots().len(), 2, "{:?}", lp.roots());
    }

    /// End-to-end: the real distribution, through the real loader, CALLING an
    /// imported function.
    ///
    /// The call is what makes this non-vacuous. Asserting only that
    /// `use("kazu")` returns `Ok` passes just as well when the import brings
    /// in nothing at all — the program `use("kazu")` alone is valid whether or
    /// not a single definition arrived. `clamp` exists **only** inside kazu, so
    /// evaluating it to the right answer is the property that cannot hold by
    /// accident.
    #[test]
    fn an_imported_function_is_actually_callable() {
        let lp = LoadPath::new([dist()]);
        let run = blue_lang_runtime::pipeline::run_with_loader(
            "use(\"kazu\", [:clamp])\nclamp(99, 1, 10)",
            blue_lang_runtime::inputs::Inputs::new(),
            &lp,
        )
        .unwrap_or_else(|e| panic!("importing kazu and calling clamp must work: {e}"));
        assert!(
            matches!(run.value, tatara_lisp_eval::Value::Int(10)),
            "clamp(99, 1, 10) came back as {:?}; the definition did not arrive \
             from the bidama",
            run.value
        );
    }

    /// The same call WITHOUT the import must fail — the control.
    ///
    /// Without this, the test above could be green because `clamp` is a
    /// builtin, and the whole loader would be proving nothing.
    #[test]
    fn the_same_call_without_the_import_fails() {
        let lp = LoadPath::new([dist()]);
        let err = blue_lang_runtime::pipeline::run_with_loader(
            "clamp(99, 1, 10)",
            blue_lang_runtime::inputs::Inputs::new(),
            &lp,
        )
        .expect_err(
            "clamp resolved with no import — it is ambient, so the import test \
             above proves nothing about loading",
        );
        let _ = err;
    }

    /// A scratch tree of files, removed and recreated per test name.
    fn tree(name: &str, files: &[(&str, &str)]) -> PathBuf {
        let root = std::env::temp_dir().join(format!("blue-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        for (rel, text) in files {
            let p = root.join(rel);
            std::fs::create_dir_all(p.parent().unwrap()).expect("mkdir");
            std::fs::write(p, text).expect("write");
        }
        root.canonicalize().expect("canonical root")
    }

    /// The project around a file supplies its `packages` roots: from a script
    /// beside the Bluefile, from a subdirectory, and from inside one of its
    /// own packages (whose distribution is the same root, listed once).
    #[test]
    fn a_file_in_a_project_finds_the_projects_package_roots() {
        let root = tree(
            "project-roots",
            &[
                (
                    "proj/Bluefile",
                    "package(\"my-proj\", \"0.1.0\")\npackages(\"pkgs\")\n",
                ),
                ("proj/pkgs/foo/Bluefile", "package(\"foo\", \"0.1.0\")\n"),
                ("proj/pkgs/foo/foo.b", "def f()\n  1\nend\n"),
            ],
        );
        let pkgs = vec![root.join("proj/pkgs")];
        assert_eq!(project_roots(&root.join("proj/main.b")), pkgs);
        assert_eq!(project_roots(&root.join("proj/deep/er/x.b")), pkgs);
        assert_eq!(project_roots(&root.join("proj/pkgs/foo/foo.b")), pkgs);
        assert!(project_roots(&root.join("elsewhere.b")).is_empty());
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The nearest project owns a file: an outer project's packages are not
    /// reached through an inner project that declares none.
    #[test]
    fn the_nearest_project_owns_the_file() {
        let root = tree(
            "nearest-project",
            &[
                (
                    "outer/Bluefile",
                    "package(\"outer-proj\", \"0.1.0\")\npackages(\"pkgs\")\n",
                ),
                (
                    "outer/inner/Bluefile",
                    "package(\"inner-proj\", \"0.1.0\")\n",
                ),
            ],
        );
        assert!(project_roots(&root.join("outer/inner/s.b")).is_empty());
        assert_eq!(
            project_roots(&root.join("outer/s.b")),
            vec![root.join("outer/pkgs")]
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// With the standard distribution compiled in, a load path with no roots
    /// still serves retsu; without the fallback it does not (the control).
    #[cfg(feature = "embedded")]
    #[test]
    fn the_standard_distribution_answers_after_every_root() {
        assert!(LoadPath::default().load("retsu").is_err());
        let lp = LoadPath::default().with_standard();
        let retsu = lp
            .load("retsu")
            .expect("retsu from the compiled-in distribution");
        assert!(retsu.iter().any(|(l, _)| l == "retsu/retsu.b"));
        assert_eq!(lp.version("kazu", None), Some("0.1.0".to_string()));
        let err = lp.load("definitely-not-a-bidama").expect_err("absent");
        assert!(err.contains("standard distribution"), "{err}");
    }

    /// A root holding a package beats the compiled-in copy of it.
    #[cfg(feature = "embedded")]
    #[test]
    fn a_root_overrides_the_compiled_in_package() {
        let root = tree(
            "override-standard",
            &[
                ("retsu/Bluefile", "package(\"retsu\", \"9.9.9\")\n"),
                ("retsu/retsu.b", "def precedence_marker()\n  42\nend\n"),
            ],
        );
        let lp = LoadPath::new([root.clone()]).with_standard();
        let src = lp.load("retsu").expect("the root's retsu");
        assert!(src.iter().any(|(_, t)| t.contains("precedence_marker")));
        assert_eq!(lp.version("retsu", None), Some("9.9.9".to_string()));
        let _ = std::fs::remove_dir_all(&root);
    }

    /// **A package is what its Bluefile names**, and none is named `blue`.
    ///
    /// Red run (2026-09-29), before the identity check: `use("mislabel")`
    /// loaded a directory declaring `package("other")` under mislabel's name.
    #[test]
    fn a_package_is_what_its_bluefile_names_and_none_is_blue() {
        let root = std::env::temp_dir().join(format!("blue-identity-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        for (dir, pkg) in [("mislabel", "other"), ("blue", "blue")] {
            std::fs::create_dir_all(root.join(dir)).expect("mkdir");
            std::fs::write(
                root.join(dir).join("Bluefile"),
                format!("package(\"{pkg}\", \"0.1.0\")\n"),
            )
            .expect("write");
            std::fs::write(
                root.join(dir).join(format!("{dir}.b")),
                "def f()\n  1\nend\n",
            )
            .expect("write");
        }
        let lp = LoadPath::new([root.clone()]);
        let e = lp.load("mislabel").expect_err("a mislabelled package");
        assert!(e.contains("declares package(\"other\")"), "{e}");
        let e = lp.load("blue").expect_err("blue is reserved");
        assert!(e.contains("no bidama may be named"), "{e}");
        let _ = std::fs::remove_dir_all(&root);
    }

    fn two_copies(name: &str) -> PathBuf {
        tree(
            name,
            &[
                (
                    "proj/Bluefile",
                    "package(\"sel-proj\", \"0.1.0\")\npackages(\"bidamas\")\n",
                ),
                (
                    "proj/bidamas/pick/Bluefile",
                    "package(\"pick\", \"0.2.0\")\n",
                ),
                ("proj/bidamas/pick/pick.b", "def p()\n  2\nend\n"),
                ("stale/pick/Bluefile", "package(\"pick\", \"0.0.9\")\n"),
                ("stale/pick/pick.b", "def p()\n  0\nend\n"),
                ("good/pick/Bluefile", "package(\"pick\", \"0.1.4\")\n"),
                ("good/pick/pick.b", "def p()\n  1\nend\n"),
                (
                    "user/Bluefile",
                    "package(\"user\", \"0.1.0\")\nneeds(\"pick\", \"^0.1\")\n",
                ),
                ("user/user.b", "use(\"pick\")\n"),
            ],
        )
    }

    fn env(path: &[&Path], dist: &[&Path]) -> Environment {
        let join = |ps: &[&Path]| {
            ps.iter()
                .map(|p| p.display().to_string())
                .collect::<Vec<_>>()
                .join(":")
        };
        Environment::from_vars(
            std::ffi::OsStr::new(&join(path)),
            std::ffi::OsStr::new(&join(dist)),
        )
    }

    #[test]
    fn the_files_project_wins_over_every_installed_copy() {
        let root = two_copies("sel-project");
        let lp = env(&[&root.join("stale")], &[&root.join("good")])
            .load_path(Some(&root.join("proj/main.b")));
        assert_eq!(
            lp.select("pick").found,
            Some(Found::Dir(root.join("proj/bidamas/pick")))
        );
        assert_eq!(lp.channels()[0], Channel::Project);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_copy_outside_the_lock_is_skipped_with_a_note_never_chosen() {
        let root = two_copies("sel-lock");
        let entry = root.join("user/user.b");
        let lp = env(&[&root.join("stale")], &[&root.join("good")]).load_path(Some(&entry));
        let sel = lp.select("pick");
        assert_eq!(sel.found, Some(Found::Dir(root.join("good/pick"))));
        assert_eq!(sel.skipped.len(), 1, "{sel:?}");
        assert!(sel.skipped[0].contains("0.0.9"), "{sel:?}");
        let only_stale = env(&[&root.join("stale")], &[]).load_path(Some(&entry));
        let err = only_stale.load("pick").expect_err("only a stale copy");
        assert!(err.contains("skipped"), "{err}");
        assert!(err.contains("outside the lock's ^0.1"), "{err}");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn with_no_project_and_no_lock_the_first_root_answers() {
        let root = two_copies("sel-none");
        let lp = env(&[&root.join("stale")], &[&root.join("good")])
            .load_path(Some(&root.join("loose.b")));
        assert_eq!(
            lp.select("pick").found,
            Some(Found::Dir(root.join("stale/pick")))
        );
        assert!(lp.select("pick").skipped.is_empty());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[cfg(feature = "embedded")]
    #[test]
    fn the_compiled_in_copy_outside_the_lock_is_skipped_too() {
        let lp = LoadPath::default().with_standard().requiring("retsu", "^9");
        let err = lp.load("retsu").expect_err("compiled-in retsu is not 9.x");
        assert!(err.contains("compiled into blue has retsu"), "{err}");
    }

    #[test]
    fn each_document_scope_resolves_through_its_own_project() {
        let a = two_copies("scope-a");
        let b = tree(
            "scope-b",
            &[
                (
                    "proj/Bluefile",
                    "package(\"sel-other\", \"0.1.0\")\npackages(\"libs\")\n",
                ),
                ("proj/libs/pick/Bluefile", "package(\"pick\", \"0.3.0\")\n"),
                ("proj/libs/pick/pick.b", "def p()\n  3\nend\n"),
            ],
        );
        let e = Environment::default();
        let sa = e.scope(Some(&a.join("proj/x.b")));
        let sb = e.scope(Some(&b.join("proj/y.b")));
        assert_ne!(sa, sb);
        assert_eq!(
            e.loader(&sa).version("pick", None),
            Some("0.2.0".to_string())
        );
        assert_eq!(
            e.loader(&sb).version("pick", None),
            Some("0.3.0".to_string())
        );
        let ws = Environment::default().with_workspace(vec![b.join("proj")]);
        assert_eq!(
            ws.load_path(None).select("pick").found,
            Some(Found::Dir(b.join("proj/libs/pick")))
        );
        let _ = std::fs::remove_dir_all(&a);
        let _ = std::fs::remove_dir_all(&b);
    }
}
