use("kazu", [:max])
use("retsu", [:first, :is_empty, :size])

# shomei (署名) — signatures and hash chains: Ed25519 and BLAKE3, for real.
#
# `angou` is the classical curriculum and says so: none of its ciphers is
# secure. This package is the other end. It signs, verifies and hashes with
# audited primitives, and it encrypts nothing, which is why its name is the
# word for a signature and not a cipher word.
#
# # What it stands on
#
# The runtime's crypto layer (blue-lang-runtime `crypto`, pure Rust, no C,
# installed in every interpreter including the wasm one):
#
#   blake3_hex(data)                             BLAKE3-256, 64 hex chars
#   ed25519_keypair(seed_hex)                    [secret_hex, public_hex]
#   ed25519_sign(secret_hex, message)            128 hex chars
#   ed25519_verify(public_hex, message, sig)     true / false
#
# A message is a string (its UTF-8 bytes) or a list of byte integers. Keys and
# signatures are hex. The runtime names say the ALGORITHM; this package's names
# say the ROLE (`sign_message`, `hash_message`), so a format written against
# it says what each field is for, and the header here says which algorithm.
#
# # Three rules this package holds
#
# **Bad input raises; only a bad signature is false.** `verify_message` is
# false for exactly one thing: a well-formed signature that does not verify.
# A key that is not hex, a signature of the wrong length or a public key that
# is not a curve point raises, from the runtime. A verifier that answered
# false for garbage would make a wiring bug look like a forgery caught.
#
# **The seed is the caller's.** `signing_keypair` takes 32 bytes of hex and
# draws no randomness, so the same seed is always the same key. That keeps
# the runtime layer pure and the RFC 8032 vectors checkable; it also means a
# weak seed is a weak key. Supply 32 bytes from a real entropy source or a
# secret store, never a password or a counter.
#
# **A chain link cannot be read two ways.** A link hashes a domain tag, the
# previous hash and the payload: `"blue-chain/v1/link\n" + prev + "\n" +
# payload`. The previous hash is refused unless it is exactly 64 lowercase
# hex characters, so where it ends is fixed and no (prev, payload) pair can
# collide with another by moving the boundary. The genesis has its own tag,
# `"blue-chain/v1/genesis\n" + label`, so two logs started with different
# labels never share a first hash, and a genesis is never mistaken for a link.
# Anyone can recompute a chain from those two lines with any BLAKE3 tool;
# the tests below pin values computed that way by `b3sum`.
#
# # What is deliberately absent
#
# **No encryption.** Nothing here hides a message; signatures prove who wrote
# it and hashes prove it did not change.
#
# **No key storage.** A secret key is a blue string while it is in use, and
# blue strings are ordinary memory. Where keys live is the caller's decision.
#
# **No clock and no sequence number.** A chain orders its payloads and proves
# none were changed, removed or reordered after the head was recorded. It does
# not say when anything happened; put a timestamp in the payload if it matters.

# ── keys ───────────────────────────────────────────────────────────

# The Ed25519 keypair for a 32-byte seed (64 hex characters): [secret, public].
# Deterministic, so the same seed always gives the same key.
def signing_keypair(seed_hex)
  ed25519_keypair(seed_hex)
end

# The secret half of a keypair: the seed, in lowercase hex. Never publish it.
def keypair_secret(kp)
  first(kp)
end

# The public half of a keypair, in lowercase hex. This is what a verifier holds.
def keypair_public(kp)
  nth(1, kp)
end

# ── signed messages ────────────────────────────────────────────────

# The Ed25519 signature of a message (a string or a byte list), in hex.
# Ed25519 is deterministic: one key and one message have one signature.
def sign_message(secret_hex, message)
  ed25519_sign(secret_hex, message)
end

# True when the signature is valid for the message under the public key; false
# when it is not. Malformed input raises rather than answering false.
def verify_message(public_hex, message, signature_hex)
  ed25519_verify(public_hex, message, signature_hex)
end

# ── hashes ─────────────────────────────────────────────────────────

# The BLAKE3-256 hash of a string or a byte list, in lowercase hex.
def hash_message(data)
  blake3_hex(data)
