use("deeta", [:as_json])

use(
  "kueri",
  [:q_and, :q_cast, :q_filter, :q_get, :q_if, :q_join, :q_max, :q_min, :q_or]
)

use("nisshi", [:el_append, :el_def])

use("raifusaikuru", [:lc_define])

use(
  "retsu",
  [
    :as_list,
    :concat_lists,
    :contains,
    :count_of,
    :count_where,
    :find_first,
    :first,
    :flat_map,
    :flatten1,
    :is_empty,
    :last,
    :push,
    :size,
    :take_n
  ]
)

use("shuugou", [:lookup, :set_equal, :unique, :unique_by])

legacy_names("0.1.1", "la")

# anaritikusu (アナリティクス) — lifecycle analytics: a database of telemetry, standard models and cross-lifecycle joins, generated from lifecycle definitions.
#
# Give it raifusaikuru definitions and the nisshi streams they were logged to,
# and it builds one DuckDB database: every stream's records, every entity's
# state after every record, the definition's own rules and tasks as tables,
# and a standard set of views per lifecycle (current state, time in each
# state, refusals and breaches per rule, tasks opened, closed and overdue,
# permits issued and their limits used), plus a join view per declared link.
# A new lifecycle gets all of it with no new code. Nothing here knows any
# domain.
#
# ## The plan (stage 1 of the blue development cycle, written before the code)
#
# Reuse map, read from source on 2026-09-24:
#
#   states, edges, gates, guards, rules,  raifusaikuru  lc_d_*, lc_atoms,
#   tasks, permits                                     lc_pred_text, lc_task_*
#   the state after every record          nisshi        el_read + el_history
#                                                       (NEW: the fold read uses,
#                                                       kept per record)
#   canonical JSON text                   nisshi        el_canon_object
#   links declared per lifecycle          raifusaikuru  NEW clause lc_link
#   a permit's issuance, as a record      raifusaikuru  NEW clause lc_permit_log
#                                                       + lc_permit_event
#   queries as data, one renderer         kueri         EXTENDED: JSON Lines
#                                                       sources, literal-row
#                                                       relations, struct and
#                                                       list types, explode,
#                                                       lead/lag, coalesce, if,
#                                                       null tests, asof joins,
#                                                       views, a database script,
#                                                       a strict seam
#   a failed query must fail              makoto's private bunseki.strict_rows
#                                         → the same guarantee as kueri's q_rows
#                                         (public blue cannot need a private
#                                         package; bunseki's run_sql already
#                                         duplicates q_duckdb)
#   tidy records → one DuckDB database    makoto's lab (lab/lab.sql over tidy
#   of typed views                        TSVs, built by nix into lab.duckdb):
#                                         the SECOND instance, so its shape —
#                                         one script of loads then views, run
#                                         into one .duckdb file — is taken, and
#                                         the script is rendered by kueri,
#                                         never hand-written (lab.sql is
#                                         `pending-blue-sql`)
#
# The shape, and the one decision it rests on — facts from DuckDB, state from
# the one fold:
#
#   FACTS   DuckDB reads each stream as JSON Lines, with every column
#           declared (a value of the wrong type fails the load; it never reads
#           as NULL).
#   STATE   raifusaikuru's fold, through nisshi's replay, writes the state
#           after every record as JSON Lines beside the database. SQL never
#           folds: phases and fields come from the fold that append and read
#           share, so the analytics cannot disagree with the engine. SQL does
#           what it is for: windows, joins and aggregation.
#   RULES   the definition's own tables (edges, rules, task evidence) are
#           literal-row relations, so the database describes itself, and the
#           models join against them rather than restating them.
#   TYPES   derived from the definition, never declared (below).
#   LINKS   `lc_link(role, target)` on the referring lifecycle. The shape
#           declared relations already agree on (raifusaikuru's header): the
#           role is the link kind nisshi writes beside each id, the target a
#           lifecycle; one row per link, however many a record carries.
#
# Idioms: the `la_` prefix; typed errors (:anaritikusu_schema for a set of
# definitions the database cannot be generated from, :anaritikusu_broken for
# a stream whose chain is broken); pure, with `now` passed in (the models that
# reach the present read it as a literal); I/O only in la_write_history,
# la_build and la_read. The four tests and a differential end-to-end test
# (a simulated day, every number computed by hand in a comment), each red-run.
#
# Dependency order: the raifusaikuru clauses, then nisshi's history, then
# kueri's extensions, then this; each step shipped with its tests before the
# next.
#
# ## Types, derived
#
# A field's or payload key's column type is read off the definition:
# constants (a field's initial value, lc_put, lc_add, lc_equals) give their
# own type; lc_stamp and lc_fresh make a time, BIGINT on the caller's clock; a
# comparison (lc_below …) or a counter makes a field numeric; lc_set and
# lc_add_from carry a key's values into a field, so a key flowing into a
# numeric field is a number, and DOUBLE, because a payload is written from
# outside and may be fractional. A permit log's keys are subject (VARCHAR) and
# BIGINT limits. Numbers widen (BIGINT with DOUBLE is DOUBLE); any other two
# types on one column are refused. What nothing constrains is VARCHAR, the
# value's JSON text — honest, not guessed.
#
# ## The database, per lifecycle `n` (every name is a view)
#
#   n_records        the stream, as read (nested payload, refusal, links)
#   n_history        the fold's state after each record, as written here
#   n_edges n_rules n_task_evidence      the definition, as rows
#   n_events         one row per record: entity seq time type status
#                    refusal_kind refusal_detail links <payload keys> prev
#                    hash sig — the telemetry schema's event table
#   n_states         one row per record: entity seq phase <fields> breach
#                    breach_capability replay_refusal — the state table
#   n_steps          the two joined, plus phase_before
#   n_unreplayed     records with no state row (0 when the history is current)
#   n_current_state  one row per entity: its phase and fields now
#   n_state_intervals, n_time_in_state   seconds in each phase, up to `now`
#   n_refusals       refused records by type and kind
#   n_gates n_guard_hits n_rule_hit_counts n_rule_hits
#                    every declared rule with how often it refused an event
#                    and how often an applied event breached it
#   n_rule_tasks n_task_asks n_task_evidence_events n_task_closes n_tasks
#   n_task_summary   a task opens when a refusing rule asks for it (its own
#                    task, or its guard's), closes at the entity's first later
#                    admitted event of one of its evidence kinds, and is
#                    overdue when it stayed open longer than it may
#   n_permits_<c> n_uses_<c> n_permit_use_<c>, for a logged capability c:
#                    each permit issued, the uses of c after it (before its
#                    not_after and before the next permit), and uses past
#                    not_after (an overrun)
#   n_granted_<c> n_unpermitted_<c>
#                    every use no permit covered, and why: none issued before
#                    it (no_permit), its not_after passed (lapsed), or it broke
#                    the guard inside the window (breach) — permit_use counts
#                    by window alone
#   n_span_<s> n_span_<s>_summary (with n_span_<s>_from, n_span_<s>_to), for
#                    a declared lc_span s: per entity, the first entry into
#                    `from`, the first entry into `to` after it, the seconds
#                    between, the time elapsed to `now` while open, done / open
#                    / abandoned (ended in a terminal without reaching `to`),
#                    and whether it passed its limit; then one summary row
#
# and per declared link, A's role r to lifecycle B:
#
#   a_r_links        A's records carrying an r link: one row per link
#   a_r_state        B's states, keyed for the join
#   a_r              each link with B's state AS OF the record's time: the
#                    latest B record at or before it (NULL when B has none:
#                    a dangling or premature link stays visible)
#   a_r_coverage     links, and how many are unresolved
#   a_r_s            per pair A –r→ B –s→ C: each A link with B's latest s
#                    link at or before it and C's state as of that B record
#                    (an order's portion, and the consumable the portion was
#                    made with, as it was when the portion was made)
#
# ## Tiers
#
# REFUSED WHEN GENERATED (:anaritikusu_schema): a link to a lifecycle not
# given; two lifecycles with one name; a payload key or field whose name is a
# generated column, or two whose names share a text; a column with two
# incompatible types; any two generated relations with one name.
# REFUSED WHEN BUILT (:anaritikusu_broken): a stream whose chain el_verify
# breaks (unsigned: signatures are the caller's, through el_open).
# LOUD AT LOAD: a payload value not of its derived type fails DuckDB's load.
# NOT CHECKED: that times within an entity's stream never decrease (a task's
# close is its first later evidence by seq, its time the evidence's own);
# "as of" is at-or-before by time, so a target record at the same second as
# the event counts as before it.
#
# ## Tests, and the red run that turned each one red (2026-09-24)
#
# 34 of 34 mutations red across this package and the three it extended, each
# applied by a driver that refuses a target not present exactly once. Here:
#
#   the telemetry schema               A12 a numeric key typed as text
#   the history                        A15 the last record dropped · A16 a
#                                      constant phase · A20 refused records
#                                      folded (nisshi's fold; also the day)
#   the simulated day (every number    A1 current state from the oldest record ·
#     by hand, and the fold as the     A2 open intervals ending at 0 · A3
#     differential)                    refusals counting admitted records · A4
#                                      guard refusals missed · A5 tasks closed by
#                                      earlier evidence · A6 overdue reversed ·
#                                      A7 an overrun counted as a use · A8 a link
#                                      joined exactly · A9 the link kind ignored ·
#                                      A10 coverage inverted · A11 a chain joined
#                                      exactly · A14 open tasks not measured to
#                                      now · A18 a link to a missing lifecycle
#   the stricter reader                A13 a breach marked on every later record
#   refusals where generated or built  A17 a broken stream built on · A19
#                                      generated names unchecked
#
# A20 is the reason the numbers are computed by hand: it corrupts the fold
# both sides of the differential share, so the two still agree, and only the
# hand-computed uses (4, not 5) go red.
#
# Added 2026-09-25 (spans and uses no permit covered, for NuPastel's measures,
# nupastel docs/plans/measures.md), 7 of 7 mutations red:
#
#   the simulated day: spans by hand   A21 a span starting where it ends · A22
#                                      an abandoned span read as open · A23 an
#                                      open span's time ending at 0 · A24 the
#                                      limit ignored · A26 (also below)
#   observed breaches and uncovered    A25 a breach inside a window counted as
#     uses, and the attempted control  covered · A26 the permit in force found by
#                                      equal seq, not as of · A27 a use before
#                                      any permit counted as covered
#
# Not covered, so not claimed: dropping the "after `from`" filter on a span's
# end changes nothing in an acyclic lifecycle, and no example has a cycle.
#
# Fixed 2026-09-25, found by NuPastel's bench day (9 orders joined to their
# oil's state before their own load, 132 pack links to a pack before its
# takes): the one-hop link's as-of join matched on time alone, so with two
# records of the linked entity in one second it took either. Now the state
# after the LAST record in that second. Red: A28 the tie-break dropped, A29
# the tie broken toward the earlier record; both turn the tie test red. The
# chain view (a_r_s) can still meet two links of one record, which is
# inherent in "B's latest s link" and left as it is.
#
# ## The benchmark (2026-09-24)
#
# nisshi's worked stream, 10,000 events over 100 consumables (5,500 refused
# by the guard), built with la_build; Apple M4 Pro, release blue 0.0.39,
# single runs:
#
#                        first version   hot path fixed
#   el_history           1.02 s          1.02 s    102 µs a record
#   la_history_text      4.59 s          2.30 s    (includes el_history)
#   la_build             8.39 s          6.07 s    read 1.9 s, verify ~1.8 s,
#                                                  history 2.3 s, DuckDB <0.1 s
#   a query              62 ms           69 ms     (count, over the views)
#
# DuckDB, over the generated views, counts the same 10,000 records, 5,500
# refused and 100 entities nisshi measured. What moved it: the history line
# was canonical JSON sorted per line; its keys are fixed, so they are now
# written in order (the same 1,724,600 bytes). What remains, in order:
# nisshi's read and verify, then el_history (its push is quadratic, 102 µs a
# record at 10,000) and each line's fields object.
#
# ## Words blue is missing (stage 5 candidates, not built here)
#
# Where this package wrote repetition by hand, the word that would remove it.
# The first five were listed by nisshi; this build adds evidence to each.
#
# - A RECORD: la_binding and la_stream are maps with hand accessors, and
#   raifusaikuru's definition grew two positional slots (links, permit logs)
#   read by nth(12, d) and nth(13, d).
# - A CLOSED KIND SET: lc_problem_kinds grew by two, each with its
#   hand-written row in the every-kind test.
# - A GUARD: this file raises in 12 places, 10 of them in the shape
#   `if … throw(error(:anaritikusu_…, "…")) end`.
# - DEFAULT ARGUMENTS: la_build_history passes el_verify(log, nil, nil).
# - A RED-RUN WORD, now EARNED: this build's driver (34 mutations, [label,
#   file, old, new, test file] → red or green with the failing tests) and
#   nisshi's (18 mutations) were written independently and agree on the shape
#   and on the one constant, a target must occur exactly once. Not small once
#   gated (a Bluefile word and a check that runs it), so listed, not built.
# - AN O(1) APPEND: el_history grows its rows with push (see the benchmark).
# - A NIL DEFAULT (`v`, or `fallback` when nil): written by hand 12 times in
#   5 packages (7 as `if v == nil … else v end`, one of them el_history's; 5
#   as `if v == nil v = … end` in kueri; counted 2026-09-24), and defined once
#   as makoto's private jikken.if_nil, a second, independent derivation. A
#   public one would turn makoto's collision gate red, so it lands with makoto
#   deleting its copy in the same change.
# - A KEYWORD FROM TEXT: kueri reads a keyword as a column and a string as a
#   value, so a column name this package computes (`"#{role}_seq"`) renders as
#   a quoted literal inside an expression unless wrapped in q_c. Four sites
#   here; two were bugs, found only by reading the rendered SQL. With a way to
#   make a keyword from text (BLUE-BATTERIES blocker 2), generated names would
#   be keywords and the trap would not exist.
# - A RENAME-WITH-PREFIX STAGE: putting a relation's columns under a prefix
#   is written by hand in la_link_state_model (`q_as("#{r}_#{f}", q_c(f))`
#   per field), again as bare names in la_link_state_names, and as five
#   one-by-one renames in the chain's via.
# - CONTENT IDENTITY FOR QUERY NODES: kueri identifies a node by its name, so
#   two different relations with one name collapse silently; la_check_unique
#   exists only to stop that. A node hashed by its rendering (shomei is
#   there) would refuse it in kueri itself.
# - A RAW STRING: a string literal holding `#{` is always interpolated, so a
#   program carrying blue source text builds the opener as concat("#", "{").
# - A DECLARED KEY TYPE: `grams` reads as a number only because its field
#   starts at 0; a key nothing in the definition constrains reads as text. A
#   type on lc_event's keys, enforced by the fold (:bad_payload for a
#   mistyped value), would make it declared and checked.
# - MOVE bunseki.strict_rows and run_sql to kueri's q_rows / q_duckdb (makoto,
#   private): the public seam now gives the same guarantee.
# (Closed 2026-09-25: NESTED VALUES READ BACK TYPED. kueri's q_rows now reads
# through `to_json`, so a LIST column such as the breach column of
# n_unpermitted_<c> comes back as a list, not as its text "[quality_ok]".)

