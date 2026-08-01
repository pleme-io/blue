//! **A language is a point in the posture space. Blue is the space.**
//!
//! Every language ships one posture, chosen once, for everything written in it.
//! Ruby picked a resident evaluator, shared mutable state and ambient load-time
//! authority; Rust picked scoped reclamation, a minimal artifact and a closed
//! world; Elixir picked process isolation and preemption. Each of those is a
//! *point*, and the qualities each forfeits are forfeited by every program in
//! the language — including the ones that never needed the quality that cost
//! them.
//!
//! **That is why languages keep getting created.** A new language is usually not
//! a new idea; it is the same ideas at a different point, because the point is
//! not something an author was allowed to choose. bīdama makes it a
//! declaration, so blue reaches the points rather than occupying one.
//!
//! # Two layers, and only one of them is a proof
//!
//! The morphology is enforced at two substrate layers, and the distinction is
//! load-bearing rather than decorative:
//!
//! - [`Layer::Rust`] — a type, a signature, or an **absent method**. The
//!   compiler refuses the illegal program. This is a proof.
//! - [`Layer::TataraLisp`] — an **absent binding**. The name does not resolve,
//!   so the capability cannot be reached. A proof at the language boundary, and
//!   a strictly weaker one: it is enforced at expansion or run time rather than
//!   at compile time, and it holds only while nothing rebinds the name.
//! - [`Layer::Unenforced`] — the posture *describes* the quality and nothing
//!   yet delivers it. Recorded so a reader can tell a shipped guarantee from a
//!   design one; [`enforcement`] returns this for four of the nine, and saying
//!   so is the difference between a model and a claim.
//!
//! # Locking
//!
//! `waku`'s narrowing is one-way — a frame can be narrowed and never widened —
//! so a package that declares a floor cannot have it relaxed by something it
//! depends on. That is what makes a declared posture a *lock* rather than a
//! preference, and it is why [`crate::resolve`] joins floors under a ceiling
//! instead of averaging them.

use blue_lang_waku::{Reach, Waku, When, Where};

use crate::quality::{qualities_at, Quality};

/// Where a quality's guarantee actually lives.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Layer {
    /// A Rust type or an absent method — the compiler refuses it. A proof.
    Rust,
    /// An absent tatara-lisp binding — the name does not resolve. Weaker than
    /// `Rust`: enforced at expansion or run time, not compile time.
    TataraLisp,
    /// Described by the posture, delivered by nothing yet.
    Unenforced,
}

impl Layer {
    /// Is this a guarantee the machine checks, or a description?
    #[must_use]
    pub fn is_enforced(self) -> bool {
        !matches!(self, Layer::Unenforced)
    }

    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            Layer::Rust => "Rust type",
            Layer::TataraLisp => "absent tatara-lisp binding",
            Layer::Unenforced => "unenforced (design)",
        }
    }
}

/// Where a quality is enforced, and by what.
///
/// **Tier-honest: four of the nine are `Unenforced`.** The posture describes
/// them and nothing delivers them yet. Rounding those up to "blue has this"
/// would make the whole morphology a claim rather than a model.
#[must_use]
pub fn enforcement(q: Quality) -> (Layer, &'static str) {
    match q {
        Quality::PreemptiveScheduling => (
            Layer::Rust,
            "`Vm::step` parks at a quantum with the frame stack intact; the frame \
             stack is a heap Vec, which is what makes a continuation savable at all",
        ),
        Quality::ProcessIsolation => (
            Layer::Rust,
            "each process owns its `Interpreter`, and `deep_copy` rebuilds a message \
             so no allocation is shared; a closure is refused rather than sent",
        ),
        Quality::SharedMutableState => (
            Layer::Rust,
            "`Value` is `Arc`-based, so structure is shared unless something copies it",
        ),
        Quality::ReproducibleMacroPhase => (
            Layer::TataraLisp,
            "there is no path-taking primitive to call — `read_file` and `slurp` are \
             UNBOUND, and a build input is reachable only by its declared content hash",
        ),
        Quality::AmbientBuildCapability => (
            Layer::TataraLisp,
            "granted by BINDING a capability the sealed posture leaves absent",
        ),
        Quality::ResidentEvaluator => (
            Layer::TataraLisp,
            "`eval` is a tatara-lisp special form; a sealed posture is the one that \
             does not bind it",
        ),
        // ── the honest four ───────────────────────────────────────────
        Quality::MinimalArtifact => (
            Layer::Unenforced,
            "no artifact writer exists — §V.10's aberto/selado split is DESIGN, so \
             nothing yet drops the evaluator from a sealed build",
        ),
        Quality::AheadOfTimeSpecialization => (
            Layer::Unenforced,
            "the macro phase can compute, but nothing specializes on a closed world — \
             §V.21's partial evaluator is DESIGN",
        ),
        Quality::ScopedReclamation => (
            Layer::Unenforced,
            "there is no arena allocator; reclamation is `Arc` refcounting everywhere, \
             so `Where::Arena` currently describes an intent, not a mechanism",
        ),
    }
}

