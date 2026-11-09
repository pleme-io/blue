---
kind: explanation
summary: "khipu, blue's knowledge graph, DESIGN: OxiRS's essence naturalized, the recon, the typed terms, the phases, the parity gates and the ledger"
---

# khipu: blue's knowledge graph, the design of record

K1a is built. K1b's store and basic graph patterns are built (2026-11-09).
The W3C suites and the rest are not built. The [Ledger](#ledger) gives the
state of each item. khipu is the
naturalization of OxiRS (https://github.com/cool-japan/oxirs, v0.4.1): an RDF
quad store, a SPARQL query and update engine, rules and shape validation, in
blue. It keeps the problem and the good ideas. It vendors no OxiRS code and
speaks no OxiRS API. K1a is `bidamas/khipu`: the term sum, quads, and
N-Triples and N-Quads read and written, each line judged alone (11 tests).
K1b's first half (2026-11-09) is in the same file (6 tests). `load` writes a
store: one JSON row per distinct quad, each term in N-Triples. DuckDB reads
the store through `kueri`. `question` and `ask` answer a basic graph pattern
(one self-join per pattern) with absent groups (NOT EXISTS), DISTINCT and
ordered, under a required row budget. A run past the budget is refused as
`:khipu_budget`. `encoded` makes an IRI from any text. The first tenant is
blue itself: `blue arika ask untested-network` asks which definitions reach
the network and no test names ([`ARIKA.md`](ARIKA.md) § What Phase 3 and the
MCP door hold). K1b's second half is the W3C N-Triples and N-Quads syntax
suites against Oxigraph. The roadmap row is the khipu track in
[`ROADMAP.md`](ROADMAP.md).

**The name.** A khipu is the Andean record of knotted cords: each knot is a
fact, and a cord hangs from a cord. That is a graph of statements.

## Destination

khipu is the one place a pleme-io system keeps facts about things as
subject, predicate, object and graph, asks them with SPARQL, derives new facts
with rules, and judges them against shapes. Every answer carries the dataset's
content hash. A bad term, an unbounded query, an unstratified rule set and an
unknown constraint each have no way to answer "ok". The store is DuckDB
through `kueri`, so blue writes the algebra and DuckDB does the joins.

arika's typed facts ([`ARIKA.md`](ARIKA.md)) are the first tenant: the same
rule engine, the same Merkle snapshot, the same GraphQL face. Blue's own
ontology is the second ([`HORIZON.md`](HORIZON.md) H19): every concept of the
language a class rendered from the table that owns it, every law a shape, and
the tests generated from the shapes. Its first slice is capabilities.

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

## Ledger

✅ built and tested · ⏳ in progress · ❌ not built

| Item | State | What makes it true |
|---|---|---|
| K1a: the term sum, quads, N-Triples and N-Quads in and out | ✅ built | `bidamas/khipu/khipu.b`, 11 tests: "what is written reads back to the same quads", "one bad line is refused alone; comments and blank lines are skipped". |
| a literal with both a language tag and a datatype | ✅ built | Test "a literal with both a language tag and a datatype has no constructor and no reading". The term sum has no constructor for it. |
| an invalid IRI or language tag | ✅ built | Tests "an IRI that is not absolute, or holds a forbidden character, is refused" and "a language tag that is not BCP 47 is refused". The parser refuses it. |
| a blank-node label that escapes its document | ✅ built | Test "blank nodes keep their document: two documents' _:b are two nodes". The scope is part of the term. |
| K1b: quads in DuckDB through `kueri`, basic graph patterns, the W3C syntax suites against Oxigraph | ⏳ in progress | Built: `load`, `question`, `ask` and `encoded` in `bidamas/khipu/khipu.b`, tests "a basic graph pattern joins in DuckDB, and an absent group removes what it matches", "a literal with a quote and a tab survives the store", "encoded text is a valid IRI and decodes to itself". Missing: the W3C suites. Done when every positive W3C N-Triples and N-Quads test parses and every negative test is refused. |
| an unbounded query | ✅ built | A row budget is a required field of `question` (default `BUDGET`). Past it, `ask` raises `:khipu_budget` and never gives a partial answer. Test "past its budget a question is refused, never cut short". The budget is a measured fact about a run, not a type. |
| a question that answers a variable no pattern binds | ✅ built | `question_sql` refuses it. Tests "a question with no pattern, or an unbound answer, is refused" and "a pattern that could match nothing is refused where it is made". |
| K2: Turtle, TriG, SPARQL SELECT, ASK, CONSTRUCT; query budgets | ❌ not built | Done when the W3C SPARQL 1.1 subset passes against Oxigraph and every unbuilt feature is refused by name. SPARQL conformance is a differential against Oxigraph on the W3C suites, a measured fact about runs. |
| K3: `khipu/ritsu`, stratified Datalog; RDFS and OWL 2 RL | ❌ not built | Done when `gurafu::topo` refuses an unstratified rule set alone, naming its cycle, and arika's call graph closes to a fixpoint. |
| K4: `khipu/kata`, SHACL core | ❌ not built | Done when each W3C SHACL core test passes or answers `blind` with its reason. An unbuilt constraint never answers `conforms`: `blind` is a distinct outcome. |
| K5: SPARQL Protocol, Graph Store Protocol, GraphQL, as a blue `service(...)` | ❌ not built | Done when a running service answers the golden queries. |
| K6: SPARQL Update; RDFC-1.0 dataset hashes; snapshots shared with arika | ❌ not built | Done when a dataset hash is stable across load order. |
| DuckDB in process | ❌ not built | `kueri` runs the `duckdb` binary (`exec_capture`), so it has no prepared statements, streaming or cross-call transactions. A host seam comes after K2 measures the subprocess cost. |
| regex for `sh:pattern` and SPARQL `REGEX` | ❌ not built | `bidamas/moji` has no `pattern`. |
| arbitrary-precision decimals for XSD `decimal` and `integer` | ❌ not built | No numeric host primitive exists. |
| streaming reads for multi-GB N-Quads | ❌ not built | `bidamas/fairu` has no `stream`. |

Vectors and embeddings stay with codesearch (arika ruling R8).

## Risks

| Risk | Mitigation |
|---|---|
| blue's immutable maps copy a large graph | the hot data stays in DuckDB; blue holds plans, not quads |
| the `duckdb` subprocess is too slow per query | K2 measures it before the host seam is built |
| two rule engines, khipu's and arika's | one engine, `khipu/ritsu`; arika is its first tenant |
| claiming "we replaced OxiRS" | parity is only the differential rows that are green |