# ── names ──────────────────────────────────────────────────────────────────

# A generated relation's name: the lifecycle's name, then `suffix`.
def n(d, suffix)
  "#{raifusaikuru::text(raifusaikuru::name(d))}_#{suffix}"
end

# The record columns an event log writes, as the events view names them.
def record_names()
  [
    "entity",
    "seq",
    "time",
    "type",
    "status",
    "refusal_kind",
    "refusal_detail",
    "links",
    "prev",
    "hash",
    "sig"
  ]
end

# The columns a state row carries besides the fields, and the ones the steps
# view adds: no field may take one of these names.
def state_names()
  [
    "entity",
    "seq",
    "time",
    "type",
    "status",
    "refusal_kind",
    "refusal_detail",
    "phase",
    "phase_before",
    "breach",
    "breach_capability",
    "replay_refusal"
  ]
end

# ── types, derived from the definition ─────────────────────────────────────

# A constant's column type, or nil for nil. A keyword is written as its text.
def lit_type(v)
  if v == nil
    nil
  elsif boolean?(v)
    :boolean
  elsif integer?(v)
    :bigint
  elsif number?(v)
    :double
  else
    :varchar
  end
end

def numeric?(t)
  t == :bigint || t == :double
end

# One type from several, nil for none: numbers widen to DOUBLE, and anything
# else must agree.
def merge(ts, what)
  known = unique(filter(fn(t) t != nil end, ts))
  if is_empty(known)
    nil
  elsif size(known) == 1
    first(known)
  elsif count_where(fn(t) numeric?(t) == false end, known) == 0
    :double
  else
    throw(
      error(
        :anaritikusu_schema,
        "#{what} holds values of types #{join(map(fn(t) to_s(t) end, known), " and ")}; a column has one type"
      )
    )
  end
end

# Every effect of every row: [:set f k], [:put f v], [:add f n], [:add_key f
# k], [:stamp f].
def effects(d)
  flat_map(fn(e) nth(4, e) end, raifusaikuru::d_edges(d))
end

# Every atomic predicate of every rule of every guard.
def atoms(d)
  flat_map(
    fn(g) flat_map(fn(r) raifusaikuru::atoms(nth(2, r)) end, nth(2, g)) end,
    raifusaikuru::d_guards(d)
  )
end

# The types the definition's constants and clocks give field `f`.
def field_evidence(d, f)
  effects = map(
    fn(x) effect_type(x) end,
    filter(fn(x) nth(1, x) == f end, anaritikusu::effects(d))
  )
  atoms = map(
    fn(a) atom_type(a) end,
    filter(fn(a) first(a) != :in && nth(1, a) == f end, anaritikusu::atoms(d))
  )
  cons(
    lit_type(lookup(raifusaikuru::d_fields(d), f)),
    concat_lists(effects, atoms)
  )
end

def effect_type(x)
  op = first(x)
  if op == :put || op == :add
    lit_type(nth(2, x))
  elsif op == :stamp
    :bigint
  else
    nil
  end
end

def atom_type(a)
  op = first(a)
  if op == :eq
    lit_type(nth(2, a))
  elsif op == :age_lt
    :bigint
  else
    nil
  end
end

# Field `f` holds a number: compared, counted, or given a numeric constant.
def needs_number?(d, f)
  compared = count_where(
    fn(a) contains([:lt, :le, :gt, :ge], first(a)) && nth(1, a) == f end,
    atoms(d)
  ) >
    0
  counted = count_where(
    fn(x) contains([:add, :add_key], first(x)) && nth(1, x) == f end,
    effects(d)
  ) >
    0
  compared ||
    counted ||
    numeric?(merge(field_evidence(d, f), "field #{raifusaikuru::show(f)}"))
end

# The effects that carry payload key `k` (by its text) into a field.
def flows_of_key(d, k)
  filter(
    fn(x)
      (first(x) == :set || first(x) == :add_key) &&
        raifusaikuru::text(nth(2, x)) == raifusaikuru::text(k)
    end,
    effects(d)
  )
end

# A logged permit's key types by text: subject is text, the limits are whole
# numbers.
def permit_key_types(d)
  logged = map(fn(l) nth(1, l) end, raifusaikuru::d_permit_logs(d))
  keys = flat_map(
    fn(e) as_list(nth(1, e)) end,
    filter(fn(e) contains(logged, first(e)) end, raifusaikuru::d_events(d))
  )
  map(fn(k) [raifusaikuru::text(k), permit_key_type(k)] end, keys)
end

def permit_key_type(k)
  if raifusaikuru::text(k) == "subject"
    :varchar
  else
    :bigint
  end
end

# A payload key's column type (see "Types, derived").
def key_type(d, k)
  fixed = lookup(permit_key_types(d), raifusaikuru::text(k))
  if fixed != nil
    fixed
  else
    flows = flows_of_key(d, k)
    targets = unique(map(fn(x) nth(1, x) end, flows))
    numeric = count_where(fn(x) first(x) == :add_key end, flows) > 0 ||
      count_where(fn(f) needs_number?(d, f) end, targets) > 0
    if numeric
      :double
    else
      t = merge(
        flat_map(fn(f) field_evidence(d, f) end, targets),
        "payload key #{raifusaikuru::show(k)}"
      )
      if t == nil
        :varchar
      else
        t
      end
    end
  end
end

# A field's column type (see "Types, derived").
def field_type(d, f)
  keys = map(
    fn(x) key_type(d, nth(2, x)) end,
    filter(
      fn(x) (first(x) == :set || first(x) == :add_key) && nth(1, x) == f end,
      effects(d)
    )
  )
  t = merge(
    concat_lists(field_evidence(d, f), keys),
    "field #{raifusaikuru::show(f)} of #{raifusaikuru::show(raifusaikuru::name(d))}"
  )
  if t != nil
    t
  elsif needs_number?(d, f)
    :double
  else
    :varchar
  end
end

# Every payload key any event declares, once by its text, first-declared
# first: the event table's columns after the record's.
def keys(d)
  unique_by(
    fn(k) raifusaikuru::text(k) end,
    flat_map(fn(e) as_list(nth(1, e)) end, raifusaikuru::d_events(d))
  )
end

# [name, type] for every payload key, the name as text.
def key_types(d)
  map(fn(k) [raifusaikuru::text(k), key_type(d, k)] end, keys(d))
end

# [name, type] for every field, in declaration order, the name as text.
def field_types(d)
  map(
    fn(f) [raifusaikuru::text(f), field_type(d, f)] end,
    raifusaikuru::d_field_names(d)
  )
end

# ── the telemetry schema ───────────────────────────────────────────────────

def link_type()
  kueri::struct_of([kueri::col(:id, :varchar), kueri::col(:kind, :varchar)])
end

# The event table's columns, as q_col: the record's, then every payload key.
def event_columns(d)
  check_names(d)
  keys = map(fn(kt) kueri::col(first(kt), nth(1, kt)) end, key_types(d))
  concat_lists(
    concat_lists(
      [
        kueri::col(:entity, :varchar),
        kueri::col(:seq, :bigint),
        kueri::col(:time, :bigint),
        kueri::col(:type, :varchar),
        kueri::col(:status, :varchar),
        kueri::col(:refusal_kind, :varchar),
        kueri::col(:refusal_detail, kueri::list_of(:varchar)),
        kueri::col(:links, kueri::list_of(link_type()))
      ],
      keys
    ),
    [
      kueri::col(:prev, :varchar),
      kueri::col(:hash, :varchar),
      kueri::col(:sig, :varchar)
    ]
  )
end

# The state table's columns, as q_col: which record, the phase, every field,
# and what the replay found (a breach, or a refusal of an admitted record).
def state_columns(d)
  check_names(d)
  fields = map(fn(ft) kueri::col(first(ft), nth(1, ft)) end, field_types(d))
  concat_lists(
    concat_lists(
      [
        kueri::col(:entity, :varchar),
        kueri::col(:seq, :bigint),
        kueri::col(:phase, :varchar)
      ],
      fields
    ),
    [
      kueri::col(:breach, kueri::list_of(:varchar)),
      kueri::col(:breach_capability, :varchar),
      kueri::col(:replay_refusal, :varchar)
    ]
  )
end

# [column, type] pairs of a q_col list, types as SQL: what a reader checks.
def columns_text(cols)
  map(fn(c) [get(c, :name), kueri::type_sql(get(c, :type), :duckdb)] end, cols)
end

# Refuse a definition whose keys or fields would take a generated column's
# name, or share a text with each other.
def check_names(d)
  keys = map(fn(k) raifusaikuru::text(k) end, anaritikusu::keys(d))
  fields = map(fn(f) raifusaikuru::text(f) end, raifusaikuru::d_field_names(d))
  taken_keys = filter(fn(k) contains(record_names(), k) end, keys)
  taken_fields = filter(fn(f) contains(state_names(), f) end, fields)
  dupes = unique(filter(fn(f) count_of(fields, f) > 1 end, fields))
  if is_empty(taken_keys) == false
    throw(
      error(
        :anaritikusu_schema,
        "#{raifusaikuru::show(raifusaikuru::name(d))}: payload key #{join(taken_keys, ", ")} is a record column's name (#{join(record_names(), ", ")}); rename the key"
      )
    )
  end
  if is_empty(taken_fields) == false
    throw(
      error(
        :anaritikusu_schema,
        "#{raifusaikuru::show(raifusaikuru::name(d))}: field #{join(taken_fields, ", ")} is a state column's name (#{join(state_names(), ", ")}); rename the field"
      )
    )
  end
  if is_empty(dupes) == false
    throw(
      error(
        :anaritikusu_schema,
        "#{raifusaikuru::show(raifusaikuru::name(d))}: two fields are named #{join(dupes, ", ")} as text"
      )
    )
  end
  d
end

# ── bindings: a definition, its stream, and where its history is written ──

# One lifecycle to analyse: its definition, the path of its nisshi stream,
# and the path its history (the state after every record) is written to.
def binding(d, stream, history)
  raifusaikuru::name(d)
  {def: d, stream: stream, history: history}
end

# waive B0013: `def` is a reserved word, so the prefix stays; anaritikusu::def names it too
def la_def(b)
  get(b, :def)
end

# ── sources: what is loaded ────────────────────────────────────────────────

# The stream as nisshi writes it, every column declared (the payload as a
# struct of the derived key types; no payload column when no event has keys).
def records_source(d, path)
  keys = key_types(d)
  payload = if is_empty(keys)
    []
  else
    [
      kueri::col(
        :payload,
        kueri::struct_of(
          map(fn(kt) kueri::col(first(kt), nth(1, kt)) end, keys)
        )
      )
    ]
  end
  refusal = kueri::struct_of(
    [kueri::col(:kind, :varchar), kueri::col(:detail, kueri::list_of(:varchar))]
  )
  cols = concat_lists(
    concat_lists(
      [
        kueri::col(:entity, :varchar),
        kueri::col(:seq, :bigint),
        kueri::col(:time, :bigint),
        kueri::col(:type, :varchar),
        kueri::col(:status, :varchar),
        kueri::col(:refusal, refusal),
        kueri::col(:links, kueri::list_of(link_type()))
      ],
      payload
    ),
    [
      kueri::col(:prev, :varchar),
      kueri::col(:hash, :varchar),
      kueri::col(:sig, :varchar)
    ]
  )
  kueri::source(
    {name: n(d, "records"), file: path, format: :jsonl, columns: cols}
  )
end

