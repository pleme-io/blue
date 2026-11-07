---
kind: explanation
summary: the long plan for blue, ten horizons from hygiene to a language that proves, replays and explains itself; destination first, each horizon with its first step, its gate and what it unlocks
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
  make its caught ratio a ratchet per package, so a test that cannot say no
  is visible.
- **Laws as theorems for a decidable fragment.** okite's laws and integer
  ranges checked by a solver for linear integer arithmetic and list lengths,
  behind one seam (CONTAIN THE C), the rest staying tested laws. A law the
  solver proves carries that tier; one it cannot stays tested.

**First step:** heni's caught ratio as a ratchet per package
(`bidamas/heni/ratio.baseline`, held by the `heni-mutations` check).
**Gate:** a mutant that survives makes its package's ratio fall, and the
check names the package and its survivors.

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

## Order

| When | Horizons | Why first |
|---|---|---|
| Now | H0; H1 (unions, patterns, `?`); H3 (the test cache) | H0 makes the ledger true; H1 completes the data model every later horizon names; H3 makes every later change cheaper to verify |
| Next | H2; H4 (async A1); H5 (arika Phase 2); H6 (heni's ratio as a ratchet) | each builds on H1's shapes or H3's identities |
| Later | H7; H8; H9; H10 | each multiplies what the earlier horizons made true |

## What this plan refuses

- A feature without a gate. Every first step above names the red run that
  proves it.
- A second language for a placement. A placement blue cannot reach is a rung
  to build, not a reason to write TypeScript, nix or Rust beside it.
- A global switch to settle a conflict between two good ideals. That is a
  blueshift position (`theory/BLUE-GAPS.md`, the rule at its head).
