space("paketto?", {status: :provisional})

verb(
  "paketto?",
  "closure",
  {
    kind: :pure,
    shape: "closure(lock) -> graph",
    laterals: [],
    fleet: "gen",
    today: "rust:blue-lang-bidama",
    meaning: "the dependency graph",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paketto?",
  "dedupe",
  {
    kind: :pure,
    shape: "dedupe(lock) -> lock",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "merge versions that one pin can serve",
    wave: 3,
    origin: "E"
  }
)

verb(
  "paketto?",
  "depend",
  {
    kind: :effect,
    shape: "depend(project, dep, opts) -> [changed pin]",
    laterals: ["idempotent"],
    fleet: "gen",
    today: "absent",
    meaning: "declare a dependency and re-lock",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paketto?",
  "explain",
  {
    kind: :pure,
    shape: "explain(conflict) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the minimal clash behind an unsolvable set",
    wave: 2,
    origin: "E"
  }
)

verb(
  "paketto?",
  "fetch",
  {
    kind: :effect,
    shape: "fetch(pin, opts) -> bytes",
    laterals: %w[cache deadline retry validate],
    fleet: "gen",
    today: "absent",
    meaning: "download one package and verify its hash",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paketto?",
  "info",
  {
    kind: :effect,
    shape: "info(name, registry) -> record",
    laterals: %w[cache error],
    fleet: nil,
    today: "absent",
    meaning: "versions, yanks and metadata of a package",
    wave: 1,
    origin: "E",
    contract: "info(name, opts) -> record"
  }
)

verb(
  "paketto?",
  "install",
  {
    kind: :effect,
    shape: "install(lock, opts) -> nil",
    laterals: %w[cache idempotent process],
    fleet: "gen",
    today: "absent",
    meaning: "place every locked package where the build reads it",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paketto?",
  "lock",
  {
    kind: :effect,
    shape: "lock(project, opts) -> [changed pin]",
    laterals: %w[idempotent serialize],
    fleet: "gen",
    today: "rust:blue-lang-bidama",
    meaning: "write the lockfile from the manifest",
    wave: 0,
    origin: "E"
  }
)

verb(
  "paketto?",
  "outdated",
  {
    kind: :effect,
    shape: "outdated(project) -> [record]",
    laterals: ["error"],
    fleet: "gen",
    today: "absent",
    meaning: "pins behind the newest allowed version",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paketto?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> manifest",
    laterals: %w[serialize validate],
    fleet: "gen",
    today: "absent",
    meaning: "a package manifest into a record",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paketto?",
  "publish",
  {
    kind: :effect,
    shape: "publish(package, registry, opts) -> record",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "upload a package version, immutable once up",
    wave: 2,
    origin: "E"
  }
)

verb(
  "paketto?",
  "read",
  {
    kind: :effect,
    shape: "read(project) -> lock",
    laterals: ["error"],
    fleet: "gen",
    today: "rust:blue-lang-bidama",
    meaning: "the lockfile of a project",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paketto?",
  "remove",
  {
    kind: :effect,
    shape: "remove(project, name) -> [changed pin]",
    laterals: ["idempotent"],
    fleet: "gen",
    today: "absent",
    meaning: "drop a dependency and re-lock",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paketto?",
  "resolve",
  {
    kind: :pure,
    shape: "resolve(manifest, index, opts) -> lock or conflict",
    laterals: %w[error validate],
    fleet: "gen",
    today: "rust:blue-lang-bidama",
    meaning: "pick one version per package that satisfies all ranges",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paketto?",
  "search",
  {
    kind: :effect,
    shape: "search(registry, query) -> [record]",
    laterals: %w[error ratelimit],
    fleet: nil,
    today: "absent",
    meaning: "packages matching a query",
    wave: 2,
    origin: "E"
  }
)

verb(
  "paketto?",
  "upgrade",
  {
    kind: :effect,
    shape: "upgrade(project, names, opts) -> [change]",
    laterals: ["idempotent"],
    fleet: "gen",
    today: "absent",
    meaning: "move pins to newer allowed versions",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paketto?",
  "vendor",
  {
    kind: :effect,
    shape: "vendor(lock, dir) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "copy sources into the tree for offline builds",
    wave: 2,
    origin: "E"
  }
)

verb(
  "paketto?",
  "verify",
  {
    kind: :effect,
    shape: "verify(lock) -> [mismatch]",
    laterals: ["validate"],
    fleet: "gen",
    today: "rust:gen",
    meaning: "lockfile against manifest and stored hashes",
    wave: 0,
    origin: "E"
  }
)

verb(
  "paketto?",
  "why",
  {
    kind: :pure,
    shape: "why(lock, name) -> [path]",
    laterals: [],
    fleet: "gen",
    today: "absent",
    meaning: "every chain that pulls a package in",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paketto?",
  "yank",
  {
    kind: :effect,
    shape: "yank(name, version, registry) -> nil",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "mark a version unfit without deleting it",
    wave: 3,
    origin: "E"
  }
)

edge("paketto?::outdated", :composes, "bajon?::compare", "latest versus pinned")
edge("paketto?::resolve", :composes, "bajon?::pick", "highest allowed version")

edge(
  "paketto?::resolve",
  :composes,
  "bajon?::satisfies?",
  "each pick fits its ranges"
)

edge("paketto?::install", :composes, "hyouka::build", "store provides packages")
edge("paketto?::fetch", :composes, "hyouka::fetch", "same verified download")
edge("paketto?::install", :composes, "paketto?::fetch", "every pin fetched")
edge("paketto?::vendor", :composes, "paketto?::fetch", "copy fetched sources")
edge("paketto?::outdated", :composes, "paketto?::info", "needs newest versions")
edge("paketto?::depend", :composes, "paketto?::lock", "add then relock")
edge("paketto?::remove", :composes, "paketto?::lock", "remove then relock")
edge("paketto?::upgrade", :composes, "paketto?::lock", "relock with new bounds")

edge(
  "paketto?::upgrade",
  :composes,
  "paketto?::outdated",
  "move what is behind"
)

edge("paketto?::lock", :composes, "paketto?::parse", "read the manifest first")
edge("paketto?::closure", :composes, "paketto?::read", "graph of the lock")

edge(
  "paketto?::lock",
  :composes,
  "paketto?::resolve",
  "lock is a stored resolution"
)

edge("paketto?::verify", :guards, "paketto?::install", "lock matches manifest")
edge("paketto?::publish", :guards, "rirezu?::publish", "registry upload step")
edge("paketto?::remove", :inverse, "paketto?::depend", "drop what add declared")
edge("paketto?::parse", :inverse, "paketto?::lock", "manifest in, lock out")
edge("paketto?::upgrade", :inverse, "paketto?::lock", "move pins versus freeze")
edge("paketto?::verify", :inverse, "paketto?::lock", "write versus check")
edge("paketto?::lock", :inverse, "paketto?::parse", "manifest in, lock out")
edge("paketto?::yank", :inverse, "paketto?::publish", "withdraw a version")
edge("paketto?::depend", :inverse, "paketto?::remove", "drop what add declared")
edge("paketto?::lock", :inverse, "paketto?::upgrade", "move pins versus freeze")
edge("paketto?::lock", :inverse, "paketto?::verify", "write versus check")
edge("paketto?::publish", :inverse, "paketto?::yank", "withdraw a version")
edge("paketto?::search", :pairs, "paketto?::info", "find then inspect")
edge("paketto?::vendor", :pairs, "paketto?::verify", "vendored copy is checked")
edge("paketto?::closure", :pairs, "paketto?::why", "graph and paths")
edge("paketto?::info", :refines, "core::get", "registry record")
edge("paketto?::search", :refines, "core::list", "registry search")
edge("paketto?::read", :refines, "core::read", "lockfile content")

edge(
  "paketto?::dedupe",
  :refines,
  "paketto?::resolve",
  "smaller satisfying set"
)

edge(
  "paketto?::explain",
  :refines,
  "paketto?::resolve",
  "says why resolve failed"
)

edge(
  "paketto?::parse",
  :requires,
  "bajon?::constraint",
  "constraints in manifests"
)

edge(
  "paketto?::publish",
  :requires,
  "bajon?::valid?",
  "version must be well formed"
)

edge("paketto?::why", :requires, "paketto?::closure", "paths through the graph")
edge("paketto?::resolve", :requires, "paketto?::info", "needs the index")
edge("paketto?::fetch", :requires, "paketto?::read", "pins say what to fetch")
edge("paketto?::install", :requires, "paketto?::verify", "check before placing")