# The history la_write_history writes: the state after each record.
def history_source(d, path)
  fields = field_types(d)
  struct = if is_empty(fields)
    []
  else
    [
      kueri::col(
        :fields,
        kueri::struct_of(
          map(fn(ft) kueri::col(first(ft), nth(1, ft)) end, fields)
        )
      )
    ]
  end
  cols = concat_lists(
    concat_lists(
      [
        kueri::col(:entity, :varchar),
        kueri::col(:seq, :bigint),
        kueri::col(:phase, :varchar)
      ],
      struct
    ),
    [
      kueri::col(:breach, kueri::list_of(:varchar)),
      kueri::col(:breach_capability, :varchar),
      kueri::col(:replay_refusal, :varchar)
    ]
  )
  kueri::source(
    {name: n(d, "history"), file: path, format: :jsonl, columns: cols}
  )
end

# ── the definition, as rows ────────────────────────────────────────────────

def text_or_nil(x)
  if x == nil
    nil
  else
    raifusaikuru::text(x)
  end
end

# Every row: the phase it leaves, the event, the phase it enters, and the
# capability that gates it (NULL when none).
def edges_rel(d)
  rows = map(
    fn(e)
      [
        raifusaikuru::text(nth(1, e)),
        raifusaikuru::text(nth(2, e)),
        raifusaikuru::text(nth(3, e)),
        text_or_nil(nth(5, e))
      ]
    end,
    raifusaikuru::d_edges(d)
  )
  kueri::values(
    {
      name: n(d, "edges"),
      columns: [
        kueri::col(:phase_before, :varchar),
        kueri::col(:type, :varchar),
        kueri::col(:phase, :varchar),
        kueri::col(:capability, :varchar)
      ],
      rows: rows
    }
  )
end

# Every rule of every guard: what it needs, in the engine's own words, and
# the task it asks for when it refuses (its own, else its guard's; NULL when
# neither names one).
def rules_rel(d)
  rows = flat_map(
    fn(g) map(fn(r) rule_row(g, r) end, nth(2, g)) end,
    raifusaikuru::d_guards(d)
  )
  kueri::values(
    {
      name: n(d, "rules"),
      columns: [
        kueri::col(:capability, :varchar),
        kueri::col(:rule, :varchar),
        kueri::col(:needs, :varchar),
        kueri::col(:task, :varchar),
        kueri::col(:escalate_after, :bigint)
      ],
      rows: rows
    }
  )
end

def rule_row(g, r)
  t = raifusaikuru::task_or(r, nth(3, g))
  task = if t == nil
    [nil, nil]
  else
    [
      raifusaikuru::text(raifusaikuru::task_name(t)),
      raifusaikuru::task_escalate_after(t)
    ]
  end
  concat_lists(
    [
      raifusaikuru::text(nth(1, g)),
      raifusaikuru::text(nth(1, r)),
      raifusaikuru::pred_text(nth(2, r))
    ],
    task
  )
end

# Every task any rule may ask for, one row per evidence kind that closes it.
def task_evidence_rel(d)
  tasks = flat_map(
    fn(g)
      filter(
        fn(t) t != nil end,
        cons(nth(3, g), map(fn(r) nth(3, r) end, nth(2, g)))
      )
    end,
    raifusaikuru::d_guards(d)
  )
  rows = unique(
    flat_map(
      fn(t)
        map(
          fn(k)
            [
              raifusaikuru::text(raifusaikuru::task_name(t)),
              raifusaikuru::text(k)
            ]
          end,
          raifusaikuru::task_evidence(t)
        )
      end,
      tasks
    )
  )
  kueri::values(
    {
      name: n(d, "task_evidence"),
      columns: [kueri::col(:task, :varchar), kueri::col(:evidence, :varchar)],
      rows: rows
    }
  )
end

# ── the models of one lifecycle ────────────────────────────────────────────

def view(d, suffix, from, pipeline)
  kueri::model(
    {name: n(d, suffix), from: from, pipeline: pipeline, materialize: :view}
  )
end

def field_names(d)
  map(fn(ft) first(ft) end, field_types(d))
end

# The event table: one row per record, the payload's keys as columns.
def events_model(d, records)
  keys = map(
    fn(kt) kueri::as(first(kt), q_get(:payload, first(kt))) end,
    key_types(d)
  )
  items = concat_lists(
    concat_lists(
      [
        :entity,
        :seq,
        :time,
        :type,
        :status,
        kueri::as(:refusal_kind, q_get(:refusal, :kind)),
        kueri::as(:refusal_detail, q_get(:refusal, :detail)),
        :links
      ],
      keys
    ),
    [:prev, :hash, :sig]
  )
  view(d, "events", records, [kueri::select(items)])
end

# The state table: one row per record, the fields as columns.
def states_model(d, history)
  fields = map(fn(f) kueri::as(f, q_get(:fields, f)) end, field_names(d))
  items = concat_lists(
    concat_lists([:entity, :seq, :phase], fields),
    [:breach, :breach_capability, :replay_refusal]
  )
  view(d, "states", history, [kueri::select(items)])
end

# Records and states joined, with the phase each record found its entity in.
def steps_model(d, events, states)
  start = raifusaikuru::text(raifusaikuru::phase(raifusaikuru::initial(d)))
  view(
    d,
    "steps",
    events,
    [
      kueri::select(
        [:entity, :seq, :time, :type, :status, :refusal_kind, :refusal_detail]
      ),
      q_join(states, [:entity, :seq]),
      kueri::derive(
        :phase_before,
        kueri::coalesce(kueri::lag(:phase, [:entity], [:seq]), start)
      )
    ]
  )
end

# Records the history has no state for: 0 when it was written from this
# stream.
def unreplayed_model(d, events, states)
  view(
    d,
    "unreplayed",
    events,
    [
      kueri::select([:entity, :seq]),
      kueri::left_join(states, [:entity, :seq]),
      q_filter(kueri::is_null(:phase)),
      kueri::group([], [kueri::agg(:records, kueri::count_all())])
    ]
  )
end

# One row per entity: its phase and fields after its last record.
def current_state_model(d, steps)
  items = concat_lists(
    concat_lists([:entity, :phase], field_names(d)),
    [kueri::as(:last_seq, :seq), kueri::as(:last_time, :time)]
  )
  view(
    d,
    "current_state",
    steps,
    [
      kueri::derive(
        :la_newest,
        kueri::row_number([:entity], [kueri::desc(:seq)])
      ),
      q_filter(kueri::eq(:la_newest, 1)),
      kueri::select(items)
    ]
  )
end

# Each record's phase held from its time until the entity's next record, or
# until `now` for the last.
def intervals_model(d, steps, now)
  view(
    d,
    "state_intervals",
    steps,
    [
      kueri::derive(:until, kueri::lead(:time, [:entity], [:seq])),
      kueri::derive(:seconds, kueri::sub(kueri::coalesce(:until, now), :time)),
      kueri::select(
        [:entity, :seq, :phase, kueri::as(:since, :time), :until, :seconds]
      )
    ]
  )
end

# Seconds per entity in each phase it has been in; ongoing is 1 for the
# phase it is in now.
def time_in_state_model(d, intervals)
  view(
    d,
    "time_in_state",
    intervals,
    [
      kueri::group(
        [:entity, :phase],
        [
          kueri::agg(:seconds, kueri::sum(:seconds)),
          kueri::agg_where(:ongoing, kueri::count_all(), kueri::is_null(:until))
        ]
      )
    ]
  )
end

# Refused records by event type and refusal kind.
def refusals_model(d, events)
  view(
    d,
    "refusals",
    events,
    [
      q_filter(kueri::eq(:status, "refused")),
      kueri::group(
        [:type, :refusal_kind],
        [kueri::agg(:records, kueri::count_all())]
      )
    ]
  )
end

# The gated rows: which capability an event in a phase uses.
def gates_model(d, edges)
  view(
    d,
    "gates",
    edges,
    [
      q_filter(kueri::not_null(:capability)),
      kueri::select([:phase_before, :type, :capability])
    ]
  )
end

# One row per rule a guard applied against a record: refused (the log
# refused the event) or breach (the replay applied it while the guard
# refused, which happens when the definition read is stricter than the one
# that wrote).
def guard_hits_model(d, steps, gates)
  view(
    d,
    "guard_hits",
    steps,
    [
      kueri::select(
        [
          :entity,
          :seq,
          :time,
          :type,
          :phase_before,
          :refusal_kind,
          :refusal_detail,
          :breach,
          :breach_capability
        ]
      ),
      kueri::left_join(gates, [:phase_before, :type]),
      q_filter(
        q_or(kueri::eq(:refusal_kind, "guard"), kueri::not_null(:breach))
      ),
      kueri::derive(
        :la_capability,
        kueri::coalesce(:breach_capability, :capability)
      ),
      kueri::derive(:la_rules, kueri::coalesce(:breach, :refusal_detail)),
      kueri::derive(
        :outcome,
        q_if(kueri::not_null(:breach), "breach", "refused")
      ),
      kueri::explode(:rule, :la_rules),
      kueri::select(
        [
          :entity,
          :seq,
          :time,
          :type,
          kueri::as(:capability, :la_capability),
          :rule,
          :outcome
        ]
      )
    ]
  )
end

def rule_hit_counts_model(d, hits)
  view(
    d,
    "rule_hit_counts",
    hits,
    [
      kueri::group(
        [:capability, :rule],
        [
          kueri::agg_where(
            :refused,
            kueri::count_all(),
            kueri::eq(:outcome, "refused")
          ),
          kueri::agg_where(
            :breached,
            kueri::count_all(),
            kueri::eq(:outcome, "breach")
          )
        ]
      )
    ]
  )
end

# Every declared rule, with how often it refused and was breached (0 when
# never: a rule that never fired is information too).
def rule_hits_model(d, rules, counts)
  view(
    d,
    "rule_hits",
    rules,
    [
      kueri::select([:capability, :rule, :needs]),
      kueri::left_join(counts, [:capability, :rule]),
      kueri::select(
        [
          :capability,
          :rule,
          :needs,
          kueri::as(:refused, kueri::coalesce(:refused, 0)),
          kueri::as(:breached, kueri::coalesce(:breached, 0))
        ]
      )
    ]
  )
end

def rule_tasks_model(d, rules)
  view(
    d,
    "rule_tasks",
    rules,
    [
      q_filter(kueri::not_null(:task)),
      kueri::select([:capability, :rule, :task, :escalate_after])
    ]
  )
end

# Each record's asks: one row per task a refusal or breach asked for.
def task_asks_model(d, hits, rule_tasks)
  view(
    d,
    "task_asks",
    hits,
    [
      q_join(rule_tasks, [:capability, :rule]),
      kueri::group(
        [:entity, :seq, :time, :task, :escalate_after],
        [kueri::agg(:asked_by, kueri::count_all())]
      )
    ]
  )
end

# Admitted events that are evidence for a task.
def task_evidence_events_model(d, steps, evidence)
  view(
    d,
    "task_evidence_events",
    steps,
    [
      q_filter(
        q_and(kueri::eq(:status, "admitted"), kueri::is_null(:replay_refusal))
      ),
      kueri::select(
        [
          :entity,
          kueri::as(:evidence_seq, :seq),
          kueri::as(:evidence_time, :time),
          kueri::as(:evidence, :type)
        ]
      ),
      q_join(evidence, [:evidence]),
      kueri::select([:entity, :task, :evidence_seq, :evidence_time])
    ]
  )
end

# Each ask with the first later evidence of its task on its entity.
def task_closes_model(d, asks, evidence_events)
  later = kueri::gt(:evidence_seq, :seq)
  view(
    d,
    "task_closes",
    asks,
    [
      kueri::left_join(evidence_events, [:entity, :task]),
      kueri::group(
        [:entity, :seq, :time, :task, :escalate_after],
        [
          kueri::agg_where(:closed_seq, q_min(:evidence_seq), later),
          kueri::agg_where(:closed_at, q_min(:evidence_time), later)
        ]
      )
    ]
  )
end

# One row per task: the asks one evidence closes are one task, opened at the
# first; still open (no evidence yet) until `now`; overdue when it stayed
# open longer than its escalate_after.
def tasks_model(d, closes, now)
  view(
    d,
    "tasks",
    closes,
    [
      kueri::group(
        [:entity, :task, :closed_seq],
        [
          kueri::agg(:opened_seq, q_min(:seq)),
          kueri::agg(:opened_at, q_min(:time)),
          kueri::agg(:asks, kueri::count_all()),
          kueri::agg(:closed_at, q_max(:closed_at)),
          kueri::agg(:escalate_after, q_max(:escalate_after))
        ]
      ),
      kueri::derive(
        :open_for,
        kueri::sub(kueri::coalesce(:closed_at, now), :opened_at)
      ),
      kueri::derive(:overdue, kueri::gt(:open_for, :escalate_after)),
      kueri::derive(
        :state,
        q_if(kueri::is_null(:closed_seq), "open", "closed")
      ),
      kueri::select(
        [
          :entity,
          :task,
          :state,
          :opened_seq,
          :opened_at,
          :closed_seq,
          :closed_at,
          :asks,
          :open_for,
          :escalate_after,
          :overdue
        ]
      )
    ]
  )
end

def task_summary_model(d, tasks)
  view(
    d,
    "task_summary",
    tasks,
    [
      kueri::group(
        [:task],
        [
          kueri::agg(:opened, kueri::count_all()),
          kueri::agg_where(
            :still_open,
            kueri::count_all(),
            kueri::eq(:state, "open")
          ),
          kueri::agg_where(
            :closed,
            kueri::count_all(),
            kueri::eq(:state, "closed")
          ),
          kueri::agg_where(:overdue, kueri::count_all(), :overdue)
        ]
      )
    ]
  )
end

