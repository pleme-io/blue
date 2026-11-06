---
kind: explanation
summary: arika, blue's word search, Phase 1 built and the rest DESIGN: the recon, phases, gates with red runs, risks and every surface that names it
---

# arika (在り処): the design of record

**Tier (2026-11-06): Phase 1 BUILT, Phases 2-7 DESIGN.** Phase 1 is
`crates/blue-lang-cli/src/arika.rs` (the facts, from the engine) and the
embedded `crates/blue-lang-cli/blue/arika.b` (ranking and every answer's
text), locked by `crates/blue-lang-cli/tests/arika.rs`. The spec (data model, tier
ladder, proofs, schema, prior art) is `theory/ARIKA.md`. This file holds what
an agent needs to build and maintain arika: the recon with paths, the phases,
the gates with their red runs, the risks, and every surface that names arika.
The roadmap row is the arika track in [`ROADMAP.md`](ROADMAP.md).

Every "today" claim was read at blue `6434ce31` on 2026-11-06.

## How to ask

| Face | Call | Phase | Tier |
|---|---|---|---|
| CLI | `blue arika like FILE[:LINE]`, `blue arika word NAME`, each with `--json` | 1 | BUILT |
| CLI | `blue arika find "intent"`, `uses ID`, `changed PKG --since V`, `groups` | 3 | DESIGN |
| Hook | `blue arika like --hook` on a `.b` Write, Edit or MultiEdit, before the write, advisory | 1 | BUILT |
| MCP | `blue_word_like`, `blue_word_find`, `blue_word_get`, `blue_word_uses`, `blue_word_changes` | 5 | DESIGN |
| GraphQL | `POST /graphql` on the arika service on ryn's engenho | 5 | DESIGN |

## What Phase 1 answers, and what it cannot see

| Question | How | Tier |
|---|---|---|
| T0: an exact copy, docs included | the draft's `def_hash` (`blue_lang_mondou::hash_checked`) equals the home's, the home checked in process | proved by test, red run: invert the comparison |
| T1: the same code, other local names | the draft's written shape equals the home's written shape | proved by test |
| T2: the same code through a wrapper | the computed shape hits `WORD_SHAPES`, the table B0070 reads | G4: `arika_and_b0070_name_the_same_word_g4`, red run: match on the written shape |
| T5: a word by name, old spelling, part or gloss | `WORD_SHAPES` words, every package's `legacy_names` moves, and `CATALOG.md` rows | proved by test; a missing catalogue is `blind`, never empty |
| a readable id | `blue:blue:<word>@<12 hex of def_hash>`; the repo is always `blue`, because `WORD_SHAPES` spans blue's bidamas only | proved by test |
| the hook | lowers the draft a Write, Edit or MultiEdit would leave, prints advice, exits 0 | test, red run: ignore the Edit |

Blind spot, shared with B0070: a home word's computed shape inlines the
forwards defined in its own file. A copy that calls the same helper by import
(`rest(scan(...))` for `retsu::running_sum`) has a different shape and is not
named. Phase 2's emitter and Phase 3's T3 witnesses are where that closes.

**A repo opts out** with `arika(false)` in its Bluefile. That configures the
`arika` output off. It deletes nothing.

## What exists today, and what arika reuses

| Piece | Path | Gives | Gap arika closes |
|---|---|---|---|
| Definition hash | `crates/blue-lang-runtime/src/def_hash.rs` | `DefHash`, `b3:<hex>`, docs hashed in, names as metadata, SCC units | no per-definition emitter |
| Shape hash | same file, `shape_hashes`, `computed_shape_hashes` | T1 and T2 keys | none |
| Word shapes | `crates/blue-lang-runtime/src/word_shapes/tables.rs` (about 4,640 rows) | B0070's 16-hex prefix table | distribution only, home word only |
| Near duplicates | `crates/blue-lang-check/src/shape.rs` | `generalize`, `Near::admits`, `groups` | no index |
| Reuse facts | `crates/blue-lang-cli/src/census.rs` `ReuseFact` | 4,687 rows over `bidamas/` in 8.5 s (measured) | no def hash, no doc, defs under 12 nodes left out |
| B0070 | `crates/blue-lang-check/src/rules.rs` | warning + `--fix` | fires after the copy |
| PostToolUse hook | `blackmatter-pleme/module/default.nix` | `blue check --reuse --hook` | sees no draft before the write |
| Structural query | `blue query` | clause algebra; 5,573 functions with reach in 9.4 s | rescans each run |
| Engine | `crates/blue-lang-mondou` | hashes, reach, `doc_view`, completion, workspace symbols | `blue context` is not shipped |
| Catalogue | `bidamas/mokuroku/mokuroku.b`, `bidamas/CATALOG.md` | 66 packages, 5,573 definitions | reads source as text; a macro-made def is not seen |
| Verb graph | `docs/verbs/merged/*.tsv` | intent vocabulary | joined only through `doc_view` |
| SQL | `bidamas/kueri` | DuckDB SQL from blue | subprocess, acceptable for the CLI |
| GraphQL | `bidamas/toriyose/danpen`, `toriyose/outou` | pure-blue parse, validate, execute | not mounted on HTTP |
| HTTP | `bidamas/eigyou/kyuuji` | `serve`, routes, guards | no JSON-RPC or MCP level |
| Crypto | `crates/blue-lang-runtime/src/crypto.rs`, `bidamas/fuuin` | `blake3`, FROST Ed25519 | no Merkle words |

