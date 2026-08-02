use("kazu")
# retsu (列) — lists, made TOTAL.
#
# This package exists because the underlying primitives are not total, and a
# standard library's first job is to close that. Measured on the runtime this
# distribution targets:
#
#   cdr([1])        => nil          -- not [], a DIFFERENT empty
#   nil == []       => false        -- the two empties are distinguishable
#   length(nil)     => runtime error: expected a string, got nil
#
# So the obvious recursive shape — `if length(xs) < 1 … else f(cdr(xs))` —
# crashes on every list, at the last element, in every package that writes it.
# It is not a rare edge: it is the base case of structural recursion.
#
# `size` / `first` / `rest` / `is_empty` are the total replacements, and every
# other bidama in this distribution is written against them rather than against
# `length` / `car` / `cdr`. That is the trade a stdlib makes on purpose: one
# indirection, in exchange for a recursion that terminates.
#
# The upstream fix is `length` accepting nil in tatara-lisp-eval. Until that
# lands this is a WORKAROUND at the library layer, not a repair of the cause —
# `length` is still reachable and still wrong.

# Total length: nil counts as empty rather than erroring.
def size(xs)
  if xs == nil
    0
  else
    length(xs)
  end
end

def is_empty(xs)
  size(xs) == 0
end

def first(xs)
  if is_empty(xs)
    nil
  else
    car(xs)
  end
end

# The tail, NORMALISED to a list.
#
# `cdr` hands back nil at the last element; this hands back [] so a caller can
# keep treating the result as a list without a nil check at every step.
def rest(xs)
  if size(xs) < 2
    []
  else
    cdr(xs)
  end
end

def last(xs)
  if is_empty(xs)
    nil
  else
    nth(size(xs) - 1, xs)
  end
end

def push(xs, v)
  append(xs, [v])
end

def concat_lists(a, b)
  append(a, b)
end

def flatten1(xss)
  reduce(fn(acc, xs) append(acc, xs) end, [], xss)
end

def indexes(xs)
  range(0, size(xs))
end

def zip_with(f, a, b)
  map(fn(i) f(nth(i, a), nth(i, b)) end, range(0, min(size(a), size(b))))
end

def zip(a, b)
  zip_with(fn(x, y) [x, y] end, a, b)
end

def repeat(v, n)
  map(fn(i) v end, range(0, n))
end

def sum_to(n)
  if n < 1
    0
  else
    n + sum_to(n - 1)
  end
end

def count_down(n)
  if n < 1
    0
  else
    count_down(n - 1)
  end
end

# The cross-package call: clamp comes from kazu.
def clamped_sum(n, lo, hi)
  clamp(sum_to(n), lo, hi)
end

test "size is total where length is not"
  # cdr of a singleton is nil, and length(nil) errors. This is the whole
  # reason the package exists, so it is the first thing asserted.
  assert size(cdr([1])) == 0
  assert size([]) == 0
  assert size([1, 2, 3]) == 3
  assert is_empty(cdr([1])) == true
end

test "rest normalises the tail to a list"
  assert rest([1, 2, 3]) == [2, 3]
  assert rest([1]) == []
  assert rest([]) == []
  # And the normalised empty is the SAME empty a literal gives, which is what
  # lets a caller compare against [] at all.
  assert rest([1]) == []
end

test "first and last, including the empty case"
  assert first([1, 2]) == 1
  assert last([1, 2]) == 2
  assert first([]) == nil
  assert last([]) == nil
end

test "structural recursion terminates over every list"
  # The shape that crashed before size/rest existed.
  assert sum_to(10) == 55
  assert count_down(50) == 0
end

test "zip, repeat, flatten"
  assert zip([1, 2], [3, 4]) == [[1, 3], [2, 4]]
  assert zip_with(fn(a, b) a + b end, [1, 2], [10, 20]) == [11, 22]
  # zip stops at the SHORTER list rather than reading past the end.
  assert zip([1], [1, 2, 3]) == [[1, 1]]
  assert repeat(7, 3) == [7, 7, 7]
  assert flatten1([[1, 2], [3]]) == [1, 2, 3]
end

test "push and indexes"
  assert push([1, 2], 3) == [1, 2, 3]
  assert push([], 1) == [1]
  assert indexes([9, 9]) == [0, 1]
