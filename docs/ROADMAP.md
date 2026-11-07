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
| **arika**: blue's word search | [`ARIKA.md`](ARIKA.md), `theory/ARIKA.md` | Phases 1 and 2 BUILT for blue's own tree (G1-G4, G6); the rest DESIGN | Phase 2's open rows (the `arika` output for other projects, mokuroku on the facts), then Phase 3: Parquet and `find` | namespaces (tree paths in IDs); verbs (the `sakuin` space for T5) | G1-G9 green on main; a session on ryn answers the golden set through `blue_word_*` |
| namespaces | [`NAMESPACES.md`](NAMESPACES.md), `theory/BLUE-NAMESPACES.md` | SHIPPED (reconciled 2026-11-06 at `cc9a1a1e`: `blue census` measures B0076, B0077 and B0078 at 0, ratchet 0; tree 10 landed) | close the flat-era `legacy_names` windows at each root's next minor | — | B0076-B0078 at error with corpus count 0 |
| absence | [`ABSENCE.md`](ABSENCE.md) | DESIGN (reconciled 2026-11-06: only P0, the document; no `umu`, no `absence.rs`, no `BLUE_ABSENCE`, B0054/B0055 reserved) | P1: `umu` and B0054/B0055 at audit | — | the doc's seal tier row |
| safety | [`SAFETY.md`](SAFETY.md) | PARTIAL (reconciled 2026-11-06: 19 rows, 6 sealed, 10 partly, 3 open; the blackhole is row 19) | rows 1, 3 and 14, the open ones | — | each SAFETY row at its stated seal tier |
| testing | [`TESTING.md`](TESTING.md) | UNRECONCILED | reconcile against the §16 tier ledger | — | the §16 ledger |
| registry | [`REGISTRY.md`](REGISTRY.md) | UNRECONCILED | reconcile against main; give the gate a way to fail | — | a registry check that exits non-zero on an absent pin (`blue registry status` reports and never fails, so it gates nothing) |
| blue on sui | `theory/BLUE-STRUCTURE.md` §5.3, `theory/SUI-FLIP.md` | UNRECONCILED | reconcile; mark §5.3 superseded (§ Rulings R1) | — | to be stated at reconcile |
| frontend | [`FRONTEND-PLAN.md`](FRONTEND-PLAN.md), `theory/BLUE-FRONTEND.md` | UNRECONCILED | reconcile against main | — | to be stated at reconcile |
| verbs | [`VERB-ROADMAP.md`](VERB-ROADMAP.md) | DESIGN (its own measured tier line, 2026-10-22) | reconcile | — | `blue verbs check` against its baseline |
| **khipu**: the knowledge graph (OxiRS naturalized) | [`KHIPU.md`](KHIPU.md) | K1a BUILT (`bidamas/khipu`: terms, N-Triples, N-Quads), the rest DESIGN | K1b: quads in DuckDB through `kueri`, basic graph patterns, the W3C syntax suites against Oxigraph | kueri; arika (shares the rule engine and snapshots) | the W3C suites of K1-K4 green as a differential against Oxigraph |
| **utsushi**: history projection (Josh naturalized) | [`UTSUSHI.md`](UTSUSHI.md) | U1 BUILT (`bidamas/utsushi`), U2-U6 DESIGN | U2: workspace entries refused one by one; `exclude`; views | gitto | `josh-filter` id parity on fixtures; the round-trip law green |
| **async**: native async, the `heikou` space | [`ASYNC.md`](ASYNC.md) | DESIGN (processes built, async words absent) | A1: `net_wait` in the node loop, node-time timers, the context record, the virtual clock in `blue test` | blue-lang-proc; HTTP2.md P3 (`net_wait`) | the conformance set green at `schedulers(1)` and `schedulers(n)`, gates A-ontology to A-replay |
| **record**: a named structure in one line | `examples/17_records.b`, okite D0017 | SHIPPED (2026-11-06, blue `cc9a1a1e`) | — | — | `spec/rows/records.b` and okite's record laws green; B0079 at error |
| **guard return** | [`GUARD-RETURN.md`](GUARD-RETURN.md) | G1 BUILT (lowering, B0080, the formatter keeps the guard), G2 DESIGN | G2: the language server and the tree-sitter grammar know `return`; a `return` inside `rescue` | — | R-lower, R-refuse, R-total green (G1); editors highlight it (G2) |

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
| 3 | Parquet plane, full CLI, T3 witnesses, CATALOG.md from facts | DESIGN |
| 4 | codesearch indexes `.b` | DESIGN |
| 5 | GraphQL + MCP HTTP service on ryn's engenho | DESIGN |
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
