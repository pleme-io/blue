use("junjo")
use("shuugou")
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

# The total sibling of `mean`: 0 rather than a 0/0 on the empty list.
#
# `mean` itself cannot be made total without changing a signature the rest of
# the distribution reads, so the guarded version lives beside it. Everything
# below that folds over deviations goes through this one, which is what makes
# those functions total without each repeating the same empty check.
def mean_or_zero(xs)
  if is_empty(xs)
    0
  else
    mean(xs)
  end
end

# Σ(x - mean)², the numerator every variance shares.
#
# Named for the statistics meaning — squared deviations FROM THE MEAN — not
# Σx². The two agree only when the mean is zero, so a reader who assumes the
# other one still gets a plausible number out, which is the worst kind of
# wrong. Every dispersion measure below is this divided by something.
def sum_of_squares(xs)
  m = mean_or_zero(xs)
  total(map(fn(x) (x - m) * (x - m) end, xs))
end

# The n-1 denominator: the variance of a POPULATION estimated from a SAMPLE.
#
# Dividing by n biases the estimate low, because the deviations are measured
# about the sample's own mean rather than the true one, and the sample mean
# sits closer to its own points than the true mean does. So this is always
# LARGER than `variance` on the same input — the property the test pins,
# because a copy-paste of the population formula still passes every other
# assertion you would think to write.
#
# One point carries no spread information at all, so it answers 0 rather
# than dividing by zero.
def sample_variance(xs)
  if size(xs) < 2
    0
  else
    sum_of_squares(xs) / (size(xs) - 1)
  end
end

def sample_stddev(xs)
  sqrt(sample_variance(xs))
end

# Spread of the sample MEAN, not of the data: how far the mean itself would
# wander if the sample were drawn again. Shrinks as sqrt(n), which is why
# quadrupling a sample only halves it.
def standard_error(xs)
  if is_empty(xs)
    0
  else
    sample_stddev(xs) / sqrt(size(xs))
  end
end

# Mean distance from the mean, without the squaring.
#
# Kept alongside stddev rather than replaced by it: squaring lets one far
# point dominate, so these two disagree on exactly the data where the
# disagreement matters.
def mean_absolute_deviation(xs)
  if is_empty(xs)
    0
  else
    m = mean(xs)
    total(map(fn(x) abs(x - m) end, xs)) / size(xs)
  end
end

# The mean of RATIOS — growth rates, index numbers, anything multiplicative.
#
# Computed through logs rather than as the n-th root of the product, because
# the product overflows long before the mean gets large. log is undefined at
# and below zero, so the caller owns keeping every element positive; this
# does not pretend otherwise by returning a number anyway.
def geometric_mean(xs)
  if is_empty(xs)
    0
  else
    exp(total(map(fn(x) log(x) end, xs)) / size(xs))
  end
end

# The mean of RATES — speeds, prices per unit, anything "per something".
#
# n / Σ(1/x). Averaging 30 and 60 km/h over equal DISTANCES gives 40, not
# 45, because more time is spent at the slower speed; that is the test.
def harmonic_mean(xs)
  if is_empty(xs)
    0
  else
    size(xs) / total(map(fn(x) 1 / x end, xs))
  end
end

# Weights need not sum to 1 — they are normalised here, so counts, hours and
# percentages all work as weights without the caller rescaling them first.
# Pairs are taken up to the shorter list, so a mismatched pair drops the
# tail rather than reading past the end.
def weighted_mean(xs, ws)
  w = total(ws)
  if near(w, 0)
    0
  else
    total(zip_with(fn(x, k) x * k end, xs, ws)) / w
  end
end

# Midpoint of the extremes. Deliberately ignores everything in between,
# which is the whole difference from `mean` and the only reason to have it:
# it answers "where is the middle of the RANGE", not "where is the middle of
# the DATA".
def midrange(xs)
  if is_empty(xs)
    0
  else
    (smallest(xs) + largest(xs)) / 2
  end
end

