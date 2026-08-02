use("ronri")
# junjo (順序) — ordering: sorting, searching, selection.
#
# Sorting lives in blue rather than being borrowed, because the interpreter's
# own `sort-by` is not reachable from blue's surface — a hyphen lexes as an
# operator. The constraint turned out to be worth something: a distribution
# that implements its own sort can state its properties, and insertion sort is
# stable, so equal elements keep their input order.

def insert_ordered(x, xs)
  if is_empty(xs)
    [x]
  else
    # `compare`, not `<=`, so this sorts STRINGS as well as numbers.
    #
    # `<` and `<=` are a type error on strings ("expected number, got string"),
    # so a `<=`-phrased sort could not order a list of words at all — it raised.
    # The reachable `compare` builtin is total over the value domain and returns
    # -1/0/1, so one implementation serves both.
    if compare(x, first(xs)) <= 0
      cons(x, xs)
    else
      cons(first(xs), insert_ordered(x, rest(xs)))
    end
  end
end

def sort(xs)
  if is_empty(xs)
    []
  else
    insert_ordered(first(xs), sort(rest(xs)))
  end
end

# NOT stable, unlike `sort` above — the header's stability claim covers the
# insertion sort, and this is a partition sort. Equal keys come back reversed
# (measured), because every later element that ties with the pivot lands in
# `smaller` and therefore in front of it. Use `sort_stable_by` where the key is
# not the whole value.
def sort_by(key, xs)
  if is_empty(xs)
    []
  else
    pivot = first(xs)
    tail = rest(xs)
    smaller = filter(fn(y) key(y) <= key(pivot) end, tail)
    larger = filter(fn(y) key(y) > key(pivot) end, tail)
    append(append(sort_by(key, smaller), [pivot]), sort_by(key, larger))
  end
end

def sort_desc(xs)
  reverse(sort(xs))
end

def is_sorted(xs)
  if size(xs) < 2
    true
  else
    if compare(first(xs), nth(1, xs)) <= 0
      is_sorted(rest(xs))
    else
      false
    end
  end
end

def bsearch(xs, target, lo, hi)
  if lo > hi
    0 - 1
  else
    mid = floor((lo + hi) / 2)
    v = nth(mid, xs)
    if v == target
      mid
    else
      if v < target
        bsearch(xs, target, mid + 1, hi)
      else
        bsearch(xs, target, lo, mid - 1)
      end
    end
  end
end

# Binary search over a SORTED list. Returns the index, or -1.
#
# -1 rather than an error: a search that does not find is an ordinary answer,
# and forcing every caller into error handling for the common case is how a
# library becomes unpleasant to use.
def index_of_sorted(xs, target)
  bsearch(xs, target, 0, size(xs) - 1)
end

def min_by(key, xs)
  first(sort_by(key, xs))
end

def max_by(key, xs)
  last(sort_by(key, xs))
end

# The three-way comparison the rest of the package is phrased in terms of.
#
# `<=` answers one question at a time, so an ordering that needs "less, equal,
# or greater" has to ask twice and the two answers can be read in the wrong
# order. One call, one of three answers: 0 - 1, 0, 1.
#
# NUMBERS ONLY. `<` on strings is a type error on this runtime, so every
# ordering in this package is an ordering of numbers, and a caller that wants
# to order anything else supplies a key function that lands on one.
def compare_values(a, b)
  if a < b
    0 - 1
  else
    if b < a
      1
    else
      0
    end
  end
end

# Lexicographic order over lists: the first differing element decides, and a
# proper prefix sorts before what extends it.
#
# LENGTH IS NOT THE FIRST TEST — [2] is greater than [1, 9, 9]. Comparing sizes
# first is the plausible-looking implementation this is written to avoid.
def compare_lists(a, b)
  if is_empty(a)
    if is_empty(b)
      0
    else
      0 - 1
    end
  else
    if is_empty(b)
      1
    else
      c = compare_values(first(a), first(b))
      if c == 0
        compare_lists(rest(a), rest(b))
      else
        c
      end
    end
  end
