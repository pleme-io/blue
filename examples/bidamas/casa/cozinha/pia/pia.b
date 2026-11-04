@moduledoc """
casa::cozinha::pia is two levels down.

    casa::cozinha::pia::torneira #=> "torneira"
"""

@doc """
torneira is on the sink.

    torneira #=> "torneira"
"""
def torneira()
  "torneira"
end

test "torneira answers from this level"
  assert torneira == "torneira"
end
