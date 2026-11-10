---
kind: explanation
summary: how a change reaches main fast without losing a test: batched lands, releases beside main, settled locks, tests skipped only by identity, suites run on runners (design, 2026-11-10)
---

# LANDING: faster to main, with every test still meaning what it meant

Status: DESIGN, 2026-11-10. Owner of the design: this file. `gen/land.b`
and `.github/workflows/land.yml` are the code it changes; `docs/TESTING.md`
owns what the suite contains. The tier ledger at the end is the only place
a status is claimed.

Operator, 2026-11-10: *"from everything we have experienced is there any
way we can speed up this pipeline while maintaining quality"*, then, to the
five changes below: *"I agree with all these, let's cash in on all their
benefits."*

## 1. Receipts (measured 2026-11-10)

| Receipt | Cost |
|---|---|
| one land reaches main at a time, at 30 to 60 minutes of CI each, with about six sessions landing | a branch waited hours in the queue |
| every `release: workspace v0.0.N` commit on main rewrites `Cargo.toml`, `Cargo.lock` and about 340 lines of `Cargo.gen.lock` | every branch that touches a lock conflicts on rebase; a land waited 24 minutes on one release run |
| `git land` refused five rebases in one day with "Cargo.gen.lock conflict beyond what regenerating can settle"; each was settled by hand with the same three commands | a human or an agent in the loop for a mechanical step |
| every land reruns the whole workspace (2,383 tests) and every `gen/*.b` test, even for a change to one crate | CI time spent re-proving what did not change |
| four agents ran full suites on cid (10 cores) at once: load 24, the build budget at 0, every agent queued for an hour, two agents stopped mid-work | local suites competed with each other and with CI's own run of the same suite |

## 2. Destination

A change reaches main in the time its own tests take, not the time the
queue takes. Every test that runs means what it meant before; a test is
skipped only when its exact identity already passed. Nothing about the
release history, the locks or the queue needs a human.

## 3. The five changes

| # | Change | Where | Quality |
|---|---|---|---|
| L1 | **Batched lands.** When several lands are queued, the turn tests them together: main plus each queued branch in queue order, as one tree. Green: main fast-forwards through all of them. Red: the batch splits in halves and each half is tested, until the breaking branch is alone and returned to its owner. | `gen/land.b`, `land.yml` | the same or stronger: branches are tested as they will run together |
| L2 | **Releases beside main.** The release takes its version from tags and writes the bumped `Cargo.toml`, `Cargo.lock` and `Cargo.gen.lock` on a release ref (`release/vX.Y.Z`), tags it and publishes from it. Main never receives a release commit. | substrate `rust-auto-release.yml` (a new input, off by default for the fleet, on for blue), blue `auto-release.yml` | the same: the published crates and the tag are built from the same tree |
| L3 | **Locks settle themselves.** When a land's rebase stops only on `Cargo.gen.lock` (and `Cargo.lock`), land takes main's `Cargo.gen.lock`, runs `gen build .`, checks `cargo metadata --locked`, and continues. Any other conflict still stops. | `gen/land.b` | the same: it is the exact command a person ran, checked by the same sha tie |
| L4 | **Tests skipped only by identity.** CI keeps blue's test store (H3 rung 3: a test is keyed by the b3 identity of the test and everything it reaches) across runs; a test whose identity already passed is reported cached, never re-run. Cargo tests run for the crates the change touches and the crates that depend on them, sharded across runners; the full suite runs post-merge and nightly. | `ci.yml`, `land.yml`, `post-merge.yml` | the same: a skip needs an identical identity, and the full suite still runs on main |
| L5 | **Suites run on runners, not laptops.** An agent or a person verifies with `git land --dry` (CI runs the suite on runners and reports) and runs locally only the tests of what they changed. | agent briefs, `CLAUDE.md`, the `fan-out` skill | the same suite, run once in the place built for it |

Two fixes ride along: the land queue never waits on a stale ticket (a land
that ends removes its ticket, landed 2026-11-10), and `gen/heni-gate.b`
returns to green by recording the packages it has no row for, so a red gate
means something again.

## 4. Order

L3 and L5 first (small, and they remove the manual stops today); L2 next
(it removes the cause of most lock conflicts); L1 (the largest gain); L4
(needs the shared test store wired into CI).

## 5. Tier ledger

| Item | Tier |
|---|---|
| L1, L2, L4, L5 | DESIGN |
| L3 | built 2026-11-10: `catch_up` in `gen/land.b` settles each commit whose rebase stops only on the locks, and `--no-regen` keeps the old stop. Four fixture tests run a fake `gen` and `cargo` on `PATH`: two commits settled one by one, a conflicted `Cargo.lock`, a lock that fails `--locked`, and a lock beside a source conflict. The first three went red on the old refusal, then green; the fourth guards the stop that stays. Dropping the `--locked` check or the `--no-regen` guard turns them red. No test runs the real `gen build .` on blue's workspace; the first land that settles on a real release is the proof |
| stale queue ticket fix | live (80fbc8e3) |
| heni-gate rows | DESIGN |
