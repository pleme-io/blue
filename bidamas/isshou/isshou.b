@moduledoc """
isshou (一生, a lifetime) — what a thing goes through, recorded and read back.

Three levels: `isshou/raifusaikuru` (event-sourced lifecycles: states,
events, fields and guards), `isshou/nisshi` (the append-only event log) and
`isshou/anaritikusu` (lifecycle analytics generated from both). The root
defines nothing; a `use("isshou")` brings all three.

    isshou::raifusaikuru::hours(2) #=> 7200
"""

test "the root reaches each of its levels by its full path"
  assert isshou::raifusaikuru::hours(2) == 7200
  assert isshou::nisshi::format == "nisshi/1"
  assert isshou::anaritikusu::lit_type(1) == :bigint
end
