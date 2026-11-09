@moduledoc """
raifusaikuru (ライフサイクル) — lifecycles: event-sourced states, guards that name the rule and the task, and permit limits.

One lifecycle definition per KIND of entity declares its states, the events
that move it, the fields its events fold into, and GUARDS: named rules over the
folded state that allow or refuse a capability ("may use"). The engine is
pure. It returns data and performs no side effects, so the same events always
give the same state, and any state can be rebuilt and audited from its log.
Nothing here knows any domain: a consumer declares its own lifecycles on top.

## The operations

  build   lc_define(name, clauses)     validate, or throw :raifusaikuru_definition
          lc_problems(name, clauses)   the same findings as data, [kind, why]
  fold    lc_state_of(def, events)     replay an entity's events, in order
          lc_resume(def, state, events), lc_step(def, state, event), lc_initial(def)
  admit   lc_admit(def, state, event)  would this event be accepted now?
          lc_admit_step(def, state, event)   [lc_admit, lc_step] from one judgement
  guard   lc_allowed(def, state, capability, now)
          allowed, or refused with the rules that refused, why, and the
          task specs to create
  permit  lc_permit_for(def, state, capability, now)
          the limits (not-after time, remaining counts) as data;
          lc_permit_payload(permit, subject) is the signing seam;
          lc_permit_event(def, permit, subject) is the issuance as an event
          to log, when the definition declares lc_permit_log

## Clauses (a definition is a list of these, nested freely)

  lc_states lc_start lc_terminals lc_rests lc_field lc_event
  lc_on(from, event, to, effects)   one transition row; `to` may be :stay
  lc_on_each(froms, event, to, effects)   the same row from several states
  lc_gate(capability, rows)        the event USES the capability
  lc_guard(capability, rules, task)   rules: lc_rule / lc_rule_task
  lc_permit(capability, terms)     terms: lc_valid_for, lc_counted
  lc_permit_log(capability, event) an issued permit is logged as `event`, a
                                   no-op accepted in every non-terminal state
  lc_link(role, target)            records may carry links of kind `role`,
                                   each naming an entity of lifecycle `target`
  lc_span(name, from, to, limit)   a duration that matters: first entry into
                                   `from` to first entry into `to` after it,
                                   with its limit (or nil)
effects   lc_set lc_put lc_add lc_add_from lc_stamp
predicates  lc_below lc_at_most lc_above lc_at_least lc_equals lc_present
            lc_fresh lc_in_phase lc_all lc_any lc_not
tasks     lc_task(name, evidence_kinds, escalate_after)

`lc_example_consumable()` is a worked definition (a consumable with a use
counter, an age limit and a quality reading); read it first.

## Recon: the shape two Rust FSMs already agree on

Two typed lifecycle FSMs were written independently and converge on one
shape: breathe's cloud-node FSM (breathe-lifecycle/src/fsm.rs, `FaseNode`)
and pangea-operator's template lifecycle (controller/lifecycle.rs, `Phase` +
`TRANSITIONS`); shigoto-fsm is the convergence harness breathe consumes and
pangea hand-rolls. Adopted here:

  - a closed, enumerated state set, where a transition exists iff a row
    exists (pangea's TRANSITIONS; breathe's legal_successors): lc_on rows;
  - an illegal (state, event) is a typed refusal naming the events that ARE
    legal there (pangea's TransitionError::Illegal { legal }): :no_edge;
  - edges shared by many states expanded into rows by one function, not
    repeated by hand (pangea's universal_edges_for): lc_on_each;
  - declared terminals with no exit, and shigoto-fsm's convergence checks:
    a non-empty state space, no dangling edge, no trap (a non-terminal with no
    exit), terminal soundness, and every state reaching a good resting state
    (lc_rests is shigoto's is_good_resting_state, for cyclic lifecycles);
  - a step that needs evidence cannot be claimed bare (breathe's
    confirm_reaped requires its witness): declared payload keys are required,
    and a task names the evidence kinds that close it.

Not adopted: breathe's phantom typestate, where an illegal transition is an
absent method. blue is dynamically typed, so this is pangea's tier instead:
rejected at the parse boundary, a bad definition when it is built and an
illegal event when it is folded. Added beyond both: guards over folded field
data, tasks and permits. Neither FSM carries data-dependent guards.

Adjacent, not merged: `utsuroi` (ensaio/utsuroi-lifecycle)
is a Rust stage PROJECTION for ephemeral resources (spawn → ready → keep →
drain → reaped) that existing domain FSMs map onto. It declares no
lifecycles and folds no events. Its named-M1 `(deflifecycle …)` keyword stays
its own.

## Tiers

REFUSED WHEN BUILT (lc_define throws; lc_problems lists each with its kind):
an undeclared state, event, field or payload key anywhere; a transition from
a missing state; two rows for one (state, event), which would make the fold
ambiguous; a trap, an unreachable state, a state that cannot reach a terminal
or resting state, a terminal with an exit; an empty guard or an empty lc_all /
lc_any (a vacuous truth); a task with no evidence or no escalation; a permit
with no time bound, a counted field its guard does not bound, or a time or
count condition under lc_any / lc_not in a permitted guard, where the limits
would not be sound; a permit log for a capability with no lc_permit, or two
for one capability; two links with one role; a span on an undeclared state,
from a state to itself, to a state no event reaches from its start, or with
a limit that is not a positive whole duration, and two spans with one name.
`lc_problem_kinds()` is the closed list, and a test row exercises every kind.
RECORDED BY THE FOLD, never thrown: an event the definition does not know,
an event with no row from the current state, one missing a declared payload
key, or one whose counter or added amount is not a number is REFUSED. It is
kept in lc_refused(state) and changes nothing else. An event on a gated row while its guard refuses still happened, so it
is APPLIED and kept in lc_breaches(state).
FAIL CLOSED: a comparison over an absent or non-numeric field is UNKNOWN,
and a rule holds only when it is known to hold (three-valued logic). An
undeclared capability is refused, never allowed.
NOT CHECKED: the clock. Event times and `now` are integers on one clock the
caller chooses (lc_minutes / lc_hours / lc_days assume seconds). Events fold
in list order, never sorted by time: order is the log's sequence.

## Permits

A permit is valid only while its guard would still allow the capability.
not_after is the earliest moment an lc_fresh conjunct of the guard expires,
or now + lc_valid_for(d) if that is sooner. The remaining count of an
lc_counted(field) is how many more uses (one unit of the field each) keep
every lc_below / lc_at_most / lc_equals conjunct on it true. The limits are
read from the guard, so they are never restated and cannot drift from it.
Fields that only events change (a reading) are frozen at the permit's basis,
the state's sequence number: a consumer re-derives on every event and revokes
when the guard refuses. Signing is NOT here: lc_permit_payload renders the
canonical text a signer signs, the seam for a crypto bidama.

An issued permit is a fact an auditor asks about, and an event log records
only events. lc_permit_log(capability, event) makes issuance an event: the
definition gains `event`, whose payload keys are the permit's limits
(subject, not_after, basis, and `<field>_left` per counted field, named by
lc_permit_count_key), and a :stay row with no effects from every
non-terminal state. So logging a permit changes no field and no phase, only
the sequence, and a terminal entity cannot be issued one. lc_permit_event
renders an issued permit as that event.

## Links

lc_link(role, target) declares that this lifecycle's records may link, with
link kind `role` (the kind an event log writes beside each link's id), to an
entity of lifecycle `target`. The shape is the one declared relations
already agree on: declared on the referring side, a role plus the target's
kind, with the id carried by the referring record (a Kubernetes
ownerReference's {kind, name}; Rails `belongs_to`; dbt's `relationships`
test). The engine folds no link: the declaration is for what reads the log
(joins generated across lifecycles). Only this definition is checked here
(names, one row per role); whether `target` exists is checked where the
lifecycles are read together.

## Spans

lc_span(name, from, to, limit) declares a duration the lifecycle is
measured by: from an entity's first entry into `from` to its first entry
into `to` after that (an order's fryer-to-mouth: fried → delivered), and the
longest it should take. A recipe's timed record is part of the lifecycle's
definition, as a link is, so the definition stays the one source every
reader derives from; the engine folds nothing for it, and anaritikusu
generates a view per span. Added 2026-09-25 for NuPastel's measures (plan:
nupastel docs/plans/measures.md); red-run: a problem row per new kind, and
the span test red when the reachability check was dropped.

    gate(:g, []) #=> []
"""

use("kazu", [:min])

use(
  "retsu",
  %i[
    as_list
    concat_lists
    contains
    count_of
    drop_n
    filter_where
    find_first
    first
    flat_map
    flatten1
    headed?
    is_empty
    last
    push
    repeat
    rest
    size
    take_n
  ]
)

use("shuugou", %i[lookup set_equal union unique unique_by])

legacy_names("0.1.1", "lc")

# ── names and time ─────────────────────────────────────────────────────────

@doc """
text: A name as text: a keyword's name, a string itself, anything else via to_s.

    text(:ready) #=> "ready"
    text(42) #=> "42"
"""
def text(x)
  if keyword?(x)
    to_s(x)
  elsif string?(x)
    x
  else
    to_s(x)
  end
end

@doc """
show: A value as it reads in a message: keywords keep their colon, strings their
quotes.

    show(:ready) #=> ":ready"
    show(nil) #=> "nil"
"""
def show(x)
  if keyword?(x)
    ":#{to_s(x)}"
  elsif string?(x)
    "\"#{x}\""
  elsif x.nil?
    "nil"
  else
    to_s(x)
  end
end

@doc """
name?: Whether a value can name a state, event or field: a keyword or a string.

    name?(:ready) #=> true
    name?(3) #=> false
"""
def name?(x)
  keyword?(x) or string?(x)
end

@doc """
minutes: Durations on a seconds clock.

    minutes(2) #=> 120
"""
def minutes(n)
  n * 60
end

@doc """
hours: `n` hours on a seconds clock.

    hours(2) #=> 7200
"""
def hours(n)
  n * 3600
end

@doc """
days: `n` days on a seconds clock.

    days(1) #=> 86400
"""
def days(n)
  n * 86400
end

# ── clauses: what a definition is written in ───────────────────────────────

@doc """
states: Declare states. May appear more than once; the mentions accumulate.

    states(%i[new used]) #=> [:lc_states, %i[new used]]
"""
def states(names)
  [:lc_states, as_list(names)]
end

@doc """
start: The state a new entity starts in: exactly one per definition.

    start(:new) #=> [:lc_start, :new]
"""
def start(state)
  [:lc_start, state]
end

@doc """
terminals: Terminal states: an entity rests there for good, and no event leaves them.

    terminals(%i[discarded]) #=> [:lc_terminals, %i[discarded]]
"""
def terminals(names)
  [:lc_terminals, as_list(names)]
end

@doc """
rests: Resting states that are not sinks (an asset in service): an entity may stay
in one indefinitely, and events still move it. Every state must be able to
reach a terminal or a resting state.

    rests(%i[in_service]) #=> [:lc_rests, %i[in_service]]
"""
def rests(names)
  [:lc_rests, as_list(names)]
end

@doc """
field: A field the events fold into, with its value before any event.

    field(:uses, 0) #=> [:lc_field, :uses, 0]
"""
def field(name, initial)
  [:lc_field, name, initial]
end

@doc """
event: An event type and the payload keys it must carry. A declared key is
required: the fold refuses an event that lacks one.

    event(:read, %i[value]) #=> [:lc_event, :read, %i[value]]
"""
def event(name, keys)
  [:lc_event, name, as_list(keys)]
end

@doc """
on: One transition row: in `from`, event `event` moves the entity to `to` and
applies `effects` in order. `to` may be :stay, a self-loop.

    on(:new, :use, :stay, []) #=> [:lc_edge, :new, :use, :new, [], nil]
"""
def on(from, event, to, effects)
  [:lc_edge, from, event, stay_to(from, to), as_list(effects), nil]
end

@doc """
stay_to: The state a row moves to: `from` itself when `to` is :stay.

    stay_to(:new, :stay) #=> :new
    stay_to(:new, :used) #=> :used
"""
def stay_to(from, to)
  if to == :stay
    from
  else
    to
  end
end

@doc """
on_each: The same row from each of several states. With :stay each row loops on its
own state.

    on_each(%i[a b], :ping, :stay, []) #=> [[:lc_edge, :a, :ping, :a, [], nil], [:lc_edge, :b, :ping, :b, [], nil]]
"""
def on_each(froms, event, to, effects)
  map((f) -> on(f, event, to, effects), as_list(froms))
end

@doc """
gate: Gate rows by a capability: the event is a USE of it. The fold evaluates the
capability's guard at the event's time and records a breach when it
refuses; lc_admit rejects such an event before it is appended.

    gate(:g, []) #=> []
"""
def gate(capability, rows)
  map((c) -> gated_row(capability, c), flat_one(rows))
end

@doc """
gated_row: One clause under `gate`: a transition row gains the capability it uses;
any other clause becomes a :lc_misgated finding for lc_define to refuse.

    gated_row(:cook, on(:a, :go, :b, [])) #=> [:lc_edge, :a, :go, :b, [], :cook]
    gated_row(:cook, start(:a)) #=> [:lc_misgated, :cook, :lc_start]
"""
def gated_row(capability, c)
  if first(c) == :lc_edge
    [:lc_edge, c[1], c[2], c[3], c[4], capability]
  else
    [:lc_misgated, capability, first(c)]
  end
end

# ── effects: what an accepted event does to the fields ─────────────────────

@doc """
set: Set a field from a payload key of the event.

    set(:quality, :value) #=> [:set, :quality, :value]
"""
def set(field, key)
  [:set, field, key]
end

@doc """
put: Set a field to a constant.

    put(:open, true) #=> [:put, :open, true]
"""
def put(field, value)
  [:put, field, value]
end

@doc """
add: Add a constant to a numeric field: a counter.

    add(:uses, 1) #=> [:add, :uses, 1]
"""
def add(field, n)
  [:add, field, n]
end

@doc """
add_from: Add a numeric payload value to a numeric field.

    add_from(:grams, :amount) #=> [:add_key, :grams, :amount]
"""
def add_from(field, key)
  [:add_key, field, key]
end

@doc """
stamp: Set a field to the event's time.

    stamp(:opened_at) #=> [:stamp, :opened_at]
"""
def stamp(field)
  [:stamp, field]
end

# ── predicates: what a rule says about the folded state ────────────────────

@doc """
below: The field is a number below the limit.

    below(:uses, 3) #=> [:lt, :uses, 3]
"""
def below(field, limit)
  [:lt, field, limit]
end

@doc """
at_most: The field is a number no greater than the limit.

    at_most(:uses, 3) #=> [:le, :uses, 3]
"""
def at_most(field, limit)
  [:le, field, limit]
end

@doc """
above: The field is a number greater than the limit.

    above(:quality, 0.5) #=> [:gt, :quality, 0.5]
"""
def above(field, limit)
  [:gt, field, limit]
end

@doc """
at_least: The field is a number no less than the limit.

    at_least(:quality, 0.5) #=> [:ge, :quality, 0.5]
"""
def at_least(field, limit)
  [:ge, field, limit]
end

@doc """
equals: The field equals the value. A float never equals an int: 1.0 is not 1.

    equals(:state, :ok) #=> [:eq, :state, :ok]
"""
def equals(field, value)
  [:eq, field, value]
end

@doc """
present: The field has a value (is not nil). Never unknown.

    present(:opened_at) #=> [:present, :opened_at]
"""
def present(field)
  [:present, field]
end

@doc """
fresh: The field holds a time less than `max_age` before now: a reading still
fresh, an item not yet too old.

    fresh(:opened_at, 3600) #=> [:age_lt, :opened_at, 3600]
"""
def fresh(field, max_age)
  [:age_lt, field, max_age]
