@doc """
clamp: The value x held between lo and hi: lo when x is below it, hi when x
is above it, x otherwise.

    clamp(5, 0, 3) #=> 3
    clamp(-2, 0, 3) #=> 0
"""
def clamp(x, lo, hi)
  min(max(x, lo), hi)
end
