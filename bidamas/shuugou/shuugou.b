use("retsu", [:first, :is_empty, :push, :rest, :size, :without])
use("ronri", [:any, :count_if, :every])

# shuugou (集合) — sets, over plain lists.
#
# No new data structure: a set is a list with no duplicates, so every list
# function keeps working on one. Membership is linear rather than constant —
# a deliberate trade, because a second container type would fork every
# function in the distribution and none of the forks would be better.

def member(xs, v)
  any((x) -> x == v, xs)
end

# Keeps the FIRST occurrence of each element.
#
# Written as a left fold rather than the obvious tail-recursion, because the
# tail-recursive shape — unique the rest, then decide about the head — silently
# keeps the LAST occurrence instead: for [1,2,1,3,2] it yields [1,3,2]. Both
# are "duplicates removed"; only one matches what a caller reading
# first-seen-order expects, and the difference is invisible until a test names
# an ordered expectation. This one did.
def unique(xs)
  reduce(
    fn(acc, x)
      if member(acc, x)
        acc
      else
        push(acc, x)
      end
    end,
    [],
    xs
  )
end

def union(a, b)
  unique(append(a, b))
end

def intersection(a, b)
  unique(filter((x) -> member(b, x), a))
end

def difference(a, b)
  unique(filter((x) -> not member(b, x), a))
end

def subset(a, b)
  every((x) -> member(b, x), a)
end

def disjoint(a, b)
  is_empty(intersection(a, b))
end

def symmetric_difference(a, b)
  union(difference(a, b), difference(b, a))
end

# The runtime has TWO empties and only one of them is `[]`:
#
#   append([], [])   => nil        range(3, 3)  => nil        nil == []  => false
#
# so a set operation that empties out through an append chain compares UNEQUAL
# to the empty set it obviously is, and `pairs([]) == []` fails while every
# non-empty case passes. `map`, `filter` and a `reduce` with a `[]` seed are
# already total; `append` and `range` are not. Every constructor below that can
# reach one of those returns through here, which is why the empty-input
# assertions in this file are exact equalities rather than size checks.
def as_set(xs)
  if xs.nil?
    []
  else
    xs
  end
end

# Cardinality counts DISTINCT elements, so it is not `size`.
#
# The distinction is the whole reason it is named: callers hand these functions
# plain lists, and a list is only a set once the duplicates are gone.
def cardinality(xs)
  size(unique(xs))
end

def is_singleton(xs)
  cardinality(xs) == 1
end

# Set equality ignores both order and multiplicity — [1,2,2] and [2,1] are the
# same set. Written as mutual inclusion rather than `unique(a) == unique(b)`
# because unique preserves first-seen ORDER, so the list comparison would call
# those two unequal.
def set_equal(a, b)
  subset(a, b) and subset(b, a)
end

def superset(a, b)
  subset(b, a)
end

# Proper = contained AND not equal. The case worth stating: no set is a proper
# subset of itself, which is what separates this from `subset`.
def proper_subset(a, b)
  subset(a, b) and not set_equal(a, b)
end

def proper_superset(a, b)
  proper_subset(b, a)
end

# Idempotent by construction: inserting a member returns the set unchanged
# rather than growing it, which is what makes this a set operation and not
# retsu's `push`.
def insert(xs, v)
  if member(xs, v)
    as_set(xs)
  else
    push(xs, v)
  end
end

# Removes EVERY occurrence, not the first.
#
# A set has no notion of "the first 1", so a remove that deletes one copy and
# leaves another would hand back a value that still `member` what was just
# removed — the postcondition every caller assumes.
def remove(xs, v)
  without(xs, v)
end

# unique, but on a derived key — keeps the first element per key, and keeps
# the ELEMENT rather than the key. Same first-seen rule as `unique`, and for
# the same reason: the tail-recursive shape keeps the last one instead, and
# nothing but an ordered expectation notices.
def unique_by(key, xs)
  reduce(
    fn(acc, x)
      if member(map(key, acc), key(x))
        acc
      else
        push(acc, x)
      end
    end,
    [],
    xs
  )
end

# Returns [key, members] PAIRS rather than a map, in first-seen key order.
#
# A pair list, because blue's map literal has no reachable key-enumeration
# builtin — so a map return would be a value a caller could not walk. The pairs
# are ordinary lists, which every function in the distribution already handles.
# Key order is first-seen, not sorted: the keys need no ordering relation, so
# sorting them would demand one the caller may not have.
def group_by(xs, key)
  map((k) -> [k, filter((x) -> key(x) == k, xs)], unique(map(key, xs)))
