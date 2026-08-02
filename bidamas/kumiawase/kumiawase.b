use("kazu")
# kumiawase (組み合わせ) — counting without enumerating.
#
# `combinations(52, 5)` is 2598960, and computing it by building the hands
# would allocate 2.6 million lists to return one number. Every function here
# counts arithmetically, which is the difference between a combinatorics
# library and a very slow list library.

def factorial(n)
  if n < 2
    1
  else
    n * factorial(n - 1)
  end
end

# Falling factorial: n * (n-1) * ... * (n-k+1) — permutations of k from n.
def permutations(n, k)
  if k < 1
    1
  else
    if k > n
      0
    else
      n * permutations(n - 1, k - 1)
    end
  end
end

# Binomial coefficient, computed by the multiplicative formula.
def combinations(n, k)
  if k < 0
    0
  else
    if k > n
      0
    else
      permutations(n, k) / factorial(k)
    end
  end
end

def binomial(n, k)
  combinations(n, k)
end

# The nth row of Pascal's triangle.
def pascal_row(n)
  map(fn(k) combinations(n, k) end, range(0, n + 1))
end

# Catalan number — the count that shows up in balanced parentheses, binary
# trees, and triangulations of a polygon.
def catalan(n)
  combinations(2 * n, n) / (n + 1)
end

test "factorial, including the empty product"
  assert factorial(0) == 1
  assert factorial(1) == 1
  assert factorial(5) == 120
end

test "permutations and combinations"
  assert permutations(5, 2) == 20
  assert combinations(5, 2) == 10
  # The symmetry C(n,k) == C(n,n-k), which a wrong formula breaks.
  assert combinations(10, 3) == combinations(10, 7)
  # Out of range is zero, not an error.
  assert combinations(3, 5) == 0
end

test "a poker hand, which is the number everyone knows"
  assert combinations(52, 5) == 2598960
end

test "pascal row sums to a power of two"
  assert pascal_row(4) == [1, 4, 6, 4, 1]
  assert reduce(fn(a, b) a + b end, 0, pascal_row(6)) == 64
end

test "catalan numbers"
  assert catalan(0) == 1
  assert catalan(4) == 14
end
