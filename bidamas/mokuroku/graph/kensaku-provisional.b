space("kensaku?", {status: :provisional})

verb(
  "kensaku?",
  "analyze",
  {
    kind: :pure,
    shape: "analyze(text, analyzer) -> tokens",
    laterals: [],
    fleet: "sakuin",
    today: "absent",
    meaning: "text to index terms: split, fold, stem",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "chunk",
  {
    kind: :pure,
    shape: "chunk(doc, opts) -> chunks",
    laterals: [],
    fleet: "codesearch",
    today: "absent",
    meaning: "split a document into pieces that fit a search unit",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "cite",
  {
    kind: :pure,
    shape: "cite(hits) -> citations",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "source, span and score for each used hit",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "delete",
  {
    kind: :effect,
    shape: "delete(index, id) -> nil",
    laterals: ["idempotent"],
    fleet: "sakuin",
    today: "absent",
    meaning: "remove a document; absent counts as done",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "expand",
  {
    kind: :effect,
    shape: "expand(model, query) -> queries",
    laterals: %w[cache deadline],
    fleet: nil,
    today: "absent",
    meaning: "rewrite a query into variants to widen recall",
    wave: 3,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "explain",
  {
    kind: :pure,
    shape: "explain(hit) -> text",
    laterals: [],
    fleet: "codesearch",
    today: "absent",
    meaning: "say why a hit matched: terms, vector, rank",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "fuse",
  {
    kind: :pure,
    shape: "fuse(lists, opts) -> hits",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "merge ranked lists into one, by reciprocal rank",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "ground",
  {
    kind: :effect,
    shape: "ground(question, index, opts) -> {text, citations}",
    laterals: %w[deadline trace],
    fleet: nil,
    today: "absent",
    meaning: "answer a question from retrieved sources only",
    wave: 3,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "index",
  {
    kind: :decl,
    shape: "index(kind, opts) -> index",
    laterals: %w[config resource],
    fleet: "sakuin",
    today: "absent",
    meaning: "declare an index: keyword, vector, hybrid or spatial",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "info",
  {
    kind: :effect,
    shape: "info(index) -> {docs, bytes, built}",
    laterals: [],
    fleet: "codesearch",
    today: "absent",
    meaning: "state of an index; docs scanned must be read",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "put",
  {
    kind: :effect,
    shape: "put(index, id, doc) -> nil",
    laterals: ["idempotent"],
    fleet: "sakuin",
    today: "absent",
    meaning: "add or replace a document in an index",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "query",
  {
    kind: :effect,
    shape: "query(index, question, params) -> records",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "ask an index in its own language, no ranking",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "rank",
  {
    kind: :pure,
    shape: "rank(items, query, opts) -> ranked",
    laterals: [],
    fleet: "furui",
    today: "absent",
    meaning: "order items by fuzzy score against a query",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "rerank",
  {
    kind: :effect,
    shape: "rerank(hits, query, opts) -> hits",
    laterals: %w[cache deadline],
    fleet: "codesearch",
    today: "absent",
    meaning: "reorder hits with a stronger model",
    wave: 3,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "search",
  {
    kind: :effect,
    shape: "search(index, query, opts) -> hits",
    laterals: %w[cache deadline],
    fleet: "codesearch",
    today: "absent",
    meaning: "ranked hits for a query: exact, keyword, vector or hybrid",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "similarity",
  {
    kind: :pure,
    shape: "similarity(a, b, metric) -> number",
    laterals: [],
    fleet: "codesearch",
    today: "absent",
    meaning: "cosine, dot or L2 closeness of two vectors",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "support?",
  {
    kind: :effect,
    shape: "support?(answer, hits) -> {supported, gaps}",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "whether the sources back every claim in an answer",
    wave: 3,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "sync",
  {
    kind: :effect,
    shape: "sync(index, source, opts) -> report",
    laterals: %w[idempotent resource],
    fleet: "codesearch",
    today: "absent",
    meaning: "bring an index level with its source, changes only",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kensaku?",
  "watch",
  {
    kind: :stream,
    shape: "watch(index, source, opts) -> nil",
    laterals: ["cancel"],
    fleet: "codesearch",
    today: "absent",
    meaning: "keep an index fresh as the source changes",
    wave: 3,
    origin: "G"
  }
)

edge("kensaku?::ground", :composes, "kensaku?::cite", "show sources")
edge("kensaku?::sync", :composes, "kensaku?::delete", "removes gone")
edge("kensaku?::sync", :composes, "kensaku?::put", "adds changes")
edge("kensaku?::ground", :composes, "kensaku?::search", "find sources")
edge("kensaku?::ground", :composes, "mokei?::ask", "answer from them")
edge("kensaku?::search", :composes, "mokei?::embed", "vector mode")
edge("kensaku?::index", :generalizes, "kensaku?::put", "documents go in")
edge("kensaku?::support?", :guards, "kensaku?::ground", "check claims")

edge(
  "kensaku?::info",
  :guards,
  "kensaku?::search",
  "check the index is not empty"
)

edge("kensaku?::put", :inverse, "kensaku?::delete", "removes what put added")
edge("kensaku?::delete", :inverse, "kensaku?::put", "removes what put added")
edge("kensaku?::watch", :lifts, "kensaku?::sync", "sync per change")
edge("kensaku?::chunk", :pairs, "kensaku?::analyze", "pieces then terms")
edge("kensaku?::explain", :pairs, "kensaku?::cite", "why and from where")
edge("kensaku?::put", :pairs, "kensaku?::delete", "add and remove")
edge("kensaku?::expand", :pairs, "kensaku?::fuse", "variants merged back")
edge("kensaku?::rerank", :refines, "kensaku?::rank", "model scoring")
edge("kensaku?::query", :refines, "kensaku?::search", "exact language, no rank")
edge("kensaku?::chunk", :requires, "bunsho?::outline", "split on structure")
edge("kensaku?::put", :requires, "kensaku?::analyze", "terms of a document")
edge("kensaku?::analyze", :requires, "kensaku?::index", "index terms")
edge("kensaku?::info", :requires, "kensaku?::index", "reads an index")
edge("kensaku?::query", :requires, "kensaku?::index", "asks an index")
edge("kensaku?::search", :requires, "kensaku?::index", "searches an index")
edge("kensaku?::watch", :requires, "kensaku?::index", "keeps an index fresh")
edge("kensaku?::cite", :requires, "kensaku?::search", "from hits")
edge("kensaku?::explain", :requires, "kensaku?::search", "about a hit")
edge("kensaku?::fuse", :requires, "kensaku?::search", "merge lists of hits")

edge(
  "kensaku?::rank",
  :requires,
  "kensaku?::similarity",
  "score from closeness"
)

edge("kensaku?::expand", :requires, "mokei?::ask", "a model rewrites")
edge("kensaku?::rerank", :requires, "mokei?::ask", "a stronger model")
edge("kensaku?::support?", :requires, "mokei?::ask", "a judge model")
edge("kensaku?::similarity", :requires, "mokei?::embed", "vectors to compare")
