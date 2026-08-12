//! **What a posture buys, what it forfeits, and which combinations are
//! genuinely exclusive — derived, not asserted.**
//!
//! A language quality is "mutually exclusive" with another only when the
//! language must choose **globally**. Ruby cannot tree-shake because `eval` may
//! name anything at run time — so *every* Ruby program forfeits a minimal
//! artifact, including the ones that never call `eval`. The exclusivity is not
//! a law of computing; it is a consequence of there being one posture for the
//! whole language.
//!
//! bīdama makes the posture a **declaration**, so the question becomes
//! per-package. This module answers four things about that:
//!
//! 1. [`qualities_at`] — what a given `waku` grants.
//! 2. [`exclusive_pairs`] — which pairs no posture grants together.
//! 3. [`minimal_exclusive_groups`] — the same question past two: which
//!    **sets** no posture grants together, minimally. A trilemma is a
//!    three-element group and a pair scan cannot see one.
//! 4. [`witness`] / [`witness_all`] — for a combination that *is* compatible,
//!    the posture proving it.
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
//! > **Every minimal exclusive group lies on one axis.** Qualities on
//! > *different* coordinates of `waku` always have a witness posture granting
//! > all of them.
//!
//! The pair form is the special case, and it is the one a reader meets first.
//! The general form is what makes it a theorem rather than a coincidence:
//! `qualities_at` reads each coordinate independently and [`all_postures`] is
//! the full product, so a set that spans two axes is satisfiable coordinate by
//! coordinate — and a group that spans two axes therefore always has a proper
//! subset that is already exclusive, which is exactly what minimality forbids.
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
    /// A macro body may call a function an earlier top-level form defined —
    /// "resident evaluator", but at expansion rather than at run time.
    ///
    /// Measured, not inferred: `expand_macro_call` runs the body through the
    /// **live** interpreter's globals, so `def n() 3 end` followed by a macro
    /// whose body calls `n()` prints a number today and would fail with
    /// `unbound symbol: n` under any schedule that expands before evaluating
    /// (`theory/SAKIDORI.md` §IX #1, and the probe there is the argument).
    ExpansionTimeEvaluation,
    /// Everything a macro emits passes the type checker — and a macro may emit
    /// an annotated declaration at all.
    ///
    /// Costs a schedule in which nothing is evaluated when a macro body runs:
    /// expansion has to *finish* before the checker starts, and it can only
    /// finish before anything is evaluated if it needs nothing evaluated.
    CheckedMacroOutput,
    /// A typed body may call a function declared later and still be checked
    /// against its real signature rather than falling to `Dyn`.
    ///
    /// What `check_program`'s deliberately whole-program pass 1 buys, and what
    /// driving that pass form-by-form silently loses.
    ForwardDeclarationChecking,
    /// A type error is reported with nothing having happened yet.
    ///
    /// `pipeline`'s own opening law — *run before check reports a type error
    /// after the side effects* — as a quality a posture can forfeit.
    CheckBeforeEffect,
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
    /// How many qualities there are — **checked during const evaluation, not
    /// remembered.**
    ///
    /// This number used to be an array arity carrying the comment "forced-arity
    /// so adding a variant without adding it here is a compile error". **That
    /// claim was false**, and measurably so: `[Quality; 9]` constrains the
    /// literal, not the enum, so a tenth variant that nobody listed compiled
    /// green and then silently sat outside every enumeration in this module —
    /// including [`exclusive_pairs`], which would have reported the lattice as
    /// having no exclusion involving it. ★★ CATALOG REFLECTION asks for the
    /// opposite, and [`Quality::chain`] delivers it: `ALL` is *built* by
    /// walking [`Quality::next`], so
    ///
    /// - a variant with no `next` arm is `E0004` in `next` itself, and
    /// - a variant spliced into the chain without growing `COUNT` trips
    ///   `chain`'s own `assert!` **at compile time**, because `ALL` is a
    ///   `const` and the walk therefore runs during const evaluation.
    ///
    /// Red run, 2026-08-12: a 14th variant added with a `next` arm and `COUNT`
    /// left at 13 → `error[E0080]: evaluation of constant value failed …
    /// the `next` chain is longer than `Quality::COUNT``. Removing the variant
    /// restored the build. The vacuity trap this repo names was live here: the
    /// old comment described a gate that did not exist.
    pub const COUNT: usize = 13;

    /// Where the chain starts. The one hand-held link, and a wrong one is a
    /// compile error rather than a silent omission: the walk would run off the
    /// end of the chain or off the end of `COUNT`.
    const FIRST: Quality = Quality::ResidentEvaluator;

    /// Every quality, in chain order.
    pub const ALL: [Quality; Self::COUNT] = Self::chain();

    /// The successor of this quality in the catalog, or `None` at the end.
    ///
    /// An exhaustive match with no wildcard arm — which is the whole point.
    /// A new variant lands here or it does not compile.
    const fn next(self) -> Option<Quality> {
        Some(match self {
            Quality::ResidentEvaluator => Quality::PreemptiveScheduling,
            Quality::PreemptiveScheduling => Quality::MinimalArtifact,
            Quality::MinimalArtifact => Quality::AheadOfTimeSpecialization,
            Quality::AheadOfTimeSpecialization => Quality::ExpansionTimeEvaluation,
            Quality::ExpansionTimeEvaluation => Quality::CheckedMacroOutput,
            Quality::CheckedMacroOutput => Quality::ForwardDeclarationChecking,
            Quality::ForwardDeclarationChecking => Quality::CheckBeforeEffect,
            Quality::CheckBeforeEffect => Quality::ReproducibleMacroPhase,
            Quality::ReproducibleMacroPhase => Quality::AmbientBuildCapability,
            Quality::AmbientBuildCapability => Quality::ProcessIsolation,
            Quality::ProcessIsolation => Quality::SharedMutableState,
            Quality::SharedMutableState => Quality::ScopedReclamation,
            Quality::ScopedReclamation => return None,
        })
    }

    const fn chain() -> [Quality; Self::COUNT] {
        let mut out = [Self::FIRST; Self::COUNT];
        let mut i = 1;
        while i < Self::COUNT {
            out[i] = match out[i - 1].next() {
                Some(q) => q,
                None => panic!("the `next` chain is shorter than `Quality::COUNT`"),
            };
            i += 1;
        }
        assert!(
            matches!(out[Self::COUNT - 1].next(), None),
            "the `next` chain is longer than `Quality::COUNT` — a quality has no slot in `ALL`"
        );
        out
    }

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
            | Quality::AheadOfTimeSpecialization
            | Quality::ExpansionTimeEvaluation
            | Quality::CheckedMacroOutput
            | Quality::ForwardDeclarationChecking
            | Quality::CheckBeforeEffect => Axis::When,
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
            Quality::ExpansionTimeEvaluation => "expansion-time evaluation",
            Quality::CheckedMacroOutput => "checked macro output",
            Quality::ForwardDeclarationChecking => "forward-declaration checking",
            Quality::CheckBeforeEffect => "check before effect",
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

