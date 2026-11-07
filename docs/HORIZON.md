---
kind: explanation
summary: the long plan for blue, ten horizons from hygiene to a language that proves, replays and explains itself, and eight authority horizons that make every host effect a capability granted from one declaration in every placement; destination first, each horizon with its first step, its gate and what it unlocks
---

# HORIZON: where blue goes next

**Tier: DESIGN (2026-11-06, blue `cc9a1a1e`, release v0.0.155).** Nothing in
this document is built unless a line says so. A horizon becomes a
[`ROADMAP.md`](ROADMAP.md) row when its first phase starts; this document holds
the destination, the ROADMAP holds the work.

## The destination

Blue is the one language a person and a model write together for everything
pleme-io runs, and the language that knows itself. Every word can be found
before it is written again. Every claim a program makes is a gate that can go
red. Every program runs where its placement says, from a kernel probe to a
browser, without a second language. Every bad state is refused at the earliest
stage that can see it, and where two good ideals conflict, a program chooses a
position on the blueshift instead of forking the language.

## Where blue stands (measured 2026-11-06)

| Fact | Value |
|---|---|
| Crates | 24, all with description and license |
| Bidamas | 65, about 180,000 lines of blue |
| Conformance | `spec/rows/`, 37 files, run on five columns (tree-walker, VM, wasm ABI, the `blue` binary, the in-process front end) |
| Safety matrix | 19 rows: 6 sealed, 10 partly, 3 open ([`SAFETY.md`](SAFETY.md)) |
| Gap ledger | of 16 pass-1 gaps: 7 closed, 7 partial, 2 not re-measured (`theory/BLUE-GAPS.md`, status pass) |
| Identity | `def_hash` per definition, docs hashed in (`blue-lang-runtime/src/def_hash.rs`) |
| Concurrency | OTP-style processes in every door (`blue-lang-proc`) |
| Reach | CLI, services as wasm components, kernel BPF (`kaaneru`), word search (`arika`) |

## The ten horizons

Each horizon names its idea, why it compounds, its first step and the gate that
proves that step. "Unlocks" names the horizons that wait on it.

### H0. Hygiene: the base the rest stands on

The 2026-11-06 survey found the drift that hand-kept tables always gather.

- Render the `docs/DIAGNOSTICS.md` codes table from `RULES` in `nix run .#regen`,
  as `docs/REFERENCE.md` already is. Twice in one day a new rule code missed it
  (B0079, B0080); a rendered table makes that unrepresentable.
- Render CATALOG's `needs` column from `Bluefile.lock`, the truth B0019 keeps,
  not from Bluefile text (19 packages wrong today).
- Ship nested levels in the `blue-lang-pkg` crate (`bidamas/**/*.b`); today the
  published crate drops all 47 level files.
- B0058 to 0 (four bidama moduledocs lack an example), then B0056 and B0057
  down by the largest packages first (isshou, toriyose, eigyou, kakehashi).
- A ROADMAP row for every doc with open phases (HTTP2, CLI-TUI, SERVICE-DATA,
  API-EVOLUTION, BUILD-STACK, BUILD-ASSURANCE, DOCUMENTATION, OPERATORS,
  KERNEL, BIDAMA-COHESION).

**Gate:** each table is generated and `-fresh` checked; the census ratchets fall.
**Unlocks:** every horizon, because a plan built on a wrong ledger is wrong.

### H1. Shapes: sums, patterns and refusals that flow

`record` gave blue products. The next forms complete the data model:

- **Unions.** `union shape = circle(r: Float) | rect(w: Float, h: Float)`: each
  arm a record, the union a closed set. `case` over a union is checked for
  exhaustiveness, which seals SAFETY row 3 ("case falls through to nil").
- **Patterns.** `case` destructures: `when rect(w, h)`, `when [x, *rest]`,
  `when {name:}`; a binding destructures: `[a, b] = pair`. Closes gap G13.
- **Refusals that flow.** On top of guard `return`: `s = read(cs)?` returns a
  refusal from the function at once, lowered to a guard, so khipu's `then`
  disappears. With unions, `ok`/`no` become one declared `result` union, and
  ABSENCE's Option is a union too: one mechanism instead of three conventions.