# Stddev as a fraction of the mean, so spreads measured in different units
# can be compared. Undefined at mean zero — guarded with `near` rather than
# `== 0` because a float mean of 0.0 does not equal the integer 0 on this
# runtime, and the naive guard would let an infinity through.
def coefficient_of_variation(xs)
  m = mean_or_zero(xs)
  if near(m, 0)
    0
  else
    stddev(xs) / m
  end
end

# median that answers 0 on the empty list instead of indexing off the end.
# Exists so every quartile helper below can be total without repeating the
# guard four times.
def median_or_zero(xs)
  if is_empty(xs)
    0
  else
    median(xs)
  end
end

# The two halves either side of the median, EXCLUDING the median itself when
# there is an odd number of points. That exclusion is Tukey's convention and
# it is what makes q1/q3 land where a boxplot draws them.
def lower_half(xs)
  s = sort(xs)
  take(floor(size(s) / 2), s)
end

def upper_half(xs)
  s = sort(xs)
  drop(ceiling(size(s) / 2), s)
end

# Quartiles as medians of the halves — NOT `percentile(xs, 0.25)`.
#
# `percentile` is a nearest-rank index: it always returns an element that is
# really in the list, so on [1,2,3,4] it answers 2 for the median where the
# median is 2.5. Defining quartiles that way would make q2 disagree with
# `median` on every even-length input, and the IQR fences below are drawn
# against THIS convention, so mixing the two would quietly move them. The
# identity the test pins is q2 == median(xs), for both parities.
#
# A one-element list has no half to take a median of; it falls back to the
# whole list, so q1 == q3 == that element rather than an index error.
def q1(xs)
  h = lower_half(xs)
  if is_empty(h)
    median_or_zero(xs)
  else
    median(h)
  end
end

def q3(xs)
  h = upper_half(xs)
  if is_empty(h)
    median_or_zero(xs)
  else
    median(h)
  end
end

def quartiles(xs)
  [q1(xs), median_or_zero(xs), q3(xs)]
end

# The middle half's width — the spread measure that a single wild point
# cannot move, which is exactly why outliers are defined against it rather
# than against stddev (a big enough outlier inflates stddev until it stops
# looking like one).
def iqr(xs)
  q3(xs) - q1(xs)
end

# Tukey's 1.5×IQR cut points, returned as [low, high].
#
# Exposed rather than kept inside `outliers` because a caller usually needs
# to know WHERE the line fell, not only which points crossed it.
def fences(xs)
  lo = q1(xs)
  hi = q3(xs)
  w = 1.5 * (hi - lo)
  [lo - w, hi + w]
end

# Points outside the fences, in input order. Empty means "nothing unusual",
# which is the answer for well-behaved data and the case a threshold-off-by
# -one still gets wrong.
def outliers(xs)
  f = fences(xs)
  lo = nth(0, f)
  hi = nth(1, f)
  filter(fn(x) (x < lo) || (x > hi) end, xs)
end

# The inverse of `percentile`: what fraction of the data is at or below x.
# Answers in [0, 1], so `percentile_rank(largest(xs), xs)` is always 1.
def percentile_rank(x, xs)
  if is_empty(xs)
    0
  else
    size(filter(fn(y) y <= x end, xs)) / size(xs)
  end
end

# Population covariance: the mean product of paired deviations.
#
# Pairs are taken up to the shorter list, and BOTH means are taken over that
# same truncated prefix — computing a mean over the full list and a product
# over the prefix is the mismatch that makes a covariance quietly wrong on
# ragged input.
def covariance(xs, ys)
  n = min(size(xs), size(ys))
  if n == 0
    0
  else
    mx = mean(take(n, xs))
    my = mean(take(n, ys))
    total(zip_with(fn(x, y) (x - mx) * (y - my) end, xs, ys)) / n
  end
end

# Pearson r — covariance divided by both spreads, so it is unitless and
# lands in [-1, 1].
#
# Answers 0 when either series is constant. r is genuinely undefined there
# (the denominator is zero), and 0 reports "no linear relationship found"
# rather than inventing an infinity or a NaN that then poisons everything
# downstream.
def correlation(xs, ys)
  d = stddev(xs) * stddev(ys)
  if near(d, 0)
    0
  else
    covariance(xs, ys) / d
  end
