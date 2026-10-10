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
//! [`LoadPath::for_entry`] is the load path of every door that runs or checks
//! a file (`blue FILE`, `run`, `test`, `check`, `ast`, `explain-name`):
//!
//! 1. **`BLUE_PATH`**, left to right: the caller's choice, and where the
//!    fleet's wrapper appends the pinned distribution.
//! 2. **The project the file sits in**: walking up from the file, the first
//!    Bluefile that is a project's contributes its `packages(dir)` roots; a
//!    bidama's own Bluefile on the way contributes the directory that holds
//!    it (its distribution) and the walk goes on.
//! 3. **The standard distribution compiled into the binary**
//!    ([`crate::embedded`], feature `embedded`, which the `blue` CLI turns
//!    on), so a bare script with no Bluefile and no `BLUE_PATH` can
//!    `use("retsu")`.
//!
//! First match wins, so a checkout on `BLUE_PATH` still overrides a project's
//! package, and either overrides the compiled-in copy.
//!
//! ## What this deliberately does NOT do
//!
//! It does not resolve versions. A root holds one directory per name, so the
//! *choice* of which version to expose is made when the root is built — by
//! nix, from a flake input, with a lock. Putting a solver here as well would
//! be a second resolution mechanism disagreeing with the first, which is the
//! failure mode `docs/COMPETING-LANGUAGES.md` §1 takes from Go: resolve in one
//! place, pin in another, never both in both.

use std::path::{Path, PathBuf};

use blue_lang_runtime::uses::Loader;

/// The environment variable that names the search roots.
pub const BLUE_PATH: &str = "BLUE_PATH";

/// An ordered list of directories to find bidamas in.
#[derive(Debug, Clone, Default)]
pub struct LoadPath {
    roots: Vec<PathBuf>,
    /// Whether the compiled-in standard distribution answers after `roots`.
    standard: bool,
}

impl LoadPath {
    /// A load path over the given roots, searched in order.
    #[must_use]
    pub fn new(roots: impl IntoIterator<Item = PathBuf>) -> Self {
        Self {
            roots: roots.into_iter().collect(),
            standard: false,
        }
    }

    /// The load path of a program at `entry`: `BLUE_PATH`, then the roots of
    /// the project around it ([`project_roots`]), then the standard
    /// distribution compiled into the binary. The module docs state the order.
    #[must_use]
    pub fn for_entry(entry: &Path) -> Self {
        let mut lp = Self::from_env();
        lp.roots.extend(project_roots(entry));
        lp.with_standard()
    }

    /// This load path, falling back to the standard distribution compiled into
    /// the binary when no root holds a package. Without the `embedded` feature
    /// nothing is compiled in and the fallback finds nothing.
    #[must_use]
    pub fn with_standard(mut self) -> Self {
        self.standard = true;
        self
    }

    /// The load path `BLUE_PATH` describes, or an empty one if it is unset.
    ///
    /// Empty rather than an error: a program with no imports must run with no
    /// packaging configured at all, and forcing every caller to handle a
    /// "BLUE_PATH unset" error would make the common case pay for the rare
    /// one. An import against an empty path fails then, naming the package.
    #[must_use]
    pub fn from_env() -> Self {
        Self::from_var(std::env::var_os(BLUE_PATH).unwrap_or_default().as_os_str())
    }

    /// Parse a `:`-separated root list.
    ///
    /// Empty segments are dropped, because `"a::b"` and a trailing `:` are what
    /// shell string-building produces by accident, and an empty segment would
    /// otherwise resolve as the process's current directory — a surprising,
    /// cwd-dependent root nobody asked for.
    #[must_use]
    pub fn from_var(var: &std::ffi::OsStr) -> Self {
        Self::new(
            var.to_string_lossy()
                .split(':')
                .filter(|s| !s.is_empty())
                .map(PathBuf::from),
        )
    }

    /// The roots, in search order.
    #[must_use]
    pub fn roots(&self) -> &[PathBuf] {
        &self.roots
    }

