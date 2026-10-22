# Merged graph: repairs and decisions (H0a)

Tier: DESIGN data. Rebuild with `duckdb < docs/verbs/queries/repair.sql` from the repo root.
Report with `duckdb < docs/verbs/queries/merged.sql`. Gate with `duckdb < docs/verbs/queries/gate.sql`
(an empty result is green). Region files in `docs/verbs/A` to `G` are provenance and unedited.

Inputs of the rebuild, all data: `../contracts.tsv`, `owners.tsv`, `renames.tsv`, `edge-fixes.tsv`, `added.tsv`.
Outputs: `verbs.tsv` (2,771 rows, 12 columns) and `edges.tsv` (4,748 rows). Counts below come from those runs.

## Repairs

| # | Repair | Before | After |
|---|---|---|---|
| a | dedupe `space::verb` keys | 2,839 rows, 87 keys twice or more (95 surplus rows) | 2,744 rows |
| b | break the five `composes` cycles | 5 groups | 0 (bounded recursion, depth 12) |
| c | add the seven referenced verbs | 7 dangling `to` | 0 dangling |
| d | `core` space for master verbs | 120 edges into `core::`, no rows | 20 `core` rows |
| e | duplicate edges and `inverse` | 23 surplus duplicates; 245 inverse edges lacked the reverse | 0; 245 reverses added |
| f | normalise `blue_today` and laterals | 139 rows (139 rows, 36 distinct values) outside the closed set; 3 rows with `resume` | 0 |
| g | merge spaces defined twice | 15 spaces in 2 to 4 regions | one row per key |
| h | `contract_shape`, `conforms` | none | 1,549 rows with a contract |

Edges: 4,529 raw, 23 exact duplicates removed, 3 cycle edges dropped, 2 turned into `refines`, 245 reverses added, 4,748 final.
Spaces: 163 to 168 (new: core, kankyou, saishikou, shuusei, shisutemu). Provisional spaces: still 94.

### a. Dedupe rule
For each key, one surviving row. Order: (1) measured `blue_today` (exists over partial over absent), because code that exists
beats a region's guess; (2) the row from the space's owning region (`owners.tsv`, with the reason per space); (3) the longer meaning
(more specific); (4) region letter. Laterals are the union of all rows; wave is the lowest. Owner rows lost to a row with real code in 8 keys.

### b. Cycles: one primitive each (`edge-fixes.tsv`)
| Group | Primitive | Edge removed or changed |
|---|---|---|
| jisho keys, entries | `entries` | `entries composes keys` dropped |
| shuugou set, retsu unique | `shuugou::set` | `retsu::unique composes shuugou::set` became `refines` |
| chokkan ask, choice | `ask` | `choice composes ask` became `refines` |
| kazu mod, floor, divmod | `floor` | `floor composes divmod` dropped |
| fairu write, with_temp_file | `write` | `write composes with_temp_file` dropped |

### c. The seven rows (`added.tsv`, region `H`)
`kueri::ident`, `ran::stream_seed`, `saishikou::retrying`, `shuusei::deep_merge`, `shuusei::put`: `exists:<bidama>`, each found in `bidamas/CATALOG.md`.
`shisutemu::run`: `partial:shisutemu` (the bidama has only accessors; the exec builtins exist, the verb does not).
`kankyou::get`: `rust:blue-lang-runtime`. There is no `kankyou` bidama; `getenv` is a runtime builtin. This is the one place the brief said `exists:`; I measured otherwise.

### d. The `core` space
20 rows, one per master verb that an edge targets (copy, create, diff, exists?, find, flat_map, get, group_by, has?, info, list, move, need, parse,
plan, put, read, render, run, update). Shape, kind and meaning come from `contracts.tsv`. `blue_today` is `absent`: a master verb is a design
word, not a definition. Wave 0.