end

# True for exactly 64 lowercase hex characters: the shape `hash_message` returns.
# Deletes each of the 16 digits with the runtime's `replace` and asks whether
# anything is left: 16 native calls instead of a lambda per character. Every
# chain_link runs this, and the per-character form was 97% of a link's cost
# (31 of 32 µs; now 12 µs. Measured 2026-09-24 by nisshi's profile).
def is_hash_hex(s)
  if string?(s)
    length(s) == 64 and
      reduce(
        (left, c) -> replace(left, c, ""),
        s,
        [
          "0",
          "1",
          "2",
          "3",
          "4",
          "5",
          "6",
          "7",
          "8",
          "9",
          "a",
          "b",
          "c",
          "d",
          "e",
          "f"
        ]
      ) ==
        ""
  else
    false
  end
end

# ── hash chains ────────────────────────────────────────────────────

# The first hash of a chain, from a label that names the log.
def chain_genesis(label)
  if string?(label)
    hash_message("blue-chain/v1/genesis\n#{label}")
  else
    raise(:chain, "a chain label must be a string")
  end
end

# The hash that follows `prev` when `payload` (a string) is appended.
# Raises when `prev` is not a hash or `payload` is not a string.
def chain_link(prev, payload)
  chain_require_hash(prev, "the previous hash")
  if string?(payload)
    hash_message("blue-chain/v1/link\n#{prev}\n#{payload}")
  else
    raise(:chain, "a chain payload must be a string; serialize it first")
  end
end

# The hash after every payload is linked in order: the genesis for no payloads.
def chain_head(genesis, payloads)
  chain_require_hash(genesis, "the genesis")
  reduce(chain_link, genesis, payloads)
end

# Every link hash in order, one per payload, as a log stores them beside its
# entries. Built with `reduce`, not recursion, so a long log does not hit
# blue's depth bound.
def chain_hashes(genesis, payloads)
  chain_require_hash(genesis, "the genesis")
  reverse(
    reduce(
      (acc, p) -> cons(chain_link(chain_prev(acc, genesis), p), acc),
      [],
      payloads
    )
  )
end

# True when linking the payloads onto the genesis reproduces `head` exactly.
# A changed, removed, added or reordered payload makes it false.
def chain_verify(genesis, payloads, head)
  chain_require_hash(head, "the head")
  chain_head(genesis, payloads) == head
end

# The index of the first stored hash that the payloads do not reproduce, or nil
# when every stored hash matches and the counts agree. A missing or extra entry
# breaks at the first position only one side has.
def chain_first_break(genesis, payloads, hashes)
  computed = chain_hashes(genesis, payloads)
  n = max(size(computed), size(hashes))
  find((i) -> chain_at(i, computed) != chain_at(i, hashes), range(0, n))
end

# The most recent link in a reversed accumulator, or the genesis when empty.
def chain_prev(acc, genesis)
  if is_empty(acc)
    genesis
  else
    first(acc)
  end
end

# The i-th element, or nil past the end, so two lists of different lengths
# compare position by position.
def chain_at(i, xs)
  if i < size(xs)
    nth(i, xs)
  end
end

# Raise unless `h` has the shape of a hash, naming which argument it was.
def chain_require_hash(h, what)
  if not is_hash_hex(h)
    raise(:chain, "#{what} must be 64 lowercase hex characters")
  end
end

# ── Merkle trees ───────────────────────────────────────────────────
#
# A chain proves a whole log; a Merkle tree proves one entry of it, to someone
# who holds only the root, with log2(n) hashes. The lines follow the chain's
# rules, with their own tags so a leaf, a node and a link are never confused:
#
#   leaf   "blue-merkle/v1/leaf\n" + payload
#   node   "blue-merkle/v1/node\n" + left + "\n" + right
#   empty  "blue-merkle/v1/empty"
#
# Leaves pair left to right. An odd node at the end of a level moves up
# unpaired, so no hash is ever duplicated (the Bitcoin tree duplicates it, and
# then two different lists share a root). A proof is a list of [side, hash]
# steps from the leaf up: "L" when the sibling sits on the left. An auditor
# replays it with b3sum and no blue. To write one as JSON, make each step an
# object: blue's JSON reads a list of [text, value] pairs as an object.

