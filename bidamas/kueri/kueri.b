use("retsu")
use("moji")
use("shuugou")
use("shisutemu")
use("deeta")
# kueri (クエリ) — queries: analysis is authored in blue, and SQL is only the rendered bridge to DuckDB.
#
# A query is blue DATA: maps built by `q_` constructors (the namespace is flat,
# so every name carries the prefix, as sabi's carry `rs_`). One renderer turns
# a model into SQL text, so quoting, literal typing, clause order and layout
# live in one place, and the same IR always renders the same bytes. SQL is a
# rendered artifact, never the authored source. The one piece of hand-written
# SQL is the escape hatch, `q_raw`, and it must declare the columns it returns.
#
# ## The model
#
#   relations    q_source(opts)  q_ref(x)  q_raw(opts)  q_model(opts)
#   stages       q_select(+ q_as)  q_derive  q_filter  q_group(+ q_agg,
#                q_agg_where)  q_join  q_left_join  q_sort(+ q_desc)  q_limit
#                — and q_then(model, stages) composes by appending data
#   expressions  q_c  q_lit(q_int q_double q_str q_bool q_null)  q_add q_sub
#                q_mul q_div  q_eq q_ne q_lt q_le q_gt q_ge  q_and q_or q_not
#                q_round  q_cast  q_min q_max q_sum q_avg q_count q_count_all
#                q_filtered (FILTER-where)  q_string_agg  q_row_number
#                q_ordered (an order for an order-sensitive aggregate)
#
# A keyword is a column and a string is a value — `q_eq(:enforcement, 0)` —
# the HoneySQL rule. A pipeline is PRQL-shaped: each stage takes a relation to
# a relation. The lowering folds consecutive stages into one SELECT while SQL's
# clause order allows it (a filter becomes WHERE, HAVING or QUALIFY by its
# position) and opens a CTE (`step_1`, `step_2`, …) only when it must.
# A cycle is unrepresentable: a ref holds its upstream VALUE, which has to
# exist before the ref can be built.
#
# ## Dialects are layers
#
# `:core` renders only what is portable across mainstream engines: CTE chains,
# WHERE / GROUP BY / HAVING, `CASE WHEN` conditional aggregates, CAST to the
# standard type names. `:duckdb` inherits every core arm and overrides where
# DuckDB is better: `agg FILTER (WHERE …)`, QUALIFY (one SELECT instead of an
# extra CTE), typed literals `0.9::DOUBLE`, `ORDER BY ALL`, `COPY … TO`, and
# `read_csv(… columns = {…})`. Core SQL is also valid DuckDB, which is how the
# tests prove the two layers compute the same rows. A construct with no core
# form — string_agg, a raw node not vouched portable, a COPY to a file,
# read_csv — has floor :duckdb.
#
# ## Rungs — the blueshift, for SQL
#
# A model declares its posture, `posture: [reach, rigor]`, which mirrors blue's
# (theory/BLUE.md §V.19–V.20):
#
#   reach  :portable | :duckdb — like waku's REACH, what a model may NAME.
#          :portable is the narrower frame. Every construct has a floor, and a
#          floor above the declared reach is refused and named on both sides,
#          like a bidama posture conflict.
#   rigor  :loose | :locked — like the RIGOR rungs. :loose is `annotated`: a
#          contract that IS declared is still checked, on that model only.
#          :locked is `checked`: a contract is required, and the determinism
#          rules hold.
#
# The default is [:duckdb, :loose], blue's own default: declare nothing and pay
# nothing. `narrow` cannot widen: each stage re-checks what it receives, so
# `q_render` re-runs `q_check` and then the dialect floor, and the renderer's
# own arms refuse a DuckDB-only node in :core — a :core rendering cannot
# contain a DuckDB form whichever door it came through. `q_shift(model)`
# answers blue shift's second question: the lowest reach that holds this model,
# and which constructs hold it there.
#
# ## Tiers — what throws, and what is only rendered
#
# THROWS, as `throw(error(:kueri_…, why))`, never a warning:
#   :kueri_reach     a construct above the declared reach
#   :kueri_locked    a locked model with no contract, an order-sensitive
#                    aggregate or window with no order, a limit with no sort
#                    right before it, or an upstream whose columns are unknown
#   :kueri_contract  a declared contract that differs from the inferred output
#   :kueri_shape     an unknown column (where the schema is known), an aggregate
#                    outside a group, a sort a later stage discards, a malformed
#                    node — refused where it is built when it is local
#   :kueri_dialect   rendering a construct below its floor
# RENDERED, by construction: a locked model's output is totally ordered —
# ORDER BY ALL in DuckDB, the contract's columns in core — so there is nothing
# to refuse.
# NOT CHECKED at M0: column TYPES and nullability (M1 binds each model against
# DuckDB with DESCRIBE rather than re-deriving DuckDB's type rules), a float
# SUM's order sensitivity (it needs types, then fsum), and whether a raw node's
# SQL returns the columns it declares or is deterministic: raw is trusted.
# `q_refusals` returns violations as data ([kind, why], read with
# q_refusal_kind / q_refusal_why); `q_check` throws them.
#
# ## Around the query
#
# q_deps / q_closure walk ref nodes into the DAG, with no parsing.
# q_render_load binds a source to a delimited file with its declared columns
# (the sniffer never decides a contract). q_render_materialize writes a model
# out. q_write_sql writes the rendered statement with a @generated header, for
# a consumer to commit and gate fresh like blue's generate(...) files.
# q_duckdb is the process seam to the `duckdb` binary (a program, not a linked
# library, so there is no C to contain; the Bluefile declares it with
# `tool("duckdb")`): a failure is [:error, stderr] and an empty result is
# [:ok, []], never confused.
#
# Design: the SQL-frameworks survey in the makoto lab (§5 sketch; this is its
# M0). Near-misses, deliberately not merged: dialeto's relational sub-IR
# (theory/DIALETO.md — design-tier, no types to compare) and sql-synthesizer
# (a Rust DDL AST with no SELECT algebra).

# ── names and literals ─────────────────────────────────────────────────────

# A name as text: a keyword's name, or the string itself.
def q_name(x)
  if keyword?(x)
    to_s(x)
  else
    x
  end
end

# Words an engine will not read as a bare identifier: SQL's reserved words and
# DuckDB's own (qualify, pivot, asof, …). A name among them is quoted.
def q_reserved_words()
  ["all", "analyse", "analyze", "and", "anti", "any", "array", "as", "asc", "asof", "asymmetric", "between", "both", "by", "case", "cast", "check", "collate", "column", "constraint", "create", "cross", "current_catalog", "current_date", "current_role", "current_time", "current_timestamp", "current_user", "default", "deferrable", "desc", "distinct", "do", "else", "end", "except", "exists", "false", "fetch", "filter", "for", "foreign", "from", "full", "grant", "group", "having", "ilike", "in", "initially", "inner", "intersect", "into", "is", "isnull", "join", "lateral", "leading", "left", "like", "limit", "localtime", "localtimestamp", "natural", "not", "notnull", "null", "offset", "on", "only", "or", "order", "outer", "over", "partition", "pivot", "placing", "positional", "primary", "qualify", "range", "references", "returning", "right", "rows", "select", "semi", "session_user", "similar", "some", "symmetric", "table", "then", "to", "trailing", "true", "union", "unique", "unpivot", "user", "using", "values", "variadic", "when", "where", "window", "with"]
end

# Lower-case ASCII, digits and underscore, not starting with a digit, and not
# reserved. Anything else is quoted, because engines fold unquoted case
# differently and a quoted name means the same thing everywhere.
def q_bare_ident?(s)
  made_of(s, "abcdefghijklmnopqrstuvwxyz_0123456789") && made_of(char_at(s, 0), "abcdefghijklmnopqrstuvwxyz_") && (contains(q_reserved_words(), s) == false)
end

# An identifier as SQL: bare when safe, otherwise double-quoted with any
# embedded quote doubled.
def q_ident(name)
  s = q_name(name)
  if q_bare_ident?(s)
    s
  else
    "\"#{replace(s, "\"", "\"\"")}\""
  end
end

# A string value as a SQL literal: single quotes, embedded quotes doubled.
def q_quote_str(s)
  "'#{replace(s, "'", "''")}'"
end

# A float's digits, always with a decimal point: to_s(1.0) is "1", which an
# engine would read as an INTEGER.
def q_float_text(x)
  s = to_s(x)
  if contains?(s, ".") || contains?(s, "e") || contains?(s, "E")
    s
  else
    "#{s}.0"
  end
end

# ── types ──────────────────────────────────────────────────────────────────

# The closed set of column types a contract or a source may declare.
def q_types()
  [:bigint, :integer, :double, :varchar, :boolean, :date]
end

def q_type(t)
  if contains(q_types(), t) == false
    throw(error(:kueri_shape, "unknown column type #{to_s(t)}; a type is one of #{join(map(fn(x) to_s(x) end, q_types()), ", ")}"))
  end
  t
end

# A type's name in a dialect. DOUBLE is DuckDB's; the standard spells it
# DOUBLE PRECISION, which DuckDB also reads.
def q_type_sql(t, dialect)
  if t == :double
    if dialect == :duckdb
      "DOUBLE"
    else
      "DOUBLE PRECISION"
    end
  else
    upcase(to_s(t))
  end
end

# A declared column: a source's input or a model's contract.
def q_col(name, t)
  {kind: :coldef, name: q_name(name), type: q_type(t)}
end

def q_col_names(cols)
  map(fn(c) get(c, :name) end, as_list(cols))
end

# ── expressions ────────────────────────────────────────────────────────────

# A column reference.
def q_c(name)
  {kind: :col, name: q_name(name)}
end

def q_int(n)
  if integer?(n) == false
    throw(error(:kueri_shape, "q_int takes an integer"))
  end
  {kind: :lit, type: :int, value: n}
end

# A DOUBLE literal, typed on purpose: DuckDB reads a bare 1.0 as DECIMAL(2,1).
def q_double(x)
  if number?(x) == false
    throw(error(:kueri_shape, "q_double takes a number"))
  end
  # NaN and the infinities have no SQL literal; x - x is 0 only when x is finite.
  if (x - x < 1) == false
    throw(error(:kueri_shape, "q_double takes a finite number"))
  end
  {kind: :lit, type: :double, value: x}
end

def q_str(s)
  {kind: :lit, type: :str, value: s}
end

def q_bool(b)
  {kind: :lit, type: :bool, value: b}
end

