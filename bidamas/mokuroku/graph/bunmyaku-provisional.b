space("bunmyaku?", {status: :provisional})

verb(
  "bunmyaku?",
  "actions",
  {
    kind: :pure,
    shape: "actions(document, range) -> [action]",
    laterals: ["migrate"],
    fleet: "blue-lang-lsp",
    today: "absent",
    meaning: "fixes and refactors offered for a range",
    wave: 2,
    origin: "F"
  }
)

verb(
  "bunmyaku?",
  "complete",
  {
    kind: :pure,
    shape: "complete(document, position) -> [item]",
    laterals: [],
    fleet: "blue-lang-mondou",
    today: "rust:blue-lang-mondou",
    meaning: "names valid at a position",
    wave: 0,
    origin: "F"
  }
)

verb(
  "bunmyaku?",
  "definition",
  {
    kind: :pure,
    shape: "definition(document, position) -> location or nil",
    laterals: [],
    fleet: "blue-lang-mondou",
    today: "rust:blue-lang-mondou",
    meaning: "where the name at a position is defined",
    wave: 0,
    origin: "F"
  }
)

verb(
  "bunmyaku?",
  "describe",
  {
    kind: :pure,
    shape: "describe(document, position) -> text",
    laterals: [],
    fleet: "blue-lang-mondou",
    today: "rust:blue-lang-mondou",
    meaning: "signature, doc and type of the name at a position",
    wave: 1,
    origin: "F"
  }
)

verb(
  "bunmyaku?",
  "diagnostics",
  {
    kind: :pure,
    shape: "diagnostics(document) -> [diagnostic]",
    laterals: ["error"],
    fleet: "blue-lang-check",
    today: "rust:blue-lang-lsp",
    meaning: "findings of the check stage with spans",
    wave: 0,
    origin: "F"
  }
)

verb(
  "bunmyaku?",
  "eval",
  {
    kind: :effect,
    shape: "eval(expr, context) -> value",
    laterals: %w[capability deadline],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "evaluate one expression in a session",
    wave: 0,
    origin: "F"
  }
)

verb(
  "bunmyaku?",
  "infer",
  {
    kind: :pure,
    shape: "infer(expr, env) -> type",
    laterals: ["validate"],
    fleet: "blue-lang-check",
    today: "rust:blue-lang-check",
    meaning: "the type of an expression in an environment",
    wave: 0,
    origin: "F"
  }
)

verb(
  "bunmyaku?",
  "references",
  {
    kind: :pure,
    shape: "references(document, position) -> [location]",
    laterals: [],
    fleet: "blue-lang-mondou",
    today: "rust:blue-lang-mondou",
    meaning: "every use of the name at a position",
    wave: 0,
    origin: "F"
  }
)

verb(
  "bunmyaku?",
  "serve",
  {
    kind: :effect,
    shape: "serve(transport, opts) -> nil",
    laterals: %w[cancel resource],
    fleet: "blue-lang-lsp",
    today: "rust:blue-lang-lsp",
    meaning: "run the language server on a transport",
    wave: 0,
    origin: "F",
    contract: "serve(transport, handler, opts) -> nil"
  }
)

verb(
  "bunmyaku?",
  "signature",
  {
    kind: :pure,
    shape: "signature(document, position) -> record or nil",
    laterals: [],
    fleet: "blue-lang-mondou",
    today: "rust:blue-lang-mondou",
    meaning: "the call signature at a position, with the active argument",
    wave: 0,
    origin: "F"
  }
)

verb(
  "bunmyaku?",
  "subtype?",
  {
    kind: :pure,
    shape: "subtype?(a, b) -> Bool",
    laterals: ["validate"],
    fleet: "blue-lang-check",
    today: "rust:blue-lang-check",
    meaning: "whether a value of type a fits where b is wanted",
    wave: 0,
    origin: "F"
  }
)

verb(
  "bunmyaku?",
  "symbols",
  {
    kind: :pure,
    shape: "symbols(document) -> [symbol]",
    laterals: [],
    fleet: "blue-lang-mondou",
    today: "rust:blue-lang-mondou",
    meaning: "the outline of a document",
    wave: 0,
    origin: "F"
  }
)

verb(
  "bunmyaku?",
  "sync",
  {
    kind: :effect,
    shape: "sync(document, change) -> nil",
    laterals: ["cache"],
    fleet: "blue-lang-lsp",
    today: "rust:blue-lang-lsp",
    meaning: "tell the server a document changed",
    wave: 0,
    origin: "F"
  }
)

edge("bunmyaku?::describe", :composes, "bunmyaku?::infer", "shows the type")

edge(
  "bunmyaku?::serve",
  :composes,
  "bunmyaku?::sync",
  "keeps documents current"
)

edge(
  "bunmyaku?::diagnostics",
  :composes,
  "kenshutsu?::check",
  "findings with spans"
)

edge("bunmyaku?::actions", :composes, "kenshutsu?::fix", "offers the fixes")
edge("bunmyaku?::eval", :composes, "koubun?::parse", "parse, check, run")

edge(
  "bunmyaku?::references",
  :composes,
  "koubun?::query",
  "find the name in trees"
)

edge(
  "bunmyaku?::references",
  :generalizes,
  "bunmyaku?::definition",
  "every use of a definition"
)

edge(
  "bunmyaku?::sync",
  :pairs,
  "bunmyaku?::diagnostics",
  "every change is rechecked"
)

edge(
  "bunmyaku?::definition",
  :pairs,
  "bunmyaku?::references",
  "definition and uses"
)

edge(
  "bunmyaku?::complete",
  :pairs,
  "bunmyaku?::signature",
  "names then call shape"
)

edge("bunmyaku?::infer", :pairs, "bunmyaku?::subtype?", "infer and compare")
edge("bunmyaku?::eval", :pairs, "genin?::inspect", "eval in a paused frame")
edge("bunmyaku?::actions", :pairs, "kakikae?::rename", "actions include rename")

edge(
  "bunmyaku?::diagnostics",
  :pairs,
  "kenshutsu?::fix",
  "diagnostic with a fix"
)

edge(
  "bunmyaku?::symbols",
  :pairs,
  "mokuroku::catalog",
  "outline and catalog agree"
)

edge(
  "bunmyaku?::describe",
  :pairs,
  "mokuroku::get",
  "hover shows the catalog entry"
)

edge("bunmyaku?::signature", :refines, "bunmyaku?::describe", "call shape only")

edge(
  "bunmyaku?::infer",
  :requires,
  "bunmyaku?::subtype?",
  "checks fit while inferring"
)

edge(
  "bunmyaku?::complete",
  :requires,
  "bunmyaku?::sync",
  "answers from the newest text"
)

edge(
  "bunmyaku?::sync",
  :requires,
  "koubun?::edit",
  "applies a change to the tree"
)

edge(
  "bunmyaku?::definition",
  :requires,
  "koubun?::parse",
  "resolves names in a tree"
)

edge("bunmyaku?::serve", :requires, "koubun?::parse", "every request parses")
edge("bunmyaku?::symbols", :requires, "koubun?::walk", "outline from the tree")
