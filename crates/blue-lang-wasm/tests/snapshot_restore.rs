//! **A blue instance's linear memory round-trips as bytes.**
//!
//! `in_engine.rs` establishes that blue *runs* as wasm. This establishes the
//! consequence: because the interpreter runs inside the instance, everything it
//! allocates is in that instance's linear memory, and linear memory is bytes
//! the host can copy out and write back into a different instance.
//!
//! **Why that is not obvious, and why the test is worth its weight.** The
//! standing objection to snapshotting a blue value is that blue's values are
//! `Arc`-based (`BLUE-MEMORY.md` §I.1) and a refcount is meaningless outside
//! the process that owns it. Compiled to wasm the objection dissolves: the
//! `Arc`s, their refcounts and the whole allocator arena are *in the snapshot*,
//! internally consistent with each other, because the snapshot is the entire
//! heap and not a serialisation of one value out of it. This test does not
//! argue that — it moves the bytes and then asks the restored instance what it
//! observes.
//!
//! **The three limits, stated with the claim rather than after it:**
//!
//! 1. **Quiescent only.** A wasm call stack is engine-internal — locals, the
//!    operand stack and return addresses are not in linear memory. A snapshot
//!    taken mid-call has no stack to resume into. This captures between calls.
//! 2. **Not an actor.** `blue_eval` builds a fresh interpreter per call, so a
//!    blue binding does not survive its own call, let alone a snapshot.
//!    Measured 2026-08-13: `x = 41` then `x + 1` reports ``unbound symbol
//!    `x` ``. What round-trips here is what the shipped ABI genuinely keeps —
//!    a blue program's error value and a host-owned heap region.
//! 3. **Nothing outside linear memory is carried, and nothing needs to be.**
//!    The module imports zero functions (`in_engine.rs` pins `imports: 0`), so
//!    there is no host handle, descriptor or external reference to miss. Its
//!    one mutable global is LLVM's unexported shadow-stack pointer, which at
//!    quiescence holds its initial value in every instance; its table is
//!    written once from an elem segment at instantiation, identically in
//!    every instance. The empirical check on all of that is the last case in
//!    the driver: the restored instance still runs a blue program correctly.

use std::path::PathBuf;
use std::process::Command;

mod harness;
use harness::build_wasm;

/// Read one `key: value` line out of the driver's output.
fn reported<'a>(stdout: &'a str, key: &str) -> &'a str {
    stdout
        .lines()
        .find_map(|l| l.strip_prefix(key))
        .unwrap_or_else(|| panic!("the driver must report `{key}`:\n{stdout}"))
        .trim()
}

/// **Capture the whole linear memory, restore it into a fresh instance, and
/// the fresh instance observes the first one's state.**
///
/// The load-bearing case is inside the driver and is the differential:
/// restoring a *different* snapshot must produce a *different* observation.
/// Without it this test is satisfied by an implementation that never restored
/// anything and simply re-derived the expected value — which is precisely the
/// failure mode a round-trip test invites. Both red runs are recorded in
/// `host/snapshot.mjs` above that case; the one that matters is red run 2,
/// where a `restore` that writes a constant passes every other check in the
/// file and is caught only there.
#[test]
fn a_blue_instances_linear_memory_round_trips_through_a_fresh_instance() {
    let wasm = build_wasm();
    let driver = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("host/snapshot.mjs");

    let out = Command::new("node")
        .arg(&driver)
        .arg(&wasm)
        .output()
        .expect("spawn node — the engine under test");

    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        out.status.success(),
        "every snapshot case must pass:\nstdout:\n{stdout}\nstderr:\n{stderr}"
    );
    assert!(
        stdout.contains("ALL SNAPSHOT CASES PASSED"),
        "every snapshot case must pass: {stdout}"
    );

    // The measurement is part of the finding, not decoration: a snapshot is
    // the *whole* heap, so its cost is set by the heap's size and not by how
    // much blue state is in it. Asserted rather than merely printed so the
    // numbers cannot silently become nonsense — a zero-byte snapshot would
    // round-trip perfectly and mean nothing.
    let bytes: usize = reported(&stdout, "snapshot-bytes:")
        .parse()
        .expect("a byte count");
    let pages: usize = reported(&stdout, "snapshot-pages:")
        .parse()
        .expect("a page count");
    assert_eq!(bytes, pages * 65_536, "a snapshot is whole pages: {stdout}");
    assert!(
        pages > 19,
        "the snapshot must be a grown heap, not a fresh one: {stdout}"
    );

    for key in ["capture-us-median:", "restore-us-median:"] {
        let us: f64 = reported(&stdout, key).parse().expect("microseconds");
        assert!(us > 0.0, "{key} must be measured, not asserted: {stdout}");
    }
}