def q_null()
  {kind: :lit, type: :null, value: nil}
end

def q_value?(x)
  number?(x) || string?(x) || boolean?(x) || null?(x)
end

# A blue value as a literal, typed by what it is: an int stays an INTEGER and a
# float becomes a DOUBLE, never the DECIMAL an untyped 1.0 would be.
def q_lit(v)
  if integer?(v)
    q_int(v)
  elsif number?(v)
    q_double(v)
  elsif string?(v)
    q_str(v)
  elsif boolean?(v)
    q_bool(v)
  elsif null?(v)
    q_null()
  else
    throw(error(:kueri_shape, "q_lit takes a number, string, boolean or nil"))
  end
end

# Anything in expression position: a keyword is a column, a value is a
# literal, and a node is itself.
def q_expr(x)
  if keyword?(x)
    q_c(x)
  elsif q_value?(x)
    q_lit(x)
  else
    x
  end
end

# A binary operator. `prec` orders them for the renderer's parentheses:
# OR 1, AND 2, NOT 3, comparisons 4, + - 5, * / 6.
def q_op(op, prec, a, b)
  {kind: :op, op: op, prec: prec, args: [q_expr(a), q_expr(b)]}
end

def q_add(a, b)
  q_op("+", 5, a, b)
end

def q_sub(a, b)
  q_op("-", 5, a, b)
end

def q_mul(a, b)
  q_op("*", 6, a, b)
end

def q_div(a, b)
  q_op("/", 6, a, b)
end

def q_eq(a, b)
  q_op("=", 4, a, b)
end

def q_ne(a, b)
  q_op("<>", 4, a, b)
end

def q_lt(a, b)
  q_op("<", 4, a, b)
end

def q_le(a, b)
  q_op("<=", 4, a, b)
end

def q_gt(a, b)
  q_op(">", 4, a, b)
end

def q_ge(a, b)
  q_op(">=", 4, a, b)
end

def q_and(a, b)
  q_op("AND", 2, a, b)
end

def q_or(a, b)
  q_op("OR", 1, a, b)
end

def q_not(a)
  {kind: :not, args: [q_expr(a)]}
end

def q_round(x, digits)
  {kind: :fn, name: "round", args: [q_expr(x), q_int(digits)]}
end

def q_cast(x, t)
  {kind: :cast, type: q_type(t), args: [q_expr(x)]}
end

# ── aggregates and windows ─────────────────────────────────────────────────

def q_agg_fn(f, args)
  {kind: :agg, fn: f, args: args, where: nil, order: []}
end

def q_min(x)
  q_agg_fn("min", [q_expr(x)])
end

def q_max(x)
  q_agg_fn("max", [q_expr(x)])
end

def q_sum(x)
  q_agg_fn("sum", [q_expr(x)])
end

def q_avg(x)
  q_agg_fn("avg", [q_expr(x)])
end

def q_count(x)
  q_agg_fn("count", [q_expr(x)])
end

# count(*).
def q_count_all()
  q_agg_fn("count", [])
end

# Joins the values with `sep`. Order-sensitive, and with no core form: MySQL,
# SQL Server and Snowflake each spell it differently.
def q_string_agg(x, sep)
  q_agg_fn("string_agg", [q_expr(x), q_str(sep)])
end

# row_number() OVER (PARTITION BY … ORDER BY …).
def q_row_number(partition, order)
  {kind: :win, fn: "row_number", args: [], partition: map(fn(p) q_name(p) end, as_list(partition)), order: map(fn(k) q_key(k) end, as_list(order))}
end

# An aggregate over only the rows where `pred` holds: FILTER (WHERE …) in
# DuckDB, CASE WHEN inside the aggregate in core.
def q_filtered(agg, pred)
  if get(agg, :kind) != :agg
    throw(error(:kueri_shape, "q_filtered takes an aggregate"))
  end
  assoc(agg, :where, q_expr(pred))
end

# An order for an order-sensitive aggregate or window.
def q_ordered(node, keys)
  if (get(node, :kind) != :agg) && (get(node, :kind) != :win)
    throw(error(:kueri_shape, "q_ordered takes an aggregate or a window"))
  end
  assoc(node, :order, map(fn(k) q_key(k) end, keys))
end

# Functions whose result depends on the order rows arrive in.
def q_order_sensitive_fns()
  ["string_agg", "row_number"]
end

# Functions with no core form.
def q_duckdb_only_fns()
  ["string_agg"]
end

# ── sort keys ──────────────────────────────────────────────────────────────

def q_key(k)
  if keyword?(k) || string?(k)
    {kind: :key, name: q_name(k), desc: false}
  else
    k
  end
end

def q_desc(name)
  {kind: :key, name: q_name(name), desc: true}
end

def q_key_names(keys)
  map(fn(k) get(k, :name) end, as_list(keys))
end

# ── relations ──────────────────────────────────────────────────────────────

# A delimited input file with DECLARED columns, in file order: read_csv maps
# them by position and never sniffs. opts: name, file, columns (q_col list),
# delim (:tab, the default, or :comma).
def q_source(opts)
  cols = as_list(get(opts, :columns))
  if is_empty(cols)
    throw(error(:kueri_shape, "source #{q_name(get(opts, :name))} declares no columns; a source states its schema, the sniffer never does"))
  end
  delim = get(opts, :delim)
  if delim == nil
    delim = :tab
  end
  if contains([:tab, :comma], delim) == false
    throw(error(:kueri_shape, "a source's delim is :tab or :comma"))
  end
  {kind: :source, name: q_name(get(opts, :name)), file: get(opts, :file), columns: cols, delim: delim}
end

# The escape hatch: hand-written SQL, which must declare the columns it
# returns. Its dialect is :duckdb unless the author vouches `dialect: :core` —
# kueri cannot read it, so it cannot prove it portable. opts: name, sql,
# columns (q_col list), dialect.
def q_raw(opts)
  cols = as_list(get(opts, :columns))
  if is_empty(cols)
    throw(error(:kueri_shape, "raw node #{q_name(get(opts, :name))} declares no columns; the escape hatch must say what it returns"))
  end
  d = get(opts, :dialect)
  if d == nil
    d = :duckdb
  end
  if contains([:core, :duckdb], d) == false
    throw(error(:kueri_shape, "a raw node's dialect is :core or :duckdb"))
  end
  {kind: :raw, name: q_name(get(opts, :name)), sql: get(opts, :sql), columns: cols, dialect: d}
end

# A reference to an upstream source or model. The DAG is these nodes.
def q_ref(x)
  k = get(x, :kind)
  if (k != :source) && (k != :model)
    throw(error(:kueri_shape, "q_ref takes a source or a model"))
  end
  {kind: :ref, target: x}
end

# A relation in from/join position: a source or model is referenced, a ref or
# raw node is itself.
def q_rel(x)
  k = get(x, :kind)
  if (k == :source) || (k == :model)
    q_ref(x)
  elsif (k == :ref) || (k == :raw)
    x
  else
    throw(error(:kueri_shape, "a relation is a source, model, ref or raw node"))
  end
end

def q_rel_name(rel)
  if get(rel, :kind) == :raw
    get(rel, :name)
  else
    get(get(rel, :target), :name)
  end
end

# ── posture ────────────────────────────────────────────────────────────────

def q_reach_words()
  [:portable, :duckdb]
end

def q_rigor_words()
  [:loose, :locked]
end

# The posture a model declares, as {reach, rigor}. Unknown words and two words
# on one axis are refused where the model is built.
def q_posture_of(words)
  ws = as_list(words)
  bad = filter(fn(w) (contains(q_reach_words(), w) || contains(q_rigor_words(), w)) == false end, ws)
  if is_empty(bad) == false
    throw(error(:kueri_shape, "unknown posture word #{to_s(first(bad))}; a posture takes a reach (:portable, :duckdb) and a rigor (:loose, :locked)"))
  end
  reach = filter(fn(w) contains(q_reach_words(), w) end, ws)
  rigor = filter(fn(w) contains(q_rigor_words(), w) end, ws)
  if (size(reach) > 1) || (size(rigor) > 1)
    throw(error(:kueri_shape, "a posture names one reach and one rigor"))
  end
  r = first(reach)
  if r == nil
    r = :duckdb
  end
  g = first(rigor)
  if g == nil
    g = :loose
  end
  {reach: r, rigor: g}
end

# The dialect a reach allows: :portable holds a model to :core.
def q_reach_dialect(reach)
  if reach == :portable
    :core
  else
    :duckdb
  end
end

# ── models and stages ──────────────────────────────────────────────────────

# A model is one SELECT with a name. opts: name, from, pipeline, posture,
# contract (q_col list), materialize (:parquet, :csv or :table; optional).
def q_model(opts)
  m = get(opts, :materialize)
  if contains([nil, :parquet, :csv, :table], m) == false
    throw(error(:kueri_shape, "materialize is :parquet, :csv or :table"))
  end
  if get(opts, :from) == nil
    throw(error(:kueri_shape, "model #{q_name(get(opts, :name))} reads from nothing"))
  end
  {kind: :model, name: q_name(get(opts, :name)), from: q_rel(get(opts, :from)), pipeline: as_list(get(opts, :pipeline)), posture: q_posture_of(get(opts, :posture)), contract: as_list(get(opts, :contract)), materialize: m}
end

# Composition by data: the same model with more stages after its own.
def q_then(model, stages)
  assoc(model, :pipeline, concat_lists(get(model, :pipeline), stages))
end

# A named output: a select item or a group aggregate.
def q_as(name, expr)
  {kind: :as, name: q_name(name), expr: q_expr(expr)}
end

def q_agg(name, expr)
  q_as(name, expr)
end

# An aggregate over only the rows where `pred` holds, named.
def q_agg_where(name, agg, pred)
  q_as(name, q_filtered(agg, pred))
end

def q_item(i)
  if keyword?(i) || string?(i)
    q_as(i, q_c(i))
  else
    i
  end
end

# Keep these columns (keywords) and computed ones (q_as), in this order.
def q_select(items)
  {kind: :select, items: map(fn(i) q_item(i) end, items)}
end

# Add one computed column; every row stays.
def q_derive(name, expr)
  {kind: :derive, name: q_name(name), expr: q_expr(expr)}
end

# Keep the rows where `pred` holds.
def q_filter(pred)
  {kind: :filter, pred: q_expr(pred)}
end

# One row per distinct key; `aggs` are q_agg / q_agg_where outputs.
def q_group(keys, aggs)
  {kind: :group, keys: map(fn(k) q_name(k) end, as_list(keys)), aggs: as_list(aggs)}