impl Axis {
    /// Every axis. Hand-listed, and the arity does not hold it — what holds it
    /// is [`Axis::isolates`], an exhaustive match that a fourth coordinate
    /// cannot be added to without `E0004`, plus
    /// `each_coordinate_decides_exactly_its_own_axis`, which fails if an axis
    /// in this list decides nothing.
    pub const ALL: [Axis; 3] = [Axis::Reach, Axis::When, Axis::Where];

    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            Axis::Reach => "Reach",
            Axis::When => "When",
            Axis::Where => "Where",
        }
    }

    /// Do these two postures differ on **this** coordinate and no other?
    ///
    /// The primitive the completeness gate is built from: it lets a test move
    /// one coordinate at a time and ask what changed, which is the only way to
    /// check that a quality is attributed to the coordinate that actually
    /// decides it rather than the one someone wrote down.
    ///
    /// The match is exhaustive and each arm names all three coordinates, so a
    /// fourth `Waku` coordinate is a compile error here rather than a
    /// silently-ignored dimension.
    #[must_use]
    pub fn isolates(self, a: &Waku, b: &Waku) -> bool {
        let reach = a.reach != b.reach;
        let when = a.when != b.when;
        let place = a.place != b.place;
        match self {
            Axis::Reach => reach && !when && !place,
            Axis::When => when && !reach && !place,
            Axis::Where => place && !reach && !when,
        }
    }
}