end

# Merge two ALREADY-SORTED lists into one sorted list.
#
# Ties take from the left list, which is what makes a merge sort stable.
def merge_sorted(a, b)
  if is_empty(a)
    b
  else
    if is_empty(b)
      a
    else
      if first(a) <= first(b)
        cons(first(a), merge_sorted(rest(a), b))
      else
        cons(first(b), merge_sorted(a, rest(b)))
      end
    end
  end
end

def merge_sorted_by(key, a, b)
  if is_empty(a)
    b
  else
    if is_empty(b)
      a
    else
      if key(first(a)) <= key(first(b))
        cons(first(a), merge_sorted_by(key, rest(a), b))
      else
        cons(first(b), merge_sorted_by(key, a, rest(b)))
      end
    end
  end
end

def is_sorted_by(key, xs)
  if size(xs) < 2
    true
  else
    if key(first(xs)) <= key(nth(1, xs))
      is_sorted_by(key, rest(xs))
    else
      false
    end
  end
end

def is_sorted_desc(xs)
  is_sorted(reverse(xs))
end

def sort_desc_by(key, xs)
  reverse(sort_by(key, xs))
end

# Insert into a list already sorted BY KEY, before the first equal key.
#
# `<=` rather than `<` is the whole of stability: a new element that ties goes
# in front of the ties already there, so building a sort by inserting each head
# into a sorted tail leaves the input order of equals intact.
def insert_sorted_by(key, x, xs)
  if is_empty(xs)
    [x]
  else
    if key(x) <= key(first(xs))
      cons(x, xs)
    else
      cons(first(xs), insert_sorted_by(key, x, rest(xs)))
    end
  end
end

# A STABLE sort by key — equal keys come out in input order.
#
# `sort_by` cannot promise this: it partitions on a pivot with `key(y) <=
# key(pivot)`, so every later element that ties with the pivot is placed
# BEFORE it. That is fine when the key is the whole value, and wrong the moment
# a record carries anything the key does not look at.
def sort_stable_by(key, xs)
  if is_empty(xs)
    []
  else
    insert_sorted_by(key, first(xs), sort_stable_by(key, rest(xs)))
  end
end

# Merge sort: split, sort each half, merge. Also stable, since merge_sorted
# breaks ties toward the left half.
#
# It exists for DEPTH, not for elegance. `sort` nests insert_ordered inside its
# own recursion, so the deepest point is roughly 2n frames; merge_sort's is
# roughly n + log2(n), because the halves are sorted one after the other rather
# than one inside the other. Measured on this runtime with a reversed input:
# `sort` sorts 300 and overflows the stack at 400, merge_sort sorts 500 and
# overflows at 600. Both are still bounded by merge_sorted's own O(n) recursion,
# so this buys a constant factor, not an asymptote.
#
# That difference is deliberately NOT asserted below. A blue `test` runs on the
# main thread under `blue test` but on a 2 MiB Rust TEST thread under `cargo
# test`, where the same `sort` call overflows at 100 rather than 400 — and a
# stack overflow ABORTS the process, so one oversized test would take all 17
# packages down with it rather than failing one assertion. Every test in this
# file is sized for the smaller budget.
def merge_sort(xs)
  if size(xs) < 2
    if is_empty(xs)
      []
    else
      xs
    end
  else
    h = floor(size(xs) / 2)
    merge_sorted(merge_sort(take(h, xs)), merge_sort(drop(h, xs)))
  end
end

# Drop ADJACENT duplicates. On a sorted list that is every duplicate; on an
# unsorted one it is only the neighbouring ones, which is the honest contract —
# this is a cheap linear pass, not a set.
def dedupe_sorted(xs)
  if is_empty(xs)
    []
  else
    if size(xs) < 2
      [first(xs)]
    else
      if first(xs) == nth(1, xs)
        dedupe_sorted(rest(xs))
      else
        cons(first(xs), dedupe_sorted(rest(xs)))
      end
    end
  end
end

