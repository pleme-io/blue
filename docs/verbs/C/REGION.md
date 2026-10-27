---
kind: explanation
summary: verb graph region C: communication and distributed systems
---

# Region C: communication and distributed systems
Rows: 324 verbs in 15 spaces, 506 edges (1.56 per verb). Drawn from: Go (net/http, context, errgroup, x/time/rate, sony/gobreaker),
Erlang/OTP (gen_server, supervisor, monitor/link), Elixir (Task, Registry, GenStage), Rust (tower, tonic, tokio),
Python (asyncio, httpx, celery), Java (resilience4j), Temporal (workflow, signal, saga), NATS/JetStream, Kafka (consumer groups,
offsets, compaction), etcd/Consul (lease, election, watch), RFCs 9110/9111 (HTTP semantics, caching), 6455, 8446, 1035, 5321.
`blue_today` uses `partial:net` for the `blue-lang-runtime` net words (`http_*`, `nats_*`, `pg`) and `exists:proc` for `blue-lang-proc`
(spawn, send, receive, link, monitor, supervise, trace, replay, defmigrate); neither is a bidama, so those two tags are not bidama names.

## Spaces (a trailing ? is provisional; the sweep in the `naming` skill is owed)
| Space | Gloss | Verbs |
|---|---|---|
| tsuushin | HTTP client, URLs, cache validators (STDLIB 4.13, extended) | 25 |
| kyuuji | HTTP server, routing, middleware, SSE, hooks (bidama exists) | 30 |
| sokketto? | sockets: TCP, UDP, TLS, WebSocket (ソケット) | 19 |
| keiyaku? | API contracts (OpenAPI, gRPC, GraphQL) and wire framing (契約) | 23 |
| messeeji? | queues, pub/sub, logs, NATS, Kafka-like (メッセージ) | 27 |
| tsuuchi? | notification to people: email, SMS, push, webhooks (通知) | 14 |
| aktaa? | actors: processes, mailboxes, supervision, nodes (アクター) | 32 |
| goui? | consensus: leader, lease, lock, quorum, clocks, gossip (合意) | 25 |
| heikou | concurrency, retry, timeout, deadline, cancel (STDLIB 4.12, extended) | 24 |
| kyoujin? | resilience: breaker, bulkhead, rate limit, shed, idempotency (強靭) | 23 |
| shigoto? | schedules, timers, job queues, DAGs, workflows, sagas (仕事) | 28 |
| chuukai? | proxy, gateway, balancing, mesh policy, CDN edge (中継) | 18 |
| ami? | network reach: DNS, discovery, VPN/WireGuard, SSH (網) | 22 |
| shihyou | SLO objectives and burn rate (bidama exists) | 8 |
| nisshi | hash-chained event log (bidama exists) | 6 |
15 spaces is one over the 6-14 target: shihyou and nisshi are small extensions of existing bidamas, not new spaces.

## The 5 highest-leverage gaps
1. `kyoujin?` (breaker, bulkhead, bucket, once): rate limiting and idempotency are re-built per consumer today (samba, pleme-middleware-rate-limit), and `heikou::retry` needs breakers to stop retry storms.
2. `goui?::lock`/`elect` with `fence`: no lease or leader verb exists, yet `shigoto::every`, `ami::register` and `messeeji::join` all need one owner.
3. `messeeji?` ack/nack/park/seek/commit: the runtime has publish, subscribe and request on NATS only; delivery control is the gap.
4. `kyuuji` route/router/wrap and the standard middleware (limit, guard, timeout, recover): the bidama has responses and `serve`, not routing.
5. `shigoto?` cron + queue + saga: one scheduler vocabulary over the fleet's `shigoto-*` crates; durable workflows are the longest-lived need.

## Stays OUT of blue (STDLIB 4.23 spirit)
- Protocol stacks in C or kernel: TCP/IP, TLS cryptography, QUIC, HTTP/2 and HTTP/3 framing. blue sees them as `version:` options and Rust seams (CONTAIN THE C).
- Concrete consensus protocols (Raft, Paxos internals), broker internals (Kafka, NATS server), DNS servers, WireGuard data plane: blue gets the client verbs and declarations.
- Raw packet capture, eBPF, routing-table edits, firewall rules (nix and the module system own them).
- Mail transfer (SMTP server), push-provider SDK internals: only the `tsuuchi::send` door.
- Shared-memory channels (blue processes share nothing).

