space("birudo?", {status: :provisional})

verb(
  "birudo?",
  "bench",
  {
    kind: :effect,
    shape: "bench(project, opts) -> [measure]",
    laterals: %w[process time],
    fleet: nil,
    today: "absent",
    meaning: "timed runs of marked workloads",
    wave: 3,
    origin: "E"
  }
)

verb(
  "birudo?",
  "build",
  {
    kind: :effect,
    shape: "build(project, targets, opts) -> [artifact]",
    laterals: %w[cache deadline error process],
    fleet: nil,
    today: "partial:hyouka",
    meaning: "produce artifacts from sources",
    wave: 1,
    origin: "E"
  }
)

verb(
  "birudo?",
  "check",
  {
    kind: :effect,
    shape: "check(project, opts) -> [diagnostic]",
    laterals: %w[process validate],
    fleet: nil,
    today: "rust:blue-lang-cli",
    meaning: "type and rule check without producing outputs",
    wave: 0,
    origin: "E"
  }
)

verb(
  "birudo?",
  "clean",
  {
    kind: :effect,
    shape: "clean(project, opts) -> {freed:}",
    laterals: %w[idempotent resource],
    fleet: "souji",
    today: "partial:souji",
    meaning: "remove build outputs",
    wave: 1,
    origin: "E"
  }
)

verb(
  "birudo?",
  "doc",
  {
    kind: :effect,
    shape: "doc(project, opts) -> [file]",
    laterals: ["serialize"],
    fleet: nil,
    today: "rust:blue-lang-cli",
    meaning: "reference pages generated from definitions",
    wave: 1,
    origin: "E"
  }
)

verb(
  "birudo?",
  "format",
  {
    kind: :effect,
    shape: "format(project, opts) -> [changed path]",
    laterals: ["idempotent"],
    fleet: nil,
    today: "rust:blue-lang-cli",
    meaning: "rewrite sources to the one canonical form",
    wave: 0,
    origin: "E"
  }
)

verb(
  "birudo?",
  "graph",
  {
    kind: :pure,
    shape: "graph(project) -> graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "targets and their inputs as a graph",
    wave: 2,
    origin: "E"
  }
)

verb(
  "birudo?",
  "key",
  {
    kind: :pure,
    shape: "key(step, inputs) -> hash",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "content address of a step from its inputs",
    wave: 1,
    origin: "E",
    contract: "key(step) -> hash"
  }
)

verb(
  "birudo?",
  "lint",
  {
    kind: :effect,
    shape: "lint(project, opts) -> [finding]",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:kijun",
    meaning: "style and correctness findings as data",
    wave: 1,
    origin: "E"
  }
)

verb(
  "birudo?",
  "plan",
  {
    kind: :pure,
    shape: "plan(project, targets, opts) -> [step]",
    laterals: %w[cache validate],
    fleet: nil,
    today: "partial:hyouka",
    meaning: "steps and cache hits a build would take",
    wave: 1,
    origin: "E"
  }
)

verb(
  "birudo?",
  "profile",
  {
    kind: :effect,
    shape: "profile(project) -> [timing]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "where build time went, per step",
    wave: 3,
    origin: "E"
  }
)

verb(
  "birudo?",
  "reproduce",
  {
    kind: :effect,
    shape: "reproduce(artifact, opts) -> Bool",
    laterals: %w[process validate],
    fleet: nil,
    today: "absent",
    meaning: "rebuild and compare hashes bit for bit",
    wave: 3,
    origin: "E"
  }
)

verb(
  "birudo?",
  "restore",
  {
    kind: :effect,
    shape: "restore(key) -> outputs or nil",
    laterals: %w[cache retry],
    fleet: nil,
    today: "absent",
    meaning: "fetch a step's outputs from the cache",
    wave: 2,
    origin: "E"
  }
)

verb(
  "birudo?",
  "run",
  {
    kind: :effect,
    shape: "run(step, opts) -> result",
    laterals: %w[capability process],
    fleet: nil,
    today: "absent",
    meaning: "one step in a sandbox with declared inputs only",
    wave: 2,
    origin: "E"
  }
)

verb(
  "birudo?",
  "save",
  {
    kind: :effect,
    shape: "save(key, outputs) -> nil",
    laterals: %w[cache idempotent],
    fleet: nil,
    today: "absent",
    meaning: "store a step's outputs under its key",
    wave: 2,
    origin: "E"
  }
)

