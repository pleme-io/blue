@moduledoc """
casa::cozinha is a level that is a directory.

    casa::cozinha::fogao #=> "fogao"
"""

@doc """
fogao is on the kitchen floor.

    fogao #=> "fogao"
"""
def fogao()
  "fogao"
end

test "fogao answers from this level"
  assert fogao == "fogao"
end
