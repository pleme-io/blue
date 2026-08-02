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

# --- the rest of the factorial family ---------------------------------------

# Double factorial: n * (n-2) * (n-4) * ... down to 2 or 1.
#
# Not factorial(n) doubled and not factorial(factorial(n)) — it is the product
# of every OTHER term, so 8!! is 384 where 8! is 40320. Both 0!! and (-1)!!
# are 1, the empty product, which is what lets the odd and even chains bottom
# out on the same branch.
def double_factorial(n)
  if n < 2
    1
  else
    n * double_factorial(n - 2)
  end
end

# Rising factorial (Pochhammer): n * (n+1) * ... * (n+k-1).
#
# The mirror of `permutations`, which falls. They agree only for k < 2:
# rising_factorial(5, 3) is 210 where permutations(5, 3) is 60. No k > n cutoff
# here — rising never runs out of terms, so nothing forces it to zero.
def rising_factorial(n, k)
  if k < 1
    1
  else
    n * rising_factorial(n + 1, k - 1)
  end
end

# C(2n, n) — the middle and largest entry of an even Pascal row, and the term
# catalan divides down.
def central_binomial(n)
  combinations(2 * n, n)
end

# Monotonic paths across a w-by-h grid, moving only right or up.
#
# A path is w rights and h ups in some order, so the count is which of the
# w+h steps are the rights — one binomial, not a search. This is the shape
# behind most "how many ways through" questions, which is why it gets a name
# instead of being spelled out at each call site.
def lattice_paths(w, h)
  combinations(w + h, w)
end

# Multinomial coefficient: how many distinct orderings a multiset with element
# counts `ks` has. (n; k1..km) = n! / (k1! * ... * km!).
#
# Built as a running product of binomials rather than from that quotient
# directly, because the quotient computes several factorials far larger than
# the answer while the binomial chain never exceeds it. MISSISSIPPI is
# multinomial([1, 4, 4, 2]) == 34650. The empty multiset has one ordering.
def multinomial(ks)
  nth(1, reduce(fn(acc, k)
    [nth(0, acc) + k, nth(1, acc) * combinations(nth(0, acc) + k, k)]
  end, [0, 1], ks))
end

# Choose k from n with repetition allowed and order ignored — "n multichoose k",
# the stars-and-bars count C(n+k-1, k).
#
# Three scoops from five flavours is 35, not the 10 `combinations` gives,
# because a repeat is legal. k=0 is guarded rather than left to the formula:
# C(n-1, 0) is 0 for n=0 under this file's k>n rule, and the empty selection
# is one way, not none.
def combinations_with_repetition(n, k)
  if k < 1
    1
  else
    combinations(n + k - 1, k)
  end
end

def multichoose(n, k)
  combinations_with_repetition(n, k)
end

# Ordered selections of k from n WITH repetition: n^k.
#
# The "how many 4-digit PINs" count — 10^4 = 10000, not permutations(10, 4).
# One arithmetic step rather than a fold, since that is all the identity is.
def permutations_with_repetition(n, k)
  expt(n, k)
end

# The sum of Pascal's nth row, which is also the number of subsets of an n-set.
#
# Returned as 2^n rather than by summing pascal_row(n): the closed form IS the
# identity, and summing would be counting by accumulation in the one place a
# single expt answers. The test checks the two against each other, so the
# shortcut stays honest.
def binomial_row_sum(n)
  expt(2, n)
end

# --- figurate numbers -------------------------------------------------------
#
# All four are closed forms, never a running sum: triangular(1000) is one
# multiply, not a thousand additions.

# 1 + 2 + ... + n, equivalently C(n+1, 2) — the handshake count.
def triangular(n)
  n * (n + 1) / 2
end

# n * (3n - 1) / 2: 1, 5, 12, 22, 35. The numbers Euler's partition recurrence
# steps by, which is why they live here rather than in a geometry package.
def pentagonal(n)
  n * (3 * n - 1) / 2
end

# n * (2n - 1): 1, 6, 15, 28. Every hexagonal number is a triangular one —
# hexagonal(n) == triangular(2n - 1) — which the test pins.
def hexagonal(n)
  n * (2 * n - 1)
end

# C(n+2, 3) — the triangular numbers stacked, i.e. cannonballs in a pyramid.
def tetrahedral(n)
  combinations(n + 2, 3)
end

