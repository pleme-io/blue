//! The import table a frame lowers to — **`theory/BLUE-EXECUTION.md` M1.**
//!
//! `BLUE-EXECUTION.md` §0 states the mechanism in one sentence: *"a module's
//! import table is the lowering of the `waku` it was minted from, so
//! narrow-cannot-widen stops being a lattice property blue asserts and becomes
//! a property the engine enforces because the import is absent."*
//!
//! This module is that lowering, and nothing else. It does **not** put an
//! import into a wasm module — a core-wasm import table is static in the
//! binary and a frame is a runtime value, so emitting one is code generation
//! behind the engine border, which is M2 and is blocked on a decision
//! `BLUE-EXECUTION.md` §VII states rather than hides. What lands here is the
//! function M2 will call, with its totality gated now rather than later.
//!
//! ## Why this is derived and not a list
//!
//! [`imports_of`] never names a capability. It filters [`Capability::ALL`] by
//! what the frame grants and asks [`Capability::import`] — an exhaustive match
//! with no wildcard arm — for each survivor. So:
//!
//! - a capability cannot be **skipped**: it is in `ALL`, which is derived from
//!   the `next` chain that a new variant must join to compile;
//! - a capability cannot be **guessed at**: adding one without deciding its
//!   import is `E0004` in `capability.rs`;
//! - an import cannot be **invented**: there is nowhere here to write one.
//!
//! A hand-listed table would satisfy every test in this file that reads a
//! *count*, which is why the gates below read the *derivation* — every subset
//! of the universe, and the narrowing law over every frame pair.

use crate::{Capability, Import, Waku};

