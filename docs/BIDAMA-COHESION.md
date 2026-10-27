---
kind: explanation
summary: one word per job, foundations below, a complete vocabulary across the bidamas (plan)
---

# BIDAMA-COHESION — one word per job, foundations below, a complete vocabulary

Status: PLAN, 2026-10-27, measured at `392aeda`: 78 bidamas (77 plus the `zenbu`
facade), 4,223 top-level definitions. The near-duplicate gate
(`crates/blue-lang-pkg/tests/distribution.rs`, `near_duplicate_shapes_only_fall`)
counts 257 definitions in 106 shape groups, each a word the distribution wants.

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
