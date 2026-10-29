space("genbo?", {status: :provisional})

verb(
  "genbo?",
  "address",
  {
    kind: :pure,
    shape: "address(bytes, opts) -> oid",
    laterals: ["serialize"],
    fleet: "daicho",
    today: "absent",
    meaning: "the id content would get, without storing it",
    wave: 2,
    origin: "B"
  }
)

verb(
  "genbo?",
  "chunk",
  {
    kind: :pure,
    shape: "chunk(bytes, opts) -> [bytes]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "split content at content-defined boundaries for deduplication",
    wave: 3,
    origin: "B"
  }
)

verb(
  "genbo?",
  "copy",
  {
    kind: :effect,
    shape: "copy(from, to, roots) -> count",
    laterals: %w[cancel deadline error idempotent],
    fleet: "daicho",
    today: "absent",
    meaning: "send the objects the target lacks for some roots",
    wave: 3,
    origin: "B",
    contract: "copy(from, to, opts) -> count"
  }
)

verb(
  "genbo?",
  "delete",
  {
    kind: :effect,
    shape: "delete(cas, oid) -> nil",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "remove one object; absent counts as done",
    wave: 3,
    origin: "B"
  }
)

verb(
  "genbo?",
  "diff",
  {
    kind: :effect,
    shape: "diff(cas, a, b) -> [change]",
    laterals: ["error"],
    fleet: "daicho",
    today: "absent",
    meaning: "the added, removed and changed paths between two trees",
    wave: 2,
    origin: "B",
    contract: "diff(cas, a, opts) -> [change]"
  }
)

verb(
  "genbo?",
  "entries",
  {
    kind: :effect,
    shape: "entries(cas, oid) -> [{name, mode, oid}]",
    laterals: ["error"],
    fleet: "daicho",
    today: "absent",
    meaning: "the children of a tree object",
    wave: 2,
    origin: "B",
    contract: "entries(cas) -> [{name, mode, oid}]"
  }
)

verb(
  "genbo?",
  "export",
  {
    kind: :effect,
    shape: "export(cas, oid, to, opts) -> [path]",
    laterals: %w[cancel capability error],
    fleet: nil,
    today: "absent",
    meaning: "write a stored tree out to a directory",
    wave: 2,
    origin: "B",
    contract: "export(cas, oid, opts) -> [path]"
  }
)

verb(
  "genbo?",
  "gc",
  {
    kind: :effect,
    shape: "gc(cas, roots, opts) -> {removed, freed}",
    laterals: %w[cancel error resource],
    fleet: "daicho",
    today: "absent",
    meaning: "delete objects no root reaches, after a dry plan",
    wave: 3,
    origin: "B"
  }
)

verb(
  "genbo?",
  "get",
  {
    kind: :effect,
    shape: "get(cas, oid) -> bytes or nil",
    laterals: %w[error validate],
    fleet: "daicho",
    today: "absent",
    meaning: "content by id, checked against its hash, or nil",
    wave: 2,
    origin: "B"
  }
)

verb(
  "genbo?",
  "has?",
  {
    kind: :effect,
    shape: "has?(cas, oid) -> Bool",
    laterals: [],
    fleet: "daicho",
    today: "absent",
    meaning: "whether an object id is stored",
    wave: 2,
    origin: "B"
  }
)

verb(
  "genbo?",
  "import",
  {
    kind: :effect,
    shape: "import(cas, path, opts) -> oid",
    laterals: %w[cancel capability error],
    fleet: "fudajiku",
    today: "absent",
    meaning: "store a directory or file and return its root id",
    wave: 2,
    origin: "B"
  }
)

verb(
  "genbo?",
  "info",
  {
    kind: :effect,
    shape: "info(cas, oid) -> {kind, size}",
    laterals: ["error"],
    fleet: "daicho",
    today: "absent",
    meaning: "the type and size of a stored object",
    wave: 2,
    origin: "B",
    contract: "info(cas, opts) -> {kind, size}"
  }
)

verb(
  "genbo?",
  "list",
  {
    kind: :effect,
    shape: "list(cas, opts) -> [oid]",
    laterals: ["error"],
    fleet: "daicho",
    today: "absent",
    meaning: "stored object ids under a prefix, sorted",
    wave: 2,
    origin: "B"
  }
)

verb(
  "genbo?",
  "need",
  {
    kind: :effect,
    shape: "need(cas, oid) -> bytes",
    laterals: %w[error validate],
    fleet: "daicho",
    today: "absent",
    meaning: "content by id, raising not_found",
    wave: 2,
    origin: "B"
  }
)

verb(
  "genbo?",
  "open",
  {
    kind: :effect,
    shape: "open(spec) -> cas",
    laterals: %w[capability config resource],
    fleet: "daicho",
    today: "absent",
    meaning: "open a content-addressed store on disk or an object store",
    wave: 2,
    origin: "B"
  }
)

verb(
  "genbo?",
  "pack",
  {
    kind: :effect,
    shape: "pack(cas, oids) -> bytes",
    laterals: %w[error serialize],
    fleet: "daicho",
    today: "absent",
    meaning: "bundle objects into one transferable pack",
    wave: 3,
    origin: "B"
  }
)