end

test "the cross-package call into kazu"
  assert clamped_sum(10, 1, 10) == 10
  assert clamped_sum(3, 1, 100) == 6
end

# ---------------------------------------------------------------------------
# Slicing and searching.
#
# ARGUMENT ORDER, stated once and held for everything below: data-first for the
# plain list operations (`take_n(xs, n)`, like `push`/`rest`/`size`), and
# FUNCTION-first for the higher-order ones (`reject(f, xs)`, like
# `map`/`filter`/`reduce`). Those are the two conventions already in the
# language and neither one covers both halves, so the split is the honest
# answer; what a package cannot afford is to be inconsistent inside itself.

# take/drop, total and data-first.
#
# The `_n` suffix is the warning sign, not decoration: the builtins are
# `take(n, xs)` — COUNT first — and these are the other way round. Two orders
# for one operation is a real hazard, so the two spellings differ visibly.
#
# On top of the order they close the partial edges: a negative count, a count
# past the end, and nil for the list all answer with a list instead of an error.
def take_n(xs, n)
  if is_empty(xs) || n < 1
    []
  else
    take(min(n, size(xs)), xs)
  end
end

def drop_n(xs, n)
  if is_empty(xs)
    []
  else
    if n < 1
      xs
    else
      drop(n, xs)
    end
  end
end

# A window by position and length. Out-of-range in either argument yields the
# overlap, which is empty when there is none — never an error.
def slice(xs, start, count)
  take_n(drop_n(xs, start), count)
end

def all_but_last(xs)
  take_n(xs, size(xs) - 1)
end

# Position of the first `v`, or 0 - 1 when absent.
#
# The sentinel is negative rather than nil so a caller can compare it — `nil < 0`
# is not a comparison this runtime will make. `contains` is the predicate to
# reach for when the position itself is not wanted.
def index_of(xs, v)
  index_of_from(xs, v, 0)
end

def index_of_from(xs, v, i)
  if is_empty(xs)
    0 - 1
  else
    if first(xs) == v
      i
    else
      index_of_from(rest(xs), v, i + 1)
    end
  end
end

def contains(xs, v)
  index_of(xs, v) >= 0
end

def count_of(xs, v)
  size(filter(fn(x) x == v end, xs))
end

def without(xs, v)
  filter(fn(x) !(x == v) end, xs)
end

test "take_n and drop_n are total where take and drop are ordered the other way"
  assert take_n([1, 2, 3], 2) == [1, 2]
  assert drop_n([1, 2, 3], 2) == [3]
  # The three edges that make these wrappers worth having.
  assert take_n([1, 2], 9) == [1, 2]
  assert take_n([1, 2], 0 - 1) == []
  assert drop_n([1, 2], 9) == []
  assert drop_n([1, 2], 0 - 1) == [1, 2]
  # nil is the other empty, and it must not reach the builtin.
  assert take_n(cdr([1]), 1) == []
  assert drop_n(cdr([1]), 1) == []
  # take_n and drop_n cut the list in two at every point, losing nothing.
  assert append(take_n([1, 2, 3], 2), drop_n([1, 2, 3], 2)) == [1, 2, 3]
end

test "slice clips instead of erroring"
  assert slice([1, 2, 3, 4], 1, 2) == [2, 3]
  assert slice([1, 2, 3], 2, 9) == [3]
  assert slice([1, 2, 3], 9, 1) == []
  assert slice([], 0, 3) == []
end

test "all_but_last, including the sizes that have no last"
  assert all_but_last([1, 2, 3]) == [1, 2]
  assert all_but_last([1]) == []
  assert all_but_last([]) == []
  # It is the complement of `last`, so the two reassemble the original.
  assert push(all_but_last([1, 2, 3]), last([1, 2, 3])) == [1, 2, 3]
end

test "index_of reports absence as a number, not nil"
  assert index_of([7, 8, 9], 8) == 1
  assert index_of([7, 8, 9], 5) == 0 - 1
  assert index_of([], 5) == 0 - 1
  # FIRST occurrence, not any occurrence.
  assert index_of([5, 5], 5) == 0
  # The sentinel is comparable, which is the point of choosing it.
  assert index_of([1], 9) < 0
end

