//! Dependency resolution.
//!
//! ## Why this exists rather than wrapping something
//!
//! The fleet has no version solver. Every consumer that needed one so far
//! either had a lockfile handed to it (cargo, bundler) or resolved a single
//! flat list. bīdama needs the real thing, because a package declares both a
//! version range *and* a posture floor, and the two interact: a version choice
//! can change the posture the program must run in.
//!
//! ## The contribution is the conflict message, not the search
//!
//! Backtracking over "newest first" is the easy half and every solver does it.
//! What makes a resolver usable is answering **why** — naming both sides and
//! the specific coordinate that failed. `bundle update` telling you only "could
//! not find compatible versions" is the failure mode this is built to avoid, and
//! it is why [`Conflict`] carries the *chain of requirements* rather than a
//! boolean.
//!
//! ## Honest limits
//!
//! This is **backtracking with conflict attribution**, not PubGrub. PubGrub's
//! contribution is *incompatibility learning* — deriving general facts from
//! failures so the same dead end is never re-entered. Without it, a
//! pathological graph can take exponential time. [`Solver::steps_taken`]
//! reports the search size and [`SolveError::Exhausted`] fires at a bound, so
//! the difference is visible rather than experienced as a hang.

use std::collections::{BTreeMap, BTreeSet};

use crate::version::{newest_first, Range, Version};

/// One package's requirements at one version.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Manifest {
    /// `name -> range`
    pub needs: BTreeMap<String, Range>,
}

impl Manifest {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn needing(mut self, name: &str, range: Range) -> Self {
        self.needs.insert(name.to_string(), range);
        self
    }
}

/// Where candidate versions and their requirements come from.
///
/// A trait so resolution is testable without a network, a registry server, or
/// a filesystem — the three things that make a solver's tests slow and flaky
/// everywhere else.
pub trait Registry {
    /// Every published version of `name`, in any order.
    fn versions(&self, name: &str) -> Vec<Version>;
    /// What `name@version` requires. `None` if that version does not exist.
    fn manifest(&self, name: &str, version: Version) -> Option<Manifest>;
}

/// An in-memory registry.
#[derive(Clone, Debug, Default)]
pub struct MapRegistry {
    entries: BTreeMap<(String, Version), Manifest>,
}

impl MapRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn add(&mut self, name: &str, version: Version, manifest: Manifest) -> &mut Self {
        self.entries.insert((name.to_string(), version), manifest);
        self
    }
}

impl Registry for MapRegistry {
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

/// One link in the chain of requirements that led to a constraint.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Requirement {
    /// Who asked. `None` for the root.
    pub from: Option<String>,
    pub package: String,
    pub range: Range,
}

impl std::fmt::Display for Requirement {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match &self.from {
            Some(from) => write!(f, "{from} requires {} {}", self.package, self.range),
            None => write!(f, "the root requires {} {}", self.package, self.range),
        }
    }
}

/// Why resolution failed, in enough detail to act on.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Conflict {
    pub package: String,
    /// Every requirement that bore on `package`. **Both sides**, so the reader
    /// does not have to reconstruct who disagreed.
    pub requirements: Vec<Requirement>,
    /// The versions that existed, so "no versions published" is
    /// distinguishable from "none satisfied".
    pub available: Vec<Version>,
}

impl std::fmt::Display for Conflict {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "cannot resolve `{}`:", self.package)?;
        for r in &self.requirements {
            writeln!(f, "  {r}")?;
        }
        if self.available.is_empty() {
            write!(f, "  and no versions of `{}` are published", self.package)
        } else {
            let list = self
                .available
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join(", ");
            write!(f, "  available: {list}")
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum SolveError {
    #[error("{0}")]
    Conflict(Conflict),
    /// The search hit its bound. Reported as its own case because it is *not*
    /// proof that no solution exists — conflating the two would let a solver
    /// claim a graph is unsatisfiable when it merely gave up.
    #[error("resolution gave up after {steps} steps; this is not proof that no solution exists")]
    Exhausted { steps: usize },
}

/// The resolved set.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Resolution {
    pub picks: BTreeMap<String, Version>,
}

impl std::fmt::Display for Resolution {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut first = true;
        for (name, version) in &self.picks {
            if !first {
                writeln!(f)?;
            }
            first = false;
            write!(f, "{name} {version}")?;
        }
        Ok(())
    }
}

