space("habu", {status: :ratified})

verb(
  "habu",
  "cancel",
  {
    kind: :effect,
    shape: "cancel(run) -> nil",
    laterals: ["cancel", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "stop a run in progress",
    wave: 2,
    origin: "F"
  }
)

verb(
  "habu",
  "create",
  {
    kind: :effect,
    shape: "create(path, value, opts) -> record",
    laterals: ["error", "idempotent", "ratelimit"],
    fleet: nil,
    today: "absent",
    meaning: "add an item that must not exist",
    wave: 1,
    origin: "E"
  }
)

verb(
  "habu",
  "delete",
  {
    kind: :effect,
    shape: "delete(path, opts) -> nil",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "remove an item",
    wave: 1,
    origin: "E"
  }
)

verb(
  "habu",
  "dispatch",
  {
    kind: :effect,
    shape: "dispatch(workflow, inputs, opts) -> run",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "start a workflow run",
    wave: 2,
    origin: "F"
  }
)

verb(
  "habu",
  "get",
  {
    kind: :effect,
    shape: "get(path, opts) -> record or nil",
    laterals: ["deadline", "error", "ratelimit", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "one API item, nil when absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "habu",
  "land",
  {
    kind: :effect,
    shape: "land(pr, opts) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "merge a pull request when checks allow",
    wave: 1,
    origin: "E"
  }
)

verb(
  "habu",
  "list",
  {
    kind: :effect,
    shape: "list(path, opts) -> [record]",
    laterals: ["deadline", "error", "ratelimit", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "every item under an API path, all pages",
    wave: 1,
    origin: "E"
  }
)

verb(
  "habu",
  "need",
  {
    kind: :effect,
    shape: "need(path, opts) -> record",
    laterals: ["error", "ratelimit"],
    fleet: nil,
    today: "absent",
    meaning: "one API item, raises when absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "habu",
  "put",
  {
    kind: :effect,
    shape: "put(path, value, opts) -> record",
    laterals: ["error", "idempotent", "ratelimit"],
    fleet: nil,
    today: "absent",
    meaning: "create or replace an item",
    wave: 1,
    origin: "E"
  }
)

verb(
  "habu",
  "query",
  {
    kind: :effect,
    shape: "query(graphql, vars) -> record",
    laterals: ["deadline", "error", "ratelimit"],
    fleet: nil,
    today: "absent",
    meaning: "a GraphQL question",
    wave: 1,
    origin: "E"
  }
)

verb(
  "habu",
  "read",
  {
    kind: :effect,
    shape: "read(path, {at:}) -> bytes",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "file content or a PR diff from the API",
    wave: 1,
    origin: "E",
    contract: "read(path, opts) -> bytes"
  }
)

verb(
  "habu",
  "rerun",
  {
    kind: :effect,
    shape: "rerun(run, opts) -> run",
    laterals: ["retry"],
    fleet: nil,
    today: "absent",
    meaning: "run again, failed jobs only if asked",
    wave: 2,
    origin: "F"
  }
)

verb(
  "habu",
  "update",
  {
    kind: :effect,
    shape: "update(path, f, opts) -> record",
    laterals: ["error", "idempotent", "ratelimit"],
    fleet: nil,
    today: "absent",
    meaning: "change an item with a function",
    wave: 1,
    origin: "E"
  }
)

verb(
  "habu",
  "wait",
  {
    kind: :effect,
    shape: "wait(run, opts) -> result",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "wait for a run to finish",
    wave: 2,
    origin: "F"
  }
)

edge("habu::list", :composes, "habu::get", "items of a path")
edge("habu::put", :composes, "habu::get", "check then upsert")
edge("habu::update", :composes, "habu::get", "read then write")
edge("habu::update", :composes, "habu::put", "conditional write")
edge("habu::land", :composes, "habu::update", "merging changes the PR")
edge("habu::put", :generalizes, "habu::create", "upsert")
edge("habu::list", :generalizes, "habu::get", "all entries")
edge("habu::query", :generalizes, "habu::get", "graphql form")
edge("habu::query", :generalizes, "habu::list", "GraphQL form")
edge("habu::dispatch", :inverse, "habu::cancel", "start and stop a run")
edge("habu::delete", :inverse, "habu::create", "remove an item")
edge("habu::create", :inverse, "habu::delete", "remove an item")
edge("habu::cancel", :inverse, "habu::dispatch", "start and stop a run")
edge("habu::create", :pairs, "gitto::push", "PR follows a pushed branch")
edge("habu::wait", :pairs, "habu::cancel", "wait with a deadline, cancel on it")
edge("habu::list", :pairs, "habu::query", "REST versus GraphQL")
edge("habu::put", :pairs, "habu::update", "replace versus change")
edge("habu::dispatch", :pairs, "habu::wait", "start then wait")
edge("habu::get", :pairs, "kadai?::get", "issues are habu paths")
edge("habu::land", :pairs, "rirezu?::cut", "merge triggers release")
edge("habu::create", :refines, "core::create", "refuses to overwrite")
edge("habu::get", :refines, "core::get", "nil when absent")
edge("habu::list", :refines, "core::list", "all pages")
edge("habu::need", :refines, "core::need", "raises when absent")
edge("habu::put", :refines, "core::put", "upsert")
edge("habu::read", :refines, "core::read", "content from API")
edge("habu::update", :refines, "core::update", "function of old value")
edge("habu::rerun", :refines, "habu::dispatch", "same inputs again")
edge("habu::need", :refines, "habu::get", "raises on absence")
edge("habu::get", :refines, "habu::need", "nil instead of raising")
edge("habu::create", :refines, "habu::put", "refuses to overwrite")
edge("habu::wait", :requires, "habu::dispatch", "waits on a started run")
edge("habu::cancel", :requires, "habu::get", "run must exist")
edge("habu::land", :requires, "paipurain?::get", "checks must pass")
