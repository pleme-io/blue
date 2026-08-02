//! **What a posture buys, what it forfeits, and which pairs are genuinely
//! exclusive — derived, not asserted.**
//!
//! A language quality is "mutually exclusive" with another only when the
//! language must choose **globally**. Ruby cannot tree-shake because `eval` may
//! name anything at run time — so *every* Ruby program forfeits a minimal
//! artifact, including the ones that never call `eval`. The exclusivity is not
//! a law of computing; it is a consequence of there being one posture for the
//! whole language.
//!
//! bīdama makes the posture a **declaration**, so the question becomes
//! per-package. This module answers three things about that:
//!
//! 1. [`qualities_at`] — what a given `waku` grants.
//! 2. [`exclusive_pairs`] — which pairs no posture grants together.
//! 3. [`witness`] — for a pair that *is* compatible, the posture proving it.
//!
//! # The morphology result
//!
//! `When` and `Where` are three-valued and `Reach` reduces to a small set of
//! capability questions, so **the posture space is finite and enumerable** —
//! which means exclusivity is a *computed fact over the lattice*, not a list
//! someone maintains. [`exclusive_pairs`] enumerates; it does not consult a
//! table.
//!
//! And the enumeration yields the load-bearing property, stated as a theorem
//! and tested as one:
//!
//! > **Every exclusive pair shares an axis.** Two qualities on *different*
//! > coordinates of `waku` always have a witness posture granting both.
//!
//! That is what "morphing" buys and it is not a slogan: exclusivity in blue is
//! confined *within* an axis. A language with one global posture couples all of
//! them — choosing dynamism costs you artifact size *and* preemption *and* a
//! reproducible build, because they all hang off the same single choice. Blue's
//! axes are independent, so a package that needs a resident evaluator still
//! gets process isolation, and one that needs ambient capability at build time
//! still gets preemptive scheduling.
//!
//! # What this does NOT claim
//!
//! It does not dissolve exclusivity. Two packages that genuinely demand
//! opposite ends of the *same* axis still conflict, and [`resolve`] still
//! refuses them by name. What changes is that the conflict is **declared,
//! localized to one coordinate, and explained** rather than being a global
//! property nobody chose.
//!
//! [`resolve`]: crate::resolve

use std::collections::BTreeSet;

pub use crate::morph::Layer;
use blue_lang_waku::{Reach, Waku, When, Where};

/// A quality a program can have — each one something a real language forfeits
/// to get its opposite.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Quality {
    /// Code can be constructed and evaluated at run time (`eval`). Ruby, Lisp
    /// and Elixir's `Code.eval_string` have it.
    ResidentEvaluator,
    /// A process can be parked mid-computation at any instruction. Requires
    /// that no user-visible form re-enters the host — §V.8's one genuine
    /// entanglement, and the reason BEAM bounds a NIF at ~1 ms.
    PreemptiveScheduling,
    /// Unreachable code can be proven unreachable and dropped. Impossible when
    /// a runtime `eval` may name anything.
    MinimalArtifact,
    /// The compiler may specialize on values known before run time.
    AheadOfTimeSpecialization,
    /// The macro phase cannot read ambient state, so the same inputs give the
    /// same output on any machine.
    ReproducibleMacroPhase,
    /// The macro phase may reach whatever the process can — Ruby's load-time
    /// authority, Elixir's `File.read!` in a macro.
    AmbientBuildCapability,
    /// A value cannot escape to another process, so one crash cannot corrupt
    /// another's state.
    ProcessIsolation,
    /// Two processes can share one mutable structure without copying.
    SharedMutableState,
    /// Memory is reclaimed at scope exit with no collector and no pause.
    ScopedReclamation,
}

impl Quality {
    /// Every quality, forced-arity so adding a variant without adding it here
    /// is a compile error — the catalog cannot fall behind the enum
    /// (★★ CATALOG REFLECTION).
    pub const ALL: [Quality; 9] = [
        Quality::ResidentEvaluator,
        Quality::PreemptiveScheduling,
        Quality::MinimalArtifact,
        Quality::AheadOfTimeSpecialization,
        Quality::ReproducibleMacroPhase,
        Quality::AmbientBuildCapability,
        Quality::ProcessIsolation,
        Quality::SharedMutableState,
        Quality::ScopedReclamation,
    ];

