@moduledoc """
casa::sala::tapete holds the pattern.

    padrao #=> "listras"
"""

@doc """
padrao is on the rug.

    padrao #=> "listras"
"""
def padrao()
  "listras"
end

test "padrao answers from this level"
  assert padrao == "listras"
end