/// The capability name whose presence decides the `Reach` qualities.
///
/// One name rather than a set: the question "may the macro phase touch the
/// outside world" is binary at this granularity, and inventing a taxonomy
/// before there are consumers for it would be a guess.
///
/// **This is the model's one measured incompleteness, named so it is not read
/// as a closed enumeration.** `Reach` is a *powerset* coordinate — `Reach::Only`
/// takes arbitrary strings — and the quality model collapses it to a single
/// bit, so [`all_postures`] samples two points of an unbounded coordinate while
/// `When` and `Where` are exhausted. A capability that is neither "io" nor
/// nothing is invisible here: the lattice cannot derive an exclusion between
/// two capabilities, because it cannot see two.
///
/// It is not fixable in this module. One quality per capability needs a
/// **closed capability universe** to enumerate over, and blue has none —
/// `blue_lang_pkg::bluefile` records the same gap from the other side, which is
/// why its `posture` primitive accepts only the `when` coordinate. Inventing
/// the universe here to make the enumeration look complete would be the tier
/// round-up this crate exists to prevent.
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

    // ── When, read as the MACRO PHASE's schedule ──────────────────────
    //
    // The same coordinate answers a second family of questions, and it is the
    // coordinate's own documented meaning that makes it the right home:
    // `When::Preceding` is described on the enum as "the macro phase's
    // schedule", and §V.14's probe P1 measured that blue's two entry points
    // differ in *nothing but* when a macro body runs and are two languages
    // because of it.
    //
    // Each value is one whole pipeline, and `theory/SAKIDORI.md` §IX #1
    // measured all three:
    //
    // | `when`      | the schedule it names                          | today |
    // |-------------|------------------------------------------------|-------|
    // | `Sealed`    | expand the whole program, then check, then run  |       |
    // | `Preceding` | per form: expand N, check N, run N              |       |
    // | `Anytime`   | check, erase, run — expansion *inside* `run`    | ✓     |
    //
    // The bottom row is what blue ships, which is why nothing a macro emits is
    // ever checked.
    if w.when >= When::Preceding {
        // The body runs against live globals, so an earlier top-level `define`
        // is a name it resolves. `Sealed` is the one schedule that has nothing
        // to resolve against.
        out.insert(Quality::ExpansionTimeEvaluation);
    }
    if w.when <= When::Preceding {
        // Expansion finishes before the checker runs — at `Sealed` for the
        // whole program at once, at `Preceding` one form at a time — so the
        // checker sees what a macro emitted.
        //
        // **These two overlap at `Preceding`, and writing them as an if/else
        // would be the whole modelling error.** The first draft did exactly
        // that, and the derivation caught it immediately: it reported
        // `expansion-time evaluation ⊥ checked macro output` as an exclusive
        // PAIR, which is strictly stronger than anything SAKIDORI §IX #1
        // measured and would have erased the trilemma — the per-form schedule
        // has both, and pays for them on the two below.
        out.insert(Quality::CheckedMacroOutput);
    }
    if w.when != When::Preceding {
        // **The one non-monotone condition in this function, and it is the
        // measurement talking rather than a convenience.**
        //
        // `Preceding` is the only schedule that forces the checker to be driven
        // form by form: expanding form N needs form N−1 *evaluated*, so form
        // N+1 is still unexpanded when form N is checked — pass 1 cannot see a
        // signature it has not expanded yet, and form N−1's effects have
        // already happened. `Sealed` and `Anytime` each leave the checker one
        // whole-program pass — one *before* expansion has any effect, one
        // *instead of* it — so both keep pass 1's forward declarations and both
        // report a type error before an interpreter is built.
        //
        // Reading the chain as a gradient here would be wrong: the middle point
        // is a local minimum for these two, not a half-way house. A reviewer
        // who "tidies" this to `w.when <= When::Preceding` has claimed the
        // per-form schedule keeps forward declarations, which §IX #1 measured
        // it does not.
        out.insert(Quality::ForwardDeclarationChecking);
        out.insert(Quality::CheckBeforeEffect);
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
///
/// **Exhaustive on two coordinates, a sample on the third** — see
/// [`IO_CAPABILITY`] for why, and for why that is a stated limit rather than a
/// fixable oversight. The consequence to hold onto: a derived exclusion is
/// sound (a pair reported exclusive really has no witness *in blue's model*),
/// and completeness holds for `When` and `Where` only. A `Reach` exclusion
/// between two named capabilities would not be found here because no posture in
/// this list distinguishes them.
///
/// All eighteen grant distinct quality sets, which
/// `every_posture_is_distinguishable_from_every_other` holds — a coordinate
/// value no quality can tell apart from its neighbour is a missing quality, and
/// that test found one.
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
    witness_all(&[a, b])
}

