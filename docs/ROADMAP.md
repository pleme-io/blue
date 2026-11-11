---
kind: reference
summary: the one blue roadmap, one row per track with its state and the evidence for it, and every conflict ruled once
---

# blue roadmap

This page has one row per track. Each row names its design doc, its state and
the evidence for that state. A ⏳ row also names what is built and the next
step. A ❌ row names the gate that makes it done. § Rulings decides each
conflict between tracks once. The `blue-roadmap` skill owns the procedure to
add or edit a row.

✅ built and tested · ⏳ in progress · ❌ not built

The state comes from main and its tests, never from a report. A ✅ cites a
test or a path. When the evidence is not on main, the row says ❌.
Measured 2026-11-09. The long plan these rows serve, ten horizons from hygiene
to replay and proof, is [`HORIZON.md`](HORIZON.md). A horizon gets a row here
when its first phase starts.

## Ledger

| Track | State | What makes it true |
|---|---|---|
| **substrate**: blue as the one language of the whole stack ([`SUBSTRATE.md`](SUBSTRATE.md)) | ❌ not built | No phase of SUBSTRATE.md §9 is on main. Next step L1.1: an engenho e2e runs the real `blue-component.wasm` with a bundle and serves a request. With the bundle path removed, it fails with the named error, not a hang. |
| **arika**: blue's word search ([`ARIKA.md`](ARIKA.md)) | ⏳ in progress | Phases 1 and 2 are built for blue's own tree: `crates/blue-lang-cli/tests/arika.rs` (G2, G3, G4), `gen/arika-facts.b`, `bidamas/SNAPSHOT.json`. Phase 3's CLI verbs (`find` over `bidamas/junni`, `get`, `uses`, `groups`, `changed`, `ask`) and the MCP door (`mcp_*` in `bidamas/eigyou/kyuuji`, `blue arika serve`) are built in process (2026-11-09): `the_golden_questions_keep_their_top_hit_g5` (G5), `docs/arika-tools.json` (G8). `why` and `blue_word_why` are built (2026-11-10): cited reasons, pins, blind sources, and `no recorded reason` when nothing says (`why_cites_the_doc_the_commits_and_the_plans_and_a_word_with_none_has_no_recorded_reason` in `crates/blue-lang-cli/tests/arika.rs`). Not built: the `arika` output for other projects, mokuroku on the facts, the Parquet plane through kueri, T3, CATALOG.md from the facts, G7, G9, the release on ryn. Done when G1 to G9 are green on main. |
| **namespaces** ([`NAMESPACES.md`](NAMESPACES.md)) | ✅ built | B0076, B0077 and B0078: `crates/blue-lang-cli/tests/levels.rs`, `crates/blue-lang-runtime/tests/levels.rs`, `crates/blue-lang-check/src/namespace_rules.rs`. Open: close the flat-era `legacy_names` windows at each root's next minor. |
| **absence** ([`ABSENCE.md`](ABSENCE.md)) | ❌ not built | Only the document exists. No `umu` bidama, no `crates/blue-lang-runtime/src/absence.rs`. B0054 and B0055 are reserved. Next step P1: `umu`, with B0054 and B0055 at audit. |
| **safety** ([`SAFETY.md`](SAFETY.md)) | ⏳ in progress | The SAFETY.md ledger holds one row per invariant with its state. Next step: rows 1, 3 and 14. Done when each row is at its stated seal. |
| **testing** ([`TESTING.md`](TESTING.md)) | ⏳ in progress | The TESTING.md ledger holds the state of each item. |
| **registry** ([`REGISTRY.md`](REGISTRY.md)) | ⏳ in progress | The sui and FlakeHub backends are built (`bidamas/touroku/touroku.b` tests). `porto` and `github` are refused as `not_built`. `blue registry status` never fails, so it gates nothing. Done when a registry check exits non-zero on an absent pin. |
| **blue on sui** | ❌ not built | No crate and no nix file calls sui's derivation seam (`sui_spec::derivation::apply`). Done when blue lowers a derivation through that seam (Ruling R1). |
| **frontend** ([`FRONTEND-PLAN.md`](FRONTEND-PLAN.md)) | ⏳ in progress | `bidamas/burauza` exists. `examples/13_web_site.b` renders and serves a page natively. Next step: that page as a declared `runtime: :wasm` service. |
| **content-addressed caching** (HORIZON H3) | ⏳ in progress | Rung 1 is built: the check cache per definition. Rung 2 is built for a bidama's own files (2026-11-10): `mkBidama`'s `analysis` output, joined by `mkAnalysis`, on `BLUE_CACHE_SHARED` in `mkBlueWithBidamas`. Rung 3 is built for the identity and the shared tier: the engine's BLAKE3 as identity, and `BLUE_CACHE_SHARED` under the check cache, the memo and the test cache. `crates/blue-lang-cli/tests/shared_cache.rs`: a second node running the same bytes caches the first's passed test, and a changed dependency runs it again. The memo stays off by default (measured slower on the corpus's tests). Not built: rungs 4 and 5, a fingerprint per bidama so a consumer's program reuses a bidama's analysis, then a node's store pushed to sui. |
| **placement parity** (HORIZON H8, [`spec/README.md`](../spec/README.md) § The evaluators) | ⏳ in progress | `checks.conformance` (`crates/blue-lang-test/tests/conformance.rs`) runs the `prints` and `fails` rows in the wasm32-wasip2 engine component under wasmtime and compares each with `blue run`. Five rows wait on component gaps (`pending("G20", "component")` to `pending("G23", "component")` in `spec/rows/`). G20: the component holds no execution bounds. G21: host errors carry the platform errno. G22: a capability the placement lacks refuses in its own words. G23: `nats_connect` panics for want of a pid. Next step: compare run receipts, not only output. |
| **verbs** ([`VERB-ROADMAP.md`](VERB-ROADMAP.md)) | ⏳ in progress | The graph is blue rows in `bidamas/mokuroku/graph/`, gated by `checks.verb-graph`. The contract table has 4 open rows. The VERB-ROADMAP.md ledger holds the rest. |
| **khipu**: the knowledge graph ([`KHIPU.md`](KHIPU.md)) | ⏳ in progress | K1a is built: `bidamas/khipu` (terms, quads, N-Triples, N-Quads). K1b's store and basic graph patterns are built (2026-11-09): DuckDB through `kueri`, NOT EXISTS, a row budget, blue's own facts as quads; tests "a basic graph pattern joins in DuckDB, and an absent group removes what it matches" and "past its budget a question is refused, never cut short" in `bidamas/khipu/khipu.b`. Not built: the W3C syntax suites against Oxigraph, then K2. Done when the W3C suites of K1 to K4 pass as a differential against Oxigraph. |
| **utsushi**: history projection ([`UTSUSHI.md`](UTSUSHI.md)) | ⏳ in progress | U1 is built: `bidamas/utsushi`. U2 to U6 are not built: the lens parser still refuses `:exclude` (utsushi test `lens_refused?`). Done when `josh-filter` ids match on the fixtures and the round-trip law is green. |
| **async**: native async, the `heikou` space ([`ASYNC.md`](ASYNC.md)) | ⏳ in progress | Built: processes (`crates/blue-lang-proc`), node-time timers (`crates/blue-lang-proc/tests/timers.rs`), `net_wait` (`crates/blue-lang-proc/tests/net_wait.rs`), record and replay (`crates/blue-lang-cli/tests/run_replay.rs`), the H4 debugger (2026-11-10): `blue debug`, a Debug Adapter Protocol server over a recorded run, with call and return steps, step back by replay, and breakpoints by name, `def_hash` or definition line (`crates/blue-lang-cli/tests/debug.rs`). Not built: a deadline narrowed inside a process, A2, `schedulers(n)` (A6). |
| **record**: a named structure in one line (`examples/17_records.b`) | ✅ built | `spec/rows/records.b`; `crates/blue-lang-runtime/tests/records.rs` (B0079) |
| **guard return** ([`GUARD-RETURN.md`](GUARD-RETURN.md)) | ⏳ in progress | G1 is built: `crates/blue-lang-syntax/src/guard.rs`, `crates/blue-lang-runtime/tests/guard_return.rs` (B0080). The tree-sitter grammar knows `return` (`tree-sitter-blue/grammar.js`, `queries/highlights.scm`). Not built: `return` inside `rescue`. |
| **types that grow** (HORIZON H2, SAFETY row 7) | ⏳ in progress | Step 1 is built: local inference in a typed definition, with `check.infer` rows in `spec/rows/check.b`. Wave 3 is built (2026-11-09): `Map(K, V)`, records and unions in signatures (B0079 on an undeclared field), list, map and record literals inferred, the static checked boundary (an untyped caller's known argument is B0005, qualified calls too) and `blueshift(:strict)` per file (B0082); rows `check.signature.*`, `check.boundary.*` and `check.B0082*` in `spec/rows/check.b`. Not built: the runtime half of the checked boundary (`shift.wrong_arg.annotated`), a Bluefile-wide position, `case` narrowing a union. |
| **proof** (HORIZON H6, [`TESTING.md`](TESTING.md)) | ⏳ in progress | Built: heni's caught ratio as a ratchet per package (`bidamas/heni/ratio.baseline`, `checks.heni-mutations`); generated properties (`crates/blue-lang-cli/tests/properties.rs`). Not built: laws over a decidable fragment, the solver seam for okite's integer laws. |
| **union** (HORIZON H1, SAFETY row 3) | ⏳ in progress | U1 and P1 are built: `spec/rows/unions.b`, `spec/rows/patterns.b`, `spec/rows/refusals.b`, `crates/blue-lang-runtime/tests/unions.rs` (B0081). Next step: one declared `result` union for ok and refused, `?` on an Option, arms with no field. |
| **HTTP/2 and gRPC** ([`HTTP2.md`](HTTP2.md)) | ⏳ in progress | P1 is built: `bidamas/eigyou/heddaa` (HPACK) and `bidamas/eigyou/tajuu` (frames). No `tls_*` words exist. P2 to P6 are not built. Next step P2: the pure connection value and its `receive` and `send` steps. |
| **CLI and TUI** ([`CLI-TUI.md`](CLI-TUI.md)) | ⏳ in progress | L1 is built: `bidamas/hikisuu` (spec, parse, help, completion) and `gamen` line output. Not built: `prompt`, `confirm` and `choose` in `gamen`, and a `read_line` host word. |
| **service data defaults** ([`SERVICE-DATA.md`](SERVICE-DATA.md)) | ⏳ in progress | Built: `bidamas/chozou/kiibariu` (RESP), `bidamas/chozou/sutoriimu` (JetStream), `bidamas/chozou/teeburu`. The SERVICE-DATA.md ledger holds the rest. |
| **API evolution** ([`API-EVOLUTION.md`](API-EVOLUTION.md)) | ❌ not built | No `api_policy` word exists in any bidama or crate. Next step P1: lifecycle words, `version`, `api_policy` and the delta catalog in pure blue. Done at P8: a service serves two versions, with the headers seen on the wire. |
| **build stack** ([`BUILD-STACK.md`](BUILD-STACK.md)) | ⏳ in progress | Built: the `runtime` and `access` entries (`crates/blue-lang-pkg/src/capabilities.rs`, `deploy/service.rs`) and the engine component (`nix build .#blue-component`). No pod runs a component. The BUILD-STACK.md ledger holds the rest. |
| **build assurance** ([`BUILD-ASSURANCE.md`](BUILD-ASSURANCE.md)) | ⏳ in progress | The BUILD-ASSURANCE.md ledger holds the state of each item. Done when `checks.build-time` fails on a derivation-count regression. |
| **documentation** ([`DOCUMENTATION.md`](DOCUMENTATION.md)) | ⏳ in progress | Built: `bidamas/hon` with `checks.docs` (`gen/docs.b`), and `bidamas/bunsho`. Not built: D5, the static site. |
| **operators** ([`OPERATORS.md`](OPERATORS.md)) | ❌ not built | No `??` and no `?.` in `spec/rows/`. Next step O1: measure `m.k` against `get`. |
| **kernel** ([`KERNEL.md`](KERNEL.md)) | ⏳ in progress | Built: `bidamas/kaaneru` with `bpf`, `btf` and `erufu`. The kernel-agent chart is in `examples/kernel-agent/deploy/kernel-agent/chart` and is not deployed. Not built: a `.ko` module and H20 admission. |
| **bidama cohesion** ([`BIDAMA-COHESION.md`](BIDAMA-COHESION.md)) | ⏳ in progress | The trees landed (`bidamas/kaaneru/bpf`, `btf`, `erufu`). `bidamas/kurasuta` exists with the typed kinds only, and its reads are not built. No `himitsu`, `habu` or `joujuu` bidama exists. Done when `blue census --reuse` reads 0. |

## The arika track

**What it makes blue.** arika turns the question "does blue already have a
word for this?" into a query with a proof. It fits blue in three ways. blue is
pattern-first: the reuse rule B0070 already turns a copy into a gate, and arika
gives that answer before the write. blue is one dialect: the service, the
schema and the Merkle words are blue. blue is written in blue and built with
nix: the facts are a nix output, and only the snapshot root is committed.
arika adds no semantics to the language and takes no position on the
blueshift.

The owners, gates and exits of each rung are in [`ARIKA.md`](ARIKA.md) § Phases.

| Item | State | What makes it true |
|---|---|---|
| Rung 1: `blue arika like` and `word`, the PreToolUse hook, the `bidama` skill step 1 | ✅ built | `crates/blue-lang-cli/tests/arika.rs`: `arika_and_b0070_name_the_same_word_g4`, `the_hook_advises_on_the_draft_before_the_write_and_never_blocks` |
| Rung 2: the fact emitter, Merkle words, `SNAPSHOT.json`, the `arika` nix output | ⏳ in progress | Built for blue's own tree: `gen/arika-facts.b`, `bidamas/SNAPSHOT.json`, `every_definition_is_one_leaf_with_its_facts_g2`. Not built: the output for other projects, mokuroku on the facts. |
| Rung 3: the Parquet plane, the full CLI, T3 witnesses, CATALOG.md from facts | ⏳ in progress | Built (2026-11-09): the CLI verbs over the facts in `crates/blue-lang-cli/blue/arika.b`, and G5, `the_golden_questions_keep_their_top_hit_g5` over `crates/blue-lang-cli/tests/arika_golden.tsv`. Not built: no crate or generator writes Parquet; T3, CATALOG.md from facts and G7 are open. |
| Rung 4: codesearch indexes `.b` | ❌ not built | Done when a codesearch index answers a query over `.b` files. |
| Rung 5: a GraphQL and MCP HTTP service | ⏳ in progress | Built (2026-11-09): the MCP door in blue (`mcp_answer`, `mcp_handler` in `bidamas/eigyou/kyuuji`), `docs/arika-tools.json` (G8), `the_mcp_door_lists_the_rendered_tools_and_answers_a_call_as_the_cli_does`. Not built: GraphQL, G9, the release on ryn. Done when a session answers the golden set through `blue_word_*`. |
| Rung 6: federation over consumer repos | ❌ not built | Done when one query answers over blue and a consumer repo. |
| Rung 7: T4 canonical forms | ❌ not built | Done when T4 names two definitions with one canonical form. |

Links: the `sakuin` and `kensaku?` spaces in [`VERB-ROADMAP.md`](VERB-ROADMAP.md)
(T5); the rmcp and stdin rows of the port register in [`STDLIB.md`](STDLIB.md)
(the MCP transport).

## Rulings

One answer per question. An overridden text stays, marked superseded with a
dated receipt.

| # | Conflict | Resolution | Rejected | Date, who |
|---|---|---|---|---|
| R1 | the earlier rule "blue expresses derivations: cut it" vs full nix in blue | operator override: blue lowers to sui's derivation seam (`sui_spec::derivation::apply`), not to `sui-ir`. The earlier rule is superseded (2026-11-06) | lowering to `sui-ir` (it copies Nix syntax) | 2026-10-24, operator |
| R2 | the check ladder's "zero analysis at rung 0" vs nil-safety on by default | builtin signatures are declared, so the nil rule needs no inference across calls; narrowing is local to one function | a global inference pass | 2026-10-24, operator |
| R3 | `delay` re-runs a re-entrant thunk vs lazy scopes for overlays | a cycle is a typed refusal that names its path. The blackhole state is SAFETY.md row 19 (2026-11-06) | silent re-entry | 2026-10-24, operator |
| R4 | FlakeHub as the registry vs pleme-io sui | the Bluefile and the lock are the truth; sui is the primary backend; FlakeHub is optional and off | FlakeHub as primary | 2026-10-24, operator |
| R5 | arika's schema source: forge-gen (OpenAPI in) vs a blue schema | a blue schema over `toriyose/outou`; GraphQL, MCP tools and tables render from it | forge-gen: a third format, and a Rust MCP proxy | 2026-11-06, operator (D2-D4) |
| R6 | mokuroku reads source as text vs the engine's facts | one producer: mondou's emitter. mokuroku reads the facts in Phase 2 and keeps its output | a second analyser | 2026-11-06, operator |
| R7 | arika's own full-text words vs the `sakuin` verb space | arika is the first consumer of `sakuin` and drives it into existence | private full-text words inside arika | 2026-11-06, operator |
| R8 | arika's T6 vs codesearch | codesearch owns vectors, BM25 and trigrams; arika feeds it word chunks and calls it for T6 | a second embedding store | 2026-11-06, operator |
| R9 | a PreToolUse hook that blocks a copy vs one that advises | advisory; the `blue census --reuse` ratchet enforces | blocking at write time | 2026-11-06, operator (D6) |
