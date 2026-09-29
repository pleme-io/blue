# A test file
#
# `blue test file.b` runs every test block; `blue run` ignores them, so tests
# live beside the code they test. Name the test for the behaviour, not the
# function. Assert the cases that tell a correct implementation from a
# plausible one: the empty input, an identity that must survive, a value
# anyone can check by hand, and the case a wrong formula still passes.
use("kazu", [:sum])
use("retsu", [:is_empty, :size])

def mean(xs)
  if is_empty(xs)
    nil
  else
    sum(xs) / size(xs)
  end
end

def variance(xs)
  m = mean(xs)
  if m == nil
    nil
  else
    mean(map(fn(x) (x - m) * (x - m) end, xs))
  end
end

test "the mean of nothing is nil, not zero"
  assert mean([]) == nil
end

test "a value anyone can check"
  assert mean([1, 2, 3, 4]) == 2.5
end

test "division keeps the fraction: 7 / 2 is 3.5"
  assert mean([3, 4]) == 3.5
end

test "the case a wrong mean still passes: identical values vary by zero"
  assert variance([5, 5, 5]) == 0
  assert variance([1, 3]) == 1
end

test "reversing twice is the identity"
  xs = [3, 1, 2]
  assert reverse(reverse(xs)) == xs
end
