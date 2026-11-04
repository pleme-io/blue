@moduledoc """
casa is a tree: a house of rooms, each room a level of this one bidama.

    endereco #=> "rua 1"
"""

@doc """
endereco is the address of the house.

    endereco #=> "rua 1"
"""
def endereco()
  "rua 1"
end

test "endereco answers from this level"
  assert endereco == "rua 1"
end