/// A language, as the posture it ships.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Shape {
    pub name: &'static str,
    pub posture: Waku,
    /// Why this posture, in one line — so a reader can check the mapping rather
    /// than take it.
    pub because: &'static str,
}

/// Known languages as points.
///
/// Approximations, and deliberately coarse: the claim is not "blue is Ruby" but
/// "the coordinate Ruby occupies is one blue can be told to occupy". Each entry
/// names its reasoning so the mapping is arguable rather than asserted.
#[must_use]
pub fn shapes() -> Vec<Shape> {
    vec![
        Shape {
            name: "Ruby",
            posture: Waku {
                reach: Reach::Unrestricted,
                when: When::Anytime,
                place: Where::Shared,
            },
            because: "eval at run time, one shared mutable heap, and load-time code with \
                      the whole filesystem open",
        },
        Shape {
            name: "Elixir",
            posture: Waku {
                reach: Reach::Unrestricted,
                when: When::Anytime,
                place: Where::Process,
            },
            because: "per-process heaps with copy-on-send, but Code.eval_string exists \
                      and a macro may File.read! anything",
        },
        Shape {
            name: "Rust",
            posture: Waku {
                reach: Reach::Unrestricted,
                when: When::Preceding,
                place: Where::Arena,
            },
            because: "a closed world at compile time and scope-bound reclamation, with \
                      build scripts holding full authority",
        },
        Shape {
            name: "sealed-embedded",
            posture: Waku {
                reach: Reach::nothing(),
                when: When::Sealed,
                place: Where::Arena,
            },
            because: "the shape a plugin host wants — no evaluator, no ambient reach, \
                      nothing escaping a scope",
        },
        Shape {
            name: "reproducible-dynamic",
            posture: Waku {
                reach: Reach::nothing(),
                when: When::Anytime,
                place: Where::Process,
            },
            because: "THE COMBINATION NO MAINSTREAM LANGUAGE OFFERS — a resident \
                      evaluator and process isolation and a build nobody can perturb",
        },
    ]
}

