//! Versions and ranges.
//!
//! Semver's *ordering* and *range* semantics, deliberately without
//! pre-release identifiers. Stated as a limit rather than left to be
//! discovered: `1.0.0-rc1` does not parse. Pre-releases carry their own
//! ordering rules (a pre-release sorts *below* its release, and is excluded
//! from ranges unless explicitly named), and a half-implementation of that is
//! worse than its absence — it resolves, quietly, to the wrong version.

use std::cmp::Ordering;
use std::fmt;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Version {
    pub major: u64,
    pub minor: u64,
    pub patch: u64,
}

impl Version {
    pub const fn new(major: u64, minor: u64, patch: u64) -> Self {
        Self {
            major,
            minor,
            patch,
        }
    }

    /// Parse `MAJOR.MINOR.PATCH`, or `MAJOR.MINOR` / `MAJOR` with the missing
    /// components zero.
    pub fn parse(s: &str) -> Result<Self, VersionError> {
        if s.contains('-') || s.contains('+') {
            return Err(VersionError::PreReleaseUnsupported(s.to_string()));
        }
        let mut parts = s.trim().split('.');
        let mut next = |name: &'static str| -> Result<u64, VersionError> {
            match parts.next() {
                None => Ok(0),
                Some(p) if p.is_empty() => Err(VersionError::Malformed {
                    input: s.to_string(),
                    component: name,
                }),
                Some(p) => p.parse().map_err(|_| VersionError::Malformed {
                    input: s.to_string(),
                    component: name,
                }),
            }
        };
        let major = next("major")?;
        let minor = next("minor")?;
        let patch = next("patch")?;
        if parts.next().is_some() {
            return Err(VersionError::Malformed {
                input: s.to_string(),
                component: "too many components",
            });
        }
        Ok(Self::new(major, minor, patch))
    }
}

impl fmt::Display for Version {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum VersionError {
    #[error("`{0}`: pre-release and build metadata are not supported")]
    PreReleaseUnsupported(String),
    #[error("`{input}`: could not read the {component}")]
    Malformed {
        input: String,
        component: &'static str,
    },
    #[error("`{0}`: not a recognised version range")]
    BadRange(String),
}

/// A set of acceptable versions.
///
/// Closed under intersection, which is what lets the solver combine two
/// packages' requirements into one question instead of re-checking both at
/// every step.
///
/// ## `==` compares SPELLING, not the set
///
/// One set of versions has several spellings: `^1.0.0` and
/// `>=1.0.0, <2.0.0` are the same set, and intersection returns the second.
/// Deriving `PartialEq` therefore gives *syntactic* equality, which is the
/// right thing for "did the manifest say what I think it said" and the wrong
/// thing for "do these two constraints admit the same versions".
///
/// Use [`Range::same_set_as`] for the semantic question. Full canonicalization
/// was considered and rejected: normalizing `Between` back into `Caret`
/// requires recognising every caret ceiling, and a normalizer that is subtly
/// incomplete is worse than an honest note — it makes `==` *look* semantic
/// while still disagreeing on the cases it missed.
///
/// The one normalization kept is `>=0.0.0` → [`Range::Any`], because that pair
/// arises from every intersection with `Any` and surprises immediately.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Range {
    /// `*` — any version.
    Any,
    /// `=1.2.3`
    Exact(Version),
    /// `>=1.2.3`
    AtLeast(Version),
    /// `^1.2.3` — at least this, below the next incompatible major.
    ///
    /// Follows Cargo's rule that `0.x` treats *minor* as the breaking
    /// component: `^0.2.1` accepts `0.2.9` and rejects `0.3.0`. Getting this
    /// wrong is how a resolver silently upgrades a consumer across a breaking
    /// 0.x change.
    Caret(Version),
    /// `>=lo, <hi` — the shape every intersection collapses to.
    Between { lo: Version, hi: Version },
    /// Nothing satisfies this. Produced by an empty intersection, and the
    /// reason a conflict can be reported precisely.
    Empty,
}

