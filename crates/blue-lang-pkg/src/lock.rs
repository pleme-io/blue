//! `Bluefile.lock` — blue's evaluation of a Bluefile, committed so nix can read
//! it without running blue.
//!
//! `theory/BLUE-STRUCTURE.md` §5.1 and phases P1/P1b.
//!
//! ## Why a committed file, and not nix calling blue
//!
//! Nix cannot run blue at evaluation time without import-from-derivation, and
//! this repo has already paid for IFD once (`CLAUDE.md`, the
//! `Cargo.gen.lock` section: a `.drv` whose validity is store-state
//! dependent). So the answer is the one that repo already reached: **commit the
//! evaluated form, and gate its freshness.** blue calls nix (to pin sources);
//! nix never calls blue.
//!
//! Before this file, `bidamas/mk-bidama.nix` re-derived each package's
//! dependencies by splitting the manifest text on `needs("` — and a computed
//! `needs` was invisible to it, measured on 2026-08-02 as a facade closure of 17
//! packages where blue resolved 18, with nothing going red. That scrape is
//! deleted; nix reads `manifest.needs` from here.
//!
//! ## The shape
//!
//! ```text
//! { "schema": 1,
//!   "bluefile_b3": "b3:…",           Inputs::hash_of(Bluefile) — no second hash
//!   "manifest": { "schema": 1, "name", "version", "needs": {name: range},
//!                 "when", "sources", "packages", "runs", "tools",
//!                 "checks", "apps", "catalog" },
//!   "sources": { name: { "url", "rev", "narHash" } } }
//! ```
//!
//! `manifest` is exactly what `blue bluefile --json` prints. Both carry a
//! schema so that P0's layout fields join as a read, not a break.
//!
//! ## Honest tier
//!
//! **Eval- and CI-caught, never unrepresentable** — the tier `Cargo.gen.lock`
//! carries, for the same reason. Nothing stops a stale lock being committed; it
//! cannot pass [`confirm`], which `blue bluefile --confirm` runs and the
//! `bidama-locks-fresh` flake check runs over every package.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::bluefile::{read_bluefile, when_label, Bluefile, BluefileError, Project};

/// The lock file, beside the Bluefile it locks.
pub const LOCK_FILE: &str = "Bluefile.lock";

/// The layout of [`Lock`]. Bump when a field changes meaning or disappears;
/// ADDING a field is not a bump — a reader ignores what it does not ask for.
pub const LOCK_SCHEMA: u32 = 1;

/// The layout of [`ManifestRecord`], under the same rule.
pub const MANIFEST_SCHEMA: u32 = 1;

/// A Bluefile's evaluation as data: what `blue bluefile --json` prints and
/// what `Bluefile.lock` carries under `manifest`.
///
/// Strings, not blue's own types: this is read by nix, which knows nothing of
/// `Range`. Ranges are recorded in their canonical `Display` form, so two
/// spellings of one range lock identically.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ManifestRecord {
    pub schema: u32,
    pub name: String,
    pub version: String,
    /// `{dependency: range}`.
    pub needs: BTreeMap<String, String>,
    /// The posture floor's `when`, as the Bluefile spells it. `anytime` when
    /// undeclared — the floor starts at the top.
    pub when: String,
    /// Every §5.5 word, flattened so each is a top-level key. Flattened rather
    /// than listed field by field so a word added to [`Project`] is recorded
    /// with no second edit here.
    #[serde(flatten)]
    pub project: Project,
}

impl ManifestRecord {
    /// The record of an evaluated Bluefile.
    #[must_use]
    pub fn of(bluefile: &Bluefile) -> Self {
        ManifestRecord {
            schema: MANIFEST_SCHEMA,
            name: bluefile.name.clone(),
            version: bluefile.version.to_string(),
            needs: bluefile
                .manifest
                .needs
                .iter()
                .map(|(name, range)| (name.clone(), range.to_string()))
                .collect(),
            when: when_label(bluefile.floor.when).to_string(),
            project: bluefile.project.clone(),
        }
    }
}

/// A source pinned to one revision of one tree.
///
/// `narHash` keeps nix's spelling because nix reads it verbatim —
/// `builtins.fetchTree` takes exactly this pair.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Pin {
    pub url: String,
    pub rev: String,
    #[serde(rename = "narHash")]
    pub nar_hash: String,
}

