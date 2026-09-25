use("retsu")
use("shuugou")
use("deeta")
use("raifusaikuru")
use("nisshi")
use("kueri")
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
def la_n(d, suffix)
  "#{lc_text(lc_name(d))}_#{suffix}"
end

# The record columns an event log writes, as the events view names them.
def la_record_names()
  ["entity", "seq", "time", "type", "status", "refusal_kind", "refusal_detail", "links", "prev", "hash", "sig"]
end

# The columns a state row carries besides the fields, and the ones the steps
# view adds: no field may take one of these names.
def la_state_names()
  ["entity", "seq", "time", "type", "status", "refusal_kind", "refusal_detail", "phase", "phase_before", "breach", "breach_capability", "replay_refusal"]
end

# ── types, derived from the definition ─────────────────────────────────────

# A constant's column type, or nil for nil. A keyword is written as its text.
def la_lit_type(v)
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

def la_numeric?(t)
  (t == :bigint) || (t == :double)
end

# One type from several, nil for none: numbers widen to DOUBLE, and anything
# else must agree.
def la_merge(ts, what)
  known = unique(filter(fn(t) t != nil end, ts))
  if is_empty(known)
    nil
  elsif size(known) == 1
    first(known)
  elsif count_where(fn(t) la_numeric?(t) == false end, known) == 0
    :double
  else
    throw(error(:anaritikusu_schema, "#{what} holds values of types #{join(map(fn(t) to_s(t) end, known), " and ")}; a column has one type"))
  end
end

# Every effect of every row: [:set f k], [:put f v], [:add f n], [:add_key f
# k], [:stamp f].
def la_effects(d)
  flat_map(fn(e) nth(4, e) end, lc_d_edges(d))
end

# Every atomic predicate of every rule of every guard.
def la_atoms(d)
  flat_map(fn(g) flat_map(fn(r) lc_atoms(nth(2, r)) end, nth(2, g)) end, lc_d_guards(d))
end

# The types the definition's constants and clocks give field `f`.
def la_field_evidence(d, f)
  effects = map(fn(x) la_effect_type(x) end, filter(fn(x) nth(1, x) == f end, la_effects(d)))
  atoms = map(fn(a) la_atom_type(a) end, filter(fn(a) (first(a) != :in) && (nth(1, a) == f) end, la_atoms(d)))
  cons(la_lit_type(lookup(lc_d_fields(d), f)), concat_lists(effects, atoms))
end

def la_effect_type(x)
  op = first(x)
  if (op == :put) || (op == :add)
    la_lit_type(nth(2, x))
  elsif op == :stamp
    :bigint
  else
    nil
  end
end

def la_atom_type(a)
  op = first(a)
  if op == :eq
    la_lit_type(nth(2, a))
  elsif op == :age_lt
    :bigint
  else
    nil
  end
end

# Field `f` holds a number: compared, counted, or given a numeric constant.
def la_needs_number?(d, f)
  compared = count_where(fn(a) contains([:lt, :le, :gt, :ge], first(a)) && (nth(1, a) == f) end, la_atoms(d)) > 0
  counted = count_where(fn(x) contains([:add, :add_key], first(x)) && (nth(1, x) == f) end, la_effects(d)) > 0
  compared || counted || la_numeric?(la_merge(la_field_evidence(d, f), "field #{lc_show(f)}"))
end

# The effects that carry payload key `k` (by its text) into a field.
def la_flows_of_key(d, k)
  filter(fn(x) ((first(x) == :set) || (first(x) == :add_key)) && (lc_text(nth(2, x)) == lc_text(k)) end, la_effects(d))
end

# A logged permit's key types by text: subject is text, the limits are whole
# numbers.
def la_permit_key_types(d)
  logged = map(fn(l) nth(1, l) end, lc_d_permit_logs(d))
  keys = flat_map(fn(e) as_list(nth(1, e)) end, filter(fn(e) contains(logged, first(e)) end, lc_d_events(d)))
  map(fn(k) [lc_text(k), la_permit_key_type(k)] end, keys)
end

def la_permit_key_type(k)
  if lc_text(k) == "subject"
    :varchar
  else
    :bigint
  end
end

# A payload key's column type (see "Types, derived").
def la_key_type(d, k)
  fixed = lookup(la_permit_key_types(d), lc_text(k))
  if fixed != nil
    fixed
  else
    flows = la_flows_of_key(d, k)
    targets = unique(map(fn(x) nth(1, x) end, flows))
    numeric = (count_where(fn(x) first(x) == :add_key end, flows) > 0) || (count_where(fn(f) la_needs_number?(d, f) end, targets) > 0)
    if numeric
      :double
    else
      t = la_merge(flat_map(fn(f) la_field_evidence(d, f) end, targets), "payload key #{lc_show(k)}")
      if t == nil
        :varchar
      else
        t
      end
    end
  end
end

# A field's column type (see "Types, derived").
def la_field_type(d, f)
  keys = map(fn(x) la_key_type(d, nth(2, x)) end, filter(fn(x) ((first(x) == :set) || (first(x) == :add_key)) && (nth(1, x) == f) end, la_effects(d)))
  t = la_merge(concat_lists(la_field_evidence(d, f), keys), "field #{lc_show(f)} of #{lc_show(lc_name(d))}")
  if t != nil
    t
  elsif la_needs_number?(d, f)
    :double
  else
    :varchar
  end
end

# Every payload key any event declares, once by its text, first-declared
# first: the event table's columns after the record's.
def la_keys(d)
  unique_by(fn(k) lc_text(k) end, flat_map(fn(e) as_list(nth(1, e)) end, lc_d_events(d)))
end

# [name, type] for every payload key, the name as text.
def la_key_types(d)
  map(fn(k) [lc_text(k), la_key_type(d, k)] end, la_keys(d))
end

# [name, type] for every field, in declaration order, the name as text.
def la_field_types(d)
  map(fn(f) [lc_text(f), la_field_type(d, f)] end, lc_d_field_names(d))
end

# ── the telemetry schema ───────────────────────────────────────────────────

def la_link_type()
  q_struct_of([q_col(:id, :varchar), q_col(:kind, :varchar)])
end

# The event table's columns, as q_col: the record's, then every payload key.
def la_event_columns(d)
  la_check_names(d)
  keys = map(fn(kt) q_col(first(kt), nth(1, kt)) end, la_key_types(d))
  concat_lists(concat_lists([q_col(:entity, :varchar), q_col(:seq, :bigint), q_col(:time, :bigint), q_col(:type, :varchar), q_col(:status, :varchar), q_col(:refusal_kind, :varchar), q_col(:refusal_detail, q_list_of(:varchar)), q_col(:links, q_list_of(la_link_type()))], keys), [q_col(:prev, :varchar), q_col(:hash, :varchar), q_col(:sig, :varchar)])
end

# The state table's columns, as q_col: which record, the phase, every field,
# and what the replay found (a breach, or a refusal of an admitted record).
def la_state_columns(d)
  la_check_names(d)
  fields = map(fn(ft) q_col(first(ft), nth(1, ft)) end, la_field_types(d))
  concat_lists(concat_lists([q_col(:entity, :varchar), q_col(:seq, :bigint), q_col(:phase, :varchar)], fields), [q_col(:breach, q_list_of(:varchar)), q_col(:breach_capability, :varchar), q_col(:replay_refusal, :varchar)])
end

# [column, type] pairs of a q_col list, types as SQL: what a reader checks.
def la_columns_text(cols)
  map(fn(c) [get(c, :name), q_type_sql(get(c, :type), :duckdb)] end, cols)
end

# Refuse a definition whose keys or fields would take a generated column's
# name, or share a text with each other.
def la_check_names(d)
  keys = map(fn(k) lc_text(k) end, la_keys(d))
  fields = map(fn(f) lc_text(f) end, lc_d_field_names(d))
  taken_keys = filter(fn(k) contains(la_record_names(), k) end, keys)
  taken_fields = filter(fn(f) contains(la_state_names(), f) end, fields)
  dupes = unique(filter(fn(f) count_of(fields, f) > 1 end, fields))
  if is_empty(taken_keys) == false
    throw(error(:anaritikusu_schema, "#{lc_show(lc_name(d))}: payload key #{join(taken_keys, ", ")} is a record column's name (#{join(la_record_names(), ", ")}); rename the key"))
  end
  if is_empty(taken_fields) == false
    throw(error(:anaritikusu_schema, "#{lc_show(lc_name(d))}: field #{join(taken_fields, ", ")} is a state column's name (#{join(la_state_names(), ", ")}); rename the field"))
  end
  if is_empty(dupes) == false
    throw(error(:anaritikusu_schema, "#{lc_show(lc_name(d))}: two fields are named #{join(dupes, ", ")} as text"))
  end
  d
end

# ── bindings: a definition, its stream, and where its history is written ──

# One lifecycle to analyse: its definition, the path of its nisshi stream,
# and the path its history (the state after every record) is written to.
def la_binding(d, stream, history)
  lc_name(d)
  {def: d, stream: stream, history: history}
end

def la_def(b)
  get(b, :def)
end

# ── sources: what is loaded ────────────────────────────────────────────────

# The stream as nisshi writes it, every column declared (the payload as a
# struct of the derived key types; no payload column when no event has keys).
def la_records_source(d, path)
  keys = la_key_types(d)
  payload = if is_empty(keys)
    []
  else
    [q_col(:payload, q_struct_of(map(fn(kt) q_col(first(kt), nth(1, kt)) end, keys)))]
  end
  refusal = q_struct_of([q_col(:kind, :varchar), q_col(:detail, q_list_of(:varchar))])
  cols = concat_lists(concat_lists([q_col(:entity, :varchar), q_col(:seq, :bigint), q_col(:time, :bigint), q_col(:type, :varchar), q_col(:status, :varchar), q_col(:refusal, refusal), q_col(:links, q_list_of(la_link_type()))], payload), [q_col(:prev, :varchar), q_col(:hash, :varchar), q_col(:sig, :varchar)])
  q_source({name: la_n(d, "records"), file: path, format: :jsonl, columns: cols})