# The leaf hash of a payload (a string).
def merkle_leaf(payload)
  if string?(payload)
    hash_message("blue-merkle/v1/leaf\n#{payload}")
  else
    raise(:merkle, "a merkle payload must be a string; serialize it first")
  end
end

# The node hash over two child hashes, left then right.
def merkle_node(left, right)
  chain_require_hash(left, "the left hash")
  chain_require_hash(right, "the right hash")
  hash_message("blue-merkle/v1/node\n#{left}\n#{right}")
end

# The root over the payloads in order; the empty root for none.
def merkle_root(payloads)
  if is_empty(payloads)
    hash_message("blue-merkle/v1/empty")
  else
    merkle_top(map(merkle_leaf, payloads))
  end
end

# The proof that payload `index` is in the tree: [side, hash] steps, leaf up.
def merkle_proof(payloads, index)
  if not (integer?(index) and index >= 0 and index < size(payloads))
    raise(:merkle, "the index must name one of the payloads")
  end
  merkle_path(map(merkle_leaf, payloads), index, [])
end

# True when the proof climbs from the payload's leaf to `root`. A step with a
# side other than "L" or "R", or a hash of the wrong shape, raises.
def merkle_verify(root, payload, proof)
  chain_require_hash(root, "the root")
  reduce(merkle_climb, merkle_leaf(payload), proof) == root
end

# The one hash a level of one node is.
def merkle_top(level)
  if size(level) == 1
    first(level)
  else
    merkle_top(merkle_up(level))
  end
end

# The next level up: each pair joined, an odd last node carried as it is.
def merkle_up(level)
  map((i) -> merkle_pair(level, i), range(0, floor((size(level) + 1) / 2)))
end

# The parent of the pair starting at 2i, or the lone node when it has no pair.
def merkle_pair(level, i)
  right = chain_at(2 * i + 1, level)
  if right.nil?
    nth(2 * i, level)
  else
    merkle_node(nth(2 * i, level), right)
  end
end

# The proof steps from position `i` of `level` to the top, `acc` reversed.
def merkle_path(level, i, acc)
  if size(level) == 1
    reverse(acc)
  else
    merkle_path(
      merkle_up(level),
      floor(i / 2),
      merkle_push(merkle_step(level, i), acc)
    )
  end
end

# The sibling of position `i` as a proof step, or nil when it has none.
def merkle_step(level, i)
  if i % 2 == 1
    ["L", nth(i - 1, level)]
  else
    merkle_side("R", chain_at(i + 1, level))
  end
end

def merkle_side(side, h)
  if h != nil
    [side, h]
  end
end

def merkle_push(step, acc)
  if step.nil?
    acc
  else
    cons(step, acc)
  end
end

# One step up a proof: the running hash joined with the step's sibling.
def merkle_climb(h, step)
  if first(step) == "L"
    merkle_node(nth(1, step), h)
  elsif first(step) == "R"
    merkle_node(h, nth(1, step))
  else
    raise(:merkle, "a proof step's side must be \"L\" or \"R\"")
  end
end

# ── verbs ──────────────────────────────────────────────────────────

# The hash of data as lowercase hex under a named algorithm; only :blake3 is
# built, any other raises :bad_option.
def hash(data, algorithm)
  if algorithm == :blake3
    hash_message(data)
  else
    raise(:bad_option, "hash: the algorithm must be :blake3, got #{algorithm}")
  end
end

# The Ed25519 signature of data under a secret, in hex; a malformed secret
# raises :bad_key.
def sign(data, secret)
  sign_message(secret, data) rescue
    raise(:bad_key, "sign: the secret must be 64 lowercase hex characters")
end

# Whether the signature holds for the data under the public key; false only
# for a well-formed signature that does not verify.
def verify?(data, signature, public)
  verify_message(public, data, signature)
end

