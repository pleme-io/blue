use("retsu")
use("kansuu")
# ronri (論理) — predicates, and the algebra over them.
#
# A predicate is a function to a boolean, and predicates compose the way
# booleans do. Building `all_of` from `every` rather than writing three
# recursive walks is the point: the combinators are the library.

def every(p, xs)
  if is_empty(xs)
    true
  else
    if p(first(xs))
      every(p, rest(xs))
    else
      false
    end
  end
end

def any(p, xs)
  if is_empty(xs)
    false
  else
    if p(first(xs))
      true
    else
      any(p, rest(xs))
    end
  end
end

def none(p, xs)
  !any(p, xs)
end

def count_if(p, xs)
  size(filter(p, xs))
end

def complement(p)
  fn(x) !p(x) end
end

def both(p, q)
  fn(x) p(x) && q(x) end
end

def either(p, q)
  fn(x) p(x) || q(x) end
end

# The rest of the connectives, so a caller never has to spell one out by hand.
#
# `xor` is `p(x) != q(x)` and nothing else; the hand-rolled
# `(p || q) && !(p && q)` is the same function written three times as long,
# and it is where a transcription error lands.
def xor(p, q)
  fn(x) p(x) != q(x) end
end

# Material implication — FALSE antecedent makes it TRUE. That is the case
# readers guess wrong, which is the whole argument for it being a named
# combinator instead of an inlined `!p(x) || q(x)` at each site.
def implies(p, q)
  fn(x) !p(x) || q(x) end
end

def nand(p, q)
  fn(x) !(p(x) && q(x)) end
end

def nor(p, q)
  fn(x) !(p(x) || q(x)) end
end

# all_of / any_of / none_of take a LIST of predicates and hand back a
# PREDICATE, so they extend both/either to n arguments rather than sitting
# beside them — `all_of([a, b, c])` is what `both(a, both(b, c))` was reaching
# for.
#
# Each is `every`/`any`/`none` run over the PREDICATES with the argument held
# fixed, which is the header's claim made literal. Two things fall out that a
# `reduce` would not give: the vacuous cases are inherited rather than chosen
# (an empty conjunction is true because `every` says so), and the walk stops at
# the first decisive predicate instead of calling all of them.
def all_of(ps)
  fn(x) every(fn(p) p(x) end, ps) end
end

def any_of(ps)
  fn(x) any(fn(p) p(x) end, ps) end
end

def none_of(ps)
  fn(x) none(fn(p) p(x) end, ps) end
end

# Predicates ABOUT lists, so `count_if(is_nonempty_pred, rows)` reads without a
# lambda. The `_pred` suffix is not decoration: retsu exports `is_empty` as a
# plain question, and a `def is_empty` here would silently replace it for every
# call in this file.
def is_empty_pred(xs)
  is_empty(xs)
end

def is_nonempty_pred(xs)
  !is_empty(xs)
end

# The counting quantifiers, between `any` (n >= 1) and `every` (n == size).
#
# COUNT FIRST, then the predicate, then the list — `take(2, xs)` and
# `nth(0, xs)` put the number first, and a library that flips the convention
# per function is how a caller ends up passing a predicate as a count.
def exactly_n(n, p, xs)
  count_if(p, xs) == n
end

def at_least_n(n, p, xs)
  count_if(p, xs) >= n
end

def at_most_n(n, p, xs)
  count_if(p, xs) <= n
end

# Strictly MORE than half — a tie is not a majority.
#
# Doubling rather than dividing is deliberate: `/` is float division here, so
# `count_if(p, xs) / size(xs) > 0.5` drags an exact question through a float,
# and it divides by zero on the empty list. `2 * k > n` is integer throughout
# and answers false for the empty list without a special case.
def majority(p, xs)
  2 * count_if(p, xs) > size(xs)
end

# Splitting a list ON a predicate.

# partition_by(p, xs) => [satisfying, not_satisfying].
#
# Two filters rather than one cons-recursion, because filter preserves order
# and a hand-rolled accumulate-then-return does not — the reversed half is the
# classic bug here, and it only shows on lists of three or more.
def partition_by(p, xs)
  [filter(p, xs), filter(complement(p), xs)]
end

