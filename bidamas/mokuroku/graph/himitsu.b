space("himitsu", {status: :ratified})

verb(
  "himitsu",
  "connect",
  {
    kind: :effect,
    shape: "connect(backend, opts) -> vault",
    laterals: %w[deadline error resource],
    fleet: "akeyless-auth",
    today: "absent",
    meaning: "authenticate to a secret backend, gated on the user",
    wave: 2,
    origin: "D"
  }
)

verb(
  "himitsu",
  "create",
  {
    kind: :effect,
    shape: "create(store, key, secret, opts) -> nil",
    laterals: %w[capability error idempotent],
    fleet: "cofre",
    today: "absent",
    meaning: "add a secret only if the name is free",
    wave: 2,
    origin: "B"
  }
)

verb(
  "himitsu",
  "decrypt",
  {
    kind: :pure,
    shape: "decrypt(bytes, key) -> secret",
    laterals: %w[capability error],
    fleet: "blackmatter-secrets",
    today: "absent",
    meaning: "open sealed data into a secret",
    wave: 2,
    origin: "B"
  }
)

verb(
  "himitsu",
  "delete",
  {
    kind: :effect,
    shape: "delete(store, key) -> nil",
    laterals: %w[capability error idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "make the secret absent",
    wave: 1,
    origin: "D"
  }
)

verb(
  "himitsu",
  "deliver",
  {
    kind: :effect,
    shape: "deliver(reference, target, opts) -> nil",
    laterals: %w[idempotent log resource],
    fleet: "cofre",
    today: "absent",
    meaning: "place a secret in a file, env or cluster Secret",
    wave: 2,
    origin: "D"
  }
)

verb(
  "himitsu",
  "diff",
  {
    kind: :effect,
    shape: "diff(declared, store) -> [change]",
    laterals: ["capability"],
    fleet: "cofre",
    today: "absent",
    meaning: "which declared secrets are missing, extra or stale",
    wave: 3,
    origin: "B"
  }
)

verb(
  "himitsu",
  "encrypt",
  {
    kind: :pure,
    shape: "encrypt(data, key) -> bytes",
    laterals: %w[capability error],
    fleet: "blackmatter-secrets",
    today: "absent",
    meaning: "seal data under a key so only the key reads it",
    wave: 2,
    origin: "B"
  }
)

verb(
  "himitsu",
  "generate",
  {
    kind: :effect,
    shape: "generate(spec) -> secret",
    laterals: %w[capability validate],
    fleet: "cofre",
    today: "absent",
    meaning: "new random secret by a typed spec",
    wave: 1,
    origin: "D"
  }
)

verb(
  "himitsu",
  "get",
  {
    kind: :effect,
    shape: "get(store, key, opts) -> secret or nil",
    laterals: %w[cache capability error resource],
    fleet: "blackmatter-secrets",
    today: "absent",
    meaning: "one secret, nil when absent",
    wave: 1,
    origin: "D"
  }
)

verb(
  "himitsu",
  "has?",
  {
    kind: :effect,
    shape: "has?(store, key) -> Bool",
    laterals: %w[capability resource],
    fleet: nil,
    today: "absent",
    meaning: "the secret exists",
    wave: 1,
    origin: "D"
  }
)

verb(
  "himitsu",
  "leaks",
  {
    kind: :effect,
    shape: "leaks(paths, opts) -> [finding]",
    laterals: %w[resource validate],
    fleet: nil,
    today: "absent",
    meaning: "secrets committed in files, by pattern and entropy",
    wave: 2,
    origin: "D"
  }
)

verb(
  "himitsu",
  "lease",
  {
    kind: :effect,
    shape: "lease(reference, opts) -> lease",
    laterals: %w[capability error log resource time],
    fleet: "akeyless-api",
    today: "absent",
    meaning: "short-lived credential issued on demand, expiring itself",
    wave: 3,
    origin: "D"
  }
)

verb(
  "himitsu",
  "list",
  {
    kind: :effect,
    shape: "list(store, opts) -> [key]",
    laterals: %w[capability error resource],
    fleet: "blackmatter-secrets",
    today: "absent",
    meaning: "keys only, never values",
    wave: 1,
    origin: "D"
  }
)

verb(
  "himitsu",
  "materialize",
  {
    kind: :effect,
    shape: "materialize(plan, opts) -> report",
    laterals: %w[capability error idempotent],
    fleet: "cofre",
    today: "absent",
    meaning: "apply a plan so each declared secret exists in its backend",
    wave: 2,
    origin: "B"
  }
)

verb(
  "himitsu",
  "need",
  {
    kind: :effect,
    shape: "need(store, key, opts) -> secret",
    laterals: %w[capability error resource],
    fleet: "blackmatter-secrets",
    today: "absent",
    meaning: "one secret, raising :not_found when absent",
    wave: 1,
    origin: "D"
  }
)

verb(
  "himitsu",
  "plan",
  {
    kind: :pure,
    shape: "plan(declared, store) -> [action]",
    laterals: ["validate"],
    fleet: "cofre",
    today: "absent",
    meaning: "the writes needed to make a store match its declaration",
    wave: 2,
    origin: "B"
  }
)

verb(
  "himitsu",
  "put",
  {
    kind: :effect,
    shape: "put(store, key, value, opts) -> secret",
    laterals: %w[capability error idempotent log resource],
    fleet: "cofre",
    today: "absent",
    meaning: "create or replace a secret",
    wave: 1,
    origin: "D"
  }
)

verb(
  "himitsu",
  "read",
  {
    kind: :effect,
    shape: "read(reference, opts) -> secret",
    laterals: %w[cache capability deadline error resource trace],
    fleet: "cofre",
    today: "absent",
    meaning: "fetch a secret by reference; it prints as <secret>",
    wave: 1,
    origin: "D"
  }
)

verb(
  "himitsu",
  "recipients",
  {
    kind: :pure,
    shape: "recipients(file) -> [text]",
    laterals: ["validate"],
    fleet: "blackmatter-secrets",
    today: "absent",
    meaning: "key ids that can open a sops file",
    wave: 2,
    origin: "D"
  }
)

verb(
  "himitsu",
  "redact",
  {
    kind: :pure,
    shape: "redact(text, secrets) -> text",
    laterals: ["log"],
    fleet: nil,
    today: "absent",
    meaning: "the text with every known secret value masked",
    wave: 1,
    origin: "B"
  }
)

verb(
  "himitsu",
  "ref",
  {
    kind: :pure,
    shape: "ref(uri) -> secret-ref",
    laterals: ["validate"],
    fleet: "cofre",
    today: "absent",
    meaning: "a typed pointer to a secret in a named backend",
    wave: 1,
    origin: "B"
  }
)

verb(
  "himitsu",
  "rekey",
  {
    kind: :effect,
    shape: "rekey(file, recipients) -> nil",
    laterals: %w[capability error idempotent log resource],
    fleet: "blackmatter-secrets",
    today: "absent",
    meaning: "re-encrypt a sops file for a new recipient set",
    wave: 2,
    origin: "D"
  }
)

verb(
  "himitsu",
  "renew",
  {
    kind: :effect,
    shape: "renew(lease) -> lease",
    laterals: %w[error idempotent time],
    fleet: nil,
    today: "absent",
    meaning: "extend a lease before it ends",
    wave: 3,
    origin: "D"
  }
)

verb(
  "himitsu",
  "reveal",
  {
    kind: :pure,
    shape: "reveal(secret) -> text",
    laterals: %w[capability log],
    fleet: nil,
    today: "absent",
    meaning: "the single door from secret to plain text",
    wave: 1,
    origin: "D"
  }
)

verb(
  "himitsu",
  "revoke",
  {
    kind: :effect,
    shape: "revoke(lease) -> nil",
    laterals: %w[error idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "end a lease now",
    wave: 3,
    origin: "D"
  }
)

verb(
  "himitsu",
  "rotate",
  {
    kind: :effect,
    shape: "rotate(reference, opts) -> secret",
    laterals: %w[capability error idempotent log retry time],
    fleet: "cofre",
    today: "absent",
    meaning: "new value stored; previous version kept for a grace period",
    wave: 2,
    origin: "D"
  }
)

verb(
  "himitsu",
  "scan",
  {
    kind: :effect,
    shape: "scan(path, opts) -> [finding]",
    laterals: %w[cancel capability],
    fleet: nil,
    today: "absent",
    meaning: "find secret-shaped values in files or history",
    wave: 3,
    origin: "B"
  }
)

verb(
  "himitsu",
  "secret",
  {
    kind: :pure,
    shape: "secret(text) -> secret",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "wrap text so it cannot be printed or logged",
    wave: 1,
    origin: "D"
  }
)

verb(
  "himitsu",
  "stale?",
  {
    kind: :effect,
    shape: "stale?(reference, policy) -> Bool",
    laterals: %w[resource time],
    fleet: nil,
    today: "absent",
    meaning: "secret is older than its rotation policy",
    wave: 2,
    origin: "D"
  }
)

verb(
  "himitsu",
  "versions",
  {
    kind: :effect,
    shape: "versions(reference) -> [record]",
    laterals: %w[capability error resource],
    fleet: nil,
    today: "absent",
    meaning: "stored versions of a secret, newest first",
    wave: 2,
    origin: "D"
  }
)

verb(
  "himitsu",
  "with_secrets",
  {
    kind: :effect,
    shape: "with_secrets(references, f) -> value",
    laterals: %w[error resource],
    fleet: nil,
    today: "absent",
    meaning: "run f with secrets delivered, then wipe them",
    wave: 2,
    origin: "D"
  }
)

edge("himitsu::scan", :composes, "fairu::walk", "reads files and history")
edge("himitsu::stale?", :composes, "fuuin?::due?", "same rotation policy")
edge("himitsu::put", :composes, "fuuin?::enclose", "stored encrypted at rest")
edge("himitsu::generate", :composes, "fuuin?::random", "bytes from entropy")

edge(
  "himitsu::rekey",
  :composes,
  "fuuin?::rewrap",
  "new recipients for data keys"
)

edge("himitsu::with_secrets", :composes, "fuuin?::zeroize", "wipe on exit")
edge("himitsu::rekey", :composes, "himitsu::decrypt", "opens under old keys")

edge(
  "himitsu::with_secrets",
  :composes,
  "himitsu::deliver",
  "deliver for the body only"
)

edge("himitsu::plan", :composes, "himitsu::diff", "declared against stored")
edge("himitsu::rekey", :composes, "himitsu::encrypt", "seals under new keys")
edge("himitsu::rotate", :composes, "himitsu::generate", "new value")
edge("himitsu::diff", :composes, "himitsu::list", "names on both sides")

edge(
  "himitsu::materialize",
  :composes,
  "himitsu::plan",
  "runs the planned writes"
)

edge("himitsu::materialize", :composes, "himitsu::put", "writes each secret")
edge("himitsu::rotate", :composes, "himitsu::put", "stored as a new version")
edge("himitsu::deliver", :composes, "himitsu::read", "read then place")
edge("himitsu::get", :composes, "himitsu::read", "ref built from store and key")
edge("himitsu::read", :composes, "himitsu::ref", "resolves the reference")

edge(
  "himitsu::read",
  :composes,
  "himitsu::reveal",
  "reveal stays in the caller"
)

edge("himitsu::leaks", :composes, "kyoukyuu?::scan", "a scan with secret rules")
edge("himitsu::encrypt", :composes, "shomei::derive", "key from a passphrase")
edge("himitsu::generate", :composes, "shomei::random", "entropy source")

edge(
  "himitsu::get",
  :generalizes,
  "himitsu::read",
  "nil when the key is absent"
)

edge(
  "himitsu::lease",
  :generalizes,
  "himitsu::read",
  "a read that expires itself"
)

edge(
  "himitsu::leaks",
  :guards,
  "himitsu::put",
  "find secrets that should be in a vault"
)

edge(
  "himitsu::connect",
  :guards,
  "himitsu::read",
  "a vault session before reads"
)

edge("himitsu::ref", :guards, "himitsu::read", "typed pointer before resolving")

edge(
  "himitsu::recipients",
  :guards,
  "himitsu::rekey",
  "see who can open before rekeying"
)

edge("himitsu::get", :guards, "kengen?::allow?", "reads pass the policy")

edge(
  "himitsu::list",
  :guards,
  "kengen?::visible",
  "list only keys the caller may see"
)

edge("himitsu::redact", :guards, "rogu::info", "secrets never reach a log line")

edge(
  "himitsu::encrypt",
  :inverse,
  "himitsu::decrypt",
  "opens what encrypt sealed"
)

edge(
  "himitsu::put",
  :inverse,
  "himitsu::delete",
  "delete makes absent what put made"
)

edge(
  "himitsu::decrypt",
  :inverse,
  "himitsu::encrypt",
  "opens what encrypt sealed"
)

edge("himitsu::revoke", :inverse, "himitsu::lease", "ends a lease early")

edge(
  "himitsu::delete",
  :inverse,
  "himitsu::put",
  "delete makes absent what put made"
)

edge("himitsu::secret", :inverse, "himitsu::reveal", "plain text from a secret")
edge("himitsu::lease", :inverse, "himitsu::revoke", "ends a lease early")
edge("himitsu::reveal", :inverse, "himitsu::secret", "plain text from a secret")
edge("himitsu::list", :pairs, "himitsu::get", "keys here, values there")
edge("himitsu::put", :pairs, "himitsu::get", "put then get returns the value")
edge("himitsu::diff", :pairs, "himitsu::materialize", "drift then repair")
edge("himitsu::versions", :pairs, "himitsu::put", "each put makes a version")

edge(
  "himitsu::reveal",
  :pairs,
  "himitsu::read",
  "only door from secret to text"
)

edge("himitsu::scan", :pairs, "himitsu::redact", "finds what redact must mask")
edge("himitsu::decrypt", :pairs, "himitsu::reveal", "open then show")
edge("himitsu::redact", :pairs, "himitsu::reveal", "masks what reveal exposes")
edge("himitsu::secret", :pairs, "himitsu::reveal", "the only way in and out")
edge("himitsu::lease", :pairs, "himitsu::revoke", "issue and end")

edge(
  "himitsu::generate",
  :pairs,
  "himitsu::rotate",
  "new value for an old name"
)

edge("himitsu::put", :pairs, "himitsu::versions", "each write is a version")
edge("himitsu::rotate", :pairs, "himitsu::versions", "old versions stay listed")
edge("himitsu::deliver", :pairs, "himitsu::with_secrets", "place and wipe")
edge("himitsu::has?", :refines, "himitsu::get", "existence only")

edge(
  "himitsu::lease",
  :refines,
  "himitsu::get",
  "issued on demand with a limit"
)

edge("himitsu::need", :refines, "himitsu::get", "raises when absent")

edge(
  "himitsu::read",
  :refines,
  "himitsu::get",
  "reads a reference, raises on absence"
)

edge("himitsu::create", :refines, "himitsu::put", "refuses to overwrite")
edge("himitsu::renew", :requires, "himitsu::lease", "extends a live lease")
edge("himitsu::versions", :requires, "himitsu::put", "every put adds a version")
edge("himitsu::rotate", :requires, "himitsu::stale?", "rotate when overdue")