    /// The directory holding `name`, or `None`.
    ///
    /// A root only counts as holding the package if the directory actually
    /// exists; an entry that is a file, or a name that is absent, is skipped
    /// so a later root still gets its chance.
    #[must_use]
    pub fn resolve(&self, name: &str) -> Option<PathBuf> {
        self.roots.iter().map(|r| r.join(name)).find(|p| p.is_dir())
    }

    /// The compiled-in standard distribution, when this path falls back to it
    /// and no root holds `name`.
    fn standard_for(&self, name: &str) -> Option<crate::embedded::Standard> {
        let s = crate::embedded::Standard;
        (self.standard && self.resolve(name).is_none() && s.has(name)).then_some(s)
    }
}

/// The bidama a Bluefile declares, if it declares one: its name is one
/// identifier (so `name::x` is a qualified name; a project's, like
/// `blue-repository`, is not) and it holds no `packages` roots, which only a
/// project does. A project may be named like a bidama (`nupastel`); its
/// `packages` still say it is the project.
fn bidama_of(bf: &crate::Bluefile) -> Option<&str> {
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
        // blue compiles only canonical source: a writable package file is
        // formatted in place first, a read-only one that is not canonical is
        // refused. `crate::canonical` holds the rule; this is the loader's door.
        let src = crate::canonical::admit(&path, src).map_err(|e| e.to_string())?;
        out.push((path.display().to_string(), src));
    }
    out.sort();
    Ok(out)
}

impl Loader for LoadPath {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        if let Some(s) = self.standard_for(name) {
            return s.load(name);
        }
        let Some(dir) = self.resolve(name) else {
            // Name the roots that were searched. "package not found" alone
            // leaves the reader unable to tell an empty BLUE_PATH from a
            // misspelled package — two problems with opposite fixes.
            let mut where_looked = if self.roots.is_empty() {
                format!("{BLUE_PATH} is empty or unset")
            } else {
                format!(
                    "searched: {}",
                    self.roots
                        .iter()
                        .map(|r| r.display().to_string())
                        .collect::<Vec<_>>()
                        .join(", ")
                )
            };
            if self.standard {
                where_looked.push_str(", then the standard distribution compiled into blue");
            }
            return Err(format!("no bidama named \"{name}\" ({where_looked})"));
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

    fn needs(
        &self,
        package: &str,
        entry_dir: Option<&Path>,
    ) -> Option<std::collections::BTreeSet<String>> {
        if entry_dir.is_none() {
            if let Some(s) = self.standard_for(package) {
                return s.needs(package, None);
            }
        }
        let dir = match entry_dir {
            Some(d) => d.to_path_buf(),
            None => self.resolve(package)?,
        };
        let text = std::fs::read_to_string(dir.join("Bluefile")).ok()?;
        let bf = crate::bluefile::read_bluefile(&text).ok()?;
        Some(bf.manifest.needs.keys().cloned().collect())
    }

    fn version(&self, package: &str, entry_dir: Option<&Path>) -> Option<String> {
        if entry_dir.is_none() {
            if let Some(s) = self.standard_for(package) {
                return s.version(package, None);
            }
        }
        let dir = match entry_dir {
            Some(d) => d.to_path_buf(),
            None => self.resolve(package)?,
        };
        let text = std::fs::read_to_string(dir.join("Bluefile")).ok()?;
        Some(
            crate::bluefile::read_bluefile(&text)
                .ok()?
                .version
                .to_string(),
        )
    }

    /// Every bidama a root holds (a directory with a Bluefile), then, when
    /// the standard distribution answers after the roots, every one of its.
    fn available(&self) -> Vec<String> {
        let mut out = std::collections::BTreeSet::new();
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
            out.extend(crate::embedded::Standard.names().into_iter().map(str::to_string));
        }
        out.into_iter().collect()
    }

    /// The `package(name, …)` of the Bluefile beside `path`, when it
    /// declares a bidama ([`bidama_of`]). A file beside a project's Bluefile
    /// is in the root namespace.
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
}
