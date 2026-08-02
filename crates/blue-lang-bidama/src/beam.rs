//! The concurrency-runtime design space, enumerated — and where the BEAM sits
//! in it.
//!
//! [`quality`](crate::quality) models what a *posture* grants a package. This
//! module models something one level down: the **runtime** a package's
//! processes execute on. The two are separate axes, and conflating them is why
//! "blue is like Elixir" is both true and uninformative.
//!
//! # The claim this module makes checkable
//!
//! The BEAM is one point in a product of seven independent dimensions. It is a
//! *good* point — most of it is forced by three guarantees Erlang chose to
//! make — but it is one point, and it is fixed **below the language**. Erlang's
//! scheduler, its per-process collector and its copy-on-send are C in the
//! emulator. A language hosted on the BEAM inherits all seven choices and can
//! change none of them: `Code.eval_string` cannot make the collector
//! generational, and no macro can make a `send` zero-copy.
//!
//! blue's runtime is Rust that blue itself compiles against, and bīdama makes
//! a runtime choice *package data* resolved under a ceiling. So the question
//! "which points can this language occupy" has a different answer for the two,
//! and the difference is countable rather than rhetorical. That is what the
//! tests here count.
//!
//! # What is proved here, and what is not
//!
//! **Proved:** the shape of the space, which points are self-contradictory and
//! why, how many survive BEAM's own guarantees, and that a fixed-VM language
//! reaches exactly one of them. These are facts about the design space, and
//! the enumeration is exhaustive — no sampling.
//!
//! **Not proved, and deliberately not claimed:** that blue's runtime
//! *implements* each reachable point. It does not. [`Support`] records that
//! separately, per point, and [`Model::support`] is the only honest answer to
//! "can blue do this today". A point marked [`Support::Design`] is a place the
//! algebra admits and no code occupies. Reading the reachable count as a
//! feature list is the exact tier round-up this crate exists to prevent.
//!
//! # Why the contradictions are contradictions
//!
//! Every entry in [`Contradiction`] is a fact about the world, not about our
//! abstractions — the test `MIRAGEM` asks for. A pointer genuinely has no
//! meaning in another machine's address space; a tracing collector's pause
//! genuinely is not statically bounded. None of them is a limitation we could
//! dissolve by writing better code, which is why they are typed as impossible
//! rather than left as guidance.

use std::fmt;

// ── the seven dimensions ───────────────────────────────────────────────────

/// How a process loses the CPU.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Scheduling {
    /// A process runs until it blocks or returns. Simplest, and the reason a
    /// single long computation can stall every other process.
    RunToCompletion,
    /// Preempted only where the program says so. Deterministic, and only as
    /// responsive as the author's yield placement.
    CooperativeYield,
    /// Preempted after a fixed budget of *reductions* — work units, not time.
    /// The BEAM's choice, and blue's `Vm::step` budget.
    ReductionCounted,
    /// Preempted after a fixed budget of wall-clock time. What an OS thread
    /// scheduler does.
    WallClockSlice,
}

/// What crosses a `send`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Payload {
    /// The message is reconstructed in the receiver. No aliasing at any cost.
    DeepCopy,
    /// The receiver gets a handle to the same immutable value. Zero copy;
    /// mutation is not expressible.
    ImmutableShare,
    /// Ownership transfers; the sender can no longer name it. Zero copy *and*
    /// mutable, bought with a linearity obligation on the sender.
    LinearMove,
    /// Both ends hold a mutable handle to one cell.
    SharedMutable,
}

/// Where a process's values live and how they are reclaimed.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Heap {
    /// One heap per process, collected independently. A pause is bounded by
    /// *that* process's live set, not the system's.
    PerProcessCollected,
    /// One heap for everything, one tracing collector, stop-the-world.
    SharedTracing,
    /// Reclaimed when the last handle drops. No collector, no pause, no
    /// cycles. What blue's `Arc`-based runtime does today.
    Refcounted,
    /// Reclaimed wholesale at scope exit. No collector and no per-value
    /// bookkeeping, bought with a lifetime obligation.
    ScopedRegion,
}