# The counted fields of a capability's permit, as their log keys.
def count_keys(d, capability)
  pm = find_first(fn(p) nth(1, p) == capability end, raifusaikuru::d_permits(d))
  map(
    fn(t) raifusaikuru::permit_count_key(nth(1, t)) end,
    filter(fn(t) first(t) == :counted end, as_list(nth(2, pm)))
  )
end

# The permit models of one logged capability: issued, used, and the two
# joined.
def permit_models(d, log, events, steps, gates)
  cap = first(log)
  c = raifusaikuru::text(cap)
  counts = count_keys(d, cap)
  permits = view(
    d,
    "permits_#{c}",
    events,
    [
      q_filter(
        q_and(
          kueri::eq(:type, raifusaikuru::text(nth(1, log))),
          kueri::eq(:status, "admitted")
        )
      ),
      kueri::derive(:next_seq, kueri::lead(:seq, [:entity], [:seq])),
      kueri::select(
        concat_lists(
          concat_lists(
            [
              :entity,
              kueri::as(:permit_seq, :seq),
              kueri::as(:issued_at, :time),
              :subject,
              :not_after,
              :basis
            ],
            counts
          ),
          [:next_seq]
        )
      )
    ]
  )
  uses = view(
    d,
    "uses_#{c}",
    steps,
    [
      q_filter(
        q_and(kueri::eq(:status, "admitted"), kueri::is_null(:replay_refusal))
      ),
      kueri::select([:entity, :seq, :time, :type, :phase_before]),
      q_join(gates, [:phase_before, :type]),
      q_filter(kueri::eq(:capability, c)),
      kueri::select(
        [:entity, kueri::as(:use_seq, :seq), kueri::as(:use_time, :time)]
      )
    ]
  )
  within = q_and(
    kueri::gt(:use_seq, :permit_seq),
    q_or(kueri::is_null(:next_seq), kueri::lt(:use_seq, :next_seq))
  )
  exceeded = map(
    fn(k) kueri::derive("#{k}_exceeded", kueri::gt(:uses, kueri::c(k))) end,
    counts
  )
  keys = concat_lists(
    concat_lists(
      [:entity, :permit_seq, :issued_at, :not_after, :subject, :basis],
      counts
    ),
    [:next_seq]
  )
  out = concat_lists(
    concat_lists(
      [
        :entity,
        :permit_seq,
        :subject,
        :issued_at,
        :not_after,
        :window_seconds,
        :basis
      ],
      counts
    ),
    concat_lists(
      [:uses, :overrun, :last_use_at],
      map(fn(k) "#{k}_exceeded" end, counts)
    )
  )
  used = view(
    d,
    "permit_use_#{c}",
    permits,
    concat_lists(
      [
        kueri::left_join(uses, [:entity]),
        kueri::group(
          keys,
          [
            kueri::agg_where(
              :uses,
              kueri::count_all(),
              q_and(within, kueri::lt(:use_time, :not_after))
            ),
            kueri::agg_where(
              :overrun,
              kueri::count_all(),
              q_and(within, kueri::ge(:use_time, :not_after))
            ),
            kueri::agg_where(
              :last_use_at,
              q_max(:use_time),
              q_and(within, kueri::lt(:use_time, :not_after))
            )
          ]
        ),
        kueri::derive(:window_seconds, kueri::sub(:not_after, :issued_at))
      ],
      push(exceeded, kueri::select(out))
    )
  )
  concat_lists(
    [permits, uses, used],
    unpermitted_models(d, log, events, steps, gates)
  )
end

# Every use of a logged capability that no permit covered, and why: the
# permit in force at a use is the entity's latest permit before it (an as-of
# join on seq); there is none (`no_permit`: a use before any was issued), its
# not_after had passed (`lapsed`), or the use broke the guard (`breach`: a
# permit derived from a guard cannot cover a use that guard refused, which is
# a permit revoked by a later reading). permit_use counts a use by its window
# only; this is where a use outside every window, and a breach inside one, are
# seen. The first reason that applies, in that order.
def unpermitted_models(d, log, events, steps, gates)
  c = raifusaikuru::text(first(log))
  granted = view(
    d,
    "granted_#{c}",
    events,
    [
      q_filter(
        q_and(
          kueri::eq(:type, raifusaikuru::text(nth(1, log))),
          kueri::eq(:status, "admitted")
        )
      ),
      kueri::select([:entity, :seq, kueri::as(:permit_seq, :seq), :not_after])
    ]
  )
  reason = q_if(
    kueri::is_null(:permit_seq),
    "no_permit",
    q_if(
      kueri::ge(:time, :not_after),
      "lapsed",
      q_if(kueri::not_null(:breach), "breach", kueri::null())
    )
  )
  unpermitted = view(
    d,
    "unpermitted_#{c}",
    steps,
    [
      q_filter(
        q_and(kueri::eq(:status, "admitted"), kueri::is_null(:replay_refusal))
      ),
      kueri::select([:entity, :seq, :time, :type, :phase_before, :breach]),
      q_join(gates, [:phase_before, :type]),
      q_filter(kueri::eq(:capability, c)),
      kueri::select([:entity, :seq, :time, :breach]),
      kueri::asof_left_join(granted, [:entity, :seq]),
      kueri::derive(:reason, reason),
      q_filter(kueri::not_null(:reason)),
      kueri::select(
        [
          :entity,
          kueri::as(:use_seq, :seq),
          kueri::as(:use_time, :time),
          :permit_seq,
          :not_after,
          :breach,
          :reason
        ]
      )
    ]
  )
  [granted, unpermitted]
end

# ── spans: a declared duration, per entity ─────────────────────────────────

# The views of one lc_span of lifecycle `d`: where each entity's span starts
# (its first record after which it is in `from`), where it ends (its first
# record after that in `to`), the two joined, and a one-row summary. A span
# is `done` when it reached `to`; `abandoned` when the entity is in a
# terminal state it never reached `to` by (it never will); `open` otherwise,
# and then its elapsed time runs to `now`, like an open task's. over_limit is
# the elapsed time past the declared limit (NULL with no limit, or abandoned).
def span_models(d, sp, steps, current, now)
  s = raifusaikuru::text(raifusaikuru::span_name(sp))
  limit = raifusaikuru::span_limit(sp)
  first_row = [
    kueri::derive(:la_first, kueri::row_number([:entity], [:seq])),
    q_filter(kueri::eq(:la_first, 1))
  ]
  starts = view(
    d,
    "span_#{s}_from",
    steps,
    flatten1(
      [
        [
          q_filter(
            kueri::eq(:phase, raifusaikuru::text(raifusaikuru::span_from(sp)))
          )
        ],
        first_row,
        [
          kueri::select(
            [:entity, kueri::as(:from_seq, :seq), kueri::as(:from_at, :time)]
          )
        ]
      ]
    )
  )
  ends = view(
    d,
    "span_#{s}_to",
    steps,
    flatten1(
      [
        [
          q_filter(
            kueri::eq(:phase, raifusaikuru::text(raifusaikuru::span_to(sp)))
          ),
          q_join(starts, [:entity]),
          q_filter(kueri::gt(:seq, :from_seq))
        ],
        first_row,
        [
          kueri::select(
            [:entity, kueri::as(:to_seq, :seq), kueri::as(:to_at, :time)]
          )
        ]
      ]
    )
  )
  # After the join with the current state, :phase is the entity's phase now.
  ended = reduce(
    fn(acc, t) q_or(acc, kueri::eq(:phase, raifusaikuru::text(t))) end,
    kueri::lit(false),
    raifusaikuru::d_terminals(d)
  )
  state = q_if(
    kueri::not_null(:to_seq),
    "done",
    q_if(ended, "abandoned", "open")
  )
  over = if limit == nil
    q_cast(kueri::null(), :boolean)
  else
    kueri::gt(:elapsed, limit)
  end
  span = view(
    d,
    "span_#{s}",
    starts,
    [
      kueri::left_join(ends, [:entity]),
      q_join(current, [:entity]),
      kueri::derive(:state, state),
      kueri::derive(:seconds, kueri::sub(:to_at, :from_at)),
      kueri::derive(
        :elapsed,
        q_if(
          kueri::eq(:state, "abandoned"),
          q_cast(kueri::null(), :bigint),
          kueri::sub(kueri::coalesce(:to_at, now), :from_at)
        )
      ),
      kueri::derive(:limit_seconds, q_cast(kueri::lit(limit), :bigint)),
      kueri::derive(:over_limit, over),
      kueri::select(
        [
          :entity,
          :state,
          :from_seq,
          :from_at,
          :to_seq,
          :to_at,
          :seconds,
          :elapsed,
          :limit_seconds,
          :over_limit
        ]
      )
    ]
  )
  summary = view(
    d,
    "span_#{s}_summary",
    span,
    [
      kueri::group(
        [],
        [
          kueri::agg(:started, kueri::count_all()),
          kueri::agg_where(
            :reached,
            kueri::count_all(),
            kueri::eq(:state, "done")
          ),
          kueri::agg_where(
            :still_open,
            kueri::count_all(),
            kueri::eq(:state, "open")
          ),
          kueri::agg_where(
            :abandoned,
            kueri::count_all(),
            kueri::eq(:state, "abandoned")
          ),
          kueri::agg_where(:over_limit, kueri::count_all(), :over_limit),
          kueri::agg(:min_seconds, q_min(:seconds)),
          kueri::agg(:avg_seconds, kueri::avg(:seconds)),
          kueri::agg(:max_seconds, q_max(:seconds)),
          kueri::agg(:limit_seconds, q_max(:limit_seconds))
        ]
      )
    ]
  )
  [starts, ends, span, summary]
end

# Every model of one lifecycle, upstream first.
def lifecycle_models(b, now)
  d = la_def(b)
  check_names(d)
  records = records_source(d, get(b, :stream))
  history = history_source(d, get(b, :history))
  edges = edges_rel(d)
  rules = rules_rel(d)
  evidence = task_evidence_rel(d)
  events = events_model(d, records)
  states = states_model(d, history)
  steps = steps_model(d, events, states)
  intervals = intervals_model(d, steps, now)
  gates = gates_model(d, edges)
  hits = guard_hits_model(d, steps, gates)
  counts = rule_hit_counts_model(d, hits)
  rule_tasks = rule_tasks_model(d, rules)
  asks = task_asks_model(d, hits, rule_tasks)
  evidence_events = task_evidence_events_model(d, steps, evidence)
  closes = task_closes_model(d, asks, evidence_events)
  tasks = tasks_model(d, closes, now)
  permits = flat_map(
    fn(l) permit_models(d, l, events, steps, gates) end,
    raifusaikuru::d_permit_logs(d)
  )
  current = current_state_model(d, steps)
  spans = flat_map(
    fn(sp) span_models(d, sp, steps, current, now) end,
    raifusaikuru::d_spans(d)
  )
  flatten1(
    [
      [
        events,
        states,
        steps,
        unreplayed_model(d, events, states),
        current,
        intervals,
        time_in_state_model(d, intervals),
        refusals_model(d, events),
        gates,
        hits,
        counts,
        rule_hits_model(d, rules, counts),
        rule_tasks,
        asks,
        evidence_events,
        closes,
        tasks,
        task_summary_model(d, tasks)
      ],
      permits,
      spans
    ]
  )
end

# ── links: joins generated from the declarations ───────────────────────────

# The binding whose lifecycle is named `target`, or a refusal naming the link.
def target(bindings, a, role, target)
  hit = find_first(
    fn(b)
      raifusaikuru::text(raifusaikuru::name(la_def(b))) ==
        raifusaikuru::text(target)
    end,
    bindings
  )
  if hit == nil
    throw(
      error(
        :anaritikusu_schema,
        "#{raifusaikuru::show(raifusaikuru::name(la_def(a)))} links #{raifusaikuru::show(role)} to lifecycle #{raifusaikuru::show(target)}, which is not among the lifecycles given (#{join(map(fn(b) raifusaikuru::text(raifusaikuru::name(la_def(b))) end, bindings), ", ")})"
      )
    )
  end
  hit
end

# A model of this set, by name.
# waive B0013: `find` is a builtin anaritikusu also uses, so the prefix stays; anaritikusu::find names it too
def la_find(models, name)
  hit = find_first(fn(m) get(m, :name) == name end, models)
  if hit == nil
    throw(error(:anaritikusu_schema, "no generated relation is named #{name}"))
  end
  hit
end

# A's records carrying a link of kind `role`: one row per link, the linked
# id in the column named for the role.
def link_rows_model(ad, role, a_events)
  r = raifusaikuru::text(role)
  view(
    ad,
    "#{r}_links",
    a_events,
    [
      kueri::select([:entity, :seq, :time, :type, :status, :links]),
      kueri::explode(:la_link, :links),
      q_filter(kueri::eq(q_get(:la_link, :kind), r)),
      kueri::select(
        [
          :entity,
          :seq,
          :time,
          :type,
          :status,
          kueri::as(r, q_get(:la_link, :id))
        ]
      )
    ]
  )
end

# B's states keyed for an asof join on the role: the id in the role's column,
# the state's columns prefixed with it. One row per entity per second: the
# state after its LAST record in that second, because an asof join matches on
# time alone, and with two records in one second (a permit and the load it
# covers) it would take either. Measured 2026-09-25: NuPastel's bench day had
# 9 orders joined to the state before their own load.
def link_state_model(ad, role, bd, b_steps)
  r = raifusaikuru::text(role)
  fields = map(fn(f) kueri::as("#{r}_#{f}", kueri::c(f)) end, field_names(bd))
  view(
    ad,
    "#{r}_state",
    b_steps,
    [
      kueri::derive(
        :la_last,
        kueri::row_number([:entity, :time], [kueri::desc(:seq)])
      ),
      q_filter(kueri::eq(:la_last, 1)),
      kueri::select(
        concat_lists(
          [
            kueri::as(r, :entity),
            :time,
            kueri::as("#{r}_seq", :seq),
            kueri::as("#{r}_phase", :phase)
          ],
          fields
        )
      )
    ]
  )