end

# JOIN … USING (keys): the keys appear once, then the left's other columns,
# then the right's.
def q_join(rel, keys)
  {kind: :join, how: :inner, rel: q_rel(rel), keys: map(fn(k) q_name(k) end, keys)}
end

def q_left_join(rel, keys)
  {kind: :join, how: :left, rel: q_rel(rel), keys: map(fn(k) q_name(k) end, keys)}
end

def q_sort(keys)
  {kind: :sort, keys: map(fn(k) q_key(k) end, keys)}
end

def q_limit(n)
  if (integer?(n) == false) || (n < 0)
    throw(error(:kueri_shape, "q_limit takes a count of zero or more"))
  end
  {kind: :limit, n: n}
end

def q_stage_exprs(stage)
  k = get(stage, :kind)
  if k == :filter
    [get(stage, :pred)]
  elsif k == :derive
    [get(stage, :expr)]
  elsif k == :select
    map(fn(i) get(i, :expr) end, get(stage, :items))
  elsif k == :group
    map(fn(a) get(a, :expr) end, get(stage, :aggs))
  else
    []
  end
end

def q_label(i, stage)
  "stage #{to_s(i + 1)} (#{to_s(get(stage, :kind))})"
end

# ── walking expressions ────────────────────────────────────────────────────

def q_kids(e)
  if (get(e, :kind) == :agg) && (get(e, :where) != nil)
    push(as_list(get(e, :args)), get(e, :where))
  else
    as_list(get(e, :args))
  end
end

# Every node of an expression, the root first.
def q_nodes(e)
  cons(e, flat_map(fn(c) q_nodes(c) end, q_kids(e)))
end

def q_nodes_of(e, kind)
  filter(fn(n) get(n, :kind) == kind end, q_nodes(e))
end

def q_node_refs(n)
  k = get(n, :kind)
  if k == :col
    [get(n, :name)]
  elsif k == :agg
    q_key_names(get(n, :order))
  elsif k == :win
    concat_lists(get(n, :partition), q_key_names(get(n, :order)))
  else
    []
  end
end

# The column names an expression reads.
def q_refs(e)
  unique(flat_map(fn(n) q_node_refs(n) end, q_nodes(e)))
end

def q_outside_aggs(e)
  if get(e, :kind) == :agg
    []
  else
    cons(e, flat_map(fn(c) q_outside_aggs(c) end, q_kids(e)))
  end
end

# The column names read OUTSIDE any aggregate — in a group, each must be a key.
def q_bare_refs(e)
  unique(flat_map(fn(n) q_node_refs(n) end, q_outside_aggs(e)))
end

def q_has?(e, kind)
  is_empty(q_nodes_of(e, kind)) == false
end

def q_nested_agg?(e)
  is_empty(filter(fn(a) is_empty(flat_map(fn(c) q_nodes_of(c, :agg) end, q_kids(a))) == false end, q_nodes_of(e, :agg))) == false
end

# ── refusals ───────────────────────────────────────────────────────────────

def q_refusal_kind(r)
  first(r)
end

def q_refusal_why(r)
  last(r)
end

def q_refusal_kinds(model)
  map(fn(r) q_refusal_kind(r) end, q_refusals(model))
end

def q_unknown_refusals(names, cols, where)
  if cols == nil
    []
  else
    missing = as_list(difference(unique(names), cols))
    if is_empty(missing)
      []
    else
      [[:kueri_shape, "#{where}: unknown column #{join(missing, ", ")}; the input has #{join(cols, ", ")}"]]
    end
  end
end

def q_dup_refusals(names, where)
  if size(unique(names)) == size(names)
    []
  else
    [[:kueri_shape, "#{where}: an output name repeats among #{join(names, ", ")}"]]
  end
end

# What no expression may hold outside a group: an aggregate. And the order
# rules every stage shares.
def q_expr_refusals(e, where, aggs_allowed, windows_allowed)
  a = if (aggs_allowed == false) && q_has?(e, :agg)
    [[:kueri_shape, "#{where}: an aggregate outside a group; aggregate in a group stage, then use its name"]]
  else
    []
  end
  w = if (windows_allowed == false) && q_has?(e, :win)
    [[:kueri_shape, "#{where}: a window here; derive it first, then use its name"]]
  else
    []
  end
  wasted = filter(fn(n) (is_empty(get(n, :order)) == false) && (contains(q_order_sensitive_fns(), get(n, :fn)) == false) end, concat_lists(q_nodes_of(e, :agg), q_nodes_of(e, :win)))
  o = map(fn(n) [:kueri_shape, "#{where}: an order on #{get(n, :fn)} changes nothing; only #{join(q_order_sensitive_fns(), " and ")} read one"] end, wasted)
  concat_lists(a, concat_lists(w, o))
end

def q_group_item_refusals(item, keys, where)
  e = get(item, :expr)
  n = get(item, :name)
  none = if q_has?(e, :agg)
    []
  else
    [[:kueri_shape, "#{where}: #{n} aggregates nothing; a plain column belongs in the keys"]]
  end
  nested = if q_nested_agg?(e)
    [[:kueri_shape, "#{where}: #{n} nests an aggregate inside an aggregate"]]
  else
    []
  end
  loose = as_list(difference(q_bare_refs(e), keys))
  outside = if is_empty(loose)
    []
  else
    [[:kueri_shape, "#{where}: #{n} reads #{join(loose, ", ")} outside an aggregate, and it is not a key"]]
  end
  concat_lists(none, concat_lists(nested, concat_lists(outside, q_expr_refusals(e, where, true, false))))
end

def q_stage_refusals(stage, cols, where, next_kind)
  k = get(stage, :kind)
  if k == :filter
    e = get(stage, :pred)
    concat_lists(q_expr_refusals(e, where, false, false), q_unknown_refusals(q_refs(e), cols, where))
  elsif k == :derive
    e = get(stage, :expr)
    dup = if (cols != nil) && contains(cols, get(stage, :name))
      [[:kueri_shape, "#{where}: #{get(stage, :name)} is already a column"]]
    else
      []
    end
    concat_lists(dup, concat_lists(q_expr_refusals(e, where, false, true), q_unknown_refusals(q_refs(e), cols, where)))
  elsif k == :select
    items = get(stage, :items)
    per = flat_map(fn(i) concat_lists(q_expr_refusals(get(i, :expr), where, false, false), q_unknown_refusals(q_refs(get(i, :expr)), cols, where)) end, items)
    concat_lists(per, q_dup_refusals(map(fn(i) get(i, :name) end, items), where))
  elsif k == :group
    keys = get(stage, :keys)
    aggs = get(stage, :aggs)
    empty = if is_empty(keys) && is_empty(aggs)
      [[:kueri_shape, "#{where}: a group with no keys and no aggregates"]]
    else
      []
    end
    reads = concat_lists(keys, flat_map(fn(a) q_refs(get(a, :expr)) end, aggs))
    per = flat_map(fn(a) q_group_item_refusals(a, keys, where) end, aggs)
    concat_lists(empty, concat_lists(q_unknown_refusals(reads, cols, where), concat_lists(q_dup_refusals(concat_lists(keys, map(fn(a) get(a, :name) end, aggs)), where), per)))
  elsif k == :join
    q_join_refusals(stage, cols, where)
  elsif k == :sort
    discarded = if (next_kind != nil) && (next_kind != :limit)
      [[:kueri_shape, "#{where}: the next stage (#{to_s(next_kind)}) discards this order; sort last, or just before a limit"]]
    else
      []
    end
    concat_lists(discarded, q_unknown_refusals(q_key_names(get(stage, :keys)), cols, where))
  else
    []
  end
end

def q_join_refusals(stage, cols, where)
  keys = get(stage, :keys)
  rc = q_rel_columns(get(stage, :rel))
  none = if is_empty(keys)
    [[:kueri_shape, "#{where}: a join needs at least one USING key"]]
  else
    []
  end
  left = q_unknown_refusals(keys, cols, where)
  right = q_unknown_refusals(keys, rc, "#{where} (right side)")
  both = if (cols == nil) || (rc == nil)
    []
  else
    as_list(difference(intersection(cols, rc), keys))
  end
  clash = if is_empty(both)
    []
  else
    [[:kueri_shape, "#{where}: #{join(both, ", ")} on both sides of the join; rename it or make it a key"]]
  end
  concat_lists(none, concat_lists(left, concat_lists(right, clash)))
end

# The columns a stage returns, or nil when its input's are unknown.
def q_stage_output(stage, cols)
  k = get(stage, :kind)
  if k == :derive
    if cols == nil
      nil
    else
      push(cols, get(stage, :name))
    end
  elsif k == :select
    map(fn(i) get(i, :name) end, get(stage, :items))
  elsif k == :group
    concat_lists(get(stage, :keys), map(fn(a) get(a, :name) end, get(stage, :aggs)))
  elsif k == :join
    rc = q_rel_columns(get(stage, :rel))
    if (cols == nil) || (rc == nil)
      nil
    else
      keys = get(stage, :keys)
      concat_lists(keys, concat_lists(as_list(difference(cols, keys)), as_list(difference(rc, keys))))
    end
  else
    cols
  end
end

def q_next_kind(stages, i)
  if i + 1 < size(stages)
    get(nth(i + 1, stages), :kind)
  else
    nil
  end
end

# Thread the schema through the pipeline: {cols, refusals}.
def q_walk(model)
  stages = get(model, :pipeline)
  start = {cols: q_rel_columns(get(model, :from)), refusals: []}
  reduce(fn(acc, ix) q_walk_stage(acc, first(ix), last(ix), q_next_kind(stages, first(ix))) end, start, enumerate(stages))
end

def q_walk_stage(acc, i, stage, next_kind)
  cols = get(acc, :cols)
  found = q_stage_refusals(stage, cols, q_label(i, stage), next_kind)
  {cols: q_stage_output(stage, cols), refusals: concat_lists(get(acc, :refusals), found)}
end

# The column names a model returns, inferred through its pipeline; nil when an
# upstream's columns are unknown.
def q_output(model)
  get(q_walk(model), :cols)
end

# What a downstream model sees: the contract when declared, the inference
# otherwise.
def q_model_columns(model)
  cn = q_col_names(get(model, :contract))
  if is_empty(cn)
    q_output(model)
  else
    cn
  end
end