def lower_bound_from(xs, target, lo, hi)
  if lo >= hi
    lo
  else
    mid = floor((lo + hi) / 2)
    if nth(mid, xs) < target
      lower_bound_from(xs, target, mid + 1, hi)
    else
      lower_bound_from(xs, target, lo, mid)
    end
  end
end

def upper_bound_from(xs, target, lo, hi)
  if lo >= hi
    lo
  else
    mid = floor((lo + hi) / 2)
    if nth(mid, xs) <= target
      upper_bound_from(xs, target, mid + 1, hi)
    else
      upper_bound_from(xs, target, lo, mid)
    end
  end
end

# The FIRST index at which target could be inserted without breaking the order.
#
# This is what `index_of_sorted` cannot tell you: binary search returns some
# matching index, and with duplicates "some" is not a position. It is also the
# answer for a value that is absent — where it would go — so it is the
# insertion point as well as the lower bound.
def lower_bound(xs, target)
  lower_bound_from(xs, target, 0, size(xs))
end

# The LAST such index — one past the final occurrence of target.
def upper_bound(xs, target)
  upper_bound_from(xs, target, 0, size(xs))
end

# How many times target occurs, in O(log n) rather than a scan.
def count_sorted(xs, target)
  upper_bound(xs, target) - lower_bound(xs, target)
end

def contains_sorted(xs, target)
  index_of_sorted(xs, target) >= 0
end

# The median of three values, which is the standard cheap pivot choice.
#
# max(min(a,b), min(max(a,b), c)) rather than nth(1, sort([a,b,c])): the whole
# point of a median-of-three pivot is to cost less than a sort.
def median_of_three(a, b, c)
  max(min(a, b), min(max(a, b), c))
end

# 0-indexed, to agree with `nth` rather than with English: nth_smallest(0, xs)
# is the minimum. Out of range is nil, not an error.
#
# POSITIONAL, not distinct: nth_smallest(1, [5, 5, 1]) is 5, because the second
# smallest of three values is the second one, duplicate or not.
def nth_smallest(n, xs)
  if (n < 0) || (n >= size(xs))
    nil
  else
    nth(n, sort(xs))
  end
end

def nth_largest(n, xs)
  if (n < 0) || (n >= size(xs))
    nil
  else
    nth(n, sort_desc(xs))
  end
end

# The n largest, largest first. Asking for more than there is yields everything
# rather than erroring — a truncation should not become an exception.
def top_n(n, xs)
  if n < 1
    []
  else
    take(n, sort_desc(xs))
  end
end

def bottom_n(n, xs)
  if n < 1
    []
  else
    take(n, sort(xs))
  end
end

# The indices of xs in sorted order: nth(nth(0, argsort(xs)), xs) is the
# smallest element. Ties keep their input order, because sort_stable_by does.
def argsort(xs)
  sort_stable_by(fn(i) nth(i, xs) end, indexes(xs))
end

# Where each element LANDS in sorted order — the inverse permutation of
# argsort, and the answer to "what position is this one in?".
#
# Ties get consecutive positions in input order rather than a shared one. That
# is the ranking that inverts argsort; the sports-style "two firsts, then a
# third" is a different function and is not this one.
def rank(xs)
  ids = indexes(xs)
  map(fn(i) count_if(fn(j) (nth(j, xs) < nth(i, xs)) || ((nth(j, xs) == nth(i, xs)) && (j < i)) end, ids) end, ids)
end

# Sorted AND without duplicates. `is_sorted` says yes to [1, 1]; this does not,
# which is the difference between an order and a strict one.
def is_strictly_sorted(xs)
  is_sorted(xs) && (size(dedupe_sorted(xs)) == size(xs))
end

# k-way merge: fold the pairwise merge over a list of sorted lists.
def merge_all_sorted(xss)
  reduce(fn(acc, xs) merge_sorted(acc, xs) end, [], xss)
end

def insert_lex(x, xss)
  if is_empty(xss)
    [x]
  else
    if compare_lists(x, first(xss)) <= 0
      cons(x, xss)
    else
      cons(first(xss), insert_lex(x, rest(xss)))
    end
  end