**First step:** `union` as a declaration that lowers like `record`, with a
check-stage rule for a `case` that misses an arm.
**Gate:** a conformance row per arm shape; the exhaustiveness rule's red run
(drop an arm, the rule fires).
**Unlocks:** H2 (types have shapes to name), ABSENCE P1, SAFETY rows 1 and 3.

### H2. Types that grow with the program

Blue's ladder stays: an unannotated program pays nothing. What grows is how
far a type reaches once it is written.

- Local inference inside a typed definition, so one annotation types its body.
- Record and union types in signatures, and parameters over them
  (`List(T)` today, `Map(K, V)` and user records next).
- The checked boundary (gap G8): an untyped caller of a typed function is
  checked at the call where the value is known, not only inside the callee.
- A per-file or per-bidama position on the blueshift (`strict`), so a
  foundation package can demand types and a script cannot be made to.

**First step:** inference of local bindings from typed parameters and literals.
**Gate:** a spec row per inference rule; the corpus check stays clean at the
`dynamic` rung (no program that runs today is refused).

### H3. Code is content: the definition hash as identity

Blue already hashes every definition. Make that hash the identity everything
keys on:

- **A test cache keyed on hashes.** A test whose target and controls hash the
  same as a passing run does not run again. The cache lives in sui, so a test
  passed on rio is passed on every node. CI time falls with every unchanged
  definition.
- **Incremental check.** The check stage keys its work on `def_hash`; editing
  one definition re-checks its callers only.
- **Semantic diff and release.** `danpen-diff` and API-EVOLUTION read change as
  "these hashes moved", so a release names exactly the definitions it changes
  and a doc-only edit is visibly one.
- **Memo by default for pure definitions** (`BLUE_MEMO` exists): a pure
  definition's result is a function of its hash and its arguments.

**First step:** `blue test` records each passing test's identity
(`test_identities` exists) and skips a test whose identity is recorded.
**Gate:** red run: change a callee, and its tests run again; change an
unrelated definition, and they do not.
**Unlocks:** H7 (memo and caching are performance), H9 (cheap re-verification).

### H4. Time: async, replay and a debugger that goes backwards

- **Async**, as designed in [`ASYNC.md`](ASYNC.md): `net_wait` in the node
  loop, node-time timers, the virtual clock in `blue test`, structured
  concurrency under the `heikou` space, every scheduler a blueshift position.
- **Replay.** Processes already write receipts. With the virtual clock, a run
  is a function of its inputs and its receipts: `blue replay <receipt>`
  re-runs a production failure on a laptop, bit for bit.
- **A debugger over replay.** A DAP server where stepping backwards is
  re-running to a point, not undoing; breakpoints on a definition's hash.

**First step:** ASYNC A1.
**Gate:** the async conformance set green at `schedulers(1)` and
`schedulers(n)`; a replayed run's receipt equals the original's.

### H5. Knowledge: the corpus as a graph you can ask

- **arika Phases 2-5** ([`ARIKA.md`](ARIKA.md)): the snapshot, the MCP service
  (`blue_word_*`), full-text through codesearch.
- **khipu over blue itself** ([`KHIPU.md`](KHIPU.md)): every definition, test,
  doc, rule, receipt and commit (read through `utsushi`) as quads, so a
  question like "which definitions reach the network and have no test?" is one
  query, and so is "what changed in the words kaaneru uses since v0.0.150?".
- **Why-answers.** A diagnostic links to its rule, its law, its witness and the
  commit that introduced it, all from the graph.

**First step:** arika Phase 2, `blue arika emit` and `SNAPSHOT.json`.
**Gate:** arika G1-G9; khipu's W3C suites against Oxigraph.

### H6. Proof: claims that cannot round up

- **Properties from what a definition already says.** A doc example is a
  point; with H2's types, blue generates the neighbourhood around it
  (property tests from signatures and examples), seeded and replayable.
- **Mutation testing as a ratchet everywhere.** `heni` runs per bidama today;
  make its caught ratio a census row per package, so a test that cannot say no
  is visible.
- **Laws as theorems for a decidable fragment.** okite's laws and integer
  ranges checked by a solver for linear integer arithmetic and list lengths,
  behind one seam (CONTAIN THE C), the rest staying tested laws. A law the
  solver proves carries that tier; one it cannot stays tested.

**First step:** heni's caught ratio in the census.
**Gate:** a mutant that survives turns its package's row red.