## Wave order and why
- Wave 0 (48): verbs that exist (kyuuji, shihyou, nisshi, the proc words, NATS words) and pure URL parsing: they only need a row and a spec.
- Wave 1 (103): the daily core: `tsuushin` store verbs, `kyuuji` routing, `heikou` retry/timeout/cancel, `kyoujin` bucket and once, `messeeji` ack set, `shigoto` cron and DAG, `sokketto` basics. Everything else leans on these.
- Wave 2 (105): TLS and certificates, SSE/WebSocket, breakers and bulkheads, leases and locks, discovery, SSH, contracts, CDN purge.
- Wave 3 (59): workflow, saga, mesh policy, webhooks at scale, clocks, shedding, hedging, auth flows.
- Wave 4 (9): replicated log (`propose`/`append`/`replicate`/`snapshot`), `merge`/`gossip`, `compact`, multicast. Needs a design decision on blue as consensus host, not only a library.

## Overlaps and duplicates with other regions
- `shigoto::parse(:cron)`/`next`/`after` and `heikou::debounce` touch time (`jikan`): the cron grammar may belong to `jikan::parse(text, :cron)`; kept here with a `requires` edge to `jikan::parse`.
- `ami::run`/`copy` mirror `shisutemu::run` and `fairu::copy` (remote forms, `refines` edges); the data-layer region may want `ami::copy` as `fairu::copy` with `on:`.
- `keiyaku::pack`/`unpack` and `frame` overlap `deeta` encodings; `keiyaku::diff` overlaps `deeta::diff`. Decision needed on whether binary layouts live in `deeta`.
- `tsuuchi::verify?`/`sign` refine `shomei`; `kyoujin::once` and `messeeji::dedupe` are the same idea at two layers (idempotency lateral).
- `kyoujin::check`, `chuukai::check` and `kyuuji::health` are three probes; kept distinct (what is probed) with `refines` edges.
- `aktaa::spawn` and `heikou::spawn` are the process and task levels of one idea; STDLIB 3.3 already lists both.
- Infrastructure as code (TLS certificate issue, DNS zone declarations in Pangea) belongs to the infra region.

## Fleet owners read (one-liners) and not read
Read: samba (leaky bucket, JetStream pull worker), pleme-middleware-rate-limit (Axum), tatara-mesh (defmesh), blackmatter-vpn (WireGuard module),
sshproxy, lava-cron (deflava-cron), grpc-forge, openapi-forge, pleme-graphql-helpers, shigoto-* (retry, budget, dag, gate, rank, fsm, emit crate headers), todoku-go (breaker.go seen).
Seen by name only, so not cited as owners: dns-reconciler, pangea-dns, kakuin-rustls, caixa-socket2, caixa-http, nats-publish, kafka-publish, twilio-sms,
ses-email-send, ntfy-push, cloudflare-cache-purge, fastly-cache-purge, github-webhook-flux, promessa-rpc, tatara-gateway-api, engenho-scheduler, breathe-discovery.

## Risks
- Blue processes need `blue run` support for `heikou` and `aktaa` over real concurrency (AUTHORING "Missing today"); wave 1 depends on it.
- TLS is the known gap (`http_request` refuses https, STDLIB D3): `tsuushin`, `sokketto::secure`, `keiyaku::call` all wait on it.
- `call` appears in aktaa, keiyaku and kyoujin with three argument shapes; the same name means "invoke through a wrapper". The check rule in STDLIB 8 should state that meaning once.
- `watch` here is a stream of events (`ami`, `goui`, `nisshi`) and matches STDLIB 3.2; `stream` kind rows must not return lazy sequences.
- Names are provisional; a collision sweep is owed for every `?` space (e.g. `ami`, short, likely to hit).