end

# How many standard deviations x sits from the mean — the transform that
# makes two differently-scaled series comparable. Zero spread means every
# point IS the mean, so every score is 0.
def z_score(x, xs)
  s = stddev(xs)
  if near(s, 0)
    0
  else
    (x - mean(xs)) / s
  end
end

def z_scores(xs)
  map(fn(x) z_score(x, xs) end, xs)
end

# Min-max rescaling onto [0, 1].
#
# A constant list has no range to divide by; it maps to all zeros rather
# than erroring, which keeps this total. Note this is a DIFFERENT rescaling
# from `z_scores` — this one pins the extremes and lets the shape move,
# z-scores pin the mean and spread and let the extremes move.
def rescale(xs)
  if is_empty(xs)
    []
  else
    lo = smallest(xs)
    w = largest(xs) - lo
    if near(w, 0)
      map(fn(x) 0 end, xs)
    else
      map(fn(x) (x - lo) / w end, xs)
    end
  end
end

# Running totals, ONE PER INPUT ELEMENT — so the last entry is exactly
# `total(xs)`. That identity is the thing to check: an off-by-one in the
# window shows up there before it shows up anywhere else.
def cumulative_sum(xs)
  map(fn(i) total(take(i + 1, xs)) end, indexes(xs))
end

# Simple moving average, one value per COMPLETE window.
#
# The result is shorter than the input by w-1. The alternative — padding the
# start with averages of partial windows — returns numbers that are not
# averages of w points while looking exactly like ones that are, so the
# short-and-honest result is the one worth having.
def moving_average(xs, w)
  if w < 1
    []
  else
    if size(xs) < w
      []
    else
      map(fn(i) mean(take(w, drop(i, xs))) end, range(0, size(xs) - w + 1))
    end
  end
end

# Population skewness: which tail is longer. Positive means the long tail is
# to the RIGHT (a few large values), negative to the left, zero symmetric.
# Negating every value must negate the answer — that is the test, and a
# formula that squares where it should cube still fails it.
def skewness(xs)
  if is_empty(xs)
    0
  else
    m = mean(xs)
    s = stddev(xs)
    if near(s, 0)
      0
    else
      total(map(fn(x) pow((x - m) / s, 3) end, xs)) / size(xs)
    end
  end
end

# EXCESS kurtosis — the normal distribution scores 0, not 3.
#
# The bare fourth moment ratio scores 3 for a normal, and reporting that as
# "kurtosis" is the classic off-by-three: every reader has to know which
# convention was used before the number means anything. Subtracting the 3
# here puts the answer on the scale where the sign alone is readable —
# positive is heavier-tailed than normal, negative is lighter.
def excess_kurtosis(xs)
  if is_empty(xs)
    0
  else
    m = mean(xs)
    s = stddev(xs)
    if near(s, 0)
      0
    else
      total(map(fn(x) pow((x - m) / s, 4) end, xs)) / size(xs) - 3
    end
  end
end

# How many times x occurs. The counting primitive the three functions below
# share, rather than three separate walks that can drift apart.
def tally(x, xs)
  size(filter(fn(y) y == x end, xs))
end

# Every distinct value paired with its count, ascending by value.
#
# `unique` is shuugou's — imported rather than rewritten, because a second
# duplicate-removal in the distribution is a second place for first-seen
# order to be got wrong. Sorting first makes the output order a property of
# the DATA rather than of how the caller happened to build the list.
def frequency_table(xs)
  map(fn(v) [v, tally(v, xs)] end, unique(sort(xs)))
end

# The most frequent value; nil for the empty list.
#
# Ties break to the SMALLEST of the tied values. Some rule is needed and
# "whichever the input happened to list first" is the one to avoid: it makes
# mode([1,1,2,2]) disagree with mode([2,2,1,1]) on data that is identical as
# a multiset. When the tie itself is the finding, use `modes`.
def mode(xs)
  if is_empty(xs)
    nil
  else
    reduce(fn(best, v) if tally(v, xs) > tally(best, xs)
      v
    else
      best
    end end, smallest(xs), unique(sort(xs)))
  end