### H7. Speed with receipts

- The bytecode VM as the default door where the conformance columns agree.
- Ahead-of-time compilation of a hot bidama to wasm, run by the same component
  host services use.
- Performance as a ratchet: `blue bench` results recorded per release, a slower
  release refused unless it carries a typed reason ([`PERFORMANCE.md`](PERFORMANCE.md)).

**First step:** a bench row set in CI with a recorded baseline.
**Gate:** red run: a deliberately slower build fails the ratchet.

### H8. Reach: one program, every placement

`fueki` renders one program by placement. Extend the placements:

- **Browser.** Frontends in blue (`theory/BLUE-FRONTEND.md`), the engine as a
  wasm component in the page.
- **Kernel.** `kaaneru` compiles blue to BPF; more program kinds, and a
  verifier report that names the blue line.
- **Nix.** Blue as the source of nix configuration (`kakehashi`): a node's
  configuration authored in blue, nix a rendering, so no hand-written nix
  remains in a blue project.
- **GPU (aspirational).** A restricted rung of blue lowered to compute shaders
  for data-parallel definitions.

**First step:** the frontend plan's first rendered page served by a blue service.
**Gate:** the same program, run through two placements, gives equal receipts.

### H9. Model-native: a language designed for the pair that writes it

- **A model eval suite as a ratchet.** Golden tasks a model must solve in blue
  (write a bidama word, fix a refusal, port a function), scored each release;
  a release that makes blue harder for models to write is visible.
- **Diagnostics as prompts.** Every rule carries a witness, a law and a fix;
  make each diagnostic's JSON a complete repair instruction, tested by the eval
  suite.
- **Naturalize as a tool.** `blue naturalize <crate|module>` scaffolds a
  bidama with a differential harness against the original, so porting a
  library is filling in rows until the harness agrees.