def q_rel_columns(rel)
  if get(rel, :kind) == :raw
    q_col_names(get(rel, :columns))
  else
    t = get(rel, :target)
    if get(t, :kind) == :source
      q_col_names(get(t, :columns))
    else
      q_model_columns(t)
    end
  end
end

# Constructs with no core form, as [what, where].
def q_duckdb_uses(model)
  from_uses = q_rel_uses(get(model, :from), "the from relation")
  stage_uses = flat_map(fn(ix) q_stage_uses(last(ix), q_label(first(ix), last(ix))) end, enumerate(get(model, :pipeline)))
  concat_lists(from_uses, stage_uses)
end

def q_stage_uses(stage, where)
  nodes = flat_map(fn(e) q_nodes(e) end, q_stage_exprs(stage))
  only = filter(fn(n) (get(n, :kind) == :agg) && contains(q_duckdb_only_fns(), get(n, :fn)) end, nodes)
  uses = map(fn(n) [get(n, :fn), where] end, only)
  if get(stage, :kind) == :join
    concat_lists(uses, q_rel_uses(get(stage, :rel), where))
  else
    uses
  end
end

def q_rel_uses(rel, where)
  if (get(rel, :kind) == :raw) && (get(rel, :dialect) == :duckdb)
    [["raw node #{get(rel, :name)}", where]]
  else
    []
  end
end

def q_reach_refusals(model)
  reach = get(get(model, :posture), :reach)
  if q_reach_dialect(reach) == :duckdb
    []
  else
    map(fn(u) [:kueri_reach, "model #{get(model, :name)} is held at :#{to_s(reach)}, but #{first(u)} at #{last(u)} has no core form (its floor is :duckdb)"] end, q_duckdb_uses(model))
  end
end

def q_contract_refusals(model, out)
  cn = q_col_names(get(model, :contract))
  if is_empty(cn) || (out == nil) || equal_lists(cn, out)
    []
  else
    [[:kueri_contract, "model #{get(model, :name)} declares #{join(cn, ", ")} but returns #{join(out, ", ")}"]]
  end
end

def q_locked_refusals(model, out)
  name = get(model, :name)
  stages = get(model, :pipeline)
  contract = if is_empty(get(model, :contract))
    [[:kueri_locked, "model #{name} is :locked and declares no contract; a locked model states the columns it returns"]]
  elsif out == nil
    [[:kueri_locked, "model #{name} is :locked, but the columns upstream of it are not declared, so its contract cannot be verified"]]
  else
    []
  end
  unordered = flat_map(fn(ix) map(fn(n) [:kueri_locked, "#{q_label(first(ix), last(ix))}: #{get(n, :fn)} with no order is not deterministic; give it one with q_ordered"] end, filter(fn(n) contains(q_order_sensitive_fns(), get(n, :fn)) && is_empty(get(n, :order)) end, flat_map(fn(e) q_nodes(e) end, q_stage_exprs(last(ix))))) end, enumerate(stages))
  limits = flat_map(fn(ix) q_locked_limit(stages, first(ix), last(ix)) end, enumerate(stages))
  concat_lists(contract, concat_lists(unordered, limits))
end

def q_locked_limit(stages, i, stage)
  if get(stage, :kind) != :limit
    []
  elsif (i > 0) && (get(nth(i - 1, stages), :kind) == :sort)
    []
  else
    [[:kueri_locked, "#{q_label(i, stage)}: a limit with no sort right before it keeps arbitrary rows"]]
  end
end

# Every violation, as data: [kind, why]. Empty when the model holds.
def q_refusals(model)
  walked = q_walk(model)
  out = get(walked, :cols)
  rigor = if get(get(model, :posture), :rigor) == :locked
    q_locked_refusals(model, out)
  else
    []
  end
  concat_lists(get(walked, :refusals), concat_lists(q_reach_refusals(model), concat_lists(q_contract_refusals(model, out), rigor)))
end

def q_refuse(refusals)
  if is_empty(refusals) == false
    throw(error(q_refusal_kind(first(refusals)), join(map(fn(r) q_refusal_why(r) end, refusals), "; ")))
  end
  nil
end

# The model, or a thrown error naming every violation (its kind is the first's).
def q_check(model)
  q_refuse(q_refusals(model))
  model
end

def q_dialect_refusals(model, dialect)
  if dialect == :duckdb
    []
  else
    map(fn(u) [:kueri_dialect, "#{first(u)} at #{last(u)} has no core form; render model #{get(model, :name)} with :duckdb"] end, q_duckdb_uses(model))
  end
end

# blue shift's two questions for a model: the lowest reach that holds it, and
# what holds it there.
def q_shift(model)
  uses = q_duckdb_uses(model)
  needs = if is_empty(uses)
    :portable
  else
    :duckdb
  end
  {needs: needs, held_by: map(fn(u) "#{first(u)} at #{last(u)}" end, uses)}
end

# ── lowering: stages into SELECT blocks ────────────────────────────────────
#
# A block is one SELECT. Its phase is the last clause filled, in SQL's order:
# 1 FROM/JOIN, 2 WHERE, 3 GROUP BY, 4 HAVING, 5 the select list, 6 QUALIFY,
# 7 ORDER BY, 8 LIMIT. A stage joins the current block while its clause comes
# later; otherwise the block closes as a CTE and a new one reads from it.
# Two moves save a CTE and are exact, not heuristic: a join after a WHERE
# (the WHERE can only name the left side's columns, and a clash across the
# join is refused), and a filter after row-wise derives that it does not read
# (moving a filter before a scalar changes nothing; before a window it would,
# so a block with a window never takes one).

def q_block(from)
  {from: from, joins: [], where: [], grouped: false, keys: [], aggs: [], having: [], items: nil, derives: [], window: false, qualify: [], order: [], order_all: false, limit: nil, phase: 0}
end

def q_derived_names(b)
  map(fn(d) get(d, :name) end, get(b, :derives))
end

def q_fits?(b, stage, dialect)
  k = get(stage, :kind)
  p = get(b, :phase)
  if k == :join
    p <= 2
  elsif k == :filter
    if p <= 4
      true
    elsif q_pushable?(b, stage)
      true
    else
      (p <= 6) && get(b, :window) && (dialect == :duckdb)
    end
  elsif k == :group
    p <= 2
  elsif k == :derive
    if p <= 2
      true
    else
      (p == 5) && (get(b, :items) == nil) && is_empty(as_list(intersection(q_refs(get(stage, :expr)), q_derived_names(b))))
    end
  elsif k == :select
    p <= 2
  elsif k == :sort
    p <= 6
  else
    p <= 7
  end
end

def q_set(b, key, value, phase)
  assoc(assoc(b, key, value), :phase, phase)
end

# A filter that can join the WHERE of a block whose select list holds only
# row-wise derives it does not read.
def q_pushable?(b, stage)
  (get(b, :phase) == 5) && (get(b, :items) == nil) && (get(b, :grouped) == false) && (get(b, :window) == false) && is_empty(as_list(intersection(q_refs(get(stage, :pred)), q_derived_names(b))))
end

# A filter after a group reads the aggregates by name; HAVING needs them
# spelled out.
def q_subst(e, items)
  k = get(e, :kind)
  if k == :col
    hit = find_first(fn(i) get(i, :name) == get(e, :name) end, items)
    if hit == nil
      e
    else
      get(hit, :expr)
    end
  elsif (k == :agg) || (k == :win) || (k == :lit)
    e
  else
    assoc(e, :args, map(fn(a) q_subst(a, items) end, get(e, :args)))
  end
end

def q_into(b, stage, dialect)
  k = get(stage, :kind)
  p = get(b, :phase)
  if k == :join
    q_set(b, :joins, push(get(b, :joins), stage), max(p, 1))
  elsif k == :filter
    if p <= 2
      q_set(b, :where, push(get(b, :where), get(stage, :pred)), 2)
    elsif q_pushable?(b, stage)
      assoc(b, :where, push(get(b, :where), get(stage, :pred)))
    elsif p <= 4
      q_set(b, :having, push(get(b, :having), q_subst(get(stage, :pred), get(b, :aggs))), 4)
    else
      q_set(b, :qualify, push(get(b, :qualify), get(stage, :pred)), 6)
    end
  elsif k == :group
    q_set(assoc(assoc(b, :grouped, true), :keys, get(stage, :keys)), :aggs, get(stage, :aggs), 3)
  elsif k == :derive
    d = q_as(get(stage, :name), get(stage, :expr))
    q_set(assoc(b, :window, get(b, :window) || q_has?(get(stage, :expr), :win)), :derives, push(get(b, :derives), d), 5)
  elsif k == :select
    q_set(b, :items, get(stage, :items), 5)
  elsif k == :sort
    q_set(b, :order, get(stage, :keys), 7)
  else
    q_set(b, :limit, get(stage, :n), 8)
  end
end

def q_lower_stage(acc, stage, dialect)
  b = get(acc, :cur)
  if q_fits?(b, stage, dialect)
    assoc(acc, :cur, q_into(b, stage, dialect))
  else
    name = "step_#{to_s(size(get(acc, :done)) + 1)}"
    {done: push(get(acc, :done), [name, b]), cur: q_into(q_block(name), stage, dialect)}
  end
end

# The pipeline as closed CTE blocks ([name, block] pairs) and a final block.
def q_lower(model, dialect)
  start = {done: [], cur: q_block(q_rel_name(get(model, :from)))}
  reduce(fn(acc, s) q_lower_stage(acc, s, dialect) end, start, get(model, :pipeline))
end

# A locked model's output order is made total: its own keys, then every other
# contract column. In DuckDB, when that is exactly the column order, it is
# ORDER BY ALL.
def q_lock_order(model, b, dialect)
  if get(get(model, :posture), :rigor) != :locked
    b
  else
    keys = get(b, :order)
    have = q_key_names(keys)
    extra = map(fn(n) q_key(n) end, filter(fn(n) contains(have, n) == false end, q_col_names(get(model, :contract))))
    total = concat_lists(keys, extra)
    all_asc = is_empty(filter(fn(k) get(k, :desc) end, total))
    assoc(assoc(b, :order, total), :order_all, (dialect == :duckdb) && all_asc && equal_lists(q_key_names(total), q_col_names(get(model, :contract))))
  end
end

# ── rendering ──────────────────────────────────────────────────────────────

def q_prec(e)
  k = get(e, :kind)
  if k == :op
    get(e, :prec)
  elsif k == :not
    3
  else
    10
  end
end