end

# Every value tied for most frequent, ascending.
#
# Exists because `mode` has to pick one, and a genuinely bimodal set has no
# single answer — reporting one hides exactly the structure worth seeing.
# A list with no repeats at all is ALL mode, which is the honest reading.
def modes(xs)
  if is_empty(xs)
    []
  else
    best = tally(mode(xs), xs)
    filter(fn(v) tally(v, xs) == best end, unique(sort(xs)))
  end
end

# The five-number summary a boxplot is drawn from, in the order it is drawn:
# [min, q1, median, q3, max]. Grouped because these five are read together,
# and answers [] rather than a list with nils in it for the empty input —
# a nil inside a numeric list propagates into arithmetic somewhere later,
# which is much harder to trace back than an obviously empty answer.
def five_number_summary(xs)
  if is_empty(xs)
    []
  else
    [smallest(xs), q1(xs), median_or_zero(xs), q3(xs), largest(xs)]
  end
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

test "sample_variance uses n-1 and therefore DIFFERS from the population one"
  # The distinction the whole pair exists for. Same data, same numerator,
  # different denominator: 5/3 against 5/4.
  assert variance([1, 2, 3, 4]) == 1.25
  assert near(sample_variance([1, 2, 3, 4]), 5 / 3) == true
  assert sample_variance([1, 2, 3, 4]) > variance([1, 2, 3, 4])
  # A constant list has no spread under either convention.
  assert sample_variance([5, 5, 5]) == 0
  # Below two points there is nothing to estimate from.
  assert sample_variance([7]) == 0
  assert sample_variance([]) == 0
end

test "sum_of_squares is deviations from the mean, not raw squares"
  # Σx² would be 1+4+9 = 14 here. The mean is 2, so the answer is 2.
  assert sum_of_squares([1, 2, 3]) == 2
  assert sum_of_squares([5, 5, 5]) == 0
  assert sum_of_squares([]) == 0
  # The identity that ties it to variance.
  assert near(sum_of_squares([2, 4, 6, 8]) / 4, variance([2, 4, 6, 8])) == true
end

test "standard_error shrinks as the sample grows"
  # sd/sqrt(n) = sqrt(2.5)/sqrt(5) = sqrt(0.5), checkable by hand.
  assert near(standard_error([1, 2, 3, 4, 5]), sqrt(0.5)) == true
  assert standard_error([]) == 0
  # Same spread, four times the data: half the standard error.
  a = [1, 2, 3, 4]
  b = [1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4]
  assert standard_error(b) < standard_error(a)
end

test "mean_absolute_deviation is not stddev"
  # [1,2,3,4]: deviations 1.5,0.5,0.5,1.5 -> mean 1. stddev is sqrt(1.25).
  # Asserted with `near`, not `==`: the deviations are floats, so the answer
  # is Float(1.0), and Float(1.0) == Int(1) is false on this runtime.
  assert near(mean_absolute_deviation([1, 2, 3, 4]), 1) == true
  assert mean_absolute_deviation([1, 2, 3, 4]) < stddev([1, 2, 3, 4])
  assert mean_absolute_deviation([5, 5, 5]) == 0
  assert mean_absolute_deviation([]) == 0
end

test "geometric_mean averages ratios"
  # 1, 4, 16 doubles-and-doubles: the middle of that progression is 4.
  assert near(geometric_mean([1, 4, 16]), 4) == true
  assert near(geometric_mean([2, 8]), 4) == true
  # Equal to the arithmetic mean only when every element is equal.
  assert near(geometric_mean([5, 5, 5]), 5) == true
  # AM-GM: the geometric mean never exceeds the arithmetic one.
  assert geometric_mean([1, 4, 16]) < mean([1, 4, 16])
end

test "harmonic_mean averages rates"
  # 30 and 60 km/h over equal distances average 40, not 45.
  assert near(harmonic_mean([30, 60]), 40) == true
  assert near(mean([30, 60]), 45) == true
  assert near(harmonic_mean([1, 2, 4]), 12 / 7) == true
  assert near(harmonic_mean([5, 5, 5]), 5) == true