/// A fact learned from a failure: this exact assignment cannot be part of any
/// solution.
///
/// PubGrub's contribution in its smallest useful form. Without it a solver
/// re-derives the same dead end from every path that reaches it, which is where
/// the exponential lives — the search is not exploring new ground, it is
/// re-proving something it already proved.
///
/// Deliberately narrow: this records *concrete rejected assignments*
/// (`name@version`), not general clauses over version ranges. A full derivation
/// graph would subsume more, and would also be a much larger thing to get right;
/// this is the part that pays for itself immediately, and `learned()` reports
/// how much it caught so the value is measured rather than assumed.
#[derive(Clone, Debug, Default)]
struct Learned {
    rejected: BTreeSet<(String, Version)>,
}

impl Learned {
    fn is_known_bad(&self, name: &str, v: Version) -> bool {
        self.rejected.contains(&(name.to_string(), v))
    }

    fn record(&mut self, name: &str, v: Version) {
        self.rejected.insert((name.to_string(), v));
    }
}

/// Is this conflict caused by `name@version` alone?
///
/// True when every requirement on the failing package originates at the root or
/// at this exact candidate. Any third contributor means a sibling choice is
/// implicated, and the candidate cannot be condemned on this evidence.
fn attributable_to(e: &SolveError, name: &str, version: Version) -> bool {
    let SolveError::Conflict(c) = e else {
        return false;
    };
    let mine = {
        let mut s = String::with_capacity(name.len() + 8);
        s.push_str(name);
        s.push(' ');
        s.push_str(&version.to_string());
        s
    };
    // An empty chain proves nothing about the cause.
    !c.requirements.is_empty()
        && c.requirements.iter().all(|r| match &r.from {
            None => true, // the root — invariant across the search
            Some(from) => from == &mine,
        })
}

pub struct Solver<'r, R: Registry> {
    registry: &'r R,
    max_steps: usize,
    steps: usize,
    learned: Learned,
    skipped: usize,
}

/// Bound on the search. Generous for any real graph; finite so a pathological
/// one reports rather than hangs. Raise with [`Solver::with_max_steps`].
pub const DEFAULT_MAX_STEPS: usize = 100_000;

impl<'r, R: Registry> Solver<'r, R> {
    pub fn new(registry: &'r R) -> Self {
        Self {
            registry,
            max_steps: DEFAULT_MAX_STEPS,
            steps: 0,
            learned: Learned::default(),
            skipped: 0,
        }
    }

    pub fn with_max_steps(mut self, max_steps: usize) -> Self {
        self.max_steps = max_steps;
        self
    }

    /// How many candidate versions were tried. Exposed because this solver
    /// does not learn incompatibilities (see the module docs), so the search
    /// size is a real property a caller may want to see.
    pub fn steps_taken(&self) -> usize {
        self.steps
    }

    /// Candidate attempts skipped because the assignment was already known bad.
    ///
    /// The measured value of learning. Zero on a graph with no repeated dead
    /// ends — which is most of them, and why this is reported rather than
    /// assumed.
    pub fn skipped_by_learning(&self) -> usize {
        self.skipped
    }

    /// Resolve `root`'s requirements.
    pub fn solve(&mut self, root: &Manifest) -> Result<Resolution, SolveError> {
        self.steps = 0;
        self.learned = Learned::default();
        self.skipped = 0;
        // Constraints accumulate as an intersection per package, alongside the
        // requirement chain that produced them — the chain is what makes a
        // conflict explainable.
        let mut constraints: BTreeMap<String, (Range, Vec<Requirement>)> = BTreeMap::new();
        for (name, range) in &root.needs {
            constraints.insert(
                name.clone(),
                (
                    *range,
                    vec![Requirement {
                        from: None,
                        package: name.clone(),
                        range: *range,
                    }],
                ),
            );
        }
        let mut picks = BTreeMap::new();
        self.search(&mut constraints, &mut picks)?;
        Ok(Resolution { picks })
    }

