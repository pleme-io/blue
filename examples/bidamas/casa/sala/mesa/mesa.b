@moduledoc """
casa::sala::mesa holds the plates.

    pratos #=> "pratos"
"""

@doc """
pratos are on the table.

    pratos #=> "pratos"
"""
def pratos()
  "pratos"
end

test "pratos answers from this level"
  assert pratos == "pratos"
end
