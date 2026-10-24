space("ronri", {status: :ratified})

verb(
  "ronri",
  "any",
  {
    kind: :pure,
    shape: "any(list, f) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:ronri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "ronri",
  "both",
  {
    kind: :pure,
    shape: "both(f, g) -> function",
    laterals: [],
    fleet: nil,
    today: "exists:ronri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "ronri",
  "either",
  {
    kind: :pure,
    shape: "either(f, g) -> function",
    laterals: [],
    fleet: nil,
    today: "exists:ronri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "ronri",
  "every",
  {
    kind: :pure,
    shape: "every(list, f) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:ronri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "ronri",
  "implies",
  {
    kind: :pure,
    shape: "implies(a, b) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:ronri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "ronri",
  "majority",
  {
    kind: :pure,
    shape: "majority(list, f) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:ronri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "ronri",
  "none",
  {
    kind: :pure,
    shape: "none(list, f) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:ronri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "ronri",
  "not",
  {
    kind: :pure,
    shape: "not(f) -> function",
    laterals: [],
    fleet: nil,
    today: "partial:ronri",
    meaning: "predicate that holds when f does not",
    wave: 0,
    origin: "A"
  }
)

verb(
  "ronri",
  "satisfiable?",
  {
    kind: :pure,
    shape: "satisfiable?(formula) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether some assignment makes a formula true",
    wave: 4,
    origin: "A"
  }
)

verb(
  "ronri",
  "table",
  {
    kind: :pure,
    shape: "table(f, arity) -> [row]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "truth table of a predicate",
    wave: 3,
    origin: "A"
  }
)

verb(
  "ronri",
  "xor",
  {
    kind: :pure,
    shape: "xor(a, b) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:ronri",
    wave: 0,
    origin: "A"
  }
)

edge("ronri::majority", :composes, "retsu::count", "count against half")
edge("ronri::none", :composes, "ronri::any", "not any")
edge("ronri::xor", :composes, "ronri::both", "or but not both")
edge("ronri::implies", :composes, "ronri::either", "not a, or b")
edge("ronri::xor", :composes, "ronri::either", "or but not both")
edge("ronri::table", :composes, "ronri::implies", "evaluate every assignment")
edge("ronri::implies", :composes, "ronri::not", "not a, or b")
edge("ronri::none", :composes, "ronri::not", "negate the test")
edge("ronri::satisfiable?", :composes, "ronri::table", "some row is true")
edge("ronri::majority", :generalizes, "ronri::any", "a threshold, not one")
edge("ronri::majority", :generalizes, "ronri::every", "a threshold, not all")
edge("ronri::any", :pairs, "retsu::find", "existence versus the item")
edge("ronri::every", :pairs, "ronri::any", "all and some")
edge("ronri::not", :pairs, "ronri::both", "and, or, not")
edge("ronri::both", :pairs, "ronri::either", "and and or")
edge("ronri::every", :pairs, "ronri::none", "all versus none")