Outside blue: tameshi (`src/merkle.rs`, RFC 9162 layout, the test oracle;
`src/signing.rs` signs only root bytes), codesearch (cannot index `.b`:
`Language::Unknown`), ola-mundo (the service shape to copy).

## Phases

Each phase is on the shortest path to the destination in `theory/ARIKA.md` §1.
No phase builds what a later phase throws away.

| # | Deliverable | Owner | Gates | Exit |
|---|---|---|---|---|
| 1 | `blue arika like` + `word` in process: T0-T2 with readable IDs, import line and fix; T5 by substring over CATALOG glosses and legacy names. PreToolUse hook `blue arika like --hook` (exit 0 always). `bidama` skill step 1 | blue (`crates/blue-lang-cli`, an embedded `blue/arika.b`), blackmatter-pleme | G4 | a copy of a foundation word gets the word before the write, on 3 fixtures |
| 2 | `blue arika emit ROOT`: every fact per package as canonical JSONL, unit roots, `SNAPSHOT.json`. Merkle words in blue. `mkBidama` and `blue.lib.project` gain an `arika` output. census, `gen/word-shapes.b` and mokuroku read the emitter | blue (mondou, cli, `mk-bidama.nix`, a Merkle level) | G1, G2, G3, G6 | snapshot committed and fresh; leaves equal the definition count; `WORD_SHAPES` bytes unchanged |
| 3 | nix-built Parquet; `find`, `uses`, `changed`, `groups` through kueri; T3 with lgg witnesses; compression rank; CATALOG.md rendered from facts | blue (mokuroku, kueri, an arika level) | G5 (CLI), G7 | about 50 golden questions pass offline in CI |
| 4 | `Language::Blue` in codesearch over `tree-sitter-blue`, one chunk per `def`; arika renders word chunks carrying the ID | codesearch | a `.b` fixture test with a red run without the language | `semantic_search` returns a `.b` chunk |
| 5 | GraphQL on `kyuuji`; MCP Streamable HTTP level in `eigyou`; the arika service (schema in blue, tools as persisted operations, T6 through codesearch HTTP, reload vigy); engenho release on ryn; `mcpServers.arika` in blackmatter-claude | blue (eigyou, toriyose), the `arika` repo, nix (`nodes/ryn`), blackmatter-claude | G5 (service), G8, G9, MCP conformance | a fresh session on ryn lists `blue_word_*` and answers the golden set with the CLI's bytes |
| 6 | consumer repos loaded from the `tend` workspace; fleet root; cross-repo callers | the `arika` repo | coverage and consistency per repo | one query spans blue and at least 3 consumer repos |
| 7 | T4: a bounded e-graph canonical form under audited laws | blue | a property test per law; a node budget with a red run | near groups collapse with 0 false merges on the golden set |

Phase 5 starts by proving the ola-mundo pod runs on ryn's engenho. That was not
verified on 2026-11-06. Phases 1-4 need no engenho.

## Gates and their red runs

