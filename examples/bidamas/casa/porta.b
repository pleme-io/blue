@moduledoc """
casa::porta is a level that is one file: `namespace()` keeps it out of casa.

    casa::porta::chave #=> "chave"
"""

namespace()

@doc """
chave is what opens the door.

    chave #=> "chave"
"""
def chave()
  "chave"
end

test "chave answers from this level"
  assert chave == "chave"
end
