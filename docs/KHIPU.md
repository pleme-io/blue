---
kind: explanation
summary: khipu, blue's knowledge graph, DESIGN: OxiRS's essence naturalized, the recon, the typed terms, the phases, the parity gates and the tier ledger
---

# khipu: blue's knowledge graph, the design of record

**Tier (2026-11-06): K1a BUILT, the rest DESIGN.** khipu is the
naturalization of OxiRS (https://github.com/cool-japan/oxirs, v0.4.1): an RDF
quad store, a SPARQL query and update engine, rules and shape validation, in
blue. It keeps the problem and the good ideas. It vendors no OxiRS code and
speaks no OxiRS API. K1a is `bidamas/khipu`: the term sum, quads, and
N-Triples and N-Quads read and written, each line judged alone (21 tests).
K1b is the DuckDB store, basic graph patterns and the W3C syntax suites. The
roadmap row is the khipu track in [`ROADMAP.md`](ROADMAP.md).

**The name.** A khipu is the Andean record of knotted cords: each knot is a
fact, and a cord hangs from a cord. That is a graph of statements.

## Destination

khipu is the one place a pleme-io system keeps facts about things as
subject, predicate, object and graph, asks them with SPARQL, derives new facts
with rules, and judges them against shapes. Every answer carries the dataset's
content hash. A bad term, an unbounded query, an unstratified rule set and an
unknown constraint each have no way to answer "ok". The store is DuckDB
through `kueri`, so blue writes the algebra and DuckDB does the joins.

arika's typed facts (`theory/ARIKA.md` §2) are the first tenant: the same
rule engine, the same Merkle snapshot, the same GraphQL face.

## What OxiRS teaches

Measured 2026-11-06 from its repository, its `TODO.md` and its
`core/oxirs-core/Cargo.toml`.

| Good idea | khipu keeps it as |
|---|---|
| store, query, rules, shapes and GraphQL in one program | one bidama tree: `khipu`, `khipu/sparql`, `khipu/ritsu` (rules), `khipu/kata` (shapes) |
| GraphQL schemas generated from an RDF vocabulary | `toriyose/outou` schemas rendered from a vocabulary graph |
| RDF 1.2 triple terms as first-class values | a variant of the term sum from Phase 1 |
| incremental shape re-validation | judge only the focus nodes a change touched |
| a Fuseki-compatible protocol | the SPARQL 1.1 Protocol and the Graph Store Protocol on `eigyou/kyuuji` |

| Leak in OxiRS (its own TODO) | khipu makes it |
|---|---|
| SPARQL-based SHACL constraints return `Ok(true)`, so they always conform | an unknown or unbuilt constraint is `blind`; `blind` is never `conforms` |
| the W3C harness compares terms with `==`, no blank-node renaming | results compared under graph isomorphism (RDFC-1.0) |
| 2PC participants and saga steps simulate success | no transaction claim without a durable commit; Phase 1 writes through DuckDB's own transaction |
| conformance numbers reported by the project itself | parity is a differential against Oxigraph on the W3C suites, in CI |
| `UPDATE USING` fails at parse time | a feature that is not built is refused by name, never parsed into a wrong plan |

The term model and parsers of OxiRS are Oxigraph's crates. So the RDF core is
not an OxiRS idea. The ideas specific to OxiRS are the shapes, rules, GraphQL
and federation planning.

## Recon: what blue already has

| Capability | Existing primitive | Gap |
|---|---|---|
| HTTP service | `bidamas/eigyou/kyuuji` | the two SPARQL protocols, content negotiation |
| GraphQL | `bidamas/toriyose/danpen` (parse, validate), `toriyose/outou` (execute) | schema from a vocabulary, resolvers over quads |
| SQL over DuckDB | `bidamas/kueri` (typed query model, `kueri::run_at`) | lowering SPARQL algebra; recursive CTEs for paths |
| graph walks | `bidamas/gurafu` (`reachable`, `topo`) | none for stratification; `topo` already refuses a cycle |
| refusals | `bidamas/kyohi`, the found / empty / refused / blind outcomes | none |
| entry-by-entry judgement | `bidamas/kousei`, `bidamas/ronri` | the SHACL core vocabulary |
| hashing | `blake3`, `bidamas/shomei` | RDFC-1.0 canonical labels |
| JSON, XML | `bidamas/deeta`, `bidamas/maakuappu` | JSON-LD and RDF/XML mappings |
| parsers | `toriyose::danpen` is the hand-written template; `kiwari` emits tree-sitter only | the RDF grammars |

About 20% of OxiRS's essence exists: the faces (HTTP, GraphQL, JSON,
hashing, refusals) at 60-70%, the core (terms, store, query, rules, shapes)
near 0%.

