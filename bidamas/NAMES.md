# The bidama name ledger

**Every package directory in `bidamas/` must have a row here, and every row must
have a package directory. A mismatch is a red build**
(`blue-lang-pkg/tests/distribution.rs::every_bidama_has_a_name_ledger_row`).

## Why this file exists

Fourteen of these names were minted inline, in the middle of writing the
library, without running the `/naming` procedure. Step 4 of that procedure is
the collision sweep against the fleet, and skipping it cost three names:

- `narabi` (並び) collided **exactly** with a live Neovim tabline crate — same
  romanization, same kanji, same crate identifier;
- `koyomi` (暦) collided **exactly** with a live calendar app, on the same
  subject, across a repo, a binary and a config-app namespace;
- `kika` (幾何) was a strict one-character prefix of live `kikai` (機械) —
  measured at 665 occurrences of the string `kika` across five repos, **664 of
  them `kikai`**, so no query isolated the geometry package.

None of that was discoverable from inside this repo, and none of it was caught
by any test, because **nothing required a name to have been adjudicated before
it shipped.** A skill cannot enforce that: a skill only runs when somebody
invokes it, and the whole failure was not invoking it.

So the enforcement is here instead, and it is deliberately dumb: a package
without a row fails the build. That does not prove the sweep was *done well* —
a row can be written carelessly. It proves the question was *asked*, at the
moment the package landed, which is the step that was actually skipped.

**Tier: CI-caught, not unrepresentable.** A determined author can write a row
that says nothing. The honest claim is that adding a package silently is no
longer possible.

## What a row must record

| field | why |
|---|---|
| name + kanji | the word being claimed |
| gloss | the Law 2 test — can a reader guess the job from this? |
| swept | the date the fleet collision sweep ran |
| verdict | KEEP / KEEP_WITH_NOTE / RENAMED-FROM |
| note | the collision or hazard worth carrying forward, or `—` |

**Sweep the gloss, not only the word.** `kōshi` (格子) was rejected fleet-wide
on 2026-08-01 for a *gloss* collision — it glosses to "lattice", and blue
already had one in `waku`'s posture lattice. The words differ; the glosses were
one word, and a reader given romaji plus one English gloss is routed to the
wrong crate.

**And remember what makes this set dangerous** (`theory/NAMING.md`, the `goi`
語彙 rule): a metaphor family is inexhaustible, but a **domain lexicon is not**.
It draws from exactly the same well the fleet mines for its own Japanese
primitives, so collisions here are the expected case, not the surprising one.

## The ledger

| name | kanji | gloss | swept | verdict | note |
|---|---|---|---|---|---|
| `kazu` | 数 | numbers — abs, sign, clamp, pow, near | 2026-08-01 | KEEP | sibling `shinsuu` (進数) contains 数; different word, no retrieval harm |
| `moji` | 文字 | strings | 2026-08-01 | KEEP_WITH_NOTE | strict prefix of live `mojiban` (文字盤, rich text rendering) sharing the whole 文字 morpheme — different altitude (a bidama vs a fleet crate), retrievability unharmed since `mojiban` is the longer string |
| `retsu` | 列 | lists, made total — size/first/rest/is_empty | 2026-08-01 | KEEP | strict suffix of its own sibling `gyouretsu` (行列); 行列 legitimately *contains* 列, so the containment teaches rather than confuses |
| `kansuu` | 関数 | function combinators — compose, pipe, flip | 2026-08-01 | KEEP_WITH_NOTE | `kan-` is the fleet's densest head (5 live); mint no sixth |
| `ronri` | 論理 | predicate algebra — every, any, none | 2026-08-01 | KEEP | — |
| `shuugou` | 集合 | sets — union, intersection, subset | 2026-08-01 | KEEP | tightest Law 2 fit in the set; zero collisions |
| `junjo` | 順序 | ordering — sort, binary search, min_by | 2026-08-01 | RENAMED-FROM `narabi` | 並び collided exactly with the live `narabi` Neovim tabline crate; 順序 also covers the order-*relation* ops "lineup" under-described |
| `toukei` | 統計 | descriptive statistics — mean, median, stddev | 2026-08-01 | KEEP_WITH_NOTE | spends the umbrella word for *all* statistics on a descriptive-only package |
| `kumiawase` | 組み合わせ | combinatorics — factorial, combinations, catalan | 2026-08-01 | KEEP_WITH_NOTE | 組 overlaps `shikumi`/`takumi`, not at word level |
| `gyouretsu` | 行列 | vectors and matrices — dot, transpose, matmul | 2026-08-01 | KEEP | best-named of the set |
| `kikagaku` | 幾何学 | plane geometry — distance, shoelace area | 2026-08-01 | RENAMED-FROM `kika` | 幾何 was a strict prefix of live `kikai` (機械): 664 of 665 `kika` hits were `kikai`. **Dissent recorded (1 of 3 lenses):** the only discipline-form (学) outlier among bare-noun siblings; cost accepted |
| `shinsuu` | 進数 | base conversion + checksums — to_hex, from_base | 2026-08-01 | RENAMED-FROM `fugou` | 符号 is the standard word for *sign* (符号付き整数) and sibling `kazu` already ships `sign`/`abs` — the name pointed at another package's job. **Dissent (1 of 3):** `luhn_valid`/`digit_sum` are fixed-decimal, so 進数 under-covers ~2 of 11 functions |
| `hizuke` | 日付 | Gregorian date arithmetic — is_leap, day_of_week | 2026-08-01 | RENAMED-FROM `koyomi` | 暦 collided exactly with a live calendar app on the same subject. **Mnemonically LATERAL, not an improvement** — 暦 was arguably the apter gloss; collision-forced |
| `angou` | 暗号 | number theory + classical ciphers | 2026-08-01 | KEEP_WITH_NOTE | two-headed package (number theory + ciphers); the "code/code" pair with `fugou` dissolved when that package became `shinsuu` |
| `ongaku` | 音楽 | twelve-tone music theory — scales, triads | 2026-08-01 | KEEP | rename to `gakuri` refuted 3/3; shared 音 with `oto` is Law 3 working |
| `seimei` | 生命 | cellular automata — Rule 110, Conway's Life | 2026-08-01 | KEEP | rename to `saibou` refuted 3/3 |
| `ran` | 乱 | seeded deterministic PRNG | 2026-08-01 | KEEP | rename to `chuusen` refuted 3/3; 乱 is the canonical morpheme (乱数). An English homograph is not a naming law — cf. `tear`, `tend`, `gen`, `blue` |

## Adding a package

1. Run `/naming` — **before** writing the code, not after.
2. Sweep the word, its near-homophones **and its gloss** against the fleet
   (~966 repos under `~/code/github/pleme-io/`, plus `theory/VOCABULARY.md`).
   A bare recursive grep at the org root reads zero files and returns empty,
   which reads as "no matches" and is a lie — use `find | xargs`, and run a
   positive control that fires before trusting any absence.
3. Add the row here in the same commit as the package.
4. Raise the package-count floor in `flake.nix` and the `>= 17` floor in
   `distribution.rs`.
