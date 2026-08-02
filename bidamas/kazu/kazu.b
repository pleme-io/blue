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

# --- predicates -------------------------------------------------------------

# Odd via the remainder rather than `!even(n)`, because blue's `%` is Euclidean
# (see mod_positive) and so `n % 2` is 1 for a negative odd number too. The
# subtraction `even` uses happens to agree; the tests below pin that agreement
# so a change to either is caught rather than assumed.
def odd(n)
  n % 2 == 1
end

# Zero by ordering, NOT by `n == 0`.
#
# This runtime does not equate across numeric kinds, so `sqrt(0) == 0` is false
# — Float(0.0) against Int(0). Every value that reached here through a `sqrt`,
# a division or a mean would therefore be reported non-zero while being zero.
# `<` and `>` DO compare across kinds, so asking "neither below nor above" is
# the kind-blind question and the one a caller means.
def is_zero(n)
  !(n < 0) && !(n > 0)
end

def is_positive(n)
  n > 0
end

def is_negative(n)
  n < 0
end

# Inclusive on both ends, matching clamp: whatever clamp returns is in_range.
def in_range(n, lo, hi)
  n >= lo && n <= hi
end

# Zero divides nothing — the guard exists because `n % 0` is a runtime error,
# so the naive one-liner crashes instead of answering.
def divides(d, n)
  if is_zero(d)
    false
  else
    n % d == 0
  end
end

# --- integer division -------------------------------------------------------

# Division that rounds toward negative infinity, not toward zero.
#
# `floor_div(0 - 7, 2)` is 0 - 4, where a language truncating toward zero says
# 0 - 3. Blue's `floor` already rounds down, so this is a naming of the intent
# rather than a repair — but the intent is exactly what gets written wrongly.
def floor_div(a, b)
  floor(a / b)
end

def ceil_div(a, b)
  ceiling(a / b)
end

# A remainder guaranteed to land in [0, abs(m)).
#
# Measured on this runtime, `%` is ALREADY Euclidean — `(0 - 7) % 3` is 2, not
# 0 - 1 as C, Rust and JavaScript would give — which is the opposite of the
# trap most readers arrive expecting. The tests below pin that fact so a
# regression in the runtime is caught here rather than in a caller's clock
# arithmetic. The `r < 0` branch keeps this function correct regardless.
def mod_positive(a, m)
  d = abs(m)
  r = a % d
  if r < 0
    r + d
  else
    r
  end
end

# --- powers and roots -------------------------------------------------------

def square(n)
  n * n
end

def cube(n)
  n * n * n
end

# Integer square root: the largest r with r * r <= n.
#
# `floor(sqrt(n))` alone is not it. `sqrt` returns a float, and a float that is
# a hair under a perfect square floors to one less — so the answer is seeded
# from `sqrt` and then walked to the true value. Negative input has no integer
# root; 0 is returned rather than erroring, so callers can fold this.
def int_sqrt(n)
  if n < 1
    0
  else
    int_sqrt_fix(n, floor(sqrt(n)))
  end
end

def int_sqrt_fix(n, r)
  if r * r > n
    int_sqrt_fix(n, r - 1)
  else
    if (r + 1) * (r + 1) <= n
      int_sqrt_fix(n, r + 1)
    else
      r
    end
  end
end

# How many decimal digits the number is written with, sign ignored.
# Zero is one digit, which is the case a `while n > 0` loop returns 0 for.
def digit_count(n)
  m = abs(n)
  if m < 10
    1
  else
    1 + digit_count(floor(m / 10))
  end
end

# --- folds over a list of numbers -------------------------------------------
#
# All five are written with `reduce` and never with `length`/`car`/`cdr`,
# which is not a style choice here: kazu is the root of this distribution's
# dependency graph — retsu, kumiawase, gyouretsu, kikagaku and ongaku all
# import it — so it cannot import retsu's total list primitives back without
# a cycle. `reduce` is the one list primitive that already handles nil, so
# these stay total on both empties without borrowing anything.

def sum(xs)
  reduce(fn(a, b) a + b end, 0, xs)
end

# Seeded with 1, not 0 — the empty product is one, and a 0 seed makes every
# answer zero.
def product(xs)
  reduce(fn(a, b) a * b end, 1, xs)
end

# nil seeds the fold so that no sentinel can be mistaken for data. Seeding
# with a large number instead makes min_of([]) report that number as the
# minimum of nothing; here the empty list answers nil, which a caller can test.
def min_of(xs)
  reduce(fn(acc, x)
    if acc == nil
      x
    else
      min(acc, x)
    end
  end, nil, xs)
end

def max_of(xs)
  reduce(fn(acc, x)
    if acc == nil
      x
    else
      max(acc, x)
    end
  end, nil, xs)
end

# The identity elements are the whole reason these read the way they do:
# gcd(0, n) is n, so 0 seeds the gcd fold; lcm(1, n) is n, so 1 seeds the lcm
# fold. Swapping them silently returns 1 from every gcd and 0 from every lcm.
def gcd_of(xs)
  reduce(fn(a, b) gcd(a, b) end, 0, xs)
