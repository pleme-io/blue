//! The gate that ties blue's **closed capability universe** to the runtime it
//! describes — `theory/BLUE-EXECUTION.md` M0/M1.
//!
//! # Why this test lives here and not in `blue-lang-waku`
//!
//! `Capability`'s four host bundles claim to be exactly what
//! `blue_lang_runtime::sys` installs. A test inside `blue-lang-waku` could only
//! compare that claim against itself — the repo's named trap: *"a gate derived
//! from the thing it checks is a tautology."* So the evidence is taken from a
//! **real interpreter**: install the sys layer into a bare one, diff the
//! reserved head names before and after, and compare the difference against the
//! universe.
//!
//! It lives in `blue-lang-cli` because `blue-lang-cli` is the only crate that
//! turns the `sys` feature on, and without it there is no host layer to install.
//!
//! # What each gate would catch
//!
//! - a new sys primitive landing with no capability claiming it — a name a frame
//!   could never grant and a program could therefore never legally call;
//! - a host name mis-filed under a **pure** bundle — which would put a host
//!   effect inside a module that derives **zero imports**, the exact failure the
//!   whole design exists to make impossible;
//! - a capability's bundle drifting away from the installer it names.
//!
//! # Red runs, recorded
//!
//! Each was performed on 2026-08-13, observed to fail, and reverted. Red runs
//! 1–3 (the closed type) are recorded in `blue_lang_waku::capability` and 4–5
//! (the derivation) in `blue_lang_waku::imports`.
//!
//! 6. **A sys name with no capability.** Deleting `"cwd"` from
//!    `FILESYSTEM_NAMES` failed
//!    `every_sys_name_is_claimed_by_exactly_one_host_capability` with
//!    `sys installs names no capability grants: ["cwd"]` (2 tests red).
//! 7. **A host name filed as pure.** Moving `"read_file"` from
//!    `FILESYSTEM_NAMES` into `COLLECTION_NAMES` failed
//!    `no_pure_capability_grants_a_host_name` with ``collections grants
//!    `read_file`, which the sys layer installs — a frame could name a host
//!    effect and derive no import for it`` (3 tests red). **This is the
//!    load-bearing red run**: the mutation is semantically meaningful — it
//!    genuinely creates a host effect reachable through a frame that derives
//!    zero imports — rather than a rename the gate cannot see.
//! 8. **The probe itself is not vacuous.** Removing the `install_sys_stdlib`
//!    call from `sys_installed_names` failed `sys_installs_a_measurable_surface`
//!    with `the sys layer installed 0 names; the floor is 37`, which is what
//!    stops every "for every sys name…" assertion below from passing over an
//!    empty set.
//! 9. **A bundle naming something the runtime does not install.** Adding
//!    `"monotonic_now"` to `CLOCK_NAMES` failed
//!    `every_host_capability_name_is_installed_by_the_sys_layer` with
//!    ``clock grants `monotonic_now`, which the sys layer does not install``
//!    — the direction red run 6 cannot reach, recorded separately because one
//!    mutation proving one direction says nothing about the other.

use std::collections::BTreeSet;

use blue_lang_waku::Capability;
use tatara_lisp_eval::Interpreter;

/// Every head name the host layer adds to an interpreter — **measured, by
/// installing it and diffing.**
///
/// `Interpreter::new()` is deliberately bare: no stdlib, no blue layers. The
/// difference is therefore exactly `install_sys_stdlib`'s contribution and
/// nothing else, which is what makes it independent evidence rather than a
/// restatement of a list.
fn sys_installed_names() -> BTreeSet<String> {
    let mut interp: Interpreter<()> = Interpreter::new();
    let before: BTreeSet<String> = interp
        .reserved_head_names()
        .iter()
        .map(|n| n.to_string())
        .collect();
    blue_lang_runtime::sys::install_sys_stdlib(&mut interp);
    let after: BTreeSet<String> = interp
        .reserved_head_names()
        .iter()
        .map(|n| n.to_string())
        .collect();
    after.difference(&before).cloned().collect()
}

/// Anti-vacuity, with the floor and the date: the host layer installs at least
/// 37 names as of 2026-08-13 (6 process, 20 filesystem, 4 environment,
/// 7 clock). Every gate below quantifies over this set.
#[test]
fn sys_installs_a_measurable_surface() {
    let names = sys_installed_names();
    assert!(
        names.len() >= 37,
        "the sys layer installed {} names; the floor is 37 (measured 2026-08-13)",
        names.len()
    );
}