/// The whole lock.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Lock {
    pub schema: u32,
    /// `Inputs::hash_of` over the Bluefile's bytes.
    pub bluefile_b3: String,
    pub manifest: ManifestRecord,
    /// One pin per `source(...)`, keyed by the source's name.
    pub sources: BTreeMap<String, Pin>,
}

/// How `blue lock` asks for a source's pin.
///
/// **The seam that keeps tests off the network.** The real implementation
/// (in `blue-lang-cli`) runs `nix flake prefetch --json <url>`; a test supplies
/// canned output. Either way the answer is the command's raw JSON, so the
/// by-key read in [`pin_of`] is exercised by both.
pub trait Prefetch {
    /// The JSON `nix flake prefetch --json <url>` prints.
    fn prefetch(&self, url: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>>;
}

/// Why a lock could not be written.
#[derive(Debug, thiserror::Error)]
pub enum LockError {
    #[error(transparent)]
    Bluefile(#[from] BluefileError),
    #[error("source `{name}` ({url}): prefetch failed: {cause}")]
    Prefetch {
        name: String,
        url: String,
        #[source]
        cause: Box<dyn std::error::Error + Send + Sync>,
    },
    #[error("source `{name}` ({url}): the prefetch output is not JSON: {cause}")]
    PrefetchJson {
        name: String,
        url: String,
        #[source]
        cause: serde_json::Error,
    },
    /// The prefetch output has no string where the pin is read from. Named by
    /// its JSON pointer, because the fix is to look at that key.
    #[error("source `{name}` ({url}): the prefetch output has no string at `{key}`")]
    MissingKey {
        name: String,
        url: String,
        key: &'static str,
    },
    /// Two keys that name the same NAR hash disagree — nix's output is not the
    /// shape this reader was written against, and guessing would pin the wrong
    /// tree.
    #[error(
        "source `{name}` ({url}): `{NAR_HASH}` is `{top}` but `{LOCKED_NAR_HASH}` is `{locked}`"
    )]
    NarHashDisagrees {
        name: String,
        url: String,
        top: String,
        locked: String,
    },
    #[error("could not serialize the lock: {0}")]
    Json(#[from] serde_json::Error),
}

/// Where the pin's revision lives in `nix flake prefetch --json` output.
pub const REV: &str = "/locked/rev";

/// Where the pin's NAR hash lives.
///
/// **Top-level `hash`, not `locked.narHash`, and that is measured.** On nix
/// 2.31.5 (2026-09-23), `nix flake prefetch --json github:pleme-io/blue`
/// prints `locked` as `{lastModified, owner, repo, rev, type}` — no `narHash`
/// at all — with the NAR hash at the top level under `hash`. Older nix also
/// emits `locked.narHash`; where it does, [`pin_of`] requires the two to agree
/// rather than preferring one.
pub const NAR_HASH: &str = "/hash";

/// The older location of the same hash, cross-checked when present.
pub const LOCKED_NAR_HASH: &str = "/locked/narHash";

/// Read a pin out of `nix flake prefetch --json` output, **by key**.
///
/// JSON pointers, never positions: a nix release that adds, removes or
/// reorders a field changes nothing here unless it moves one of these two.
pub fn pin_of(name: &str, url: &str, json: &str) -> Result<Pin, LockError> {
    let value: serde_json::Value =
        serde_json::from_str(json).map_err(|cause| LockError::PrefetchJson {
            name: name.to_string(),
            url: url.to_string(),
            cause,
        })?;
    let at = |key: &'static str| -> Result<String, LockError> {
        value
            .pointer(key)
            .and_then(serde_json::Value::as_str)
            .map(str::to_string)
            .ok_or_else(|| LockError::MissingKey {
                name: name.to_string(),
                url: url.to_string(),
                key,
            })
    };
    let rev = at(REV)?;
    let nar_hash = at(NAR_HASH)?;
    if let Some(locked) = value
        .pointer(LOCKED_NAR_HASH)
        .and_then(serde_json::Value::as_str)
    {
        if locked != nar_hash {
            return Err(LockError::NarHashDisagrees {
                name: name.to_string(),
                url: url.to_string(),
                top: nar_hash,
                locked: locked.to_string(),
            });
        }
    }
    Ok(Pin {
        url: url.to_string(),
        rev,
        nar_hash,
    })
}

