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
    if x <= first(xs)
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
    if first(xs) <= nth(1, xs)
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
end