/// **Every host primitive is claimed by exactly one host capability.**
///
/// The completeness direction: a sys name no capability grants is a name no
/// frame can permit, so a program calling it escapes its frame on a call the
/// runtime is perfectly willing to make.
#[test]
fn every_sys_name_is_claimed_by_exactly_one_host_capability() {
    let installed = sys_installed_names();
    let hosts = Capability::host_effects();

    let unclaimed: Vec<&String> = installed
        .iter()
        .filter(|n| !hosts.iter().any(|c| c.grants(n)))
        .collect();
    assert!(
        unclaimed.is_empty(),
        "sys installs names no capability grants: {unclaimed:?}"
    );

    let doubly_claimed: Vec<&String> = installed
        .iter()
        .filter(|n| hosts.iter().filter(|c| c.grants(n)).count() > 1)
        .collect();
    assert!(
        doubly_claimed.is_empty(),
        "these names are granted by more than one host capability: {doubly_claimed:?}"
    );
}

/// **And every name a host capability grants is one the sys layer installs.**
///
/// The soundness direction. A bundle that named something the runtime does not
/// install would let a frame grant a capability that opens an import for a
/// function nobody can call — an import with no callee is exactly the kind of
/// stub `BLUE-EXECUTION.md` §0 says must not exist.
#[test]
fn every_host_capability_name_is_installed_by_the_sys_layer() {
    let installed = sys_installed_names();
    for c in Capability::host_effects() {
        for name in c.names() {
            assert!(
                installed.contains(name),
                "{} grants `{name}`, which the sys layer does not install",
                c.label()
            );
        }
    }
}

/// **No PURE capability grants a host name.**
///
/// The one that matters most. A pure bundle derives no import, so a host name
/// filed under one would be nameable inside a module whose import table is
/// empty — the design's central claim, inverted.
#[test]
fn no_pure_capability_grants_a_host_name() {
    let installed = sys_installed_names();
    for c in Capability::ALL {
        if c.is_host_effect() {
            continue;
        }
        for name in c.names() {
            assert!(
                !installed.contains(name),
                "{} grants `{name}`, which the sys layer installs — a frame could name a \
                 host effect and derive no import for it",
                c.label()
            );
        }
    }
}

/// Every host capability's bundle is non-empty and its import is distinct.
///
/// Anti-vacuity for the two direction gates: both quantify over
/// `c.names()`, and both pass trivially over a bundle that grants nothing.
#[test]
fn each_host_capability_carries_a_real_bundle_and_a_real_import() {
    let counts: Vec<(&str, usize)> = Capability::host_effects()
        .into_iter()
        .map(|c| (c.label(), c.names().len()))
        .collect();
    assert_eq!(counts.len(), 4, "the floor, 2026-08-13: {counts:?}");
    for (label, n) in &counts {
        assert!(*n > 0, "{label} grants no names");
    }
    // The measured shape of `blue_lang_runtime::sys`'s four installers on
    // 2026-08-13. A change to the runtime moves these, and moving them is a
    // decision rather than a slip.
    assert_eq!(
        counts,
        vec![
            ("process", 6),
            ("filesystem", 20),
            ("environment", 4),
            ("clock", 7)
        ]
    );
}

/// **`interpreter_hostless` is not hostless when the `sys` feature is on.**
///
/// Recorded as a measurement rather than left as a surprise. It forks a base
/// built by `interpreter(&mut ())`, and `interpreter` installs the sys layer
/// under `#[cfg(feature = "sys")]` — so in any build that turns the feature on
/// (this crate's, and every `cargo test --workspace` run through cargo's
/// feature unification) the "hostless" interpreter binds all 37 host
/// primitives.
///
/// Two documents credited the opposite. `blue-lang-pkg`'s `bluefile` module said
/// the manifest interpreter was *"safe by absence of a binding"*; it is safe by
/// the `check_reach` frame, which is a much narrower claim and the only true
/// one. This test is what makes the correction a measurement.
///
/// It asserts the CURRENT behaviour, so that changing it is a deliberate act
/// that fails here and gets a decision, rather than a quiet fix that leaves two
/// modules' docs describing different runtimes.
#[test]
fn interpreter_hostless_binds_the_host_layer_when_sys_is_enabled() {
    let interp = blue_lang_runtime::interpreter_hostless();
    let bound: Vec<&str> = ["read_file", "rm_rf", "exec_capture", "getenv", "now"]
        .into_iter()
        .filter(|n| interp.resolve_head(n).is_some())
        .collect();
    assert_eq!(
        bound.len(),
        5,
        "with `sys` on, `interpreter_hostless` binds the host layer; it bound {bound:?}"
    );
}