test "contains, count_of and without"
  assert contains([1, 2], 2) == true
  assert contains([1, 2], 3) == false
  # Nothing is contained in nothing — the vacuous case a wrong predicate gets right by luck.
  assert contains([], 1) == false
  assert count_of([1, 2, 1, 1], 1) == 3
  assert count_of([1, 2], 9) == 0
  assert count_of([], 1) == 0
  assert without([1, 2, 1], 1) == [2]
  # Removing every occurrence, not the first: nothing of `v` survives.
  assert count_of(without([1, 1, 1], 1), 1) == 0
  assert without([1, 2], 9) == [1, 2]
end

# ---------------------------------------------------------------------------
# Editing by position.
#
# All three clamp rather than reject: an index outside the list is a no-op that
# returns the list, because the alternative in a language with no exceptions is
# a caller that must bounds-check before every call and gets it wrong once.

# nil-to-[] normalisation, in one place.
#
# The two empties again, and this time from an operation whose arguments were
# BOTH lists: `append([], [])` hands back nil, so `remove_at([1], 0) == []` is
# false without this. Every constructor below that can produce an empty result
# funnels through it, so a caller never has to ask which empty it got.
def as_list(xs)
  if is_empty(xs)
    []
  else
    xs
  end
end

def insert_at(xs, i, v)
  append(take_n(xs, i), cons(v, drop_n(xs, i)))
end

def remove_at(xs, i)
  as_list(append(take_n(xs, i), drop_n(xs, i + 1)))
end

# Replace, rather than remove-and-insert, so size is preserved and an
# out-of-range index changes nothing.
def update_at(xs, i, v)
  map(fn(j) if j == i
        v
      else
        nth(j, xs)
      end end, indexes(xs))
end

def partition_at(xs, i)
  [take_n(xs, i), drop_n(xs, i)]
end

# Fixed-size groups, last one short.
#
# The `n < 1` guard is load-bearing: without it a chunk size of zero drops
# nothing each pass and the recursion never reaches the empty list.
def chunk(xs, n)
  if is_empty(xs) || n < 1
    []
  else
    cons(take_n(xs, n), chunk(drop_n(xs, n), n))
  end
end

# Overlapping windows of width n — chunk's sliding sibling.
#
# A width wider than the list has no windows at all, which is why this answers
# [] rather than one short window: a caller asking for pairs wants pairs.
def windows(xs, n)
  if n < 1 || size(xs) < n
    []
  else
    map(fn(i) slice(xs, i, n) end, range(0, size(xs) - n + 1))
  end
end

# Rotate left by n, wrapping. Negative n rotates right, and n past the end
# wraps, because `modulo` here floors rather than truncating.
def rotate(xs, n)
  if is_empty(xs)
    []
  else
    k = modulo(n, size(xs))
    append(drop_n(xs, k), take_n(xs, k))
  end
end

def interleave(a, b)
  as_list(flatten1(zip(a, b)))
end

test "insert_at and remove_at, at the ends and past them"
  assert insert_at([1, 3], 1, 2) == [1, 2, 3]
  assert insert_at([1, 2], 0, 0) == [0, 1, 2]
  assert insert_at([1, 2], 2, 3) == [1, 2, 3]
  assert insert_at([], 0, 1) == [1]
  # Past the end appends rather than erroring.
  assert insert_at([1], 9, 2) == [1, 2]
  assert remove_at([1, 2, 3], 1) == [1, 3]
  assert remove_at([1], 0) == []
  assert remove_at([1, 2], 9) == [1, 2]
  assert remove_at([1, 2], 0 - 1) == [1, 2]
  # They are inverses at any in-range index, which no off-by-one survives.
  assert remove_at(insert_at([1, 2, 3], 2, 99), 2) == [1, 2, 3]
end

test "update_at replaces in place"
  assert update_at([1, 2, 3], 1, 9) == [1, 9, 3]
  assert update_at([1, 2, 3], 0, 9) == [9, 2, 3]
  # Out of range is a no-op, and size never changes — the difference from
  # insert_at, which is the mistake this pair invites.
  assert update_at([1, 2], 9, 0) == [1, 2]
  assert size(update_at([1, 2, 3], 1, 9)) == 3
  assert update_at([], 0, 9) == []
end

