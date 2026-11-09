---
kind: explanation
summary: blue as the one language of the whole stack — business logic in blue, everything it needs rendered; layer 1 cloud on engenho, layer 2 every placement, layer 3 high-assurance local systems (design)
---

# SUBSTRATE — blue as the one language of the whole stack

Status: DESIGN, 2026-11-09, at blue `3345779c` (v0.0.172) and engenho `1523893`;
revised the same day after an independent review against the code.
The operator's direction, 2026-11-08 and 2026-11-09: build bottom up; the
business logic of everything is blue, and everything it requires (the Helm
stack, the Kubernetes objects, the libraries) is rendered from it; blue is
"Darklang-style", one singular language; maximize reuse of what exists. This
doc owns that direction and points at the docs that own each part
(`BUILD-STACK.md`, `SERVICE-ARCHITECTURE.md`, `SERVICE-ACCESS.md`,
`SERVICE-DATA.md`, `DATA-FRAMEWORK.md`, `STDLIB.md`, `FRONTEND-PLAN.md`,
`HORIZON.md`, and in `theory/`: `BLUE.md`, `BLUE-STRUCTURE.md`, `FUEKI.md`,
`IBUKI.md`, `BLUE-FRONTEND.md`). Where they rule, this doc follows them (§7).

## 1. Destination

A person writes one thing: blue. A program declares what it is (a service, a
frontend, an appliance, a reconciler) and what it holds (its data model, its
routes, its queues, its schedules, its secrets, its peers, its authority) in
blue, beside the code that is its behaviour. Everything else is a rendering of
that one source and is never edited by hand: the wasm component, every
Kubernetes object, the Flux objects that place it, the SQL and migrations of
its data, the typed clients of its peers, the frontend bundle for each
placement. On engenho the program runs as a WASI component in-process, holds
only what its declaration grants, and reads the Kubernetes API through the same
typed kinds engenho itself uses, so a reconciler is a blue program like any
other. During development an edit is live without a deploy step, against
traces of real requests; what a cluster runs for good is still what git
pins. The same declarations render to a browser, a phone, a desktop and a local
appliance; and two blue systems that meet over the ibuki wire prove to each
other, with tameshi receipts and shomei signatures, what they ran and what they
saw, with no server between them.

**World-facts that bound it:** the Kubernetes API, its OpenAPI schema and its
discovery document (plural names and scope are only in discovery) are fixed
upstream; WASI 0.2 gives a component only the imports its host links; a
browser runs wasm only through JavaScript and the DOM; iOS forbids executing
downloaded code, so an iOS placement ships its engine and bundle inside the
app; a signature proves who signed, never that the signer was honest. Every
other limit below is ours to remove.

## 2. Ground: what exists (measured 2026-11-09)

BUILT = code and a test on main; PARTIAL; DESIGN = doc only; ABSENT.

### Layer 1: blue on engenho

