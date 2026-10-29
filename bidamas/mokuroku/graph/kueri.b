space("kueri", {status: :ratified})

verb(
  "kueri",
  "asof_join",
  {
    kind: :pure,
    shape: "asof_join(left, right, on) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "partial:kueri",
    meaning: "join each left row to the nearest earlier right row",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kueri",
  "count",
  {
    kind: :pure,
    shape: "count(plan) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "absent",
    meaning: "a plan that yields the row count",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kueri",
  "derive",
  {
    kind: :pure,
    shape: "derive(plan, items) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "exists:kueri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kueri",
  "describe",
  {
    kind: :pure,
    shape: "describe(plan) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "absent",
    meaning: "per-column type, nulls and summary figures",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kueri",
  "distinct",
  {
    kind: :pure,
    shape: "distinct(plan, keys) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "absent",
    meaning: "one row per distinct key",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kueri",
  "except",
  {
    kind: :pure,
    shape: "except(a, b) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "absent",
    meaning: "rows of a that are not in b",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kueri",
  "explain",
  {
    kind: :pure,
    shape: "explain(plan) -> text",
    laterals: [],
    fleet: "kueri",
    today: "absent",
    meaning: "the engine's execution plan as text",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kueri",
  "explode",
  {
    kind: :pure,
    shape: "explode(plan, column) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "exists:kueri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kueri",
  "filter",
  {
    kind: :pure,
    shape: "filter(plan, predicate) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "exists:kueri",
    meaning: "keep rows where the predicate holds",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kueri",
  "from",
  {
    kind: :pure,
    shape: "from(source, opts) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "partial:kueri",
    meaning: "start a plan from a table, file or plan",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kueri",
  "group",
  {
    kind: :pure,
    shape: "group(plan, keys, aggregates) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "exists:kueri",
    wave: 0,
    origin: "A",
    contract: "group(plan, keys, opts) -> plan"
  }
)

verb(
  "kueri",
  "ident",
  {
    kind: :pure,
    shape: "ident(name) -> text",
    laterals: [],
    fleet: nil,
    today: "exists:kueri",
    wave: 0,
    origin: "H"
  }
)

verb(
  "kueri",
  "join",
  {
    kind: :pure,
    shape: "join(left, right, on, opts) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "exists:kueri",
    meaning: "rows paired across two plans by a condition",
    wave: 0,
    origin: "A",
    contract: "join(left, right) -> plan"
  }
)

verb(
  "kueri",
  "left_join",
  {
    kind: :pure,
    shape: "left_join(left, right, on) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "exists:kueri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kueri",
  "load",
  {
    kind: :effect,
    shape: "load(path, opts) -> plan",
    laterals: %w[capability error],
    fleet: nil,
    today: "absent",
    meaning: "a file of CSV, JSON or Parquet as a source",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kueri",
  "pivot",
  {
    kind: :pure,
    shape: "pivot(plan, on, value, agg) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "absent",
    meaning: "row values turned into columns",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kueri",
  "query",
  {
    kind: :effect,
    shape: "query(store, sql, params) -> [record]",
    laterals: %w[capability deadline error],
    fleet: "kueri",
    today: "partial:kueri",
    meaning: "raw SQL against a store, returning records",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kueri",
  "render",
  {
    kind: :pure,
    shape: "render(plan, dialect) -> text",
    laterals: ["serialize"],
    fleet: "kueri",
    today: "exists:kueri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kueri",
  "run",
  {
    kind: :effect,
    shape: "run(plan, opts) -> [record]",
    laterals: %w[capability deadline error resource],
    fleet: "kueri",
    today: "partial:kueri",
    meaning: "execute a plan in memory or in DuckDB",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kueri",
  "sample",
  {
    kind: :pure,
    shape: "sample(plan, n, rng) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "absent",
    meaning: "n rows chosen with a seeded stream",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kueri",
  "save",
  {
    kind: :effect,
    shape: "save(plan, path, opts) -> nil",
    laterals: %w[capability error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "write a plan's rows to a file",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kueri",
  "schema",
  {
    kind: :pure,
    shape: "schema(plan) -> schema",
    laterals: ["validate"],
    fleet: "kueri",
    today: "absent",
    meaning: "column names and types a plan yields",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kueri",
  "select",
  {
    kind: :pure,
    shape: "select(plan, items) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "exists:kueri",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kueri",
  "sort",
  {
    kind: :pure,
    shape: "sort(plan, keys) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "exists:kueri",
    wave: 0,
    origin: "A",
    contract: "sort(plan, opts) -> plan"
  }
)

verb(
  "kueri",
  "take",
  {
    kind: :pure,
    shape: "take(plan, n, opts) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "partial:kueri",
    meaning: "keep the first n rows",
    wave: 0,
    origin: "A",
    contract: "take(plan, n) -> plan"
  }
)

verb(
  "kueri",
  "union",
  {
    kind: :pure,
    shape: "union(a, b, opts) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "absent",
    meaning: "rows of both plans",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kueri",
  "unpivot",
  {
    kind: :pure,
    shape: "unpivot(plan, columns, opts) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "absent",
    meaning: "columns turned into row values",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kueri",
  "window",
  {
    kind: :pure,
    shape: "window(plan, items, opts) -> plan",
    laterals: ["validate"],
    fleet: "kueri",
    today: "exists:kueri",
    wave: 0,
    origin: "A"
  }
)

edge("kueri::load", :composes, "deeta::parse", "CSV and JSON sources")
edge("kueri::save", :composes, "deeta::write", "file format from the extension")
edge("kueri::sample", :composes, "kakuritsu?::int", "draws row positions")
edge("kueri::describe", :composes, "kueri::group", "aggregate each column")
edge("kueri::run", :composes, "kueri::query", "execute the text")

edge(
  "kueri::explain",
  :composes,
  "kueri::render",
  "ask the engine about the text"
)

edge("kueri::run", :composes, "kueri::render", "render, then execute")
edge("kueri::group", :composes, "kueri::select", "aggregates are select items")
edge("kueri::take", :composes, "kueri::sort", "first rows of the order")
edge("kueri::window", :composes, "retsu::windows", "frames over ordered rows")
edge("kueri::describe", :composes, "toukei::summary", "figures per column")
edge("kueri::join", :generalizes, "kueri::left_join", "inner and outer")
edge("kueri::query", :generalizes, "kueri::run", "raw SQL, not a plan")
edge("kueri::render", :guards, "kueri::run", "SQL text is what the engine runs")
edge("kueri::schema", :guards, "kueri::run", "know the columns before running")
edge("kueri::from", :guards, "kueri::select", "a plan starts from a source")
edge("kueri::save", :inverse, "kueri::load", "rows to file and back")
edge("kueri::load", :inverse, "kueri::save", "rows to file and back")
edge("kueri::select", :pairs, "kueri::derive", "choose versus add columns")
edge("kueri::union", :pairs, "kueri::except", "add and subtract rows")

edge(
  "kueri::explode",
  :pairs,
  "kueri::group",
  "split a list versus collect rows"
)

edge("kueri::join", :pairs, "kueri::group", "combine tables then collapse rows")
edge("kueri::window", :pairs, "kueri::group", "keep rows versus collapse them")
edge("kueri::run", :pairs, "kueri::save", "execute and persist")
edge("kueri::filter", :pairs, "kueri::select", "rows versus columns")
edge("kueri::sort", :pairs, "kueri::take", "order then cut")
edge("kueri::pivot", :pairs, "kueri::unpivot", "rows to columns and back")

edge(
  "kueri::schema",
  :pairs,
  "sukiima?::validate",
  "rows checked against the schema"
)

edge("kueri::query", :pairs, "teeburu::query", "DuckDB versus PostgreSQL")
edge("kueri::sort", :refines, "junjo::sort_by", "rows ordered by keys")
edge("kueri::load", :refines, "kueri::from", "a file as the source")
edge("kueri::count", :refines, "kueri::group", "one group over all rows")
edge("kueri::distinct", :refines, "kueri::group", "group on all columns")

edge(
  "kueri::asof_join",
  :refines,
  "kueri::join",
  "match by nearest earlier key"
)

edge("kueri::left_join", :refines, "kueri::join", "keeps unmatched left rows")
edge("kueri::derive", :refines, "kueri::select", "select plus every old column")
edge("kueri::sample", :refines, "kueri::take", "random rows, not first rows")
edge("kueri::filter", :refines, "retsu::filter", "rows are a list")
edge("kueri::explode", :refines, "retsu::flat_map", "one row per list item")
edge("kueri::group", :refines, "retsu::group_by", "rows grouped by keys")
edge("kueri::select", :refines, "retsu::map", "each row rewritten")
edge("kueri::take", :refines, "retsu::take", "the first rows")
edge("kueri::distinct", :refines, "retsu::unique", "rows without repeats")
edge("kueri::except", :refines, "shuugou::difference", "rows as a set")
edge("kueri::join", :refines, "shuugou::product", "a filtered product")
edge("kueri::union", :refines, "shuugou::union", "rows as a set")