# How many elements at the FRONT satisfy p. This is the only recursion in the
# take/drop family: the four functions below are each one call into it plus a
# total builtin, instead of four near-identical walks that can disagree.
def prefix_len(p, xs)
  if is_empty(xs)
    0
  else
    if p(first(xs))
      1 + prefix_len(p, rest(xs))
    else
      0
    end
  end
end

def take_while_pred(p, xs)
  take(prefix_len(p, xs), xs)
end

def drop_while_pred(p, xs)
  drop(prefix_len(p, xs), xs)
end

# take_until stops BEFORE the first element that satisfies p, and stops for
# good — it is a prefix, not a filter, so a later element that fails p is NOT
# picked back up. That distinction is the whole reason it is not `filter`.
def take_until(p, xs)
  take_while_pred(complement(p), xs)
end

def drop_until(p, xs)
  drop_while_pred(complement(p), xs)
end

# span_by(p, xs) => [prefix, remainder], the take_while_pred/drop_while_pred pair.
#
# The prefix sibling of partition_by, and both are worth having: on [1, 9, 1]
# they disagree, because partition_by scans the whole list and span_by stops.
def span_by(p, xs)
  [take_while_pred(p, xs), drop_while_pred(p, xs)]
end

# Searching by a predicate.

# Lift a VALUE into a predicate — the constructor that lets the rest of this
# file be used without writing a lambda: count_if(equals(3), xs),
# find_index_by(equals("b"), xs), none(equals(nil), xs).
def equals(v)
  fn(x) x == v end
end

# via(f, p) asks p about f(x) rather than about x — `count_if(via(abs,
# equals(2)), xs)` counts the twos of either sign, and `find_by(via(size,
# equals(0)), rows)` finds the first empty row, both without a lambda.
#
# It is kansuu's `compose` with the arguments named for this use: compose
# applies its SECOND argument first, so `compose(p, f)` is the right order and
# `compose(f, p)` would hand a boolean to f. Stating it once here is cheaper
# than getting it right at every call site.
def via(f, p)
  compose(p, f)
end

# The index of the first satisfying element, or 0 - 1 when there is none.
#
# 0 - 1 rather than nil is the distribution's convention for a missing index
# (junjo's index_of_sorted, angou's find_index_of): nil would flow into
# arithmetic silently, whereas 0 - 1 is out of range for every list.
def find_index_from(p, xs, i)
  if is_empty(xs)
    0 - 1
  else
    if p(first(xs))
      i
    else
      find_index_from(p, rest(xs), i + 1)
    end
  end
end

def find_index_by(p, xs)
  find_index_from(p, xs, 0)
end

# The first satisfying ELEMENT, or nil — nil here matches retsu's first([]),
# where "no such element" is genuinely absence rather than a position.
def find_by(p, xs)
  if is_empty(xs)
    nil
  else
    if p(first(xs))
      first(xs)
    else
      find_by(p, rest(xs))
    end
  end
end

# Every index whose element satisfies p; find_index_by is its first entry.
def indexes_where(p, xs)
  filter(fn(i) p(nth(i, xs)) end, indexes(xs))
end

test "the vacuous cases, which is where predicate libraries go wrong"
  # Everything holds of nothing; nothing holds of nothing.
  assert every(fn(x) x > 0 end, []) == true
  assert any(fn(x) x > 0 end, []) == false
  assert none(fn(x) x > 0 end, []) == true
end

test "every, any, none"
  pos = fn(x) x > 0 end
  assert every(pos, [1, 2, 3]) == true
  assert every(pos, [1, 0, 3]) == false
  assert any(pos, [0 - 1, 2]) == true
  assert none(pos, [0 - 1, 0 - 2]) == true
end

test "count_if"
  assert count_if(fn(x) x % 2 == 0 end, [1, 2, 3, 4, 5, 6]) == 3
end

test "predicate algebra"
  pos = fn(x) x > 0 end
  even_p = fn(x) x % 2 == 0 end
  assert both(pos, even_p)(4) == true
  assert both(pos, even_p)(3) == false
  assert either(pos, even_p)(0 - 2) == true
  assert complement(pos)(0 - 1) == true
end

test "xor is exclusive where either is not"
  pos = fn(x) x > 0 end
  even_p = fn(x) x % 2 == 0 end
  # The row that separates xor from either: BOTH true is FALSE.
  assert xor(pos, even_p)(4) == false
  assert either(pos, even_p)(4) == true
  assert xor(pos, even_p)(3) == true
  assert xor(pos, even_p)(0 - 2) == true
  assert xor(pos, even_p)(0 - 3) == false