test "partition_at splits without losing anything"
  assert partition_at([1, 2, 3], 1) == [[1], [2, 3]]
  assert partition_at([1, 2], 0) == [[], [1, 2]]
  assert partition_at([1, 2], 9) == [[1, 2], []]
  assert partition_at([], 1) == [[], []]
end

test "chunk groups, and terminates on a zero width"
  assert chunk([1, 2, 3, 4], 2) == [[1, 2], [3, 4]]
  # A short final group is kept, not dropped or padded.
  assert chunk([1, 2, 3], 2) == [[1, 2], [3]]
  assert chunk([], 2) == []
  # The guard against a non-terminating recursion.
  assert chunk([1, 2], 0) == []
  # Chunking loses no element, whatever the remainder.
  assert flatten1(chunk([1, 2, 3, 4, 5], 3)) == [1, 2, 3, 4, 5]
end

test "windows slide by one and overlap"
  assert windows([1, 2, 3, 4], 2) == [[1, 2], [2, 3], [3, 4]]
  # n windows of width w over a list of length n + w - 1.
  assert size(windows([1, 2, 3, 4, 5], 3)) == 3
  # Exactly one window when the width is the whole list, none when it is wider.
  assert windows([1, 2], 2) == [[1, 2]]
  assert windows([1, 2], 3) == []
  assert windows([], 1) == []
  assert windows([1, 2], 0) == []
end

test "rotate wraps in both directions"
  assert rotate([1, 2, 3, 4], 1) == [2, 3, 4, 1]
  # Negative rotates the other way, which is the branch a truncating modulo
  # would get wrong.
  assert rotate([1, 2, 3, 4], 0 - 1) == [4, 1, 2, 3]
  # A full turn, and more than a full turn, are identities on the count.
  assert rotate([1, 2, 3], 3) == [1, 2, 3]
  assert rotate([1, 2, 3], 4) == rotate([1, 2, 3], 1)
  assert rotate([1, 2, 3], 0) == [1, 2, 3]
  assert rotate([], 2) == []
end

test "interleave alternates and stops at the shorter list"
  assert interleave([1, 2], [3, 4]) == [1, 3, 2, 4]
  assert interleave([1], [2, 3, 4]) == [1, 2]
  assert interleave([], [1, 2]) == []
end

# ---------------------------------------------------------------------------
# Predicates and folds. These take the FUNCTION first, matching
# `map`/`filter`/`reduce`, and not the data-first order used above.

# The first element satisfying f, or nil.
#
# nil doubles as "no match", which is only ambiguous for a list that itself
# holds nil; `index_of` and a numeric sentinel is the way out when that matters.
def find_first(f, xs)
  if is_empty(xs)
    nil
  else
    if f(first(xs))
      first(xs)
    else
      find_first(f, rest(xs))
    end
  end
end

def reject(f, xs)
  filter(fn(x) !f(x) end, xs)
end

def count_where(f, xs)
  size(filter(f, xs))
end

# Both halves of one pass, in the order [kept, rejected].
def partition(f, xs)
  [filter(f, xs), reject(f, xs)]
end

# take_while stops at the FIRST failure and does not resume — the difference
# from `filter`, and the only reason both exist.
def take_while(f, xs)
  if is_empty(xs)
    []
  else
    if f(first(xs))
      cons(first(xs), take_while(f, rest(xs)))
    else
      []
    end
  end
end

def drop_while(f, xs)
  if is_empty(xs)
    []
  else
    if f(first(xs))
      drop_while(f, rest(xs))
    else
      xs
    end
  end
end

# Every intermediate accumulator of a `reduce`, init included, so the result is
# one longer than the input and `last(scan(...)) == reduce(...)`.
def scan(f, init, xs)
  cons(init, scan_from(f, init, xs))
end

def scan_from(f, acc, xs)
  if is_empty(xs)
    []
  else
    nxt = f(acc, first(xs))
    cons(nxt, scan_from(f, nxt, rest(xs)))
  end
end

# Running totals in the usual sense — same length as the input, no leading
# zero. That is `scan` with its seed dropped, which is what "running total"
# means to everyone who is not thinking about folds.
def running_sum(xs)
  rest(scan(fn(a, b) a + b end, 0, xs))
end

def enumerate(xs)
  zip(indexes(xs), xs)