# A child in operator position. Lower precedence is parenthesized; so is equal
# precedence on the right (the tree's grouping is kept exactly, which matters
# for float arithmetic) and on either side of a comparison.
def q_operand(child, parent_prec, tie_wraps, dialect)
  s = q_render_expr(child, dialect)
  cp = q_prec(child)
  if (cp < parent_prec) || (tie_wraps && (cp == parent_prec))
    "(#{s})"
  else
    s
  end
end

def q_render_lit(e, dialect)
  t = get(e, :type)
  v = get(e, :value)
  if t == :int
    to_s(v)
  elsif t == :double
    if dialect == :duckdb
      "#{q_float_text(v)}::DOUBLE"
    else
      "CAST(#{q_float_text(v)} AS DOUBLE PRECISION)"
    end
  elsif t == :str
    q_quote_str(v)
  elsif t == :bool
    if v
      "TRUE"
    else
      "FALSE"
    end
  else
    "NULL"
  end
end

def q_render_key(k)
  if get(k, :desc)
    "#{q_ident(get(k, :name))} DESC"
  else
    q_ident(get(k, :name))
  end
end

def q_order_suffix(keys)
  if is_empty(keys)
    ""
  else
    " ORDER BY #{join(map(fn(k) q_render_key(k) end, keys), ", ")}"
  end
end

# An aggregate. The FILTER-where form is DuckDB's; core moves the predicate
# into a CASE inside the aggregate, which every mainstream engine reads.
def q_render_agg(e, dialect)
  f = get(e, :fn)
  if contains(q_duckdb_only_fns(), f) && (dialect != :duckdb)
    throw(error(:kueri_dialect, "#{f} has no core form; render it with :duckdb"))
  end
  args = get(e, :args)
  pred = get(e, :where)
  order = q_order_suffix(get(e, :order))
  shown = if is_empty(args)
    "*"
  else
    join(map(fn(a) q_render_expr(a, dialect) end, args), ", ")
  end
  if pred == nil
    "#{f}(#{shown}#{order})"
  elsif dialect == :duckdb
    "#{f}(#{shown}#{order}) FILTER (WHERE #{q_render_expr(pred, dialect)})"
  else
    inner = if is_empty(args)
      "1"
    else
      q_render_expr(first(args), dialect)
    end
    "#{f}(CASE WHEN #{q_render_expr(pred, dialect)} THEN #{inner} END#{order})"
  end
end

def q_render_win(e, dialect)
  part = if is_empty(get(e, :partition))
    []
  else
    ["PARTITION BY #{join(map(fn(p) q_ident(p) end, get(e, :partition)), ", ")}"]
  end
  ord = if is_empty(get(e, :order))
    []
  else
    ["ORDER BY #{join(map(fn(k) q_render_key(k) end, get(e, :order)), ", ")}"]
  end
  "#{get(e, :fn)}() OVER (#{join(concat_lists(part, ord), " ")})"
end

# One expression, in one dialect. The only place an expression becomes text.
def q_render_expr(e, dialect)
  k = get(e, :kind)
  if k == :col
    q_ident(get(e, :name))
  elsif k == :lit
    q_render_lit(e, dialect)
  elsif k == :op
    p = get(e, :prec)
    args = get(e, :args)
    "#{q_operand(first(args), p, p == 4, dialect)} #{get(e, :op)} #{q_operand(last(args), p, true, dialect)}"
  elsif k == :not
    "NOT #{q_operand(first(get(e, :args)), 3, false, dialect)}"
  elsif k == :fn
    "#{get(e, :name)}(#{join(map(fn(a) q_render_expr(a, dialect) end, get(e, :args)), ", ")})"
  elsif k == :cast
    "CAST(#{q_render_expr(first(get(e, :args)), dialect)} AS #{q_type_sql(get(e, :type), dialect)})"
  elsif k == :agg
    q_render_agg(e, dialect)
  elsif k == :win
    q_render_win(e, dialect)
  else
    throw(error(:kueri_shape, "no renderer arm for a #{to_s(k)} node"))
  end
end

def q_render_item(item, dialect)
  e = get(item, :expr)
  if (get(e, :kind) == :col) && (get(e, :name) == get(item, :name))
    q_ident(get(item, :name))
  else
    "#{q_render_expr(e, dialect)} AS #{q_ident(get(item, :name))}"
  end
end

def q_render_conj(preds, dialect)
  q_render_expr(reduce(fn(a, p) q_and(a, p) end, first(preds), rest(preds)), dialect)
end

def q_select_texts(b, dialect)
  if get(b, :grouped)
    concat_lists(map(fn(k) q_ident(k) end, get(b, :keys)), map(fn(a) q_render_item(a, dialect) end, get(b, :aggs)))
  elsif get(b, :items) != nil
    map(fn(i) q_render_item(i, dialect) end, get(b, :items))
  else
    cons("*", map(fn(d) q_render_item(d, dialect) end, get(b, :derives)))
  end
end

# `  item,` per line, the last without its comma.
def q_list_lines(items)
  n = size(items)
  map(fn(ix) if first(ix) + 1 < n
    "  #{last(ix)},"
  else
    "  #{last(ix)}"
  end end, enumerate(items))
end

def q_clause(word, preds, dialect)
  if is_empty(preds)
    []
  else
    ["#{word} #{q_render_conj(preds, dialect)}"]
  end
end

def q_join_line(j)
  word = if get(j, :how) == :left
    "LEFT JOIN"
  else
    "JOIN"
  end
  "#{word} #{q_ident(q_rel_name(get(j, :rel)))} USING (#{join(map(fn(k) q_ident(k) end, get(j, :keys)), ", ")})"
end

# One SELECT, as lines, clauses in SQL's order.
def q_block_lines(b, dialect)
  sel = q_select_texts(b, dialect)
  head = if size(sel) == 1
    ["SELECT #{first(sel)}"]
  else
    cons("SELECT", q_list_lines(sel))
  end
  from = cons("FROM #{q_ident(get(b, :from))}", map(fn(j) q_join_line(j) end, get(b, :joins)))
  group = if get(b, :grouped) && (is_empty(get(b, :keys)) == false)
    ["GROUP BY #{join(map(fn(k) q_ident(k) end, get(b, :keys)), ", ")}"]
  else
    []
  end
  order = if get(b, :order_all)
    ["ORDER BY ALL"]
  elsif is_empty(get(b, :order))
    []
  else
    ["ORDER BY #{join(map(fn(k) q_render_key(k) end, get(b, :order)), ", ")}"]
  end
  limit = if get(b, :limit) == nil
    []
  else
    ["LIMIT #{to_s(get(b, :limit))}"]
  end
  tail = concat_lists(q_clause("WHERE", get(b, :where), dialect), concat_lists(group, concat_lists(q_clause("HAVING", get(b, :having), dialect), concat_lists(q_clause("QUALIFY", get(b, :qualify), dialect), concat_lists(order, limit)))))
  concat_lists(head, concat_lists(from, tail))
end

def q_indent(lines)
  map(fn(l) "  #{l}" end, lines)
end

def q_raws(model)
  rels = cons(get(model, :from), map(fn(s) get(s, :rel) end, filter(fn(s) get(s, :kind) == :join end, get(model, :pipeline))))
  unique_by(fn(r) get(r, :name) end, filter(fn(r) get(r, :kind) == :raw end, rels))
end

def q_render_raw(r, dialect)
  if (get(r, :dialect) == :duckdb) && (dialect != :duckdb)
    throw(error(:kueri_dialect, "raw node #{get(r, :name)} is not vouched portable; render it with :duckdb"))
  end
  "#{q_ident(get(r, :name))} AS (\n#{get(r, :sql)}\n)"
end

# The query text, unchecked: q_render is the door that checks first.
def q_render_query(model, dialect)
  low = q_lower(model, dialect)
  final = q_lock_order(model, get(low, :cur), dialect)
  raw_ctes = map(fn(r) q_render_raw(r, dialect) end, q_raws(model))
  step_ctes = map(fn(c) "#{first(c)} AS (\n#{join(q_indent(q_block_lines(last(c), dialect)), "\n")}\n)" end, get(low, :done))
  ctes = concat_lists(raw_ctes, step_ctes)
  body = join(q_block_lines(final, dialect), "\n")
  if is_empty(ctes)
    body
  else
    "WITH #{join(ctes, ", ")}\n#{body}"
  end
end

# A model as one SQL query in `dialect` (:core or :duckdb), with no trailing
# semicolon. Checks first, then the dialect floor: it throws, never degrades.
def q_render(model, dialect)
  if contains([:core, :duckdb], dialect) == false
    throw(error(:kueri_shape, "a dialect is :core or :duckdb"))
  end
  q_check(model)
  q_refuse(q_dialect_refusals(model, dialect))
  q_render_query(model, dialect)
end

# ── around the query: loading, materializing, files ────────────────────────

def q_delim_sql(d)
  if d == :comma
    "','"
  else
    "'\\t'"
  end
end

# A view that reads a source's file with its declared columns. DuckDB only:
# read_csv has no core form.
def q_render_load(source, path, dialect)
  if dialect != :duckdb
    throw(error(:kueri_dialect, "read_csv has no core form; load source #{get(source, :name)} with :duckdb"))
  end
  cols = join(map(fn(c) "#{q_quote_str(get(c, :name))}: #{q_quote_str(q_type_sql(get(c, :type), :duckdb))}" end, get(source, :columns)), ", ")
  "CREATE OR REPLACE VIEW #{q_ident(get(source, :name))} AS\nSELECT * FROM read_csv(#{q_quote_str(path)}, delim = #{q_delim_sql(get(source, :delim))}, header = true, columns = {#{cols}})"
end

# Where a model's materialization lands by default: <name>.parquet or .csv.
def q_materialize_target(model)
  m = get(model, :materialize)
  if m == :parquet
    "#{get(model, :name)}.parquet"
  elsif m == :csv
    "#{get(model, :name)}.csv"
  else
    nil
  end
end

# The statement that writes a model out: COPY … TO a zstd Parquet or a headed
# CSV (DuckDB), or CREATE TABLE … AS (both dialects).
def q_render_materialize(model, dialect, target)
  m = get(model, :materialize)
  sql = q_render(model, dialect)
  if m == :table
    "CREATE TABLE #{q_ident(get(model, :name))} AS\n#{sql}"
  elsif m == nil
    throw(error(:kueri_shape, "model #{get(model, :name)} declares no materialize"))
  elsif dialect != :duckdb
    throw(error(:kueri_dialect, "COPY to a file has no core form; model #{get(model, :name)} materializes as :#{to_s(m)}, so render it with :duckdb or materialize :table"))
  elsif m == :parquet
    "COPY (\n#{sql}\n) TO #{q_quote_str(target)} (FORMAT parquet, COMPRESSION zstd)"
  else
    "COPY (\n#{sql}\n) TO #{q_quote_str(target)} (FORMAT csv, HEADER)"
  end