end

# The history la_write_history writes: the state after each record.
def la_history_source(d, path)
  fields = la_field_types(d)
  struct = if is_empty(fields)
    []
  else
    [q_col(:fields, q_struct_of(map(fn(ft) q_col(first(ft), nth(1, ft)) end, fields)))]
  end
  cols = concat_lists(concat_lists([q_col(:entity, :varchar), q_col(:seq, :bigint), q_col(:phase, :varchar)], struct), [q_col(:breach, q_list_of(:varchar)), q_col(:breach_capability, :varchar), q_col(:replay_refusal, :varchar)])
  q_source({name: la_n(d, "history"), file: path, format: :jsonl, columns: cols})
end

# ── the definition, as rows ────────────────────────────────────────────────

def la_text_or_nil(x)
  if x == nil
    nil
  else
    lc_text(x)
  end
end

# Every row: the phase it leaves, the event, the phase it enters, and the
# capability that gates it (NULL when none).
def la_edges_rel(d)
  rows = map(fn(e) [lc_text(nth(1, e)), lc_text(nth(2, e)), lc_text(nth(3, e)), la_text_or_nil(nth(5, e))] end, lc_d_edges(d))
  q_values({name: la_n(d, "edges"), columns: [q_col(:phase_before, :varchar), q_col(:type, :varchar), q_col(:phase, :varchar), q_col(:capability, :varchar)], rows: rows})
end

# Every rule of every guard: what it needs, in the engine's own words, and
# the task it asks for when it refuses (its own, else its guard's; NULL when
# neither names one).
def la_rules_rel(d)
  rows = flat_map(fn(g) map(fn(r) la_rule_row(g, r) end, nth(2, g)) end, lc_d_guards(d))
  q_values({name: la_n(d, "rules"), columns: [q_col(:capability, :varchar), q_col(:rule, :varchar), q_col(:needs, :varchar), q_col(:task, :varchar), q_col(:escalate_after, :bigint)], rows: rows})
end

def la_rule_row(g, r)
  t = lc_task_or(r, nth(3, g))
  task = if t == nil
    [nil, nil]
  else
    [lc_text(lc_task_name(t)), lc_task_escalate_after(t)]
  end
  concat_lists([lc_text(nth(1, g)), lc_text(nth(1, r)), lc_pred_text(nth(2, r))], task)
end

# Every task any rule may ask for, one row per evidence kind that closes it.
def la_task_evidence_rel(d)
  tasks = flat_map(fn(g) filter(fn(t) t != nil end, cons(nth(3, g), map(fn(r) nth(3, r) end, nth(2, g)))) end, lc_d_guards(d))
  rows = unique(flat_map(fn(t) map(fn(k) [lc_text(lc_task_name(t)), lc_text(k)] end, lc_task_evidence(t)) end, tasks))
  q_values({name: la_n(d, "task_evidence"), columns: [q_col(:task, :varchar), q_col(:evidence, :varchar)], rows: rows})
end

# ── the models of one lifecycle ────────────────────────────────────────────

def la_view(d, suffix, from, pipeline)
  q_model({name: la_n(d, suffix), from: from, pipeline: pipeline, materialize: :view})
end

def la_field_names(d)
  map(fn(ft) first(ft) end, la_field_types(d))
end

# The event table: one row per record, the payload's keys as columns.
def la_events_model(d, records)
  keys = map(fn(kt) q_as(first(kt), q_get(:payload, first(kt))) end, la_key_types(d))
  items = concat_lists(concat_lists([:entity, :seq, :time, :type, :status, q_as(:refusal_kind, q_get(:refusal, :kind)), q_as(:refusal_detail, q_get(:refusal, :detail)), :links], keys), [:prev, :hash, :sig])
  la_view(d, "events", records, [q_select(items)])
end

# The state table: one row per record, the fields as columns.
def la_states_model(d, history)
  fields = map(fn(f) q_as(f, q_get(:fields, f)) end, la_field_names(d))
  items = concat_lists(concat_lists([:entity, :seq, :phase], fields), [:breach, :breach_capability, :replay_refusal])
  la_view(d, "states", history, [q_select(items)])
end

# Records and states joined, with the phase each record found its entity in.
def la_steps_model(d, events, states)
  start = lc_text(lc_phase(lc_initial(d)))
  la_view(d, "steps", events, [q_select([:entity, :seq, :time, :type, :status, :refusal_kind, :refusal_detail]), q_join(states, [:entity, :seq]), q_derive(:phase_before, q_coalesce(q_lag(:phase, [:entity], [:seq]), start))])
end

# Records the history has no state for: 0 when it was written from this
# stream.
def la_unreplayed_model(d, events, states)
  la_view(d, "unreplayed", events, [q_select([:entity, :seq]), q_left_join(states, [:entity, :seq]), q_filter(q_is_null(:phase)), q_group([], [q_agg(:records, q_count_all())])])
end

# One row per entity: its phase and fields after its last record.
def la_current_state_model(d, steps)
  items = concat_lists(concat_lists([:entity, :phase], la_field_names(d)), [q_as(:last_seq, :seq), q_as(:last_time, :time)])
  la_view(d, "current_state", steps, [q_derive(:la_newest, q_row_number([:entity], [q_desc(:seq)])), q_filter(q_eq(:la_newest, 1)), q_select(items)])
end

# Each record's phase held from its time until the entity's next record, or
# until `now` for the last.
def la_intervals_model(d, steps, now)
  la_view(d, "state_intervals", steps, [q_derive(:until, q_lead(:time, [:entity], [:seq])), q_derive(:seconds, q_sub(q_coalesce(:until, now), :time)), q_select([:entity, :seq, :phase, q_as(:since, :time), :until, :seconds])])
end

# Seconds per entity in each phase it has been in; ongoing is 1 for the
# phase it is in now.
def la_time_in_state_model(d, intervals)
  la_view(d, "time_in_state", intervals, [q_group([:entity, :phase], [q_agg(:seconds, q_sum(:seconds)), q_agg_where(:ongoing, q_count_all(), q_is_null(:until))])])
end

# Refused records by event type and refusal kind.
def la_refusals_model(d, events)
  la_view(d, "refusals", events, [q_filter(q_eq(:status, "refused")), q_group([:type, :refusal_kind], [q_agg(:records, q_count_all())])])
end

# The gated rows: which capability an event in a phase uses.
def la_gates_model(d, edges)
  la_view(d, "gates", edges, [q_filter(q_not_null(:capability)), q_select([:phase_before, :type, :capability])])
end

# One row per rule a guard applied against a record: refused (the log
# refused the event) or breach (the replay applied it while the guard
# refused, which happens when the definition read is stricter than the one
# that wrote).
def la_guard_hits_model(d, steps, gates)
  la_view(d, "guard_hits", steps, [
    q_select([:entity, :seq, :time, :type, :phase_before, :refusal_kind, :refusal_detail, :breach, :breach_capability]),
    q_left_join(gates, [:phase_before, :type]),
    q_filter(q_or(q_eq(:refusal_kind, "guard"), q_not_null(:breach))),
    q_derive(:la_capability, q_coalesce(:breach_capability, :capability)),
    q_derive(:la_rules, q_coalesce(:breach, :refusal_detail)),
    q_derive(:outcome, q_if(q_not_null(:breach), "breach", "refused")),
    q_explode(:rule, :la_rules),
    q_select([:entity, :seq, :time, :type, q_as(:capability, :la_capability), :rule, :outcome])])
end

def la_rule_hit_counts_model(d, hits)
  la_view(d, "rule_hit_counts", hits, [q_group([:capability, :rule], [q_agg_where(:refused, q_count_all(), q_eq(:outcome, "refused")), q_agg_where(:breached, q_count_all(), q_eq(:outcome, "breach"))])])
end

# Every declared rule, with how often it refused and was breached (0 when
# never: a rule that never fired is information too).
def la_rule_hits_model(d, rules, counts)
  la_view(d, "rule_hits", rules, [q_select([:capability, :rule, :needs]), q_left_join(counts, [:capability, :rule]), q_select([:capability, :rule, :needs, q_as(:refused, q_coalesce(:refused, 0)), q_as(:breached, q_coalesce(:breached, 0))])])
end

def la_rule_tasks_model(d, rules)
  la_view(d, "rule_tasks", rules, [q_filter(q_not_null(:task)), q_select([:capability, :rule, :task, :escalate_after])])
end

# Each record's asks: one row per task a refusal or breach asked for.
def la_task_asks_model(d, hits, rule_tasks)
  la_view(d, "task_asks", hits, [q_join(rule_tasks, [:capability, :rule]), q_group([:entity, :seq, :time, :task, :escalate_after], [q_agg(:asked_by, q_count_all())])])
end

# Admitted events that are evidence for a task.
def la_task_evidence_events_model(d, steps, evidence)
  la_view(d, "task_evidence_events", steps, [q_filter(q_and(q_eq(:status, "admitted"), q_is_null(:replay_refusal))), q_select([:entity, q_as(:evidence_seq, :seq), q_as(:evidence_time, :time), q_as(:evidence, :type)]), q_join(evidence, [:evidence]), q_select([:entity, :task, :evidence_seq, :evidence_time])])