end

@doc """
in_phase: The entity is in one of these states.

    in_phase(%i[open]) #=> [:in, %i[open]]
"""
def in_phase(states)
  [:in, as_list(states)]
end

@doc """
all: Every predicate holds. Unknown when none refuses and one is unknown.

    all([present(:a)]) #=> [:all, [[:present, :a]]]
"""
def all(preds)
  [:all, as_list(preds)]
end

@doc """
any: Some predicate holds. Unknown when none holds and one is unknown.

    any([present(:a)]) #=> [:any, [[:present, :a]]]
"""
def any(preds)
  [:any, as_list(preds)]
end

# waive B0013: `not` is a builtin raifusaikuru also uses, so the prefix stays; isshou::raifusaikuru::not names it too
@doc """
lc_not: The predicate does not hold. The negation of unknown is unknown.

    lc_not(present(:a)) #=> [:not, [:present, :a]]
"""
def lc_not(pred)
  [:not, pred]
end

# ── guards, tasks and permits ──────────────────────────────────────────────

@doc """
task: A task spec: its name, the evidence kinds that close it, and how long it may
stay open before it escalates. Only data: the engine creates nothing.

    task(:recheck, %i[reading], 3600) #=> [:lc_task, :recheck, %i[reading], 3600]
"""
def task(name, evidence, escalate_after)
  [:lc_task, name, as_list(evidence), escalate_after]
end

@doc """
task_name: A task spec's name.

    task_name(task(:recheck, %i[reading], 3600)) #=> :recheck
"""
def task_name(t)
  t[1]
end

@doc """
task_evidence: The evidence kinds that close a task spec.

    task_evidence(task(:recheck, %i[reading], 3600)) #=> %i[reading]
"""
def task_evidence(t)
  t[2]
end

@doc """
task_escalate_after: How long a task spec may stay open before it escalates.

    task_escalate_after(task(:recheck, %i[reading], 3600)) #=> 3600
"""
def task_escalate_after(t)
  t[3]
end

@doc """
rule: A named rule. A guard allows its capability only when every rule holds.

    rule(:r, below(:n, 3)) #=> [:lc_rule, :r, below(:n, 3), nil]
"""
def rule(name, pred)
  [:lc_rule, name, pred, nil]
end

@doc """
rule_task: A named rule whose refusal asks for its own task.

    rule_task(:r, present(:a), :t) #=> [:lc_rule, :r, [:present, :a], :t]
"""
def rule_task(name, pred, task)
  [:lc_rule, name, pred, task]
end

@doc """
guard: The guard for a capability: its rules, all of which must hold, and the task
a refusing rule asks for when it names none (nil: no task).

    guard(:use, [], nil) #=> [:lc_guard, :use, [], nil]
"""
def guard(capability, rules, task)
  [:lc_guard, capability, as_list(rules), task]
end

@doc """
valid_for: A permit lives at most `duration` from its issue: the renewal cadence.

    valid_for(3600) #=> [:valid_for, 3600]
"""
def valid_for(duration)
  [:valid_for, duration]
end

@doc """
counted: The device counts one unit of `field` per use, so the permit carries how many
uses remain.

    counted(:uses) #=> [:counted, :uses]
"""
def counted(field)
  [:counted, field]
end

@doc """
permit: A capability enforced away from the engine, by a device, gets a permit. Its
limits are derived from the capability's guard.

    permit(:use, [valid_for(60)]) #=> [:lc_permit, :use, [[:valid_for, 60]]]
"""
def permit(capability, terms)
  [:lc_permit, capability, as_list(terms)]
end

@doc """
permit_log: An issued permit for `capability` is logged as `event`: the definition gains
the event (its keys are the permit's limits) and a no-op :stay row from every
non-terminal state. lc_permit_event renders a permit as the event.

    permit_log(:use, :permitted) #=> [:lc_permit_log, :use, :permitted]
"""
def permit_log(capability, event)
  [:lc_permit_log, capability, event]
end

@doc """
permit_count_key: The payload key a logged permit carries a counted field's remaining uses
under: "<field>_left".

    permit_count_key(:uses) #=> "uses_left"
"""
def permit_count_key(field)
  "#{text(field)}_left"
end

# ── links ──────────────────────────────────────────────────────────────────

@doc """
link: This lifecycle's records may carry links of kind `role`, each naming an
entity of lifecycle `target`. Declared here, folded nowhere: it is for what
reads the log (joins across lifecycles).

    link(:batch, :lot) #=> [:lc_link, :batch, :lot]
"""
def link(role, target)
  [:lc_link, role, target]
end

# ── spans ──────────────────────────────────────────────────────────────────

@doc """
span: A span: the time from an entity's first entry into state `from` to its
first entry into state `to` after that, a duration that matters on its own
(an order's fryer-to-mouth). `limit` is the longest it should take, on the
caller's clock, or nil for none. Declared here, folded nowhere, like a link:
it is for what reads the log (anaritikusu generates a view per span).

    span(:cook, :fried, :served, 300) #=> [:lc_span, :cook, :fried, :served, 300]
"""
def span(name, from, to, limit)
  [:lc_span, name, from, to, limit]
end

@doc """
span_name: A declared span's parts, as lc_d_spans returns them: [name, from, to, limit].

    span_name([:cook, :fried, :served, 300]) #=> :cook
"""
def span_name(s)
  s[0]
end

@doc """
span_from: The state a declared span starts at.

    span_from([:cook, :fried, :served, 300]) #=> :fried
"""
def span_from(s)
  s[1]
end

@doc """
span_to: The state a declared span ends at.

    span_to([:cook, :fried, :served, 300]) #=> :served
"""
def span_to(s)
  s[2]
end

@doc """
span_limit: The longest a declared span should take, or nil for none.

    span_limit([:cook, :fried, :served, 300]) #=> 300
"""
def span_limit(s)
  s[3]
end

# ── reading clauses ────────────────────────────────────────────────────────

@doc """
flat: A clause is a list headed by a keyword; anything else is a list of clauses
(as lc_on_each and lc_gate return), flattened.

    flat([start(:a), [states([:a]), [terminals([:a])]]]) #=> [[:lc_start, :a], [:lc_states, [:a]], [:lc_terminals, [:a]]]
"""
def flat(clauses)
  flat_map(as_list(clauses), flat_one)
end

@doc """
flat_one: One element of a clause list as clauses: a keyword-headed list is itself,
any other list is flattened, and anything else is a :lc_not_a_clause finding.

    flat_one(start(:a)) #=> [[:lc_start, :a]]
    flat_one(7) #=> [[:lc_not_a_clause, 7]]
"""
def flat_one(c)
  if list?(c) and is_empty(c) == false and keyword?(first(c))
    [c]
  elsif list?(c)
    flat(c)
  else
    [[:lc_not_a_clause, c]]
  end
end

@doc """
tagged: The clauses of a flat clause list that carry `tag`, in order.

    tagged([start(:a), states([:a]), start(:b)], :lc_start) #=> [[:lc_start, :a], [:lc_start, :b]]
"""
def tagged(flat, tag)
  filter_where(flat, first, tag)
end

@doc """
known_tags: Every clause tag a definition may hold; any other is a :bad_clause.

    size(known_tags) #=> 12
"""
def known_tags()
  %i[
    lc_start
    lc_states
    lc_terminals
    lc_rests
    lc_field
    lc_event
    lc_edge
    lc_guard
    lc_permit
    lc_permit_log
    lc_link
    lc_span
  ]
end

@doc """
parse: The parsed form, which lc_define seals as the definition once it validates:
[tag, name, flat, states, starts, terminals, rests, fields, events, edges,
guards, permits, links, permit_logs, spans]. fields are [name, initial];
events are [name, keys]; links are [role, target]; permit_logs are
[capability, event]; spans are [name, from, to, limit].
A permit log's event and rows are added to events and edges here, before
validation, so they are checked like any the author wrote.

    parse(:c, [states([:a]), start(:a)])[3] #=> [:a]
"""
def parse(name, clauses)
  flat = isshou::raifusaikuru::flat(clauses)
  states = flat_map(tagged(flat, :lc_states), (c) -> c[1])
  starts = map((c) -> c[1], tagged(flat, :lc_start))
  terminals = flat_map(tagged(flat, :lc_terminals), (c) -> c[1])
  rests = flat_map(tagged(flat, :lc_rests), (c) -> c[1])
  fields = map((c) -> [c[1], c[2]], tagged(flat, :lc_field))
  permits = tagged(flat, :lc_permit)
  logs = map((c) -> [c[1], c[2]], tagged(flat, :lc_permit_log))
  open = filter((s) -> contains(terminals, s) == false, unique(states))
  events = concat_lists(
    map((c) -> [c[1], c[2]], tagged(flat, :lc_event)),
    map((l) -> [l[1], permit_log_keys(permits, first(l))], logs)
  )
  edges = concat_lists(
    tagged(flat, :lc_edge),
    flat_map(logs, (l) -> map((s) -> [:lc_edge, s, l[1], s, [], nil], open))
  )
  links = map((c) -> [c[1], c[2]], tagged(flat, :lc_link))
  spans = map((c) -> [c[1], c[2], c[3], c[4]], tagged(flat, :lc_span))
  [
    :lc_parsed,
    name,
    flat,
    states,
    starts,
    terminals,
    rests,
    fields,
    events,
    edges,
    tagged(flat, :lc_guard),
    permits,
    links,
    logs,
    spans
  ]
end

@doc """
permit_log_keys: The payload keys of a logged permit for `capability`: subject, not_after,
basis, and one per counted field of its lc_permit (none when it has none).

    permit_log_keys([permit(:use, [counted(:uses)])], :use) #=> [:subject, :not_after, :basis, "uses_left"]
"""
def permit_log_keys(permits, capability)
  pm = find_first((p) -> p[1] == capability, permits)
  counted = if pm.nil?
    []
  else
    map(
      (t) -> t[1],
      filter((t) -> list?(t) and first(t) == :counted, as_list(pm[2]))
    )
  end
  concat_lists(%i[subject not_after basis], map(permit_count_key, counted))
end

@doc """
d_name: A definition's name.

    d_name(example_consumable) #=> :consumable
"""
def d_name(d)
  d[1]
end

@doc """
d_flat: A definition's clauses, flattened.

    first(d_flat(example_consumable)) #=> [:lc_states, %i[sealed open spent discarded]]
"""
def d_flat(d)
  d[2]
end

@doc """
d_states: A definition's declared states, in declaration order.

    d_states(example_consumable) #=> %i[sealed open spent discarded]
"""
def d_states(d)
  d[3]
end

@doc """
d_starts: Every start a definition declares; a sound one has exactly one.

    d_starts(example_consumable) #=> [:sealed]
"""
def d_starts(d)
  d[4]
end

@doc """
d_start: The state a new entity of the definition starts in.

    d_start(example_consumable) #=> :sealed
"""
def d_start(d)
  first(d[4])
end

@doc """
d_terminals: A definition's terminal states.

    d_terminals(example_consumable) #=> %i[spent discarded]
"""
def d_terminals(d)
  d[5]
end

@doc """
d_rests: A definition's resting states that are not terminals.

    d_rests(example_consumable) #=> []
"""
def d_rests(d)
  d[6]
end

@doc """
d_fields: A definition's fields, [name, initial], in declaration order.

    first(d_fields(example_consumable)) #=> [:uses, 0]
"""
def d_fields(d)
  d[7]
end

@doc """
d_names: The names of the declarations in slot `i` of a definition: the first of each.

    d_names([0, [[:a, 1], [:b, 2]]], 1) #=> [:a, :b]
"""
def d_names(d, i)
  map((x) -> first(x), d[i])
end

@doc """
d_field_names: The names of a definition's fields.

    d_field_names(example_consumable) #=> %i[uses opened_at quality read_at]
"""
def d_field_names(d)
  d_names(d, 7)
end

@doc """
d_events: A definition's events, [name, keys], in declaration order.

    d_events(example_consumable)[2] #=> [:reading, [:value]]
"""
def d_events(d)
  d[8]
end

@doc """
d_event_names: The names of a definition's events.

    d_event_names(example_consumable) #=> %i[open use reading finish discard]
"""
def d_event_names(d)
  d_names(d, 8)
end

@doc """
d_edges: A definition's transition rows, [:lc_edge, from, event, to, effects, capability].

    first(d_edges(example_consumable)) #=> [:lc_edge, :sealed, :open, :open, [[:stamp, :opened_at]], nil]
"""
def d_edges(d)
  d[9]
end

@doc """
d_guards: A definition's guard clauses.

    size(d_guards(example_consumable)) #=> 1
"""
def d_guards(d)
  d[10]
end

@doc """
d_capabilities: The capabilities a definition guards.

    d_capabilities(example_consumable) #=> [:use]
"""
def d_capabilities(d)
  map((g) -> g[1], d[10])
end

@doc """
d_permits: A definition's permit clauses.

    first(d_permits(example_consumable))[1] #=> :use
"""
def d_permits(d)
  d[11]
end

@doc """
d_links: The declared links, [role, target], in declaration order.

    d_links(example_consumable) #=> []
"""
def d_links(d)
  d[12]
end

@doc """
d_permit_logs: The permit logs, [capability, event], in declaration order.

    d_permit_logs(example_consumable) #=> []
"""
def d_permit_logs(d)
  d[13]
end

@doc """
d_spans: The declared spans, [name, from, to, limit], in declaration order.

    d_spans(example_consumable) #=> []
"""
def d_spans(d)
  d[14]
end

# ── validation: every finding, as data ─────────────────────────────────────

@doc """
problem_kinds: Every kind of problem the builder reports. Closed: lc_problem refuses any
other, and a test row exercises each.

    first(problem_kinds) #=> :bad_name
"""
def problem_kinds()
  %i[
    bad_name
    bad_clause
    bad_gate
    no_states
    duplicate_state
    reserved_name
    duplicate_field
    duplicate_event
    duplicate_key
    no_start
    many_starts
    unknown_state
    unknown_event
    unknown_field
    unknown_payload
    bad_effect
    duplicate_edge
    unknown_capability
    terminal_has_exit
    trap
    unreachable
    no_end
    cannot_converge
    duplicate_guard
    empty_guard
    bad_rule
    duplicate_rule
    bad_predicate
    bad_task
    duplicate_permit
    bad_permit
    unbounded_permit
    unbounded_count
    permit_needs_conjunction
    duplicate_permit_log
    duplicate_link
    duplicate_span
    bad_span
  ]
end

@doc """
problem: One finding, [kind, why]. A kind outside problem_kinds is an internal error,
raised as :raifusaikuru_internal.

    problem(:trap, "state :a has no exit") #=> [:trap, "state :a has no exit"]
"""
def problem(kind, why)
  if contains(problem_kinds, kind) == false
    raise(:raifusaikuru_internal, "unlisted problem kind #{show(kind)}")
  end
  [kind, why]
end

@doc """
problem_kind: A problem's kind, one of lc_problem_kinds().

    problem_kind([:trap, "state :a has no exit"]) #=> :trap
"""
def problem_kind(p)
  first(p)
end

@doc """
problem_why: A problem's explanation, naming what is wrong and where.

    problem_why([:trap, "state :a has no exit"]) #=> "state :a has no exit"
"""
def problem_why(p)
  p[1]
end

@doc """
problem_text: A problem as one line: its kind, a colon, its explanation.

    problem_text([:trap, "state :a has no exit"]) #=> "trap: state :a has no exit"
"""
def problem_text(p)
  "#{to_s(first(p))}: #{p[1]}"
end

@doc """
dupes: Every value that occurs more than once, once each, in first-seen order.

    dupes(%i[a b a c b a]) #=> %i[a b]
"""
def dupes(xs)
  unique(filter((x) -> count_of(xs, x) > 1, xs))