end

def flat_map(f, xs)
  as_list(flatten1(map(f, xs)))
end

# The inverse of zip: a list of pairs back into [firsts, seconds].
def unzip(ps)
  [map(fn(p) nth(0, p) end, ps), map(fn(p) nth(1, p) end, ps)]
end

test "find_first returns the element, not its position"
  assert find_first(fn(x) x > 1 end, [1, 2, 3]) == 2
  assert find_first(fn(x) x > 9 end, [1, 2]) == nil
  # Nothing satisfies anything in an empty list — including a predicate that is
  # true of everything, which is where a vacuous implementation shows up.
  assert find_first(fn(x) true end, []) == nil
end

test "reject, count_where and partition"
  assert reject(fn(x) x > 2 end, [1, 2, 3, 4]) == [1, 2]
  assert reject(fn(x) true end, [1, 2]) == []
  assert reject(fn(x) false end, [1, 2]) == [1, 2]
  assert count_where(fn(x) x > 1 end, [1, 2, 3]) == 2
  assert count_where(fn(x) x > 1 end, []) == 0
  assert partition(fn(x) x > 2 end, [1, 3, 2, 4]) == [[3, 4], [1, 2]]
  # The two halves account for every element exactly once, whatever the predicate.
  assert count_where(fn(x) x > 2 end, [1, 3, 2, 4]) + size(reject(fn(x) x > 2 end, [1, 3, 2, 4])) == 4
  assert partition(fn(x) true end, []) == [[], []]
end

test "take_while and drop_while stop at the first failure"
  assert take_while(fn(x) x < 3 end, [1, 2, 3, 1]) == [1, 2]
  # The trailing 1 passes the predicate and is still dropped — this is what
  # separates take_while from filter, and filter would answer [1, 2, 1].
  assert drop_while(fn(x) x < 3 end, [1, 2, 3, 1]) == [3, 1]
  assert take_while(fn(x) false end, [1, 2]) == []
  assert drop_while(fn(x) true end, [1, 2]) == []
  assert take_while(fn(x) true end, []) == []
  assert drop_while(fn(x) true end, []) == []
  # Together they rebuild the input, at any split point.
  assert append(take_while(fn(x) x < 3 end, [1, 2, 3, 1]), drop_while(fn(x) x < 3 end, [1, 2, 3, 1])) == [1, 2, 3, 1]
end

test "scan keeps every intermediate accumulator"
  assert scan(fn(a, b) a + b end, 0, [1, 2, 3]) == [0, 1, 3, 6]
  # Seed included, so an empty input still yields the seed and the length is
  # always size + 1 — the off-by-one a plausible implementation gets wrong.
  assert scan(fn(a, b) a + b end, 7, []) == [7]
  assert size(scan(fn(a, b) a + b end, 0, [1, 2, 3])) == 4
  # The last accumulator is exactly what reduce would have returned.
  assert last(scan(fn(a, b) a + b end, 0, [1, 2, 3, 4])) == reduce(fn(a, b) a + b end, 0, [1, 2, 3, 4])
  # It is not sum-specific.
  assert scan(fn(a, b) a * b end, 1, [2, 3, 4]) == [1, 2, 6, 24]
end

test "running_sum has no leading seed"
  assert running_sum([1, 2, 3]) == [1, 3, 6]
  assert running_sum([]) == []
  assert size(running_sum([1, 2, 3, 4])) == 4
  # Negative steps go down again, so this is a running total and not a maximum.
  assert running_sum([5, 0 - 3]) == [5, 2]
end

test "enumerate, flat_map and unzip"
  assert enumerate([7, 8]) == [[0, 7], [1, 8]]
  assert enumerate([]) == []
  assert flat_map(fn(x) [x, x] end, [1, 2]) == [1, 1, 2, 2]
  # A function returning an empty list contributes nothing rather than a hole.
  assert flat_map(fn(x) [] end, [1, 2]) == []
  assert flat_map(fn(x) [x] end, []) == []
  assert unzip([[1, 3], [2, 4]]) == [[1, 2], [3, 4]]
  assert unzip([]) == [[], []]
  # unzip undoes zip — the identity that catches a transposed implementation.
  assert unzip(zip([1, 2, 3], [4, 5, 6])) == [[1, 2, 3], [4, 5, 6]]