end

test "implies is true whenever the antecedent is false"
  pos = fn(x) x > 0 end
  even_p = fn(x) x % 2 == 0 end
  # Vacuously true, twice: -3 is not positive, so the implication holds
  # regardless of the consequent. A `p(x) && q(x)` mistake fails right here.
  assert implies(pos, even_p)(0 - 3) == true
  assert implies(pos, even_p)(0 - 4) == true
  assert implies(pos, even_p)(4) == true
  assert implies(pos, even_p)(3) == false
end

test "nand and nor obey De Morgan"
  pos = fn(x) x > 0 end
  even_p = fn(x) x % 2 == 0 end
  # An independent derivation of the same functions, checked on all four rows
  # of the truth table: a swapped &&/|| in either one shows up as a mismatch.
  demorgan_nand = either(complement(pos), complement(even_p))
  demorgan_nor = both(complement(pos), complement(even_p))
  probes = [4, 3, 0 - 2, 0 - 3]
  assert every(fn(x) nand(pos, even_p)(x) == demorgan_nand(x) end, probes) == true
  assert every(fn(x) nor(pos, even_p)(x) == demorgan_nor(x) end, probes) == true
  assert nand(pos, even_p)(4) == false
  assert nor(pos, even_p)(0 - 3) == true
end

test "all_of, any_of and none_of over an EMPTY predicate list"
  # The same vacuity as every/any, one level up: an empty conjunction holds of
  # everything and an empty disjunction holds of nothing. A fold seeded the
  # wrong way round passes every other test in this file and fails these two.
  assert all_of([])(99) == true
  assert any_of([])(99) == false
  assert none_of([])(99) == true
end

test "all_of, any_of and none_of over a list of predicates"
  pos = fn(x) x > 0 end
  even_p = fn(x) x % 2 == 0 end
  small = fn(x) x < 10 end
  assert all_of([pos, even_p, small])(4) == true
  assert all_of([pos, even_p, small])(12) == false
  assert any_of([pos, even_p, small])(0 - 3) == true
  assert none_of([pos, even_p])(0 - 3) == true
  # none_of is the complement of any_of by construction; assert it stays so.
  probes = [4, 3, 0 - 2, 0 - 3]
  assert every(fn(x) none_of([pos, even_p])(x) == !any_of([pos, even_p])(x) end, probes) == true
end

test "all_of, any_of and none_of stop at the first decisive predicate"
  # `length(nil)` is a runtime ERROR — measured, and the reason retsu's `size`
  # exists. So a predicate that calls it is a bomb, and these three assertions
  # only complete at all if the bomb is never reached. That makes the
  # short-circuit a proven property rather than a comment: a reduce-based
  # implementation, which calls every predicate, turns each line into an ERROR.
  bomb = fn(x) length(nil) end
  assert any_of([fn(x) true end, bomb])(0) == true
  assert all_of([fn(x) false end, bomb])(0) == false
  assert none_of([fn(x) true end, bomb])(0) == false
end

test "the emptiness predicates pass by name"
  # The point of the _pred wrappers: no lambda at the call site.
  assert count_if(is_empty_pred, [[], [1], [], [2, 3]]) == 2
  assert count_if(is_nonempty_pred, [[], [1], [], [2, 3]]) == 2
  assert every(is_empty_pred, []) == true
  # cdr of a singleton is nil, not [] — is_empty_pred inherits retsu's totality
  # rather than erroring the way a length-based test would.
  assert is_empty_pred(cdr([1])) == true
end

test "the counting quantifiers, including the empty list"
  even_p = fn(x) x % 2 == 0 end
  xs = [1, 2, 3, 4, 5, 6]
  assert exactly_n(3, even_p, xs) == true
  assert exactly_n(2, even_p, xs) == false
  assert at_least_n(3, even_p, xs) == true
  assert at_least_n(4, even_p, xs) == false
  assert at_most_n(3, even_p, xs) == true
  assert at_most_n(2, even_p, xs) == false
  # Zero of nothing satisfies anything: the boundary a >/< instead of >=/<=
  # gets wrong, and the only reading under which the quantifiers agree with
  # every/any on the empty list.
  assert exactly_n(0, even_p, []) == true
  assert at_least_n(0, even_p, []) == true
  assert at_most_n(0, even_p, []) == true
  assert at_least_n(1, even_p, []) == false
