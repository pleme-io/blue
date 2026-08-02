use("retsu")
use("shuugou")
use("junjo")
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

# A draw in [0, bound) taken from the TOP of the word rather than the bottom.
#
# This exists because `next_int` is wrong for small bounds and cannot be fixed
# without changing its answers. The multiplier and the increment are both odd,
# so s(n+1) = s(n) + 1 (mod 2) exactly — the low bit of this generator
# ALTERNATES. `take_ints(seed, 2, n)` is 0,1,0,1 forever, and every d6 stream
# drawn with `% 6` flips parity on every roll. Dividing by the modulus first
# throws the bad bits away instead of returning them.
def next_uniform(seed, bound)
  floor(next_float(seed) * bound)
end

# The top bit, for the same reason: `next_int(seed, 2)` would be a metronome.
def next_bool(seed)
  next_seed(seed) >= 2147483648
end

def take_bools(seed, n)
  if n < 1
    []
  else
    cons(next_bool(seed), take_bools(next_seed(seed), n - 1))
  end
end

# n floats in [0, 1). Never reaches 1: the largest seed is 2^32 - 1.
def take_floats(seed, n)
  if n < 1
    []
  else
    cons(next_float(seed), take_floats(next_seed(seed), n - 1))
  end
end

# Dice are 1-based, which is the whole reason these exist rather than callers
# writing next_uniform themselves and getting a 0 on the table.
def roll(seed, sides)
  1 + next_uniform(seed, sides)
end

def roll_dice(seed, count, sides)
  if count < 1
    []
  else
    cons(roll(seed, sides), roll_dice(next_seed(seed), count - 1, sides))
  end
end

def roll_sum(seed, count, sides)
  reduce(fn(a, b) a + b end, 0, roll_dice(seed, count, sides))
end

# Roll with advantage: the best of `count` dice, reproducibly.
def roll_best(seed, count, sides)
  max_of(roll_dice(seed, count, sides))
end

def roll_worst(seed, count, sides)
  min_of(roll_dice(seed, count, sides))
end

# Two seeds whose streams do not overlap, for handing an independent source to
# a sub-computation without threading one seed through it.
#
# The naive split — [seed, next_seed(seed)] — gives two streams offset by ONE
# step, so the second replays the first nineteen values out of twenty. The
# offset is the 32-bit golden ratio, which lands the second stream far enough
# along the cycle that the overlap is a coincidence rather than a structure.
def split_seed(seed)
  [next_seed(seed), next_seed(modulo(seed + 2654435769, 4294967296))]
end

# `choice` off the top of the word. Kept separate rather than folded into
# `choice`, whose answers other packages already depend on: picking from a
# two-element list with `choice` alternates, and picking from an eight-element
# one cycles its low three bits, which is exactly how a shuffle stops shuffling.
def pick(seed, xs)
  nth(next_uniform(seed, size(xs)), xs)
end

# n picks WITH replacement — repeats are expected, and the list is not consumed.
def choices(seed, xs, n)
  if n < 1
    []
  else
    cons(pick(seed, xs), choices(next_seed(seed), xs, n - 1))
  end
end

# Fisher-Yates, written as select-and-remove because there is no mutable array
# to swap inside: draw a position, take that element out, recurse on the rest.
# Same distribution as the swapping form, and the seed threads visibly.
def shuffle(seed, xs)
  if is_empty(xs)
    []
  else
    i = next_uniform(seed, size(xs))
    cons(nth(i, xs), shuffle(next_seed(seed), remove_at(xs, i)))
  end
end

# n picks WITHOUT replacement. Asking for more than there is gives everything
# rather than an error, which is what a caller sampling a short list means.
def sample_n(seed, xs, n)
  take_n(shuffle(seed, xs), n)
end

def total_weight(ws)
  reduce(fn(a, b) a + b end, 0, ws)
end

# Walk the weights subtracting as we go — the inverse-CDF pick.
#
# The subtraction is the piece that is easy to omit, and omitting it is
# invisible with two buckets: [1, 1, 1] is the smallest case where the middle
# option silently becomes unreachable. The comparison is strict, so a bucket
# of weight 0 is stepped over rather than matched at r = 0.
def weight_walk(xs, ws, r)
  if is_empty(rest(ws))
    first(xs)
  else
    if r < first(ws)
      first(xs)
    else
      weight_walk(rest(xs), rest(ws), r - first(ws))
    end
  end
