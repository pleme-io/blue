space("tanni?", {status: :provisional})

verb(
  "tanni?",
  "add",
  {
    kind: :pure,
    shape: "add(a, b) -> quantity",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "sum of two quantities; mismatched dimensions raise",
    wave: 3,
    origin: "A"
  }
)

verb(
  "tanni?",
  "base",
  {
    kind: :pure,
    shape: "base(quantity) -> quantity",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "quantity in the SI base units",
    wave: 3,
    origin: "A"
  }
)

verb(
  "tanni?",
  "compare",
  {
    kind: :pure,
    shape: "compare(a, b) -> int",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "order two quantities of one dimension",
    wave: 3,
    origin: "A"
  }
)

verb(
  "tanni?",
  "compatible?",
  {
    kind: :pure,
    shape: "compatible?(a, b) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether two units share a dimension",
    wave: 3,
    origin: "A"
  }
)

verb(
  "tanni?",
  "convert",
  {
    kind: :pure,
    shape: "convert(quantity, unit) -> quantity",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "same amount in another unit of the same dimension",
    wave: 3,
    origin: "A"
  }
)

verb(
  "tanni?",
  "dimension",
  {
    kind: :pure,
    shape: "dimension(quantity) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "exponents of length, mass, time and so on",
    wave: 3,
    origin: "A"
  }
)

verb(
  "tanni?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text) -> quantity",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "text like \"5 km/h\" to a quantity",
    wave: 3,
    origin: "A"
  }
)

verb(
  "tanni?",
  "quantity",
  {
    kind: :pure,
    shape: "quantity(value, unit) -> quantity",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "a number with a unit",
    wave: 3,
    origin: "A"
  }
)

verb(
  "tanni?",
  "render",
  {
    kind: :pure,
    shape: "render(quantity, opts) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "quantity to text in a chosen unit",
    wave: 3,
    origin: "A"
  }
)

verb(
  "tanni?",
  "scale",
  {
    kind: :pure,
    shape: "scale(quantity, factor) -> quantity",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "quantity multiplied by a plain number",
    wave: 3,
    origin: "A"
  }
)

verb(
  "tanni?",
  "unit",
  {
    kind: :decl,
    shape: "unit(name, definition) -> unit",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare a unit by its dimension and factor",
    wave: 3,
    origin: "A"
  }
)

edge("tanni?::render", :composes, "kazu::render", "number part")
edge("tanni?::parse", :composes, "moji::find", "number then unit text")

edge(
  "tanni?::convert",
  :composes,
  "seimitsu?::ratio",
  "factors are exact fractions"
)

edge("tanni?::compare", :composes, "tanni?::base", "compare in base units")
edge("tanni?::convert", :composes, "tanni?::base", "via base units")
edge("tanni?::add", :composes, "tanni?::convert", "bring b into a's unit")
edge("tanni?::compatible?", :composes, "tanni?::dimension", "equal exponents")
edge("tanni?::parse", :composes, "tanni?::quantity", "text to value and unit")

edge(
  "tanni?::scale",
  :composes,
  "tanni?::quantity",
  "rebuild with the new value"
)

edge("tanni?::compatible?", :guards, "tanni?::add", "checked before adding")

edge(
  "tanni?::unit",
  :guards,
  "tanni?::quantity",
  "a quantity needs a declared unit"
)

edge(
  "tanni?::render",
  :inverse,
  "tanni?::parse",
  "text and quantity round-trip"
)

edge(
  "tanni?::parse",
  :inverse,
  "tanni?::render",
  "text and quantity round-trip"
)

edge("tanni?::base", :pairs, "tanni?::convert", "canonical form for comparison")

edge(
  "tanni?::add",
  :requires,
  "tanni?::compatible?",
  "mismatch raises dimension_mismatch"
)

edge("tanni?::convert", :requires, "tanni?::compatible?", "same dimension only")
edge("tanni?::base", :requires, "tanni?::unit", "factor from the declaration")

edge(
  "tanni?::dimension",
  :requires,
  "tanni?::unit",
  "read from the declaration"
)

edge("tanni?::quantity", :requires, "tanni?::unit", "attaches a unit")