end

# The columns a one-hop link view returns, after A's own.
def link_state_names(role, bd)
  r = raifusaikuru::text(role)
  concat_lists(
    ["#{r}_seq", "#{r}_phase"],
    map(fn(f) "#{r}_#{f}" end, field_names(bd))
  )
end

# Each link with the linked entity's state as of the record's time.
def link_model(ad, role, bd, rows, state)
  r = raifusaikuru::text(role)
  view(
    ad,
    r,
    rows,
    [
      kueri::asof_left_join(state, [r, :time]),
      kueri::select(
        concat_lists(
          [:entity, :seq, :time, :type, :status, r],
          link_state_names(role, bd)
        )
      )
    ]
  )
end

def link_coverage_model(ad, role, link)
  r = raifusaikuru::text(role)
  view(
    ad,
    "#{r}_coverage",
    link,
    [
      kueri::group(
        [],
        [
          kueri::agg(:links, kueri::count_all()),
          kueri::agg_where(
            :unresolved,
            kueri::count_all(),
            kueri::is_null(kueri::c("#{r}_seq"))
          )
        ]
      )
    ]
  )
end

# The four models of one declared link of A.
def link_models(bindings, models, a, link)
  ad = la_def(a)
  role = first(link)
  b = target(bindings, a, role, nth(1, link))
  bd = la_def(b)
  rows = link_rows_model(ad, role, la_find(models, n(ad, "events")))
  state = link_state_model(ad, role, bd, la_find(models, n(bd, "steps")))
  joined = link_model(ad, role, bd, rows, state)
  [rows, state, joined, link_coverage_model(ad, role, joined)]
end

# A chain A –r1→ B –r2→ C: each A link with B's latest r2 link at or before
# the A record's time, and C's state as of that B record.
def chain_models(bindings, models, a, l1, l2)
  ad = la_def(a)
  bd = la_def(target(bindings, a, first(l1), nth(1, l1)))
  cd = la_def(
    target(
      bindings,
      target(bindings, a, first(l1), nth(1, l1)),
      first(l2),
      nth(1, l2)
    )
  )
  r1 = raifusaikuru::text(first(l1))
  r2 = raifusaikuru::text(first(l2))
  b_link = la_find(models, n(bd, r2))
  c_cols = concat_lists([r2], link_state_names(first(l2), cd))
  via = view(
    ad,
    "#{r1}_#{r2}_via",
    b_link,
    [
      kueri::select(
        concat_lists(
          [
            kueri::as(r1, :entity),
            :time,
            kueri::as("#{r1}_time", :time),
            kueri::as("#{r1}_event_seq", :seq),
            kueri::as("#{r1}_type", :type)
          ],
          c_cols
        )
      )
    ]
  )
  chain = view(
    ad,
    "#{r1}_#{r2}",
    la_find(models, n(ad, "#{r1}_links")),
    [
      kueri::asof_left_join(via, [r1, :time]),
      kueri::select(
        concat_lists(
          [
            :entity,
            :seq,
            :time,
            :type,
            :status,
            r1,
            "#{r1}_event_seq",
            "#{r1}_time",
            "#{r1}_type"
          ],
          c_cols
        )
      )
    ]
  )
  [via, chain]
end

# ── the whole set ──────────────────────────────────────────────────────────

# Every model for these lifecycles, upstream first: each lifecycle's, then a
# join per declared link, then a chain per pair of links end to start.
# Refuses (:anaritikusu_schema) two lifecycles with one name, a link to a
# lifecycle not given, and any two generated relations with one name.
def models(bindings, now)
  bs = as_list(bindings)
  names = map(fn(b) raifusaikuru::text(raifusaikuru::name(la_def(b))) end, bs)
  dup = unique(filter(fn(n) count_of(names, n) > 1 end, names))
  if is_empty(dup) == false
    throw(
      error(:anaritikusu_schema, "two lifecycles are named #{join(dup, ", ")}")
    )
  end
  if integer?(now) == false
    throw(
      error(
        :anaritikusu_schema,
        "now is a whole-number time on the lifecycles' clock, not #{raifusaikuru::show(now)}"
      )
    )
  end
  own = flat_map(fn(b) lifecycle_models(b, now) end, bs)
  links = flat_map(
    fn(b)
      flat_map(
        fn(l) link_models(bs, own, b, l) end,
        raifusaikuru::d_links(la_def(b))
      )
    end,
    bs
  )
  both = concat_lists(own, links)
  chains = flat_map(
    fn(b)
      flat_map(
        fn(l1) chains_from(bs, both, b, l1) end,
        raifusaikuru::d_links(la_def(b))
      )
    end,
    bs
  )
  all = concat_lists(both, chains)
  check_unique(all, flat_map(fn(b) source_names(la_def(b)) end, bs))
  all
end

# The relations a lifecycle loads rather than derives.
def source_names(d)
  map(
    fn(x) n(d, x) end,
    ["records", "history", "edges", "rules", "task_evidence"]
  )
end

def chains_from(bindings, models, a, l1)
  bd = la_def(target(bindings, a, first(l1), nth(1, l1)))
  flat_map(
    fn(l2) chain_models(bindings, models, a, l1, l2) end,
    raifusaikuru::d_links(bd)
  )
end

# Every generated relation (the models and the loaded sources) by name: two
# with one name would collapse into one in the database, since kueri
# identifies a node by its name.
def check_unique(models, sources)
  names = concat_lists(map(fn(m) get(m, :name) end, models), sources)
  dup = unique(filter(fn(n) count_of(names, n) > 1 end, names))
  if is_empty(dup) == false
    throw(
      error(
        :anaritikusu_schema,
        "two generated relations are named #{join(dup, ", ")}; rename a lifecycle, role or field"
      )
    )
  end
  models
end

# The script that builds the database: every load, then every view.
def script(bindings, now)
  kueri::render_script(models(bindings, now), :duckdb, "anaritikusu")
end

# ── the history: the state after every record ──────────────────────────────

# A value as JSON data: a keyword becomes its text, everywhere inside.
def json_value(v)
  if v == nil
    nil
  elsif keyword?(v)
    raifusaikuru::text(v)
  elsif list?(v)
    map(fn(x) json_value(x) end, v)
  else
    v
  end
end

# One history line: the record, the state after it, and what the replay
# found on it — a breach (the guard refused an event it applied) or a
# refusal of an admitted record. Canonical JSON, keys in code-point order.
def history_line(r, s)
  pos = raifusaikuru::seq(s) - 1
  folded = nisshi::rec_admitted?(r)
  b = last(raifusaikuru::breaches(s))
  rf = last(raifusaikuru::refused(s))
  breach = if folded && b != nil && raifusaikuru::breach_position(b) == pos
    b
  else
    nil
  end
  refusal = if folded && rf != nil && raifusaikuru::refusal_position(rf) == pos
    raifusaikuru::text(raifusaikuru::refusal_kind(rf))
  else
    nil
  end
  rules = if breach == nil
    nil
  else
    map(fn(x) raifusaikuru::text(x) end, raifusaikuru::breach_rules(breach))
  end
  capability = if breach == nil
    nil
  else
    raifusaikuru::text(raifusaikuru::breach_capability(breach))
  end
  fields = if is_empty(raifusaikuru::fields(s))
    ""
  else
    ",\"fields\":#{nisshi::canon_object(map(fn(kv) [raifusaikuru::text(first(kv)), json_value(nth(1, kv))] end, raifusaikuru::fields(s)))}"
  end
  # The keys are fixed, so they are written in code-point order here rather
  # than sorted per line (the benchmark's hot path; el_canon_object still
  # orders the fields, whose names are the definition's).
  "{\"breach\":#{nisshi::canon(rules)},\"breach_capability\":#{nisshi::canon(capability)},\"entity\":#{json_stringify(nisshi::rec_entity(r))}#{fields},\"phase\":#{json_stringify(raifusaikuru::text(raifusaikuru::phase(s)))},\"replay_refusal\":#{nisshi::canon(refusal)},\"seq\":#{to_s(nisshi::rec_seq(r))}}"
end

# The history of a log value that was read: one line per record. Pure.
def history_text(log)
  nisshi::unlines(
    map(fn(x) history_line(first(x), nth(1, x)) end, nisshi::history(log))
  )
end

# Write a log's history to `path`; returns the path.
def write_history(log, path)
  write_file(path, history_text(log))
  path
end

# ── building and reading the database ──────────────────────────────────────

# A stream to analyse: its definition, its path and its label (the genesis
# nisshi hashes it under).
def stream(d, path, label)
  raifusaikuru::name(d)
  {def: d, path: path, label: label}
end

# The bindings la_build uses: each stream's history under `dir`.
def bindings(dir, streams)
  map(
    fn(s)
      binding(
        get(s, :def),
        get(s, :path),
        path_join(
          dir,
          "#{raifusaikuru::text(raifusaikuru::name(get(s, :def)))}.history.jsonl"
        )
      )
    end,
    as_list(streams)
  )
end

# Build the database under `dir`: read and verify every stream (a broken
# chain throws :anaritikusu_broken), write each history, write the script
# (lifecycles.sql, for a reader or a nix build), and run it into a fresh
# lifecycles.duckdb. Returns the database's path.
def build(dir, streams, now)
  bindings = anaritikusu::bindings(dir, streams)
  script = anaritikusu::script(bindings, now)
  map(fn(s) build_history(dir, s) end, as_list(streams))
  write_file(path_join(dir, "lifecycles.sql"), script)
  db = path_join(dir, "lifecycles.duckdb")
  if path_exists(db)
    rm(db)
  end
  kueri::run_at(db, script)
  db
end

def build_history(dir, s)
  d = get(s, :def)
  log = nisshi::read(get(s, :path), get(s, :label), d)
  rep = nisshi::verify(log, nil, nil)
  if nisshi::intact?(rep) == false
    throw(
      error(
        :anaritikusu_broken,
        "#{get(s, :path)}: position #{to_s(nisshi::break_position(rep))}, #{to_s(nisshi::break_kind(rep))}: #{nisshi::break_why(rep)}"
      )
    )
  end
  write_history(
    log,
    path_join(dir, "#{raifusaikuru::text(raifusaikuru::name(d))}.history.jsonl")
  )
end

# A model's rows from the database at `db`, as value lists in its column
# order, sorted by every column; a failed query throws (:kueri_query). A
# generated view is read from the database; any other model over them (a
# question of its own) runs its query there.
def read(db, model)
  cols = kueri::output(model)
  query = if get(model, :materialize) == :view
    kueri::model({name: "la_read", from: model, pipeline: [kueri::sort(cols)]})
  else
    kueri::then(model, [kueri::sort(cols)])
  end
  map(
    fn(row) map(fn(c) as_json(row, c) end, cols) end,
    kueri::rows_at(db, kueri::render(query, :duckdb))
  )
end

# ── worked examples: three lifecycles and a day ────────────────────────────

# raifusaikuru's example consumable, with its permits logged as `permit`.
def example_consumable()
  lc_define(
    :consumable,
    push(
      raifusaikuru::example_consumable_clauses(),
      raifusaikuru::permit_log(:use, :permit)
    )
  )
end

# The same consumable read by a stricter definition: fewer than 3 uses. Built
# from the example's clauses with the one rule replaced, as data.
def example_consumable_strict()
  clauses = map(
    fn(c) example_tighten(c) end,
    push(
      raifusaikuru::example_consumable_clauses(),
      raifusaikuru::permit_log(:use, :permit)
    )
  )
  lc_define(:consumable, clauses)
end

def example_tighten(c)
  if list?(c) && is_empty(c) == false && first(c) == :lc_guard
    [
      :lc_guard,
      nth(1, c),
      map(fn(r) example_tighten_rule(r) end, nth(2, c)),
      nth(3, c)
    ]
  else
    c
  end
end

def example_tighten_rule(r)
  if nth(1, r) == :uses_left
    raifusaikuru::rule(:uses_left, raifusaikuru::below(:uses, 3))
  else
    r
  end
end

# A portion made with a consumable: its make event links the item.
def example_portion()
  lc_define(
    :portion,
    [
      raifusaikuru::states([:new, :made, :served, :wasted]),
      raifusaikuru::start(:new),
      raifusaikuru::terminals([:served, :wasted]),
      raifusaikuru::field(:grams, 0),
      raifusaikuru::field(:made_at, nil),
      raifusaikuru::field(:served_at, nil),
      raifusaikuru::event(:make, [:grams]),
      raifusaikuru::event(:serve, []),
      raifusaikuru::event(:waste, []),
      raifusaikuru::on(
        :new,
        :make,
        :made,
        [raifusaikuru::set(:grams, :grams), raifusaikuru::stamp(:made_at)]
      ),
      raifusaikuru::on(
        :made,
        :serve,
        :served,
        [raifusaikuru::stamp(:served_at)]
      ),
      raifusaikuru::on(:made, :waste, :wasted, []),
      raifusaikuru::link(:item, :consumable)
    ]
  )
end