end

def lcm_of(xs)
  reduce(fn(a, b) lcm(a, b) end, 1, xs)
end

# --- interpolation, rounding, ratios ----------------------------------------

# Linear interpolation, written `a + (b - a) * t` rather than
# `a * (1 - t) + b * t` because this form returns `a` and `b` EXACTLY at t=0
# and t=1 — no float creeps into an endpoint — and t outside [0,1]
# extrapolates rather than being clamped, which is what callers reach for.
def lerp(a, b, t)
  a + (b - a) * t
end

# Round to a number of decimal places. `places` is a count, so 0 or more;
# a negative count is not rejected but is not what this scales for.
def round_to(n, places)
  f = expt(10, places)
  round(n * f) / f
end

# `part` expressed as a percentage of `whole`.
#
# Multiplied before dividing on purpose: `part / whole * 100` rounds once more
# than it needs to, and on this runtime it also throws away the exact-integer
# result that `part * 100 / whole` keeps.
def percent(part, whole)
  part * 100 / whole
end

# Percentage change from one value to another. The denominator is the value
# moved FROM, which is what makes the operation asymmetric: 200 up to 250 is
# +25%, but 250 back down to 200 is -20%, not -25%.
def percent_change(from, to)
  (to - from) * 100 / from
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

test "odd agrees with even, including where the two implementations differ"
  assert odd(3) == true
  assert odd(4) == false
  assert odd(0) == false
  # The negatives are the point: `odd` asks the remainder, `even` subtracts.
  # If either drifts this is where it shows.
  assert odd(0 - 3) == true
  assert odd(0 - 4) == false
  assert odd(0 - 3) == !even(0 - 3)
  assert odd(0 - 4) == !even(0 - 4)
end

test "is_zero sees a float zero that == does not"
  assert is_zero(0) == true
  assert is_zero(1) == false
  assert is_zero(0 - 1) == false
  # The whole reason is_zero is not `n == 0`: this runtime says otherwise.
  assert (sqrt(0) == 0) == false
  assert is_zero(sqrt(0)) == true
  assert is_zero(0.0) == true
end

test "is_positive and is_negative both reject zero"
  assert is_positive(3) == true
  assert is_negative(0 - 3) == true
  # A sign predicate written as `!is_negative` calls zero positive. Neither does.
  assert is_positive(0) == false
  assert is_negative(0) == false
end

test "in_range is inclusive, and clamp always lands inside it"
  assert in_range(5, 1, 10) == true
  assert in_range(1, 1, 10) == true
  assert in_range(10, 1, 10) == true
  assert in_range(0, 1, 10) == false
  assert in_range(11, 1, 10) == false
  # The property that ties the two together, on both sides and in the middle.
  assert in_range(clamp(99, 1, 10), 1, 10) == true
  assert in_range(clamp(0 - 99, 1, 10), 1, 10) == true
  assert in_range(clamp(5, 1, 10), 1, 10) == true
end

test "divides answers for zero instead of erroring on it"
  assert divides(3, 12) == true
  assert divides(5, 12) == false
  # Everything divides zero; zero divides nothing. The second case is a
  # runtime error without the guard, not a false.
  assert divides(3, 0) == true
  assert divides(0, 5) == false
  assert divides(0, 0) == false
  assert divides(3, 0 - 12) == true
end

test "floor_div rounds down, which is not truncation"
  assert floor_div(7, 2) == 3
  assert floor_div(6, 3) == 2
  # Truncation toward zero would say 0 - 3 here. This is the whole function.
  assert floor_div(0 - 7, 2) == 0 - 4
  assert floor_div(0 - 6, 3) == 0 - 2
end

test "ceil_div rounds up, exact division stays put"
  assert ceil_div(7, 2) == 4
  assert ceil_div(6, 3) == 2
  assert ceil_div(0 - 7, 2) == 0 - 3
  # The pairing every "how many pages" calculation wants.
  assert ceil_div(10, 3) == 4
  assert floor_div(10, 3) == 3
end

test "mod_positive never returns a negative, and blue's % already agrees"
  assert mod_positive(7, 3) == 1
  assert mod_positive(0 - 7, 3) == 2
  assert mod_positive(0, 5) == 0
  # Clock arithmetic: one hour before midnight is 11, not 0 - 1.
  assert mod_positive(0 - 1, 12) == 11
  # A negative modulus still yields a non-negative remainder.
  assert mod_positive(7, 0 - 3) == 1
  assert mod_positive(0 - 7, 0 - 3) == 2
  # Measured, and counter to C/Rust/JS: blue's own % is Euclidean already.
  # Pinned so a runtime change surfaces here and not in a caller.
  assert (0 - 7) % 3 == 2
  assert 7 % (0 - 3) == 1
end

