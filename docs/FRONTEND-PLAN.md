# FRONTEND-PLAN — building the blue frontend framework

Design: [`theory/BLUE-FRONTEND.md`](https://github.com/pleme-io/theory/blob/main/BLUE-FRONTEND.md).
This file is the build plan: what, where, in which order, and when each step is
done. Counted 2026-10-23 against `docs/verbs/merged/verbs.tsv` and the repos named.

## 0. Destination

One blue program renders a page on the server, hydrates it in the browser,
installs as a PWA, and reads all its data through masked fragments over one
normalized, entity-keyed cache that hanabi keeps live. A team writes `.b` files
only. Rust grows only at three seams: the wasm runtime, the DOM import table,
and hanabi's hot path.

## 1. What exists to build on

| Piece | State | Where |
|---|---|---|
| `gamen` bidama: theme, token colours, contrast, terminal `show` | built | `bidamas/gamen/` |
| `gamen?` graph rows: 34 verbs (3 wave 0, 21 wave 1, 10 wave 2): `component`, `view`, `state`, `render`, `layout`, `on`, `check`, `diff`, `focus`, … | rows only | `bidamas/mokuroku/graph/gamen-provisional.b` |
| `kyasshu?` graph rows: 19 cache verbs (`get`, `put`, `invalidate`, `memoize`, `remember`, `fresh?`, `refresh`, `tier`, …) | rows only | `graph/kyasshu-provisional.b` |
| `kyuuji`: `serve`, `response`, `json`, `metered`, … (wave 0); `route`, `router`, `match`, `mount`, `header`, `redirect`, `guard`, `body` (wave 1); `stream`, `upgrade`, `file`, `cors` (wave 2) | wave 0 built | `bidamas/kyuuji/` |
| `ugoki`: spring, tween, ease, sample, settled? | built | `bidamas/ugoki/` |
| `kousei`, `shisei`, `bougyo`: entries, postures, request defence | built | `bidamas/` |
| `kiwari`: one grammar spec, every syntax artifact emitted | built | `bidamas/kiwari/` |
| `blue-lang-wasm`: the full pipeline as a wasm32 module, zero imports | built | `crates/blue-lang-wasm/` |
| `blue-lang-host`: embed blue in a Rust program, `#[host]`, `Session`, frames | built | `crates/blue-lang-host/` |
| hanabi: APQ, entity cache, cache invalidation, federation planner, WS proxy, `ServerBuilder` extension points | built (Rust) | `hanabi/src/federation/`, `builder.rs` |
| a GraphQL parser or client in blue | **absent** | only `habu::query` (one row), `keiyaku?::parse` (wave 1) |

Correction to the design doc: the browser runtime is **not** blocked on
`tatara-wasm`. That blocker (BLUE-EXECUTION M2) is blue *hosting* wasm. The
browser runs `blue-lang-wasm` itself; it needs an import table, which is a
change to that crate.

## 2. Tracks

Each milestone ships its graph rows, contracts, unit tests seen red, spec rows,
docs regenerated, and CI green by full SHA. "Rule" means a `RULES` row with a
witness and an autofix where one exists.

### F0 — Names, rows, contracts (gate for everything)

- Naming sweep (`naming` skill) for: the GraphQL/requirement space (working
  name `yokyuu?`), the browser-runtime space (working name `burauza?`), and
  the web words added to `gamen?` (`fragment`, `island`, `hydrate`, `labels`).
  Cache stays `kyasshu?`; promote it. Decided 2026-10-23: `danpen` (requirement
  space), `burauza` (browser runtime), `kyasshu` promoted; `docs/verbs/names/RULINGS.md`.
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

- `route`, `router`, `match`, `mount`, `header`, `redirect`, `guard`, `body`,
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

The frontend renders from a blue service, so the backend is closed with it. The
gap rows are `theory/FUEKI.md` §IV G, H and I; each closes there, not here.

| ID | Closes | Work |
|---|---|---|
| S1 | G1, H1 | concurrent requests, keep-alive, HTTP/2, TLS, gRPC: owned by `docs/HTTP2.md` P2–P6 (`net_wait` poll loop, rustls), not a second plan |
| S2 | G3 | a YAML reader (a bidama on kiwari, or the runtime) |
| S3 | I3 | `settei` rebuilt on `kousei`; `{tier, source}` per key |
| S4 | I4 | readiness distinct from liveness; drain on a signal |
| S5 | I5 | `kiroku`: JSON-line log layer; `nisshi` events when on |
| S6 | I7 | cofre's `SecretRef`; a `show` that redacts by construction |
| S7 | H2 | a RESP client under `Capability::Network`; a `cache` field on `service` |
| S8 | I2 | authn (RS256 JWT verify, OIDC) and authz layers; rate limit as a `shisei` posture |
| S9 | H1 | a PDF writer, so kensa's host form can be configured off |

Done when every G, H and I row is `exists` and kensa runs as a pure blue service.

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
placement datum (`theory/FUEKI.md`), never a fork of the views.

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