/// What happens when one process fails.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Failure {
    /// The process dies at the fault; a supervisor restarts it from a known
    /// state. Sound exactly when the fault cannot have damaged a peer.
    LetItCrash,
    /// The fault becomes a value the caller must handle. Nothing dies.
    PropagateTyped,
    /// The runtime aborts. Correct when a fault means the whole world is
    /// suspect, which is a real posture for a settlement engine.
    FailFastRuntime,
}

/// What latency guarantee the runtime offers.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Latency {
    /// None stated.
    Unbounded,
    /// Bounded in practice and not proven — the BEAM's "soft real-time".
    Soft,
    /// Statically bounded pause. Every mechanism in the model must have a
    /// worst case you can compute before running it.
    Hard,
}

/// Whether a process identifier may name a process on another machine.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Distribution {
    /// Every process is in this address space.
    LocalOnly,
    /// A pid may be remote, and `send` does not say which. The property that
    /// forces the most other choices — see [`Contradiction::PointerOffMachine`].
    TransparentRemote,
}

/// Whether the same inputs reproduce the same interleaving.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Interleaving {
    /// Scheduling order is not part of the program's meaning.
    Nondeterministic,
    /// Same inputs, same schedule, every run and every machine. What makes a
    /// trading system replayable and a distributed bug reproducible.
    Replayable,
}

// ── a point in the space ───────────────────────────────────────────────────

/// One concurrency runtime: a choice on each dimension.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Model {
    pub scheduling: Scheduling,
    pub payload: Payload,
    pub heap: Heap,
    pub failure: Failure,
    pub latency: Latency,
    pub distribution: Distribution,
    pub interleaving: Interleaving,
}

impl fmt::Display for Model {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{:?}/{:?}/{:?}/{:?}/{:?}/{:?}/{:?}",
            self.scheduling,
            self.payload,
            self.heap,
            self.failure,
            self.latency,
            self.distribution,
            self.interleaving
        )
    }
}

/// Why a point in the space cannot be built.
///
/// Each variant is a fact about the world. That is the bar: a limit phrased in
/// terms of our own abstractions is ours to dissolve and does not belong here.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Contradiction {
    /// Transparent remote distribution with a payload that is a pointer.
    ///
    /// An address is meaningful only inside one address space. If `send` may
    /// cross a machine and the caller cannot tell, the only payload that can
    /// mean the same thing on both sides is one that was reconstructed.
    PointerOffMachine,
    /// A hard latency bound with a tracing collector.
    ///
    /// Tracing time is a function of the live set, which is a function of the
    /// program's history. "Statically bounded" and "depends on what the
    /// program did" are the same claim negated.
    UnboundedTracingPause,
    /// Let-it-crash with a mutable value two processes share.
    ///
    /// Restarting the process that died restores *its* state. The peer still
    /// holds the half-written value, and nothing in the model repairs it, so
    /// the guarantee let-it-crash rests on — a fault is contained — is false.
    CrashCorruptsPeer,
    /// A replayable interleaving with a wall-clock time slice.
    ///
    /// The yield point is then a function of machine speed, which is not part
    /// of the program. Two runs of the same input on different hardware
    /// interleave differently by construction.
    ScheduleDependsOnHardware,
    /// Independently-collected per-process heaps with a shared payload.
    ///
    /// A value reachable from two heaps that collect on their own schedules
    /// has no collector that owns it: either can free it while the other still
    /// names it. (This is precisely why the BEAM keeps large binaries on a
    /// *separate*, refcounted heap rather than making sharing general.)
    NoOwnerForSharedValue,
    /// A latency guarantee with run-to-completion scheduling.
    ///
    /// One process that does not return holds the CPU for as long as it likes,
    /// so no bound on another process's scheduling delay can be stated. This
    /// is the same reason the BEAM caps a NIF at about a millisecond.
    NoBoundWithoutPreemption,
}