end

# Each ask with the first later evidence of its task on its entity.
def la_task_closes_model(d, asks, evidence_events)
  later = q_gt(:evidence_seq, :seq)
  la_view(d, "task_closes", asks, [q_left_join(evidence_events, [:entity, :task]), q_group([:entity, :seq, :time, :task, :escalate_after], [q_agg_where(:closed_seq, q_min(:evidence_seq), later), q_agg_where(:closed_at, q_min(:evidence_time), later)])])
end

# One row per task: the asks one evidence closes are one task, opened at the
# first; still open (no evidence yet) until `now`; overdue when it stayed
# open longer than its escalate_after.
def la_tasks_model(d, closes, now)
  la_view(d, "tasks", closes, [
    q_group([:entity, :task, :closed_seq], [q_agg(:opened_seq, q_min(:seq)), q_agg(:opened_at, q_min(:time)), q_agg(:asks, q_count_all()), q_agg(:closed_at, q_max(:closed_at)), q_agg(:escalate_after, q_max(:escalate_after))]),
    q_derive(:open_for, q_sub(q_coalesce(:closed_at, now), :opened_at)),
    q_derive(:overdue, q_gt(:open_for, :escalate_after)),
    q_derive(:state, q_if(q_is_null(:closed_seq), "open", "closed")),
    q_select([:entity, :task, :state, :opened_seq, :opened_at, :closed_seq, :closed_at, :asks, :open_for, :escalate_after, :overdue])])
end

def la_task_summary_model(d, tasks)
  la_view(d, "task_summary", tasks, [q_group([:task], [q_agg(:opened, q_count_all()), q_agg_where(:still_open, q_count_all(), q_eq(:state, "open")), q_agg_where(:closed, q_count_all(), q_eq(:state, "closed")), q_agg_where(:overdue, q_count_all(), :overdue)])])
end

# The counted fields of a capability's permit, as their log keys.
def la_count_keys(d, capability)
  pm = find_first(fn(p) nth(1, p) == capability end, lc_d_permits(d))
  map(fn(t) lc_permit_count_key(nth(1, t)) end, filter(fn(t) first(t) == :counted end, as_list(nth(2, pm))))
end

# The permit models of one logged capability: issued, used, and the two
# joined.
def la_permit_models(d, log, events, steps, gates)
  cap = first(log)
  c = lc_text(cap)
  counts = la_count_keys(d, cap)
  permits = la_view(d, "permits_#{c}", events, [q_filter(q_and(q_eq(:type, lc_text(nth(1, log))), q_eq(:status, "admitted"))), q_derive(:next_seq, q_lead(:seq, [:entity], [:seq])), q_select(concat_lists(concat_lists([:entity, q_as(:permit_seq, :seq), q_as(:issued_at, :time), :subject, :not_after, :basis], counts), [:next_seq]))])
  uses = la_view(d, "uses_#{c}", steps, [q_filter(q_and(q_eq(:status, "admitted"), q_is_null(:replay_refusal))), q_select([:entity, :seq, :time, :type, :phase_before]), q_join(gates, [:phase_before, :type]), q_filter(q_eq(:capability, c)), q_select([:entity, q_as(:use_seq, :seq), q_as(:use_time, :time)])])
  within = q_and(q_gt(:use_seq, :permit_seq), q_or(q_is_null(:next_seq), q_lt(:use_seq, :next_seq)))
  exceeded = map(fn(k) q_derive("#{k}_exceeded", q_gt(:uses, q_c(k))) end, counts)
  keys = concat_lists(concat_lists([:entity, :permit_seq, :issued_at, :not_after, :subject, :basis], counts), [:next_seq])
  out = concat_lists(concat_lists([:entity, :permit_seq, :subject, :issued_at, :not_after, :window_seconds, :basis], counts), concat_lists([:uses, :overrun, :last_use_at], map(fn(k) "#{k}_exceeded" end, counts)))
  used = la_view(d, "permit_use_#{c}", permits, concat_lists([q_left_join(uses, [:entity]), q_group(keys, [q_agg_where(:uses, q_count_all(), q_and(within, q_lt(:use_time, :not_after))), q_agg_where(:overrun, q_count_all(), q_and(within, q_ge(:use_time, :not_after))), q_agg_where(:last_use_at, q_max(:use_time), q_and(within, q_lt(:use_time, :not_after)))]), q_derive(:window_seconds, q_sub(:not_after, :issued_at))], push(exceeded, q_select(out))))
  concat_lists([permits, uses, used], la_unpermitted_models(d, log, events, steps, gates))
end

# Every use of a logged capability that no permit covered, and why: the
# permit in force at a use is the entity's latest permit before it (an as-of
# join on seq); there is none (`no_permit`: a use before any was issued), its
# not_after had passed (`lapsed`), or the use broke the guard (`breach`: a
# permit derived from a guard cannot cover a use that guard refused, which is
# a permit revoked by a later reading). permit_use counts a use by its window
# only; this is where a use outside every window, and a breach inside one, are
# seen. The first reason that applies, in that order.
def la_unpermitted_models(d, log, events, steps, gates)
  c = lc_text(first(log))
  granted = la_view(d, "granted_#{c}", events, [q_filter(q_and(q_eq(:type, lc_text(nth(1, log))), q_eq(:status, "admitted"))), q_select([:entity, :seq, q_as(:permit_seq, :seq), :not_after])])
  reason = q_if(q_is_null(:permit_seq), "no_permit", q_if(q_ge(:time, :not_after), "lapsed", q_if(q_not_null(:breach), "breach", q_null())))
  unpermitted = la_view(d, "unpermitted_#{c}", steps, [
    q_filter(q_and(q_eq(:status, "admitted"), q_is_null(:replay_refusal))),
    q_select([:entity, :seq, :time, :type, :phase_before, :breach]),
    q_join(gates, [:phase_before, :type]),
    q_filter(q_eq(:capability, c)),
    q_select([:entity, :seq, :time, :breach]),
    q_asof_left_join(granted, [:entity, :seq]),
    q_derive(:reason, reason),
    q_filter(q_not_null(:reason)),
    q_select([:entity, q_as(:use_seq, :seq), q_as(:use_time, :time), :permit_seq, :not_after, :breach, :reason])])
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
def la_span_models(d, sp, steps, current, now)
  s = lc_text(lc_span_name(sp))
  limit = lc_span_limit(sp)
  first_row = [q_derive(:la_first, q_row_number([:entity], [:seq])), q_filter(q_eq(:la_first, 1))]
  starts = la_view(d, "span_#{s}_from", steps, flatten1([[q_filter(q_eq(:phase, lc_text(lc_span_from(sp))))], first_row, [q_select([:entity, q_as(:from_seq, :seq), q_as(:from_at, :time)])]]))
  ends = la_view(d, "span_#{s}_to", steps, flatten1([[q_filter(q_eq(:phase, lc_text(lc_span_to(sp)))), q_join(starts, [:entity]), q_filter(q_gt(:seq, :from_seq))], first_row, [q_select([:entity, q_as(:to_seq, :seq), q_as(:to_at, :time)])]]))
  # After the join with the current state, :phase is the entity's phase now.
  ended = reduce(fn(acc, t) q_or(acc, q_eq(:phase, lc_text(t))) end, q_lit(false), lc_d_terminals(d))
  state = q_if(q_not_null(:to_seq), "done", q_if(ended, "abandoned", "open"))
  over = if limit == nil
    q_cast(q_null(), :boolean)
  else
    q_gt(:elapsed, limit)
  end
  span = la_view(d, "span_#{s}", starts, [
    q_left_join(ends, [:entity]),
    q_join(current, [:entity]),
    q_derive(:state, state),
    q_derive(:seconds, q_sub(:to_at, :from_at)),
    q_derive(:elapsed, q_if(q_eq(:state, "abandoned"), q_cast(q_null(), :bigint), q_sub(q_coalesce(:to_at, now), :from_at))),
    q_derive(:limit_seconds, q_cast(q_lit(limit), :bigint)),
    q_derive(:over_limit, over),
    q_select([:entity, :state, :from_seq, :from_at, :to_seq, :to_at, :seconds, :elapsed, :limit_seconds, :over_limit])])
  summary = la_view(d, "span_#{s}_summary", span, [q_group([], [
    q_agg(:started, q_count_all()),
    q_agg_where(:reached, q_count_all(), q_eq(:state, "done")),
    q_agg_where(:still_open, q_count_all(), q_eq(:state, "open")),
    q_agg_where(:abandoned, q_count_all(), q_eq(:state, "abandoned")),
    q_agg_where(:over_limit, q_count_all(), :over_limit),
    q_agg(:min_seconds, q_min(:seconds)),
    q_agg(:avg_seconds, q_avg(:seconds)),
    q_agg(:max_seconds, q_max(:seconds)),
    q_agg(:limit_seconds, q_max(:limit_seconds))])])
  [starts, ends, span, summary]
end