# An order of portions: each add_portion links one.
def example_order()
  lc_define(
    :order,
    [
      raifusaikuru::states([:new, :placed, :ready, :delivered, :cancelled]),
      raifusaikuru::start(:new),
      raifusaikuru::terminals([:delivered, :cancelled]),
      raifusaikuru::field(:portions, 0),
      raifusaikuru::field(:placed_at, nil),
      raifusaikuru::field(:delivered_at, nil),
      raifusaikuru::event(:place, []),
      raifusaikuru::event(:add_portion, []),
      raifusaikuru::event(:ready, []),
      raifusaikuru::event(:deliver, []),
      raifusaikuru::event(:cancel, []),
      raifusaikuru::on(
        :new,
        :place,
        :placed,
        [raifusaikuru::stamp(:placed_at)]
      ),
      raifusaikuru::on(
        :placed,
        :add_portion,
        :stay,
        [raifusaikuru::add(:portions, 1)]
      ),
      raifusaikuru::on(:placed, :ready, :ready, []),
      raifusaikuru::on(
        :ready,
        :deliver,
        :delivered,
        [raifusaikuru::stamp(:delivered_at)]
      ),
      raifusaikuru::on_each([:placed, :ready], :cancel, :cancelled, []),
      raifusaikuru::link(:portion, :portion),
      raifusaikuru::span(:lead, :placed, :delivered, 2000),
      raifusaikuru::span(:ready_to_door, :ready, :delivered, nil)
    ]
  )
end

# A simulated day, in time order: [lifecycle, entity, event, links]. An event
# [:la_permit, time, subject] is a permit the engine issues at that moment
# (lc_permit_for on the entity's state) and logs (lc_permit_event).
def example_day()
  [
    [
      :consumable,
      "item-1",
      raifusaikuru::ev(:reading, 28800, [[:value, 10]]),
      []
    ],
    [
      :consumable,
      "item-2",
      raifusaikuru::ev(:reading, 28900, [[:value, 10]]),
      []
    ],
    [:consumable, "item-1", raifusaikuru::ev(:open, 29000, []), []],
    [:consumable, "item-1", [:la_permit, 29100, "device-1"], []],
    [:order, "o-1", raifusaikuru::ev(:place, 29100, []), []],
    [:consumable, "item-1", raifusaikuru::ev(:use, 29200, []), []],
    [
      :portion,
      "p-1",
      raifusaikuru::ev(:make, 29250, [[:grams, 120]]),
      [[:item, "item-1"], [:lot, "L-7"]]
    ],
    [:consumable, "item-1", raifusaikuru::ev(:use, 29300, []), []],
    [:consumable, "item-1", raifusaikuru::ev(:use, 29400, []), []],
    [:portion, "p-1", raifusaikuru::ev(:serve, 29400, []), []],
    [
      :order,
      "o-1",
      raifusaikuru::ev(:add_portion, 29450, []),
      [[:portion, "p-1"]]
    ],
    [:consumable, "item-2", raifusaikuru::ev(:open, 29500, []), []],
    [:consumable, "item-2", [:la_permit, 29550, "device-2"], []],
    [:consumable, "item-2", raifusaikuru::ev(:use, 29600, []), []],
    [
      :portion,
      "p-3",
      raifusaikuru::ev(:make, 29650, [[:grams, 130]]),
      [[:item, "item-2"]]
    ],
    [:consumable, "item-2", raifusaikuru::ev(:open, 29700, []), []],
    [
      :consumable,
      "item-1",
      raifusaikuru::ev(:reading, 30000, [[:value, 26]]),
      []
    ],
    [:consumable, "item-3", raifusaikuru::ev(:discard, 30000, []), []],
    [:order, "o-2", raifusaikuru::ev(:place, 30000, []), []],
    [
      :portion,
      "p-2",
      raifusaikuru::ev(:make, 30050, [[:grams, 110]]),
      [[:item, "item-1"]]
    ],
    [:consumable, "item-1", raifusaikuru::ev(:use, 30100, []), []],
    [:consumable, "item-3", raifusaikuru::ev(:polish, 30100, []), []],
    [
      :order,
      "o-2",
      raifusaikuru::ev(:add_portion, 30100, []),
      [[:portion, "p-2"]]
    ],
    [:portion, "p-2", raifusaikuru::ev(:waste, 30500, []), []],
    [:order, "o-2", raifusaikuru::ev(:cancel, 30600, []), []],
    [
      :consumable,
      "item-1",
      raifusaikuru::ev(:reading, 31000, [[:value, 12]]),
      []
    ],
    [:portion, "p-3", raifusaikuru::ev(:serve, 31000, []), []],
    [
      :order,
      "o-1",
      raifusaikuru::ev(:add_portion, 31050, []),
      [[:portion, "p-3"]]
    ],
    [:consumable, "item-1", raifusaikuru::ev(:use, 31100, []), []],
    [:order, "o-1", raifusaikuru::ev(:ready, 31200, []), []],
    [:order, "o-1", raifusaikuru::ev(:deliver, 31500, []), []],
    [:consumable, "item-1", raifusaikuru::ev(:finish, 32000, []), []],
    [
      :portion,
      "p-4",
      raifusaikuru::ev(:make, 33000, [[:grams, 100]]),
      [[:item, "item-9"]]
    ],
    [:order, "o-3", raifusaikuru::ev(:place, 33100, []), []],
    [:portion, "p-4", raifusaikuru::ev(:serve, 33500, []), []],
    [
      :order,
      "o-3",
      raifusaikuru::ev(:add_portion, 33600, []),
      [[:portion, "p-4"]]
    ],
    [:order, "o-3", raifusaikuru::ev(:deliver, 33700, []), []],
    [:consumable, "item-2", raifusaikuru::ev(:use, 40000, []), []],
    [:consumable, "item-2", raifusaikuru::ev(:use, 44000, []), []]
  ]
end

# The day's three streams under `dir`: [la_stream …], after appending every
# event to its lifecycle's stream through nisshi.
def example_streams(dir)
  defs = [example_consumable(), example_portion(), example_order()]
  streams = map(
    fn(d)
      stream(
        d,
        path_join(dir, "#{raifusaikuru::text(raifusaikuru::name(d))}.jsonl"),
        "anaritikusu-example/#{raifusaikuru::text(raifusaikuru::name(d))}"
      )
    end,
    defs
  )
  logs = reduce(
    fn(m, s)
      assoc(
        m,
        raifusaikuru::text(raifusaikuru::name(get(s, :def))),
        nisshi::read(get(s, :path), get(s, :label), get(s, :def))
      )
    end,
    {},
    streams
  )
  reduce(fn(m, x) example_append(m, x) end, logs, example_day())
  streams
end

def example_append(logs, x)
  kind = raifusaikuru::text(first(x))
  log = get(logs, kind)
  ev = example_event(log, nth(1, x), nth(2, x))
  assoc(logs, kind, el_append(log, nth(1, x), ev, nth(3, x)))
end

def example_event(log, entity, ev)
  if first(ev) == :la_permit
    d = el_def(log)
    raifusaikuru::permit_event(
      d,
      raifusaikuru::permit_for(d, nisshi::state(log, entity), :use, nth(1, ev)),
      nth(2, ev)
    )
  else
    ev
  end
end

# A fresh directory under TMPDIR for a test.
def test_dir(name)
  dir = path_join(
    getenv("TMPDIR", "/tmp"),
    "anaritikusu-#{name}-#{to_s(now_ns())}"
  )
  mkdir_p(dir)
  dir
end

# A value as the tests compare it: numbers as floats (DuckDB answers 12.0
# where the fold holds 12).
def norm(v)
  if number?(v)
    to_float(v)
  else
    v
  end
end

def norm_rows(rows)
  map(fn(r) map(fn(v) norm(v) end, r) end, rows)
end

# ── tests ──────────────────────────────────────────────────────────────────

test "the telemetry schema is derived from the definition: the record's columns, then the typed keys and fields"
  d = example_consumable()
  # By hand: value flows into quality, which lc_below compares, so both are
  # DOUBLE; uses counts from 0 by 1 (BIGINT); opened_at and read_at are
  # stamped (BIGINT); the permit log's keys are subject text and whole-number
  # limits.
  assert columns_text(event_columns(d)) ==
    [
      ["entity", "VARCHAR"],
      ["seq", "BIGINT"],
      ["time", "BIGINT"],
      ["type", "VARCHAR"],
      ["status", "VARCHAR"],
      ["refusal_kind", "VARCHAR"],
      ["refusal_detail", "VARCHAR[]"],
      ["links", "STRUCT(id VARCHAR, kind VARCHAR)[]"],
      ["value", "DOUBLE"],
      ["subject", "VARCHAR"],
      ["not_after", "BIGINT"],
      ["basis", "BIGINT"],
      ["uses_left", "BIGINT"],
      ["prev", "VARCHAR"],
      ["hash", "VARCHAR"],
      ["sig", "VARCHAR"]
    ]
  assert columns_text(state_columns(d)) ==
    [
      ["entity", "VARCHAR"],
      ["seq", "BIGINT"],
      ["phase", "VARCHAR"],
      ["uses", "BIGINT"],
      ["opened_at", "BIGINT"],
      ["quality", "DOUBLE"],
      ["read_at", "BIGINT"],
      ["breach", "VARCHAR[]"],
      ["breach_capability", "VARCHAR"],
      ["replay_refusal", "VARCHAR"]
    ]
  # grams is set from a key into a field that starts at 0: numbers, widened
  # to DOUBLE because the key comes from outside.
  assert field_types(example_portion()) ==
    [["grams", :double], ["made_at", :bigint], ["served_at", :bigint]]
  # The empty case: a lifecycle with no fields and no payload keys has the
  # record's columns and nothing else.
  bare = lc_define(
    :bare,
    [
      raifusaikuru::states([:a, :b]),
      raifusaikuru::start(:a),
      raifusaikuru::terminals([:b]),
      raifusaikuru::event(:go, []),
      raifusaikuru::on(:a, :go, :b, [])
    ]
  )
  assert size(event_columns(bare)) == 11
  assert map(fn(c) get(c, :name) end, state_columns(bare)) ==
    ["entity", "seq", "phase", "breach", "breach_capability", "replay_refusal"]
  # Unconstrained is text, never a guess.
  noted = lc_define(
    :noted,
    [
      raifusaikuru::states([:a, :b]),
      raifusaikuru::start(:a),
      raifusaikuru::terminals([:b]),
      raifusaikuru::field(:note, nil),
      raifusaikuru::event(:go, [:note]),
      raifusaikuru::on(:a, :go, :b, [raifusaikuru::set(:note, :note)])
    ]
  )
  assert key_types(noted) == [["note", :varchar]]
  # Controls: a key named like a record column, a field named like a state
  # column, and a field whose constants disagree are refused.
  clash = lc_define(
    :clash,
    [
      raifusaikuru::states([:a, :b]),
      raifusaikuru::start(:a),
      raifusaikuru::terminals([:b]),
      raifusaikuru::event(:go, [:time]),
      raifusaikuru::on(:a, :go, :b, [])
    ]
  )
  assert error?(try(event_columns(clash), catch(e(), e)))
  phased = lc_define(
    :phased,
    [
      raifusaikuru::states([:a, :b]),
      raifusaikuru::start(:a),
      raifusaikuru::terminals([:b]),
      raifusaikuru::field(:phase, nil),
      raifusaikuru::event(:go, []),
      raifusaikuru::on(:a, :go, :b, [])
    ]
  )
  assert error?(try(state_columns(phased), catch(e(), e)))
  mixed = lc_define(
    :mixed,
    [
      raifusaikuru::states([:a, :b]),
      raifusaikuru::start(:a),
      raifusaikuru::terminals([:b]),
      raifusaikuru::field(:x, 0),
      raifusaikuru::event(:go, []),
      raifusaikuru::on(:a, :go, :b, [raifusaikuru::put(:x, "high")])
    ]
  )
  assert error?(try(field_types(mixed), catch(e(), e)))
end

