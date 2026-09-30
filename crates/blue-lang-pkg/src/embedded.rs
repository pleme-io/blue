//! The standard distribution, compiled in: a [`Loader`] that needs no
//! `BLUE_PATH` and no files on disk.
//!
//! For a host embedding blue (arnes): its programs `use("retsu")` and get the
//! same packages `blue` resolves from the pinned distribution. Built by
//! `build.rs` from the checkout's `bidamas/`, so it is exactly the revision
//! the crate was built from. A registry build carries no `bidamas/`, and the
//! set is empty: check [`Standard::is_empty`] rather than assume.

use blue_lang_runtime::uses::Loader;

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
        PACKAGES.iter().map(|(n, _)| *n).collect()
    }
}

impl Loader for Standard {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        PACKAGES
            .iter()
            .find(|(n, _)| *n == name)
            .map(|(_, files)| {
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
}

#[cfg(test)]
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
}
