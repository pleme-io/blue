space("kakunou?", {status: :provisional})

verb(
  "kakunou?",
  "batch",
  {
    kind: :effect,
    shape: "batch(store, ops) -> [result]",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "apply many writes atomically or none",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "clear",
  {
    kind: :effect,
    shape: "clear(store, prefix) -> count",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "delete every key under a prefix",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "close",
  {
    kind: :effect,
    shape: "close(store) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "release the store",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "compact",
  {
    kind: :effect,
    shape: "compact(store) -> nil",
    laterals: %w[cancel resource],
    fleet: nil,
    today: "absent",
    meaning: "reclaim space held by deleted entries",
    wave: 4,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "count",
  {
    kind: :effect,
    shape: "count(store, opts) -> number",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "how many keys lie under a prefix",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "create",
  {
    kind: :effect,
    shape: "create(store, key, value, opts) -> value",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "set a key only if it is absent",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "delete",
  {
    kind: :effect,
    shape: "delete(store, key) -> nil",
    laterals: %w[error idempotent],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "make the key absent; absent counts as done",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "expire",
  {
    kind: :effect,
    shape: "expire(store, key, ttl) -> nil",
    laterals: %w[idempotent time],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "make a key vanish after a duration",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "export",
  {
    kind: :stream,
    shape: "export(store, f, opts) -> count",
    laterals: %w[cancel error],
    fleet: nil,
    today: "absent",
    meaning: "call f per entry for a full copy out",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "get",
  {
    kind: :effect,
    shape: "get(store, key, opts) -> value or nil",
    laterals: %w[deadline error trace],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "the value at a key, or nil when absent",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "get_many",
  {
    kind: :effect,
    shape: "get_many(store, keys) -> map",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "the values of many keys in one round trip",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "has?",
  {
    kind: :effect,
    shape: "has?(store, key) -> Bool",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "whether a key is present",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "import",
  {
    kind: :effect,
    shape: "import(store, entries, opts) -> count",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "load many entries in bulk",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "increment",
  {
    kind: :effect,
    shape: "increment(store, key, by) -> number",
    laterals: %w[error idempotent],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "add to a counter atomically and return it",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "index",
  {
    kind: :effect,
    shape: "index(store, field, opts) -> nil",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "declare a secondary index on a document field",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "info",
  {
    kind: :effect,
    shape: "info(store) -> {keys, bytes, engine}",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "size and engine facts of the store as a record",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "keys",
  {
    kind: :effect,
    shape: "keys(store, opts) -> [key]",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "every key under a prefix, sorted",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "list",
  {
    kind: :effect,
    shape: "list(store, opts) -> [{key, value}]",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "every entry under a prefix, all pages, sorted",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "need",
  {
    kind: :effect,
    shape: "need(store, key, opts) -> value",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "the value at a key, raising not_found",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "open",
  {
    kind: :effect,
    shape: "open(spec) -> store",
    laterals: %w[capability config resource],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "connect to an embedded, Redis, etcd or document store",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "patch",
  {
    kind: :effect,
    shape: "patch(store, key, patch) -> doc",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "deep-merge a patch into the stored document",
    wave: 3,
    origin: "B",
    contract: "patch(store, key, opts) -> doc"
  }
)

verb(
  "kakunou?",
  "put",
  {
    kind: :effect,
    shape: "put(store, key, value, opts) -> value",
    laterals: %w[deadline error idempotent],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "create or replace the value at a key",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "query",
  {
    kind: :effect,
    shape: "query(store, filter, opts) -> [doc]",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "documents matching a filter record, sorted",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "range",
  {
    kind: :effect,
    shape: "range(store, from, to, opts) -> [{key, value}]",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "entries between two keys in key order",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "snapshot",
  {
    kind: :effect,
    shape: "snapshot(store) -> view",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "a read-only view frozen at one moment",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "swap",
  {
    kind: :effect,
    shape: "swap(store, key, expected, new) -> Bool",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "set new only if the value equals expected",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "ttl",
  {
    kind: :effect,
    shape: "ttl(store, key) -> duration or nil",
    laterals: ["time"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "time left before a key vanishes, or nil",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "update",
  {
    kind: :effect,
    shape: "update(store, key, f, opts) -> value",
    laterals: %w[error idempotent retry],
    fleet: nil,
    today: "absent",
    meaning: "replace a value with f(old); conflict if it moved",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "watch",
  {
    kind: :stream,
    shape: "watch(store, f, opts) -> nil",
    laterals: %w[cancel deadline],
    fleet: nil,
    today: "absent",
    meaning: "call f per key change under a prefix",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kakunou?",
  "with_transaction",
  {
    kind: :effect,
    shape: "with_transaction(store, f, opts) -> value",
    laterals: %w[error resource retry],
    fleet: nil,
    today: "absent",
    meaning: "run f against a consistent view; commit or abandon",
    wave: 3,
    origin: "B"
  }
)

edge(
  "kakunou?::open",
  :composes,
  "himitsu::read",
  "credentials from a secret ref"
)

edge(
  "kakunou?::with_transaction",
  :composes,
  "kakunou?::batch",
  "commit applies the collected writes"
)

edge("kakunou?::update", :composes, "kakunou?::get", "reads the old value")
edge("kakunou?::clear", :composes, "kakunou?::keys", "finds the keys")
edge("kakunou?::count", :composes, "kakunou?::keys", "size of the key set")

edge(
  "kakunou?::query",
  :composes,
  "kakunou?::list",
  "filter applied to listed documents"
)

edge(
  "kakunou?::update",
  :composes,
  "kakunou?::swap",
  "writes only if unchanged"
)

edge(
  "kakunou?::patch",
  :composes,
  "shuusei::deep_merge",
  "deep merge of the patch"
)

edge("kakunou?::open", :inverse, "kakunou?::close", "releases the store")

edge(
  "kakunou?::put",
  :inverse,
  "kakunou?::delete",
  "delete makes absent what put made"
)

edge("kakunou?::import", :inverse, "kakunou?::export", "whole store back in")
edge("kakunou?::export", :inverse, "kakunou?::import", "whole store back in")
edge("kakunou?::close", :inverse, "kakunou?::open", "releases the store")

edge(
  "kakunou?::delete",
  :inverse,
  "kakunou?::put",
  "delete makes absent what put made"
)

edge("kakunou?::clear", :lifts, "kakunou?::delete", "prefix at once")
edge("kakunou?::get_many", :lifts, "kakunou?::get", "one round trip for many")
edge("kakunou?::list", :lifts, "kakunou?::get", "every entry of a prefix")
edge("kakunou?::watch", :lifts, "kakunou?::get", "change stream of keys")
edge("kakunou?::export", :lifts, "kakunou?::list", "whole store out")
edge("kakunou?::batch", :lifts, "kakunou?::put", "many writes as one unit")
edge("kakunou?::import", :lifts, "kakunou?::put", "bulk load")
edge("kakunou?::import", :pairs, "fairu::stream", "bulk load from a file")

edge(
  "kakunou?::compact",
  :pairs,
  "kakunou?::clear",
  "reclaims what deletes left"
)

edge("kakunou?::open", :pairs, "kakunou?::close", "handle and its release")
edge("kakunou?::info", :pairs, "kakunou?::count", "size facts")
edge("kakunou?::list", :pairs, "kakunou?::keys", "entries beside names")
edge("kakunou?::index", :pairs, "kakunou?::query", "indexes speed filters")
edge("kakunou?::expire", :pairs, "kakunou?::ttl", "set and read the lifetime")

edge(
  "kakunou?::snapshot",
  :pairs,
  "kakunou?::with_transaction",
  "frozen view for reads"
)

edge("kakunou?::has?", :refines, "kakunou?::get", "existence only")
edge("kakunou?::need", :refines, "kakunou?::get", "raises when absent")
edge("kakunou?::ttl", :refines, "kakunou?::info", "one fact about a key")
edge("kakunou?::keys", :refines, "kakunou?::list", "names only")

edge(
  "kakunou?::query",
  :refines,
  "kakunou?::list",
  "filters by document fields"
)

edge("kakunou?::range", :refines, "kakunou?::list", "bounded by two keys")
edge("kakunou?::create", :refines, "kakunou?::put", "refuses to overwrite")
edge("kakunou?::swap", :refines, "kakunou?::put", "conditional write")

edge(
  "kakunou?::increment",
  :refines,
  "kakunou?::update",
  "numeric add inside the store"
)

edge(
  "kakunou?::patch",
  :refines,
  "kakunou?::update",
  "patch inside the document"
)

edge("kakunou?::expire", :requires, "kakunou?::has?", "key must be present")
edge("kakunou?::get", :requires, "kakunou?::open", "needs a connected store")