end

test "weighted_mean reduces to mean under equal weights"
  # The identity that catches a wrong normalisation.
  assert weighted_mean([1, 2, 3], [1, 1, 1]) == mean([1, 2, 3])
  assert weighted_mean([1, 2, 3], [2, 2, 2]) == mean([1, 2, 3])
  # 90 counting triple against 80 counting once.
  assert weighted_mean([90, 80], [3, 1]) == 87.5
  # All the weight on one point returns that point.
  assert weighted_mean([1, 100], [0, 1]) == 100
  assert weighted_mean([1, 2], [0, 0]) == 0
end

test "midrange ignores everything between the extremes"
  assert midrange([1, 2, 3, 100]) == 50.5
  # The mean does not, which is the difference that matters.
  assert mean([1, 2, 3, 100]) == 26.5
  assert midrange([5, 5, 5]) == 5
  assert midrange([]) == 0
end

test "coefficient_of_variation is unitless"
  # mean 5, stddev 2 -> 0.4, all three checkable by hand.
  xs = [2, 4, 4, 4, 5, 5, 7, 9]
  assert mean(xs) == 5
  assert variance(xs) == 4
  assert near(coefficient_of_variation(xs), 0.4) == true
  # Doubling every value doubles the spread AND the mean: the ratio holds.
  assert near(coefficient_of_variation(map(fn(x) x * 2 end, xs)), 0.4) == true
  assert near(coefficient_of_variation([5, 5, 5]), 0) == true
  # Total: a mean of zero has no scale to divide by, and neither has nothing.
  assert coefficient_of_variation([0 - 2, 2]) == 0
  assert coefficient_of_variation([]) == 0
end

test "q2 IS the median, for both parities"
  # The identity that separates this convention from a nearest-rank one:
  # on [1,2,3,4] the nearest-rank quartile would answer 2, not 2.5.
  assert nth(1, quartiles([1, 2, 3, 4])) == median([1, 2, 3, 4])
  assert nth(1, quartiles([1, 2, 3, 4, 5])) == median([1, 2, 3, 4, 5])
  assert quartiles([1, 2, 3, 4]) == [1.5, 2.5, 3.5]
  # Odd length: the median is excluded from both halves.
  assert quartiles([1, 2, 3, 4, 5]) == [1.5, 3, 4.5]
  # Unsorted input must give the same answer as sorted.
  assert quartiles([5, 1, 4, 2, 3]) == quartiles([1, 2, 3, 4, 5])
end

test "quartiles are total on short and empty lists"
  assert quartiles([]) == [0, 0, 0]
  assert quartiles([7]) == [7, 7, 7]
  assert quartiles([1, 3]) == [1, 2, 3]
  assert iqr([7]) == 0
  assert iqr([]) == 0
end

test "iqr ignores the tails that spread does not"
  # Same middle, wildly different extremes: iqr holds, spread explodes.
  a = [1, 2, 3, 4, 5, 6, 7, 8]
  b = [0 - 1000, 2, 3, 4, 5, 6, 7, 1000]
  # `near`, not `==`: both quartiles are half-way values, so the width is
  # Float(4.0) and Float(4.0) == Int(4) is false here.
  assert near(iqr(a), 4) == true
  assert near(iqr(b), 4) == true
  assert spread(a) == 7
  assert spread(b) == 2000
end

test "outliers by the 1.5 IQR fences"
  # q1 = 3, q3 = 8, iqr = 5, so the fences are -4.5 and 15.5.
  xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 100]
  assert q1(xs) == 3
  assert q3(xs) == 8
  assert fences(xs) == [0 - 4.5, 15.5]
  assert outliers(xs) == [100]
  # Well-behaved data has none — the case a too-tight threshold fails.
  assert outliers([1, 2, 3, 4, 5]) == []
  assert outliers([5, 5, 5, 5]) == []
  assert outliers([]) == []
  # Both tails, and the result keeps input order rather than sorted order.
  assert outliers([50, 1, 2, 3, 4, 5, 6, 7, 8, 0 - 50]) == [50, 0 - 50]