| Piece | Tier | Evidence |
|---|---|---|
| `service(...)` with `access`, `runtime`, `schema`, `cache`, `slo` | BUILT | `crates/blue-lang-pkg/src/deploy/service.rs` |
| Runtime rung: wasm by default, native with a named reason | BUILT | `BUILD-STACK.md` §2, `deploy/runtime.rs` |
| One shared engine component (wasip2) | BUILT; 180 conformance rows on its column, 167 agree | `crates/blue-lang-component`; ROADMAP placement-parity row |
| haibi renders chart, values schema, config, DDL, migration, SLO | BUILT, as Go-template lines over pleme-lib helpers | `bidamas/eigyou/haibi/haibi.b` |
| pleme-lib: 96 hand-written `.tpl` helpers, 122 of 153 helmworks charts depend on it | HAND-WRITTEN, fleet-wide | `helmworks/charts/pleme-lib/templates/` |
| `workload(...)` renders typed objects (Deployment, Service, Kustomization) | BUILT (Rust) | `crates/blue-lang-pkg/src/deploy/render.rs` |
| engenho runs WASI P2 pods in-process | BUILT, tested with a probe component | `engenho-kubelet/src/wasm_backend.rs` |
| kidou (blue in engenho) admits pods, turns `access` into runtime grants | BUILT | `engenho-kubelet/blue/kidou/kidou.b` |
| ola-mundo's release pins `runtime.component.closure` on ryn | DONE; whether the pod serves is unmeasured | `nix/nodes/ryn/default.nix` (`6dd08d07`) |
| Imports derived from `access` (link-time authority) | DESIGN, blocked (M2) | `crates/blue-lang-waku/src/imports.rs`; one engine for every service (`nix/service.nix`) |
| Typed Kubernetes kinds generated from vendored OpenAPI v1.34.0 | BUILT (Rust, engenho) | `engenho-kube-codegen`, `engenho-types/vendor/openapi/v1.34.0` |
| Kubernetes client with watch | BUILT (Rust, engenho) | `engenho-kube-client` (`KubeClient`, `Watcher`) |
| Controller loop | BUILT (Rust, engenho) | `engenho-controllers/src/controller.rs` (`Controller::tick`) |
| "blue decides, Rust applies" seam | BUILT | `engenho-blue/src/lib.rs` (`BlueWorker`), used by kidou |
| `kurasuta`: Kubernetes verbs in blue (`watch`, `diff`, `describe`, `render`; writes go through GitOps) | DESIGN (ratified space) | `docs/STDLIB.md` §4.18, `mokuroku/graph/kurasuta.b` |
| Placement on a node without Flux | BUILT | `pleme.engenho.helm.releases` (`theory/FUEKI.md` G6) |
| Flux objects from `placement(...)`; GitOps inside engenho | DESIGN | `BUILD-STACK.md` §3.1; `engenho/docs/NATIVE-GITOPS.md` |

### Constructs, mapped to ratified spaces

| Construct | Tier | Owner |
|---|---|---|
| route and handler | BUILT as words | `kyuuji` |
| data model → SQL, migrations, API | `teeburu` `model`/`evolve`/`judge` BUILT; the model bidama of `theory/BLUE.md` §V.32 DESIGN | `DATA-FRAMEWORK.md` D1–D6, `SERVICE-DATA.md` |
| schedule | DESIGN (ratified space) + BUILT timers | `shigoto` (`every`, `next`, `missed`, `backfill`, `claim`, `timer`); ASYNC A1 `after`, `sleep_until`; engenho `cron.rs` |
| queue and message | DESIGN spaces; NATS client BUILT | `taiki`, `messeeji` spaces; `net/nats.rs` |
| secret | law ruled, reader designed | declarations name cofre's `SecretRef` (`theory/FUEKI.md` R5, E3); runtime reads through shikumi `SecretSource` (`SERVICE-ARCHITECTURE.md` §5a) and blue's `himitsu` record |
| typed peer API | PARTIAL | `toriyose/outou` (GraphQL from a blue schema); `katachi`, `seigyo` proposed (`SERVICE-ARCHITECTURE.md` §5e, §6) |
| retry and restart | BUILT | `saishikou`, `blue-lang-proc` |
| deployless edit | ABSENT | — |
| request traces | PARTIAL (spans in process, no export) | `tsuiseki` |

### Layer 2 and layer 3

Layer 2: `frontend(...)` parses; `gamen`, `kyasshu`, `ugoki` and the
zero-import `blue-lang-wasm` are BUILT; `burauza` PARTIAL; DOM capability,
element tree, hydration DESIGN; desktop (mado) and iOS/Android (asobi) shells
DESIGN (`FRONTEND-PLAN.md`; `theory/BLUE-FRONTEND.md` §10).
Layer 3: the runtime `wire` (binary payloads since v0.0.169), `ibuki` (22
tests), `shomei` (33 tests), receipts v2, `def_hash`, appliances with bounds and
threshold signing, and `receipt(...)` → tameshi are BUILT; rings charged to an
app allocation DESIGN; a live tameshi chain writer PARTIAL (`theory/IBUKI.md`
§VII; `theory/FUEKI.md` D2–D5).

