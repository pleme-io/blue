space("teeburu", {status: :ratified})

verb(
  "teeburu",
  "alive?",
  {
    kind: :effect,
    shape: "alive?(conn) -> Bool",
    laterals: ["deadline"],
    fleet: "pleme-database",
    today: "absent",
    meaning: "whether the server answers a trivial statement",
    wave: 1,
    origin: "B"
  }
)

verb(
  "teeburu",
  "begin",
  {
    kind: :effect,
    shape: "begin(conn, opts) -> tx",
    laterals: %w[error resource],
    fleet: "pleme-database",
    today: "absent",
    meaning: "open a transaction at an isolation level",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "close",
  {
    kind: :effect,
    shape: "close(conn) -> nil",
    laterals: ["resource"],
    fleet: "pleme-database",
    today: "partial:teeburu",
    meaning: "end a connection; later calls on it raise",
    wave: 1,
    origin: "B"
  }
)

verb(
  "teeburu",
  "columns",
  {
    kind: :effect,
    shape: "columns(conn, table) -> [column]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "the columns, types and constraints of a table",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "commit",
  {
    kind: :effect,
    shape: "commit(tx) -> nil",
    laterals: ["error"],
    fleet: "pleme-database",
    today: "absent",
    meaning: "make a transaction permanent",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "connect",
  {
    kind: :effect,
    shape: "connect(url, opts) -> conn",
    laterals: %w[capability config deadline resource],
    fleet: "pleme-database",
    today: "partial:teeburu",
    meaning: "open one database connection from a URL or settings",
    wave: 1,
    origin: "B"
  }
)

verb(
  "teeburu",
  "copy",
  {
    kind: :effect,
    shape: "copy(from, to, opts) -> count",
    laterals: %w[cancel deadline error],
    fleet: "shinka",
    today: "absent",
    meaning: "copy a table or model between databases",
    wave: 3,
    origin: "B"
  }
)

verb(
  "teeburu",
  "count",
  {
    kind: :effect,
    shape: "count(conn, table, opts) -> number",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "how many rows match a filter",
    wave: 1,
    origin: "B"
  }
)

verb(
  "teeburu",
  "create",
  {
    kind: :effect,
    shape: "create(conn, table, row) -> row",
    laterals: %w[error idempotent],
    fleet: "pleme-database",
    today: "partial:teeburu",
    meaning: "insert a new row and return it; exists if duplicate",
    wave: 1,
    origin: "B"
  }
)

verb(
  "teeburu",
  "delete",
  {
    kind: :effect,
    shape: "delete(conn, table, key) -> nil",
    laterals: %w[error idempotent],
    fleet: "pleme-database",
    today: "absent",
    meaning: "make the row absent; absent counts as done",
    wave: 1,
    origin: "B",
    contract: "delete(conn, table, opts) -> nil"
  }
)

verb(
  "teeburu",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> [change]",
    laterals: [],
    fleet: "shinka",
    today: "absent",
    meaning: "the changes that turn schema a into schema b",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "dump",
  {
    kind: :stream,
    shape: "dump(conn, source, f) -> count",
    laterals: %w[cancel deadline error],
    fleet: nil,
    today: "absent",
    meaning: "stream a table or query out, row by row",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "execute",
  {
    kind: :effect,
    shape: "execute(conn, sql, params) -> {affected}",
    laterals: %w[deadline error trace],
    fleet: "pleme-database",
    today: "absent",
    meaning: "run one parameterized statement for its effect",
    wave: 1,
    origin: "B"
  }
)

verb(
  "teeburu",
  "explain",
  {
    kind: :effect,
    shape: "explain(conn, sql, params) -> plan",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "the execution plan the server chose for a statement",
    wave: 2,
    origin: "B",
    contract: "explain(conn, sql) -> plan"
  }
)

verb(
  "teeburu",
  "get",
  {
    kind: :effect,
    shape: "get(conn, table, key) -> row or nil",
    laterals: %w[deadline error],
    fleet: "pleme-database",
    today: "absent",
    meaning: "one row by primary key, or nil when absent",
    wave: 1,
    origin: "B",
    contract: "get(conn, table, opts) -> row or nil"
  }
)

verb(
  "teeburu",
  "has?",
  {
    kind: :effect,
    shape: "has?(conn, table, key) -> Bool",
    laterals: ["deadline"],
    fleet: "pleme-database",
    today: "absent",
    meaning: "whether a row with the key exists",
    wave: 1,
    origin: "B",
    contract: "has?(conn, table) -> Bool"
  }
)

verb(
  "teeburu",
  "list",
  {
    kind: :effect,
    shape: "list(conn, table, opts) -> [row]",
    laterals: %w[deadline error],
    fleet: "pleme-database",
    today: "partial:teeburu",
    meaning: "rows matching a filter, ordered, every page",
    wave: 1,
    origin: "B",
    contract: "list(conn, opts) -> [row]"
  }
)

verb(
  "teeburu",
  "listen",
  {
    kind: :stream,
    shape: "listen(conn, channel, f) -> nil",
    laterals: %w[cancel deadline],
    fleet: nil,
    today: "absent",
    meaning: "call f per notification on a channel",
    wave: 3,
    origin: "B",
    contract: "listen(conn, opts) -> nil"
  }
)

verb(
  "teeburu",
  "load",
  {
    kind: :effect,
    shape: "load(conn, table, rows) -> count",
    laterals: %w[cancel deadline error],
    fleet: nil,
    today: "absent",
    meaning: "bulk insert many rows in one round trip",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "need",
  {
    kind: :effect,
    shape: "need(conn, table, key) -> row",
    laterals: %w[deadline error],
    fleet: "pleme-database",
    today: "absent",
    meaning: "one row by primary key, raising not_found",
    wave: 1,
    origin: "B",
    contract: "need(conn, table, opts) -> row"
  }
)

verb(
  "teeburu",
  "notify",
  {
    kind: :effect,
    shape: "notify(conn, channel, payload) -> nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "send a notification on a channel",
    wave: 3,
    origin: "B"
  }
)

verb(
  "teeburu",
  "parse",
  {
    kind: :pure,
    shape: "parse(url) -> {host, port, db, user}",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "split a database URL into its parts",
    wave: 1,
    origin: "B"
  }
)

verb(
  "teeburu",
  "plan",
  {
    kind: :pure,
    shape: "plan(changes) -> [statement]",
    laterals: ["validate"],
    fleet: "shinka",
    today: "absent",
    meaning: "the DDL statements for schema changes, ordered safely",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "pool",
  {
    kind: :effect,
    shape: "pool(url, opts) -> pool",
    laterals: %w[config ratelimit resource],
    fleet: "pleme-database",
    today: "absent",
    meaning: "a bounded set of reusable connections",
    wave: 2,
    origin: "B",
    contract: "pool(url, f, opts) -> pool"
  }
)

verb(
  "teeburu",
  "put",
  {
    kind: :effect,
    shape: "put(conn, table, key, row) -> row",
    laterals: %w[error idempotent],
    fleet: "pleme-database",
    today: "absent",
    meaning: "insert or replace a row by key",
    wave: 1,
    origin: "B",
    contract: "put(conn, table, key, opts) -> row"
  }
)

verb(
  "teeburu",
  "query",
  {
    kind: :effect,
    shape: "query(conn, sql, params) -> [row]",
    laterals: %w[deadline error retry trace],
    fleet: "pleme-database",
    today: "partial:teeburu",
    meaning: "run one parameterized statement and return its rows",
    wave: 1,
    origin: "B"
  }
)

verb(
  "teeburu",
  "quote",
  {
    kind: :pure,
    shape: "quote(ident) -> text",
    laterals: [],
    fleet: nil,
    today: "partial:teeburu",
    meaning: "an identifier made safe to put in SQL",
    wave: 0,
    origin: "B"
  }
)

verb(
  "teeburu",
  "rollback",
  {
    kind: :effect,
    shape: "rollback(tx) -> nil",
    laterals: %w[error idempotent],
    fleet: "pleme-database",
    today: "absent",
    meaning: "discard a transaction; already ended counts as done",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "savepoint",
  {
    kind: :effect,
    shape: "savepoint(tx, f) -> value",
    laterals: %w[error resource],
    fleet: nil,
    today: "absent",
    meaning: "run f in a nested unit that rolls back alone",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "schema",
  {
    kind: :effect,
    shape: "schema(conn) -> schema",
    laterals: ["error"],
    fleet: "shinka",
    today: "absent",
    meaning: "the whole live schema as one record",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "script",
  {
    kind: :effect,
    shape: "script(conn, text) -> [tag]",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "run an unparameterized multi-statement script",
    wave: 1,
    origin: "B"
  }
)

verb(
  "teeburu",
  "stream",
  {
    kind: :stream,
    shape: "stream(conn, sql, params, f) -> nil",
    laterals: %w[cancel deadline error],
    fleet: nil,
    today: "absent",
    meaning: "call f per row from a server cursor",
    wave: 2,
    origin: "B",
    contract: "stream(conn, sql, params, opts) -> nil"
  }
)

verb(
  "teeburu",
  "tables",
  {
    kind: :effect,
    shape: "tables(conn) -> [name]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "the table names visible to the connection",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "update",
  {
    kind: :effect,
    shape: "update(conn, table, key, f) -> row",
    laterals: %w[error idempotent retry],
    fleet: "pleme-database",
    today: "absent",
    meaning: "replace a row with f(old); conflict if it changed",
    wave: 1,
    origin: "B",
    contract: "update(conn, table, key, opts) -> row"
  }
)

verb(
  "teeburu",
  "with_connection",
  {
    kind: :effect,
    shape: "with_connection(pool, f) -> value",
    laterals: %w[cancel error resource],
    fleet: "pleme-database",
    today: "absent",
    meaning: "lend a pooled connection to f and take it back",
    wave: 2,
    origin: "B"
  }
)

verb(
  "teeburu",
  "with_transaction",
  {
    kind: :effect,
    shape: "with_transaction(conn, f, opts) -> value",
    laterals: %w[cancel error resource retry],
    fleet: "pleme-database",
    today: "absent",
    meaning: "run f in one transaction; commit, or roll back on raise",
    wave: 1,
    origin: "B"
  }
)

edge("teeburu::plan", :composes, "kueri::render", "statement text")

edge(
  "teeburu::query",
  :composes,
  "kueri::render",
  "accepts a query value or text"
)

edge("teeburu::connect", :composes, "settei::read", "settings supply the URL")
edge("teeburu::with_transaction", :composes, "teeburu::begin", "opens the unit")
edge("teeburu::schema", :composes, "teeburu::columns", "describes each table")

edge(
  "teeburu::with_transaction",
  :composes,
  "teeburu::commit",
  "on normal return"
)

edge("teeburu::pool", :composes, "teeburu::connect", "holds many connections")
edge("teeburu::copy", :composes, "teeburu::dump", "reads the source table")

edge(
  "teeburu::create",
  :composes,
  "teeburu::execute",
  "insert returning the row"
)

edge("teeburu::delete", :composes, "teeburu::execute", "delete statement")
edge("teeburu::load", :composes, "teeburu::execute", "batched insert")
edge("teeburu::notify", :composes, "teeburu::execute", "sends via a statement")
edge("teeburu::put", :composes, "teeburu::execute", "upsert statement")
edge("teeburu::update", :composes, "teeburu::get", "reads the old row")
edge("teeburu::copy", :composes, "teeburu::load", "writes the target table")
edge("teeburu::connect", :composes, "teeburu::parse", "URL split into parts")
edge("teeburu::update", :composes, "teeburu::put", "writes the new row")
edge("teeburu::alive?", :composes, "teeburu::query", "trivial statement probe")
edge("teeburu::columns", :composes, "teeburu::query", "catalog select")
edge("teeburu::count", :composes, "teeburu::query", "aggregate select")
edge("teeburu::explain", :composes, "teeburu::query", "asks for the plan")
edge("teeburu::get", :composes, "teeburu::query", "select by primary key")

edge(
  "teeburu::list",
  :composes,
  "teeburu::query",
  "select with filter and order"
)

edge("teeburu::tables", :composes, "teeburu::query", "catalog select")

edge(
  "teeburu::with_transaction",
  :composes,
  "teeburu::rollback",
  "on any raise"
)

edge("teeburu::dump", :composes, "teeburu::stream", "rows out one by one")
edge("teeburu::schema", :composes, "teeburu::tables", "names each table")

edge(
  "teeburu::update",
  :composes,
  "teeburu::with_transaction",
  "keeps read and write atomic"
)

edge("teeburu::parse", :guards, "teeburu::connect", "reject a bad URL early")

edge(
  "teeburu::quote",
  :guards,
  "teeburu::query",
  "identifiers are never interpolated raw"
)

edge(
  "teeburu::alive?",
  :guards,
  "teeburu::with_connection",
  "health check before lending"
)

edge(
  "teeburu::rollback",
  :inverse,
  "teeburu::begin",
  "discards what begin opened"
)

edge("teeburu::connect", :inverse, "teeburu::close", "ends the connection")
edge("teeburu::close", :inverse, "teeburu::connect", "ends the connection")

edge(
  "teeburu::delete",
  :inverse,
  "teeburu::create",
  "makes absent what create made"
)

edge(
  "teeburu::create",
  :inverse,
  "teeburu::delete",
  "makes absent what create made"
)

edge("teeburu::load", :inverse, "teeburu::dump", "rows back out of the table")
edge("teeburu::dump", :inverse, "teeburu::load", "rows back out of the table")

edge(
  "teeburu::begin",
  :inverse,
  "teeburu::rollback",
  "discards what begin opened"
)

edge("teeburu::load", :lifts, "teeburu::create", "many rows per round trip")
edge("teeburu::list", :lifts, "teeburu::get", "many rows by filter")
edge("teeburu::stream", :lifts, "teeburu::query", "per-row form with a cursor")
edge("teeburu::quote", :pairs, "kueri::ident", "one identifier rule")
edge("teeburu::connect", :pairs, "teeburu::alive?", "open then probe")
edge("teeburu::commit", :pairs, "teeburu::begin", "close of the unit")
edge("teeburu::tables", :pairs, "teeburu::columns", "names then shapes")
edge("teeburu::schema", :pairs, "teeburu::diff", "live shape against declared")

edge(
  "teeburu::query",
  :pairs,
  "teeburu::execute",
  "rows out versus effect only"
)

edge("teeburu::count", :pairs, "teeburu::list", "number beside rows")
edge("teeburu::listen", :pairs, "teeburu::notify", "receiver and sender")
edge("teeburu::get", :pairs, "teeburu::put", "read and write by key")
edge("teeburu::put", :refines, "teeburu::create", "create that may replace")

edge(
  "teeburu::script",
  :refines,
  "teeburu::execute",
  "many statements, no parameters"
)

edge("teeburu::has?", :refines, "teeburu::get", "existence only")
edge("teeburu::need", :refines, "teeburu::get", "raises when absent")
edge("teeburu::execute", :refines, "teeburu::query", "no rows returned")

edge(
  "teeburu::savepoint",
  :refines,
  "teeburu::with_transaction",
  "nested unit inside one"
)

edge(
  "teeburu::savepoint",
  :requires,
  "teeburu::begin",
  "needs an open transaction"
)

edge("teeburu::plan", :requires, "teeburu::diff", "statements for the changes")

edge(
  "teeburu::with_connection",
  :requires,
  "teeburu::pool",
  "lends from the pool"
)

edge(
  "teeburu::diff",
  :requires,
  "teeburu::schema",
  "compares two live or declared schemas"
)
