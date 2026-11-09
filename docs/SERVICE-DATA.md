---
kind: explanation
summary: Postgres, Valkey and the nervous system as the configurable defaults of a blue service (design)
---

# SERVICE-DATA — Postgres, Valkey and the nervous system as defaults

Status: ⏳ in progress. The model steps, telemetry export, the RESP client and
JetStream are built. The [Ledger](#ledger) at the end says what else is built.
Measured over the 2 Bluefiles that declare a `service(...)` (kensa, ola-mundo)
of 14. This doc extends `BUILD-STACK.md` §3.1. The model's design is
`DATA-FRAMEWORK.md`: a model lives in its own bidama. The whole stack is
`SUBSTRATE.md` (2026-11-09).

## 1. Destination

A blue service gets a database, a cache, an event stream and full
observability by declaring them, with defaults that work unchanged and every
part configurable in blue. Postgres comes with a model, an ORM, versioned
migrations that shinka runs and kenshi gates; Valkey serves entity caches,
sessions, queues and pub/sub beside it; NATS JetStream carries the service's
events out and in, with change capture through an outbox or escuta; logs,
metrics and traces ship to the fleet's stores. All of it renders through
pleme-lib's primitives into the service's chart, ships with nix through
substrate, and runs on engenho or under Flux.

## 2. The words

```ruby
model("orders", {
  entities: {
    order: {key: :id, fields: {id: :uuid, total: :decimal, state: :text},
            indexes: [[:state]], relations: {customer: :customer},
            cache: {ttl: "5m", invalidate_on: :write},
            events: :publish}
  }
})

service("orders", {
  database:  {provider: :cnpg, instances: 2, pitr: true, migrator: :keifu},
  cache:     {provider: :pleme_cache, uses: [:entity, :session, :queue, :pubsub]},
  events:    {stream: "orders", publish: ["order.created", "order.updated"],
              subscribe: {"payments.settled" => :settle}, cdc: :outbox},
  observe:   {logs: :vector, metrics: :victoria, traces: :otlp, alerts: :slo},
  migration: {gate: :kenshi}
})
```

Every field has a default, so `service("orders", {})` with a `model` already
gets a database, migrations, a cache for its entities and observability;
`events` is off until a stream is named.

| Field | Default | Choices |
|---|---|---|
| `database.provider` | `:cnpg` on a cluster, `:node_socket` on a NixOS host (plo's native Postgres, peer auth) | `:cnpg`, `:node_socket`, `:external` |
| `database.engine` | `:postgres` | `:postgres` (primary), `:mysql` (keifu-core's other engine), more as each gets a native renderer (§2a) |
| `database.migrator` | `:keifu` (shinka applies it in process) | `:keifu` and every tool in shinka's set (`shinka/src/migrator/types.rs:15`), each a rendering of the same blue model (§2a) |
| `cache.provider` | `:pleme_cache` | `:pleme_cache`, `:external`, `:off` |
| `events.cdc` | `:outbox` | `:outbox`, `:escuta` (once escuta has a Postgres source) |
| `observe.*` | every signal on | each turned off alone |
| `migration.gate` | `:kenshi` | `:kenshi`, `:none` (typed reason) |

## 2a. Models evolve in pure blue (operator, 2026-10-27)

A data model and every change to it are written in blue and nowhere else.
SQL files, changelogs and ORM entities are renderings, made for whatever the
chosen migrator reads. Nobody writes a migration by hand.

| Part | Answer | Rejected |
|---|---|---|
| The model | `model(...)` is a blue value with a `version`. The Bluefile lock pins each version's hash | a schema file next to the code |
| A change | the diff of two model versions, computed in blue (`teeburu::evolve(from, to)`), as typed steps: `add_entity`, `add_field`, `rename`, `retype`, `add_index`, `split`, `merge`, `drop` | hand-written `ALTER` |
| Intent the diff cannot see | a rename or split is declared on the new version (`renamed_from: :old`); without it the judge refuses the drop-and-add pair, so no data is lost silently | guessing a rename from shape |
| Data backfill | a blue expression over kueri's typed SQL AST (`backfill: {total: sum(:lines, :amount)}`), lowered to SQL beside the DDL | row-by-row host code |
| Destructive steps | `drop` and narrowing `retype` need `allow: :destructive` on that one step; everything else in the version still applies | a global unsafe flag |
| Rendering | one blue renderer per migrator, chosen by `database.migrator`. The default is `:keifu`: a keifu changelog that shinka applies in process, with its ledger, checksums and witness. `:sqlx`, `:refinery`, `:diesel`, `:goose`, `:golang_migrate`, `:atlas`, `:dbmate`, `:flyway` and `:liquibase` each get their own directory or file form | a single SQL dialect for every tool |
| Native per backend | each typed step lowers to the backend's own fastest safe form, never a lowest-common-denominator SQL. Postgres is the primary target: transactional DDL, `CREATE INDEX CONCURRENTLY` (outside the transaction), constraints added `NOT VALID` and then `VALIDATE`d, `ADD COLUMN` with a constant default (no table rewrite), batched keyset backfills, and `lock_timeout` on every step. MySQL renders to online `ALGORITHM=INSTANT` or `INPLACE` forms. A step a backend cannot do natively is refused for that backend by name | one portable SQL for every engine |
| Valkey, loose | the server has no schema. A cache entry carries the hash of the model version it encodes in its key (`orders:v<hash>:order:<id>`), so after a model change reads go to new keys and old keys expire by TTL. No flush and no migration step | a cache migration job |
| Valkey, strict | a `kv_model(...)` (or `cache: {strict: true}` on an entity) is a schema at the blue layer: typed fields, the encoding (hash, JSON, stream entry), key pattern and TTL. Blue checks every write and every read against it and refuses a value that does not match. Evolution uses the same `teeburu::evolve` steps as Postgres. It renders to one of two Valkey forms: `upgrade: :on_read` (default; read the old version, transform it in blue, write the new version) or `upgrade: :eager` (a shinka job that walks the old keys with `SCAN` in batches, pipelines the rewrite and leaves the TTL as it was). Steps that Valkey cannot carry, such as indexes and relations, are refused for it by name | trusting whatever a key holds |
| Accessors | typed blue accessors are rendered from the same version (`orders::order::find`, `insert`, `update`) | ORM entities written by hand |
| Gate | `blue check` rejects a model change that has no version bump, a version with no lowering for the chosen migrator, or a lowering that changes once it has shipped (the checksum is pinned in the lock) | a review comment |

A transform that kueri's AST cannot express is a gap in kueri. Grow kueri
to cover it. Do not escape to raw SQL or Rust.

## 3. How each lowers

The chart side below is today's rendering. From 2026-11-09 typed objects are
the source, and each pleme-lib helper is configured off per chart as typed
rendering covers it (`SUBSTRATE.md` §7, L1.3).

| Battery | Blue side | Chart side (pleme-lib) | Operators |
|---|---|---|---|
| Postgres | `model` → versioned DDL diffs and typed accessors (teeburu grown on kueri's SQL AST); the runtime's `pg_connect`/`pg_query` | `pleme-cnpg-cluster` or `pleme-database` as a subchart, `_pitr.tpl`; `shinkaDatabaseMigration` and its wait init container instead of haibi's hand-written psql job | shinka runs the versioned migration; kenshi correlates it by the `kenshi.pleme.io/service` label and gates promotion |
| Valkey | a RESP client in `blue-lang-runtime` (`resp_connect`, `get`, `set`, `del`, `publish`, `subscribe`), cache keys and invalidation rendered from `model` | `pleme-cache` as a subchart (a hardened image instead of upstream `valkey/valkey`); TLS and the password file as today | — |
| Events | JetStream in the runtime's NATS client (ack, durable consumers); an outbox written in the same transaction as the change, drained to the stream; a subscription word that runs a handler under supervision | `pleme-lib.jetstream` streams and its init job; `pleme-nats` | escuta for log-based capture later |
| Observability | `rogu` to Vector, `tsuiseki` to OTLP, `keisoku` on `/metrics`, `shihyou` rules and dashboard | `pleme-lib.observabilityBundle`, `_alerts.tpl`, `_grafana.tpl` | the fleet stores: VictoriaMetrics, VictoriaLogs (fed by NATS), Grafana |

## 4. Build order

S1 to S6 are the build steps. Each one is a row in the [Ledger](#ledger), with
its state and its evidence.

## Ledger

The state of each step and each pending row, measured on 2026-11-09.

✅ built and tested · ⏳ in progress · ❌ not built

| Item | State | What makes it true |
|---|---|---|
| S1: haibi renders on pleme-lib's `shinkaDatabaseMigration`, the wait init container, `observabilityBundle` and `jetstream`, and emits the kenshi labels | ❌ not built | haibi names none of these (`bidamas/eigyou/haibi/haibi.b`). It still writes a full `schema.sql` apply every time |
| S2: model steps in `teeburu` | ⏳ in progress | `model`, `version_hash`, `evolve`, `judge`, `postgres`, `keifu`, `kv_model`, `kv_check` and `kv_upgrade` in `bidamas/chozou/teeburu/teeburu.b` (15 tests). Typed accessors, the lock pin and the `blue check` gate are missing (rows below) |
| S2b: one renderer per remaining shinka migrator, each applied to a real Postgres | ❌ not built | Only `keifu` renders |
| S3: telemetry export | ✅ built | `rogu::exporting` to Vector, `tsuiseki::exporter` to OTLP/HTTP, `keisoku::endpoint` on `/metrics`; each on by default and off alone through `observe` (`rogu::on?`). The chart side is pleme-lib 0.55.0 `telemetry-export` and `kenshi-labels` |
| S4: the RESP client | ✅ built | `resp_*` in `crates/blue-lang-runtime` (`tests/resp.rs`) and `bidamas/chozou/kiibariu` (8 tests): get, set with a TTL, del, pub/sub, SCAN, versioned keys, strict `put` and `fetch`, `read_upgrading`, `upgrade_eager` |
| S5: JetStream | ✅ built | `bidamas/chozou/sutoriimu` (5 tests) and `crates/blue-lang-runtime/tests/jetstream.rs`: streams, publish with ack, durable pull consumers, ack and nak, the outbox drained with SKIP LOCKED, `consumer` under a one-for-one supervisor |
| S6: `database.provider: :node_socket`; escuta's Postgres source | ❌ not built | No `node_socket` in haibi or `crates/blue-lang-pkg` |
| Model cache keys: a model's `cache` field rendered to `kiibariu` key prefixes, invalidated on write | ❌ not built | Needs a renderer from `model` to haibi's cache binding |
| Typed accessors from a model version (`orders::order::find`, `insert`, `update`) | ❌ not built | `teeburu::insert_statement` is the hand-written seed |
| Lock pin: the lock pins each version's hash, and `blue check` refuses a change with no version bump | ❌ not built | The Bluefile has no `model` word (`crates/blue-lang-pkg/src/bluefile.rs`) |
| shinka's keifu applier honours `runInTransaction="false"` | ❌ not built | shinka `keifu-core` reads only `id` and `author` |
| MySQL online DDL (`ALGORITHM=INSTANT` or `INPLACE`) | ❌ not built | Needs a second lowering shaped like `pg_step` |
| `upgrade_eager` rendered as a shinka job | ❌ not built | Waits on S2 and haibi |
| Strict Valkey entries as hashes or stream entries | ❌ not built | `kv_model` refuses `encoding: :hash` and `:stream` by name |
| RESP over TLS | ❌ not built | `resp_connect` refuses TLS by name. Waits on the runtime's TLS transport (`HTTP2.md` P4) |
| A hardened Valkey image | ❌ not built | `pleme-cache` still runs upstream `valkey/valkey` |
| Outbox without duplicates | ❌ not built | The drain is at-least-once. A `Nats-Msg-Id` header would let JetStream drop a duplicate, but `nats_publish` takes no headers |
| haibi passes `observe` and the kenshi values into the chart | ❌ not built | Waits on S1 |
| escuta as the change-capture source | ❌ not built | escuta runs nowhere. Its README calls its MySQL decoder unverified and its NATS sink core NATS, not JetStream |
| kensa's Valkey binding | ❌ not built | The binding is typed and never connects. kensa does not use `kiibariu` yet |
