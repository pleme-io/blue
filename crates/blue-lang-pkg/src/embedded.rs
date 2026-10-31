//! The standard distribution, compiled in: a [`Loader`] that needs no
//! `BLUE_PATH` and no files on disk.
//!
//! For a host embedding blue (arnes), and for the `blue` binary itself, whose
//! load path ends here (`LoadPath::with_standard`): a script with no Bluefile
//! and no `BLUE_PATH` can `use("retsu")` and get the same packages `blue`
//! resolves from the pinned distribution. Each package's Bluefile is compiled
//! in beside its source, so its `needs` and version are checked as they are
//! for a package on disk. Built by
//! `build.rs` from the checkout's `bidamas/`, so it is exactly the revision
//! the crate was built from. A registry build carries no `bidamas/`, and the
//! set is empty: check [`Standard::is_empty`] rather than assume.

use std::collections::BTreeSet;
use std::path::Path;

use blue_lang_runtime::uses::Loader;

/// One compiled-in package: its name, its Bluefile, and its `.b` files as
/// `(label, source)` pairs.
pub type Package = (
    &'static str,
    &'static str,
    &'static [(&'static str, &'static str)],
);

include!(concat!(env!("OUT_DIR"), "/embedded.rs"));

/// The compiled-in standard distribution.
#[derive(Debug, Clone, Copy, Default)]
pub struct Standard;

impl Standard {
    /// Whether no package was compiled in (a build without `bidamas/`).
    #[must_use]
    pub fn is_empty(self) -> bool {
        PACKAGES.is_empty()
    }

    /// The package names, sorted.
    #[must_use]
    pub fn names(self) -> Vec<&'static str> {
        PACKAGES.iter().map(|(n, _, _)| *n).collect()
    }

    /// Whether `name` is compiled in.
    #[must_use]
    pub fn has(self, name: &str) -> bool {
        PACKAGES.iter().any(|(n, _, _)| *n == name)
    }

    pub(crate) fn bluefile(self, name: &str) -> Option<crate::Bluefile> {
        let (_, text, _) = PACKAGES.iter().find(|(n, _, _)| *n == name)?;
        crate::read_bluefile(text).ok()
    }
}

impl Loader for Standard {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        PACKAGES
            .iter()
            .find(|(n, _, _)| *n == name)
            .map(|(_, _, files)| {
                files
                    .iter()
                    .map(|(l, t)| ((*l).to_owned(), (*t).to_owned()))
                    .collect()
            })
            .ok_or_else(|| {
                format!(
                    "cannot load bidama \"{name}\": not in the compiled-in standard distribution"
                )
            })
    }

    fn needs(&self, package: &str, _entry_dir: Option<&Path>) -> Option<BTreeSet<String>> {
        let (_, _, files) = PACKAGES.iter().find(|(n, _, _)| *n == package)?;
        let mut used = crate::needs::uses_in(files.iter().map(|(_, t)| *t));
        used.remove(package);
        Some(used)
    }

    fn version(&self, package: &str, _entry_dir: Option<&Path>) -> Option<String> {
        Some(self.bluefile(package)?.version.to_string())
    }
}

#[cfg(all(test, feature = "embedded"))]
mod tests {
    use super::*;

    #[test]
    fn the_standard_distribution_is_compiled_in_and_serves_by_name() {
        assert!(!Standard.is_empty());
        let names = Standard.names();
        assert!(
            names.contains(&"retsu") && names.contains(&"ronri"),
            "{names:?}"
        );
        assert!(names.windows(2).all(|w| w[0] < w[1]));
        let retsu = Standard.load("retsu").unwrap();
        assert!(retsu
            .iter()
            .any(|(l, t)| l == "retsu/retsu.b" && t.contains("def ")));
        assert!(Standard
            .load("no-such-bidama")
            .unwrap_err()
            .contains("no-such-bidama"));
    }

    /// The compiled-in Bluefile is the one on disk: kazu needs nothing and
    /// shuugou needs retsu, read back from each package's own lock.
    #[test]
    fn each_package_carries_its_own_bluefile() {
        let dir = |pkg: &str| {
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../bidamas")
                .join(pkg)
        };
        for pkg in ["kazu", "shuugou"] {
            let disk =
                crate::read_bluefile(&std::fs::read_to_string(dir(pkg).join("Bluefile")).unwrap())
                    .unwrap();
            assert_eq!(Standard.version(pkg, None), Some(disk.version.to_string()));
            assert_eq!(
                Standard.needs(pkg, None),
                crate::lock::locked_needs(&dir(pkg)).map(|n| n.into_keys().collect())
            );
        }
        assert!(Standard.needs("no-such-bidama", None).is_none());
    }
}
