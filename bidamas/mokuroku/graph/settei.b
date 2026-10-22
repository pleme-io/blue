space("settei", {status: :ratified})

verb(
  "settei",
  "defaults",
  {
    kind: :pure,
    shape: "defaults(app) -> record",
    laterals: ["config"],
    fleet: "shikumi",
    today: "partial:settei",
    meaning: "the built-in default record of an app",
    wave: 0,
    origin: "B"
  }
)

verb(
  "settei",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> [change]",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "the settings that differ between two records",
    wave: 1,
    origin: "B"
  }
)

verb(
  "settei",
  "explain",
  {
    kind: :pure,
    shape: "explain(config, path) -> {value, tier, source}",
    laterals: ["config"],
    fleet: "shikumi",
    today: "absent",
    meaning: "which tier and file a setting value came from",
    wave: 1,
    origin: "B"
  }
)

verb(
  "settei",
  "file",
  {
    kind: :effect,
    shape: "file(app, tier) -> path",
    laterals: ["capability", "config"],
    fleet: "okiba",
    today: "partial:settei",
    meaning: "where the config file of an app tier lives",
    wave: 0,
    origin: "B"
  }
)

verb(
  "settei",
  "get",
  {
    kind: :pure,
    shape: "get(config, path) -> value or nil",
    laterals: ["config"],
    fleet: "shikumi",
    today: "partial:settei",
    meaning: "one setting by dotted path, or nil when absent",
    wave: 0,
    origin: "B"
  }
)

verb(
  "settei",
  "has?",
  {
    kind: :pure,
    shape: "has?(config, path) -> Bool",
    laterals: ["config"],
    fleet: "shikumi",
    today: "absent",
    meaning: "whether a setting is defined",
    wave: 0,
    origin: "B"
  }
)

verb(
  "settei",
  "list",
  {
    kind: :pure,
    shape: "list(config, opts) -> [{path, value}]",
    laterals: ["config"],
    fleet: "shikumi",
    today: "absent",
    meaning: "every setting as a sorted path and value list",
    wave: 1,
    origin: "B"
  }
)

verb(
  "settei",
  "merge",
  {
    kind: :pure,
    shape: "merge(a, b) -> record",
    laterals: ["config"],
    fleet: "shikumi",
    today: "partial:settei",
    meaning: "combine two records, b winning, deep for maps",
    wave: 0,
    origin: "B"
  }
)

verb(
  "settei",
  "need",
  {
    kind: :pure,
    shape: "need(config, path) -> value",
    laterals: ["config", "error"],
    fleet: "shikumi",
    today: "absent",
    meaning: "one setting by dotted path, raising not_found",
    wave: 0,
    origin: "B"
  }
)

verb(
  "settei",
  "put",
  {
    kind: :effect,
    shape: "put(app, tier, path, value) -> nil",
    laterals: ["config", "error", "idempotent"],
    fleet: "shikumi",
    today: "absent",
    meaning: "write one setting into a named tier file",
    wave: 2,
    origin: "B",
    contract: "put(app, tier, path, opts) -> nil"
  }
)

verb(
  "settei",
  "read",
  {
    kind: :effect,
    shape: "read(app, defaults, opts) -> record",
    laterals: ["config", "error", "validate"],
    fleet: "shikumi",
    today: "partial:settei",
    meaning: "resolve defaults, then file, then environment into one record",
    wave: 0,
    origin: "B",
    contract: "read(app, opts) -> record"
  }
)

verb(
  "settei",
  "reload",
  {
    kind: :effect,
    shape: "reload(app) -> record",
    laterals: ["config", "error"],
    fleet: "shikumi",
    today: "absent",
    meaning: "read the tiers again and return the fresh record",
    wave: 2,
    origin: "B"
  }
)

verb(
  "settei",
  "schema",
  {
    kind: :pure,
    shape: "schema(defaults) -> schema",
    laterals: ["config", "validate"],
    fleet: "shikumi",
    today: "absent",
    meaning: "the schema a defaults record implies",
    wave: 1,
    origin: "B"
  }
)

verb(
  "settei",
  "validate",
  {
    kind: :pure,
    shape: "validate(config, schema) -> [problem]",
    laterals: ["config", "validate"],
    fleet: "shikumi",
    today: "absent",
    meaning: "check a record against a schema, naming each fault",
    wave: 1,
    origin: "B"
  }
)

verb(
  "settei",
  "watch",
  {
    kind: :stream,
    shape: "watch(app, f, opts) -> nil",
    laterals: ["cancel", "config", "time"],
    fleet: "shikumi",
    today: "absent",
    meaning: "call f with the new record whenever a tier changes",
    wave: 2,
    origin: "B"
  }
)

edge("settei::file", :composes, "fairu::join", "file name under it")
edge("settei::file", :composes, "fairu::place", "config tier directory")
edge("settei::watch", :composes, "fairu::watch", "file change events")
edge("settei::put", :composes, "fairu::write", "atomic file write")
edge("settei::read", :composes, "settei::defaults", "lowest tier")
edge("settei::put", :composes, "settei::file", "which tier file")
edge("settei::read", :composes, "settei::file", "finds the file")
edge("settei::diff", :composes, "settei::list", "compares path lists")

edge(
  "settei::read",
  :composes,
  "settei::merge",
  "file and environment layered on"
)

edge(
  "settei::validate",
  :composes,
  "settei::schema",
  "checks against the schema"
)

edge("settei::merge", :composes, "shuusei::deep_merge", "deep for maps")
edge("settei::put", :composes, "shuusei::put", "amends the document")

edge(
  "settei::validate",
  :guards,
  "settei::reload",
  "refuse a bad record on reload"
)

edge("settei::watch", :lifts, "settei::reload", "each change reloads")
edge("settei::list", :pairs, "settei::get", "all paths beside one")
edge("settei::explain", :pairs, "settei::list", "origin beside value")
edge("settei::diff", :pairs, "settei::merge", "compare then combine")
edge("settei::file", :pairs, "settei::put", "file beside write")
edge("settei::get", :pairs, "settei::put", "read and write a setting")
edge("settei::get", :pairs, "settei::read", "lookup in the record")
edge("settei::watch", :pairs, "settei::reload", "change and refresh")
edge("settei::defaults", :pairs, "settei::schema", "values and their types")
edge("settei::schema", :pairs, "settei::validate", "shape and its check")
edge("settei::explain", :refines, "settei::get", "adds tier and file")
edge("settei::has?", :refines, "settei::get", "existence only")
edge("settei::need", :refines, "settei::get", "raises when absent")
edge("settei::reload", :refines, "settei::read", "read again now")

edge(
  "settei::schema",
  :requires,
  "settei::defaults",
  "types come from defaults"
)
