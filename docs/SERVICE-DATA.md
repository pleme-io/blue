---
kind: explanation
---

# SERVICE-DATA — Postgres, Valkey and the nervous system as defaults

Status: DESIGN, 2026-10-27. Measured over the 2 Bluefiles that declare a
`service(...)` (kensa, ola-mundo) of 14. Extends `BUILD-STACK.md` §3.1.

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
  database:  {provider: :cnpg, instances: 2, pitr: true, migrator: :seaorm},
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
| Valkey | no schema, so no migrations. Every cache key carries the hash of the model version it encodes (`orders:v<hash>:order:<id>`), so a model change reads new keys and the old ones expire by TTL. No flush, no migration step | a cache migration job |
| Accessors | typed blue accessors are rendered from the same version (`orders::order::find`, `insert`, `update`) | ORM entities written by hand |
| Gate | `blue check` rejects a model change that has no version bump, a version with no lowering for the chosen migrator, or a lowering that changes once it has shipped (the checksum is pinned in the lock) | a review comment |

A transform that kueri's AST cannot express is a gap in kueri. Grow kueri
to cover it. Do not escape to raw SQL or Rust.

## 3. How each lowers

| Battery | Blue side | Chart side (pleme-lib) | Operators |
|---|---|---|---|
| Postgres | `model` → versioned DDL diffs and typed accessors (teeburu grown on kueri's SQL AST); the runtime's `pg_connect`/`pg_query` | `pleme-cnpg-cluster` or `pleme-database` as a subchart, `_pitr.tpl`; `shinkaDatabaseMigration` and its wait init container instead of haibi's hand-written psql job | shinka runs the versioned migration; kenshi correlates it by the `kenshi.pleme.io/service` label and gates promotion |
| Valkey | a RESP client in `blue-lang-runtime` (`resp_connect`, `get`, `set`, `del`, `publish`, `subscribe`), cache keys and invalidation rendered from `model` | `pleme-cache` as a subchart (a hardened image instead of upstream `valkey/valkey`); TLS and the password file as today | — |
| Events | JetStream in the runtime's NATS client (ack, durable consumers); an outbox written in the same transaction as the change, drained to the stream; a subscription word that runs a handler under supervision | `pleme-lib.jetstream` streams and its init job; `pleme-nats` | escuta for log-based capture later |
| Observability | `rogu` to Vector, `tsuiseki` to OTLP, `keisoku` on `/metrics`, `shihyou` rules and dashboard | `pleme-lib.observabilityBundle`, `_alerts.tpl`, `_grafana.tpl` | the fleet stores: VictoriaMetrics, VictoriaLogs (fed by NATS), Grafana |

## 4. Build order

| Step | Work | Serves (of 2 services) |
|---|---|---|
| S1 | haibi renders on pleme-lib's `shinkaDatabaseMigration`, wait init container, `observabilityBundle` and `jetstream`, and emits the kenshi labels (with H3 in `helmworks/docs/BLUE-SERVICES.md`) | 2 |
| S2 | `model(...)` with versions, `teeburu::evolve`, the §2a judge and gate, the keifu renderer, typed accessors | 2 |
| S2b | one renderer per remaining shinka migrator, each tested by applying it to a real Postgres | services that pin a tool |
| S3 | telemetry export: `rogu` → Vector, `tsuiseki` → OTLP, `/metrics` from `keisoku` | 2 |
| S4 | the RESP client and model-rendered cache keys; a hardened Valkey image | 1 now, 2 by default |
| S5 | JetStream in the NATS client, the outbox, the subscription word | the gate for every event-driven service |
| S6 | `database.provider: :node_socket` for hosts like plo; escuta's Postgres source | hosts; log-based capture |

## 5. Known gaps carried in

- escuta is deployed nowhere, and its own README calls its MySQL decoder
  unverified and its NATS sink core NATS, not JetStream.
- haibi writes its migration as a full `schema.sql` apply every time; S1/S2
  replace that with versioned migrations.
- kensa's Valkey binding is typed and never connects (no RESP client).