end

# Sort a list OF LISTS lexicographically.
#
# `sort` cannot do this at all — `<` on two lists is a type error on this
# runtime, not a lexicographic comparison — so compare_lists is the only way
# the order exists, and this is what makes it usable. Stable, by insertion.
def sort_lists(xss)
  if is_empty(xss)
    []
  else
    insert_lex(first(xss), sort_lists(rest(xss)))
  end
end

test "sort orders, is idempotent, and handles the small cases"
  assert sort([3, 1, 2]) == [1, 2, 3]
  assert sort([]) == []
  assert sort([1]) == [1]
  assert sort(sort([5, 3, 9, 1])) == [1, 3, 5, 9]
  assert sort([2, 2, 1]) == [1, 2, 2]
end

test "is_sorted agrees with sort"
  assert is_sorted([1, 2, 2, 3]) == true
  assert is_sorted([2, 1]) == false
  assert is_sorted([]) == true
  assert is_sorted(sort([9, 4, 7, 1, 3])) == true
end

test "sort_by uses the key, sort_desc reverses"
  assert sort_by(fn(x) 0 - x end, [1, 3, 2]) == [3, 2, 1]
  assert sort_desc([1, 3, 2]) == [3, 2, 1]
end

test "binary search finds, and reports absence as -1"
  xs = [1, 3, 5, 7, 9]
  assert index_of_sorted(xs, 1) == 0
  assert index_of_sorted(xs, 9) == 4
  assert index_of_sorted(xs, 5) == 2
  assert index_of_sorted(xs, 4) == 0 - 1
  assert index_of_sorted([], 1) == 0 - 1
end

test "min_by and max_by"
  assert min_by(fn(x) x end, [3, 1, 2]) == 1
  assert max_by(fn(x) x end, [3, 1, 2]) == 3
  # The vacuous case: the extreme of nothing is nil rather than an error,
  # because sort_by of [] is [] and retsu's first/last are total over it.
  assert min_by(fn(x) x end, []) == nil
  assert max_by(fn(x) x end, []) == nil
  # A key that is not the value, which is the only reason these exist at all.
  assert min_by(fn(p) nth(1, p) end, [["a", 9], ["b", 2]]) == ["b", 2]
end

test "compare_values answers all three cases, including the equal one"
  assert compare_values(1, 2) == 0 - 1
  assert compare_values(2, 1) == 1
  # The case a two-branch comparison gets wrong: equal is its own answer.
  assert compare_values(2, 2) == 0
  assert compare_values(0 - 3, 0 - 1) == 0 - 1
end

test "compare_lists is lexicographic, not by length"
  # A prefix sorts before what extends it.
  assert compare_lists([1, 2], [1, 2, 3]) == 0 - 1
  assert compare_lists([1, 2, 3], [1, 2]) == 1
  # The first difference decides even when the shorter list wins.
  assert compare_lists([2], [1, 9, 9]) == 1
  assert compare_lists([1, 9, 9], [2]) == 0 - 1
  assert compare_lists([1, 2], [1, 2]) == 0
  assert compare_lists([], []) == 0
  assert compare_lists([], [0]) == 0 - 1
end

test "merge_sorted merges without re-sorting"
  assert merge_sorted([1, 4, 7], [2, 3, 9]) == [1, 2, 3, 4, 7, 9]
  # Either side empty is the identity, and neither empty is nil.
  assert merge_sorted([], [1, 2]) == [1, 2]
  assert merge_sorted([1, 2], []) == [1, 2]
  assert merge_sorted([], []) == []
  # Duplicates across the two sides survive; a merge is not a union.
  assert merge_sorted([1, 1], [1]) == [1, 1, 1]
  # Disjoint ranges: the answer is a concatenation, which a naive interleave
  # would get wrong.
  assert merge_sorted([1, 2], [8, 9]) == [1, 2, 8, 9]
  assert is_sorted(merge_sorted([1, 5, 5], [0, 5, 6])) == true
end

