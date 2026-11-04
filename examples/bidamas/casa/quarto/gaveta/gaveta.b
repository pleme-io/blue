@moduledoc """
casa::quarto::gaveta is three levels down, and the words in it read as data.

    casa::quarto::gaveta::meias #=> {cor: "azul"}
"""

@doc """
meias are in the drawer.

    meias #=> {cor: "azul"}
"""
def meias()
  {cor: "azul"}
end

test "meias answers from this level"
  assert meias == {cor: "azul"}
end