# Every model of one lifecycle, upstream first.
def la_lifecycle_models(b, now)
  d = la_def(b)
  la_check_names(d)
  records = la_records_source(d, get(b, :stream))
  history = la_history_source(d, get(b, :history))
  edges = la_edges_rel(d)
  rules = la_rules_rel(d)
  evidence = la_task_evidence_rel(d)
  events = la_events_model(d, records)
  states = la_states_model(d, history)
  steps = la_steps_model(d, events, states)
  intervals = la_intervals_model(d, steps, now)
  gates = la_gates_model(d, edges)
  hits = la_guard_hits_model(d, steps, gates)
  counts = la_rule_hit_counts_model(d, hits)
  rule_tasks = la_rule_tasks_model(d, rules)
  asks = la_task_asks_model(d, hits, rule_tasks)
  evidence_events = la_task_evidence_events_model(d, steps, evidence)
  closes = la_task_closes_model(d, asks, evidence_events)
  tasks = la_tasks_model(d, closes, now)
  permits = flat_map(fn(l) la_permit_models(d, l, events, steps, gates) end, lc_d_permit_logs(d))
  current = la_current_state_model(d, steps)
  spans = flat_map(fn(sp) la_span_models(d, sp, steps, current, now) end, lc_d_spans(d))
  flatten1([[events, states, steps, la_unreplayed_model(d, events, states), current, intervals, la_time_in_state_model(d, intervals), la_refusals_model(d, events), gates, hits, counts, la_rule_hits_model(d, rules, counts), rule_tasks, asks, evidence_events, closes, tasks, la_task_summary_model(d, tasks)], permits, spans])
end

# ── links: joins generated from the declarations ───────────────────────────

# The binding whose lifecycle is named `target`, or a refusal naming the link.
def la_target(bindings, a, role, target)
  hit = find_first(fn(b) lc_text(lc_name(la_def(b))) == lc_text(target) end, bindings)
  if hit == nil
    throw(error(:anaritikusu_schema, "#{lc_show(lc_name(la_def(a)))} links #{lc_show(role)} to lifecycle #{lc_show(target)}, which is not among the lifecycles given (#{join(map(fn(b) lc_text(lc_name(la_def(b))) end, bindings), ", ")})"))
  end
  hit
end

# A model of this set, by name.
def la_find(models, name)
  hit = find_first(fn(m) get(m, :name) == name end, models)
  if hit == nil
    throw(error(:anaritikusu_schema, "no generated relation is named #{name}"))
  end
  hit
end

# A's records carrying a link of kind `role`: one row per link, the linked
# id in the column named for the role.
def la_link_rows_model(ad, role, a_events)
  r = lc_text(role)
  la_view(ad, "#{r}_links", a_events, [q_select([:entity, :seq, :time, :type, :status, :links]), q_explode(:la_link, :links), q_filter(q_eq(q_get(:la_link, :kind), r)), q_select([:entity, :seq, :time, :type, :status, q_as(r, q_get(:la_link, :id))])])
end

# B's states keyed for an asof join on the role: the id in the role's column,
# the state's columns prefixed with it. One row per entity per second: the
# state after its LAST record in that second, because an asof join matches on
# time alone, and with two records in one second (a permit and the load it
# covers) it would take either. Measured 2026-09-25: NuPastel's bench day had
# 9 orders joined to the state before their own load.
def la_link_state_model(ad, role, bd, b_steps)
  r = lc_text(role)
  fields = map(fn(f) q_as("#{r}_#{f}", q_c(f)) end, la_field_names(bd))
  la_view(ad, "#{r}_state", b_steps, [q_derive(:la_last, q_row_number([:entity, :time], [q_desc(:seq)])), q_filter(q_eq(:la_last, 1)), q_select(concat_lists([q_as(r, :entity), :time, q_as("#{r}_seq", :seq), q_as("#{r}_phase", :phase)], fields))])
end

# The columns a one-hop link view returns, after A's own.
def la_link_state_names(role, bd)
  r = lc_text(role)
  concat_lists(["#{r}_seq", "#{r}_phase"], map(fn(f) "#{r}_#{f}" end, la_field_names(bd)))
end

# Each link with the linked entity's state as of the record's time.
def la_link_model(ad, role, bd, rows, state)
  r = lc_text(role)
  la_view(ad, r, rows, [q_asof_left_join(state, [r, :time]), q_select(concat_lists([:entity, :seq, :time, :type, :status, r], la_link_state_names(role, bd)))])
end

def la_link_coverage_model(ad, role, link)
  r = lc_text(role)
  la_view(ad, "#{r}_coverage", link, [q_group([], [q_agg(:links, q_count_all()), q_agg_where(:unresolved, q_count_all(), q_is_null(q_c("#{r}_seq")))])])
end

# The four models of one declared link of A.
def la_link_models(bindings, models, a, link)
  ad = la_def(a)
  role = first(link)
  b = la_target(bindings, a, role, nth(1, link))
  bd = la_def(b)
  rows = la_link_rows_model(ad, role, la_find(models, la_n(ad, "events")))
  state = la_link_state_model(ad, role, bd, la_find(models, la_n(bd, "steps")))
  joined = la_link_model(ad, role, bd, rows, state)
  [rows, state, joined, la_link_coverage_model(ad, role, joined)]
end

# A chain A –r1→ B –r2→ C: each A link with B's latest r2 link at or before
# the A record's time, and C's state as of that B record.
def la_chain_models(bindings, models, a, l1, l2)
  ad = la_def(a)
  bd = la_def(la_target(bindings, a, first(l1), nth(1, l1)))
  cd = la_def(la_target(bindings, la_target(bindings, a, first(l1), nth(1, l1)), first(l2), nth(1, l2)))
  r1 = lc_text(first(l1))
  r2 = lc_text(first(l2))
  b_link = la_find(models, la_n(bd, r2))
  c_cols = concat_lists([r2], la_link_state_names(first(l2), cd))
  via = la_view(ad, "#{r1}_#{r2}_via", b_link, [q_select(concat_lists([q_as(r1, :entity), :time, q_as("#{r1}_time", :time), q_as("#{r1}_event_seq", :seq), q_as("#{r1}_type", :type)], c_cols))])
  chain = la_view(ad, "#{r1}_#{r2}", la_find(models, la_n(ad, "#{r1}_links")), [q_asof_left_join(via, [r1, :time]), q_select(concat_lists([:entity, :seq, :time, :type, :status, r1, "#{r1}_event_seq", "#{r1}_time", "#{r1}_type"], c_cols))])
  [via, chain]
end

# ── the whole set ──────────────────────────────────────────────────────────

# Every model for these lifecycles, upstream first: each lifecycle's, then a
# join per declared link, then a chain per pair of links end to start.
# Refuses (:anaritikusu_schema) two lifecycles with one name, a link to a
# lifecycle not given, and any two generated relations with one name.
def la_models(bindings, now)
  bs = as_list(bindings)
  names = map(fn(b) lc_text(lc_name(la_def(b))) end, bs)
  dup = unique(filter(fn(n) count_of(names, n) > 1 end, names))
  if is_empty(dup) == false
    throw(error(:anaritikusu_schema, "two lifecycles are named #{join(dup, ", ")}"))
  end
  if integer?(now) == false
    throw(error(:anaritikusu_schema, "now is a whole-number time on the lifecycles' clock, not #{lc_show(now)}"))
  end
  own = flat_map(fn(b) la_lifecycle_models(b, now) end, bs)
  links = flat_map(fn(b) flat_map(fn(l) la_link_models(bs, own, b, l) end, lc_d_links(la_def(b))) end, bs)
  both = concat_lists(own, links)
  chains = flat_map(fn(b) flat_map(fn(l1) la_chains_from(bs, both, b, l1) end, lc_d_links(la_def(b))) end, bs)
  all = concat_lists(both, chains)
  la_check_unique(all, flat_map(fn(b) la_source_names(la_def(b)) end, bs))
  all
end

# The relations a lifecycle loads rather than derives.
def la_source_names(d)
  map(fn(x) la_n(d, x) end, ["records", "history", "edges", "rules", "task_evidence"])
end

def la_chains_from(bindings, models, a, l1)
  bd = la_def(la_target(bindings, a, first(l1), nth(1, l1)))
  flat_map(fn(l2) la_chain_models(bindings, models, a, l1, l2) end, lc_d_links(bd))
end

# Every generated relation (the models and the loaded sources) by name: two
# with one name would collapse into one in the database, since kueri
# identifies a node by its name.
def la_check_unique(models, sources)
  names = concat_lists(map(fn(m) get(m, :name) end, models), sources)
  dup = unique(filter(fn(n) count_of(names, n) > 1 end, names))
  if is_empty(dup) == false
    throw(error(:anaritikusu_schema, "two generated relations are named #{join(dup, ", ")}; rename a lifecycle, role or field"))
  end
  models
end

# The script that builds the database: every load, then every view.
def la_script(bindings, now)
  q_render_script(la_models(bindings, now), :duckdb, "anaritikusu")
end

# ── the history: the state after every record ──────────────────────────────

# A value as JSON data: a keyword becomes its text, everywhere inside.
def la_json_value(v)
  if v == nil
    nil
  elsif keyword?(v)
    lc_text(v)
  elsif list?(v)
    map(fn(x) la_json_value(x) end, v)
  else
    v
  end
end

# One history line: the record, the state after it, and what the replay
# found on it — a breach (the guard refused an event it applied) or a
# refusal of an admitted record. Canonical JSON, keys in code-point order.
def la_history_line(r, s)
  pos = lc_seq(s) - 1
  folded = el_rec_admitted?(r)
  b = last(lc_breaches(s))
  rf = last(lc_refused(s))
  breach = if folded && (b != nil) && (lc_breach_position(b) == pos)
    b
  else
    nil
  end
  refusal = if folded && (rf != nil) && (lc_refusal_position(rf) == pos)
    lc_text(lc_refusal_kind(rf))
  else
    nil
  end
  rules = if breach == nil
    nil
  else
    map(fn(x) lc_text(x) end, lc_breach_rules(breach))
  end
  capability = if breach == nil
    nil
  else
    lc_text(lc_breach_capability(breach))
  end
  fields = if is_empty(lc_fields(s))
    ""
  else
    ",\"fields\":#{el_canon_object(map(fn(kv) [lc_text(first(kv)), la_json_value(nth(1, kv))] end, lc_fields(s)))}"
  end
  # The keys are fixed, so they are written in code-point order here rather
  # than sorted per line (the benchmark's hot path; el_canon_object still
  # orders the fields, whose names are the definition's).
  "{\"breach\":#{el_canon(rules)},\"breach_capability\":#{el_canon(capability)},\"entity\":#{json_stringify(el_rec_entity(r))}#{fields},\"phase\":#{json_stringify(lc_text(lc_phase(s)))},\"replay_refusal\":#{el_canon(refusal)},\"seq\":#{to_s(el_rec_seq(r))}}"