test "the division identity holds across signs"
  # floor_div and mod_positive are one decomposition, not two functions:
  # a == floor_div(a, b) * b + mod_positive(a, b) for positive b.
  assert floor_div(0 - 7, 3) * 3 + mod_positive(0 - 7, 3) == 0 - 7
  assert floor_div(7, 3) * 3 + mod_positive(7, 3) == 7
  assert floor_div(0 - 9, 3) * 3 + mod_positive(0 - 9, 3) == 0 - 9
end

test "square and cube, where sign tells them apart"
  assert square(4) == 16
  assert cube(2) == 8
  assert square(0) == 0
  # square discards the sign, cube keeps it. An abs-based cube passes the
  # positive cases and fails this one.
  assert square(0 - 4) == 16
  assert cube(0 - 2) == 0 - 8
end

test "int_sqrt is exact on and around perfect squares"
  assert int_sqrt(16) == 4
  assert int_sqrt(15) == 3
  assert int_sqrt(17) == 4
  assert int_sqrt(0) == 0
  assert int_sqrt(1) == 1
  assert int_sqrt(2) == 1
  # An integer answer, not the float sqrt returns. == would fail on that.
  assert int_sqrt(1000000) == 1000
  assert int_sqrt(999999) == 999
  # Negative has no integer root; it must not spin or error.
  assert int_sqrt(0 - 5) == 0
end

test "digit_count counts zero as one digit"
  assert digit_count(0) == 1
  assert digit_count(7) == 1
  assert digit_count(10) == 2
  assert digit_count(99) == 2
  assert digit_count(100) == 3
  assert digit_count(123456) == 6
  # The sign is not a digit.
  assert digit_count(0 - 1234) == 4
end

test "sum and product carry the right empty"
  assert sum([1, 2, 3, 4]) == 10
  assert product([1, 2, 3, 4]) == 24
  assert sum([0 - 1, 1]) == 0
  # The empty cases are the ones a seed gets wrong: an empty sum is 0 and an
  # empty product is 1. A product seeded with 0 passes every other assertion
  # here and fails this one.
  assert sum([]) == 0
  assert product([]) == 1
  # And nil, the other empty, which cdr hands back and length errors on.
  assert sum(nil) == 0
  assert product(nil) == 1
end

test "min_of and max_of report nothing for nothing"
  assert min_of([3, 7, 1]) == 1
  assert max_of([3, 7, 1]) == 7
  assert min_of([5]) == 5
  assert max_of([5]) == 5
  assert min_of([3, 0 - 7, 2]) == 0 - 7
  # A fold seeded with a big/small sentinel answers that sentinel here.
  assert min_of([]) == nil
  assert max_of([]) == nil
  assert min_of(nil) == nil
  assert max_of(nil) == nil
end

test "gcd_of and lcm_of are seeded with the right identity"
  # gcd_of seeded with 1 would return 1 for everything; lcm_of seeded with 0
  # would return 0 for everything. These two lines catch both.
  assert gcd_of([12, 18, 24]) == 6
  assert lcm_of([4, 6]) == 12
  assert lcm_of([2, 3, 4]) == 12
  assert gcd_of([7, 13]) == 1
  # The identities themselves.
  assert gcd_of([]) == 0
  assert lcm_of([]) == 1
  assert gcd_of([0, 0]) == 0
  assert gcd_of([9]) == 9
  assert lcm_of([9]) == 9
end

test "lerp hits both endpoints exactly and extrapolates past them"
  # Exact, not near: an endpoint that needs a tolerance is a broken lerp.
  assert lerp(0, 10, 0) == 0
  assert lerp(0, 10, 1) == 10
  assert lerp(10, 20, 1) == 20
  # The middle goes through a float, so it needs near().
  assert near(lerp(0, 10, 0.5), 5) == true
  assert near(lerp(10, 20, 0.5), 15) == true
  assert near(lerp(0, 10, 0.25), 2.5) == true
  # t outside [0,1] extrapolates. A lerp that clamps returns 10 here.
  assert near(lerp(0, 10, 2), 20) == true
  assert near(lerp(0, 10, 0 - 1), 0 - 10) == true
end

test "round_to keeps the places asked for"
  assert round_to(3.14159, 2) == 3.14
  assert round_to(3.14159, 4) == 3.1416
  assert round_to(1 / 3, 3) == 0.333
  # Zero places is a whole number, rounded half away from zero.
  assert round_to(2.5, 0) == 3
  assert round_to(2.4, 0) == 2
  # Already-short input is left alone rather than lengthened.
  assert round_to(5, 2) == 5
end

test "percent and percent_change, where the denominator is the trap"
  assert percent(25, 200) == 12.5
  assert percent(1, 4) == 25
  assert percent(0, 5) == 0
  assert percent(200, 200) == 100
  # The asymmetry: the same absolute move is a different percentage each way,
  # because the denominator is where you started. A formula dividing by `to`
  # gives 20 and -25 here, which is the classic reversal.
  assert percent_change(200, 250) == 25
  assert percent_change(250, 200) == 0 - 20
  assert percent_change(100, 100) == 0
  assert percent_change(100, 200) == 100
end