verb(
  "birudo?",
  "stale?",
  {
    kind: :effect,
    shape: "stale?(step) -> Bool",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "whether inputs changed since the last output",
    wave: 1,
    origin: "E"
  }
)

verb(
  "birudo?",
  "target",
  {
    kind: :pure,
    shape: "target(name) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a platform triple with its capabilities",
    wave: 2,
    origin: "E"
  }
)

verb(
  "birudo?",
  "test",
  {
    kind: :effect,
    shape: "test(project, opts) -> report",
    laterals: %w[deadline process test],
    fleet: nil,
    today: "rust:blue-lang-cli",
    meaning: "run the project tests and return a report",
    wave: 0,
    origin: "E"
  }
)

verb(
  "birudo?",
  "toolchain",
  {
    kind: :effect,
    shape: "toolchain(spec) -> toolchain",
    laterals: %w[cache process],
    fleet: nil,
    today: "absent",
    meaning: "the compiler and tools a build is pinned to",
    wave: 2,
    origin: "E"
  }
)

verb(
  "birudo?",
  "watch",
  {
    kind: :stream,
    shape: "watch(project, f, opts) -> nil",
    laterals: %w[cancel process],
    fleet: nil,
    today: "absent",
    meaning: "rebuild when inputs change",
    wave: 2,
    origin: "E"
  }
)

edge("birudo?::profile", :composes, "birudo?::build", "timing of build")
edge("birudo?::reproduce", :composes, "birudo?::build", "second build")
edge("birudo?::plan", :composes, "birudo?::graph", "order from the graph")

edge(
  "birudo?::stale?",
  :composes,
  "birudo?::key",
  "key changed since last build"
)

edge("birudo?::build", :composes, "birudo?::plan", "plan then execute")
edge("birudo?::build", :composes, "birudo?::restore", "reuse cached outputs")
edge("birudo?::build", :composes, "birudo?::run", "each step runs")
edge("birudo?::test", :composes, "birudo?::run", "tests are sandboxed steps")
edge("birudo?::build", :composes, "birudo?::save", "store new outputs")
edge("birudo?::plan", :composes, "birudo?::stale?", "skip fresh steps")
edge("birudo?::watch", :composes, "birudo?::stale?", "rebuild only stale steps")
edge("birudo?::reproduce", :composes, "hyouka::verify", "compare hashes")
edge("birudo?::lint", :composes, "kijun::check", "project rules")

edge(
  "birudo?::reproduce",
  :guards,
  "kyoukyuu?::attest",
  "attest only reproducible builds"
)

edge("birudo?::clean", :inverse, "birudo?::build", "remove outputs")
edge("birudo?::build", :inverse, "birudo?::clean", "remove outputs")
edge("birudo?::lint", :inverse, "birudo?::format", "fix versus find")
edge("birudo?::format", :inverse, "birudo?::lint", "fix versus find")

edge(
  "birudo?::save",
  :inverse,
  "birudo?::restore",
  "read versus write of cache"
)

edge(
  "birudo?::restore",
  :inverse,
  "birudo?::save",
  "read versus write of cache"
)

edge("birudo?::watch", :lifts, "birudo?::build", "rebuild per change")
edge("birudo?::target", :pairs, "birudo?::build", "target selects outputs")
edge("birudo?::format", :pairs, "birudo?::check", "format then check")
edge("birudo?::profile", :pairs, "birudo?::graph", "time per node")
edge("birudo?::key", :pairs, "birudo?::restore", "key finds outputs")
edge("birudo?::check", :refines, "birudo?::build", "build without outputs")
edge("birudo?::lint", :refines, "birudo?::check", "style findings")
edge("birudo?::bench", :refines, "birudo?::test", "timed tests")
edge("birudo?::graph", :refines, "core::info", "target structure")
edge("birudo?::plan", :refines, "core::plan", "steps and cache hits")
edge("birudo?::run", :refines, "core::run", "sandboxed step")

edge(
  "birudo?::toolchain",
  :refines,
  "hyouka::build",
  "tools come from the store"
)

edge("birudo?::test", :requires, "birudo?::build", "tests run built code")
edge("birudo?::doc", :requires, "birudo?::check", "docs from checked code")
edge("birudo?::save", :requires, "birudo?::key", "stored under its key")
edge("birudo?::build", :requires, "birudo?::toolchain", "pinned tools")

edge(
  "birudo?::target",
  :requires,
  "birudo?::toolchain",
  "target needs its tools"
)

edge("birudo?::build", :requires, "paketto?::install", "dependencies first")
edge("birudo?::key", :requires, "shomei::hash", "hash of inputs")