end

test "at_least_n and at_most_n recover any and every at the boundaries"
  even_p = fn(x) x % 2 == 0 end
  probes = [[], [1], [2], [1, 2], [2, 4], [1, 3, 5]]
  # An independent definition of the same two functions. at_least_n(1) IS any;
  # at_most_n(0) IS none. If either bound is off by one this fails on [2].
  assert every(fn(xs) at_least_n(1, even_p, xs) == any(even_p, xs) end, probes) == true
  assert every(fn(xs) at_most_n(0, even_p, xs) == none(even_p, xs) end, probes) == true
  assert every(fn(xs) exactly_n(size(xs), even_p, xs) == every(even_p, xs) end, probes) == true
end

test "majority needs strictly more than half"
  even_p = fn(x) x % 2 == 0 end
  # An exact tie is NOT a majority — the case `>=` still passes and `>` catches.
  assert majority(even_p, [1, 2]) == false
  assert majority(even_p, [1, 2, 4]) == true
  assert majority(even_p, [1, 3, 4]) == false
  # Odd sizes, where an integer-halving implementation drifts: 2 of 5 is not a
  # majority, 3 of 5 is.
  assert majority(even_p, [2, 4, 1, 3, 5]) == false
  assert majority(even_p, [2, 4, 6, 1, 3]) == true
  # No majority of nothing, and no division by zero getting there.
  assert majority(even_p, []) == false
  assert majority(even_p, [2]) == true
end

test "partition_by keeps both halves in order and loses nothing"
  even_p = fn(x) x % 2 == 0 end
  assert partition_by(even_p, [1, 2, 3, 4, 5]) == [[2, 4], [1, 3, 5]]
  # Order INSIDE each half is the input order — an accumulator-based partition
  # returns [[4, 2], [5, 3, 1]] and passes a size-only check.
  assert partition_by(even_p, [4, 2, 3]) == [[4, 2], [3]]
  # Nothing is dropped and nothing is duplicated: the halves reassemble.
  parts = partition_by(even_p, [1, 2, 3, 4, 5])
  assert size(nth(0, parts)) + size(nth(1, parts)) == 5
  assert append(nth(0, parts), nth(1, parts)) == [2, 4, 1, 3, 5]
  assert partition_by(even_p, []) == [[], []]
end

test "take_until stops at the FIRST hit and does not resume"
  big = fn(x) x > 3 end
  # The 1 after the 4 is not picked back up — this is what separates a prefix
  # from a filter, and a filter-based take_until returns [1, 2, 3, 1] here.
  assert take_until(big, [1, 2, 3, 4, 5, 1]) == [1, 2, 3]
  assert drop_until(big, [1, 2, 3, 4, 5, 1]) == [4, 5, 1]
  # Boundaries: hit at the head, and never a hit at all.
  assert take_until(big, [9, 1, 2]) == []
  assert take_until(big, [1, 2]) == [1, 2]
  assert drop_until(big, [1, 2]) == []
  assert take_until(big, []) == []
  assert drop_until(big, []) == []
end

test "take_while_pred and drop_while_pred split a list in two"
  small = fn(x) x < 4 end
  assert take_while_pred(small, [1, 2, 3, 4, 1]) == [1, 2, 3]
  assert drop_while_pred(small, [1, 2, 3, 4, 1]) == [4, 1]
  # The invariant that must survive for any predicate and any list: the two
  # pieces concatenate back to the original, in order.
  #
  # The probes are all NON-EMPTY on purpose: append([], []) evaluates to nil,
  # not [], so the reassembly of an empty list cannot be stated as an equality
  # against [] at all. That is the same two-empties trap retsu was written for,
  # reached from a second direction — it is append that is partial here, not
  # anything in this file. The empty case is asserted below with is_empty.
  probes = [[1], [9], [1, 2, 3, 4, 1], [9, 9], [1, 9, 1]]
  assert every(fn(xs) append(take_while_pred(small, xs), drop_while_pred(small, xs)) == xs end, probes) == true
  assert is_empty(take_while_pred(small, [])) == true
  assert is_empty(drop_while_pred(small, [])) == true
  # take_until is take_while_pred of the complement, on the same probes plus [].
  assert every(fn(xs) take_until(small, xs) == take_while_pred(complement(small), xs) end, probes) == true
  assert take_until(small, []) == take_while_pred(complement(small), [])
  assert prefix_len(small, [1, 2, 9, 1]) == 2
  assert prefix_len(small, []) == 0
