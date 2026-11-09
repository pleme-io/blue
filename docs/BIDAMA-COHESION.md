---
kind: explanation
summary: one word per job, foundations below, a complete vocabulary across the bidamas (plan)
---

# BIDAMA-COHESION — one word per job, foundations below, a complete vocabulary

This plan was measured at `392aeda` (2026-10-27): 78 bidamas (77 plus the
`zenbu` facade) and 4,223 top-level definitions. The near-duplicate gate
(`crates/blue-lang-pkg/tests/distribution.rs`, `near_duplicate_shapes_only_fall`)
then counted 257 definitions in 106 shape groups, each a word the distribution
wants. The [Ledger](#7-ledger) gives the state of each item today.

## 1. Destination

Every recurring shape is one word in the lowest bidama that can own it, and every
other bidama imports it. Foundations (`kazu`, `kansuu`, `deeta`, `retsu`, `ronri`,
`junjo`, `moji`, `kyohi`, `kousei`, `jisho`) depend only on each other. Service batteries depend on
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

Each domain the distribution lacks is a row of the [Ledger](#7-ledger), with
its evidence.

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

### State at `5805e0d1` (main, 2026-11-06)

Landed: the tree feature, trees 1 to 9, and one spelling per name (B0076 a
qualified name is its full path, B0077 one `use("a/b")` per tree, B0078 a
redundant use, each with a fix). 5,572 definitions in 280 files. Exact copies:
0 against `reuse.baseline`. Near duplicates: 24 definitions in 11 groups
(`NEAR_SHAPE_DEFINITIONS`), down from 252. A group whose shared shape is one call
of a named word (`self/fold`, `kansuu/maybe`) is reuse already made and is not
counted (`Near::count_forwards` turns that back on). The 11 left share a shape
and not a meaning: `ronri/both` and `either` short-circuit differently,
`kazu/in_range` and `ukai/corp_iface?` only both hold two tests. The reuse census now reads a word
through a one-call wrapper to a sibling, so `kazu::sum` written as `fold` still
names a `reduce` copy of it; the exact and near duplicate gates read the written
shape, where a wrapper is reuse.

Open, in order:

- `deeta/line_breaks` and `moji::repeated` are one word; deeta needs nothing,
  and a `use` of moji turns 53 of deeta's bare `first`, `rest`, `last` and `max`
  calls into B0012 until the retsu and kazu `legacy_names` windows close at
  0.2.0.
- A foundation takes a new edge only when it is worth every consumer's closure:
  `retsu::size` keeps its own nil check (`granularity` holds retsu at kazu), and
  `angou::atbash` keeps its own join rather than load moji.

Decided from 2: `moji` needs `junjo`, which needs `ronri`. Both depend only on
foundations and join the list in section 1. Moving `sort` below them would copy
it. Open from 3: a `use` spelled
`%i[bpf]` keeps its diagnostic without a fix; nix, the solver, the registry and
`confirm_dir` do not follow a move yet.

### The trees

A level never imports its ancestor, so a family whose members need each other
gets a new neutral root. Names were swept against the fleet (0 hits unless
noted); run `/naming` before minting one. Move in this order, one family per
landing, with a `legacy_packages` row per moved package:

| Order | Root | Children | Fleet consumers to fix |
|---|---|---|---|
| 1 | `mitoshi` 見通し | rogu, tsuiseki, keisoku | none |
| 2 | `chozou` 貯蔵 (alt. `takuwae`) | teeburu, kiibariu, sutoriimu | ola-mundo (1 use) |
| 3 | `suugaku` 数学 | gyouretsu, kinji, kumiawase, toukei, ryouiki, tokumei | makoto (18 use), nupastel |
| 4 | `koubou` 工房 | kikagaku, rittai, zumen, kakou | nupastel (5 use) |
| 5 | `todokede` 届出 | jitaku, kurashi, motenashi, empresa, kinko | nix (3 use) |
| 6 | `kakehashi` 架け橋 (alt. `fushin`) | nikkusu, hyouka, kirikae, kijun, tehai, souji | nix, substrate, blackmatter-akeyless |
| 7 | `eigyou` 営業 | kyuuji, bougyo, shisei, tsuushin, heddaa, tajuu, shihyou, haibi | rubrica, ola-mundo |
| 8 | `isshou` 一生 | raifusaikuru, nisshi, anaritikusu | nupastel (11 use, 11 needs) |
| 9 | `toriyose` 取り寄せ | danpen, outou, kyasshu | none |
| 10 | `kaaneru` (exists) | bpf, btf, erufu | kanshi |

The consumers named here warn (B0021) until each moves to the new paths:
`blue gen/consumers.b fix <repo>` rewrites one.

Rejected root names: `souko` (reserved for object stores), `madoguchi`
(escriba), `uketsuke` (spent), `sengen` (substring in engenho), `keika`
(prefix of `keikaku`). Flat: the foundations of section 1 plus `shuugou`,
`ronri`, `junjo`, and every package with no family. The "Bluefile drift" the
design listed is not drift: `blue lock` derives `needs` from the `use` forms,
a Bluefile row only narrows a range, and B0019 gates the lock.

Moving a family, as tree 1 did: `git mv` each package under the root and
delete its Bluefile and lock (a level has none); write the root's Bluefile with
`legacy_packages`; `blue check --fix` each level (it relocks the root); edit
`zenbu` by hand to `use` the root; one NAMES.md row for the tree; `blue lock`,
`gen/regen.b`, the distribution suite and a consumer sweep. Tree 1 found four
defects, each fixed with a red test: `--fix` on a level read a Bluefile beside
the file; the distribution gate ran no level's tests; mokuroku keyed verbs by
package only; a B0015 reorder parted a waiver from its `use`, after which
`--fix` deleted waived imports from `zenbu`.

### After the trees

Section 3 is done. Four words of section 2 are not written (see the Ledger). The arnes copies
`wariate::bump` (home `toriyose::danpen::deeper`, now `kansuu::maybe`) and
`yushutsu::column` (home `suugaku::gyouretsu::col`) move to a foundation word.

## 7. Ledger

✅ built and tested · ⏳ in progress · ❌ not built

| Item | State | What makes it true |
|---|---|---|
| section 2 merges | ⏳ in progress | Written: `kansuu::maybe`, `apply_when`, `juxt_with`; `retsu::if_empty`; `junjo::sort_with`, `insert_with`; `jisho::get_any`; `ongaku::chord_from_root`. Not written: `retsu::fold`, `retsu::find_where`, `retsu::span_end`, `kansuu::lift2`. |
| section 3 layering | ⏳ in progress | `kyuuji` no longer needs `tesuto`; `kyohi` holds `raised`. `tsuushin` still needs `kyuuji` (`bidamas/eigyou/tsuushin/tsuushin.b`). |
| trees 1 to 10 | ✅ built | Each root exists under `bidamas/`, with its `legacy_packages` rows; tree 10 is `bidamas/kaaneru/{bpf,btf,erufu}`. |
| exact copies | ⏳ in progress | `reuse.baseline` records 4 copies, one each in `examples/05_errors.b`, `gen/prepush.b`, `gen/retired.b` and `spec/docs.b`. The census holds them and refuses a new one (`blue census --reuse`). |
| near duplicates | ⏳ in progress | `NEAR_SHAPE_DEFINITIONS = 24` (11 groups) in `crates/blue-lang-pkg/tests/distribution.rs`, down from 252. The arnes copies `wariate::bump` and `yushutsu::column` still wait for a foundation word. |
| C0: the newline-escape ban | ✅ built | B0065 (`docs/DIAGNOSTICS.md`). |
| CLI arguments | ✅ built | `bidamas/hikisuu`. 14 bidamas parsed `"--flag"` by hand at the 2026-10-27 measure (C5). |
| environment, dotenv | ⏳ in progress | `bidamas/settei` resolves settings from defaults, a file and the environment. No `kankyou` bidama and no dotenv reader exist. 22 bidamas called `getenv` directly (2026-10-27). |
| time, durations, cron | ❌ not built | No `jikan` bidama. `hizuke` is the calendar only. |
| parallel map, timeouts, supervision words | ❌ not built | No `heikou` bidama ([`ASYNC.md`](ASYNC.md)). |
| rate limit, circuit breaker, bulkhead | ❌ not built | No `kyoujin` bidama. `bougyo` has no rate posture. |
| files and paths | ⏳ in progress | `bidamas/fairu` has 8 definitions. |
| processes | ⏳ in progress | `bidamas/shisutemu` has 15 definitions. Some bidamas still call `exec_*` directly. |
| HTTP client | ⏳ in progress | `eigyou/tsuushin`: URL and a basic request. No JSON or pagination helpers. |
| encodings | ⏳ in progress | base64 and hex in `shinsuu`. No base64url and no URL encoding outside `kyuuji`. |
| UUID, semver, regex | ❌ not built | No definition in `bidamas/`. Regex needs a runtime primitive. |
| Kubernetes (`kurasuta`) | ⏳ in progress | `bidamas/kurasuta` holds the `kinds` level. The reads of `STDLIB.md` §4.18 are not built. |
| secrets, GitHub, units (`himitsu`, `habu`, `joujuu`) | ❌ not built | Designed in `STDLIB.md` §4.18 to §4.21. No such bidama. |
