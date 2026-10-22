space("sukiima?", {status: :provisional})

verb(
  "sukiima?",
  "coerce",
  {
    kind: :pure,
    shape: "coerce(value, schema) -> value",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "convert text and numbers to the schema's types",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "compatible?",
  {
    kind: :pure,
    shape: "compatible?(old, new, direction) -> Bool",
    laterals: ["migrate"],
    fleet: nil,
    today: "absent",
    meaning: "whether data moves between versions safely",
    wave: 3,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "conforms?",
  {
    kind: :pure,
    shape: "conforms?(value, schema) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "whether the value matches the schema",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "defaults",
  {
    kind: :pure,
    shape: "defaults(schema) -> value",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a value filled with every declared default",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "describe",
  {
    kind: :pure,
    shape: "describe(schema) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "schema in prose for a human",
    wave: 3,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "diff",
  {
    kind: :pure,
    shape: "diff(old, new) -> [change]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "how two schemas differ, field by field",
    wave: 3,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "enum_of",
  {
    kind: :decl,
    shape: "enum_of(values) -> shape",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "shape of one value from a closed set",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "example",
  {
    kind: :pure,
    shape: "example(schema, seed) -> value",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a valid value generated from the schema",
    wave: 3,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "explain",
  {
    kind: :pure,
    shape: "explain(value, schema) -> [problem]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "every problem as path and reason",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "fields",
  {
    kind: :pure,
    shape: "fields(schema) -> [field]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "name, shape and default of each field",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "infer",
  {
    kind: :pure,
    shape: "infer(values, opts) -> schema",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "schema that fits a set of example values",
    wave: 3,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "list_of",
  {
    kind: :decl,
    shape: "list_of(shape) -> shape",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "shape of a list of one shape",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "map_of",
  {
    kind: :decl,
    shape: "map_of(key, value) -> shape",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "shape of a map with typed keys and values",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "one_of",
  {
    kind: :decl,
    shape: "one_of(shapes) -> shape",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "shape of a value matching any listed shape",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "optional",
  {
    kind: :decl,
    shape: "optional(shape) -> shape",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "shape that also accepts nil",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> schema",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "JSON Schema text to a schema",
    wave: 3,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "refine",
  {
    kind: :decl,
    shape: "refine(shape, predicate, why) -> shape",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "shape narrowed by a predicate with a reason",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "render",
  {
    kind: :pure,
    shape: "render(schema, format) -> text",
    laterals: ["serialize"],
    fleet: "haibi",
    today: "partial:haibi",
    meaning: "schema as JSON Schema text",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "schema",
  {
    kind: :decl,
    shape: "schema(name, shape) -> schema",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare a named type as data",
    wave: 2,
    origin: "A",
    contract: "schema(name) -> schema"
  }
)

verb(
  "sukiima?",
  "shape",
  {
    kind: :decl,
    shape: "shape(fields) -> shape",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "shape of a record with named typed fields",
    wave: 2,
    origin: "A"
  }
)

verb(
  "sukiima?",
  "validate",
  {
    kind: :pure,
    shape: "validate(value, schema) -> value",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "return the value or raise every problem at once",
    wave: 2,
    origin: "A"
  }
)

edge("sukiima?::parse", :composes, "deeta::parse", "schema text is a document")

edge(
  "sukiima?::example",
  :composes,
  "kakuritsu?::choice",
  "vary fields by seed"
)

edge(
  "sukiima?::validate",
  :composes,
  "kyohi::check",
  "one error carrying every problem"
)

edge("sukiima?::infer", :composes, "retsu::group_by", "group values by shape")
edge("sukiima?::refine", :composes, "ronri::both", "conjoin predicates")
edge("sukiima?::validate", :composes, "ronri::every", "every item must conform")

edge(
  "sukiima?::example",
  :composes,
  "sukiima?::defaults",
  "start from the defaults"
)

edge("sukiima?::compatible?", :composes, "sukiima?::diff", "safe changes only")

edge(
  "sukiima?::conforms?",
  :composes,
  "sukiima?::explain",
  "no problems means conforms"
)

edge(
  "sukiima?::validate",
  :composes,
  "sukiima?::explain",
  "raise the problems explain finds"
)

edge(
  "sukiima?::defaults",
  :composes,
  "sukiima?::fields",
  "each field's default"
)

edge(
  "sukiima?::describe",
  :composes,
  "sukiima?::fields",
  "prose from the fields"
)

edge("sukiima?::diff", :composes, "sukiima?::fields", "compare field by field")
edge("sukiima?::render", :composes, "sukiima?::fields", "walk the fields")

edge(
  "sukiima?::shape",
  :composes,
  "sukiima?::optional",
  "fields may be optional"
)

edge(
  "sukiima?::schema",
  :composes,
  "sukiima?::shape",
  "a name for a record shape"
)

edge("sukiima?::coerce", :composes, "sukiima?::validate", "convert, then check")

edge(
  "sukiima?::refine",
  :guards,
  "sukiima?::validate",
  "predicate runs in validate"
)

edge(
  "sukiima?::render",
  :inverse,
  "sukiima?::parse",
  "schema and JSON Schema round-trip"
)

edge(
  "sukiima?::parse",
  :inverse,
  "sukiima?::render",
  "schema and JSON Schema round-trip"
)

edge("sukiima?::validate", :pairs, "deeta::parse", "parse, then validate")

edge(
  "sukiima?::compatible?",
  :pairs,
  "sukiima?::coerce",
  "safe change or convertible value"
)

edge(
  "sukiima?::example",
  :pairs,
  "sukiima?::conforms?",
  "generated values conform"
)

edge(
  "sukiima?::coerce",
  :pairs,
  "sukiima?::defaults",
  "convert, then fill gaps"
)

edge(
  "sukiima?::infer",
  :pairs,
  "sukiima?::example",
  "learn a shape or make a value"
)

edge("sukiima?::shape", :pairs, "sukiima?::fields", "declare and read")

edge(
  "sukiima?::list_of",
  :pairs,
  "sukiima?::map_of",
  "the two collection shapes"
)

edge("sukiima?::describe", :pairs, "sukiima?::render", "prose versus machine")
edge("sukiima?::schema", :pairs, "sukiima?::validate", "declare then check")
edge("sukiima?::diff", :refines, "deeta::diff", "changes between shapes")
edge("sukiima?::render", :refines, "deeta::render", "output is a document")
edge("sukiima?::enum_of", :refines, "sukiima?::one_of", "a one_of of literals")
edge("sukiima?::optional", :refines, "sukiima?::one_of", "value or nil")

edge(
  "sukiima?::conforms?",
  :refines,
  "sukiima?::validate",
  "Bool instead of raising"
)

edge(
  "sukiima?::map_of",
  :requires,
  "sukiima?::list_of",
  "shares element shapes"
)

edge("sukiima?::explain", :requires, "sukiima?::schema", "walks the shape")

edge(
  "sukiima?::one_of",
  :requires,
  "sukiima?::schema",
  "alternatives are shapes"
)

edge(
  "sukiima?::fields",
  :requires,
  "sukiima?::shape",
  "only records have fields"
)
