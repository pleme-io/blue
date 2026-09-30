use("deeta", [:as_json])
use("kazu")
use("moji", [:char_at, :made_of, :strip_suffix])

use(
  "retsu",
  [
    :as_list,
    :concat_lists,
    :contains,
    :count_where,
    :enumerate,
    :equal_lists,
    :find_first,
    :first,
    :flat_map,
    :is_empty,
    :last,
    :push,
    :rest,
    :size
  ]
)

use("shisutemu", [:status_of, :stderr_of, :stdout_of])
use("shuugou", [:difference, :intersection, :unique, :unique_by])

legacy_names("0.1.1", "q")

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
#   relations    q_source(opts: delimited or JSON Lines)  q_values(opts: literal
#                rows)  q_ref(x)  q_raw(opts)  q_model(opts)
#   stages       q_select(+ q_as)  q_derive  q_explode  q_filter  q_group(+
#                q_agg, q_agg_where)  q_join  q_left_join  q_asof_left_join
#                q_sort(+ q_desc)  q_limit
#                — and q_then(model, stages) composes by appending data
#   expressions  q_c  q_lit(q_int q_double q_str q_bool q_null)  q_add q_sub
#                q_mul q_div  q_eq q_ne q_lt q_le q_gt q_ge  q_and q_or q_not
#                q_is_null q_not_null  q_if  q_coalesce  q_get (a struct field)
#                q_round  q_cast  q_min q_max q_sum q_avg q_count q_count_all
#                q_filtered (FILTER-where)  q_string_agg  q_row_number  q_lead
#                q_lag  q_ordered (an order for an order-sensitive aggregate)
#   types        q_types() (scalars)  q_struct_of(cols)  q_list_of(t)
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
# q_render_load binds a source to a delimited or JSON Lines file with its
# declared columns (the sniffer never decides a contract), or loads literal
# rows. q_render_materialize writes a model out (a file, a table or a view).
# q_write_sql writes the rendered statement with a @generated header, for a
# consumer to commit and gate fresh like blue's generate(...) files;
# q_render_script renders a whole database (every load, then every model as a
# view or table, upstream first). q_duckdb is the process seam to the `duckdb`
# binary (a program, not a linked library, so there is no C to contain; the
# Bluefile declares it with `tool("duckdb")`): a failure is [:error, stderr]
# and an empty result is [:ok, []], never confused. q_duckdb_at runs against
# a database file; q_rows / q_rows_at THROW :kueri_query on a failure, for
# callers that must never read one as no rows.
#
# A DAG node is identified by its NAME: q_closure and q_render_script keep the
# first node of each name, so two different relations given one name collapse
# silently. A generator names its relations uniquely (and checks it); content
# identity for nodes is not built.
#
# Design: the SQL-frameworks survey in the makoto lab (§5 sketch; this is its
# M0). Near-misses, deliberately not merged: dialeto's relational sub-IR
# (theory/DIALETO.md — design-tier, no types to compare) and sql-synthesizer
# (a Rust DDL AST with no SELECT algebra).

# ── names and literals ─────────────────────────────────────────────────────

# A name as text: a keyword's name, or the string itself.
def name(x)
  if keyword?(x)
    to_s(x)
  else
    x
  end
end

# Words an engine will not read as a bare identifier: SQL's reserved words and
# DuckDB's own (qualify, pivot, asof, …). A name among them is quoted.
def reserved_words()
  [
    "all",
    "analyse",
    "analyze",
    "and",
    "anti",
    "any",
    "array",
    "as",
    "asc",
    "asof",
    "asymmetric",
    "between",
    "both",
    "by",
    "case",
    "cast",
    "check",
    "collate",
    "column",
    "constraint",
    "create",
    "cross",
    "current_catalog",
    "current_date",
    "current_role",
    "current_time",
    "current_timestamp",
    "current_user",
    "default",
    "deferrable",
    "desc",
    "distinct",
    "do",
    "else",
    "end",
    "except",
    "exists",
    "false",
    "fetch",
    "filter",
    "for",
    "foreign",
    "from",
    "full",
    "grant",
    "group",
    "having",
    "ilike",
    "in",
    "initially",
    "inner",
    "intersect",
    "into",
    "is",
    "isnull",
    "join",
    "lateral",
    "leading",
    "left",
    "like",
    "limit",
    "localtime",
    "localtimestamp",
    "natural",
    "not",
    "notnull",
    "null",
    "offset",
    "on",
    "only",
    "or",
    "order",
    "outer",
    "over",
    "partition",
    "pivot",
    "placing",
    "positional",
    "primary",
    "qualify",
    "range",
    "references",
    "returning",
    "right",
    "rows",
    "select",
    "semi",
    "session_user",
    "similar",
    "some",
    "symmetric",
    "table",
    "then",
    "to",
    "trailing",
    "true",
    "union",
    "unique",
    "unpivot",
    "user",
    "using",
    "values",
    "variadic",
    "when",
    "where",
    "window",
    "with"
  ]
end

# Lower-case ASCII, digits and underscore, not starting with a digit, and not
# reserved. Anything else is quoted, because engines fold unquoted case
# differently and a quoted name means the same thing everywhere.
def bare_ident?(s)
  made_of(s, "abcdefghijklmnopqrstuvwxyz_0123456789") &&
    made_of(char_at(s, 0), "abcdefghijklmnopqrstuvwxyz_") &&
    contains(reserved_words(), s) == false
end

# An identifier as SQL: bare when safe, otherwise double-quoted with any
# embedded quote doubled.
def ident(name)
  s = kueri::name(name)
  if bare_ident?(s)
    s
  else
    "\"#{replace(s, "\"", "\"\"")}\""
  end
end

# A string value as a SQL literal: single quotes, embedded quotes doubled.
def quote_str(s)
  "'#{replace(s, "'", "''")}'"
end

# A float's digits, always with a decimal point: to_s(1.0) is "1", which an
# engine would read as an INTEGER.
def float_text(x)
  s = to_s(x)
  if contains?(s, ".") || contains?(s, "e") || contains?(s, "E")
    s
  else
    "#{s}.0"
  end
end

# ── types ──────────────────────────────────────────────────────────────────

# The closed set of scalar column types a contract or a source may declare.
# Composite types are built from them: q_struct_of and q_list_of.
def types()
  [:bigint, :integer, :double, :varchar, :boolean, :date]
end

def type(t)
  if keyword?(t) && contains(types(), t)
    t
  elsif keyword?(t) || composite?(t) == false
    throw(
      error(
        :kueri_shape,
        "unknown column type #{to_s(t)}; a type is one of #{blue::join(map(fn(x) to_s(x) end, types()), ", ")}, or q_struct_of / q_list_of over them"
      )
    )
  else
    t
  end
end

# A composite type: a map built by q_struct_of or q_list_of.
def composite?(t)
  t != nil &&
    keyword?(t) == false &&
    list?(t) == false &&
    string?(t) == false &&
    number?(t) == false &&
    boolean?(t) == false &&
    contains([:struct, :list], blue::get(t, :kind))
end

# A struct type: named fields, each declared with q_col. JSON objects load
# into it; read a field with q_get. DuckDB only.
def struct_of(cols)
  fs = as_list(cols)
  if is_empty(fs)
    throw(error(:kueri_shape, "a struct type has at least one field"))
  end
  {kind: :struct, fields: fs}
end

# A list type: JSON arrays load into it; q_explode makes a row per element.
# DuckDB only.
def list_of(t)
  {kind: :list, of: type(t)}
end

# A type's name in a dialect. DOUBLE is DuckDB's; the standard spells it
# DOUBLE PRECISION, which DuckDB also reads. Structs and lists are DuckDB's
# alone.
def type_sql(t, dialect)
  if composite?(t)
    composite_sql(t, dialect)
  elsif t == :double
    if dialect == :duckdb
      "DOUBLE"
    else
      "DOUBLE PRECISION"
    end
  else
    upcase(to_s(t))
  end
end

def composite_sql(t, dialect)
  if dialect != :duckdb
    throw(
      error(
        :kueri_dialect,
        "struct and list types have no core form; render with :duckdb"
      )
    )
  end
  if blue::get(t, :kind) == :list
    "#{type_sql(blue::get(t, :of), dialect)}[]"
  else
    "STRUCT(#{blue::join(map(fn(c) "#{ident(blue::get(c, :name))} #{type_sql(blue::get(c, :type), dialect)}" end, blue::get(t, :fields)), ", ")})"
  end
end

# A declared column: a source's input or a model's contract.
def col(name, t)
  {kind: :coldef, name: kueri::name(name), type: type(t)}
end

def col_names(cols)
  map(fn(c) blue::get(c, :name) end, as_list(cols))
end

# ── expressions ────────────────────────────────────────────────────────────

# A column reference.
def c(name)
  {kind: :col, name: kueri::name(name)}
end

def int(n)
  if integer?(n) == false
    throw(error(:kueri_shape, "q_int takes an integer"))
  end
  {kind: :lit, type: :int, value: n}
end

# A DOUBLE literal, typed on purpose: DuckDB reads a bare 1.0 as DECIMAL(2,1).
def double(x)
  if number?(x) == false
    throw(error(:kueri_shape, "q_double takes a number"))
  end
  # NaN and the infinities have no SQL literal; x - x is 0 only when x is finite.
  if x - x < 1 == false
    throw(error(:kueri_shape, "q_double takes a finite number"))
  end
  {kind: :lit, type: :double, value: x}
end

def str(s)
  {kind: :lit, type: :str, value: s}
end

def bool(b)
  {kind: :lit, type: :bool, value: b}
end

def null()
  {kind: :lit, type: :null, value: nil}
end

def value?(x)
  number?(x) || string?(x) || boolean?(x) || null?(x)
end

# A blue value as a literal, typed by what it is: an int stays an INTEGER and a
# float becomes a DOUBLE, never the DECIMAL an untyped 1.0 would be.
def lit(v)
  if integer?(v)
    int(v)
  elsif number?(v)
    double(v)
  elsif string?(v)
    str(v)
  elsif boolean?(v)
    bool(v)
  elsif null?(v)
    null()
  else
    throw(error(:kueri_shape, "q_lit takes a number, string, boolean or nil"))
  end
end

# Anything in expression position: a keyword is a column, a value is a
# literal, and a node is itself.
def expr(x)
  if keyword?(x)
    c(x)
  elsif value?(x)
    lit(x)
  else
    x
  end
end

# A binary operator. `prec` orders them for the renderer's parentheses:
# OR 1, AND 2, NOT 3, comparisons 4, + - 5, * / 6.
def op(op, prec, a, b)
  {kind: :op, op: op, prec: prec, args: [expr(a), expr(b)]}
end

def add(a, b)
  op("+", 5, a, b)
end

def sub(a, b)
  op("-", 5, a, b)
end

def mul(a, b)
  op("*", 6, a, b)
end

def div(a, b)
  op("/", 6, a, b)
end

def eq(a, b)
  op("=", 4, a, b)
end

def ne(a, b)
  op("<>", 4, a, b)
end

def lt(a, b)
  op("<", 4, a, b)
end

def le(a, b)
  op("<=", 4, a, b)
end

def gt(a, b)
  op(">", 4, a, b)
end

def ge(a, b)
  op(">=", 4, a, b)
end

# waive B0013: `and` is a builtin kueri also uses, so the prefix stays; kueri::and names it too
def q_and(a, b)
  op("AND", 2, a, b)
end

# waive B0013: `or` is a builtin kueri also uses, so the prefix stays; kueri::or names it too
def q_or(a, b)
  op("OR", 1, a, b)
end

# waive B0013: `not` is a builtin kueri also uses, so the prefix stays; kueri::not names it too
def q_not(a)
  {kind: :not, args: [expr(a)]}
end

# waive B0013: `round` is a builtin kueri also uses, so the prefix stays; kueri::round names it too
def q_round(x, digits)
  {kind: :fn, name: "round", args: [expr(x), int(digits)]}
end

# waive B0013: `cast` is a builtin kueri also uses, so the prefix stays; kueri::cast names it too
def q_cast(x, t)
  {kind: :cast, type: type(t), args: [expr(x)]}
end

# The first of two values that is not NULL.
def coalesce(a, b)
  {kind: :fn, name: "coalesce", args: [expr(a), expr(b)]}
end

# The value is NULL: absent, never a comparison (x = NULL is never true).
def is_null(a)
  {kind: :postfix, op: "IS NULL", args: [expr(a)]}
end

def not_null(a)
  {kind: :postfix, op: "IS NOT NULL", args: [expr(a)]}
end

# `a` where `cond` holds, else `b`: CASE WHEN … THEN … ELSE … END.
# waive B0013: `if` is a reserved word, so the prefix stays; kueri::if names it too
def q_if(cond, a, b)
  {kind: :case, args: [expr(cond), expr(a), expr(b)]}
end

# A field of a struct value (a JSON object loaded as q_struct_of). DuckDB
# only.
# waive B0013: `get` is a builtin kueri also uses, so the prefix stays; kueri::get names it too
def q_get(x, field)
  {kind: :field, name: name(field), args: [expr(x)]}
end

# ── aggregates and windows ─────────────────────────────────────────────────

def agg_fn(f, args)
  {kind: :agg, fn: f, args: args, where: nil, order: []}
end

# waive B0013: `min` is a builtin kueri also uses, so the prefix stays; kueri::min names it too
def q_min(x)
  agg_fn("min", [expr(x)])
end

# waive B0013: `max` is a builtin kueri also uses, so the prefix stays; kueri::max names it too
def q_max(x)
  agg_fn("max", [expr(x)])
end

def sum(x)
  agg_fn("sum", [expr(x)])
end

def avg(x)
  agg_fn("avg", [expr(x)])
end

# waive B0013: `count` is a builtin kueri also uses, so the prefix stays; kueri::count names it too
def q_count(x)
  agg_fn("count", [expr(x)])
end

# count(*).
def count_all()
  agg_fn("count", [])
end

# Joins the values with `sep`. Order-sensitive, and with no core form: MySQL,
# SQL Server and Snowflake each spell it differently.
def string_agg(x, sep)
  agg_fn("string_agg", [expr(x), str(sep)])
