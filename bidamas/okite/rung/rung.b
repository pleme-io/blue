@moduledoc """
okite::rung is the level D0016's laws read through: a tree in the distribution.

    rung_word #=> :rung
"""

@doc """
rung_word names this level.

    rung_word #=> :rung
"""
def rung_word()
  :rung
end

test "rung_word answers from its own level"
  assert rung_word == :rung
end