end

@doc """
int_at_least?: True when `x` is an integer no smaller than `low`.

    int_at_least?(3, 1) #=> true
"""
def int_at_least?(x, low)
  integer?(x) and x >= low
end

@doc """
positive_int?: True when `x` is an integer of at least 1.

    positive_int?(1) #=> true
    positive_int?(0) #=> false
"""
def positive_int?(x)
  int_at_least?(x, 1)
end

@doc """
problems: Why a definition would be refused: a list of [kind, why], empty when it is
sound. lc_define throws exactly these.

    problems(:base, example_base) #=> []
"""
def problems(name, clauses)
  check(parse(name, clauses))
end

@doc """
check: find unreachable states, duplicates and bad guards.

    check(parse(:base, example_base)) #=> []
"""
def check(p)
  as_list(
    flatten1(
      [
        pb_shape(p),
        pb_names(p),
        pb_start(p),
        pb_edges(p),
        pb_graph(p),
        pb_guards(p),
        pb_permits(p),
        pb_permit_logs(p),
        pb_links(p),
        pb_spans(p)
      ]
    )
  )
end

@doc """
pb_spans: A span names two declared states, `to` reachable from `from`, with a limit
that is a positive whole duration or nil; one row per name.

    map(problem_kind, pb_spans(parse(:c, [states(%i[a b]), span(:s, :a, :a, nil)]))) #=> [:bad_span]
"""
def pb_spans(p)
  spans = d_spans(p)
  dup = map(
    fn(n)
      problem(:duplicate_span, "span #{show(n)} is declared more than once")
    end,
    dupes(map(span_name, spans))
  )
  concat_lists(flat_map(spans, (s) -> pb_span(p, s)), dup)
end

@doc """
pb_span: The problems of one span: a name that is not a name, an undeclared state, a
limit that is not a positive whole duration, a span from a state to itself, or
one whose end no event reaches from its start.

    p = parse(:c, [states(%i[a b]), on(:a, :go, :b, [])])
    pb_span(p, [:s, :a, :b, 60]) #=> []
    map(problem_kind, pb_span(p, [:s, :b, :a, 0])) #=> %i[bad_span bad_span]
"""
def pb_span(p, s)
  where = "span #{show(span_name(s))}"
  states = d_states(p)
  from = span_from(s)
  to = span_to(s)
  named = if name?(span_name(s)) and name?(from) and name?(to)
    []
  else
    [
      problem(
        :bad_name,
        "lc_span(#{show(span_name(s))}, #{show(from)}, #{show(to)}, …) takes a name and two states, each a name"
      )
    ]
  end
  known = concat_lists(
    pb_state(from, states, where),
    pb_state(to, states, where)
  )
  limit = if span_limit(s).nil? or positive_int?(span_limit(s))
    []
  else
    [
      problem(
        :bad_span,
        "#{where}: its limit is a positive whole duration or nil, not #{show(span_limit(s))}"
      )
    ]
  end
  shape = if is_empty(known) == false
    []
  elsif from == to
    [
      problem(
        :bad_span,
        "#{where} starts and ends in #{show(from)}; a span runs between two states"
      )
    ]
  elsif contains(
      forward(
        map((e) -> [e[1], e[3]], d_edges(p)),
        [from],
        size(unique(states))
      ),
      to
    ) == false
    [
      problem(
        :bad_span,
        "#{where}: no events lead from #{show(from)} to #{show(to)}, so it could never end"
      )
    ]
  else
    []
  end
  flatten1([named, known, limit, shape])
end

@doc """
pb_permit_logs: A permit log names a capability that has an lc_permit, once.

    map(problem_kind, pb_permit_logs(parse(:c, [permit_log(:fly, :flown)]))) #=> [:unknown_capability]
"""
def pb_permit_logs(p)
  logs = d_permit_logs(p)
  caps = map((pm) -> pm[1], d_permits(p))
  bad = map(
    fn(l)
      problem(
        :bad_name,
        "lc_permit_log(#{show(first(l))}, #{show(l[1])}) takes a capability and an event, each a name"
      )
    end,
    filter((l) -> (name?(first(l)) and name?(l[1])) == false, logs)
  )
  unknown = map(
    fn(l)
      problem(
        :unknown_capability,
        "lc_permit_log(#{show(first(l))}, …): no lc_permit declares #{show(first(l))}, and a logged permit's keys are its limits"
      )
    end,
    filter((l) -> name?(first(l)) and contains(caps, first(l)) == false, logs)
  )
  dup = map(
    fn(c)
      problem(
        :duplicate_permit_log,
        "capability #{show(c)} has more than one lc_permit_log"
      )
    end,
    dupes(map((l) -> first(l), logs))
  )
  flatten1([bad, unknown, dup])
end

@doc """
pb_links: A link names a role and a target lifecycle, one row per role.

    map(problem_kind, pb_links(parse(:c, [link(:batch, :lot), link(:batch, :bin)]))) #=> [:duplicate_link]
"""
def pb_links(p)
  links = d_links(p)
  bad = map(
    fn(l)
      problem(
        :bad_name,
        "lc_link(#{show(first(l))}, #{show(l[1])}) takes a role and a target lifecycle, each a name"
      )
    end,
    filter((l) -> (name?(first(l)) and name?(l[1])) == false, links)
  )
  dup = map(
    fn(r)
      problem(
        :duplicate_link,
        "role #{show(r)} is declared by more than one lc_link"
      )
    end,
    dupes(map((l) -> first(l), links))
  )
  concat_lists(bad, dup)
end

@doc """
pb_shape: The problems of a definition's outline: a name that is not a keyword or a
string, and every clause whose tag is not a known one.

    map(problem_kind, pb_shape(parse("c", [7]))) #=> [:bad_clause]
    map(problem_kind, pb_shape(parse(3, []))) #=> [:bad_name]
"""
def pb_shape(p)
  bad = filter((c) -> contains(known_tags, first(c)) == false, d_flat(p))
  named = if name?(d_name(p))
    []
  else
    [
      problem(
        :bad_name,
        "a lifecycle is named by a keyword or a string, not #{show(d_name(p))}"
      )
    ]
  end
  concat_lists(named, map(pb_clause, bad))
end

@doc """
pb_clause: The problem one unknown clause makes: a gated clause that is not a row, a
value that is not a clause, or an unknown tag.

    problem_kind(pb_clause([:lc_misgated, :use, :lc_start])) #=> :bad_gate
    problem_kind(pb_clause([:lc_wat])) #=> :bad_clause
"""
def pb_clause(c)
  if first(c) == :lc_misgated
    problem(
      :bad_gate,
      "lc_gate(#{show(c[1])}, …) wraps a #{show(c[2])} clause; only lc_on rows can be gated"
    )
  elsif first(c) == :lc_not_a_clause
    problem(
      :bad_clause,
      "#{show(c[1])} is not a clause; build clauses with lc_states, lc_on, lc_guard and the rest"
    )
  else
    problem(:bad_clause, "unknown clause #{show(first(c))}")
  end
end

@doc """
pb_names: The problems of the declared names: no states, a value that is not a name,
:stay as a state, and a state, field, event or payload key declared twice.

    map(problem_kind, pb_names(parse(:c, []))) #=> [:no_states]
    map(problem_kind, pb_names(parse(:c, [states(%i[a a stay])]))) #=> %i[reserved_name duplicate_state]
"""
def pb_names(p)
  states = d_states(p)
  fields = d_field_names(p)
  events = d_event_names(p)
  empty = if is_empty(states)
    [problem(:no_states, "a lifecycle declares its states with lc_states")]
  else
    []
  end
  bad = map(
    fn(x)
      problem(
        :bad_name,
        "#{show(x)} is not a name; states, fields, events and payload keys are keywords or strings"
      )
    end,
    filter(
      (x) -> name?(x) == false,
      flatten1([states, fields, events, flat_map(d_events(p), (e) -> e[1])])
    )
  )
  reserved = map(
    fn(_x)
      problem(
        :reserved_name,
        ":stay means a self-loop in lc_on and cannot name a state"
      )
    end,
    filter((x) -> x == :stay, states)
  )
  ds = map(
    fn(x)
      problem(:duplicate_state, "state #{show(x)} is declared more than once")
    end,
    dupes(states)
  )
  df = map(
    fn(x)
      problem(:duplicate_field, "field #{show(x)} is declared more than once")
    end,
    dupes(fields)
  )
  de = map(
    fn(x)
      problem(:duplicate_event, "event #{show(x)} is declared more than once")
    end,
    dupes(events)
  )
  dk = flat_map(
    d_events(p),
    fn(e)
      map(
        fn(k)
          problem(
            :duplicate_key,
            "event #{show(first(e))} lists payload key #{show(k)} twice"
          )
        end,
        dupes(e[1])
      )
    end
  )
  flatten1([empty, bad, reserved, ds, df, de, dk])
end

@doc """
pb_declared: No problem when `x` is among `declared`; otherwise one problem of `kind`
saying, at `where`, that `x` is not a declared `what`.

    pb_declared(:a, [:a], "here", :unknown_state, "state") #=> []
"""
def pb_declared(x, declared, where, kind, what)
  if contains(declared, x)
    []
  else
    [problem(kind, "#{where}: #{show(x)} is not a declared #{what}")]
  end
end

@doc """
pb_state: No problem when `s` is a declared state, else one :unknown_state at `where`.

    pb_state(:a, [:a], "lc_start") #=> []
    pb_state(:b, [:a], "lc_start") #=> [[:unknown_state, "lc_start: :b is not a declared state"]]
"""
def pb_state(s, states, where)
  pb_declared(s, states, where, :unknown_state, "state")
end

@doc """
pb_start: The problems of a definition's start, terminals and rests: no start, more
than one, or any of them naming an undeclared state.

    map(problem_kind, pb_start(parse(:c, [states([:a])]))) #=> [:no_start]
    map(problem_kind, pb_start(parse(:c, [states([:a]), start(:a), terminals([:z])]))) #=> [:unknown_state]
"""
def pb_start(p)
  states = d_states(p)
  starts = d_starts(p)
  n = size(starts)
  count = if n == 0
    [problem(:no_start, "a lifecycle names its first state with lc_start")]
  elsif n > 1
    [
      problem(
        :many_starts,
        "lc_start appears #{to_s(n)} times; an entity starts in exactly one state"
      )
    ]
  else
    pb_state(first(starts), states, "lc_start")
  end
  flatten1(
    [
      count,
      flat_map(d_terminals(p), (s) -> pb_state(s, states, "lc_terminals")),
      flat_map(d_rests(p), (s) -> pb_state(s, states, "lc_rests"))
    ]
  )
end

@doc """
edge_where: Where a row is, as a problem names it.

    edge_where(on(:a, :go, :b, [])) #=> "the row :a --:go--> :b"
"""
def edge_where(e)
  "the row #{show(e[1])} --#{show(e[2])}--> #{show(e[3])}"
end

@doc """
pb_edges: The problems of every row, and of two rows leaving one state on one event.

    p = parse(:c, [states(%i[a b]), event(:go, []), on(:a, :go, :b, []), on(:a, :go, :a, [])])
    map(problem_kind, pb_edges(p)) #=> [:duplicate_edge]
"""
def pb_edges(p)
  _states = d_states(p)
  edges = d_edges(p)
  keys = map((e) -> [e[1], e[2]], edges)
  dup = map(
    fn(k)
      problem(
        :duplicate_edge,
        "two rows leave #{show(first(k))} on #{show(k[1])}; the fold would be ambiguous"
      )
    end,
    dupes(keys)
  )
  concat_lists(flat_map(edges, (e) -> pb_edge(p, e)), dup)
end

@doc """
pb_edge: The problems of one row: an undeclared state at either end, an undeclared
event, a bad effect, or a gate no guard declares.

    p = parse(:c, [states([:a]), event(:go, [])])
    map(problem_kind, pb_edge(p, on(:a, :go, :z, []))) #=> [:unknown_state]
    map(problem_kind, pb_edge(p, on(:a, :fly, :a, []))) #=> [:unknown_event]
"""
def pb_edge(p, e)
  where = edge_where(e)
  states = d_states(p)
  from = if contains(states, e[1])
    []
  else
    [
      problem(
        :unknown_state,
        "#{where}: a transition from #{show(e[1])}, which is not a declared state"
      )
    ]
  end
  to = pb_state(e[3], states, where)
  declared = contains(d_event_names(p), e[2])
  ev = if declared
    []
  else
    [problem(:unknown_event, "#{where}: #{show(e[2])} is not a declared event")]
  end
  keys = if declared
    lookup(d_events(p), e[2])
  else
    []
  end
  effects = flat_map(e[4], (f) -> pb_effect(p, f, keys, where))
  gate = if e[5].nil? or contains(d_capabilities(p), e[5])
    []
  else
    [
      problem(
        :unknown_capability,
        "#{where} is gated by #{show(e[5])}, which no lc_guard declares"
      )
    ]
  end
  flatten1([from, to, ev, effects, gate])
end

@doc """
pb_field: No problem when `f` is a declared field, else one :unknown_field at `where`.

    pb_field(:uses, [:uses], "here") #=> []
    map(problem_kind, pb_field(:age, [:uses], "here")) #=> [:unknown_field]
"""
def pb_field(f, fields, where)
  pb_declared(f, fields, where, :unknown_field, "field")
end

@doc """
pb_effect: The problems of one effect on a row whose event carries `keys`: not an
effect, an undeclared field, an undeclared payload key, a counter whose
initial value is not a number, or an lc_add of something not a number.

    p = parse(:c, [field(:uses, 0), field(:note, nil)])
    pb_effect(p, add(:uses, 1), [], "here") #=> []
    map(problem_kind, pb_effect(p, add(:note, 1), [], "here")) #=> [:bad_effect]
    map(problem_kind, pb_effect(p, set(:uses, :n), [], "here")) #=> [:unknown_payload]
"""
def pb_effect(p, eff, keys, where)
  if list?(eff) == false or
      size(eff) != 3 and size(eff) != 2 or
      contains(%i[set put add add_key stamp], first(eff)) == false
    [
      problem(
        :bad_effect,
        "#{where}: #{show(eff)} is not an effect; use lc_set, lc_put, lc_add, lc_add_from or lc_stamp"
      )
    ]
  else
    op = first(eff)
    f = eff[1]
    known = pb_field(f, d_field_names(p), where)
    key = if (op == :set or op == :add_key) and contains(keys, eff[2]) == false
      [
        problem(
          :unknown_payload,
          "#{where}: reads payload key #{show(eff[2])}, which the event does not declare"
        )
      ]
    else
      []
    end
    counter = if (op == :add or op == :add_key) and
        is_empty(known) and
        number?(lookup(d_fields(p), f)) == false
      [
        problem(
          :bad_effect,
          "#{where}: adds to #{show(f)}, whose initial value is not a number; a counter starts at a number"
        )
      ]
    else
      []
    end
    amount = if op == :add and number?(eff[2]) == false
      [
        problem(
          :bad_effect,
          "#{where}: lc_add takes a number, not #{show(eff[2])}"
        )
      ]
    else
      []
    end
    flatten1([known, key, counter, amount])
  end
end

@doc """
forward: States reachable from `seeds` along `pairs` ([from, to]), within n rounds.

    forward([[:a, :b], [:b, :c]], [:a], 3) #=> %i[a b c]
"""
def forward(pairs, seeds, n)
  reach(pairs, seeds, n, 0, 1)
end

@doc """
backward: States that can reach `goals` along `pairs`, within n rounds.

    backward([[:a, :b], [:b, :c]], [:c], 3) #=> %i[c b a]
"""
def backward(pairs, goals, n)
  reach(pairs, goals, n, 1, 0)