# --- counts defined by a recurrence -----------------------------------------
#
# A recurrence with two recursive calls and no memo re-derives its whole tree
# on every call: the textbook `f(n-1) + f(n-2)` makes fibonacci(30) millions of
# calls for arithmetic that is thirty additions. Every count in this section
# therefore avoids that shape — the linear ones are walked FORWARD carrying the
# last two answers, and stirling2, whose recurrence branches on both arguments,
# is replaced by a closed form outright.

def fibonacci(n)
  fib_onward(n, 0, 1)
end

# `a` is F(i) and `b` is F(i+1); each step slides the window one place right.
def fib_onward(n, a, b)
  if n < 1
    a
  else
    fib_onward(n - 1, b, a + b)
  end
end

# Lucas numbers: the same recurrence as fibonacci, seeded 2, 1 instead of 0, 1.
# The seeds are the entire difference, which is why they share a step shape.
def lucas(n)
  lucas_onward(n, 2, 1)
end

def lucas_onward(n, a, b)
  if n < 1
    a
  else
    lucas_onward(n - 1, b, a + b)
  end
end

# Derangements (subfactorial !n): permutations that leave NOTHING in place.
#
# D(n) = (n-1) * (D(n-1) + D(n-2)), so 4 people can misdeliver 4 hats 9 ways.
# D(0) is 1 — the empty permutation moves everything it has — and D(1) is 0,
# which is the pair of seeds a plain n!/e rounding gets wrong at the bottom.
def derangements(n)
  if n < 1
    1
  else
    derangements_onward(n, 1, 1, 0)
  end
end

# `prev` is D(k-1) and `cur` is D(k), walked up to k = n.
def derangements_onward(n, k, prev, cur)
  if k >= n
    cur
  else
    derangements_onward(n, k + 1, cur, k * (cur + prev))
  end
end

def subfactorial(n)
  derangements(n)
end

# Stirling numbers of the second kind: ways to split an n-set into exactly k
# non-empty unlabelled blocks.
#
# Computed from the inclusion-exclusion closed form rather than the
# S(n,k) = k*S(n-1,k) + S(n-1,k-1) recurrence, because that recurrence has two
# recursive calls and no memo to share them — exponential for the same answer
# this sum reaches in k+1 terms. The division by k! is exact by construction:
# the sum counts ORDERED block assignments and k! is how many orderings each
# unordered partition was counted under.
def stirling2(n, k)
  if n < 0 || k < 0
    0
  else
    if k > n
      0
    else
      if k < 1
        # One way to partition nothing (into no blocks); no way to cover a
        # non-empty set with zero blocks.
        if n < 1
          1
        else
          0
        end
      else
        stirling2_terms(n, k, 0) / factorial(k)
      end
    end
  end
end

def stirling2_terms(n, k, j)
  if j > k
    0
  else
    expt(0 - 1, j) * combinations(k, j) * expt(k - j, n) +
      stirling2_terms(n, k, j + 1)
  end
end

# Bell number: partitions of an n-set into ANY number of blocks, which is the
# Stirling row summed. Defined this way rather than by its own recurrence so
# that the two cannot drift apart.
def bell(n)
  sum(map(fn(k) stirling2(n, k) end, range(0, n + 1)))
end

# Surjections: functions from an n-set ONTO all k elements of a k-set.
#
# k! * S(n,k) — a partition into k blocks, then a labelling of the blocks.
# The reason it is written on top of stirling2 rather than by its own
# inclusion-exclusion sum is that the two would then be independent formulas
# for one fact, free to disagree.
def surjections(n, k)
  factorial(k) * stirling2(n, k)
end

# --- partitions of an integer -----------------------------------------------

# Partitions of n using no part larger than m.
#
# The split is on the largest part: either m is not used at all (n, m-1) or it
# is used at least once (n-m, m). That is a count of two subproblems, never a
# list of partitions — p(50) is 204226, and enumerating them to size the list
# is exactly what this package exists not to do.
def partitions_with_max(n, m)
  if n < 0
    0
  else
    if n < 1
      1
    else
      if m < 1
        0
      else
        partitions_with_max(n, m - 1) + partitions_with_max(n - m, m)
      end
    end
  end
end

# p(n): 1, 1, 2, 3, 5, 7, 11 — the number of ways to write n as a sum of
# positive integers, order disregarded. p(0) is 1, the empty sum.
def partitions(n)
  if n < 0
    0
  else
    partitions_with_max(n, n)
  end
