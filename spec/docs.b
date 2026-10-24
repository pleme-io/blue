@moduledoc """
The documentation forms: `@doc` above a definition, `@moduledoc` first in a
file. Each example below is a test.

    total([1, 2, 3]) #=> 6
"""

@doc """
inc adds one to a number.

    inc(1) #=> 2
    inc(-1) #=> 0
"""
def inc(n)
  n + 1
end

# A comment above a doc stays above it: the lossless door holds both.
@doc """
total sums a list of numbers.

    xs = [inc(0), 2]
    total(xs) #=> 3
    total([]) #=> 0
"""
def total(xs)
  reduce((a, b) -> a + b, 0, xs)
end

@doc """
ZERO is the sum of nothing.

    ZERO #=> total([])
"""
ZERO = 0

test "a documented definition is the definition"
  assert inc(41) == 42
  assert ZERO == 0
end