impl Range {
    pub fn parse(s: &str) -> Result<Self, VersionError> {
        let s = s.trim();
        if s == "*" || s.is_empty() {
            return Ok(Range::Any);
        }
        if let Some(rest) = s.strip_prefix(">=") {
            return Ok(Range::AtLeast(Version::parse(rest)?));
        }
        if let Some(rest) = s.strip_prefix('^') {
            return Ok(Range::Caret(Version::parse(rest)?));
        }
        if let Some(rest) = s.strip_prefix('=') {
            return Ok(Range::Exact(Version::parse(rest)?));
        }
        // A bare version means caret, as Cargo does. Chosen over `Exact`
        // deliberately: a bare `"1.2"` in a manifest almost always means
        // "compatible with", and reading it as Exact makes every transitive
        // dependency conflict.
        if s.chars().next().is_some_and(|c| c.is_ascii_digit()) {
            return Ok(Range::Caret(Version::parse(s)?));
        }
        Err(VersionError::BadRange(s.to_string()))
    }

    pub fn contains(&self, v: Version) -> bool {
        match self {
            Range::Any => true,
            Range::Empty => false,
            Range::Exact(x) => v == *x,
            Range::AtLeast(lo) => v >= *lo,
            Range::Caret(lo) => v >= *lo && v < caret_ceiling(*lo),
            Range::Between { lo, hi } => v >= *lo && v < *hi,
        }
    }

    /// Versions satisfying both. `Empty` when they are incompatible, which is
    /// the fact a conflict report needs.
    pub fn intersect(self, other: Range) -> Range {
        if matches!(self, Range::Empty) || matches!(other, Range::Empty) {
            return Range::Empty;
        }
        // An exact version on either side reduces to a membership question.
        if let Range::Exact(v) = self {
            return if other.contains(v) {
                Range::Exact(v)
            } else {
                Range::Empty
            };
        }
        if let Range::Exact(v) = other {
            return if self.contains(v) {
                Range::Exact(v)
            } else {
                Range::Empty
            };
        }
        let (lo_a, hi_a) = self.bounds();
        let (lo_b, hi_b) = other.bounds();
        let lo = lo_a.max(lo_b);
        let hi = match (hi_a, hi_b) {
            (None, None) => None,
            (Some(h), None) | (None, Some(h)) => Some(h),
            (Some(a), Some(b)) => Some(a.min(b)),
        };
        match hi {
            Some(h) if lo >= h => Range::Empty,
            Some(h) => Range::Between { lo, hi: h },
            // `>=0.0.0` IS `*`, so normalize the spelling. Without this,
            // `Any ∩ Any` returned `AtLeast(0.0.0)` — the same set under a
            // different name, which breaks structural equality for callers and
            // makes `Display` inconsistent. Canonicalizing is stronger than
            // asking every caller to compare by membership.
            None if lo == Version::new(0, 0, 0) => Range::Any,
            None => Range::AtLeast(lo),
        }
    }

    /// Do two ranges admit exactly the same versions, regardless of spelling?
    ///
    /// Decided over the boundary versions of both ranges, which is sufficient:
    /// a `Range` is a half-open interval (or a point, or empty), so two of them
    /// differ only if they differ at some bound or just inside/outside it.
    pub fn same_set_as(self, other: Range) -> bool {
        if matches!(self, Range::Empty) || matches!(other, Range::Empty) {
            return matches!(self, Range::Empty) && matches!(other, Range::Empty);
        }
        let mut probes = Vec::new();
        for r in [self, other] {
            let (lo, hi) = r.bounds();
            probes.push(lo);
            if lo.patch > 0 {
                probes.push(Version::new(lo.major, lo.minor, lo.patch - 1));
            }
            probes.push(next_patch(lo));
            if let Some(h) = hi {
                probes.push(h);
                if h.patch > 0 {
                    probes.push(Version::new(h.major, h.minor, h.patch - 1));
                }
                probes.push(next_patch(h));
            }
        }
        probes.push(Version::new(0, 0, 0));
        probes.iter().all(|v| self.contains(*v) == other.contains(*v))
    }

    /// `(inclusive lower, exclusive upper)`.
    fn bounds(self) -> (Version, Option<Version>) {
        match self {
            Range::Any => (Version::new(0, 0, 0), None),
            Range::Empty => (Version::new(u64::MAX, u64::MAX, u64::MAX), None),
            Range::Exact(v) => (v, Some(next_patch(v))),
            Range::AtLeast(lo) => (lo, None),
            Range::Caret(lo) => (lo, Some(caret_ceiling(lo))),
            Range::Between { lo, hi } => (lo, Some(hi)),
        }
    }
}

fn next_patch(v: Version) -> Version {
    Version::new(v.major, v.minor, v.patch.saturating_add(1))
}