### f. Closed sets
`blue_today`: `exists:<bidama>`, `partial:<bidama>`, `rust:<crate>`, `absent`. A bidama is a directory with a Bluefile under `bidamas/`
(the gate globs it). `exists:builtin`, `partial:builtin`, `partial:net`: `rust:blue-lang-runtime`. `proc`: `rust:blue-lang-proc`. `bidama`: `rust:blue-lang-bidama`.
`blue`: `rust:blue-lang-cli`. A name that is not a bidama (kenban, kenkou, joutai, meirei, sanshou, waku, wariate, yushutsu, chuuzou, kiban) became `rust:<name>`.
Laterals: the 19 plus `-` for none. `resume` became `cancel`: the three rows (a paused run is cancelled or continued) touch the same concern.
Shape repair: `kenban::exports` and `yushutsu::exports` had no parentheses; they are `exports() -> rows`.

### h. Contract columns
`contract_shape` is the shape rewritten to the contract. `conforms`: `yes` when the shape has an argument count inside the contract's range and
options only where the contract takes them; `no` otherwise; `na` when the verb has no contract (1,222 rows). A conforming row keeps its argument names.
A nonconforming row keeps its first name, drops surplus trailing arguments into `opts`, and pads missing ones from the contract.
Result: 1,378 `yes`, 171 `no`. This is soft: 133 contracts mark an argument optional (`?`) or ambient (`~`), which widens the range.
`merged.sql` lists conformance per verb; `walk`, `pipe`, `flatten`, `take`, `graft`, `slice` are the worst.

## Contracts (`../contracts.tsv`, 353 rows)
222 names used in 3 or more spaces (recomputed on the raw data) + 47 STDLIB section 3 master verbs outside that set + 84 verbs made by the renames below.
Status: 92 `stdlib` (section 3 fixes it), 251 `decided`, 10 `open`. `fail` is not a verb (STDLIB 3.5) and has no row.
Rules used for `decided`, in order: (1) STDLIB 2 and 3 fix shape, return and errors; (2) subject first, options last as one record; (3) a store
verb takes `~store` (the store may be ambient: `kankyou::get(name)`); (4) the majority arity in the data, when STDLIB is silent; (5) an argument
that only some spaces take is optional (`?`); (6) a second meaning gets its own verb (renames).

### Open contracts (10; each needs the operator)
| Verb | Question | Recommendation |
|---|---|---|
| `info` | `rogu::info` is a log level, every other `info` is state (STDLIB D5) | keep both; qualified names bound the confusion |
| `check` | findings list, or raise-all (`kyohi::check`, STDLIB 4.9) | `check` returns findings everywhere; `kyohi::enforce` raises |
| `merge` | pure value combine and `gitto::merge` share a name | keep one `merge`; `habu::merge` is now `land` |
| `apply` | one word for plan, patch, delta, migration | keep; `kiban::apply` stays behind a reconciler |
| `call` | RPC call; `keiyaku::call` has 3 positionals | keep `call(target, input, opts)`; fold `operation` into the target |
| `convert` | G's proposed master verb | accept: `convert(value, to, from?)` |
| `advance` | G's proposed master verb | accept: one step of a world, run or clock |
| `send` | G's proposed master verb | accept: `send(target, message)`; `publish` stays for fan-out |
| `on` | G's proposed master verb | accept: subject first, handler last, returns the subject |
| `verify` | verdict, findings or nil across 10 spaces | `verify(subject, policy?)` returns a verdict; raises `:tampered`; `verify?` is the Bool |