| Gate | Proves | Red run |
|---|---|---|
| G1 `arika-fresh` | committed `SNAPSHOT.json` root equals the nix-built root | edit a def, do not regenerate |
| G2 `arika-coverage` | leaves equal every definition the engine sees (5,573 functions in `bidamas/`, 2026-11-06) | drop one leaf in the emitter |
| G3 `arika-word-shapes-parity` | each `WORD_SHAPES` prefix matches a shape row with the same home | corrupt one table row |
| G4 `arika-b0070-parity` (BUILT: `crates/blue-lang-cli/tests/arika.rs`) | `like` and B0070 name the same word for every definition of 12 nodes or more; below that B0070 is silent by design and `like` still answers | match on the written shape instead of the computed one: G4 and two more tests go red |
| G5 `arika-queries` | the golden questions keep their top hit, on CLI and service | remove one gloss |
| G6 `arika-proof` | proofs verify; tameshi RFC 9162 vectors pass in blue | flip one leaf byte |
| G7 `arika-consistency` | snapshot n+1 extends n; `seq` grows | reuse a `seq` |
| G8 `arika-schema-fresh` | SDL and tool list are rendered from the blue schema | hand-edit the SDL |
| G9 liveness vigy | the loaded root equals the newest built root | stop the reload sidecar |
| G10 mutants | `heni` on arika's blue; `cargo mutants` on the Rust emitter | — |

Nothing here makes a stale answer unrepresentable. Each answer carries its
`snapshot_root`, so a stale answer is visible.

## Risks

| Risk | Mitigation |
|---|---|
| two analysers drift from B0070 or `blue query` | one emitter in mondou; G3, G4 |
| a stale index answers confidently | `snapshot_root` in every answer; `blind`, never `empty` (G9) |
| a draft lowers in the wrong `BLUE_PATH` | `like` takes `repo`, as `census::environment_over` does (G4) |
| tameshi signs only root bytes | sign the header hash; fix `SignedRoot` upstream |
| tameshi's `full` feature pulls akeyless and axum | Merkle words in blue, tameshi as oracle (D3) |
| blue has no stdin, so no stdio MCP | HTTP MCP first (D4) |
| T3 is all-pairs | size buckets, then LSH once measured |
| a doc edit moves `def_hash` and its callers' | shape hash for "same code"; `changed` reports doc-only moves |
| another session lands in blue at the same time | Phase 1 touches only the CLI and a new embedded program |

## Conflicts found, and their rulings

These are recorded in [`ROADMAP.md`](ROADMAP.md) § Rulings.

- `docs/API-EVOLUTION.md` says no blue GraphQL executor exists. `toriyose/outou`
  is one. The line is stale and gets a dated correction when Phase 5 starts.
- forge-gen reads OpenAPI only. arika's schema source stays blue.
- mokuroku reads text; arika reads the engine. mokuroku moves onto the emitter
  in Phase 2 and keeps its output.
- The `sakuin` verb space (T5) has no words today. arika is its first consumer
  and drives it, rather than minting its own full-text words.
- The `sakuin` repo is a tantivy wrapper whose CLAUDE.md says "Tankyu". That is
  a stale name, fixed separately.

## Surfaces that name arika

| Surface | Path | Tier |
|---|---|---|
| spec | `theory/ARIKA.md`; rows in `theory/VOCABULARY.md`, `theory/NAMING.md`; pointer in `theory/BLUE-ENGINE.md` §5.3 | canonical |
| this file + roadmap track | `docs/ARIKA.md`, `docs/ROADMAP.md` | advisory |
| agent guide | `docs/agents.md` (renders `CLAUDE.md`, `AGENTS.md`, `llms-full.txt`) | generated, gated fresh |
| skills | `blackmatter-pleme/skills/bidama` (step 1), `blackmatter-pleme/skills/arika` (maintenance) | advisory |
| org pointer | `blackmatter-pleme/docs/pleme-io-CLAUDE.md` HOUSE STYLE "Find before you write blue" | advisory |
| knowledge note | `nix/docs/knowledge/pleme-io/blue/` | recall |
| repo declaration | `pangea-architectures/workspaces/pleme-io-opensource/org.yaml` | declared, not applied |
| CLI + rule | `crates/blue-lang-cli/src/arika.rs`, `crates/blue-lang-cli/blue/arika.b`; B0070's explanation names arika | built |
| PreToolUse hook | `blackmatter-pleme/module/default.nix`, `blue arika like --hook` on `Edit\|Write\|MultiEdit` | built |
| still to come | `mcpServers.arika` (Phase 5), engenho release in `nix/nodes/ryn` (Phase 5) | — |

When a phase ships, update its row here, the roadmap tier, the skill text and
the knowledge note in the same pass.
