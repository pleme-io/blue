space("kadai?", {status: :provisional})

verb(
  "kadai?",
  "assign",
  {
    kind: :effect,
    shape: "assign(issue, who) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "name the owner of an issue",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kadai?",
  "comment",
  {
    kind: :effect,
    shape: "comment(issue, text) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "add a note to an issue",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kadai?",
  "create",
  {
    kind: :effect,
    shape: "create(tracker, value, opts) -> issue",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "open a new issue; refuse a duplicate key",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kadai?",
  "delete",
  {
    kind: :effect,
    shape: "delete(tracker, id) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "remove an issue; absent counts as done",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kadai?",
  "duplicates",
  {
    kind: :pure,
    shape: "duplicates(issues) -> [group]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "issues that describe one problem",
    wave: 3,
    origin: "F"
  }
)

verb(
  "kadai?",
  "get",
  {
    kind: :effect,
    shape: "get(tracker, id) -> issue or nil",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "one issue or nil",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kadai?",
  "link",
  {
    kind: :effect,
    shape: "link(issue, to, kind) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "relate two issues: blocks, duplicates, relates",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kadai?",
  "list",
  {
    kind: :effect,
    shape: "list(tracker, filter) -> [issue]",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "issues matching a filter, all pages, sorted",
    wave: 2,
    origin: "F",
    contract: "list(tracker, opts) -> [issue]"
  }
)

verb(
  "kadai?",
  "need",
  {
    kind: :effect,
    shape: "need(tracker, id) -> issue",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "one issue, raising not_found when absent",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kadai?",
  "query",
  {
    kind: :effect,
    shape: "query(tracker, question, params) -> [issue]",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "ask a tracker in its own query language",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kadai?",
  "sync",
  {
    kind: :effect,
    shape: "sync(from, to, opts) -> report",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "mirror issues between two trackers",
    wave: 3,
    origin: "F"
  }
)

verb(
  "kadai?",
  "transition",
  {
    kind: :effect,
    shape: "transition(issue, to, opts) -> issue",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "move an issue along its workflow; refuse an illegal move",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kadai?",
  "triage",
  {
    kind: :pure,
    shape: "triage(issues, rules) -> [issue]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "issues ordered and labelled by stated rules",
    wave: 3,
    origin: "F"
  }
)

verb(
  "kadai?",
  "update",
  {
    kind: :effect,
    shape: "update(tracker, id, f) -> issue",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "change an issue; conflict on a concurrent write",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kadai?",
  "watch",
  {
    kind: :stream,
    shape: "watch(tracker, f, opts) -> nil",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "call f per issue change until it returns stop",
    wave: 3,
    origin: "F"
  }
)

edge("kadai?::duplicates", :composes, "kadai?::list", "compares listed issues")
edge("kadai?::sync", :composes, "kadai?::list", "reads one tracker")
edge("kadai?::triage", :composes, "kadai?::list", "orders listed issues")
edge("kadai?::sync", :composes, "kadai?::update", "writes the other")
edge("kadai?::watch", :lifts, "kadai?::get", "follows changes")
edge("kadai?::sync", :pairs, "habu::update", "writes through habu")

edge(
  "kadai?::transition",
  :pairs,
  "kadai?::assign",
  "a move often changes owner"
)

edge("kadai?::delete", :pairs, "kadai?::duplicates", "duplicates are closed")
edge("kadai?::query", :pairs, "kadai?::list", "filter versus language")
edge("kadai?::get", :pairs, "kadai?::need", "nil versus raise")

edge(
  "kadai?::comment",
  :pairs,
  "rebyuu?::comment",
  "same meaning on another subject"
)

edge("kadai?::triage", :pairs, "shougai?::classify", "severity ranks the queue")
edge("kadai?::create", :pairs, "shougai?::postmortem", "action items")
edge("kadai?::link", :pairs, "youken?::satisfies", "issue to requirement")
edge("kadai?::create", :refines, "habu::create", "issue tracker entry")
edge("kadai?::delete", :refines, "habu::delete", "issue removed")
edge("kadai?::get", :refines, "habu::get", "issue by id")
edge("kadai?::list", :refines, "habu::list", "issues by filter")
edge("kadai?::need", :refines, "habu::need", "issue or raise")
edge("kadai?::query", :refines, "habu::query", "tracker query language")
edge("kadai?::update", :refines, "habu::update", "issue with f")
edge("kadai?::assign", :requires, "kadai?::get", "issue must exist")
edge("kadai?::comment", :requires, "kadai?::get", "issue must exist")
edge("kadai?::link", :requires, "kadai?::get", "both issues exist")

edge(
  "kadai?::transition",
  :requires,
  "nisshi::replay",
  "workflow is a lifecycle"
)
