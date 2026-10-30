space("bunsho", {status: :ratified})

verb(
  "bunsho",
  "check",
  {
    kind: :pure,
    shape: "check(doc, rules) -> findings",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "find dead links, skipped heading levels, missing alt text",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "convert",
  {
    kind: :pure,
    shape: "convert(doc, to) -> doc",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a document in another format, content kept",
    wave: 2,
    origin: "G"
  }
)

verb(
  "bunsho",
  "deck",
  {
    kind: :decl,
    shape: "deck(slides, theme) -> doc",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare a slide deck",
    wave: 2,
    origin: "G"
  }
)

verb(
  "bunsho",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> changes",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "structural changes between two documents",
    wave: 2,
    origin: "G"
  }
)

verb(
  "bunsho",
  "extract",
  {
    kind: :pure,
    shape: "extract(doc, kind) -> parts",
    laterals: [],
    fleet: nil,
    today: "exists:bunsho",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "fill",
  {
    kind: :pure,
    shape: "fill(template, data) -> doc",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "a template with its slots filled from a record",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "find",
  {
    kind: :pure,
    shape: "find(doc, query) -> node or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the first node that matches a query",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "map_nodes",
  {
    kind: :pure,
    shape: "map_nodes(doc, f) -> doc",
    laterals: [],
    fleet: nil,
    today: "exists:bunsho",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "highlight",
  {
    kind: :pure,
    shape: "highlight(code, language) -> spans",
    laterals: [],
    fleet: "hikari",
    today: "absent",
    meaning: "code split into classed token spans",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "merge",
  {
    kind: :pure,
    shape: "merge(a, b, opts) -> doc",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "combine two documents; conflict is a refusal",
    wave: 2,
    origin: "G"
  }
)

verb(
  "bunsho",
  "normalize",
  {
    kind: :pure,
    shape: "normalize(doc) -> doc",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the one canonical form of a document",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "outline",
  {
    kind: :pure,
    shape: "outline(doc) -> heading tree",
    laterals: [],
    fleet: "mojiban",
    today: "absent",
    meaning: "the headings of a document, nested",
    wave: 1,
    origin: "G",
    contract: "outline(doc, span, name) -> heading tree"
  }
)

verb(
  "bunsho",
  "paginate",
  {
    kind: :pure,
    shape: "paginate(doc, page) -> pages",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "break a document into pages of a size",
    wave: 3,
    origin: "G"
  }
)

verb(
  "bunsho",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format?) -> doc",
    laterals: ["validate"],
    fleet: "mojiban",
    today: "exists:bunsho",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "put",
  {
    kind: :pure,
    shape: "put(doc, id, node) -> doc",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a document with a section or cell replaced",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "read",
  {
    kind: :effect,
    shape: "read(src, opts) -> doc",
    laterals: ["resource"],
    fleet: "mojiban",
    today: "absent",
    meaning: "a document file read to a tree, by extension",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "redact",
  {
    kind: :pure,
    shape: "redact(doc, rules) -> doc",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a document with sensitive spans masked",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "render",
  {
    kind: :pure,
    shape: "render(doc, format?) -> text",
    laterals: ["serialize"],
    fleet: "mojiban",
    today: "exists:bunsho",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "rebase",
  {
    kind: :pure,
    shape: "rebase(doc, from, to) -> doc",
    laterals: [],
    fleet: nil,
    today: "exists:bunsho",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "walk",
  {
    kind: :pure,
    shape: "walk(doc) -> [node]",
    laterals: [],
    fleet: nil,
    today: "exists:bunsho",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "section",
  {
    kind: :pure,
    shape: "section(doc, anchor) -> [node] or nil",
    laterals: [],
    fleet: nil,
    today: "exists:bunsho",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "slide",
  {
    kind: :decl,
    shape: "slide(layout, content) -> slide",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare one slide: layout, text, figures, notes",
    wave: 2,
    origin: "G"
  }
)

verb(
  "bunsho",
  "table",
  {
    kind: :decl,
    shape: "table(columns, rows) -> table",
    laterals: ["validate"],
    fleet: "caixa-csv",
    today: "absent",
    meaning: "declare rows under typed columns",
    wave: 1,
    origin: "G"
  }
)

verb(
  "bunsho",
  "write",
  {
    kind: :effect,
    shape: "write(doc, target, opts) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "a document tree written to a file",
    wave: 1,
    origin: "G"
  }
)

edge("bunsho::convert", :composes, "bunsho::parse", "parse the source")

edge(
  "bunsho::normalize",
  :composes,
  "bunsho::parse",
  "parse then render canonical"
)

edge("bunsho::read", :composes, "bunsho::parse", "file then tree")
edge("bunsho::fill", :composes, "bunsho::put", "slots are puts")
edge("bunsho::convert", :composes, "bunsho::render", "render the target")

edge(
  "bunsho::deck",
  :composes,
  "bunsho::render",
  "a deck renders to pdf or html"
)

edge(
  "bunsho::normalize",
  :composes,
  "bunsho::render",
  "parse then render canonical"
)

edge("bunsho::write", :composes, "bunsho::render", "tree then file")
edge("bunsho::extract", :composes, "bunsho::walk", "the nodes of one kind")
edge("bunsho::rebase", :composes, "bunsho::map_nodes", "rewrites link nodes")
edge("bunsho::walk", :requires, "bunsho::parse", "needs a tree")
edge("bunsho::map_nodes", :requires, "bunsho::parse", "needs a tree")

edge(
  "bunsho::section",
  :requires,
  "bunsho::parse",
  "anchors come from the tree"
)

edge("bunsho::deck", :composes, "bunsho::slide", "a deck is slides")
edge("bunsho::write", :guards, "bunsho::redact", "redact before write")
edge("bunsho::check", :guards, "bunsho::render", "no output with dead links")
edge("bunsho::redact", :guards, "bunsho::write", "no secret in output")
edge("bunsho::merge", :inverse, "bunsho::diff", "apply what diff found")
edge("bunsho::diff", :inverse, "bunsho::merge", "apply what diff found")
edge("bunsho::render", :inverse, "bunsho::parse", "text to tree and back")
edge("bunsho::parse", :inverse, "bunsho::render", "text to tree and back")
edge("bunsho::put", :pairs, "bunsho::section", "write and read by id")
edge("bunsho::section", :pairs, "bunsho::put", "read and write by id")
edge("bunsho::extract", :refines, "bunsho::find", "all parts of a kind")

edge(
  "bunsho::table",
  :requires,
  "bunsho::extract",
  "tables are extracted parts"
)

edge("bunsho::diff", :requires, "bunsho::normalize", "compare canonical forms")

edge("bunsho::merge", :requires, "bunsho::normalize", "merge canonical forms")
edge("bunsho::read", :requires, "bunsho::normalize", "one form after reading")

edge(
  "bunsho::check",
  :requires,
  "bunsho::outline",
  "heading levels from the outline"
)

edge("bunsho::paginate", :requires, "bunsho::outline", "break before headings")

edge("bunsho::fill", :requires, "bunsho::parse", "templates are documents")
edge("bunsho::find", :requires, "bunsho::parse", "searches a tree")
edge("bunsho::highlight", :requires, "bunsho::parse", "code blocks are nodes")
edge("bunsho::outline", :requires, "bunsho::parse", "needs a tree")
edge("bunsho::slide", :requires, "gamen?::layout", "slides are laid out")

edge("bunsho::paginate", :requires, "gamen?::measure", "page breaks need sizes")

edge("bunsho::highlight", :requires, "gamen?::paint", "spans become ink")
edge("bunsho::deck", :requires, "gamen?::theme", "slides take a theme")
edge("bunsho::table", :requires, "gamen?::view", "a table is a view")