end

test "percentile_rank inverts percentile"
  xs = [1, 2, 3, 4, 5]
  assert percentile_rank(3, xs) == 0.6
  assert percentile_rank(5, xs) == 1
  assert percentile_rank(0, xs) == 0
  # The largest value always ranks 1, whatever the data.
  assert percentile_rank(largest([3, 9, 1, 7]), [3, 9, 1, 7]) == 1
  assert percentile_rank(1, []) == 0
end

test "covariance of a series with ITSELF is its variance"
  # The identity that catches a dropped deviation or a wrong denominator.
  assert near(covariance([1, 2, 3], [1, 2, 3]), variance([1, 2, 3])) == true
  # Reversed: same magnitude, opposite sign.
  assert near(covariance([1, 2, 3], [3, 2, 1]), 0 - variance([1, 2, 3])) == true
  # Nothing co-varies with a constant.
  assert covariance([1, 2, 3], [5, 5, 5]) == 0
  assert covariance([], []) == 0
  assert covariance([1, 2, 3], []) == 0
  # Order of the arguments cannot matter.
  a = [2, 4, 4, 4, 5]
  b = [1, 3, 5, 7, 9]
  assert covariance(a, b) == covariance(b, a)
end

test "correlation lands in [-1, 1] and is unitless"
  # Perfectly linear, different scales: r is 1 either way.
  assert near(correlation([1, 2, 3], [2, 4, 6]), 1) == true
  assert near(correlation([1, 2, 3], [100, 200, 300]), 1) == true
  assert near(correlation([1, 2, 3], [3, 2, 1]), 0 - 1) == true
  # A hand-checkable middle: cov 1, both stddevs sqrt(1.25) -> 1/1.25 = 0.8.
  assert near(correlation([1, 2, 3, 4], [1, 3, 2, 4]), 0.8) == true
  # Constant series: undefined, reported as 0 rather than an infinity.
  assert correlation([1, 2, 3], [5, 5, 5]) == 0
  assert correlation([5, 5, 5], [5, 5, 5]) == 0
end

test "z_scores have mean 0 and stddev 1"
  # The defining property of the transform, and the one a wrong denominator
  # breaks while every individual score still looks reasonable.
  xs = [2, 4, 4, 4, 5, 5, 7, 9]
  assert near(mean(z_scores(xs)), 0) == true
  assert near(stddev(z_scores(xs)), 1) == true
  # mean 5, stddev 2, so these are checkable by hand.
  assert near(z_score(5, xs), 0) == true
  assert near(z_score(9, xs), 2) == true
  assert near(z_score(2, xs), 0 - 1.5) == true
  # No spread means every point is the mean.
  assert z_score(5, [5, 5, 5]) == 0
end

test "rescale pins the extremes at 0 and 1"
  assert rescale([10, 20, 30]) == [0, 0.5, 1]
  # The invariant, on data with no round numbers in it at all.
  xs = [3, 17, 5, 11, 2]
  assert near(smallest(rescale(xs)), 0) == true
  assert near(largest(rescale(xs)), 1) == true
  # A constant list has no range to divide by.
  assert rescale([7, 7, 7]) == [0, 0, 0]
  assert rescale([]) == []
  # Rescaling is monotone: order is preserved.
  assert nth(0, rescale([3, 17, 5])) < nth(1, rescale([3, 17, 5]))
end

test "cumulative_sum ends at the total"
  assert cumulative_sum([1, 2, 3, 4]) == [1, 3, 6, 10]
  assert cumulative_sum([]) == []
  assert cumulative_sum([5]) == [5]
  # The identity: last entry is the whole sum, and length is preserved.
  xs = [4, 0 - 2, 9, 1]
  assert last(cumulative_sum(xs)) == total(xs)
  assert size(cumulative_sum(xs)) == size(xs)
end

