space("kumo?", {status: :provisional})

verb(
  "kumo?",
  "events",
  {
    kind: :effect,
    shape: "events(opts) -> [event]",
    laterals: ["error", "time"],
    fleet: nil,
    today: "absent",
    meaning: "the audit trail of changes",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kumo?",
  "find",
  {
    kind: :effect,
    shape: "find(query, opts) -> [resource]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "resources by tag or attribute across kinds",
    wave: 2,
    origin: "E",
    contract: "find(query, query, opts) -> [resource]"
  }
)

verb(
  "kumo?",
  "get",
  {
    kind: :effect,
    shape: "get(kind, id, opts) -> resource or nil",
    laterals: ["error", "ratelimit"],
    fleet: "cordel",
    today: "absent",
    meaning: "one cloud resource, nil when absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kumo?",
  "has?",
  {
    kind: :effect,
    shape: "has?(kind, id, opts) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a resource exists",
    wave: 1,
    origin: "E",
    contract: "has?(kind, id) -> Bool"
  }
)

verb(
  "kumo?",
  "list",
  {
    kind: :effect,
    shape: "list(kind, opts) -> [resource]",
    laterals: ["deadline", "error", "ratelimit"],
    fleet: "cordel",
    today: "absent",
    meaning: "cloud resources of a kind, all pages",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kumo?",
  "need",
  {
    kind: :effect,
    shape: "need(kind, id, opts) -> resource",
    laterals: ["error"],
    fleet: "cordel",
    today: "absent",
    meaning: "one cloud resource, raises when absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kumo?",
  "quota",
  {
    kind: :effect,
    shape: "quota(kind, opts) -> {used:, limit:}",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "how much of a limit is spent",
    wave: 2,
    origin: "E",
    contract: "quota(kind, key) -> {used:, limit:}"
  }
)

verb(
  "kumo?",
  "regions",
  {
    kind: :effect,
    shape: "regions(opts) -> [region]",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "regions available to the account",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kumo?",
  "tag",
  {
    kind: :effect,
    shape: "tag(resource, tags) -> nil",
    laterals: ["capability", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "set tags on a resource",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kumo?",
  "tags",
  {
    kind: :effect,
    shape: "tags(resource) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "the tags on a resource",
    wave: 2,
    origin: "E"
  }
)

verb(
  "kumo?",
  "wait",
  {
    kind: :effect,
    shape: "wait(resource, state, opts) -> resource",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "block until a resource reaches a state",
    wave: 2,
    origin: "E"
  }
)

verb(
  "kumo?",
  "whoami",
  {
    kind: :effect,
    shape: "whoami(opts) -> identity",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "the account and role the credential acts as",
    wave: 1,
    origin: "E"
  }
)

edge("kumo?::need", :composes, "kumo?::get", "get then raise")
edge("kumo?::wait", :composes, "kumo?::get", "poll state")
edge("kumo?::find", :composes, "kumo?::tags", "tag query")
edge("kumo?::find", :generalizes, "kumo?::list", "across kinds")
edge("kumo?::quota", :guards, "kouchiku?::apply", "capacity before creating")
edge("kumo?::whoami", :guards, "kumo?::list", "know the account first")
edge("kumo?::tags", :inverse, "kumo?::tag", "write versus read")
edge("kumo?::tag", :inverse, "kumo?::tags", "write versus read")
edge("kumo?::events", :pairs, "kouchiku?::drift", "who changed what")
edge("kumo?::regions", :pairs, "kumo?::quota", "quota per region")
edge("kumo?::get", :refines, "core::get", "nil when absent")
edge("kumo?::tags", :refines, "core::get", "resource tags")
edge("kumo?::has?", :refines, "core::has?", "resource exists")
edge("kumo?::quota", :refines, "core::info", "limit and use")
edge("kumo?::events", :refines, "core::list", "audit trail")
edge("kumo?::list", :refines, "core::list", "cloud resources")
edge("kumo?::regions", :refines, "core::list", "available regions")
edge("kumo?::need", :refines, "core::need", "raises when absent")
edge("kumo?::tag", :requires, "kumo?::whoami", "acts under an identity")
