space("mokuroku", {status: :ratified})

verb(
  "mokuroku",
  "catalog",
  {
    kind: :pure,
    shape: "catalog(roots) -> catalog",
    laterals: ["serialize"],
    fleet: nil,
    today: "partial:mokuroku",
    meaning: "every package and definition under some roots",
    wave: 0,
    origin: "F"
  }
)

verb(
  "mokuroku",
  "check",
  {
    kind: :pure,
    shape: "check(catalog) -> findings",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:mokuroku",
    meaning: "find name collisions and shadowed names",
    wave: 0,
    origin: "G"
  }
)

verb(
  "mokuroku",
  "coverage",
  {
    kind: :pure,
    shape: "coverage(catalog) -> ratio",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the share of entries that are documented",
    wave: 1,
    origin: "F"
  }
)

verb(
  "mokuroku",
  "diff",
  {
    kind: :pure,
    shape: "diff(old, new) -> [change]",
    laterals: ["migrate"],
    fleet: nil,
    today: "absent",
    meaning: "added, removed and changed entries between two catalogs",
    wave: 1,
    origin: "F"
  }
)

verb(
  "mokuroku",
  "extract",
  {
    kind: :pure,
    shape: "extract(source) -> [entry]",
    laterals: ["serialize"],
    fleet: "pleme-doc-gen",
    today: "partial:mokuroku",
    meaning: "signature, gloss, tests and waivers from source text",
    wave: 0,
    origin: "F"
  }
)

verb(
  "mokuroku",
  "get",
  {
    kind: :pure,
    shape: "get(catalog, name) -> entry or nil",
    laterals: [],
    fleet: "blue-lang-cli",
    today: "rust:blue-lang-cli",
    meaning: "one entry by qualified name, or nil",
    wave: 0,
    origin: "F"
  }
)

verb(
  "mokuroku",
  "list",
  {
    kind: :pure,
    shape: "list(roots) -> packages",
    laterals: [],
    fleet: nil,
    today: "partial:mokuroku",
    meaning: "every package on a path",
    wave: 0,
    origin: "G"
  }
)

verb(
  "mokuroku",
  "render",
  {
    kind: :pure,
    shape: "render(catalog, format) -> text",
    laterals: ["serialize"],
    fleet: "pleme-doc-gen",
    today: "partial:mokuroku",
    meaning: "a catalog as a document, stable order",
    wave: 0,
    origin: "F"
  }
)

verb(
  "mokuroku",
  "run",
  {
    kind: :effect,
    shape: "run(catalog, opts) -> report",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "run the examples in the docs as tests",
    wave: 2,
    origin: "F"
  }
)

edge("mokuroku::coverage", :composes, "mokuroku::check", "share without gaps")
edge("mokuroku::catalog", :composes, "mokuroku::extract", "over every package")
edge("mokuroku::run", :composes, "tesuto?::run", "examples run as tests")
edge("mokuroku::list", :generalizes, "mokuroku::check", "the set checked")

edge(
  "mokuroku::diff",
  :guards,
  "rirezu?::breaking?",
  "interface change feeds it"
)

edge("mokuroku::render", :inverse, "mokuroku::catalog", "catalog to a document")
edge("mokuroku::catalog", :inverse, "mokuroku::render", "catalog to a document")
edge("mokuroku::get", :pairs, "bunmyaku?::describe", "same text in the editor")
edge("mokuroku::render", :pairs, "bunsho::render", "catalogs are documents")

edge(
  "mokuroku::catalog",
  :pairs,
  "chishiki?::index",
  "catalog entries are indexed"
)

edge("mokuroku::render", :pairs, "chishiki?::publish", "docs are published")
edge("mokuroku::coverage", :pairs, "hadome::judge", "doc coverage cannot fall")

edge(
  "mokuroku::extract",
  :pairs,
  "hinagata?::generate",
  "docs are generated output"
)

edge(
  "mokuroku::render",
  :pairs,
  "hinagata?::regen",
  "CATALOG is a generated file"
)

edge("mokuroku::check", :pairs, "kenshutsu?::check", "doc gaps are findings")

edge(
  "mokuroku::diff",
  :pairs,
  "rirezu?::changelog",
  "interface changes in the notes"
)

edge("mokuroku::run", :pairs, "tesuto?::snapshot", "examples compare outputs")
edge("mokuroku::get", :refines, "mokuroku::catalog", "one entry")
edge("mokuroku::extract", :requires, "koubun?::parse", "reads definitions")
edge("mokuroku::check", :requires, "mokuroku::catalog", "gaps in entries")
edge("mokuroku::diff", :requires, "mokuroku::catalog", "two catalogs")
edge("mokuroku::check", :requires, "mokuroku::list", "checks the whole set")
edge("mokuroku::render", :requires, "mokuroku::list", "catalog of packages")
