# P2P: a zero-server peer network in blue, and a game platform on it

Status: DESIGN, 2026-11-09, revised after an independent review the same day.
Owner of the design: this file. It refines [`SUBSTRATE.md`](SUBSTRATE.md)
layer 3 (phases L3.1 and L3.2) and
[`theory/IBUKI.md`](https://github.com/pleme-io/theory/blob/main/IBUKI.md).
The tier ledger at the end is the only place a status is claimed.

## 1. Destination

Peers run blue programs that agree on shared state with no server. Every state
change is a pure blue transition `(state, input) -> state`. A peer signs its
step, runs the transition, and announces the new root. Other peers fetch only
the blocks they lack, verify each block against the root, re-run the
transition, and exclude a peer whose root does not match, with a signed proof.
The network is a set of separate blue libraries (bidamas). Any blue program
embeds them, on any placement: CLI, node service, WebAssembly component, mado
desktop, asobi mobile. A game is one consumer. The Aqui neighbourhood map mesh
and local-first apps are others.

**Blue is the platform, not a guest.** The protocols, gossip, pacing (LEDBAT is
already blue, `bidamas/ibuki`), block sync, the signed step log, matches,
commit-reveal, netcode and re-execution checks are blue. The rules of one game
run as a sealed blue process that a blue node spawns with an empty capability
ceiling ("blue hosts blue"). Rust supplies only what blue cannot: the
interpreter, the UDP socket, and primitives (BLAKE3 and its chunk tree, Ed25519,
X25519, an AEAD, disk bytes). When BLUE-NATIVE self-hosting lands
(`theory/BLUE-NATIVE.md` §5), the interpreter moves up the ladder too.

World-facts that limit the design:

- **W1 NAT.** Direct connection succeeds in about 70% (libp2p DCUtR
  measurement, https://arxiv.org/abs/2604.12484) to 90% (iroh,
  https://docs.iroh.computer/concepts/holepunching) of setups. A zero-server
  network still needs a relay that any peer can run.
- **W2 Full state.** In lockstep and rollback every peer holds the whole state,
  so hidden information leaks to a modified client. Only commit-reveal (or
  mental poker) hides state, and only where a game is built around it.
- **W3 Determinism.** Re-execution proves nothing unless every peer computes the
  same bytes. Platform libm floats (`sin`, `cos`, `powf`), allocator byte
  counts and compiler instruction counts all differ between machines today.
- **W4 Last revealer.** In commit-reveal the last peer to reveal can abort after
  seeing the rest. Only a timeout with forfeit, and never a re-roll, bounds it.
- **W5 Two parties.** With two peers, a disagreement cannot say who lied: each
  holds a proof against the other. Arbitration needs a third verifier.
- **W6 Free keys.** A key costs nothing, so an open network faces sybil and
  eclipse attacks. Invite-only rosters avoid them; open lobbies need more.

## 2. Ground: what exists today

Measured 2026-11-09 against blue main, tameshi and kensa. Paths are in blue
unless named. Rows marked "branch" are on an unlanded branch, not on main.

| Need | State | Where |
|---|---|---|
| UDP wire, MTU 1280, Flash token bucket, Tide ring | TESTED (Rust holds only the bucket and the ring) | `crates/blue-lang-runtime/src/wire/mod.rs` |
| LEDBAT pacing, Tide and Flash protocol words | TESTED, in blue | `bidamas/ibuki/ibuki.b` |
| announce / want / part / ack | TESTED, crash proofs only, explicit `host:port` peers, unauthenticated | `bidamas/kodou/kodou.b` |
| capability ceiling per process; a breach is fatal | TESTED | `crates/blue-lang-waku/src/capability.rs` |
| stepped clock, seeded entropy, loopback wire | TESTED | `crates/blue-lang-waku/src/provision.rs`, `runtime/src/provide.rs` |
| blue process under a frame ("blue hosts blue") | TESTED | `examples/docking`, `crates/blue-lang-proc/src/code.rs` (`spawn_code`) |
| two-party frame: the meet of two ceilings | TESTED as pure words; runtime rendezvous DESIGN | `bidamas/ibuki/ibuki.b` (`airlock_frame`) |
| moving a server and its state over Tide | TESTED | `crates/blue-lang-proc/src/node.rs` (`evict`, `accept`) |
| receipts naming `input_root` and `output_root` | TESTED, unsigned, `spawn_server` only | `crates/blue-lang-proc/src/receipt.rs` |
| `state_root` of a value | EXISTS but lossy: Str, Symbol and Keyword collapse; closures, NaN and Inf become null; Int and Str map keys collide | `crates/blue-lang-runtime/src/json.rs` |
| a second root: Merkle over Strand entries | TESTED, differs from the receipt root | `bidamas/ibuki/ibuki.b` (`state_root`) |
| `blue replay` of a crash trace | TESTED; not a `(state, input)` re-run | `crates/blue-lang-cli/src/replay.rs` |
| record and replay of any run, `net_wait` | branch `h4/replay-net-wait` | not on main |
| signed, hash-chained event log with replay into states | TESTED (22 tests) | `bidamas/isshou/nisshi` |
| Ed25519, Merkle, CT-style roots and proofs, hash chains | TESTED, in blue | `bidamas/shomei` |
| threshold signing (FROST, RFC 9591) | TESTED | tameshi `src/threshold/`, blue `fuuin` |
| last-writer-wins CRDT with roots and a step chain | TESTED; `written` accepts only `:put` and `:merge` | `bidamas/ibuki/ibuki.b` (Strand) |
| append-only storage | TESTED | `crates/blue-lang-runtime/src/storage.rs` (`append_log`, `read_log`) |
| block store keyed by hash | ABSENT (the mondou memo store is keyed per blue version) | `crates/blue-lang-mondou/src/store.rs` |
| X25519, AEAD | ABSENT from the host seam | `crates/blue-lang-runtime/src/crypto.rs` |
| peer set, discovery, NAT traversal, relay | ABSENT | none |
| matches, commit-reveal, lockstep, rollback | ABSENT | none |

Corrections to the model this design started from: tameshi is an evidence and
attestation library, not a state engine; kensa admits deployments and does not
verify peers; no Fjall or RocksDB store exists; ibuki is the wire, pacing and the
Strand, not yet a gossip mesh. tameshi's `encrypted_chain.rs` is a home-made
BLAKE3 keystream and is not reused.

## 3. Research

| Prior art | Verdict | Why, for a blue platform |
|---|---|---|
| BLAKE3 verified streaming (Bao, iroh-blobs) | adapt | Verify each fetched range against the root. Blue implements the protocol; Rust exposes the chunk-tree primitive. https://github.com/oconnor663/bao |
| HyParView + Plumtree (iroh-gossip) | adapt, later | Partial views and a lazy-repair tree, in blue over kodou, for open lobbies. https://github.com/n0-computer/iroh-gossip |
| SWIM | adapt | Liveness for small rosters. https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf |
| Noise handshakes | adopt the pattern | Mutual authentication from static keys, then AEAD frames. https://noiseprotocol.org/noise.html |
| UDP hole punching with relay fallback (iroh, DCUtR) | adapt | The relay is a blue service any peer can run. https://github.com/libp2p/specs/blob/master/relay/DCUtR.md |
| GGPO / GGRS rollback | adapt | Input delay, prediction window (0 = lockstep), save/load/advance, checksum desync, local sync test, as a blue bidama. https://github.com/gschup/ggrs |
| Lockstep (Age of Empires) | adopt the model | https://www.gamedeveloper.com/programming/1500-archers-on-a-28-8-network-programming-in-age-of-empires-and-beyond |
| Commit-reveal with forfeit | adopt | Simultaneous moves and shared seeds; an abort forfeits, never re-rolls. |
| ECVRF (RFC 9381) | adapt | One-party verifiable draws. https://www.rfc-editor.org/rfc/rfc9381.html |
| Willow data model | adapt for persistent worlds | https://willowprotocol.org/ |
| Automerge, Loro | skip for rules | A CRDT merge accepts any write; rule-bound moves need a validated log. |
| wasmtime deterministic settings | adopt for the component placement | https://docs.wasmtime.dev/examples-deterministic-wasm-execution.html |
| iroh, libp2p, Hypercore as libraries | rejected | Their protocol logic lives in Rust or JavaScript and does not embed in a blue program on every placement. |

## 4. The libraries

Each is its own bidama with its own Bluefile and tests, and no game words. A
library marked (new) gets its name from the `naming` skill before it is minted;
the words `link`, `reach` and `session` are already taken (`kodou::link`,
`ibuki::reach`, `runtime/src/session.rs`).

| Library | Owns | Extends |
|---|---|---|
| host seam (Rust) | UDP datagrams, `net_wait`, BLAKE3 chunk tree, Ed25519, X25519, an AEAD, disk bytes | `runtime/src/wire`, `runtime/src/crypto.rs`, H4 |
| canonical root (new) | one type-tagged encoding of a blue value and its root; a value with no encoding is refused | replaces the lossy `json::state_root` for this use; ibuki's root adopts it |
| ibuki | Tide and Flash pacing (blue LEDBAT) | `bidamas/ibuki` |
| kodou | announce / want / part / ack for any root, only behind an authenticated channel; part size derived from the layers below | `bidamas/kodou` |
| channel (new) | Noise-pattern handshake from shomei keys, AEAD frames, address validation | shomei, host X25519 and AEAD |
| peer set (new) | fixed rosters first; SWIM liveness; HyParView topics later | kodou |
| traversal (new) | hole punching, a relay protocol with quotas, the relay service | channel |
| block sync (new) | blocks keyed by root, verified range fetch, persisted through append storage | `runtime/src/storage.rs`, host chunk tree |
| step log | per-peer signed steps: match id, tick, `def_hash`, engine identity, previous head, inputs, R, R′ | `bidamas/isshou/nisshi` |
| verdict (new) | re-execution check; signed fraud and equivocation proofs scoped to (match, peer) | step log, sealed rules process |
| match (new) | roster, the two-party frame, agreed seed, timeouts | `ibuki::airlock_frame` |
| fairness (new) | commit-reveal rounds with forfeit; ECVRF draws | shomei |
| netcode (new) | lockstep and rollback over a sealed rules process | match, step log |

A consumer takes only what it uses: a map mesh takes channel, peer set, block
sync and step log; a game adds match, fairness and netcode.

## 5. States and trust

**Trust model.** A peer is its Ed25519 key. A peer may say one thing: "in match
M, at tick t, after head H, with engine E running rules D, inputs I take root R
to root R′", signed. Inputs in one tick are ordered by the signing key. No peer
computes for another; every claim is re-run. A relay sees only AEAD ciphertext.

**Determinism.** The rules process runs under a determinism position: the
checker refuses platform float words in rules code (fixed-point words instead),
the step names the engine identity (blue version and bounds), and a run that
exhausts its budget is a reported mismatch, never fraud. Peers on different
engine identities do not judge each other.

States of one peer's view of another, in a match:

| State | Meaning | Exit |
|---|---|---|
| Unknown | no step yet | Announced, or Silent at the join timeout |
| Announced | a signed step seen, blocks missing | Fetching |
| Fetching | blocks arriving, each verified against R′ | Verified, Diverged, or Withheld at the fetch timeout |
| Verified | blocks complete, re-run root equal | Announced on the next step, Silent at the step timeout |
| Diverged | re-run root differs | Excluded, with a signed fraud proof |
| Equivocated | two signed steps for one tick with different roots | Excluded; the two steps are the proof, no re-run needed |
| Withheld | announced blocks not served in time | Excluded by forfeit |
| Silent | no step within the timeout | Excluded by forfeit |
| Excluded | proof or forfeit recorded for (match, peer) | final for this match only |

Bad states refused, each scoped to the fault:

- An unsigned step, or one without a match id and previous head, has no
  constructor in the step log, so an old or foreign step cannot be replayed.
- A block whose hash differs from its address is refused alone.
- A fraud proof is verified before it is gossiped, and it excludes one peer from
  one match. It never names a `def_hash`, so it cannot refuse the game for
  everyone.
- With two peers, a disagreement ends the match for both (W5). A match of three
  or more excludes the peer the others' re-runs agree against.

## 6. Diagrams

Context: the libraries and the one host seam.

```mermaid
flowchart TB
  subgraph Blue[blue program, any placement]
    Net[netcode] --> Match[match]
    Net --> Fair[fairness]
    Net --> Log[step log]
    Log --> Verdict[verdict]
    Verdict --> Rules[(sealed rules process\nceiling: none)]
    Log --> Sync[block sync]
    Sync --> Kodou[kodou]
    Peers[peer set] --> Kodou
    Kodou --> Chan[channel: handshake + AEAD]
    Chan --> Pace[ibuki pacing]
    Pace --> Trav[traversal: hole punch + relay]
    Root[canonical root] -.-> Log
    Root -.-> Sync
  end
  Trav --> Seam[[host seam: UDP, BLAKE3 chunk tree, Ed25519, X25519, AEAD, disk]]
```

Main flow: one step, from input to a verified root on another peer.

```mermaid
sequenceDiagram
  participant A as peer A
  participant RA as A's sealed rules
  participant B as peer B
  participant RB as B's sealed rules
  A->>RA: state at R, inputs of tick t (ordered by key)
  RA-->>A: state at R'
  A->>A: sign {M, t, head H, engine E, rules D, I, R, R'}; append
  A->>B: announce R' (kodou over channel, Flash)
  B->>A: want missing blocks (Tide)
  A-->>B: parts, each verified against R'
  B->>RB: state at R, same inputs
  RB-->>B: state at R''
  alt R'' == R'
    B->>B: Verified
  else R'' != R'
    B->>B: signed fraud proof for (M, A); verified, then gossiped
  end
```

Lifecycle of one peer, as another peer sees it.

```mermaid
stateDiagram-v2
  [*] --> Unknown
  Unknown --> Announced: signed step
  Unknown --> Silent: join timeout
  Announced --> Fetching: want sent
  Announced --> Equivocated: second step, same tick
  Fetching --> Verified: re-run equal
  Fetching --> Diverged: re-run differs
  Fetching --> Withheld: fetch timeout
  Verified --> Announced: next step
  Verified --> Silent: step timeout
  Diverged --> Excluded: fraud proof
  Equivocated --> Excluded: two steps
  Withheld --> Excluded: forfeit
  Silent --> Excluded: forfeit
  Excluded --> [*]
```

## 7. Decisions

| Decision | Chosen | Rejected, and why |
|---|---|---|
| Where protocol logic lives | blue bidamas | a Rust host with a blue guest: it would not embed in a blue program on every placement, and the house ladder puts it in blue |
| Transport | the existing wire plus blue protocols | iroh or libp2p as libraries: Rust-side protocol logic; QUIC brings TLS where a blue Noise-pattern handshake fits |
| Rules isolation | a blue process with an empty ceiling | a wasm sandbox per game: a second boundary blue already provides |
| State identity | one type-tagged canonical encoding and root | the JSON `state_root`: lossy, two states can share a root |
| Step log | extend `isshou/nisshi` | a new chain beside it |
| Anti-cheat | re-execution, signed fraud and equivocation proofs scoped to (match, peer) | kensa immunity entries: keyed by `def_hash`, unsigned, global |
| Floats in rules | refused by a check position; fixed-point words | platform libm: peers diverge |
| Two-player disputes | both lose the match | a referee peer: one peer becomes a server |
| Hidden information | commit-reveal per game design | none is possible in lockstep (W2) |

## 8. Open questions

| Question | Kind |
|---|---|
| Which AEAD (ChaCha20-Poly1305 or AES-GCM) and Noise pattern (IK or XX) | ours |
| Block size, and how a blue value maps onto blocks | ours |
| The type tags and order rules of the canonical encoding | ours |
| Relay quotas and who runs relays | ours |
| Sybil and eclipse resistance for open lobbies (W6) | ours, after invite-only rosters |
| Share of target home networks behind symmetric NAT | world-fact, to measure |
| Mobile limits on holding a UDP socket in the background (asobi) | world-fact |

## 9. Phases

Each phase ends green and moves its ledger rows. Names marked (new) are minted
through the `naming` skill in the phase that builds them.

- **P0 Seam and root.** Host X25519, an AEAD and the BLAKE3 chunk tree as host
  words; the canonical encoding and root in blue, with a red run showing two
  different values never share a root. `net_wait` and record/replay land (H4).
- **P1 Channel and sync.** The handshake and AEAD frames; kodou for any root,
  only behind the channel, part size derived from the layers; block sync with
  verified fetch over append storage; a fixed roster. Gate: two peers on the
  tailnet sync a value by root, and a tampered block is refused alone.
- **P2 Steps and verdict.** The signed step log over nisshi; spawning the sealed
  rules process with a determinism position; re-execution; fraud and
  equivocation proofs. Gate: in a fixed roster of three, a peer that lies about
  one root is excluded by the other two with a proof; an equivocating peer is
  excluded with no re-run.
- **P3 Match, fairness, netcode.** The roster and two-party frame at run time,
  agreed seed by commit-reveal with forfeit, lockstep (prediction window 0).
  Gate: a two-player turn-based match on the tailnet, replayable from its logs.
- **P4 Traversal.** Hole punching and a blue relay service with quotas. Gate: two
  peers behind different home NATs connect, directly or through the relay.
- **P5 Rollback and open play.** Prediction and resimulation, gossip topics for
  lobbies with sybil resistance, persistent worlds.

## 10. Tier ledger

| Item | Design | Exists | Tested | Live |
|---|---|---|---|---|
| wire, bucket, ring | ✅ | ✅ | ✅ | ❌ |
| ibuki pacing (LEDBAT) | ✅ | ✅ | ✅ | ❌ |
| `net_wait`, record and replay of any run | ✅ | branch | branch | ❌ |
| host X25519, AEAD, chunk tree | ✅ | ❌ | ❌ | ❌ |
| canonical root | ✅ | ❌ (lossy JSON root only) | ❌ | ❌ |
| kodou for any root, authenticated | ✅ | crash proofs, unauthenticated | crash proofs | ❌ |
| channel | ✅ | ❌ | ❌ | ❌ |
| peer set | ✅ | ❌ | ❌ | ❌ |
| block sync | ✅ | append storage only | append storage | ❌ |
| step log | ✅ | nisshi, unsigned receipts | nisshi | ❌ |
| verdict (re-execution, proofs) | ✅ | ❌ | ❌ | ❌ |
| match, fairness, netcode | ✅ | two-party frame words | two-party frame words | ❌ |
| traversal | ✅ | ❌ | ❌ | ❌ |
