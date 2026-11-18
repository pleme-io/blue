@moduledoc """
kitei (既定) — defaults: the registry of the rules by which blue picks a default from a fact it holds. Each row is one rule of the default cascade (docs/FACTS.md): the facts it reads and the lever it pulls, the receipt that names it in a run, the switch that turns it off, its state and the tests that lock it. The table in docs/PERFORMANCE.md, the verdicts of `blue shift --defaults` and the switches the runtime reads are held to these rows.

    switch_of("R4") #=> "BLUE_FOLD=off"
"""

use("retsu", %i[first size])

@doc """
rule: one rule of the default cascade. `needs` is its body: the facts that must all hold of a definition for the rule to fire (a Horn clause), each a keyword the runtime computes. `state` is :shipped, :folded (its lever lives in another rule, named in `lever`) or :refused (measured, and the ratchet kept it out).

    rule("R0", [:pure], "a fact", "a lever", "a receipt", "BLUE_X=off", :shipped, "a test").id #=> "R0"
"""
record rule(id, needs, when, lever, receipt, switch, state, locks)

@doc """
rules: every rule of the default cascade, in the order of its id.

    size(rules) #=> 14
"""
def rules()
  [
    rule(
      "R1",
      [:agreed_construct],
      "a construct every evaluator column agrees on",
      "the program runs on the VM",
      "door receipt",
      "BLUE_DOOR=walker",
      :shipped,
      "tests/door.rs"
    ),
    rule(
      "R2",
      %i[pure self_overlapping],
      "a pure definition that calls itself at two or more places",
      "its calls are answered from a table",
      "door receipt",
      "BLUE_MEMO=off",
      :shipped,
      "tests/door.rs"
    ),
    rule(
      "R3",
      [:compute_chain],
      "a map, filter or reduce chain of callbacks that only compute",
      "the chain runs as one pass, and the unfused chain on the first error",
      "fused row",
      "BLUE_FUSE=off",
      :shipped,
      "tests/fusion.rs"
    ),
    rule(
      "R4",
      %i[pure literal_call],
      "a pure definition called with literal arguments where the call can run more than once",
      "its value is computed before the run",
      "folded row",
      "BLUE_FOLD=off",
      :shipped,
      "tests/fold.rs"
    ),
    rule(
      "R5",
      [:operator_on_numbers],
      "a call of an operator on two Ints or two Floats",
      "it is computed in place, with the tag check as its guard",
      "none",
      "none",
      :shipped,
      "spec/rows/equality.b"
    ),
    rule(
      "R6",
      [:proven_types],
      "a definition whose argument types are proven",
      "the guard drops in compiled code: folded into R7",
      "none",
      "none",
      :folded,
      "tests/native_tier.rs"
    ),
    rule(
      "R7",
      %i[artifact hot],
      "a definition with a native artifact whose calls averaged 0.2 ms or more through its library, or 20 ms with an executable only",
      "its calls are answered by the artifact, in process through its library when it has one",
      "door receipt",
      "BLUE_NATIVE=off",
      :shipped,
      "tests/native_tier.rs"
    ),
    rule(
      "R8",
      %i[pure stored_costly],
      "a pure definition with a stored result that cost 20 ms or more",
      "its calls are answered from the store",
      "door receipt",
      "BLUE_MEMO=off",
      :shipped,
      "tests/fleet_memo.rs"
    ),
    rule(
      "R9",
      [:record_type],
      "a record type",
      "its shape is fixed once at its declaration",
      "none",
      "none",
      :shipped,
      "record.rs"
    ),
    rule(
      "R10",
      [:member_test],
      "a callback that tests member?(x, s) on a local the definition never assigns",
      "membership is answered from an index of s built for that call",
      "indexed row",
      "BLUE_INDEX=off",
      :shipped,
      "tests/member_index.rs"
    ),
    rule(
      "R11",
      [:closed_list_region],
      "a closed region of list-holding definitions under a root that takes and returns no list",
      "an arena",
      "none",
      "none",
      :refused,
      "measured 1.03 ± 0.07"
    ),
    rule(
      "R12",
      [:no_writable_code],
      "a placement that forbids writable code",
      "ahead-of-time code only",
      "none",
      "none",
      :shipped,
      "tests/placement_tiers.rs"
    ),
    rule(
      "R13",
      [:string_append_loop],
      "a reduce whose callback appends to its string accumulator and reads it nowhere else",
      "the string is built once: its start, then the join of what each step appends",
      "built row",
      "BLUE_BUILDER=off",
      :shipped,
      "tests/builder.rs"
    ),
    rule(
      "R14",
      %i[pure slow_program],
      "a pure definition of a program whose last run evaluated for 20 ms or more",
      "its results are recorded to the store with their cost, so R8 answers the costly ones from the next run",
      "door receipt",
      "BLUE_MEMO=off",
      :shipped,
      "tests/fleet_memo.rs"
    )
  ]