test "merge_sorted_by merges on the key"
  key = fn(p) nth(0, p) end
  a = [[1, "a"], [3, "c"]]
  b = [[2, "b"], [4, "d"]]
  assert merge_sorted_by(key, a, b) == [[1, "a"], [2, "b"], [3, "c"], [4, "d"]]
  assert merge_sorted_by(key, [], b) == b
  # A tie takes from the LEFT list, which is what makes a merge sort stable.
  assert merge_sorted_by(key, [[1, "left"]], [[1, "right"]]) == [[1, "left"], [1, "right"]]
end

test "is_sorted_by, is_sorted_desc"
  assert is_sorted_by(fn(x) 0 - x end, [3, 2, 1]) == true
  assert is_sorted_by(fn(x) 0 - x end, [1, 2, 3]) == false
  assert is_sorted_by(fn(x) x end, []) == true
  assert is_sorted_desc([3, 2, 2, 1]) == true
  assert is_sorted_desc([1, 2]) == false
  # A single element is both, which is the pair of vacuous cases.
  assert is_sorted_desc([7]) == true
  assert is_sorted([7]) == true
end

test "sort_desc_by orders by key, descending"
  assert sort_desc_by(fn(x) x end, [1, 3, 2]) == [3, 2, 1]
  assert sort_desc_by(fn(p) nth(1, p) end, [["a", 1], ["b", 9]]) == [["b", 9], ["a", 1]]
end

test "insert_sorted_by puts a tie in FRONT of the ties already there"
  key = fn(p) nth(0, p) end
  ins = fn(x, xs) insert_sorted_by(key, x, xs) end
  assert ins([2, "new"], [[1, "a"], [3, "c"]]) == [[1, "a"], [2, "new"], [3, "c"]]
  # The stability-carrying case: the arriving [2, "new"] lands before the
  # [2, "old"] already present.
  assert ins([2, "new"], [[2, "old"]]) == [[2, "new"], [2, "old"]]
  assert ins([1, "a"], []) == [[1, "a"]]
end

test "sort_stable_by keeps equal keys in input order"
  # Five records over two keys: a stable sort must return the members of each
  # key in the order they arrived, and any sort that reorders ties fails here.
  # The payload is what makes the tie observable at all — on bare numbers,
  # stability cannot be seen.
  key = fn(p) nth(0, p) end
  rs = [[2, "b1"], [1, "a1"], [2, "b2"], [1, "a2"], [2, "b3"]]
  assert sort_stable_by(key, rs) == [[1, "a1"], [1, "a2"], [2, "b1"], [2, "b2"], [2, "b3"]]
  # On distinct keys it agrees with sort_by, so stability is the ONLY thing
  # that separates the two sorts.
  ds = [[3, "c"], [1, "a"], [2, "b"]]
  assert sort_stable_by(key, ds) == sort_by(key, ds)
  assert sort_stable_by(key, []) == []
  assert is_sorted_by(key, sort_stable_by(key, rs)) == true
end

test "merge_sort agrees with sort, which is two algorithms checking each other"
  xs = [5, 3, 9, 1, 7, 3, 0, 8, 2, 9, 4, 6]
  assert merge_sort(xs) == sort(xs)
  assert merge_sort(xs) == [0, 1, 2, 3, 3, 4, 5, 6, 7, 8, 9, 9]
  # An odd length exercises the uneven split, where an off-by-one in `floor`
  # would drop or duplicate the middle element.
  assert merge_sort([3, 1, 2]) == [1, 2, 3]
  assert size(merge_sort([3, 1, 2, 5, 4])) == 5
  assert merge_sort([]) == []
  assert merge_sort([1]) == [1]
  # Already sorted and exactly reversed are the two inputs a split-and-merge
  # gets wrong in opposite ways.
  assert merge_sort([1, 2, 3, 4]) == [1, 2, 3, 4]
  assert merge_sort([4, 3, 2, 1]) == [1, 2, 3, 4]
end