end

# The file a consumer commits: a @generated header naming the blue program,
# then the model's statement — its materialization when it declares one, the
# query otherwise.
def q_render_file(model, dialect, source)
  header = "-- @generated by #{source} (kueri, #{to_s(dialect)}). Do not edit: regenerate from the blue model."
  stmt = if get(model, :materialize) == nil
    q_render(model, dialect)
  else
    q_render_materialize(model, dialect, q_materialize_target(model))
  end
  "#{header}\n#{stmt};\n"
end

# Write the rendered file; returns the path.
def q_write_sql(path, model, dialect, source)
  write_file(path, q_render_file(model, dialect, source))
  path
end

# ── the DAG ────────────────────────────────────────────────────────────────

def q_rels(model)
  cons(get(model, :from), map(fn(s) get(s, :rel) end, filter(fn(s) get(s, :kind) == :join end, get(model, :pipeline))))
end

def q_targets(model)
  map(fn(r) get(r, :target) end, filter(fn(r) get(r, :kind) == :ref end, q_rels(model)))
end

# The names a model reads directly, first-seen order. Raw nodes are opaque and
# contribute none.
def q_deps(model)
  unique(map(fn(t) get(t, :name) end, q_targets(model)))
end

# Every upstream source and model, each before anything that reads it.
def q_closure(model)
  unique_by(fn(n) get(n, :name) end, flat_map(fn(t) q_closure_of(t) end, q_targets(model)))
end

def q_closure_of(t)
  if get(t, :kind) == :source
    [t]
  else
    push(q_closure(t), t)
  end
end

def q_sources(model)
  filter(fn(n) get(n, :kind) == :source end, q_closure(model))
end

# ── the DuckDB seam ────────────────────────────────────────────────────────

# Run SQL through the `duckdb` binary on PATH: [:ok, rows] or [:error, stderr].
# Rows are JSON documents (read fields with q_row_values or deeta). Only
# statements that return rows print, so a script may load views first.
def q_duckdb(sql)
  cap = exec_capture("duckdb", "-json", "-c", sql)
  if status_of(cap) != 0
    [:error, stderr_of(cap)]
  elsif trim(stdout_of(cap)) == ""
    [:ok, []]
  else
    [:ok, json_parse(stdout_of(cap))]
  end
end

def q_duckdb_failed?(result)
  first(result) == :error
end

# The rows of a result as value lists, columns in `names` order; [] when it
# failed (ask q_duckdb_failed? first when a failure must not read as empty).
def q_row_values(result, names)
  if q_duckdb_failed?(result)
    []
  else
    map(fn(row) map(fn(n) as_json(row, q_name(n)) end, names) end, last(result))
  end
end

# ── worked examples ────────────────────────────────────────────────────────
#
# Two analysis models, authored the way a consumer writes them. The tests pin
# their rendering in both dialects and run them end to end in DuckDB.

# Worked example: per relationship length, the promise-keeping rate with and
# without enforcement (a flat table of replicate means and spreads).
def q_example_horizons()
  q_source({name: :horizons, file: "horizons.tsv", columns: [q_col(:rounds_together, :bigint), q_col(:enforcement, :double), q_col(:keep_mean, :double), q_col(:keep_sd, :double)]})
end

# Worked example: how much full enforcement lifts keeping, per length. Every
# aggregate is a FILTER-where aggregate, so the whole model is ONE SELECT, and
# it holds at [:portable, :locked].
def q_example_leverage()
  without = q_filtered(q_max(:keep_mean), q_eq(:enforcement, 0))
  full = q_filtered(q_max(:keep_mean), q_eq(:enforcement, 1))
  q_model({name: :leverage, from: q_example_horizons(), posture: [:portable, :locked], materialize: :parquet,
    pipeline: [
      q_group([:rounds_together], [
        q_agg(:keep_without_enforcement, q_round(without, 3)),
        q_agg(:keep_with_full_enforcement, q_round(full, 3)),
        q_agg(:leverage, q_round(q_sub(full, without), 3)),
        q_agg(:widest_spread, q_round(q_max(:keep_sd), 3))]),
      q_sort([:rounds_together])],
    contract: [q_col(:rounds_together, :bigint), q_col(:keep_without_enforcement, :double), q_col(:keep_with_full_enforcement, :double), q_col(:leverage, :double), q_col(:widest_spread, :double)]})
end

# Worked example: which cell ran at which horizon and enforcement.
def q_example_curve_cells()
  q_source({name: :curve_cells, file: "curve_cells.tsv", columns: [q_col(:cell, :bigint), q_col(:rounds, :bigint), q_col(:enforcement, :double)]})
end

# Worked example: each cell's replicate mean, min and max of keeping.
def q_example_curve_keep()
  q_source({name: :curve_keep, file: "curve_keep.tsv", columns: [q_col(:cell, :bigint), q_col(:mean, :double), q_col(:min, :double), q_col(:max, :double)]})
end

# Worked example: the lowest enforcement at which a horizon keeps at least 90%
# (rounded to 3 places, as reported), and how many enforcement levels are
# bimodal (replicates more than 0.5 apart).
def q_example_tipping()
  q_model({name: :tipping, from: q_example_curve_keep(), posture: [:portable, :locked],
    pipeline: [
      q_join(q_example_curve_cells(), [:cell]),
      q_group([:rounds], [
        q_agg_where(:tipping_enforcement, q_min(:enforcement), q_ge(q_round(:mean, 3), 0.9)),
        q_agg_where(:bimodal_levels, q_count_all(), q_gt(q_sub(:max, :min), 0.5))]),
      q_sort([:rounds])],
    contract: [q_col(:rounds, :bigint), q_col(:tipping_enforcement, :double), q_col(:bimodal_levels, :bigint)]})
end

# ── tests ──────────────────────────────────────────────────────────────────

test "an empty pipeline is SELECT * from its relation, in both dialects, and holds"
  m = q_model({name: :everything, from: q_example_horizons()})
  assert q_render(m, :duckdb) == "SELECT *\nFROM horizons"
  assert q_render(m, :core) == "SELECT *\nFROM horizons"
  assert is_empty(q_refusals(m)) == true
  assert q_output(m) == ["rounds_together", "enforcement", "keep_mean", "keep_sd"]
  assert get(q_shift(m), :needs) == :portable
  assert is_empty(get(q_shift(m), :held_by)) == true
  # A raw node is opaque to the DAG: a model over one reads nothing it can name.
  raw = q_raw({name: :one, sql: "SELECT 1 AS x", columns: [q_col(:x, :integer)]})
  assert is_empty(q_deps(q_model({name: :r, from: raw}))) == true
  assert is_empty(q_closure(q_model({name: :r, from: raw}))) == true
end

test "the dialects differ only where a construct does: a neutral model renders the same bytes"
  m = q_model({name: :recent, from: q_example_horizons(), pipeline: [q_filter(q_gt(:rounds_together, 5)), q_derive(:gap, q_sub(:keep_mean, :keep_sd)), q_select([:rounds_together, :gap]), q_sort([q_desc(:gap)]), q_limit(3)]})
  assert q_render(m, :core) == q_render(m, :duckdb)
  # Composition is data: appending stages in two steps is appending them in one.
  a = [q_filter(q_gt(:rounds_together, 5)), q_derive(:gap, q_sub(:keep_mean, :keep_sd))]
  b = [q_select([:rounds_together, :gap]), q_sort([q_desc(:gap)]), q_limit(3)]
  base = q_model({name: :recent, from: q_example_horizons()})
  assert q_render(q_then(q_then(base, a), b), :duckdb) == q_render(q_then(base, concat_lists(a, b)), :duckdb)
  assert q_render(q_then(base, concat_lists(a, b)), :duckdb) == q_render(m, :duckdb)
end

test "leverage renders to one SELECT: FILTER in DuckDB, CASE in core, and a locked total order"
  m = q_example_leverage()
  duck = join([
    "SELECT",
    "  rounds_together,",
    "  round(max(keep_mean) FILTER (WHERE enforcement = 0), 3) AS keep_without_enforcement,",
    "  round(max(keep_mean) FILTER (WHERE enforcement = 1), 3) AS keep_with_full_enforcement,",
    "  round(max(keep_mean) FILTER (WHERE enforcement = 1) - max(keep_mean) FILTER (WHERE enforcement = 0), 3) AS leverage,",
    "  round(max(keep_sd), 3) AS widest_spread",
    "FROM horizons",
    "GROUP BY rounds_together",
    "ORDER BY ALL"], "\n")
  core = join([
    "SELECT",
    "  rounds_together,",
    "  round(max(CASE WHEN enforcement = 0 THEN keep_mean END), 3) AS keep_without_enforcement,",
    "  round(max(CASE WHEN enforcement = 1 THEN keep_mean END), 3) AS keep_with_full_enforcement,",
    "  round(max(CASE WHEN enforcement = 1 THEN keep_mean END) - max(CASE WHEN enforcement = 0 THEN keep_mean END), 3) AS leverage,",
    "  round(max(keep_sd), 3) AS widest_spread",
    "FROM horizons",
    "GROUP BY rounds_together",
    "ORDER BY rounds_together, keep_without_enforcement, keep_with_full_enforcement, leverage, widest_spread"], "\n")
  assert q_render(m, :duckdb) == duck
  assert q_render(m, :core) == core
  # FILTER has a core form, so the model is portable, and nothing holds it.
  assert get(q_shift(m), :needs) == :portable
end