end

# row_number() OVER (PARTITION BY … ORDER BY …).
def row_number(partition, order)
  window("row_number", [], partition, order)
end

# The value of `x` in the next row of its partition, in `order`; NULL on the
# last. An order is required: without one the next row is arbitrary.
def lead(x, partition, order)
  ordered_window("lead", x, partition, order)
end

# The value of `x` in the previous row; NULL on the first.
def lag(x, partition, order)
  ordered_window("lag", x, partition, order)
end

def ordered_window(f, x, partition, order)
  if is_empty(as_list(order))
    throw(
      error(
        :kueri_shape,
        "#{f} needs an order; without one the neighbouring row is arbitrary"
      )
    )
  end
  window(f, [expr(x)], partition, order)
end

def window(f, args, partition, order)
  {
    kind: :win,
    fn: f,
    args: args,
    partition: map(fn(p) name(p) end, as_list(partition)),
    order: map(fn(k) key(k) end, as_list(order))
  }
end

# An aggregate over only the rows where `pred` holds: FILTER (WHERE …) in
# DuckDB, CASE WHEN inside the aggregate in core.
def filtered(agg, pred)
  if blue::get(agg, :kind) != :agg
    throw(error(:kueri_shape, "q_filtered takes an aggregate"))
  end
  assoc(agg, :where, expr(pred))
end

# An order for an order-sensitive aggregate or window.
def ordered(node, keys)
  if blue::get(node, :kind) != :agg && blue::get(node, :kind) != :win
    throw(error(:kueri_shape, "q_ordered takes an aggregate or a window"))
  end
  assoc(node, :order, map(fn(k) key(k) end, keys))
end

# Functions whose result depends on the order rows arrive in.
def order_sensitive_fns()
  ["string_agg", "row_number", "lead", "lag"]
end

# Functions with no core form.
def duckdb_only_fns()
  ["string_agg"]
end

# ── sort keys ──────────────────────────────────────────────────────────────

def key(k)
  if keyword?(k) || string?(k)
    {kind: :key, name: name(k), desc: false}
  else
    k
  end
end

def desc(name)
  {kind: :key, name: kueri::name(name), desc: true}
end

def key_names(keys)
  map(fn(k) blue::get(k, :name) end, as_list(keys))
end

# ── relations ──────────────────────────────────────────────────────────────

# An input file with DECLARED columns. opts: name, file, columns (q_col
# list), format (:delimited, the default, or :jsonl), delim (:tab, the
# default, or :comma; delimited only).
#   :delimited  read_csv maps the columns by position and never sniffs.
#   :jsonl      JSON Lines: read_json maps them by key, a missing key is NULL,
#               and a value that is not of its column's type fails the load,
#               never reads as NULL. Columns may be q_struct_of / q_list_of.
def source(opts)
  cols = as_list(blue::get(opts, :columns))
  if is_empty(cols)
    throw(
      error(
        :kueri_shape,
        "source #{name(blue::get(opts, :name))} declares no columns; a source states its schema, the sniffer never does"
      )
    )
  end
  format = blue::get(opts, :format)
  if format == nil
    format = :delimited
  end
  if contains([:delimited, :jsonl], format) == false
    throw(error(:kueri_shape, "a source's format is :delimited or :jsonl"))
  end
  delim = blue::get(opts, :delim)
  if delim == nil
    delim = :tab
  end
  if contains([:tab, :comma], delim) == false
    throw(error(:kueri_shape, "a source's delim is :tab or :comma"))
  end
  {
    kind: :source,
    name: name(blue::get(opts, :name)),
    file: blue::get(opts, :file),
    columns: cols,
    delim: delim,
    format: format
  }
end

# A relation of literal rows with declared scalar columns: data a program
# built (a definition's own tables, a lookup), loaded as a view in either
# dialect — never hand-written SQL. opts: name, columns (q_col list), rows
# (lists of numbers, strings, booleans or nil, one per column).
def values(opts)
  name = kueri::name(blue::get(opts, :name))
  cols = as_list(blue::get(opts, :columns))
  if is_empty(cols)
    throw(error(:kueri_shape, "values #{name} declares no columns"))
  end
  if is_empty(blue::filter(fn(c) composite?(blue::get(c, :type)) end, cols)) ==
    false
    throw(
      error(
        :kueri_shape,
        "values #{name}: a literal row holds scalars; a list is one row per element"
      )
    )
  end
  rows = as_list(blue::get(opts, :rows))
  n = size(cols)
  bad = blue::filter(
    fn(r)
      list?(r) == false ||
        size(r) != n ||
        count_where(fn(v) value?(v) == false end, r) > 0
    end,
    rows
  )
  if is_empty(bad) == false
    throw(
      error(
        :kueri_shape,
        "values #{name}: every row is #{to_s(n)} literals (numbers, strings, booleans or nil)"
      )
    )
  end
  {
    kind: :source,
    name: name,
    file: nil,
    columns: cols,
    delim: nil,
    format: :values,
    rows: rows
  }
end

# The escape hatch: hand-written SQL, which must declare the columns it
# returns. Its dialect is :duckdb unless the author vouches `dialect: :core` —
# kueri cannot read it, so it cannot prove it portable. opts: name, sql,
# columns (q_col list), dialect.
def raw(opts)
  cols = as_list(blue::get(opts, :columns))
  if is_empty(cols)
    throw(
      error(
        :kueri_shape,
        "raw node #{name(blue::get(opts, :name))} declares no columns; the escape hatch must say what it returns"
      )
    )
  end
  d = blue::get(opts, :dialect)
  if d == nil
    d = :duckdb
  end
  if contains([:core, :duckdb], d) == false
    throw(error(:kueri_shape, "a raw node's dialect is :core or :duckdb"))
  end
  {
    kind: :raw,
    name: name(blue::get(opts, :name)),
    sql: blue::get(opts, :sql),
    columns: cols,
    dialect: d
  }
end

# A reference to an upstream source or model. The DAG is these nodes.
def ref(x)
  k = blue::get(x, :kind)
  if k != :source && k != :model
    throw(error(:kueri_shape, "q_ref takes a source or a model"))
  end
  {kind: :ref, target: x}
end

# A relation in from/join position: a source or model is referenced, a ref or
# raw node is itself.
def rel(x)
  k = blue::get(x, :kind)
  if k == :source || k == :model
    ref(x)
  elsif k == :ref || k == :raw
    x
  else
    throw(error(:kueri_shape, "a relation is a source, model, ref or raw node"))
  end
end

def rel_name(rel)
  if blue::get(rel, :kind) == :raw
    blue::get(rel, :name)
  else
    blue::get(blue::get(rel, :target), :name)
  end
end

# ── posture ────────────────────────────────────────────────────────────────

def reach_words()
  [:portable, :duckdb]
end

def rigor_words()
  [:loose, :locked]
end

# The posture a model declares, as {reach, rigor}. Unknown words and two words
# on one axis are refused where the model is built.
def posture_of(words)
  ws = as_list(words)
  bad = blue::filter(
    fn(w)
      (contains(reach_words(), w) || contains(rigor_words(), w)) == false
    end,
    ws
  )
  if is_empty(bad) == false
    throw(
      error(
        :kueri_shape,
        "unknown posture word #{to_s(first(bad))}; a posture takes a reach (:portable, :duckdb) and a rigor (:loose, :locked)"
      )
    )
  end
  reach = blue::filter(fn(w) contains(reach_words(), w) end, ws)
  rigor = blue::filter(fn(w) contains(rigor_words(), w) end, ws)
  if size(reach) > 1 || size(rigor) > 1
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
def reach_dialect(reach)
  if reach == :portable
    :core
  else
    :duckdb
  end
end

# ── models and stages ──────────────────────────────────────────────────────

# A model is one SELECT with a name. opts: name, from, pipeline, posture,
# contract (q_col list), materialize (:parquet, :csv, :table or :view;
# optional).
def model(opts)
  m = blue::get(opts, :materialize)
  if contains([nil, :parquet, :csv, :table, :view], m) == false
    throw(error(:kueri_shape, "materialize is :parquet, :csv, :table or :view"))
  end
  if blue::get(opts, :from) == nil
    throw(
      error(
        :kueri_shape,
        "model #{name(blue::get(opts, :name))} reads from nothing"
      )
    )
  end
  known(
    {
      kind: :model,
      name: name(blue::get(opts, :name)),
      from: rel(blue::get(opts, :from)),
      pipeline: as_list(blue::get(opts, :pipeline)),
      posture: posture_of(blue::get(opts, :posture)),
      contract: as_list(blue::get(opts, :contract)),
      materialize: m
    }
  )
end

# Composition by data: the same model with more stages after its own.
def then(model, stages)
  known(
    assoc(model, :pipeline, concat_lists(blue::get(model, :pipeline), stages))
  )
end

# A model with the columns its walk infers stored in it, as :known (nil when
# an upstream's are unknown). A model is built only from relations that
# already exist, and each upstream model carries its own, so the walk reads
# them in one step instead of walking the graph again. Without it a view over
# a shared upstream re-walked that upstream once per path to it (anaritikusu's
# `steps` feeds some twenty views). Measured 2026-09-25 over NuPastel's 79
# generated views: q_check of all of them 1147 → 104 ms, q_output 1162 →
# 102 ms, and the whole script 2.85 s → 0.47 s with moji's includes fix.
def known(m)
  assoc(m, :known, blue::get(walk(m), :cols))
end

# A named output: a select item or a group aggregate.
def as(name, expr)
  {kind: :as, name: kueri::name(name), expr: kueri::expr(expr)}
end

def agg(name, expr)
  as(name, expr)
end

# An aggregate over only the rows where `pred` holds, named.
def agg_where(name, agg, pred)
  as(name, filtered(agg, pred))
end

def item(i)
  if keyword?(i) || string?(i)
    as(i, c(i))
  else
    i
  end
end

# Keep these columns (keywords) and computed ones (q_as), in this order.
def select(items)
  {kind: :select, items: map(fn(i) item(i) end, items)}
end

# Add one computed column; every row stays.
def derive(name, expr)
  {kind: :derive, name: kueri::name(name), expr: kueri::expr(expr)}
end

# One row per element of a list: each row repeats once per element of
# `list_expr`, the element in the new column `name`, and a row whose list is
# empty or NULL is dropped (unnest). DuckDB only.
def explode(name, list_expr)
  {kind: :explode, name: kueri::name(name), expr: expr(list_expr)}
end

# Keep the rows where `pred` holds.
# waive B0013: `filter` is a builtin kueri also uses, so the prefix stays; kueri::filter names it too
def q_filter(pred)
  {kind: :filter, pred: expr(pred)}
end

# One row per distinct key; `aggs` are q_agg / q_agg_where outputs.
def group(keys, aggs)
  {
    kind: :group,
    keys: map(fn(k) name(k) end, as_list(keys)),
    aggs: as_list(aggs)
  }
end

# JOIN … USING (keys): the keys appear once, then the left's other columns,
# then the right's.
# waive B0013: `join` is a builtin kueri also uses, so the prefix stays; kueri::join names it too
def q_join(rel, keys)
  {
    kind: :join,
    how: :inner,
    rel: kueri::rel(rel),
    keys: map(fn(k) name(k) end, keys)
  }
end

def left_join(rel, keys)
  {
    kind: :join,
    how: :left,
    rel: kueri::rel(rel),
    keys: map(fn(k) name(k) end, keys)
  }
end

# ASOF LEFT JOIN … USING (keys): the LAST key matches inexactly — each left
# row takes the right row whose key is the greatest at or below its own (the
# right side as of the left row's moment); the other keys match exactly. A
# left row with no match keeps NULLs. DuckDB only.
def asof_left_join(rel, keys)
  {
    kind: :join,
    how: :asof_left,
    rel: kueri::rel(rel),
    keys: map(fn(k) name(k) end, keys)
  }
end

def sort(keys)
  {kind: :sort, keys: map(fn(k) key(k) end, keys)}
end

def limit(n)
  if integer?(n) == false || n < 0
    throw(error(:kueri_shape, "q_limit takes a count of zero or more"))
  end
  {kind: :limit, n: n}
end

def stage_exprs(stage)
  k = blue::get(stage, :kind)
  if k == :filter
    [blue::get(stage, :pred)]
  elsif k == :derive || k == :explode
    [blue::get(stage, :expr)]
  elsif k == :select
    map(fn(i) blue::get(i, :expr) end, blue::get(stage, :items))
  elsif k == :group
    map(fn(a) blue::get(a, :expr) end, blue::get(stage, :aggs))
  else
    []
  end
end

def label(i, stage)
  "stage #{to_s(i + 1)} (#{to_s(blue::get(stage, :kind))})"
end

# ── walking expressions ────────────────────────────────────────────────────

def kids(e)
  if blue::get(e, :kind) == :agg && blue::get(e, :where) != nil
    push(as_list(blue::get(e, :args)), blue::get(e, :where))
  else
    as_list(blue::get(e, :args))
  end
end

# Every node of an expression, the root first.
def nodes(e)
  cons(e, flat_map(fn(c) nodes(c) end, kids(e)))
end

def nodes_of(e, kind)
  blue::filter(fn(n) blue::get(n, :kind) == kind end, nodes(e))
end

def node_refs(n)
  k = blue::get(n, :kind)
  if k == :col
    [blue::get(n, :name)]
  elsif k == :agg
    key_names(blue::get(n, :order))
  elsif k == :win
    concat_lists(blue::get(n, :partition), key_names(blue::get(n, :order)))
  else
    []
  end
end

# The column names an expression reads.
def refs(e)
  unique(flat_map(fn(n) node_refs(n) end, nodes(e)))
end

def outside_aggs(e)
  if blue::get(e, :kind) == :agg
    []
  else
    cons(e, flat_map(fn(c) outside_aggs(c) end, kids(e)))
  end
end

# The column names read OUTSIDE any aggregate — in a group, each must be a key.
def bare_refs(e)
  unique(flat_map(fn(n) node_refs(n) end, outside_aggs(e)))
end

def has?(e, kind)
  is_empty(nodes_of(e, kind)) == false