test "the history is the fold's state after every record, and names what the replay found"
  d = example_consumable()
  dir = test_dir("history")
  p = path_join(dir, "c.jsonl")
  # The empty case: no stream, no history.
  assert history_text(nisshi::read(p, "t", d)) == ""
  nisshi::append_all(
    nisshi::read(p, "t", d),
    [
      ["item-1", raifusaikuru::ev(:open, 1000, []), []],
      ["item-1", raifusaikuru::ev(:reading, 1100, [[:value, 26]]), []],
      ["item-1", raifusaikuru::ev(:use, 1200, []), []],
      ["item-1", raifusaikuru::ev(:use, 1300, []), []]
    ]
  )
  log = nisshi::read(p, "t", d)
  lines = nisshi::lines(history_text(log))
  # By hand: open, a reading of 26, then two uses the guard refuses
  # (quality_ok), written refused: the state after each use is the state
  # before it, and nothing is a breach.
  assert size(lines) == 4
  assert nth(2, lines) ==
    "{\"breach\":null,\"breach_capability\":null,\"entity\":\"item-1\",\"fields\":{\"opened_at\":1000,\"quality\":26,\"read_at\":1100,\"uses\":0},\"phase\":\"open\",\"replay_refusal\":null,\"seq\":2}"
  assert nth(3, lines) == replace(nth(2, lines), "\"seq\":2", "\"seq\":3")
  # Read by a definition with no quality rule, the same stream's admitted
  # records fold the same; read by one where `use` has no row at all, an
  # admitted use would be refused on replay and says so. Here: a stream whose
  # admitted open the strict reader cannot accept.
  closed = lc_define(
    :consumable,
    [
      raifusaikuru::states([:sealed, :gone]),
      raifusaikuru::start(:sealed),
      raifusaikuru::terminals([:gone]),
      raifusaikuru::event(:open, []),
      raifusaikuru::event(:reading, [:value]),
      raifusaikuru::event(:use, []),
      raifusaikuru::on(:sealed, :reading, :gone, [])
    ]
  )
  first_line = first(nisshi::lines(history_text(nisshi::read(p, "t", closed))))
  assert contains?(first_line, "\"replay_refusal\":\"no_edge\"")
  assert contains?(first_line, "\"phase\":\"sealed\"")
  # The control: the tightened guard turns an applied event into a breach
  # (the strict example allows 3 uses; this stream has none admitted, so a
  # stream with four admitted uses is written first).
  q = path_join(dir, "s.jsonl")
  nisshi::append_all(
    nisshi::read(q, "t", d),
    [
      ["item-1", raifusaikuru::ev(:reading, 1000, [[:value, 10]]), []],
      ["item-1", raifusaikuru::ev(:open, 1100, []), []],
      ["item-1", raifusaikuru::ev(:use, 1200, []), []],
      ["item-1", raifusaikuru::ev(:use, 1300, []), []],
      ["item-1", raifusaikuru::ev(:use, 1400, []), []],
      ["item-1", raifusaikuru::ev(:use, 1500, []), []]
    ]
  )
  strict = nisshi::lines(
    history_text(nisshi::read(q, "t", example_consumable_strict()))
  )
  assert map(
    fn(l)
      contains?(l, "\"breach\":[\"uses_left\"],\"breach_capability\":\"use\"")
    end,
    strict
  ) ==
    [false, false, false, false, false, true]
  rm_rf(dir)
end

test "the database for a simulated day: every view's numbers, checked by hand, and the fold as the differential"
  dir = test_dir("day")
  streams = example_streams(dir)
  now = 86400
  db = build(dir, streams, now)
  ms = models(bindings(dir, streams), now)
  view = fn(name) norm_rows(read(db, la_find(ms, name))) end
  # The day, per stream (seq in brackets; time in seconds, 08:00 is 28800,
  # `now` is the end of the day, 86400). consumable, raifusaikuru's example
  # (a use needs: open; a reading under 4 h old and below 24; fewer than 40
  # uses; opened under 72 h ago), with its permits logged:
  #   item-1 [0] 28800 reading 10  [1] 29000 open  [2] 29100 permit
  #          [3] 29200 use  [4] 29300 use  [5] 29400 use  [6] 30000 reading 26
  #          [7] 30100 use REFUSED guard quality_ok (26 is not below 24)
  #          [8] 31000 reading 12  [9] 31100 use  [10] 32000 finish -> spent
  #   item-2 [0] 28900 reading 10  [1] 29500 open  [2] 29550 permit
  #          [3] 29600 use  [4] 29700 open REFUSED no_edge (already open)
  #          [5] 40000 use (reading 11100 s old, fresh)
  #          [6] 44000 use REFUSED guard reading_fresh (15100 s >= 14400)
  #   item-3 [0] 30000 discard -> discarded  [1] 30100 polish REFUSED unknown
  # portion (links :item to a consumable):
  #   p-1 [0] 29250 make 120 item-1 (and a link of kind lot, which no
  #       lc_link declares: carried by the log, joined by nothing)
  #       [1] 29400 serve
  #   p-2 [0] 30050 make 110 item-1  [1] 30500 waste
  #   p-3 [0] 29650 make 130 item-2  [1] 31000 serve
  #   p-4 [0] 33000 make 100 item-9 (no such consumable)  [1] 33500 serve
  # order (links :portion to a portion):
  #   o-1 [0] 29100 place  [1] 29450 add p-1  [2] 31050 add p-3  [3] 31200 ready
  #       [4] 31500 deliver
  #   o-2 [0] 30000 place  [1] 30100 add p-2  [2] 30600 cancel
  #   o-3 [0] 33100 place  [1] 33600 add p-4  [2] 33700 deliver REFUSED no_edge
  #
  # Every record has its state: nothing unreplayed.
  assert map(
    fn(n) view("#{n}_unreplayed") end,
    ["consumable", "portion", "order"]
  ) ==
    [[[0.0]], [[0.0]], [[0.0]]]
  # Current state. item-1: four admitted uses (the refused one at 30100 is
  # not folded), quality 12 from the last reading, read at 31000. item-2:
  # two admitted uses; the refused open changed nothing (opened_at 29500).
  # item-3 was discarded sealed; its refused polish is its last record.
  assert view("consumable_current_state") ==
    norm_rows(
      [
        ["item-1", "spent", 4, 29000, 12, 31000, 10, 32000],
        ["item-2", "open", 2, 29500, 10, 28900, 6, 44000],
        ["item-3", "discarded", 0, nil, nil, nil, 1, 30100]
      ]
    )
  assert view("portion_current_state") ==
    norm_rows(
      [
        ["p-1", "served", 120, 29250, 29400, 1, 29400],
        ["p-2", "wasted", 110, 30050, nil, 1, 30500],
        ["p-3", "served", 130, 29650, 31000, 1, 31000],
        ["p-4", "served", 100, 33000, 33500, 1, 33500]
      ]
    )
  assert view("order_current_state") ==
    norm_rows(
      [
        ["o-1", "delivered", 2, 29100, 31500, 4, 31500],
        ["o-2", "cancelled", 1, 30000, nil, 2, 30600],
        ["o-3", "placed", 1, 33100, nil, 2, 33700]
      ]
    )
  # The differential: the same phases and fields as nisshi's own replay.
  map(fn(s) example_differential(db, ms, s) end, streams)
  # Time in each state, to 86400. item-1: sealed 28800-29000 = 200, open
  # 29000-32000 = 3000, spent 32000-86400 = 54400 (now). item-2: sealed
  # 28900-29500 = 600, open 29500-86400 = 56900 (now). item-3: discarded
  # 30000-86400 = 56400 (now).
  assert view("consumable_time_in_state") ==
    norm_rows(
      [
        ["item-1", "open", 3000, 0],
        ["item-1", "sealed", 200, 0],
        ["item-1", "spent", 54400, 1],
        ["item-2", "open", 56900, 1],
        ["item-2", "sealed", 600, 0],
        ["item-3", "discarded", 56400, 1]
      ]
    )
  # o-1: placed 29100-31200 = 2100, ready 31200-31500 = 300, delivered
  # 31500-86400 = 54900. o-2: placed 600, cancelled 55800. o-3: placed
  # 33100-86400 = 53300 (its refused deliver left it placed).
  assert view("order_time_in_state") ==
    norm_rows(
      [
        ["o-1", "delivered", 54900, 1],
        ["o-1", "placed", 2100, 0],
        ["o-1", "ready", 300, 0],
        ["o-2", "cancelled", 55800, 1],
        ["o-2", "placed", 600, 0],
        ["o-3", "placed", 53300, 1]
      ]
    )
  # Refusals by type and kind.
  assert view("consumable_refusals") ==
    norm_rows(
      [
        ["open", "no_edge", 1],
        ["polish", "unknown_event", 1],
        ["use", "guard", 2]
      ]
    )
  assert view("portion_refusals") == []
  assert view("order_refusals") == norm_rows([["deliver", "no_edge", 1]])
  # Every declared rule: quality_ok refused item-1's use at 30100,
  # reading_fresh item-2's at 44000; no breaches (nisshi refuses at append).
  assert view("consumable_rule_hits") ==
    norm_rows(
      [
        ["use", "is_open", "phase in [:open]", 0, 0],
        ["use", "not_too_old", "opened_at less than 259200 old", 0, 0],
        ["use", "quality_ok", "quality below 24", 1, 0],
        ["use", "reading_fresh", "read_at less than 14400 old", 1, 0],
        ["use", "uses_left", "uses below 40", 0, 0]
      ]
    )
  # Tasks. quality_ok names no task, so its guard's `replace` (evidence
  # reading or scan, 1200 s) opens at 30100 and item-1's reading at 31000
  # closes it: open 900 s, not overdue. reading_fresh asks take_reading
  # (evidence reading, 1200 s) at 44000, and no reading follows: open
  # 86400 - 44000 = 42400 s, overdue.
  assert view("consumable_tasks") ==
    norm_rows(
      [
        [
          "item-1",
          "replace",
          "closed",
          7,
          30100,
          8,
          31000,
          1,
          900,
          1200,
          false
        ],
        [
          "item-2",
          "take_reading",
          "open",
          6,
          44000,
          nil,
          nil,
          1,
          42400,
          1200,
          true
        ]
      ]
    )
  assert view("consumable_task_summary") ==
    norm_rows([["replace", 1, 0, 1, 0], ["take_reading", 1, 1, 0, 1]])
  # Permits. item-1's at 29100: not_after = min(28800 + 14400, 29000 +
  # 259200, 29100 + 7200) = 36300, 40 uses left, basis 2 (two events folded);
  # used by the four admitted uses after it, all before 36300, the last at
  # 31100. item-2's at 29550: not_after = min(43300, 288700, 36750) = 36750;
  # one use at 29600 inside it, and the use at 40000 after not_after, an
  # overrun (the guard still held, the permit had lapsed).
  assert view("consumable_permit_use_use") ==
    norm_rows(
      [
        [
          "item-1",
          2,
          "device-1",
          29100,
          36300,
          7200,
          2,
          40,
          4,
          0,
          31100,
          false
        ],
        ["item-2", 2, "device-2", 29550, 36750, 7200, 2, 40, 1, 1, 29600, false]
      ]
    )
  # Links: each portion's consumable as it was when the portion was made (its
  # latest record at or before the make). p-1 at 29250: item-1 after [3]
  # (1 use, quality 10). p-2 at 30050: item-1 after [6], the reading of 26,
  # out of spec. p-3 at 29650: item-2 after [3]. p-4 names item-9, which has
  # no records: the row stays, unresolved.
  assert view("portion_item") ==
    norm_rows(
      [
        [
          "p-1",
          0,
          29250,
          "make",
          "admitted",
          "item-1",
          3,
          "open",
          1,
          29000,
          10,
          28800
        ],
        [
          "p-2",
          0,
          30050,
          "make",
          "admitted",
          "item-1",
          6,
          "open",
          3,
          29000,
          26,
          30000
        ],
        [
          "p-3",
          0,
          29650,
          "make",
          "admitted",
          "item-2",
          3,
          "open",
          1,
          29500,
          10,
          28900
        ],
        [
          "p-4",
          0,
          33000,
          "make",
          "admitted",
          "item-9",
          nil,
          nil,
          nil,
          nil,
          nil,
          nil
        ]
      ]
    )
  assert view("portion_item_coverage") == [[4.0, 1.0]]
  # Each order's portion as it was when it was added.
  assert view("order_portion") ==
    norm_rows(
      [
        [
          "o-1",
          1,
          29450,
          "add_portion",
          "admitted",
          "p-1",
          1,
          "served",
          120,
          29250,
          29400
        ],
        [
          "o-1",
          2,
          31050,
          "add_portion",
          "admitted",
          "p-3",
          1,
          "served",
          130,
          29650,
          31000
        ],
        [
          "o-2",
          1,
          30100,
          "add_portion",
          "admitted",
          "p-2",
          0,
          "made",
          110,
          30050,
          nil
        ],
        [
          "o-3",
          1,
          33600,
          "add_portion",
          "admitted",
          "p-4",
          1,
          "served",
          100,
          33000,
          33500
        ]
      ]
    )
  assert view("order_portion_coverage") == [[4.0, 0.0]]
  # The chain, generated from the two declarations: each order's portion, the
  # consumable that portion was made with, and that consumable's state at the
  # make. o-2's portion p-2 was made with item-1 while its quality read 26.
  assert view("order_portion_item") ==
    norm_rows(
      [
        [
          "o-1",
          1,
          29450,
          "add_portion",
          "admitted",
          "p-1",
          0,
          29250,
          "make",
          "item-1",
          3,
          "open",
          1,
          29000,
          10,
          28800
        ],
        [
          "o-1",
          2,
          31050,
          "add_portion",
          "admitted",
          "p-3",
          0,
          29650,
          "make",
          "item-2",
          3,
          "open",
          1,
          29500,
          10,
          28900
        ],
        [
          "o-2",
          1,
          30100,
          "add_portion",
          "admitted",
          "p-2",
          0,
          30050,
          "make",
          "item-1",
          6,
          "open",
          3,
          29000,
          26,
          30000
        ],
        [
          "o-3",
          1,
          33600,
          "add_portion",
          "admitted",
          "p-4",
          0,
          33000,
          "make",
          "item-9",
          nil,
          nil,
          nil,
          nil,
          nil,
          nil
        ]
      ]
    )
  # The event table's payload column, read back typed.
  readings = kueri::model(
    {
      name: :la_readings,
      from: la_find(ms, "consumable_events"),
      pipeline: [
        q_filter(kueri::eq(:type, "reading")),
        kueri::select([:entity, :seq, :value])
      ]
    }
  )
  assert norm_rows(read(db, readings)) ==
    norm_rows(
      [
        ["item-1", 0, 10],
        ["item-1", 6, 26],
        ["item-1", 8, 12],
        ["item-2", 0, 10]
      ]
    )
  # Spans, declared on the order. lead (placed -> delivered, limit 2000):
  # o-1 placed 29100 [0], delivered 31500 [4]: 2400 s, over. o-2 was placed
  # at 30000 and cancelled, a terminal it never reaches delivered from:
  # abandoned, no elapsed time, not judged. o-3 placed 33100 and never
  # delivered (its deliver was refused): open, 86400 - 33100 = 53300 s, over.
  # ready_to_door (ready -> delivered, no limit): only o-1 was ready, at 31200
  # [3], delivered 300 s later.
  assert view("order_span_lead") ==
    norm_rows(
      [
        ["o-1", "done", 0, 29100, 4, 31500, 2400, 2400, 2000, true],
        ["o-2", "abandoned", 0, 30000, nil, nil, nil, nil, 2000, nil],
        ["o-3", "open", 0, 33100, nil, nil, nil, 53300, 2000, true]
      ]
    )
  assert view("order_span_lead_summary") ==
    norm_rows([[3, 1, 1, 1, 2, 2400, 2400, 2400, 2000]])
  assert view("order_span_ready_to_door") ==
    norm_rows([["o-1", "done", 3, 31200, 4, 31500, 300, 300, nil, nil]])
  assert view("order_span_ready_to_door_summary") ==
    norm_rows([[1, 1, 0, 0, 0, 300, 300, 300, nil]])
  # Uses no permit covered: item-2's use at 40000 [5] came after its permit's
  # not_after (36750): lapsed. Every other admitted use sat inside a window.
  assert view("consumable_unpermitted_use") ==
    norm_rows([["item-2", 5, 40000, 2, 36750, nil, "lapsed"]])
  rm_rf(dir)
