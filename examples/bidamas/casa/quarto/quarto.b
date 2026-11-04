@moduledoc """
casa::quarto holds the bed, and a level below it holds the drawer.

    casa::quarto::cama #=> "cama"
"""

@doc """
cama is in the bedroom.

    cama #=> "cama"
"""
def cama()
  "cama"
end

test "cama answers from this level"
  assert cama == "cama"
end