test "moving_average returns one value per COMPLETE window"
  assert moving_average([1, 2, 3, 4, 5], 3) == [2, 3, 4]
  # Window of 1 is the identity — the case an off-by-one in the range breaks.
  assert moving_average([1, 2, 3], 1) == [1, 2, 3]
  # Window of n is the mean of the whole list, once.
  assert moving_average([1, 2, 3, 4], 4) == [2.5]
  # Length shrinks by exactly w-1, and a window that does not fit gives none.
  assert size(moving_average([1, 2, 3, 4, 5], 2)) == 4
  assert moving_average([1, 2], 5) == []
  assert moving_average([1, 2], 0) == []
  assert moving_average([], 3) == []
end

test "skewness signs the long tail"
  # Symmetric data has none — the case a formula that squares still passes,
  # which is why the negation identity below is asserted too.
  assert near(skewness([1, 2, 3, 4, 5]), 0) == true
  assert skewness([1, 1, 1, 10]) > 0
  assert skewness([1, 10, 10, 10]) < 0
  # Mirroring the data must mirror the answer.
  xs = [1, 2, 2, 3, 9]
  assert near(skewness(map(fn(x) 0 - x end, xs)), 0 - skewness(xs)) == true
  assert skewness([5, 5, 5]) == 0
  assert skewness([]) == 0
end

test "excess_kurtosis is on the normal-is-zero scale"
  # [1..5]: m2 = 2, m4 = 6.8, ratio 1.7, minus 3 -> -1.3. All by hand.
  assert near(excess_kurtosis([1, 2, 3, 4, 5]), 0 - 1.3) == true
  # Uniform-ish data is flatter than normal; a spike with outliers is not.
  assert excess_kurtosis([1, 2, 3, 4, 5]) < 0
  assert excess_kurtosis([1, 5, 5, 5, 5, 5, 9]) > 0
  assert excess_kurtosis([5, 5, 5]) == 0
  assert excess_kurtosis([]) == 0
end

test "mode does not depend on input order"
  # Identical as multisets, so they must agree. A first-seen tie-break
  # answers 1 for one and 2 for the other.
  assert mode([1, 1, 2, 2]) == mode([2, 2, 1, 1])
  assert mode([1, 1, 2, 2]) == 1
  assert mode([1, 2, 2, 3]) == 2
  assert mode([5]) == 5
  assert mode([]) == nil
  # The mode really is the most frequent value.
  xs = [4, 7, 4, 9, 4, 7]
  assert tally(mode(xs), xs) == 3
end

test "modes exposes the tie that mode has to hide"
  assert modes([1, 1, 2, 2]) == [1, 2]
  assert modes([1, 2, 2, 3]) == [2]
  # No repeats means everything ties at one occurrence.
  assert modes([3, 1, 2]) == [1, 2, 3]
  assert modes([]) == []
  # mode is always among the modes.
  assert contains(modes([4, 4, 9, 9, 1]), mode([4, 4, 9, 9, 1])) == true
end

test "frequency_table account for every element exactly once"
  assert frequency_table([3, 1, 1, 2]) == [[1, 2], [2, 1], [3, 1]]
  assert frequency_table([]) == []
  # The identity: the counts must sum back to the size of the input.
  xs = [5, 3, 5, 5, 1, 3, 9]
  assert total(map(fn(p) nth(1, p) end, frequency_table(xs))) == size(xs)
  assert size(frequency_table(xs)) == size(unique(xs))
end

test "five_number_summary is the boxplot, in drawing order"
  assert five_number_summary([1, 2, 3, 4, 5]) == [1, 1.5, 3, 4.5, 5]
  # It must agree with the parts it is built from, on any data.
  xs = [8, 2, 9, 4, 1, 6, 3]
  s = five_number_summary(xs)
  assert nth(0, s) == smallest(xs)
  assert nth(2, s) == median(xs)
  assert nth(4, s) == largest(xs)
  # Sorted ascending, always.
  assert nth(0, s) <= nth(1, s)
  assert nth(1, s) <= nth(2, s)
  assert nth(2, s) <= nth(3, s)
  assert nth(3, s) <= nth(4, s)
  # Empty in, empty out — never a list with nils hiding inside it.
  assert five_number_summary([]) == []
end
