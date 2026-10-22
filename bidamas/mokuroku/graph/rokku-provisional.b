space("rokku?", {status: :provisional})

verb(
  "rokku?",
  "acquire",
  {
    kind: :effect,
    shape: "acquire(locks, name, opts) -> lease",
    laterals: ["deadline", "error", "resource", "retry"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "take a named lock with a time limit, waiting up to wait",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rokku?",
  "barrier",
  {
    kind: :effect,
    shape: "barrier(locks, name, n, opts) -> nil",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "wait until n parties have arrived",
    wave: 4,
    origin: "B"
  }
)

verb(
  "rokku?",
  "close",
  {
    kind: :effect,
    shape: "close(locks) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "release the backend connection",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rokku?",
  "elect",
  {
    kind: :effect,
    shape: "elect(locks, name, f, opts) -> nil",
    laterals: ["cancel", "resource", "switch", "time"],
    fleet: "shinka",
    today: "absent",
    meaning: "run f only while this process is the leader",
    wave: 3,
    origin: "B"
  }
)

verb(
  "rokku?",
  "expired?",
  {
    kind: :pure,
    shape: "expired?(lease, now) -> Bool",
    laterals: ["time"],
    fleet: "almoxarifado",
    today: "absent",
    meaning: "whether a lease has passed its end",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rokku?",
  "fence",
  {
    kind: :pure,
    shape: "fence(lease) -> number",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "the rising token a storage layer uses to reject stale holders",
    wave: 3,
    origin: "B"
  }
)

verb(
  "rokku?",
  "held?",
  {
    kind: :effect,
    shape: "held?(lease) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "whether a lease is still valid",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rokku?",
  "holder",
  {
    kind: :effect,
    shape: "holder(locks, name) -> {owner, since, expires} or nil",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "who holds a lock now, or nil when free",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rokku?",
  "list",
  {
    kind: :effect,
    shape: "list(locks, opts) -> [holder]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "every held lock under a prefix",
    wave: 3,
    origin: "B"
  }
)

verb(
  "rokku?",
  "open",
  {
    kind: :effect,
    shape: "open(spec) -> locks",
    laterals: ["capability", "config", "resource"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "connect to a lock backend: file, database, Redis or cluster",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rokku?",
  "release",
  {
    kind: :effect,
    shape: "release(lease) -> nil",
    laterals: ["idempotent", "resource"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "give up a lock; already released counts as done",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rokku?",
  "renew",
  {
    kind: :effect,
    shape: "renew(lease, by) -> lease",
    laterals: ["error", "time"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "lengthen the life of a lease before it lapses",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rokku?",
  "revoke",
  {
    kind: :effect,
    shape: "revoke(locks, name) -> nil",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "take a lock from its holder by force",
    wave: 3,
    origin: "B"
  }
)

verb(
  "rokku?",
  "with_lock",
  {
    kind: :effect,
    shape: "with_lock(locks, name, f, opts) -> value",
    laterals: ["cancel", "deadline", "error", "resource"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "run f while holding a lock, releasing on any exit",
    wave: 2,
    origin: "B",
    contract: "with_lock(locks, name, opts) -> value"
  }
)

edge(
  "rokku?::barrier",
  :composes,
  "rokku?::acquire",
  "counts arrivals under a lock"
)

edge("rokku?::elect", :composes, "rokku?::acquire", "campaigns")
edge("rokku?::with_lock", :composes, "rokku?::acquire", "takes the lock")
edge("rokku?::held?", :composes, "rokku?::expired?", "validity by clock")

edge(
  "rokku?::with_lock",
  :composes,
  "rokku?::release",
  "frees it on every exit"
)

edge("rokku?::elect", :composes, "rokku?::renew", "holds leadership")

edge(
  "rokku?::renew",
  :generalizes,
  "himitsu::renew",
  "one meaning for every lease"
)

edge(
  "rokku?::revoke",
  :generalizes,
  "himitsu::revoke",
  "one meaning for every grant"
)

edge(
  "rokku?::renew",
  :generalizes,
  "kyasshu?::renew",
  "one meaning for every lifetime"
)

edge(
  "rokku?::renew",
  :generalizes,
  "taiki?::renew",
  "one meaning for every lease"
)

edge("rokku?::fence", :guards, "kakunou?::put", "storage rejects stale holders")
edge("rokku?::expired?", :guards, "rokku?::renew", "late renewals are refused")
edge("rokku?::release", :inverse, "rokku?::acquire", "gives the lock back")
edge("rokku?::open", :inverse, "rokku?::close", "releases the backend")
edge("rokku?::close", :inverse, "rokku?::open", "releases the backend")
edge("rokku?::acquire", :inverse, "rokku?::release", "gives the lock back")
edge("rokku?::list", :lifts, "rokku?::holder", "all locks under a prefix")
edge("rokku?::fence", :pairs, "rokku?::acquire", "token issued with the lease")
edge("rokku?::holder", :pairs, "rokku?::acquire", "who won")
edge("rokku?::open", :pairs, "rokku?::close", "handle and its release")
edge("rokku?::acquire", :pairs, "rokku?::release", "take and give back")
edge("rokku?::revoke", :refines, "rokku?::release", "forced by someone else")
edge("rokku?::renew", :requires, "rokku?::held?", "only a valid lease")
