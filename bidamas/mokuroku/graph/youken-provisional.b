space("youken?", {status: :provisional})

verb(
  "youken?",
  "covered?",
  {
    kind: :pure,
    shape: "covered?(requirement) -> Bool",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "whether every acceptance has passing evidence",
    wave: 3,
    origin: "F"
  }
)

verb(
  "youken?",
  "diff",
  {
    kind: :pure,
    shape: "diff(old, new) -> [change]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "requirements added, removed or reworded between versions",
    wave: 4,
    origin: "F"
  }
)

verb(
  "youken?",
  "gaps",
  {
    kind: :pure,
    shape: "gaps(requirements) -> [requirement]",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "requirements with no evidence or failing evidence",
    wave: 3,
    origin: "F"
  }
)

verb(
  "youken?",
  "impact",
  {
    kind: :pure,
    shape: "impact(changes, requirements) -> [requirement]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "requirements that a set of changes may break",
    wave: 4,
    origin: "F"
  }
)

verb(
  "youken?",
  "list",
  {
    kind: :effect,
    shape: "list(source, filter) -> [requirement]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "requirements by area or state",
    wave: 3,
    origin: "F",
    contract: "list(source, opts) -> [requirement]"
  }
)

verb(
  "youken?",
  "requirement",
  {
    kind: :decl,
    shape: "requirement(id, text, acceptance) -> requirement",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare a need with a testable acceptance",
    wave: 3,
    origin: "F"
  }
)

verb(
  "youken?",
  "satisfies",
  {
    kind: :decl,
    shape: "satisfies(requirement, evidence) -> row",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "bind a requirement to a test or check that shows it",
    wave: 3,
    origin: "F"
  }
)

verb(
  "youken?",
  "trace",
  {
    kind: :pure,
    shape: "trace(requirement) -> [link]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the tests, code and decisions behind a requirement",
    wave: 3,
    origin: "F"
  }
)

edge("youken?::satisfies", :composes, "tesuto?::case", "evidence is a test")
edge("youken?::gaps", :composes, "youken?::covered?", "the not covered")
edge("youken?::trace", :composes, "youken?::satisfies", "follows the bindings")
edge("youken?::covered?", :composes, "youken?::trace", "all evidence passes")
edge("youken?::list", :generalizes, "youken?::requirement", "declared needs")
edge("youken?::list", :pairs, "kadai?::list", "needs become issues")
edge("youken?::gaps", :pairs, "keikaku?::risk", "uncovered needs are risks")

edge(
  "youken?::requirement",
  :pairs,
  "ketsugi?::propose",
  "needs lead to decisions"
)

edge("youken?::diff", :pairs, "mokuroku::diff", "both diff declared surfaces")
edge("youken?::trace", :pairs, "mokuroku::get", "trace to docs")
edge("youken?::covered?", :pairs, "rebyuu?::ready?", "coverage gates landing")

edge(
  "youken?::impact",
  :pairs,
  "tesuto?::affected",
  "impact on needs and tests"
)

edge("youken?::satisfies", :pairs, "tesuto?::cover", "evidence versus coverage")
edge("youken?::diff", :requires, "youken?::list", "two versions")

edge(
  "youken?::requirement",
  :requires,
  "youken?::satisfies",
  "a need needs evidence"
)

edge("youken?::impact", :requires, "youken?::trace", "from code to needs")