/// The shape whose granted qualities match this posture's exactly, if any.
#[must_use]
pub fn shape_of(w: &Waku) -> Option<&'static str> {
    let have = qualities_at(w);
    shapes()
        .into_iter()
        .find(|s| qualities_at(&s.posture) == have)
        .map(|s| s.name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::quality::{all_postures, Axis};
    use std::collections::BTreeSet;

    /// **Blue contains every shape.** Each named language's coordinate is a
    /// posture blue can be told to occupy — that is the whole claim, and it is
    /// checkable because the lattice is enumerable.
    #[test]
    fn blue_contains_every_language_shape() {
        let lattice = all_postures();
        for s in shapes() {
            assert!(
                lattice.iter().any(|w| qualities_at(w) == qualities_at(&s.posture)),
                "{} sits at a coordinate blue cannot express",
                s.name
            );
        }
    }

    /// **The shapes are genuinely DISTINCT** — no two grant the same qualities.
    /// If they collapsed, "blue contains them all" would be trivially true and
    /// mean nothing.
    #[test]
    fn the_shapes_are_distinct_points() {
        let mut seen: Vec<(&str, BTreeSet<Quality>)> = Vec::new();
        for s in shapes() {
            let q = qualities_at(&s.posture);
            if let Some((other, _)) = seen.iter().find(|(_, prev)| *prev == q) {
                panic!("{} and {other} are the same point — the catalog is not distinct", s.name);
            }
            seen.push((s.name, q));
        }
        assert_eq!(seen.len(), 5);
    }

    /// **Blue's default IS Ruby's shape.** Not a coincidence — blue's surface is
    /// Ruby's, and an author who declares nothing should get Ruby's semantics.
    #[test]
    fn the_default_posture_is_rubys_shape() {
        assert_eq!(shape_of(&Waku::top()), Some("Ruby"));
    }

    /// **The combination no mainstream language offers exists here**: a resident
    /// evaluator, process isolation, and a reproducible build at once. Ruby has
    /// the first and neither other; Rust has the last two and not the first.
    #[test]
    fn the_combination_no_mainstream_language_offers_is_reachable() {
        let s = shapes()
            .into_iter()
            .find(|s| s.name == "reproducible-dynamic")
            .expect("declared");
        let q = qualities_at(&s.posture);
        assert!(q.contains(&Quality::ResidentEvaluator));
        assert!(q.contains(&Quality::ProcessIsolation));
        assert!(q.contains(&Quality::ReproducibleMacroPhase));

        // And no OTHER shape in the catalog has all three — which is what makes
        // it the interesting point rather than a restatement.
        let others = shapes()
            .into_iter()
            .filter(|o| o.name != "reproducible-dynamic")
            .filter(|o| {
                let oq = qualities_at(&o.posture);
                oq.contains(&Quality::ResidentEvaluator)
                    && oq.contains(&Quality::ProcessIsolation)
                    && oq.contains(&Quality::ReproducibleMacroPhase)
            })
            .count();
        assert_eq!(others, 0, "then it would not be the novel point");
    }

    /// Ruby forfeits exactly what its single global choice costs it — the
    /// mapping is checkable, not asserted.
    #[test]
    fn rubys_shape_forfeits_what_ruby_actually_forfeits() {
        let ruby = shapes().into_iter().find(|s| s.name == "Ruby").expect("declared");
        let lost = crate::quality::forfeits_at(&ruby.posture);
        assert!(lost.contains(&Quality::MinimalArtifact), "Ruby cannot tree-shake");
        assert!(lost.contains(&Quality::PreemptiveScheduling));
        assert!(lost.contains(&Quality::ProcessIsolation));
        assert!(lost.contains(&Quality::ReproducibleMacroPhase));
    }

    // ---- enforcement, tier-honest --------------------------------------

    /// **Four of the nine are UNENFORCED, and the catalog says so.** Rounding
    /// them up would make the morphology a claim rather than a model.
    #[test]
    fn the_unenforced_qualities_are_named_as_such() {
        let unenforced: Vec<Quality> = Quality::ALL
            .iter()
            .copied()
            .filter(|q| !enforcement(*q).0.is_enforced())
            .collect();
        assert_eq!(
            unenforced,
            vec![
                Quality::MinimalArtifact,
                Quality::AheadOfTimeSpecialization,
                Quality::ScopedReclamation,
            ],
            "the honest set changed — update the ledger deliberately, not by accident"
        );
    }

    /// Every quality has a stated enforcement site with a reason. A quality
    /// whose enforcement nobody wrote down is one nobody can check.
    #[test]
    fn every_quality_states_where_it_is_enforced_and_why() {
        for q in Quality::ALL {
            let (layer, why) = enforcement(q);
            assert!(!why.is_empty(), "{} has no reason", q.label());
            assert!(
                why.len() > 30,
                "{} has a reason too short to be one: {why}",
                q.label()
            );
            let _ = layer;
        }
    }

    /// **The Rust layer is strictly stronger, and the split follows the axis.**
    /// The `When`/`Reach` qualities are language-surface facts — a form or a
    /// binding — so they land at the tatara-lisp boundary; the `Where` ones are
    /// about how values are represented, which is a Rust type question.
    #[test]
    fn the_enforcement_layer_follows_the_axis() {
        for q in Quality::ALL {
            let (layer, _) = enforcement(q);
            if !layer.is_enforced() {
                continue;
            }
            let expected = match q.axis() {
                Axis::Where => Layer::Rust,
                Axis::When | Axis::Reach => Layer::TataraLisp,
            };
            // PreemptiveScheduling is the deliberate exception: it is a `When`
            // quality enforced in Rust, because parking a continuation is a
            // property of the VM's frame stack rather than of any form.
            if q == Quality::PreemptiveScheduling {
                assert_eq!(layer, Layer::Rust);
                continue;
            }
            assert_eq!(layer, expected, "{} is enforced at the wrong layer", q.label());
        }
    }

    /// Anti-vacuity: some qualities really are enforced. A catalog that was all
    /// `Unenforced` would pass the honesty test above and mean nothing.
    #[test]
    fn the_enforced_set_is_not_empty() {
        let enforced = Quality::ALL
            .iter()
            .filter(|q| enforcement(**q).0.is_enforced())
            .count();
        assert_eq!(enforced, 6, "six of nine are real guarantees today");
    }
}
