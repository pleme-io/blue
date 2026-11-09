---
kind: explanation
summary: arika, blue's word search, Phases 1 and 2 built for blue's own tree and the rest DESIGN: the recon, phases, gates with red runs, risks and every surface that names it
---

# arika (在り処): the design of record

**Tier (2026-11-09): Phases 1 and 2 BUILT for blue's own tree; Phase 3's CLI
and Phase 5's MCP door BUILT in process; the rest DESIGN.** Phase 1 is
`crates/blue-lang-cli/src/arika.rs` (the facts, from the engine) and the
embedded `crates/blue-lang-cli/blue/arika.b` (ranking and every answer's
text), locked by `crates/blue-lang-cli/tests/arika.rs`. Phase 2 adds the
per-definition producer `crates/blue-lang-mondou/src/facts.rs`, `blue arika
emit`, the RFC 9162 words `shomei::ct_*`, the committed header
`bidamas/SNAPSHOT.json` (`generate("arika-snapshot")` in the root `Bluefile`,
`gen/arika.b`) and the facts as a nix output, `packages.arika-facts`
(`run("arika-facts")`, `gen/arika-facts.b`), never committed (D1). Phase 3
(2026-11-09) adds `find` (BM25 through the new `bidamas/junni`), `get`,
`uses`, `groups`, `changed`, `golden` (G5) and the facts' `calls`, `reach`
and `tests`; Phase 5 adds the MCP words in `eigyou/kyuuji` (`mcp_answer`,
`mcp_handler`), the tool schema `TOOLS` in `arika.b`, `blue arika tools`
(rendered to `docs/arika-tools.json`, G8), `blue arika mcp` (one request) and
`blue arika serve` (Streamable HTTP). Open: the Parquet plane, T3 witnesses,
CATALOG.md from the facts, G7, G9, `blue_word_like` as a tool, GraphQL, and
the release on ryn. Two Phase 2 rows stay DESIGN: the `arika` output of
`mkBidama` and `blue.lib.project` for other projects, and mokuroku reading the
facts. The spec (data model, tier
ladder, proofs, schema, prior art) is `theory/ARIKA.md`. This file holds what
an agent needs to build and maintain arika: the recon with paths, the phases,
the gates with their red runs, the risks, and every surface that names arika.
The roadmap row is the arika track in [`ROADMAP.md`](ROADMAP.md).

Every "today" claim was read at blue `6434ce31` on 2026-11-06.

## How to ask

| Face | Call | Phase | Tier |
|---|---|---|---|
| CLI | `blue arika like FILE[:LINE]`, `blue arika word NAME`, each with `--json` | 1 | BUILT |
| CLI | `blue arika emit [ROOT] [--facts FILE]` writes the header `ROOT/SNAPSHOT.json` and the facts; `like` and `word` take `--snapshot HEADER --facts FILE` and answer from the facts, or refuse them as blind when their root is not the header's | 2 | BUILT |
| CLI | `blue arika find "intent"`, `get WORD`, `uses WORD\|ID`, `groups [--min N]`, `changed PKG --since OLD.jsonl`, `golden FILE`, each with `--json` and `--snapshot HEADER --facts FILE` (without them the facts of `--root`, default `bidamas`, are built in process) | 3 | BUILT (2026-11-09) |
| CLI | `blue arika ask untested-CAPABILITY`: blue's definitions, tests, doc examples and rules as khipu quads, asked through DuckDB; `blue arika quads OUT` writes the N-Quads | 3 | BUILT (2026-11-09) |
| Hook | `blue arika like --hook` on a `.b` Write, Edit or MultiEdit, before the write, advisory | 1 | BUILT |
| MCP | `blue_word_find`, `blue_word_get`, `blue_word_uses`, `blue_word_groups`, `blue_word_changes`, `blue_word_ask`: `blue arika serve [ADDR]` (Streamable HTTP, JSON answers), `blue arika mcp REQUEST` (one JSON-RPC message), `blue arika tools` (the list) | 5 | BUILT in process (2026-11-09); not released on ryn |
| MCP | `blue_word_like` | 5 | DESIGN: a draft needs the engine, which the blue service does not hold |
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