/// The import table `waku` lowers to.
///
/// Deterministic order: [`Capability::ALL`]'s, which puts the pure bundles
/// first and therefore emits host imports in a stable sequence.
///
/// Two properties this buys, both gated below:
///
/// - **An empty frame derives an empty table.** `blue-lang-wasm`'s shipped
///   `imports: 0` is preserved verbatim, which is the condition the corpus
///   cites blue for — the resolution is never "give blue a socket".
/// - **Narrowing can only ever shrink the table.** A capability the frame lost
///   has no entry, no symbol and no stub.
///
/// `Reach::Unrestricted` is the top of the coordinate, so it derives *every*
/// host import. That is the honest total lowering and it is worth stating
/// plainly rather than special-casing: an unannotated blue program runs in
/// [`Waku::top`], and a module minted from `top` could reach everything blue
/// can reach. Narrowing is what makes an artifact smaller than that.
#[must_use]
pub fn imports_of(waku: &Waku) -> Vec<Import> {
    Capability::ALL
        .into_iter()
        .filter(|c| waku.reach.grants(*c))
        .filter_map(Capability::import)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Reach, When, Where};
    use std::collections::BTreeSet;

    fn frame(caps: impl IntoIterator<Item = Capability>) -> Waku {
        Waku {
            reach: Reach::only(caps),
            when: When::Preceding,
            place: Where::Process,
        }
    }

    /// **The shipped property, preserved verbatim.** A frame that declares
    /// nothing opens nothing.
    #[test]
    fn an_empty_frame_derives_no_imports() {
        assert!(imports_of(&Waku::bottom()).is_empty());
        assert!(imports_of(&frame([])).is_empty());
    }

    /// A frame of purely pure bundles still opens nothing — which is the
    /// interesting half, because it is the frame `blue-lang-wasm` is minted
    /// from and it is not empty.
    #[test]
    fn a_frame_of_pure_capabilities_derives_no_imports() {
        let pure: Vec<Capability> = Capability::ALL
            .into_iter()
            .filter(|c| !c.is_host_effect())
            .collect();
        assert_eq!(pure.len(), 6, "the floor, 2026-08-13");
        assert!(imports_of(&frame(pure)).is_empty());
    }

    /// The top of the coordinate derives every host import — the honest total
    /// lowering, asserted rather than left to be discovered.
    #[test]
    fn the_top_frame_derives_every_host_import() {
        let table = imports_of(&Waku::top());
        assert_eq!(table.len(), Capability::host_effects().len());
        assert_eq!(table.len(), 4, "the floor, 2026-08-13");
    }

    /// **The totality gate, over every subset of the universe.**
    ///
    /// 2^10 = 1024 frames, each compared against an *independently computed*
    /// expectation — the subset intersected with the host effects — rather than
    /// against `imports_of` itself. A hand-listed table passes the count tests
    /// above and fails here the moment one capability is missing from it.
    #[test]
    fn the_table_is_exactly_the_host_capabilities_the_frame_grants() {
        let all = Capability::ALL;
        for mask in 0u32..(1 << Capability::COUNT) {
            let subset: Vec<Capability> = (0..Capability::COUNT)
                .filter(|i| mask & (1 << i) != 0)
                .map(|i| all[i])
                .collect();
            let want: Vec<Import> = subset
                .iter()
                .filter(|c| c.is_host_effect())
                .map(|c| c.import().expect("a host effect has an import"))
                .collect();
            assert_eq!(
                imports_of(&frame(subset.clone())),
                want,
                "frame {:?}",
                subset.iter().map(|c| c.label()).collect::<Vec<_>>()
            );
        }
    }

    /// **A frame that omits a capability omits its import.**
    ///
    /// The one-line statement of the whole design, and the target of red run 4
    /// below: it is the test that goes red when the derivation stops reading
    /// the frame.
    #[test]
    fn a_frame_that_omits_a_capability_omits_its_import() {
        let with = imports_of(&frame([Capability::FileSystem, Capability::Clock]));
        let without = imports_of(&frame([Capability::Clock]));
        let fs = Capability::FileSystem
            .import()
            .expect("filesystem is a host effect");
        assert!(
            with.contains(&fs),
            "the granted import must appear: {with:?}"
        );
        assert!(
            !without.contains(&fs),
            "the omitted import must NOT appear: {without:?}"
        );
        // Anti-vacuity: the two tables must actually differ, and by exactly
        // that one entry. A derivation that returned an empty table always
        // would satisfy the `!contains` half on its own.
        assert_eq!(with.len(), without.len() + 1);
        assert_eq!(without.len(), 1);
    }

    /// **narrow-cannot-widen, carried through the lowering.**
    ///
    /// The lattice law says the narrowed frame is below its receiver. This says
    /// the *artifact* follows: a narrowed frame's table is a subset of the
    /// receiver's, so no narrowing can ever add an opening. Exhaustive over
    /// every ordered pair of a spread of frames.
    #[test]
    fn narrowing_never_widens_the_import_table() {
        let frames = [
            Waku::top(),
            Waku::bottom(),
            frame([Capability::FileSystem]),
            frame([Capability::Clock, Capability::Process]),
            frame([Capability::Operators, Capability::Environment]),
            frame(Capability::ALL),
        ];
        for a in &frames {
            for b in &frames {
                let before: BTreeSet<Import> = imports_of(a).into_iter().collect();
                let after: BTreeSet<Import> = imports_of(&a.narrow(b)).into_iter().collect();
                assert!(
                    after.is_subset(&before),
                    "narrowing widened the table: {before:?} -> {after:?}"
                );
            }
        }
    }

    /// Anti-vacuity for the law above: narrowing must be able to actually
    /// REMOVE an import. If every table were empty the subset law would hold
    /// trivially.
    #[test]
    fn narrowing_actually_removes_an_import() {
        let open = Waku::top();
        let narrowed = open.narrow(&frame([Capability::Operators]));
        assert_eq!(imports_of(&open).len(), 4);
        assert!(
            imports_of(&narrowed).is_empty(),
            "narrowing to a pure bundle must close every import"
        );
    }

    // ── RED RUNS, recorded ────────────────────────────────────────────────
    //
    // 4. **The table is derived, not hand-listed.** Verified 2026-08-13 by
    //    deleting `.filter(|c| waku.reach.grants(*c))` from `imports_of` — the
    //    only line where the frame is read. FIVE tests went red, including
    //    `a_frame_that_omits_a_capability_omits_its_import` with
    //
    //        the omitted import must NOT appear: [Import { module: "blue:host",
    //        field: "process" }, Import { module: "blue:host", field: "fs" },
    //        Import { module: "blue:host", field: "env" }, Import { module:
    //        "blue:host", field: "clock" }]
    //
    //    — the expected import stopped following the frame and started
    //    appearing unconditionally. Reverted.
    //
    // 5. **A plausible hand-list does not pass.** Verified 2026-08-13 by
    //    replacing the body of `imports_of` with `Capability::host_effects()
    //    .filter_map(Capability::import)`, which ignores the frame and is
    //    exactly the shape a maintained table would take. The same five tests
    //    failed, `the_table_is_exactly_the_host_capabilities_the_frame_grants`
    //    on the very first subset (`frame []`). Reverted.
    //
    //    Recorded because the repo's named trap is a mutation that is
    //    semantically equivalent to the original: this one is NOT — it changes
    //    what the function computes for every frame except `Waku::top()`, and
    //    the gate sees it.
}
