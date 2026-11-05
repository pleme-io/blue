@moduledoc """
koubou (工房, workshop) — shapes made, measured and cut.

Four levels: `koubou/kikagaku` (plane geometry), `koubou/rittai` (solids),
`koubou/zumen` (drawings) and `koubou/kakou` (sheet-metal work). The root
defines nothing; a `use("koubou")` brings all four.
"""

test "the root reaches each of its levels by the path below it"
  assert kikagaku::midpoint([0, 0], [2, 4]) == [1, 2]
  assert rittai::z([1, 2, 3]) == 3
  assert zumen::num(1.5) == "1.5"
  assert kakou::outside_setback(90, 1, 1) > 1.99
end