## What Phase 2 holds

Two files, as D1 rules: a small committed header and the facts it roots, a nix
output.

- **The header**, `bidamas/SNAPSHOT.json` (format `arika/1`, 12 KB on
  2026-11-06): canonical JSON, keys sorted, one package per line. It holds
  `definitions`, `leaves`, `blind`, the `snapshot_root`, and per package its
  `unit_root` and row count. It changes only when a fact changes.
- **The facts**, `facts.jsonl` in `nix build .#arika-facts` (beside a copy of
  the header): one row per line, in unit order. A row is one definition the
  engine sees, of any kind (function, value, macro): `id`
  (`blue:blue:<package path>::<word>@<12 hex>`), `word`, `package`, `name`,
  `kind`, `def_hash`, `shape` (computed, T2), `written_shape` (T1), `size`,
  `file` (relative to the root), `line`, `gloss` (the first line of its `@doc`,
  as CATALOG.md writes it) and `legacy` (the old spellings that moved to it,
  with `since`).

| Piece | Rule |
|---|---|
| leaf | BLAKE3 of the row's canonical JSON |
| unit root | `shomei::ct_root` over a package's leaves: RFC 9162 layout, leaf `0x00`, node `0x01`, tameshi's `compute_leaf_root` |
| snapshot root | `ct_root` over the unit roots, in package order |
| determinism | rows sorted by package, word, file, line; paths relative; no time, commit or engine version in either file |
| coverage | `emit` refuses to write when the rows are not the definitions the producer counted |
| a file that does not check | listed in `blind` with its reason; the other files still emit |
| a stale index | `like` and `word` recompute the root of the facts they are given; when it is not the header's they answer `blind` and name the rebuild, never a stale `found` or `empty` |