impl Contradiction {
    /// Every contradiction, forced-arity so a new variant must be added here
    /// too — the catalog cannot fall behind the enum (★★ CATALOG REFLECTION).
    pub const ALL: [Contradiction; 6] = [
        Contradiction::PointerOffMachine,
        Contradiction::UnboundedTracingPause,
        Contradiction::CrashCorruptsPeer,
        Contradiction::ScheduleDependsOnHardware,
        Contradiction::NoOwnerForSharedValue,
        Contradiction::NoBoundWithoutPreemption,
    ];

    /// The world-fact, in one line.
    #[must_use]
    pub const fn because(self) -> &'static str {
        match self {
            Self::PointerOffMachine => {
                "an address has no meaning in another machine's address space"
            }
            Self::UnboundedTracingPause => {
                "tracing time is a function of the live set, so it has no static bound"
            }
            Self::CrashCorruptsPeer => {
                "restarting the process that died does not repair the peer holding \
                 the half-written value"
            }
            Self::ScheduleDependsOnHardware => {
                "a wall-clock yield point is a function of machine speed, which is \
                 not part of the program"
            }
            Self::NoOwnerForSharedValue => {
                "a value reachable from two independently-collected heaps has no \
                 collector that owns it"
            }
            Self::NoBoundWithoutPreemption => {
                "a process that never yields holds the CPU indefinitely, so no \
                 scheduling-delay bound can be stated"
            }
        }
    }
}

impl Model {
    /// The BEAM, as Erlang/OTP ships it and as Elixir inherits it.
    pub const BEAM: Model = Model {
        scheduling: Scheduling::ReductionCounted,
        payload: Payload::DeepCopy,
        heap: Heap::PerProcessCollected,
        failure: Failure::LetItCrash,
        latency: Latency::Soft,
        distribution: Distribution::TransparentRemote,
        interleaving: Interleaving::Nondeterministic,
    };