end

@doc """
named: the rule with the id `id`, or nil when no rule has it.

    named("R10").switch #=> "BLUE_INDEX=off"
    named("R99") #=> nil
"""
def named(id)
  find(rules, (r) -> r.id == id)
end

@doc """
switch_of: the switch that turns the rule `id` off, "none" for a rule with no switch, or nil when no rule has the id.

    switch_of("R7") #=> "BLUE_NATIVE=off"
"""
def switch_of(id)
  r = named(id)
  if r.nil?
    nil
  else
    r.switch
  end
end

@doc """
shipped: the ids of the rules a run applies today.

    first(shipped) #=> "R1"
"""
def shipped()
  map((r) -> r.id, filter((r) -> r.state == :shipped, rules))
end

@doc """
fires?: whether the rule `id` fires on a definition whose facts are `held`: the rule is shipped and every fact it needs is held.

    fires?("R2", %i[pure self_overlapping]) #=> true
    fires?("R2", [:self_overlapping]) #=> false
"""
def fires?(id, held)
  r = named(id)
  if r.nil? or r.state != :shipped
    false
  else
    every?((f) -> member?(f, held), r.needs)
  end
end

test "every rule has a distinct id in order, and a state blue knows"
  ids = map((r) -> r.id, rules)
  assert ids == map((n) -> "R#{n}", range(1, 15))
  assert every?((r) -> member?(r.state, %i[shipped folded refused]), rules)
end

test "a rule with a switch names a BLUE variable and the value that turns it off"
  switched = filter((r) -> r.switch != "none", rules)
  assert size(switched) == 9
  assert every?(
    (r) -> starts_with?(r.switch, "BLUE_") and contains?(r.switch, "="),
    switched
  )
end

test "the rules that are not shipped are R6, folded into R7, and R11, refused"
  assert size(shipped) == 12
  assert not member?("R6", shipped)
  assert not member?("R11", shipped)
  assert named("R6").state == :folded
  assert named("R11").state == :refused
end

test "an unknown id names no rule and no switch"
  assert named("R0").nil?
  assert switch_of("").nil?
  assert switch_of("R9") == "none"
end

test "a rule is a record that names its id, switch and state"
  r = rule(
    "R0",
    [:pure],
    "a fact",
    "a lever",
    "none",
    "BLUE_X=off",
    :shipped,
    "a test"
  )
  assert rule?(r)
  assert r.switch == "BLUE_X=off"
  assert not rule?({id: "R0"})
end

test "a rule fires only when every fact it needs is held, and only when shipped"
  assert fires?("R4", %i[literal_call pure self_overlapping])
  assert not fires?("R4", [:literal_call])
  assert not fires?("R4", [])
  assert fires?("R10", [:member_test])
  assert not fires?("R11", [:closed_list_region])
  assert not fires?("R6", [:proven_types])
  assert not fires?("R99", [:pure])
  assert every?((r) -> size(r.needs) > 0, rules)
end
