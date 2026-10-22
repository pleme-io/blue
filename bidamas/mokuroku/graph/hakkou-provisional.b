space("hakkou?", {status: :provisional})

verb(
  "hakkou?",
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
  "hakkou?",
  "build",
  {
    kind: :effect,
    shape: "build(project, opts) -> artifact",
    laterals: ["cache", "process"],
    fleet: nil,
    today: "absent",
    meaning: "make the release artifact reproducibly",
    wave: 1,
    origin: "F"
  }
)

verb(
  "hakkou?",
  "canary",
  {
    kind: :effect,
    shape: "canary(release, share, opts) -> verdict",
    laterals: ["cancel", "test", "time"],
    fleet: nil,
    today: "absent",
    meaning: "send a share of traffic to a release and judge it",
    wave: 3,
    origin: "F"
  }
)

verb(
  "hakkou?",
  "changelog",
  {
    kind: :pure,
    shape: "changelog(changes, opts) -> text",
    laterals: ["serialize"],
    fleet: "releaser",
    today: "absent",
    meaning: "release notes from changes, grouped by kind",
    wave: 1,
    origin: "F"
  }
)

verb(
  "hakkou?",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> [change]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the changes between two releases",
    wave: 2,
    origin: "F"
  }
)

verb(
  "hakkou?",
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
  "hakkou?",
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
  "hakkou?",
  "plan",
  {
    kind: :pure,
    shape: "plan(project, opts) -> [action]",
    laterals: [],
    fleet: "releaser",
    today: "absent",
    meaning: "what a release would do, changing nothing",
    wave: 1,
    origin: "F"
  }
)

verb(
  "hakkou?",
  "promote",
  {
    kind: :effect,
    shape: "promote(release, env, opts) -> nil",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "move a release to the next environment after its gates",
    wave: 2,
    origin: "F"
  }
)

verb(
  "hakkou?",
  "publish",
  {
    kind: :effect,
    shape: "publish(artifact, registry, opts) -> release",
    laterals: ["idempotent", "retry"],
    fleet: "cartorio",
    today: "absent",
    meaning: "upload an artifact and record its provenance",
    wave: 2,
    origin: "F"
  }
)

verb(
  "hakkou?",
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
  "hakkou?",
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
  "hakkou?",
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
  "hakkou?",
  "yank",
  {
    kind: :effect,
    shape: "yank(release, reason) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "withdraw a published version without deleting it",
    wave: 3,
    origin: "F"
  }
)

edge("hakkou?::promote", :composes, "hakkou?::pin", "sets the next environment")

edge(
  "hakkou?::rollback",
  :composes,
  "hakkou?::pin",
  "pins the previous release"
)

edge("hakkou?::canary", :composes, "shihyou::meets?", "judged by objectives")
edge("hakkou?::breaking?", :guards, "hakkou?::next", "a break needs a major")
edge("hakkou?::plan", :guards, "hakkou?::publish", "preview before upload")

edge(
  "hakkou?::publish",
  :guards,
  "hakkou?::released?",
  "publish once per version"
)

edge("hakkou?::rollback", :inverse, "hakkou?::promote", "forward and back")
edge("hakkou?::promote", :inverse, "hakkou?::rollback", "forward and back")
edge("hakkou?::next", :pairs, "hakkou?::breaking?", "major only on a break")
edge("hakkou?::diff", :pairs, "hakkou?::changelog", "same range, two views")
edge("hakkou?::changelog", :pairs, "hakkou?::next", "notes and version agree")
edge("hakkou?::publish", :pairs, "hakkou?::pin", "publish then pin")
edge("hakkou?::pin", :pairs, "hakkou?::promote", "environment pins")
edge("hakkou?::plan", :pairs, "hakkou?::promote", "promotion is planned")

edge(
  "hakkou?::released?",
  :pairs,
  "hakkou?::publish",
  "check before publish keeps it once"
)

edge("hakkou?::canary", :pairs, "hakkou?::rollback", "a bad canary rolls back")
edge("hakkou?::build", :pairs, "hakkou?::sbom", "build then its parts list")
edge("hakkou?::publish", :pairs, "nisshi::append", "release events are logged")
edge("hakkou?::yank", :pairs, "shougai?::mitigate", "yank is a mitigation")

edge(
  "hakkou?::canary",
  :refines,
  "hakkou?::promote",
  "partial, judged promotion"
)

edge(
  "hakkou?::yank",
  :refines,
  "hakkou?::rollback",
  "withdraws a published version"
)

edge("hakkou?::diff", :requires, "gitto::diff", "commits between releases")
edge("hakkou?::changelog", :requires, "gitto::list", "groups commits by kind")
edge("hakkou?::next", :requires, "gitto::list", "reads commits since last tag")

edge(
  "hakkou?::publish",
  :requires,
  "hakkou?::build",
  "publishes what was built"
)

edge("hakkou?::sbom", :requires, "hakkou?::build", "parts of the artifact")
edge("hakkou?::build", :requires, "hakkou?::next", "version is set first")
edge("hakkou?::pin", :requires, "hakkou?::publish", "only published releases")
edge("hakkou?::breaking?", :requires, "mokuroku::diff", "interface changes")
