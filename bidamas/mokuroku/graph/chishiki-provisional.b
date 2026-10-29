space("chishiki?", {status: :provisional})

verb(
  "chishiki?",
  "delete",
  {
    kind: :effect,
    shape: "delete(wiki, page) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "remove a page; an absent page counts as done",
    wave: 2,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "duplicates",
  {
    kind: :pure,
    shape: "duplicates(wiki) -> [group]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "pages that say nearly the same thing",
    wave: 3,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "export",
  {
    kind: :effect,
    shape: "export(wiki, target, opts) -> nil",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "write a space or subtree as sealed files",
    wave: 3,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "get",
  {
    kind: :effect,
    shape: "get(wiki, page) -> page or nil",
    laterals: ["deadline"],
    fleet: "confluence-pr-refresh",
    today: "absent",
    meaning: "one page by title or id, or nil",
    wave: 2,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "index",
  {
    kind: :effect,
    shape: "index(sources, opts) -> index",
    laterals: %w[cache resource],
    fleet: nil,
    today: "absent",
    meaning: "build a search index over pages and docs",
    wave: 2,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "links_to",
  {
    kind: :pure,
    shape: "links_to(wiki, page) -> [page]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "pages that link to a page",
    wave: 3,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "list",
  {
    kind: :effect,
    shape: "list(wiki, opts) -> [page]",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "every page of a space, all pages, sorted",
    wave: 2,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "orphans",
  {
    kind: :pure,
    shape: "orphans(wiki) -> [page]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "pages that nothing links to",
    wave: 3,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "plan",
  {
    kind: :pure,
    shape: "plan(runbook, opts) -> [action]",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "the actions a runbook would take, changing nothing",
    wave: 2,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "publish",
  {
    kind: :effect,
    shape: "publish(doc, wiki, opts) -> page",
    laterals: ["idempotent"],
    fleet: "confluence-pr-refresh",
    today: "absent",
    meaning: "put a generated document in a wiki at its anchor",
    wave: 2,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "put",
  {
    kind: :effect,
    shape: "put(wiki, page, content) -> page",
    laterals: ["idempotent"],
    fleet: "confluence-pr-refresh",
    today: "absent",
    meaning: "create or replace a page",
    wave: 2,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "run",
  {
    kind: :effect,
    shape: "run(runbook, opts) -> report",
    laterals: %w[cancel capability log],
    fleet: nil,
    today: "absent",
    meaning: "run steps; stop at the first failed check",
    wave: 3,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "runbook",
  {
    kind: :decl,
    shape: "runbook(name, steps) -> runbook",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "declare ordered steps, each with a check and a rollback",
    wave: 2,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "search",
  {
    kind: :effect,
    shape: "search(index, query, opts) -> [hit]",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "ranked pages for a text query",
    wave: 2,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "stale?",
  {
    kind: :pure,
    shape: "stale?(page, since) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "whether a page is older than the code or date it describes",
    wave: 3,
    origin: "F"
  }
)

verb(
  "chishiki?",
  "update",
  {
    kind: :effect,
    shape: "update(wiki, page, f) -> page",
    laterals: %w[error idempotent],
    fleet: "confluence-pr-refresh",
    today: "absent",
    meaning: "change one anchored section; refuse a stale version",
    wave: 2,
    origin: "F"
  }
)

edge(
  "chishiki?::orphans",
  :composes,
  "chishiki?::links_to",
  "pages with no inbound link"
)

edge(
  "chishiki?::export",
  :composes,
  "chishiki?::list",
  "every page in the space"
)

edge("chishiki?::index", :composes, "chishiki?::list", "indexes listed pages")
edge("chishiki?::duplicates", :composes, "chishiki?::search", "similar pages")

edge(
  "chishiki?::publish",
  :composes,
  "chishiki?::update",
  "replaces one anchored section"
)

edge("chishiki?::run", :composes, "rogu::info", "each step is logged")
edge("chishiki?::list", :generalizes, "chishiki?::get", "all pages")
edge("chishiki?::plan", :guards, "chishiki?::run", "preview before steps")
edge("chishiki?::put", :inverse, "chishiki?::delete", "create and remove")
edge("chishiki?::put", :inverse, "chishiki?::get", "read and write")
edge("chishiki?::delete", :inverse, "chishiki?::put", "create and remove")
edge("chishiki?::get", :inverse, "chishiki?::put", "read and write")

edge(
  "chishiki?::stale?",
  :pairs,
  "chishiki?::duplicates",
  "both are garden checks"
)

edge(
  "chishiki?::delete",
  :pairs,
  "chishiki?::orphans",
  "orphans are deleted on review"
)

edge(
  "chishiki?::links_to",
  :pairs,
  "chishiki?::orphans",
  "inbound links versus none"
)

edge("chishiki?::export", :pairs, "chishiki?::publish", "out and in")
edge("chishiki?::index", :pairs, "chishiki?::stale?", "stale pages rank lower")
edge("chishiki?::search", :pairs, "mokuroku::get", "search finds, get reads")

edge(
  "chishiki?::publish",
  :pairs,
  "mokuroku::render",
  "rendered docs go to the wiki"
)

edge("chishiki?::run", :pairs, "shougai?::mitigate", "runbook steps mitigate")
edge("chishiki?::runbook", :pairs, "shougai?::route", "alerts name runbooks")
edge("chishiki?::update", :refines, "chishiki?::put", "partial and versioned")

edge(
  "chishiki?::search",
  :requires,
  "chishiki?::index",
  "search needs an index"
)

edge("chishiki?::get", :requires, "chishiki?::list", "pages named by list")
edge("chishiki?::links_to", :requires, "chishiki?::list", "scans page links")

edge(
  "chishiki?::runbook",
  :requires,
  "chishiki?::plan",
  "declared to be planned"
)

edge(
  "chishiki?::stale?",
  :requires,
  "gitto::info",
  "compares with code change time"
)
