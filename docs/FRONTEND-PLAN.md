---
kind: explanation
summary: the build plan for blue's frontend framework
---

# FRONTEND-PLAN — building the blue frontend framework

Status: ⏳ in progress. The server side, the GraphQL documents, the data laws
and the cache are built. The browser runtime, live data and the component
library are not. The [Ledger](#ledger) at the end says what is built.

This file is the build plan: what, where, in which order, and when each step is
done. Counted 2026-10-23 against `docs/verbs/merged/verbs.tsv` and the repos named.
The whole stack this plan is layer 2 of is [`SUBSTRATE.md`](SUBSTRATE.md)
(2026-11-09).

## 0. Destination

One blue program renders a page on the server, hydrates it in the browser,
installs as a PWA, and reads all its data through masked fragments over one
normalized, entity-keyed cache that hanabi keeps live. A team writes `.b` files
only. Rust grows only at three seams: the wasm runtime, the DOM import table,
and hanabi's hot path.

## 1. What exists to build on

The [Ledger](#ledger) lists each piece this plan builds on, with its state.
Besides the blue pieces, hanabi (Rust) already has APQ, an entity cache, cache
invalidation, a federation planner, a WS proxy and `ServerBuilder` extension
points (`hanabi/src/federation/`, `builder.rs`).

The browser runtime is **not** blocked on `tatara-wasm`. That blocker is about
blue *hosting* wasm. The
browser runs `blue-lang-wasm` itself; it needs an import table, which is a
change to that crate.

## 2. Tracks

Each milestone ships its graph rows, contracts, unit tests seen red, spec rows,
docs regenerated, and CI green by full SHA. "Rule" means a `RULES` row with a
witness and an autofix where one exists.

### F0 — Names, rows, contracts (gate for everything)

- Names, decided 2026-10-23 (`docs/verbs/names/RULINGS.md`): `danpen` is the
  GraphQL document space, `burauza` the browser runtime, and `kyasshu` the
  cache, promoted. The web words `fragment`, `island`, `hydrate` and `labels`
  are added to `gamen?`.
- Rows in `bidamas/mokuroku/graph/`, contracts in `docs/verbs/contracts.tsv`,
  `blue verbs check` rc 0, hadome baseline not grown.
- Bluefile word `frontend(name, {views:, tokens:, schema:, pwa:})`: a `WORDS`
  row, `MANIFEST_NAMES`, `nix/project.nix` `known` plus lowering, spec row.
- Done when: every verb below has a row and a decided contract.

### F1 — Element tree and the HTML renderer (pure blue)

- `gamen::view`, `component` (props, slots, variants, events, a11y row),
  `render(tree, :html)`, `layout`, `style` from token roles.
- The tree is records: `{tag:, props:, children:}` and `text`. A closed tag
  and attribute table, one source, generated like kigou's tables.
- Security as rules: text is always escaped; an attribute name outside the
  table is a check error; a URL attribute takes only `https`, `mailto` and
  relative; inline script and `on*` string attributes are unrepresentable.
- `gamen::check`: a11y faults (missing label, role, alt, focus order) as rules.
- Tests: tree equality per component; the escaping rule seen red on a crafted
  `"<script>"`; every tag row renders; a property test that render ∘ parse of
  the output keeps the text.
- Done when: a static page with components renders from blue with no Rust edit.

### F2 — Server: kyuuji wave 1 and 2

- `route`, `router`, `resolve`, `mount`, `header`, `redirect`, `guard`, `body`,
  `recover`, `timeout`, then `stream`, `file`, `cors`, `upgrade`.
- `serve` answers a view route with rendered HTML; `bougyo` sets CSP (no
  inline script, the hydrate module by hash) and the security headers.
- Tests: each verb against `request(...)` fixtures, no socket; one socket test.
- Done when: a multi-route SSR site runs from `blue run`, behind hanabi.

### F3 — GraphQL in blue (`danpen`)

- A GraphQL grammar as a `kiwari` spec → the blue parser for SDL and
  executable documents.
- `parse`, `validate(doc, schema)`, `fragment`, `compose`, `hash`, `print`.
- Second implementation, per the house rule: a Rust test crate (dev-only)
  validates the same corpus with `apollo-compiler`; the two must agree on every
  document. The corpus is real: gaveta's and lilitu's SDL, kensa's schema.
- Done when: every query in lilitu's frontend parses, validates and re-prints
  identically to the second implementation.

### F4 — The data laws as check rules

- Fragment refs as a type in `blue-lang-check` (a `Seam` kind): reading an
  undeclared field is a rule (law 1). The parent cannot read a child's field.
- Composition at check time: a view's operation is the union of its
  components' fragments (law 2); a field absent from the SDL is a rule.
- Entity-backed values: a literal list equal to an SDL enum is a rule
  (law 4); `labels` is the one allowed form.
- The schema enters through `generate(...)`: the SDL is an input, the check
  reads the generated table, `-fresh` keeps it current.
- Tests: one witness per rule (`every_rule_fires_on_its_witness_and_only_it`);
  a mutation per rule seen red; the LSP shows each at its span.
- Done when: the four laws hold on the corpus and the ratchet for undeclared
  reads starts at 0.
- Built 2026-10-24: B0048 undeclared-field-read (law 1, ratchet 0),
  B0049 fragment-not-composed (law 2, fix adds the spread), B0050
  field-not-in-schema (law 2 and `labels`), B0051 enum-mirror (law 4), B0052
  query-text (law 3's check-time half: no operation text in a view, ratchet
  0; the hash table is F7). The table is `danpen::render(sdl, :table)` through
  `generate(...)`; `examples/frontend` is the worked project;
  `docs/DIAGNOSTICS.md` has the shape. `gamen::labels` and
  `danpen::compose(root_fragment, fragments)` landed with them.

### F5 — Normalized cache and the data runtime (`kyasshu`)

- `normalize(response, schema)` → `Type:id` entities; fragment reads from the
  store; one key function, generated, also emitted for hanabi's entity cache.
- Policies per fragment: `ttl`, `stale: :revalidate`, `persist`, `evict`,
  each a `kousei` entry configured off alone.
- Mutations declare `touches:`; optimistic writes are a `machine`
  `pending → confirmed | rolled_back`; the compiler checks coverage.
- Server-side execution first: SSR fetches through `tsuushin` (wave 1 verbs)
  with the persisted hash.
- Tests: normalize/denormalize round trip as a property; two components share
  one entity copy; rollback restores the exact prior store.
- Done when: an SSR page with nested fragments renders from one request.

### F6 — State and change

- Forms: `signal`, `store`, `memo`, `machine`. `machine` is a table with an
  exhaustive match; an illegal transition is a rule.
- `gamen::diff(old_tree, new_tree)` → a patch list (wave 2 row). Keyed
  children. The patch list is data, so the server can test it.
- Dependency tracking: a `memo` records the signals it read; a write marks
  dependants; one flush per frame. In blue; move to Rust only on a measured
  frame budget miss.
- Tests: diff minimality on fixtures; property: apply(diff(a, b), a) == b;
  a machine with a missing transition fails check.

### F7 — Hanabi embeds blue (hanabi repo)

- Add `blue-lang-host`; one `Program` per product; a `#[host]` impl exposes
  session, Redis entity cache, entity events, request context.
- Order, each behind `blue.<surface>.enabled` (YAML readers stay, configured
  off later, never deleted): config entries → persisted-operation table →
  webhooks → middleware slots → routes → OAuth claim maps → rate limit and
  `X-Product` routing as `shisei` postures.
- Frames: a webhook gets Network and Entropy; middleware gets none.
- Measure `Hosted::call` on the request path before moving middleware; the
  budget is a ratchet.
- Tests: each surface has a Rust test that loads a `.b` fixture and a red run;
  the YAML and blue spellings of the same config produce the same `AppConfig`.

### F8 — Browser runtime (`blue-lang-wasm` + `burauza`)

- `Capability::Dom` (E0004 at the four sites); `imports_of` derives the import
  table; `blue-lang-wasm` gains the imports behind the frame. Zero-import build
  stays as its own arm.
- The contained seam: one generated JS loader (fetch the module, bind the
  import table, forward events). No authored JS. A test reads the generated
  file and fails on any name not in the import table.
- Hydration: the server ships the tree and the store snapshot; the client
  rebuilds the same tree and attaches handlers; islands by `hydrate: :visible`.
- Client data: `fetch` import for persisted queries; the store from F5 runs
  unchanged in the browser.
- Budgets measured first, then ratcheted: wasm bytes (compressed), time to
  interactive, idle redraw = 0.
- Tests: renderer agreement, html vs hydrated DOM, on every spec row (headless
  browser in the nix check); the import-table test.

### F9 — Live data

- graphql-ws subscriptions spoken in blue over `kyuuji::upgrade` and a
  `tsuushin` client socket; hanabi's entity events carry `Type:id`; the store
  patches or drops the key.
- Tests: an event invalidates exactly its key; reconnect resumes; the feed is
  replayable (`blue replay`).

### F10 — PWA

- `pwa` declaration → `manifest.json` and the service worker, both generated.
- The worker is the second contained seam: generated, typed absence when a
  browser lacks an API. Offline routes and `persist` policies use IndexedDB
  through the `Dom` import table.
- Tests: manifest from tokens; offline fixture serves the cached shell.

### F11 — Build and dev loop

- `frontend` lowers in `nix/project.nix` to: the SSR service, the wasm bundle,
  the generated tables, the PWA files, and `checks.*-fresh`.
- `blue dev`: `blue serve` session behind hanabi; save → redefine →
  push the patch to the open tab.
- Delivery unchanged: `trunk` is replaced by the nix bundle; armázem → hanabi.

### F12 — Component library

- Port Tela's widget typescape (12 families) to bidamas, one per family;
  tokens from ishou roles; motion from `ugoki`; each component with a11y rows
  and tree tests. Start with what the kensa console needs.

### F13 — kensa console (the pilot)

- Views over kensa's GraphQL: compliance matrix, control detail, evidence
  timeline, attestation verify. Evidence pack export (signed OSCAL, verifies
  offline). The old `ui/index.html` stays, configured off.
- Done when: an auditor flow (open, filter, verify, export) runs on the stack.

### S — The service side, complete (decided 2026-10-24)

The frontend renders from a blue service, so the backend is closed with it.

| ID | Work |
|---|---|
| S1 | concurrent requests, keep-alive, HTTP/2, TLS, gRPC: owned by `docs/HTTP2.md` P2–P6 (`net_wait` poll loop, rustls), not a second plan |
| S2 | a YAML reader (a bidama on kiwari, or the runtime) |
| S3 | `settei` rebuilt on `kousei`; `{tier, source}` per key |
| S4 | readiness distinct from liveness; drain on a signal |
| S5 | `kiroku`: JSON-line log layer; `nisshi` events when on |
| S6 | cofre's `SecretRef`; a `show` that redacts by construction |
| S7 | a RESP client under `Capability::Network`; a `cache` field on `service` |
| S8 | authn (RS256 JWT verify, OIDC) and authz layers; rate limit as a `shisei` posture |
| S9 | a PDF writer, so kensa's host form can be configured off |

Done when S1 to S9 are built and kensa runs as a pure blue service.

### F14 — The design language (after F12)

A blue design system that takes its principles from Material Design 3 and the
other mature systems, and its look from the house theme (Nord). Principles, not
branding: no Google marks, names or assets.

- CSS, HTML, JS loaders, icons and fonts are build outputs, never authored. A
  view states style as token roles; `frontend` in the Bluefile lowers through
  `nix/project.nix` to one stylesheet holding only the rules the views use
  (atomic, content-hashed class names), the component tables and the assets,
  each with its `-fresh` check. A `.css`, `.js` or `.html` file authored in a
  blue project is a rule, so the abstraction cannot be bypassed.
- Tokens in three tiers, reference → system → component, as one blue table;
  every renderer (HTML/CSS custom properties, terminal `irodori`, mado) is
  generated from it.
- Colour roles from tonal palettes built from a seed, each pair contrast-checked
  as a rule (`gamen::check`).
- Elevation is tonal surface, never a shadow. Shape and type scales; state
  layers (hover, focus, pressed, dragged) as one table; density levels.
- Motion tokens (duration, easing) are `ugoki` springs and tweens.
- Adaptive layout by window size class (compact, medium, expanded) with the
  canonical layouts (list-detail, supporting pane, feed).
- From Carbon: dense data views, tables and filters for kensa. From Radix and
  the WAI-ARIA patterns: behaviour separated from style, keyboard and focus
  rules per component. From Apple HIG and Fluent: motion that follows input.
- Each component carries an anatomy, states, a11y rows and tree tests.
- Done when the kensa console is rebuilt on it, with no literal colour, size or
  duration in any view.

### F15 — Phone and desktop from the same code

One blue app, unchanged, renders to web, desktop and phone; the target is a
placement datum, never a fork of the views. Its phases in
the whole-stack order are `SUBSTRATE.md` L2.1 to L2.3.

- The element tree, tokens, store and data laws are target-free; only the
  renderer and the import table change per target.
- Desktop: a GPU renderer for the element tree on the mado stack (Nord, no
  shadows, `ugoki` motion), packaged by nix for macOS and Linux.
- Phone: an iOS and an Android shell that host `blue-lang-wasm` with a native
  import table (the asobi and recanto iOS loop is the first host), and the PWA
  (F10) as the zero-install path.
- Adaptive layout (F14 window size classes) is how one view fits each screen.
- Renderer agreement is a gate: every spec row renders the same tree on every
  target.
- Done when the kensa console runs as web, desktop and iOS builds from one
  Bluefile.

## 3. Order and dependencies

```
F0 ─┬─ F1 ── F2 ──────────────┬─ F13 (SSR console, first usable product)
    ├─ F3 ── F4 ── F5 ────────┤
    ├─ F6 (after F1)          ├─ F8 ── F9 ── F10
    └─ F7 (hanabi, parallel)  └─ F11, F12 grow with each
```

| Wave | Milestones | Usable result |
|---|---|---|
| A | F0, F1, F3 (parser), F7 config | static SSR pages; GraphQL documents parsed in blue |
| B | F2, F4, F5 (server side), F7 persisted ops | SSR pages with masked, composed, persisted data |
| C | F13 SSR, F6, F12 (console set) | the kensa console, server-rendered |
| D | F8, F9 | hydrated, live pages |
| E | F10, F11 dev loop, F7 remaining surfaces | installable PWA; hanabi policy in blue |
| S | S1–S9, beside waves B–E, three agents at a time | kensa as a pure blue service |
| F | F14, F15 | the design language; the console on web, desktop and phone |

## 4. How the agents run it

From the H1 receipts (2026-10-22/23):

- One writing agent per milestone, each in its own worktree **and its own
  cargo target dir**, `CARGO_INCREMENTAL=0`. A shared target clobbered binaries
  across worktrees and rewrote 54 bidama files.
- Agents push to branches named `frontend/<milestone>`; one integrator merges
  a wave to `main` in one push, so CI runs once per wave, not once per commit.
- Each agent runs the pre-push gate locally and reports test names with their
  red runs; an audit agent re-runs them in a fresh worktree before the wave
  counts as done.
- hanabi (F7) and kensa (F13) are separate repos: separate agents, no shared
  worktree.

## 5. Gates and ratchets

| Gate | Start | Direction |
|---|---|---|
| components reading an undeclared field | 0 | stays 0 |
| hand-written query strings in `.b` | measured at F4 | down |
| literal colours, literal enum mirrors | measured at F1/F4 | down |
| authored `.css`/`.js`/`.html` in a blue project | measured at F11 | 0 |
| a11y rows uncovered by a component | measured at F12 | down |
| wasm bytes, time to interactive, idle redraws | measured at F8 | down |
| `Hosted::call` p99 on hanabi's request path | measured at F7 | not up |
| renderer agreement (html vs hydrated) | every spec row | total |

## 6. Risks

- **wasm size and speed.** The whole interpreter ships to the browser. Measure
  at F8 before more work lands on it; the VM path and `restricted` rung are
  the levers, not a second runtime.
- **GraphQL correctness.** A hand parser drifts. The apollo-compiler second
  implementation is the guard, not optional.
- **XSS.** A renderer is an injection surface. The closed tag table and the
  escaping rules land with F1, before any data reaches a page.
- **hanabi latency.** Policy in an interpreter on the hot path. Measure first;
  a surface that misses its budget stays in Rust, recorded with its number.
- **Scope.** F0–F5 and F13 are the product. F8–F10 are the polish. Ship the
  SSR console before the browser runtime.

## Ledger

The state of each piece and each milestone, measured on 2026-11-09.

✅ built and tested · ⏳ in progress · ❌ not built

| Item | State | What makes it true |
|---|---|---|
| F0: names, rows, contracts; the `frontend(...)` Bluefile word | ✅ built | `docs/verbs/names/RULINGS.md`; `crates/blue-lang-pkg/src/deploy/frontend.rs` and its test |
| F1: element tree and the HTML renderer | ✅ built | `gamen` `view`, `component`, `render`, `layout`, `style`, `check`, `escape` (`bidamas/gamen/gamen.b`, 60 tests), with tests "text and attribute values are always escaped" and "the table is closed: no script, style or frame tag and no on attribute" |
| F2: kyuuji waves 0 to 2 | ⏳ in progress | `route`, `router`, `resolve`, `timeout`, `stream`, `upgrade` and the rest in `bidamas/eigyou/kyuuji/kyuuji.b` (34 tests). `timeout` checks its deadline only when the handler returns, `stream` buffers, and the wire refuses an `upgrade` hand-off with 501: each needs a host seam |
| F3: GraphQL in blue (`danpen`) | ✅ built | `parse`, `validate`, `fragment`, `compose`, `hash`, `render` in `bidamas/toriyose/danpen/danpen.b` (32 tests); the second implementation agrees through `crates/blue-lang-danpen-diff/tests/agree.rs` (apollo-compiler) |
| F4: the data laws as check rules | ✅ built | B0048 to B0052 in `crates/blue-lang-check/src/`; `examples/frontend` |
| F5: normalized cache (`kyasshu`) | ⏳ in progress | `bidamas/toriyose/kyasshu/kyasshu.b` (16 tests): `normalize`, `read`, `write`, policies, mutations that declare `touches`, optimistic writes settled by `settle`. SSR through `tsuushin` with the persisted hash is not built |
| F6: `signal`, `store`, `memo`, `machine`; `gamen::diff` | ❌ not built | No such word in `gamen` or a bidama of its own |
| F7: hanabi embeds blue | ⏳ in progress | hanabi depends on `blue-lang-host` and loads `blue/hanabi/hanabi.b` (`src/blue.rs`, `tests/blue_config_test.rs`). Webhooks, middleware, routes, OAuth claim maps and postures in blue are not built |
| F8: browser runtime | ⏳ in progress | `bidamas/burauza/burauza.b` renders the manifest, the service worker and the one loader script; its `engine` row runs `blue-lang-wasm` in the page with no import, from the sources `blue bundle --sources` writes, and puts the rendered section and the run's receipt in the page (`crates/blue-lang-wasm/page/serve.b`, gated by `crates/blue-lang-cli/tests/placement.rs`: the same bytes and receipt as `blue run`). No `Capability::Dom`, no import table, no hydration, no headless-browser run |
| F9: live data over graphql-ws | ❌ not built | No graphql-ws word exists |
| F10: PWA | ⏳ in progress | `burauza`'s `install` renders the manifest and the service worker. No offline routes or `persist` policies over IndexedDB |
| F11: build and dev loop (`frontend` lowering, `blue dev`) | ❌ not built | `nix/project.nix` lowers no wasm bundle for a frontend, and there is no `blue dev` |
| F12: component library | ❌ not built | No component bidama exists |
| F13: kensa console | ❌ not built | Done when an auditor flow (open, filter, verify, export) runs on the stack |
| F14: the design language | ❌ not built | Waits on F12 |
| F15: phone and desktop from the same code | ❌ not built | Done when the kensa console runs as web, desktop and iOS builds from one Bluefile |
| S1: concurrent requests, keep-alive, HTTP/2, TLS, gRPC | ⏳ in progress | The `tcp_*` words and `net_wait` are built. HTTP/2 P2 to P6 are not (`HTTP2.md`) |
| S2: a YAML reader | ✅ built | `deeta::parse(text, :yaml)` (`bidamas/deeta/deeta.b`); a second implementation agrees through `crates/blue-lang-yaml-diff/tests/agree.rs` |
| S3: `settei` rebuilt on `kousei`, `{tier, source}` per key | ❌ not built | `bidamas/settei/settei.b` does not use `kousei` |
| S4: readiness apart from liveness; drain on a signal | ❌ not built | `SERVICE-ARCHITECTURE.md` P5 |
| S5: `kiroku`, a JSON-line log layer | ❌ not built | No `kiroku` bidama exists. `rogu` writes JSON lines today |
| S6: cofre's `SecretRef`; a `show` that redacts by construction | ❌ not built | No secret read word exists |
| S7: a RESP client; a `cache` field on `service` | ✅ built | `bidamas/chozou/kiibariu` (8 tests), `crates/blue-lang-runtime/tests/resp.rs`; `cache` in `crates/blue-lang-pkg/src/deploy/service.rs` |
| S8: authn (RS256 JWT, OIDC), authz, rate limit as a posture | ❌ not built | The service config carries `api.auth` only |
| S9: a PDF writer | ❌ not built | `bunsho` refuses `:pdf` by name (`bidamas/bunsho/bunsho.b`) |