end

@doc """
reach: `seeds` and every state reached from them within n rounds, stepping from slot
`from` of a pair to slot `to`.

    reach([[:a, :b]], [:a], 1, 0, 1) #=> [:a, :b]
"""
def reach(pairs, seeds, n, from, to)
  reduce(
    fn(acc, _i)
      union(
        acc,
        map((pr) -> pr[to], filter((pr) -> contains(acc, pr[from]), pairs))
      )
    end,
    seeds,
    range(0, n)
  )
end

@doc """
pb_graph: The graph problems of a definition whose states and one start are sound;
none until they are, so a broken outline is not reported twice.

    pb_graph(parse(:c, example_consumable_clauses)) #=> []
    map(problem_kind, pb_graph(parse(:c, [states(%i[a b]), start(:a), terminals([:b])]))) #=> %i[trap unreachable]
"""
def pb_graph(p)
  states = unique(d_states(p))
  if is_empty(states) or
      size(d_starts(p)) != 1 or
      contains(states, d_start(p)) == false
    []
  else
    pb_graph_of(p, states)
  end
end

@doc """
pb_graph_of: The graph problems over `states`: a terminal with an exit, a trap, a state
the start cannot reach, and a state from which no terminal or resting state
can be reached (or no end at all).

    p = parse(:c, [states(%i[a b]), start(:a), on(:a, :go, :b, []), on(:b, :go, :a, [])])
    map(problem_kind, pb_graph_of(p, %i[a b])) #=> [:no_end]
"""
def pb_graph_of(p, states)
  terminals = d_terminals(p)
  sound = filter(
    (e) -> contains(states, e[1]) and contains(states, e[3]),
    d_edges(p)
  )
  pairs = map((e) -> [e[1], e[3]], sound)
  exits = (s) -> filter((e) -> e[1] == s, d_edges(p))
  leaky = map(
    fn(s)
      problem(
        :terminal_has_exit,
        "terminal #{show(s)} has a row leaving it; a terminal accepts no event"
      )
    end,
    filter((s) -> is_empty(exits(s)) == false, unique(terminals))
  )
  traps = filter(
    (s) -> is_empty(exits(s)) and contains(terminals, s) == false,
    states
  )
  trapped = map(
    fn(s)
      problem(:trap, "#{show(s)} has no row leaving it and is not a terminal")
    end,
    traps
  )
  n = size(states)
  reached = forward(pairs, [d_start(p)], n)
  unreached = map(
    fn(s)
      problem(
        :unreachable,
        "no events lead from #{show(d_start(p))} to #{show(s)}"
      )
    end,
    filter((s) -> contains(reached, s) == false, states)
  )
  ends = union(terminals, d_rests(p))
  converge = if is_empty(ends)
    [
      problem(
        :no_end,
        "no state is a terminal (lc_terminals) or a resting state (lc_rests), so nothing can converge"
      )
    ]
  else
    home = backward(pairs, ends, n)
    map(
      fn(s)
        problem(
          :cannot_converge,
          "from #{show(s)} no terminal or resting state can be reached"
        )
      end,
      filter(
        (s) -> contains(home, s) == false and contains(traps, s) == false,
        states
      )
    )
  end
  flatten1([leaky, trapped, unreached, converge])
end

@doc """
pb_pred: The problems of a predicate at `where`, over the declared `fields` and
`states`: not a predicate, an unknown op, a malformed atom, an undeclared field
or state, or an empty lc_all or lc_any.

    pb_pred(below(:n, 3), [:n], [:a], "here") #=> []
    map(problem_kind, pb_pred(below(:m, 3), [:n], [:a], "here")) #=> [:unknown_field]
    map(problem_kind, pb_pred([], [:n], [:a], "here")) #=> [:bad_predicate]
"""
def pb_pred(pr, fields, states, where)
  if list?(pr) == false or is_empty(pr)
    [
      problem(
        :bad_predicate,
        "#{where}: #{show(pr)} is not a predicate; build one with lc_below, lc_fresh, lc_all and the rest"
      )
    ]
  else
    op = first(pr)
    if contains(%i[lt le gt ge], op)
      if number?(pr[2])
        pb_field(pr[1], fields, where)
      else
        concat_lists(
          pb_field(pr[1], fields, where),
          [
            problem(
              :bad_predicate,
              "#{where}: compares #{show(pr[1])} with #{show(pr[2])}, which is not a number"
            )
          ]
        )
      end
    elsif op == :eq or op == :present
      pb_field(pr[1], fields, where)
    elsif op == :age_lt
      if positive_int?(pr[2])
        pb_field(pr[1], fields, where)
      else
        concat_lists(
          pb_field(pr[1], fields, where),
          [
            problem(
              :bad_predicate,
              "#{where}: lc_fresh takes a positive whole duration, not #{show(pr[2])}"
            )
          ]
        )
      end
    elsif op == :in
      if is_empty(pr[1])
        [problem(:bad_predicate, "#{where}: lc_in_phase([]) holds of nothing")]
      else
        flat_map(pr[1], (s) -> pb_state(s, states, where))
      end
    elsif op == :all or op == :any
      if is_empty(pr[1])
        [
          problem(
            :bad_predicate,
            "#{where}: an empty #{show(op)} is a vacuous truth; state the condition"
          )
        ]
      else
        flat_map(pr[1], (c) -> pb_pred(c, fields, states, where))
      end
    elsif op == :not
      pb_pred(pr[1], fields, states, where)
    else
      [problem(:bad_predicate, "#{where}: unknown predicate #{show(op)}")]
    end
  end
end

@doc """
pb_task: The problems of a task spec at `where`: not a task, not named by a name, no
evidence kind or one that is not a name, or an escalation that is not a
positive whole duration.

    pb_task(task(:t, [:scan], 60), "here") #=> []
    map(problem_kind, pb_task(task(:t, [], 0), "here")) #=> %i[bad_task bad_task]
"""
def pb_task(t, where)
  if list?(t) == false or size(t) != 4 or first(t) != :lc_task
    [
      problem(
        :bad_task,
        "#{where}: #{show(t)} is not a task; build one with lc_task"
      )
    ]
  else
    name = if name?(t[1])
      []
    else
      [problem(:bad_task, "#{where}: a task is named by a keyword or a string")]
    end
    evidence = if is_empty(t[2]) or
        is_empty(filter((k) -> name?(k) == false, t[2])) == false
      [
        problem(
          :bad_task,
          "#{where}: task #{show(t[1])} needs at least one evidence kind, each a name; evidence is what closes a task"
        )
      ]
    else
      []
    end
    escalate = if positive_int?(t[3])
      []
    else
      [
        problem(
          :bad_task,
          "#{where}: task #{show(t[1])} escalates after a positive whole duration, not #{show(t[3])}"
        )
      ]
    end
    flatten1([name, evidence, escalate])
  end
end

@doc """
rule?: Whether a value has the shape lc_rule and lc_rule_task build.

    rule?(rule(:r, present(:a))) #=> true
    rule?(present(:a)) #=> false
"""
def rule?(r)
  headed?(r, 4, :lc_rule)
end

@doc """
pb_guards: The problems of every guard, and of two guards for one capability.

    map(problem_kind, pb_guards(parse(:c, [guard(:g, [rule(:r, present(:a))], nil), guard(:g, [rule(:r, present(:a))], nil)]))) #=> %i[unknown_field unknown_field duplicate_guard]
"""
def pb_guards(p)
  caps = d_capabilities(p)
  dup = map(
    fn(c)
      problem(
        :duplicate_guard,
        "capability #{show(c)} has more than one lc_guard"
      )
    end,
    dupes(caps)
  )
  concat_lists(flat_map(d_guards(p), (g) -> pb_guard(p, g)), dup)
end

@doc """
pb_guard: The problems of one guard: a capability that is not a name, no rules, a
value that is not a rule, two rules with one name, and the problems of each
rule's predicate and task and of the guard's default task.

    p = parse(:c, [field(:n, 0)])
    pb_guard(p, guard(:g, [rule(:r, below(:n, 3))], nil)) #=> []
    map(problem_kind, pb_guard(p, guard(:g, [], nil))) #=> [:empty_guard]
"""
def pb_guard(p, g)
  cap = g[1]
  where = "guard #{show(cap)}"
  rules = g[2]
  named = if name?(cap)
    []
  else
    [
      problem(
        :bad_name,
        "#{where}: a capability is named by a keyword or a string"
      )
    ]
  end
  empty = if is_empty(rules)
    [
      problem(
        :empty_guard,
        "#{where} has no rules, so it would allow anything; state at least one"
      )
    ]
  else
    []
  end
  shaped = filter(rule?, rules)
  malformed = map(
    fn(r)
      problem(
        :bad_rule,
        "#{where}: #{show(r)} is not a rule; build one with lc_rule or lc_rule_task"
      )
    end,
    filter((r) -> rule?(r) == false, rules)
  )
  dup = map(
    (n) -> problem(:duplicate_rule, "#{where}: two rules are named #{show(n)}"),
    dupes(map((r) -> r[1], shaped))
  )
  preds = flat_map(
    shaped,
    fn(r)
      pb_pred(
        r[2],
        d_field_names(p),
        d_states(p),
        "#{where}, rule #{show(r[1])}"
      )
    end
  )
  tasks = flat_map(
    filter((r) -> r[3] != nil, shaped),
    (r) -> pb_task(r[3], "#{where}, rule #{show(r[1])}")
  )
  default = if g[3].nil?
    []
  else
    pb_task(g[3], where)
  end
  flatten1([named, empty, malformed, dup, preds, tasks, default])
end

@doc """
conjuncts: The atoms in positive conjunctive position: each rule's predicate, and
inside lc_all, recursively. Only these may bound a permit.

    conjuncts(all([below(:n, 3), any([present(:a)])])) #=> [[:lt, :n, 3], [:any, [[:present, :a]]]]
"""
def conjuncts(pr)
  if first(pr) == :all
    flat_map(pr[1], conjuncts)
  else
    [pr]
  end
end

@doc """
atoms: Every atom of a predicate, beneath lc_all, lc_any and lc_not alike.

    atoms(all([below(:n, 3), lc_not(present(:a))])) #=> [[:lt, :n, 3], [:present, :a]]
"""
def atoms(pr)
  op = first(pr)
  if op == :all or op == :any
    flat_map(pr[1], atoms)
  elsif op == :not
    atoms(pr[1])
  else
    [pr]
  end
end

@doc """
hidden_atoms: Every atom beneath an lc_any or an lc_not.

    hidden_atoms(all([below(:n, 3), lc_not(present(:a))])) #=> [[:present, :a]]
"""
def hidden_atoms(pr)
  op = first(pr)
  if op == :all
    flat_map(pr[1], hidden_atoms)
  elsif op == :any or op == :not
    atoms(pr)
  else
    []
  end
end

@doc """
guard_pred: The guard as one predicate: the conjunction of its rules.

    guard_pred(guard(:g, [rule(:r, below(:n, 3))], nil)) #=> [:all, [[:lt, :n, 3]]]
"""
def guard_pred(g)
  all(map((r) -> r[2], g[2]))
end

@doc """
drifts?: An atom that changes as a permit is used: any lc_fresh (time passes), or a
comparison over a counted field (uses accumulate).

    drifts?(below(:uses, 3), [:uses]) #=> true
    drifts?(below(:quality, 3), [:uses]) #=> false
"""
def drifts?(atom, counted)
  first(atom) == :age_lt or
    contains(%i[lt le gt ge eq], first(atom)) and contains(counted, atom[1])
end

@doc """
pb_permits: The problems of every permit, and of two permits for one capability.

    pb_permits(parse(:c, example_consumable_clauses)) #=> []
    map(problem_kind, pb_permits(parse(:c, [permit(:fly, [valid_for(60)])]))) #=> [:unknown_capability]
"""
def pb_permits(p)
  caps = map((pm) -> pm[1], d_permits(p))
  dup = map(
    fn(c)
      problem(
        :duplicate_permit,
        "capability #{show(c)} has more than one lc_permit"
      )
    end,
    dupes(caps)
  )
  concat_lists(flat_map(d_permits(p), (pm) -> pb_permit(p, pm)), dup)
end

@doc """
pb_permit: The problems of one permit: a capability no guard declares, else the
problems of its terms once its guard is itself sound.

    p = parse(:c, example_consumable_clauses)
    pb_permit(p, permit(:use, [valid_for(60)])) #=> []
"""
def pb_permit(p, pm)
  cap = pm[1]
  where = "permit #{show(cap)}"
  g = find_first((x) -> x[1] == cap, d_guards(p))
  if g.nil?
    [
      problem(
        :unknown_capability,
        "#{where}: no lc_guard declares #{show(cap)}, and a permit's limits come from its guard"
      )
    ]
  elsif is_empty(g[2]) == false and is_empty(pb_guard(p, g))
    pb_permit_terms(p, pm, g, where)
  else
    []
  end
end

@doc """
pb_permit_terms: The problems of a permit's terms against its guard: a term that is not
valid_for or a declared counted field, no time bound from the guard or a
valid_for, a counted field no below, at-most or equal conjunct bounds, and a
drifting atom hidden under lc_any or lc_not.

    p = parse(:c, example_consumable_clauses)
    pb_permit_terms(p, permit(:use, [valid_for(60), counted(:uses)]), guard_for(p, :use), "permit :use") #=> []
    map(problem_kind, pb_permit_terms(p, permit(:use, [counted(:quality), counted(:read_at)]), guard_for(p, :use), "permit :use")) #=> [:unbounded_count]
"""
def pb_permit_terms(p, pm, g, where)
  terms = pm[2]
  counted = map(
    (t) -> t[1],
    filter((t) -> list?(t) and first(t) == :counted, terms)
  )
  bad = map(
    fn(t)
      problem(
        :bad_permit,
        "#{where}: #{show(t)} is not a permit term; use lc_valid_for(positive whole duration) or lc_counted(field)"
      )
    end,
    filter((t) -> permit_term?(t, d_field_names(p)) == false, terms)
  )
  conj = conjuncts(guard_pred(g))
  timed = is_empty(filter((t) -> list?(t) and first(t) == :valid_for, terms)) ==
    false or is_empty(filter((a) -> first(a) == :age_lt, conj)) == false
  unbounded = if timed
    []
  else
    [
      problem(
        :unbounded_permit,
        "#{where} would never expire: add lc_valid_for, or an lc_fresh rule to its guard"
      )
    ]
  end
  uncounted = map(
    fn(f)
      problem(
        :unbounded_count,
        "#{where} counts #{show(f)}, but no lc_below, lc_at_most or lc_equals rule of its guard bounds it"
      )
    end,
    filter(
      fn(f)
        is_empty(
          filter((a) -> contains(%i[lt le eq], first(a)) and a[1] == f, conj)
        )
      end,
      counted
    )
  )
  hidden = filter((a) -> drifts?(a, counted), hidden_atoms(guard_pred(g)))
  loose = map(
    fn(a)
      problem(
        :permit_needs_conjunction,
        "#{where}: #{pred_text(a)} sits under lc_any or lc_not, so no sound limit follows from it; make it a rule of its own"
      )
    end,
    hidden
  )
  flatten1([bad, unbounded, uncounted, loose])
end

@doc """
permit_term?: Whether `t` is a sound permit term over `fields`: a valid_for of a
positive whole duration, or a counted field the definition declares.

    permit_term?(valid_for(60), []) #=> true
    permit_term?(counted(:uses), [:quality]) #=> false
"""
def permit_term?(t, fields)
  if list?(t) and size(t) == 2 and first(t) == :valid_for
    positive_int?(t[1])
  elsif list?(t) and size(t) == 2 and first(t) == :counted
    contains(fields, t[1])
  else
    false
  end
