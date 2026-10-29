space("yobidashi?", {status: :provisional})

verb(
  "yobidashi?",
  "delete",
  {
    kind: :effect,
    shape: "delete(name) -> nil",
    laterals: ["idempotent"],
    fleet: "wasm-operator",
    today: "absent",
    meaning: "remove a function",
    wave: 4,
    origin: "E"
  }
)

verb(
  "yobidashi?",
  "deploy",
  {
    kind: :effect,
    shape: "deploy(module, opts) -> function",
    laterals: %w[capability idempotent log],
    fleet: "wasm-operator",
    today: "absent",
    meaning: "place a module where it runs",
    wave: 3,
    origin: "E"
  }
)

verb(
  "yobidashi?",
  "get",
  {
    kind: :effect,
    shape: "get(name) -> function or nil",
    laterals: ["error"],
    fleet: "wasm-operator",
    today: "absent",
    meaning: "one function, nil when absent",
    wave: 3,
    origin: "E"
  }
)

verb(
  "yobidashi?",
  "invoke",
  {
    kind: :effect,
    shape: "invoke(function, input, opts) -> output",
    laterals: %w[deadline error resource],
    fleet: "wasm-engine",
    today: "absent",
    meaning: "run a function once",
    wave: 3,
    origin: "E"
  }
)

verb(
  "yobidashi?",
  "limit",
  {
    kind: :decl,
    shape: "limit(function, record) -> function",
    laterals: %w[capability resource],
    fleet: "wasm-engine",
    today: "absent",
    meaning: "fuel, memory and time a run may use",
    wave: 3,
    origin: "E"
  }
)

verb(
  "yobidashi?",
  "list",
  {
    kind: :effect,
    shape: "list(opts) -> [function]",
    laterals: ["error"],
    fleet: "wasm-operator",
    today: "absent",
    meaning: "functions and their versions",
    wave: 3,
    origin: "E"
  }
)

verb(
  "yobidashi?",
  "pack",
  {
    kind: :effect,
    shape: "pack(source, target, opts) -> module",
    laterals: %w[cache process],
    fleet: "wasm-engine",
    today: "absent",
    meaning: "compile a function to a portable module",
    wave: 3,
    origin: "E"
  }
)

verb(
  "yobidashi?",
  "read",
  {
    kind: :effect,
    shape: "read(function, opts) -> text",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "logs from a function's runs",
    wave: 3,
    origin: "E"
  }
)

verb(
  "yobidashi?",
  "resize",
  {
    kind: :effect,
    shape: "resize(function, bounds) -> function",
    laterals: %w[resource switch],
    fleet: "wasm-operator",
    today: "absent",
    meaning: "set minimum and maximum instances",
    wave: 4,
    origin: "E"
  }
)

verb(
  "yobidashi?",
  "route",
  {
    kind: :decl,
    shape: "route(function, pattern) -> route",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "the requests that reach a function",
    wave: 4,
    origin: "E"
  }
)

verb(
  "yobidashi?",
  "versions",
  {
    kind: :effect,
    shape: "versions(function) -> [version]",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "published versions of a function",
    wave: 4,
    origin: "E"
  }
)

edge("yobidashi?::resize", :composes, "yobidashi?::get", "bounds on a function")

edge(
  "yobidashi?::versions",
  :composes,
  "yobidashi?::get",
  "versions of one function"
)

edge("yobidashi?::limit", :guards, "yobidashi?::invoke", "bounds every run")
edge("yobidashi?::deploy", :inverse, "yobidashi?::delete", "remove a function")
edge("yobidashi?::delete", :inverse, "yobidashi?::deploy", "remove a function")

edge(
  "yobidashi?::route",
  :pairs,
  "yobidashi?::deploy",
  "reachable after deploy"
)

edge("yobidashi?::pack", :pairs, "yobidashi?::limit", "module and its bounds")
edge("yobidashi?::pack", :refines, "birudo?::build", "module is a build output")
edge("yobidashi?::get", :refines, "core::get", "nil when absent")
edge("yobidashi?::list", :refines, "core::list", "functions")
edge("yobidashi?::versions", :refines, "core::list", "published versions")
edge("yobidashi?::read", :refines, "core::read", "function logs")
edge("yobidashi?::invoke", :refines, "core::run", "one call")
edge("yobidashi?::deploy", :refines, "tenkai?::start", "placing a version")
edge("yobidashi?::resize", :refines, "youryou?::resize", "instance bounds")
edge("yobidashi?::invoke", :requires, "yobidashi?::deploy", "must be placed")
edge("yobidashi?::deploy", :requires, "yobidashi?::pack", "needs a module")
