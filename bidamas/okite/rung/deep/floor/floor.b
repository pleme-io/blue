@moduledoc """
okite::rung::deep::floor is the third level down for D0016's laws.

    floor_word #=> :floor
"""

@doc """
floor_word names this level.

    floor_word #=> :floor
"""
def floor_word()
  :floor
end

test "floor_word answers from its own level"
  assert floor_word == :floor
end
