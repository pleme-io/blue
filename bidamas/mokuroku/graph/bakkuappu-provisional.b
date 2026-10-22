space("bakkuappu?", {status: :provisional})

verb(
  "bakkuappu?",
  "backup",
  {
    kind: :effect,
    shape: "backup(source, target, opts) -> manifest",
    laterals: ["cancel", "deadline", "error", "idempotent", "log", "retry"],
    fleet: "hozon",
    today: "absent",
    meaning: "copy a snapshot to a target, hashed and optionally encrypted",
    wave: 2,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "copy",
  {
    kind: :effect,
    shape: "copy(from, to, opts) -> manifest",
    laterals: ["cancel", "deadline", "error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "copy a backup from one target to another",
    wave: 3,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "delete",
  {
    kind: :effect,
    shape: "delete(target, id) -> nil",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "remove one backup; absent counts as done",
    wave: 3,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> [change]",
    laterals: [],
    fleet: "fudajiku",
    today: "absent",
    meaning: "files added, removed or changed between two manifests",
    wave: 2,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "drill",
  {
    kind: :effect,
    shape: "drill(target, opts) -> report",
    laterals: ["deadline", "error", "log", "resource"],
    fleet: "pitr-forge",
    today: "absent",
    meaning: "restore into scratch space and prove the data is usable",
    wave: 3,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "info",
  {
    kind: :effect,
    shape: "info(target, id) -> manifest",
    laterals: ["error"],
    fleet: "hozon",
    today: "absent",
    meaning: "the manifest of one backup: files, hashes, sizes, time",
    wave: 2,
    origin: "B",
    contract: "info(target, opts) -> manifest"
  }
)

verb(
  "bakkuappu?",
  "lag",
  {
    kind: :effect,
    shape: "lag(from, to) -> duration",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "how far behind the source a replica is",
    wave: 3,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "list",
  {
    kind: :effect,
    shape: "list(target, opts) -> [manifest]",
    laterals: ["error"],
    fleet: "hozon",
    today: "absent",
    meaning: "every backup at a target, newest first",
    wave: 2,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "manifest",
  {
    kind: :pure,
    shape: "manifest(entries) -> manifest",
    laterals: ["serialize"],
    fleet: "fudajiku",
    today: "absent",
    meaning: "the hashed list of files a backup holds",
    wave: 2,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "mirror",
  {
    kind: :effect,
    shape: "mirror(from, to, opts) -> [action]",
    laterals: ["cancel", "deadline", "error", "idempotent", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "make the target match the source once, deleting extras on request",
    wave: 2,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "plan",
  {
    kind: :pure,
    shape: "plan(source, target, opts) -> [action]",
    laterals: ["log", "validate"],
    fleet: "hozon",
    today: "absent",
    meaning: "what a backup would copy and prune, changing nothing",
    wave: 2,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "promote",
  {
    kind: :effect,
    shape: "promote(replica, opts) -> nil",
    laterals: ["error", "switch"],
    fleet: nil,
    today: "absent",
    meaning: "make a replica the writable primary",
    wave: 4,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "prune",
  {
    kind: :effect,
    shape: "prune(target, policy, opts) -> [id]",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "remove backups the retention policy no longer keeps",
    wave: 3,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "replicate",
  {
    kind: :stream,
    shape: "replicate(from, to, opts) -> nil",
    laterals: ["cancel", "error", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "keep a target following a source continuously",
    wave: 3,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "restore",
  {
    kind: :effect,
    shape: "restore(target, to, opts) -> manifest",
    laterals: ["cancel", "deadline", "error", "log", "validate"],
    fleet: "hozon",
    today: "absent",
    meaning: "bring a backup back, to a point in time when given",
    wave: 2,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "retain",
  {
    kind: :decl,
    shape: "retain(rules) -> policy",
    laterals: ["config", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare how many daily, weekly and monthly backups to keep",
    wave: 3,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "schedule",
  {
    kind: :decl,
    shape: "schedule(source, target, spec) -> decl",
    laterals: ["config", "time"],
    fleet: "pitr-forge",
    today: "absent",
    meaning: "declare a backup on a repeating time rule",
    wave: 3,
    origin: "B",
    contract: "schedule(source, target, opts) -> decl"
  }
)

verb(
  "bakkuappu?",
  "snapshot",
  {
    kind: :effect,
    shape: "snapshot(source, opts) -> snap",
    laterals: ["error", "idempotent", "resource", "time"],
    fleet: "hozon",
    today: "absent",
    meaning: "a consistent point-in-time copy of files, a volume or a database",
    wave: 2,
    origin: "B"
  }
)

verb(
  "bakkuappu?",
  "verify?",
  {
    kind: :effect,
    shape: "verify?(target, opts) -> Bool",
    laterals: ["deadline", "validate"],
    fleet: "hozon",
    today: "absent",
    meaning: "whether stored backups still match their manifest hashes",
    wave: 2,
    origin: "B",
    contract: "verify?(target) -> Bool"
  }
)

edge(
  "bakkuappu?::backup",
  :composes,
  "asshuku?::compress",
  "shrinks before storing"
)

edge(
  "bakkuappu?::schedule",
  :composes,
  "bakkuappu?::backup",
  "runs on the rule"
)

edge("bakkuappu?::mirror", :composes, "bakkuappu?::copy", "transfers it")
edge("bakkuappu?::prune", :composes, "bakkuappu?::delete", "removes the rest")
edge("bakkuappu?::mirror", :composes, "bakkuappu?::diff", "finds what differs")
edge("bakkuappu?::prune", :composes, "bakkuappu?::list", "candidates")

edge(
  "bakkuappu?::backup",
  :composes,
  "bakkuappu?::manifest",
  "records what was stored"
)

edge(
  "bakkuappu?::diff",
  :composes,
  "bakkuappu?::manifest",
  "compares two manifests"
)

edge(
  "bakkuappu?::info",
  :composes,
  "bakkuappu?::manifest",
  "reads one manifest"
)

edge(
  "bakkuappu?::verify?",
  :composes,
  "bakkuappu?::manifest",
  "compares to recorded hashes"
)

edge(
  "bakkuappu?::drill",
  :composes,
  "bakkuappu?::restore",
  "restores into scratch space"
)

edge(
  "bakkuappu?::backup",
  :composes,
  "bakkuappu?::snapshot",
  "copies a fixed state"
)

edge(
  "bakkuappu?::drill",
  :composes,
  "bakkuappu?::verify?",
  "proves the data is usable"
)

edge(
  "bakkuappu?::restore",
  :composes,
  "bakkuappu?::verify?",
  "hashes checked on the way"
)

edge(
  "bakkuappu?::backup",
  :composes,
  "himitsu::encrypt",
  "encrypts before storing"
)

edge(
  "bakkuappu?::promote",
  :composes,
  "rokku?::revoke",
  "fences the old primary"
)

edge("bakkuappu?::manifest", :composes, "shomei::hash", "hash per file")
edge("bakkuappu?::verify?", :composes, "shomei::hash", "recomputes digests")

edge(
  "bakkuappu?::copy",
  :composes,
  "souko?::copy",
  "moves a backup between targets"
)

edge("bakkuappu?::list", :composes, "souko?::list", "backups stored as objects")
edge("bakkuappu?::backup", :composes, "souko?::put", "object store target")

edge(
  "bakkuappu?::plan",
  :guards,
  "bakkuappu?::backup",
  "preview before copying"
)

edge(
  "bakkuappu?::retain",
  :guards,
  "bakkuappu?::delete",
  "policy decides what may go"
)

edge(
  "bakkuappu?::lag",
  :guards,
  "bakkuappu?::promote",
  "promote only a caught-up replica"
)

edge(
  "bakkuappu?::verify?",
  :guards,
  "bakkuappu?::restore",
  "prove before bringing back"
)

edge("bakkuappu?::delete", :inverse, "bakkuappu?::backup", "removes one backup")

edge(
  "bakkuappu?::restore",
  :inverse,
  "bakkuappu?::backup",
  "brings the data back"
)

edge("bakkuappu?::backup", :inverse, "bakkuappu?::delete", "removes one backup")

edge(
  "bakkuappu?::backup",
  :inverse,
  "bakkuappu?::restore",
  "brings the data back"
)

edge("bakkuappu?::replicate", :lifts, "bakkuappu?::mirror", "continuous form")

edge(
  "bakkuappu?::snapshot",
  :pairs,
  "bakkuappu?::backup",
  "consistent source for the copy"
)

edge(
  "bakkuappu?::list",
  :pairs,
  "bakkuappu?::info",
  "backups and their manifests"
)

edge("bakkuappu?::lag", :pairs, "bakkuappu?::replicate", "measures its delay")

edge(
  "bakkuappu?::prune",
  :pairs,
  "bakkuappu?::retain",
  "policy and its enforcement"
)

edge(
  "bakkuappu?::schedule",
  :pairs,
  "bakkuappu?::retain",
  "when to run and what to keep"
)

edge(
  "bakkuappu?::snapshot",
  :pairs,
  "genbo?::import",
  "deduplicated storage of the copy"
)

edge(
  "bakkuappu?::manifest",
  :pairs,
  "genbo?::tree",
  "manifest is a merkle node"
)

edge(
  "bakkuappu?::promote",
  :requires,
  "bakkuappu?::replicate",
  "needs a following replica"
)