end

# [value, count] pairs, in first-seen order. Same representation as group_by,
# and the counts sum back to size(xs) — the invariant a double-counting
# implementation breaks.
def frequencies(xs)
  map((v) -> [v, count_if((x) -> x == v, xs)], unique(xs))
end

# The value for a key in a pair list, or nil when absent.
#
# It exists because group_by and frequencies return pair lists: without it
# every caller writes the same filter-then-nth by hand, and gets the missing
# case wrong the first time. nil rather than an error, for the same reason
# junjo's binary search returns -1 — absence is an ordinary answer.
def lookup(ps, k)
  hit = filter((p) -> first(p) == k, ps)
  if is_empty(hit)
    nil
  else
    nth(1, first(hit))
  end
end

# The most frequent value; nil for the empty input.
#
# Ties go to the first-seen value, because the fold replaces only on a STRICT
# improvement. A `>=` there returns the LAST of the tied values instead, and no
# test with a single clear winner would ever catch the difference.
def most_common(xs)
  fs = frequencies(xs)
  if is_empty(fs)
    nil
  else
    nth(
      0,
      reduce(
        fn(best, p)
          if nth(1, p) > nth(1, best)
            p
          else
            best
          end
        end,
        first(fs),
        rest(fs)
      )
    )
  end
end

# A list is a set exactly when it carries no duplicate — the precondition every
# function above states informally, made checkable.
def is_set(xs)
  size(xs) == cardinality(xs)
end

# The power set of an already-deduplicated list. Split out from `power_set` so
# the size bound is checked ONCE, at the top, rather than on every one of the
# 2^n recursive calls.
def power_set_of(xs)
  if is_empty(xs)
    [[]]
  else
    subs = power_set_of(rest(xs))
    append(subs, map((s) -> cons(first(xs), s), subs))
  end
end

# All subsets, INCLUDING the empty set and the set itself.
#
# Bounded at 12 distinct elements — 4096 subsets — because 2^n stops being a
# value and becomes an outage: 20 elements is a million allocated lists, and
# the caller who typed that meant to pass something smaller. Over the bound it
# returns [], which is distinguishable from every real answer: a genuine power
# set always member at least [], so `is_empty(power_set(xs))` means refused
# and never means computed.
def power_set(xs)
  s = unique(xs)
  if size(s) > 12
    []
  else
    power_set_of(s)
  end
end

# All [a, b] pairs with a from the first set and b from the second. ORDERED
# pairs — [1,2] and [2,1] are different elements — which is what separates this
# from `pairs` below.
def cartesian_product(a, b)
  as_set(reduce((acc, x) -> append(acc, map((y) -> [x, y], b)), [], a))
end

# Every UNORDERED pair of distinct members: [1,2] appears, [2,1] does not, and
# [1,1] never does. Indexing j from i+1 is what buys all three at once — a
# double loop over the whole set would produce n^2 entries including the
# reversals and the self-pairs.
def pairs(xs)
  s = unique(xs)
  as_set(
    reduce(
      fn(acc, i)
        append(acc, map((j) -> [nth(i, s), nth(j, s)], range(i + 1, size(s))))
      end,
      [],
      range(0, size(s))
    )
  )
end

def union_all(xss)
  reduce(union, [], xss)
end

# The intersection of a FAMILY of sets. Seeded with the first member rather
# than with [], because [] is the identity for union and the annihilator for
# intersection — folding intersection from [] returns [] for every input.
#
# The empty family returns [] rather than the universe, which is the only total
# answer available: there is no universe to return.
def intersection_all(xss)
  if is_empty(xss)
    []
  else
    reduce(intersection, first(xss), rest(xss))
  end
end

test "unique removes duplicates, keeping first-seen order"
  assert unique([1, 2, 1, 3, 2]) == [1, 2, 3]
  assert unique([]) == []
  assert unique([1]) == [1]
end

test "union, intersection, difference"
  assert union([1, 2], [2, 3]) == [1, 2, 3]
  assert intersection([1, 2, 3], [2, 3, 4]) == [2, 3]
  assert difference([1, 2, 3], [2]) == [1, 3]
  assert symmetric_difference([1, 2], [2, 3]) == [1, 3]
end

test "empty? is true of the empty set and of nil, false of any member"
  assert empty?([])
  assert empty?(nil)
  assert empty?(difference([1, 2], [2, 1]))
  assert empty?(intersection([1], [2]))
  assert not empty?([1])
  assert not empty?([nil])
  assert not empty?(union([], [3]))