end

# ── the definition ─────────────────────────────────────────────────────────

# waive B0013: `define` is a builtin raifusaikuru also uses, so the prefix stays; isshou::raifusaikuru::define names it too
@doc """
lc_define: Build a lifecycle definition from clauses, or throw :raifusaikuru_definition
naming every problem. Only a built definition is accepted by the fold, the
guards and the permits.

    first(lc_define(:c, [states([:a]), start(:a), terminals([:a])])) #=> :lc_def
    (lc_define(:c, []) rescue :refused) #=> :refused
"""
def lc_define(name, clauses)
  p = parse(name, clauses)
  problems = check(p)
  if is_empty(problems) == false
    raise(
      :raifusaikuru_definition,
      "lifecycle #{show(name)} refused: #{join(map(problem_text, problems), "; ")}"
    )
  end
  cons(:lc_def, rest(p))
end

# waive B0013: `require` is a builtin raifusaikuru also uses, so the prefix stays; isshou::raifusaikuru::require names it too
@doc """
lc_require: `d` itself when it is a definition lc_define built; anything else is
refused as :raifusaikuru_use, so no unchecked definition reaches the fold.

    lc_require(example_consumable) == example_consumable #=> true
    (lc_require([:lc_parsed]) rescue :refused) #=> :refused
"""
def lc_require(d)
  if (list?(d) and is_empty(d) == false and first(d) == :lc_def) == false
    raise(
      :raifusaikuru_use,
      "not a built lifecycle definition; build it with lc_define, which validates it"
    )
  end
  d
end

@doc """
name: The definition's name.

    name(example_consumable) #=> :consumable
"""
def name(d)
  d_name(lc_require(d))
end

@doc """
edge_for: The row that event `event` takes from state `phase`, or nil when none does.

    edge_for(example_consumable, :sealed, :open)[3] #=> :open
    edge_for(example_consumable, :spent, :open) #=> nil
"""
def edge_for(d, phase, event)
  find_first((e) -> e[1] == phase and e[2] == event, d_edges(d))
end

@doc """
legal_events: The events accepted in a state, in declaration order: what an illegal
event's refusal names.

    legal_events(example_consumable, :sealed) #=> %i[open reading discard]
"""
def legal_events(d, phase)
  unique(map((e) -> e[2], filter((e) -> e[1] == phase, d_edges(lc_require(d)))))
end

@doc """
capability_row: The first row whose second slot is `capability`, or nil.

    capability_row([[:guard, :use, 1]], :use) #=> [:guard, :use, 1]
"""
def capability_row(rows, capability)
  find_first((r) -> r[1] == capability, rows)
end

@doc """
guard_for: The guard clause of `capability`, or nil when the definition guards none.

    guard_for(example_consumable, :use)[1] #=> :use
    guard_for(example_consumable, :fly) #=> nil
"""
def guard_for(d, capability)
  capability_row(d_guards(d), capability)
end

@doc """
permit_spec_for: The permit clause of `capability`, or nil when it has none.

    permit_spec_for(example_consumable, :use)[2] #=> [[:valid_for, 7200], [:counted, :uses]]
"""
def permit_spec_for(d, capability)
  capability_row(d_permits(d), capability)
end

# ── events ─────────────────────────────────────────────────────────────────

@doc """
ev: An event: its type, its time on the caller's clock, and its payload as
[key, value] pairs.

    ev(:reading, 30, [[:value, 7]]) #=> [:reading, 30, [[:value, 7]]]
"""
def ev(type, time, payload)
  [type, time, as_list(payload)]
end

@doc """
ev_type: An event's type.

    ev_type(ev(:reading, 30, [[:value, 7]])) #=> :reading
"""
def ev_type(ev)
  ev[0]
end

@doc """
ev_time: An event's time, on the caller's clock.

    ev_time(ev(:reading, 30, [[:value, 7]])) #=> 30
"""
def ev_time(ev)
  ev[1]
end

@doc """
ev_payload: An event's payload, as [key, value] pairs.

    ev_payload(ev(:reading, 30, [[:value, 7]])) #=> [[:value, 7]]
"""
def ev_payload(ev)
  as_list(ev[2])
end

@doc """
ev_get: A payload value, or nil when the key is absent.

    ev_get(ev(:reading, 30, [[:value, 7]]), :value) #=> 7
    ev_get(ev(:reading, 30, []), :value) #=> nil
"""
def ev_get(ev, key)
  lookup(ev_payload(ev), key)
end

@doc """
ev_has?: Whether the event's payload carries `key`, even with a nil value.

    ev_has?(ev(:reading, 30, [[:value, nil]]), :value) #=> true
    ev_has?(ev(:reading, 30, []), :value) #=> false
"""
def ev_has?(ev, key)
  find_first((kv) -> first(kv) == key, ev_payload(ev)) != nil
end

# ── state and the fold ─────────────────────────────────────────────────────

@doc """
initial: The state before any event. A state is
[:lc_state, phase, fields, seq, as_of, refused, breaches]; fields are
[name, value] pairs in declaration order, so two states compare with ==.

    initial(example_consumable)[1] #=> :sealed
"""
def initial(d)
  lc_require(d)
  [:lc_state, d_start(d), d_fields(d), 0, nil, [], []]
end

@doc """
phase: The state the entity is in.

    phase(state_of(example_consumable, [ev(:open, 10, [])])) #=> :open
"""
def phase(s)
  s[1]
end

@doc """
fields: Every field as [name, value], in declaration order.

    fields(initial(example_consumable)) #=> [[:uses, 0], [:opened_at, nil], [:quality, nil], [:read_at, nil]]
"""
def fields(s)
  s[2]
end

@doc """
value: A field's value, or nil.

    value(state_of(example_consumable, [ev(:open, 10, [])]), :opened_at) #=> 10
"""
def value(s, field)
  lookup(fields(s), field)
end

@doc """
seq: How many events the state has consumed, accepted or refused: the position
the next event will have, and a permit's basis.

    seq(state_of(example_consumable, [ev(:open, 10, []), ev(:fly, 11, [])])) #=> 2
"""
def seq(s)
  s[3]
end

@doc """
as_of: The time of the last applied event, or nil before any.

    as_of(initial(example_consumable)) #=> nil
    as_of(state_of(example_consumable, [ev(:open, 10, [])])) #=> 10
"""
def as_of(s)
  s[4]
end

@doc """
refused: Refused events, oldest first: [position, type, kind, detail]. kind is
:unknown_event, :no_edge (detail: the legal events), :missing_payload
(detail: the missing keys), :bad_payload (detail: the key whose value is not
a number) or :bad_field (detail: the counter that holds no number).

    refused(state_of(example_consumable, [ev(:fly, 5, [])])) #=> [[0, :fly, :unknown_event, nil]]
"""
def refused(s)
  s[5]
end

@doc """
refusal_position: The position in the log of a refused event.

    refusal_position([0, :fly, :unknown_event, nil]) #=> 0
"""
def refusal_position(r)
  r[0]
end

@doc """
refusal_type: The type of a refused event.

    refusal_type([0, :fly, :unknown_event, nil]) #=> :fly
"""
def refusal_type(r)
  r[1]
end

@doc """
refusal_kind: Why an event was refused, one of the kinds `refused` lists.

    refusal_kind([0, :fly, :unknown_event, nil]) #=> :unknown_event
"""
def refusal_kind(r)
  r[2]
end

@doc """
refusal_detail: What a refusal names: the legal events, the missing keys, or the key or
field that holds no number.

    refusal_detail([1, :open, :no_edge, %i[use finish]]) #=> %i[use finish]
"""
def refusal_detail(r)
  r[3]
end

@doc """
breaches: Breaches, oldest first: [position, type, capability, refusing rules]. A gated
event that happened while its guard refused: it was applied, and this is the
record of it.

    breaches(initial(example_consumable)) #=> []
"""
def breaches(s)
  s[6]
end

@doc """
breach_position: The position in the log of a breaching event.

    breach_position([6, :use, :use, [:quality_ok]]) #=> 6
"""
def breach_position(b)
  b[0]
end

@doc """
breach_type: The type of a breaching event.

    breach_type([6, :use, :use, [:quality_ok]]) #=> :use
"""
def breach_type(b)
  b[1]
end

@doc """
breach_capability: The capability a breaching event used.

    breach_capability([6, :use, :use, [:quality_ok]]) #=> :use
"""
def breach_capability(b)
  b[2]
end

@doc """
breach_rules: The rules that refused when the breaching event happened.

    breach_rules([6, :use, :use, [:quality_ok]]) #=> [:quality_ok]
"""
def breach_rules(b)
  b[3]
end

@doc """
judge: The one decision about an event in a state:
  [:ok, row]              accepted
  [:breach, row, verdict] a gated row whose guard refuses
  [:refuse, kind, detail].

    judge(example_consumable, initial(example_consumable), ev(:fly, 1, [])) #=> [:refuse, :unknown_event, nil]
    first(judge(example_consumable, initial(example_consumable), ev(:open, 1, []))) #=> :ok
"""
def judge(d, s, ev)
  t = ev_type(ev)
  if contains(d_event_names(d), t) == false
    [:refuse, :unknown_event, nil]
  else
    e = edge_for(d, phase(s), t)
    if e.nil?
      [:refuse, :no_edge, legal_events(d, phase(s))]
    else
      judge_row(d, s, ev, e)
    end
  end
end

@doc """
judge_row: The decision for an event that has a row: refused for a missing payload
key, a non-numeric added value or a non-numeric counter, accepted when the row
is ungated, and a breach when its guard refuses at the event's time.

    judge_row(example_consumable, initial(example_consumable), ev(:reading, 1, []), edge_for(example_consumable, :sealed, :reading)) #=> [:refuse, :missing_payload, [:value]]
"""
def judge_row(d, s, ev, e)
  missing = filter(
    (k) -> ev_has?(ev, k) == false,
    as_list(lookup(d_events(d), ev_type(ev)))
  )
  effects = e[4]
  bad_keys = filter(
    (k) -> number?(ev_get(ev, k)) == false,
    map((f) -> f[2], filter((f) -> first(f) == :add_key, effects))
  )
  bad_fields = filter(
    (f) -> number?(value(s, f)) == false,
    map(
      (f) -> f[1],
      filter((f) -> first(f) == :add or first(f) == :add_key, effects)
    )
  )
  if is_empty(missing) == false
    [:refuse, :missing_payload, missing]
  elsif is_empty(bad_keys) == false
    [:refuse, :bad_payload, first(bad_keys)]
  elsif is_empty(bad_fields) == false
    [:refuse, :bad_field, first(bad_fields)]
  elsif e[5].nil?
    [:ok, e]
  else
    v = allowed(d, s, e[5], ev_time(ev))
    if is_allowed(v)
      [:ok, e]
    else
      [:breach, e, v]
    end
  end
end

@doc """
put_field: The [name, value] pairs with field `f` set to `v`, order kept.

    put_field([[:a, 1], [:b, 2]], :b, 5) #=> [[:a, 1], [:b, 5]]
"""
def put_field(fs, f, v)
  map((kv) -> put_pair(kv, f, v), fs)
end

@doc """
put_pair: One [name, value] pair, its value replaced by `v` when its name is `f`.

    put_pair([:a, 1], :a, 9) #=> [:a, 9]
    put_pair([:b, 1], :a, 9) #=> [:b, 1]
"""
def put_pair(kv, f, v)
  if first(kv) == f
    [f, v]
  else
    kv
  end
end

@doc """
effect: The fields after one effect of an accepted event: set from a payload key, put a
constant, add a constant or a payload value, or stamp the event's time.

    effect([[:uses, 2]], add(:uses, 1), ev(:use, 5, [])) #=> [[:uses, 3]]
    effect([[:at, nil]], stamp(:at), ev(:open, 5, [])) #=> [[:at, 5]]
"""
def effect(fs, eff, ev)
  op = first(eff)
  f = eff[1]
  if op == :set
    put_field(fs, f, ev_get(ev, eff[2]))
  elsif op == :put
    put_field(fs, f, eff[2])
  elsif op == :add
    put_field(fs, f, lookup(fs, f) + eff[2])
  elsif op == :add_key
    put_field(fs, f, lookup(fs, f) + ev_get(ev, eff[2]))
  else
    put_field(fs, f, ev_time(ev))
  end
end

@doc """
step: One event, folded. Total: a refused event is recorded and changes nothing
else, and every event advances the sequence.

    phase(step(example_consumable, initial(example_consumable), ev(:open, 1, []))) #=> :open
"""
def step(d, s, ev)
  lc_require(d)
  lc_apply(d, s, ev, judge(d, s, ev))
end

# waive B0013: `apply` is a builtin raifusaikuru also uses, so the prefix stays; isshou::raifusaikuru::apply names it too
@doc """
lc_apply: The state after an event lc_judge has already decided: the second half of
lc_step, shared with lc_admit_step so a judgement is made once.

    refused(lc_apply(example_consumable, initial(example_consumable), ev(:fly, 1, []), [:refuse, :unknown_event, nil])) #=> [[0, :fly, :unknown_event, nil]]
"""
def lc_apply(_d, s, ev, j)
  pos = seq(s)
  if first(j) == :refuse
    [
      :lc_state,
      phase(s),
      isshou::raifusaikuru::fields(s),
      pos + 1,
      as_of(s),
      push(refused(s), [pos, ev_type(ev), j[1], j[2]]),
      isshou::raifusaikuru::breaches(s)
    ]
  else
    e = j[1]
    fields = reduce(
      (fs, eff) -> effect(fs, eff, ev),
      isshou::raifusaikuru::fields(s),
      e[4]
    )
    breaches = if first(j) == :breach
      push(
        isshou::raifusaikuru::breaches(s),
        [pos, ev_type(ev), e[5], refused_rules(j[2])]
      )
    else
      isshou::raifusaikuru::breaches(s)
    end
    [:lc_state, e[3], fields, pos + 1, ev_time(ev), refused(s), breaches]
  end
end

@doc """
resume: Continue a fold from a state.

    phase(resume(example_consumable, state_of(example_consumable, [ev(:open, 1, [])]), [ev(:finish, 2, [])])) #=> :spent
"""
def resume(d, s, events)
  lc_require(d)
  reduce((acc, ev) -> step(d, acc, ev), s, as_list(events))
end

@doc """
state_of: Replay an entity's events, in order, into its state.

    value(state_of(example_consumable, [ev(:open, 1, []), ev(:use, 2, []), ev(:use, 3, [])]), :uses) #=> 2
"""
def state_of(d, events)
  resume(d, initial(d), events)
end

@doc """
admit: Would `ev` be accepted in `s`? [:admit], or [:reject, kind, detail] with the
fold's refusal kinds plus :guard (detail: the verdict) for a gated event
whose guard refuses at the event's time. Check before appending: the fold
would record the same event as refused, or as a breach.

    admit(example_consumable, initial(example_consumable), ev(:open, 1, [])) #=> [:admit]
    admit(example_consumable, initial(example_consumable), ev(:finish, 1, [])) #=> [:reject, :no_edge, %i[open reading discard]]
"""
def admit(d, s, ev)
  lc_require(d)
  admission(judge(d, s, ev))
end

@doc """
admission: lc_judge's decision as lc_admit answers it.

    admission([:refuse, :unknown_event, nil]) #=> [:reject, :unknown_event, nil]
"""
def admission(j)
  if first(j) == :ok
    [:admit]
  elsif first(j) == :breach
    [:reject, :guard, j[2]]
  else
    [:reject, j[1], j[2]]
  end
end

