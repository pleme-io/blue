---
kind: explanation
summary: verb graph region B: storage and state
---

# Region B: storage and state (2026-10-22)

458 verbs in 20 spaces, 706 edges (1.54 per verb). Above the 6-14 aim on purpose: the region names 20 separate domains and no space passes 41 verbs. Drawn from: Python pathlib/shutil/tarfile, Go os/io/fs and database/sql, Elixir File/Ecto/GenStage/Broadway, Erlang/OTP (ETS, mnesia), Rust std::fs/sqlx/tantivy/redb, Java JDBC/NIO, Swift FileManager/CoreData, Redis and etcd command sets, S3/GCS APIs, Kafka/Pulsar log semantics, SQS visibility timeouts, Temporal/Cadence/Step Functions, git plumbing, IPFS/CAR, RFC 6962 (merkle), CRDT literature (Shapiro et al.), restic/borg.
Fleet column cites the owning repo at repo level (read each CLAUDE.md or README one-liner, not function by function). `partial:shisutemu` means a runtime word exists today (`read_file`, `walk_dir`, ...) and STDLIB §4.1 promotes it into `fairu`.

## Spaces (S = existing, N = new provisional name with ?)
| space | gloss | verbs |
|---|---|---|
| fairu (S, design) | files and paths | 41 |
| asshuku? (N) 圧縮 | compression, archives, binary deltas | 14 |
| souko? (N) 倉庫 | object and blob stores (S3, R2, GCS, local) | 30 |
| teeburu (S) | relational databases: connection, pool, transaction, schema | 36 |
| ikou? (N) 移行 | migration over any store (SQL, kv, files, events) | 15 |
| shuunou? (N) 収納 | key-value and document stores | 30 |
| sakuin (N, fleet crate exists) 索引 | full-text, inverted and vector indexes | 29 |
| kyasshu? (N) | caches: TTL, LRU, read/write-through, invalidation | 19 |
| nisshi (S) | event logs, streams, event sourcing, CDC | 32 |
| taiki? (N) 待機 | durable queues | 20 |
| genbo? (N, daicho crate name) 原簿 | content-addressed object store, merkle trees | 22 |
| rekishi? (N) 歴史 | versions and history on any value (git is one kind) | 22 |
| yuugou? (N) 融合 | CRDTs and version vectors | 21 |
| hozon? (N, fleet repo exists) 保存 | backup, restore, replication | 19 |
| himitsu (S, design) | secrets | 24 |
| settei (S) | typed config store | 15 |
| rokku? (N) | locks, leases, leader election | 14 |
| raifusaikuru (S) | state machines, extended to persisted workflows and sagas | 22 |
| shinsuu (S) | numbers for storage: checksums, bytes, varints, sizes | 13 |
| shomei (S) | hashes, signatures, hash chains, merkle proofs | 20 |

## The five highest-leverage gaps
1. **One store contract.** souko, shuunou, teeburu, sakuin, genbo and settei all answer `get`/`need`/`has?`/`put`/`create`/`update`/`delete`/`list`/`watch` with the §3.2 laws. Only the spaces differ. 12 of the 20 spaces have no bidama today, and 2 more (fairu, himitsu) are only designed in STDLIB.
2. **The data layer.** teeburu has 8 definitions (`open`, `rows`, `insert`, `latest` and their statement builders); the fleet has `pleme-database` (pool, transaction, repository) and `shinka`. `with_transaction`, `update` with conflict, schema `diff`/`plan` and `ikou::apply` close the largest owed section (STDLIB §11).
3. **`rokku` (locks and leases).** Redis locking, shinka leader election, raifusaikuru single writer, ikou single runner and hozon promote each hand-roll one. `renew` and `revoke` become the one lease vocabulary (also himitsu, taiki, kyasshu).
4. **`genbo` + `rekishi`.** A content-addressed store and a history over it give backup, nisshi snapshots, cartorio/reduto-style merkle identity and daicho a shared blue surface. gitto becomes a refinement of rekishi.
5. **`kyasshu` as the cache lateral.** `fetch` (get or compute once, single-flight), `invalidate` and `memoize` replace the ad hoc caches in pleme-database, pleme-redis and token-cache-go.