end

# Weights need not be normalised and need not be integers; they are divided by
# their own total. All-zero weights are a caller error rather than a meaning —
# the walk falls through to the LAST bucket, which is at least total and
# pinned by a test rather than left to be discovered.
def weighted_choice(seed, xs, ws)
  weight_walk(xs, ws, next_float(seed) * total_weight(ws))
end

# Box-Muller. Consumes TWO words of the stream, which is why take_gaussians
# advances twice per draw — reusing one word for both u1 and u2 correlates the
# radius with the angle and the result stops being normal.
#
# u1 is (s + 1) / (2^32 + 1) rather than s / 2^32 so it can never be exactly 0:
# log(0) is where this formula blows up, and seed 0 reaches it.
def next_gaussian(seed)
  s1 = next_seed(seed)
  s2 = next_seed(s1)
  u1 = (s1 + 1) / 4294967297
  u2 = s2 / 4294967296
  sqrt(0 - (2 * log(u1))) * cos(6.283185307179586 * u2)
end

def next_normal(seed, mean, sd)
  mean + (sd * next_gaussian(seed))
end

def take_gaussians(seed, n)
  if n < 1
    []
  else
    cons(next_gaussian(seed), take_gaussians(next_seed(next_seed(seed)), n - 1))
  end
end

def next_step(seed)
  if next_bool(seed)
    1
  else
    0 - 1
  end
end

# Positions, not steps: the caller wants the path. Each entry differs from the
# one before it by exactly 1, which is the property that separates a walk from
# a list of draws.
def random_walk(seed, n)
  running_sum(map(fn(s) next_step(s) end, seeds(seed, n)))
end

test "next_uniform stays in bounds and covers them"
  vs = map(fn(s) next_uniform(s, 6) end, seeds(4, 200))
  assert every(fn(v) v >= 0 && v < 6 end, vs) == true
  # A generator that never emits 0 or never emits 5 still passes a bounds
  # check; only the face count catches it.
  assert size(unique(vs)) == 6
end

test "next_uniform escapes the alternating low bit that next_int is stuck with"
  # The distinguishing property, and the reason next_uniform exists at all:
  # a two-valued stream off the low bit repeats NO value twice in a row.
  bits = map(fn(s) next_uniform(s, 2) end, seeds(1, 12))
  low = take_ints(1, 2, 12)
  assert any(fn(p) first(p) == last(p) end, zip(bits, rest(bits))) == true
  assert any(fn(p) first(p) == last(p) end, zip(low, rest(low))) == false
end

test "next_bool is both values, and is not a metronome"
  assert next_bool(1) == next_bool(1)
  # next_seed(1) is 1015568748, below half the modulus.
  assert next_bool(1) == false
  bs = take_bools(9, 60)
  assert size(unique(bs)) == 2
  assert size(bs) == 60
  assert take_bools(9, 0) == []
  # Off the low bit this would be true,false,true,false forever — the coin
  # would land the same way every second toss and both the value check above
  # and a fair-looking 30/30 count would still pass.
  assert any(fn(p) first(p) == last(p) end, zip(bs, rest(bs))) == true
end

test "take_floats lands in the unit interval and averages near its middle"
  fs = take_floats(21, 400)
  assert every(fn(f) f >= 0 && f < 1 end, fs) == true
  assert size(fs) == 400
  assert take_floats(21, 0) == []
  # A stuck stream also satisfies the bounds; the mean does not.
  assert near_within(reduce(fn(a, b) a + b end, 0, fs) / 400, 0.5, 0.05) == true
end

test "a die never shows zero and never shows sides + 1"
  vs = roll_dice(6, 120, 6)
  assert every(fn(v) v >= 1 && v <= 6 end, vs) == true
  assert size(vs) == 120
  # The off-by-one that a bounds check on a d6 misses entirely.
  assert every(fn(s) roll(s, 1) == 1 end, seeds(3, 20)) == true
  assert roll_dice(6, 0, 6) == []
  assert roll_sum(6, 0, 6) == 0
end

