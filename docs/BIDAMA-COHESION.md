---
kind: explanation
summary: one word per job, foundations below, a complete vocabulary across the bidamas (plan)
---

# BIDAMA-COHESION — one word per job, foundations below, a complete vocabulary

Status: PLAN, 2026-10-27, measured at `392aeda`: 78 bidamas (77 plus the `zenbu`
facade), 4,223 top-level definitions. The near-duplicate gate
(`crates/blue-lang-pkg/tests/distribution.rs`, `near_duplicate_shapes_only_fall`)
counts 257 definitions in 106 shape groups, each a word the distribution wants.

Status 2026-11-05: IN FLIGHT. Three branches wait to land, and the namespace
trees add a second axis (section 6). Pick up from section 6.

## 1. Destination

Every recurring shape is one word in the lowest bidama that can own it, and every
other bidama imports it. Foundations (`kazu`, `kansuu`, `deeta`, `retsu`, `moji`,
`kyohi`, `kousei`, `jisho`) depend only on each other. Service batteries depend on
each other where they meet (retry under supervision, rate limits in the request
path). A domain every service needs has a bidama before a second service writes it
by hand. The near-duplicate pin only falls.

## 2. Merges, ranked by reuse

| # | Group (definitions / packages) | One word | Owner |
|---|---|---|---|
| 1 | nil check, then apply (10 / 8) | `maybe(x, default, f)` | kansuu |
| 2 | `reduce` sums and folds (10 / 7) | `fold(xs, init, op)`; sums call `kazu::sum` | retsu |
| 3 | find a row by a field (9 / 5) | `find_where(rows, key, value)` | retsu |
| 4 | `jitaku`'s copies of `kousei` (8 / 2) | import them; `kousei` gains `float_in` | kousei |
| 5 | predicate combinators (10 / 2) | `lift2(op, f, g)`, `juxt_with(q, fs)` | kansuu |
| 6 | apply only when a predicate holds (5 / 4) | `when(x, pred, f)` | kansuu |
| 7 | default on an empty list (4 / 3) | `if_empty(xs, d, f)` | retsu |
| 8 | sort and insert by comparator (6 / 2) | `sort_with`, `insert_with` | junjo |
| 9 | element-wise zip (5 / 2) | `zip_with` (exists) | retsu |
| 10 | GraphQL definitions by kind (4 / 2) | `definitions_of` (exists) | danpen |
| 11 | scan while a predicate holds (5 / 2) | `span_end(xs, i, n, pred)` | retsu |
| 12 | first of two keys (3 / 3) | `get_any(m, keys)` | jisho |
| 13 | temporary directory (2 / 2) | `scratch` (exists) | tesuto |
| 14 | exact copies of exported words (6 / 6) | import `jisho::from_entries`, `retsu::index_of`, `retsu::repeat` | jisho, retsu |
| 15 | `ongaku` chords and scales (18 / 1) | `chord(root, intervals)` | ongaku |

## 3. Layering fixes

| Fault | Evidence | Fix |
|---|---|---|
| a server needs a screen and a test library | `kyuuji` needs `gamen` and `tesuto`; `use("tesuto", [:raises?])` at `kyuuji/kyuuji.b:11` | `raises?` moves to `kyohi` (refusals); ten production bidamas stop needing `tesuto` |
| a client needs the server | `tsuushin` needs `kyuuji` | the shared request/response types move to a lower bidama both use |
| declared, then copied | `jitaku` imports ten `kousei` words and redefines six (`jitaku/jitaku.b:54-1090`) | delete the copies (merge 4) |
| retry written twice | `kirikae/kirikae.b:59-69` beside `saishikou` | `kirikae` takes its policy from `saishikou` |
| process results read twice | `kirikae/{exit_status_of,text_of}` beside `shisutemu::status_of` | import |
| batteries no one wires | `saishikou`, `keisoku`, `tsuiseki`, `hizuke` have no dependents | wired by the service runtime (`BUILD-STACK.md` §5.1) and by the new bidamas below |

No dependency cycle exists (every `needs` edge checked).

## 4. Vocabulary gaps

| Domain | State | Evidence |
|---|---|---|
| environment, dotenv | absent | 22 bidamas call `getenv` directly |
| time, durations, cron | partial | `hizuke` is the calendar only; 21 bidamas use `now_ms`/`sleep_ms` |
| CLI arguments | absent | 14 bidamas parse `"--flag"` by hand |
| parallel map, timeouts, supervision wording | absent | the runtime supervisor (`blue-lang-proc`) has no blue words |
| rate limit, circuit breaker, bulkhead | absent | `bougyo` has no rate posture (`SERVICE-ARCHITECTURE.md` §5d) |
| files and paths | partial | `fairu` has 4 definitions; 501 call sites in 65 files |
| processes | partial | `shisutemu` has 12; 11 bidamas still call `exec_*` |
| HTTP client | partial | `tsuushin`: URL and a basic request; no JSON or pagination helpers |
| encodings | partial | base64 and hex in `shinsuu`; no base64url, no URL encoding outside `kyuuji` |
| UUID, semver, regex | absent | none; UUID needs only `random_bytes` and hex; regex needs a runtime primitive |
| secrets, Kubernetes, GitHub, units | designed | `STDLIB.md` §4.18-4.21 (`himitsu`, `kurasuta`, `habu`, `joujuu`) |

## 5. Build order

Each step lands green: `blue test` per touched bidama, the distribution suite, and
the near-duplicate pin lowered to the measured count in the same commit.