test "tipping renders a join, count(*) FILTER against a CASE that counts a 1, and typed floats"
  m = q_example_tipping()
  duck = join([
    "SELECT",
    "  rounds,",
    "  min(enforcement) FILTER (WHERE round(mean, 3) >= 0.9::DOUBLE) AS tipping_enforcement,",
    "  count(*) FILTER (WHERE max - min > 0.5::DOUBLE) AS bimodal_levels",
    "FROM curve_keep",
    "JOIN curve_cells USING (cell)",
    "GROUP BY rounds",
    "ORDER BY ALL"], "\n")
  core = join([
    "SELECT",
    "  rounds,",
    "  min(CASE WHEN round(mean, 3) >= CAST(0.9 AS DOUBLE PRECISION) THEN enforcement END) AS tipping_enforcement,",
    "  count(CASE WHEN max - min > CAST(0.5 AS DOUBLE PRECISION) THEN 1 END) AS bimodal_levels",
    "FROM curve_keep",
    "JOIN curve_cells USING (cell)",
    "GROUP BY rounds",
    "ORDER BY rounds, tipping_enforcement, bimodal_levels"], "\n")
  assert q_render(m, :duckdb) == duck
  assert q_render(m, :core) == core
  assert q_output(m) == ["rounds", "tipping_enforcement", "bimodal_levels"]
end

test "a long pipeline folds into the fewest SELECTs: QUALIFY saves DuckDB a pass that core spends as a WHERE"
  m = q_model({name: :widest, from: q_example_curve_keep(),
    pipeline: [
      q_filter(q_gt(:mean, 0.1)),
      q_join(q_example_curve_cells(), [:cell]),
      q_derive(:spread, q_sub(:max, :min)),
      q_filter(q_lt(:enforcement, 0.75)),
      q_filter(q_gt(:spread, 0.3)),
      q_derive(:rank, q_row_number([:rounds], [q_desc(:mean)])),
      q_filter(q_eq(:rank, 1)),
      q_group([:rounds], [q_agg(:n, q_count_all()), q_agg(:widest, q_max(:spread))]),
      q_filter(q_ge(:n, 1)),
      q_sort([q_desc(:widest)]),
      q_limit(10)]})
  step_1 = [
    "WITH step_1 AS (",
    "  SELECT",
    "    *,",
    "    max - min AS spread",
    "  FROM curve_keep",
    "  JOIN curve_cells USING (cell)"]
  duck = join(concat_lists(step_1, [
    "  WHERE mean > 0.1::DOUBLE AND enforcement < 0.75::DOUBLE",
    "), step_2 AS (",
    "  SELECT",
    "    *,",
    "    row_number() OVER (PARTITION BY rounds ORDER BY mean DESC) AS rank",
    "  FROM step_1",
    "  WHERE spread > 0.3::DOUBLE",
    "  QUALIFY rank = 1",
    ")",
    "SELECT",
    "  rounds,",
    "  count(*) AS n,",
    "  max(spread) AS widest",
    "FROM step_2",
    "GROUP BY rounds",
    "HAVING count(*) >= 1",
    "ORDER BY widest DESC",
    "LIMIT 10"]), "\n")
  core = join(concat_lists(step_1, [
    "  WHERE mean > CAST(0.1 AS DOUBLE PRECISION) AND enforcement < CAST(0.75 AS DOUBLE PRECISION)",
    "), step_2 AS (",
    "  SELECT",
    "    *,",
    "    row_number() OVER (PARTITION BY rounds ORDER BY mean DESC) AS rank",
    "  FROM step_1",
    "  WHERE spread > CAST(0.3 AS DOUBLE PRECISION)",
    ")",
    "SELECT",
    "  rounds,",
    "  count(*) AS n,",
    "  max(spread) AS widest",
    "FROM step_2",
    "WHERE rank = 1",
    "GROUP BY rounds",
    "HAVING count(*) >= 1",
    "ORDER BY widest DESC",
    "LIMIT 10"]), "\n")
  assert q_render(m, :duckdb) == duck
  assert q_render(m, :core) == core
  # Eleven stages, two CTEs: the WHERE went past the join, the second filter
  # past the scalar derive, and the post-group filter became HAVING.
  assert size(get(q_lower(m, :duckdb), :done)) == 2
end

test "literals are typed on purpose and identifiers are quoted only when they must be"
  assert q_render_expr(q_lit(1), :duckdb) == "1"
  # to_s(1.0) is "1": without the typing this would be an INTEGER, and a bare
  # 1.0 would be DuckDB's DECIMAL(2,1).
  assert q_render_expr(q_lit(1.0), :duckdb) == "1.0::DOUBLE"
  assert q_render_expr(q_lit(1.0), :core) == "CAST(1.0 AS DOUBLE PRECISION)"
  assert q_render_expr(q_lit(0 - 0.5), :duckdb) == "-0.5::DOUBLE"
  assert q_render_expr(q_lit("it's"), :core) == "'it''s'"
  assert q_render_expr(q_lit(true), :core) == "TRUE"
  assert q_render_expr(q_lit(nil), :core) == "NULL"
  assert q_render_expr(q_cast(:x, :double), :core) == "CAST(x AS DOUBLE PRECISION)"
  assert q_render_expr(q_cast(:x, :bigint), :duckdb) == "CAST(x AS BIGINT)"
  assert q_ident(:keep_mean) == "keep_mean"
  assert q_ident("order") == "\"order\""
  assert q_ident("Mean") == "\"Mean\""
  assert q_ident("9lives") == "\"9lives\""
  assert q_ident("a\"b") == "\"a\"\"b\""
  # The tree's grouping survives: a - (b - c) keeps its parentheses, and
  # (a - b) - c needs none.
  assert q_render_expr(q_sub(:a, q_sub(:b, :c)), :core) == "a - (b - c)"
  assert q_render_expr(q_sub(q_sub(:a, :b), :c), :core) == "a - b - c"
  assert q_render_expr(q_mul(q_add(:a, :b), :c), :core) == "(a + b) * c"
  assert q_render_expr(q_not(q_or(q_eq(:a, 1), q_eq(:b, 2))), :core) == "NOT (a = 1 OR b = 2)"
end

test "a duckdb-only construct in a :portable model is refused, and q_check throws it"
  plays = q_source({name: :plays, file: "plays.tsv", columns: [q_col(:rounds, :bigint), q_col(:game, :varchar), q_col(:score, :double)]})
  names = q_filtered(q_string_agg(:game, ","), q_gt(:score, 0.5))
  stages = [q_group([:rounds], [q_agg(:games, q_ordered(names, [:game]))])]
  held = q_model({name: :names, from: plays, posture: [:portable], pipeline: stages})
  assert q_refusal_kinds(held) == [:kueri_reach]
  assert error?(try(q_check(held), catch(e(), e))) == true
  assert error?(try(q_render(held, :duckdb), catch(e(), e))) == true
  # The control: the same stages at :duckdb reach hold, so the posture was the
  # whole of the refusal.
  free = q_model({name: :names, from: plays, posture: [:duckdb], pipeline: stages})
  assert is_empty(q_refusals(free)) == true
  assert q_render(free, :duckdb) == "SELECT\n  rounds,\n  string_agg(game, ',' ORDER BY game) FILTER (WHERE score > 0.5::DOUBLE) AS games\nFROM plays\nGROUP BY rounds"
  # And q_shift names what holds it there.
  assert get(q_shift(free), :needs) == :duckdb
  assert get(q_shift(free), :held_by) == ["string_agg at stage 1 (group)"]
end

test "a locked model refuses what would make its output depend on luck"
  src = q_source({name: :plays, file: "plays.tsv", columns: [q_col(:game, :varchar), q_col(:score, :double)]})
  unordered = q_model({name: :names, from: src, posture: [:duckdb, :locked], pipeline: [q_group([], [q_agg(:games, q_string_agg(:game, ","))])], contract: [q_col(:games, :varchar)]})
  assert q_refusal_kinds(unordered) == [:kueri_locked]
  ordered = q_model({name: :names, from: src, posture: [:duckdb, :locked], pipeline: [q_group([], [q_agg(:games, q_ordered(q_string_agg(:game, ","), [:game]))])], contract: [q_col(:games, :varchar)]})
  assert is_empty(q_refusals(ordered)) == true
  assert q_render(ordered, :duckdb) == "SELECT string_agg(game, ',' ORDER BY game) AS games\nFROM plays\nORDER BY ALL"
  no_contract = q_model({name: :top, from: src, posture: [:locked], pipeline: [q_sort([q_desc(:score)]), q_limit(1)]})
  assert q_refusal_kinds(no_contract) == [:kueri_locked]
  lucky = q_model({name: :top, from: src, posture: [:locked], pipeline: [q_limit(1)], contract: [q_col(:game, :varchar), q_col(:score, :double)]})
  assert q_refusal_kinds(lucky) == [:kueri_locked]
  assert error?(try(q_check(lucky), catch(e(), e))) == true
  # The control: a sort right before the limit, and the order is completed
  # with the rest of the contract so ties cannot fall either way.
  top = q_model({name: :top, from: src, posture: [:locked], pipeline: [q_sort([q_desc(:score)]), q_limit(1)], contract: [q_col(:game, :varchar), q_col(:score, :double)]})
  assert error?(try(q_check(top), catch(e(), e))) == false
  assert q_render(top, :duckdb) == "SELECT *\nFROM plays\nORDER BY score DESC, game\nLIMIT 1"
  # :loose asks for none of it.
  assert is_empty(q_refusals(q_model({name: :top, from: src, pipeline: [q_limit(1)]}))) == true
end

test "a declared contract is checked at any rigor, and a wrong one throws"
  wrong = q_model({name: :w, from: q_example_horizons(), pipeline: [q_select([:rounds_together, :keep_mean])], contract: [q_col(:rounds_together, :bigint), q_col(:keep_sd, :double)]})
  assert q_refusal_kinds(wrong) == [:kueri_contract]
  assert error?(try(q_render(wrong, :core), catch(e(), e))) == true
  right = q_model({name: :w, from: q_example_horizons(), pipeline: [q_select([:rounds_together, :keep_mean])], contract: [q_col(:rounds_together, :bigint), q_col(:keep_mean, :double)]})
  assert is_empty(q_refusals(right)) == true
  # A model downstream sees the contract as its input schema.
  down = q_model({name: :d, from: right, pipeline: [q_filter(q_gt(:keep_sd, 0))]})
  assert q_refusal_kinds(down) == [:kueri_shape]
end