/// A posture granting **every** quality in `group`, if one exists.
///
/// [`witness`] past two. The empty group is granted by any posture, which is
/// the right answer and matters: [`minimal_exclusive_groups`] asks it about
/// subsets on the way down.
#[must_use]
pub fn witness_all(group: &[Quality]) -> Option<Waku> {
    all_postures().into_iter().find(|w| {
        let q = qualities_at(w);
        group.iter().all(|g| q.contains(g))
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

/// The bit position of each quality, so a set of them is one integer.
///
/// `1 << COUNT` has to fit, and the catalog is nowhere near the edge — but a
/// silent wrap would turn the whole enumeration below into nonsense, so it is
/// a compile error rather than a comment.
const _: () = assert!(
    Quality::COUNT < 32,
    "`minimal_exclusive_groups` packs the catalog into a u32"
);

fn mask_of(w: &Waku) -> u32 {
    let have = qualities_at(w);
    let mut m = 0;
    for (i, q) in Quality::ALL.iter().enumerate() {
        if have.contains(q) {
            m |= 1 << i;
        }
    }
    m
}

/// Every **minimal** set of qualities no posture grants together.
///
/// # Why this exists and a pair scan does not suffice
///
/// A *trilemma* — pick any two of three — contains no exclusive pair at all.
/// Each pair has a witness; only the triple has none. So a derivation that
/// enumerates pairs reports a trilemma as *nothing*, which is the worst
/// possible answer: it looks like a checked absence.
///
/// `theory/SAKIDORI.md` §IX #1 measured exactly such a shape in blue's macro
/// phase, and the point of deriving it here rather than writing it down is that
/// the lattice then also finds the ones nobody measured.
///
/// # Minimal, not merely exclusive
///
/// Every superset of an exclusive set is exclusive, so the unfiltered answer is
/// mostly noise — `{sharing, isolation, anything}` restates one pair a thousand
/// times. A group is kept only when **dropping any one member makes it
/// satisfiable again**, which is the same standard as a minimal unsatisfiable
/// core.
///
/// Groups come out in ascending size and each group in catalog order, so
/// the size-2 prefix is [`exclusive_pairs`] — asserted, not assumed, by
/// `the_two_derivations_agree_on_pairs`.
#[must_use]
pub fn minimal_exclusive_groups() -> Vec<Vec<Quality>> {
    // One bit per quality and one mask per posture, computed once. The direct
    // form calls `qualities_at` inside a 2^13 loop and allocates a `BTreeSet`
    // a couple of million times; this is the same enumeration, not a heuristic
    // over it, and `the_two_derivations_agree_on_pairs` holds the two together.
    let postures: Vec<u32> = all_postures().iter().map(mask_of).collect();
    let satisfiable = |g: u32| postures.iter().any(|p| p & g == g);

    let mut out: Vec<Vec<Quality>> = Vec::new();
    for g in 0u32..(1 << Quality::COUNT) {
        if g.count_ones() < 2 || satisfiable(g) {
            continue;
        }
        let minimal = (0..Quality::COUNT)
            .filter(|i| g & (1 << i) != 0)
            .all(|i| satisfiable(g & !(1 << i)));
        if minimal {
            out.push(
                (0..Quality::COUNT)
                    .filter(|i| g & (1 << i) != 0)
                    .map(|i| Quality::ALL[i])
                    .collect(),
            );
        }
    }
    out.sort_by(|a, b| a.len().cmp(&b.len()).then_with(|| a.cmp(b)));
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

    /// **The theorem past two: every MINIMAL exclusive group lies on one
    /// axis.** The pair form above is its special case, and this is the form
    /// that is actually load-bearing — a trilemma spanning two axes would be
    /// invisible to the pair scan and would break independence just as badly.
    #[test]
    fn every_minimal_exclusive_group_lies_on_one_axis() {
        for g in minimal_exclusive_groups() {
            let axes: BTreeSet<Axis> = g.iter().map(|q| q.axis()).collect();
            assert_eq!(
                axes.len(),
                1,
                "this group is exclusive ACROSS axes, which would break the \
                 independence the whole model rests on: {:?}",
                g.iter().map(|q| q.label()).collect::<Vec<_>>()
            );
        }
    }

    /// **THE MACRO-PHASE TRILEMMA, DERIVED.**
    ///
    /// `theory/SAKIDORI.md` §IX #1 measured it — *pick two of (A) macro bodies
    /// see earlier top-level definitions, (B) whole-program signature
    /// collection, (C) no side effects before any check* — and left it as
    /// prose. Nothing here lists it. It falls out because
    /// [`qualities_at`] puts all four on the `When` coordinate with supports
    /// that pairwise overlap and jointly do not:
    ///
    /// | quality | granted at |
    /// |---|---|
    /// | (A) expansion-time evaluation | `Preceding`, `Anytime` |
    /// | (B) forward-declaration checking | `Sealed`, `Anytime` |
    /// | (C) check before effect | `Sealed`, `Anytime` |
    /// | the goal: checked macro output | `Sealed`, `Preceding` |
    ///
    /// A ∩ B = `{Anytime}`, A ∩ goal = `{Preceding}`, B ∩ goal = `{Sealed}` —
    /// so **no pair is exclusive**, and a pair scan reports nothing at all.
    /// The triple is empty, which is the trilemma.
    ///
    /// **Red run, 2026-08-12.** `qualities_at`'s `w.when <= When::Preceding`
    /// guard on `checked macro output` replaced by `true`, so the quality is
    /// granted everywhere and the lattice can no longer exclude it. Both
    /// corners disappear from `minimal_exclusive_groups` and this test fails;
    /// `a_resident_evaluator_excludes_checked_macro_output` and the
    /// completeness gate fail with it (the latter on *"granted by EVERY
    /// posture, so the lattice decides nothing about it"*). Restoring the
    /// guard returned all three to green. **This is the proof that the group
    /// is derived rather than listed** — nothing anywhere names these two
    /// triples, and changing one grant condition is enough to erase them.
    #[test]
    fn the_macro_phase_trilemma_falls_out_of_the_enumeration() {
        let groups = minimal_exclusive_groups();
        let derived = |xs: &[Quality]| {
            let mut want = xs.to_vec();
            want.sort_unstable();
            groups.iter().any(|g| *g == want)
        };

        // (A) + (B) + the goal.
        assert!(
            derived(&[
                Quality::ExpansionTimeEvaluation,
                Quality::ForwardDeclarationChecking,
                Quality::CheckedMacroOutput,
            ]),
            "the A+B corner is not derived: {:?}",
            groups
        );
        // (A) + (C) + the goal.
        assert!(
            derived(&[
                Quality::ExpansionTimeEvaluation,
                Quality::CheckBeforeEffect,
                Quality::CheckedMacroOutput,
            ]),
            "the A+C corner is not derived: {:?}",
            groups
        );

        // …and the load-bearing negative: none of the three PAIRS is
        // exclusive, so this is genuinely a trilemma and not two exclusions
        // wearing a hat. If a pair here ever became exclusive, the model would
        // be saying something much stronger than SAKIDORI measured.
        for (a, b) in [
            (
                Quality::ExpansionTimeEvaluation,
                Quality::ForwardDeclarationChecking,
            ),
            (
                Quality::ExpansionTimeEvaluation,
                Quality::CheckedMacroOutput,
            ),
            (
                Quality::ForwardDeclarationChecking,
                Quality::CheckedMacroOutput,
            ),
        ] {
            assert!(
                witness(a, b).is_some(),
                "{} + {} must still have a witness — pick TWO of three",
                a.label(),
                b.label()
            );
        }
    }

    /// **The one new PAIR the trilemma brought with it**, and it is the sharp
    /// end of the whole thing: a posture that keeps `eval` resident can never
    /// promise that what a macro emitted was checked, because at `Anytime`
    /// expansion cannot finish before the checker starts.
    ///
    /// Derived, not asserted — `witness` searches the lattice and finds
    /// nothing.
    #[test]
    fn a_resident_evaluator_excludes_checked_macro_output() {
        assert!(witness(Quality::ResidentEvaluator, Quality::CheckedMacroOutput).is_none());
        assert!(
            exclusive_pairs().contains(&(Quality::ResidentEvaluator, Quality::CheckedMacroOutput))
        );
    }

    /// **The completeness gate (★★ CLOSED-LOOP MASS-SYNTHESIS).** A quality
    /// that lands without an axis, a tier, a reason or a place in the
    /// derivation must fail the build.
    ///
    /// Most of that is the compiler's job and is stated here so a reader knows
    /// where to look: `axis`, `label`, `next` and `enforcement` are exhaustive
    /// matches with no wildcard arm (`E0004`), and `Quality::chain` turns a
    /// variant with no slot in `ALL` into a const-evaluation failure. This test
    /// covers what the compiler cannot see — that the row is *meaningful*, not
    /// merely present.
    ///
    /// **Anti-vacuity floors, measured 2026-08-12**, because a gate that
    /// iterates an empty catalog verifies nothing and this repo has been bitten
    /// by exactly that: 13 qualities, 3 axes, 7 derived pairs, 15 derived
    /// minimal groups.
    #[test]
    fn every_quality_has_an_axis_a_tier_and_a_place_in_the_derivation() {
        assert!(
            Quality::ALL.len() >= 13,
            "the catalog shrank to {} — a quality was removed, not added",
            Quality::ALL.len()
        );
        assert_eq!(Quality::ALL.len(), Quality::COUNT);
        assert!(Axis::ALL.len() >= 3);

        let lattice = all_postures();
        for q in Quality::ALL {
            assert!(!q.label().is_empty(), "{q:?} has no label");
            assert!(
                Axis::ALL.contains(&q.axis()),
                "{} names an axis outside `Axis::ALL`",
                q.label()
            );
            let (_, why) = crate::morph::enforcement(q);
            assert!(
                why.len() > 30,
                "{} has a reason too short to be one: {why}",
                q.label()
            );

            // It must be a CHOICE the lattice makes: some posture grants it and
            // some posture does not. A quality granted by every posture is not
            // a posture question at all, and one granted by none is a name for
            // something blue cannot be.
            assert!(
                lattice.iter().any(|w| qualities_at(w).contains(&q)),
                "{} is granted by no posture",
                q.label()
            );
            assert!(
                lattice.iter().any(|w| !qualities_at(w).contains(&q)),
                "{} is granted by EVERY posture, so the lattice decides nothing \
                 about it — it does not belong here",
                q.label()
            );
        }

        assert!(
            exclusive_pairs().len() >= 7,
            "the derivation found {} pairs, below the 2026-08-12 floor of 7",
            exclusive_pairs().len()
        );
        assert!(
            minimal_exclusive_groups().len() >= 15,
            "the derivation found {} minimal groups, below the 2026-08-12 floor of 15",
            minimal_exclusive_groups().len()
        );
    }

    /// **The gate that makes the axis attribution real rather than a label.**
    ///
    /// Move one coordinate of a posture and nothing else, and ask what changed:
    /// every quality that moved must be attributed to *that* coordinate, and
    /// something must move. This is what stops `axis()` from being a comment —
    /// it anchors the attribution to `qualities_at`, which is where the
    /// derivation actually reads from.
    ///
    /// **Red run, 2026-08-12:** `Quality::ProcessIsolation`'s arm in `axis()`
    /// moved from `Axis::Where` to `Axis::When` → this test fails with
    /// *"process isolation moved when only Where changed"*, and
    /// `every_exclusive_pair_shares_an_axis` fails alongside it because
    /// `process isolation ⊥ shared mutable state` becomes a cross-axis pair.
    /// Restoring the arm returned both to green. The mutation is not
    /// semantically equivalent — it changes which coordinate the model claims
    /// decides isolation — which is the trap this repo names.
    ///
    /// It is also the axis-completeness check: an axis that no posture pair can
    /// isolate, or that decides no quality, is a dead coordinate and fails
    /// here.
    #[test]
    fn each_coordinate_decides_exactly_its_own_axis() {
        let lattice = all_postures();
        for axis in Axis::ALL {
            let mut moved = 0usize;
            for a in &lattice {
                for b in &lattice {
                    if !axis.isolates(a, b) {
                        continue;
                    }
                    let (qa, qb) = (qualities_at(a), qualities_at(b));
                    let diff: Vec<Quality> = qa.symmetric_difference(&qb).copied().collect();
                    assert!(
                        !diff.is_empty(),
                        "{} changed and no quality moved: {a:?} vs {b:?}",
                        axis.label()
                    );
                    for q in &diff {
                        assert_eq!(
                            q.axis(),
                            axis,
                            "{} moved when only {} changed, but claims the {} axis",
                            q.label(),
                            axis.label(),
                            q.axis().label()
                        );
                    }
                    moved += diff.len();
                }
            }
            assert!(
                moved > 0,
                "no posture pair isolates {} — the coordinate is dead in this lattice",
                axis.label()
            );
        }
    }

    /// The two derivations must agree where they overlap.
    ///
    /// `exclusive_pairs` walks the catalog directly and asks [`witness`];
    /// `minimal_exclusive_groups` packs postures into bitmasks and enumerates
    /// subsets. They are independent code paths reaching the same fact, which
    /// is the standard this repo sets — a gate derived from the thing it checks
    /// is a tautology.
    #[test]
    fn the_two_derivations_agree_on_pairs() {
        let from_groups: Vec<(Quality, Quality)> = minimal_exclusive_groups()
            .into_iter()
            .filter(|g| g.len() == 2)
            .map(|g| (g[0], g[1]))
            .collect();
        assert_eq!(from_groups, exclusive_pairs());
    }

    /// Minimality is not decoration: dropping any member of a derived group
    /// must make it satisfiable, and no group may contain another.
    #[test]
    fn every_derived_group_is_actually_minimal() {
        let groups = minimal_exclusive_groups();
        for g in &groups {
            assert!(witness_all(g).is_none(), "{g:?} has a witness");
            for i in 0..g.len() {
                let mut sub = g.clone();
                sub.remove(i);
                assert!(
                    witness_all(&sub).is_some(),
                    "{sub:?} is already exclusive, so {g:?} is not minimal"
                );
            }
            for other in &groups {
                if other != g {
                    assert!(
                        !other.iter().all(|q| g.contains(q)),
                        "{g:?} contains {other:?}"
                    );
                }
            }
        }
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

    /// **The hole detector: no two postures grant the same qualities.**
    ///
    /// This is the completeness check the catalog could not do for itself. A
    /// coordinate value that no quality distinguishes from its neighbour is a
    /// declaration an author can make and nothing can act on — the lattice has
    /// a point and the model has no name for what it buys. That is precisely a
    /// missing quality, and it fails here rather than sitting unnoticed.
    ///
    /// **This test was RED before the macro-phase qualities landed, and that is
    /// how the hole was found.** Under the nine-quality catalog `When::Sealed`
    /// and `When::Preceding` granted *identical* sets — `{preemptive
    /// scheduling, minimal artifact, ahead-of-time specialization}` for both —
    /// so a three-valued coordinate was carrying two distinguishable values and
    /// six of the eighteen postures were duplicates of another six. Measured by
    /// reverting the new `When` block: 12 distinct quality sets over 18
    /// postures. With the block: 18 over 18.
    ///
    /// It also fixed a shipped catalog entry nobody could have caught before:
    /// `shapes()` placed Rust at `Preceding`, a choice that was unobservable
    /// while the two points collapsed.
    #[test]
    fn every_posture_is_distinguishable_from_every_other() {
        let lattice = all_postures();
        let mut seen: Vec<(Waku, BTreeSet<Quality>)> = Vec::new();
        for w in lattice {
            let have = qualities_at(&w);
            if let Some((other, _)) = seen.iter().find(|(_, q)| *q == have) {
                panic!(
                    "{w:?} and {other:?} grant the same qualities — a coordinate value \
                     no quality distinguishes is a hole in the catalog, not a subtlety"
                );
            }
            seen.push((w, have));
        }
        assert_eq!(seen.len(), 18, "the lattice is 3 x 3 x 2");
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