@doc """
admit_step: lc_admit and lc_step from ONE judgement: [admission, state after]. An
appender that checks an event and then folds it needs both, and the
judgement is most of a step's cost (nisshi's profile, 2026-09-24: lc_admit
181 µs and lc_step 202 µs on one event, each judging it).

    first(admit_step(example_consumable, initial(example_consumable), ev(:open, 1, []))) #=> [:admit]
"""
def admit_step(d, s, ev)
  lc_require(d)
  j = judge(d, s, ev)
  [admission(j), lc_apply(d, s, ev, j)]
end

@doc """
admitted?: Whether an admission accepts the event.

    admitted?([:admit]) #=> true
    admitted?([:reject, :unknown_event, nil]) #=> false
"""
def admitted?(a)
  first(a) == :admit
end

@doc """
reject_kind: Why an admission rejects: a fold refusal kind, or :guard.

    reject_kind([:reject, :unknown_event, nil]) #=> :unknown_event
"""
def reject_kind(a)
  a[1]
end

@doc """
reject_detail: What a rejection names: the refusal's detail, or the guard's verdict.

    reject_detail([:reject, :no_edge, [:open]]) #=> [:open]
"""
def reject_detail(a)
  a[2]
end

# ── guards ─────────────────────────────────────────────────────────────────

@doc """
k: A boolean as a three-valued truth: :yes or :no.

    k(true) #=> :yes
    k(false) #=> :no
"""
def k(b)
  if b
    :yes
  else
    :no
  end
end

@doc """
k_absorb: Three-valued fold: `dominant` if any value is, else :unknown if any is,
else `otherwise`.

    k_absorb(%i[yes unknown], :no, :yes) #=> :unknown
"""
def k_absorb(vs, dominant, otherwise)
  if contains(vs, dominant)
    dominant
  elsif contains(vs, :unknown)
    :unknown
  else
    otherwise
  end
end

@doc """
k_and: Three-valued and: :no if any value is, else :unknown if any is, else :yes.

    k_and(%i[yes yes]) #=> :yes
    k_and(%i[yes unknown no]) #=> :no
"""
def k_and(vs)
  k_absorb(vs, :no, :yes)
end

@doc """
k_or: Three-valued or: :yes if any value is, else :unknown if any is, else :no.

    k_or(%i[no unknown]) #=> :unknown
    k_or(%i[no yes]) #=> :yes
"""
def k_or(vs)
  k_absorb(vs, :yes, :no)
end

@doc """
k_not: Three-valued not: :yes and :no swap, and :unknown stays unknown.

    k_not(:yes) #=> :no
    k_not(:unknown) #=> :unknown
"""
def k_not(v)
  if v == :yes
    :no
  elsif v == :no
    :yes
  else
    :unknown
  end
end

# waive B0013: `compare` is a builtin raifusaikuru also uses, so the prefix stays; isshou::raifusaikuru::compare names it too
@doc """
lc_compare: A numeric comparison named by a predicate's op: :lt, :le, :gt, else :ge.

    lc_compare(:lt, 3, 4) #=> true
    lc_compare(:ge, 3, 4) #=> false
"""
def lc_compare(op, v, limit)
  if op == :lt
    v < limit
  elsif op == :le
    v <= limit
  elsif op == :gt
    v > limit
  else
    v >= limit
  end
end

# waive B0013: `eval` is a builtin raifusaikuru also uses, so the prefix stays; isshou::raifusaikuru::eval names it too
@doc """
lc_eval: A predicate over a state at time `now`: :yes, :no or :unknown. A comparison
over an absent or non-numeric field is :unknown, never :yes or :no.

    lc_eval(below(:uses, 40), initial(example_consumable), 0) #=> :yes
    lc_eval(below(:quality, 24), initial(example_consumable), 0) #=> :unknown
"""
def lc_eval(pr, s, now)
  op = first(pr)
  if contains(%i[lt le gt ge], op)
    v = value(s, pr[1])
    if number?(v)
      k(lc_compare(op, v, pr[2]))
    else
      :unknown
    end
  elsif op == :eq
    v = value(s, pr[1])
    if v.nil?
      :unknown
    else
      k(v == pr[2])
    end
  elsif op == :present
    k(value(s, pr[1]) != nil)
  elsif op == :age_lt
    v = value(s, pr[1])
    if number?(v) and number?(now)
      k(now - v < pr[2])
    else
      :unknown
    end
  elsif op == :in
    k(contains(pr[1], phase(s)))
  elsif op == :all
    k_and(map((c) -> lc_eval(c, s, now), pr[1]))
  elsif op == :any
    k_or(map((c) -> lc_eval(c, s, now), pr[1]))
  else
    k_not(lc_eval(pr[1], s, now))
  end
end

@doc """
task_or: The task a refusing rule asks for: its own, else the guard's `default`.

    task_or(rule(:r, present(:a)), :fallback) #=> :fallback
    task_or(rule_task(:r, present(:a), :own), :fallback) #=> :own
"""
def task_or(rule, default)
  if rule[3].nil?
    default
  else
    rule[3]
  end
end

@doc """
allowed: Is `capability` allowed in `s` at time `now`? The verdict is data:
  [:allowed, capability]
  [:refused, capability, reasons, tasks]
reasons: [rule, status, predicate, observed, now, phase] for each refusing
rule, in the guard's order; status is :no, or :unknown when a field it reads
is absent. tasks: the task specs those rules ask for, once per name. An
undeclared capability is refused, never allowed.

    allowed(example_consumable, state_of(example_consumable, [ev(:open, 0, []), ev(:reading, 1, [[:value, 20]])]), :use, 10) #=> [:allowed, :use]
    first(allowed(example_consumable, initial(example_consumable), :fly, 10)) #=> :refused
"""
def allowed(d, s, capability, now)
  lc_require(d)
  g = guard_for(d, capability)
  if g.nil?
    [
      :refused,
      capability,
      [[:undeclared_capability, :no, nil, [], now, phase(s)]],
      []
    ]
  else
    judged = map((r) -> [r, lc_eval(r[2], s, now)], g[2])
    bad = filter((rv) -> rv[1] != :yes, judged)
    if is_empty(bad)
      [:allowed, capability]
    else
      reasons = map(
        fn(rv)
          [
            first(rv)[1],
            rv[1],
            first(rv)[2],
            observed(first(rv)[2], s),
            now,
            phase(s)
          ]
        end,
        bad
      )
      tasks = unique_by(
        (t) -> t[1],
        filter((t) -> t != nil, map((rv) -> task_or(first(rv), g[3]), bad))
      )
      [:refused, capability, reasons, tasks]
    end
  end
end

@doc """
is_allowed: Whether a verdict allows its capability.

    is_allowed([:allowed, :use]) #=> true
    is_allowed([:refused, :use, [], []]) #=> false
"""
def is_allowed(v)
  first(v) == :allowed
end

@doc """
verdict_capability: The capability a verdict is about.

    verdict_capability([:allowed, :use]) #=> :use
"""
def verdict_capability(v)
  v[1]
end

@doc """
refused_rules: The refusing rules' names, in the guard's order; [] when allowed.

    refused_rules(allowed(example_consumable, state_of(example_consumable, [ev(:open, 0, [])]), :use, 10)) #=> %i[reading_fresh quality_ok]
"""
def refused_rules(v)
  if is_allowed(v)
    []
  else
    map((r) -> first(r), v[2])
  end
end

@doc """
refused_rule: The rule that refused (the first, in the guard's order), or nil when allowed.

    refused_rule(allowed(example_consumable, initial(example_consumable), :use, 10)) #=> :is_open
"""
def refused_rule(v)
  first(refused_rules(v))
end

@doc """
verdict_tasks: The task specs a refusal asks for; [] when allowed.

    verdict_tasks([:allowed, :use]) #=> []
    map(task_name, verdict_tasks(allowed(example_consumable, state_of(example_consumable, [ev(:open, 0, [])]), :use, 10))) #=> %i[take_reading replace]
"""
def verdict_tasks(v)
  if is_allowed(v)
    []
  else
    v[3]
  end
end

@doc """
pred_fields: The fields a predicate reads, once each, in first-seen order.

    pred_fields(all([below(:uses, 3), present(:at), below(:uses, 9)])) #=> %i[uses at]
"""
def pred_fields(pr)
  op = first(pr)
  if op == :all or op == :any
    unique(flat_map(pr[1], pred_fields))
  elsif op == :not
    pred_fields(pr[1])
  elsif op == :in
    []
  else
    [pr[1]]
  end
end

@doc """
observed: The value in `s` of each field a predicate reads, as [field, value].

    observed(below(:uses, 3), initial(example_consumable)) #=> [[:uses, 0]]
"""
def observed(pr, s)
  map((f) -> [f, value(s, f)], pred_fields(pr))
end

@doc """
pred_has?: Whether a predicate holds an atom of op `target` anywhere inside it.

    pred_has?(all([present(:a), in_phase([:open])]), :in) #=> true
    pred_has?(present(:a), :age_lt) #=> false
"""
def pred_has?(pr, target)
  contains(map((a) -> first(a), atoms(pr)), target)
end

@doc """
pred_text: A predicate as words: "quality below 24".

    pred_text(below(:quality, 24)) #=> "quality below 24"
    pred_text(lc_not(present(:at))) #=> "not (at present)"
"""
def pred_text(pr)
  op = first(pr)
  if op == :lt
    "#{text(pr[1])} below #{show(pr[2])}"
  elsif op == :le
    "#{text(pr[1])} at most #{show(pr[2])}"
  elsif op == :gt
    "#{text(pr[1])} above #{show(pr[2])}"
  elsif op == :ge
    "#{text(pr[1])} at least #{show(pr[2])}"
  elsif op == :eq
    "#{text(pr[1])} equal to #{show(pr[2])}"
  elsif op == :present
    "#{text(pr[1])} present"
  elsif op == :age_lt
    "#{text(pr[1])} less than #{to_s(pr[2])} old"
  elsif op == :in
    "phase in [#{join(map(show, pr[1]), ", ")}]"
  elsif op == :all
    "all of (#{join(map(pred_text, pr[1]), "; ")})"
  elsif op == :any
    "any of (#{join(map(pred_text, pr[1]), "; ")})"
  else
    "not (#{pred_text(pr[1])})"
  end
end

@doc """
observed_text: One observed [field, value] as words, an absent value said as such.

    observed_text([:quality, 26]) #=> "quality = 26"
    observed_text([:quality, nil]) #=> "quality is absent"
"""
def observed_text(kv)
  if kv[1].nil?
    "#{text(first(kv))} is absent"
  else
    "#{text(first(kv))} = #{show(kv[1])}"
  end
end

@doc """
reason_text: One refusal reason as a sentence: the rule, what it needs, and what was
observed, with the phase or the clock when the predicate reads them.

    reason_text([:quality_ok, :no, below(:quality, 24), [[:quality, 26]], 10, :open]) #=> "quality_ok: needs quality below 24; quality = 26"
"""
def reason_text(r)
  if r[2].nil?
    "#{text(first(r))}: no guard declares this capability"
  else
    pr = r[2]
    phase = if pred_has?(pr, :in)
      ["phase = #{show(r[5])}"]
    else
      []
    end
    clock = if pred_has?(pr, :age_lt)
      ["now = #{to_s(r[4])}"]
    else
      []
    end
    seen = flatten1([map(observed_text, r[3]), phase, clock])
    "#{text(first(r))}: needs #{pred_text(pr)}; #{join(seen, ", ")}"
  end
end

@doc """
why: Each refusal as a sentence a person can act on:
"quality_ok: needs quality below 24; quality = 26". [] when allowed.

    why([:allowed, :use]) #=> []
"""
def why(v)
  if is_allowed(v)
    []
  else
    map(reason_text, v[2])
  end
end

# ── permits ────────────────────────────────────────────────────────────────

@doc """
min_known: The least of the values that are not nil, or nil when none is.

    min_known([nil, 7, 3]) #=> 3
    min_known([nil]) #=> nil
"""
def min_known(xs)
  known = filter((x) -> x != nil, xs)
  if is_empty(known)
    nil
  else
    reduce((a, b) -> min(a, b), first(known), rest(known))
  end
end

@doc """
time_bound: The moment the guard could first stop holding as time passes: the earliest
expiry of an lc_fresh conjunct (its field's time + its max age), or nil when
no conjunct ages. Read only on an allowed state, where every conjunct holds.

    d = example_consumable
    time_bound(guard_for(d, :use), state_of(d, example_log)) #=> 15400
"""
def time_bound(g, s)
  ages = filter((a) -> first(a) == :age_lt, conjuncts(guard_pred(g)))
  min_known(map((a) -> value(s, a[1]) + a[2], ages))
end

@doc """
count_bound: How many more uses (one unit of `field` each) keep every conjunct on it
true: below L allows ceil(L - v), at most L allows floor(L - v) + 1, equal
allows 1. nil when nothing bounds it.

    d = example_consumable
    count_bound(guard_for(d, :use), state_of(d, example_log), :uses) #=> 37
    count_bound(guard_for(d, :use), state_of(d, example_log), :opened_at) #=> nil
"""
def count_bound(g, s, field)
  v = value(s, field)
  atoms = filter(
    (a) -> contains(%i[lt le eq], first(a)) and a[1] == field,
    conjuncts(guard_pred(g))
  )
  min_known(map((a) -> uses_left(first(a), v, a[2]), atoms))
end

@doc """
uses_left: How many more uses of one unit each keep one conjunct true: below L allows
ceil(L - v), at most L allows floor(L - v) + 1, and equal allows 1.

    uses_left(:lt, 37, 40) #=> 3
    uses_left(:le, 37, 40) #=> 4
"""
def uses_left(op, v, limit)
  if op == :lt
    ceiling(limit - v)
  elsif op == :le
    floor(limit - v) + 1
  else
    1
  end
end

@doc """
permit_for: The permit for `capability` in `s` at `now`, as data:
  [:permit, lifecycle, capability, issued_at, not_after, counts, basis]
  [:no_permit, capability, why, detail]
counts: [field, remaining] for each lc_counted field; basis: lc_seq(s), the
state the limits were derived from. why: :no_permit_declared, :refused
(detail: the verdict), :unbounded or :unbounded_count (detail: the field).
The engine signs nothing; see lc_permit_payload.

    d = example_consumable
    permit_for(d, state_of(d, example_log), :use, 2400) #=> [:permit, :consumable, :use, 2400, 9600, [[:uses, 37]], 5]
    first(permit_for(d, initial(d), :use, 2400)) #=> :no_permit
"""
def permit_for(d, s, capability, now)
  lc_require(d)
  spec = permit_spec_for(d, capability)
  if spec.nil?
    [:no_permit, capability, :no_permit_declared, nil]
  else
    v = allowed(d, s, capability, now)
    if is_allowed(v)
      permit_limits(d, s, spec, now)
    else
      [:no_permit, capability, :refused, v]
    end
  end
end

@doc """
permit_limits: The permit an allowed state earns: not_after is the soonest of the
guard's time bound and each valid_for window, and each counted field carries
its count bound. No permit when nothing bounds the time or a count.

    d = example_consumable
    permit_limits(d, state_of(d, example_log), permit_spec_for(d, :use), 2400)[4] #=> 9600
"""
def permit_limits(d, s, spec, now)
  capability = spec[1]
  g = guard_for(d, capability)
  terms = spec[2]
  windows = map((t) -> now + t[1], filter((t) -> first(t) == :valid_for, terms))
  not_after = min_known(cons(time_bound(g, s), windows))
  counts = map(
    (t) -> [t[1], count_bound(g, s, t[1])],
    filter((t) -> first(t) == :counted, terms)
  )
  unbounded = filter((c) -> c[1].nil?, counts)
  if not_after.nil?
    [:no_permit, capability, :unbounded, nil]
  elsif is_empty(unbounded) == false
    [:no_permit, capability, :unbounded_count, first(first(unbounded))]
  else
    [:permit, d_name(d), capability, now, not_after, counts, seq(s)]
  end