end

# ---------------------------------------------------------------------------
# Comparison.

# Element-wise equality that treats the two empties as one.
#
# `==` on lists is structural and works, so this is not a reimplementation of
# it — it exists because `cdr([1]) == []` is FALSE, so any comparison against a
# computed tail is wrong at exactly the recursion's base case. Anything built
# out of `rest`/`take_n`/`drop_n` should be compared with this, not with `==`.
def equal_lists(a, b)
  if is_empty(a) || is_empty(b)
    is_empty(a) && is_empty(b)
  else
    if first(a) == first(b)
      equal_lists(rest(a), rest(b))
    else
      false
    end
  end
end

# Read as "p is a prefix of xs" — the subject comes first, as in the name.
def is_prefix_of(p, xs)
  equal_lists(p, take_n(xs, size(p)))
end

def is_suffix_of(s, xs)
  equal_lists(s, drop_n(xs, size(xs) - size(s)))
end

# Flatten exactly `depth` levels.
#
# There is deliberately no depth-unlimited `flatten`, and it is not an omission
# of convenience: it cannot be written here. Deciding whether an element is a
# list or a leaf needs a list predicate, and the only one the runtime has is
# spelled `list?` — a name blue's lexer rejects, so it is unreachable. Every
# alternative probe is partial: `length`, `nth`, `map` and `append` all raise on
# a non-list, `to_s` erases the structure it would have to reveal
# (`to_s([[1],[2]])` and `to_s([1,2])` are the same string), and there is no
# way to catch the raise. So the depth is the caller's to state, and a level
# whose elements are not all lists is an error rather than a silent pass.
def flatten_n(xss, depth)
  if depth < 1 || is_empty(xss)
    as_list(xss)
  else
    flatten_n(flatten1(xss), depth - 1)
  end
end

test "equal_lists equates the two empties, which == does not"
  # The whole reason this is not just `==`.
  assert (cdr([1]) == []) == false
  assert equal_lists(cdr([1]), []) == true
  assert equal_lists([], []) == true
  assert equal_lists([1, 2], [1, 2]) == true
  assert equal_lists([1, 2], [1, 3]) == false
  # Different lengths, in both directions — a same-length-only comparison
  # would report the first of these true.
  assert equal_lists([1, 2], [1]) == false
  assert equal_lists([1], [1, 2]) == false
  # Empty against non-empty, which is the vacuous case that goes wrong.
  assert equal_lists([], [1]) == false
  assert equal_lists([1], []) == false
  # It survives a computed tail, which is where `==` fails.
  assert equal_lists(rest([1, 2]), drop_n([1, 2], 1)) == true
end

test "is_prefix_of and is_suffix_of"
  assert is_prefix_of([1, 2], [1, 2, 3]) == true
  assert is_suffix_of([2, 3], [1, 2, 3]) == true
  # A prefix is not a suffix and the reverse, or the two are the same function.
  assert is_suffix_of([1, 2], [1, 2, 3]) == false
  assert is_prefix_of([2, 3], [1, 2, 3]) == false
  # The empty list prefixes and suffixes everything; a longer candidate does neither.
  assert is_prefix_of([], [1, 2]) == true
  assert is_suffix_of([], [1, 2]) == true
  assert is_prefix_of([1, 2, 3], [1, 2]) == false
  assert is_suffix_of([1, 2, 3], [1, 2]) == false
  # A list is both a prefix and a suffix of itself.
  assert is_prefix_of([1, 2], [1, 2]) == true
  assert is_suffix_of([1, 2], [1, 2]) == true
end

test "flatten_n unwraps exactly the depth asked for"
  assert flatten_n([[1, 2], [3]], 1) == [1, 2, 3]
  assert flatten_n([[[1], [2]], [[3]]], 2) == [1, 2, 3]
  # One level short leaves the inner lists intact — the whole point of the
  # depth being explicit.
  assert flatten_n([[[1], [2]], [[3]]], 1) == [[1], [2], [3]]
  # Depth zero is the identity, and a depth past the structure is not reached
  # because the list empties out first.
  assert flatten_n([[1], [2]], 0) == [[1], [2]]
  assert flatten_n([], 3) == []
  assert flatten_n([[], []], 1) == []
end