end

def nested_agg?(e)
  is_empty(
    blue::filter(
      fn(a)
        is_empty(flat_map(fn(c) nodes_of(c, :agg) end, kids(a))) == false
      end,
      nodes_of(e, :agg)
    )
  ) ==
    false
end

# ── refusals ───────────────────────────────────────────────────────────────

def refusal_kind(r)
  first(r)
end

def refusal_why(r)
  last(r)
end

def refusal_kinds(model)
  map(fn(r) refusal_kind(r) end, refusals(model))
end

def unknown_refusals(names, cols, where)
  if cols == nil
    []
  else
    missing = as_list(difference(unique(names), cols))
    if is_empty(missing)
      []
    else
      [
        [
          :kueri_shape,
          "#{where}: unknown column #{blue::join(missing, ", ")}; the input has #{blue::join(cols, ", ")}"
        ]
      ]
    end
  end
end

def dup_refusals(names, where)
  if size(unique(names)) == size(names)
    []
  else
    [
      [
        :kueri_shape,
        "#{where}: an output name repeats among #{blue::join(names, ", ")}"
      ]
    ]
  end
end

# What no expression may hold outside a group: an aggregate. And the order
# rules every stage shares.
def expr_refusals(e, where, aggs_allowed, windows_allowed)
  a = if aggs_allowed == false && has?(e, :agg)
    [
      [
        :kueri_shape,
        "#{where}: an aggregate outside a group; aggregate in a group stage, then use its name"
      ]
    ]
  else
    []
  end
  w = if windows_allowed == false && has?(e, :win)
    [
      [
        :kueri_shape,
        "#{where}: a window here; derive it first, then use its name"
      ]
    ]
  else
    []
  end
  wasted = blue::filter(
    fn(n)
      is_empty(blue::get(n, :order)) == false &&
        contains(order_sensitive_fns(), blue::get(n, :fn)) == false
    end,
    concat_lists(nodes_of(e, :agg), nodes_of(e, :win))
  )
  o = map(
    fn(n)
      [
        :kueri_shape,
        "#{where}: an order on #{blue::get(n, :fn)} changes nothing; only #{blue::join(order_sensitive_fns(), " and ")} read one"
      ]
    end,
    wasted
  )
  concat_lists(a, concat_lists(w, o))
end

def group_item_refusals(item, keys, where)
  e = blue::get(item, :expr)
  n = blue::get(item, :name)
  none = if has?(e, :agg)
    []
  else
    [
      [
        :kueri_shape,
        "#{where}: #{n} aggregates nothing; a plain column belongs in the keys"
      ]
    ]
  end
  nested = if nested_agg?(e)
    [[:kueri_shape, "#{where}: #{n} nests an aggregate inside an aggregate"]]
  else
    []
  end
  loose = as_list(difference(bare_refs(e), keys))
  outside = if is_empty(loose)
    []
  else
    [
      [
        :kueri_shape,
        "#{where}: #{n} reads #{blue::join(loose, ", ")} outside an aggregate, and it is not a key"
      ]
    ]
  end
  concat_lists(
    none,
    concat_lists(
      nested,
      concat_lists(outside, expr_refusals(e, where, true, false))
    )
  )
end

def stage_refusals(stage, cols, where, next_kind)
  k = blue::get(stage, :kind)
  if k == :filter
    e = blue::get(stage, :pred)
    concat_lists(
      expr_refusals(e, where, false, false),
      unknown_refusals(refs(e), cols, where)
    )
  elsif k == :derive
    e = blue::get(stage, :expr)
    dup = if cols != nil && contains(cols, blue::get(stage, :name))
      [
        [
          :kueri_shape,
          "#{where}: #{blue::get(stage, :name)} is already a column"
        ]
      ]
    else
      []
    end
    concat_lists(
      dup,
      concat_lists(
        expr_refusals(e, where, false, true),
        unknown_refusals(refs(e), cols, where)
      )
    )
  elsif k == :explode
    e = blue::get(stage, :expr)
    dup = if cols != nil && contains(cols, blue::get(stage, :name))
      [
        [
          :kueri_shape,
          "#{where}: #{blue::get(stage, :name)} is already a column"
        ]
      ]
    else
      []
    end
    concat_lists(
      dup,
      concat_lists(
        expr_refusals(e, where, false, false),
        unknown_refusals(refs(e), cols, where)
      )
    )
  elsif k == :select
    items = blue::get(stage, :items)
    per = flat_map(
      fn(i)
        concat_lists(
          expr_refusals(blue::get(i, :expr), where, false, false),
          unknown_refusals(refs(blue::get(i, :expr)), cols, where)
        )
      end,
      items
    )
    concat_lists(
      per,
      dup_refusals(map(fn(i) blue::get(i, :name) end, items), where)
    )
  elsif k == :group
    keys = blue::get(stage, :keys)
    aggs = blue::get(stage, :aggs)
    empty = if is_empty(keys) && is_empty(aggs)
      [[:kueri_shape, "#{where}: a group with no keys and no aggregates"]]
    else
      []
    end
    reads = concat_lists(
      keys,
      flat_map(fn(a) refs(blue::get(a, :expr)) end, aggs)
    )
    per = flat_map(fn(a) group_item_refusals(a, keys, where) end, aggs)
    concat_lists(
      empty,
      concat_lists(
        unknown_refusals(reads, cols, where),
        concat_lists(
          dup_refusals(
            concat_lists(keys, map(fn(a) blue::get(a, :name) end, aggs)),
            where
          ),
          per
        )
      )
    )
  elsif k == :join
    join_refusals(stage, cols, where)
  elsif k == :sort
    discarded = if next_kind != nil && next_kind != :limit
      [
        [
          :kueri_shape,
          "#{where}: the next stage (#{to_s(next_kind)}) discards this order; sort last, or just before a limit"
        ]
      ]
    else
      []
    end
    concat_lists(
      discarded,
      unknown_refusals(key_names(blue::get(stage, :keys)), cols, where)
    )
  else
    []
  end
end

def join_refusals(stage, cols, where)
  keys = blue::get(stage, :keys)
  rc = rel_columns(blue::get(stage, :rel))
  none = if is_empty(keys)
    [[:kueri_shape, "#{where}: a join needs at least one USING key"]]
  else
    []
  end
  left = unknown_refusals(keys, cols, where)
  right = unknown_refusals(keys, rc, "#{where} (right side)")
  both = if cols == nil || rc == nil
    []
  else
    as_list(difference(intersection(cols, rc), keys))
  end
  clash = if is_empty(both)
    []
  else
    [
      [
        :kueri_shape,
        "#{where}: #{blue::join(both, ", ")} on both sides of the join; rename it or make it a key"
      ]
    ]
  end
  concat_lists(none, concat_lists(left, concat_lists(right, clash)))
end

# The columns a stage returns, or nil when its input's are unknown.
def stage_output(stage, cols)
  k = blue::get(stage, :kind)
  if k == :derive || k == :explode
    if cols == nil
      nil
    else
      push(cols, blue::get(stage, :name))
    end
  elsif k == :select
    map(fn(i) blue::get(i, :name) end, blue::get(stage, :items))
  elsif k == :group
    concat_lists(
      blue::get(stage, :keys),
      map(fn(a) blue::get(a, :name) end, blue::get(stage, :aggs))
    )
  elsif k == :join
    rc = rel_columns(blue::get(stage, :rel))
    if cols == nil || rc == nil
      nil
    else
      keys = blue::get(stage, :keys)
      concat_lists(
        keys,
        concat_lists(
          as_list(difference(cols, keys)),
          as_list(difference(rc, keys))
        )
      )
    end
  else
    cols
  end
end

def next_kind(stages, i)
  if i + 1 < size(stages)
    blue::get(nth(i + 1, stages), :kind)
  else
    nil
  end
end

# Thread the schema through the pipeline: {cols, refusals}.
def walk(model)
  stages = blue::get(model, :pipeline)
  start = {cols: rel_columns(blue::get(model, :from)), refusals: []}
  reduce(
    fn(acc, ix)
      walk_stage(acc, first(ix), last(ix), next_kind(stages, first(ix)))
    end,
    start,
    enumerate(stages)
  )
end

def walk_stage(acc, i, stage, next_kind)
  cols = blue::get(acc, :cols)
  found = stage_refusals(stage, cols, label(i, stage), next_kind)
  {
    cols: stage_output(stage, cols),
    refusals: concat_lists(blue::get(acc, :refusals), found)
  }
end

# The column names a model returns, inferred through its pipeline; nil when an
# upstream's columns are unknown.
def output(model)
  blue::get(walk(model), :cols)
end

# What a downstream model sees: the contract when declared, the inference
# otherwise.
def model_columns(model)
  cn = col_names(blue::get(model, :contract))
  if is_empty(cn) == false
    cn
  elsif blue::get(model, :known) != nil
    blue::get(model, :known)
  else
    output(model)
  end
end

def rel_columns(rel)
  if blue::get(rel, :kind) == :raw
    col_names(blue::get(rel, :columns))
  else
    t = blue::get(rel, :target)
    if blue::get(t, :kind) == :source
      col_names(blue::get(t, :columns))
    else
      model_columns(t)
    end
  end
end

# Constructs with no core form, as [what, where].
def duckdb_uses(model)
  from_uses = rel_uses(blue::get(model, :from), "the from relation")
  stage_uses = flat_map(
    fn(ix) kueri::stage_uses(last(ix), label(first(ix), last(ix))) end,
    enumerate(blue::get(model, :pipeline))
  )
  concat_lists(from_uses, stage_uses)
end

def stage_uses(stage, where)
  nodes = flat_map(fn(e) kueri::nodes(e) end, stage_exprs(stage))
  only = blue::filter(fn(n) duckdb_node?(n) end, nodes)
  uses = map(fn(n) [node_label(n), where] end, only)
  k = blue::get(stage, :kind)
  if k == :join
    asof = if blue::get(stage, :how) == :asof_left
      [["an asof join", where]]
    else
      []
    end
    concat_lists(
      uses,
      concat_lists(asof, rel_uses(blue::get(stage, :rel), where))
    )
  elsif k == :explode
    push(uses, ["unnest", where])
  else
    uses
  end
end

# An expression node with no core form: a DuckDB-only aggregate, or a struct
# field.
def duckdb_node?(n)
  k = blue::get(n, :kind)
  k == :field || k == :agg && contains(duckdb_only_fns(), blue::get(n, :fn))
end

def node_label(n)
  if blue::get(n, :kind) == :field
    "struct field #{blue::get(n, :name)}"
  else
    blue::get(n, :fn)
  end
end

def rel_uses(rel, where)
  if blue::get(rel, :kind) == :raw && blue::get(rel, :dialect) == :duckdb
    [["raw node #{blue::get(rel, :name)}", where]]
  else
    []
  end
end

def reach_refusals(model)
  reach = blue::get(blue::get(model, :posture), :reach)
  if reach_dialect(reach) == :duckdb
    []
  else
    map(
      fn(u)
        [
          :kueri_reach,
          "model #{blue::get(model, :name)} is held at :#{to_s(reach)}, but #{first(u)} at #{last(u)} has no core form (its floor is :duckdb)"
        ]
      end,
      duckdb_uses(model)
    )
  end
end

def contract_refusals(model, out)
  cn = col_names(blue::get(model, :contract))
  if is_empty(cn) || out == nil || equal_lists(cn, out)
    []
  else
    [
      [
        :kueri_contract,
        "model #{blue::get(model, :name)} declares #{blue::join(cn, ", ")} but returns #{blue::join(out, ", ")}"
      ]
    ]
  end
end

def locked_refusals(model, out)
  name = blue::get(model, :name)
  stages = blue::get(model, :pipeline)
  contract = if is_empty(blue::get(model, :contract))
    [
      [
        :kueri_locked,
        "model #{name} is :locked and declares no contract; a locked model states the columns it returns"
      ]
    ]
  elsif out == nil
    [
      [
        :kueri_locked,
        "model #{name} is :locked, but the columns upstream of it are not declared, so its contract cannot be verified"
      ]
    ]
  else
    []
  end
  unordered = flat_map(
    fn(ix)
      map(
        fn(n)
          [
            :kueri_locked,
            "#{label(first(ix), last(ix))}: #{blue::get(n, :fn)} with no order is not deterministic; give it one with q_ordered"
          ]
        end,
        blue::filter(
          fn(n)
            contains(order_sensitive_fns(), blue::get(n, :fn)) &&
              is_empty(blue::get(n, :order))
          end,
          flat_map(fn(e) nodes(e) end, stage_exprs(last(ix)))
        )
      )
    end,
    enumerate(stages)
  )
  limits = flat_map(
    fn(ix) locked_limit(stages, first(ix), last(ix)) end,
    enumerate(stages)
  )
  concat_lists(contract, concat_lists(unordered, limits))
end

def locked_limit(stages, i, stage)
  if blue::get(stage, :kind) != :limit
    []
  elsif i > 0 && blue::get(nth(i - 1, stages), :kind) == :sort
    []
  else
    [
      [
        :kueri_locked,
        "#{label(i, stage)}: a limit with no sort right before it keeps arbitrary rows"
      ]
    ]
  end
end

# Every violation, as data: [kind, why]. Empty when the model holds.
def refusals(model)
  walked = walk(model)
  out = blue::get(walked, :cols)
  rigor = if blue::get(blue::get(model, :posture), :rigor) == :locked
    locked_refusals(model, out)
  else
    []
  end
  concat_lists(
    blue::get(walked, :refusals),
    concat_lists(
      reach_refusals(model),
      concat_lists(contract_refusals(model, out), rigor)
    )
  )
end

def refuse(refusals)
  if is_empty(refusals) == false
    throw(
      error(
        refusal_kind(first(refusals)),
        blue::join(map(fn(r) refusal_why(r) end, refusals), "; ")
      )
    )
  end
  nil
end

# The model, or a thrown error naming every violation (its kind is the first's).
def check(model)
  refuse(refusals(model))
  model
end

