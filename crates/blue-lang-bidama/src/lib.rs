//! `bīdama` (ビー玉) — a blue package, and posture resolution over a set of them.
//!
//! The name is a find rather than a coinage: the ビー derives from ビードロ
//! *bīdoro*, from Portuguese **vidro**, *glass*. The fleet's two naming
//! languages meet inside one word, and it lands in the window family blue
//! already opened — **mado** (window) → **garasu** (glass) → **waku** (the
//! frame) → **bīdama** (the small glass thing that fits with others).
//!
//! ## Floors only. Ceilings live at the root.
//!
//! `theory/BLUE.md` §V.19 first had a package declare both a floor and a
//! ceiling. §V.24 corrected it: **a leaf-side ceiling is Cargo's documented
//! anti-pattern by name**, and the only mechanism that manufactures an
//! absorbing axis out of a gradient. So:
//!
//! - a [`Bidama`] declares a **floor** — the least frame it needs;
//! - the **root** declares the ceiling — the most the application permits.
//!
//! Resolution is then one line of lattice arithmetic: **join the floors,
//! check the join fits under the ceiling.** `a ∨ b ⊑ ceiling`.
//!
//! ## What this is not
//!
//! Not a version solver. §V.24 established that the shape survives — one
//! CDCL solver over two `VersionSet` implementations — but that **the
//! pricing does not**: conflicts are what make resolution NP-complete, and
//! ceilings *are* the conflicts. Version solving is a separate, larger
//! piece of work; this crate resolves *postures* over an already-chosen set.
//!
//! ## The honest scope
//!
//! §V.24's measured finding is that blue has **exactly one** axis that can
//! produce a mutual exclusion — [`When`]'s resident-evaluator bit, one bit
//! per artifact. Every other coordinate is per-declaration and
//! **structurally cannot partition an ecosystem**. So blue's fragmentation
//! exposure is Rust's `no_std` shape, not a continuum, and this resolver is
//! deliberately small to match.

pub mod beam;
pub mod morph;
pub mod quality;
pub use beam::{
    beam_variants, reachable_by_blue, reachable_by_hosted_language, Contradiction, Distribution,
    Failure, Heap, Interleaving, Latency, Model, Payload, Scheduling, Support,
};
pub use morph::{enforcement, shape_of, shapes, Layer, Shape};
pub use quality::{
    all_postures, exclusive_pairs, forfeits_at, qualities_at, witness, Axis, Quality,
};

use blue_lang_waku::{Waku, When};

/// A blue package.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Bidama {
    pub name: String,
    /// The least frame this package needs. **A floor, never a ceiling.**
    pub floor: Waku,
}

impl Bidama {
    pub fn new(name: impl Into<String>, floor: Waku) -> Self {
        Self {
            name: name.into(),
            floor,
        }
    }
}

/// Why a set of packages could not be resolved under a ceiling.
///
/// **Every conflict names both sides and the specific property**, because a
/// resolver that cannot answer *why* is not a resolver — that is the whole
/// standard PubGrub set, applied to postures.
///
/// **One variant per waku coordinate, and the caller can match on it.** This
/// was a struct carrying the reason as a prose `String`, which had two costs.
/// A consumer could not act on the cause without parsing English. And
/// `explain` ended in an unconditional branch that asserted "requires a heap
/// the root does not permit" — correct only because `Waku::leq` happens to
/// have exactly three coordinates, so the moment a fourth algebra joined the
/// resolution its conflicts would have been reported as heap conflicts, with
/// an empty culprit list and no way to notice.
///
/// The variants are the coordinates. Adding one is a compile error at every
/// match, which is the point.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Conflict {
    /// **WHEN** — the quantized coordinate, and the only one that can produce
    /// a structural mutual exclusion: an artifact either carries the evaluator
    /// or it does not, so there is no middle posture satisfying both.
    Schedule {
        culprits: Vec<String>,
        /// Whether what was demanded is specifically a resident evaluator,
        /// which is the case an author most needs to see.
        needs_resident_evaluator: bool,
    },
    /// **REACH** — a package wants names the root's capability policy does not
    /// grant.
    Capability { culprits: Vec<String> },
    /// **WHERE** — a package wants a heap the root does not permit.
    Heap { culprits: Vec<String> },
}

impl Conflict {
    /// The packages whose floors jointly exceeded the ceiling.
    #[must_use]
    pub fn culprits(&self) -> &[String] {
        match self {
            Self::Schedule { culprits, .. }
            | Self::Capability { culprits }
            | Self::Heap { culprits } => culprits,
        }
    }