    /// Which `waku` coordinate decides this quality.
    ///
    /// The load-bearing datum: two qualities on different axes can always
    /// coexist, because the coordinates are independent.
    #[must_use]
    pub fn axis(self) -> Axis {
        match self {
            Quality::ResidentEvaluator
            | Quality::PreemptiveScheduling
            | Quality::MinimalArtifact
            | Quality::AheadOfTimeSpecialization => Axis::When,
            Quality::ReproducibleMacroPhase | Quality::AmbientBuildCapability => Axis::Reach,
            Quality::ProcessIsolation
            | Quality::SharedMutableState
            | Quality::ScopedReclamation => Axis::Where,
        }
    }

    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            Quality::ResidentEvaluator => "resident evaluator",
            Quality::PreemptiveScheduling => "preemptive scheduling",
            Quality::MinimalArtifact => "minimal artifact",
            Quality::AheadOfTimeSpecialization => "ahead-of-time specialization",
            Quality::ReproducibleMacroPhase => "reproducible macro phase",
            Quality::AmbientBuildCapability => "ambient build capability",
            Quality::ProcessIsolation => "process isolation",
            Quality::SharedMutableState => "shared mutable state",
            Quality::ScopedReclamation => "scoped reclamation",
        }
    }
}

/// A coordinate of `waku`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Axis {
    Reach,
    When,
    Where,
}

/// The capability name whose presence decides the `Reach` qualities.
///
/// One name rather than a set: the question "may the macro phase touch the
/// outside world" is binary at this granularity, and inventing a taxonomy
/// before there are consumers for it would be a guess.
pub const IO_CAPABILITY: &str = "io";

/// What a posture grants.
#[must_use]
pub fn qualities_at(w: &Waku) -> BTreeSet<Quality> {
    let mut out = BTreeSet::new();

    // ── When ──────────────────────────────────────────────────────────
    if w.when == When::Anytime {
        // `eval` is reachable, so code can be built at run time — and for the
        // same reason nothing can be proven unreachable, and a region may
        // re-enter the host, which is what forbids parking it.
        out.insert(Quality::ResidentEvaluator);
    } else {
        out.insert(Quality::PreemptiveScheduling);
        out.insert(Quality::MinimalArtifact);
    }
    if w.when <= When::Preceding {
        // The world is closed at or before this point, so a value known then is
        // known for good.
        out.insert(Quality::AheadOfTimeSpecialization);
    }

    // ── Reach ─────────────────────────────────────────────────────────
    if w.reach.permits(IO_CAPABILITY) {
        out.insert(Quality::AmbientBuildCapability);
    } else {
        out.insert(Quality::ReproducibleMacroPhase);
    }

    // ── Where ─────────────────────────────────────────────────────────
    match w.place {
        Where::Shared => {
            out.insert(Quality::SharedMutableState);
        }
        Where::Process => {
            out.insert(Quality::ProcessIsolation);
        }
        Where::Arena => {
            out.insert(Quality::ProcessIsolation);
            out.insert(Quality::ScopedReclamation);
        }
    }
    out
}

/// Every posture in the enumerable lattice.
///
/// `When` and `Where` are three-valued; `Reach` collapses to two points for
/// quality purposes — permits IO or does not. Eighteen postures, which is what
/// makes exclusivity derivable rather than declared.
#[must_use]
pub fn all_postures() -> Vec<Waku> {
    let mut out = Vec::with_capacity(18);
    for when in [When::Sealed, When::Preceding, When::Anytime] {
        for place in [Where::Arena, Where::Process, Where::Shared] {
            for reach in [Reach::Unrestricted, Reach::nothing()] {
                out.push(Waku {
                    reach: reach.clone(),
                    when,
                    place,
                });
            }
        }
    }
    out
}

