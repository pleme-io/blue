use("narabi")
# toukei (統計) — descriptive statistics.
#
# Integer-mean is the trap this avoids: `/` is float division in blue, so
# mean([1,2]) is 1.5 rather than 1. A statistics package that silently
# truncates is worse than none, because every number it returns is plausible.

def total(xs)
  reduce(fn(a, b) a + b end, 0, xs)
end

def mean(xs)
  total(xs) / size(xs)
end

def median(xs)
  s = sort(xs)
  n = size(s)
  half = floor(n / 2)
  if n % 2 == 1
    nth(half, s)
  else
    (nth(half - 1, s) + nth(half, s)) / 2
  end
end

def spread(xs)
  s = sort(xs)
  last(s) - first(s)
end

def variance(xs)
  m = mean(xs)
  total(map(fn(x) (x - m) * (x - m) end, xs)) / size(xs)
end

def stddev(xs)
  sqrt(variance(xs))
end

def smallest(xs)
  first(sort(xs))
end

def largest(xs)
  last(sort(xs))
end

# The value below which the given fraction of the data falls.
def percentile(xs, frac)
  s = sort(xs)
  idx = floor(frac * (size(s) - 1))
  nth(idx, s)
end

test "mean does NOT truncate"
  # The whole reason this package divides the way it does.
  assert mean([1, 2]) == 1.5
  assert mean([2, 4, 6]) == 4
end

test "median handles both parities"
  assert median([3, 1, 2]) == 2
  assert median([4, 1, 3, 2]) == 2.5
  assert median([5]) == 5
end

test "spread, smallest, largest, percentile"
  assert spread([3, 9, 1]) == 8
  assert smallest([3, 9, 1]) == 1
  assert largest([3, 9, 1]) == 9
  assert percentile([1, 2, 3, 4, 5], 0) == 1
  assert percentile([1, 2, 3, 4, 5], 1) == 5
end

test "variance is zero for a constant list"
  # The case that catches a wrong mean: if mean is off, this is not zero.
  assert variance([5, 5, 5]) == 0
  assert near(stddev([5, 5, 5]), 0) == true
  assert near(variance([1, 3]), 1) == true
end
