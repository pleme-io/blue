@doc """
clamp: The value x held between lo and hi.

    clamp(5, 0, 10) #=> 5
    clamp(-3, 0, 10) #=> 0
    clamp(42, 0, 10) #=> 10
"""
def clamp(x, lo, hi)
  if x < lo
    lo
  elsif x > hi
    hi
  else
    x
  end
end

test "clamp holds a value inside the bounds"
  assert clamp(0, 0, 10) == 0
  assert clamp(10, 0, 10) == 10
  assert clamp(11, 0, 10) == 10
end