| Step | Work |
|---|---|
| C0 | the newline-escape ban lands first (it rewrites every bidama) |
| C1 | merges 14, 13, 9, 10 (imports of words that already exist) |
| C2 | merges 1, 2, 3, 6, 7, 11, 12 (new foundation words) and 4, 5, 8 |
| C3 | layering: `raises?` to `kyohi`; `tsuushin`/`kyuuji` shared types; `kirikae` onto `saishikou` and `shisutemu` |
| C4 | new bidamas, each through `/naming`: environment (`kankyou`), time and durations (`jikan`), CLI arguments (`hikisuu`), parallelism and supervision (`heikou`), rate limiting and breakers (`kyoujin`) |
| C5 | adoption: the 22, 21 and 14 call sites move onto C4's words |
| C6 | the designed batteries (`himitsu`, `kurasuta`, `habu`, `joujuu`) per `STDLIB.md` |

## 6. Namespace trees and the 2026-11-05 handoff

Measured at `fb0ac803` (main, 2026-11-05): 97 bidamas, 5,471 definitions. Exact
copies (`blue census bidamas --reuse --json`): 10, each with its home. Near
duplicates: 252 definitions in 103 groups. Print the groups with
`NEAR_SHAPE_DEFINITIONS = 0` in `crates/blue-lang-pkg/tests/distribution.rs` and
`cargo test -p blue-lang-pkg --test distribution near_duplicate_shapes_only_fall`.

### Branches, in landing order

Land each with `git land`, rebased onto the newest main, after
`cargo test --workspace --exclude blue-lang-wasm`.

| # | Branch | Head | What it holds | State |
|---|---|---|---|---|
| 1 | `namespaces/nested-land` | `6f7a35f0` | the tree feature (`57a545d6`, rebased onto `82aae46a`) and the fix for its two red gates (CI 2026-11-05T02:11Z): a docs link and R0002 in `gen/consumers.b` | prepush green; workspace suite not yet run after the rebase |
| 2 | `bidamas/exact-copies` | `526129316` | the 10 census copies and 3 in-package twins, each removed word with a `legacy_names` or retired row; new `retsu::index_of_at`, `kueri::names_of`; pins SHAPE_GROUPS 18→16, NEAR 252→235, SHAPE_HASH 27→16 | 2,140 workspace tests green on its base (`fb0ac803`); rebase onto 1 |
| 3 | `blue/package-rename-bridge` | `0d033196` | B0074 moved-package: `legacy_packages(since, [["bpf", "kaaneru/bpf"]])` in the new root's Bluefile, `blue check --fix` rewriting `use`, qualifiers and `needs` | 2,164 green, 5 red runs; stacked on `57a545d6`, so rebase onto 1; run `blue gen/consumers.b sweep --record` before landing (prepush `swept-codes` was skipped) |

Open from 2: `moji` (a foundation) now needs `junjo`, which needs `ronri` and
`kansuu`. Decide: add `junjo` and `ronri` to the foundation list in section 1,
or move `sort` and `insert_ordered` down. Open from 3: a `use` spelled
`%i[bpf]` keeps its diagnostic without a fix; nix, the solver, the registry and
`confirm_dir` do not follow a move yet.

### The trees

A level never imports its ancestor, so a family whose members need each other
gets a new neutral root. Names were swept against the fleet (0 hits unless
noted); run `/naming` before minting one. Move in this order, one family per
landing, with a `legacy_packages` row per moved package:

| Order | Root | Children | Fleet consumers to fix |
|---|---|---|---|
| 1 | `mitoshi` 見通し (alt. `mimamori`) | rogu, tsuiseki, keisoku | none |
| 2 | `chozou` 貯蔵 (alt. `takuwae`) | teeburu, kiibariu, sutoriimu | ola-mundo (1 use) |
| 3 | `suugaku` 数学 | gyouretsu, kinji, kumiawase, toukei, ryouiki, tokumei | makoto (18 use), nupastel |
| 4 | `koubou` 工房 | kikagaku, rittai, zumen, kakou | nupastel (5 use) |
| 5 | `todokede` 届出 | jitaku, kurashi, motenashi, empresa, kinko | nix (3 use) |
| 6 | `kakehashi` 架け橋 (alt. `fushin`) | nikkusu, hyouka, kirikae, kijun, tehai, souji | nix, substrate, blackmatter-akeyless |
| 7 | `eigyou` 営業 | kyuuji, bougyo, shisei, tsuushin, heddaa, tajuu, shihyou, haibi | rubrica, ola-mundo |
| 8 | `isshou` 一生 | raifusaikuru, nisshi, anaritikusu | nupastel (11 use, 11 needs) |
| 9 | `toriyose` 取り寄せ | danpen, outou, kyasshu | none |
| 10 | `kaaneru` (exists) | bpf, btf, erufu | kanshi; LAST, kernel work is live (`land/fc-objects`) |

Rejected root names: `souko` (reserved for object stores), `madoguchi`
(escriba), `uketsuke` (spent), `sengen` (substring in engenho), `keika`
(prefix of `keikaku`). Flat: the foundations of section 1 plus `shuugou`,
`ronri`, `junjo`, and every package with no family. Before the first move, fix
the Bluefile drift the design found: undeclared imports in erufu, fuuin, gurafu,
happa, ibuki, kiibariu, kodou, sutoriimu, teeburu, and bpf→btf, keisoku→rogu,
tehai→tesuto, anaritikusu→tesuto.

### After the trees

Sections 2 to 5 stand: the 235 near duplicates fall onto one word each (C2,
C3), then the new bidamas (C4). The arnes copies `wariate::bump` (home
`danpen::deeper`) and `yushutsu::column` (home `gyouretsu::col`) move to a
foundation word once those land.
