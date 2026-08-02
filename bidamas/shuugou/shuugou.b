use("ronri")
# shuugou (集合) — sets, over plain lists.
#
# No new data structure: a set is a list with no duplicates, so every list
# function keeps working on one. Membership is linear rather than constant —
# a deliberate trade, because a second container type would fork every
# function in the distribution and none of the forks would be better.

def contains(xs, v)
  any(fn(x) x == v end, xs)
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
  reduce(fn(acc, x) if contains(acc, x)
    acc
  else
    push(acc, x)
  end end, [], xs)
end

def union(a, b)
  unique(append(a, b))
end

def intersection(a, b)
  unique(filter(fn(x) contains(b, x) end, a))
end

def difference(a, b)
  unique(filter(fn(x) !contains(b, x) end, a))
end

def subset(a, b)
  every(fn(x) contains(b, x) end, a)
end

def disjoint(a, b)
  is_empty(intersection(a, b))
end

def symmetric_difference(a, b)
  union(difference(a, b), difference(b, a))
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

test "the empty-set laws"
  # The empty set is a subset of everything and disjoint from everything —
  # the two laws an implementation built from a loop usually gets wrong.
  assert subset([], [1, 2]) == true
  assert subset([1], []) == false
  assert subset([1, 2], [2, 1, 3]) == true
  assert disjoint([], [1]) == true
  assert disjoint([1], [1]) == false
end