end

@doc """
has_permit?: Whether permit_for answered a permit rather than :no_permit.

    has_permit?([:permit, :consumable, :use, 2400, 9600, [[:uses, 37]], 5]) #=> true
    has_permit?([:no_permit, :use, :no_permit_declared, nil]) #=> false
"""
def has_permit?(p)
  first(p) == :permit
end

@doc """
permit_lifecycle: The lifecycle a permit was issued under.

    permit_lifecycle([:permit, :consumable, :use, 2400, 9600, [[:uses, 37]], 5]) #=> :consumable
"""
def permit_lifecycle(p)
  p[1]
end

@doc """
permit_capability: The capability a permit grants.

    permit_capability([:permit, :consumable, :use, 2400, 9600, [[:uses, 37]], 5]) #=> :use
"""
def permit_capability(p)
  p[2]
end

@doc """
permit_issued_at: When a permit was issued, on the caller's clock.

    permit_issued_at([:permit, :consumable, :use, 2400, 9600, [[:uses, 37]], 5]) #=> 2400
"""
def permit_issued_at(p)
  p[3]
end

@doc """
permit_not_after: The last moment a permit is valid.

    permit_not_after([:permit, :consumable, :use, 2400, 9600, [[:uses, 37]], 5]) #=> 9600
"""
def permit_not_after(p)
  p[4]
end

@doc """
permit_counts: A permit's remaining counts, [field, remaining].

    permit_counts([:permit, :consumable, :use, 2400, 9600, [[:uses, 37]], 5]) #=> [[:uses, 37]]
"""
def permit_counts(p)
  p[5]
end

@doc """
permit_count: The remaining count of one counted field.

    permit_count([:permit, :consumable, :use, 2400, 9600, [[:uses, 37]], 5], :uses) #=> 37
"""
def permit_count(p, field)
  lookup(p[5], field)
end

@doc """
permit_basis: The sequence number of the state a permit's limits were derived from.

    permit_basis([:permit, :consumable, :use, 2400, 9600, [[:uses, 37]], 5]) #=> 5
"""
def permit_basis(p)
  p[6]
end

@doc """
no_permit_why: Why there is no permit (:no_permit_declared, :refused, :unbounded,
:unbounded_count), and its detail.

    no_permit_why([:no_permit, :use, :no_permit_declared, nil]) #=> :no_permit_declared
"""
def no_permit_why(p)
  p[2]
end

@doc """
no_permit_detail: What a missing permit names: the refusing verdict, or the unbounded field.

    no_permit_detail([:no_permit, :use, :unbounded_count, :uses]) #=> :uses
"""
def no_permit_detail(p)
  p[3]
end

@doc """
permit_payload: THE SIGNING SEAM. The canonical text of a permit issued to `subject` (the
device or entity that enforces it): one key=value per line in a fixed order,
for a signer to sign and a device to verify byte for byte. Signing belongs
to a crypto bidama; this engine depends on none.

    first(split(permit_payload([:permit, :consumable, :use, 2400, 9600, [[:uses, 37]], 5], :fryer), line_break)) #=> "raifusaikuru-permit/1"
"""
def permit_payload(p, subject)
  if has_permit?(p) == false
    raise(:raifusaikuru_use, "there is no permit to render: #{show(p[2])}")
  end
  head = [
    "raifusaikuru-permit/1",
    "lifecycle=#{text(p[1])}",
    "subject=#{text(subject)}",
    "capability=#{text(p[2])}",
    "issued_at=#{to_s(p[3])}",
    "not_after=#{to_s(p[4])}"
  ]
  counts = map((c) -> "count.#{text(first(c))}=#{to_s(c[1])}", p[5])
  lines = flatten1([head, counts, ["basis=#{to_s(p[6])}"]])
  if is_empty(filter((l) -> contains?(l, line_break), lines)) == false
    raise(
      :raifusaikuru_use,
      "a permit's names must not contain a newline: the payload is one key=value per line"
    )
  end
  join(lines, line_break)
end

@doc """
permit_event: The issuance of permit `p` to `subject` as the event the definition's
lc_permit_log declares: at the permit's issue time, with its limits as the
payload (subject as text, not_after, basis, and lc_permit_count_key(field)
per counted field). Throws :raifusaikuru_use when there is no permit or the
capability's issuance is not logged.

    d = lc_define(:c, push(example_consumable_clauses, permit_log(:use, :permitted)))
    ev_type(permit_event(d, [:permit, :c, :use, 2400, 9600, [[:uses, 37]], 5], :fryer)) #=> :permitted
"""
def permit_event(d, p, subject)
  lc_require(d)
  if has_permit?(p) == false
    raise(:raifusaikuru_use, "there is no permit to log: #{show(p[2])}")
  end
  log = find_first((l) -> first(l) == permit_capability(p), d_permit_logs(d))
  if log.nil?
    raise(
      :raifusaikuru_use,
      "capability #{show(permit_capability(p))} declares no lc_permit_log, so its permits are not logged"
    )
  end
  counts = map((c) -> [permit_count_key(first(c)), c[1]], permit_counts(p))
  ev(
    log[1],
    permit_issued_at(p),
    concat_lists(
      [
        [:subject, text(subject)],
        [:not_after, permit_not_after(p)],
        [:basis, permit_basis(p)]
      ],
      counts
    )
  )
end

# ── a worked example: a consumable ─────────────────────────────────────────

@doc """
example_consumable: A consumable, generic: sealed until opened, then used until spent or
discarded. A use needs the item open, a quality reading under 4 h old and
below 24, fewer than 40 uses, and under 72 h since opening. `use` is gated,
so a use while refused is recorded as a breach. A device enforcing `use`
holds a permit of at most 2 h that counts uses. Time is in seconds.

    phase(state_of(example_consumable, example_log)) #=> :open
"""
def example_consumable()
  lc_define(:consumable, example_consumable_clauses)
end

@doc """
example_consumable_clauses: The example's clauses, before lc_define: a consumer extends the example by
adding clauses (a permit log, a link) rather than restating it.

    first(example_consumable_clauses) #=> [:lc_states, %i[sealed open spent discarded]]
"""
def example_consumable_clauses()
  replace = task(:replace, %i[reading scan], minutes(20))
  rules = [
    rule_task(
      :is_open,
      in_phase([:open]),
      task(:open_one, [:scan], minutes(20))
    ),
    rule_task(
      :reading_fresh,
      fresh(:read_at, hours(4)),
      task(:take_reading, [:reading], minutes(20))
    ),
    rule(:quality_ok, below(:quality, 24)),
    rule(:uses_left, below(:uses, 40)),
    rule(:not_too_old, fresh(:opened_at, hours(72)))
  ]
  [
    states(%i[sealed open spent discarded]),
    start(:sealed),
    terminals(%i[spent discarded]),
    field(:uses, 0),
    field(:opened_at, nil),
    field(:quality, nil),
    field(:read_at, nil),
    event(:open, []),
    event(:use, []),
    event(:reading, [:value]),
    event(:finish, []),
    event(:discard, []),
    on(:sealed, :open, :open, [stamp(:opened_at)]),
    gate(:use, on(:open, :use, :stay, [add(:uses, 1)])),
    on_each(
      %i[sealed open],
      :reading,
      :stay,
      [set(:quality, :value), stamp(:read_at)]
    ),
    on(:open, :finish, :spent, []),
    on_each(%i[sealed open], :discard, :discarded, []),
    guard(:use, rules, replace),
    permit(:use, [valid_for(hours(2)), counted(:uses)])
  ]
end

@doc """
example_log: The example's log: a reading of 10 at 1000, opened at 2000, three uses.

    value(state_of(example_consumable, example_log), :uses) #=> 3
"""
def example_log()
  [
    ev(:reading, 1000, [[:value, 10]]),
    ev(:open, 2000, []),
    ev(:use, 2100, []),
    ev(:use, 2200, []),
    ev(:use, 2300, [])
  ]
end

# ── tests ──────────────────────────────────────────────────────────────────

test "the empty case: no events give the initial state, which may not be used"
  d = example_consumable
  s = state_of(d, [])
  assert s == initial(d)
  assert phase(s) == :sealed
  assert fields(s) ==
    [[:uses, 0], [:opened_at, nil], [:quality, nil], [:read_at, nil]]
  assert seq(s) == 0
  assert as_of(s).nil?
  assert is_empty(refused(s))
  assert is_empty(breaches(s))
  # Sealed, never read, never opened: every rule but the counter refuses, and
  # the three whose fields are absent are UNKNOWN, not passed.
  v = allowed(d, s, :use, 0)
  assert refused_rules(v) == %i[is_open reading_fresh quality_ok not_too_old]
  assert map((r) -> r[1], v[2]) == %i[no unknown unknown unknown]
  assert map(task_name, verdict_tasks(v)) == %i[open_one take_reading replace]
  assert no_permit_why(permit_for(d, s, :use, 0)) == :refused
end

test "an identity: replaying a state's own events reproduces it, and a fold resumes where it stopped"
  d = example_consumable
  log = example_log
  s = state_of(d, log)
  assert state_of(d, log) == s
  assert resume(d, s, []) == s
  assert map(
    (k) -> resume(d, state_of(d, take_n(log, k)), drop_n(log, k)) == s,
    range(0, size(log) + 1)
  ) == repeat(true, size(log) + 1)
  assert permit_for(d, s, :use, 3000) ==
    permit_for(d, state_of(d, log), :use, 3000)
end

test "a worked lifecycle, checked by hand"
  # Event by event, time in seconds (4 h = 14400, 72 h = 259200, 2 h = 7200):
  #   1000 reading 10  sealed -> sealed  quality 10, read_at 1000
  #   2000 open        sealed -> open    opened_at 2000
  #   2100 use         open -> open      the guard holds at 2100 (read 1100 s
  #                                      ago < 14400; 10 < 24; 0 < 40; opened
  #                                      100 s ago < 259200), so no breach; uses 1
  #   2200 use                           uses 2
  #   2300 use                           uses 3
  # Final: open, uses 3, opened_at 2000, quality 10, read_at 1000; 5 events
  # consumed, as of 2300.
  # Permit at 3000: not_after = min(1000 + 14400 = 15400, 2000 + 259200 =
  # 261200, 3000 + 7200 = 10200) = 10200; uses left 40 - 3 = 37.
  # Permit at 12000: min(15400, 261200, 19200) = 15400, the reading's expiry.
  # At 15400 the reading is exactly 4 h old: reading_fresh refuses and asks
  # for take_reading.
  d = example_consumable
  s = state_of(d, example_log)
  assert phase(s) == :open
  assert fields(s) ==
    [[:uses, 3], [:opened_at, 2000], [:quality, 10], [:read_at, 1000]]
  assert seq(s) == 5
  assert as_of(s) == 2300
  assert refused(s) == []
  assert breaches(s) == []
  assert is_allowed(allowed(d, s, :use, 3000))
  p = permit_for(d, s, :use, 3000)
  assert permit_not_after(p) == 10200
  assert permit_count(p, :uses) == 37
  assert permit_basis(p) == 5
  assert permit_not_after(permit_for(d, s, :use, 12000)) == 15400
  assert permit_payload(p, "device-7") ==
    join_lines(
      %w[
        raifusaikuru-permit/1
        lifecycle=consumable
        subject=device-7
        capability=use
        issued_at=3000
        not_after=10200
        count.uses=37
        basis=5
      ]
    )
  v = allowed(d, s, :use, 15400)
  assert refused_rule(v) == :reading_fresh
  assert map(task_name, verdict_tasks(v)) == [:take_reading]
  assert why(v) ==
    ["reading_fresh: needs read_at less than 14400 old; read_at = 1000, now = 15400"]
end

test "a control: a guard that must refuse, says why, names the task, and a use anyway is a breach"
  d = example_consumable
  s = state_of(d, push(example_log, ev(:reading, 4000, [[:value, 26]])))
  # quality 26 is not below 24; quality_ok names no task, so the guard's own
  # `replace` is asked for.
  v = allowed(d, s, :use, 4100)
  assert is_allowed(v) == false
  assert refused_rules(v) == [:quality_ok]
  assert why(v) == ["quality_ok: needs quality below 24; quality = 26"]
  t = first(verdict_tasks(v))
  assert task_name(t) == :replace
  assert task_evidence(t) == %i[reading scan]
  assert task_escalate_after(t) == 1200
  assert no_permit_why(permit_for(d, s, :use, 4100)) == :refused
  # Rejected before it is appended ...
  u = ev(:use, 4100, [])
  assert admit(d, s, u) == [:reject, :guard, v]
  # ... and if it happened anyway, the fold applies the fact and records the breach.
  s2 = step(d, s, u)
  assert value(s2, :uses) == 4
  assert breaches(s2) == [[6, :use, :use, [:quality_ok]]]
  # An undeclared capability is refused, never allowed.
  assert why(allowed(d, s, :fly, 0)) ==
    ["undeclared_capability: no guard declares this capability"]
end

test "a control: a definition with an undeclared state is refused when built"
  bad = [
    states(%i[a b]),
    start(:a),
    terminals([:b]),
    event(:go, []),
    on(:a, :go, :b, []),
    on(:b, :go, :c, [])
  ]
  kinds = map(problem_kind, problems(:bad, bad))
  assert contains(kinds, :unknown_state)
  assert error?(
    begin
      lc_define(:bad, bad)
    rescue e
      e
    end
  )
  # The same clauses with :c declared as a state still fail, now on the graph:
  # b is terminal yet has a row leaving it.
  assert contains(
    map(problem_kind, problems(:bad, push(bad, states([:c])))),
    :terminal_has_exit
  )
  # And an unbuilt definition is refused at use: the fold takes only what
  # lc_define sealed.
  assert error?(
    begin
      state_of(bad, [])
    rescue e
      e
    end
  )
end

@doc """
example_base: The sound base definition each row of example_problem_rows adds its
defect to.

    problems(:base, example_base) #=> []
"""
def example_base()
  [
    states(%i[a b]),
    start(:a),
    terminals([:b]),
    field(:n, 0),
    event(:go, []),
    event(:tick, [:k]),
    on(:a, :go, :b, []),
    on(:a, :tick, :stay, [add(:n, 1)]),
    guard(:g, [rule(:r, below(:n, 3))], nil)
  ]
end

