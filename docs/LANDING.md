---
kind: explanation
summary: "how a change reaches main fast without losing a test: batched lands, releases beside main, settled locks, tests skipped only by identity, suites run on runners (design, 2026-11-10)"
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
| L2 | **Releases beside main.** The release takes its version from tags and writes the bumped `Cargo.toml`, `Cargo.lock` and `Cargo.gen.lock` in a detached commit beside main, reachable only by its tag `vX.Y.Z`, and publishes from that tag. Main never receives a release commit, so `release_hold` in `gen/land.b` is off for a repository whose auto-release runs in tag mode. | substrate `rust-auto-release.yml` (a new input, off by default for the fleet, on for blue), blue `auto-release.yml` | the same: the published crates and the tag are built from the same tree |
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

## 5. Hardening after four parallel lands (2026-11-12)

| Receipt (measured 2026-11-11/12) | Change |
|---|---|
| R1: four lands (h7, h8, h9, h10) cancelled each other's runs for about two hours and main never moved: a `--watch` run again composed and pushed `land/batch-h7/speed` again (runs 43139583615 to 43150756893, four cancelled), and one land built batches under another branch's name | One land per branch: a `--watch` land takes a lock, `held/` beside its log, that only one `mkdir` makes, naming its pid. A second `--watch` of the branch attaches: it prints the first land's log as it grows and ends with its code and reason, and it pushes nothing. A land without `--watch` refuses while one holds the branch. A lock whose pid no longer runs is taken over. A land stops when its worktree's branch is no longer the one it holds (`moved_home`). `land.yml` no longer cancels a running run when its ref is pushed again: `cancel-in-progress` is on only when the repository variable `BLUE_LAND_CANCEL_IN_PROGRESS=on`. A land that joins while a batch runs waits in `wait_turn` and pushes nothing until the run ends. |
| R2: three lands wrote one shared `land.log` and overwrote each other; one land exited 1 with no word and left its ticket | Each land keeps its log and its exit record under the repository's common git directory, at `.git/land/<slug>/` (the slug its ticket carries); the land prints the path first. Every end goes through `quit(code, why)`: the reason reaches the terminal, the log and `exit`. A red run now ends "run N is red at JOB" (`end_reason`), where it ended with a bare 1 before. A ticket with no heartbeat for 30 minutes and no live run that stands for it (`stale_tickets`) is reaped by the next land that waits, which says so. A land following its own run beats, so its ticket stays alive. A verdict whose ticket is gone (`stale_verdicts`) has no reader, since a land reads its verdict only beside its ticket; the next land that waits reaps it too (six stayed behind on 2026-11-11/12). |
| R3: reds came about 25 minutes into a run: reuse-ratchet at 26.4 min (run 43143400946), the `land` check at 23.3 min (run 43147715519), each late in a flake-check shard | A `first-gates` job in `ci.yml` runs beside the suite as soon as blue is built: the prose gates and the census ratchets (`gen/prepush.b --first-gates`). A red one stops the run through stop-on-red. It does not gate the suite, so a green land takes no longer. Off: `BLUE_LAND_FIRST_GATES=off`. `cargo fmt` stays the first step of the cargo-test job. |

`BLUE_LAND_POLL_SECONDS` sets how often a land polls (default 60); the fixture tests run at 1.

## 6. Tier ledger

