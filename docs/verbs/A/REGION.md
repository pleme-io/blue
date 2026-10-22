# Region A: data and knowledge (578 verbs, 30 spaces, 875 edges)

Source: `verbs.tsv`, `edges.tsv` (built from `src/` by `src/build.py`; 0 validation errors, every verb has an edge).
Drew from: Rust serde/jiff/regex/uuid, Python json/datetime/decimal/pathlib/difflib/pint, Elixir Enum/Map/Date,
Clojure core, Haskell containers/parsec, Go encoding/time/archive, Java BigDecimal/ICU, SQL/DuckDB, jq, RFC 3339/4180/6902.
Read: `docs/STDLIB.md` (§2-4, 11), `bidamas/CATALOG.md`, `bidamas/NAMES.md`, tatara-lisp-script stdlib file list.
Convention: `-` in laterals means none. `exists:builtin` marks runtime primitives (STDLIB says now, sleep, base64, json stay primitives).
`jisho` and `jikan` are DESIGN-only (no bidama yet), so their rows read `absent`/`partial` against deeta and hizuke.

## Spaces
Existing, extended: deeta (formats, encodings, paths), jisho (maps), jikan (instants, durations, schedules),
hizuke (calendar), moji (text, patterns, templates), retsu (lists), junjo (order), shuugou (sets), kazu,
toukei, gyouretsu (matrices), kikagaku (2D), rittai (3D), ronri, kansuu, kumiawase, kueri (query IR over DuckDB).
New, all PROVISIONAL (the naming sweep is owed; none is swept):
- katachi? (形, shape): schemas, validation, refinement, coercion, JSON Schema
- bunpou? (文法, grammar): lexers, grammars, parse trees, spans
- sabun? (差分, difference): diff, patch, three-way merge on text and lists
- kokusai? (国際, international): locales, catalogs, plural rules, locale formats
- hani? (範囲, range): intervals over numbers, instants, positions
- gurafu? (グラフ): graphs and trees (a tree refines a graph)
- kyuu? (キュー): fifo, lifo, priority and ring queues
- seimitsu? (精密, precise): big integers, decimals, rationals
- tanni? (単位, unit): quantities and dimensions
- kakuritsu? (確率, probability): seeded random streams, distributions, simulation
- shikibetsu? (識別, identify): uuid, ulid, nanoid, obscured integer ids
- chiri? (地理, geography): coordinates, great-circle math, cells, projections
- assaku? (圧縮, compression): codecs and archives

Only 13 new spaces beyond the 6-14 band because 17 existing ones are in scope; templating is folded into moji, schedules into jikan.

## Five highest-leverage gaps
1. katachi: no schema or validate verb. `validate` is a lateral, 2,824 types derive JsonSchema (STDLIB §11a), and every space needs one door.
2. deeta path verbs (`put`, `update`, `delete`, `merge`, `patch`, `canonical`, `address`): documents are read-only today; content addressing needs `canonical`.
3. jikan + zones: instants, durations and schedules as values (no unit-less integers); needs the one `zone_offset` primitive.
4. moji patterns + sabun: regex words exist in tatara-lisp-script but not in blue; diff/patch/merge3 has no owner outside git.
5. gurafu + kyuu: graphs, trees and queues are written by hand per space (topo, reachable, Dijkstra) and blue has no queue.

## Stays OUT of blue
- Cryptography beyond hashing (shomei/angou own it); TLS; locale data tables (CLDR) as hand-written code: load them as data (kokusai wave 3-4).
- Full ICU collation and break iterators, SAT/SMT solvers, sparse or GPU linear algebra, SVD at scale: a Rust crate behind a bidama if ever needed.
- Protobuf codegen and wire schemas: forge-gen owns it (STDLIB §4.5); deeta keeps `pack` for cbor, msgpack, bencode only.
- GIS databases, map tiles, geocoding (network): tsuushin plus an external service; chiri is pure math.
- Plotting and table GUIs; machine learning; image and audio codecs (other regions).
- Mutable arrays, hash tables with identity semantics, open file handles: blue values are immutable; kyuu and shuugou return new values.

## Wave order
- 0 (218 rows): verbs that exist today under another spelling (retsu, shuugou, toukei, gyouretsu, kikagaku, rittai, ronri, kansuu, kueri, hizuke). Cost is renames and the `?` predicate law.
- 1 (112): small blue code over existing primitives: deeta path edits and convert, jikan on hizuke, moji patterns on `regex.rs`, kazu math words, shikibetsu on `uuid.rs`, seeded kakuritsu streams.
- 2 (126): new pure-blue spaces: katachi, sabun, hani, gurafu, kyuu, bunpou, moji templates, jikan zones and schedules.
- 3 (108): need a Rust primitive or a data table: tz database, big and decimal, units table, compression (`caixa-flate2` is vendored), locales, normalize/graphemes, geo math, query on cbor/msgpack.
- 4 (14): research-grade: eigen, flow, SAT, grammar generation, cells and projections.
Reason: the cheapest verbs first, and the spaces many later verbs compose from (deeta, jikan, katachi, gurafu) before the ones that only consume them.

## Overlaps with other regions
- fairu/shisutemu/shomei/kyohi/gitto are other regions' spaces; edges name them (`fairu::read`, `shomei::hash`, `kyohi::check`, `gitto::diff`, `gitto::merge`).
- `deeta::diff` vs `sabun::diff` vs `gitto::diff`: one meaning, three subjects; sabun is the engine, the others `refine` it. Region owner of gitto should confirm.
- `jikan::schedule/next` vs any heikou/cron runner: A owns the schedule value; running a schedule is another region's `every`.
- `memoize`/`once` (kansuu) are the cache and idempotent laterals' functions; the lateral battery must own them.
- `shikibetsu::derive` and `deeta::address` call `shomei::hash`; the crypto region owns the digest set.
- `kokusai` and `moji::compare` touch accessibility and web regions (locale negotiation).

## Risks
- Name collisions: `list`, `parse`, `render`, `diff`, `merge`, `scale`, `bounds` repeat across spaces on purpose; each is the same meaning only if the laws hold. `retsu::update` and `jisho::update` take `f`, `kyuu` has no `update`.
- `deeta::pack/unpack` return bytes and `render/parse` text: two verbs because a return shape never depends on options.
- Return shapes for seeded draws (`{value, rng}` records) are verbose: expect a threading macro (state monad) as a blue form; a decision for the owner of syntax.
- 66 of 578 rows cite a fleet owner (25 of them the kueri bidama itself); the rest are `-` because I read no owner. `tatara-lisp-script` (30 rows) is cited from its file list and word names only, not its tests.
- `moji` renames (`is_blank` to `blank?`) and `kazu::near?` follow STDLIB §4.8/4.22 and were not re-checked against canonical-forms.
- Row counts per space exceed the 15-40 target for four spaces (jikan 43, moji 44, retsu 43, gurafu 35 is within) and fall below it for six (kumiawase 5, junjo 9, sabun 10, ronri 11, assaku 11, rittai 11): they are small by nature or already complete.
