---
kind: explanation
summary: the roadmap to full software verbalization
---

# Blue verb roadmap: full software verbalization

Operator, 2026-10-22: *"extend bluelang batteries included nature by going to all of software engineering and building the language and verb graph and giving blue a development roadmap for full software verbalization."*

This document extends [`STDLIB.md`](STDLIB.md) (22 scripting spaces) to the rest of software engineering. The law has four parts. Each meaning has one short verb. Distinct meanings have distinct verbs. Larger verbs are built from smaller ones. Each verb has laws. The cross-cutting concerns are the laterals (error, retry, deadline and the others in §1). The graph's data model, gates and coverage metric are in [`verbs/H/DESIGN.md`](verbs/H/DESIGN.md).

The [Ledger](#ledger) shows what is built. §1 to §3 record the first measurement. DuckDB measured it on 2026-10-22 over the seven region tables in `docs/verbs/` (`duckdb -c ".read docs/verbs/queries/contracts.sql"`). Research agents wrote those tables from the existing docs, the catalogue and the fleet. The graph today lives as blue rows in `bidamas/mokuroku/graph/`, and `docs/verbs/merged/verbs.tsv` renders it. On 2026-11-09 it holds 2,809 verbs in 169 spaces: 414 exist, 212 are partial, 158 live only in Rust and 2,025 are absent.

## 1. The graph today

| Region | Covers | Verbs | Spaces |
|---|---|---|---|
| A | data, text, math, time | 578 | 30 |
| B | storage and state | 458 | 20 |
| C | network and distributed | 324 | 15 |
| D | security and trust | 343 | 20 |
| E | build, ship, run | 346 | 29 |
| F | observe, test, quality, process | 395 | 30 |
| G | interfaces, AI, devices, domains | 395 | 36 |
| **Merged** | | **2,839 rows, 2,744 distinct space::verb, 1,328 distinct verb names** | **163 (69 existing, 94 provisional)** |

- 4,529 relations: composes 1,311 · pairs 1,029 · requires 857 · refines 536 · inverse 297 · guards 297 · lifts 106 · generalizes 96. Every verb has at least one relation; there are no self-loops.
- Blue has **474 of the 2,839** verbs (17%), 167 partially, and 2,198 (77%) are absent.
- By wave: 619 · 743 · 870 · 543 · 64 for waves 0 to 4. Of the 619 wave-0 verbs, 461 already exist; **74 are genuinely to build now**.
- Kind: pure 1,399 · effect 1,166 · decl 211 · stream 63. Half the graph is pure, which is what blue is best at.
- Laterals touched, by verbs: error 606 · validate 422 · idempotent 266 · deadline 263 · time 236 · resource 220 · capability 187 · cancel 153 · serialize 135 · config 123 · log 123 · process 119 · retry 111 · cache 93 · test 77 · trace 52 · switch 52 · ratelimit 41 · migrate 27. Test, trace, ratelimit and migrate are the thin ones.

## 2. What the merge found

| # | Finding | Measure | Fix |
|---|---|---|---|
| 1 | **The shared verbs do not share a shape.** 222 verb names occur in three or more spaces; only 48 take the same number of positional arguments everywhere. `list` has 54 spaces and three arities, `get` 43 and three, `put` 25 and three. | `queries/contracts.sql` | Write the verb contract table first (H0). It makes the one-verb-per-meaning law concrete. |
| 2 | Regions overlap. 87 `space::verb` keys appear in two regions (`gitto` and `habu` in E and F, `gyouretsu` in A and G) and 15 spaces are defined by more than one. | `queries/defects.sql` | One owner per space. E owns `gitto` and `habu` as build tools; F owns them as review. Merge, keep the more specific row. |
| 3 | **Five contradictions in `composes`.** Mutual cycles: `jisho::keys` and `entries`; `shuugou::set` and `retsu::unique`; `chokkan::ask` and `choice`; `kazu::mod`, `floor` and `divmod`; `fairu::write` and `with_temp_file`. | `queries/graph.sql` | Name one primitive in each group. The other is built from it. |
| 4 | Seven existing verbs are referenced but not listed: `kankyou::get`, `kueri::ident`, `ran::stream_seed`, `saishikou::retrying`, `shisutemu::run`, `shuusei::deep_merge`, `shuusei::put`. 120 more edges point at `core::` master verbs. | `queries/defects.sql` | Add the seven rows. Give `core::` its own space of master verbs. |
| 5 | 21 duplicate relations. `inverse` is stored one way (248 of 297 lack the reverse). | `queries/graph.sql` | Deduplicate on import. The importer adds the reverse (`H/DESIGN.md`). |
| 6 | 94 provisional space names are unswept. Two worry me already: `shoumeisho?` sounds like `shomei` (proposed `inkan?`), and `ikou?` is near `jikou`. | | One naming pass over all 94, in batches by region, before any bidama is created. |
| 7 | The `blue_today` column drifted. Regions wrote `exists:<crate>`, `exists:builtin` and `partial:net`. | | Add one value, `rust:<crate>`: owned by Rust, no blue surface yet. |
| 8 | The lateral column drifted: `resume` appears as a lateral in 3 rows, and no such lateral exists. | | Map it to `cancel` or add it deliberately. |

## 3. The spine: what everything stands on

The build order comes from the graph. These are the spaces that the most other spaces build on (`queries/fanin.sql`):

| Space | Dependent spaces | Verbs | Exist today |
|---|---|---|---|
| `shomei` (hash, sign, verify) | 22 | 43 | 12 |
| `nisshi` (append-only record) | 12 | 62 | 22 |
| `fairu` (files) | 11 | 41 | 0 |
| `retsu` (lists) | 11 | 43 | 36 |
| `gitto` (git) | 10 | 47 | 0 |
| `gamen?` (views) | 8 | 34 | 0 |
| `moderu?` (models) | 7 | 18 | 0 |
| `jikan` (time) | 7 | 43 | 3 |
| `moji` (text) | 7 | 44 | 20 |
| `kobun?` (syntax) | 6 | 17 | 6 |
| `kagi?` (keys, entropy, encryption) | 5 | 30 | 0 |

`shomei::hash` alone has 42 relations. The cross-cutting `kyohi` ledger of error kinds comes first because every effect verb raises through it.

## 4. Phases

Each phase ends when its gates are green and the coverage ratchet has moved. A phase never waits on a later one.

**H0. Contracts and the graph machine.** Blue only; no new bidama.
- Write the verb contract table for the ~40 shared verbs (`list`, `get`, `put`, `read`, `render`, `parse`, `diff`, `check`, `watch`, `delete`, `plan`, `run`, `merge`, `need`, `update`, `query`, ...): arity, subject, options record, return, error. This resolves finding 1.
- Fix findings 2 to 8 in the data.
- Import the tables as blue rows in `bidamas/mokuroku/graph/` (design: `H/DESIGN.md`), with gates G1 to G10 and their red runs, and `docs/VERBS.md` generated.
- Record the first coverage baseline in `hadome`. No percentage is quoted until it exists.
- Exit: the gates run in CI and the contract table is a data file the gates read.

**H1. The spine.** The highest fan-in spaces, wave 0 and 1 verbs first.
- `kyohi` as the ledger of error kinds, then `shomei`, `nisshi`, `fairu`, `retsu`, `moji`, `jikan` (instants and durations as values), `deeta` (edit: put, update, delete, merge, patch, canonical, address), and `katachi?` (schema and validate).
- Unblockers, decided before this phase starts (see §5): TLS, an entropy capability, `kagi?`.
- The 74 wave-0 verbs not yet built land here.

**H2. Stores and conversation.** One store contract for `souko?`, `shuunou?`, `teeburu`, `sakuin?`, `genbo?`, `rokku?`; `tsuushin`, `kyuuji` routing, `heikou`, `kyoujin?` (breaker, bulkhead, bucket, once), `messeeji?` (ack, nack, park, seek).

**H3. Ship and observe.** `birudo?`, `paketto?`/`bajon?`, `tenkai?` and `kenkou?` (one rollout vocabulary), `kiban?` (plan and drift, with `apply` gated behind a reconciler), `kentei?` (snapshot, fixture, quarantine, shard), `keisoku?`/`tsuiseki?`/`rogu` (metrics, traces, logs), `hakkou?` (`breaking?` from the surface diff), `kobun?` and `gengo?` (blue's own tooling as verbs).

**H4. Surfaces and intelligence.** `gamen?` and `ugoki?` (views and the motion vocabulary mado is waiting for), `moderu?`, `dairi?`, `kensaku?`, `saiten?` (one `ask`, `call`, `search`, `score` for arnes, chokkan and codesearch), `bunsho?` (documents), `kinyuu?` (money), `chizu?` (geo).

**H5. Horizon.** The 64 wave-4 verbs (replicated log, gossip, hardware seams) and the Rust-only spaces that keep a blue surface (GPU passes, codecs, font shaping, the MMIO seam).

## 5. Operator decisions (made 2026-10-22: the recommended defaults)

1. **TLS.** Build TLS wave 2 as a pure-Rust provider behind `Capability::Network`: no C, rustls with a RustCrypto provider. No process boundary to a TLS proxy. Not started; it belongs to H1.
2. **Master verbs.** `check`, `advance`, `send`, `on`, `call` and `convert` are master verbs as written in `contracts.tsv`; the ten open contract rows are `decided` (`info` keeps both forms, `merge` is one verb with `gitto::merge` refining it, `apply` stays behind the reconciler, `verify` raises `tampered` and `verify?` is its Bool pair). `check` returns `[finding]`; its raising form is `kyohi::enforce`. Details: `verbs/names/RULINGS.md`.
3. **Entropy.** `Capability::Entropy` is built (2026-10-23): `random_bytes(n)` from the system source, `shomei::random`, `same?`, `mac` and `hash` for sha1, sha256, sha512 and blake3. `fuuin` is ratified (2026-10-31) with the threshold verbs realized (`generate` for a threshold group, `offer`, `sign`, `combine`, over the `mpc_threshold` capability); `random` and `derive` still wait and build on `shomei::random`.
4. **Space counts.** The naming rulings merge `assaku` into `asshuku` and `hakkou` into `rirezu`; the other overlapping pairs stay split with a stated split (`verbs/names/RULINGS.md`). The remaining review of E and G stays open.
5. **Scope of `blue_today: rust:<crate>`.** Still open.

## 6. How this stays honest

- Provenance: each region's `verbs.tsv`, `edges.tsv` and `REGION.md` are in `docs/verbs/<R>/`, unedited, so any figure above can be rechecked. `docs/verbs/merge.sql` loads them; `docs/verbs/queries/` holds the four analyses.
- The fleet column cites only what the agents read. Of region A's 578 rows, 66 name an owner. Treat `-` as "not read", not "none".
- `blue_today` is by name. Before a wave is planned, its rows are re-measured against the catalogue.
- The region tables were written in one pass by separate agents with one shared brief. Findings 1 to 8 are what that approach could not catch alone, which is why H0 comes first.

## Ledger

✅ built and tested · ⏳ in progress · ❌ not built

Measured 2026-11-09 on `docs/verbs/merged/verbs.tsv`, which `gen/verbs/verbs.b` renders from `bidamas/mokuroku/graph/`.

| Item | State | What makes it true |
|---|---|---|
| H0: the graph as blue rows | ✅ built | `bidamas/mokuroku/graph/` holds the rows. `gen/verbs/verbs.b` and `gen/verbs/edges.b` render `docs/verbs/merged/verbs.tsv` and `edges.tsv`. `gen/verb-graph.b` test "the committed graph loads without one refusal". |
| H0: findings 2 to 8 repaired in the data | ✅ built | `docs/verbs/merged/CHANGES.md` repairs a to h. The `rust:` value of `blue_today` exists (158 rows). |
| H0: the 94 provisional names swept | ✅ built | `docs/verbs/names/N1.tsv`, `N2.tsv` and `RULINGS.md` |
| H0: the verb contract table | ⏳ in progress | `docs/verbs/contracts.tsv` renders from the graph (`gen/verbs/contracts.b`): 286 rows decided, 93 from STDLIB, 4 open. |
| H0: gates over the graph | ⏳ in progress | `checks.verb-graph` runs G1, G2, G4, G7 and G9, each with a fixture that names its bad row. Its live probe checks that each `exists` row resolves and has a test. G3, G6 and G8 do not exist. |
| H0: the coverage baseline | ✅ built | `bidamas/mokuroku/graph/graph.baseline`; `gen/verb-graph.b` test "the committed graph breaks no gate beyond the debt it recorded" |
| H0: `docs/VERBS.md` rendered from the graph | ❌ not built | No generator writes `docs/VERBS.md`. |
| H1: the spine | ⏳ in progress | Wave 0 has 635 verbs: 343 exist and 17 are absent. The rest are partial or live only in Rust. Wave 1 has 723 verbs: 48 exist and 597 are absent. |
| H1: TLS | ❌ not built | No `rustls` in any crate. Done when a pure-Rust provider sits behind `Capability::Network`. |
| H1: entropy | ✅ built | `random_bytes` in `crates/blue-lang-runtime/src/provide.rs`; `shomei::random` in `bidamas/shomei/shomei.b` |
| H1: `fuuin` threshold verbs | ✅ built | `generate` and `combine` in `bidamas/fuuin/fuuin.b`, with its tests |
| H2: stores and conversation | ⏳ in progress | `bidamas/chozou` holds `teeburu`, `kiibariu` and `sutoriimu`. No one store contract joins the store spaces. |
| H3: ship and observe | ❌ not built | No `birudo`, `tenkai` or `rirezu` bidama exists. |
| H4: surfaces and intelligence | ⏳ in progress | `bidamas/gamen`, `bidamas/ugoki` and `bidamas/bunsho` exist. No `dairi`, `kensaku`, `saiten`, `kinyuu` or `chizu` bidama exists. |
| Waves 2 and 3 | ❌ not built | Wave 2 has 865 verbs: 22 exist and 830 are absent. Wave 3 has 523 verbs: 1 exists and 518 are absent. |
| H5: horizon | ❌ not built | None of the 63 wave-4 verbs exists. |
| Decision 5: the scope of `blue_today: rust:<crate>` | ❌ not built | The value exists in the data. Its scope is not decided. |