# Whether the payloads reproduce the stated head from the genesis.
def verify_chain(genesis, payloads, head)
  chain_verify(genesis, payloads, head)
end

# The sibling path, leaf up, that shows payload `index` is in the tree.
def proof(payloads, index)
  merkle_proof(payloads, index)
end

# Whether a proof climbs from the payload to the root.
def verify_proof?(root, payload, proof)
  merkle_verify(root, payload, proof)
end

# ── tests ──────────────────────────────────────────────────────────
#
# Oracles, all outside this package: RFC 8032 §7.1 (Ed25519), BLAKE3's official
# test_vectors.json, and `b3sum` 1.8.2 over the two chain lines above.
#
# Red runs, 2026-09-24, each observed and reverted:
#   - the link without its domain tag: 1 red, the b3sum test. The tamper
#     tests stayed green, since a consistent wrong format still detects
#     tampering; only the independent value pins the format.
#   - chain_verify comparing the head with itself: 1 red, the tamper test.
#   - verify_message ORed with true: 1 red, the round-trip controls. The RFC
#     vectors stayed green, since a vector only ever asks for a yes.

test "the empty message: the official BLAKE3 vector and RFC 8032 TEST 1"
  assert hash_message("") ==
    "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
  assert hash_message([]) == hash_message("")
  kp = signing_keypair("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
  assert keypair_public(kp) ==
    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  assert sign_message(keypair_secret(kp), "") ==
    "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
end

test "RFC 8032 TEST 2 (the one byte 0x72, written as r) and TEST 3 (bytes af 82)"
  pub2 = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
  sig2 = "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"
  assert keypair_public(
    signing_keypair("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb")
  ) ==
    pub2
  assert sign_message(
    "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
    "r"
  ) ==
    sig2
  assert verify_message(pub2, "r", sig2) == true
  assert verify_message(pub2, [114], sig2) == true
  pub3 = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"
  sig3 = "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"
  assert sign_message(
    "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
    [175, 130]
  ) ==
    sig3
  assert verify_message(pub3, [175, 130], sig3) == true
end

test "a signature round-trips, and fails for a changed message, key or signature"
  kp = signing_keypair("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb")
  other = signing_keypair("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
  sig = sign_message(keypair_secret(kp), "permit: door 3, until 18:00")
  assert verify_message(
    keypair_public(kp),
    "permit: door 3, until 18:00",
    sig
  ) ==
    true
  assert verify_message(
    keypair_public(kp),
    "permit: door 3, until 19:00",
    sig
  ) ==
    false
  assert verify_message(
    keypair_public(other),
    "permit: door 3, until 18:00",
    sig
  ) ==
    false
  forged = sign_message(keypair_secret(other), "permit: door 3, until 18:00")
  assert verify_message(
    keypair_public(kp),
    "permit: door 3, until 18:00",
    forged
  ) ==
    false
end

test "malformed input raises instead of answering false"
  pub = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
  assert (verify_message("abcd", "m", "00") rescue :raised) == :raised
  assert (verify_message(pub, "m", "not hex") rescue :raised) == :raised
  assert (sign_message("00", "m") rescue :raised) == :raised
  assert (hash_message(nil) rescue :raised) == :raised
  assert (hash_message([256]) rescue :raised) == :raised
  assert error?(
    begin
      signing_keypair(42)
    rescue e
      e
    end
  )
end

test "is_hash_hex accepts exactly the shape hash_message returns"
  assert is_hash_hex(hash_message("x"))
  assert not is_hash_hex(upcase(hash_message("x")))
  assert not is_hash_hex("abc")
  assert not is_hash_hex(nil)
  assert not is_hash_hex(concat(hash_message("x"), "0"))
end

test "chain values match b3sum over the two documented lines"
  g = chain_genesis("test-log")
  assert g == "1f8f9ab8cbe27c7636f7e6ac2f7e4e950a631972e9061c34d68a86ba1759c8a4"
  l1 = chain_link(g, "event-1")
  assert l1 ==
    "340a67af6036a998f2720cbe2a5ac48cd15562e4020913ed157722ef05e27eaa"
  assert chain_link(l1, "event-2") ==
    "53255aaf3c113bc2c2bb75162cc0131201a7382d0890a5bb575ae395f55c097c"
  assert chain_hashes(g, ["event-1", "event-2"]) ==
    [l1, "53255aaf3c113bc2c2bb75162cc0131201a7382d0890a5bb575ae395f55c097c"]
  assert chain_head(g, ["event-1", "event-2"]) ==
    "53255aaf3c113bc2c2bb75162cc0131201a7382d0890a5bb575ae395f55c097c"
end

test "an empty chain is its genesis, and two labels never share one"
  g = chain_genesis("test-log")
  assert chain_head(g, []) == g
  assert is_empty(chain_hashes(g, []))
  assert chain_verify(g, [], g)
  assert chain_first_break(g, [], []).nil?
  assert chain_genesis("other-log") != g
  assert chain_genesis("") != hash_message("")
end

test "a changed, dropped, added or reordered payload breaks the chain"
  g = chain_genesis("test-log")
  events = ["event-1", "event-2", "event-3"]
  head_hash = chain_head(g, events)
  stored = chain_hashes(g, events)
  assert chain_verify(g, events, head_hash)
  assert chain_first_break(g, events, stored).nil?
  assert not chain_verify(g, ["event-1", "event-X", "event-3"], head_hash)
  assert not chain_verify(g, ["event-1", "event-3"], head_hash)
  assert not chain_verify(
    g,
    ["event-1", "event-2", "event-3", "event-4"],
    head_hash
  )
  assert not chain_verify(g, ["event-2", "event-1", "event-3"], head_hash)
  assert chain_first_break(g, ["event-1", "event-X", "event-3"], stored) == 1
  assert chain_first_break(g, ["event-1", "event-2"], stored) == 2
  assert chain_first_break(g, ["event-9", "event-2", "event-3"], stored) == 0
end

test "a link refuses a previous hash or payload it cannot place"
  g = chain_genesis("test-log")
  assert (chain_link("abc", "x") rescue :raised) == :raised
  assert (chain_link(upcase(g), "x") rescue :raised) == :raised
  assert (chain_link(g, 42) rescue :raised) == :raised
  assert (chain_verify(g, [], "not a head") rescue :raised) == :raised
  assert (chain_genesis(nil) rescue :raised) == :raised
end

test "merkle values match b3sum over the three documented lines"
  la = "d6f59f937f1a20df8ffe84872b79005f6a3cf8a799dba3795247ff2d6f2bfbca"
  lb = "2519d16b7f5b5e538c69a7a37820024b75462a429b675f17c1369ff3f504a8ac"
  lc = "eb4773482ec97958492c784c9fa2a8f247bb1a9657710c9e4a2e1118a9deaf3f"
  nab = "f5a5d8aff2c96f3abd9d097277b4dde881f23bae1f05ee31b2d3e064c6d9c81b"
  assert merkle_leaf("a") == la
  assert merkle_leaf("b") == lb
  assert merkle_node(la, lb) == nab
  assert merkle_root(["a", "b"]) == nab
  assert merkle_root(["a", "b", "c"]) ==
    "b48d08dfd84e110f9790ac8bb31b50aedb753ff315ad2db75dd812b8fba02251"
  assert merkle_proof(["a", "b", "c"], 2) == [["L", nab]]
  assert merkle_proof(["a", "b", "c"], 0) == [["R", lb], ["R", lc]]
end

test "the empty tree, a single leaf, and a leaf never equal to a node or link"
  assert merkle_root([]) ==
    "e0e9879448ec201f6ccd55c9bc3b9970074f37d1e34dc7b80f15d4d046f5c388"
  assert merkle_root(["a"]) == merkle_leaf("a")
  assert merkle_proof(["a"], 0) == []
  assert merkle_verify(merkle_root(["a"]), "a", [])
  assert merkle_leaf("a") != hash_message("a")
  assert merkle_leaf("a") != chain_link(chain_genesis(""), "a")
end

test "every proof of every tree from 1 to 9 leaves verifies"
  events = (n) -> map((i) -> "event-#{i}", range(0, n))
  proves = fn(xs)
    every?(
      (i) -> merkle_verify(merkle_root(xs), nth(i, xs), merkle_proof(xs, i)),
      range(0, size(xs))
    )
  end
  assert every?((n) -> proves(events(n)), range(1, 10))
end

test "a changed payload, a swapped proof or a reordered list breaks the root"
  xs = ["a", "b", "c", "d", "e"]
  root = merkle_root(xs)
  assert not merkle_verify(root, "X", merkle_proof(xs, 1))
  assert not merkle_verify(root, "b", merkle_proof(xs, 2))
  assert merkle_root(["b", "a", "c", "d", "e"]) != root
  assert merkle_root(["a", "b", "c", "d"]) != root
  assert merkle_root(["a", "b", "c", "d", "e", "e"]) != root
end

test "merkle refuses what it cannot place"
  assert (merkle_leaf(42) rescue :raised) == :raised
  assert (merkle_node("abc", merkle_leaf("a")) rescue :raised) == :raised
  assert (merkle_proof(["a"], 1) rescue :raised) == :raised
  assert (merkle_proof(["a"], -1) rescue :raised) == :raised
  assert (merkle_verify("nope", "a", []) rescue :raised) == :raised
  assert (merkle_verify(
    merkle_root(["a", "b"]),
    "a",
    [["X", merkle_leaf("b")]]
  ) rescue
    :raised) ==
    :raised
end

test "hash names its algorithm and refuses the ones that are not built"
  assert hash("", :blake3) ==
    "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
  assert hash("x", :blake3) == hash_message("x")
  assert hash([120], :blake3) == hash("x", :blake3)
  assert hash("x", :blake3) != hash("y", :blake3)
  assert (hash("x", :sha256) rescue :raised) == :raised
  assert (hash("x", nil) rescue :raised) == :raised
end

test "sign and verify? agree with RFC 8032 and fail for a changed input"
  seed = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
  pub = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
  sig = "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"
  assert sign("r", seed) == sig
  assert sign([114], seed) == sig
  assert verify?("r", sig, pub) == true
  assert verify?("s", sig, pub) == false
  assert verify?(
    "r",
    sign(
      "r",
      "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
    ),
    pub
  ) ==
    false
end

test "sign refuses a secret it cannot place and verify? refuses garbage"
  pub = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
  assert (sign("m", "00") rescue :bad) == :bad
  assert (verify?("m", "not hex", pub) rescue :raised) == :raised
  assert (verify?("m", "00", "abcd") rescue :raised) == :raised
  assert error?(
    begin
      sign("m", 42)
    rescue e
      e
    end
  )
end

test "verify_chain and proof follow the chain and the tree"
  g = chain_genesis("test-log")
  events = ["event-1", "event-2"]
  head_hash = "53255aaf3c113bc2c2bb75162cc0131201a7382d0890a5bb575ae395f55c097c"
  assert verify_chain(g, events, head_hash)
  assert verify_chain(g, [], g)
  assert not verify_chain(g, ["event-2", "event-1"], head_hash)
  assert not verify_chain(g, ["event-1"], head_hash)
  assert (verify_chain(g, events, "nope") rescue :raised) == :raised
  nab = "f5a5d8aff2c96f3abd9d097277b4dde881f23bae1f05ee31b2d3e064c6d9c81b"
  assert proof(["a", "b", "c"], 2) == [["L", nab]]
  assert proof(["a"], 0) == []
  assert (proof(["a"], 1) rescue :raised) == :raised
  assert verify_proof?(
    merkle_root(["a", "b", "c"]),
    "c",
    proof(["a", "b", "c"], 2)
  )
  assert verify_proof?(merkle_root(["a"]), "a", [])
  assert not verify_proof?(
    merkle_root(["a", "b", "c"]),
    "b",
    proof(["a", "b", "c"], 2)
  )
  assert not verify_proof?(
    merkle_root(["a", "b", "c"]),
    "X",
    proof(["a", "b", "c"], 0)
  )
  assert (verify_proof?("nope", "a", []) rescue :raised) == :raised
end