| Item | Tier |
|---|---|
| L2 | live (2c3ea8b0, `release-ref-mode: tag`): v0.0.193 is tagged at cafef4c8, a commit beside main that main does not contain; main's `[workspace.package].version` stays 0.0.192 and gained no release commit; crates.io serves 0.0.193. `gen/land.b` reads the workflow (`releases_beside_main?`) and turns `release_hold` off, so no land waits on a release run |
| L4, L5 | DESIGN |
| L1 | built 2026-11-10, no real batch run yet: `land_batch` in `gen/land.b`. A ticket now names its land's HEAD. The land at the front of the queue rebases main plus up to 7 lands queued after it into one tree, pushes it to `land/batch-<slug>`, and halves a red batch (`bisect`) until the breaking land is alone. A queued land reads its verdict from `land-verdict/<at>/<slug>`, and its `--watch` ends with it. Off: `--no-batch`, or the repository variable `BLUE_LAND_BATCH=off`: the turn refuses a batch, land.yml fails it at a step of its own, and the leader lands alone. Tested locally: pure tests of batch formation, halving and blame (8 mutants of `bisect`, `halves`, `batch_of`, `undecided` and `verdict_of` each turn a test red), and fixture tests with a fake `gh`: a green batch lands two lands in one run, a red batch lands its leader and blames the other with no run of its own, a blamed land's watch ends with the reason, `--no-batch` takes no one, the turn refuses a batch while off (8 driver mutants red, the land without batching among them). Only CI proves a batch run on real runners fast-forwarding main through several lands, the turn and absorb-release on a batch ref, and two real clients passing a verdict |
| L3 | built 2026-11-10: `catch_up` in `gen/land.b` settles each commit whose rebase stops only on the locks, and `--no-regen` keeps the old stop. Four fixture tests run a fake `gen` and `cargo` on `PATH`: two commits settled one by one, a conflicted `Cargo.lock`, a lock that fails `--locked`, and a lock beside a source conflict. The first three went red on the old refusal, then green; the fourth guards the stop that stays. Dropping the `--locked` check or the `--no-regen` guard turns them red. No test runs the real `gen build .` on blue's workspace; the first land that settles on a real release is the proof |
| a batch holds every land it names | built 2026-11-11: run 43028336649 on `land/batch-service/component-bidamas` was green and held none of that land's commits. Its leader had been blamed alone, and the back half of the batch ran under the leader's name. The worktree reflog also shows a later compose for the same land that held none of its commits, because another git had moved that worktree's HEAD. Now, before any suite runs, `try_batch` proves that the tree holds each land: each own commit reaches the tree by patch-id (`git cherry`) or by its rebased identity (author, author time, subject). A land that the tree does not hold leaves the batch. It gets a `land-alone/<at>/<slug>` notice beside its ticket, keeps its ticket and its place, and lands alone next. A batch ref takes the name of the first land it holds. Every exit that reports "landed" first proves that main holds the branch's commits; if not, it exits 1 and names the missing commits. A stale `index.lock` in the land's own worktree (older than the land, no process holding it) stops the land before it rebases and names the path. Five fixture tests: red on the old driver, green on the new one |
| stale queue ticket fix | live (80fbc8e3) |
| heni-gate rows | DESIGN |
| R2: a log and an exit record per land, a reason on every end, stale tickets reaped | built 2026-11-12 (§5). Fixture tests, red on the old driver, then green: two lands of two branches keep two logs; a red run ends "run 100 is red at ci / check / cargo-test" on the terminal, in the log and in `exit`; a ticket two hours old with no heartbeat is reaped with a message. The first real land after this commit is the live proof |
| R3: first gates beside the suite | built 2026-11-12 (§5): `first_gates` in `gen/prepush.b` (a test red when the ratchets leave the list), the `first-gates` job in `ci.yml`. Time to first red for a docs-only failure (a hand edit to the generated README, two dry lands pushed 20 s apart): 26.6 min on main's ci.yml (run 43186773560, flake-check 1/6) and 21.0 min with first-gates (run 43186819534, `generated-readme-fresh`); from the end of the blue job, 20.0 min and 12.0 min. The first-gates job itself took 11.7 min, so it is the next thing to make smaller |
| R1: one land per branch, attach, no cancel on a second push | built 2026-11-12 (§5). Fixture tests: a second `--watch` of a held branch attaches, pushes nothing and ends with the holder's code, and a plain land refuses (red on the old driver: it pushed `land/topic`); a dead holder's lock is taken over; `land.yml`'s `cancel-in-progress` reads `BLUE_LAND_CANCEL_IN_PROGRESS` (red on the old `true`); two lands that join during a running batch push nothing until it ends, cancel nothing, and form the next batch (green on the old driver too: `settle` already waited, so this test locks it). No real run has attached yet |
