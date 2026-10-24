space("danpen", {status: :ratified})

verb(
  "danpen",
  "check",
  {
    kind: :pure,
    shape: "check(subject, rules, opts) -> [finding]",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:danpen",
    wave: 1,
    origin: "I"
  }
)

verb(
  "danpen",
  "compose",
  {
    kind: :pure,
    shape: "compose(first, second) -> operation",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:danpen",
    wave: 1,
    origin: "I"
  }
)

verb(
  "danpen",
  "fragment",
  {
    kind: :decl,
    shape: "fragment(name, spec) -> fragment",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:danpen",
    wave: 1,
    origin: "I"
  }
)

verb(
  "danpen",
  "hash",
  {
    kind: :pure,
    shape: "hash(operation, algorithm) -> hex",
    laterals: ["cache"],
    fleet: "hanabi",
    today: "exists:danpen",
    wave: 1,
    origin: "I"
  }
)

verb(
  "danpen",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, opts) -> document",
    laterals: ["error"],
    fleet: nil,
    today: "exists:danpen",
    wave: 1,
    origin: "I"
  }
)

verb(
  "danpen",
  "render",
  {
    kind: :pure,
    shape: "render(document, format, opts) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "exists:danpen",
    wave: 1,
    origin: "I"
  }
)

verb(
  "danpen",
  "select",
  {
    kind: :pure,
    shape: "select(value, fragment) -> value",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:danpen",
    wave: 1,
    origin: "I"
  }
)

verb(
  "danpen",
  "validate",
  {
    kind: :pure,
    shape: "validate(document, schema, opts) -> document",
    laterals: ["validate", "error"],
    fleet: nil,
    today: "exists:danpen",
    wave: 1,
    origin: "I"
  }
)

edge(
  "danpen::compose",
  :composes,
  "danpen::fragment",
  "union of fragment selections"
)

edge(
  "danpen::hash",
  :composes,
  "danpen::render",
  "digest of the canonical text"
)

edge(
  "danpen::check",
  :composes,
  "danpen::validate",
  "fields absent from the schema"
)

edge(
  "danpen::hash",
  :composes,
  "shomei::hash",
  "sha256 by default, what persisted queries send"
)

edge(
  "danpen::check",
  :guards,
  "danpen::select",
  "undeclared reads refused at check"
)

edge("danpen::render", :inverse, "danpen::parse", "text back from a tree")
edge("danpen::parse", :inverse, "danpen::render", "text back from a tree")

edge(
  "danpen::fragment",
  :pairs,
  "gamen?::component",
  "a component's declared data"
)

edge("danpen::compose", :pairs, "gamen?::view", "a view's one operation")
edge("danpen::check", :refines, "core::check", "the four data laws")
edge("danpen::parse", :refines, "core::parse", "GraphQL as the format")
edge("danpen::render", :refines, "core::render", "GraphQL as the format")

edge(
  "danpen::select",
  :refines,
  "jisho::select",
  "the keys come from a fragment"
)

edge("danpen::select", :requires, "danpen::fragment", "the declared selection")

edge(
  "danpen::validate",
  :requires,
  "danpen::parse",
  "a document before a schema"
)

edge(
  "danpen::compose",
  :requires,
  "danpen::validate",
  "fragments checked against the schema"
)
