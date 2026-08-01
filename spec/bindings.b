# Local bindings and lambdas.
#
# Before these, blue had no way to NAME a value: `x = 5` was a parse error, so
# every program was a single expression. And with no lambda the higher-order
# functions were unreachable in practice — `map` worked only if you happened to
# want a named stdlib function.

def with_local(n)
  doubled = n * 2
  doubled + 1
end
test "a binding names a value"
  x = 5
  assert x + 1 == 6
end
test "bindings are visible to later statements"
  a = 2
  b = 3
  assert a * b == 6
end
test "a binding works inside a def"
  assert with_local(5) == 11
end
test "a lambda is a value"
  double = fn(x)
    x * 2
  end
  assert double(21) == 42
end
test "a lambda closes over its environment"
  n = 10
  add_n = fn(x)
    x + n
  end
  assert add_n(5) == 15
end
test "lambdas make the higher-order functions usable"
  squares = map(fn(x)
    x * x
  end, [1, 2, 3])
  assert join(squares, ",") == "1,4,9"
end
test "filter selects"
  assert join(filter(even?, [1, 2, 3, 4]), ",") == "2,4"
end