/// The exclusive ceiling of `^v`.
///
/// Cargo's rule: below 1.0, *minor* is the breaking component.
fn caret_ceiling(v: Version) -> Version {
    if v.major > 0 {
        Version::new(v.major + 1, 0, 0)
    } else if v.minor > 0 {
        Version::new(0, v.minor + 1, 0)
    } else {
        Version::new(0, 0, v.patch + 1)
    }
}

impl fmt::Display for Range {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Range::Any => f.write_str("*"),
            Range::Empty => f.write_str("<nothing>"),
            Range::Exact(v) => write!(f, "={v}"),
            Range::AtLeast(v) => write!(f, ">={v}"),
            Range::Caret(v) => write!(f, "^{v}"),
            Range::Between { lo, hi } => write!(f, ">={lo}, <{hi}"),
        }
    }
}

/// Highest first — the order a solver should try candidates in.
pub fn newest_first(mut versions: Vec<Version>) -> Vec<Version> {
    versions.sort_by(|a, b| b.cmp(a));
    versions.dedup();
    versions
}

/// Total order, exposed so callers do not re-derive it.
pub fn compare(a: Version, b: Version) -> Ordering {
    a.cmp(&b)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(a: u64, b: u64, c: u64) -> Version {
        Version::new(a, b, c)
    }

    #[test]
    fn versions_parse_and_order() {
        assert_eq!(Version::parse("1.2.3").unwrap(), v(1, 2, 3));
        assert_eq!(Version::parse("1.2").unwrap(), v(1, 2, 0));
        assert_eq!(Version::parse("1").unwrap(), v(1, 0, 0));
        assert!(v(1, 0, 0) < v(1, 0, 1));
        assert!(v(1, 9, 9) < v(2, 0, 0));
    }

    /// **Pre-releases are rejected, not mis-parsed.** A partial implementation
    /// resolves quietly to the wrong version, which is worse than refusing.
    #[test]
    fn a_pre_release_is_rejected_rather_than_silently_truncated() {
        assert!(matches!(
            Version::parse("1.0.0-rc1"),
            Err(VersionError::PreReleaseUnsupported(_))
        ));
        assert!(matches!(
            Version::parse("1.0.0+build5"),
            Err(VersionError::PreReleaseUnsupported(_))
        ));
    }

    #[test]
    fn malformed_versions_are_rejected() {
        for bad in ["", "x", "1.x", "1..2", "1.2.3.4"] {
            assert!(Version::parse(bad).is_err(), "{bad:?} should not parse");
        }
    }

    /// **Caret below 1.0 breaks on MINOR.** Getting this wrong silently
    /// upgrades a consumer across a breaking 0.x change, which is the most
    /// common resolver bug there is.
    #[test]
    fn caret_treats_zero_x_minor_as_breaking() {
        let r = Range::parse("^0.2.1").unwrap();
        assert!(r.contains(v(0, 2, 1)));
        assert!(r.contains(v(0, 2, 99)));
        assert!(!r.contains(v(0, 3, 0)), "0.3.0 is a breaking change from 0.2.x");
        assert!(!r.contains(v(0, 2, 0)), "below the floor");

        let r1 = Range::parse("^1.2.0").unwrap();
        assert!(r1.contains(v(1, 9, 9)));
        assert!(!r1.contains(v(2, 0, 0)));
    }

    /// A bare version means caret, as Cargo does. Reading it as exact would
    /// make every transitive dependency conflict.
    #[test]
    fn a_bare_version_means_caret_not_exact() {
        assert_eq!(Range::parse("1.2.0").unwrap(), Range::Caret(v(1, 2, 0)));
        assert!(Range::parse("1.2.0").unwrap().contains(v(1, 5, 0)));
        assert!(!Range::parse("=1.2.0").unwrap().contains(v(1, 5, 0)));
    }

    #[test]
    fn ranges_intersect() {
        let a = Range::parse(">=1.0.0").unwrap();
        let b = Range::parse("^1.2.0").unwrap();
        let both = a.intersect(b);
        assert!(both.contains(v(1, 2, 0)));
        assert!(both.contains(v(1, 9, 0)));
        assert!(!both.contains(v(1, 1, 0)));
        assert!(!both.contains(v(2, 0, 0)));
    }

    /// **An incompatible intersection is `Empty`, not a range nothing fits.**
    /// The distinction is what lets a conflict be reported as a conflict.
    #[test]
    fn incompatible_ranges_intersect_to_empty() {
        let a = Range::parse("^1.0.0").unwrap();
        let b = Range::parse("^2.0.0").unwrap();
        assert_eq!(a.intersect(b), Range::Empty);
        assert!(!a.intersect(b).contains(v(1, 0, 0)));
        assert!(!a.intersect(b).contains(v(2, 0, 0)));
    }

    #[test]
    fn exact_intersections_are_membership_questions() {
        let e = Range::Exact(v(1, 2, 3));
        assert_eq!(e.intersect(Range::parse("^1.0.0").unwrap()), e);
        assert_eq!(e.intersect(Range::parse("^2.0.0").unwrap()), Range::Empty);
    }

    /// Intersection is commutative and idempotent — properties the solver
    /// relies on when it combines constraints in arbitrary order.
    #[test]
    fn intersection_is_commutative_and_idempotent() {
        let ranges = [
            Range::Any,
            Range::parse("^1.0.0").unwrap(),
            Range::parse(">=1.5.0").unwrap(),
            Range::Exact(v(1, 6, 0)),
            Range::parse("^0.2.0").unwrap(),
        ];
        for a in ranges {
            // By SET, not by spelling: `^1.0.0 ∩ ^1.0.0` returns
            // `>=1.0.0, <2.0.0`, which is the same set under another name. See
            // `Range`'s docs for why that is not canonicalized away.
            assert!(
                a.intersect(a).same_set_as(a),
                "idempotent by set: {a} ∩ {a} = {}",
                a.intersect(a)
            );
            for b in ranges {
                let ab = a.intersect(b);
                let ba = b.intersect(a);
                // Compare by membership: two spellings of one set are equal.
                for probe in [
                    v(0, 1, 0),
                    v(0, 2, 5),
                    v(1, 0, 0),
                    v(1, 5, 0),
                    v(1, 6, 0),
                    v(2, 0, 0),
                ] {
                    assert_eq!(
                        ab.contains(probe),
                        ba.contains(probe),
                        "commutative at {probe} for {a} ∩ {b}"
                    );
                }
            }
        }
    }

    /// The spelling is canonical: `>=0.0.0` normalizes to `*`, so two
    /// spellings of one set are also structurally equal.
    #[test]
    fn an_unbounded_intersection_normalizes_to_any() {
        assert_eq!(Range::Any.intersect(Range::Any), Range::Any);
        assert_eq!(
            Range::AtLeast(v(0, 0, 0)).intersect(Range::Any),
            Range::Any,
            ">=0.0.0 is the same set as *"
        );
        assert_eq!(
            Range::AtLeast(v(1, 0, 0)).intersect(Range::Any),
            Range::AtLeast(v(1, 0, 0)),
            "a real lower bound is preserved"
        );
    }

    #[test]
    fn any_is_the_intersection_identity() {
        for spec in ["^1.0.0", ">=2.0.0", "=1.2.3", "*"] {
            let r = Range::parse(spec).unwrap();
            for probe in [v(0, 1, 0), v(1, 0, 0), v(1, 2, 3), v(2, 5, 0)] {
                assert_eq!(r.intersect(Range::Any).contains(probe), r.contains(probe));
            }
        }
    }

    /// `same_set_as` must actually distinguish different sets, or the
    /// idempotence test above would pass on anything.
    #[test]
    fn same_set_as_separates_genuinely_different_ranges() {
        let caret = Range::parse("^1.0.0").unwrap();
        let between = Range::Between {
            lo: v(1, 0, 0),
            hi: v(2, 0, 0),
        };
        assert!(caret.same_set_as(between), "two spellings of one set");
        assert!(!caret.same_set_as(Range::parse("^2.0.0").unwrap()));
        assert!(!caret.same_set_as(Range::parse(">=1.0.0").unwrap()));
        assert!(!caret.same_set_as(Range::Any));
        assert!(!caret.same_set_as(Range::Empty));
        assert!(Range::Empty.same_set_as(Range::Empty));
        assert!(!Range::Any.same_set_as(Range::Empty));
    }

    #[test]
    fn newest_first_sorts_and_dedups() {
        let out = newest_first(vec![v(1, 0, 0), v(2, 0, 0), v(1, 0, 0), v(1, 5, 0)]);
        assert_eq!(out, vec![v(2, 0, 0), v(1, 5, 0), v(1, 0, 0)]);
    }
}
