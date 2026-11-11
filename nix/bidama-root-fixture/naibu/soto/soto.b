@moduledoc """
soto: the level naibu reaches.

    double(3) #=> 6
"""

@doc """
double: n times two.

    double(3) #=> 6
"""
def double(n)
  n * 2
end

test "double doubles"
  assert double(4) == 8
end