end

# The history of a log value that was read: one line per record. Pure.
def la_history_text(log)
  el_unlines(map(fn(x) la_history_line(first(x), nth(1, x)) end, el_history(log)))
end

# Write a log's history to `path`; returns the path.
def la_write_history(log, path)
  write_file(path, la_history_text(log))
  path
end

# ── building and reading the database ──────────────────────────────────────

# A stream to analyse: its definition, its path and its label (the genesis
# nisshi hashes it under).
def la_stream(d, path, label)
  lc_name(d)
  {def: d, path: path, label: label}
end

# The bindings la_build uses: each stream's history under `dir`.
def la_bindings(dir, streams)
  map(fn(s) la_binding(get(s, :def), get(s, :path), path_join(dir, "#{lc_text(lc_name(get(s, :def)))}.history.jsonl")) end, as_list(streams))
end

# Build the database under `dir`: read and verify every stream (a broken
# chain throws :anaritikusu_broken), write each history, write the script
# (lifecycles.sql, for a reader or a nix build), and run it into a fresh
# lifecycles.duckdb. Returns the database's path.
def la_build(dir, streams, now)
  bindings = la_bindings(dir, streams)
  script = la_script(bindings, now)
  map(fn(s) la_build_history(dir, s) end, as_list(streams))
  write_file(path_join(dir, "lifecycles.sql"), script)
  db = path_join(dir, "lifecycles.duckdb")
  if path_exists(db)
    rm(db)
  end
  q_run_at(db, script)
  db
end

def la_build_history(dir, s)
  d = get(s, :def)
  log = el_read(get(s, :path), get(s, :label), d)
  rep = el_verify(log, nil, nil)
  if el_intact?(rep) == false
    throw(error(:anaritikusu_broken, "#{get(s, :path)}: position #{to_s(el_break_position(rep))}, #{to_s(el_break_kind(rep))}: #{el_break_why(rep)}"))
  end
  la_write_history(log, path_join(dir, "#{lc_text(lc_name(d))}.history.jsonl"))
end

# A model's rows from the database at `db`, as value lists in its column
# order, sorted by every column; a failed query throws (:kueri_query). A
# generated view is read from the database; any other model over them (a
# question of its own) runs its query there.
def la_read(db, model)
  cols = q_output(model)
  query = if get(model, :materialize) == :view
    q_model({name: "la_read", from: model, pipeline: [q_sort(cols)]})
  else
    q_then(model, [q_sort(cols)])
  end
  map(fn(row) map(fn(c) as_json(row, c) end, cols) end, q_rows_at(db, q_render(query, :duckdb)))
end

# ── worked examples: three lifecycles and a day ────────────────────────────

# raifusaikuru's example consumable, with its permits logged as `permit`.
def la_example_consumable()
  lc_define(:consumable, push(lc_example_consumable_clauses(), lc_permit_log(:use, :permit)))
end

# The same consumable read by a stricter definition: fewer than 3 uses. Built
# from the example's clauses with the one rule replaced, as data.
def la_example_consumable_strict()
  clauses = map(fn(c) la_example_tighten(c) end, push(lc_example_consumable_clauses(), lc_permit_log(:use, :permit)))
  lc_define(:consumable, clauses)
end

def la_example_tighten(c)
  if list?(c) && (is_empty(c) == false) && (first(c) == :lc_guard)
    [:lc_guard, nth(1, c), map(fn(r) la_example_tighten_rule(r) end, nth(2, c)), nth(3, c)]
  else
    c
  end
end

def la_example_tighten_rule(r)
  if nth(1, r) == :uses_left
    lc_rule(:uses_left, lc_below(:uses, 3))
  else
    r
  end
end

# A portion made with a consumable: its make event links the item.
def la_example_portion()
  lc_define(:portion, [lc_states([:new, :made, :served, :wasted]), lc_start(:new), lc_terminals([:served, :wasted]), lc_field(:grams, 0), lc_field(:made_at, nil), lc_field(:served_at, nil), lc_event(:make, [:grams]), lc_event(:serve, []), lc_event(:waste, []), lc_on(:new, :make, :made, [lc_set(:grams, :grams), lc_stamp(:made_at)]), lc_on(:made, :serve, :served, [lc_stamp(:served_at)]), lc_on(:made, :waste, :wasted, []), lc_link(:item, :consumable)])
end

# An order of portions: each add_portion links one.
def la_example_order()
  lc_define(:order, [lc_states([:new, :placed, :ready, :delivered, :cancelled]), lc_start(:new), lc_terminals([:delivered, :cancelled]), lc_field(:portions, 0), lc_field(:placed_at, nil), lc_field(:delivered_at, nil), lc_event(:place, []), lc_event(:add_portion, []), lc_event(:ready, []), lc_event(:deliver, []), lc_event(:cancel, []), lc_on(:new, :place, :placed, [lc_stamp(:placed_at)]), lc_on(:placed, :add_portion, :stay, [lc_add(:portions, 1)]), lc_on(:placed, :ready, :ready, []), lc_on(:ready, :deliver, :delivered, [lc_stamp(:delivered_at)]), lc_on_each([:placed, :ready], :cancel, :cancelled, []), lc_link(:portion, :portion), lc_span(:lead, :placed, :delivered, 2000), lc_span(:ready_to_door, :ready, :delivered, nil)])
end

# A simulated day, in time order: [lifecycle, entity, event, links]. An event
# [:la_permit, time, subject] is a permit the engine issues at that moment
# (lc_permit_for on the entity's state) and logs (lc_permit_event).
def la_example_day()
  [[:consumable, "item-1", lc_ev(:reading, 28800, [[:value, 10]]), []],
   [:consumable, "item-2", lc_ev(:reading, 28900, [[:value, 10]]), []],
   [:consumable, "item-1", lc_ev(:open, 29000, []), []],
   [:consumable, "item-1", [:la_permit, 29100, "device-1"], []],
   [:order, "o-1", lc_ev(:place, 29100, []), []],
   [:consumable, "item-1", lc_ev(:use, 29200, []), []],
   [:portion, "p-1", lc_ev(:make, 29250, [[:grams, 120]]), [[:item, "item-1"], [:lot, "L-7"]]],
   [:consumable, "item-1", lc_ev(:use, 29300, []), []],
   [:consumable, "item-1", lc_ev(:use, 29400, []), []],
   [:portion, "p-1", lc_ev(:serve, 29400, []), []],
   [:order, "o-1", lc_ev(:add_portion, 29450, []), [[:portion, "p-1"]]],
   [:consumable, "item-2", lc_ev(:open, 29500, []), []],
   [:consumable, "item-2", [:la_permit, 29550, "device-2"], []],
   [:consumable, "item-2", lc_ev(:use, 29600, []), []],
   [:portion, "p-3", lc_ev(:make, 29650, [[:grams, 130]]), [[:item, "item-2"]]],
   [:consumable, "item-2", lc_ev(:open, 29700, []), []],
   [:consumable, "item-1", lc_ev(:reading, 30000, [[:value, 26]]), []],
   [:consumable, "item-3", lc_ev(:discard, 30000, []), []],
   [:order, "o-2", lc_ev(:place, 30000, []), []],
   [:portion, "p-2", lc_ev(:make, 30050, [[:grams, 110]]), [[:item, "item-1"]]],
   [:consumable, "item-1", lc_ev(:use, 30100, []), []],
   [:consumable, "item-3", lc_ev(:polish, 30100, []), []],
   [:order, "o-2", lc_ev(:add_portion, 30100, []), [[:portion, "p-2"]]],
   [:portion, "p-2", lc_ev(:waste, 30500, []), []],
   [:order, "o-2", lc_ev(:cancel, 30600, []), []],
   [:consumable, "item-1", lc_ev(:reading, 31000, [[:value, 12]]), []],
   [:portion, "p-3", lc_ev(:serve, 31000, []), []],
   [:order, "o-1", lc_ev(:add_portion, 31050, []), [[:portion, "p-3"]]],
   [:consumable, "item-1", lc_ev(:use, 31100, []), []],
   [:order, "o-1", lc_ev(:ready, 31200, []), []],
   [:order, "o-1", lc_ev(:deliver, 31500, []), []],
   [:consumable, "item-1", lc_ev(:finish, 32000, []), []],
   [:portion, "p-4", lc_ev(:make, 33000, [[:grams, 100]]), [[:item, "item-9"]]],
   [:order, "o-3", lc_ev(:place, 33100, []), []],
   [:portion, "p-4", lc_ev(:serve, 33500, []), []],
   [:order, "o-3", lc_ev(:add_portion, 33600, []), [[:portion, "p-4"]]],
   [:order, "o-3", lc_ev(:deliver, 33700, []), []],
   [:consumable, "item-2", lc_ev(:use, 40000, []), []],
   [:consumable, "item-2", lc_ev(:use, 44000, []), []]]
end