test "dedupe_sorted removes runs, and only runs"
  assert dedupe_sorted([1, 1, 2, 3, 3, 3]) == [1, 2, 3]
  assert dedupe_sorted([]) == []
  assert dedupe_sorted([1]) == [1]
  assert dedupe_sorted([1, 1, 1]) == [1]
  assert dedupe_sorted([1, 2, 3]) == [1, 2, 3]
  # ADJACENT only: unsorted input keeps the separated pair, which is the line
  # between this and a set operation.
  assert dedupe_sorted([1, 2, 1]) == [1, 2, 1]
  # Sorting first is what makes it a full dedupe, and the two compose into a
  # sorted union of two sorted lists.
  assert dedupe_sorted(sort([1, 2, 1])) == [1, 2]
  assert dedupe_sorted(merge_sorted([1, 3, 5], [3, 4, 5])) == [1, 3, 4, 5]
end

test "lower_bound and upper_bound bracket a run of duplicates"
  xs = [1, 3, 3, 3, 5]
  # The pair is the whole point: index_of_sorted lands SOMEWHERE in the run,
  # these two say where the run starts and ends.
  assert lower_bound(xs, 3) == 1
  assert upper_bound(xs, 3) == 4
  assert count_sorted(xs, 3) == 3
  # An absent value gets the same answer from both — where it would go.
  assert lower_bound(xs, 4) == 4
  assert upper_bound(xs, 4) == 4
  assert count_sorted(xs, 4) == 0
  # Off both ends, and empty.
  assert lower_bound(xs, 0) == 0
  assert upper_bound(xs, 9) == 5
  assert lower_bound([], 1) == 0
  assert count_sorted([], 1) == 0
  # The identity that defines an insertion point: inserting there keeps order.
  assert is_sorted(append(append(take(lower_bound(xs, 4), xs), [4]), drop(lower_bound(xs, 4), xs))) == true
end

test "contains_sorted"
  assert contains_sorted([1, 3, 5], 3) == true
  assert contains_sorted([1, 3, 5], 4) == false
  assert contains_sorted([], 1) == false
  assert contains_sorted([2], 2) == true
end

test "median_of_three is the middle whatever the order"
  # All six permutations, because a pivot chooser that works only for the
  # already-sorted arrangement is the classic wrong version.
  assert median_of_three(1, 2, 3) == 2
  assert median_of_three(1, 3, 2) == 2
  assert median_of_three(2, 1, 3) == 2
  assert median_of_three(2, 3, 1) == 2
  assert median_of_three(3, 1, 2) == 2
  assert median_of_three(3, 2, 1) == 2
  # Ties, where "the one that is neither the min nor the max" stops existing.
  assert median_of_three(5, 5, 1) == 5
  assert median_of_three(1, 5, 1) == 1
  assert median_of_three(7, 7, 7) == 7
  # Against the obvious-but-costlier oracle.
  assert median_of_three(9, 2, 4) == nth(1, sort([9, 2, 4]))
end

test "nth_smallest and nth_largest are positional, and total"
  xs = [3, 1, 2]
  assert nth_smallest(0, xs) == 1
  assert nth_smallest(2, xs) == 3
  assert nth_largest(0, xs) == 3
  assert nth_largest(2, xs) == 1
  # Duplicates count as separate positions — the second smallest of [5,5,1]
  # is 5, not "the second distinct value".
  assert nth_smallest(1, [5, 5, 1]) == 5
  assert nth_largest(1, [5, 5, 1]) == 5
  # Out of range answers nil rather than erroring, in both directions.
  assert nth_smallest(3, xs) == nil
  assert nth_smallest(0 - 1, xs) == nil
  assert nth_largest(9, xs) == nil
  assert nth_smallest(0, []) == nil
end

test "top_n and bottom_n"
  xs = [5, 1, 9, 3]
  assert top_n(2, xs) == [9, 5]
  assert bottom_n(2, xs) == [1, 3]
  assert top_n(0, xs) == []
  # More than there is yields everything rather than erroring.
  assert top_n(9, [1, 2]) == [2, 1]
  assert bottom_n(9, [1, 2]) == [1, 2]
  assert top_n(2, []) == []
  # Duplicates occupy their own slots.
  assert top_n(2, [7, 7, 1]) == [7, 7]
  assert top_n(1, xs) == [nth_largest(0, xs)]