end

test "find_index_by reports the first hit, or 0 - 1"
  even_p = fn(x) x % 2 == 0 end
  # Two matches: the FIRST index, not the last, and not the count of matches.
  assert find_index_by(even_p, [1, 2, 3, 4]) == 1
  assert find_index_by(even_p, [2, 4]) == 0
  # A miss is 0 - 1, which no list can index — nil would flow into arithmetic.
  assert find_index_by(even_p, [1, 3, 5]) == 0 - 1
  assert find_index_by(even_p, []) == 0 - 1
  # Whatever index comes back really does satisfy the predicate.
  xs = [1, 3, 8, 5]
  assert even_p(nth(find_index_by(even_p, xs), xs)) == true
end

test "find_by returns the element, and nil for a miss"
  even_p = fn(x) x % 2 == 0 end
  assert find_by(even_p, [1, 2, 3, 4]) == 2
  assert find_by(even_p, [1, 3]) == nil
  assert find_by(even_p, []) == nil
  # find_by and find_index_by agree about whether there IS a hit.
  probes = [[], [1], [2], [1, 2, 3], [1, 3]]
  assert every(fn(xs) (find_by(even_p, xs) == nil) == (find_index_by(even_p, xs) == 0 - 1) end, probes) == true
end

test "indexes_where agrees with count_if and starts at find_index_by"
  even_p = fn(x) x % 2 == 0 end
  assert indexes_where(even_p, [1, 2, 3, 4]) == [1, 3]
  assert indexes_where(even_p, []) == []
  assert indexes_where(even_p, [1, 3]) == []
  probes = [[], [1], [2], [1, 2, 3, 4], [2, 2, 2]]
  assert every(fn(xs) size(indexes_where(even_p, xs)) == count_if(even_p, xs) end, probes) == true
  assert first(indexes_where(even_p, [1, 2, 4])) == find_index_by(even_p, [1, 2, 4])
end

test "span_by stops where partition_by keeps scanning"
  small = fn(x) x < 4 end
  # The one input that tells the two apart: the trailing 1 satisfies the
  # predicate but is NOT in span_by's prefix, because a 9 ended it.
  assert span_by(small, [1, 9, 1]) == [[1], [9, 1]]
  assert partition_by(small, [1, 9, 1]) == [[1, 1], [9]]
  assert span_by(small, []) == [[], []]
  assert span_by(small, [9, 9]) == [[], [9, 9]]
end

test "equals lifts a value into a predicate"
  assert count_if(equals(3), [3, 1, 3, 2]) == 2
  assert find_index_by(equals("b"), ["a", "b", "c"]) == 1
  assert none(equals(9), [1, 2]) == true
  # Equality is structural, so a list is a perfectly good value to look for.
  assert equals([1, 2])([1, 2]) == true
  assert equals([1, 2])([2, 1]) == false
  # 0 and false are distinct values, not one falsy thing — a truthiness-based
  # implementation of equals confuses them.
  assert equals(0)(0) == true
  assert equals(0)(false) == false
  assert every(equals(1), []) == true
  # And it composes with the algebra rather than sitting outside it.
  assert count_if(either(equals(1), equals(2)), [1, 2, 3]) == 2
end

test "via asks the predicate about a derived value"
  # The cross-package call: via is kansuu's compose, in the order that puts f
  # first. Both signs count, which is only true if abs really ran before the
  # comparison.
  assert count_if(via(abs, equals(2)), [2, 0 - 2, 3]) == 2
  # The case that fails if the composition order is flipped: -5 is not > 1, but
  # abs(-5) is.
  assert via(abs, fn(x) x > 1 end)(0 - 5) == true
  assert every(via(abs, fn(x) x > 1 end), [0 - 5, 5]) == true
  # via over a list-shaped value, where the derived thing is a size.
  assert count_if(via(size, equals(0)), [[], [1], []]) == 2
  assert every(via(size, equals(0)), []) == true
end