/// Evaluate a Bluefile and pin its sources — what `blue lock` writes.
pub fn lock(bluefile_src: &str, prefetch: &dyn Prefetch) -> Result<Lock, LockError> {
    let bluefile = read_bluefile(bluefile_src)?;
    let mut sources = BTreeMap::new();
    for (name, source) in &bluefile.project.sources {
        let json = prefetch
            .prefetch(&source.url)
            .map_err(|cause| LockError::Prefetch {
                name: name.clone(),
                url: source.url.clone(),
                cause,
            })?;
        sources.insert(name.clone(), pin_of(name, &source.url, &json)?);
    }
    Ok(Lock {
        schema: LOCK_SCHEMA,
        bluefile_b3: blue_lang_runtime::Inputs::hash_of(bluefile_src.as_bytes()),
        manifest: ManifestRecord::of(&bluefile),
        sources,
    })
}

/// The one rendering of a lock or a manifest record: pretty, keys in
/// `BTreeMap` order, one trailing newline. One door, so `blue lock` and
/// `blue bluefile --json` cannot print the same record two ways.
pub fn render<T: Serialize>(value: &T) -> Result<String, serde_json::Error> {
    let mut out = serde_json::to_string_pretty(value)?;
    out.push('\n');
    Ok(out)
}

/// Whether a committed lock is blue's evaluation of the Bluefile beside it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum Freshness {
    Fresh,
    Stale { reason: Staleness },
}

impl Freshness {
    #[must_use]
    pub fn is_fresh(&self) -> bool {
        matches!(self, Freshness::Fresh)
    }
}

/// Why a lock is not fresh. Each arm says what to look at.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, thiserror::Error)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Staleness {
    #[error("there is no {LOCK_FILE} beside the Bluefile")]
    Missing,
    #[error("{LOCK_FILE} is not a lock: {error}")]
    Unreadable { error: String },
    #[error("{LOCK_FILE} has schema {recorded:?}; this blue writes {expected}")]
    Schema {
        recorded: Option<u64>,
        expected: u32,
    },
    /// The Bluefile changed after the lock was written. The common case.
    #[error("the Bluefile hashes to {computed}, and the lock records {recorded}")]
    Hash { recorded: String, computed: String },
    /// Same bytes, different evaluation: the lock was edited by hand, or the
    /// blue that wrote it evaluated the manifest differently.
    #[error("the recorded manifest differs from blue's evaluation at: {}", .differing.join(", "))]
    Manifest { differing: Vec<String> },
    /// The pins do not cover exactly the declared sources, or a pin is for a
    /// different URL than the source declares.
    #[error("sources: unpinned {unpinned:?}, stray {stray:?}, pinned to another url {moved:?}")]
    Sources {
        unpinned: Vec<String>,
        stray: Vec<String>,
        moved: Vec<String>,
    },
}