test "roll_sum adds the dice rather than picking one of them"
  # 4d20 lives in [4, 80] and nowhere else; a sum mistaken for a max or a
  # single roll collapses into [1, 20] and never leaves it.
  totals = map(fn(s) roll_sum(s, 4, 20) end, seeds(77, 60))
  assert every(fn(t) t >= 4 && t <= 80 end, totals) == true
  assert any(fn(t) t > 20 end, totals) == true
  # One die summed is that die.
  assert every(fn(s) roll_sum(s, 1, 6) == roll(s, 6) end, seeds(12, 20)) == true
  # 2d6 cannot be 1, however the dice fall — the off-by-one a range check on a
  # single die would let through.
  assert every(fn(s) roll_sum(s, 2, 6) >= 2 end, seeds(12, 40)) == true
end

test "advantage of one die is that die"
  assert every(fn(s) roll_best(s, 1, 20) == roll(s, 20) end, seeds(31, 15)) == true
  assert every(fn(s) roll_worst(s, 1, 20) == roll(s, 20) end, seeds(31, 15)) == true
  assert roll_best(5, 3, 6) >= roll_worst(5, 3, 6)
end

test "split_seed gives two streams that do not replay each other"
  p = split_seed(1)
  a = first(p)
  b = last(p)
  # The failure this catches: b = next_seed(a), which shares 19 of these 20.
  assert is_empty(intersection(take_ints(a, 1000000, 20), take_ints(b, 1000000, 20))) == true
  assert is_empty(intersection(take_ints(a, 1000000, 20), take_ints(next_seed(a), 1000000, 20))) == false
  assert split_seed(1) == split_seed(1)
  assert split_seed(1) != split_seed(2)
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

test "shuffle returns a permutation, not a sample"
  xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  s = shuffle(42, xs)
  # The property a broken shuffle fails: a dropped, duplicated or invented
  # element survives a size check but not this one.
  assert sort(s) == sort(xs)
  assert size(s) == 10
  assert shuffle(42, xs) == shuffle(42, xs)
  assert shuffle(1, xs) != shuffle(2, xs)
end

test "shuffle actually reorders, and handles the degenerate lists"
  xs = [1, 2, 3, 4, 5, 6, 7, 8]
  assert shuffle(42, xs) != xs
  assert shuffle(7, []) == []
  assert shuffle(7, [9]) == [9]
  # A shuffle that only ever rotates also permutes; it must not fix element 0
  # for every seed.
  assert any(fn(s) first(shuffle(s, xs)) != 1 end, seeds(5, 10)) == true
end

test "shuffle reaches both orders of a two-element list"
  # A shuffle that is secretly a fixed reordering — the identity, or a plain
  # reverse — permutes correctly and passes the sort test above. Only asking
  # for both outcomes across seeds separates it from a real one.
  outs = map(fn(s) shuffle(s, [1, 2]) end, seeds(3, 20))
  assert contains(outs, [1, 2]) == true
  assert contains(outs, [2, 1]) == true
end

test "sample_n draws without replacement"
  xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  s = sample_n(88, xs, 4)
  assert size(s) == 4
  # Without replacement means no repeats — the one thing that separates this
  # from `choices`.
  assert size(unique(s)) == 4
  assert subset(s, xs) == true
  assert sample_n(88, xs, 0) == []
  # Asking for more than exists yields everything, not an error or a short list.
  assert sort(sample_n(88, xs, 50)) == sort(xs)
end

test "choices draws WITH replacement"
  cs = choices(5, [1, 2], 30)
  assert size(cs) == 30
  assert subset(cs, [1, 2]) == true
  # The distinguishing pair: repeats must be possible here and impossible in
  # sample_n over the same two-element list.
  assert any(fn(p) first(p) == last(p) end, zip(cs, rest(cs))) == true
  assert size(unique(sample_n(5, [1, 2], 2))) == 2
end

test "pick is a member, and is not stuck on the low bits"
  assert every(fn(s) contains([1, 2, 3], pick(s, [1, 2, 3])) end, seeds(4, 30)) == true
  ps = map(fn(s) pick(s, [1, 2]) end, seeds(1, 12))
  assert any(fn(p) first(p) == last(p) end, zip(ps, rest(ps))) == true
end

test "a weight of zero is never chosen"
  # The case a plausible `<=` walk gets wrong, and the reason weighted_choice
  # is worth having at all.
  assert every(fn(s) weighted_choice(s, ["a", "b"], [1, 0]) == "a" end, seeds(2, 40)) == true
  assert every(fn(s) weighted_choice(s, ["a", "b"], [0, 1]) == "b" end, seeds(2, 40)) == true
  assert every(fn(s) weighted_choice(s, ["a", "b", "c"], [0, 1, 0]) == "b" end, seeds(9, 40)) == true
