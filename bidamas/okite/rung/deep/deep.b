@moduledoc """
okite::rung::deep is the second level down for D0016's laws.

    deep_word #=> :deep
"""

@doc """
deep_word names this level.

    deep_word #=> :deep
"""
def deep_word()
  :deep
end

@doc """
deep_depth names how far down this level is.

    deep_depth #=> :two_down
"""
def deep_depth()
  :two_down
end

test "deep_word answers from its own level"
  assert deep_word == :deep
end
