//! A **git-backed** registry — packaging with no package server.
//!
//! ## The thesis
//!
//! blue does not need a registry service. A bidama is a directory containing a
//! `Bluefile`, and a distribution is a directory of those in git. Resolution
//! reads the working tree; publishing is `git push`; auditing is `git log`;
//! rollback is `git checkout`. There is no index to be stale, no server to be
//! down, and no second source of truth to reconcile with the repository.
//!
//! That is not a novel idea — Go modules resolve straight from VCS, and Nix
//! flakes pin git revisions — but it is the one that matches this fleet, where
//! *every* artifact is already content-addressed and git-hosted.
//!
//! ## Why this is an impl, not a rewrite
//!
//! [`Registry`] is a two-method trait ([`versions`], [`manifest`]) and the
//! solver is written against it, so a git source is a NEW IMPLEMENTATION beside
//! [`MapRegistry`] rather than a change to resolution. The solver is untouched
//! by this file, which is the whole reason the trait was worth having and the
//! reason "make packaging git-based" is additive rather than a fork.
//!
//! ## Versions come from the manifest, not the directory
//!
//! A directory name says `kazu`; the version lives in `Bluefile`'s
//! `package("kazu", "0.1.0")` call. Reading it from the manifest means the
//! version is stated once, in blue, by the package itself — a directory named
//! `kazu-0.1.0` would be a second place for it to be wrong.
//!
//! **Tier, stated because it bounds what this file claims:** this resolves from
//! a WORKING TREE — a checkout that is already on disk. It does not fetch, and
//! it does not pin a revision. Multi-version resolution therefore needs either
//! a worktree per tag or a git-object reader; both are real work and neither is
//! here. What this delivers is *"packaging reads git instead of a registry
//! service"*, not *"packaging pins git revisions"*, and those are different
//! claims.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use crate::bluefile;
use crate::solve::{Manifest, Registry};
use crate::version::Version;

/// A registry backed by a directory of bidamas in a git checkout.
///
/// Layout, one directory per package:
///
/// ```text
/// bidamas/
///   kazu/Bluefile      package("kazu", "0.1.0")
///   moji/Bluefile      package("moji", "0.1.0")
///   retsu/Bluefile     package("retsu", "0.1.0") + needs("kazu", "^0.1")
/// ```
#[derive(Clone, Debug, Default)]
pub struct GitRegistry {
    entries: BTreeMap<(String, Version), Manifest>,
}

impl GitRegistry {
    /// Scan a distribution directory, reading every `<pkg>/Bluefile`.
    ///
    /// A directory without a `Bluefile` is **skipped, not an error**: a
    /// distribution can legitimately hold docs, fixtures or a `.git`, and
    /// failing the whole scan because one folder is not a package would make
    /// the registry hostage to anything that shares the directory.
    ///
    /// A `Bluefile` that exists and does NOT parse is a different matter — that
    /// is a broken package, and it is returned as an error rather than skipped,
    /// because silently omitting it would surface later as "package not found",
    /// which sends the reader looking for a missing directory instead of a
    /// syntax error.
    pub fn scan(root: impl AsRef<Path>) -> Result<Self, GitRegistryError> {
        let root = root.as_ref();
        let mut entries = BTreeMap::new();

        let dir = std::fs::read_dir(root).map_err(|e| GitRegistryError::Unreadable {
            path: root.to_path_buf(),
            message: e.to_string(),
        })?;

        for e in dir.filter_map(Result::ok) {
            let path = e.path();
            if !path.is_dir() {
                continue;
            }
            let manifest_path = path.join("Bluefile");
            let Ok(text) = std::fs::read_to_string(&manifest_path) else {
                continue; // not a package; see the doc comment
            };
            let bf =
                bluefile::read_bluefile(&text).map_err(|err| GitRegistryError::BadManifest {
                    path: manifest_path.clone(),
                    message: err.to_string(),
                })?;
            entries.insert((bf.name.clone(), bf.version), bf.manifest);
        }

        Ok(Self { entries })
    }

    /// Number of packages found — so a caller can refuse an empty distribution
    /// rather than resolve against nothing and report "not found".
    #[must_use]
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

impl Registry for GitRegistry {
    fn versions(&self, name: &str) -> Vec<Version> {
        self.entries
            .keys()
            .filter(|(n, _)| n == name)
            .map(|(_, v)| *v)
            .collect()
    }

    fn manifest(&self, name: &str, version: Version) -> Option<Manifest> {
        self.entries.get(&(name.to_string(), version)).cloned()
    }
}

/// Why a git-backed scan failed.
///
/// Both variants carry the PATH. A packaging error that says only "parse error"
/// makes the reader grep a distribution to find which package broke.
#[derive(Debug, thiserror::Error)]
pub enum GitRegistryError {
    #[error("distribution directory {path} is unreadable: {message}")]
    Unreadable { path: PathBuf, message: String },
    #[error("{path} is not a valid Bluefile: {message}")]
    BadManifest { path: PathBuf, message: String },
}