end

test "weighted_choice follows the weights it was given"
  picks = map(fn(s) weighted_choice(s, ["a", "b"], [9, 1]) end, seeds(101, 200))
  # Equal treatment would give roughly 100 each; 9:1 must be lopsided.
  assert count_of(picks, "a") > (3 * count_of(picks, "b"))
  assert count_of(picks, "b") > 0
  # Equal weights must reach every option, including the last.
  assert size(unique(map(fn(s) weighted_choice(s, [1, 2, 3], [1, 1, 1]) end, seeds(5, 100)))) == 3
  assert weighted_choice(4, ["only"], [1]) == "only"
end

test "the degenerate weightings answer rather than error"
  # Documented, not desirable: with nothing to weigh, the walk runs off the
  # end. Pinned so a future change to weight_walk has to notice.
  assert weighted_choice(4, ["a", "b"], [0, 0]) == "b"
  assert weighted_choice(4, [], []) == nil
end

test "gaussians have the right centre AND the right spread"
  gs = take_gaussians(13, 400)
  assert size(gs) == 400
  m = reduce(fn(a, b) a + b end, 0, gs) / 400
  assert near_within(m, 0, 0.15) == true
  # The mean alone passes for any symmetric formula. The second moment is what
  # catches a dropped factor of 2 in sqrt(-2 log u), which would give 0.5.
  v = reduce(fn(a, b) a + (b * b) end, 0, gs) / 400
  assert near_within(v, 1, 0.2) == true
  assert any(fn(g) g < 0 end, gs) == true
  assert any(fn(g) g > 0 end, gs) == true
  assert take_gaussians(13, 0) == []
end

test "next_normal is next_gaussian shifted and scaled"
  # The identity a wrong scaling cannot satisfy.
  assert every(fn(s) next_normal(s, 0, 1) == next_gaussian(s) end, seeds(6, 20)) == true
  assert every(fn(s) near(next_normal(s, 10, 2), 10 + (2 * next_gaussian(s))) end, seeds(6, 20)) == true
  # Shifting by 100 must move the whole cloud, not widen it.
  ns = map(fn(s) next_normal(s, 100, 1) end, seeds(17, 200))
  assert every(fn(n) n > 94 && n < 106 end, ns) == true
end

test "a random walk steps by exactly one, every time"
  w = random_walk(23, 60)
  assert size(w) == 60
  assert random_walk(23, 0) == []
  assert contains([1, 0 - 1], first(w)) == true
  # The property that separates a walk from a list of draws: successive
  # positions are adjacent. A walk built from raw draws fails here.
  assert every(fn(p) abs(last(p) - first(p)) == 1 end, zip(w, rest(w))) == true
  # And it must actually wander rather than march.
  assert size(unique(w)) > 2
  assert random_walk(23, 60) == random_walk(23, 60)
end

test "one seed reproduces every stream; two seeds diverge"
  # The package's contract applied to each stream kind rather than to
  # next_seed alone: a function that quietly reached for anything outside its
  # seed would pass the generator test at the top of the file and fail here.
  assert take_floats(31, 20) == take_floats(31, 20)
  assert take_floats(31, 20) != take_floats(32, 20)
  assert take_bools(31, 20) == take_bools(31, 20)
  assert take_bools(31, 20) != take_bools(32, 20)
  assert take_gaussians(31, 20) == take_gaussians(31, 20)
  assert take_gaussians(31, 20) != take_gaussians(32, 20)
  assert roll_dice(31, 20, 6) == roll_dice(31, 20, 6)
  assert roll_dice(31, 20, 6) != roll_dice(32, 20, 6)
  assert random_walk(31, 20) == random_walk(31, 20)
  assert random_walk(31, 20) != random_walk(32, 20)
  assert choices(31, [1, 2, 3, 4], 20) == choices(31, [1, 2, 3, 4], 20)
  assert choices(31, [1, 2, 3, 4], 20) != choices(32, [1, 2, 3, 4], 20)
  assert shuffle(31, [1, 2, 3, 4, 5, 6]) == shuffle(31, [1, 2, 3, 4, 5, 6])
  assert shuffle(31, [1, 2, 3, 4, 5, 6]) != shuffle(32, [1, 2, 3, 4, 5, 6])
end
