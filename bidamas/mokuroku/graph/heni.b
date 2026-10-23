space("heni", {status: :ratified})

verb(
  "heni",
  "apply",
  {
    kind: :pure,
    shape: "apply(text, mutation) -> text",
    laterals: ["test"],
    fleet: nil,
    today: "exists:heni",
    meaning: "text with one mutation applied, or an error",
    wave: 0,
    origin: "F"
  }
)

verb(
  "heni",
  "mutations",
  {
    kind: :pure,
    shape: "mutations(parsed) -> [mutation]",
    laterals: ["test"],
    fleet: nil,
    today: "exists:heni",
    meaning: "every one-literal change a package admits",
    wave: 0,
    origin: "F"
  }
)

verb(
  "heni",
  "ok?",
  {
    kind: :pure,
    shape: "ok?(report) -> Bool",
    laterals: ["test"],
    fleet: nil,
    today: "exists:heni",
    meaning: "whether every mutation was caught",
    wave: 0,
    origin: "F"
  }
)

verb(
  "heni",
  "run",
  {
    kind: :effect,
    shape: "run(package, opts) -> report",
    laterals: ["process", "test"],
    fleet: nil,
    today: "exists:heni",
    meaning: "mutate a fresh copy per change and run its tests",
    wave: 0,
    origin: "F"
  }
)

verb(
  "heni",
  "score",
  {
    kind: :pure,
    shape: "score(report) -> ratio",
    laterals: ["test"],
    fleet: nil,
    today: "partial:heni",
    meaning: "the share of mutations the tests caught",
    wave: 1,
    origin: "F"
  }
)

verb(
  "heni",
  "survivors",
  {
    kind: :pure,
    shape: "survivors(report) -> [mutation]",
    laterals: ["test"],
    fleet: nil,
    today: "partial:heni",
    meaning: "the mutations no test caught",
    wave: 0,
    origin: "F"
  }
)

edge("heni::run", :composes, "heni::apply", "one fresh copy per mutation")
edge("heni::score", :composes, "heni::survivors", "caught share")
edge("heni::run", :composes, "tesuto?::run", "runs the package tests")

edge(
  "heni::ok?",
  :guards,
  "rirezu?::build",
  "surviving mutants block a release"
)

edge("heni::apply", :pairs, "kakikae?::apply", "both write a changed tree")
edge("heni::score", :pairs, "tesuto?::cover", "two measures of test strength")
edge("heni::survivors", :pairs, "tesuto?::uncovered", "both name missing tests")
edge("heni::ok?", :refines, "heni::score", "score is 1")
edge("heni::apply", :requires, "heni::mutations", "applies one of them")
edge("heni::run", :requires, "heni::mutations", "one run per mutation")
edge("heni::survivors", :requires, "heni::run", "reads a report")

edge(
  "heni::mutations",
  :requires,
  "koubun?::parse",
  "mutations come from the tree"
)