# The day's three streams under `dir`: [la_stream …], after appending every
# event to its lifecycle's stream through nisshi.
def la_example_streams(dir)
  defs = [la_example_consumable(), la_example_portion(), la_example_order()]
  streams = map(fn(d) la_stream(d, path_join(dir, "#{lc_text(lc_name(d))}.jsonl"), "anaritikusu-example/#{lc_text(lc_name(d))}") end, defs)
  logs = reduce(fn(m, s) assoc(m, lc_text(lc_name(get(s, :def))), el_read(get(s, :path), get(s, :label), get(s, :def))) end, {}, streams)
  reduce(fn(m, x) la_example_append(m, x) end, logs, la_example_day())
  streams
end

def la_example_append(logs, x)
  kind = lc_text(first(x))
  log = get(logs, kind)
  ev = la_example_event(log, nth(1, x), nth(2, x))
  assoc(logs, kind, el_append(log, nth(1, x), ev, nth(3, x)))
end

def la_example_event(log, entity, ev)
  if first(ev) == :la_permit
    d = el_def(log)
    lc_permit_event(d, lc_permit_for(d, el_state(log, entity), :use, nth(1, ev)), nth(2, ev))
  else
    ev
  end
end

# A fresh directory under TMPDIR for a test.
def la_test_dir(name)
  dir = path_join(getenv("TMPDIR", "/tmp"), "anaritikusu-#{name}-#{to_s(now_ns())}")
  mkdir_p(dir)
  dir
end

# A value as the tests compare it: numbers as floats (DuckDB answers 12.0
# where the fold holds 12).
def la_norm(v)
  if number?(v)
    to_float(v)
  else
    v
  end
end

def la_norm_rows(rows)
  map(fn(r) map(fn(v) la_norm(v) end, r) end, rows)
end

# ── tests ──────────────────────────────────────────────────────────────────

test "the telemetry schema is derived from the definition: the record's columns, then the typed keys and fields"
  d = la_example_consumable()
  # By hand: value flows into quality, which lc_below compares, so both are
  # DOUBLE; uses counts from 0 by 1 (BIGINT); opened_at and read_at are
  # stamped (BIGINT); the permit log's keys are subject text and whole-number
  # limits.
  assert la_columns_text(la_event_columns(d)) == [["entity", "VARCHAR"], ["seq", "BIGINT"], ["time", "BIGINT"], ["type", "VARCHAR"], ["status", "VARCHAR"], ["refusal_kind", "VARCHAR"], ["refusal_detail", "VARCHAR[]"], ["links", "STRUCT(id VARCHAR, kind VARCHAR)[]"], ["value", "DOUBLE"], ["subject", "VARCHAR"], ["not_after", "BIGINT"], ["basis", "BIGINT"], ["uses_left", "BIGINT"], ["prev", "VARCHAR"], ["hash", "VARCHAR"], ["sig", "VARCHAR"]]
  assert la_columns_text(la_state_columns(d)) == [["entity", "VARCHAR"], ["seq", "BIGINT"], ["phase", "VARCHAR"], ["uses", "BIGINT"], ["opened_at", "BIGINT"], ["quality", "DOUBLE"], ["read_at", "BIGINT"], ["breach", "VARCHAR[]"], ["breach_capability", "VARCHAR"], ["replay_refusal", "VARCHAR"]]
  # grams is set from a key into a field that starts at 0: numbers, widened
  # to DOUBLE because the key comes from outside.
  assert la_field_types(la_example_portion()) == [["grams", :double], ["made_at", :bigint], ["served_at", :bigint]]
  # The empty case: a lifecycle with no fields and no payload keys has the
  # record's columns and nothing else.
  bare = lc_define(:bare, [lc_states([:a, :b]), lc_start(:a), lc_terminals([:b]), lc_event(:go, []), lc_on(:a, :go, :b, [])])
  assert size(la_event_columns(bare)) == 11
  assert map(fn(c) get(c, :name) end, la_state_columns(bare)) == ["entity", "seq", "phase", "breach", "breach_capability", "replay_refusal"]
  # Unconstrained is text, never a guess.
  noted = lc_define(:noted, [lc_states([:a, :b]), lc_start(:a), lc_terminals([:b]), lc_field(:note, nil), lc_event(:go, [:note]), lc_on(:a, :go, :b, [lc_set(:note, :note)])])
  assert la_key_types(noted) == [["note", :varchar]]
  # Controls: a key named like a record column, a field named like a state
  # column, and a field whose constants disagree are refused.
  clash = lc_define(:clash, [lc_states([:a, :b]), lc_start(:a), lc_terminals([:b]), lc_event(:go, [:time]), lc_on(:a, :go, :b, [])])
  assert error?(try(la_event_columns(clash), catch(e(), e)))
  phased = lc_define(:phased, [lc_states([:a, :b]), lc_start(:a), lc_terminals([:b]), lc_field(:phase, nil), lc_event(:go, []), lc_on(:a, :go, :b, [])])
  assert error?(try(la_state_columns(phased), catch(e(), e)))
  mixed = lc_define(:mixed, [lc_states([:a, :b]), lc_start(:a), lc_terminals([:b]), lc_field(:x, 0), lc_event(:go, []), lc_on(:a, :go, :b, [lc_put(:x, "high")])])
  assert error?(try(la_field_types(mixed), catch(e(), e)))
end

test "the history is the fold's state after every record, and names what the replay found"
  d = la_example_consumable()
  dir = la_test_dir("history")
  p = path_join(dir, "c.jsonl")
  # The empty case: no stream, no history.
  assert la_history_text(el_read(p, "t", d)) == ""
  el_append_all(el_read(p, "t", d), [["item-1", lc_ev(:open, 1000, []), []], ["item-1", lc_ev(:reading, 1100, [[:value, 26]]), []], ["item-1", lc_ev(:use, 1200, []), []], ["item-1", lc_ev(:use, 1300, []), []]])
  log = el_read(p, "t", d)
  lines = el_lines(la_history_text(log))
  # By hand: open, a reading of 26, then two uses the guard refuses
  # (quality_ok), written refused: the state after each use is the state
  # before it, and nothing is a breach.
  assert size(lines) == 4
  assert nth(2, lines) == "{\"breach\":null,\"breach_capability\":null,\"entity\":\"item-1\",\"fields\":{\"opened_at\":1000,\"quality\":26,\"read_at\":1100,\"uses\":0},\"phase\":\"open\",\"replay_refusal\":null,\"seq\":2}"
  assert nth(3, lines) == replace(nth(2, lines), "\"seq\":2", "\"seq\":3")
  # Read by a definition with no quality rule, the same stream's admitted
  # records fold the same; read by one where `use` has no row at all, an
  # admitted use would be refused on replay and says so. Here: a stream whose
  # admitted open the strict reader cannot accept.
  closed = lc_define(:consumable, [lc_states([:sealed, :gone]), lc_start(:sealed), lc_terminals([:gone]), lc_event(:open, []), lc_event(:reading, [:value]), lc_event(:use, []), lc_on(:sealed, :reading, :gone, [])])
  first_line = first(el_lines(la_history_text(el_read(p, "t", closed))))
  assert contains?(first_line, "\"replay_refusal\":\"no_edge\"")
  assert contains?(first_line, "\"phase\":\"sealed\"")
  # The control: the tightened guard turns an applied event into a breach
  # (the strict example allows 3 uses; this stream has none admitted, so a
  # stream with four admitted uses is written first).
  q = path_join(dir, "s.jsonl")
  el_append_all(el_read(q, "t", d), [["item-1", lc_ev(:reading, 1000, [[:value, 10]]), []], ["item-1", lc_ev(:open, 1100, []), []], ["item-1", lc_ev(:use, 1200, []), []], ["item-1", lc_ev(:use, 1300, []), []], ["item-1", lc_ev(:use, 1400, []), []], ["item-1", lc_ev(:use, 1500, []), []]])
  strict = el_lines(la_history_text(el_read(q, "t", la_example_consumable_strict())))
  assert map(fn(l) contains?(l, "\"breach\":[\"uses_left\"],\"breach_capability\":\"use\"") end, strict) == [false, false, false, false, false, true]
  rm_rf(dir)
end

