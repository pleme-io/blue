@moduledoc """
casa::quarto::gaveta::fundo is as deep as a bidama needs.

    carta #=> "carta"
"""

@doc """
carta is at the bottom of the drawer.

    carta #=> "carta"
"""
def carta()
  "carta"
end

test "carta answers from this level"
  assert carta == "carta"
end
