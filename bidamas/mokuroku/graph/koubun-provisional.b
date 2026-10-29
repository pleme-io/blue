space("koubun?", {status: :provisional})

verb(
  "koubun?",
  "children",
  {
    kind: :pure,
    shape: "children(node) -> [node]",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-syntax",
    meaning: "the direct children of a node, in order",
    wave: 0,
    origin: "F"
  }
)

verb(
  "koubun?",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> [change]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "tree changes between two sources, not text lines",
    wave: 2,
    origin: "F"
  }
)

verb(
  "koubun?",
  "edit",
  {
    kind: :pure,
    shape: "edit(tree, range, text) -> tree",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a new tree after a text change, reusing the rest",
    wave: 3,
    origin: "F"
  }
)

verb(
  "koubun?",
  "errors",
  {
    kind: :pure,
    shape: "errors(tree) -> [error]",
    laterals: ["error"],
    fleet: "blue-lang-syntax",
    today: "rust:blue-lang-syntax",
    meaning: "the error nodes of a tree with expected tokens",
    wave: 1,
    origin: "F"
  }
)

verb(
  "koubun?",
  "grammar",
  {
    kind: :pure,
    shape: "grammar(spec) -> parser",
    laterals: ["validate"],
    fleet: "blue-lang-kiwari",
    today: "partial:kiwari",
    meaning: "a parser built from a grammar spec",
    wave: 2,
    origin: "F"
  }
)

verb(
  "koubun?",
  "hash",
  {
    kind: :pure,
    shape: "hash(tree) -> text",
    laterals: ["serialize"],
    fleet: "blue-lang-mondou",
    today: "rust:blue-lang-mondou",
    meaning: "identity of a tree; a definition hashes with its callees",
    wave: 0,
    origin: "F"
  }
)

verb(
  "koubun?",
  "highlight",
  {
    kind: :pure,
    shape: "highlight(tree) -> [span]",
    laterals: [],
    fleet: "blue-lang-kiwari",
    today: "partial:kiwari",
    meaning: "spans tagged with a role such as keyword or name",
    wave: 1,
    origin: "F"
  }
)

verb(
  "koubun?",
  "kind",
  {
    kind: :pure,
    shape: "kind(node) -> name",
    laterals: [],
    fleet: "blue-lang-syntax",
    today: "rust:blue-lang-syntax",
    meaning: "the grammar name of a node",
    wave: 0,
    origin: "F"
  }
)

verb(
  "koubun?",
  "lex",
  {
    kind: :pure,
    shape: "lex(source, lang) -> [token]",
    laterals: [],
    fleet: "blue-lang-syntax",
    today: "rust:blue-lang-syntax",
    meaning: "source text to tokens with positions",
    wave: 0,
    origin: "F"
  }
)

verb(
  "koubun?",
  "normalize",
  {
    kind: :pure,
    shape: "normalize(tree) -> tree",
    laterals: ["serialize"],
    fleet: "blue-lang-syntax",
    today: "rust:blue-lang-syntax",
    meaning: "the canonical tree for equivalent surface forms",
    wave: 1,
    origin: "F"
  }
)

verb(
  "koubun?",
  "parent",
  {
    kind: :pure,
    shape: "parent(tree, node) -> node or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the node that holds a node, or nil at the root",
    wave: 1,
    origin: "F"
  }
)

verb(
  "koubun?",
  "parse",
  {
    kind: :pure,
    shape: "parse(source, lang) -> tree",
    laterals: %w[error validate],
    fleet: "blue-lang-syntax",
    today: "rust:blue-lang-syntax",
    meaning: "source text to a tree with spans; error nodes kept",
    wave: 0,
    origin: "F"
  }
)

verb(
  "koubun?",
  "query",
  {
    kind: :pure,
    shape: "query(tree, pattern) -> [match]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "nodes that match a structural pattern",
    wave: 2,
    origin: "F"
  }
)

