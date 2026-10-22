space("rirezu?", {status: :provisional})

verb(
  "rirezu?",
  "changelog",
  {
    kind: :effect,
    shape: "changelog(repo, plan) -> nil",
    laterals: ["idempotent", "serialize"],
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
    laterals: ["idempotent", "log"],
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
    laterals: ["log", "switch"],
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
    laterals: ["error", "idempotent", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "send artifacts to registries and hosts",
    wave: 2,
    origin: "E"
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
    laterals: ["idempotent", "log"],
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
edge("rirezu?::cut", :composes, "rirezu?::plan", "plan then tag")

edge(
  "rirezu?::publish",
  :composes,
  "ryuutsuu?::publish",
  "binaries to a channel"
)

edge("rirezu?::verify", :composes, "ryuutsuu?::verify", "assets match record")
edge("rirezu?::publish", :composes, "tsumini?::push", "images to a registry")

edge(
  "rirezu?::publish",
  :guards,
  "rirezu?::promote",
  "published before promoted"
)

edge("rirezu?::cut", :guards, "rirezu?::publish", "tag exists first")
edge("rirezu?::notes", :inverse, "rirezu?::changelog", "write versus render")
edge("rirezu?::changelog", :inverse, "rirezu?::notes", "write versus render")
edge("rirezu?::yank", :inverse, "rirezu?::publish", "withdraw")
edge("rirezu?::publish", :inverse, "rirezu?::yank", "withdraw")
edge("rirezu?::yank", :pairs, "paketto?::yank", "withdraw in registry and host")
edge("rirezu?::get", :refines, "core::get", "one release")
edge("rirezu?::list", :refines, "core::list", "releases")
edge("rirezu?::notes", :refines, "core::render", "commits to text")
edge("rirezu?::plan", :requires, "gitto::list", "reads commits")
edge("rirezu?::publish", :requires, "rirezu?::cut", "cut first")

edge(
  "rirezu?::promote",
  :requires,
  "rirezu?::verify",
  "verify before moving on"
)