end

test "the empty-set laws"
  # The empty set is a subset of everything and disjoint from everything —
  # the two laws an implementation built from a loop usually gets wrong.
  assert subset([], [1, 2]) == true
  assert subset([1], []) == false
  assert subset([1, 2], [2, 1, 3]) == true
  assert disjoint([], [1]) == true
  assert disjoint([1], [1]) == false
end

test "cardinality counts distinct elements, which size does not"
  assert cardinality([1, 1, 2]) == 2
  assert size([1, 1, 2]) == 3
  assert cardinality([]) == 0
  assert is_singleton([1, 1, 1]) == true
  assert is_singleton([1, 2]) == false
  assert is_singleton([]) == false
end

test "set equality ignores order and multiplicity"
  # The pair that a `unique(a) == unique(b)` implementation gets wrong: both
  # sides denote {1,2}, but unique preserves first-seen order so the lists
  # differ.
  assert set_equal([1, 2, 2], [2, 1]) == true
  assert set_equal([1, 2], [1, 2, 3]) == false
  assert set_equal([], []) == true
  assert set_equal([], [1]) == false
end

test "superset mirrors subset"
  assert superset([1, 2, 3], [1, 2]) == true
  assert superset([1], [1, 2]) == false
  # Everything is a superset of the empty set, including the empty set.
  assert superset([1], []) == true
  assert superset([], []) == true
end

test "proper containment excludes equality"
  # The case that separates proper_subset from subset: a set is a subset of
  # itself and NOT a proper subset of itself.
  assert subset([1, 2], [2, 1]) == true
  assert proper_subset([1, 2], [2, 1]) == false
  assert proper_subset([1], [1, 2]) == true
  assert proper_subset([], [1]) == true
  assert proper_subset([], []) == false
  assert proper_superset([1, 2], [1]) == true
  assert proper_superset([1], [1]) == false
end

test "insert is idempotent, remove takes every copy"
  assert insert([1, 2], 3) == [1, 2, 3]
  assert insert([1, 2], 2) == [1, 2]
  assert insert([], 1) == [1]
  # Inserting twice must not grow the set — the property that distinguishes
  # this from push.
  assert insert(insert([1], 2), 2) == [1, 2]
  # Both copies go, so the postcondition holds afterwards.
  assert remove([1, 2, 1], 1) == [2]
  assert member(remove([1, 2, 1], 1), 1) == false
  assert remove([1], 2) == [1]
  assert remove([1], 1) == []
  assert remove([], 1) == []
end

test "unique_by keeps the first element per key, not the last"
  # Keys are 1, 1, 2, 2 — so 11 and 2 survive. A last-wins implementation
  # returns [21, 12] and passes every unordered check.
  assert unique_by((n) -> n % 10, [11, 21, 2, 12]) == [11, 2]
  assert unique_by((x) -> x, [1, 2, 1]) == unique([1, 2, 1])
  assert unique_by((x) -> x, []) == []
  # A constant key collapses everything to one element.
  assert unique_by((_x) -> 0, [5, 6, 7]) == [5]
end

test "group_by partitions, in first-seen key order"
  # Key 1 is seen before key 0, so it comes first — a sorted-key
  # implementation returns the pairs the other way round.
  assert group_by([1, 2, 3, 4], (n) -> n % 2) == [[1, [1, 3]], [0, [2, 4]]]
  assert group_by([], (x) -> x) == []
  # A partition loses nothing and duplicates nothing: the group sizes sum
  # back to the input size.
  gs = group_by([1, 2, 3, 4, 5, 6, 7], (n) -> n % 3)
  assert reduce((a, p) -> a + size(nth(1, p)), 0, gs) == 7
end

test "frequencies counts, and the counts sum to the input size"
  assert frequencies([1, 1, 2]) == [[1, 2], [2, 1]]
  assert frequencies([]) == []
  fs = frequencies([1, 2, 2, 3, 3, 3])
  assert reduce((a, p) -> a + nth(1, p), 0, fs) == 6
  # One pair per DISTINCT value.
  assert size(fs) == cardinality([1, 2, 2, 3, 3, 3])
end

test "lookup reads a pair list, and reports absence as nil"
  assert lookup(frequencies([1, 1, 2]), 1) == 2
  assert lookup(group_by([1, 2, 3], (n) -> n % 2), 0) == [2]
  assert lookup(frequencies([1]), 9).nil?
  assert lookup([], 1).nil?
end

