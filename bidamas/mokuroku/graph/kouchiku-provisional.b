space("kouchiku?", {status: :provisional})

verb(
  "kouchiku?",
  "apply",
  {
    kind: :effect,
    shape: "apply(plan, opts) -> result",
    laterals: ["capability", "error", "log"],
    fleet: nil,
    today: "absent",
    meaning: "carry out a reviewed plan, gated and logged",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "check",
  {
    kind: :pure,
    shape: "check(stack) -> [finding]",
    laterals: ["test", "validate"],
    fleet: "pangea-sim",
    today: "absent",
    meaning: "refuse a bad stack before any plan",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "claim",
  {
    kind: :effect,
    shape: "claim(stack, opts) -> lease",
    laterals: ["capability", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "claim the state against a second writer",
    wave: 2,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "declare",
  {
    kind: :decl,
    shape: "declare(name, resources) -> stack",
    laterals: ["config", "validate"],
    fleet: "pangea-core",
    today: "absent",
    meaning: "infrastructure as typed resources",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "destroy",
  {
    kind: :effect,
    shape: "destroy(stack, opts) -> result",
    laterals: ["capability", "log"],
    fleet: nil,
    today: "absent",
    meaning: "remove everything a stack owns",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> [change]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "differences between two plans or stacks",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "drift",
  {
    kind: :effect,
    shape: "drift(stack) -> [difference]",
    laterals: ["error", "time"],
    fleet: "pangea-operator",
    today: "absent",
    meaning: "where real state left the declaration",
    wave: 2,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "get",
  {
    kind: :effect,
    shape: "get(stack, address) -> resource or nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "one resource in state, nil when absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "graph",
  {
    kind: :pure,
    shape: "graph(stack) -> graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "resource dependencies",
    wave: 2,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "import",
  {
    kind: :effect,
    shape: "import(stack, resource, id) -> state",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "adopt an existing resource into a stack",
    wave: 3,
    origin: "E",
    contract: "import(stack, resource, opts) -> state"
  }
)

verb(
  "kouchiku?",
  "list",
  {
    kind: :effect,
    shape: "list(stack, opts) -> [resource]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "resources a stack holds",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "move",
  {
    kind: :effect,
    shape: "move(stack, from, to) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "rename a resource without recreating it",
    wave: 3,
    origin: "E",
    contract: "move(stack, from, opts) -> nil"
  }
)

verb(
  "kouchiku?",
  "output",
  {
    kind: :effect,
    shape: "output(stack, name) -> value",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "a value a stack exports",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "plan",
  {
    kind: :effect,
    shape: "plan(stack, opts) -> plan",
    laterals: ["deadline", "error", "idempotent"],
    fleet: "pangea-operator",
    today: "absent",
    meaning: "what apply would create, change and delete",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "refresh",
  {
    kind: :effect,
    shape: "refresh(stack) -> state",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "read real state back into the record",
    wave: 2,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "render",
  {
    kind: :pure,
    shape: "render(stack, format) -> text",
    laterals: ["serialize"],
    fleet: "pangea-core",
    today: "absent",
    meaning: "a stack in the planner's input format",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "test",
  {
    kind: :effect,
    shape: "test(stack, suite) -> report",
    laterals: ["test"],
    fleet: "kensa",
    today: "absent",
    meaning: "prove a stack against its compliance suite",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kouchiku?",
  "unlock",
  {
    kind: :effect,
    shape: "unlock(lease) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "give up a state claim",
    wave: 2,
    origin: "E"
  }
)

edge("kouchiku?::test", :composes, "kouchiku?::check", "proof of a stack")
edge("kouchiku?::drift", :composes, "kouchiku?::diff", "compare to declaration")
edge("kouchiku?::plan", :composes, "kouchiku?::diff", "declared versus real")
edge("kouchiku?::output", :composes, "kouchiku?::get", "reads state")
edge("kouchiku?::graph", :composes, "kouchiku?::list", "edges between entries")

edge(
  "kouchiku?::drift",
  :composes,
  "kouchiku?::refresh",
  "refresh then compare"
)

edge(
  "kouchiku?::plan",
  :composes,
  "kouchiku?::refresh",
  "plan from current state"
)

edge("kouchiku?::apply", :guards, "kouchiku?::destroy", "same gates")
edge("kouchiku?::claim", :guards, "kouchiku?::move", "no move without a claim")
edge("kouchiku?::check", :guards, "kouchiku?::plan", "refuse before planning")

edge(
  "kouchiku?::apply",
  :guards,
  "kouchiku?::refresh",
  "state read after apply"
)

edge(
  "kouchiku?::destroy",
  :inverse,
  "kouchiku?::apply",
  "remove what apply made"
)

edge("kouchiku?::unlock", :inverse, "kouchiku?::claim", "claim versus release")

edge(
  "kouchiku?::apply",
  :inverse,
  "kouchiku?::destroy",
  "remove what apply made"
)

edge("kouchiku?::import", :inverse, "kouchiku?::destroy", "adopt versus remove")
edge("kouchiku?::destroy", :inverse, "kouchiku?::import", "adopt versus remove")
edge("kouchiku?::claim", :inverse, "kouchiku?::unlock", "claim versus release")
edge("kouchiku?::declare", :pairs, "kouchiku?::check", "declared then checked")
edge("kouchiku?::import", :pairs, "kouchiku?::drift", "adopt what drift found")
edge("kouchiku?::test", :pairs, "kyoukyuu?::verify", "compliance evidence")
edge("kouchiku?::plan", :pairs, "tenkai?::plan", "plan for infra and for apps")
edge("kouchiku?::diff", :refines, "core::diff", "between plans")
edge("kouchiku?::get", :refines, "core::get", "one state entry")
edge("kouchiku?::list", :refines, "core::list", "state entries")
edge("kouchiku?::move", :refines, "core::move", "rename in state")
edge("kouchiku?::declare", :refines, "core::parse", "stack as data")
edge("kouchiku?::plan", :refines, "core::plan", "dry run of apply")
edge("kouchiku?::refresh", :refines, "core::read", "real state into record")
edge("kouchiku?::render", :refines, "core::render", "stack to planner input")
edge("kouchiku?::output", :refines, "kouchiku?::get", "exported value")
edge("kouchiku?::apply", :requires, "kouchiku?::claim", "one writer at a time")
edge("kouchiku?::unlock", :requires, "kouchiku?::claim", "releases a lease")

edge(
  "kouchiku?::render",
  :requires,
  "kouchiku?::declare",
  "renders a declared stack"
)

edge("kouchiku?::apply", :requires, "kouchiku?::plan", "apply a reviewed plan")
edge("kouchiku?::import", :requires, "kumo?::need", "resource must exist")
