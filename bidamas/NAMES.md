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
| `kazu` | 数 | numbers — abs, sign, clamp, pow, near | 2026-08-02 | KEEP | Clean on every surface (repo / crate / org.yaml / theory), with a firing control. Siblings `shinsuu` (進数) and `kansuu` (関数) contain 数 in **kanji only** — both take the on'yomi `-suu`, so `kazu` is not a substring of either romaji identifier and the containment is invisible to search. Every non-blue string hit is vendored fixture data (`kazusa`, `mikazuki`, a `~kazu/` URL). Strongest name in the set. |
| `moji` | 文字 | strings — empty, present, longer | 2026-08-02 | KEEP_WITH_NOTE | Strict prefix of live `mojiban` (文字盤) sharing the whole 文字 morpheme. **Note rewritten 2026-08-02 — the prior rationale ("retrievability unharmed since `mojiban` is the longer string") was BACKWARDS: searching the shorter string returns every instance of the longer, which is why the longest name in a chain is self-retrievable and the shortest is not.** Measured: fleet `moji` hits are dominated by **`emoji`** (~3.7–8.5k), an interferer ~30× larger than the `mojiban` the old row cited and never mentioned. Kept anyway, because that mass is **noise, not a misroute** — vendored Unicode tables and font data, unlike `kika`→`kikai` where the interferer was a live pleme-io primitive a reader could believe they had arrived at. `emoji` contains `moji` as a *suffix*, so one leading word boundary excludes the whole family; token-anchored, bare `moji` is ~20 hits. Name-vs-name interference is `mojiban` at ~120 — 5–8× below the 664 that forced the `kika` rename — and blue depends on `katsuji`, on `mojiban` **nowhere**, so the two never meet in a build graph. Rename to `mojiretsu` reached a 2-of-3 majority and was **refuted 3-of-3**: it keeps 文字 whole so it cures nothing, and would make `retsu` (9 importers) a suffix of two live siblings. Do not re-propose. 0 importers. |
| `retsu` | 列 | lists, made total — size/first/rest/is_empty | 2026-08-02 | KEEP | Strict suffix of its own sibling `gyouretsu` (行列). **Measured, replacing the prior unevidenced assertion:** inside blue `retsu` ≈ 54 vs `gyouretsu` = 3, ~94% precision — the **inverse** of kika/kikai (664 of 665 landing on the wrong word). In *prefix* containment the longer word drowns the shorter; here the contained word is the hub (9 importers vs `gyouretsu`'s 0) and stays dominant. And the containment is semantic, not accidental: 幾何/機械 share no kanji at all (a romaji coincidence pointing at machinery), while 列 ⊂ 行列 is the same kanji and `gyouretsu.b:2` does `use("retsu")` — the name mirrors the dependency, so a reader who lands on the wrong one has been taught the relationship. |
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
| `zenbu` | 全部 | the facade — every bidama in the distribution, as one dependency | 2026-08-02 | KEEP_WITH_NOTE | The only STRUCTURAL name in the set. Every sibling is a subject noun (numbers, lists, geometry); this one names the *collection*, deliberately — the `goi` (語彙) rule says a domain lexicon is exhaustible, so a facade that spent a subject word would burn one for nothing. **`soroi` (揃い) was the first choice and is REFUTED by the sweep:** it is already live in blue's OWN spec as `(defsoroi …)` (`theory/BLUE.md` §V.10, `theory/VOCABULARY.md`), glossed *"a matched set — nothing missing"*. Same word, same kanji, same gloss, same repo — the `koyomi` failure exactly, and invisible from inside `bidamas/`. That hit also refutes **`ichishiki` (一式, "one complete set")**, which is clean on the *word* (0 fleet hits) and collides on the *gloss* — the `kōshi` (格子) rejection of 2026-08-01 repeated. **Measured 2026-08-02** over the 970 repo directories under `~/code/github/pleme-io/` (`rg --no-ignore`, excluding `.git`/`target`/`node_modules`/`.direnv`; positive control `kikai` = 1163 occurrences in 176 files, so the absences below were *read*, not assumed): `zenbu` = 8 raw hits, **0 real** — every one is base64 payload inside a vendored `*.caixa.lisp` or Japanese prose in `caixa-erased-serde/benches/twitter.json`. That is the `emoji` class of noise, not a live primitive. 0 repo-name hits; 0 in `theory/VOCABULARY.md`; 0 inside blue. **The one containment worth carrying:** bare `zen` IS live (`opencode-zen`, `kura-provider/src/zen.rs`, `dougu/src/zen.rs`). It is the benign direction — `zenbu` is the LONGER string and therefore self-retrievable, and 禅 shares neither kanji nor meaning with 全部, so a reader who lands here while searching `zen` cannot believe they arrived. Contrast `kika`→`kikai`, where the interferer *was* the answer 664 times in 665 and offered no such signal. 0 importers, and structurally there will never be any: the facade is the leaf every other bidama is upstream of. |
| `shisutemu` | システム | system — process, filesystem, env, clock | 2026-08-03 | KEEP_WITH_NOTE | Katakana loanword for *system*, written honestly rather than forced into a kanji compound — the package is the HOST side of the runtime (the `sys` feature seam: process captures, filesystem, env, clock), and that is the surface the gloss pins to, so the name cannot read as "system" the abstraction. **Measured 2026-08-03** over `~/code/github/pleme-io/` (`rg --no-ignore`, `.git`/`target`/`node_modules` excluded): `shisutemu` = 6 hits, all inside blue (this package + the zenbu facade) — 0 fleet repos, 0 crates, 0 `theory/VOCABULARY.md` entries, 0 repo names. Not a prefix of, nor prefixed by, any sibling: `shigoto` 仕事, `shikumi` 仕組み, `shinsuu` 進数, `shuugou` 集合, `seimei` 生命 all diverge from `shisutemu` at the second mora. The near-homophone worth carrying is the ENGLISH *system* / `sistemas` — the same gloss in roman scripts, which is exactly why the gloss is the runtime surface and not the bare word. 1 importer (zenbu). |
| `deeta` | データ | data — JSON parse, get, stringify, read safely | 2026-08-03 | KEEP_WITH_NOTE | Katakana loanword for *data*, spelled with the full three mora `deeta` rather than the two-mora `deta` because **`deta` is a substring of the fleet's dense `data-` English words** (`dataset`, `datadog`, `data-plane`) and every `data`-prefixed identifier a search returns; `deeta` is contained in none of them. **Measured 2026-08-03** over `~/code/github/pleme-io/`: `deeta` = 6 hits — 5 inside blue, 1 base64 payload inside vendored `caixa-jpeg-decoder/jpeg-decoder.caixa.lisp` (the `emoji` noise class, not a live primitive). 0 fleet repos, 0 `theory/VOCABULARY.md` entries. The GLOSS is the dense half — bare "data" would be the `kōshi` failure — so it is pinned to the JSON surface, and no live vocabulary entry glosses a primitive as just "data" (`dialeto`, `urdume`, `crivo` all carry specific data-*glosses*). Depends on nothing: the json primitives are runtime layer 4, so this is the leaf of leaves. 1 importer (zenbu). |

## Adding a package

1. Run `/naming` — **before** writing the code, not after.
2. Sweep the word, its near-homophones **and its gloss** against the fleet
   (~966 repos under `~/code/github/pleme-io/`, plus `theory/VOCABULARY.md`).
   A bare recursive grep at the org root reads zero files and returns empty,
   which reads as "no matches" and is a lie — use `find | xargs`, and run a
   positive control that fires before trusting any absence.
3. Add the row here in the same commit as the package.
4. Raise the package-count floor in `flake.nix` and the `>= 19` floor in
   `distribution.rs`.
5. Add a `needs(...)`/`use(...)` pair to **`zenbu`**, the facade. It is an
   ordinary bidama that declares every other one, so a consumer can take the
   whole distribution as a single dependency — and a package left out of it is
   a package the facade silently stops covering.
   `granularity.rs::the_facade_is_an_ordinary_bidama_with_many_needs` fails the
   build if you forget.
