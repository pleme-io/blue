@moduledoc """
casa::sala::luz holds the lamp.

    casa::sala::luz::lampada #=> "lampada"
"""

@doc """
lampada is on the ceiling.

    lampada #=> "lampada"
"""
def lampada()
  "lampada"
end

test "lampada answers from this level"
  assert lampada == "lampada"
end
