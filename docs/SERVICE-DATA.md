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
| `database.migrator` | `:seaorm` (kensa's `PgStore` already uses it) | `:seaorm`, `:keifu`, `:sqlx`, `:refinery`, `:diesel` (shinka's set, `shinka/src/migrator/types.rs:15`) |
| `cache.provider` | `:pleme_cache` | `:pleme_cache`, `:external`, `:off` |
| `events.cdc` | `:outbox` | `:outbox`, `:escuta` (once escuta has a Postgres source) |
| `observe.*` | every signal on | each turned off alone |
| `migration.gate` | `:kenshi` | `:kenshi`, `:none` (typed reason) |

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
| S2 | `model(...)`: versioned DDL diffs for shinka's migrator, typed accessors | 2 |
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
