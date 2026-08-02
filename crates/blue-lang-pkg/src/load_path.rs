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
}

impl LoadPath {
    /// A load path over the given roots, searched in order.
    #[must_use]
    pub fn new(roots: impl IntoIterator<Item = PathBuf>) -> Self {
        Self {
            roots: roots.into_iter().collect(),
        }
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
        out.push((path.display().to_string(), src));
    }
    out.sort();
    Ok(out)
}

impl Loader for LoadPath {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        let Some(dir) = self.resolve(name) else {
            // Name the roots that were searched. "package not found" alone
            // leaves the reader unable to tell an empty BLUE_PATH from a
            // misspelled package — two problems with opposite fixes.
            let where_looked = if self.roots.is_empty() {
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
            return Err(format!("no bidama named \"{name}\" ({where_looked})"));
        };

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
            "use(\"kazu\")\nclamp(99, 1, 10)",
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
}
