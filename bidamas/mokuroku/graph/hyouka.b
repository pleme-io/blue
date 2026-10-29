space("hyouka", {status: :ratified})

verb(
  "hyouka",
  "build",
  {
    kind: :effect,
    shape: "build(installable, opts) -> [out path]",
    laterals: %w[cache deadline error process],
    fleet: nil,
    today: "partial:hyouka",
    meaning: "realise a derivation and return its output paths",
    wave: 0,
    origin: "E"
  }
)

verb(
  "hyouka",
  "build_log",
  {
    kind: :effect,
    shape: "build_log(installable) -> text",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "the build log of a derivation",
    wave: 1,
    origin: "E"
  }
)

verb(
  "hyouka",
  "check",
  {
    kind: :effect,
    shape: "check(flake, opts) -> [finding]",
    laterals: %w[error test],
    fleet: nil,
    today: "absent",
    meaning: "run the flake checks and return failures as data",
    wave: 1,
    origin: "E"
  }
)

verb(
  "hyouka",
  "clean",
  {
    kind: :effect,
    shape: "clean(opts) -> {freed:}",
    laterals: %w[error idempotent resource],
    fleet: "souji",
    today: "partial:souji",
    meaning: "delete store paths nothing refers to, dry run first",
    wave: 1,
    origin: "E"
  }
)

verb(
  "hyouka",
  "copy",
  {
    kind: :effect,
    shape: "copy(paths, {to:}) -> nil",
    laterals: %w[deadline error idempotent retry],
    fleet: nil,
    today: "absent",
    meaning: "move closures between stores or hosts",
    wave: 1,
    origin: "E",
    contract: "copy(paths, to, opts) -> nil"
  }
)

verb(
  "hyouka",
  "depends",
  {
    kind: :effect,
    shape: "depends(path, on) -> [path]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "the reference chain from one path to another",
    wave: 2,
    origin: "E"
  }
)

verb(
  "hyouka",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> [change]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "closure difference between two store paths",
    wave: 2,
    origin: "E"
  }
)

verb(
  "hyouka",
  "eval",
  {
    kind: :effect,
    shape: "eval(installable, opts) -> value",
    laterals: %w[cache deadline error],
    fleet: nil,
    today: "partial:hyouka",
    meaning: "evaluate a nix expression to a value",
    wave: 0,
    origin: "E",
    contract: "eval(installable, context, opts) -> value"
  }
)

verb(
  "hyouka",
  "fetch",
  {
    kind: :effect,
    shape: "fetch(url, opts) -> {path:, hash:}",
    laterals: %w[cache error retry],
    fleet: nil,
    today: "absent",
    meaning: "prefetch a source and return its content hash",
    wave: 2,
    origin: "E"
  }
)

verb(
  "hyouka",
  "get",
  {
    kind: :effect,
    shape: "get(flake_lock, input) -> pin or nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "pinned revision of one flake input, nil if absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "hyouka",
  "info",
  {
    kind: :effect,
    shape: "info(path, opts) -> path info",
    laterals: ["error"],
    fleet: nil,
    today: "partial:hyouka",
    meaning: "store path record: size, references, signatures",
    wave: 0,
    origin: "E"
  }
)

verb(
  "hyouka",
  "lock",
  {
    kind: :effect,
    shape: "lock(flake, {inputs:}) -> [changed input]",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "update flake.lock inputs, writing only through nix",
    wave: 1,
    origin: "E",
    contract: "lock(flake, opts) -> [changed input]"
  }
)

verb(
  "hyouka",
  "plan",
  {
    kind: :pure,
    shape: "plan(installable) -> {build:, fetch:}",
    laterals: %w[cache error],
    fleet: nil,
    today: "partial:hyouka",
    meaning: "what a build would build and fetch, changing nothing",
    wave: 0,
    origin: "E"
  }
)

verb(
  "hyouka",
  "run",
  {
    kind: :effect,
    shape: "run(installable, args, opts) -> result",
    laterals: %w[error process],
    fleet: nil,
    today: "absent",
    meaning: "build then run an app output to completion",
    wave: 1,
    origin: "E"
  }
)

verb(
  "hyouka",
  "search",
  {
    kind: :effect,
    shape: "search(flake, query) -> [record]",
    laterals: %w[cache error],
    fleet: nil,
    today: "absent",
    meaning: "find packages by name or description",
    wave: 2,
    origin: "E"
  }
)

verb(
  "hyouka",
  "show",
  {
    kind: :effect,
    shape: "show(flake) -> record",
    laterals: %w[cache error],
    fleet: nil,
    today: "absent",
    meaning: "the outputs a flake offers, by system",
    wave: 1,
    origin: "E"
  }
)

verb(
  "hyouka",
  "verify",
  {
    kind: :effect,
    shape: "verify(path, opts) -> [mismatch]",
    laterals: %w[error validate],
    fleet: nil,
    today: "absent",
    meaning: "check store contents and signatures against their hashes",
    wave: 2,
    origin: "E"
  }
)

edge("hyouka::check", :composes, "birudo?::test", "a flake check runs tests")
edge("hyouka::check", :composes, "hyouka::build", "checks are builds")
edge("hyouka::run", :composes, "hyouka::build", "build then execute")
edge("hyouka::build", :composes, "hyouka::eval", "instantiate then realise")
edge("hyouka::show", :composes, "hyouka::eval", "outputs are an evaluation")
edge("hyouka::build", :composes, "hyouka::plan", "plan before realise")

edge(
  "hyouka::verify",
  :guards,
  "hyouka::copy",
  "check contents before trusting"
)

edge("hyouka::clean", :inverse, "hyouka::build", "frees what builds made")
edge("hyouka::build", :inverse, "hyouka::clean", "frees what builds made")
edge("hyouka::lock", :inverse, "hyouka::get", "write versus read of a pin")
edge("hyouka::get", :inverse, "hyouka::lock", "write versus read of a pin")
edge("hyouka::copy", :pairs, "hosuto?::converge", "closure then switch")
edge("hyouka::build_log", :pairs, "hyouka::build", "a build leaves a log")
edge("hyouka::eval", :pairs, "hyouka::build", "value then realise")
edge("hyouka::info", :pairs, "hyouka::depends", "record then references")
edge("hyouka::fetch", :pairs, "hyouka::lock", "fetch yields the pinned hash")
edge("hyouka::search", :pairs, "hyouka::show", "find then inspect")
edge("hyouka::copy", :refines, "core::copy", "closure to a host or store")
edge("hyouka::get", :refines, "core::get", "nil when input is absent")
edge("hyouka::info", :refines, "core::info", "store path state")
edge("hyouka::plan", :refines, "core::plan", "dry run of build")
edge("hyouka::eval", :refines, "core::read", "value of an expression")
edge("hyouka::verify", :refines, "kyoukyuu?::verify", "store contents check")
edge("hyouka::lock", :requires, "gitto::fetch", "inputs come from remotes")
edge("hyouka::copy", :requires, "hyouka::info", "references decide the closure")
edge("hyouka::depends", :requires, "hyouka::info", "walks references")
edge("hyouka::diff", :requires, "hyouka::info", "compare reference sets")
