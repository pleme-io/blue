space("okite", {status: :ratified})

verb(
  "okite",
  "counterexample",
  {
    kind: :effect,
    shape: "counterexample(law, opts) -> value or nil",
    laterals: ["test"],
    fleet: "caixa-proptest",
    today: "partial:okite",
    meaning: "a shrunk value that breaks a law, or nil",
    wave: 1,
    origin: "F"
  }
)

verb(
  "okite",
  "generate",
  {
    kind: :pure,
    shape: "generate(shape, seed, n) -> [value]",
    laterals: ["test"],
    fleet: "caixa-proptest",
    today: "exists:okite",
    meaning: "n values of a shape from a seed, same every time",
    wave: 0,
    origin: "F",
    contract: "generate(shape, seed, opts) -> [value]"
  }
)

verb(
  "okite",
  "holds?",
  {
    kind: :effect,
    shape: "holds?(law, opts) -> Bool",
    laterals: ["test"],
    fleet: "caixa-proptest",
    today: "exists:okite",
    meaning: "whether a law holds over generated cases",
    wave: 0,
    origin: "F"
  }
)

verb(
  "okite",
  "law",
  {
    kind: :decl,
    shape: "law(name, shape, f) -> law",
    laterals: ["test"],
    fleet: nil,
    today: "exists:okite",
    meaning: "declare a property that must hold for all generated values",
    wave: 0,
    origin: "F"
  }
)

edge("okite::holds?", :composes, "okite::generate", "draws cases then checks")

edge(
  "okite::generate",
  :pairs,
  "genin?::shrink",
  "generated values are shrunk on failure"
)

edge("okite::law", :pairs, "heni::survivors", "a survivor asks for a new law")

edge(
  "okite::counterexample",
  :refines,
  "okite::holds?",
  "returns the failing value"
)

edge("okite::law", :requires, "okite::generate", "laws draw values")
edge("okite::holds?", :requires, "okite::law", "checks a law")
