def squarer(parent, i, x)
  send(parent, [:square, i, x * x])
end

def squares(xs)
  me = self
  started = map((i) -> spawn(squarer, [me, i, xs[i]]), range(count(xs)))
  map((i) -> receive([:square, i, :_])[2], range(length(started)))
end