test "shape: unknown columns, a stray aggregate, a plain column in a group, and a discarded sort"
  h = q_example_horizons()
  assert q_refusal_kinds(q_model({name: :a, from: h, pipeline: [q_filter(q_gt(:nope, 1))]})) == [:kueri_shape]
  assert q_refusal_kinds(q_model({name: :b, from: h, pipeline: [q_derive(:m, q_max(:keep_mean))]})) == [:kueri_shape]
  assert q_refusal_kinds(q_model({name: :c, from: h, pipeline: [q_group([:rounds_together], [q_agg(:e, q_add(:enforcement, q_max(:keep_mean)))])]})) == [:kueri_shape]
  assert q_refusal_kinds(q_model({name: :d, from: h, pipeline: [q_sort([:keep_mean]), q_filter(q_gt(:keep_mean, 0))]})) == [:kueri_shape]
  assert q_refusal_kinds(q_model({name: :e, from: h, pipeline: [q_group([:rounds_together], [q_agg(:m, q_max(q_max(:keep_mean)))])]})) == [:kueri_shape]
  assert q_refusal_kinds(q_model({name: :f, from: h, pipeline: [q_join(h, [:rounds_together])]})) == [:kueri_shape]
  # The control: the same stages, well formed, hold.
  assert is_empty(q_refusals(q_model({name: :g, from: h, pipeline: [q_filter(q_gt(:keep_mean, 0)), q_sort([:keep_mean])]}))) == true
end

test "the renderer holds the floor on its own: no door leads a duckdb form into core"
  m = q_model({name: :names, from: q_example_horizons(), posture: [:duckdb], pipeline: [q_group([:rounds_together], [q_agg(:games, q_ordered(q_string_agg(:rounds_together, ","), [:rounds_together]))])]})
  assert is_empty(q_refusals(m)) == true
  assert error?(try(q_render(m, :core), catch(e(), e))) == true
  assert error?(try(q_render_expr(q_string_agg(:x, ","), :core), catch(e(), e))) == true
  assert error?(try(q_render_query(m, :core), catch(e(), e))) == true
  raw = q_model({name: :r, from: q_raw({name: :one, sql: "SELECT 1 AS x", columns: [q_col(:x, :integer)]})})
  assert error?(try(q_render_query(raw, :core), catch(e(), e))) == true
  assert error?(try(q_render(m, :duckdb), catch(e(), e))) == false
  assert error?(try(q_render_load(q_example_horizons(), "h.tsv", :core), catch(e(), e))) == true
  assert error?(try(q_render(m, :postgres), catch(e(), e))) == true
end

test "malformed nodes are refused where they are built"
  assert error?(try(q_source({name: :s, file: "s.tsv"}), catch(e(), e))) == true
  assert error?(try(q_raw({name: :r, sql: "SELECT 1"}), catch(e(), e))) == true
  assert error?(try(q_col(:x, :float), catch(e(), e))) == true
  assert error?(try(q_model({name: :m, from: q_example_horizons(), posture: [:strict]}), catch(e(), e))) == true
  assert error?(try(q_model({name: :m, from: q_example_horizons(), posture: [:portable, :duckdb]}), catch(e(), e))) == true
  assert error?(try(q_limit(0 - 1), catch(e(), e))) == true
  assert error?(try(q_filtered(q_c(:x), q_gt(:x, 1)), catch(e(), e))) == true
  # The control: a well-formed source is not an error.
  assert error?(try(q_example_horizons(), catch(e(), e))) == false
end

test "refs are the DAG: direct deps, and a closure with every upstream before its readers"
  assert q_deps(q_example_leverage()) == ["horizons"]
  assert q_deps(q_example_tipping()) == ["curve_keep", "curve_cells"]
  summary = q_model({name: :summary, from: q_example_tipping(), pipeline: [q_join(q_example_leverage(), [:rounds])]})
  assert q_deps(summary) == ["tipping", "leverage"]
  assert map(fn(n) get(n, :name) end, q_closure(summary)) == ["curve_keep", "curve_cells", "tipping", "horizons", "leverage"]
  assert map(fn(n) get(n, :name) end, q_sources(summary)) == ["curve_keep", "curve_cells", "horizons"]
end

test "a raw node is the escape hatch: its own CTE, its declared columns, and :duckdb unless vouched"
  raw = q_raw({name: :seeds, sql: "SELECT range AS seed FROM range(3)", columns: [q_col(:seed, :bigint)]})
  m = q_model({name: :evens, from: raw, pipeline: [q_filter(q_eq(q_sub(:seed, q_mul(q_div(:seed, 2), 2)), 0))]})
  assert q_output(m) == ["seed"]
  assert q_render(m, :duckdb) == "WITH seeds AS (\nSELECT range AS seed FROM range(3)\n)\nSELECT *\nFROM seeds\nWHERE seed - seed / 2 * 2 = 0"
  assert q_refusal_kinds(assoc(m, :posture, q_posture_of([:portable]))) == [:kueri_reach]
  vouched = q_raw({name: :one, sql: "SELECT 1 AS x", columns: [q_col(:x, :integer)], dialect: :core})
  assert is_empty(q_refusals(q_model({name: :v, from: vouched, posture: [:portable]}))) == true
end

test "materialize: COPY to a file in DuckDB, CREATE TABLE AS in both, and no file COPY in core"
  m = q_example_leverage()
  sql = q_render(m, :duckdb)
  assert q_render_materialize(m, :duckdb, "out/leverage.parquet") == "COPY (\n#{sql}\n) TO 'out/leverage.parquet' (FORMAT parquet, COMPRESSION zstd)"
  assert error?(try(q_render_materialize(m, :core, "x.parquet"), catch(e(), e))) == true
  as_table = assoc(m, :materialize, :table)
  assert q_render_materialize(as_table, :core, nil) == "CREATE TABLE leverage AS\n#{q_render(m, :core)}"
  as_csv = assoc(m, :materialize, :csv)
  assert q_render_materialize(as_csv, :duckdb, "l.csv") == "COPY (\n#{sql}\n) TO 'l.csv' (FORMAT csv, HEADER)"
end

test "q_write_sql writes the @generated file a consumer commits and gates fresh"
  path = path_join(getenv("TMPDIR", "."), "kueri-write-test.sql")
  m = q_example_tipping()
  assert q_write_sql(path, m, :duckdb, "analysis/tipping.b") == path
  written = read_file(path)
  assert written == "-- @generated by analysis/tipping.b (kueri, duckdb). Do not edit: regenerate from the blue model.\n#{q_render(m, :duckdb)};\n"
  # A model that materializes writes its COPY, to <name>.parquet beside it.
  assert contains?(q_render_file(q_example_leverage(), :duckdb, "l.b"), ") TO 'leverage.parquet' (FORMAT parquet, COMPRESSION zstd);\n") == true
  rm(path)
end

test "the DuckDB seam: an empty result is not a failure, a broken query is not empty, and 1.0 needs its type"
  r = q_duckdb("SELECT 1 AS x WHERE false")
  assert q_duckdb_failed?(r) == false
  assert is_empty(q_row_values(r, [:x])) == true
  assert q_duckdb_failed?(q_duckdb("SELECT FROM nowhere")) == true
  # The trap the literal typing exists for, measured on the engine itself.
  t = q_duckdb("SELECT typeof(1.0) AS bare, typeof(#{q_render_expr(q_lit(1.0), :duckdb)}) AS typed, typeof(#{q_render_expr(q_lit(1.0), :core)}) AS core")
  assert q_row_values(t, [:bare, :typed, :core]) == [["DECIMAL(2,1)", "DOUBLE", "DOUBLE"]]
end

test "end to end: both dialects' SQL, over fixture files, gives the known leverage and tipping answers"
  dir = getenv("TMPDIR", ".")
  files = [
    ["horizons.tsv", "rounds_together\tenforcement\tkeep_mean\tkeep_sd\n1\t0\t0.1\t0.02\n1\t0.5\t0.3\t0.04\n1\t1\t0.6\t0.05\n10\t0\t0.4\t0.1\n10\t1\t0.9\t0.08\n10\t1\t0.85\t0.12\n100\t0\t0.95\t0.01\n100\t1\t0.95\t0.2\n1000\t1\t0.7\t0.3\n"],
    ["curve_cells.tsv", "cell\trounds\tenforcement\n1\t5\t0.0\n2\t5\t0.5\n3\t5\t1.0\n4\t50\t0.0\n5\t50\t0.5\n6\t50\t1.0\n7\t500\t0.25\n"],
    ["curve_keep.tsv", "cell\tmean\tmin\tmax\n1\t0.2\t0.1\t0.3\n2\t0.8996\t0.2\t0.95\n3\t0.97\t0.9\t1.0\n4\t0.5\t0.0\t0.9\n5\t0.89\t0.6\t0.99\n6\t0.92\t0.3\t1.0\n7\t0.4\t0.35\t0.45\n"]]
  map(fn(f) write_file(path_join(dir, "kueri-e2e-#{first(f)}"), last(f)) end, files)
  loads = fn(m) map(fn(s) q_render_load(s, path_join(dir, "kueri-e2e-#{get(s, :file)}"), :duckdb) end, q_sources(m)) end
  run = fn(m, d) q_duckdb(join(push(loads(m), q_render(m, d)), ";\n")) end
  lev = q_example_leverage()
  lev_names = q_col_names(get(lev, :contract))
  # Per length: max keep without and with enforcement, their rounded
  # difference, the widest spread. 1000 has no unenforced row: NULL, not 0.
  lev_known = [[1, 0.1, 0.6, 0.5, 0.05], [10, 0.4, 0.9, 0.5, 0.12], [100, 0.95, 0.95, 0.0, 0.2], [1000, nil, 0.7, nil, 0.3]]
  assert q_duckdb_failed?(run(lev, :duckdb)) == false
  assert q_row_values(run(lev, :duckdb), lev_names) == lev_known
  assert q_row_values(run(lev, :core), lev_names) == lev_known
  tip = q_example_tipping()
  tip_names = q_col_names(get(tip, :contract))
  # Cell 2's mean 0.8996 rounds to 0.9 and counts; cell 5's 0.89 does not.
  # Horizon 500 never reaches 90%: NULL tipping, zero bimodal levels.
  tip_known = [[5, 0.5, 1], [50, 1.0, 2], [500, nil, 0]]
  assert q_row_values(run(tip, :duckdb), tip_names) == tip_known
  assert q_row_values(run(tip, :core), tip_names) == tip_known
  # The materialization runs too: COPY to Parquet, read back identical.
  pq = path_join(dir, "kueri-e2e-leverage.parquet")
  copied = q_duckdb(join(push(loads(lev), q_render_materialize(lev, :duckdb, pq)), ";\n"))
  assert q_duckdb_failed?(copied) == false
  assert q_row_values(q_duckdb("SELECT * FROM read_parquet(#{q_quote_str(pq)})"), lev_names) == lev_known
  map(fn(f) rm(path_join(dir, "kueri-e2e-#{first(f)}")) end, files)
  rm(pq)
end