test "most_common, including the tie and the empty input"
  assert most_common([1, 2, 2, 3]) == 2
  assert most_common([]).nil?
  assert most_common([7]) == 7
  # A tie resolves to the first-seen value; `>=` in the fold returns 2.
  assert most_common([1, 1, 2, 2]) == 1
  # And a later value still wins when it is a strict majority, which catches
  # a fold that never replaces at all.
  assert most_common([3, 3, 1, 1, 1]) == 1
  assert most_common(["a", "b", "a"]) == "a"
end

test "is_set is the precondition the other functions assume"
  assert is_set([1, 2, 3]) == true
  assert is_set([1, 2, 1]) == false
  assert is_set([]) == true
  # unique is exactly the function that establishes it.
  assert is_set(unique([1, 2, 1])) == true
end

test "power_set, its size, and its two guaranteed members"
  assert power_set([1, 2]) == [[], [2], [1], [1, 2]]
  # The power set of the empty set is NOT empty — it is the set containing
  # the empty set, which is the case a loop-based implementation misses.
  assert power_set([]) == [[]]
  assert size(power_set([1, 2, 3])) == 8
  assert member(power_set([1, 2, 3]), []) == true
  assert member(power_set([1, 2, 3]), [1, 2, 3]) == true
  # Duplicates are collapsed first, so the size is 2^cardinality, not 2^size.
  assert size(power_set([1, 1, 2])) == 4
  # Every member is a subset of the original — the defining property.
  assert every((s) -> subset(s, [1, 2, 3]), power_set([1, 2, 3])) == true
end

test "power_set refuses past its bound, distinguishably"
  # 13 distinct elements is over the bound. The refusal is [], which no real
  # power set can be, because a real one always member [].
  assert power_set(range(0, 13)) == []
  assert member(power_set(range(0, 13)), []) == false
  # One under the bound still computes.
  assert size(power_set(range(0, 12))) == 4096
end

test "cartesian_product is ordered pairs, and empty on an empty side"
  assert cartesian_product([1, 2], [3, 4]) == [[1, 3], [1, 4], [2, 3], [2, 4]]
  assert size(cartesian_product([1, 2, 3], [4, 5])) == 6
  # A x empty is empty, both ways round — the law an implementation that
  # returns [[1, nil]] or the other empty gets wrong.
  assert cartesian_product([1], []) == []
  assert cartesian_product([], [1]) == []
  assert cartesian_product([], []) == []
  # Ordered, so the reversal is a different element and is not present.
  assert member(cartesian_product([1], [2]), [1, 2]) == true
  assert member(cartesian_product([1], [2]), [2, 1]) == false
end

test "pairs are unordered, distinct, and C(n,2) of them"
  assert pairs([1, 2, 3]) == [[1, 2], [1, 3], [2, 3]]
  # Each pair once: the reversal must NOT also be there.
  assert member(pairs([1, 2]), [2, 1]) == false
  # No self-pair, which a double loop over the whole set produces.
  assert member(pairs([1, 2]), [1, 1]) == false
  # C(5,2) == 10, checkable without running anything.
  assert size(pairs(range(0, 5))) == 10
  assert pairs([1]) == []
  assert pairs([]) == []
  # Duplicates collapse first, so these two lists have the same pairs.
  assert pairs([1, 1, 2]) == [[1, 2]]
end

test "union_all and intersection_all fold a family of sets"
  assert union_all([[1, 2], [2, 3], [3, 4]]) == [1, 2, 3, 4]
  assert union_all([]) == []
  assert intersection_all([[1, 2, 3], [2, 3], [3, 4]]) == [3]
  # A one-member family is that member — the case a []-seeded fold gets
  # wrong, because [] annihilates intersection and would return [].
  assert intersection_all([[1, 2]]) == [1, 2]
  assert intersection_all([[1, 2], [3]]) == []
  assert intersection_all([]) == []
end

def disjoint?(a, b)
  disjoint(a, b)
end

def product(a, b)
  cartesian_product(a, b)
end

def subset?(a, b)
  subset(a, b)
end

test "disjoint? and subset? answer for the empty set"
  assert disjoint?([1, 2], [3])
  assert not disjoint?([1, 2], [2])
  assert disjoint?([], [])
  assert subset?([1], [1, 2])
  assert not subset?([3], [1, 2])
  assert subset?([], [])
  assert subset?([], [1])
end

test "product pairs every item of the first set with every item of the second"
  assert product([1, 2], ["a"]) == [[1, "a"], [2, "a"]]
  assert product([], [1]) == []
  assert product([1], []) == []
  assert size(product([1, 2], [3, 4])) == 4
end
