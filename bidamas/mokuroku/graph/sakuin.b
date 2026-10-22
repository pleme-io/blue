space("sakuin", {status: :ratified})

verb(
  "sakuin",
  "analyze",
  {
    kind: :pure,
    shape: "analyze(text, opts) -> [token]",
    laterals: [],
    fleet: "sakuin",
    today: "absent",
    meaning: "split text into index tokens: case, stems, stop words",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "close",
  {
    kind: :effect,
    shape: "close(index) -> nil",
    laterals: ["resource"],
    fleet: "sakuin",
    today: "absent",
    meaning: "release the index and its writer lock",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "commit",
  {
    kind: :effect,
    shape: "commit(index) -> nil",
    laterals: ["error", "resource"],
    fleet: "sakuin",
    today: "absent",
    meaning: "make pending writes visible to searches",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "count",
  {
    kind: :effect,
    shape: "count(index, query) -> number",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "how many documents match a query",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "delete",
  {
    kind: :effect,
    shape: "delete(index, id) -> nil",
    laterals: ["error", "idempotent"],
    fleet: "sakuin",
    today: "absent",
    meaning: "remove one document by id; absent counts as done",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "distance",
  {
    kind: :pure,
    shape: "distance(a, b, metric) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "cosine, L2 or dot distance between two vectors",
    wave: 3,
    origin: "B",
    contract: "distance(a, b, opts) -> number"
  }
)

verb(
  "sakuin",
  "embed",
  {
    kind: :effect,
    shape: "embed(text, opts) -> vector",
    laterals: ["deadline", "error", "ratelimit", "retry"],
    fleet: "codesearch",
    today: "absent",
    meaning: "the vector a model gives a text",
    wave: 3,
    origin: "B"
  }
)

verb(
  "sakuin",
  "facet",
  {
    kind: :effect,
    shape: "facet(index, query, field) -> [{value, count}]",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "count hits per value of a field",
    wave: 3,
    origin: "B"
  }
)

verb(
  "sakuin",
  "fuse",
  {
    kind: :pure,
    shape: "fuse(rankings, opts) -> [hit]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "merge several ranked lists by reciprocal rank",
    wave: 3,
    origin: "B"
  }
)

verb(
  "sakuin",
  "get",
  {
    kind: :effect,
    shape: "get(index, id) -> doc or nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "the stored document by id, or nil",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "has?",
  {
    kind: :effect,
    shape: "has?(index, id) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a document with the id is indexed",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "highlight",
  {
    kind: :pure,
    shape: "highlight(doc, question, opts) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the document text with matched terms marked",
    wave: 3,
    origin: "B",
    contract: "highlight(doc, question) -> text"
  }
)

verb(
  "sakuin",
  "info",
  {
    kind: :effect,
    shape: "info(index) -> {docs, bytes, schema}",
    laterals: [],
    fleet: "codesearch",
    today: "absent",
    meaning: "size and schema facts of the index",
    wave: 3,
    origin: "B"
  }
)

verb(
  "sakuin",
  "invert",
  {
    kind: :pure,
    shape: "invert(docs, opts) -> postings",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "build an in-memory inverted index from documents",
    wave: 3,
    origin: "B"
  }
)

verb(
  "sakuin",
  "list",
  {
    kind: :effect,
    shape: "list(index, opts) -> [id]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "document ids, sorted, all pages",
    wave: 3,
    origin: "B"
  }
)

verb(
  "sakuin",
  "lookup",
  {
    kind: :pure,
    shape: "lookup(postings, term) -> [id]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the document ids holding a term in an in-memory index",
    wave: 3,
    origin: "B"
  }
)

verb(
  "sakuin",
  "nearest",
  {
    kind: :pure,
    shape: "nearest(vectors, q, k, opts) -> [{id, distance}]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the k closest vectors to q by exact scan",
    wave: 3,
    origin: "B"
  }
)

verb(
  "sakuin",
  "open",
  {
    kind: :effect,
    shape: "open(spec) -> index",
    laterals: ["capability", "config", "resource"],
    fleet: "sakuin",
    today: "absent",
    meaning: "open or create a search index at a path or URL",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "optimize",
  {
    kind: :effect,
    shape: "optimize(index) -> nil",
    laterals: ["cancel", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "merge index segments to speed later searches",
    wave: 4,
    origin: "B"
  }
)

verb(
  "sakuin",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, opts) -> question",
    laterals: ["validate"],
    fleet: "sakuin",
    today: "absent",
    meaning: "turn a query string into a structured question",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "purge",
  {
    kind: :effect,
    shape: "purge(index, query) -> count",
    laterals: ["error"],
    fleet: "sakuin",
    today: "absent",
    meaning: "remove every document matching a query",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "put",
  {
    kind: :effect,
    shape: "put(index, id, doc) -> nil",
    laterals: ["error", "idempotent"],
    fleet: "sakuin",
    today: "absent",
    meaning: "add or replace one document by id",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "query",
  {
    kind: :effect,
    shape: "query(index, question, params) -> [hit]",
    laterals: ["deadline", "error"],
    fleet: "codesearch",
    today: "absent",
    meaning: "hits for a structured question in the index language",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "reindex",
  {
    kind: :effect,
    shape: "reindex(index, source, opts) -> count",
    laterals: ["cancel", "error", "migrate"],
    fleet: "sakuin",
    today: "absent",
    meaning: "rebuild the index from a source of documents",
    wave: 3,
    origin: "B"
  }
)

verb(
  "sakuin",
  "schema",
  {
    kind: :decl,
    shape: "schema(fields) -> schema",
    laterals: ["validate"],
    fleet: "sakuin",
    today: "absent",
    meaning: "declare the fields of a document and how each is indexed",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "score",
  {
    kind: :pure,
    shape: "score(postings, terms, opts) -> [{id, score}]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "rank documents by BM25 over an in-memory index",
    wave: 3,
    origin: "B"
  }
)

verb(
  "sakuin",
  "search",
  {
    kind: :effect,
    shape: "search(index, text, opts) -> {hits, total}",
    laterals: ["deadline", "error", "trace"],
    fleet: "sakuin",
    today: "absent",
    meaning: "ranked hits for free text, with filter, sort and page",
    wave: 2,
    origin: "B"
  }
)

verb(
  "sakuin",
  "similar",
  {
    kind: :effect,
    shape: "similar(index, subject, opts) -> [hit]",
    laterals: ["deadline", "error"],
    fleet: "codesearch",
    today: "absent",
    meaning: "hits nearest to a document or vector",
    wave: 3,
    origin: "B"
  }
)

verb(
  "sakuin",
  "suggest",
  {
    kind: :effect,
    shape: "suggest(index, prefix, opts) -> [text]",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "completions for a typed prefix",
    wave: 3,
    origin: "B"
  }
)

edge("sakuin::reindex", :composes, "fairu::walk", "file sources are walked")
edge("sakuin::highlight", :composes, "sakuin::analyze", "finds matched terms")
edge("sakuin::invert", :composes, "sakuin::analyze", "postings from tokens")
edge("sakuin::parse", :composes, "sakuin::analyze", "terms of the query text")
edge("sakuin::put", :composes, "sakuin::analyze", "tokens for each text field")
edge("sakuin::search", :composes, "sakuin::analyze", "same tokens as indexing")
edge("sakuin::similar", :composes, "sakuin::embed", "vector of the subject")
edge("sakuin::score", :composes, "sakuin::lookup", "ranks looked-up documents")
edge("sakuin::similar", :composes, "sakuin::nearest", "closest vectors")
edge("sakuin::search", :composes, "sakuin::parse", "query text to question")
edge("sakuin::purge", :composes, "sakuin::query", "finds the documents")

edge(
  "sakuin::fuse",
  :composes,
  "sakuin::search",
  "merges text and vector rankings"
)

edge(
  "sakuin::commit",
  :guards,
  "sakuin::search",
  "searches see committed writes"
)

edge("sakuin::parse", :guards, "sakuin::search", "reject a bad query early")
edge("sakuin::open", :inverse, "sakuin::close", "releases the index")
edge("sakuin::put", :inverse, "sakuin::delete", "removes what put added")
edge("sakuin::close", :inverse, "sakuin::open", "releases the index")
edge("sakuin::delete", :inverse, "sakuin::put", "removes what put added")
edge("sakuin::purge", :lifts, "sakuin::delete", "by question not by id")
edge("sakuin::reindex", :lifts, "sakuin::put", "whole source into the index")
edge("sakuin::delete", :pairs, "sakuin::commit", "removals show after commit")
edge("sakuin::optimize", :pairs, "sakuin::commit", "segment merge after writes")
edge("sakuin::facet", :pairs, "sakuin::count", "counts per value and total")
edge("sakuin::info", :pairs, "sakuin::count", "size and schema facts")
edge("sakuin::list", :pairs, "sakuin::count", "ids beside their count")
edge("sakuin::distance", :pairs, "sakuin::nearest", "metric for the scan")
edge("sakuin::commit", :pairs, "sakuin::put", "writes show after commit")
edge("sakuin::get", :pairs, "sakuin::put", "store and fetch by id")
edge("sakuin::query", :pairs, "sakuin::search", "structured and free text")
edge("sakuin::embed", :pairs, "sakuin::similar", "text to vector to hits")
edge("sakuin::has?", :refines, "sakuin::get", "existence only")
edge("sakuin::count", :refines, "sakuin::query", "number not hits")
edge("sakuin::facet", :refines, "sakuin::query", "counts per field value")
edge("sakuin::search", :refines, "sakuin::query", "ranked free-text form")
edge("sakuin::similar", :refines, "sakuin::query", "nearest by vector")
edge("sakuin::score", :refines, "sakuin::search", "in-memory form")
edge("sakuin::suggest", :refines, "sakuin::search", "prefix completions")
edge("sakuin::nearest", :refines, "sakuin::similar", "exact scan form")

edge(
  "sakuin::optimize",
  :requires,
  "sakuin::commit",
  "merges committed segments"
)

edge("sakuin::nearest", :requires, "sakuin::distance", "ranks by the metric")
edge("sakuin::lookup", :requires, "sakuin::invert", "needs built postings")
edge("sakuin::open", :requires, "sakuin::schema", "fields define the index")
edge("sakuin::put", :requires, "sakuin::schema", "fields are checked")
