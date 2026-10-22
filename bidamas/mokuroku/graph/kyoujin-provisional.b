space("kyoujin?", {status: :provisional})

verb(
  "kyoujin?",
  "admit",
  {
    kind: :effect,
    shape: "admit(bucket, key, n) -> Bool",
    laterals: ["ratelimit"],
    fleet: "samba",
    today: "absent",
    meaning: "Take n tokens now if present; never waits.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "breaker",
  {
    kind: :decl,
    shape: "breaker(name, opts) -> breaker",
    laterals: ["config", "error"],
    fleet: "todoku-go",
    today: "absent",
    meaning: "Declare a breaker: failure count, window and reset time.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "bucket",
  {
    kind: :decl,
    shape: "bucket(rate, burst) -> bucket",
    laterals: ["config", "ratelimit"],
    fleet: "samba",
    today: "absent",
    meaning: "Declare a token bucket by rate and burst.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "bulkhead",
  {
    kind: :decl,
    shape: "bulkhead(name, limit, queue) -> bulkhead",
    laterals: ["config", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "Declare a bound on concurrent callers of one resource.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "drain",
  {
    kind: :effect,
    shape: "drain(source, opts) -> info",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Finish queued work and stop taking more.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "enter",
  {
    kind: :effect,
    shape: "enter(bulkhead, f, opts) -> value",
    laterals: ["deadline", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "Run f in a bulkhead slot; raise when full.",
    wave: 2,
    origin: "C",
    contract: "enter(bulkhead, f) -> value"
  }
)

verb(
  "kyoujin?",
  "hedge",
  {
    kind: :effect,
    shape: "hedge(f, after) -> value",
    laterals: ["deadline", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "Start a second try after a delay; keep the first answer.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "inject",
  {
    kind: :decl,
    shape: "inject(fault, opts) -> wrapper",
    laterals: ["switch", "test"],
    fleet: nil,
    today: "absent",
    meaning: "Add delay, error or loss to a call, for chaos tests.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "key",
  {
    kind: :pure,
    shape: "key(request) -> idempotency key",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "The stable key that names one logical request.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "limiter",
  {
    kind: :decl,
    shape: "limiter(count, duration) -> limiter",
    laterals: ["ratelimit"],
    fleet: "pleme-middleware-rate-limit",
    today: "absent",
    meaning: "Declare a sliding-window quota.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "once",
  {
    kind: :effect,
    shape: "once(store, key, f) -> value",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "Run f once per key; later calls return the stored result.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "pressure",
  {
    kind: :effect,
    shape: "pressure(queue) -> level",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "How full a queue or pool is, as a level.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "probe",
  {
    kind: :effect,
    shape: "probe(probe, opts) -> record",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Run a health probe; return status and detail.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "protect",
  {
    kind: :effect,
    shape: "protect(breaker, f) -> value",
    laterals: ["error", "retry"],
    fleet: "todoku-go",
    today: "absent",
    meaning: "Run f through a breaker; open breaker raises at once.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "quota",
  {
    kind: :effect,
    shape: "quota(limiter, key) -> record",
    laterals: ["ratelimit"],
    fleet: nil,
    today: "absent",
    meaning: "Remaining, limit and reset time for a key.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "ready?",
  {
    kind: :effect,
    shape: "ready?(checks) -> Bool",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Whether every required check passes.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "reset",
  {
    kind: :effect,
    shape: "reset(breaker) -> nil",
    laterals: ["switch"],
    fleet: nil,
    today: "absent",
    meaning: "Force a breaker closed.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "seen?",
  {
    kind: :effect,
    shape: "seen?(store, key) -> Bool",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "Whether a key already ran.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "shed",
  {
    kind: :pure,
    shape: "shed(load, policy) -> Bool",
    laterals: ["ratelimit", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "Whether to refuse work now to keep latency.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "slow",
  {
    kind: :effect,
    shape: "slow(source, level) -> nil",
    laterals: ["ratelimit"],
    fleet: nil,
    today: "absent",
    meaning: "Tell a producer to slow until pressure falls.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "state",
  {
    kind: :effect,
    shape: "state(breaker) -> :closed or :open or :half_open",
    laterals: [],
    fleet: "todoku-go",
    today: "absent",
    meaning: "Where a breaker stands now.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyoujin?",
  "take",
  {
    kind: :effect,
    shape: "take(bucket, key, n, opts) -> nil",
    laterals: ["deadline", "ratelimit"],
    fleet: "samba",
    today: "absent",
    meaning: "Wait until n tokens are free, then take them.",
    wave: 1,
    origin: "C",
    contract: "take(bucket, key) -> nil"
  }
)

verb(
  "kyoujin?",
  "trip",
  {
    kind: :effect,
    shape: "trip(breaker) -> nil",
    laterals: ["switch"],
    fleet: nil,
    today: "absent",
    meaning: "Force a breaker open.",
    wave: 2,
    origin: "C"
  }
)

edge(
  "kyoujin?::enter",
  :composes,
  "heikou::limit",
  "a bulkhead is a semaphore with a queue"
)

edge("kyoujin?::hedge", :composes, "heikou::race", "second try races the first")
edge("kyoujin?::probe", :composes, "heikou::timeout", "a probe is bounded")

edge(
  "kyoujin?::take",
  :composes,
  "kyoujin?::admit",
  "admit, else wait for refill"
)

edge("kyoujin?::ready?", :composes, "kyoujin?::probe", "all required probes")

edge(
  "kyoujin?::limiter",
  :generalizes,
  "kyoujin?::bucket",
  "a quota counted over a window"
)

edge(
  "kyoujin?::protect",
  :guards,
  "heikou::retry",
  "an open breaker ends retries"
)

edge("kyoujin?::key", :guards, "kyoujin?::once", "keys decide sameness")

edge(
  "kyoujin?::slow",
  :inverse,
  "kyoujin?::drain",
  "stop intake fully versus slow it"
)

edge("kyoujin?::trip", :inverse, "kyoujin?::reset", "force open, force closed")

edge(
  "kyoujin?::drain",
  :inverse,
  "kyoujin?::slow",
  "stop intake fully versus slow it"
)

edge("kyoujin?::reset", :inverse, "kyoujin?::trip", "force open, force closed")

edge(
  "kyoujin?::breaker",
  :pairs,
  "chuukai?::eject",
  "breaker locally, eject at the edge"
)

edge(
  "kyoujin?::admit",
  :pairs,
  "chuukai?::route",
  "per-route limits at the edge"
)

edge(
  "kyoujin?::drain",
  :pairs,
  "heikou::cancel",
  "drain waits where cancel stops"
)

edge("kyoujin?::take", :pairs, "heikou::deadline", "waiting is bounded")
edge("kyoujin?::bucket", :pairs, "kyoujin?::admit", "declare and use")

edge(
  "kyoujin?::inject",
  :pairs,
  "kyoujin?::breaker",
  "chaos exercises breakers"
)

edge("kyoujin?::bulkhead", :pairs, "kyoujin?::enter", "declare and use")

edge(
  "kyoujin?::shed",
  :pairs,
  "kyoujin?::pressure",
  "pressure decides what to refuse"
)

edge("kyoujin?::breaker", :pairs, "kyoujin?::protect", "declare and use")
edge("kyoujin?::pressure", :pairs, "messeeji?::lag", "queue depth beside lag")

edge(
  "kyoujin?::bucket",
  :pairs,
  "shigoto?::budget",
  "rate and parallelism bounds"
)

edge("kyoujin?::probe", :pairs, "shihyou::budget", "probes and objectives")

edge(
  "kyoujin?::inject",
  :refines,
  "kyoujin?::protect",
  "a wrapper around a call"
)

edge("kyoujin?::once", :refines, "kyoujin?::seen?", "seen? plus run")
edge("kyoujin?::trip", :refines, "kyoujin?::state", "forces a state")

edge(
  "kyoujin?::protect",
  :requires,
  "kyoujin?::breaker",
  "a breaker is required"
)

edge("kyoujin?::state", :requires, "kyoujin?::breaker", "reads a breaker")
edge("kyoujin?::admit", :requires, "kyoujin?::bucket", "takes from a bucket")

edge(
  "kyoujin?::enter",
  :requires,
  "kyoujin?::bulkhead",
  "needs the declared bound"
)

edge(
  "kyoujin?::hedge",
  :requires,
  "kyoujin?::key",
  "hedged calls must be idempotent"
)

edge("kyoujin?::once", :requires, "kyoujin?::key", "stored result per key")
edge("kyoujin?::seen?", :requires, "kyoujin?::key", "asks about a key")
edge("kyoujin?::quota", :requires, "kyoujin?::limiter", "reads a limiter")
edge("kyoujin?::slow", :requires, "kyoujin?::pressure", "reacts to a level")