## The typed core

- **A term is one of five.** `iri(text)` (RFC 3987, refused at parse),
  `blank(scope, label)` (the scope is the source graph's hash, so a label
  cannot escape its document), `plain(text)`, `lang(text, tag)` (a BCP 47 tag,
  refused at parse; the datatype is `rdf:langString` by construction) and
  `typed(text, datatype)`. A literal with both a tag and a datatype has no
  constructor. `triple(s, p, o)` is the RDF 1.2 triple term.
- **A term's id is its hash.** BLAKE3 of the term's canonical bytes, so the
  dictionary is content-addressed and two loads agree on ids.
- **A query has a budget.** Rows, path depth and SERVICE depth are required
  fields with defaults. A query past its budget answers `refused` with the
  bound it hit, never a partial result read as complete.
- **A rule set is stratified or refused.** Rules with negation or aggregates
  are ordered by `gurafu::topo`. A negative cycle refuses that rule set alone,
  naming the cycle; other rule sets still run.
- **A shape is entries.** Each SHACL core constraint is a `kousei` entry,
  judged alone. Recursive shapes are refused. A constraint khipu does not
  implement answers `blind`.

## Phases

No phase builds what a later phase throws away.

| # | Deliverable | Gate | Exit |
|---|---|---|---|
| K1 | the term sum; N-Triples and N-Quads in and out; quads in DuckDB through `kueri`; basic graph patterns | the W3C N-Triples and N-Quads syntax suites, differential against Oxigraph | every positive test parses, every negative test is refused |
| K2 | Turtle and TriG; SPARQL SELECT, ASK and CONSTRUCT over BGP, OPTIONAL, UNION, FILTER, property paths; budgets | the W3C SPARQL 1.1 query suite subset, results compared under isomorphism, Oxigraph as oracle | the subset passes; every unbuilt feature is refused by name |
| K3 | `khipu/ritsu`: stratified semi-naive Datalog over DuckDB tables; RDFS and OWL 2 RL as rule sets | rule-set fixtures with a red run (a negative cycle) | arika's call graph and a vocabulary close to a fixpoint |
| K4 | `khipu/kata`: SHACL core | the W3C SHACL core suite | each test passes or is `blind` with its reason; none is `conforms` falsely |
| K5 | the SPARQL Protocol, Graph Store Protocol and a generated GraphQL schema as a blue `service(...)` | protocol fixtures; a service test | a running service answers the golden queries |
| K6 | SPARQL Update; RDFC-1.0 dataset hashes; snapshots shared with arika | update suite subset; canonicalization test vectors | a dataset hash is stable across load order |

## What blue lacks (host primitives)

| Need | Why | Where it goes |
|---|---|---|
| DuckDB in process | `kueri` runs the `duckdb` binary: no prepared statements, streaming or cross-call transactions | a `blue-lang-host` seam, after K2 measures the subprocess cost |
| regex | `sh:pattern`, SPARQL `REGEX` | `moji::pattern` (DESIGN in `STDLIB.md`) |
| arbitrary-precision decimals | XSD `decimal` and `integer` | a numeric host primitive |
| streaming reads | multi-GB N-Quads | `fairu::stream` (DESIGN) |

Vectors and embeddings stay with codesearch (arika ruling R8).

## Tier ledger

<!-- tier-ledger -->

| OxiRS capability | khipu realization | tier |
|---|---|---|
| a literal with both a language tag and a datatype | no constructor in the term sum | truly-unrep |
| an invalid IRI or language tag | refused when the term is parsed | parse-time-rejected |
| a blank-node label escaping its document | the label's scope is part of the term | truly-unrep |
| an unbounded query | a required budget; past it, `refused` | only-mitigated (C2) |
| an unstratified rule set | `gurafu::topo` refuses that rule set | parse-time-rejected |
| an unbuilt SHACL constraint reading as conforms | `blind` is a distinct outcome | truly-unrep |
| SPARQL conformance | a differential against Oxigraph on the W3C suites | only-mitigated (C2) |

C2 is the external-world ceiling: the budget and the oracle are measured
facts about runs, not types.

## Risks

| Risk | Mitigation |
|---|---|
| blue's immutable maps copy a large graph | the hot data stays in DuckDB; blue holds plans, not quads |
| the `duckdb` subprocess is too slow per query | K2 measures it before the host seam is built |
| two rule engines, khipu's and arika's | one engine, `khipu/ritsu`; arika is its first tenant |
| claiming "we replaced OxiRS" | parity is only the differential rows that are green |