verb(
  "genbo?",
  "put",
  {
    kind: :effect,
    shape: "put(cas, bytes, opts) -> oid",
    laterals: %w[error idempotent serialize],
    fleet: "daicho",
    today: "absent",
    meaning: "store content under its own hash and return the id",
    wave: 2,
    origin: "B"
  }
)

verb(
  "genbo?",
  "reachable",
  {
    kind: :effect,
    shape: "reachable(cas, roots) -> set",
    laterals: %w[cancel error],
    fleet: "daicho",
    today: "absent",
    meaning: "the set of ids reachable from several roots",
    wave: 3,
    origin: "B"
  }
)

verb(
  "genbo?",
  "tree",
  {
    kind: :effect,
    shape: "tree(cas, entries) -> oid",
    laterals: %w[error idempotent serialize],
    fleet: "daicho",
    today: "absent",
    meaning: "store a named set of child ids as one merkle node",
    wave: 2,
    origin: "B"
  }
)

verb(
  "genbo?",
  "unpack",
  {
    kind: :effect,
    shape: "unpack(cas, bytes) -> [oid]",
    laterals: %w[serialize validate],
    fleet: "daicho",
    today: "absent",
    meaning: "store every object in a pack after checking each hash",
    wave: 3,
    origin: "B"
  }
)

verb(
  "genbo?",
  "verify",
  {
    kind: :effect,
    shape: "verify(cas) -> [oid]",
    laterals: %w[cancel validate],
    fleet: "daicho",
    today: "absent",
    meaning: "the ids whose content no longer matches their hash",
    wave: 2,
    origin: "B"
  }
)

verb(
  "genbo?",
  "walk",
  {
    kind: :effect,
    shape: "walk(cas, oid) -> [oid]",
    laterals: %w[cancel error],
    fleet: "daicho",
    today: "absent",
    meaning: "every object reachable from a root, each once",
    wave: 2,
    origin: "B",
    contract: "walk(cas, opts) -> [oid]"
  }
)

edge("genbo?::import", :composes, "fairu::walk", "finds the files")
edge("genbo?::export", :composes, "fairu::write", "writes each file")
edge("genbo?::put", :composes, "genbo?::address", "id is the content hash")
edge("genbo?::verify", :composes, "genbo?::address", "recomputes each hash")
edge("genbo?::import", :composes, "genbo?::chunk", "large files in chunks")
edge("genbo?::gc", :composes, "genbo?::delete", "removes the rest")
edge("genbo?::diff", :composes, "genbo?::entries", "compares two trees")
edge("genbo?::export", :composes, "genbo?::entries", "reads each node")
edge("genbo?::walk", :composes, "genbo?::entries", "follows children")
edge("genbo?::verify", :composes, "genbo?::list", "checks every object")
edge("genbo?::copy", :composes, "genbo?::pack", "sends only missing objects")
edge("genbo?::tree", :composes, "genbo?::put", "stores the node")
edge("genbo?::gc", :composes, "genbo?::reachable", "what is kept")
edge("genbo?::import", :composes, "genbo?::tree", "one node per directory")
edge("genbo?::copy", :composes, "genbo?::walk", "finds what is missing")
edge("genbo?::reachable", :composes, "genbo?::walk", "union over roots")
edge("genbo?::address", :composes, "shomei::address", "digest with algorithm")
edge("genbo?::open", :composes, "souko?::open", "object store backend")
edge("genbo?::put", :inverse, "genbo?::delete", "removes what put stored")
edge("genbo?::tree", :inverse, "genbo?::entries", "entries rebuild the node")
edge("genbo?::import", :inverse, "genbo?::export", "tree back to a directory")
edge("genbo?::export", :inverse, "genbo?::import", "tree back to a directory")
edge("genbo?::unpack", :inverse, "genbo?::pack", "objects back into the store")
edge("genbo?::delete", :inverse, "genbo?::put", "removes what put stored")
edge("genbo?::entries", :inverse, "genbo?::tree", "entries rebuild the node")
edge("genbo?::pack", :inverse, "genbo?::unpack", "objects back into the store")
edge("genbo?::walk", :lifts, "genbo?::entries", "whole graph from one node")
edge("genbo?::pack", :lifts, "genbo?::get", "many objects in one pack")
edge("genbo?::unpack", :lifts, "genbo?::put", "each object verified and stored")
edge("genbo?::pack", :pairs, "genbo?::copy", "transfer unit")
edge("genbo?::reachable", :pairs, "genbo?::gc", "roots decide what stays")
edge("genbo?::put", :pairs, "genbo?::has?", "skip storing what exists")
edge("genbo?::chunk", :pairs, "genbo?::import", "boundaries for deduplication")
edge("genbo?::list", :pairs, "genbo?::info", "ids and their facts")
edge("genbo?::get", :pairs, "genbo?::put", "store and fetch by id")
edge("genbo?::list", :pairs, "genbo?::verify", "enumerate then check")
edge("genbo?::diff", :pairs, "rekishi?::diff", "trees under commits")
edge("genbo?::tree", :pairs, "shomei::root", "a tree id is a merkle node")
edge("genbo?::has?", :refines, "genbo?::get", "existence only")
edge("genbo?::info", :refines, "genbo?::get", "kind and size without content")
edge("genbo?::need", :refines, "genbo?::get", "raises when absent")
