use("retsu")
use("shuugou")
# ran (乱) — deterministic pseudo-randomness.
#
# Every function takes a seed and returns the next seed alongside its value,
# so the whole package is pure. That is not a limitation worked around — it is
# the feature: a shuffle that cannot be reproduced cannot be debugged, and a
# test over random input is only useful if a failure can be replayed.
#
# The generator is a linear congruential one with the constants from Numerical
# Recipes. Adequate for simulation and sampling; NOT for anything where
# unpredictability matters. Use the word "random" here to mean "arbitrary and
# repeatable", never "secure".

def next_seed(seed)
  ((1664525 * seed) + 1013904223) % 4294967296
end

def next_int(seed, bound)
  next_seed(seed) % bound
end

def next_float(seed)
  next_seed(seed) / 4294967296
end

def next_range(seed, lo, hi)
  lo + (next_seed(seed) % (hi - lo))
end

# A list of n values, threading the seed through so the sequence advances.
def take_ints(seed, bound, n)
  if n < 1
    []
  else
    cons(next_int(seed, bound), take_ints(next_seed(seed), bound, n - 1))
  end
end

def seeds(seed, n)
  if n < 1
    []
  else
    s = next_seed(seed)
    cons(s, seeds(s, n - 1))
  end
end

# Pick an element by index. Returns the element, not the seed — callers who
# need to keep drawing advance the seed themselves.
def choice(seed, xs)
  nth(next_int(seed, size(xs)), xs)
end

test "the generator is deterministic"
  # The property the whole package exists for: same seed, same answer, always.
  assert next_seed(1) == next_seed(1)
  assert take_ints(42, 100, 5) == take_ints(42, 100, 5)
end

test "different seeds give different streams"
  assert take_ints(1, 1000, 5) != take_ints(2, 1000, 5)
end

test "values stay inside their bounds"
  vs = take_ints(7, 10, 50)
  assert every(fn(v) v >= 0 && v < 10 end, vs) == true
  assert size(vs) == 50
end

test "a stream actually advances rather than repeating one value"
  # A seed threaded wrongly produces the same number fifty times, which still
  # passes a bounds check — so the bound test above is not enough on its own.
  vs = take_ints(3, 1000, 20)
  assert size(unique(vs)) > 1
end

test "next_range respects both ends"
  vs = map(fn(s) next_range(s, 10, 20) end, seeds(5, 30))
  assert every(fn(v) v >= 10 && v < 20 end, vs) == true
end

test "choice returns a member of the list"
  assert contains([1, 2, 3], choice(99, [1, 2, 3])) == true
end
