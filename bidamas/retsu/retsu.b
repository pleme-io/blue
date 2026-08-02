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