## 3. Research

Cited from prior knowledge on 2026-11-09; each row is re-read at review before
a phase adopts it.

| Prior art | What it proves | Decision |
|---|---|---|
| Darklang (darklang.com) | one language with handlers, datastores, workers and crons; deployless edits; trace-driven development | ADOPT the construct set, the dev-time live loop and traces; SKIP its hosted cloud and structured editor |
| Kubernetes OpenAPI v3 + discovery | kind schemas (OpenAPI) and plural/scope (discovery) | ADOPT both, as engenho-kube-codegen already does |
| kube-rs, controller-runtime | list/watch/reconcile/status | ADAPT through engenho's `Controller::tick` + `BlueWorker`; no second loop |
| Helm 3 | the install format Flux and engenho consume | ADAPT: a chart is one output of typed objects (§7), not the source |
| Flux | GitOps placement | ADOPT, rendered from `placement(...)`, beside the node arm |
| WASI 0.2, wasi-http | a component holds only linked imports | ADOPT as the M2 target; until then kidou grants are the enforcement |
| SpinKube, runwasi | wasm on Kubernetes via RuntimeClass | ADOPT the RuntimeClass contract; SKIP the shim (engenho runs components in-process) |
| Unison | content-addressed code makes swaps cheap | ADAPT via `def_hash` (HORIZON H3) for the dev loop |
| OpenTelemetry OTLP | the common trace wire | ADOPT for tsuiseki export |

## 4. The model

### 4.1 One source, typed objects, many outputs

```mermaid
flowchart LR
  B["blue source<br/>declarations + business logic"] --> O["typed objects in blue<br/>(kinds generated by engenho-kube-codegen)"]
  O --> H["Helm chart (one output)"]
  O --> F["Flux HelmRelease / Kustomization"]
  O --> N["node release (pleme.engenho.helm.releases)"]
  O --> P["NetworkPolicy, RBAC from access"]
  B --> W["program bundle (def_hash) on the shared engine"]
  B --> D["SQL + migrations (teeburu model), typed clients (toriyose/outou)"]
  O -. "same kinds" .-> K["kurasuta: watch, diff, describe;<br/>BlueWorker decides, engenho applies"]
```

The center of layer 1 is **one typed set of Kubernetes kinds visible in blue,
generated by the generator engenho already has** (`engenho-kube-codegen` over
the vendored OpenAPI plus discovery). blue does not get a second generator: the
same codegen emits blue records beside the Rust types. `render.rs`, haibi and
every placement emit through those records; a reconciler reads through them.

### 4.2 The constructs

| Declaration | Behaviour lives in | Renders to |
|---|---|---|
| `service(...)` | `kyuuji` handlers | Deployment/Service objects, chart, Flux or node release |
| `model` (its own bidama, `theory/BLUE.md` §V.32) | queries over the model | SQL DDL, migrations, data API (`DATA-FRAMEWORK.md`) |
| `shigoto` schedule | a handler per firing; `claim` holds a lease so one replica fires; `missed`/`backfill` cover scale-to-zero and swaps | a supervised timer in the service |
| `taiki`/`messeeji` queue | a handler per message | NATS JetStream objects, supervised consumers |
| secret | `himitsu` record read through shikumi `SecretSource` | cofre `SecretRef` in the declaration (FUEKI R5) |
| peer | calls through the generated client | the client; the NetworkPolicy egress rule |
| `placement(...)` | — | Flux objects for a cluster, or a node release |
| reconciler | a blue `BlueWorker` decision over typed kinds | a watch in engenho; RBAC for exactly its kinds |

### 4.3 Host seams (the only Rust)