end

# Partitions of n into EXACTLY k parts.
#
# Split on whether the smallest part is 1 (drop it: n-1 into k-1 parts) or
# every part exceeds 1 (subtract one from each: n-k into k parts). Summing
# this over k recovers partitions(n), which is the test below.
def partitions_into(n, k)
  if n < 0 || k < 0
    0
  else
    if k < 1
      if n < 1
        1
      else
        0
      end
    else
      if n < k
        0
      else
        partitions_into(n - 1, k - 1) + partitions_into(n - k, k)
      end
    end
  end
end

# --- compositions -----------------------------------------------------------

# Compositions: n written as an ORDERED sum of exactly k positive parts.
#
# The counterpart to partitions_into, and the pair is worth holding side by
# side: 4 = 3+1 and 4 = 1+3 are two compositions but one partition. Counted by
# choosing where to cut a row of n items, hence C(n-1, k-1).
def compositions(n, k)
  if n < 1
    if k < 1
      1
    else
      0
    end
  else
    if k < 1
      0
    else
      combinations(n - 1, k - 1)
    end
  end
end

# Compositions of n into any number of parts: 2^(n-1), one binary choice at
# each of the n-1 gaps. Zero has the empty composition and no gaps at all,
# which the formula would answer with a half.
def compositions_total(n)
  if n < 1
    1
  else
    expt(2, n - 1)
  end
end

# --- ratios of counts -------------------------------------------------------
#
# A combinatorial probability is one count over another, and the pair is exact
# where its float quotient is not: the chance of a given four-of-a-kind is
# 1/649740 exactly and 0.0000015390... approximately. These keep the pair.

# Reduce [numerator, denominator] to lowest terms, sign carried on the
# numerator so that a value has exactly one reduced form.
#
# A zero denominator is handed back untouched rather than divided by: there is
# no lowest term for an undefined ratio, and erroring would make this unusable
# in a fold over counts that can legitimately be zero.
def simplify_ratio(n, d)
  if is_zero(d)
    [n, d]
  else
    simplify_by_gcd(n, d, gcd(abs(n), abs(d)))
  end
end

# Divide both terms by g, flipping both signs when the denominator is the one
# carrying the minus. Split out because the sign branch needs g named, and an
# assignment inside the caller's else-branch would bury the guard above it.
def simplify_by_gcd(n, d, g)
  if d < 0
    [(0 - n) / g, (0 - d) / g]
  else
    [n / g, d / g]
  end
end

# Whether two counts share no factor. gcd(0, 0) is 0, so nothing is coprime to
# itself at zero — but 1 is coprime to everything, zero included.
def coprime(a, b)
  gcd(abs(a), abs(b)) == 1
end

# --- the triangle itself ----------------------------------------------------

# Rows 0 through n of Pascal's triangle.
#
# Each row is computed from the binomial formula rather than from the row above
# it. That is slower per entry and the right trade here: a row built by adding
# its predecessor cannot be asked for on its own, and pascal_row(40) with no
# preamble is the call a caller actually makes.
def pascal_triangle(n)
  map(fn(r) pascal_row(r) end, range(0, n + 1))
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

test "double factorial skips a term, which is what tells it from factorial"
  assert double_factorial(8) == 384
  assert double_factorial(7) == 105
  # Both empty products, and the base case each chain lands on.
  assert double_factorial(0) == 1
  assert double_factorial(0 - 1) == 1
  assert double_factorial(1) == 1
  assert double_factorial(2) == 2
  # The identity that catches an off-by-one in the step: (2n)!! == 2^n * n!.
  assert double_factorial(10) == expt(2, 5) * factorial(5)
  # And the pair that reassembles the ordinary factorial.
  assert double_factorial(6) * double_factorial(5) == factorial(6)
end

test "rising factorial climbs where permutations fall"
  assert rising_factorial(5, 3) == 210
  assert rising_factorial(1, 5) == 120
  assert rising_factorial(7, 0) == 1
  # They agree only at k < 2 — this is the case a copy-paste of `permutations`
  # would still pass, and the next one is where it breaks.
  assert rising_factorial(5, 1) == permutations(5, 1)
  assert rising_factorial(5, 3) == 210
  assert permutations(5, 3) == 60
  # Rising has no k > n cutoff: it keeps going where permutations returns 0.
  assert rising_factorial(2, 5) == 720
  assert permutations(2, 5) == 0
