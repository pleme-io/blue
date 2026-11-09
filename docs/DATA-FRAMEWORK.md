---
kind: explanation
summary: the design of the data framework, one blue model rendered to schema, migrations, queries and GraphQL with nothing written twice, and the research it rests on
---

# The data framework: one model, every rendering, nothing written twice

The pieces this framework composes are built. The compiler, the gates and
rungs D2 to D6 are not built. The [Ledger](#ledger) gives the state of each
item. This page holds the design and the research it rests on.

## Destination

Anything that has to be modeled is declared once, as a blue model, in its own
bidama. Storage, migrations, queries, the GraphQL API, the client's typed
fragments and cache, key-value and stream shapes, test gates and ontology
classes are renderings of it. SQL is never written by hand: it is a rendering
of `kueri`'s typed tree. One `use` gives a program the whole path.

## Research it rests on

Two surveys (2026-11-07): the systems that compile GraphQL or a model to a
database, and the programming-languages and database research under them.
Each idea below is adopted with the property it gives and how that property is
measured.

**Planning and execution**

- *Plan once, run many* (PostGraphile 5's Grafast,
  https://grafast.org/grafast/plan-resolvers): a plan cannot see input values,
  so one plan serves every call of an operation. Blue keys the plan by the
  operation's hash and the hashes of the model definitions it reads, so a plan
  is never flushed by hand and never served stale. Measure: change one field;
  the plans invalidated equal the plans that read it, no more.
- *Normalization* (Cheney, Lindley, Wadler, ICFP 2013,
  https://doi.org/10.1145/2500365.2500586): a first-order typed query normalizes
  to one SQL query. *Query shredding* (SIGMOD 2014,
  https://arxiv.org/abs/1404.7078): a nested result becomes a fixed number of
  flat queries, one per nested collection. *One statement by construction*
  (Gel, https://arxiv.org/pdf/2507.16089; Drizzle; Hasura,
  https://hasura.io/blog/architecture-of-a-high-performance-graphql-to-sql-server-58d9944b8a87):
  a nested JSON aggregate over LATERAL joins. One statement is not always
  fastest at high row counts (https://github.com/webNeat/sql-single-vs-multiple-queries),
  so the compiler picks the aggregate plan or the shredded plan per operation,
  and the count is a function of the result type, never of the data. Measure:
  fuzz nesting depth 1 to 6 and data size 1 to 10⁵; the statement log shows the
  count the type predicts.
- *A cost bound before execution* (static bounds in linear time,
  https://arxiv.org/abs/2009.05632): every operation carries an upper bound on
  the rows it can return, checked at build time. Measure: no operation's
  observed rows exceed its bound.

**Authority**

- *Authorization compiled into the same SQL* (Hasura row permissions; Zero's
  permission clauses): blue lowers the capability frame and the model's rules
  into the query's WHERE clause, and also into a Postgres RLS policy from the
  same source, so the database refuses what the compiler would. An operation
  without its frame does not compile. Object capabilities (Miller, 2006), Effekt
  (OOPSLA 2020) and the WebAssembly component model are the lineage. Measure:
  random frames and queries against an oracle filter; mutation tests that
  delete a rule must fail the build. RLS's known cliff, a per-row function call
  (https://supabase.github.io/splinter/0003_auth_rls_initplan), is a lint, and
  every rule's column must be indexed.
- *Trusted operations*: production runs only operations whose hash the build
  produced, and the hash is the operation's `def_hash`, so no manifest ships
  beside the deploy (Relay and Apollo use a separate id and an audit phase;
  automatic persisted queries are not a safelist,
  https://www.apollographql.com/docs/graphos/routing/persisted-queries).
  Measure: operations reaching the server without a build hash: 0.

**Change**

- *Grow only* (Datomic, https://docs.datomic.com/schema/schema.html): a rename
  is a new definition plus an alias, never a reused name.
- *Schema modification operators* (PRISM/PRISM++, Curino et al.): the only
  legal migration steps are a closed set of operators, each with a *lens*
  (Foster, Pierce et al., TOPLAS 2007; Cambria, Ink & Switch 2020) whose
  round-trip laws hold, and each run as *expand, then contract* with versioned
  views so two versions are live at once (pgroll; F1 online schema change,
  VLDB 2013). Contract waits until no live operation hash reads the old
  definition. Measure: property tests of the lens laws; destructive DDL emitted
  without a recorded zero-reader proof: 0.
- *Lint by class* (Atlas, https://atlasgo.io/lint/analyzers): destructive,
  data-dependent and backward-incompatible changes each have a code, and a
  forced class cannot be suppressed.

**Caching and incrementality**

- *Query-based incremental computation* (Salsa; "Build systems à la carte",
  Mokhov, Mitchell, Peyton Jones, ICFP 2018,
  https://doi.org/10.1145/3236774): each stage is a memoized query with early
  cutoff, keyed by BLAKE3 hashes (HORIZON H3's one store). An *interface hash*
  beside the body hash keeps a change inside a body from invalidating callers.
  Measure: an edit trace counts recomputed nodes.
- *Incremental view maintenance* (DBSP, Budiu et al., VLDB 2023,
  https://www.vldb.org/pvldb/vol16/p1601-budiu.pdf; Differential Dataflow;
  Noria, OSDI 2018): the `keifu` changelog is a stream of signed deltas, and a
  cached result is maintained, not invalidated. *Read-set invalidation* (Convex,
  https://docs.convex.dev/understanding/) comes for free, because the read set
  is known when the operation compiles. Live queries share one statement per
  cohort of the same shape (Hasura's multiplexing). Measure: maintained result
  equals a full recompute after every change; work grows with the delta; stale
  reads under a write fuzzer: 0.

**Proof**

- *Transparency logs* (Certificate Transparency, RFC 9162): the changelog is
  append-only, with inclusion and consistency proofs; a result carries a Merkle
  receipt over its rows (tameshi). Proofs cover inclusion and order, not the
  query's correctness; proofs of computation (folding schemes) are deferred as
  too costly.

**Macros**

- *Hygiene by sets of scopes* (Flatt, POPL 2016) and *typed staging* (Scala 3
  quotes; MetaOCaml): the `model` form expands before the check stage, with
  hygiene, and the expansion is checked. Blue's `defmacro` expands after the
  check and is not hygienic today, so the model macro waits on that.

## Failure modes it is designed against

From the systems survey, each with its counter here:

| Failure | Counter |
|---|---|
| JSON-aggregate memory and plan cliffs on large nested reads (Hasura issues) | plan choice per operation plus the static cost bound |
| RLS performance cliffs | the per-row-call lint and indexed rule columns |
| an engine whose memory grows with its metadata | the model compiles away; nothing interprets metadata at run time |
| breaking platform rewrites (Hasura 2 to DDN, Prisma Accelerate's retirement) | a bidama pinned by version and hash |
| an unbatched escape hatch brings N+1 back | no hand resolver over the database; a computed field is a typed, batched query |
| lint suppressions and data-dependent changes pass CI | forced classes cannot be suppressed |
| a persisted-query cache that accepts any operation | trusted operations by build hash only |

## Rungs

| Rung | Builds | Gate |
|---|---|---|
| D1 | teeburu → outou bridge; `/graphql` route; rubrica on it | rubrica's schema test, red run on an unknown field |
| D2 | the compiler: an operation to one `kueri` plan (aggregate or shredded), plan cache by hash, cost bound | statement count equals the type's prediction under fuzzing |
| D3 | frames and model rules into WHERE and RLS from one source | oracle filter over random frames; a deleted rule fails the build |
| D4 | migrations: the operator set, lenses, expand and contract, lint classes; haibi's text DDL replaced | lens laws; zero destructive DDL without a zero-reader proof |
| D5 | the keifu stream maintains caches (DBSP algebra); live-query cohorts | maintained equals recomputed; zero stale reads |
| D6 | the `model` macro, hygienic and checked; the framework's entry bidama, named by the naming procedure | capture tests; every expansion type-checks |

The order puts D1 first because rubrica needs it now, and D2 before D3
because authority compiles into the plan D2 produces.

## Ledger

✅ built and tested · ⏳ in progress · ❌ not built

| Item | State | What makes it true |
|---|---|---|
| model, version hash, `evolve`, `judge`, Postgres, `keifu` changelog | ✅ built | `bidamas/chozou/teeburu/teeburu.b`, 15 tests, among them "keifu renders one changeSet per change, escaped, outside a transaction where it must be". |
| key-value and stream shapes | ✅ built | `kv_model` in teeburu; `bidamas/chozou/kiibariu` (8 tests) and `bidamas/chozou/sutoriimu` (5 tests). |
| typed SQL tree rendered to DuckDB | ✅ built | `bidamas/kueri/kueri.b`, 31 tests; the Bluefile `query` word. |
| GraphQL documents and fragments | ✅ built | `bidamas/toriyose/danpen`, 32 tests. |
| GraphQL executor, `from_model`, SDL | ✅ built | `bidamas/toriyose/outou`, 18 tests. It resolves field by field: no plan, no batching. |
| normalized client store | ✅ built | `bidamas/toriyose/kyasshu`, 16 tests. |
| migration CR and additive SQL | ⏳ in progress | `bidamas/eigyou/haibi`, 22 tests. It renders text lines, not the operator set of D4. |
| content-addressed identity | ✅ built | `def_hash` (`crates/blue-lang-runtime/src/def_hash.rs`). |
| capability frames | ⏳ in progress | `crates/blue-lang-waku`: a frame per interpreter. A frame per bidama (HORIZON H13) is not built. |
| D1: teeburu → outou bridge; `/graphql` route; rubrica on it | ⏳ in progress | `from_teeburu` in outou; test "a teeburu model derives a schema: names cased, types mapped as data, an unmapped type and a clash refused alone". No `/graphql` route serves it. |
| D2: an operation compiled to one `kueri` plan, plan cache by hash, cost bound | ❌ not built | Done when the statement count equals the type's prediction under fuzzing. |
| D3: frames and model rules into WHERE and RLS from one source | ❌ not built | Done when an oracle filter agrees over random frames and a deleted rule fails the build. |
| D4: migration operators, lenses, expand and contract, lint classes | ❌ not built | Done when the lens laws hold and no destructive DDL runs without a zero-reader proof. |
| D5: the keifu stream maintains caches; live-query cohorts | ❌ not built | Done when maintained equals recomputed, with zero stale reads. |
| D6: the `model` macro; the framework's entry bidama | ❌ not built | Done when capture tests pass and every expansion type-checks. |