end

test "observed breaches and uses no permit covered: each found, with the reason, and asking for its task"
  dir = test_dir("observed")
  d = example_consumable()
  s = stream(d, path_join(dir, "consumable.jsonl"), "anaritikusu-observed")
  log0 = nisshi::read(get(s, :path), get(s, :label), d)
  # item-a, seq in brackets: [0] reading 10 at 1000, [1] open 1100, [2] a use
  # OBSERVED at 1200 before any permit (the guard holds, so no breach),
  # [3] a permit at 1300, [4] a use at 1400, [5] a reading of 26 at 1500,
  # [6] a use OBSERVED at 1600 (quality_ok refuses: a breach), [7] a use
  # ATTEMPTED at 9000 (refused), [8] a use OBSERVED at 9100 (a breach again).
  l1 = nisshi::append_all(
    log0,
    [
      ["item-a", raifusaikuru::ev(:reading, 1000, [[:value, 10]]), []],
      ["item-a", raifusaikuru::ev(:open, 1100, []), []]
    ]
  )
  l2 = nisshi::observe(l1, "item-a", raifusaikuru::ev(:use, 1200, []), [])
  l3 = el_append(
    l2,
    "item-a",
    raifusaikuru::permit_event(
      d,
      raifusaikuru::permit_for(d, nisshi::state(l2, "item-a"), :use, 1300),
      "dev"
    ),
    []
  )
  l4 = nisshi::append_all(
    l3,
    [
      ["item-a", raifusaikuru::ev(:use, 1400, []), []],
      ["item-a", raifusaikuru::ev(:reading, 1500, [[:value, 26]]), []]
    ]
  )
  l5 = nisshi::observe(l4, "item-a", raifusaikuru::ev(:use, 1600, []), [])
  l6 = el_append(l5, "item-a", raifusaikuru::ev(:use, 9000, []), [])
  nisshi::observe(l6, "item-a", raifusaikuru::ev(:use, 9100, []), [])
  now = 20000
  db = build(dir, [s], now)
  ms = models(bindings(dir, [s]), now)
  view = fn(name) norm_rows(read(db, la_find(ms, name))) end
  # By hand. The permit at 1300: not_after = min(1000 + 14400, 1100 + 259200,
  # 1300 + 7200) = 8500, 39 uses left (one use folded), basis 3. The use at
  # 1200 had no permit before it; the one at 1600 broke the guard inside the
  # window; the one at 9100 came after not_after (and broke the guard too:
  # lapsed is reported first). The use at 1400 was covered. (The breach column
  # is a VARCHAR[], and it reads back as a list.)
  assert view("consumable_unpermitted_use") ==
    norm_rows(
      [
        ["item-a", 2, 1200, nil, nil, nil, "no_permit"],
        ["item-a", 6, 1600, 3, 8500, ["quality_ok"], "breach"],
        ["item-a", 8, 9100, 3, 8500, ["quality_ok"], "lapsed"]
      ]
    )
  # The permit's window counts the uses at 1400 and 1600 (by window alone) and
  # the overrun at 9100.
  assert view("consumable_permit_use_use") ==
    norm_rows(
      [["item-a", 3, "dev", 1300, 8500, 7200, 3, 39, 2, 1, 1600, false]]
    )
  # quality_ok refused one attempt and was breached twice; the three asks are
  # one `replace` task, opened at 1600, never closed (no later reading), open
  # 20000 - 1600 = 18400 s against 1200: overdue.
  assert filter(
    fn(r) nth(1, r) == "quality_ok" end,
    view("consumable_rule_hits")
  ) ==
    norm_rows([["use", "quality_ok", "quality below 24", 1, 2]])
  assert view("consumable_tasks") ==
    norm_rows(
      [["item-a", "replace", "open", 6, 1600, nil, nil, 3, 18400, 1200, true]]
    )
  # The breaches were applied: four uses folded (1200, 1400, 1600, 9100).
  assert view("consumable_current_state") ==
    norm_rows([["item-a", "open", 4, 1100, 26, 1500, 8, 9100]])
  # The control: with the observed uses appended as attempts instead, the
  # guard refuses them, nothing is breached, and only the use before any
  # permit is left uncovered.
  dir2 = test_dir("attempted")
  s2 = stream(d, path_join(dir2, "consumable.jsonl"), "anaritikusu-observed")
  m1 = nisshi::append_all(
    nisshi::read(get(s2, :path), get(s2, :label), d),
    [
      ["item-a", raifusaikuru::ev(:reading, 1000, [[:value, 10]]), []],
      ["item-a", raifusaikuru::ev(:open, 1100, []), []],
      ["item-a", raifusaikuru::ev(:use, 1200, []), []]
    ]
  )
  m2 = el_append(
    m1,
    "item-a",
    raifusaikuru::permit_event(
      d,
      raifusaikuru::permit_for(d, nisshi::state(m1, "item-a"), :use, 1300),
      "dev"
    ),
    []
  )
  nisshi::append_all(
    m2,
    [
      ["item-a", raifusaikuru::ev(:use, 1400, []), []],
      ["item-a", raifusaikuru::ev(:reading, 1500, [[:value, 26]]), []],
      ["item-a", raifusaikuru::ev(:use, 1600, []), []],
      ["item-a", raifusaikuru::ev(:use, 9000, []), []],
      ["item-a", raifusaikuru::ev(:use, 9100, []), []]
    ]
  )
  db2 = build(dir2, [s2], now)
  ms2 = models(bindings(dir2, [s2]), now)
  assert norm_rows(read(db2, la_find(ms2, "consumable_unpermitted_use"))) ==
    norm_rows([["item-a", 2, 1200, nil, nil, nil, "no_permit"]])
  assert filter(
    fn(r) nth(1, r) == "quality_ok" end,
    norm_rows(read(db2, la_find(ms2, "consumable_rule_hits")))
  ) ==
    norm_rows([["use", "quality_ok", "quality below 24", 3, 0]])
  rm_rf(dir)
  rm_rf(dir2)
end

# nisshi's replay and the database agree on every entity's phase and fields.
def example_differential(db, ms, s)
  d = get(s, :def)
  nf = size(raifusaikuru::d_field_names(d))
  fold = map(
    fn(es)
      norm_rows(
        [
          cons(
            first(es),
            cons(
              raifusaikuru::text(raifusaikuru::phase(nth(1, es))),
              map(fn(kv) nth(1, kv) end, raifusaikuru::fields(nth(1, es)))
            )
          )
        ]
      )
    end,
    nisshi::states(nisshi::read(get(s, :path), get(s, :label), d))
  )
  sql = map(
    fn(r) take_n(r, 2 + nf) end,
    norm_rows(read(db, la_find(ms, n(d, "current_state"))))
  )
  if set_equal(map(fn(x) first(x) end, fold), sql) == false
    throw(
      error(
        :anaritikusu_test,
        "#{raifusaikuru::text(raifusaikuru::name(d))}: the database's current state differs from nisshi's replay"
      )
    )
  end
  size(sql)
end

test "a stricter reader: an applied event becomes a breach, and asks for its task"
  dir = test_dir("strict")
  streams = example_streams(dir)
  strict = map(fn(s) example_restrict(s) end, streams)
  db = build(dir, strict, 86400)
  ms = models(bindings(dir, strict), 86400)
  view = fn(name) norm_rows(read(db, la_find(ms, name))) end
  # Read with fewer than 3 uses allowed, item-1's use at 31100 [9] (its 4th)
  # was applied while uses_left refused: one breach. Its task is the guard's
  # `replace`, and nothing after [9] is evidence: open 86400 - 31100 = 55300,
  # overdue. The use at 30100 still reads as refused by the log.
  assert view("consumable_rule_hits") ==
    norm_rows(
      [
        ["use", "is_open", "phase in [:open]", 0, 0],
        ["use", "not_too_old", "opened_at less than 259200 old", 0, 0],
        ["use", "quality_ok", "quality below 24", 1, 0],
        ["use", "reading_fresh", "read_at less than 14400 old", 1, 0],
        ["use", "uses_left", "uses below 3", 0, 1]
      ]
    )
  assert view("consumable_task_summary") ==
    norm_rows([["replace", 2, 1, 1, 1], ["take_reading", 1, 1, 0, 1]])
  # A breach is applied: item-1 still ends with four uses.
  assert first(view("consumable_current_state")) ==
    first(norm_rows([["item-1", "spent", 4, 29000, 12, 31000, 10, 32000]]))
  rm_rf(dir)
end

def example_restrict(s)
  if raifusaikuru::text(raifusaikuru::name(get(s, :def))) == "consumable"
    stream(example_consumable_strict(), get(s, :path), get(s, :label))
  else
    s
  end
end

test "the set is refused where it cannot be generated, and a broken stream is refused where it is built"
  dir = test_dir("refused")
  portion = binding(
    example_portion(),
    path_join(dir, "p.jsonl"),
    path_join(dir, "p.h")
  )
  consumable = binding(
    example_consumable(),
    path_join(dir, "c.jsonl"),
    path_join(dir, "c.h")
  )
  # The empty case: no lifecycles, no models.
  assert is_empty(models([], 0))
  # A link to a lifecycle not given; the same set with it holds.
  assert error?(try(models([portion], 0), catch(e(), e)))
  assert size(models([portion, consumable], 0)) > 0
  # Two lifecycles with one name; a role whose generated name collides with a
  # standard view (a role named `events`); `now` that is not a time.
  assert error?(try(models([consumable, consumable], 0), catch(e(), e)))
  evented = lc_define(
    :portion,
    [
      raifusaikuru::states([:a, :b]),
      raifusaikuru::start(:a),
      raifusaikuru::terminals([:b]),
      raifusaikuru::event(:go, []),
      raifusaikuru::on(:a, :go, :b, []),
      raifusaikuru::link(:events, :consumable)
    ]
  )
  assert error?(
    try(models([binding(evented, "x", "y"), consumable], 0), catch(e(), e))
  )
  assert error?(try(models([consumable], 1.5), catch(e(), e)))
  # A stream with a changed line is not built on.
  streams = example_streams(dir)
  path = get(first(streams), :path)
  write_file(path, replace(read_file(path), "\"time\":29300", "\"time\":29301"))
  assert error?(try(build(dir, streams, 86400), catch(e(), e)))
  rm_rf(dir)
end

test "as of, with two records of the linked entity in one second: the state after the later one"
  dir = test_dir("tie")
  d = example_consumable()
  p = example_portion()
  sc = stream(d, path_join(dir, "consumable.jsonl"), "anaritikusu-tie")
  sp = stream(p, path_join(dir, "portion.jsonl"), "anaritikusu-tie")
  # item-t: [0] reading 10 at 1000, [1] open 1100, [2] and [3] two uses at
  # 1200. p-t is made at 1200 and p-u at 1300, each linking item-t. By hand:
  # both see item-t after [3], two uses, whichever order the database keeps
  # the two 1200 records in.
  nisshi::append_all(
    nisshi::read(get(sc, :path), get(sc, :label), d),
    [
      ["item-t", raifusaikuru::ev(:reading, 1000, [[:value, 10]]), []],
      ["item-t", raifusaikuru::ev(:open, 1100, []), []],
      ["item-t", raifusaikuru::ev(:use, 1200, []), []],
      ["item-t", raifusaikuru::ev(:use, 1200, []), []]
    ]
  )
  nisshi::append_all(
    nisshi::read(get(sp, :path), get(sp, :label), p),
    [
      [
        "p-t",
        raifusaikuru::ev(:make, 1200, [[:grams, 100]]),
        [[:item, "item-t"]]
      ],
      [
        "p-u",
        raifusaikuru::ev(:make, 1300, [[:grams, 90]]),
        [[:item, "item-t"]]
      ]
    ]
  )
  db = build(dir, [sc, sp], 5000)
  ms = models(bindings(dir, [sc, sp]), 5000)
  assert map(
    fn(r) [first(r), nth(6, r), nth(8, r)] end,
    norm_rows(read(db, la_find(ms, "portion_item")))
  ) ==
    norm_rows([["p-t", 3, 2], ["p-u", 3, 2]])
  rm_rf(dir)
end
