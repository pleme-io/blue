space("bajon?", {status: :provisional})

verb(
  "bajon?",
  "bump",
  {
    kind: :pure,
    shape: "bump(version, part) -> version",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "next major, minor, patch or prerelease",
    wave: 1,
    origin: "E"
  }
)

verb(
  "bajon?",
  "change",
  {
    kind: :pure,
    shape: "change(a, b) -> :major, :minor, :patch or :none",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "how big a step between two versions is",
    wave: 2,
    origin: "E"
  }
)

verb(
  "bajon?",
  "compare",
  {
    kind: :pure,
    shape: "compare(a, b) -> -1, 0 or 1",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "order two versions by their scheme",
    wave: 1,
    origin: "E"
  }
)

verb(
  "bajon?",
  "constraint",
  {
    kind: :pure,
    shape: "constraint(text) -> constraint",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "a version constraint as a value",
    wave: 1,
    origin: "E"
  }
)

verb(
  "bajon?",
  "intersect",
  {
    kind: :pure,
    shape: "intersect(a, b) -> constraint or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "what two constraints both allow",
    wave: 2,
    origin: "E"
  }
)

verb(
  "bajon?",
  "next",
  {
    kind: :pure,
    shape: "next(version, changes) -> version",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the bump that conventional commits require",
    wave: 2,
    origin: "E"
  }
)

verb(
  "bajon?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, scheme) -> version",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "text into a version, semver or calver",
    wave: 1,
    origin: "E"
  }
)

verb(
  "bajon?",
  "pick",
  {
    kind: :pure,
    shape: "pick(versions, constraint) -> version or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the highest version a constraint allows",
    wave: 1,
    origin: "E"
  }
)

verb(
  "bajon?",
  "render",
  {
    kind: :pure,
    shape: "render(version) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "a version as canonical text",
    wave: 1,
    origin: "E"
  }
)

verb(
  "bajon?",
  "satisfies?",
  {
    kind: :pure,
    shape: "satisfies?(version, constraint) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a version fits a constraint",
    wave: 1,
    origin: "E"
  }
)

verb(
  "bajon?",
  "valid?",
  {
    kind: :pure,
    shape: "valid?(text, scheme) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "whether text is a well-formed version",
    wave: 1,
    origin: "E"
  }
)

edge("bajon?::next", :composes, "bajon?::bump", "picked part then bump")
edge("bajon?::change", :composes, "bajon?::compare", "size of a step")
edge("bajon?::pick", :composes, "bajon?::compare", "highest wins")

edge(
  "bajon?::satisfies?",
  :composes,
  "bajon?::compare",
  "bounds are comparisons"
)

edge(
  "bajon?::intersect",
  :composes,
  "bajon?::constraint",
  "constraints combine"
)

edge("bajon?::pick", :composes, "bajon?::satisfies?", "filter then max")
edge("bajon?::valid?", :guards, "bajon?::parse", "predicate for parse")
edge("bajon?::change", :inverse, "bajon?::bump", "step in, step out")
edge("bajon?::bump", :inverse, "bajon?::change", "step in, step out")
edge("bajon?::render", :inverse, "bajon?::parse", "text and version")
edge("bajon?::parse", :inverse, "bajon?::render", "text and version")
edge("bajon?::change", :pairs, "bajon?::bump", "step names a bump")

edge(
  "bajon?::intersect",
  :pairs,
  "paketto?::resolve",
  "resolver intersects ranges"
)

edge("bajon?::constraint", :refines, "core::parse", "constraint text to value")
edge("bajon?::render", :refines, "core::render", "canonical text")

edge(
  "bajon?::satisfies?",
  :requires,
  "bajon?::constraint",
  "tests a constraint"
)

edge("bajon?::bump", :requires, "bajon?::parse", "acts on a version")
edge("bajon?::compare", :requires, "bajon?::parse", "compares parsed versions")
edge("bajon?::next", :requires, "gitto::list", "reads commits")