Rust stays where blue cannot reach a world-fact: the wasmtime host and WASI
links (`wasm_backend.rs`), sockets and TLS, the Kubernetes transport and watch
(`engenho-kube-client`), crypto, and the OS shells of layer 2. The pattern is
`BlueWorker`: blue decides, Rust applies. Each seam is one crate behind one
capability in `blue-lang-waku/src/capability.rs`.

### 4.4 Reuse: every piece extends what exists

Rule: no construct, phase or placement starts a primitive while a row below is
the near-miss; a new word comes only after `blue arika word` and `blue arika
like` find nothing (`theory/ARIKA.md`); a shape seen twice is promoted, and the
reuse census holds it.

| Need | Extends | Not |
|---|---|---|
| Kubernetes kinds | `engenho-kube-codegen` (emit blue records too) | a second generator, hand-typed kinds |
| Kubernetes reads, watch, reconcile | `engenho-kube-client`, `Controller::tick`, `BlueWorker`, `kurasuta` verbs | a new client or loop; vigy (a native host runtime, not reachable from a component) |
| routes, handlers | `kyuuji` | a second router |
| data model | the §V.32 model bidama (`DATA-FRAMEWORK.md`), `teeburu` (`model`/`evolve`/`judge`); SQL rendered from `kueri`'s typed tree (§V.32) | hand SQL; a second model beside the bidama; `kueri` as the model (it renders the SQL, it does not hold the shape) |
| schedules | `shigoto`, ASYNC timers, engenho `cron.rs` | a CronJob per schedule |
| queues | `taiki`/`messeeji` spaces over `net/nats.rs` | a new broker client |
| secrets | cofre `SecretRef` (declared), shikumi `SecretSource` + `himitsu` (read) | blue's own parallel `SecretRef` (FUEKI E3) |
| typed peer APIs | `toriyose/outou`, `katachi`, `seigyo` | hand clients |
| retry, supervision | `saishikou`, `blue-lang-proc` | ad-hoc retries |
| loop liveness | `shinchoku` | a new probe |
| config, every entry judged alone | `kousei`, `settei` | ad-hoc parsing |
| render to files | `render.rs` typed objects, haibi as its blue face | Go-template strings |
| node admission, grants | `kidou`, waku capabilities | a second policy engine |
| traces | `tsuiseki` + OTLP | a new tracer |
| caching | mondou `Store` domains (HORIZON H3) | a cache per feature |
| views on every placement | `gamen`, `ugoki`, `kyasshu`, `burauza` | a view layer per placement |
| wire, peers | `ibuki`, runtime `wire` | a new transport |
| signatures, receipts | `shomei`, tameshi, receipts v2 | a new crypto layer |
| tests, laws, differentials | `tesuto`, `okite`, `heni`, `happa` | per-feature harnesses |

## 5. States and trust

```mermaid
stateDiagram-v2
  [*] --> Declared
  Declared --> RefusedAtDeclaration: an entry fails its check (that entry only)
  Declared --> Rendered
  Rendered --> Stale: a rendered file no longer matches its source
  Stale --> Rendered: regen
  Rendered --> Built
  Built --> RefusedAtAdmission: kidou refuses the pod
  Built --> Unready: admitted, starting
  Unready --> Ready
  Ready --> Draining: swap or shutdown
  Draining --> Ready: dev swap done (all replicas on one hash)
  Ready --> Drifted: live hash differs from what git pins
  Drifted --> Ready: promote to git, or revert
  Ready --> CrashLoop: a swap fails its probes
  CrashLoop --> Ready: rolled back to the last good hash
  Ready --> Held: an edit's access hash differs
  Held --> Rendered: goes through render + review
  Held --> Declared: rejected
  Ready --> Blind: no heartbeat, no trace export
  Blind --> Ready: evidence returns
  Ready --> Off: configured off
```

