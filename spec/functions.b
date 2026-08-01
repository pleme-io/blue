# Functions: definition, recursion, and the sliding scale.
#
# `fact` is annotated and `add` is not. Both run; the annotated one additionally
# buys analysis. That is the whole sliding-scale claim, stated in blue.

def add(a, b)
  a + b
end
def fact(n: Int) -> Int
  if n < 2
    1
  else
    n * fact(n - 1)
  end
end
def sum(n, acc)
  if n == 0
    acc
  else
    sum(n - 1, acc + n)
  end
end
test "an untyped function"
  assert add(2, 3) == 5
end
test "an annotated function computes the same thing"
  assert fact(6) == 720
end
test "recursion with an accumulator"
  assert sum(10, 0) == 55
end
def classify(n)
  if n < 0
    -1
  else
    1
  end
end
test "a branch returns the taken arm"
  assert classify(5) == 1
  assert classify(-5) == -1
end
test "unless is a negated if"
  assert if !(1 > 2)
    7
  else
    8
  end == 7
end
