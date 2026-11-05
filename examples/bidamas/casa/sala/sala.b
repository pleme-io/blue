@moduledoc """
casa::sala holds the sofa.

    sofa #=> "sofa"
"""

@doc """
sofa is in the living room.

    sofa #=> "sofa"
"""
def sofa()
  "sofa"
end

test "sofa answers from this level"
  assert sofa == "sofa"
end