## Renames (101 rows, 89 target names; reasons per row in `renames.tsv`)
Rule: the bare name keeps the meaning most spaces share (and STDLIB's); the other meaning gets a short distinct verb. `space::old>new`.
call: kyoujin?::call>protect. check: chuukai?::check>probe, kyoujin?::check>probe, kazu::check>dimension. run: sekai?::run>simulate.
plan: gyouretsu::plan>compile, byouga?::plan>compile. diff: yuugou?::diff>delta.
merge: habu::merge>land, hani?::merge>coalesce, nisshi::merge>interleave, shuunou?::merge>patch.
put: tehai::put>write. update: haifu?::update>upgrade, paketto?::update>upgrade, shinsa?::update>catchup. create: assaku?::create>pack.
list: kokusai?::list>phrase. get: hata?::get>eval. add: paketto?::add>depend. assign: kengen?::assign>bind. at: shigoto?::at>timer.
audit: kyoukyuu?::audit>audit_lock. sign: kazu::sign>signum. log: kazu::log>logarithm, hyouka::log>build_log. root: kazu::root>nth_root, kinji::root>zero.
truncate: kazu::truncate>whole. order: angou::order>period. offset: kikagaku::offset>grow. scale: ongaku::scale>notes, seimitsu?::scale>places,
jikkou?::scale>resize, youryou?::scale>resize. drain: kyuu?::drain>unload. record: genin?::record>tape, nisshi::record>entry, katachi?::record>shape,
onsei?::record>listen. test: toukei::test>hypothesis, kentei?::test>case. trace: gyouretsu::trace>diagsum. text: kyuuji::text>plain.
status: kyohi::status>exit_status. path: settei::path>file, shoumeisho?::path>chain_of. pin: moderu?::pin>prefix, shoumeisho?::pin>fingerprint,
souchi?::pin>terminal. lock: goui?::lock>with_lock, haichi?::lock>freeze, kiban?::lock>claim, kagi?::lock>enclose. link: chuuzou::link>assemble,
shomei::link>chain. join: goui?, messeeji?, sokketto?::join>enter. split: chuukai?::split>weigh, kakuritsu?::split>fork. stack: genin?::stack>frames,
shinsa?::stack>train. group: aktaa?::group>team, heikou::group>scope. tree: paketto?::tree>closure. range: bajon?::range>constraint, souko?::range>slice.
open: kagi?::open>unseal, ami?::open>connect. close: kinyuu?::close>seal. commit: hiyou?::commit>reserve, shomei::commit>pledge.
extract: kakikae?::extract>outline, assaku?::extract>unpack, asshuku?::extract>unpack_to. identity: gyouretsu::identity>eye, shoumeisho?::identity>principal.
limit: kueri::limit>take, kyuuji::limit>throttle. pick: gitto::pick>graft, rekishi?::pick>graft. project: nisshi::project>fold.
schedule: sekai?::schedule>arrange. select: gamen?::select>choose. signal: souchi?::signal>waveform. start: raifusaikuru::start>initial.
translate: kikagaku::translate>shift, rittai::translate>shift. trim: gazou?::trim>cut, onsei?::trim>cut. version: keiyaku?::version>negotiate,
jikkou?::version>versions. window: kyoujin?::window>limiter. wrap: kagi?::wrap>shield. explain: kurasuta::explain>describe.
fetch: kyasshu?::fetch>remember. rotate (geometry): gazou?, kikagaku, rittai, retsu::rotate>turn.
Seven renames first collided with a verb the space already had (scan, advance, grant, pool, seal, quota, unpack); they got the distinct names above.
Edges that named a renamed key follow the new key.

## For the operator to veto, biggest first
1. 23 renamed rows sit on code that exists today (`exists:` or `partial:`): retsu::rotate, kazu::sign, gyouretsu::identity and ::trace, kikagaku::rotate and ::translate,
   rittai::rotate and ::translate, kueri::limit, nisshi::record, settei::path, raifusaikuru::start, shomei::link, kyuuji::text, angou::order, tehai::put,
   paketto?::tree, genin?::record, kentei?::test, chuuzou::link, ongaku::scale, kinji::root. Each is a code migration; strike a row from `renames.tsv` to keep the old name.
2. The dedupe prefers real code over the owner region (8 keys). Reversing it changes `blue_today` on those keys only.
3. `exists:<non-bidama>` became `rust:<crate>` (139 rows, 36 distinct values). Roadmap decision 5 (does `rust:` count toward coverage) stays open.
4. Contract ranges are lenient (optional and ambient arguments). Tightening any contract moves rows from `yes` to `no`; the table is the single place to do it.
5. Cycle primitives: `entries`, `shuugou::set`, `ask`, `floor`, `write`. Each is an edge in `edge-fixes.tsv`.
6. `kankyou::get` is `rust:blue-lang-runtime`, not `exists:`; `core` rows are `absent`.
7. `info` keeps two meanings (open above); `ran::walk` (random walk) keeps `walk`; `kyuu?::drain>unload` and `sekai?::run>simulate` are my names, not an agent's.
8. 94 provisional space names are still unswept (roadmap finding 6); `assaku?` and `asshuku?` look like one space.
