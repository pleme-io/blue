space("fuuin", {status: :ratified})

verb(
  "fuuin",
  "combine",
  {
    kind: :pure,
    shape: "combine(parts, opts) -> signature",
    laterals: %w[capability error validate],
    fleet: "tameshi",
    today: "exists:fuuin",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "derive",
  {
    kind: :pure,
    shape: "derive(secret, salt, info, opts) -> key",
    laterals: %w[error validate],
    fleet: nil,
    today: "absent",
    meaning: "several independent keys from one secret (HKDF)",
    wave: 1,
    origin: "D"
  }
)

verb(
  "fuuin",
  "destroy",
  {
    kind: :effect,
    shape: "destroy(key_id, opts) -> nil",
    laterals: %w[idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "erase key material; data under it is gone for good",
    wave: 3,
    origin: "D"
  }
)

verb(
  "fuuin",
  "due?",
  {
    kind: :pure,
    shape: "due?(key, policy, now) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "key is older than its rotation policy allows",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "enclose",
  {
    kind: :effect,
    shape: "enclose(data, key_id, opts) -> envelope",
    laterals: %w[capability error resource],
    fleet: "cofre",
    today: "absent",
    meaning: "envelope encryption: fresh data key wrapped by a managed key",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "encrypted?",
  {
    kind: :pure,
    shape: "encrypted?(bytes) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "bytes look like one of our envelopes",
    wave: 1,
    origin: "D"
  }
)

verb(
  "fuuin",
  "exchange",
  {
    kind: :pure,
    shape: "exchange(secret, peer_public) -> key",
    laterals: %w[error validate],
    fleet: nil,
    today: "absent",
    meaning: "shared key from my secret and a peer public key",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "generate",
  {
    kind: :effect,
    shape: "generate(kind, opts) -> key",
    laterals: %w[capability error],
    fleet: "cofre",
    today: "partial:fuuin",
    meaning: "new key of a kind from secure entropy",
    wave: 1,
    origin: "D"
  }
)

verb(
  "fuuin",
  "hybrid",
  {
    kind: :pure,
    shape: "hybrid(classical, post_quantum) -> algorithm",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "pair two schemes so breaking one alone is not enough",
    wave: 4,
    origin: "D"
  }
)

verb(
  "fuuin",
  "offer",
  {
    kind: :effect,
    shape: "offer(share, data) -> record",
    laterals: %w[capability error],
    fleet: "tameshi",
    today: "exists:fuuin",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "open_as",
  {
    kind: :pure,
    shape: "open_as(envelope, secret, opts) -> bytes",
    laterals: %w[error validate],
    fleet: nil,
    today: "absent",
    meaning: "open an envelope sealed to my public key",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "open_stream",
  {
    kind: :stream,
    shape: "open_stream(source, target, key) -> nil",
    laterals: %w[cancel error resource],
    fleet: nil,
    today: "absent",
    meaning: "open a chunked envelope, failing on the first bad chunk",
    wave: 3,
    origin: "D"
  }
)

verb(
  "fuuin",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> key",
    laterals: %w[serialize validate],
    fleet: nil,
    today: "absent",
    meaning: "PEM, JWK or hex text to a key",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "peek",
  {
    kind: :pure,
    shape: "peek(envelope) -> record",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "read algorithm and key id without opening",
    wave: 1,
    origin: "D"
  }
)

verb(
  "fuuin",
  "quantum_safe?",
  {
    kind: :pure,
    shape: "quantum_safe?(algorithm) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "algorithm resists a quantum computer",
    wave: 3,
    origin: "D"
  }
)

verb(
  "fuuin",
  "random",
  {
    kind: :effect,
    shape: "random(count) -> bytes",
    laterals: %w[capability error],
    fleet: nil,
    today: "absent",
    meaning: "secure random bytes from the host entropy source",
    wave: 1,
    origin: "D"
  }
)

verb(
  "fuuin",
  "rebuild",
  {
    kind: :pure,
    shape: "rebuild(shares) -> secret",
    laterals: %w[error validate],
    fleet: "tameshi",
    today: "absent",
    meaning: "secret from a threshold of shares",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "render",
  {
    kind: :pure,
    shape: "render(key, format) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "key to PEM, JWK or hex; secret half only on request",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "retire",
  {
    kind: :effect,
    shape: "retire(key_id) -> nil",
    laterals: %w[idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "stop a key from sealing new data; old data still opens",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "rewrap",
  {
    kind: :effect,
    shape: "rewrap(envelope, key_id) -> envelope",
    laterals: %w[idempotent resource],
    fleet: nil,
    today: "absent",
    meaning: "move the data key to a new key without touching data",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "rotate",
  {
    kind: :effect,
    shape: "rotate(key_id, opts) -> key",
    laterals: %w[idempotent log time],
    fleet: "cofre",
    today: "absent",
    meaning: "new key version; old versions still open old data",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "seal",
  {
    kind: :effect,
    shape: "seal(data, key, opts) -> envelope",
    laterals: %w[capability error],
    fleet: nil,
    today: "absent",
    meaning: "authenticated encryption; any tampering breaks it",
    wave: 1,
    origin: "D"
  }
)

verb(
  "fuuin",
  "sign",
  {
    kind: :effect,
    shape: "sign(data, share, opts) -> record",
    laterals: %w[capability error],
    fleet: "tameshi",
    today: "exists:fuuin",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "seal_stream",
  {
    kind: :stream,
    shape: "seal_stream(source, target, key) -> nil",
    laterals: %w[cancel error resource],
    fleet: nil,
    today: "absent",
    meaning: "seal data larger than memory in authenticated chunks",
    wave: 3,
    origin: "D"
  }
)

verb(
  "fuuin",
  "seal_to",
  {
    kind: :effect,
    shape: "seal_to(data, recipient_public, opts) -> envelope",
    laterals: %w[capability error],
    fleet: nil,
    today: "absent",
    meaning: "seal so only the holder of a secret key can open",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "share",
  {
    kind: :effect,
    shape: "share(secret, threshold, count) -> [share]",
    laterals: %w[capability error],
    fleet: "tameshi",
    today: "absent",
    meaning: "Shamir shares; any threshold of them rebuild the secret",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "shield",
  {
    kind: :pure,
    shape: "shield(key, wrapping_key) -> text",
    laterals: %w[error validate],
    fleet: nil,
    today: "absent",
    meaning: "encrypt one key under another key",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "strength",
  {
    kind: :pure,
    shape: "strength(key) -> bits",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "security bits a key or parameter set gives",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "stretch",
  {
    kind: :pure,
    shape: "stretch(password, salt, opts) -> key",
    laterals: %w[resource validate],
    fleet: "x-crypto",
    today: "absent",
    meaning: "password to key with a memory-hard function",
    wave: 1,
    origin: "D"
  }
)

verb(
  "fuuin",
  "unlock",
  {
    kind: :effect,
    shape: "unlock(envelope, opts) -> bytes",
    laterals: %w[error resource],
    fleet: "cofre",
    today: "absent",
    meaning: "open an envelope by asking for its data key",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "unseal",
  {
    kind: :pure,
    shape: "unseal(envelope, key, opts) -> bytes",
    laterals: %w[error validate],
    fleet: nil,
    today: "absent",
    meaning: "decrypt and check; raises :tampered on a bad tag",
    wave: 1,
    origin: "D"
  }
)

verb(
  "fuuin",
  "unwrap",
  {
    kind: :pure,
    shape: "unwrap(text, wrapping_key) -> key",
    laterals: %w[error validate],
    fleet: nil,
    today: "absent",
    meaning: "recover a key wrapped under another key",
    wave: 2,
    origin: "D"
  }
)

verb(
  "fuuin",
  "zeroize",
  {
    kind: :effect,
    shape: "zeroize(secret) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "overwrite secret bytes in memory (needs runtime support)",
    wave: 3,
    origin: "D"
  }
)

edge(
  "fuuin::hybrid",
  :composes,
  "fuuin::exchange",
  "classical plus post-quantum exchange"
)

edge(
  "fuuin::seal_to",
  :composes,
  "fuuin::exchange",
  "ephemeral exchange then seal"
)

edge("fuuin::enclose", :composes, "fuuin::generate", "fresh data key each time")

edge("fuuin::rotate", :composes, "fuuin::generate", "new version of the key")

edge(
  "fuuin::combine",
  :requires,
  "fuuin::sign",
  "a threshold of signature shares"
)

edge("fuuin::sign", :requires, "fuuin::offer", "nonces committed in round one")

edge(
  "fuuin::offer",
  :requires,
  "fuuin::generate",
  "a share of a threshold group"
)

edge(
  "fuuin::combine",
  :pairs,
  "shomei::verify?",
  "the signature is ordinary Ed25519"
)

edge("fuuin::generate", :composes, "fuuin::random", "key bytes from entropy")
edge("fuuin::enclose", :composes, "fuuin::seal", "data sealed under data key")

edge(
  "fuuin::seal_to",
  :composes,
  "fuuin::seal",
  "payload sealed under derived key"
)

edge("fuuin::shield", :composes, "fuuin::seal", "key sealed under key")

edge(
  "fuuin::enclose",
  :composes,
  "fuuin::shield",
  "data key wrapped by managed key"
)

edge(
  "fuuin::rewrap",
  :composes,
  "fuuin::unlock",
  "unwrap then wrap under new key"
)

edge("fuuin::derive", :composes, "shomei::mac", "extract and expand steps")
edge("fuuin::seal", :composes, "shomei::mac", "tag authenticates ciphertext")

edge(
  "fuuin::hybrid",
  :generalizes,
  "fuuin::quantum_safe?",
  "safe when either part holds"
)

edge(
  "fuuin::zeroize",
  :guards,
  "fuuin::destroy",
  "memory wiped when a key dies"
)

edge(
  "fuuin::enclose",
  :guards,
  "fuuin::due?",
  "policy age checked at lock time"
)

edge(
  "fuuin::quantum_safe?",
  :guards,
  "fuuin::generate",
  "filters kinds for long-lived data"
)

edge(
  "fuuin::strength",
  :guards,
  "fuuin::generate",
  "names security bits of a request"
)

edge(
  "fuuin::unseal",
  :guards,
  "fuuin::peek",
  "peek chooses the key to open with"
)

edge("fuuin::due?", :guards, "fuuin::rotate", "decides when rotation runs")

edge(
  "fuuin::retire",
  :guards,
  "fuuin::rotate",
  "old version retires after rotate"
)

edge("fuuin::retire", :guards, "fuuin::seal", "retired keys cannot seal")

edge(
  "fuuin::generate",
  :guards,
  "fuuin::strength",
  "refuses kinds below the minimum"
)

edge("fuuin::encrypted?", :guards, "fuuin::unseal", "avoid opening plain bytes")

edge("fuuin::peek", :guards, "fuuin::unseal", "learn key id before opening")

edge(
  "fuuin::generate",
  :inverse,
  "fuuin::destroy",
  "key cannot return once gone"
)

edge(
  "fuuin::unlock",
  :inverse,
  "fuuin::enclose",
  "asks the key service to unwrap"
)

edge(
  "fuuin::destroy",
  :inverse,
  "fuuin::generate",
  "key cannot return once gone"
)

edge("fuuin::seal_to", :inverse, "fuuin::open_as", "opens with the secret key")

edge(
  "fuuin::seal_stream",
  :inverse,
  "fuuin::open_stream",
  "undoes chunked sealing"
)

edge("fuuin::render", :inverse, "fuuin::parse", "key to text")
edge("fuuin::share", :inverse, "fuuin::rebuild", "split what rebuild joins")
edge("fuuin::parse", :inverse, "fuuin::render", "key to text")
edge("fuuin::unseal", :inverse, "fuuin::seal", "decrypts and authenticates")

edge(
  "fuuin::open_stream",
  :inverse,
  "fuuin::seal_stream",
  "undoes chunked sealing"
)

edge("fuuin::open_as", :inverse, "fuuin::seal_to", "opens with the secret key")

edge("fuuin::rebuild", :inverse, "fuuin::share", "split what rebuild joins")
edge("fuuin::unwrap", :inverse, "fuuin::shield", "recover the wrapped key")

edge(
  "fuuin::enclose",
  :inverse,
  "fuuin::unlock",
  "asks the key service to unwrap"
)

edge("fuuin::seal", :inverse, "fuuin::unseal", "decrypts and authenticates")
edge("fuuin::shield", :inverse, "fuuin::unwrap", "recover the wrapped key")

edge("fuuin::seal_stream", :lifts, "fuuin::seal", "chunked sealing of streams")

edge(
  "fuuin::open_stream",
  :lifts,
  "fuuin::unseal",
  "chunked opening of streams"
)

edge(
  "fuuin::exchange",
  :pairs,
  "fuuin::derive",
  "shared secret then derive keys"
)

edge("fuuin::encrypted?", :pairs, "fuuin::peek", "detect, then read the header")

edge(
  "fuuin::rotate",
  :pairs,
  "fuuin::retire",
  "old version retires after rotation"
)

edge("fuuin::rewrap", :pairs, "fuuin::rotate", "rotation moves data keys over")

edge("fuuin::seal", :pairs, "fuuin::unseal", "every seal has an open")
edge("fuuin::shield", :pairs, "fuuin::unwrap", "every wrap has an unwrap")
edge("fuuin::zeroize", :pairs, "himitsu::reveal", "wipe after plain text use")

edge(
  "fuuin::stretch",
  :pairs,
  "ninshou?::protect",
  "password storage uses stretching"
)

edge(
  "fuuin::stretch",
  :refines,
  "fuuin::derive",
  "derive from a low-entropy password"
)

edge("fuuin::derive", :refines, "shomei::mac", "HKDF is built from keyed hash")
edge("fuuin::rotate", :requires, "fuuin::due?", "rotate when policy says so")

edge(
  "fuuin::exchange",
  :requires,
  "fuuin::generate",
  "each side needs a keypair"
)

edge(
  "fuuin::random",
  :requires,
  "fuuin::generate",
  "entropy is the base of every key"
)

edge("fuuin::exchange", :requires, "fuuin::parse", "peer key arrives as text")

edge(
  "fuuin::hybrid",
  :requires,
  "fuuin::quantum_safe?",
  "one half must be post-quantum"
)

edge("fuuin::seal", :requires, "fuuin::random", "fresh nonce per message")

edge(
  "fuuin::share",
  :requires,
  "fuuin::random",
  "share polynomial needs entropy"
)

edge("fuuin::parse", :requires, "fuuin::render", "round trip law")
edge("fuuin::destroy", :requires, "fuuin::retire", "retire before erasing")

edge("fuuin::rebuild", :requires, "fuuin::share", "needs a threshold of shares")

edge(
  "fuuin::share",
  :requires,
  "fuuin::strength",
  "threshold must keep the bits"
)