end

test "argsort returns indices, and indexing by them sorts"
  assert argsort([30, 10, 20]) == [1, 2, 0]
  assert argsort([]) == []
  assert argsort([4]) == [0]
  # The identity that makes it argsort rather than a permutation that happens
  # to look right on one input.
  xs = [5, 3, 9, 1, 7]
  assert map(fn(i) nth(i, xs) end, argsort(xs)) == sort(xs)
  # Ties keep input order: index 0 before index 2, both holding 5.
  assert argsort([5, 1, 5]) == [1, 0, 2]
end

test "rank inverts argsort"
  assert rank([30, 10, 20]) == [2, 0, 1]
  assert rank([]) == []
  assert rank([9]) == [0]
  assert rank([1, 2, 3]) == [0, 1, 2]
  # Ties get consecutive positions in input order, so a rank list is always a
  # permutation — this is what a shared-rank implementation gets wrong.
  assert rank([5, 1, 5]) == [1, 0, 2]
  assert sort(rank([7, 7, 7])) == [0, 1, 2]
  # The inverse-permutation identity, stated directly.
  xs = [5, 3, 9, 1, 7]
  assert map(fn(i) nth(i, rank(xs)) end, argsort(xs)) == range(0, size(xs))
  # And the round trip: the rank of an element indexes it in the sorted list.
  assert map(fn(i) nth(nth(i, rank(xs)), sort(xs)) end, indexes(xs)) == xs
end

test "is_strictly_sorted rejects the duplicates is_sorted allows"
  assert is_strictly_sorted([1, 2, 3]) == true
  # The whole distinction, in one pair of assertions.
  assert is_sorted([1, 1, 2]) == true
  assert is_strictly_sorted([1, 1, 2]) == false
  assert is_strictly_sorted([2, 1]) == false
  assert is_strictly_sorted([]) == true
  assert is_strictly_sorted([7]) == true
end

test "merge_all_sorted merges k lists at once"
  assert merge_all_sorted([[1, 4], [2, 5], [3, 6]]) == [1, 2, 3, 4, 5, 6]
  # The folds that a reduce over the wrong initial value gets wrong.
  assert merge_all_sorted([]) == []
  assert merge_all_sorted([[1, 2]]) == [1, 2]
  assert merge_all_sorted([[], []]) == []
  # Duplicates across lists all survive: k-way merge, not k-way union.
  assert merge_all_sorted([[1], [1], [1]]) == [1, 1, 1]
  assert is_sorted(merge_all_sorted([[9], [0, 5], [3]])) == true
end

test "sort_lists orders lexicographically, which plain sort cannot do at all"
  # A reader can check this by hand: [1,2,3] < [1,9] because 2 < 9 at the
  # first difference, and both are below [2] despite being longer.
  assert sort_lists([[2], [1, 9], [1, 2, 3]]) == [[1, 2, 3], [1, 9], [2]]
  assert sort_lists([]) == []
  assert sort_lists([[1]]) == [[1]]
  # The empty list sorts first, being a prefix of everything.
  assert sort_lists([[1], [], [0]]) == [[], [0], [1]]
  assert sort_lists([[1, 2], [1]]) == [[1], [1, 2]]
  # Sorting an already-sorted list of lists changes nothing.
  assert sort_lists(sort_lists([[3], [1, 1], [2]])) == [[1, 1], [2], [3]]
end

test "sort orders STRINGS, not only numbers"
  # `<=` raises on strings, so this is the assertion that would have failed
  # before sort was phrased on `compare`.
  assert sort(["pear", "apple", "fig"]) == ["apple", "fig", "pear"]
  assert is_sorted(["a", "b", "c"]) == true
  assert is_sorted(["b", "a"]) == false
  # And numbers still sort, which is what makes `compare` the right seam
  # rather than a string-only special case.
  assert sort([3, 1, 2]) == [1, 2, 3]
end