test "the database for a simulated day: every view's numbers, checked by hand, and the fold as the differential"
  dir = la_test_dir("day")
  streams = la_example_streams(dir)
  now = 86400
  db = la_build(dir, streams, now)
  ms = la_models(la_bindings(dir, streams), now)
  view = fn(name) la_norm_rows(la_read(db, la_find(ms, name))) end
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
  assert map(fn(n) view("#{n}_unreplayed") end, ["consumable", "portion", "order"]) == [[[0.0]], [[0.0]], [[0.0]]]
  # Current state. item-1: four admitted uses (the refused one at 30100 is
  # not folded), quality 12 from the last reading, read at 31000. item-2:
  # two admitted uses; the refused open changed nothing (opened_at 29500).
  # item-3 was discarded sealed; its refused polish is its last record.
  assert view("consumable_current_state") == la_norm_rows([["item-1", "spent", 4, 29000, 12, 31000, 10, 32000], ["item-2", "open", 2, 29500, 10, 28900, 6, 44000], ["item-3", "discarded", 0, nil, nil, nil, 1, 30100]])
  assert view("portion_current_state") == la_norm_rows([["p-1", "served", 120, 29250, 29400, 1, 29400], ["p-2", "wasted", 110, 30050, nil, 1, 30500], ["p-3", "served", 130, 29650, 31000, 1, 31000], ["p-4", "served", 100, 33000, 33500, 1, 33500]])
  assert view("order_current_state") == la_norm_rows([["o-1", "delivered", 2, 29100, 31500, 4, 31500], ["o-2", "cancelled", 1, 30000, nil, 2, 30600], ["o-3", "placed", 1, 33100, nil, 2, 33700]])
  # The differential: the same phases and fields as nisshi's own replay.
  map(fn(s) la_example_differential(db, ms, s) end, streams)
  # Time in each state, to 86400. item-1: sealed 28800-29000 = 200, open
  # 29000-32000 = 3000, spent 32000-86400 = 54400 (now). item-2: sealed
  # 28900-29500 = 600, open 29500-86400 = 56900 (now). item-3: discarded
  # 30000-86400 = 56400 (now).
  assert view("consumable_time_in_state") == la_norm_rows([["item-1", "open", 3000, 0], ["item-1", "sealed", 200, 0], ["item-1", "spent", 54400, 1], ["item-2", "open", 56900, 1], ["item-2", "sealed", 600, 0], ["item-3", "discarded", 56400, 1]])
  # o-1: placed 29100-31200 = 2100, ready 31200-31500 = 300, delivered
  # 31500-86400 = 54900. o-2: placed 600, cancelled 55800. o-3: placed
  # 33100-86400 = 53300 (its refused deliver left it placed).
  assert view("order_time_in_state") == la_norm_rows([["o-1", "delivered", 54900, 1], ["o-1", "placed", 2100, 0], ["o-1", "ready", 300, 0], ["o-2", "cancelled", 55800, 1], ["o-2", "placed", 600, 0], ["o-3", "placed", 53300, 1]])
  # Refusals by type and kind.
  assert view("consumable_refusals") == la_norm_rows([["open", "no_edge", 1], ["polish", "unknown_event", 1], ["use", "guard", 2]])
  assert view("portion_refusals") == []
  assert view("order_refusals") == la_norm_rows([["deliver", "no_edge", 1]])
  # Every declared rule: quality_ok refused item-1's use at 30100,
  # reading_fresh item-2's at 44000; no breaches (nisshi refuses at append).
  assert view("consumable_rule_hits") == la_norm_rows([["use", "is_open", "phase in [:open]", 0, 0], ["use", "not_too_old", "opened_at less than 259200 old", 0, 0], ["use", "quality_ok", "quality below 24", 1, 0], ["use", "reading_fresh", "read_at less than 14400 old", 1, 0], ["use", "uses_left", "uses below 40", 0, 0]])
  # Tasks. quality_ok names no task, so its guard's `replace` (evidence
  # reading or scan, 1200 s) opens at 30100 and item-1's reading at 31000
  # closes it: open 900 s, not overdue. reading_fresh asks take_reading
  # (evidence reading, 1200 s) at 44000, and no reading follows: open
  # 86400 - 44000 = 42400 s, overdue.
  assert view("consumable_tasks") == la_norm_rows([["item-1", "replace", "closed", 7, 30100, 8, 31000, 1, 900, 1200, false], ["item-2", "take_reading", "open", 6, 44000, nil, nil, 1, 42400, 1200, true]])
  assert view("consumable_task_summary") == la_norm_rows([["replace", 1, 0, 1, 0], ["take_reading", 1, 1, 0, 1]])
  # Permits. item-1's at 29100: not_after = min(28800 + 14400, 29000 +
  # 259200, 29100 + 7200) = 36300, 40 uses left, basis 2 (two events folded);
  # used by the four admitted uses after it, all before 36300, the last at
  # 31100. item-2's at 29550: not_after = min(43300, 288700, 36750) = 36750;
  # one use at 29600 inside it, and the use at 40000 after not_after, an
  # overrun (the guard still held, the permit had lapsed).
  assert view("consumable_permit_use_use") == la_norm_rows([["item-1", 2, "device-1", 29100, 36300, 7200, 2, 40, 4, 0, 31100, false], ["item-2", 2, "device-2", 29550, 36750, 7200, 2, 40, 1, 1, 29600, false]])
  # Links: each portion's consumable as it was when the portion was made (its
  # latest record at or before the make). p-1 at 29250: item-1 after [3]
  # (1 use, quality 10). p-2 at 30050: item-1 after [6], the reading of 26,
  # out of spec. p-3 at 29650: item-2 after [3]. p-4 names item-9, which has
  # no records: the row stays, unresolved.
  assert view("portion_item") == la_norm_rows([["p-1", 0, 29250, "make", "admitted", "item-1", 3, "open", 1, 29000, 10, 28800], ["p-2", 0, 30050, "make", "admitted", "item-1", 6, "open", 3, 29000, 26, 30000], ["p-3", 0, 29650, "make", "admitted", "item-2", 3, "open", 1, 29500, 10, 28900], ["p-4", 0, 33000, "make", "admitted", "item-9", nil, nil, nil, nil, nil, nil]])
  assert view("portion_item_coverage") == [[4.0, 1.0]]
  # Each order's portion as it was when it was added.
  assert view("order_portion") == la_norm_rows([["o-1", 1, 29450, "add_portion", "admitted", "p-1", 1, "served", 120, 29250, 29400], ["o-1", 2, 31050, "add_portion", "admitted", "p-3", 1, "served", 130, 29650, 31000], ["o-2", 1, 30100, "add_portion", "admitted", "p-2", 0, "made", 110, 30050, nil], ["o-3", 1, 33600, "add_portion", "admitted", "p-4", 1, "served", 100, 33000, 33500]])
  assert view("order_portion_coverage") == [[4.0, 0.0]]
  # The chain, generated from the two declarations: each order's portion, the
  # consumable that portion was made with, and that consumable's state at the
  # make. o-2's portion p-2 was made with item-1 while its quality read 26.
  assert view("order_portion_item") == la_norm_rows([["o-1", 1, 29450, "add_portion", "admitted", "p-1", 0, 29250, "make", "item-1", 3, "open", 1, 29000, 10, 28800], ["o-1", 2, 31050, "add_portion", "admitted", "p-3", 0, 29650, "make", "item-2", 3, "open", 1, 29500, 10, 28900], ["o-2", 1, 30100, "add_portion", "admitted", "p-2", 0, 30050, "make", "item-1", 6, "open", 3, 29000, 26, 30000], ["o-3", 1, 33600, "add_portion", "admitted", "p-4", 0, 33000, "make", "item-9", nil, nil, nil, nil, nil, nil]])
  # The event table's payload column, read back typed.
  readings = q_model({name: :la_readings, from: la_find(ms, "consumable_events"), pipeline: [q_filter(q_eq(:type, "reading")), q_select([:entity, :seq, :value])]})
  assert la_norm_rows(la_read(db, readings)) == la_norm_rows([["item-1", 0, 10], ["item-1", 6, 26], ["item-1", 8, 12], ["item-2", 0, 10]])
  # Spans, declared on the order. lead (placed -> delivered, limit 2000):
  # o-1 placed 29100 [0], delivered 31500 [4]: 2400 s, over. o-2 was placed
  # at 30000 and cancelled, a terminal it never reaches delivered from:
  # abandoned, no elapsed time, not judged. o-3 placed 33100 and never
  # delivered (its deliver was refused): open, 86400 - 33100 = 53300 s, over.
  # ready_to_door (ready -> delivered, no limit): only o-1 was ready, at 31200
  # [3], delivered 300 s later.
  assert view("order_span_lead") == la_norm_rows([["o-1", "done", 0, 29100, 4, 31500, 2400, 2400, 2000, true], ["o-2", "abandoned", 0, 30000, nil, nil, nil, nil, 2000, nil], ["o-3", "open", 0, 33100, nil, nil, nil, 53300, 2000, true]])
  assert view("order_span_lead_summary") == la_norm_rows([[3, 1, 1, 1, 2, 2400, 2400, 2400, 2000]])
  assert view("order_span_ready_to_door") == la_norm_rows([["o-1", "done", 3, 31200, 4, 31500, 300, 300, nil, nil]])
  assert view("order_span_ready_to_door_summary") == la_norm_rows([[1, 1, 0, 0, 0, 300, 300, 300, nil]])
  # Uses no permit covered: item-2's use at 40000 [5] came after its permit's
  # not_after (36750): lapsed. Every other admitted use sat inside a window.
  assert view("consumable_unpermitted_use") == la_norm_rows([["item-2", 5, 40000, 2, 36750, nil, "lapsed"]])
  rm_rf(dir)
end