    fn search(
        &mut self,
        constraints: &mut BTreeMap<String, (Range, Vec<Requirement>)>,
        picks: &mut BTreeMap<String, Version>,
    ) -> Result<(), SolveError> {
        // Pick the next unresolved package deterministically (BTreeMap order),
        // so the same input always produces the same resolution AND the same
        // error. A resolver whose output depends on hash order is one nobody
        // can reproduce a bug in.
        let next = constraints
            .keys()
            .find(|name| !picks.contains_key(*name))
            .cloned();
        let Some(name) = next else {
            return Ok(()); // Everything resolved.
        };

        let (range, chain) = constraints[&name].clone();
        let available = newest_first(self.registry.versions(&name));
        let candidates: Vec<Version> = available
            .iter()
            .copied()
            .filter(|v| range.contains(*v))
            .collect();

        if candidates.is_empty() {
            return Err(SolveError::Conflict(Conflict {
                package: name.clone(),
                requirements: chain,
                available,
            }));
        }

        let mut last_conflict = None;
        for candidate in candidates {
            // Consult what previous failures proved. Reaching the same
            // assignment by a different path does not make it viable, and
            // re-deriving that is exactly the exponential.
            if self.learned.is_known_bad(&name, candidate) {
                self.skipped += 1;
                continue;
            }
            self.steps += 1;
            if self.steps > self.max_steps {
                return Err(SolveError::Exhausted { steps: self.steps });
            }

            let Some(manifest) = self.registry.manifest(&name, candidate) else {
                continue;
            };

            // Speculate: take a copy so a failed branch leaves nothing behind.
            // Without this, a rejected candidate's constraints would poison the
            // next attempt and the solver would report a conflict that does not
            // exist.
            let mut next_constraints = constraints.clone();
            let mut next_picks = picks.clone();
            next_picks.insert(name.clone(), candidate);

            let mut viable = true;
            for (dep, dep_range) in &manifest.needs {
                let entry = next_constraints
                    .entry(dep.clone())
                    .or_insert((Range::Any, Vec::new()));
                let combined = entry.0.intersect(*dep_range);
                entry.1.push(Requirement {
                    from: Some(format!("{name} {candidate}")),
                    package: dep.clone(),
                    range: *dep_range,
                });
                entry.0 = combined;
                if matches!(combined, Range::Empty) {
                    last_conflict = Some(SolveError::Conflict(Conflict {
                        package: dep.clone(),
                        requirements: entry.1.clone(),
                        available: newest_first(self.registry.versions(dep)),
                    }));
                    viable = false;
                    break;
                }
                // A package already picked must still satisfy the new
                // constraint; otherwise a later requirement could silently
                // disagree with an earlier pick.
                if let Some(picked) = next_picks.get(dep) {
                    if !combined.contains(*picked) {
                        last_conflict = Some(SolveError::Conflict(Conflict {
                            package: dep.clone(),
                            requirements: entry.1.clone(),
                            available: newest_first(self.registry.versions(dep)),
                        }));
                        viable = false;
                        break;
                    }
                }
            }
            if !viable {
                // Learn ONLY if the empty intersection is attributable — the
                // same rule as the subtree branch below, and unsound without it.
                //
                // The comment here used to claim "the conflict came from the
                // candidate's OWN manifest, not from anything the caller chose".
                // That is false: the intersection is against constraints ALREADY
                // in scope, which include every sibling the caller picked. A
                // candidate that fails under `p@2` may be fine under `p@1`, and
                // condemning it globally makes the solver report a satisfiable
                // graph as unsatisfiable — see `soundness::
                // a_context_dependent_failure_does_not_condemn_the_candidate`,
                // which is the test I should have written first.
                if let Some(e) = &last_conflict {
                    if attributable_to(e, &name, candidate) {
                        self.learned.record(&name, candidate);
                    }
                }
                continue;
            }

            match self.search(&mut next_constraints, &mut next_picks) {
                Ok(()) => {
                    *constraints = next_constraints;
                    *picks = next_picks;
                    return Ok(());
                }
                Err(e @ SolveError::Exhausted { .. }) => return Err(e),
                Err(e) => {
                    // Learn ONLY IF THE FAILURE IS ATTRIBUTABLE to this
                    // candidate. This is the whole soundness question and the
                    // first version got it wrong.
                    //
                    // "The subtree failed, so the assignment is dead" is FALSE:
                    // the subtree also carries constraints inherited from the
                    // caller, so it may have failed for a reason that has
                    // nothing to do with this candidate. Recording it anyway
                    // marks good candidates dead, and with enough of them every
                    // version of some package gets crossed off — the solver
                    // then reports an unsatisfiable graph that is perfectly
                    // satisfiable. My own test caught exactly that: a
                    // `Conflict` on `free0`, a package with no constraints at
                    // all.
                    //
                    // Sound rule: the failure is attributable when every
                    // requirement bearing on the failing package comes from
                    // either the ROOT or from THIS candidate. Root requirements
                    // are invariant across the whole search, so if no sibling
                    // choice contributed, no sibling choice could have caused
                    // it — and the assignment really is dead everywhere.
                    //
                    // This learns strictly less than PubGrub, which tracks the
                    // full derivation and can attribute through several hops.
                    // It is the part that is sound without one.
                    if attributable_to(&e, &name, candidate) {
                        self.learned.record(&name, candidate);
                    }
                    last_conflict = Some(e);
                }
            }
        }

        Err(last_conflict.unwrap_or_else(|| {
            SolveError::Conflict(Conflict {
                package: name.clone(),
                requirements: chain,
                available: newest_first(self.registry.versions(&name)),
            })
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(a: u64, b: u64, c: u64) -> Version {
        Version::new(a, b, c)
    }

    fn r(s: &str) -> Range {
        Range::parse(s).expect("range")
    }

    fn solve(reg: &MapRegistry, root: Manifest) -> Result<Resolution, SolveError> {
        Solver::new(reg).solve(&root)
    }

    #[test]
    fn a_single_dependency_resolves_to_the_newest_match() {
        let mut reg = MapRegistry::new();
        reg.add("a", v(1, 0, 0), Manifest::new())
            .add("a", v(1, 5, 0), Manifest::new())
            .add("a", v(2, 0, 0), Manifest::new());
        let out = solve(&reg, Manifest::new().needing("a", r("^1.0.0"))).expect("resolve");
        assert_eq!(out.picks["a"], v(1, 5, 0), "newest within the range");
    }

    #[test]
    fn transitive_dependencies_resolve() {
        let mut reg = MapRegistry::new();
        reg.add("a", v(1, 0, 0), Manifest::new().needing("b", r("^1.0.0")))
            .add("b", v(1, 2, 0), Manifest::new().needing("c", r(">=0.1.0")))
            .add("c", v(0, 4, 0), Manifest::new());
        let out = solve(&reg, Manifest::new().needing("a", r("^1.0.0"))).expect("resolve");
        assert_eq!(out.picks.len(), 3);
        assert_eq!(out.picks["c"], v(0, 4, 0));
    }

    /// **Backtracking.** The newest `a` needs a `b` that does not exist, so the
    /// solver must fall back to an older `a` rather than reporting failure.
    #[test]
    fn the_solver_backtracks_past_an_unsatisfiable_newest_version() {
        let mut reg = MapRegistry::new();
        reg.add("a", v(2, 0, 0), Manifest::new().needing("b", r("^9.0.0")))
            .add("a", v(1, 0, 0), Manifest::new().needing("b", r("^1.0.0")))
            .add("b", v(1, 0, 0), Manifest::new());
        let out = solve(&reg, Manifest::new().needing("a", r("*"))).expect("must backtrack");
        assert_eq!(out.picks["a"], v(1, 0, 0), "a 2.0.0 is unsatisfiable");
        assert_eq!(out.picks["b"], v(1, 0, 0));
    }

    /// A failed branch must leave nothing behind. Without speculation on a
    /// copy, the rejected candidate's constraints poison the retry and the
    /// solver reports a conflict that does not exist.
    #[test]
    fn a_rejected_candidate_does_not_poison_the_retry() {
        let mut reg = MapRegistry::new();
        reg.add(
            "a",
            v(2, 0, 0),
            Manifest::new().needing("shared", r("^2.0.0")),
        )
        .add(
            "a",
            v(1, 0, 0),
            Manifest::new().needing("shared", r("^1.0.0")),
        )
        .add("shared", v(1, 0, 0), Manifest::new());
        // The root also pins `shared` to 1.x, so a@2.0.0 must fail and a@1.0.0
        // must then succeed against an UNPOLLUTED constraint set.
        let out = solve(
            &reg,
            Manifest::new()
                .needing("a", r("*"))
                .needing("shared", r("^1.0.0")),
        )
        .expect("a@1.0.0 must still resolve");
        assert_eq!(out.picks["a"], v(1, 0, 0));
        assert_eq!(out.picks["shared"], v(1, 0, 0));
    }

    /// **A conflict names both sides and the coordinate.** This is the whole
    /// point: "could not find compatible versions" is the message this exists
    /// to avoid.
    #[test]
    fn a_conflict_names_both_requirements_and_what_was_available() {
        let mut reg = MapRegistry::new();
        reg.add(
            "left",
            v(1, 0, 0),
            Manifest::new().needing("shared", r("^1.0.0")),
        )
        .add(
            "right",
            v(1, 0, 0),
            Manifest::new().needing("shared", r("^2.0.0")),
        )
        .add("shared", v(1, 0, 0), Manifest::new())
        .add("shared", v(2, 0, 0), Manifest::new());
        let err = solve(
            &reg,
            Manifest::new()
                .needing("left", r("*"))
                .needing("right", r("*")),
        )
        .expect_err("1.x and 2.x cannot both hold");

        let SolveError::Conflict(c) = err else {
            panic!("expected a Conflict, got {err:?}");
        };
        assert_eq!(c.package, "shared");
        let text = c.to_string();
        assert!(text.contains("left"), "must name the left side: {text}");
        assert!(text.contains("right"), "must name the right side: {text}");
        assert!(
            text.contains("^1.0.0") && text.contains("^2.0.0"),
            "must name both ranges: {text}"
        );
        assert!(
            text.contains("1.0.0, ") || text.contains("2.0.0"),
            "must list what was available: {text}"
        );
    }

    /// "Never published" and "published but none satisfied" are different
    /// problems with different fixes, so they read differently.
    #[test]
    fn an_unpublished_package_is_distinguishable_from_an_unsatisfiable_one() {
        let reg = MapRegistry::new();
        let err = solve(&reg, Manifest::new().needing("ghost", r("*"))).expect_err("no versions");
        assert!(
            err.to_string()
                .contains("no versions of `ghost` are published"),
            "got {err}"
        );

        let mut reg2 = MapRegistry::new();
        reg2.add("real", v(1, 0, 0), Manifest::new());
        let err2 =
            solve(&reg2, Manifest::new().needing("real", r("^5.0.0"))).expect_err("no match");
        let text = err2.to_string();
        assert!(!text.contains("no versions"), "it IS published: {text}");
        assert!(text.contains("available: 1.0.0"), "{text}");
    }

    /// **Determinism.** Same input, same resolution AND same error — a resolver
    /// whose output depends on iteration order is one nobody can reproduce a
    /// bug in.
    #[test]
    fn resolution_is_deterministic() {
        let mut reg = MapRegistry::new();
        reg.add("a", v(1, 0, 0), Manifest::new().needing("c", r("*")))
            .add("b", v(1, 0, 0), Manifest::new().needing("c", r("*")))
            .add("c", v(1, 0, 0), Manifest::new())
            .add("c", v(1, 1, 0), Manifest::new());
        let root = Manifest::new().needing("a", r("*")).needing("b", r("*"));
        let first = solve(&reg, root.clone()).expect("resolve");
        for _ in 0..8 {
            assert_eq!(solve(&reg, root.clone()).expect("resolve"), first);
        }
    }

    /// **Giving up is not proof of unsatisfiability.** Conflating the two lets
    /// a solver claim a graph is impossible when it merely ran out of budget.
    #[test]
    fn exhaustion_is_reported_as_its_own_case_not_as_a_conflict() {
        let mut reg = MapRegistry::new();
        // Enough candidates that a 1-step budget cannot finish.
        for patch in 0..20 {
            reg.add(
                "a",
                v(1, 0, patch),
                Manifest::new().needing("b", r("^9.0.0")),
            );
        }
        reg.add("b", v(1, 0, 0), Manifest::new());
        let err = Solver::new(&reg)
            .with_max_steps(1)
            .solve(&Manifest::new().needing("a", r("*")))
            .expect_err("must give up");
        assert!(
            matches!(err, SolveError::Exhausted { .. }),
            "expected Exhausted, got {err:?}"
        );
        assert!(
            err.to_string().contains("not proof"),
            "the message must not read as unsatisfiability: {err}"
        );
    }

    /// Anti-vacuity: the same graph with a generous budget resolves, so the
    /// exhaustion above is the budget's doing and not a real conflict.
    #[test]
    fn the_same_graph_resolves_with_a_normal_budget() {
        let mut reg = MapRegistry::new();
        for patch in 0..20 {
            reg.add(
                "a",
                v(1, 0, patch),
                Manifest::new().needing("b", r("^9.0.0")),
            );
        }
        reg.add("a", v(0, 9, 0), Manifest::new());
        reg.add("b", v(1, 0, 0), Manifest::new());
        let out = Solver::new(&reg)
            .solve(&Manifest::new().needing("a", r("*")))
            .expect("resolves with a real budget");
        assert_eq!(out.picks["a"], v(0, 9, 0));
    }

    /// An empty root resolves to nothing, rather than erroring or inventing a
    /// pick.
    #[test]
    fn an_empty_root_resolves_to_an_empty_set() {
        let reg = MapRegistry::new();
        let out = solve(&reg, Manifest::new()).expect("resolve");
        assert!(out.picks.is_empty());
    }

    /// A diamond — two paths to one package — resolves to ONE version, not two.
    #[test]
    fn a_diamond_resolves_to_a_single_shared_version() {
        let mut reg = MapRegistry::new();
        reg.add(
            "left",
            v(1, 0, 0),
            Manifest::new().needing("shared", r(">=1.0.0")),
        )
        .add(
            "right",
            v(1, 0, 0),
            Manifest::new().needing("shared", r("^1.2.0")),
        )
        .add("shared", v(1, 0, 0), Manifest::new())
        .add("shared", v(1, 5, 0), Manifest::new())
        .add("shared", v(2, 0, 0), Manifest::new());
        let out = solve(
            &reg,
            Manifest::new()
                .needing("left", r("*"))
                .needing("right", r("*")),
        )
        .expect("resolve");
        assert_eq!(
            out.picks["shared"],
            v(1, 5, 0),
            "the intersection of >=1.0.0 and ^1.2.0, newest first"
        );
    }
}

#[cfg(test)]
mod learning {
    use super::*;

    fn v(a: u64, b: u64, c: u64) -> Version {
        Version::new(a, b, c)
    }
    fn r(s: &str) -> Range {
        Range::parse(s).expect("range")
    }

    /// A graph that forces the SAME dead end to be reached from many paths.
    ///
    /// `n` independent packages named `aaa*` each have two versions and no
    /// constraints, so the solver enumerates 2^n combinations of them. `zzz`
    /// sorts LAST, so every one of those combinations reaches it — and every
    /// `zzz` version needs a `ghost` that does not exist.
    ///
    /// The names matter and the first version of this fixture got them wrong.
    /// Selection is BTreeMap order, so `doomed` sorted *before* `free*`: the
    /// dead end was reached once, learned, and never revisited, and the test
    /// measured nothing. Repetition has to be constructed, not assumed.
    ///
    /// The solve FAILS either way. The win is entirely in the work avoided,
    /// which is the honest thing to measure — an optimisation that changed the
    /// answer would be a bug.
    fn repeated_dead_end(n: usize) -> (MapRegistry, Manifest) {
        let mut reg = MapRegistry::new();
        let mut root = Manifest::new();
        for i in 0..n {
            let name = format!("aaa{i}");
            reg.add(&name, v(1, 0, 0), Manifest::new());
            reg.add(&name, v(2, 0, 0), Manifest::new());
            root = root.needing(&name, r("*"));
        }
        for patch in 0..6 {
            reg.add(
                "zzz",
                v(1, 0, patch),
                Manifest::new().needing("ghost", r("^9.0.0")),
            );
        }
        root = root.needing("zzz", r("*"));
        (reg, root)
    }

    /// **Learning proves the dead end once and skips it thereafter.**
    ///
    /// Six `zzz` versions, each reached from every combination of the free
    /// packages. Without learning each combination re-derives all six; with it
    /// they are condemned on the first pass and skipped after.
    #[test]
    fn learning_skips_a_dead_end_already_proved() {
        let (reg, root) = repeated_dead_end(5);
        let mut solver = Solver::new(&reg);
        solver.solve(&root).expect_err("the graph is unsatisfiable");
        assert!(
            solver.skipped_by_learning() >= 6,
            "the dead end must be re-reached and skipped, not re-derived;              skipped={} steps={}",
            solver.skipped_by_learning(),
            solver.steps_taken()
        );
    }

    /// **The dead end costs a CONSTANT, not a multiple.**
    ///
    /// Doubling the free packages multiplies the combinations — that work is
    /// real and unavoidable. What must not multiply is the dead end: the six
    /// `zzz` versions are attempted once in total either way, so the extra
    /// steps between the two runs come from enumeration alone.
    #[test]
    fn the_dead_end_is_paid_for_once_regardless_of_branching() {
        let mut attempts = Vec::new();
        for n in [3usize, 6] {
            let (reg, root) = repeated_dead_end(n);
            let mut solver = Solver::new(&reg);
            solver.solve(&root).expect_err("unsatisfiable");
            // Steps count ATTEMPTED candidates; skips are not steps. The
            // difference between total reaches and attempts is what learning
            // saved.
            attempts.push((solver.steps_taken(), solver.skipped_by_learning()));
        }
        let (small_steps, small_skipped) = attempts[0];
        let (large_steps, large_skipped) = attempts[1];
        assert!(
            large_skipped > small_skipped,
            "more branching must mean more skips, not more work: {attempts:?}"
        );
        // The six doomed attempts are a constant inside both step counts.
        assert!(
            large_steps - small_steps < large_skipped,
            "the growth in real work must be smaller than what learning avoided: \
             {attempts:?}"
        );
    }

    /// Anti-vacuity: learning must not change ANSWERS    /// Anti-vacuity: learning must not change ANSWERS, only work. A cache that
    /// alters resolutions is a bug wearing an optimisation's clothes.
    #[test]
    fn learning_never_changes_the_resolution() {
        let mut reg = MapRegistry::new();
        reg.add("a", v(2, 0, 0), Manifest::new().needing("b", r("^9.0.0")))
            .add("a", v(1, 0, 0), Manifest::new().needing("b", r("^1.0.0")))
            .add("b", v(1, 0, 0), Manifest::new())
            .add("c", v(1, 0, 0), Manifest::new().needing("a", r("*")));
        let root = Manifest::new().needing("a", r("*")).needing("c", r("*"));

        let mut solver = Solver::new(&reg);
        let learned = solver.solve(&root).expect("resolve");
        assert_eq!(learned.picks["a"], v(1, 0, 0));
        assert_eq!(learned.picks["b"], v(1, 0, 0));
    }

    /// **A conflict must still be reported, and still name both sides.**
    /// Learning prunes the search; it must not prune the explanation.
    #[test]
    fn learning_does_not_degrade_the_conflict_report() {
        let mut reg = MapRegistry::new();
        reg.add(
            "left",
            v(1, 0, 0),
            Manifest::new().needing("shared", r("^1.0.0")),
        )
        .add(
            "right",
            v(1, 0, 0),
            Manifest::new().needing("shared", r("^2.0.0")),
        )
        .add("shared", v(1, 0, 0), Manifest::new())
        .add("shared", v(2, 0, 0), Manifest::new());
        let err = Solver::new(&reg)
            .solve(
                &Manifest::new()
                    .needing("left", r("*"))
                    .needing("right", r("*")),
            )
            .expect_err("unsatisfiable");
        let text = err.to_string();
        assert!(text.contains("left") && text.contains("right"), "{text}");
        assert!(text.contains("^1.0.0") && text.contains("^2.0.0"), "{text}");
    }

    /// Learning is per-solve, not shared across calls — a `Solver` reused
    /// against a DIFFERENT registry must not carry stale facts.
    #[test]
    fn learned_facts_do_not_leak_between_solves() {
        let mut reg = MapRegistry::new();
        reg.add("a", v(1, 0, 0), Manifest::new().needing("ghost", r("*")));
        let mut solver = Solver::new(&reg);
        assert!(solver.solve(&Manifest::new().needing("a", r("*"))).is_err());

        // Same solver, a root that CAN be satisfied. If `a@1.0.0` stayed marked
        // dead the second solve would wrongly fail.
        let mut reg2 = MapRegistry::new();
        reg2.add("a", v(1, 0, 0), Manifest::new());
        let mut solver2 = Solver::new(&reg2);
        assert!(solver2.solve(&Manifest::new().needing("a", r("*"))).is_ok());
        assert_eq!(solver2.skipped_by_learning(), 0);
    }
}

#[cfg(test)]
mod soundness {
    use super::*;

    fn v(a: u64, b: u64, c: u64) -> Version {
        Version::new(a, b, c)
    }
    fn r(s: &str) -> Range {
        Range::parse(s).expect("range")
    }

    /// **The graph that catches unsound learning.**
    ///
    /// `p` is chosen before `q`. Under `p@2` the shared constraint narrows to
    /// `^2`, so `q@1`'s own `^1` demand intersects to empty and `q@1` fails —
    /// *in that context*. Under `p@1` it is perfectly fine.
    ///
    /// A solver that condemns `q@1` on that first failure skips it when `p@1`
    /// is tried, finds `q` has no candidates left, and reports an
    /// **unsatisfiable graph that is satisfiable**. That is the worst class of
    /// bug an optimisation can introduce: not slower, WRONG.
    ///
    /// I wrote that solver twice before writing this test — once learning on
    /// any subtree failure, once learning on any empty intersection. Both
    /// passed every other test in this file.
    fn context_dependent_failure() -> (MapRegistry, Manifest) {
        let mut reg = MapRegistry::new();
        reg.add(
            "p",
            v(2, 0, 0),
            Manifest::new().needing("shared", r("^2.0.0")),
        )
        .add(
            "p",
            v(1, 0, 0),
            Manifest::new().needing("shared", r("^1.0.0")),
        )
        .add(
            "q",
            v(1, 0, 0),
            Manifest::new().needing("shared", r("^1.0.0")),
        )
        .add("shared", v(1, 0, 0), Manifest::new())
        .add("shared", v(2, 0, 0), Manifest::new());
        (
            reg,
            Manifest::new().needing("p", r("*")).needing("q", r("*")),
        )
    }

    /// A failure in ONE caller context must not condemn the candidate in
    /// another.
    #[test]
    fn a_context_dependent_failure_does_not_condemn_the_candidate() {
        let (reg, root) = context_dependent_failure();
        let out = Solver::new(&reg)
            .solve(&root)
            .expect("this graph IS satisfiable: p@1 + q@1 + shared@1");
        assert_eq!(out.picks["p"], v(1, 0, 0));
        assert_eq!(out.picks["q"], v(1, 0, 0));
        assert_eq!(out.picks["shared"], v(1, 0, 0));
    }

    /// **The same trap one level deeper — a context-dependent SUBTREE failure.**
    ///
    /// Under `p@2`, `q@1` itself intersects fine; it is `mid@1`, one hop below,
    /// that collides with the narrowed `shared`. So `q@1`'s whole subtree fails
    /// in that context and succeeds under `p@1`.
    ///
    /// This is a separate gate from the direct case because it exercises a
    /// separate branch: condemning on subtree failure and condemning on empty
    /// intersection are two different pieces of code, and a test for one does
    /// not cover the other. Both were unsound; only one was caught until this
    /// existed.
    #[test]
    fn a_context_dependent_subtree_failure_does_not_condemn_the_candidate() {
        let mut reg = MapRegistry::new();
        reg.add(
            "p",
            v(2, 0, 0),
            Manifest::new().needing("shared", r("^2.0.0")),
        )
        .add(
            "p",
            v(1, 0, 0),
            Manifest::new().needing("shared", r("^1.0.0")),
        )
        .add("q", v(1, 0, 0), Manifest::new().needing("mid", r("^1.0.0")))
        .add(
            "mid",
            v(1, 0, 0),
            Manifest::new().needing("shared", r("^1.0.0")),
        )
        .add("shared", v(1, 0, 0), Manifest::new())
        .add("shared", v(2, 0, 0), Manifest::new());

        let out = Solver::new(&reg)
            .solve(&Manifest::new().needing("p", r("*")).needing("q", r("*")))
            .expect("satisfiable: p@1 + q@1 + mid@1 + shared@1");
        assert_eq!(out.picks["p"], v(1, 0, 0));
        assert_eq!(out.picks["q"], v(1, 0, 0));
        assert_eq!(out.picks["mid"], v(1, 0, 0));
    }

    /// The same property stated over the whole search: learning may change how
    /// long a solve takes and must never change what it returns.
    #[test]
    fn learning_is_answer_preserving_across_a_family_of_graphs() {
        let mut reg = MapRegistry::new();
        reg.add("app", v(1, 0, 0), Manifest::new().needing("lib", r("*")))
            .add(
                "lib",
                v(3, 0, 0),
                Manifest::new().needing("core", r("^3.0.0")),
            )
            .add(
                "lib",
                v(2, 0, 0),
                Manifest::new().needing("core", r("^2.0.0")),
            )
            .add(
                "lib",
                v(1, 0, 0),
                Manifest::new().needing("core", r("^1.0.0")),
            )
            .add("core", v(1, 0, 0), Manifest::new())
            .add("core", v(2, 0, 0), Manifest::new());

        // Pinning `core` to 1.x makes lib@3 and lib@2 fail in THIS context
        // while both are fine in others.
        let root = Manifest::new()
            .needing("app", r("*"))
            .needing("core", r("^1.0.0"));
        let out = Solver::new(&reg).solve(&root).expect("lib@1 satisfies it");
        assert_eq!(out.picks["lib"], v(1, 0, 0));
        assert_eq!(out.picks["core"], v(1, 0, 0));
    }
}