/// Check a committed lock against the Bluefile beside it, **offline**.
///
/// The `b3` comparison is `gen confirm`'s `sha256(Cargo.lock)` check with
/// blue's own hash. The manifest comparison is what makes this more than a
/// hash check: a lock whose bytes match but whose manifest was edited, or was
/// written by a blue that evaluated differently, is stale too — compared as
/// JSON values, so an extra or missing key counts. Pins cannot be re-fetched
/// offline; what is checked is that they cover exactly the declared sources.
///
/// `lock_text` is `None` when there is no lock file.
pub fn confirm(bluefile_src: &str, lock_text: Option<&str>) -> Result<Freshness, LockError> {
    let stale = |reason| Ok(Freshness::Stale { reason });
    let Some(text) = lock_text else {
        return stale(Staleness::Missing);
    };
    // Untyped first, so a lock from a future schema says so rather than
    // failing to parse as this one.
    let recorded: serde_json::Value = match serde_json::from_str(text) {
        Ok(v) => v,
        Err(e) => {
            return stale(Staleness::Unreadable {
                error: e.to_string(),
            })
        }
    };
    let schema = recorded.get("schema").and_then(serde_json::Value::as_u64);
    if schema != Some(u64::from(LOCK_SCHEMA)) {
        return stale(Staleness::Schema {
            recorded: schema,
            expected: LOCK_SCHEMA,
        });
    }
    let lock: Lock = match serde_json::from_value(recorded.clone()) {
        Ok(l) => l,
        Err(e) => {
            return stale(Staleness::Unreadable {
                error: e.to_string(),
            })
        }
    };

    let computed = blue_lang_runtime::Inputs::hash_of(bluefile_src.as_bytes());
    if lock.bluefile_b3 != computed {
        return stale(Staleness::Hash {
            recorded: lock.bluefile_b3,
            computed,
        });
    }

    let bluefile = read_bluefile(bluefile_src)?;
    let evaluated = serde_json::to_value(ManifestRecord::of(&bluefile))?;
    let written = recorded
        .get("manifest")
        .cloned()
        .unwrap_or(serde_json::Value::Null);
    if written != evaluated {
        return stale(Staleness::Manifest {
            differing: differing_keys(&written, &evaluated),
        });
    }

    let declared = &bluefile.project.sources;
    let unpinned: Vec<String> = declared
        .keys()
        .filter(|n| !lock.sources.contains_key(*n))
        .cloned()
        .collect();
    let stray: Vec<String> = lock
        .sources
        .keys()
        .filter(|n| !declared.contains_key(*n))
        .cloned()
        .collect();
    let moved: Vec<String> = lock
        .sources
        .iter()
        .filter(|(n, pin)| declared.get(*n).is_some_and(|s| s.url != pin.url))
        .map(|(n, _)| n.clone())
        .collect();
    if !(unpinned.is_empty() && stray.is_empty() && moved.is_empty()) {
        return stale(Staleness::Sources {
            unpinned,
            stray,
            moved,
        });
    }
    Ok(Freshness::Fresh)
}