@doc """
example_problem_rows: One row per problem kind: [defect, kind]. Each defect is added to
example_base, and the rows cover problem_kinds.

    example_problem_rows[1] #=> [[[:lc_misgated, :g, :lc_field]], :bad_gate]
"""
def example_problem_rows()
  [
    [[[:lc_frob, 1]], :bad_clause],
    [gate(:g, field(:z, 0)), :bad_gate],
    [states([7]), :bad_name],
    [states([:a]), :duplicate_state],
    [states([:stay]), :reserved_name],
    [field(:n, 1), :duplicate_field],
    [event(:go, []), :duplicate_event],
    [event(:e2, %i[x x]), :duplicate_key],
    [start(:b), :many_starts],
    [on(:x, :go, :b, []), :unknown_state],
    [on(:a, :fly, :b, []), :unknown_event],
    [guard(:h, [rule(:r, below(:nope, 1))], nil), :unknown_field],
    [[event(:e2, []), on(:a, :e2, :stay, [set(:n, :v)])], :unknown_payload],
    [[event(:e2, []), on(:a, :e2, :stay, [%i[frob n]])], :bad_effect],
    [on(:a, :go, :a, []), :duplicate_edge],
    [permit(:nope, [valid_for(60)]), :unknown_capability],
    [on(:b, :go, :a, []), :terminal_has_exit],
    [[states([:c]), event(:hop, []), on(:a, :hop, :c, [])], :trap],
    [[states([:c]), terminals([:c])], :unreachable],
    [
      [
        states(%i[c d]),
        event(:hop, []),
        on(:a, :hop, :c, []),
        on(:c, :hop, :d, []),
        on(:d, :go, :c, [])
      ],
      :cannot_converge
    ],
    [guard(:g, [rule(:r, present(:n))], nil), :duplicate_guard],
    [guard(:h, [], nil), :empty_guard],
    [guard(:h, [[:frob]], nil), :bad_rule],
    [
      guard(:h, [rule(:r, present(:n)), rule(:r, present(:n))], nil),
      :duplicate_rule
    ],
    [guard(:h, [rule(:r, all([]))], nil), :bad_predicate],
    [guard(:h, [rule_task(:r, present(:n), task(:t, [], 60))], nil), :bad_task],
    [
      [permit(:g, [valid_for(60)]), permit(:g, [valid_for(60)])],
      :duplicate_permit
    ],
    [permit(:g, [valid_for(0)]), :bad_permit],
    [permit(:g, []), :unbounded_permit],
    [
      [field(:m, 0), permit(:g, [valid_for(60), counted(:m)])],
      :unbounded_count
    ],
    [
      [
        field(:t, nil),
        guard(:h, [rule(:r, any([fresh(:t, 60), present(:t)]))], nil),
        permit(:h, [valid_for(60)])
      ],
      :permit_needs_conjunction
    ],
    [
      [
        permit(:g, [valid_for(60)]),
        permit_log(:g, :issued),
        permit_log(:g, :issued_again)
      ],
      :duplicate_permit_log
    ],
    [[link(:peer, :other), link(:peer, :another)], :duplicate_link],
    [[span(:s, :a, :b, nil), span(:s, :a, :b, 60)], :duplicate_span],
    [span(:s, :b, :a, nil), :bad_span]
  ]
end

test "every kind of bad definition is refused when built, one row per kind"
  assert problems(:base, example_base) == []
  rows = example_problem_rows
  missed = filter(
    fn(row)
      contains(
        map(problem_kind, problems(:base, push(example_base, first(row)))),
        row[1]
      ) == false
    end,
    rows
  )
  assert map((row) -> row[1], missed) == []
  # The three that cannot be added to a sound base are checked on their own.
  assert contains(map(problem_kind, problems(7, example_base)), :bad_name)
  assert contains(map(problem_kind, problems(:x, [start(:a)])), :no_states)
  assert contains(
    map(problem_kind, problems(:x, [states([:a]), terminals([:a])])),
    :no_start
  )
  assert contains(
    map(
      problem_kind,
      problems(
        :x,
        [
          states(%i[a b]),
          start(:a),
          event(:go, []),
          on(:a, :go, :b, []),
          on(:b, :go, :a, [])
        ]
      )
    ),
    :no_end
  )
  # The closed list, all of it exercised: a new kind without a row fails here.
  covered = unique(
    concat_lists(
      map((row) -> row[1], rows),
      %i[bad_name no_states no_start no_end]
    )
  )
  assert set_equal(covered, problem_kinds)
end

test "the fold records what it refuses and never throws"
  d = example_consumable
  s = state_of(d, example_log)
  s2 = resume(
    d,
    s,
    [
      ev(:open, 2400, []),
      ev(:fly, 2500, []),
      ev(:reading, 2600, []),
      ev(:discard, 2700, []),
      ev(:use, 2800, [])
    ]
  )
  assert refused(s2) ==
    [
      [5, :open, :no_edge, %i[use reading finish discard]],
      [6, :fly, :unknown_event, nil],
      [7, :reading, :missing_payload, [:value]],
      [9, :use, :no_edge, []]
    ]
  assert phase(s2) == :discarded
  assert value(s2, :uses) == 3
  assert seq(s2) == 10
  assert as_of(s2) == 2700
  # The same judgements, asked before appending.
  assert admit(d, s, ev(:open, 2400, [])) ==
    [:reject, :no_edge, %i[use reading finish discard]]
  assert admitted?(admit(d, s, ev(:use, 2400, [])))
  assert legal_events(d, :discarded) == []
end

test "lc_admit_step answers exactly as lc_admit and lc_step do, for admitted, refused and breaching events"
  d = example_consumable
  s = state_of(d, example_log)
  high = state_of(d, push(example_log, ev(:reading, 4000, [[:value, 26]])))
  cases = [
    [s, ev(:use, 2400, [])],
    [s, ev(:open, 2400, [])],
    [s, ev(:fly, 2400, [])],
    [s, ev(:reading, 2400, [])],
    [high, ev(:use, 4100, [])],
    [initial(d), ev(:reading, 10, [[:value, 3]])]
  ]
  assert map(
    fn(c)
      admit_step(d, first(c), c[1]) ==
        [admit(d, first(c), c[1]), step(d, first(c), c[1])]
    end,
    cases
  ) == repeat(true, size(cases))
  # The breach case is in the list: rejected by admission, applied by the step.
  b = admit_step(d, high, ev(:use, 4100, []))
  assert reject_kind(first(b)) == :guard
  assert size(breaches(b[1])) == 1
end

test "a logged permit is an event: a no-op in every non-terminal state, refused in a terminal one, rendered from the permit"
  # The empty case: a definition that logs nothing and links nothing.
  plain = example_consumable
  assert d_permit_logs(plain) == []
  assert d_links(plain) == []
  d = lc_define(
    :consumable,
    push(
      push(example_consumable_clauses, permit_log(:use, :permit)),
      link(:batch, :lot)
    )
  )
  assert d_permit_logs(d) == [%i[use permit]]
  assert d_links(d) == [%i[batch lot]]
  # The generated event's keys are the permit's limits, and the rows are the
  # two non-terminal states' self-loops.
  assert lookup(d_events(d), :permit) ==
    [:subject, :not_after, :basis, "uses_left"]
  assert map(
    (e) -> [e[1], e[3], e[4], e[5]],
    filter((e) -> e[2] == :permit, d_edges(d))
  ) == [[:sealed, :sealed, [], nil], [:open, :open, [], nil]]
  # A value checked by hand: the worked log's permit at 3000 (not_after 10200,
  # 37 uses left, basis 5, as the worked-lifecycle test computes).
  s = state_of(d, example_log)
  ev = permit_event(d, permit_for(d, s, :use, 3000), "device-7")
  assert ev ==
    isshou::raifusaikuru::ev(
      :permit,
      3000,
      [
        [:subject, "device-7"],
        [:not_after, 10200],
        [:basis, 5],
        ["uses_left", 37]
      ]
    )
  # The identity: logging it changes nothing but the sequence.
  s2 = step(d, s, ev)
  assert [phase(s2), fields(s2), refused(s2), breaches(s2), seq(s2)] ==
    [phase(s), fields(s), refused(s), breaches(s), seq(s) + 1]
  # Controls: a terminal entity cannot be issued one; a definition that does
  # not log the capability cannot render one; and a log needs a permit.
  spent = resume(d, s, [isshou::raifusaikuru::ev(:finish, 3100, [])])
  assert refusal_kind(
    last(
      refused(
        step(
          d,
          spent,
          isshou::raifusaikuru::ev(
            :permit,
            3200,
            [[:subject, "d"], [:not_after, 1], [:basis, 1], ["uses_left", 1]]
          )
        )
      )
    )
  ) == :no_edge
  assert error?(
    begin
      permit_event(plain, permit_for(plain, s, :use, 3000), "device-7")
    rescue e
      e
    end
  )
  assert contains(
    map(
      problem_kind,
      problems(:x, push(example_consumable_clauses, permit_log(:fly, :flown)))
    ),
    :unknown_capability
  )
  assert contains(
    map(
      problem_kind,
      problems(
        :x,
        push(
          push(example_consumable_clauses, permit_log(:use, :permit)),
          event(:permit, [])
        )
      )
    ),
    :duplicate_event
  )
end

test "a permit never outlives its guard, in time or in uses"
  d = example_consumable
  s = state_of(d, example_log)
  # At 12000 the reading binds: allowed until the permit's not_after, refused at it.
  na = permit_not_after(permit_for(d, s, :use, 12000))
  assert is_allowed(allowed(d, s, :use, na - 1))
  assert refused_rules(allowed(d, s, :use, na)) == [:reading_fresh]
  # 37 uses remain: after 36 the 37th is still allowed, after 37 the next is not.
  left = permit_count(permit_for(d, s, :use, 3000), :uses)
  uses = (k) -> map((i) -> ev(:use, 3000 + i, []), range(0, k))
  assert is_allowed(allowed(d, resume(d, s, uses(left - 1)), :use, 3100))
  spent = resume(d, s, uses(left))
  assert breaches(spent) == []
  assert refused_rules(allowed(d, spent, :use, 3100)) == [:uses_left]
  assert size(breaches(resume(d, s, uses(left + 1)))) == 1
end

test "a span is declared, checked when built, read back, and folds nothing"
  # The empty case: a definition that declares none.
  assert d_spans(example_consumable) == []
  # The identity: a span changes no state; the same log folds the same.
  d = lc_define(
    :consumable,
    push(
      push(
        example_consumable_clauses,
        span(:open_to_done, :open, :spent, hours(8))
      ),
      span(:shelf, :sealed, :open, nil)
    )
  )
  assert state_of(d, example_log) == state_of(example_consumable, example_log)
  # Read back in declaration order, through its accessors.
  assert d_spans(d) ==
    [[:open_to_done, :open, :spent, 28800], [:shelf, :sealed, :open, nil]]
  s = first(d_spans(d))
  assert [span_name(s), span_from(s), span_to(s), span_limit(s)] ==
    [:open_to_done, :open, :spent, 28800]
  # Controls, each refused when built with its kind: an undeclared state; one
  # state at both ends; an end no event reaches from the start (spent is
  # terminal, so nothing leads from it to open); a limit that is not a
  # positive whole duration; a state that is not a name.
  kinds = fn(extra)
    map(problem_kind, problems(:x, push(example_consumable_clauses, extra)))
  end
  assert kinds(span(:s, :open, :gone, nil)) == [:unknown_state]
  assert kinds(span(:s, :open, :open, nil)) == [:bad_span]
  assert kinds(span(:s, :spent, :open, nil)) == [:bad_span]
  assert kinds(span(:s, :open, :spent, 0)) == [:bad_span]
  assert kinds(span(:s, 7, :spent, 60)) == %i[bad_name unknown_state]
  assert error?(
    begin
      lc_define(
        :x,
        push(example_consumable_clauses, span(:s, :spent, :open, nil))
      )
    rescue e
      e
    end
  )
end

test "rule is a named predicate with no task, and rule_task carries its own task"
  assert rule(:r, below(:n, 3)) == [:lc_rule, :r, below(:n, 3), nil]
  t = task(:fix, [:scan], 60)
  assert rule_task(:r, below(:n, 3), t) == [:lc_rule, :r, below(:n, 3), t]
  assert rule(:r, present(:n))[3].nil?
  assert rule(:other, present(:n))[1] == :other
end

test "gate lays a capability on every edge of its rows, flattening nested rows"
  e1 = on(:a, :go, :b, [])
  e2 = on(:a, :tick, :stay, [])
  assert gate(:g, e1) == [[:lc_edge, :a, :go, :b, [], :g]]
  assert gate(:g, [e1, e2]) ==
    [[:lc_edge, :a, :go, :b, [], :g], [:lc_edge, :a, :tick, :a, [], :g]]
  assert gate(:g, [[e1], [[e2]]]) == gate(:g, [e1, e2])
  assert gate(:g, on_each(%i[a b], :tick, :stay, [])) ==
    [[:lc_edge, :a, :tick, :a, [], :g], [:lc_edge, :b, :tick, :b, [], :g]]
end

test "gate marks a clause that is not an edge, and an empty gate has no row"
  assert gate(:g, field(:z, 0)) == [%i[lc_misgated g lc_field]]
  assert gate(:g, []) == []
  assert gate(:g, [7]) == [%i[lc_misgated g lc_not_a_clause]]
end

test "check is empty for a sound definition and names each kind of fault"
  assert check(parse(:base, example_base)) == []
  bad = push(example_base, on(:x, :go, :b, []))
  assert map(problem_kind, check(parse(:base, bad))) == [:unknown_state]
  twice = push(example_base, states([:a]))
  assert contains(
    map(problem_kind, check(parse(:base, twice))),
    :duplicate_state
  )
end

test "check agrees with problems, and a gate on a field is a bad_gate"
  assert check(parse(:base, example_base)) == problems(:base, example_base)
  g = push(example_base, gate(:g, field(:z, 0)))
  assert contains(map(problem_kind, check(parse(:base, g))), :bad_gate)
  assert check(parse(:base, g)) == problems(:base, g)
end

test "check on a definition with no clause at all reports the missing states and start"
  kinds = map(problem_kind, check(parse(:empty, [])))
  assert contains(kinds, :no_states)
  assert contains(kinds, :no_start)
end

test "the general words on the empty case"
  assert d_names([0, []], 1) == []
  assert int_at_least?(nil, 0) == false
  assert pb_declared(:a, [], "w", :unknown_state, "state") ==
    [problem(:unknown_state, "w: :a is not a declared state")]
  assert reach([], [:a], 3, 0, 1) == [:a]
  assert capability_row([], :use).nil?
  assert k_absorb([], :no, :yes) == :yes
end

test "the general words as identity: each original word is one call of its general word"
  d = parse(:base, example_base)
  assert d_field_names(d) == d_names(d, 7)
  assert d_event_names(d) == d_names(d, 8)
  assert positive_int?(1) == int_at_least?(1, 1)
  assert pb_state(:x, [:x], "w") ==
    pb_declared(:x, [:x], "w", :unknown_state, "state")
  assert pb_field(:z, [], "w") ==
    pb_declared(:z, [], "w", :unknown_field, "field")
  pairs = [%i[a b], %i[b c]]
  assert forward(pairs, [:a], 2) == reach(pairs, [:a], 2, 0, 1)
  assert backward(pairs, [:c], 2) == reach(pairs, [:c], 2, 1, 0)
  assert guard_for(d, :use) == capability_row(d_guards(d), :use)
  assert k_and(%i[yes unknown]) == k_absorb(%i[yes unknown], :no, :yes)
  assert k_or(%i[no unknown]) == k_absorb(%i[no unknown], :yes, :no)
end

test "the general words on known values"
  assert d_names([0, [[:a, 1], [:b, 2]]], 1) == %i[a b]
  assert int_at_least?(0, 0)
  assert int_at_least?(0, 1) == false
  assert int_at_least?(1.5, 0) == false
  assert pb_field(:z, [:y], "w") ==
    [problem(:unknown_field, "w: :z is not a declared field")]
  assert set_equal(reach([%i[a b], %i[b c]], [:a], 2, 0, 1), %i[a b c])
  assert set_equal(reach([%i[a b], %i[b c]], [:c], 1, 1, 0), %i[c b])
  assert capability_row([[:guard, :use, 1], [:guard, :x, 2]], :x) ==
    [:guard, :x, 2]
  assert k_and(%i[yes no unknown]) == :no
  assert k_or(%i[no unknown]) == :unknown
  assert k_or(%i[no yes]) == :yes
end

test "tagged keeps the clauses that carry the tag"
  assert tagged([], :lc_start) == []
  assert tagged([[:lc_start, 1], [:lc_rule, 2], [:lc_start, 3]], :lc_start) ==
    [[:lc_start, 1], [:lc_start, 3]]
end

test "rule? is a four-item lc_rule clause"
  assert rule?(%i[lc_rule a e b]) == true
  assert rule?(%i[lc_rule a]) == false
  assert rule?(nil) == false
end
