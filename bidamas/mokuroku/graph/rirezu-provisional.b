space("rirezu?", {status: :provisional})

verb(
  "rirezu?",
  "breaking?",
  {
    kind: :pure,
    shape: "breaking?(old, new) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "whether the interface lost or changed an entry",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rirezu?",
  "build",
  {
    kind: :effect,
    shape: "build(project, opts) -> artifact",
    laterals: %w[cache process],
    fleet: nil,
    today: "absent",
    meaning: "make the release artifact reproducibly",
    wave: 1,
    origin: "F"
  }
)

verb(
  "rirezu?",
  "canary",
  {
    kind: :effect,
    shape: "canary(release, share, opts) -> verdict",
    laterals: %w[cancel test time],
    fleet: nil,
    today: "absent",
    meaning: "send a share of traffic to a release and judge it",
    wave: 3,
    origin: "F"
  }
)

verb(
  "rirezu?",
  "changelog",
  {
    kind: :effect,
    shape: "changelog(repo, plan) -> nil",
    laterals: %w[idempotent serialize],
    fleet: nil,
    today: "absent",
    meaning: "insert notes into the changelog file",
    wave: 2,
    origin: "E"
  }
)

verb(
  "rirezu?",
  "cut",
  {
    kind: :effect,
    shape: "cut(repo, plan, opts) -> release",
    laterals: %w[idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "bump, tag and record a release",
    wave: 1,
    origin: "E",
    contract: "cut(repo, plan, to) -> release"
  }
)

verb(
  "rirezu?",
  "diff",
  {
    kind: :effect,
    shape: "diff(repo, a, b) -> [change]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "changes between two releases",
    wave: 1,
    origin: "E",
    contract: "diff(repo, a, opts) -> [change]"
  }
)

verb(
  "rirezu?",
  "get",
  {
    kind: :effect,
    shape: "get(repo, tag) -> release or nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "one release, nil when absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "rirezu?",
  "latest",
  {
    kind: :effect,
    shape: "latest(repo, channel) -> release or nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "newest release on a channel",
    wave: 1,
    origin: "E"
  }
)

verb(
  "rirezu?",
  "list",
  {
    kind: :effect,
    shape: "list(repo, opts) -> [release]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "releases, newest first",
    wave: 1,
    origin: "E"
  }
)

verb(
  "rirezu?",
  "next",
  {
    kind: :pure,
    shape: "next(project, changes) -> version",
    laterals: [],
    fleet: "releaser",
    today: "absent",
    meaning: "the next version from the kinds of change since the last",
    wave: 1,
    origin: "F"
  }
)

verb(
  "rirezu?",
  "notes",
  {
    kind: :pure,
    shape: "notes(changes) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "changelog text from commits",
    wave: 1,
    origin: "E",
    contract: "notes(changes, kind) -> text"
  }
)

verb(
  "rirezu?",
  "pin",
  {
    kind: :effect,
    shape: "pin(env, release) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "set which release an environment runs",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rirezu?",
  "plan",
  {
    kind: :pure,
    shape: "plan(repo, changes, opts) -> release plan",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "next version, notes and targets from changes",
    wave: 1,
    origin: "E"
  }
)

verb(
  "rirezu?",
  "promote",
  {
    kind: :effect,
    shape: "promote(release, to) -> release",
    laterals: %w[log switch],
    fleet: nil,
    today: "absent",
    meaning: "move a release to the next channel",
    wave: 2,
    origin: "E"
  }
)

verb(
  "rirezu?",
  "publish",
  {
    kind: :effect,
    shape: "publish(release, targets, opts) -> [record]",
    laterals: %w[error idempotent retry],
    fleet: nil,
    today: "absent",
    meaning: "send artifacts to registries and hosts",
    wave: 2,
    origin: "E"
  }
)

verb(
  "rirezu?",
  "released?",
  {
    kind: :effect,
    shape: "released?(project, version) -> Bool",
    laterals: [],
    fleet: "releaser",
    today: "absent",
    meaning: "whether a version is already published",
    wave: 1,
    origin: "F"
  }
)

verb(
  "rirezu?",
  "rollback",
  {
    kind: :effect,
    shape: "rollback(env, opts) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "return an environment to its previous release",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rirezu?",
  "sbom",
  {
    kind: :pure,
    shape: "sbom(artifact) -> doc",
    laterals: ["serialize"],
    fleet: "tameshi",
    today: "absent",
    meaning: "the list of parts inside an artifact",
    wave: 3,
    origin: "F"
  }
)

verb(
  "rirezu?",
  "verify",
  {
    kind: :effect,
    shape: "verify(release) -> [mismatch]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "assets match recorded hashes and signatures",
    wave: 2,
    origin: "E"
  }
)

verb(
  "rirezu?",
  "yank",
  {
    kind: :effect,
    shape: "yank(release, reason) -> nil",
    laterals: %w[idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "withdraw a release, keeping the record",
    wave: 3,
    origin: "E"
  }
)

edge("rirezu?::plan", :composes, "bajon?::next", "next version")
edge("rirezu?::diff", :composes, "gitto::diff", "changes between tags")
edge("rirezu?::get", :composes, "gitto::get", "one tag")
edge("rirezu?::list", :composes, "gitto::list", "releases are tags")
edge("rirezu?::cut", :composes, "gitto::tag", "tag marks the release")
edge("rirezu?::latest", :composes, "rirezu?::list", "newest of the list")
edge("rirezu?::changelog", :composes, "rirezu?::notes", "write notes to file")
edge("rirezu?::plan", :composes, "rirezu?::notes", "notes in the plan")
edge("rirezu?::promote", :composes, "rirezu?::pin", "sets the next environment")

edge(
  "rirezu?::rollback",
  :composes,
  "rirezu?::pin",
  "pins the previous release"
)

edge("rirezu?::cut", :composes, "rirezu?::plan", "plan then tag")

edge(
  "rirezu?::publish",
  :composes,
  "ryuutsuu?::publish",
  "binaries to a channel"
)

edge("rirezu?::verify", :composes, "ryuutsuu?::verify", "assets match record")
edge("rirezu?::canary", :composes, "shihyou::meets?", "judged by objectives")
edge("rirezu?::publish", :composes, "tsumini?::push", "images to a registry")
edge("rirezu?::breaking?", :guards, "rirezu?::next", "a break needs a major")

edge(
  "rirezu?::publish",
  :guards,
  "rirezu?::promote",
  "published before promoted"
)

edge("rirezu?::cut", :guards, "rirezu?::publish", "tag exists first")
edge("rirezu?::plan", :guards, "rirezu?::publish", "preview before upload")

edge(
  "rirezu?::publish",
  :guards,
  "rirezu?::released?",
  "publish once per version"
)

edge("rirezu?::notes", :inverse, "rirezu?::changelog", "write versus render")
edge("rirezu?::changelog", :inverse, "rirezu?::notes", "write versus render")
edge("rirezu?::rollback", :inverse, "rirezu?::promote", "forward and back")
edge("rirezu?::yank", :inverse, "rirezu?::publish", "withdraw")
edge("rirezu?::promote", :inverse, "rirezu?::rollback", "forward and back")
edge("rirezu?::publish", :inverse, "rirezu?::yank", "withdraw")
edge("rirezu?::publish", :pairs, "nisshi::append", "release events are logged")
edge("rirezu?::yank", :pairs, "paketto?::yank", "withdraw in registry and host")
edge("rirezu?::next", :pairs, "rirezu?::breaking?", "major only on a break")
edge("rirezu?::diff", :pairs, "rirezu?::changelog", "same range, two views")
edge("rirezu?::changelog", :pairs, "rirezu?::next", "notes and version agree")
edge("rirezu?::publish", :pairs, "rirezu?::pin", "publish then pin")
edge("rirezu?::pin", :pairs, "rirezu?::promote", "environment pins")
edge("rirezu?::plan", :pairs, "rirezu?::promote", "promotion is planned")

edge(
  "rirezu?::released?",
  :pairs,
  "rirezu?::publish",
  "check before publish keeps it once"
)

edge("rirezu?::canary", :pairs, "rirezu?::rollback", "a bad canary rolls back")
edge("rirezu?::build", :pairs, "rirezu?::sbom", "build then its parts list")
edge("rirezu?::yank", :pairs, "shougai?::mitigate", "yank is a mitigation")
edge("rirezu?::get", :refines, "core::get", "one release")
edge("rirezu?::list", :refines, "core::list", "releases")
edge("rirezu?::notes", :refines, "core::render", "commits to text")

edge(
  "rirezu?::canary",
  :refines,
  "rirezu?::promote",
  "partial, judged promotion"
)

edge(
  "rirezu?::yank",
  :refines,
  "rirezu?::rollback",
  "withdraws a published version"
)

edge("rirezu?::diff", :requires, "gitto::diff", "commits between releases")
edge("rirezu?::changelog", :requires, "gitto::list", "groups commits by kind")
edge("rirezu?::next", :requires, "gitto::list", "reads commits since last tag")
edge("rirezu?::plan", :requires, "gitto::list", "reads commits")
edge("rirezu?::breaking?", :requires, "mokuroku::diff", "interface changes")

edge(
  "rirezu?::publish",
  :requires,
  "rirezu?::build",
  "publishes what was built"
)

edge("rirezu?::sbom", :requires, "rirezu?::build", "parts of the artifact")
edge("rirezu?::publish", :requires, "rirezu?::cut", "cut first")
edge("rirezu?::build", :requires, "rirezu?::next", "version is set first")
edge("rirezu?::pin", :requires, "rirezu?::publish", "only published releases")

edge(
  "rirezu?::promote",
  :requires,
  "rirezu?::verify",
  "verify before moving on"
)
