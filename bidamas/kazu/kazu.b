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