def dialect_refusals(model, dialect)
  if dialect == :duckdb
    []
  else
    map(
      fn(u)
        [
          :kueri_dialect,
          "#{first(u)} at #{last(u)} has no core form; render model #{blue::get(model, :name)} with :duckdb"
        ]
      end,
      duckdb_uses(model)
    )
  end
end

# blue shift's two questions for a model: the lowest reach that holds it, and
# what holds it there.
def shift(model)
  uses = duckdb_uses(model)
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
# so a block with a window never takes one). An explode's unnest joins only a
# select list that has nothing in it yet, and a window never joins a select
# list that unnests: which rows a window sees beside an unnest is DuckDB's
# evaluation order, not a rule this renderer should lean on. A filter that
# does not read the element still moves before the unnest, which is exact.

def block(from)
  {
    from: from,
    joins: [],
    where: [],
    grouped: false,
    keys: [],
    aggs: [],
    having: [],
    items: nil,
    derives: [],
    window: false,
    exploded: false,
    qualify: [],
    order: [],
    order_all: false,
    limit: nil,
    phase: 0
  }
end

def derived_names(b)
  map(fn(d) blue::get(d, :name) end, blue::get(b, :derives))
end

def fits?(b, stage, dialect)
  k = blue::get(stage, :kind)
  p = blue::get(b, :phase)
  if k == :join
    p <= 2
  elsif k == :filter
    if p <= 4
      true
    elsif pushable?(b, stage)
      true
    else
      p <= 6 && blue::get(b, :window) && dialect == :duckdb
    end
  elsif k == :group
    p <= 2
  elsif k == :derive
    if p <= 2
      true
    else
      p == 5 &&
        blue::get(b, :items) == nil &&
        is_empty(
          as_list(intersection(refs(blue::get(stage, :expr)), derived_names(b)))
        ) &&
        (blue::get(b, :exploded) && has?(blue::get(stage, :expr), :win)) ==
          false
    end
  elsif k == :explode
    p <= 2
  elsif k == :select
    p <= 2
  elsif k == :sort
    p <= 6
  else
    p <= 7
  end
end

def set(b, key, value, phase)
  assoc(assoc(b, key, value), :phase, phase)
end

# A filter that can join the WHERE of a block whose select list holds only
# row-wise derives it does not read.
def pushable?(b, stage)
  blue::get(b, :phase) == 5 &&
    blue::get(b, :items) == nil &&
    blue::get(b, :grouped) == false &&
    blue::get(b, :window) == false &&
    is_empty(
      as_list(intersection(refs(blue::get(stage, :pred)), derived_names(b)))
    )
end

# A filter after a group reads the aggregates by name; HAVING needs them
# spelled out.
def subst(e, items)
  k = blue::get(e, :kind)
  if k == :col
    hit = find_first(
      fn(i) blue::get(i, :name) == blue::get(e, :name) end,
      items
    )
    if hit == nil
      e
    else
      blue::get(hit, :expr)
    end
  elsif k == :agg || k == :win || k == :lit
    e
  else
    assoc(e, :args, map(fn(a) subst(a, items) end, blue::get(e, :args)))
  end
end

def into(b, stage, _dialect)
  k = blue::get(stage, :kind)
  p = blue::get(b, :phase)
  if k == :join
    set(b, :joins, push(blue::get(b, :joins), stage), kazu::max(p, 1))
  elsif k == :filter
    if p <= 2
      set(b, :where, push(blue::get(b, :where), blue::get(stage, :pred)), 2)
    elsif pushable?(b, stage)
      assoc(b, :where, push(blue::get(b, :where), blue::get(stage, :pred)))
    elsif p <= 4
      set(
        b,
        :having,
        push(
          blue::get(b, :having),
          subst(blue::get(stage, :pred), blue::get(b, :aggs))
        ),
        4
      )
    else
      set(b, :qualify, push(blue::get(b, :qualify), blue::get(stage, :pred)), 6)
    end
  elsif k == :group
    set(
      assoc(assoc(b, :grouped, true), :keys, blue::get(stage, :keys)),
      :aggs,
      blue::get(stage, :aggs),
      3
    )
  elsif k == :derive
    d = as(blue::get(stage, :name), blue::get(stage, :expr))
    set(
      assoc(
        b,
        :window,
        blue::get(b, :window) || has?(blue::get(stage, :expr), :win)
      ),
      :derives,
      push(blue::get(b, :derives), d),
      5
    )
  elsif k == :explode
    d = as(
      blue::get(stage, :name),
      {kind: :unnest, args: [blue::get(stage, :expr)]}
    )
    set(assoc(b, :exploded, true), :derives, push(blue::get(b, :derives), d), 5)
  elsif k == :select
    set(b, :items, blue::get(stage, :items), 5)
  elsif k == :sort
    set(b, :order, blue::get(stage, :keys), 7)
  else
    set(b, :limit, blue::get(stage, :n), 8)
  end
end

def lower_stage(acc, stage, dialect)
  b = blue::get(acc, :cur)
  if fits?(b, stage, dialect)
    assoc(acc, :cur, into(b, stage, dialect))
  else
    name = "step_#{to_s(size(blue::get(acc, :done)) + 1)}"
    {
      done: push(blue::get(acc, :done), [name, b]),
      cur: into(block(name), stage, dialect)
    }
  end
end

# The pipeline as closed CTE blocks ([name, block] pairs) and a final block.
def lower(model, dialect)
  start = {done: [], cur: block(rel_name(blue::get(model, :from)))}
  reduce(
    fn(acc, s) lower_stage(acc, s, dialect) end,
    start,
    blue::get(model, :pipeline)
  )
end

# A locked model's output order is made total: its own keys, then every other
# contract column. In DuckDB, when that is exactly the column order, it is
# ORDER BY ALL.
def lock_order(model, b, dialect)
  if blue::get(blue::get(model, :posture), :rigor) != :locked
    b
  else
    keys = blue::get(b, :order)
    have = key_names(keys)
    extra = map(
      fn(n) key(n) end,
      blue::filter(
        fn(n) contains(have, n) == false end,
        col_names(blue::get(model, :contract))
      )
    )
    total = concat_lists(keys, extra)
    all_asc = is_empty(blue::filter(fn(k) blue::get(k, :desc) end, total))
    assoc(
      assoc(b, :order, total),
      :order_all,
      dialect == :duckdb &&
        all_asc &&
        equal_lists(key_names(total), col_names(blue::get(model, :contract)))
    )
  end
end

# ── rendering ──────────────────────────────────────────────────────────────

def prec(e)
  k = blue::get(e, :kind)
  if k == :op
    blue::get(e, :prec)
  elsif k == :not
    3
  elsif k == :postfix
    4
  else
    10
  end
end

# A child in operator position. Lower precedence is parenthesized; so is equal
# precedence on the right (the tree's grouping is kept exactly, which matters
# for float arithmetic) and on either side of a comparison.
def operand(child, parent_prec, tie_wraps, dialect)
  s = render_expr(child, dialect)
  cp = prec(child)
  if cp < parent_prec || tie_wraps && cp == parent_prec
    "(#{s})"
  else
    s
  end
end

def render_lit(e, dialect)
  t = blue::get(e, :type)
  v = blue::get(e, :value)
  if t == :int
    to_s(v)
  elsif t == :double
    if dialect == :duckdb
      "#{float_text(v)}::DOUBLE"
    else
      "CAST(#{float_text(v)} AS DOUBLE PRECISION)"
    end
  elsif t == :str
    quote_str(v)
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

def render_key(k)
  if blue::get(k, :desc)
    "#{ident(blue::get(k, :name))} DESC"
  else
    ident(blue::get(k, :name))
  end
end

def order_suffix(keys)
  if is_empty(keys)
    ""
  else
    " ORDER BY #{blue::join(map(fn(k) render_key(k) end, keys), ", ")}"
  end
end

# An aggregate. The FILTER-where form is DuckDB's; core moves the predicate
# into a CASE inside the aggregate, which every mainstream engine reads.
def render_agg(e, dialect)
  f = blue::get(e, :fn)
  if contains(duckdb_only_fns(), f) && dialect != :duckdb
    throw(
      error(:kueri_dialect, "#{f} has no core form; render it with :duckdb")
    )
  end
  args = blue::get(e, :args)
  pred = blue::get(e, :where)
  order = order_suffix(blue::get(e, :order))
  shown = if is_empty(args)
    "*"
  else
    blue::join(map(fn(a) render_expr(a, dialect) end, args), ", ")
  end
  if pred == nil
    "#{f}(#{shown}#{order})"
  elsif dialect == :duckdb
    "#{f}(#{shown}#{order}) FILTER (WHERE #{render_expr(pred, dialect)})"
  else
    inner = if is_empty(args)
      "1"
    else
      render_expr(first(args), dialect)
    end
    "#{f}(CASE WHEN #{render_expr(pred, dialect)} THEN #{inner} END#{order})"
  end
end

def render_win(e, dialect)
  part = if is_empty(blue::get(e, :partition))
    []
  else
    [
      "PARTITION BY #{blue::join(map(fn(p) ident(p) end, blue::get(e, :partition)), ", ")}"
    ]
  end
  ord = if is_empty(blue::get(e, :order))
    []
  else
    [
      "ORDER BY #{blue::join(map(fn(k) render_key(k) end, blue::get(e, :order)), ", ")}"
    ]
  end
  args = blue::join(
    map(fn(a) render_expr(a, dialect) end, as_list(blue::get(e, :args))),
    ", "
  )
  "#{blue::get(e, :fn)}(#{args}) OVER (#{blue::join(concat_lists(part, ord), " ")})"
end

# One expression, in one dialect. The only place an expression becomes text.
def render_expr(e, dialect)
  k = blue::get(e, :kind)
  if k == :col
    ident(blue::get(e, :name))
  elsif k == :lit
    render_lit(e, dialect)
  elsif k == :op
    p = blue::get(e, :prec)
    args = blue::get(e, :args)
    "#{operand(first(args), p, p == 4, dialect)} #{blue::get(e, :op)} #{operand(last(args), p, true, dialect)}"
  elsif k == :not
    "NOT #{operand(first(blue::get(e, :args)), 3, false, dialect)}"
  elsif k == :fn
    "#{blue::get(e, :name)}(#{blue::join(map(fn(a) render_expr(a, dialect) end, blue::get(e, :args)), ", ")})"
  elsif k == :cast
    "CAST(#{render_expr(first(blue::get(e, :args)), dialect)} AS #{type_sql(blue::get(e, :type), dialect)})"
  elsif k == :agg
    render_agg(e, dialect)
  elsif k == :win
    render_win(e, dialect)
  elsif k == :postfix
    "#{operand(first(blue::get(e, :args)), 4, true, dialect)} #{blue::get(e, :op)}"
  elsif k == :case
    args = blue::get(e, :args)
    "CASE WHEN #{render_expr(nth(0, args), dialect)} THEN #{render_expr(nth(1, args), dialect)} ELSE #{render_expr(nth(2, args), dialect)} END"
  elsif k == :field
    duckdb_floor(dialect, "a struct field")
    "(#{render_expr(first(blue::get(e, :args)), dialect)}).#{ident(blue::get(e, :name))}"
  elsif k == :unnest
    duckdb_floor(dialect, "unnest")
    "unnest(#{render_expr(first(blue::get(e, :args)), dialect)})"
  else
    throw(error(:kueri_shape, "no renderer arm for a #{to_s(k)} node"))
  end
end

# The renderer's own floor: a DuckDB-only construct never renders as core,
# whichever door it came through.
def duckdb_floor(dialect, what)
  if dialect != :duckdb
    throw(
      error(:kueri_dialect, "#{what} has no core form; render with :duckdb")
    )
  end
end

def render_item(item, dialect)
  e = blue::get(item, :expr)
  if blue::get(e, :kind) == :col &&
    blue::get(e, :name) == blue::get(item, :name)
    ident(blue::get(item, :name))
  else
    "#{render_expr(e, dialect)} AS #{ident(blue::get(item, :name))}"
  end
end

def render_conj(preds, dialect)
  render_expr(
    reduce(fn(a, p) q_and(a, p) end, first(preds), rest(preds)),
    dialect
  )
end

def select_texts(b, dialect)
  if blue::get(b, :grouped)
    concat_lists(
      map(fn(k) ident(k) end, blue::get(b, :keys)),
      map(fn(a) render_item(a, dialect) end, blue::get(b, :aggs))
    )
  elsif blue::get(b, :items) != nil
    map(fn(i) render_item(i, dialect) end, blue::get(b, :items))
  else
    cons("*", map(fn(d) render_item(d, dialect) end, blue::get(b, :derives)))
  end
end

# `  item,` per line, the last without its comma.
def list_lines(items)
  n = size(items)
  map(
    fn(ix)
      if first(ix) + 1 < n
        "  #{last(ix)},"
      else
        "  #{last(ix)}"
      end
    end,
    enumerate(items)
  )
end

def clause(word, preds, dialect)
  if is_empty(preds)
    []
  else
    ["#{word} #{render_conj(preds, dialect)}"]
  end
end

def join_line(j, dialect)
  how = blue::get(j, :how)
  word = if how == :left
    "LEFT JOIN"
  elsif how == :asof_left
    duckdb_floor(dialect, "an asof join")
    "ASOF LEFT JOIN"
  else
    "JOIN"
  end
  "#{word} #{ident(rel_name(blue::get(j, :rel)))} USING (#{blue::join(map(fn(k) ident(k) end, blue::get(j, :keys)), ", ")})"
end

