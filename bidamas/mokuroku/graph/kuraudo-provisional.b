space("kuraudo?", {status: :provisional})

verb(
  "kuraudo?",
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
  "kuraudo?",
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
  "kuraudo?",
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
  "kuraudo?",
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
  "kuraudo?",
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
  "kuraudo?",
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
  "kuraudo?",
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
  "kuraudo?",
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
  "kuraudo?",
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
  "kuraudo?",
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
  "kuraudo?",
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
  "kuraudo?",
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

edge("kuraudo?::need", :composes, "kuraudo?::get", "get then raise")
edge("kuraudo?::wait", :composes, "kuraudo?::get", "poll state")
edge("kuraudo?::find", :composes, "kuraudo?::tags", "tag query")
edge("kuraudo?::find", :generalizes, "kuraudo?::list", "across kinds")
edge("kuraudo?::quota", :guards, "kouchiku?::apply", "capacity before creating")
edge("kuraudo?::whoami", :guards, "kuraudo?::list", "know the account first")
edge("kuraudo?::tags", :inverse, "kuraudo?::tag", "write versus read")
edge("kuraudo?::tag", :inverse, "kuraudo?::tags", "write versus read")
edge("kuraudo?::events", :pairs, "kouchiku?::drift", "who changed what")
edge("kuraudo?::regions", :pairs, "kuraudo?::quota", "quota per region")
edge("kuraudo?::get", :refines, "core::get", "nil when absent")
edge("kuraudo?::tags", :refines, "core::get", "resource tags")
edge("kuraudo?::has?", :refines, "core::has?", "resource exists")
edge("kuraudo?::quota", :refines, "core::info", "limit and use")
edge("kuraudo?::events", :refines, "core::list", "audit trail")
edge("kuraudo?::list", :refines, "core::list", "cloud resources")
edge("kuraudo?::regions", :refines, "core::list", "available regions")
edge("kuraudo?::need", :refines, "core::need", "raises when absent")
edge("kuraudo?::tag", :requires, "kuraudo?::whoami", "acts under an identity")
