# H: the verb GRAPH as data blue owns (META region)

Read: STDLIB §0-§11, mokuroku (text scan, CATALOG.md, `name_collisions`), okite (`decisions()` with laws),
hadome (`judge`: Unrecorded/Held/Grew), kousei, `docs.rs` `NAMES`, `rules.rs` `Rule`, `spec/rows`,
CONVERGENT-EVIDENCE, JOEIRA §6.2. Files here: `verbs.tsv` and `edges.tsv` (30 rows each, loaded
unchanged by `queries.sql`, which ran green under duckdb: 16 absent verbs, 1 orphan, 3 shape divergences).

Destination: the vocabulary is ONE graph in blue source; TSV, DuckDB tables, VERBS.md, REFERENCE rows,
LSP answers, skeletons and lint rules are renderings. Code without a row fails the build; a row without code is counted debt.

## 1. Where it lives and the record shapes

**Home: `bidamas/mokuroku/graph/`**, one blue file per space plus `vocab.b`. This extends STDLIB §5.1
(`mokuroku/verbs.b`) instead of adding a bidama: mokuroku already scans packages, renders, and owns
collisions, so no new name needs the `naming` sweep. One file per space avoids seven regions
conflicting in one file; edges live in the file of their `from`. `blue verbs export` is the only
writer of TSV. Row files are evaluated under a **graph frame**: the only names bound are the row words
below (same mechanism as a Bluefile's `WORDS` and `project_rules`), so a row file is safe by frame.
The package ties to its rows with the Bluefile word `space("fairu")` (STDLIB §5.1; one `WORDS` row in
`blue-lang-pkg` plus one row in `nix/project.nix`, because the engine refuses unlowered words).

```ruby
vocab(:read, {meaning: "the whole content of a source", shape: "read(source, opts) -> content",
              rets: [:text, :bytes, :value, :record], raises: [:not_found], laws: [:write_then_read]})
space("fairu", {gloss: "files and paths", status: :ratified})        # kakuritsu? => status: :provisional
verb("fairu", :read, {kind: :effect, shape: "read(path, opts) -> text", laterals: [:error, :capability],
                      fleet: nil, today: "partial:shisutemu", meaning: "whole content of a file",
                      wave: 0, origin: "B"})
edge("deeta::read", :composes, "fairu::read", "get the file text first")
lateral(:retry, {battery: "heikou"})        raw(:exec_capture, "shisutemu::capture")
activity("http-client", {domain: :network, repos: 112, evidence: "reqwest dep, STDLIB 11a", verbs: ["tsuushin::request"]})
```

**Node = `space::verb`.** Authored columns are exactly the brief's: `region space verb kind shape
laterals fleet blue_today meaning wave` (`region` is stored as `origin`, `blue_today` as `today`; the
exporter restores the names). Authored extras with defaults: `enabled: true`, `replaced_by: nil`.
Derived, never authored (blue computes them, so they cannot lie): `id`, `npos` and `has_opts` and
`ret` (parsed from `shape`), `doc_ok` (mokuroku entry has its doc line), `laws` (from the master `vocab`
row), `tests` (mokuroku test count), `impl` (the package defines the name at an arity inside the shape).
**Same verb name = same family, not an edge.** `deeta::read` and `fairu::read` are one vocabulary
entry (`vocab(:read)`) seen in two spaces; an edge between them is red unless it is `composes`/`requires`
(a layer using the layer below). This is the verb-law matrix: columns are spaces, rows are `vocab` verbs.

**Edge = `from rel to why`**, the eight relations, validated against the closed `rels` list:

| rel | shape rule | algebra |
|---|---|---|
| `inverse` | any two verbs | involution: each verb has at most one partner, stored once, read both ways |
| `composes` | from built from to | DAG; `to` has wave at most `from`'s wave |
| `refines` / `generalizes` | one stored (`refines`), the other derived | a partial order; no cycle |
| `requires` | precondition | DAG together with `composes`; same wave rule |
| `lifts` | `kind(from)=stream`, `kind(to)` in effect/pure | functional: one stream form per batch verb |
| `guards` | `from` is a predicate (`name?`) or `pure` | `guards` target is an effect |
| `pairs` | symmetric | stored once |

The importer canonicalises both directions of `refines`/`generalizes`/`inverse`, so the seven regions load
unchanged. Round-trip law: `export(import(tsv))` equals the sorted `tsv` (DuckDB `EXCEPT` both ways).

**Configured off, never deleted.** A retired or contested verb is `enabled: false` with `replaced_by`;
it keeps its row, laws and tests. A provisional space (`kakuritsu?`) has `status: :provisional`: its
rows are checked by every graph gate except the implementation matrix, and may not hold wave 0 or 1.
Naming it (the `naming` skill) flips one field.

## 2. The invariants as gates (each gets a red run before it lands)

Homes: **R** = a `RULES` row in `blue_lang_check` (sees blue source, runs in `blue check`/LSP),
**O** = an okite decision with laws (data in, `true` out, runs in okite's own tests), **N** = a nix
check (`checks.bidama-verbs`, `checks.verb-laws`, `checks.verb-graph`; a blue program over rows),
**S** = a spec row (only for Rust primitives; evaluators must agree). The same G-queries live in
`queries.sql` as the analysis face and a cross-check: a fixture of bad rows must yield identical findings
from the blue gate and the SQL (a pair of tests, so neither is a tautology of the other).

| # | Invariant | Home | How it is detected | Red run (break it, see it named) |
|---|---|---|---|---|
| G1 | one meaning per verb | N + O | ordered meaning tokens (stop words dropped) equal for two different verbs of one space with no `refines`/`generalizes`/`inverse` edge; plus a `synonym` table of banned spellings (`fetch` for `get`, `remove` for `delete`); plus the same final shape and laterals under two names (convergence signal, CONVERGENT-EVIDENCE: report as "merge or justify") | add `fairu::slurp` meaning "whole content of a file": names `read`/`slurp` |
| G2 | closed vocabulary | N + R | a space `verb` row whose name has no `vocab` row (N); a public def in a space package that is no row, helpers excepted via a ratchet list (R `verb-not-in-graph`, STDLIB §5.2 item 2) | declare `:fetch` on fairu; define `fairu::glob2` |
| G3 | short-name rule | R `verb-name-shape` | one lowercase word, optional `?`, optional `verb_noun` only when the noun is in the space's declared nouns; no `is_`, `_or`, `try_` (STDLIB §2.1, §8) | rename to `read_or`, `is_file` |
| G4 | `composes`/`requires` acyclic, wave-monotone | N + O | DFS over rows; `to.wave <= from.wave` | add `fairu::read composes deeta::read` |
| G5 | every verb has doc + law + test | N | `doc_ok and laws>0 and tests>0` for each `enabled` verb with `today` in exists/partial; verbs with `absent` are exempt but counted | delete a doc line; drop a law name |
| G6 | every lateral edge resolves | N | `laterals` names are in the closed `lateral` rows; each lateral has a `battery` that is a bidama in `catalog_of`; a verb touching `retry` must have `heikou` reachable via `requires` or a `pairs` edge | list `retry` on a verb, delete `heikou` |
| G7 | `inverse` symmetric/involutive | O | stored once and read both ways, so asymmetry is unrepresentable; the import check fails a TSV with `a inverse b` and `b inverse c` | add `jisho::put inverse jisho::has?` |
| G8 | same-named verbs, same shape across spaces | N (`verb-laws` matrix) + R `verb-arity` | `vocab.shape` fixes positionals, options-last and the allowed `rets`; each space row must match; the package def's arity must sit inside it (R, STDLIB §5.2 item 1); laws run per space with its adapter (STDLIB §5.3) | give `habu::delete` a third positional |
| G9 | edge endpoints exist, relation in closed set, no same-name edge | N | join to nodes | `edge("fairu::rd", ...)` |
| G10 | graph and code agree | N + R | `impl` true for every `exists`; `today: absent` while the package defines the name is red (the row lies); builtin rows agree with `docs::NAMES` (S: existing `reference.rs` both-ways test, extended to name `vocab` verbs) | define `fairu::list` without flipping the row |

R rules start as ratchets (`ratchet: Some(n)`, counted by `blue census`) and become errors at zero
(STDLIB §8), each with a witness and explanation. A law about a Rust primitive gets a spec row; every
other law is a blue property test in a space adapter (okite's `values(seed, n)` supplies the cases).

## 3. Generation from the graph

| Output | How | Gate |
|---|---|---|
| `docs/VERBS.md` | `generate("verbs", "docs/VERBS.md", ...)` in the root Bluefile: the matrix (verb x space), then per space shape, laterals, wave, edges | `generated-verbs-fresh`; `nix run .#regen` |
| `blue reference` rows | the renderer takes `docs::NAMES` (builtins) union enabled graph verbs; same row type (name, signature, doc) | the existing two-way comparison, extended |
| LSP completion and hover | mondou holds the table (`id`, shape, meaning, laws, edges); completion after `fairu::` lists the space's verbs, hover shows shape + meaning + laws + `composes` parents; code action "add missing verb" for a matrix hole | an LSP test per answer kind |
| skeleton bidama per space | `blue verbs scaffold fairu` writes `fairu.b` with every enabled verb as a stub that `raise :not_implemented`, its doc line, its four tests (STDLIB §2.8) and its law call, so a new space starts red-by-row, not blank | the stubs fail G5 until filled: the skeleton IS the to-do list |
| suggestion engine | a lint over the resolved tree (`blue ast --resolved`, mondou `def_hash`): (a) a call to a `raw` name (`exec_capture`, `getenv`) suggests the verb; (b) a def whose callee set contains all `composes` targets of verb Y suggests "Y exists"; (c) a def whose shape and laterals equal a verb's suggests the verb. The `raw` table is data, so one `RULES` row (`raw-for-verb`) replaces STDLIB §8's six hand-written steering slugs | each suggestion kind has a witness; ships as warnings under a ratchet |
| TSV and DuckDB | `blue verbs export` writes verbs.tsv, edges.tsv, laterals.tsv, activities.tsv; analysis is `duckdb < queries.sql` | round-trip law |

## 4. The verbalization coverage metric (a ratchet, JOEIRA §6.2)

Three numbers, never blended into one score, each with its denominator and date printed on every run
(a zero denominator is red: anti-vacuity).

* **V1, sites (exact, code-derived).** Denominator: every resolved *operation site* in the blue corpus
  (the STDLIB §9 method: `blue ast --resolved --json` over every `.b` file under the fleet, worktrees
  and `spec/` excluded). An operation site is a call to a host-effect builtin (names whose topic is
  File/Process/Network/Nix or that carry a `Capability`), or to a space verb, or inside a hand-rolled
  wrapper (a def whose body calls a `raw` name). Numerator: sites whose callee is an `enabled`
  `space::verb` that passes G5 and G10. The rest are *raw sites*. Re-measured each run, never recorded
  as an estimate.
* **V2, activities (the horizon).** Denominator: a taxonomy of what pleme-io programs actually do,
  measured not invented: `activity` rows keyed by the external capability a program uses, weighted
  by `repos` (the count of repos depending on it: STDLIB §11a already counts serde 473, tokio 249,
  clap 244, tracing 232, reqwest 112, kube-rs 37 ...), plus the `def...` keywords of tatara-lisp
  domains (595 `TataraDomain` derives, STDLIB §13). Numerator: activities with at least one
  `enabled` verb at `exists`. This is the "full software verbalization" number: it rises when a
  region's wave lands, and the 1,400-repo fleet is the denominator that keeps it honest.
* **V3, graph health.** Verbs passing G5 over enabled verbs; falls when a row is added without its law.

**Ratchet shape** (hadome kinds, joeira-ratchet when it lands; hadome is the blue rung):

| kind | key | size | direction |
|---|---|---|---|
| `raw-sites` | bidama or repo scope | raw site count | ceiling: grows is red |
| `unverbalized-activities` | taxonomy domain | activities with no verb at exists | ceiling |
| `verbalized-activities` | taxonomy domain | covered activities | floor (the direction flips, as JOEIRA names for floors) |
| `ungated-verbs` | space | verbs failing G5 | ceiling |

Total coverage: a scope present in the corpus with no baseline row is `unrecorded` and red, so a new
repo or bidama must be recorded on purpose. Down is banked by `blue verbs census --bank` (rewrites the
baseline lower); only a large unbanked shrink is red. Up needs a receipt naming a world fact or a measured
A/B. The number only rises because the ceilings only fall and the floor only rises.
**Not measured yet:** no baseline exists; the first run records one. Do not quote a percentage before it.

## 5. The queries (all in `queries.sql`, validated on the 30-row sample)

No implementation: Q1 (absent, by wave). Space divergence: G7-shape query (modal arity, options-last and
return class per verb name; sample result flags `habu::delete`, `jisho::delete`, `jisho::get`: real design
questions, since `kankyou::get(name)` has no store argument and `jisho::delete` is pure). Hubs: Q3 (sample:
`tsuushin::request` degree 6). Orphans: Q4 (sample: `rogu::info`). Longest `composes` chains: Q5 (recursive
CTE, depth 2 in sample). Laterals by verbs touching: Q6 (sample: `capability` 22, `error` 20, six laterals at 0:
config, migrate, resource, switch, test, time: unused batteries or missing verbs). Wave burn-down: Q7 (built,
partial, absent per wave). Plus Q8 requires-closure (what a verb drags in) and Q9 (a verb scheduled before
something it needs). Gate queries G0-G7 return zero rows when green.

## 6. Build order for the machinery (waves) and what is blue

| Wave | Delivers | Blue vs Rust |
|---|---|---|
| H0 | row words and graph frame; `graph/vocab.b` seeded from STDLIB §3; `blue verbs import/export`; gates G1, G2(N), G4, G7, G9 as one blue program; TSV round trip; load all seven regions and report duplicates | blue except one `WORDS` row and one `project.nix` row |
| H1 | `checks.bidama-verbs` and `verb-laws` (adapters in blue); G3, G8, G2(R) as RULES rows; `docs/VERBS.md` and `blue reference` union; G5, G6, G10 | blue + three RULES rows in Rust (the rule table is Rust by design) |
| H2 | census and V1/V2/V3, hadome kinds, `--bank`; `activity` seeding from the Cargo and lisp censuses; `raw-for-verb` rule | blue; the file walk stays blue unless measured too slow, then a Rust primitive |
| H3 | LSP completion/hover, scaffold generator (a blue macro `defspace`), suggestion engine (a), (b), (c) | LSP wiring in Rust (mondou answers from a table); the rest blue |
| H4 | convergence miner (two spaces, different verb names, equal shapes: propose a merge), fleet tatara-lisp domain mining, `blue verbs query` over DuckDB behind a blue surface | blue; DuckDB is an external tool used for analysis, never for gating |

Gating stays in blue (no duckdb in the nix sandbox). The SQL is the independent second implementation.
Risks: a variable command name hides the tool (STDLIB §9), so V1 undercounts raw process sites: state it each run. A G1 false positive is silenced by a `refines` edge, which states the relation.