# One SELECT, as lines, clauses in SQL's order.
def block_lines(b, dialect)
  sel = select_texts(b, dialect)
  head = if size(sel) == 1
    ["SELECT #{first(sel)}"]
  else
    cons("SELECT", list_lines(sel))
  end
  from = cons(
    "FROM #{ident(blue::get(b, :from))}",
    map(fn(j) join_line(j, dialect) end, blue::get(b, :joins))
  )
  group = if blue::get(b, :grouped) && is_empty(blue::get(b, :keys)) == false
    [
      "GROUP BY #{blue::join(map(fn(k) ident(k) end, blue::get(b, :keys)), ", ")}"
    ]
  else
    []
  end
  order = if blue::get(b, :order_all)
    ["ORDER BY ALL"]
  elsif is_empty(blue::get(b, :order))
    []
  else
    [
      "ORDER BY #{blue::join(map(fn(k) render_key(k) end, blue::get(b, :order)), ", ")}"
    ]
  end
  limit = if blue::get(b, :limit) == nil
    []
  else
    ["LIMIT #{to_s(blue::get(b, :limit))}"]
  end
  tail = concat_lists(
    clause("WHERE", blue::get(b, :where), dialect),
    concat_lists(
      group,
      concat_lists(
        clause("HAVING", blue::get(b, :having), dialect),
        concat_lists(
          clause("QUALIFY", blue::get(b, :qualify), dialect),
          concat_lists(order, limit)
        )
      )
    )
  )
  concat_lists(head, concat_lists(from, tail))
end

def indent(lines)
  map(fn(l) "  #{l}" end, lines)
end

def raws(model)
  rels = cons(
    blue::get(model, :from),
    map(
      fn(s) blue::get(s, :rel) end,
      blue::filter(
        fn(s) blue::get(s, :kind) == :join end,
        blue::get(model, :pipeline)
      )
    )
  )
  unique_by(
    fn(r) blue::get(r, :name) end,
    blue::filter(fn(r) blue::get(r, :kind) == :raw end, rels)
  )
end

def render_raw(r, dialect)
  if blue::get(r, :dialect) == :duckdb && dialect != :duckdb
    throw(
      error(
        :kueri_dialect,
        "raw node #{blue::get(r, :name)} is not vouched portable; render it with :duckdb"
      )
    )
  end
  "#{ident(blue::get(r, :name))} AS (\n#{blue::get(r, :sql)}\n)"
end

# The query text, unchecked: q_render is the door that checks first.
def render_query(model, dialect)
  low = lower(model, dialect)
  final = lock_order(model, blue::get(low, :cur), dialect)
  raw_ctes = map(fn(r) render_raw(r, dialect) end, raws(model))
  step_ctes = map(
    fn(c)
      "#{first(c)} AS (\n#{blue::join(indent(block_lines(last(c), dialect)), "\n")}\n)"
    end,
    blue::get(low, :done)
  )
  ctes = concat_lists(raw_ctes, step_ctes)
  body = blue::join(block_lines(final, dialect), "\n")
  if is_empty(ctes)
    body
  else
    "WITH #{blue::join(ctes, ", ")}\n#{body}"
  end
end

# A model as one SQL query in `dialect` (:core or :duckdb), with no trailing
# semicolon. Checks first, then the dialect floor: it throws, never degrades.
def render(model, dialect)
  if contains([:core, :duckdb], dialect) == false
    throw(error(:kueri_shape, "a dialect is :core or :duckdb"))
  end
  check(model)
  refuse(dialect_refusals(model, dialect))
  render_query(model, dialect)
end

# ── around the query: loading, materializing, files ────────────────────────

def delim_sql(d)
  if d == :comma
    "','"
  else
    "'\\t'"
  end
end

# A view that loads a source with its declared columns: a delimited file
# (read_csv) or JSON Lines (read_json), DuckDB only; or literal rows
# (q_values), in either dialect, where `path` is not read.
def render_load(source, path, dialect)
  f = blue::get(source, :format)
  if f == :values
    render_values_load(source, dialect)
  else
    reader = if f == :jsonl
      "read_json"
    else
      "read_csv"
    end
    if dialect != :duckdb
      throw(
        error(
          :kueri_dialect,
          "#{reader} has no core form; load source #{blue::get(source, :name)} with :duckdb"
        )
      )
    end
    cols = blue::join(
      map(
        fn(c)
          "#{quote_str(blue::get(c, :name))}: #{quote_str(type_sql(blue::get(c, :type), :duckdb))}"
        end,
        blue::get(source, :columns)
      ),
      ", "
    )
    how = if f == :jsonl
      "format = 'newline_delimited'"
    else
      "delim = #{delim_sql(blue::get(source, :delim))}, header = true"
    end
    "CREATE OR REPLACE VIEW #{ident(blue::get(source, :name))} AS\nSELECT * FROM #{reader}(#{quote_str(path)}, #{how}, columns = {#{cols}})"
  end
end

