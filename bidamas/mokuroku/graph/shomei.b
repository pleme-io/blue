space("shomei", {status: :ratified})

verb(
  "shomei",
  "accumulate",
  {
    kind: :pure,
    shape: "accumulate(acc, payload) -> acc",
    laterals: ["serialize"],
    fleet: "reduto",
    today: "absent",
    meaning: "add a leaf to a merkle accumulator without a rebuild",
    wave: 3,
    origin: "B"
  }
)

verb(
  "shomei",
  "address",
  {
    kind: :pure,
    shape: "address(bytes, opts) -> oid",
    laterals: ["serialize"],
    fleet: "daicho",
    today: "absent",
    meaning: "a self-describing content id: algorithm plus digest",
    wave: 2,
    origin: "B"
  }
)

verb(
  "shomei",
  "algorithms",
  {
    kind: :pure,
    shape: "algorithms(opts) -> [record]",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "supported algorithms with strength and status",
    wave: 1,
    origin: "D"
  }
)

verb(
  "shomei",
  "batch_verify?",
  {
    kind: :pure,
    shape: "batch_verify?(items) -> Bool",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "many signatures checked together, faster than one by one",
    wave: 3,
    origin: "D"
  }
)

verb(
  "shomei",
  "chain",
  {
    kind: :pure,
    shape: "chain(previous, payload) -> hex",
    laterals: ["serialize", "validate"],
    fleet: "tameshi",
    today: "exists:shomei",
    meaning: "hash that follows when a payload is appended",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "consistency",
  {
    kind: :pure,
    shape: "consistency(old_n, new_n, payloads) -> [step]",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "a proof that a larger tree extends a smaller one",
    wave: 3,
    origin: "B"
  }
)

verb(
  "shomei",
  "derive",
  {
    kind: :pure,
    shape: "derive(secret, salt, opts) -> bytes",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "stretch a secret into a key with a salted KDF",
    wave: 3,
    origin: "B"
  }
)

verb(
  "shomei",
  "equal?",
  {
    kind: :pure,
    shape: "equal?(a, b) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "compare two secrets or digests in constant time",
    wave: 1,
    origin: "B"
  }
)

verb(
  "shomei",
  "fingerprint",
  {
    kind: :pure,
    shape: "fingerprint(key) -> hex",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "short stable id of a public key",
    wave: 1,
    origin: "D"
  }
)

verb(
  "shomei",
  "first_break",
  {
    kind: :pure,
    shape: "first_break(genesis, payloads, hashes) -> index or nil",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:shomei",
    meaning: "index of the first stored hash the payloads miss",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "genesis",
  {
    kind: :pure,
    shape: "genesis(label) -> hex",
    laterals: ["serialize", "validate"],
    fleet: "tameshi",
    today: "exists:shomei",
    meaning: "first hash of a named chain",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "hash",
  {
    kind: :pure,
    shape: "hash(data, algorithm, opts) -> hex",
    laterals: ["error", "serialize", "validate"],
    fleet: "tameshi",
    today: "exists:shomei",
    meaning: "digest of bytes or text under a named algorithm",
    wave: 0,
    origin: "D",
    contract: "hash(data, algorithm) -> hex"
  }
)

verb(
  "shomei",
  "hash?",
  {
    kind: :pure,
    shape: "hash?(text, algorithm) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:shomei",
    meaning: "text has the shape of a digest",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "hash_file",
  {
    kind: :effect,
    shape: "hash_file(path, algorithm) -> hex",
    laterals: ["error", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "digest of a file, read in chunks",
    wave: 1,
    origin: "D"
  }
)

verb(
  "shomei",
  "hash_stream",
  {
    kind: :stream,
    shape: "hash_stream(source, algorithm) -> text",
    laterals: ["cancel", "deadline", "error"],
    fleet: nil,
    today: "absent",
    meaning: "a digest of a file or stream without holding it whole",
    wave: 1,
    origin: "B"
  }
)

verb(
  "shomei",
  "head",
  {
    kind: :pure,
    shape: "head(genesis, payloads) -> hex",
    laterals: ["serialize", "validate"],
    fleet: "tameshi",
    today: "exists:shomei",
    meaning: "hash after all payloads are linked",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "intact?",
  {
    kind: :pure,
    shape: "intact?(genesis, payloads, head) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:shomei",
    meaning: "re-linking the payloads reproduces the head",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "keypair",
  {
    kind: :pure,
    shape: "keypair(seed) -> record",
    laterals: ["error", "validate"],
    fleet: "tameshi",
    today: "partial:shomei",
    meaning: "signing key and public key from a seed",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "mac",
  {
    kind: :pure,
    shape: "mac(data, key, algorithm) -> hex",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "exists:shomei",
    meaning: "keyed digest proving data came from a key holder",
    wave: 1,
    origin: "D"
  }
)

verb(
  "shomei",
  "opens?",
  {
    kind: :pure,
    shape: "opens?(commitment, value, nonce) -> Bool",
    laterals: ["validate"],
    fleet: "tameshi",
    today: "absent",
    meaning: "commitment matches the revealed value",
    wave: 2,
    origin: "D"
  }
)

verb(
  "shomei",
  "pledge",
  {
    kind: :pure,
    shape: "pledge(value, nonce) -> hex",
    laterals: ["validate"],
    fleet: "tameshi",
    today: "absent",
    meaning: "hiding, binding commitment to a value",
    wave: 2,
    origin: "D"
  }
)

verb(
  "shomei",
  "proof",
  {
    kind: :pure,
    shape: "proof(payloads, index) -> [step]",
    laterals: ["serialize"],
    fleet: "cartorio",
    today: "exists:shomei",
    meaning: "the sibling path that shows a payload is in the tree",
    wave: 0,
    origin: "B"
  }
)

verb(
  "shomei",
  "prove",
  {
    kind: :pure,
    shape: "prove(payloads, index) -> [step]",
    laterals: ["error", "validate"],
    fleet: "tameshi",
    today: "exists:shomei",
    meaning: "inclusion proof for one payload",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "proves?",
  {
    kind: :pure,
    shape: "proves?(root, payload, proof) -> Bool",
    laterals: ["validate"],
    fleet: "tameshi",
    today: "exists:shomei",
    meaning: "proof climbs from payload to root",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "public",
  {
    kind: :pure,
    shape: "public(keypair) -> hex",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:shomei",
    meaning: "the half a verifier holds",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "random",
  {
    kind: :effect,
    shape: "random(n) -> bytes",
    laterals: ["capability"],
    fleet: nil,
    today: "exists:shomei",
    meaning: "n bytes from the system entropy source",
    wave: 1,
    origin: "B"
  }
)

verb(
  "shomei",
  "root",
  {
    kind: :pure,
    shape: "root(payloads) -> hex",
    laterals: ["serialize", "validate"],
    fleet: "tameshi",
    today: "exists:shomei",
    meaning: "Merkle root over payloads in order",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "same?",
  {
    kind: :pure,
    shape: "same?(a, b) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:shomei",
    meaning: "equality that takes equal time for every input",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "sign",
  {
    kind: :pure,
    shape: "sign(data, secret) -> hex",
    laterals: ["error", "validate"],
    fleet: "tameshi",
    today: "exists:shomei",
    meaning: "signature over data",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "trail",
  {
    kind: :pure,
    shape: "trail(genesis, payloads) -> [hex]",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:shomei",
    meaning: "every link hash in order",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "verify?",
  {
    kind: :pure,
    shape: "verify?(data, signature, public) -> Bool",
    laterals: ["error", "validate"],
    fleet: "tameshi",
    today: "exists:shomei",
    meaning: "signature is valid; malformed input raises",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shomei",
  "verify_chain",
  {
    kind: :pure,
    shape: "verify_chain(genesis, payloads, head) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:shomei",
    meaning: "whether the payloads reproduce the stated head",
    wave: 0,
    origin: "B"
  }
)

verb(
  "shomei",
  "verify_proof?",
  {
    kind: :pure,
    shape: "verify_proof?(root, payload, proof) -> Bool",
    laterals: ["validate"],
    fleet: "cartorio",
    today: "exists:shomei",
    meaning: "whether a proof climbs from a payload to the root",
    wave: 0,
    origin: "B"
  }
)

edge("shomei::head", :composes, "shomei::chain", "fold link over payloads")

edge(
  "shomei::trail",
  :composes,
  "shomei::chain",
  "keep every intermediate hash"
)

edge("shomei::address", :composes, "shomei::hash", "digest plus algorithm tag")
edge("shomei::chain", :composes, "shomei::hash", "hash of prev and payload")
edge("shomei::derive", :composes, "shomei::hash", "stretched hash")
edge("shomei::fingerprint", :composes, "shomei::hash", "hash of the public key")

edge(
  "shomei::genesis",
  :composes,
  "shomei::hash",
  "label hashed with format tag"
)

edge(
  "shomei::hash_file",
  :composes,
  "shomei::hash",
  "hash chunks of a read file"
)

edge("shomei::pledge", :composes, "shomei::hash", "hash of value with nonce")
edge("shomei::proves?", :composes, "shomei::hash", "climb proof by hashing")
edge("shomei::root", :composes, "shomei::hash", "hash per node")
edge("shomei::sign", :composes, "shomei::hash", "signs the digest")
edge("shomei::intact?", :composes, "shomei::head", "recompute and compare head")
edge("shomei::verify_chain", :composes, "shomei::head", "recomputes the head")
edge("shomei::proof", :composes, "shomei::root", "tree levels hashed")

edge(
  "shomei::first_break",
  :composes,
  "shomei::trail",
  "compare stored with recomputed"
)

edge(
  "shomei::sign",
  :generalizes,
  "kyoukyuu?::sign",
  "an artifact signature adds identity"
)

edge(
  "shomei::root",
  :generalizes,
  "shomei::head",
  "a tree root versus a chain head"
)

edge("shomei::hash", :generalizes, "shomei::mac", "a mac is a hash with a key")

edge(
  "shomei::algorithms",
  :guards,
  "shomei::hash",
  "names which algorithms may be asked for"
)

edge(
  "shomei::hash?",
  :guards,
  "shomei::hash",
  "check shape before trusting text"
)

edge(
  "shomei::same?",
  :guards,
  "shomei::mac",
  "compare tags without timing leak"
)

edge("shomei::opens?", :guards, "shomei::same?", "compare commitments safely")
edge("shomei::equal?", :guards, "shomei::verify?", "constant-time compare")

edge(
  "shomei::same?",
  :guards,
  "shomei::verify?",
  "compare digests without timing leak"
)

edge("shomei::hash?", :guards, "shomei::verify_chain", "shape check first")
edge("shomei::pledge", :inverse, "shomei::opens?", "checks a revealed value")
edge("shomei::opens?", :inverse, "shomei::pledge", "checks a revealed value")

edge(
  "shomei::verify_proof?",
  :inverse,
  "shomei::proof",
  "checks the path climbs"
)

edge("shomei::proves?", :inverse, "shomei::prove", "checks what prove built")
edge("shomei::prove", :inverse, "shomei::proves?", "checks what prove built")
edge("shomei::verify?", :inverse, "shomei::sign", "checks what sign made")
edge("shomei::sign", :inverse, "shomei::verify?", "checks what sign made")

edge(
  "shomei::proof",
  :inverse,
  "shomei::verify_proof?",
  "checks the path climbs"
)

edge("shomei::head", :lifts, "shomei::chain", "whole chain")

edge(
  "shomei::hash_file",
  :lifts,
  "shomei::hash",
  "streams instead of holding all bytes"
)

edge("shomei::hash_stream", :lifts, "shomei::hash", "file or stream form")

edge(
  "shomei::batch_verify?",
  :lifts,
  "shomei::verify?",
  "many signatures at once"
)

edge(
  "shomei::fingerprint",
  :pairs,
  "fuuin?::parse",
  "fingerprint names a parsed key"
)

edge("shomei::address", :pairs, "genbo?::put", "id of stored content")
edge("shomei::root", :pairs, "genbo?::tree", "merkle node of children")
edge("shomei::genesis", :pairs, "shomei::chain", "first hash then each next")

edge(
  "shomei::accumulate",
  :pairs,
  "shomei::consistency",
  "appending keeps old roots valid"
)

edge("shomei::equal?", :pairs, "shomei::hash", "compare digests safely")

edge(
  "shomei::hash",
  :pairs,
  "shomei::hash?",
  "a hash always passes the shape check"
)

edge("shomei::trail", :pairs, "shomei::head", "head is the last of the trail")

edge(
  "shomei::first_break",
  :pairs,
  "shomei::intact?",
  "index form and yes-no form"
)

edge("shomei::public", :pairs, "shomei::keypair", "the two halves of a key")

edge(
  "shomei::pledge",
  :pairs,
  "shomei::opens?",
  "every commitment has an opening"
)

edge("shomei::prove", :pairs, "shomei::proves?", "every proof has its check")
edge("shomei::proof", :pairs, "shomei::root", "path to the root")
edge("shomei::keypair", :pairs, "shomei::sign", "keys for signing")
edge("shomei::verify?", :pairs, "shomei::sign", "check what sign made")
edge("shomei::sign", :pairs, "shomei::verify?", "every signature has its check")

edge(
  "shomei::intact?",
  :refines,
  "shomei::first_break",
  "yes when there is no break"
)

edge("shomei::mac", :refines, "shomei::hash", "a digest that needs a key")

edge(
  "shomei::consistency",
  :refines,
  "shomei::proof",
  "old root inside the new"
)

edge("shomei::accumulate", :refines, "shomei::root", "incremental form")

edge(
  "shomei::batch_verify?",
  :refines,
  "shomei::verify?",
  "same answer, one pass"
)

edge(
  "shomei::first_break",
  :refines,
  "shomei::verify_chain",
  "says where it fails"
)

edge(
  "shomei::keypair",
  :requires,
  "fuuin?::random",
  "seed must come from secure entropy"
)

edge(
  "shomei::chain",
  :requires,
  "shomei::genesis",
  "every chain starts at a genesis"
)

edge("shomei::keypair", :requires, "shomei::hash", "seed to key uses a hash")
edge("shomei::sign", :requires, "shomei::keypair", "needs the secret half")

edge(
  "shomei::fingerprint",
  :requires,
  "shomei::public",
  "names only the public half"
)

edge("shomei::verify?", :requires, "shomei::public", "needs the public half")
edge("shomei::keypair", :requires, "shomei::random", "seed from entropy")
edge("shomei::prove", :requires, "shomei::root", "proof is relative to a root")