verb(
  "koubun?",
  "render",
  {
    kind: :pure,
    shape: "render(tree, lang) -> text",
    laterals: ["serialize"],
    fleet: "blue-lang-fmt",
    today: "rust:blue-lang-fmt",
    meaning: "a tree back to source text",
    wave: 0,
    origin: "F"
  }
)

verb(
  "koubun?",
  "span",
  {
    kind: :pure,
    shape: "span(node) -> range",
    laterals: [],
    fleet: "blue-lang-syntax",
    today: "rust:blue-lang-syntax",
    meaning: "the start and end position of a node",
    wave: 0,
    origin: "F"
  }
)

verb(
  "koubun?",
  "text",
  {
    kind: :pure,
    shape: "text(node) -> text",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-syntax",
    meaning: "the source text under a node",
    wave: 0,
    origin: "F"
  }
)

verb(
  "koubun?",
  "walk",
  {
    kind: :pure,
    shape: "walk(tree, order) -> [node]",
    laterals: [],
    fleet: "blue-lang-syntax",
    today: "rust:blue-lang-syntax",
    meaning: "every node in a fixed order",
    wave: 0,
    origin: "F",
    contract: "walk(tree, opts) -> [node]"
  }
)

edge("koubun?::grammar", :composes, "kiwari::render", "a parser from the spec")
edge("koubun?::parse", :composes, "koubun?::lex", "tokens then structure")

edge(
  "koubun?::hash",
  :composes,
  "koubun?::normalize",
  "hash of the canonical tree"
)

edge("koubun?::query", :composes, "koubun?::walk", "matches along the walk")
edge("koubun?::parent", :inverse, "koubun?::children", "down and up")
edge("koubun?::children", :inverse, "koubun?::parent", "down and up")
edge("koubun?::render", :inverse, "koubun?::parse", "source to tree and back")
edge("koubun?::parse", :inverse, "koubun?::render", "source to tree and back")

edge(
  "koubun?::errors",
  :pairs,
  "bunmyaku?::diagnostics",
  "parse errors are diagnostics"
)

edge("koubun?::span", :pairs, "bunmyaku?::diagnostics", "findings carry spans")
edge("koubun?::highlight", :pairs, "bunmyaku?::symbols", "colour and outline")
edge("koubun?::edit", :pairs, "kakikae?::apply", "edit one range or many")
edge("koubun?::diff", :pairs, "kakikae?::plan", "tree changes become edits")
edge("koubun?::hash", :pairs, "kenshutsu?::clones", "equal hash is a clone")

edge(
  "koubun?::render",
  :pairs,
  "kenshutsu?::format",
  "format is render of a normal tree"
)

edge("koubun?::lex", :pairs, "kiwari::literals", "tokens come from literals")
edge("koubun?::kind", :pairs, "kiwari::rule", "kinds are rule names")

edge(
  "koubun?::text",
  :pairs,
  "koubun?::children",
  "text of a node and its parts"
)

edge("koubun?::walk", :pairs, "koubun?::query", "visit versus match")
edge("koubun?::kind", :pairs, "koubun?::span", "node name and place")

edge(
  "koubun?::edit",
  :refines,
  "koubun?::parse",
  "reparse that reuses the tree"
)

edge("koubun?::lex", :refines, "koubun?::parse", "first stage of parse")

edge(
  "koubun?::normalize",
  :refines,
  "koubun?::parse",
  "canonical result of parse"
)

edge("koubun?::grammar", :requires, "kiwari::rule", "built from rules")
edge("koubun?::walk", :requires, "koubun?::children", "visits via children")
edge("koubun?::highlight", :requires, "koubun?::kind", "roles by node kind")
edge("koubun?::errors", :requires, "koubun?::parse", "error nodes of a parse")
edge("koubun?::edit", :requires, "koubun?::span", "edits a range")
edge("koubun?::text", :requires, "koubun?::span", "text is the span's slice")
edge("koubun?::diff", :requires, "koubun?::walk", "compares node by node")
edge("koubun?::parent", :requires, "koubun?::walk", "up from a visited node")