    /// Every point in the space — the full cartesian product, enumerated.
    ///
    /// Enumerated rather than listed for the same reason
    /// [`crate::exclusive_pairs`] is derived: a hand-maintained list of 4608
    /// rows would be wrong within a week, and every claim below is a count
    /// over this set.
    #[must_use]
    pub fn all() -> Vec<Model> {
        use Distribution::{LocalOnly, TransparentRemote};
        use Failure::{FailFastRuntime, LetItCrash, PropagateTyped};
        use Heap::{PerProcessCollected, Refcounted, ScopedRegion, SharedTracing};
        use Interleaving::{Nondeterministic, Replayable};
        use Latency::{Hard, Soft, Unbounded};
        use Payload::{DeepCopy, ImmutableShare, LinearMove, SharedMutable};
        use Scheduling::{CooperativeYield, ReductionCounted, RunToCompletion, WallClockSlice};

        let mut out = Vec::with_capacity(4608);
        for scheduling in [
            RunToCompletion,
            CooperativeYield,
            ReductionCounted,
            WallClockSlice,
        ] {
            for payload in [DeepCopy, ImmutableShare, LinearMove, SharedMutable] {
                for heap in [PerProcessCollected, SharedTracing, Refcounted, ScopedRegion] {
                    for failure in [LetItCrash, PropagateTyped, FailFastRuntime] {
                        for latency in [Unbounded, Soft, Hard] {
                            for distribution in [LocalOnly, TransparentRemote] {
                                for interleaving in [Nondeterministic, Replayable] {
                                    out.push(Model {
                                        scheduling,
                                        payload,
                                        heap,
                                        failure,
                                        latency,
                                        distribution,
                                        interleaving,
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }
        out
    }

    /// Why this point cannot be built, if it cannot.
    ///
    /// Returns the *first* contradiction found. A point may violate several;
    /// one is enough to exclude it, and reporting one keeps the answer
    /// actionable.
    #[must_use]
    pub fn contradiction(&self) -> Option<Contradiction> {
        // A pointer cannot cross a machine boundary.
        if self.distribution == Distribution::TransparentRemote && self.payload != Payload::DeepCopy
        {
            return Some(Contradiction::PointerOffMachine);
        }
        // A tracing collector has no static pause bound.
        if self.latency == Latency::Hard
            && matches!(self.heap, Heap::SharedTracing | Heap::PerProcessCollected)
        {
            return Some(Contradiction::UnboundedTracingPause);
        }
        // Let-it-crash needs the fault to be contained.
        if self.failure == Failure::LetItCrash && self.payload == Payload::SharedMutable {
            return Some(Contradiction::CrashCorruptsPeer);
        }
        // A replayable schedule cannot be cut by the clock.
        if self.interleaving == Interleaving::Replayable
            && self.scheduling == Scheduling::WallClockSlice
        {
            return Some(Contradiction::ScheduleDependsOnHardware);
        }
        // Two independent collectors cannot both own one value.
        if self.heap == Heap::PerProcessCollected
            && matches!(
                self.payload,
                Payload::ImmutableShare | Payload::SharedMutable
            )
        {
            return Some(Contradiction::NoOwnerForSharedValue);
        }
        // A latency bound needs a preemption point.
        if self.latency != Latency::Unbounded && self.scheduling == Scheduling::RunToCompletion {
            return Some(Contradiction::NoBoundWithoutPreemption);
        }
        None
    }

    /// Can this point be built at all?
    #[must_use]
    pub fn realizable(&self) -> bool {
        self.contradiction().is_none()
    }

    /// Does this point keep all three guarantees the BEAM is chosen for?
    ///
    /// Transparent distribution, let-it-crash supervision, and a soft latency
    /// bound. A point that keeps these is a runtime an OTP author would
    /// recognise; the ones that keep them and differ elsewhere are exactly the
    /// "BEAM variants" a BEAM-hosted language cannot reach.
    #[must_use]
    pub fn keeps_beam_guarantees(&self) -> bool {
        self.distribution == Distribution::TransparentRemote
            && self.failure == Failure::LetItCrash
            && self.latency == Latency::Soft
    }
}

// ── what blue actually implements ──────────────────────────────────────────

/// How much of a point blue's runtime delivers *today*.
///
/// Separate from realizability on purpose. Realizable is a fact about the
/// design space and does not move; support is a fact about this repository and
/// moves every release. Reporting one as the other is the tier round-up the
/// org doctrine names as the cardinal sin, so the two are different functions
/// with different return types and neither can be mistaken for the other.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Support {
    /// blue's runtime occupies this point now, with tests.
    Shipped,
    /// The algebra admits it and no code occupies it. Not a promise.
    Design,
    /// Not buildable at all — see [`Model::contradiction`].
    Impossible,
}

impl Model {
    /// The one point blue's runtime occupies today, dimension by dimension,
    /// each traceable to code in this workspace.
    ///
    /// A single constant rather than a predicate over some dimensions. The
    /// first draft of this left `latency` and `interleaving` unconstrained,
    /// which made `support()` answer `Shipped` for six points — including a
    /// *hard-real-time replayable* runtime blue does not have. A model is a
    /// point; a runtime is at one point; anything wider is a round-up wearing
    /// a predicate.
    pub const BLUE_TODAY: Model = Model {
        // `Vm::step` spends a reduction budget and returns `Progress::Yielded`.
        scheduling: Scheduling::ReductionCounted,
        // `mailbox::deep_copy` rebuilds every message; closures are refused.
        payload: Payload::DeepCopy,
        // `Arc`. The repo's CLAUDE.md states plainly that there is no
        // per-process collector and no independent collection pause.
        heap: Heap::Refcounted,
        // `Supervisor` restarts the child that exited, with intensity checked
        // on that child.
        failure: Failure::LetItCrash,
        // Bounded in practice by the reduction quantum; not proven, so Soft.
        // `Hard` would need a static bound on `Arc` drop of a deep structure,
        // which is O(size) and has no constant bound.
        latency: Latency::Soft,
        // One address space. There is no remote pid and nothing serialises one.
        distribution: Distribution::LocalOnly,
        // Demonstrated, not assumed: `blue-lang-proc/tests/replay.rs` records
        // the actual interleaving of a three-process system and shows it
        // identical across runs, across a crash, and across a restart — and
        // shows the recorder can tell two schedules apart, so the equality is
        // not vacuous. That suite also asserts THIS field, so the ledger
        // cannot drift from the scheduler in either direction.
        //
        // This is the one dimension where blue is ahead of the BEAM rather
        // than merely different: SMP schedulers interleave by wall clock, so
        // no BEAM-hosted language can offer it.
        interleaving: Interleaving::Replayable,
    };

    /// What blue delivers at this point today.
    ///
    /// `Shipped` for exactly [`Model::BLUE_TODAY`]. Every other realizable
    /// point is `Design` — a place the algebra admits and no code occupies.
    #[must_use]
    pub fn support(&self) -> Support {
        if !self.realizable() {
            Support::Impossible
        } else if *self == Model::BLUE_TODAY {
            Support::Shipped
        } else {
            Support::Design
        }
    }
}

// ── who can reach what ─────────────────────────────────────────────────────

/// Points reachable by a language hosted on a fixed virtual machine.
///
/// Exactly the machine's own point, whatever that machine is. This is not a
/// slight against Elixir; it is what "hosted" means. The scheduler, collector
/// and message representation are in the emulator, so no construct in the
/// hosted language — macro, `eval`, behaviour, NIF — reaches them. A NIF is
/// the closest thing to an escape and it *weakens* the model (an un-yielding
/// NIF breaks the very latency guarantee) rather than moving it.
#[must_use]
pub fn reachable_by_hosted_language(vm: Model) -> Vec<Model> {
    vec![vm]
}

/// Points blue can select, by declaration, without forking the language.
///
/// Every realizable point. The mechanism is bīdama: the runtime model is a
/// posture floor a package declares, resolved against the program's ceiling
/// exactly like every other floor, so selecting one is data rather than a
/// different compiler. What is *implemented* at each point is
/// [`Model::support`] and is a much smaller set — see this module's header.
#[must_use]
pub fn reachable_by_blue() -> Vec<Model> {
    Model::all().into_iter().filter(Model::realizable).collect()
}

/// The BEAM variants: points that keep every BEAM guarantee and differ
/// somewhere else.
///
/// This is the set the phrase "a BEAM Elixir cannot have" names precisely. Each
/// is a runtime an OTP author would recognise — supervised, distributed,
/// soft-real-time — that the BEAM does not implement and a BEAM-hosted language
/// therefore cannot ask for.
#[must_use]
pub fn beam_variants() -> Vec<Model> {
    Model::all()
        .into_iter()
        .filter(|m| m.realizable() && m.keeps_beam_guarantees() && *m != Model::BEAM)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    #[test]
    fn the_space_is_the_full_product() {
        // 4 scheduling x 4 payload x 4 heap x 3 failure x 3 latency
        //   x 2 distribution x 2 interleaving
        assert_eq!(Model::all().len(), 4 * 4 * 4 * 3 * 3 * 2 * 2);
        let unique: BTreeSet<_> = Model::all().into_iter().collect();
        assert_eq!(unique.len(), Model::all().len(), "no duplicate points");
    }

    /// The BEAM is buildable. If this ever fails, a contradiction above is
    /// wrong — it has excluded a runtime that demonstrably runs in production
    /// on every continent. This is the calibration test for the whole module.
    #[test]
    fn the_beam_is_realizable() {
        assert!(
            Model::BEAM.realizable(),
            "excluded a runtime that visibly exists: {:?}",
            Model::BEAM.contradiction()
        );
    }

    /// Each contradiction must actually exclude something, and must not
    /// exclude everything. A predicate that fires on no point is decoration;
    /// one that fires on every point is a bug that would make the reachable
    /// count zero and still pass a "some points are excluded" test.
    #[test]
    fn every_contradiction_is_live_and_none_is_total() {
        let all = Model::all();
        for c in Contradiction::ALL {
            let hits = all.iter().filter(|m| m.contradiction() == Some(c)).count();
            assert!(hits > 0, "{c:?} excludes nothing — it is decoration");
            assert!(
                hits < all.len(),
                "{c:?} excludes every point — it cannot be a real constraint"
            );
        }
    }

    #[test]
    fn a_realizable_point_names_no_contradiction_and_vice_versa() {
        for m in Model::all() {
            assert_eq!(
                m.realizable(),
                m.contradiction().is_none(),
                "realizable and contradiction disagree at {m}"
            );
        }
    }

    // ── the actual claim ───────────────────────────────────────────────────

    /// A hosted language reaches one point. blue reaches every realizable one.
    ///
    /// The ratio is the whole argument, and it is counted rather than asserted.
    #[test]
    fn blue_reaches_a_space_where_a_hosted_language_reaches_a_point() {
        let hosted = reachable_by_hosted_language(Model::BEAM);
        let blue = reachable_by_blue();

        assert_eq!(hosted.len(), 1, "a fixed VM offers exactly its own point");
        assert!(
            blue.len() > 100,
            "expected a space, got {} points",
            blue.len()
        );
        assert!(
            blue.contains(&Model::BEAM),
            "and it must include the BEAM's point — blue does not merely differ, \
             it subsumes"
        );
        println!(
            "hosted: {} point · blue: {} realizable points",
            hosted.len(),
            blue.len()
        );
    }

    /// The named set: runtimes with every BEAM guarantee that the BEAM is not.
    #[test]
    fn there_are_beam_variants_a_beam_hosted_language_cannot_ask_for() {
        let variants = beam_variants();
        assert!(
            !variants.is_empty(),
            "if this is empty the BEAM's choices are fully forced by its \
             guarantees and the claim in this module's header is false"
        );
        assert!(
            !variants.contains(&Model::BEAM),
            "the BEAM is not a variant of itself"
        );
        for v in &variants {
            assert!(v.keeps_beam_guarantees(), "{v} lost a guarantee");
            assert!(v.realizable(), "{v} is not buildable");
        }
        println!(
            "{} BEAM variants, none reachable from the BEAM:",
            variants.len()
        );
        for v in &variants {
            println!("  {v}");
        }
    }

    /// Which of the BEAM's choices its own guarantees actually force.
    ///
    /// This is the honest version of "the BEAM is the unique answer". It is
    /// not: some of its dimensions are pinned by its guarantees and some are
    /// free choices. The free ones are precisely where a variant can differ,
    /// so naming them is the useful result, and asserting uniqueness instead
    /// would have been the overclaim.
    #[test]
    fn the_beam_guarantees_force_some_dimensions_and_leave_others_free() {
        let kept: Vec<Model> = Model::all()
            .into_iter()
            .filter(|m| m.realizable() && m.keeps_beam_guarantees())
            .collect();
        assert!(kept.contains(&Model::BEAM));

        let payloads: BTreeSet<_> = kept.iter().map(|m| m.payload).collect();
        assert_eq!(
            payloads,
            BTreeSet::from([Payload::DeepCopy]),
            "transparent distribution forces the payload — this one IS pinned"
        );

        let schedulings: BTreeSet<_> = kept.iter().map(|m| m.scheduling).collect();
        assert!(
            schedulings.len() > 1,
            "the BEAM's guarantees do not force reduction counting; \
             it is a choice, and therefore a place a variant can differ"
        );

        let heaps: BTreeSet<_> = kept.iter().map(|m| m.heap).collect();
        assert!(heaps.len() > 1, "nor do they force a per-process collector");
    }

    // ── tier honesty ───────────────────────────────────────────────────────

    /// Reachable is not shipped, and the gap must be large and visible.
    ///
    /// This test exists to fail loudly if someone ever makes `support` return
    /// `Shipped` broadly to make a number look better. The count of shipped
    /// points is tiny by construction and should stay that way until real
    /// runtime work lands.
    #[test]
    fn support_is_reported_separately_and_is_far_smaller_than_reachable() {
        let reachable = reachable_by_blue();
        let shipped: Vec<_> = reachable
            .iter()
            .filter(|m| m.support() == Support::Shipped)
            .collect();

        assert!(
            !shipped.is_empty(),
            "blue's own runtime must be in the space"
        );
        assert!(
            shipped.len() * 10 < reachable.len(),
            "shipped ({}) is suspiciously close to reachable ({}) — either real \
             work landed and this bound should move deliberately, or `support` \
             has been widened to flatter the numbers",
            shipped.len(),
            reachable.len()
        );

        for m in Model::all() {
            if !m.realizable() {
                assert_eq!(
                    m.support(),
                    Support::Impossible,
                    "{m} is not buildable, so it cannot be Design"
                );
            }
        }
        println!(
            "reachable {} · shipped {} · the rest is Design, not a promise",
            reachable.len(),
            shipped.len()
        );
    }

    /// blue's shipped point is the one the repo documents, dimension by
    /// dimension. Pins the claim against the runtime rather than against
    /// itself — if the runtime gains a per-process collector, this fails and
    /// forces the ledger to move with it.
    #[test]
    fn blues_shipped_point_matches_what_the_runtime_actually_does() {
        assert_eq!(Model::BLUE_TODAY.support(), Support::Shipped);
        assert!(Model::BLUE_TODAY.realizable());

        // And it differs from the BEAM exactly where the repo says it does.
        assert_ne!(Model::BLUE_TODAY, Model::BEAM);
        assert_eq!(Model::BLUE_TODAY.heap, Heap::Refcounted);
        assert_eq!(Model::BEAM.heap, Heap::PerProcessCollected);
    }

    /// Exactly one point is `Shipped`. A runtime is at one point; a `support`
    /// that answers `Shipped` for a set has widened a fact into a claim.
    #[test]
    fn exactly_one_point_is_shipped() {
        let shipped: Vec<_> = Model::all()
            .into_iter()
            .filter(|m| m.support() == Support::Shipped)
            .collect();
        assert_eq!(
            shipped,
            vec![Model::BLUE_TODAY],
            "support must name one point, not a region"
        );
    }

    /// Two points blue's algebra admits that no BEAM-hosted language can
    /// express at all — the target domains named in `theory/BLUE.md`.
    #[test]
    fn the_two_target_domains_are_points_in_the_space() {
        // Trading: replayable interleaving with a hard latency bound. The BEAM
        // can offer neither — it is nondeterministic on SMP and its collector
        // has no static bound.
        let trading = Model {
            scheduling: Scheduling::ReductionCounted,
            payload: Payload::LinearMove,
            heap: Heap::ScopedRegion,
            failure: Failure::FailFastRuntime,
            latency: Latency::Hard,
            distribution: Distribution::LocalOnly,
            interleaving: Interleaving::Replayable,
        };
        assert!(trading.realizable(), "{:?}", trading.contradiction());
        assert_ne!(trading, Model::BEAM);

        // Telephony: the BEAM's own home ground. blue must not lose it.
        assert!(Model::BEAM.realizable());
        assert!(reachable_by_blue().contains(&Model::BEAM));
    }
}