end

test "central binomial is the largest entry of its row"
  assert central_binomial(0) == 1
  assert central_binomial(3) == 20
  assert central_binomial(5) == 252
  assert central_binomial(4) == max_of(pascal_row(8))
  # The relation catalan is defined by, checked from the other side.
  assert catalan(5) * 6 == central_binomial(5)
end

test "multinomial counts MISSISSIPPI without spelling it"
  assert multinomial([1, 4, 4, 2]) == 34650
  # An empty multiset has exactly one ordering; a single block has one too.
  assert multinomial([]) == 1
  assert multinomial([7]) == 1
  # Two blocks is the binomial coefficient — a wrong denominator breaks here.
  assert multinomial([3, 2]) == combinations(5, 3)
  assert multinomial([1, 1, 1]) == factorial(3)
  # Order of the counts cannot matter.
  assert multinomial([2, 1, 3]) == multinomial([3, 1, 2])
end

test "combinations with repetition allows the repeat that combinations forbids"
  # Three scoops from five flavours: 35 with repeats, 10 without.
  assert combinations_with_repetition(5, 3) == 35
  assert combinations(5, 3) == 10
  assert multichoose(5, 3) == 35
  # k=0 is the empty selection: one way, even from an empty set. The bare
  # formula asks for C(n-1, 0) and answers 0 for n=0.
  assert combinations_with_repetition(0, 0) == 1
  assert combinations_with_repetition(4, 0) == 1
  # Nothing can be drawn from an empty set, though.
  assert combinations_with_repetition(0, 3) == 0
  # k=1 has no room to repeat, so the two must agree.
  assert combinations_with_repetition(6, 1) == combinations(6, 1)
end

test "permutations with repetition is a power, not a falling product"
  assert permutations_with_repetition(10, 4) == 10000
  assert permutations_with_repetition(2, 8) == 256
  assert permutations_with_repetition(5, 0) == 1
  # Where it parts company with the ordered-without-repetition count.
  assert permutations_with_repetition(4, 2) == 16
  assert permutations(4, 2) == 12
  # And it keeps counting past n, where permutations has run out of items.
  assert permutations_with_repetition(2, 5) == 32
  assert permutations(2, 5) == 0
end

test "binomial row sum agrees with the row it summarises"
  assert binomial_row_sum(0) == 1
  assert binomial_row_sum(10) == 1024
  # The closed form against the actual row — the check that keeps the shortcut
  # honest rather than merely self-consistent.
  assert binomial_row_sum(6) == sum(pascal_row(6))
  assert binomial_row_sum(9) == sum(pascal_row(9))
  # The alternating sum is the companion identity: every row past the first
  # cancels to nothing. A row that is off by one entry fails this and not the
  # sum above.
  assert sum(map(fn(k) expt(0 - 1, k) * combinations(7, k) end, range(0, 8))) == 0
  assert sum(map(fn(k) expt(0 - 1, k) * combinations(0, k) end, range(0, 1))) == 1
end

test "figurate numbers, each against a value you can count by hand"
  assert triangular(0) == 0
  assert triangular(1) == 1
  assert triangular(4) == 10
  assert triangular(10) == 55
  assert pentagonal(1) == 1
  assert pentagonal(2) == 5
  assert pentagonal(4) == 22
  # Measured, and worth relying on: the same expression gives the GENERALIZED
  # pentagonal numbers for negative indices — 1, 2, 5, 7, 12 interleaved — so
  # Euler's partition recurrence can walk k = 1, -1, 2, -2 through this one
  # function without a second definition.
  assert pentagonal(0 - 1) == 2
  assert pentagonal(0 - 2) == 7
  assert pentagonal(0) == 0
  assert hexagonal(1) == 1
  assert hexagonal(4) == 28
  # An empty pyramid holds nothing — C(2,3) is out of range, and this file's
  # k > n rule already answers 0 rather than erroring.
  assert tetrahedral(0) == 0
  assert tetrahedral(1) == 1
  assert tetrahedral(3) == 10
  # The identities that separate these from four unrelated formulas: every
  # hexagonal number is an odd-indexed triangular one, and a tetrahedral
  # number is the triangular numbers stacked.
  assert hexagonal(5) == triangular(9)
  assert tetrahedral(4) ==
    triangular(1) + triangular(2) + triangular(3) + triangular(4)
  # Triangular is a binomial in disguise, which is why it lives in this file.
  assert triangular(9) == combinations(10, 2)
