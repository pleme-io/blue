# kazu (数) — numbers.
#
# The arithmetic every language ships and blue did not: clamping, sign,
# min/max, and integer power. Written in blue itself, not Rust, which is the
# point of a bidama — the standard library grows in the language, so a user
# reading it learns the language rather than an FFI boundary.

def abs(n)
  if n < 0
    0 - n
  else
    n
  end
end

def sign(n)
  if n < 0
    0 - 1
  else
    if n > 0
      1
    else
      0
    end
  end
end

def max(a, b)
  if a > b
    a
  else
    b
  end
end

def min(a, b)
  if a < b
    a
  else
    b
  end
end

# Clamp into [lo, hi]. Named `clamp` rather than `bound` because every
# neighbouring language spells it this way, and a stdlib that renames familiar
# operations taxes every reader for no gain.
def clamp(n, lo, hi)
  max(lo, min(n, hi))
end

def pow(base, exp)
  if exp < 1
    1
  else
    base * pow(base, exp - 1)
  end
end

def even(n)
  n - (n / 2) * 2 == 0
end

# Approximate equality, for the float results `sqrt` and friends return.
#
# Needed because this runtime does not equate across numeric kinds:
#
#   sqrt(25) == 5     => false      -- Float(5.0) vs Int(5)
#
# So an exact `==` against an integer literal fails for every root, mean or
# ratio, and a caller who writes the obvious assertion gets a false negative.
# Comparing by distance is the standard answer and the honest one.
def near(a, b)
  near_within(a, b, 0.000001)
end

def near_within(a, b, eps)
  d = a - b
  if d < 0
    (0 - d) <= eps
  else
    d <= eps
  end
end

test "abs, sign, and the zero case sign implementations drop"
  assert abs(0 - 5) == 5
  assert abs(5) == 5
  assert abs(0) == 0
  assert sign(0 - 7) == 0 - 1
  assert sign(7) == 1
  # A two-branch sign() reports zero as positive. This is that test.
  assert sign(0) == 0
end

test "max, min, clamp"
  assert max(3, 7) == 7
  assert min(3, 7) == 3
  assert clamp(99, 1, 10) == 10
  assert clamp(0 - 5, 1, 10) == 1
  assert clamp(5, 1, 10) == 5
end

test "pow and even"
  assert pow(2, 10) == 1024
  assert pow(5, 0) == 1
  assert even(4) == true
  assert even(3) == false
  assert even(0) == true
end

test "near bridges the int/float divide that == does not"
  assert near(sqrt(25), 5) == true
  assert near(sqrt(16), 4) == true
  assert near(1, 2) == false
  # And it is a tolerance, not a rounding: a genuine difference stays unequal.
  assert near_within(1, 1.5, 0.1) == false
  assert near_within(1, 1.05, 0.1) == true
end
