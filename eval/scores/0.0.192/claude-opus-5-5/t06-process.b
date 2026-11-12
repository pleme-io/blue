def square_to(parent, i, x)
  send(parent, [:square, i, x * x])
end

def squares(xs)
  parent = self
  idx = range(count(xs))
  map((i) -> spawn(square_to, [parent, i, xs[i]]), idx)
  map((i) -> receive([:square, i, :_])[2], idx)
end

test "squares of the empty list is empty"
  assert squares([]) == []
end

test "squares keeps the order of xs"
  assert squares([3, 1, 2]) == [9, 1, 4]
  assert squares([5, -2, 0, 4]) == [25, 4, 0, 16]
end
