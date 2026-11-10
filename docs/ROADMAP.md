---
kind: reference
summary: the one blue roadmap, one row per track with its tier, next step and done gate, and every conflict ruled once
---

# blue roadmap

One row per track. Each row names its design doc, its tier, its next step, what
it depends on, and the gate that proves it done. Conflicts between tracks are
decided once, in § Rulings. The gap ledger (what is broken) is
`theory/BLUE-GAPS.md`; this file is the plan (what is built next, and why). The
`blue-roadmap` skill owns the procedure for adding and editing a row.

**Tier is read from main and CI, never from a report.** DESIGN: no code.
PARTIAL: some phases on main with green CI. SHIPPED: the done gate is green on
main. UNRECONCILED: the row is seeded, and its tier is not yet measured.

Seeded 2026-11-06 at blue `6434ce31`. The long plan these rows serve, ten
horizons from hygiene to replay and proof, is [`HORIZON.md`](HORIZON.md); a
horizon gets a row here when its first phase starts.

## Tracks

| Track | Design doc | Tier | Next step | Depends on | Done gate |
|---|---|---|---|---|---|
| **substrate**: blue as the one language of the whole stack | [`SUBSTRATE.md`](SUBSTRATE.md) | DESIGN (2026-11-09: no phase on main; ola-mundo's release pins its component closure on ryn, and whether it serves is unmeasured) | L1.1: probe ola-mundo's pod on ryn; an engenho e2e runs the real `blue-component.wasm` with a bundle and serves a request | placement parity (the component); engenho (`engenho-kube-codegen`, `BlueWorker`) | each phase of SUBSTRATE §9 green with its red run; L1.1: the e2e serves a request, and with the bundle path removed it fails with the named error, not a hang |
| **arika**: blue's word search | [`ARIKA.md`](ARIKA.md), `theory/ARIKA.md` | Phases 1 and 2 BUILT for blue's own tree (G1-G4, G6); Phase 3's CLI (`find` over `sakuin`, `get`, `uses`, `groups`, `changed`, `ask`) and the MCP door (`kyuuji` `mcp_*`, `blue arika serve`) BUILT in process (G5, G8; 2026-11-09); the rest DESIGN | Phase 3's rest (Parquet through kueri, T3, CATALOG.md from facts, G7); Phase 5's release on ryn and G9; Phase 2's open rows | namespaces (tree paths in IDs); verbs (the `sakuin` space for T5) | G1-G9 green on main; a session on ryn answers the golden set through `blue_word_*` |
| namespaces | [`NAMESPACES.md`](NAMESPACES.md), `theory/BLUE-NAMESPACES.md` | SHIPPED (reconciled 2026-11-06 at `cc9a1a1e`: `blue census` measures B0076, B0077 and B0078 at 0, ratchet 0; tree 10 landed) | close the flat-era `legacy_names` windows at each root's next minor | — | B0076-B0078 at error with corpus count 0 |
| absence | [`ABSENCE.md`](ABSENCE.md) | DESIGN (reconciled 2026-11-06: only P0, the document; no `umu`, no `absence.rs`, no `BLUE_ABSENCE`, B0054/B0055 reserved) | P1: `umu` and B0054/B0055 at audit | — | the doc's seal tier row |
| safety | [`SAFETY.md`](SAFETY.md) | PARTIAL (reconciled 2026-11-06: 19 rows, 6 sealed, 10 partly, 3 open; the blackhole is row 19) | rows 1, 3 and 14, the open ones | — | each SAFETY row at its stated seal tier |
| testing | [`TESTING.md`](TESTING.md) | UNRECONCILED | reconcile against the §16 tier ledger | — | the §16 ledger |
| registry | [`REGISTRY.md`](REGISTRY.md) | UNRECONCILED | reconcile against main; give the gate a way to fail | — | a registry check that exits non-zero on an absent pin (`blue registry status` reports and never fails, so it gates nothing) |
| blue on sui | `theory/BLUE-STRUCTURE.md` §5.3, `theory/SUI-FLIP.md` | UNRECONCILED | reconcile; mark §5.3 superseded (§ Rulings R1) | — | to be stated at reconcile |
| frontend | [`FRONTEND-PLAN.md`](FRONTEND-PLAN.md), `theory/BLUE-FRONTEND.md` | UNRECONCILED | reconcile against main | — | to be stated at reconcile |
| **placement parity** (HORIZON H8) | [`spec/README.md`](../spec/README.md) § The evaluators, `theory/FUEKI.md` | PARTIAL: the gate is built. The conformance `component` column runs every `prints` and `fails` row (180) in the wasm32-wasip2 engine component under wasmtime and compares it with `cli` (`blue run`): 167 agree, 13 pending, 5 of them on new placement gaps G20 (the component holds no execution bounds and its wasm stack ends before the call-depth budget), G21 (host errors carry the platform errno), G22 (a capability the placement lacks, `exec_into`, refuses in its own words), G23 (`nats_connect` panics for want of a pid) | the run receipt from the component, so the gate compares receipts and not only output; then close G20-G23; the frontend's first page as a declared `runtime: :wasm` service (`examples/13_web_site.b` already renders and serves it natively) | the component (`nix build .#blue-component`) | `checks.<system>.conformance` green with the column strict; red run: a component that prints one extra byte fails every `prints` row naming `stdout at byte N` |
| verbs | [`VERB-ROADMAP.md`](VERB-ROADMAP.md) | DESIGN (its own measured tier line, 2026-10-22) | reconcile | — | `blue verbs check` against its baseline |
| **khipu**: the knowledge graph (OxiRS naturalized) | [`KHIPU.md`](KHIPU.md) | K1a BUILT (`bidamas/khipu`: terms, N-Triples, N-Quads); K1b's store and basic graph patterns BUILT (DuckDB through `kueri`, NOT EXISTS, a row budget; blue ingested as quads, 2026-11-09); the rest DESIGN | K1b's rest: the W3C syntax suites against Oxigraph; then K2 | kueri; arika (shares the rule engine and snapshots) | the W3C suites of K1-K4 green as a differential against Oxigraph |
| **utsushi**: history projection (Josh naturalized) | [`UTSUSHI.md`](UTSUSHI.md) | U1 BUILT (`bidamas/utsushi`), U2-U6 DESIGN | U2: workspace entries refused one by one; `exclude`; views | gitto | `josh-filter` id parity on fixtures; the round-trip law green |
| **async**: native async, the `heikou` space | [`ASYNC.md`](ASYNC.md) | PARTIAL (processes built; A1 built: node-time timers, the context deadline, the virtual clock in `blue test`, and `net_wait` in the node loop over the `tcp_*` words, 2026-11-09; HORIZON H4 replay built: `blue run --record` and `blue replay <receipt>`, the replayed receipt equal to the original's; the H4 debugger built 2026-11-10: `blue debug`, a DAP server over a recorded run, call and return steps, step back by replay, breakpoints by name, `def_hash` or definition line) | a deadline narrowed inside a process; then A2; `schedulers(n)` (A6) | blue-lang-proc | the conformance set green at `schedulers(1)` and `schedulers(n)`, gates A-ontology to A-replay |
| **record**: a named structure in one line | `examples/17_records.b`, okite D0017 | SHIPPED (2026-11-06, blue `cc9a1a1e`) | — | — | `spec/rows/records.b` and okite's record laws green; B0079 at error |
| **guard return** | [`GUARD-RETURN.md`](GUARD-RETURN.md) | G1 BUILT (lowering, B0080, the formatter keeps the guard), G2 DESIGN | G2: the language server and the tree-sitter grammar know `return`; a `return` inside `rescue` | — | R-lower, R-refuse, R-total green (G1); editors highlight it (G2) |
| **proof** (HORIZON H6) | [`HORIZON.md`](HORIZON.md) §H6, [`TESTING.md`](TESTING.md) | PARTIAL (2026-11-09): heni's caught ratio a ratchet per package BUILT (`bidamas/heni/ratio.baseline`, `checks.heni-mutations`); generated properties BUILT (`blue_lang_check::properties`: `@doc` example calls of a typed definition, neighbours drawn by `ran`'s generator from `BLUE_PROPERTY_SEED`, held to the declared return type); laws over a decidable fragment DESIGN | record and named return types; drawn `List` and `Sym` arguments; then the solver seam for okite's integer laws | H2 (types to draw from) | `crates/blue-lang-cli/tests/properties.rs` green: a drawn neighbour fails where the example passes, the same seed replays it, an untyped definition gets none |
| **types that grow** (H2) | [`HORIZON.md`](HORIZON.md) § H2, [`SAFETY.md`](SAFETY.md) row 7 | PARTIAL: step 1 BUILT (local inference in a typed definition), wave 3 BUILT 2026-11-09: `Map(K, V)`, records and unions in signatures (field types read, B0079 on an undeclared field), list/map/record literals inferred, the static checked boundary (an untyped caller's known argument is B0005, qualified calls included), `blueshift(:strict)` per file (B0082) | the runtime half of G8 (`shift.wrong_arg.annotated`); a Bluefile-wide position; `case` narrowing a union | H1 (shapes to name) | a spec row per rule (`check.infer.*`, `check.signature.*`, `check.boundary.*`, `check.B0082*`) green; the corpus checks clean at `dynamic` || **union** (HORIZON H1, first step) | [`HORIZON.md`](HORIZON.md) §H1, SAFETY row 3 | U1 BUILT: `union shape = circle(r: Float) \| rect(w: Float, h: Float)` declares each arm as a record and `shape?`; a `case` over a union's arms that misses one and has no `else` is B0081; fmt, kiwari and tree-sitter know it. P1 BUILT: a `when` destructures (`rect(w, h)`, `[x, *rest]`, `{name:}`), and B0081 counts a destructuring arm; `[a, b] = pair` and `{name:} = m` bind or raise :pattern; `x = f(y)?` returns a kyohi refusal through a guard `return`. | H1: one declared `result` union for ok/refused; `?` on an Option; arms with no field; record patterns across bidamas | record | `spec/rows/unions.b`, `spec/rows/patterns.b`, `spec/rows/refusals.b` and `crates/blue-lang-runtime/tests/unions.rs` green; B0081 at error |
| HTTP/2 and gRPC | [`HTTP2.md`](HTTP2.md) | PARTIAL (reconciled 2026-11-08 at `5399e761` against its §12 ledger): P1 BUILT and tested (`eigyou/heddaa` HPACK, `eigyou/tajuu` frames and `step`, `text_bytes` and `bytes_text`, 45 heni mutations caught); P2 to P6 DESIGN. The `tcp_*` stream words and `net_wait` are built (2026-11-09, HORIZON H4); no `tls_*` | P2: the pure connection value and its `receive` and `send` steps (§13), with the h2spec cases as byte transcripts | — | P3 `checks.network`: `curl --http2-prior-knowledge` and `h2spec` against a blue server; P5: `grpcurl` and a Go client against a blue server |
| CLI and TUI | [`CLI-TUI.md`](CLI-TUI.md) | PARTIAL (reconciled 2026-11-08): L1 BUILT 2026-10-27 (`hikisuu`: spec, parse, help, completion, `command`; `gamen` line output); L2 to L4 DESIGN. No `prompt`, `confirm` or `choose` in `gamen`, no `read_line` host word | L2: the `Terminal` capability with `read_line` and `is_terminal`; `prompt`, `confirm`, `choose` | — | L4: the remaining hand parsers moved onto `hikisuu`, `hand-rolled-flags` at warning |
| service data defaults | [`SERVICE-DATA.md`](SERVICE-DATA.md) | PARTIAL (reconciled 2026-11-08 against its §4): S3, S4 and S5 BUILT (telemetry export, the RESP client `kiibariu`, JetStream `sutoriimu`); S2 partial (`teeburu::model`, `evolve`, `judge`); S1, S2b, S6 and eleven `pending-*` rows open | S1: haibi renders pleme-lib's `shinkaDatabaseMigration`, the wait init container, `observabilityBundle` and `jetstream` | helmworks H3; HTTP/2 P4 for `pending-resp-tls` | §4's pending table empty and both services (kensa, ola-mundo) on the defaults |
| API evolution | [`API-EVOLUTION.md`](API-EVOLUTION.md) | DESIGN (reconciled 2026-11-08 against its §18 ledger: every lifecycle, version, rendering and storage-planner item is design; only kensa's hand-written `/api/v1` and `kensa.v1` are live) | P1: katachi lifecycle words, `version`, `api_policy`, the delta catalog and the §9 refusals, in pure blue | HTTP/2 P5 for P6 | P8: kensa serves two versions, the headers seen on the wire |
| build stack | [`BUILD-STACK.md`](BUILD-STACK.md) | PARTIAL (reconciled 2026-11-08 against its §8 ledger): S1, S2 and S4 BUILT 2026-10-28 and 10-29 (`runtime` and `access` with the judge, the engine component, the wasm chart); S3 and S5 to S8 DESIGN; no release sets `runtime.component.closure` and no pod runs a component | S3: a component's imports derived from `access.effects` | build assurance B1 for S6 | S8: a handler that raises answers 500, the next request succeeds, and a crash loop backs off (counted in a test) |
| build assurance | [`BUILD-ASSURANCE.md`](BUILD-ASSURANCE.md) | PARTIAL (reconciled 2026-11-08 against its §9): A BUILT 2026-10-27 (the blue actions and `blue-project.yml`); B0 measured for kensa only; B1 to B7 DESIGN | B1: sui pull on by default per system, CI push on for Bluefile repos | — | B7: `checks.build-time` fails on a derivation-count regression |
| documentation | [`DOCUMENTATION.md`](DOCUMENTATION.md) | PARTIAL (reconciled 2026-11-08 against its §8): D0 to D4.1 and D8 BUILT; D7's tree BUILT (`bunsho`); D5, D6 and D9 DESIGN. The census still counts B0056 and B0057 (HORIZON H0) | D5: the static site, published from `blue-project.yml` | build assurance A | D6: `ola-mundo` renders every rendering of §4 by default |
| operators | [`OPERATORS.md`](OPERATORS.md) | DESIGN (reconciled 2026-11-08 against its §9: O1 to O9 design; no `??` or `?.` in `spec/rows/`) | O1: measure `m.k` against `get`, then `m.k` or `m[:k]`, `xs[i]`, `[*xs, y]`, `a..b`, `in` | — | O3: the nested-call corpus rewritten onto the collection-slot pipe with output identical |
| kernel | [`KERNEL.md`](KERNEL.md) | PARTIAL (BUILDING, reconciled 2026-11-08 against its §6 ledger: the encoder, compiler, `btf`, `erufu`, CO-RE and every attach kind listed BUILT, most measured on plo; the kernel-agent chart built and not deployed; a `.ko` module and H20 admission DESIGN) | the kernel-agent chart deployed on one cluster | HORIZON H20 for admission | H20: every program the compiler accepts is admitted by every kernel in the matrix |
| bidama cohesion | [`BIDAMA-COHESION.md`](BIDAMA-COHESION.md) | PARTIAL (reconciled 2026-11-08 against its §6): trees 1 to 10 landed (`kaaneru/bpf`, `btf`, `erufu` on main), exact copies 0, near duplicates 24 in 11 groups; C6's batteries (`himitsu`, `kurasuta`, `habu`, `joujuu`) DESIGN, none on main | the arnes copies of `wariate::bump` and `yushutsu::column` onto foundation words (§ After the trees) | — | `near_duplicate_shapes_only_fall` at its floor and `blue census --reuse` at 0 |

## The arika track

**What it makes blue.** arika makes "does blue already have a word for this?" a
query with a proof. It fits blue's identity: pattern-first (`theory/BLUE.md`
§I.1), because the reuse rule B0070 already turns a copy into a gate and arika
moves that answer before the write; one dialect (§0), because the service, the
schema and the Merkle words are written in blue; and "we write blue, we leverage
nix" (`theory/BLUE-STRUCTURE.md` §5.5), because facts are a nix output and only
the snapshot root is committed. It adds no semantics to the language and no
position on the blueshift.

Rungs (owners, gates and exits are in [`ARIKA.md`](ARIKA.md) § Phases):

| Rung | Content | Tier |
|---|---|---|
| 1 | `blue arika like` / `word`, PreToolUse hook, `bidama` skill step 1 | BUILT (G4 in `crates/blue-lang-cli/tests/arika.rs`) |
| 2 | fact emitter, Merkle words, `SNAPSHOT.json`, `arika` nix output | BUILT for blue's tree (G1, G2, G3, G6); the output for other projects and mokuroku on the facts DESIGN |
| 3 | Parquet plane, full CLI, T3 witnesses, CATALOG.md from facts | PARTIAL: the CLI verbs and G5 BUILT (2026-11-09); Parquet, T3, CATALOG.md from facts and G7 DESIGN |
| 4 | codesearch indexes `.b` | DESIGN |
| 5 | GraphQL + MCP HTTP service on ryn's engenho | PARTIAL: the MCP door in blue and G8 BUILT (2026-11-09); GraphQL, G9 and the release on ryn DESIGN |
| 6 | federation over consumer repos | DESIGN |
| 7 | T4 canonical forms | DESIGN |

Links: the `sakuin` and `kensaku?` spaces in [`VERB-ROADMAP.md`](VERB-ROADMAP.md)
(T5); the rmcp and stdin rows of the port register in [`STDLIB.md`](STDLIB.md)
(the MCP transport).

## Rulings

One answer per question. An overridden text stays, marked superseded with a
dated receipt.

| # | Conflict | Resolution | Rejected | Date, who |
|---|---|---|---|---|
| R1 | `theory/BLUE-STRUCTURE.md` §5.3 "blue expresses derivations: cut it" vs full nix in blue | operator override: blue lowers to sui's derivation seam (`sui_spec::derivation::apply`), not to `sui-ir`. §5.3 is superseded, its text kept, and carries the mark (2026-11-06) | lowering to `sui-ir` (it copies Nix syntax) | 2026-10-24, operator |
| R2 | the check ladder's "zero analysis at rung 0" vs nil-safety on by default | builtin signatures are declared, so the nil rule needs no inference across calls; narrowing is local to one function | a global inference pass | 2026-10-24, operator |
| R3 | `delay` re-runs a re-entrant thunk vs lazy scopes for overlays | a cycle is a typed refusal that names its path. The blackhole state is SAFETY.md row 19 (2026-11-06) | silent re-entry | 2026-10-24, operator |
| R4 | FlakeHub as the registry vs pleme-io sui | the Bluefile and the lock are the truth; sui is the primary backend; FlakeHub is optional and off | FlakeHub as primary | 2026-10-24, operator |
| R5 | arika's schema source: forge-gen (OpenAPI in) vs a blue schema | a blue schema over `toriyose/outou`; GraphQL, MCP tools and tables render from it | forge-gen: a third format, and a Rust MCP proxy | 2026-11-06, operator (D2-D4) |
| R6 | mokuroku reads source as text vs the engine's facts | one producer: mondou's emitter. mokuroku reads the facts in Phase 2 and keeps its output | a second analyser | 2026-11-06, operator |
| R7 | arika's own full-text words vs the `sakuin` verb space | arika is the first consumer of `sakuin` and drives it into existence | private full-text words inside arika | 2026-11-06, operator |
| R8 | arika's T6 vs codesearch | codesearch owns vectors, BM25 and trigrams; arika feeds it word chunks and calls it for T6 | a second embedding store | 2026-11-06, operator |
| R9 | a PreToolUse hook that blocks a copy vs one that advises | advisory; the `blue census --reuse` ratchet enforces | blocking at write time | 2026-11-06, operator (D6) |