- **Absence is a state** (`Blind`), never `Ready` and never refused.
- **Authority today is kidou's runtime grant**; link-time imports from `access`
  are the M2 target (`imports.rs`). An edit is held when its `access` hash
  differs from the running one; it is never compared by imports, because every
  service shares one engine.
- **Git stays the truth for what a cluster runs** (`SERVICE-ACCESS.md` §5–6).
  A live dev swap moves the service to `Drifted` until it is promoted (a commit
  that pins the new hash) or reverted; Flux would otherwise undo it.
- **Partial swaps:** a swap completes when every replica reports the new hash;
  until then the service is `Draining`, and a failed replica rolls the whole
  set back.

## 6. The dev loop: an edit goes live

```mermaid
sequenceDiagram
  participant Dev as person
  participant Blue as blue (check, def_hash, render)
  participant Store as sui (bundles by hash)
  participant K as kidou on engenho
  participant Pods as replicas
  Dev->>Blue: edit a handler
  Blue->>Blue: check; access hash unchanged?
  Blue->>Store: push bundle (content hash)
  Blue->>K: offer hash for service S (dev lane)
  K->>Pods: drain, swap at a request boundary
  Pods-->>K: all replicas on the new hash (else roll back)
  K-->>Dev: Drifted; traces (OTLP) tagged with the hash
  Dev->>Blue: promote: commit pins the hash; Flux/node release agrees
```

## 7. Decisions (and where existing law wins)

| Decision | Why; alternatives rejected |
|---|---|
| Typed objects are the source; Helm is one output | the review showed the better alternative already exists (`render.rs`); Go-template strings are the `format!`-of-a-target-syntax the house bans, and `hole(path, type)` (`SERVICE-ARCHITECTURE.md` §5e) shows the fight they cause. The chart stays an output because Flux and nodes consume it |
| pleme-lib and haibi's string templates are **configured off** per chart as typed rendering covers them, never deleted | `theory/FUEKI.md` R7 (retirement is a flag); pleme-lib serves 122 charts, so this is fleet-wide and per chart |
| Kinds come from `engenho-kube-codegen` | a second generator in blue (two sources of one schema) |
| Reconcilers use `BlueWorker` + `Controller::tick` | vigy (native host runtime, ticks only); a Rust operator per CRD (moves logic out of blue) |
| Writes reach clusters through GitOps; blue reads, watches, diffs and decides | `STDLIB.md` §4.18 rules kurasuta has no writes; engenho applies what a `BlueWorker` decides on the node it runs |
| Secrets: cofre `SecretRef` declared, shikumi read | blue's parallel `SecretRef` (`theory/FUEKI.md` E3 calls it the cardinal sin) |
| The engine stays nix, written once in the blue repo | `theory/BLUE-STRUCTURE.md` §5.5, ROADMAP R1; blue drives nix through kakehashi, it does not replace the engine |
| The data model is its own bidama | `theory/BLUE.md` §V.32 (newer than the `model(...)` Bluefile word in `SERVICE-ARCHITECTURE.md` §5c); that doc is reconciled to it |
| CRDs: a controller's CRD stays derived from its Rust types; a blue reconciler's CRD from its blue kinds | `SERVICE-ARCHITECTURE.md` §5e; one owner per CRD |
| Placement has two arms: a node (engenho release) and a cluster (Flux) | `BUILD-STACK.md` §3.1 |
| Deployless is a dev lane with a `Drifted` state, promoted by commit | pushing to the cluster directly (Flux reverts it; review is skipped) |

## 8. Open questions

| Question | Kind |
|---|---|
| Does ola-mundo's component pod serve on ryn today | ours to measure (L1.1) |
| How codegen emits blue records: a generated bidama per API group, or one | ours |
| Long-lived connections across a swap | ours: drain or pin per connection |
| The browser loader: generated or one fixed loader | ours |
| iOS live edit: dev builds only | world-fact (App Store rules) |

## 9. Phases

Each phase names the row of §4.4 it extends and a red run that must fail
without it.