# Literal rows as a view, each column cast to its declared type (so a column
# that is all NULL is still typed). No rows: the typed columns and no row.
def render_values_load(source, dialect)
  cols = blue::get(source, :columns)
  typed = blue::join(
    map(
      fn(c)
        "CAST(#{ident(blue::get(c, :name))} AS #{type_sql(blue::get(c, :type), dialect)}) AS #{ident(blue::get(c, :name))}"
      end,
      cols
    ),
    ", "
  )
  rows = blue::get(source, :rows)
  body = if is_empty(rows)
    "SELECT #{blue::join(map(fn(c) "CAST(NULL AS #{type_sql(blue::get(c, :type), dialect)}) AS #{ident(blue::get(c, :name))}" end, cols), ", ")} WHERE FALSE"
  else
    lines = map(
      fn(r)
        "(#{blue::join(map(fn(v) render_lit(lit(v), dialect) end, r), ", ")})"
      end,
      rows
    )
    "SELECT #{typed}\nFROM (VALUES\n  #{blue::join(lines, ",\n  ")}\n) AS t(#{blue::join(map(fn(c) ident(blue::get(c, :name)) end, cols), ", ")})"
  end
  "CREATE OR REPLACE VIEW #{ident(blue::get(source, :name))} AS\n#{body}"
end

# Where a model's materialization lands by default: <name>.parquet or .csv.
def materialize_target(model)
  m = blue::get(model, :materialize)
  if m == :parquet
    "#{blue::get(model, :name)}.parquet"
  elsif m == :csv
    "#{blue::get(model, :name)}.csv"
  else
    nil
  end
end

# The statement that writes a model out: COPY … TO a zstd Parquet or a headed
# CSV (DuckDB), or CREATE TABLE … AS / CREATE OR REPLACE VIEW … AS (both
# dialects).
def render_materialize(model, dialect, target)
  m = blue::get(model, :materialize)
  sql = render(model, dialect)
  if m == :table
    "CREATE TABLE #{ident(blue::get(model, :name))} AS\n#{sql}"
  elsif m == :view
    "CREATE OR REPLACE VIEW #{ident(blue::get(model, :name))} AS\n#{sql}"
  elsif m == nil
    throw(
      error(
        :kueri_shape,
        "model #{blue::get(model, :name)} declares no materialize"
      )
    )
  elsif dialect != :duckdb
    throw(
      error(
        :kueri_dialect,
        "COPY to a file has no core form; model #{blue::get(model, :name)} materializes as :#{to_s(m)}, so render it with :duckdb or materialize :table"
      )
    )
  elsif m == :parquet
    "COPY (\n#{sql}\n) TO #{quote_str(target)} (FORMAT parquet, COMPRESSION zstd)"
  else
    "COPY (\n#{sql}\n) TO #{quote_str(target)} (FORMAT csv, HEADER)"
  end
end

# The file a consumer commits: a @generated header naming the blue program,
# then the model's statement — its materialization when it declares one, the
# query otherwise.
def render_file(model, dialect, source)
  header = "-- @generated by #{source} (kueri, #{to_s(dialect)}). Do not edit: regenerate from the blue model."
  stmt = if blue::get(model, :materialize) == nil
    render(model, dialect)
  else
    render_materialize(model, dialect, materialize_target(model))
  end
  "#{header}\n#{stmt};\n"
end

# Write the rendered file; returns the path.
def write_sql(path, model, dialect, source)
  write_file(path, render_file(model, dialect, source))
  path
end

# One script that builds a database: every source the models read, loaded
# (each from its own :file, or its literal rows), then every model, upstream
# before downstream, as its materialization; each once, by name. Every model
# in it materializes as a :view or a :table, because what reads a model names
# it. The same @generated header as q_render_file.
def render_script(models, dialect, source)
  nodes = unique_by(
    fn(n) blue::get(n, :name) end,
    flat_map(fn(m) push(closure(m), m) end, as_list(models))
  )
  sources = blue::filter(fn(n) blue::get(n, :kind) == :source end, nodes)
  ms = blue::filter(fn(n) blue::get(n, :kind) == :model end, nodes)
  loose = blue::filter(
    fn(m) contains([:view, :table], blue::get(m, :materialize)) == false end,
    ms
  )
  if is_empty(loose) == false
    throw(
      error(
        :kueri_shape,
        "a script builds relations, and #{blue::join(map(fn(m) blue::get(m, :name) end, loose), ", ")} materialize as neither :view nor :table"
      )
    )
  end
  stmts = concat_lists(
    map(fn(s) render_load(s, blue::get(s, :file), dialect) end, sources),
    map(fn(m) render_materialize(m, dialect, nil) end, ms)
  )
  "-- @generated by #{source} (kueri, #{to_s(dialect)}). Do not edit: regenerate from the blue model.\n#{blue::join(stmts, ";\n")};\n"
end

# ── the DAG ────────────────────────────────────────────────────────────────

def rels(model)
  cons(
    blue::get(model, :from),
    map(
      fn(s) blue::get(s, :rel) end,
      blue::filter(
        fn(s) blue::get(s, :kind) == :join end,
        blue::get(model, :pipeline)
      )
    )
  )
end

def targets(model)
  map(
    fn(r) blue::get(r, :target) end,
    blue::filter(fn(r) blue::get(r, :kind) == :ref end, rels(model))
  )
end

# The names a model reads directly, first-seen order. Raw nodes are opaque and
# contribute none.
def deps(model)
  unique(map(fn(t) blue::get(t, :name) end, targets(model)))
end

# Every upstream source and model, each before anything that reads it.
def closure(model)
  unique_by(
    fn(n) blue::get(n, :name) end,
    flat_map(fn(t) closure_of(t) end, targets(model))
  )
end

def closure_of(t)
  if blue::get(t, :kind) == :source
    [t]
  else
    push(closure(t), t)
  end
end

def sources(model)
  blue::filter(fn(n) blue::get(n, :kind) == :source end, closure(model))
end

# ── the DuckDB seam ────────────────────────────────────────────────────────

# Run SQL through the `duckdb` binary on PATH: [:ok, rows] or [:error, stderr].
# Rows are JSON documents (read fields with q_row_values or deeta). Only
# statements that return rows print, so a script may load views first. The
# values are the CLI's DISPLAY rendering, whose types move with the DuckDB
# version (see q_rows); read values through q_rows, q_rows_at or
# q_script_rows, which convert with `to_json`.
def duckdb(sql)
  duckdb_result(exec_capture("duckdb", "-json", "-c", sql))
end

# q_duckdb against a database file (created when absent), so what a script
# builds persists: [:ok, rows] or [:error, stderr].
def duckdb_at(db, sql)
  duckdb_result(exec_capture("duckdb", db, "-json", "-c", sql))
end

def duckdb_result(cap)
  if status_of(cap) != 0
    [:error, stderr_of(cap)]
  elsif trim(stdout_of(cap)) == ""
    [:ok, []]
  else
    [:ok, json_parse(stdout_of(cap))]
  end
end

def duckdb_failed?(result)
  first(result) == :error
end

# The rows of ONE query, or a THROWN :kueri_query when it failed: a failed
# query never reads as no rows (the guarantee makoto's bunseki.strict_rows
# gives, here for the public distribution).
#
# Values are converted by DuckDB's `to_json`, never taken from the CLI's
# `-json` rendering. That rendering is a display format: since DuckDB 1.5 it
# prints HUGEINT, UHUGEINT and DECIMAL as strings, and `sum` over integers is a
# HUGEINT, so one query read 1780 under 1.4.3 and "1780" under 1.5.2
# (measured 2026-09-25). `to_json` is the conversion itself and gives the same
# values on both.
def rows(sql)
  rows_of(duckdb(json_rows(sql)), sql)
end

# q_rows against a database file.
def rows_at(db, sql)
  rows_of(duckdb_at(db, json_rows(sql)), sql)
end

# Statements first (loads, views), then ONE query whose rows are read: one
# process, so what the statements made in memory is still there.
def script_rows(statements, query)
  rows_of(duckdb(script_text(statements, query)), query)
end

# q_script_rows against a database file.
def script_rows_at(db, statements, query)
  rows_of(duckdb_at(db, script_text(statements, query)), query)
end

# A script run for what it builds in `db` (views, tables); throws
# :kueri_query when it failed. Nothing it prints is read.
def run_at(db, script)
  checked(duckdb_at(db, script), script)
  nil
end

def script_text(statements, query)
  blue::join(push(as_list(statements), json_rows(query)), ";\n")
end

# One query as one row per result row, each a JSON document of its columns.
# The newline before `)` keeps a trailing `--` comment from swallowing it.
def json_rows(sql)
  "SELECT to_json(kueri_row) AS kueri_row FROM (\n#{strip_suffix(trim(sql), ";")}\n) AS kueri_row"
end

def rows_of(result, sql)
  map(fn(row) as_json(row, "kueri_row") end, checked(result, sql))
end

def checked(result, sql)
  if duckdb_failed?(result)
    throw(error(:kueri_query, "#{trim(last(result))} -- in: #{sql}"))
  end
  last(result)
end

# The rows of a result as value lists, columns in `names` order; [] when it
# failed (ask q_duckdb_failed? first when a failure must not read as empty).
def row_values(result, names)
  if duckdb_failed?(result)
    []
  else
    map(fn(row) map(fn(n) as_json(row, name(n)) end, names) end, last(result))
  end
end

# ── worked examples ────────────────────────────────────────────────────────
#
# Two analysis models, authored the way a consumer writes them. The tests pin
# their rendering in both dialects and run them end to end in DuckDB.

# Worked example: per relationship length, the promise-keeping rate with and
# without enforcement (a flat table of replicate means and spreads).
def example_horizons()
  source(
    {
      name: :horizons,
      file: "horizons.tsv",
      columns: [
        col(:rounds_together, :bigint),
        col(:enforcement, :double),
        col(:keep_mean, :double),
        col(:keep_sd, :double)
      ]
    }
  )
end

# Worked example: how much full enforcement lifts keeping, per length. Every
# aggregate is a FILTER-where aggregate, so the whole model is ONE SELECT, and
# it holds at [:portable, :locked].
def example_leverage()
  without = filtered(q_max(:keep_mean), eq(:enforcement, 0))
  full = filtered(q_max(:keep_mean), eq(:enforcement, 1))
  model(
    {
      name: :leverage,
      from: example_horizons(),
      posture: [:portable, :locked],
      materialize: :parquet,
      pipeline: [
        group(
          [:rounds_together],
          [
            agg(:keep_without_enforcement, q_round(without, 3)),
            agg(:keep_with_full_enforcement, q_round(full, 3)),
            agg(:leverage, q_round(sub(full, without), 3)),
            agg(:widest_spread, q_round(q_max(:keep_sd), 3))
          ]
        ),
        sort([:rounds_together])
      ],
      contract: [
        col(:rounds_together, :bigint),
        col(:keep_without_enforcement, :double),
        col(:keep_with_full_enforcement, :double),
        col(:leverage, :double),
        col(:widest_spread, :double)
      ]
    }
  )
end

# Worked example: which cell ran at which horizon and enforcement.
def example_curve_cells()
  source(
    {
      name: :curve_cells,
      file: "curve_cells.tsv",
      columns: [
        col(:cell, :bigint),
        col(:rounds, :bigint),
        col(:enforcement, :double)
      ]
    }
  )
end

# Worked example: each cell's replicate mean, min and max of keeping.
def example_curve_keep()
  source(
    {
      name: :curve_keep,
      file: "curve_keep.tsv",
      columns: [
        col(:cell, :bigint),
        col(:mean, :double),
        col(:min, :double),
        col(:max, :double)
      ]
    }
  )
end

# Worked example: the lowest enforcement at which a horizon keeps at least 90%
# (rounded to 3 places, as reported), and how many enforcement levels are
# bimodal (replicates more than 0.5 apart).
def example_tipping()
  model(
    {
      name: :tipping,
      from: example_curve_keep(),
      posture: [:portable, :locked],
      pipeline: [
        q_join(example_curve_cells(), [:cell]),
        group(
          [:rounds],
          [
            agg_where(
              :tipping_enforcement,
              q_min(:enforcement),
              ge(q_round(:mean, 3), 0.9)
            ),
            agg_where(:bimodal_levels, count_all(), gt(sub(:max, :min), 0.5))
          ]
        ),
        sort([:rounds])
      ],
      contract: [
        col(:rounds, :bigint),
        col(:tipping_enforcement, :double),
        col(:bimodal_levels, :bigint)
      ]
    }
  )
end

# ── tests ──────────────────────────────────────────────────────────────────

test "an empty pipeline is SELECT * from its relation, in both dialects, and holds"
  m = model({name: :everything, from: example_horizons()})
  assert render(m, :duckdb) == "SELECT *\nFROM horizons"
  assert render(m, :core) == "SELECT *\nFROM horizons"
  assert is_empty(refusals(m)) == true
  assert output(m) == ["rounds_together", "enforcement", "keep_mean", "keep_sd"]
  assert blue::get(shift(m), :needs) == :portable
  assert is_empty(blue::get(shift(m), :held_by)) == true
  # A raw node is opaque to the DAG: a model over one reads nothing it can name.
  raw = kueri::raw(
    {name: :one, sql: "SELECT 1 AS x", columns: [col(:x, :integer)]}
  )
  assert is_empty(deps(model({name: :r, from: raw}))) == true
  assert is_empty(closure(model({name: :r, from: raw}))) == true
end

test "the dialects differ only where a construct does: a neutral model renders the same bytes"
  m = model(
    {
      name: :recent,
      from: example_horizons(),
      pipeline: [
        q_filter(gt(:rounds_together, 5)),
        derive(:gap, sub(:keep_mean, :keep_sd)),
        select([:rounds_together, :gap]),
        sort([desc(:gap)]),
        limit(3)
      ]
    }
  )
  assert render(m, :core) == render(m, :duckdb)
  # Composition is data: appending stages in two steps is appending them in one.
  a = [
    q_filter(gt(:rounds_together, 5)),
    derive(:gap, sub(:keep_mean, :keep_sd))
  ]
  b = [select([:rounds_together, :gap]), sort([desc(:gap)]), limit(3)]
  base = model({name: :recent, from: example_horizons()})
  assert render(then(then(base, a), b), :duckdb) ==
    render(then(base, concat_lists(a, b)), :duckdb)
  assert render(then(base, concat_lists(a, b)), :duckdb) == render(m, :duckdb)
end

test "leverage renders to one SELECT: FILTER in DuckDB, CASE in core, and a locked total order"
  m = example_leverage()
  duck = blue::join(
    [
      "SELECT",
      "  rounds_together,",
      "  round(max(keep_mean) FILTER (WHERE enforcement = 0), 3) AS keep_without_enforcement,",
      "  round(max(keep_mean) FILTER (WHERE enforcement = 1), 3) AS keep_with_full_enforcement,",
      "  round(max(keep_mean) FILTER (WHERE enforcement = 1) - max(keep_mean) FILTER (WHERE enforcement = 0), 3) AS leverage,",
      "  round(max(keep_sd), 3) AS widest_spread",
      "FROM horizons",
      "GROUP BY rounds_together",
      "ORDER BY ALL"
    ],
    "\n"
  )
  core = blue::join(
    [
      "SELECT",
      "  rounds_together,",
      "  round(max(CASE WHEN enforcement = 0 THEN keep_mean END), 3) AS keep_without_enforcement,",
      "  round(max(CASE WHEN enforcement = 1 THEN keep_mean END), 3) AS keep_with_full_enforcement,",
      "  round(max(CASE WHEN enforcement = 1 THEN keep_mean END) - max(CASE WHEN enforcement = 0 THEN keep_mean END), 3) AS leverage,",
      "  round(max(keep_sd), 3) AS widest_spread",
      "FROM horizons",
      "GROUP BY rounds_together",
      "ORDER BY rounds_together, keep_without_enforcement, keep_with_full_enforcement, leverage, widest_spread"
    ],
    "\n"
  )
  assert render(m, :duckdb) == duck
  assert render(m, :core) == core
  # FILTER has a core form, so the model is portable, and nothing holds it.
  assert blue::get(shift(m), :needs) == :portable
end

test "tipping renders a join, count(*) FILTER against a CASE that counts a 1, and typed floats"
  m = example_tipping()
  duck = blue::join(
    [
      "SELECT",
      "  rounds,",
      "  min(enforcement) FILTER (WHERE round(mean, 3) >= 0.9::DOUBLE) AS tipping_enforcement,",
      "  count(*) FILTER (WHERE max - min > 0.5::DOUBLE) AS bimodal_levels",
      "FROM curve_keep",
      "JOIN curve_cells USING (cell)",
      "GROUP BY rounds",
      "ORDER BY ALL"
    ],
    "\n"
  )
  core = blue::join(
    [
      "SELECT",
      "  rounds,",
      "  min(CASE WHEN round(mean, 3) >= CAST(0.9 AS DOUBLE PRECISION) THEN enforcement END) AS tipping_enforcement,",
      "  count(CASE WHEN max - min > CAST(0.5 AS DOUBLE PRECISION) THEN 1 END) AS bimodal_levels",
      "FROM curve_keep",
      "JOIN curve_cells USING (cell)",
      "GROUP BY rounds",
      "ORDER BY rounds, tipping_enforcement, bimodal_levels"
    ],
    "\n"
  )
  assert render(m, :duckdb) == duck
  assert render(m, :core) == core
  assert output(m) == ["rounds", "tipping_enforcement", "bimodal_levels"]
end

test "a long pipeline folds into the fewest SELECTs: QUALIFY saves DuckDB a pass that core spends as a WHERE"
  m = model(
    {
      name: :widest,
      from: example_curve_keep(),
      pipeline: [
        q_filter(gt(:mean, 0.1)),
        q_join(example_curve_cells(), [:cell]),
        derive(:spread, sub(:max, :min)),
        q_filter(lt(:enforcement, 0.75)),
        q_filter(gt(:spread, 0.3)),
        derive(:rank, row_number([:rounds], [desc(:mean)])),
        q_filter(eq(:rank, 1)),
        group([:rounds], [agg(:n, count_all()), agg(:widest, q_max(:spread))]),
        q_filter(ge(:n, 1)),
        sort([desc(:widest)]),
        limit(10)
      ]
    }
  )
  step_1 = [
    "WITH step_1 AS (",
    "  SELECT",
    "    *,",
    "    max - min AS spread",
    "  FROM curve_keep",
    "  JOIN curve_cells USING (cell)"
  ]
  duck = blue::join(
    concat_lists(
      step_1,
      [
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
        "LIMIT 10"
      ]
    ),
    "\n"
  )
  core = blue::join(
    concat_lists(
      step_1,
      [
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
        "LIMIT 10"
      ]
    ),
    "\n"
  )
  assert render(m, :duckdb) == duck
  assert render(m, :core) == core
  # Eleven stages, two CTEs: the WHERE went past the join, the second filter
  # past the scalar derive, and the post-group filter became HAVING.
  assert size(blue::get(lower(m, :duckdb), :done)) == 2
end

test "literals are typed on purpose and identifiers are quoted only when they must be"
  assert render_expr(lit(1), :duckdb) == "1"
  # to_s(1.0) is "1": without the typing this would be an INTEGER, and a bare
  # 1.0 would be DuckDB's DECIMAL(2,1).
  assert render_expr(lit(1.0), :duckdb) == "1.0::DOUBLE"
  assert render_expr(lit(1.0), :core) == "CAST(1.0 AS DOUBLE PRECISION)"
  assert render_expr(lit(-0.5), :duckdb) == "-0.5::DOUBLE"
  assert render_expr(lit("it's"), :core) == "'it''s'"
  assert render_expr(lit(true), :core) == "TRUE"
  assert render_expr(lit(nil), :core) == "NULL"
  assert render_expr(q_cast(:x, :double), :core) ==
    "CAST(x AS DOUBLE PRECISION)"
  assert render_expr(q_cast(:x, :bigint), :duckdb) == "CAST(x AS BIGINT)"
  assert ident(:keep_mean) == "keep_mean"
  assert ident("order") == "\"order\""
  assert ident("Mean") == "\"Mean\""
  assert ident("9lives") == "\"9lives\""
  assert ident("a\"b") == "\"a\"\"b\""
  # The tree's grouping survives: a - (b - c) keeps its parentheses, and
  # (a - b) - c needs none.
  assert render_expr(sub(:a, sub(:b, :c)), :core) == "a - (b - c)"
  assert render_expr(sub(sub(:a, :b), :c), :core) == "a - b - c"
  assert render_expr(mul(add(:a, :b), :c), :core) == "(a + b) * c"
  assert render_expr(q_not(q_or(eq(:a, 1), eq(:b, 2))), :core) ==
    "NOT (a = 1 OR b = 2)"
end

test "a duckdb-only construct in a :portable model is refused, and q_check throws it"
  plays = source(
    {
      name: :plays,
      file: "plays.tsv",
      columns: [
        col(:rounds, :bigint),
        col(:game, :varchar),
        col(:score, :double)
      ]
    }
  )
  names = filtered(string_agg(:game, ","), gt(:score, 0.5))
  stages = [group([:rounds], [agg(:games, ordered(names, [:game]))])]
  held = model(
    {name: :names, from: plays, posture: [:portable], pipeline: stages}
  )
  assert refusal_kinds(held) == [:kueri_reach]
  assert error?(try(check(held), catch(e(), e))) == true
  assert error?(try(render(held, :duckdb), catch(e(), e))) == true
  # The control: the same stages at :duckdb reach hold, so the posture was the
  # whole of the refusal.
  free = model(
    {name: :names, from: plays, posture: [:duckdb], pipeline: stages}
  )
  assert is_empty(refusals(free)) == true
  assert render(free, :duckdb) ==
    "SELECT\n  rounds,\n  string_agg(game, ',' ORDER BY game) FILTER (WHERE score > 0.5::DOUBLE) AS games\nFROM plays\nGROUP BY rounds"
  # And q_shift names what holds it there.
  assert blue::get(shift(free), :needs) == :duckdb
  assert blue::get(shift(free), :held_by) == ["string_agg at stage 1 (group)"]
end

test "a locked model refuses what would make its output depend on luck"
  src = source(
    {
      name: :plays,
      file: "plays.tsv",
      columns: [col(:game, :varchar), col(:score, :double)]
    }
  )
  unordered = model(
    {
      name: :names,
      from: src,
      posture: [:duckdb, :locked],
      pipeline: [group([], [agg(:games, string_agg(:game, ","))])],
      contract: [col(:games, :varchar)]
    }
  )
  assert refusal_kinds(unordered) == [:kueri_locked]
  ordered = model(
    {
      name: :names,
      from: src,
      posture: [:duckdb, :locked],
      pipeline: [
        group(
          [],
          [agg(:games, kueri::ordered(string_agg(:game, ","), [:game]))]
        )
      ],
      contract: [col(:games, :varchar)]
    }
  )
  assert is_empty(refusals(ordered)) == true
  assert render(ordered, :duckdb) ==
    "SELECT string_agg(game, ',' ORDER BY game) AS games\nFROM plays\nORDER BY ALL"
  no_contract = model(
    {
      name: :top,
      from: src,
      posture: [:locked],
      pipeline: [sort([desc(:score)]), limit(1)]
    }
  )
  assert refusal_kinds(no_contract) == [:kueri_locked]
  lucky = model(
    {
      name: :top,
      from: src,
      posture: [:locked],
      pipeline: [limit(1)],
      contract: [col(:game, :varchar), col(:score, :double)]
    }
  )
  assert refusal_kinds(lucky) == [:kueri_locked]
  assert error?(try(check(lucky), catch(e(), e))) == true
  # The control: a sort right before the limit, and the order is completed
  # with the rest of the contract so ties cannot fall either way.
  top = model(
    {
      name: :top,
      from: src,
      posture: [:locked],
      pipeline: [sort([desc(:score)]), limit(1)],
      contract: [col(:game, :varchar), col(:score, :double)]
    }
  )
  assert error?(try(check(top), catch(e(), e))) == false
  assert render(top, :duckdb) ==
    "SELECT *\nFROM plays\nORDER BY score DESC, game\nLIMIT 1"
  # :loose asks for none of it.
  assert is_empty(
    refusals(model({name: :top, from: src, pipeline: [limit(1)]}))
  ) ==
    true
end

test "a declared contract is checked at any rigor, and a wrong one throws"
  wrong = model(
    {
      name: :w,
      from: example_horizons(),
      pipeline: [select([:rounds_together, :keep_mean])],
      contract: [col(:rounds_together, :bigint), col(:keep_sd, :double)]
    }
  )
  assert refusal_kinds(wrong) == [:kueri_contract]
  assert error?(try(render(wrong, :core), catch(e(), e))) == true
  right = model(
    {
      name: :w,
      from: example_horizons(),
      pipeline: [select([:rounds_together, :keep_mean])],
      contract: [col(:rounds_together, :bigint), col(:keep_mean, :double)]
    }
  )
  assert is_empty(refusals(right)) == true
  # A model downstream sees the contract as its input schema.
  down = model({name: :d, from: right, pipeline: [q_filter(gt(:keep_sd, 0))]})
  assert refusal_kinds(down) == [:kueri_shape]
end

test "shape: unknown columns, a stray aggregate, a plain column in a group, and a discarded sort"
  h = example_horizons()
  assert refusal_kinds(
    model({name: :a, from: h, pipeline: [q_filter(gt(:nope, 1))]})
  ) ==
    [:kueri_shape]
  assert refusal_kinds(
    model({name: :b, from: h, pipeline: [derive(:m, q_max(:keep_mean))]})
  ) ==
    [:kueri_shape]
  assert refusal_kinds(
    model(
      {
        name: :c,
        from: h,
        pipeline: [
          group(
            [:rounds_together],
            [agg(:e, add(:enforcement, q_max(:keep_mean)))]
          )
        ]
      }
    )
  ) ==
    [:kueri_shape]
  assert refusal_kinds(
    model(
      {
        name: :d,
        from: h,
        pipeline: [sort([:keep_mean]), q_filter(gt(:keep_mean, 0))]
      }
    )
  ) ==
    [:kueri_shape]
  assert refusal_kinds(
    model(
      {
        name: :e,
        from: h,
        pipeline: [
          group([:rounds_together], [agg(:m, q_max(q_max(:keep_mean)))])
        ]
      }
    )
  ) ==
    [:kueri_shape]
  assert refusal_kinds(
    model({name: :f, from: h, pipeline: [q_join(h, [:rounds_together])]})
  ) ==
    [:kueri_shape]
  # The control: the same stages, well formed, hold.
  assert is_empty(
    refusals(
      model(
        {
          name: :g,
          from: h,
          pipeline: [q_filter(gt(:keep_mean, 0)), sort([:keep_mean])]
        }
      )
    )
  ) ==
    true
end

test "the renderer holds the floor on its own: no door leads a duckdb form into core"
  m = model(
    {
      name: :names,
      from: example_horizons(),
      posture: [:duckdb],
      pipeline: [
        group(
          [:rounds_together],
          [
            agg(
              :games,
              ordered(string_agg(:rounds_together, ","), [:rounds_together])
            )
          ]
        )
      ]
    }
  )
  assert is_empty(refusals(m)) == true
  assert error?(try(render(m, :core), catch(e(), e))) == true
  assert error?(try(render_expr(string_agg(:x, ","), :core), catch(e(), e))) ==
    true
  assert error?(try(render_query(m, :core), catch(e(), e))) == true
  raw = model(
    {
      name: :r,
      from: kueri::raw(
        {name: :one, sql: "SELECT 1 AS x", columns: [col(:x, :integer)]}
      )
    }
  )
  assert error?(try(render_query(raw, :core), catch(e(), e))) == true
  assert error?(try(render(m, :duckdb), catch(e(), e))) == false
  assert error?(
    try(render_load(example_horizons(), "h.tsv", :core), catch(e(), e))
  ) ==
    true
  assert error?(try(render(m, :postgres), catch(e(), e))) == true
end

test "malformed nodes are refused where they are built"
  assert error?(try(source({name: :s, file: "s.tsv"}), catch(e(), e))) == true
  assert error?(try(raw({name: :r, sql: "SELECT 1"}), catch(e(), e))) == true
  assert error?(try(col(:x, :float), catch(e(), e))) == true
  assert error?(
    try(
      model({name: :m, from: example_horizons(), posture: [:strict]}),
      catch(e(), e)
    )
  ) ==
    true
  assert error?(
    try(
      model(
        {name: :m, from: example_horizons(), posture: [:portable, :duckdb]}
      ),
      catch(e(), e)
    )
  ) ==
    true
  assert error?(try(limit(-1), catch(e(), e))) == true
  assert error?(try(filtered(c(:x), gt(:x, 1)), catch(e(), e))) == true
  # The control: a well-formed source is not an error.
  assert error?(try(example_horizons(), catch(e(), e))) == false
end

test "refs are the DAG: direct deps, and a closure with every upstream before its readers"
  assert deps(example_leverage()) == ["horizons"]
  assert deps(example_tipping()) == ["curve_keep", "curve_cells"]
  summary = model(
    {
      name: :summary,
      from: example_tipping(),
      pipeline: [q_join(example_leverage(), [:rounds])]
    }
  )
  assert deps(summary) == ["tipping", "leverage"]
  assert map(fn(n) blue::get(n, :name) end, closure(summary)) ==
    ["curve_keep", "curve_cells", "tipping", "horizons", "leverage"]
  assert map(fn(n) blue::get(n, :name) end, sources(summary)) ==
    ["curve_keep", "curve_cells", "horizons"]
end

test "a raw node is the escape hatch: its own CTE, its declared columns, and :duckdb unless vouched"
  raw = kueri::raw(
    {
      name: :seeds,
      sql: "SELECT range AS seed FROM range(3)",
      columns: [col(:seed, :bigint)]
    }
  )
  m = model(
    {
      name: :evens,
      from: raw,
      pipeline: [q_filter(eq(sub(:seed, mul(div(:seed, 2), 2)), 0))]
    }
  )
  assert output(m) == ["seed"]
  assert render(m, :duckdb) ==
    "WITH seeds AS (\nSELECT range AS seed FROM range(3)\n)\nSELECT *\nFROM seeds\nWHERE seed - seed / 2 * 2 = 0"
  assert refusal_kinds(assoc(m, :posture, posture_of([:portable]))) ==
    [:kueri_reach]
  vouched = kueri::raw(
    {
      name: :one,
      sql: "SELECT 1 AS x",
      columns: [col(:x, :integer)],
      dialect: :core
    }
  )
  assert is_empty(
    refusals(model({name: :v, from: vouched, posture: [:portable]}))
  ) ==
    true
end

test "materialize: COPY to a file in DuckDB, CREATE TABLE AS in both, and no file COPY in core"
  m = example_leverage()
  sql = render(m, :duckdb)
  assert render_materialize(m, :duckdb, "out/leverage.parquet") ==
    "COPY (\n#{sql}\n) TO 'out/leverage.parquet' (FORMAT parquet, COMPRESSION zstd)"
  assert error?(
    try(render_materialize(m, :core, "x.parquet"), catch(e(), e))
  ) ==
    true
  as_table = assoc(m, :materialize, :table)
  assert render_materialize(as_table, :core, nil) ==
    "CREATE TABLE leverage AS\n#{render(m, :core)}"
  as_csv = assoc(m, :materialize, :csv)
  assert render_materialize(as_csv, :duckdb, "l.csv") ==
    "COPY (\n#{sql}\n) TO 'l.csv' (FORMAT csv, HEADER)"
end

test "q_write_sql writes the @generated file a consumer commits and gates fresh"
  path = path_join(getenv("TMPDIR", "."), "kueri-write-test.sql")
  m = example_tipping()
  assert write_sql(path, m, :duckdb, "analysis/tipping.b") == path
  written = read_file(path)
  assert written ==
    "-- @generated by analysis/tipping.b (kueri, duckdb). Do not edit: regenerate from the blue model.\n#{render(m, :duckdb)};\n"
  # A model that materializes writes its COPY, to <name>.parquet beside it.
  assert contains?(
    render_file(example_leverage(), :duckdb, "l.b"),
    ") TO 'leverage.parquet' (FORMAT parquet, COMPRESSION zstd);\n"
  ) ==
    true
  rm(path)
end

test "the DuckDB seam: an empty result is not a failure, a broken query is not empty, and 1.0 needs its type"
  r = duckdb("SELECT 1 AS x WHERE false")
  assert duckdb_failed?(r) == false
  assert is_empty(row_values(r, [:x])) == true
  assert duckdb_failed?(duckdb("SELECT FROM nowhere")) == true
  # The trap the literal typing exists for, measured on the engine itself.
  t = duckdb(
    "SELECT typeof(1.0) AS bare, typeof(#{render_expr(lit(1.0), :duckdb)}) AS typed, typeof(#{render_expr(lit(1.0), :core)}) AS core"
  )
  assert row_values(t, [:bare, :typed, :core]) ==
    [["DECIMAL(2,1)", "DOUBLE", "DOUBLE"]]
end

test "end to end: both dialects' SQL, over fixture files, gives the known leverage and tipping answers"
  dir = getenv("TMPDIR", ".")
  files = [
    [
      "horizons.tsv",
      "rounds_together\tenforcement\tkeep_mean\tkeep_sd\n1\t0\t0.1\t0.02\n1\t0.5\t0.3\t0.04\n1\t1\t0.6\t0.05\n10\t0\t0.4\t0.1\n10\t1\t0.9\t0.08\n10\t1\t0.85\t0.12\n100\t0\t0.95\t0.01\n100\t1\t0.95\t0.2\n1000\t1\t0.7\t0.3\n"
    ],
    [
      "curve_cells.tsv",
      "cell\trounds\tenforcement\n1\t5\t0.0\n2\t5\t0.5\n3\t5\t1.0\n4\t50\t0.0\n5\t50\t0.5\n6\t50\t1.0\n7\t500\t0.25\n"
    ],
    [
      "curve_keep.tsv",
      "cell\tmean\tmin\tmax\n1\t0.2\t0.1\t0.3\n2\t0.8996\t0.2\t0.95\n3\t0.97\t0.9\t1.0\n4\t0.5\t0.0\t0.9\n5\t0.89\t0.6\t0.99\n6\t0.92\t0.3\t1.0\n7\t0.4\t0.35\t0.45\n"
    ]
  ]
  map(
    fn(f) write_file(path_join(dir, "kueri-e2e-#{first(f)}"), last(f)) end,
    files
  )
  loads = fn(m)
    map(
      fn(s)
        render_load(
          s,
          path_join(dir, "kueri-e2e-#{blue::get(s, :file)}"),
          :duckdb
        )
      end,
      sources(m)
    )
  end
  run = fn(m, d) duckdb(blue::join(push(loads(m), render(m, d)), ";\n")) end
  lev = example_leverage()
  lev_names = col_names(blue::get(lev, :contract))
  # Per length: max keep without and with enforcement, their rounded
  # difference, the widest spread. 1000 has no unenforced row: NULL, not 0.
  lev_known = [
    [1, 0.1, 0.6, 0.5, 0.05],
    [10, 0.4, 0.9, 0.5, 0.12],
    [100, 0.95, 0.95, 0.0, 0.2],
    [1000, nil, 0.7, nil, 0.3]
  ]
  assert duckdb_failed?(run(lev, :duckdb)) == false
  assert row_values(run(lev, :duckdb), lev_names) == lev_known
  assert row_values(run(lev, :core), lev_names) == lev_known
  tip = example_tipping()
  tip_names = col_names(blue::get(tip, :contract))
  # Cell 2's mean 0.8996 rounds to 0.9 and counts; cell 5's 0.89 does not.
  # Horizon 500 never reaches 90%: NULL tipping, zero bimodal levels.
  tip_known = [[5, 0.5, 1], [50, 1.0, 2], [500, nil, 0]]
  assert row_values(run(tip, :duckdb), tip_names) == tip_known
  assert row_values(run(tip, :core), tip_names) == tip_known
  # The materialization runs too: COPY to Parquet, read back identical.
  pq = path_join(dir, "kueri-e2e-leverage.parquet")
  copied = duckdb(
    blue::join(push(loads(lev), render_materialize(lev, :duckdb, pq)), ";\n")
  )
  assert duckdb_failed?(copied) == false
  assert row_values(
    duckdb("SELECT * FROM read_parquet(#{quote_str(pq)})"),
    lev_names
  ) ==
    lev_known
  map(fn(f) rm(path_join(dir, "kueri-e2e-#{first(f)}")) end, files)
  rm(pq)
end

# A small JSON Lines stream in an event log's shape (a refusal object, a list
# of link objects, a payload object) and the source that declares it.
def example_records_text()
  blue::join(
    [
      "{\"entity\":\"item-1\",\"links\":[],\"payload\":{\"value\":10},\"refusal\":null,\"seq\":0,\"time\":1000}",
      "{\"entity\":\"item-1\",\"links\":[{\"id\":\"B-7\",\"kind\":\"batch\"}],\"payload\":{},\"refusal\":{\"detail\":[\"quality_ok\",\"uses_left\"],\"kind\":\"guard\"},\"seq\":1,\"time\":1100}",
      "{\"entity\":\"item-2\",\"links\":[],\"payload\":{\"value\":10.5,\"note\":\"x\"},\"refusal\":null,\"seq\":0,\"time\":1200}",
      ""
    ],
    "\n"
  )
end

def example_records(path)
  source(
    {
      name: :recs,
      file: path,
      format: :jsonl,
      columns: [
        col(:entity, :varchar),
        col(:seq, :bigint),
        col(:time, :bigint),
        col(
          :refusal,
          struct_of([col(:kind, :varchar), col(:detail, list_of(:varchar))])
        ),
        col(
          :links,
          list_of(struct_of([col(:id, :varchar), col(:kind, :varchar)]))
        ),
        col(:payload, struct_of([col(:value, :double)]))
      ]
    }
  )
end

# Run a model over its loaded sources, in memory: its rows as value lists.
def example_run(m, names)
  loads = map(
    fn(s) render_load(s, blue::get(s, :file), :duckdb) end,
    sources(m)
  )
  map(
    fn(row) map(fn(n) as_json(row, name(n)) end, names) end,
    script_rows(loads, render(m, :duckdb))
  )
end

test "JSON Lines and literal rows load with declared types, and struct fields and explode read them"
  path = path_join(
    getenv("TMPDIR", "."),
    "kueri-records-#{to_s(now_ns())}.jsonl"
  )
  write_file(path, example_records_text())
  recs = example_records(path)
  assert render_load(recs, "r.jsonl", :duckdb) ==
    "CREATE OR REPLACE VIEW recs AS\nSELECT * FROM read_json('r.jsonl', format = 'newline_delimited', columns = {'entity': 'VARCHAR', 'seq': 'BIGINT', 'time': 'BIGINT', 'refusal': 'STRUCT(kind VARCHAR, detail VARCHAR[])', 'links': 'STRUCT(id VARCHAR, kind VARCHAR)[]', 'payload': 'STRUCT(value DOUBLE)'})"
  # One row per refusing rule: the refused record's two rules; the admitted
  # records' refusal is NULL, so they explode into no rows.
  rules = model(
    {
      name: :rules,
      from: recs,
      pipeline: [
        explode(:rule, q_get(:refusal, :detail)),
        select([:entity, :seq, :rule])
      ]
    }
  )
  assert render(rules, :duckdb) ==
    "WITH step_1 AS (\n  SELECT\n    *,\n    unnest((refusal).detail) AS rule\n  FROM recs\n)\nSELECT\n  entity,\n  seq,\n  rule\nFROM step_1"
  assert example_run(then(rules, [sort([:rule])]), [:entity, :seq, :rule]) ==
    [["item-1", 1, "quality_ok"], ["item-1", 1, "uses_left"]]
  # A link's fields; a payload key absent from a line is NULL, and 10 loads as
  # the DOUBLE its column declares.
  links = model(
    {
      name: :ls,
      from: recs,
      pipeline: [
        explode(:link, :links),
        select(
          [
            :entity,
            as(:link_id, q_get(:link, :id)),
            as(:link_kind, q_get(:link, :kind))
          ]
        )
      ]
    }
  )
  assert example_run(links, [:entity, :link_id, :link_kind]) ==
    [["item-1", "B-7", "batch"]]
  values = model(
    {
      name: :vs,
      from: recs,
      pipeline: [
        select([:entity, :seq, as(:value, q_get(:payload, :value))]),
        sort([:entity, :seq])
      ]
    }
  )
  assert example_run(values, [:entity, :seq, :value]) ==
    [["item-1", 0, 10.0], ["item-1", 1, nil], ["item-2", 0, 10.5]]
  # Literal rows: typed, NULLs kept, and none at all still typed.
  gates = kueri::values(
    {
      name: :gates,
      columns: [col(:kind, :varchar), col(:weight, :bigint)],
      rows: [["guard", 2], ["no_edge", nil]]
    }
  )
  assert render_load(gates, nil, :core) ==
    "CREATE OR REPLACE VIEW gates AS\nSELECT CAST(kind AS VARCHAR) AS kind, CAST(weight AS BIGINT) AS weight\nFROM (VALUES\n  ('guard', 2),\n  ('no_edge', NULL)\n) AS t(kind, weight)"
  weighed = model(
    {
      name: :w,
      from: recs,
      pipeline: [
        derive(:kind, q_get(:refusal, :kind)),
        q_join(gates, [:kind]),
        select([:entity, :kind, :weight])
      ]
    }
  )
  assert example_run(weighed, [:entity, :kind, :weight]) ==
    [["item-1", "guard", 2]]
  none = kueri::values({name: :none, columns: [col(:kind, :varchar)], rows: []})
  assert example_run(
    model(
      {name: :n, from: none, pipeline: [group([], [agg(:n, count_all())])]}
    ),
    [:n]
  ) ==
    [[0]]
  # Controls: a value that is not its column's type fails the load, loudly,
  # and q_rows throws rather than answer no rows; no door renders these
  # constructs as core.
  write_file(
    path,
    "{\"entity\":\"x\",\"payload\":{\"value\":\"high\"},\"seq\":0,\"time\":1}\n"
  )
  assert error?(try(example_run(values, [:entity]), catch(e(), e)))
  rm(path)
  assert error?(try(render_load(recs, "r.jsonl", :core), catch(e(), e)))
  assert error?(try(render(links, :core), catch(e(), e)))
  assert error?(try(render_query(links, :core), catch(e(), e)))
  assert error?(
    try(
      render_query(
        model(
          {
            name: :f,
            from: recs,
            pipeline: [select([as(:k, q_get(:refusal, :kind))])]
          }
        ),
        :core
      ),
      catch(e(), e)
    )
  )
  assert error?(try(type_sql(list_of(:varchar), :core), catch(e(), e)))
  assert blue::get(shift(links), :held_by) ==
    [
      "unnest at stage 1 (explode)",
      "struct field id at stage 2 (select)",
      "struct field kind at stage 2 (select)"
    ]
  assert error?(
    try(
      kueri::values(
        {name: :bad, columns: [col(:a, :varchar)], rows: [["a", "b"]]}
      ),
      catch(e(), e)
    )
  )
  assert error?(try(struct_of([]), catch(e(), e)))
end

# Steps of two entities as literal rows: entity, seq, time, phase.
def example_steps()
  values(
    {
      name: :steps,
      columns: [
        col(:entity, :varchar),
        col(:seq, :bigint),
        col(:time, :bigint),
        col(:phase, :varchar)
      ],
      rows: [
        ["e1", 0, 100, "a"],
        ["e1", 1, 250, "b"],
        ["e1", 2, 400, "c"],
        ["e2", 0, 120, "a"]
      ]
    }
  )
end

# Each step's interval: until the entity's next step, or `now` (1000) when it
# is the last; the phase before it (or "start"); open or closed.
def example_intervals()
  model(
    {
      name: :intervals,
      from: example_steps(),
      materialize: :view,
      pipeline: [
        derive(:until, lead(:time, [:entity], [:seq])),
        derive(:before, coalesce(lag(:phase, [:entity], [:seq]), "start")),
        derive(:seconds, sub(coalesce(:until, 1000), :time)),
        derive(:state, q_if(is_null(:until), "open", "closed")),
        select([:entity, :seq, :before, :phase, :until, :seconds, :state])
      ]
    }
  )
end

test "lead, lag, coalesce, a conditional, null tests and an asof join: rendered once and run"
  m = example_intervals()
  assert render(m, :duckdb) ==
    blue::join(
      [
        "WITH step_1 AS (",
        "  SELECT",
        "    *,",
        "    lead(time) OVER (PARTITION BY entity ORDER BY seq) AS until,",
        "    coalesce(lag(phase) OVER (PARTITION BY entity ORDER BY seq), 'start') AS before",
        "  FROM steps",
        "), step_2 AS (",
        "  SELECT",
        "    *,",
        "    coalesce(until, 1000) - time AS seconds,",
        "    CASE WHEN until IS NULL THEN 'open' ELSE 'closed' END AS state",
        "  FROM step_1",
        ")",
        "SELECT",
        "  entity,",
        "  seq,",
        "  before,",
        "  phase,",
        "  until,",
        "  seconds,",
        "  state",
        "FROM step_2"
      ],
      "\n"
    )
  # Lead, lag and CASE are core SQL: the same bytes in both dialects.
  assert render(m, :core) == render(m, :duckdb)
  # By hand: e1 steps at 100, 250, 400 -> intervals 150, 150, and 1000 - 400
  # = 600 still open; e2 one step at 120 -> 880 open.
  names = [:entity, :seq, :before, :phase, :until, :seconds, :state]
  assert example_run(then(m, [sort([:entity, :seq])]), names) ==
    [
      ["e1", 0, "start", "a", 250, 150, "closed"],
      ["e1", 1, "a", "b", 400, 150, "closed"],
      ["e1", 2, "b", "c", nil, 600, "open"],
      ["e2", 0, "start", "a", nil, 880, "open"]
    ]
  # The asof join: each probe takes the latest reading at or before its time.
  readings = values(
    {
      name: :readings,
      columns: [col(:entity, :varchar), col(:time, :bigint), col(:q, :double)],
      rows: [["e1", 90, 1.0], ["e1", 240, 2.0]]
    }
  )
  probes = values(
    {
      name: :probes,
      columns: [
        col(:entity, :varchar),
        col(:time, :bigint),
        col(:tag, :varchar)
      ],
      rows: [
        ["e1", 100, "a"],
        ["e1", 250, "b"],
        ["e1", 50, "early"],
        ["e3", 100, "none"]
      ]
    }
  )
  asof = model(
    {
      name: :asof,
      from: probes,
      pipeline: [
        asof_left_join(readings, [:entity, :time]),
        select([:tag, :q]),
        sort([:tag])
      ]
    }
  )
  assert contains?(
    render(asof, :duckdb),
    "ASOF LEFT JOIN readings USING (entity, time)"
  )
  assert example_run(asof, [:tag, :q]) ==
    [["a", 1.0], ["b", 2.0], ["early", nil], ["none", nil]]
  # Controls: a lead with no order, and an asof join held at :portable or
  # rendered as core.
  assert error?(try(lead(:time, [:entity], []), catch(e(), e)))
  assert refusal_kinds(assoc(asof, :posture, posture_of([:portable]))) ==
    [:kueri_reach]
  assert error?(try(render_query(asof, :core), catch(e(), e)))
  assert render_expr(q_not(is_null(:x)), :core) == "NOT x IS NULL"
end

test "a script builds a database file of views, upstream first, and q_rows never reads a failure as no rows"
  m = example_intervals()
  script = render_script([m], :duckdb, "kueri test")
  assert starts_with?(script, "-- @generated by kueri test (kueri, duckdb).")
  # Two statements, the load before the view that reads it, then the end.
  parts = split(script, ";\n")
  assert size(parts) == 3
  assert ends_with?(first(parts), render_load(example_steps(), nil, :duckdb))
  assert starts_with?(
    nth(1, parts),
    "CREATE OR REPLACE VIEW intervals AS\nWITH step_1 AS ("
  )
  assert last(parts) == ""
  db = path_join(getenv("TMPDIR", "."), "kueri-script-#{to_s(now_ns())}.duckdb")
  assert duckdb_failed?(duckdb_at(db, script)) == false
  # The views persist in the file: a second process reads them.
  assert rows_at(db, "SELECT sum(seconds) AS s FROM intervals") ==
    rows("SELECT 1780 AS s")
  rm(db)
  # The empty case and the control: no rows is [], a failure throws.
  assert rows("SELECT 1 AS x WHERE false") == []
  assert error?(try(rows("SELECT FROM nowhere"), catch(e(), e)))
  # A model a script cannot name (no :view or :table) is refused.
  assert error?(
    try(
      render_script([assoc(m, :materialize, nil)], :duckdb, "t"),
      catch(e(), e)
    )
  )
end

test "q_rows reads values by conversion, so a DuckDB display change never changes a value's type"
  # Each type DuckDB 1.5's `-json` display prints as a string (measured
  # 2026-09-25): a sum over integers (HUGEINT), a DECIMAL, a UHUGEINT.
  rows = kueri::rows(
    "SELECT sum(x) AS s, 1.25::DECIMAL(10,2) AS d, 7::UHUGEINT AS u FROM (VALUES (1780)) t(x)"
  )
  row = first(rows)
  assert [as_json(row, "s"), as_json(row, "d"), as_json(row, "u")] ==
    [1780, 1.25, 7]
  assert integer?(as_json(row, "s"))
  # The identity: a trailing `;` or `--` comment is the same query.
  assert kueri::rows("SELECT 1780 AS s;") == kueri::rows("SELECT 1780 AS s")
  assert kueri::rows("SELECT 1780 AS s -- the total") ==
    kueri::rows("SELECT 1780 AS s")
  # A script's statements run first, then its one query is read.
  assert script_rows(
    ["CREATE TEMP TABLE k AS SELECT 2 AS n"],
    "SELECT sum(n) AS n FROM k"
  ) ==
    kueri::rows("SELECT 2 AS n")
  # The control: a script that fails throws, it never reads as done.
  db = path_join(getenv("TMPDIR", "."), "kueri-run-#{to_s(now_ns())}.duckdb")
  assert error?(
    try(run_at(db, "CREATE VIEW v AS SELECT * FROM nowhere"), catch(e(), e))
  )
  assert run_at(db, "CREATE VIEW v AS SELECT 3 AS n") == nil
  assert rows_at(db, "SELECT n FROM v") == kueri::rows("SELECT 3 AS n")
  rm(db)
end

test "a model carries its columns, so a model built on it (plain or composed) sees exactly them, without re-walking"
  base = example_steps()
  a = model(
    {
      name: :ka,
      from: base,
      pipeline: [derive(:next_time, lead(:time, [:entity], [:seq]))],
      materialize: :view
    }
  )
  # The empty case: a model with no stages carries its relation's columns.
  bare = model({name: :kbare, from: base, materialize: :view})
  assert blue::get(bare, :known) == ["entity", "seq", "time", "phase"]
  # The identity: what it carries is what its walk infers.
  assert blue::get(a, :known) == output(a)
  assert blue::get(a, :known) == ["entity", "seq", "time", "phase", "next_time"]
  # Composed: q_then carries the columns after the added stages, and a model
  # built on the composed one reads them (and refuses a column it dropped).
  c = then(a, [select([:entity, :next_time])])
  assert blue::get(c, :known) == ["entity", "next_time"]
  over = model(
    {name: :kc, from: c, pipeline: [select([:next_time])], materialize: :view}
  )
  assert output(over) == ["next_time"]
  assert error?(
    try(
      check(
        model(
          {name: :kd, from: c, pipeline: [select([:phase])], materialize: :view}
        )
      ),
      catch(e(), e)
    )
  )
end
