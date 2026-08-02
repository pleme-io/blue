use("kazu")
use("retsu")
# gyouretsu (行列) — vectors and matrices as nested lists.
#
# A matrix is a list of rows. No new type, for the same reason shuugou uses
# plain lists: a bespoke container would need its own map, its own equality
# and its own printer, and none of those would be better than the ones a list
# already has.

def dot(a, b)
  reduce(fn(acc, i) acc + (nth(i, a) * nth(i, b)) end, 0, range(0, length(a)))
end

def scale(k, v)
  map(fn(x) k * x end, v)
end

def vadd(a, b)
  map(fn(i) nth(i, a) + nth(i, b) end, range(0, length(a)))
end

def vsub(a, b)
  map(fn(i) nth(i, a) - nth(i, b) end, range(0, length(a)))
end

def magnitude(v)
  sqrt(dot(v, v))
end

def rows(m)
  length(m)
end

def cols(m)
  length(car(m))
end

def col(m, j)
  map(fn(r) nth(j, r) end, m)
end

def transpose(m)
  map(fn(j) col(m, j) end, range(0, cols(m)))
end

def matmul(a, b)
  bt = transpose(b)
  map(fn(r) map(fn(c) dot(r, c) end, bt) end, a)
end

def identity_matrix(n)
  map(fn(i) map(fn(j) if i == j
    1
  else
    0
  end end, range(0, n)) end, range(0, n))
end

test "dot product and magnitude"
  assert dot([1, 2, 3], [4, 5, 6]) == 32
  # A 3-4-5 triangle, so the magnitude is exact rather than approximate.
  assert near(magnitude([3, 4]), 5) == true
end

test "vector arithmetic"
  assert scale(3, [1, 2]) == [3, 6]
  assert vadd([1, 2], [3, 4]) == [4, 6]
  assert vsub([5, 5], [1, 2]) == [4, 3]
end

test "transpose is its own inverse"
  m = [[1, 2, 3], [4, 5, 6]]
  assert transpose(m) == [[1, 4], [2, 5], [3, 6]]
  assert transpose(transpose(m)) == m
end

test "matrix multiply, and identity leaves a matrix alone"
  a = [[1, 2], [3, 4]]
  assert matmul(a, identity_matrix(2)) == a
  assert matmul(a, [[0, 1], [1, 0]]) == [[2, 1], [4, 3]]
end