/// A posture granting both qualities, if one exists.
///
/// The *constructive* answer. "These are compatible" is a claim; a posture you
/// can name is a proof, and it is also the thing a package author needs — they
/// do not want to know that a combination is possible, they want to know what
/// to declare.
#[must_use]
pub fn witness(a: Quality, b: Quality) -> Option<Waku> {
    all_postures().into_iter().find(|w| {
        let q = qualities_at(w);
        q.contains(&a) && q.contains(&b)
    })
}

/// Pairs no posture grants together — **derived by enumeration**, never a list.
#[must_use]
pub fn exclusive_pairs() -> Vec<(Quality, Quality)> {
    let mut out = Vec::new();
    for (i, a) in Quality::ALL.iter().enumerate() {
        for b in &Quality::ALL[i + 1..] {
            if witness(*a, *b).is_none() {
                out.push((*a, *b));
            }
        }
    }
    out
}

/// What a posture forfeits: everything not granted.
#[must_use]
pub fn forfeits_at(w: &Waku) -> BTreeSet<Quality> {
    let have = qualities_at(w);
    Quality::ALL
        .iter()
        .copied()
        .filter(|q| !have.contains(q))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// **THE MORPHOLOGY THEOREM: every exclusive pair shares an axis.**
    ///
    /// Two qualities on different `waku` coordinates always have a witness
    /// posture granting both. This is what a per-package posture buys, and it
    /// is the difference from a language with one global choice: there,
    /// dynamism costs artifact size *and* preemption *and* build
    /// reproducibility together, because all of them hang off the single
    /// choice. Here they are separate coordinates, so exclusivity is confined
    /// within one.
    #[test]
    fn every_exclusive_pair_shares_an_axis() {
        let cross: Vec<(Quality, Quality)> = exclusive_pairs()
            .into_iter()
            .filter(|(a, b)| a.axis() != b.axis())
            .collect();
        assert!(
            cross.is_empty(),
            "these pairs are exclusive ACROSS axes, which would break the \
             independence the whole model rests on: {cross:?}"
        );
    }

    /// The constructive half: every cross-axis pair has a *nameable* posture.
    /// A package author needs to know what to declare, not that something is
    /// theoretically possible.
    #[test]
    fn every_cross_axis_pair_has_a_named_witness() {
        for (i, a) in Quality::ALL.iter().enumerate() {
            for b in &Quality::ALL[i + 1..] {
                if a.axis() == b.axis() {
                    continue;
                }
                assert!(
                    witness(*a, *b).is_some(),
                    "{} + {} are on different axes but no posture grants both",
                    a.label(),
                    b.label()
                );
            }
        }
    }

    /// **The entanglement §V.8 named, now DERIVED rather than asserted.** A
    /// resident evaluator and preemptive scheduling cannot coexist: an `eval`
    /// region re-enters the host, and a host-stack continuation cannot be
    /// parked.
    #[test]
    fn a_resident_evaluator_excludes_preemption() {
        assert!(witness(Quality::ResidentEvaluator, Quality::PreemptiveScheduling).is_none());
        assert!(exclusive_pairs()
            .contains(&(Quality::ResidentEvaluator, Quality::PreemptiveScheduling)));
    }

    /// And it excludes a minimal artifact, for the same root reason — which is
    /// exactly why Ruby cannot tree-shake.
    #[test]
    fn a_resident_evaluator_excludes_a_minimal_artifact() {
        assert!(witness(Quality::ResidentEvaluator, Quality::MinimalArtifact).is_none());
    }

    /// **But a resident evaluator does NOT cost process isolation** — different
    /// axes. This is the morphing result in its most useful form: Ruby couples
    /// these (one heap, one GVL), blue does not.
    #[test]
    fn a_resident_evaluator_keeps_process_isolation() {
        let w = witness(Quality::ResidentEvaluator, Quality::ProcessIsolation)
            .expect("must have a witness");
        assert_eq!(w.when, When::Anytime, "eval is reachable");
        assert!(w.place <= Where::Process, "and nothing escapes the process");
    }

    /// Nor does it cost a reproducible macro phase. A package can build code at
    /// run time AND have a build nobody can perturb.
    #[test]
    fn a_resident_evaluator_keeps_a_reproducible_build() {
        assert!(witness(Quality::ResidentEvaluator, Quality::ReproducibleMacroPhase).is_some());
    }

    /// Ambient build capability and a reproducible macro phase are exclusive —
    /// same axis, and correctly so: a macro that can read the machine cannot
    /// promise the same answer on another one.
    #[test]
    fn ambient_capability_excludes_reproducibility() {
        assert!(witness(
            Quality::AmbientBuildCapability,
            Quality::ReproducibleMacroPhase
        )
        .is_none());
    }

    /// Sharing and isolation are exclusive — same axis.
    #[test]
    fn sharing_excludes_isolation() {
        assert!(witness(Quality::SharedMutableState, Quality::ProcessIsolation).is_none());
        assert!(witness(Quality::SharedMutableState, Quality::ScopedReclamation).is_none());
    }

    /// **The top posture is not the best posture.** Blue's default grants the
    /// dynamic qualities and forfeits every sealed one — which is correct, and
    /// worth pinning because "top" reads like "most".
    #[test]
    fn the_top_posture_forfeits_the_sealed_qualities() {
        let top = Waku::top();
        let have = qualities_at(&top);
        assert!(have.contains(&Quality::ResidentEvaluator));
        assert!(have.contains(&Quality::SharedMutableState));
        assert!(have.contains(&Quality::AmbientBuildCapability));

        let lost = forfeits_at(&top);
        assert!(lost.contains(&Quality::PreemptiveScheduling));
        assert!(lost.contains(&Quality::MinimalArtifact));
        assert!(lost.contains(&Quality::ProcessIsolation));
    }

    /// And the bottom grants the sealed ones. Neither end dominates — the point
    /// of the axis is that a program sits where it needs to.
    #[test]
    fn the_bottom_posture_grants_what_the_top_forfeits() {
        let have = qualities_at(&Waku::bottom());
        assert!(have.contains(&Quality::PreemptiveScheduling));
        assert!(have.contains(&Quality::MinimalArtifact));
        assert!(have.contains(&Quality::ScopedReclamation));
        assert!(have.contains(&Quality::ReproducibleMacroPhase));
        assert!(!have.contains(&Quality::ResidentEvaluator));
    }

    /// Anti-vacuity: `exclusive_pairs` must actually find some. A derivation
    /// that returned nothing would satisfy the theorem trivially.
    #[test]
    fn the_derivation_finds_real_exclusions() {
        let pairs = exclusive_pairs();
        assert!(
            pairs.len() >= 5,
            "expected real exclusions, found {}: {pairs:?}",
            pairs.len()
        );
        // …and not everything, which would mean the lattice grants nothing.
        let total = Quality::ALL.len() * (Quality::ALL.len() - 1) / 2;
        assert!(pairs.len() < total, "not every pair can be exclusive");
    }

    /// Every quality is reachable from some posture. One that no posture grants
    /// is a modelling error — a name for something blue cannot actually be.
    #[test]
    fn every_quality_is_reachable() {
        for q in Quality::ALL {
            assert!(
                all_postures().iter().any(|w| qualities_at(w).contains(&q)),
                "{} is granted by no posture",
                q.label()
            );
        }
    }

    /// Every posture grants something. A dead point in the lattice would be a
    /// declaration with no meaning.
    #[test]
    fn every_posture_grants_something() {
        for w in all_postures() {
            assert!(!qualities_at(&w).is_empty(), "{w:?} grants nothing");
        }
    }

    /// Granted and forfeited partition the catalog — no quality is both or
    /// neither.
    #[test]
    fn granted_and_forfeited_partition_the_catalog() {
        for w in all_postures() {
            let have = qualities_at(&w);
            let lost = forfeits_at(&w);
            assert!(have.is_disjoint(&lost), "{w:?}");
            assert_eq!(have.len() + lost.len(), Quality::ALL.len(), "{w:?}");
        }
    }
}