end

test "fibonacci is seeded at zero, and stays cheap far out"
  assert fibonacci(0) == 0
  assert fibonacci(1) == 1
  assert fibonacci(2) == 1
  assert fibonacci(10) == 55
  # An implementation seeded 1,1 passes every line above except this one.
  assert fibonacci(7) == 13
  # Far enough out that a doubly-recursive version would still be running.
  assert fibonacci(30) == 832040
end

test "lucas is the same recurrence with different seeds"
  assert lucas(0) == 2
  assert lucas(1) == 1
  assert lucas(5) == 11
  assert lucas(10) == 123
  # The identity binding the two families: L(n) == F(n-1) + F(n+1). This is
  # what a copy of fibonacci that forgot to change the seeds fails.
  assert lucas(6) == fibonacci(5) + fibonacci(7)
  assert lucas(9) == fibonacci(8) + fibonacci(10)
end

test "derangements, where the two seeds are the whole difficulty"
  assert derangements(4) == 9
  assert derangements(5) == 44
  assert subfactorial(4) == 9
  # The empty permutation deranges vacuously; one item cannot move at all.
  assert derangements(0) == 1
  assert derangements(1) == 0
  assert derangements(2) == 1
  assert derangements(3) == 2
  # Every permutation fixes some subset and deranges the rest, so the
  # binomial convolution must rebuild n! exactly. A shifted recurrence still
  # produces plausible-looking numbers and fails here.
  assert sum(map(fn(k) combinations(5, k) * derangements(5 - k) end,
    range(0, 6))) == factorial(5)
end

test "stirling numbers of the second kind"
  assert stirling2(4, 2) == 7
  assert stirling2(5, 3) == 25
  # A set splits into singletons exactly one way, and into one block one way.
  assert stirling2(6, 6) == 1
  assert stirling2(6, 1) == 1
  # S(n, n-1) is C(n,2): exactly one pair shares a block.
  assert stirling2(6, 5) == combinations(6, 2)
  # The empty edges, which the closed form alone gets wrong without the guard.
  assert stirling2(0, 0) == 1
  assert stirling2(3, 0) == 0
  assert stirling2(0, 2) == 0
  assert stirling2(2, 5) == 0
  assert stirling2(0 - 1, 1) == 0
end

test "surjections count the onto maps, not all of them"
  # 2^3 total maps from a 3-set to a 2-set, minus the 2 constant ones.
  assert surjections(3, 2) == 6
  assert permutations_with_repetition(2, 3) == 8
  # Onto a set its own size is a permutation; onto one element there is one map.
  assert surjections(4, 4) == factorial(4)
  assert surjections(4, 1) == 1
  # No map from a smaller set can cover a larger one.
  assert surjections(2, 3) == 0
  assert surjections(0, 0) == 1
  # Every map is a surjection onto its image, so classifying all k^n maps by
  # image size must give them all back. This is the identity that catches a
  # missing k! as well as a wrong stirling row.
  assert sum(map(fn(k) combinations(3, k) * surjections(4, k) end,
    range(0, 4))) == permutations_with_repetition(3, 4)
end

test "lattice paths across a grid"
  assert lattice_paths(2, 2) == 6
  assert lattice_paths(3, 3) == 20
  # A grid with no width has exactly one path — straight up — not zero.
  assert lattice_paths(0, 5) == 1
  assert lattice_paths(0, 0) == 1
  # The square grid is the central binomial, and the count cannot care which
  # axis is which.
  assert lattice_paths(4, 4) == central_binomial(4)
  assert lattice_paths(2, 5) == lattice_paths(5, 2)
end

test "bell numbers are the stirling row summed"
  assert bell(0) == 1
  assert bell(1) == 1
  assert bell(2) == 2
  assert bell(3) == 5
  assert bell(5) == 52
  # The independent recurrence B(n+1) == sum C(n,k) * B(k). If either bell or
  # stirling2 drifts, this is the line that notices.
  assert bell(6) == sum(map(fn(k) combinations(5, k) * bell(k) end, range(0, 6)))
end