/// The top-level keys two manifest records disagree on — the part of a
/// `Manifest` staleness a reader acts on.
fn differing_keys(a: &serde_json::Value, b: &serde_json::Value) -> Vec<String> {
    match (a.as_object(), b.as_object()) {
        (Some(a), Some(b)) => {
            let keys: std::collections::BTreeSet<&String> = a.keys().chain(b.keys()).collect();
            keys.into_iter()
                .filter(|k| a.get(*k) != b.get(*k))
                .cloned()
                .collect()
        }
        _ => vec!["manifest".to_string()],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A prefetcher that answers from a table and records nothing else — the
    /// network is never touched.
    struct Canned(BTreeMap<&'static str, String>);

    impl Prefetch for Canned {
        fn prefetch(&self, url: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
            self.0
                .get(url)
                .cloned()
                .ok_or_else(|| String::from("no canned answer for this url").into())
        }
    }

    /// The exact shape nix 2.31.5 printed for `github:pleme-io/blue` on
    /// 2026-09-23 — `locked` carries no `narHash`.
    const PREFETCH_2_31: &str = r#"{"hash":"sha256-83hQT5WB0TIJVH71DYQAdCX4PYNKucSmJRvk5LkflzQ=","locked":{"lastModified":1790187679,"owner":"pleme-io","repo":"blue","rev":"03ae6ac5c7b38a8bb82cea5cc92c8ab237750d27","type":"github"},"original":{"owner":"pleme-io","repo":"blue","type":"github"},"storePath":"/nix/store/zrhpyzzbmqg622gk1xx9sj03lvmymbrp-source"}"#;

    const WITH_SOURCE: &str = "package(\"proj\", \"0.1.0\")\n\
        needs(\"kazu\", \"^0.1\")\n\
        source(\"blue\", \"github:pleme-io/blue\", \"bidamas\")\n\
        packages(\"bidamas\")\n";

    fn canned() -> Canned {
        Canned(BTreeMap::from([(
            "github:pleme-io/blue",
            PREFETCH_2_31.to_string(),
        )]))
    }

    #[test]
    fn a_pin_is_read_by_key_from_real_prefetch_output() {
        let pin = pin_of("blue", "github:pleme-io/blue", PREFETCH_2_31).expect("pin");
        assert_eq!(pin.rev, "03ae6ac5c7b38a8bb82cea5cc92c8ab237750d27");
        assert_eq!(
            pin.nar_hash,
            "sha256-83hQT5WB0TIJVH71DYQAdCX4PYNKucSmJRvk5LkflzQ="
        );
        assert_eq!(pin.url, "github:pleme-io/blue");
    }

    /// **By key, not by position.** The same facts with every key reordered, an
    /// unknown field added, and the older `locked.narHash` present and
    /// agreeing: the pin is identical.
    #[test]
    fn a_pin_survives_reordered_and_extra_keys() {
        let shuffled = r#"{"storePath":"/nix/store/x-source","newField":[1,2,3],
            "locked":{"type":"github","narHash":"sha256-83hQT5WB0TIJVH71DYQAdCX4PYNKucSmJRvk5LkflzQ=","rev":"03ae6ac5c7b38a8bb82cea5cc92c8ab237750d27","repo":"blue"},
            "hash":"sha256-83hQT5WB0TIJVH71DYQAdCX4PYNKucSmJRvk5LkflzQ="}"#;
        assert_eq!(
            pin_of("blue", "github:pleme-io/blue", shuffled).expect("pin"),
            pin_of("blue", "github:pleme-io/blue", PREFETCH_2_31).expect("pin")
        );
    }

    #[test]
    fn a_missing_rev_is_named_by_its_key() {
        let err = pin_of("blue", "u", r#"{"hash":"sha256-x","locked":{}}"#).expect_err("no rev");
        assert!(
            matches!(err, LockError::MissingKey { key: REV, .. }),
            "got {err}"
        );
        let err = pin_of("blue", "u", r#"{"locked":{"rev":"abc"}}"#).expect_err("no hash");
        assert!(
            matches!(err, LockError::MissingKey { key: NAR_HASH, .. }),
            "got {err}"
        );
    }

    #[test]
    fn two_disagreeing_nar_hashes_are_refused_not_chosen_between() {
        let err = pin_of(
            "blue",
            "u",
            r#"{"hash":"sha256-a","locked":{"rev":"r","narHash":"sha256-b"}}"#,
        )
        .expect_err("disagree");
        assert!(
            matches!(err, LockError::NarHashDisagrees { .. }),
            "got {err}"
        );
    }

    #[test]
    fn a_lock_pins_every_source_and_records_the_evaluation() {
        let lock = lock(WITH_SOURCE, &canned()).expect("lock");
        assert_eq!(lock.schema, LOCK_SCHEMA);
        assert_eq!(
            lock.bluefile_b3,
            blue_lang_runtime::Inputs::hash_of(WITH_SOURCE.as_bytes())
        );
        assert_eq!(lock.manifest.name, "proj");
        assert_eq!(lock.manifest.needs["kazu"], "^0.1.0");
        assert_eq!(lock.manifest.when, "anytime");
        assert_eq!(lock.manifest.project.packages, vec!["bidamas"]);
        assert_eq!(
            lock.sources["blue"].rev,
            "03ae6ac5c7b38a8bb82cea5cc92c8ab237750d27"
        );
    }

    /// A prefetch failure names the source; it is never a lock with a hole.
    #[test]
    fn a_failed_prefetch_is_an_error_naming_the_source() {
        let err = lock(WITH_SOURCE, &Canned(BTreeMap::new())).expect_err("no answer");
        assert!(
            matches!(err, LockError::Prefetch { ref name, .. } if name == "blue"),
            "got {err}"
        );
    }

    /// The rendered lock reads back as the same lock, and the manifest's §5.5
    /// words sit at its top level where nix reads them.
    #[test]
    fn a_rendered_lock_round_trips_and_is_confirmed_fresh() {
        let lock_value = lock(WITH_SOURCE, &canned()).expect("lock");
        let text = render(&lock_value).expect("render");
        assert!(text.ends_with('\n'));
        let back: Lock = serde_json::from_str(&text).expect("parse");
        assert_eq!(back, lock_value);
        let v: serde_json::Value = serde_json::from_str(&text).expect("value");
        assert_eq!(v["manifest"]["packages"][0], "bidamas");
        assert_eq!(
            v["sources"]["blue"]["narHash"],
            lock_value.sources["blue"].nar_hash
        );
        assert_eq!(
            confirm(WITH_SOURCE, Some(&text)).expect("confirm"),
            Freshness::Fresh
        );
    }

    #[test]
    fn no_lock_is_stale_as_missing() {
        assert_eq!(
            confirm(WITH_SOURCE, None).expect("confirm"),
            Freshness::Stale {
                reason: Staleness::Missing
            }
        );
    }

    /// **P1's second red run, as a test.** Zeroing the recorded hash makes the
    /// lock stale.
    #[test]
    fn a_zeroed_hash_is_stale() {
        let mut l = lock(WITH_SOURCE, &canned()).expect("lock");
        l.bluefile_b3 = String::from("b3:") + &"0".repeat(64);
        let verdict = confirm(WITH_SOURCE, Some(&render(&l).expect("render"))).expect("confirm");
        assert!(
            matches!(
                verdict,
                Freshness::Stale {
                    reason: Staleness::Hash { .. }
                }
            ),
            "got {verdict:?}"
        );
    }

    /// An edited Bluefile — one byte — is stale without relocking.
    #[test]
    fn an_edited_bluefile_is_stale_until_relocked() {
        let text = render(&lock(WITH_SOURCE, &canned()).expect("lock")).expect("render");
        let edited = String::from(WITH_SOURCE) + "tool(\"jq\")\n";
        assert!(!confirm(&edited, Some(&text)).expect("confirm").is_fresh());
        let relocked = render(&lock(&edited, &canned()).expect("lock")).expect("render");
        assert!(confirm(&edited, Some(&relocked))
            .expect("confirm")
            .is_fresh());
    }

    /// **The manifest half is not vacuous.** Same Bluefile bytes, the hash left
    /// intact, one dependency deleted from the recorded manifest by hand: the
    /// hash check alone would call this fresh, and nix would build a closure one
    /// package short — the 2026-08-02 failure, arriving by a different door.
    #[test]
    fn a_hand_edited_manifest_is_stale_even_with_the_right_hash() {
        let mut l = lock(WITH_SOURCE, &canned()).expect("lock");
        l.manifest.needs.clear();
        let verdict = confirm(WITH_SOURCE, Some(&render(&l).expect("render"))).expect("confirm");
        assert_eq!(
            verdict,
            Freshness::Stale {
                reason: Staleness::Manifest {
                    differing: vec!["needs".into()]
                }
            }
        );
    }

    #[test]
    fn a_pin_that_does_not_match_the_declared_sources_is_stale() {
        let mut l = lock(WITH_SOURCE, &canned()).expect("lock");
        let pin = l.sources.remove("blue").expect("pin");
        l.sources.insert("other".into(), pin);
        let verdict = confirm(WITH_SOURCE, Some(&render(&l).expect("render"))).expect("confirm");
        assert_eq!(
            verdict,
            Freshness::Stale {
                reason: Staleness::Sources {
                    unpinned: vec!["blue".into()],
                    stray: vec!["other".into()],
                    moved: vec![],
                }
            }
        );
    }

    #[test]
    fn an_unknown_key_or_a_future_schema_is_stale_not_ignored() {
        let text = render(&lock(WITH_SOURCE, &canned()).expect("lock")).expect("render");
        let mut v: serde_json::Value = serde_json::from_str(&text).expect("value");
        v["extra"] = serde_json::Value::Bool(true);
        assert!(matches!(
            confirm(WITH_SOURCE, Some(&v.to_string())).expect("confirm"),
            Freshness::Stale {
                reason: Staleness::Unreadable { .. }
            }
        ));
        let mut v: serde_json::Value = serde_json::from_str(&text).expect("value");
        v["schema"] = serde_json::Value::from(2);
        assert!(matches!(
            confirm(WITH_SOURCE, Some(&v.to_string())).expect("confirm"),
            Freshness::Stale {
                reason: Staleness::Schema { .. }
            }
        ));
    }

    /// The verdict is printed for machines as well as people.
    #[test]
    fn freshness_serializes_with_a_status_and_a_reason() {
        let v = serde_json::to_value(Freshness::Stale {
            reason: Staleness::Missing,
        })
        .expect("json");
        assert_eq!(v["status"], "stale");
        assert_eq!(v["reason"]["kind"], "missing");
        assert_eq!(
            serde_json::to_value(Freshness::Fresh).expect("json")["status"],
            "fresh"
        );
    }
}