## Stays out of blue (and why)
- Database engines, query planners, B-tree and LSM internals, WAL writers: C/Rust engines behind the `open` seam (CONTAIN THE C). Blue speaks their protocol (pg wire exists) or embeds one behind a bidama.
- Filesystem and volume internals: mount, fsck, partitioning, LVM, ZFS send. Nix and the module system own host layout (STDLIB §4.1 left out chmod/symlink for the same reason; `fairu::link` and `mode` are rows configured off, wave 3).
- Distributed consensus (Raft, Paxos) and broker internals (Kafka brokers, Redis server): `rokku`/`taiki`/`shuunou` are clients.
- ORMs and entity derives: STDLIB §4.23 already excludes them; haibi renders schema from Bluefile rows.
- Embedding model training and serving: `sakuin::embed` calls a provider.
- GUI file managers and cloud-drive sync clients (gaveta-client).

## Wave order (reason)
- **0 (64 rows):** exists, or a rename of a builtin: fairu path nouns and core verbs, nisshi `verify?`/`canon`/`genesis`, raifusaikuru declarations, shomei hash/chain/merkle renames, settei read/get/merge, `teeburu::quote`.
- **1 (92):** the verbs most programs reach first: fairu `read_bytes`/`stream`/`update`, souko core, teeburu core + `with_transaction`, ikou plan/apply/status, kyasshu core, himitsu read/get/need/redact, shomei `hash_stream`/`random`/`equal?`, nisshi open/append/replay. They need only primitives that exist or move from tatara-lisp-script (fs, sops, hash).
- **2 (176):** everything needing a new runtime primitive but a known shape: pools, listen/notify, search index, queues, locks, history, archives, backup, shuunou core.
- **3 (120):** real engines and depth: CRDTs, merkle consistency, bisect/blame, object versions and retention, sagas, data capture, vector search.
- **4 (6):** crypto-shredding `forget`, `promote`, `barrier`, `converge`, index `optimize`, kv `compact`: need an operator decision or a sibling region.
Order inside a wave follows the dependency edges: rokku before ikou/raifusaikuru writers; genbo before rekishi before hozon.

## Overlaps with other regions
- `gitto` (VCS region): rekishi generalizes gitto::merge/diff/create/read. One owner of 3-way merge text (`rekishi::three_way`) is needed.
- `deeta`/formats: `asshuku` compress/archive may belong to a formats or bytes region; `shinsuu::to_bytes`/`to_varint` likewise. Merge, do not duplicate.
- `heikou`/`saishikou`: taiki::work and ikou::backfill compose them; retry and deadline stay there.
- `rogu`: `himitsu::redact` guards every log line; the hook belongs to rogu.
- Observability region: `nisshi::publish`/`subscribe` vs NATS/Vector streams; `kyasshu::info` vs metrics.
- Security region: himitsu `encrypt`/`decrypt`/`derive` vs angou and shomei; keep one set (shomei owns primitives, himitsu owns the secret-shaped door).
- Cloud/k8s region: souko policy and lifecycle vs terraform resources; rokku k8s Lease backend vs kurasuta.
- Data/ML region: `sakuin::embed`, `similar`, `nearest`; `kueri` already renders SQL (teeburu::query accepts its IR).

## Risks
- **Verb collisions inside the region.** `renew`/`revoke` (4 spaces), `touch` (fairu only, since kyasshu uses `renew`), `snapshot` (nisshi, hozon, shuunou, genbo-adjacent), `stream`, `seal` (nisshi freeze, never himitsu encrypt), `copy` (7 spaces). Each carries one meaning; the matrix gate must hold them.
- **`partial` counts are by name only.** blue_today reads the bidama catalogue and runtime docs, not call sites; re-measure before wave planning.
- **Names are unswept.** `taiki`, `rokku`, `ikou`, `souko`, `rekishi`, `kyasshu`, `shuunou`, `asshuku`, `yuugou` matched 0 repo directories (`jikou` is near `ikou`); `sakuin`, `hozon`, `genbo` name existing same-domain fleet crates (reuse, not collision). The `naming` skill's sweep, including crates.io, is owed for each.
- **Atomicity claims differ by backend.** `souko::move`, `hozon::mirror` and `nisshi::append_all` promise less on object stores than on a local disk; the laws must say which verbs are atomic and which raise `:not_atomic`.
- **Event sourcing and erasure conflict.** `nisshi::forget` needs per-subject keys before the hash chain can stay valid (wave 4, DESIGN only).
- **Fleet citations are repo-level.** Function-level owners (for example which daicho crate holds `list`/`info`) were not read.
