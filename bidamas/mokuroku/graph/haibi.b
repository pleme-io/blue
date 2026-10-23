space("haibi", {status: :ratified})

verb(
  "haibi",
  "check",
  {
    kind: :pure,
    shape: "check(service, row) -> [refusal]",
    laterals: ["validate"],
    fleet: "haibi",
    today: "partial:haibi",
    meaning: "refuse a row that breaks the declared table",
    wave: 0,
    origin: "E"
  }
)

verb(
  "haibi",
  "ddl",
  {
    kind: :pure,
    shape: "ddl(service) -> text",
    laterals: ["serialize"],
    fleet: "haibi",
    today: "exists:haibi",
    meaning: "database schema statements from declared tables",
    wave: 0,
    origin: "E"
  }
)

verb(
  "haibi",
  "render",
  {
    kind: :pure,
    shape: "render(service, opts) -> [file]",
    laterals: ["serialize", "validate"],
    fleet: "haibi",
    today: "partial:haibi",
    meaning: "chart, values, schema and rules from one service spec",
    wave: 0,
    origin: "E"
  }
)

verb(
  "haibi",
  "schema",
  {
    kind: :pure,
    shape: "schema(service) -> schema",
    laterals: ["validate"],
    fleet: "haibi",
    today: "partial:haibi",
    meaning: "values.schema.json from the service defaults",
    wave: 0,
    origin: "E"
  }
)

edge("haibi::render", :composes, "haibi::ddl", "service tables become DDL")
edge("haibi::render", :composes, "haibi::schema", "chart ships its schema")
edge("haibi::check", :guards, "haibi::ddl", "rows must fit the tables")
edge("haibi::schema", :pairs, "kurasuta::render", "schema guards chart values")
edge("haibi::ddl", :refines, "core::render", "tables to SQL")
edge("haibi::schema", :refines, "core::render", "values schema from defaults")
edge("haibi::render", :requires, "haibi::check", "validated spec renders")
