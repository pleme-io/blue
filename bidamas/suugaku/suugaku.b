@moduledoc """
suugaku (数学, mathematics) — numbers worked over as a discipline.

Six levels: `suugaku/gyouretsu` (vectors and matrices), `suugaku/kinji`
(numerical methods), `suugaku/kumiawase` (combinatorics), `suugaku/toukei`
(descriptive statistics), `suugaku/ryouiki` (scenario discovery) and
`suugaku/tokumei` (privacy-preserving aggregates). The root defines nothing; a
`use("suugaku")` brings all six.
"""

test "the root reaches each of its levels by the path below it"
  assert gyouretsu::dot([1, 2, 3], [4, 5, 6]) == 32
  assert kumiawase::combinations(52, 5) == 2_598_960
  assert toukei::mean([1, 2]) == 1.5
  assert tokumei::epsilon(0) == 0
  assert ryouiki::box_around([]) == []
  assert kinji::trapz([0, 1, 3], [0, 2, 6]) > 8.99
end