`seq`, `commit`, `engine_identity` and `expires` are left out, because each
would make the same tree give different bytes; G7 (Phase 3) is where `seq` is
checked. `census --reuse` reads the same producer (`facts::of_entry`), and
`gen/word-shapes.b` reads census, so `WORD_SHAPES` comes from it too. The
Bluefile's `run` takes `inputs` for this (`run(name, file[, reads[,
inputs]])`, under `$GEN_ROOT`), as `generate` and `check` do.

Measured 2026-11-06 on blue's tree: 5,737 definitions, 5,737 leaves, 102
units, 0 blind.

**A repo opts out** with `arika(false)` in its Bluefile. That configures the
`arika` output off. It deletes nothing.

## What Phase 3 and the MCP door hold (2026-11-09)

Each facts row gains three fields, from one more pass of the same producer
(`blue_lang_mondou::facts::of_entry_linked`): `calls` (the words the
definition names, `reach::form_reach`), `reach` (the host capabilities it
reaches through any chain, `reach::host_reach`) and `tests` (each test block
and `@doc` example that names it: file, line, name, `doc`). A test exercises a
word when its body names it directly; a word reached only through another
word is not tested by that test.

| Verb | Answers | Words |
|---|---|---|
| `find TEXT` | words ranked by BM25 over name parts, package and gloss | `junni::invert`, `junni::score` |
| `get WORD` | every row of a word, by word or readable id | `get_answer` |
| `uses WORD` | the definitions whose `calls` hold the word | `uses_answer` |
| `groups` | functions of 12 nodes or more sharing one computed shape across words | `groups_answer` |
| `changed PKG --since OLD` | words added, removed, and moved (code, or doc and names only) | `changed_answer` |
| `golden FILE` | G5: each `intent<TAB>word` line whose word is no longer `find`'s top hit | `golden_answer` |
| `ask NAME` | a named khipu question over blue's quads | `blue_quads`, `khipu::ask` |

blue's quads live under `urn:blue:` in the graph `urn:blue:snapshot:<root>`:
`def:WORD` with `rdf:type` Function, Value or Macro, `p:package`, `p:file`,
`p:line`, `p:defHash`, `p:gloss`, `p:reaches capability:C` and `p:calls`;
`test:FILE:LINE` with type Test or DocExample, `p:name` and `p:exercises`;
`rule:CODE` with type Rule, `p:slug`, `p:severity` and `p:law`. The question
`untested-network` is one basic graph pattern with one absent group:

```
?d p:reaches capability:network .  NOT EXISTS { ?t p:exercises ?d }
```

Measured 2026-11-09 on blue's tree: 5,966 definitions in 106 units.

The MCP door is blue end to end: `eigyou/kyuuji`'s `mcp_answer` speaks
JSON-RPC 2.0 (`initialize`, `ping`, `tools/list`, `tools/call`, notifications
unanswered), `mcp_handler` serves it as Streamable HTTP with JSON answers (no
stream), and `arika.b`'s `TOOLS` is the schema: `tool_list` renders the MCP
list from it and `tool_call` answers each tool through the CLI's own
`verb_answer`, so a tool's structured content is the CLI's `--json` answer.

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
| 3 | nix-built Parquet; `find`, `uses`, `changed`, `groups` through kueri; T3 with lgg witnesses; compression rank; CATALOG.md rendered from facts | blue (mokuroku, kueri, an arika level) | G5 (CLI), G7 | about 50 golden questions pass offline in CI. **2026-11-09:** the verbs BUILT in process over the facts (not yet through kueri or Parquet); 22 golden questions under G5; T3, the rank, CATALOG.md from facts and G7 open |
| 4 | `Language::Blue` in codesearch over `tree-sitter-blue`, one chunk per `def`; arika renders word chunks carrying the ID | codesearch | a `.b` fixture test with a red run without the language | `semantic_search` returns a `.b` chunk |
| 5 | GraphQL on `kyuuji`; MCP Streamable HTTP level in `eigyou`; the arika service (schema in blue, tools as persisted operations, T6 through codesearch HTTP, reload vigy); engenho release on ryn; `mcpServers.arika` in blackmatter-claude | blue (eigyou, toriyose), the `arika` repo, nix (`nodes/ryn`), blackmatter-claude | G5 (service), G8, G9, MCP conformance | a fresh session on ryn lists `blue_word_*` and answers the golden set with the CLI's bytes. **2026-11-09:** the MCP words in `eigyou/kyuuji` (not a new level), the blue schema and G8 BUILT; GraphQL, T6, the reload vigy (G9), the release and `mcpServers.arika` open |
| 6 | consumer repos loaded from the `tend` workspace; fleet root; cross-repo callers | the `arika` repo | coverage and consistency per repo | one query spans blue and at least 3 consumer repos |
| 7 | T4: a bounded e-graph canonical form under audited laws | blue | a property test per law; a node budget with a red run | near groups collapse with 0 false merges on the golden set |

Phase 5 starts by proving the ola-mundo pod runs on ryn's engenho. That was not
verified on 2026-11-06. Phases 1-4 need no engenho.

## Gates and their red runs

| Gate | Proves | Red run |
|---|---|---|
| G1 `arika-fresh` (BUILT: `checks.generated-arika-snapshot-fresh`) | the committed header equals the nix-built one, byte for byte; `emit_is_byte_identical_for_the_same_tree_wherever_it_lies` locks the determinism of header and facts | edit a def, do not regenerate; for the test, write absolute paths into rows |
| G2 `arika-coverage` (BUILT: `every_definition_is_one_leaf_with_its_facts_g2`, and `emit` refuses) | leaves equal every definition the engine sees (5,737 in `bidamas/`, 2026-11-06) | drop one leaf in the emitter: `emit` raises `arika_coverage` |
| G3 `arika-word-shapes-parity` (BUILT: `every_word_shapes_row_is_a_fact_row_with_the_same_home_g3`) | each `WORD_SHAPES` prefix matches a fact row with the same home, and every fact row of 12 nodes or more has a table row | a table row that no longer matches: editing `shomei` without regenerating the table named 5 rows |
| facts parity (BUILT: `like_from_the_facts_answers_as_the_engine_does`, `word_from_the_facts_finds_what_the_engine_finds`) | `like --snapshot --facts` gives the in-process answer for every fixture word, T0, T1 and T2; `word` from the facts keeps the engine's names, parts and old spellings | read T1 from the computed shape instead of the written one |
| stale facts (BUILT: `facts_that_do_not_hash_to_the_header_are_refused_as_blind`, and a blue test in `arika.b`) | facts whose root is not the header's are answered `blind`, for `like` and `word` | skip the root check: the edited fact is answered as found |
| G4 `arika-b0070-parity` (BUILT: `crates/blue-lang-cli/tests/arika.rs`) | `like` and B0070 name the same word for every definition of 12 nodes or more; below that B0070 is silent by design and `like` still answers | match on the written shape instead of the computed one: G4 and two more tests go red |
| G5 `arika-queries` (BUILT for the CLI and the tool: `the_golden_questions_keep_their_top_hit_g5` over `crates/blue-lang-cli/tests/arika_golden.tsv`, and `the_mcp_door_lists_the_rendered_tools_and_answers_a_call_as_the_cli_does`) | the golden questions keep their top hit, on CLI and service | remove one gloss |
| G6 `arika-proof` (BUILT: `bidamas/shomei/shomei.b` tests) | `ct_proof` verifies for every leaf; `ct_root` for 0-9 leaves and every proof of a 7-leaf tree equal tameshi `61c77f8` (`compute_leaf_root`, `leaf_inclusion_proof`) | flip the leaf domain byte: 3 tests go red |
| G7 `arika-consistency` | snapshot n+1 extends n; `seq` grows | reuse a `seq` |
| G8 `arika-schema-fresh` (BUILT for the tool list: `generate("arika-tools")` writes `docs/arika-tools.json` from `TOOLS`, checked fresh by nix and by the MCP test; the SDL waits on GraphQL) | SDL and tool list are rendered from the blue schema | hand-edit the SDL |
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
| header, facts + emitter | `bidamas/SNAPSHOT.json`, `gen/arika.b`, `gen/arika-facts.b` (`packages.arika-facts`), `crates/blue-lang-mondou/src/facts.rs`, `shomei::ct_*` | built (Phase 2) |
| agent guide | `docs/agents.md` (renders `CLAUDE.md`, `AGENTS.md`, `llms-full.txt`) | generated, gated fresh |
| skills | `blackmatter-pleme/skills/bidama` (step 1), `blackmatter-pleme/skills/arika` (maintenance) | advisory |
| org pointer | `blackmatter-pleme/docs/pleme-io-CLAUDE.md` HOUSE STYLE "Find before you write blue" | advisory |
| knowledge note | `nix/docs/knowledge/pleme-io/blue/` | recall |
| repo declaration | `pangea-architectures/workspaces/pleme-io-opensource/org.yaml` | declared, not applied |
| CLI + rule | `crates/blue-lang-cli/src/arika.rs`, `crates/blue-lang-cli/blue/arika.b`; B0070's explanation names arika | built |
| PreToolUse hook | `blackmatter-pleme/module/default.nix`, `blue arika like --hook` on `Edit\|Write\|MultiEdit` | built |
| full text + MCP | `bidamas/junni`, `bidamas/eigyou/kyuuji` (`mcp_*`), `TOOLS` in `arika.b`, `docs/arika-tools.json`, `gen/arika-tools.b` | built (2026-11-09) |
| still to come | `mcpServers.arika` (Phase 5), engenho release in `nix/nodes/ryn` (Phase 5) | — |

When a phase ships, update its row here, the roadmap tier, the skill text and
the knowledge note in the same pass.
