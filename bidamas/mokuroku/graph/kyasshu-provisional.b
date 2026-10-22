space("kyasshu?", {status: :provisional})

verb(
  "kyasshu?",
  "clear",
  {
    kind: :effect,
    shape: "clear(cache) -> nil",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "drop every entry",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "delete",
  {
    kind: :effect,
    shape: "delete(cache, key) -> nil",
    laterals: ["cache", "idempotent"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "drop one entry; absent counts as done",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "flush",
  {
    kind: :effect,
    shape: "flush(cache) -> count",
    laterals: ["cache", "error"],
    fleet: nil,
    today: "absent",
    meaning: "push pending write-behind entries to the backing store",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "fresh?",
  {
    kind: :pure,
    shape: "fresh?(entry, now) -> Bool",
    laterals: ["cache", "time"],
    fleet: "token-cache-go",
    today: "absent",
    meaning: "whether an entry is still inside its lifetime",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "get",
  {
    kind: :effect,
    shape: "get(cache, key) -> value or nil",
    laterals: ["cache", "time"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "the cached value, or nil when absent or expired",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "has?",
  {
    kind: :effect,
    shape: "has?(cache, key) -> Bool",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "whether a live entry exists, counting no hit",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "info",
  {
    kind: :effect,
    shape: "info(cache) -> {hits, misses, evictions, size}",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "counters and size of the cache as a record",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "invalidate",
  {
    kind: :effect,
    shape: "invalidate(cache, subject) -> count",
    laterals: ["cache", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "mark stale by key, prefix, tag or dependency",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "key",
  {
    kind: :pure,
    shape: "key(parts) -> text",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "one canonical cache key built from ordered parts",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "memoize",
  {
    kind: :pure,
    shape: "memoize(f, opts) -> f",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "a function that remembers results by argument",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "open",
  {
    kind: :effect,
    shape: "open(spec) -> cache",
    laterals: ["config", "resource"],
    fleet: "almoxarifado",
    today: "absent",
    meaning: "make a cache with a size, policy and lifetime",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "put",
  {
    kind: :effect,
    shape: "put(cache, key, value, opts) -> value",
    laterals: ["cache", "time"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "store a value, evicting by policy when full",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "refresh",
  {
    kind: :effect,
    shape: "refresh(cache, key, f) -> value",
    laterals: ["cache", "error"],
    fleet: nil,
    today: "absent",
    meaning: "recompute one entry now, serving the old one meanwhile",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "remember",
  {
    kind: :effect,
    shape: "remember(cache, key, f, opts) -> value",
    laterals: ["cache", "deadline", "error", "idempotent"],
    fleet: "almoxarifado",
    today: "absent",
    meaning: "get, or compute with f once for concurrent callers and store",
    wave: 1,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "renew",
  {
    kind: :effect,
    shape: "renew(cache, key, ttl) -> nil",
    laterals: ["cache", "time"],
    fleet: nil,
    today: "absent",
    meaning: "lengthen the life of an entry without changing its value",
    wave: 2,
    origin: "B",
    contract: "renew(cache, key, opts) -> nil"
  }
)

verb(
  "kyasshu?",
  "save",
  {
    kind: :effect,
    shape: "save(cache, path) -> nil",
    laterals: ["cache", "serialize"],
    fleet: "token-cache-go",
    today: "absent",
    meaning: "persist entries to disk so a restart keeps them",
    wave: 3,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "sweep",
  {
    kind: :effect,
    shape: "sweep(cache) -> count",
    laterals: ["cache", "time"],
    fleet: nil,
    today: "absent",
    meaning: "remove every expired entry now",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "tier",
  {
    kind: :pure,
    shape: "tier(caches) -> cache",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "layer caches so a miss falls to the next and fills upward",
    wave: 2,
    origin: "B"
  }
)

verb(
  "kyasshu?",
  "warm",
  {
    kind: :effect,
    shape: "warm(cache, source, keys) -> count",
    laterals: ["cache", "cancel"],
    fleet: nil,
    today: "absent",
    meaning: "fill entries ahead of demand",
    wave: 3,
    origin: "B"
  }
)

edge("kyasshu?::save", :composes, "fairu::write", "persists entries")
edge("kyasshu?::open", :composes, "kakunou?::open", "optional shared tier")
edge("kyasshu?::flush", :composes, "kakunou?::put", "write-behind target")

edge(
  "kyasshu?::get",
  :composes,
  "kyasshu?::fresh?",
  "expired entries read as absent"
)

edge(
  "kyasshu?::remember",
  :composes,
  "kyasshu?::fresh?",
  "stale entries are recomputed"
)

edge("kyasshu?::sweep", :composes, "kyasshu?::fresh?", "finds expired entries")
edge("kyasshu?::remember", :composes, "kyasshu?::get", "hit path")

edge(
  "kyasshu?::refresh",
  :composes,
  "kyasshu?::put",
  "stores the recomputed value"
)

edge(
  "kyasshu?::remember",
  :composes,
  "kyasshu?::put",
  "miss path stores the result"
)

edge(
  "kyasshu?::memoize",
  :composes,
  "kyasshu?::remember",
  "function results cached by argument"
)

edge(
  "kyasshu?::tier",
  :composes,
  "kyasshu?::remember",
  "miss falls to the next layer"
)

edge("kyasshu?::key", :composes, "shomei::hash", "stable digest of parts")
edge("kyasshu?::put", :inverse, "kyasshu?::delete", "drops what put stored")
edge("kyasshu?::delete", :inverse, "kyasshu?::put", "drops what put stored")
edge("kyasshu?::clear", :lifts, "kyasshu?::delete", "every entry")
edge("kyasshu?::sweep", :lifts, "kyasshu?::delete", "many at once")

edge(
  "kyasshu?::warm",
  :lifts,
  "kyasshu?::remember",
  "many keys ahead of demand"
)

edge("kyasshu?::info", :pairs, "kyasshu?::get", "counters beside lookups")
edge("kyasshu?::key", :pairs, "kyasshu?::get", "the lookup subject")
edge("kyasshu?::memoize", :pairs, "kyasshu?::key", "argument digest as key")
edge("kyasshu?::save", :pairs, "kyasshu?::open", "persist then reload")
edge("kyasshu?::flush", :pairs, "kyasshu?::put", "write-behind drains puts")
edge("kyasshu?::get", :pairs, "kyasshu?::put", "read and write sides")
edge("kyasshu?::invalidate", :pairs, "kyasshu?::put", "staleness and refill")

edge(
  "kyasshu?::invalidate",
  :refines,
  "kyasshu?::delete",
  "by prefix, tag or dependency"
)

edge("kyasshu?::has?", :refines, "kyasshu?::get", "no hit counted")
edge("kyasshu?::refresh", :refines, "kyasshu?::remember", "forced recompute")
edge("kyasshu?::renew", :requires, "kyasshu?::has?", "entry must be live")