test "observed breaches and uses no permit covered: each found, with the reason, and asking for its task"
  dir = la_test_dir("observed")
  d = la_example_consumable()
  s = la_stream(d, path_join(dir, "consumable.jsonl"), "anaritikusu-observed")
  log0 = el_read(get(s, :path), get(s, :label), d)
  # item-a, seq in brackets: [0] reading 10 at 1000, [1] open 1100, [2] a use
  # OBSERVED at 1200 before any permit (the guard holds, so no breach),
  # [3] a permit at 1300, [4] a use at 1400, [5] a reading of 26 at 1500,
  # [6] a use OBSERVED at 1600 (quality_ok refuses: a breach), [7] a use
  # ATTEMPTED at 9000 (refused), [8] a use OBSERVED at 9100 (a breach again).
  l1 = el_append_all(log0, [["item-a", lc_ev(:reading, 1000, [[:value, 10]]), []], ["item-a", lc_ev(:open, 1100, []), []]])
  l2 = el_observe(l1, "item-a", lc_ev(:use, 1200, []), [])
  l3 = el_append(l2, "item-a", lc_permit_event(d, lc_permit_for(d, el_state(l2, "item-a"), :use, 1300), "dev"), [])
  l4 = el_append_all(l3, [["item-a", lc_ev(:use, 1400, []), []], ["item-a", lc_ev(:reading, 1500, [[:value, 26]]), []]])
  l5 = el_observe(l4, "item-a", lc_ev(:use, 1600, []), [])
  l6 = el_append(l5, "item-a", lc_ev(:use, 9000, []), [])
  el_observe(l6, "item-a", lc_ev(:use, 9100, []), [])
  now = 20000
  db = la_build(dir, [s], now)
  ms = la_models(la_bindings(dir, [s]), now)
  view = fn(name) la_norm_rows(la_read(db, la_find(ms, name))) end
  # By hand. The permit at 1300: not_after = min(1000 + 14400, 1100 + 259200,
  # 1300 + 7200) = 8500, 39 uses left (one use folded), basis 3. The use at
  # 1200 had no permit before it; the one at 1600 broke the guard inside the
  # window; the one at 9100 came after not_after (and broke the guard too:
  # lapsed is reported first). The use at 1400 was covered. (The breach column
  # is a VARCHAR[], and it reads back as a list.)
  assert view("consumable_unpermitted_use") == la_norm_rows([["item-a", 2, 1200, nil, nil, nil, "no_permit"], ["item-a", 6, 1600, 3, 8500, ["quality_ok"], "breach"], ["item-a", 8, 9100, 3, 8500, ["quality_ok"], "lapsed"]])
  # The permit's window counts the uses at 1400 and 1600 (by window alone) and
  # the overrun at 9100.
  assert view("consumable_permit_use_use") == la_norm_rows([["item-a", 3, "dev", 1300, 8500, 7200, 3, 39, 2, 1, 1600, false]])
  # quality_ok refused one attempt and was breached twice; the three asks are
  # one `replace` task, opened at 1600, never closed (no later reading), open
  # 20000 - 1600 = 18400 s against 1200: overdue.
  assert filter(fn(r) nth(1, r) == "quality_ok" end, view("consumable_rule_hits")) == la_norm_rows([["use", "quality_ok", "quality below 24", 1, 2]])
  assert view("consumable_tasks") == la_norm_rows([["item-a", "replace", "open", 6, 1600, nil, nil, 3, 18400, 1200, true]])
  # The breaches were applied: four uses folded (1200, 1400, 1600, 9100).
  assert view("consumable_current_state") == la_norm_rows([["item-a", "open", 4, 1100, 26, 1500, 8, 9100]])
  # The control: with the observed uses appended as attempts instead, the
  # guard refuses them, nothing is breached, and only the use before any
  # permit is left uncovered.
  dir2 = la_test_dir("attempted")
  s2 = la_stream(d, path_join(dir2, "consumable.jsonl"), "anaritikusu-observed")
  m1 = el_append_all(el_read(get(s2, :path), get(s2, :label), d), [["item-a", lc_ev(:reading, 1000, [[:value, 10]]), []], ["item-a", lc_ev(:open, 1100, []), []], ["item-a", lc_ev(:use, 1200, []), []]])
  m2 = el_append(m1, "item-a", lc_permit_event(d, lc_permit_for(d, el_state(m1, "item-a"), :use, 1300), "dev"), [])
  el_append_all(m2, [["item-a", lc_ev(:use, 1400, []), []], ["item-a", lc_ev(:reading, 1500, [[:value, 26]]), []], ["item-a", lc_ev(:use, 1600, []), []], ["item-a", lc_ev(:use, 9000, []), []], ["item-a", lc_ev(:use, 9100, []), []]])
  db2 = la_build(dir2, [s2], now)
  ms2 = la_models(la_bindings(dir2, [s2]), now)
  assert la_norm_rows(la_read(db2, la_find(ms2, "consumable_unpermitted_use"))) == la_norm_rows([["item-a", 2, 1200, nil, nil, nil, "no_permit"]])
  assert filter(fn(r) nth(1, r) == "quality_ok" end, la_norm_rows(la_read(db2, la_find(ms2, "consumable_rule_hits")))) == la_norm_rows([["use", "quality_ok", "quality below 24", 3, 0]])
  rm_rf(dir)
  rm_rf(dir2)
end

# nisshi's replay and the database agree on every entity's phase and fields.
def la_example_differential(db, ms, s)
  d = get(s, :def)
  nf = size(lc_d_field_names(d))
  fold = map(fn(es) la_norm_rows([cons(first(es), cons(lc_text(lc_phase(nth(1, es))), map(fn(kv) nth(1, kv) end, lc_fields(nth(1, es)))))]) end, el_states(el_read(get(s, :path), get(s, :label), d)))
  sql = map(fn(r) take_n(r, 2 + nf) end, la_norm_rows(la_read(db, la_find(ms, la_n(d, "current_state")))))
  if set_equal(map(fn(x) first(x) end, fold), sql) == false
    throw(error(:anaritikusu_test, "#{lc_text(lc_name(d))}: the database's current state differs from nisshi's replay"))
  end
  size(sql)
end

test "a stricter reader: an applied event becomes a breach, and asks for its task"
  dir = la_test_dir("strict")
  streams = la_example_streams(dir)
  strict = map(fn(s) la_example_restrict(s) end, streams)
  db = la_build(dir, strict, 86400)
  ms = la_models(la_bindings(dir, strict), 86400)
  view = fn(name) la_norm_rows(la_read(db, la_find(ms, name))) end
  # Read with fewer than 3 uses allowed, item-1's use at 31100 [9] (its 4th)
  # was applied while uses_left refused: one breach. Its task is the guard's
  # `replace`, and nothing after [9] is evidence: open 86400 - 31100 = 55300,
  # overdue. The use at 30100 still reads as refused by the log.
  assert view("consumable_rule_hits") == la_norm_rows([["use", "is_open", "phase in [:open]", 0, 0], ["use", "not_too_old", "opened_at less than 259200 old", 0, 0], ["use", "quality_ok", "quality below 24", 1, 0], ["use", "reading_fresh", "read_at less than 14400 old", 1, 0], ["use", "uses_left", "uses below 3", 0, 1]])
  assert view("consumable_task_summary") == la_norm_rows([["replace", 2, 1, 1, 1], ["take_reading", 1, 1, 0, 1]])
  # A breach is applied: item-1 still ends with four uses.
  assert first(view("consumable_current_state")) == first(la_norm_rows([["item-1", "spent", 4, 29000, 12, 31000, 10, 32000]]))
  rm_rf(dir)
end

def la_example_restrict(s)
  if lc_text(lc_name(get(s, :def))) == "consumable"
    la_stream(la_example_consumable_strict(), get(s, :path), get(s, :label))
  else
    s
  end
end

test "the set is refused where it cannot be generated, and a broken stream is refused where it is built"
  dir = la_test_dir("refused")
  portion = la_binding(la_example_portion(), path_join(dir, "p.jsonl"), path_join(dir, "p.h"))
  consumable = la_binding(la_example_consumable(), path_join(dir, "c.jsonl"), path_join(dir, "c.h"))
  # The empty case: no lifecycles, no models.
  assert is_empty(la_models([], 0))
  # A link to a lifecycle not given; the same set with it holds.
  assert error?(try(la_models([portion], 0), catch(e(), e)))
  assert size(la_models([portion, consumable], 0)) > 0
  # Two lifecycles with one name; a role whose generated name collides with a
  # standard view (a role named `events`); `now` that is not a time.
  assert error?(try(la_models([consumable, consumable], 0), catch(e(), e)))
  evented = lc_define(:portion, [lc_states([:a, :b]), lc_start(:a), lc_terminals([:b]), lc_event(:go, []), lc_on(:a, :go, :b, []), lc_link(:events, :consumable)])
  assert error?(try(la_models([la_binding(evented, "x", "y"), consumable], 0), catch(e(), e)))
  assert error?(try(la_models([consumable], 1.5), catch(e(), e)))
  # A stream with a changed line is not built on.
  streams = la_example_streams(dir)
  path = get(first(streams), :path)
  write_file(path, replace(read_file(path), "\"time\":29300", "\"time\":29301"))
  assert error?(try(la_build(dir, streams, 86400), catch(e(), e)))
  rm_rf(dir)
end

test "as of, with two records of the linked entity in one second: the state after the later one"
  dir = la_test_dir("tie")
  d = la_example_consumable()
  p = la_example_portion()
  sc = la_stream(d, path_join(dir, "consumable.jsonl"), "anaritikusu-tie")
  sp = la_stream(p, path_join(dir, "portion.jsonl"), "anaritikusu-tie")
  # item-t: [0] reading 10 at 1000, [1] open 1100, [2] and [3] two uses at
  # 1200. p-t is made at 1200 and p-u at 1300, each linking item-t. By hand:
  # both see item-t after [3], two uses, whichever order the database keeps
  # the two 1200 records in.
  el_append_all(el_read(get(sc, :path), get(sc, :label), d), [["item-t", lc_ev(:reading, 1000, [[:value, 10]]), []], ["item-t", lc_ev(:open, 1100, []), []], ["item-t", lc_ev(:use, 1200, []), []], ["item-t", lc_ev(:use, 1200, []), []]])
  el_append_all(el_read(get(sp, :path), get(sp, :label), p), [["p-t", lc_ev(:make, 1200, [[:grams, 100]]), [[:item, "item-t"]]], ["p-u", lc_ev(:make, 1300, [[:grams, 90]]), [[:item, "item-t"]]]])
  db = la_build(dir, [sc, sp], 5000)
  ms = la_models(la_bindings(dir, [sc, sp]), 5000)
  assert map(fn(r) [first(r), nth(6, r), nth(8, r)] end, la_norm_rows(la_read(db, la_find(ms, "portion_item")))) == la_norm_rows([["p-t", 3, 2], ["p-u", 3, 2]])
  rm_rf(dir)
end
