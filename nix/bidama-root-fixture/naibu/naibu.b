@moduledoc """
naibu: a bidama whose root reaches a level of its own.

    twice(21) #=> 42
"""

use("naibu/soto", [:double])

@doc """
twice: double of n, through the level soto.

    twice(2) #=> 4
"""
def twice(n)
  double(n)
end

test "the root reaches its own level"
  assert twice(21) == 42
end