    /// Which coordinate failed, as a stable label.
    #[must_use]
    pub const fn coordinate(&self) -> &'static str {
        match self {
            Self::Schedule { .. } => "when",
            Self::Capability { .. } => "reach",
            Self::Heap { .. } => "where",
        }
    }
}

impl std::fmt::Display for Conflict {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let because = match self {
            Self::Schedule {
                needs_resident_evaluator: true,
                ..
            } => {
                "a resident evaluator (runtime `eval`) is required, but the root seals \
                 the artifact. This is the one axis that quantizes — an artifact either \
                 carries the evaluator or it does not, so there is no middle posture \
                 that satisfies both."
            }
            Self::Schedule { .. } => {
                "a wider evaluation schedule is required, but the root seals the artifact."
            }
            Self::Capability { .. } => "requires names the root's capability policy does not grant",
            Self::Heap { .. } => "requires a heap the root does not permit",
        };
        write!(
            f,
            "cannot resolve: {} — {because}",
            self.culprits().join(" and ")
        )
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Resolution {
    /// The frame the program runs in: the join of every floor.
    pub posture: Waku,
    /// Does the resolved posture keep the evaluator in the artifact?
    ///
    /// This is the one bit that can partition the ecosystem, surfaced so a
    /// build can act on it (§V.10's `aberto`/`selado`).
    pub needs_resident_evaluator: bool,
}

/// Resolve a set of packages under a root ceiling.
///
/// `join the floors, check ⊑ ceiling`. The join is the smallest frame that
/// satisfies every package; if it does not fit under the ceiling, the
/// application asked for something its dependencies cannot provide.
pub fn resolve(bidama: &[Bidama], ceiling: &Waku) -> Result<Resolution, Conflict> {
    let mut posture = Waku::bottom();
    for b in bidama {
        posture = posture.join(&b.floor);
    }

    if !posture.leq(ceiling) {
        return Err(explain(bidama, ceiling, &posture));
    }

    Ok(Resolution {
        needs_resident_evaluator: posture.needs_resident_evaluator(),
        posture,
    })
}

/// Build the explanation: which packages drove the join past the ceiling,
/// and on which coordinate.
fn explain(bidama: &[Bidama], ceiling: &Waku, joined: &Waku) -> Conflict {
    // WHEN — the quantized coordinate, and the only one that can produce a
    // structural mutual exclusion. Reported first because it is the one an
    // author most needs to see.
    if joined.when > ceiling.when {
        let culprits: Vec<String> = bidama
            .iter()
            .filter(|b| b.floor.when > ceiling.when)
            .map(|b| b.name.clone())
            .collect();
        return Conflict::Schedule {
            culprits,
            needs_resident_evaluator: joined.when == When::Anytime,
        };
    }

    if !joined.reach.leq(&ceiling.reach) {
        let culprits: Vec<String> = bidama
            .iter()
            .filter(|b| !b.floor.reach.leq(&ceiling.reach))
            .map(|b| b.name.clone())
            .collect();
        return Conflict::Capability { culprits };
    }

    // WHERE — checked with an `if`, not as a fallthrough.
    //
    // This used to be the unconditional tail: whatever was left got reported
    // as a heap conflict. That was true only because `Waku::leq` compares
    // exactly three coordinates, so "not WHEN and not REACH" implied WHERE by
    // arithmetic rather than by test. `every_failing_pair_is_explained_by_a_
    // coordinate_that_actually_exceeds` is what now holds that, exhaustively
    // over every posture pair, so the implication is checked rather than
    // assumed — and a fourth coordinate lands here as an explicit gap instead
    // of silently wearing WHERE's label with an empty culprit list.
    if joined.place > ceiling.place {
        let culprits: Vec<String> = bidama
            .iter()
            .filter(|b| b.floor.place > ceiling.place)
            .map(|b| b.name.clone())
            .collect();
        return Conflict::Heap { culprits };
    }

    unreachable!(
        "resolve only calls explain when `joined ⊑ ceiling` is false, and \
         `Waku::leq` is componentwise over exactly WHEN, REACH and WHERE — so \
         at least one of the three above must have fired. Reaching here means \
         a coordinate was added to `Waku` without adding it to `Conflict`."
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use blue_lang_waku::{Reach, Where};

    fn pure(name: &str, names: &[&str]) -> Bidama {
        Bidama::new(
            name,
            Waku {
                reach: Reach::only(names.iter().copied()),
                when: When::Preceding,
                place: Where::Process,
            },
        )
    }

    fn needs_eval(name: &str) -> Bidama {
        Bidama::new(
            name,
            Waku {
                reach: Reach::Unrestricted,
                when: When::Anytime,
                place: Where::Process,
            },
        )
    }

    #[test]
    fn an_empty_set_resolves_to_the_bottom() {
        let r = resolve(&[], &Waku::top()).expect("resolves");
        assert_eq!(r.posture, Waku::bottom());
        assert!(!r.needs_resident_evaluator);
    }

    #[test]
    fn compatible_packages_resolve_to_the_join_of_their_floors() {
        let bs = [pure("a", &["+"]), pure("b", &["*"])];
        let r = resolve(&bs, &Waku::top()).expect("resolves");
        assert!(
            r.posture.reach.permits("+"),
            "the join must include a's names"
        );
        assert!(
            r.posture.reach.permits("*"),
            "the join must include b's names"
        );
    }

    /// The resolved posture is the SMALLEST frame satisfying everyone —
    /// above every floor, and below anything else that is.
    #[test]
    fn the_resolved_posture_is_the_least_frame_satisfying_every_floor() {
        let bs = [pure("a", &["+"]), pure("b", &["*"])];
        let r = resolve(&bs, &Waku::top()).expect("resolves");
        for b in &bs {
            assert!(b.floor.leq(&r.posture), "{} floor not satisfied", b.name);
        }
        // Anything strictly smaller fails somebody.
        let smaller = Waku {
            reach: Reach::only(["+"]),
            ..r.posture.clone()
        };
        assert!(!bs[1].floor.leq(&smaller));
    }

    /// **Every failing resolution is explained by a coordinate that actually
    /// exceeds the ceiling.** Exhaustive over every ordered posture pair.
    ///
    /// This is what holds the `unreachable!` at the end of `explain`. That
    /// branch used to be the *reporting* path: whatever was not WHEN and not
    /// REACH was labelled a heap conflict, which was true only because
    /// `Waku::leq` compares exactly three coordinates. So the implication was
    /// arithmetic, not a test, and a fourth coordinate would have inherited
    /// WHERE's label with an empty culprit list — a conflict that reads as
    /// explained and names nobody.
    ///
    /// Checking it over all pairs means the `unreachable!` is a fact about
    /// this lattice rather than a hope, and adding a coordinate to `Waku`
    /// fails here rather than lying at runtime.
    #[test]
    fn every_failing_pair_is_explained_by_a_coordinate_that_actually_exceeds() {
        let postures = all_postures();
        let mut failures = 0usize;

        for floor in &postures {
            for ceiling in &postures {
                if floor.leq(ceiling) {
                    continue;
                }
                failures += 1;
                let err = resolve(&[Bidama::new("p", floor.clone())], ceiling)
                    .expect_err("floor exceeds ceiling, so this must conflict");

                // The named coordinate must be one that genuinely exceeds.
                let honest = match &err {
                    Conflict::Schedule { .. } => floor.when > ceiling.when,
                    Conflict::Capability { .. } => !floor.reach.leq(&ceiling.reach),
                    Conflict::Heap { .. } => floor.place > ceiling.place,
                };
                assert!(
                    honest,
                    "reported {} for {floor:?} under {ceiling:?}, but that \
                     coordinate does not exceed",
                    err.coordinate()
                );

                // And it must name somebody. An empty culprit list is the
                // exact symptom the old fallthrough produced.
                assert!(
                    !err.culprits().is_empty(),
                    "{} conflict named nobody for {floor:?} under {ceiling:?}",
                    err.coordinate()
                );
            }
        }

        // Anti-vacuity: if no pair failed, the loop above asserted nothing.
        assert!(
            failures > 0,
            "no posture pair failed to resolve — this gate measured nothing"
        );
    }

    // ---- the one axis that can partition an ecosystem -----------------

    /// A package needing runtime `eval` cannot go in a sealed artifact,
    /// and the failure names both the package and the reason.
    #[test]
    fn a_sealed_root_rejects_a_package_that_needs_the_evaluator() {
        let ceiling = Waku {
            reach: Reach::Unrestricted,
            when: When::Preceding, // sealed: no resident evaluator
            place: Where::Shared,
        };
        let err = resolve(&[needs_eval("scripting")], &ceiling).expect_err("must conflict");
        assert_eq!(err.culprits(), ["scripting"]);
        assert_eq!(err.coordinate(), "when");
        assert!(
            matches!(
                err,
                Conflict::Schedule {
                    needs_resident_evaluator: true,
                    ..
                }
            ),
            "the CAUSE must be matchable, not only readable: {err:?}"
        );
        assert!(err.to_string().contains("resident evaluator"), "{err}");
        assert!(
            err.to_string().contains("quantizes"),
            "the message should say WHY there is no middle posture: {err}"
        );
    }

    /// And it names EVERY culprit, not just the first.
    #[test]
    fn every_offending_package_is_named() {
        let ceiling = Waku {
            when: When::Preceding,
            ..Waku::top()
        };
        let err = resolve(
            &[needs_eval("a"), pure("ok", &["+"]), needs_eval("b")],
            &ceiling,
        )
        .expect_err("must conflict");
        assert_eq!(err.culprits(), ["a", "b"]);
        assert!(!err.culprits().contains(&"ok".to_string()));
    }

    /// The bit is surfaced on SUCCESS too, so a build knows which artifact
    /// kind it is producing.
    #[test]
    fn a_successful_resolution_reports_the_evaluator_bit() {
        let open = resolve(&[needs_eval("s")], &Waku::top()).expect("resolves");
        assert!(open.needs_resident_evaluator);

        let sealed = resolve(&[pure("p", &["+"])], &Waku::top()).expect("resolves");
        assert!(!sealed.needs_resident_evaluator);
    }

    #[test]
    fn a_capability_ceiling_is_enforced_and_explained() {
        let ceiling = Waku {
            reach: Reach::only(["+", "*"]),
            when: When::Preceding,
            place: Where::Shared,
        };
        let err = resolve(&[pure("net", &["http_get"])], &ceiling).expect_err("must conflict");
        assert_eq!(err.culprits(), ["net"]);
        assert_eq!(err.coordinate(), "reach");
        assert!(err.to_string().contains("capability policy"), "{err}");
    }

    #[test]
    fn a_heap_ceiling_is_enforced() {
        let ceiling = Waku {
            place: Where::Arena,
            ..Waku::top()
        };
        let shared = Bidama::new(
            "cache",
            Waku {
                place: Where::Shared,
                ..Waku::bottom()
            },
        );
        let err = resolve(&[shared], &ceiling).expect_err("must conflict");
        assert_eq!(err.coordinate(), "where");
        assert!(err.to_string().contains("heap"), "{err}");
    }

    // ---- order independence -------------------------------------------

    /// Resolution must not depend on declaration order. Join is
    /// commutative and associative, so this follows — but a resolver that
    /// short-circuited or mutated state could break it, so it is pinned.
    #[test]
    fn resolution_is_order_independent() {
        let a = pure("a", &["+"]);
        let b = pure("b", &["*"]);
        let c = needs_eval("c");
        let fwd = resolve(&[a.clone(), b.clone(), c.clone()], &Waku::top()).expect("ok");
        let rev = resolve(&[c, b, a], &Waku::top()).expect("ok");
        assert_eq!(fwd, rev);
    }

    // ---- anti-vacuity ---------------------------------------------------

    /// The resolver must be able to FAIL. If everything resolved, every
    /// success assertion above would be worthless.
    #[test]
    fn the_resolver_actually_rejects_something() {
        let ceiling = Waku::bottom();
        assert!(resolve(&[pure("anything", &["+"])], &ceiling).is_err());
    }

    /// And it must be able to SUCCEED under a non-trivial ceiling — a
    /// resolver that rejected everything would pass every failure test.
    #[test]
    fn the_resolver_actually_accepts_something_nontrivial() {
        let ceiling = Waku {
            reach: Reach::only(["+", "*", "list"]),
            when: When::Preceding,
            place: Where::Process,
        };
        assert!(resolve(&[pure("a", &["+"]), pure("b", &["*"])], &ceiling).is_ok());
    }

    /// A conflict message must be human-readable end to end.
    #[test]
    fn a_conflict_renders_as_a_sentence() {
        let ceiling = Waku {
            when: When::Preceding,
            ..Waku::top()
        };
        let err = resolve(&[needs_eval("scripting")], &ceiling).expect_err("conflict");
        let s = err.to_string();
        assert!(s.starts_with("cannot resolve: scripting"), "{s}");
    }
}