### Layer 1: cloud on engenho

- **L1.1 Measure and serve.** Probe ola-mundo's pod on ryn; add an engenho e2e
  that runs the real `blue-component.wasm` with a bundle and serves a request
  (extends `tests/wasm_backend.rs`). Red: the same test with the program bundle
  path removed fails with the named error, not a hang.
- **L1.2 Blue records from engenho-kube-codegen.** Red: a rendered greeter
  object built from the generated records with an unknown field does not
  construct; and a golden of the generated records changes when the vendored
  schema changes (proves the generator is used, not bypassed).
- **L1.3 Typed rendering replaces string templates, per chart, configured.**
  The greeter chart renders its objects from the records with pleme-lib
  configured off for it. Red: re-enabling a hand template for an object the
  records render fails the freshness check; the count of hand-kept templates on
  the greeter path is zero and ratcheted.
- **L1.4 `placement(...)` → Flux and node release.** Red: a placement naming an
  undeclared cluster or node is refused alone; Flux on ryn reconciles the
  rendered HelmRelease.
- **L1.5 A blue reconciler.** A `BlueWorker` decision over the typed kinds on
  engenho, with RBAC rendered from the kinds it names. Red: a decision naming a
  kind outside its declaration is refused before apply; a kidou-style test
  shows the Rust side applies nothing it was not told.
- **L1.6 Constructs.** `shigoto` schedules (with `claim`), `taiki` queues, the
  secret read path, typed peer clients. Red per construct: a schedule with two
  replicas fires once (claim), a missed firing during a swap is backfilled, a
  secret value never prints (`himitsu`), a peer call to an undeclared peer is
  refused.
- **L1.7 Dev loop and traces.** Bundle swap under kidou in a dev lane, the
  `Drifted` state, promotion by commit, OTLP export keyed by hash. Red: an edit
  whose `access` hash differs is held; a swap where one replica fails rolls the
  set back.

### Layer 2: every placement

- **L2.1 Browser, L2.2 Desktop (mado), L2.3 Mobile (asobi).** All render the
  same `gamen` views, `ugoki` motion and `kyasshu` store; a placement adds a
  host seam, never a view layer. Red: one program whose receipts differ between
  two placements fails H8's parity gate, naming the row.

### Layer 3: high-assurance local

- **L3.1 Envision**, as typed design entries with trust models (local-first
  sync, offline collaboration, provable appliances, peer attestations). Gate:
  each entry names the primitives of §4.4 it uses and the bad state it makes
  unrepresentable; an entry naming a primitive that does not exist is refused
  by review.
- **L3.2 Build** on `ibuki`, `wire`, `shomei`, tameshi and receipts v2: rings
  charged to the app allocation, a live chain writer, receipts exchanged over
  the wire. The Aqui neighborhood map mesh is the first application. Red: a
  chunk whose hash does not match the root it claims is refused; a chunk signed
  by a key that does not own the coordinate is refused.

## 10. Tier ledger

| Item | Design | Exists | Tested | Live |
|---|---|---|---|---|
| L1.1 component serves on engenho | ✅ | release pinned on ryn | probe component only | unmeasured |
| L1.2 blue records from codegen | ✅ | Rust codegen | Rust only | ❌ |
| L1.3 typed rendering per chart | ✅ | `render.rs` objects | yes (render.rs) | ❌ |
| L1.4 placement → Flux / node | ✅ | node arm | node arm | node arm |
| L1.5 blue reconciler | ✅ | `BlueWorker`, kidou | kidou | kidou on ryn |
| L1.6 constructs | ✅ | spaces ratified; timers, NATS client | partial | ❌ |
| L1.7 dev loop + traces | ✅ | ❌ | ❌ | ❌ |
| L2.1–L2.3 placements | ✅ | wasm engine, gamen | partial | ❌ |
| L3.1–L3.2 local assurance | ✅ | primitives | primitives | ❌ |