- **Context packs.** `blue context <word>` returns the word, its laws, its
  callers and its tests in one bounded answer (arika's facts).

**First step:** ten golden tasks and a scored run recorded per release.
**Gate:** the score is a census row; it may not fall without a typed reason.

### H10. Ecosystem: bidamas anyone can trust

- A registry of bidamas with quality signals computed, not claimed: docs
  coverage, tests, heni ratio, reach, conformance, model-eval score.
- Signed releases (`shomei`) and lock-verified loading (gap G10).

**First step:** the quality signals rendered per package in CATALOG.
**Gate:** each signal reproduces from the lock alone.

## Authority: one capability set, every placement (H11 to H18)

Added 2026-11-07 (blue `9ca7c2cc`, release v0.0.160), from two read-only
surveys of the language and of every placement. Every "built" below cites code.

**The destination.** Authority in blue is a capability, and a capability comes
from one place. A program, a bidama, a process and a service each hold only
what their declaration grants, narrowed from their caller and never widened.
One closed set, `blue_lang_waku::Capability`, names every host effect, and
every other list is a projection of it. One declaration renders the boundary
of every placement: the interpreter frame, the embedder posture, the wasm
imports and grant, the engenho native enclosure, the Kubernetes NetworkPolicy
and securityContext, the systemd sandbox, the image entrypoint and the browser
CSP. One gate proves that the placements agree. A program with no declaration
is pure. Ambient authority is a declaration (`allow(:all)`), visible and
counted, never a default.

World-facts that limit this destination: WASI has no subprocess; a dynamic
language cannot prove higher-order purity without an effect system (H14 builds
one); the kernel verifier and the browser origin are boundaries blue renders
to, not boundaries it replaces.

### Where authority stands (measured 2026-11-07)

| Fact | Value |
|---|---|
| Capability set | 6 pure and 14 host bundles, closed, no `Other` arm (`crates/blue-lang-waku/src/capability.rs:349-426`) |
| Lattice | `Reach` with meet and join; `narrow` is the only run-time move, there is no widen (`crates/blue-lang-waku/src/lib.rs:70-297`) |
| Lock check | `⋁ floors ⊑ allow ∨ provided`, per definition (`crates/blue-lang-pkg/src/capabilities.rs:862-1035`); runs only when the root declares `allow`, a provider or `bounds` (`:1097`) |
| Run-time hold | one frame for the whole interpreter; a breach is fatal, exit 77 (`crates/blue-lang-runtime/src/lib.rs:376-543`) |
| Default | ambient when nothing is declared: `blue run`, `load_hosted`, an embedder with no posture |
| Adoption | 1 of 88 Bluefiles declares `reach` (`bidamas/kaaneru`), 1 declares `allow` (`examples/docking`) |
| Service access | `Access`, with a second, 7-variant `Effect` enum (`crates/blue-lang-pkg/src/deploy/runtime.rs:8`) |
| Placements with a boundary derived from `access` | 1 of 14: the engenho wasm pod (`blue.pleme.io/access`, enforced by engenho's kidou) |
| Placements with no boundary | GitHub Actions `run.b`, the image entrypoint, `mkBlueApp` executables, the systemd and launchd trio |

### H11. One vocabulary

`access.effects` names 7 `Effect`s; the Bluefile's `allow` and `reach` name 14
`Capability`s, spelled differently (`kernel_bpf`, `kernel-bpf`). Nothing ties
a service's code to its `access`.

- `Effect` becomes a projection of `Capability`: a total, tested map, so a
  capability added to waku has a service spelling or the build fails.
- A service's code floor, which `blue lock` already derives, must fit under its
  `access.effects`.
- One spelling, read both ways by the parser, printed one way.

**First step:** `Effect` derived from `Capability` by an exhaustive map, and
`blue lock` refuses a service whose floor exceeds `access.effects`, naming the
definition.
**Gate:** red run: a service whose code calls `exec_into` without `:process`
in `access` fails the lock.
**Unlocks:** H12, H16.

### H12. Pure by default

Every door with no declaration is ambient today. The flip comes in rings, each
its own land. `allow(:all)` stays a legal declaration, so no behaviour is
deleted; it is configured, and the configuration is visible.

1. A census: every Bluefile and every action `run.b` in pleme-io declares
   `allow`; a check counts the undeclared ones, and the count only falls.
2. The lattice check runs on every lock, not only when the root declares.
3. Embedders: a `Load` with no posture is pure, and ambient is
   `posture(Capability::all())`. A posture refusal is fatal, as `blue run`'s
   breach is, unless the embedder declares it catchable.
4. `blue run` with no declaration grants nothing; `--allow all` and
   `allow(:all)` keep the old behaviour.

**First step:** rings 1 and 2.
**Gate:** red run: a project with no `allow`, whose bidama declares
`reach(%i[clock])` and calls `read_file`, fails `blue lock`.
**Unlocks:** H13.

### H13. Authority per bidama at run time

The run-time hold is one frame for the whole interpreter. A bidama gets every
capability the root grants, and code a dependency gained after locking is held
only by the root.

- Each package runs in its own frame: its declared `reach` met with its
  caller's hold.
- `process` implies every capability, since a subprocess can do anything; a
  grant of it reads as top.
- Program macros run in the macro-phase frame (today they expand under the
  run's hold; `theory/BLUE.md`, the 2026-08-01 macro-phase correction).
- A spawned process holds its spawner's frame or a narrower one.

**First step:** per-package frames through the scoped-provider path
(`crates/blue-lang-runtime/src/lib.rs:395-431`), and `process` implies all.
**Gate:** red run: under a root `allow(%i[filesystem clock])`, a bidama with
`reach(%i[clock])` that calls `read_file` is refused at run time.
**Unlocks:** H15.

### H14. The checker sees authority

Refusals come from the lock and the runtime, never from `blue check`, so an
editor sees none of them.

- Effect inference per definition in the check stage, from the free-name walk
  the lock uses, with an effect variable so `map(f, xs)` carries `f`'s
  effects.
- A `capability-escape` B-code at check time, with the path to the host word
  (gap G9's destination).
- ASYNC's `suspends` joins the same effect row.

**First step:** the B-code for first-order escapes, judged against the root
Bluefile's ceiling.
**Gate:** red run: `blue check` on a file that calls `now_ms` under
`allow([])` names the code and the line.

### H15. Capabilities as values

Authority today is "can name X". An object capability is a value: passed in,
narrowed and revoked.

- A grant is a value (`fs = grant(:filesystem, under: "/data")`), and the host
  word takes it.
- Attenuation: `fs.under("logs")`, `net.only("db:5432")` (per-peer egress
  inside the language), `clock.monotonic`.
- Revocation by the grant's maker; a use after revoke is a typed refusal.
- The ambient names stay as sugar over the root grant, configured off per
  project.
- New capabilities: `secret` (SAFETY row 14: opaque, redacted on print,
  refused on send), `stdout`, `gpu`. An embedder extension joins the closed
  set or is refused.

**First step:** the filesystem grant with `under`, and the `secret`
capability.
**Gate:** red run: a function given `fs.under("a")` cannot read `b/x`; a
printed secret shows `<secret>`.

### H16. One declaration, every placement

Only the engenho wasm pod turns `access` into a boundary today.

- haibi also renders `kakoi.pleme.io/access`, so a native-rung service gets
  its enclosure from the same declaration; one annotation read by both doors
  is the destination.
- A wasm component imports only what `access.effects` grants (SERVICE-ACCESS
  S3).
- The chart renders NetworkPolicy egress and ingress, read-only `reads`
  volumes and `automountServiceAccountToken` (A2).
- The trio renders systemd `IPAddressAllow`, `ReadOnlyPaths`,
  `NoNewPrivileges` and `SystemCallFilter` (A3).
- The image entrypoint and `mkBlueApp` executables run with `--allow` derived
  from `access`; a Rust host loads a service program under
  `posture(access.effects)` (A5).
- An action's `run.b` gets a Bluefile with `allow`.
- `frontend(...)` and `workload(...)` gain `access`; a frontend's CSP and
  `connect-src` render from it.
- Default egress: the code renders `[]`; SERVICE-ACCESS.md §3 says the
  declared bindings plus DNS. The doc's default is the destination.

**First step:** haibi renders the kakoi annotation, and the
`-component-serves` check's wasmtime flags derive from `access`.
**Gate:** red run: on engenho, a native pod of a service with `egress: []`
that opens a socket is refused.
**Unlocks:** H17.

### H17. Parity: the placements agree on authority

kakoi, kidou, the chart and the trio each keep their own effect table. Nothing
proves that one `access` allows and refuses the same effects in each.

- A capability conformance matrix, in the shape of `spec/rows`: per
  capability, a probe that succeeds when granted and is refused when withheld,
  on every placement column.
- kakoi and kidou read one effect table generated from waku.

H8 compares what a program computes across placements; H17 compares what it is
allowed to do.

**First step:** the matrix on three columns: `blue run`, the wasm component,
the engenho wasm pod.
**Gate:** red run: one column that allows a withheld capability turns the
matrix red.

### H18. Least privilege as a ratchet

The hold already counts calls per granted name
(`crates/blue-lang-runtime/src/lib.rs:440-475`).

- Each run's receipt records the capabilities it used.
- Declared minus used is a census row per package, and it only falls.
- `blue lock --tighten` writes the narrowest `reach` the code allows.

**First step:** used capabilities in the receipt, and the census row.
**Gate:** a capability declared and never used by the test suite appears in
the census, and the row may not rise.

## Order

| When | Horizons | Why first |
|---|---|---|
| Now | H0; H1 (unions, patterns, `?`); H3 (the test cache) | H0 makes the ledger true; H1 completes the data model every later horizon names; H3 makes every later change cheaper to verify |
| Next | H2; H4 (async A1); H5 (arika Phase 2); H6 (heni in the census) | each builds on H1's shapes or H3's identities |
| Later | H7; H8; H9; H10 | each multiplies what the earlier horizons made true |
| Authority, now | H11; H12 rings 1 and 2; H16's first step | one vocabulary first, so every later horizon names one set; the census measures the flip before it happens |
| Authority, next | H12 rings 3 and 4; H13; H17 | per-bidama frames and the parity matrix stand on one vocabulary |
| Authority, later | H14; H15; H18 | effect inference and capability values change the language surface; least privilege needs receipts from every placement |

## What this plan refuses

- A feature without a gate. Every first step above names the red run that
  proves it.
- A second language for a placement. A placement blue cannot reach is a rung
  to build, not a reason to write TypeScript, nix or Rust beside it.
- Ambient authority as a default. It stays legal as a declaration.
- A placement that configures its boundary by hand. Each boundary is rendered
  from the one declaration.
- A global switch to settle a conflict between two good ideals. That is a
  blueshift position (`theory/BLUE-GAPS.md`, the rule at its head).
