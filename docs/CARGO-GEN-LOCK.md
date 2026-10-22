# `Cargo.gen.lock` is committed, and that is a trade

The rationale is recorded here because the artifact itself landed in `d917383`,
a commit about Japanese naming that says nothing about it — three concurrent
sessions were writing to this repo that night and one swept the other's staged
files into its own commit. A 5880-line generated file appearing with no
explanation is how the next author learns to distrust it.

**Why it exists.** Without a committed delta, substrate takes the IFD path and
says so on every evaluation — ten times in one `nix flake check`:

    trace: mkBuildSpec[IFD]: no committed Cargo.build-spec.json for
    /nix/store/…-source → eval-time `gen build` (network). Commit one for a
    deterministic no-IFD build.

That runs `gen build` inside a `__noChroot` sandbox *during eval* — network,
variable latency, and a derivation whose `.drv` exists only because eval put it
there. When that `.drv` is not valid in the store at build time the check dies
with `path '…-cargo-build-spec-ifd.drv' is not valid`. **That failure is
store-state dependent, not a property of this source** — on a warm store where
the IFD `.drv` is still valid the same tree checks green, which it did here
before the fix. Do not read one green run as evidence the path is sound.

Measured with a control, same eval, one file moved: delta absent → 1 trace,
delta present → 0.

**Why the delta and not `Cargo.build-spec.json`.** substrate's
`reusable-gen-spec.yml` states the doctrine — "the committed artifact is the
slim `Cargo.gen.lock` … a gitignored `Cargo.build-spec.json` intermediate" —
and `lockfile-builder` reads the delta *first*, reconstructing the graph in
pure Nix. 197 KB against 417 KB, and committing both would be two derived
files that can disagree.

**The cost, and what pays it.** A checked-in derived file can go stale: land a
`cargo update` without re-running `gen build` and substrate reconstructs the
build graph from a delta describing a dependency set the lock no longer has.
Two things hold it, neither of which existed before:

- **`checks.gen-confirm`** — already emitted by substrate's tool-release and
  until now passing over nothing. Its `gen confirm . --if-present` *tolerates*
  a repo with no delta; blue had none, so the check was green having verified
  nothing. With the delta committed it recomputes `sha256(Cargo.lock)` offline
  and compares it to the recorded `cargo_lock_sha256`. Red run: that field
  zeroed by hand → `{"status":"stale"}`, exit 1; restored → `{"status":"fresh"}`,
  14 manifests verified, exit 0.
- **`.github/workflows/gen-spec.yml`** — the regen. On main `gen build . --commit`
  is a no-op when fresh; on a PR it regenerates without committing and fails if
  the result differs.

**Honest tier: eval- and CI-caught, not unrepresentable.** Nothing stops a
stale delta being committed locally; it cannot pass `nix flake check`.

**Generate the delta AFTER any lock work, never before.** `gen build` rewrites
`Cargo.gen.lock` from whatever `Cargo.lock` it finds, so generating against a
stale lock ties the delta to bytes about to change — and it can quietly revert
an in-flight `Cargo.lock` edit. Verify the tie afterwards by comparing
`shasum -a 256 Cargo.lock` against the delta's `cargo_lock_sha256`; a tie that
reports fresh against a lock you never checked is the trap.