test "partitions of an integer, counted rather than listed"
  assert partitions(0) == 1
  assert partitions(1) == 1
  assert partitions(4) == 5
  assert partitions(5) == 7
  assert partitions(10) == 42
  # Far enough that enumerating the partitions would be the slow way round.
  assert partitions(20) == 627
  # Negative has no partitions; the guard keeps the recurrence from running off.
  assert partitions(0 - 3) == 0
  # Bounding the part size is a real restriction: 4 = 3+1 = 2+2 = 2+1+1 = 1*4
  # once no part may exceed 3, which drops 4 itself.
  assert partitions_with_max(4, 3) == 4
  assert partitions_with_max(4, 1) == 1
  assert partitions_with_max(4, 4) == partitions(4)
end

test "partitions into exactly k parts sum back to partitions"
  assert partitions_into(4, 2) == 2
  assert partitions_into(7, 3) == 4
  assert partitions_into(5, 1) == 1
  assert partitions_into(5, 5) == 1
  # Only the empty sum has no parts at all.
  assert partitions_into(0, 0) == 1
  assert partitions_into(3, 0) == 0
  assert partitions_into(3, 4) == 0
  # The identity that ties the two counts together across every k at once.
  assert sum(map(fn(k) partitions_into(9, k) end, range(0, 10))) == partitions(9)
end

test "compositions are ordered where partitions are not"
  assert compositions(4, 2) == 3
  assert partitions_into(4, 2) == 2
  assert compositions(5, 1) == 1
  assert compositions(5, 5) == 1
  # Only the empty sum composes nothing; nothing else does.
  assert compositions(0, 0) == 1
  assert compositions(0, 3) == 0
  assert compositions(3, 0) == 0
  # And the row must sum to the closed form, at zero as well as above it.
  assert compositions_total(4) == 8
  assert sum(map(fn(k) compositions(4, k) end,
    range(0, 5))) == compositions_total(4)
  assert compositions_total(1) == 1
  assert compositions_total(0) == 1
  assert sum(map(fn(k) compositions(0, k) end,
    range(0, 1))) == compositions_total(0)
end

test "simplify_ratio reduces, normalises the sign, and survives a zero"
  assert simplify_ratio(6, 8) == [3, 4]
  assert simplify_ratio(4, 2) == [2, 1]
  # Already lowest terms comes back unchanged rather than scaled.
  assert simplify_ratio(3, 7) == [3, 7]
  # Sign lives on the numerator, so a value has exactly one reduced form.
  assert simplify_ratio(3, 0 - 6) == [0 - 1, 2]
  assert simplify_ratio(0 - 3, 6) == [0 - 1, 2]
  assert simplify_ratio(0 - 3, 0 - 6) == [1, 2]
  # Zero over anything is 0/1; anything over zero is undefined and is returned
  # untouched instead of erroring on a gcd of nothing.
  assert simplify_ratio(0, 5) == [0, 1]
  assert simplify_ratio(5, 0) == [5, 0]
  assert simplify_ratio(0, 0) == [0, 0]
  # What it is for: the odds of a specific poker hand, exactly.
  assert simplify_ratio(4, combinations(52, 5)) == [1, 649740]
end

test "coprime, including the two cases people argue about"
  assert coprime(8, 15) == true
  assert coprime(8, 12) == false
  assert coprime(0 - 8, 15) == true
  # 1 is coprime to everything, zero included; 0 is coprime to nothing but 1.
  assert coprime(1, 0) == true
  assert coprime(0, 5) == false
  assert coprime(0, 0) == false
  # A reduced ratio is by definition a coprime pair — the two functions agree
  # or one of them is wrong.
  assert coprime(nth(0, simplify_ratio(24, 36)),
    nth(1, simplify_ratio(24, 36))) == true
end

test "pascal triangle rows, and the recurrence between them"
  assert pascal_triangle(0) == [[1]]
  assert pascal_triangle(3) == [[1], [1, 1], [1, 2, 1], [1, 3, 3, 1]]
  # Each row is built from the formula, never from its predecessor — so the
  # additive law is a genuine check on the triangle rather than a restatement.
  assert nth(2, nth(5, pascal_triangle(5))) ==
    nth(1, pascal_row(4)) + nth(2, pascal_row(4))
  # The hockey-stick identity: a diagonal sums to the entry below its end.
  assert combinations(2, 2) + combinations(3, 2) + combinations(4, 2) ==
    combinations(5, 3)
end
