---
kind: explanation
summary: the naming sweep of the verb graph's spaces, and the rulings
---

# Naming sweep: what is applied and what the operator decided

Source: `N1.tsv` and `N2.tsv` (94 provisional spaces swept 2026-10-22: 28 KEEP, 39 KEEP_WITH_NOTE, 27 REJECT). Method: the `naming` skill over the whole fleet with a file-count control, plus crates.io with a User-Agent and positive and negative controls.

## Applied before the rulings
The 23 REJECT names whose swept alternative is unambiguous are renamed in `merged/` through `merged/space-renames.tsv`, the last stage of `queries/repair.sql`. Delete a row there to keep the old name and rerun the script.

## Decided 2026-10-22
The operator accepted every recommended default. Each row below is a row of `merged/space-renames.tsv` or a note on a kept name.

| Subject | Decision |
|---|---|
| `assaku` | merged into the existing space `asshuku` (duplicate verb keys keep the `asshuku` row) |
| `shigoto`, `tsuuchi` | kept, provisional mark dropped: each is the blue face of a live repo (a word on two rungs stays on both) |
| `haichi` | renamed `uwagaki` |
| `hakkou` | merged into `rirezu` (release); duplicate keys keep the `rirezu` row |
| `chizu` and `chiri` | stay two spaces. `chizu` is maps as data (layers, tiles, features, scale). `chiri` is geography as coordinates (points, distance, projection, geocoding) |
| `rokku` and `goui` | stay two spaces. `rokku` is local: one process or one host (mutex, file lock, semaphore). `goui` is distributed: acquire, elect, fence, renew across nodes |
| `kyuu` (now `junban`), `taiki`, `messeeji`, `kyuuji` | stay four spaces. `junban` is the in-memory structure and its ordering (queue, heap, priority). `taiki` is the store-backed queue (durable, leased). `messeeji` is the network message queue (ack, nack, park, seek). `kyuuji` stays HTTP routing |
| `yuugou` | renamed `tougou` |
| `keikaku` | renamed `puran` |
| `tegata` | ratified as the space name. `theory/TEGATA.md` still calls the name proposed; the doc is to be ratified as the same name (theory is not edited here) |
| `genbo` | kept. It stays the blue face of the `daicho` object database; the space is named only for as long as the two share one vocabulary |
| `kumo` | renamed `kuraudo`: the crate `kumo` is taken (a web crawler) |
| `moderu` | renamed `mokei`: the crate `moderu` is taken (a glTF representation) |
| `sekai` | renamed `waarudo`: the crate `sekai` is taken (a dead multi-agent observer). `sekkei`, `seki` and `tenkai` are near neighbours, not alternatives |
| `ky-` head | kept as is (`kyohi`, `kyuuji`, `kyasshu`, `kyoui`, `kyoujin`) |
| `chuukai` | kept, with the word taken as 仲介 |

The three crate alternatives were checked on 2026-10-22: no file in six org directories (`rg --no-ignore -l -w -i -g '!**/target*/**'`), no directory, crates.io 404 with the User-Agent `pleme-io-ci`. Controls: `shikumi` 2076 files, `serde` crates.io 200, a nonsense word 0 files and 404.

## Decided 2026-10-22: verb contracts
`contracts.tsv` has no `open` row left (10 became `decided`):

- `info` keeps both forms. No field changed.
- `check` returns `[finding]`, empty when sound. Its raising form is `kyohi::enforce` (new contract row `enforce`, new verb row, edge `kyohi::enforce composes core::check`). The shipped `kyohi::refuse(refusals) -> nil` raised, which is the `enforce` meaning; its callers (kinji, kueri, settei, chokkan) call `enforce` with `kind: :first` since 2026-10-23, `kyohi::check(subject, rules)` returns the findings, and okite D0014 pins the equality.
- `merge` is one master verb; `gitto::merge` refines it (`edges`: `gitto::merge refines core::merge`).
- `apply` stays behind the reconciler: an effect that raises `conflict`.
- `call(target, input, opts)` stays.
- `verify` raises `tampered` on a bad verdict. `verify?` returns Bool and is its predicate pair (`core::verify pairs core::verify?`).
- `convert`, `advance`, `send` and `on` are master verbs as written.

Generated rows: `merged/added.tsv` (`kyohi::enforce`) and `merged/added-edges.tsv` (four edges), read by `queries/repair.sql`.

## Decided 2026-10-23, operator delegated: the frontend spaces (F0)
The operator delegated the names on one condition: no conflict in the fleet, on crates.io or among the bidamas and spaces. Each name below passed and carries no `?`.

| Subject | Decision | Gloss |
|---|---|---|
| `yokyuu?` (working name) | named `danpen` | 断片, fragment: GraphQL documents, fragments, composition, masking, persisted hashes. `yokyuu` is a wrong romanization of 要求 (`youkyuu`), and "requirement" is the sense the space `youken?` already holds |
| `burauza?` (working name) | named `burauza` | ブラウザ, browser: the browser runtime (mount, apply, listen, request, save, install) |
| `kyasshu?` | promoted to `kyasshu` | キャッシュ, cache. The `ky-` head ruling above already kept it; it gains `normalize`, `settle`, `watch` |
| `gamen?` | unchanged | F1 owns its rows; it gains `labels`, `island`, `hydrate` |

Collision check, 2026-10-23: `rg --no-ignore -l -w -i` over the pleme-io root found 0 files for `danpen` and `etsuran`, and for `burauza` only the two design docs that proposed it (`FRONTEND-PLAN.md`, `BLUE-FRONTEND.md`). No repo directory. crates.io 404 for both with the User-Agent `pleme-io-ci`. Controls: `shikumi` 1859 files, 138 `caixa` directories, `serde` crates.io 200, a nonsense word 404. Near names checked: `handan` and `shindan` (repos, a different head), `furagu?` (rules out the loanword `furagumento`), `kueri` and `mondou` (rule out a query word), `youken?` (rules out "requirement").

Verbs: one verb per meaning, so four plan words take the existing verb.

- `print` is `danpen::render` (master `render`: a value to canonical text).
- `mask` is `danpen::select` (vocab `select`: only the listed parts of a value). `tokumei::mask` keeps its meaning, hide characters.
- `patch` is `burauza::apply`, which refines `gamen?::apply` (make a surface show the patches). Master `patch` returns a value; this changes a live page.
- `fetch` is `burauza::request`, which refines `tsuushin::request`. Master `fetch` brings a remote thing to local disk.
- `persist` is `burauza::save`, which refines `kyasshu::save` (vocab `save`: write a held state to storage).

New vocab rows: `fragment`, `settle`, `labels`, `island`, `hydrate`, `mount`, `install`. `mount` and `install` also give `kyuuji::mount`, `paketto?::install` and `ryuutsuu?::install` a contract, so the g2 baseline shrank by three (banked with `blue verbs check --record`).

## Decided 2026-10-24: `kyuuji::match` is `kyuuji::resolve` (F2)

- The plan named the wave 1 verb `match`. `match` is a tatara special form, and a special form is a `match` arm in no environment, so a bidama definition of that name can never be called. F2 shipped it as `kyuuji::resolve(app, req) -> route and params or nil`; the row is in `bidamas/mokuroku/graph/kyuuji.b`.
- `resolve` takes a request to the route that answers it, and its params. There is no master verb `resolve` to refine, so the row stands alone.
