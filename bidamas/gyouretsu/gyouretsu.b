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

# Zero-length test by distance, never by `== 0`.
#
# `magnitude([0, 0])` is Float(0.0) and `Float(0.0) == Int(0)` is false in this
# runtime, so the obvious guard lets a zero vector through into a division and
# the interpreter aborts with `division by zero`. Every guard below routes
# through here for that reason.
def is_zero_vector(v)
  near(dot(v, v), 0)
end

# Element-wise approximate equality. Anything that has been through `/` or
# `sqrt` comes back as a float, and `[0.6, 0.8] == [0.6, 0.8]` is only true when
# both sides took the identical float path — so a caller comparing a computed
# vector against a written-out literal needs this, not `==`.
def vector_near(a, b)
  if size(a) == size(b)
    reduce(fn(acc, i) acc && near(nth(i, a), nth(i, b)) end, true, indexes(a))
  else
    false
  end
end

def normalize(v)
  if is_zero_vector(v)
    v
  else
    scale(1 / magnitude(v), v)
  end
end

# Distance between two vectors of any arity. Named `vdistance` rather than
# `distance` because kikagaku already owns `distance` for 2-D points, and a
# program that imports both should not have one silently win.
def vdistance(a, b)
  magnitude(vsub(a, b))
end

# The same ordering without the square root — for sorting or comparing
# distances, where the root costs precision and buys nothing.
def vdistance_squared(a, b)
  d = vsub(a, b)
  dot(d, d)
end

# The 3-D cross product only. There is no n-dimensional cross product, so this
# takes 3-vectors and nothing else; passing anything shorter reads past the end
# of the list rather than silently answering.
def cross_product(a, b)
  [(nth(1, a) * nth(2, b)) - (nth(2, a) * nth(1, b)),
   (nth(2, a) * nth(0, b)) - (nth(0, a) * nth(2, b)),
   (nth(0, a) * nth(1, b)) - (nth(1, a) * nth(0, b))]
end

# Vector projection of a onto b. The denominator is dot(b, b) — using dot(a, a)
# is the classic transposition, and it still returns a plausible vector, which
# is why the test asserts the residual is orthogonal rather than just a value.
def projection(a, b)
  if is_zero_vector(b)
    b
  else
    scale(dot(a, b) / dot(b, b), b)
  end
end

# Arc cosine by bisection, because this runtime has no `acos` — `sin`, `cos`,
# `tan`, `log` and `exp` are the whole trigonometric surface.
#
# cos is strictly decreasing on [0, pi], so bisection converges without a
# derivative, and it is total: an argument that has drifted just outside
# [-1, 1] by float error lands on 0 or pi instead of producing NaN.
def arccos(x)
  arccos_bisect(x, 0, 3.141592653589793, 60)
end

def arccos_bisect(x, lo, hi, n)
  mid = (lo + hi) / 2
  if n < 1
    mid
  else
    if cos(mid) > x
      arccos_bisect(x, mid, hi, n - 1)
    else
      arccos_bisect(x, lo, mid, n - 1)
    end
  end
end

# Angle in radians. A zero vector has no direction, so there is no angle to
# report; 0 is returned rather than crashing in the division.
def angle_between(a, b)
  if is_zero_vector(a) || is_zero_vector(b)
    0
  else
    arccos(dot(a, b) / (magnitude(a) * magnitude(b)))
  end
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

# --- matrix shape ------------------------------------------------------------

# `rows`/`cols` above are the fast path and both go through `length`/`car`,
# which abort on an empty matrix. `shape` is the total one: a matrix with no
# rows is 0 by 0 rather than an error, so predicates can be written without a
# separate emptiness branch at every call site.
def shape(m)
  if size(m) < 1
    [0, 0]
  else
    [size(m), size(first(m))]
  end
end

def row(m, i)
  nth(i, m)
end

def is_square(m)
  nth(0, shape(m)) == nth(1, shape(m))
end

# --- matrix comparison -------------------------------------------------------

# `==` already compares nested lists structurally, so this is not a re-spelling
# of it: `map` over an empty `range` yields nil, `[] == nil` is false, and two
# 0-by-0 matrices built by different routes therefore compare unequal. Comparing
# by shape and index makes both empties the same empty.
def matrix_equal(a, b)
  if shape(a) == shape(b)
    reduce(fn(acc, i)
      acc && reduce(fn(inner, j) inner && (nth(j, row(a, i)) == nth(j, row(b, i))) end,
                    true, indexes(row(a, i)))
    end, true, indexes(a))
  else
    false
  end
end

# The one to reach for after a divide, a root or a solve — see vector_near.
def matrix_near(a, b)
  if shape(a) == shape(b)
    reduce(fn(acc, i) acc && vector_near(row(a, i), row(b, i)) end, true, indexes(a))
  else
    false
  end
end

def is_symmetric(m)
  is_square(m) && matrix_equal(m, transpose(m))
end

def is_identity(m)
  is_square(m) && matrix_equal(m, identity_matrix(size(m)))
end

# --- matrix construction and arithmetic --------------------------------------

def filled(r, c, v)
  map(fn(i) map(fn(j) v end, range(0, c)) end, range(0, r))
end

def zeros(r, c)
  filled(r, c, 0)
end

def madd(a, b)
  map(fn(i) vadd(row(a, i), row(b, i)) end, indexes(a))
end

def msub(a, b)
  map(fn(i) vsub(row(a, i), row(b, i)) end, indexes(a))
end

def mscale(k, m)
  map(fn(r) scale(k, r) end, m)
end

# Matrix times column vector. Written separately from `matmul` because wrapping
# a vector as a one-column matrix and unwrapping the result is the step callers
# get wrong — `matmul(m, [v])` multiplies by a one-ROW matrix and is a shape
# error, not the answer.
def mvmul(m, v)
  map(fn(r) dot(r, v) end, m)
end

# Outer product: an n-vector and an m-vector give an n-by-m rank-1 matrix.
# The dual of `dot`, which contracts the same two vectors to a scalar.
def outer_product(a, b)
  map(fn(x) map(fn(y) x * y end, b) end, a)
end

def diagonal(m)
  s = shape(m)
  map(fn(i) nth(i, row(m, i)) end, range(0, min(nth(0, s), nth(1, s))))
end

def trace(m)
  sum(diagonal(m))
end

# Entrywise product, which is NOT matrix multiplication. It exists here under
# its own name precisely because `a * b` read aloud means this to most people
# and `matmul` to linear algebra, and a package that offered only one of them
# would let the wrong one be reached for silently.
def hadamard(a, b)
  map(fn(i) map(fn(j) nth(j, row(a, i)) * nth(j, row(b, i)) end, indexes(row(a, i))) end, indexes(a))
end

# A matrix whose transpose is its inverse — rotations and reflections. Tested
# with matrix_near rather than matrix_equal because any real rotation goes
# through sin/cos and lands on floats.
def is_orthogonal(m)
  is_square(m) && matrix_near(matmul(m, transpose(m)), identity_matrix(size(m)))
end

# --- determinants, minors, inverses ------------------------------------------

def replace_col(m, j, v)
  map(fn(i) update_at(row(m, i), j, nth(i, v)) end, indexes(m))
end

# The matrix with row i and column j struck out. `minor` is the DETERMINANT of
# this, which is the usual source of confusion, so both names exist and each
# means exactly what the textbook means.
def submatrix(m, i, j)
  map(fn(r) remove_at(r, j) end, remove_at(m, i))
end

# The checkerboard sign (-1)^(i+j) that turns a minor into a cofactor. Getting
# it backwards flips the sign of every determinant of odd order, which a 2-by-2
# test cannot see — hence the 3-by-3 and 4-by-4 cases in the tests.
def cofactor_sign(i, j)
  if even(i + j)
    1
  else
    0 - 1
  end
end

# Laplace expansion along the first row, so this is general rather than a pair
# of hard-coded 2-by-2 and 3-by-3 formulas. That costs n! multiplications and
# is the wrong algorithm above about 8-by-8 — for those, row-reduce instead.
# The empty determinant is 1, which is what makes the recursion bottom out
# without a separate 2-by-2 base case.
def determinant(m)
  if size(m) < 1
    1
  else
    sum(map(fn(j)
      cofactor_sign(0, j) * nth(j, first(m)) * determinant(submatrix(m, 0, j))
    end, indexes(first(m))))
  end
end

def minor(m, i, j)
  determinant(submatrix(m, i, j))
end

def cofactor(m, i, j)
  cofactor_sign(i, j) * minor(m, i, j)
end

# The transpose of the cofactor matrix — note the transpose, which is the step
# that gets dropped and leaves an "inverse" that is right only for symmetric
# matrices.
def adjugate(m)
  transpose(map(fn(i) map(fn(j) cofactor(m, i, j) end, indexes(row(m, i))) end, indexes(m)))
end

# The empty list means "no inverse", not "the empty matrix": a singular matrix
# has no inverse to return, and returning one anyway — or dividing by the zero
# determinant — is the alternative. Callers test with `size(inverse(m)) < 1`.
def inverse(m)
  d = determinant(m)
  if near(d, 0)
    []
  else
    mscale(1 / d, adjugate(m))
  end
end

# Non-negative powers only. A negative power is spelled
# `matrix_power(inverse(m), n)`, which forces the caller past the singular case
# instead of hiding an empty inverse inside a loop.
def matrix_power(m, n)
  if n < 1
    identity_matrix(size(m))
  else
    matmul(m, matrix_power(m, n - 1))
  end
end

# --- linear systems ----------------------------------------------------------

# Cramer's rule for m * x = b, at any order. Returns [] when the system has no
# unique solution, which is every singular matrix — both the no-solution and
# the infinitely-many-solutions case, and Cramer's rule cannot tell them apart.
def solve_cramer(m, b)
  d = determinant(m)
  if near(d, 0)
    []
  else
    map(fn(j) determinant(replace_col(m, j, b)) / d end, indexes(b))
  end
end

# The 2-by-2 case by name, since it is the one that turns up by hand.
def solve2x2(m, b)
  solve_cramer(m, b)
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

test "normalize gives a unit vector, and leaves the zero vector alone"
  # 3-4-5 again, so the answer is exact and checkable by hand.
  assert vector_near(normalize([3, 4]), [0.6, 0.8]) == true
  assert near(magnitude(normalize([2, 3, 6])), 1) == true
  # The case an `== 0` guard crashes on rather than fails.
  assert normalize([0, 0]) == [0, 0]
  assert is_zero_vector([0, 0, 0]) == true
end

test "vector_near is not vector equality"
  # Measured: `6 / 2` comes back as Int(3), so an exact division does NOT force
  # the float path — but `sqrt` always does. Scaling by a root therefore makes
  # `==` against the integer literal false while the vectors are the same
  # vector, which is the whole reason vector_near exists.
  assert (scale(sqrt(4), [1, 2]) == [2, 4]) == false
  assert vector_near(scale(sqrt(4), [1, 2]), [2, 4]) == true
  assert vector_near([1, 2], [1, 2, 3]) == false
  assert vector_near([], []) == true
end

test "distance between vectors"
  assert near(vdistance([1, 1], [4, 5]), 5) == true
  assert vdistance_squared([1, 1], [4, 5]) == 25
  assert near(vdistance([1, 2, 3], [1, 2, 3]), 0) == true
end

test "cross product is orthogonal and anticommutative"
  assert cross_product([1, 0, 0], [0, 1, 0]) == [0, 0, 1]
  a = [2, 3, 4]
  b = [5, 6, 7]
  c = cross_product(a, b)
  # The property a wrong sign or a transposed term still fails.
  assert dot(a, c) == 0
  assert dot(b, c) == 0
  assert cross_product(b, a) == scale(0 - 1, c)
  # A vector crossed with itself is the zero vector.
  assert cross_product(a, a) == [0, 0, 0]
end

test "projection lands on b and leaves an orthogonal residual"
  a = [3, 4]
  b = [1, 0]
  p = projection(a, b)
  assert vector_near(p, [3, 0]) == true
  # dot(a, b) / dot(a, a) is the classic transposition; it gives [2.4, 0] here,
  # which still looks like a projection but leaves a non-orthogonal residual.
  assert near(dot(vsub(a, p), b), 0) == true
  # Projecting a projection changes nothing.
  assert vector_near(projection(p, b), p) == true
  assert projection([1, 2], [0, 0]) == [0, 0]
end

test "arccos and angle_between"
  assert near(arccos(1), 0) == true
  assert near(arccos(0), 1.5707963267948966) == true
  assert near(arccos(0 - 1), 3.141592653589793) == true
  assert near(angle_between([1, 0], [0, 1]), 1.5707963267948966) == true
  assert near(angle_between([1, 0], [3, 0]), 0) == true
  # The antiparallel case, which a bisection that never reaches its top end
  # gets wrong while every other case still passes.
  assert near(angle_between([1, 0], [0 - 1, 0]), 3.141592653589793) == true
  assert angle_between([0, 0], [1, 0]) == 0
end

test "shape and squareness survive the empty matrix"
  assert shape([[1, 2, 3], [4, 5, 6]]) == [2, 3]
  assert shape([]) == [0, 0]
  assert is_square([[1, 2], [3, 4]]) == true
  assert is_square([[1, 2, 3], [4, 5, 6]]) == false
  # A 0-by-0 matrix is square. `rows`/`cols` cannot answer this at all.
  assert is_square([]) == true
  assert row([[1, 2], [3, 4]], 1) == [3, 4]
end

test "matrix_equal identifies the two empties that == keeps apart"
  # Measured: `cdr` and `range(0, 0)` produce nil, `map` produces []. A matrix
  # whose rows have all been walked off is therefore not `==` to the empty
  # matrix even though both hold no rows.
  e = cdr([[1, 2]])
  assert (e == []) == false
  assert matrix_equal(e, []) == true
  assert matrix_equal([[1, 2]], [[1, 2]]) == true
  assert matrix_equal([[1, 2]], [[1, 3]]) == false
  assert matrix_equal([[1, 2]], [[1, 2], [3, 4]]) == false
end

test "matrix_near tolerates the float path matrix_equal rejects"
  m = mscale(sqrt(4), [[1, 2], [3, 4]])
  assert matrix_equal(m, [[2, 4], [6, 8]]) == false
  assert matrix_near(m, [[2, 4], [6, 8]]) == true
  assert matrix_near([[1]], [[1, 2]]) == false
end

test "symmetry and identity"
  assert is_symmetric([[1, 2], [2, 1]]) == true
  # Symmetric in shape but not in content — the case a check that only compared
  # shapes would pass.
  assert is_symmetric([[1, 2], [3, 1]]) == false
  assert is_symmetric([[1, 2, 3], [4, 5, 6]]) == false
  assert is_identity(identity_matrix(3)) == true
  assert is_identity([[1, 0], [0, 2]]) == false
  # Every entry on the diagonal is right but an off-diagonal is not.
  assert is_identity([[1, 1], [0, 1]]) == false
end

test "matrix addition, subtraction and scaling"
  a = [[1, 2], [3, 4]]
  b = [[5, 6], [7, 8]]
  assert madd(a, b) == [[6, 8], [10, 12]]
  assert msub(madd(a, b), b) == a
  assert mscale(2, a) == [[2, 4], [6, 8]]
  # A matrix plus its negation is the zero matrix, and zeros is the identity of
  # madd — both fail if mscale multiplies rows instead of entries.
  assert madd(a, mscale(0 - 1, a)) == zeros(2, 2)
  assert madd(a, zeros(2, 2)) == a
  assert filled(2, 3, 7) == [[7, 7, 7], [7, 7, 7]]
end

test "matrix times vector agrees with matmul"
  m = [[1, 2], [3, 4]]
  assert mvmul(m, [1, 1]) == [3, 7]
  assert mvmul(identity_matrix(2), [5, 6]) == [5, 6]
  # A one-column matrix through matmul must give the same numbers, which is the
  # check that catches mvmul dotting against columns instead of rows.
  assert transpose(matmul(m, transpose([[1, 1]]))) == [[3, 7]]
end

test "outer product is the transpose of the swapped outer product"
  assert outer_product([1, 2], [3, 4]) == [[3, 4], [6, 8]]
  assert outer_product([1, 2, 3], [4, 5]) == transpose(outer_product([4, 5], [1, 2, 3]))
  # Rank one: the trace of an outer product is the dot product.
  assert trace(outer_product([1, 2, 3], [4, 5, 6])) == dot([1, 2, 3], [4, 5, 6])
end

test "diagonal and trace"
  assert diagonal([[1, 2], [3, 4]]) == [1, 4]
  assert trace([[1, 2], [3, 4]]) == 5
  assert trace(identity_matrix(4)) == 4
  # The main diagonal of a non-square matrix stops at the short side rather
  # than reading past the end of a row.
  assert diagonal([[1, 2, 3], [4, 5, 6]]) == [1, 5]
  # trace(AB) == trace(BA) even when AB and BA are different matrices.
  a = [[1, 2], [3, 4]]
  b = [[0, 1], [1, 0]]
  assert trace(matmul(a, b)) == trace(matmul(b, a))
end

test "submatrix and minor are different things"
  m = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
  assert submatrix(m, 0, 0) == [[5, 6], [8, 9]]
  assert submatrix(m, 1, 1) == [[1, 3], [7, 9]]
  # minor is the determinant of that submatrix: 5*9 - 6*8.
  assert minor(m, 0, 0) == 0 - 3
  # cofactor(0,1) carries the minus sign; minor(0,1) does not.
  assert minor(m, 0, 1) == 0 - 6
  assert cofactor(m, 0, 1) == 6
  assert cofactor(m, 0, 0) == minor(m, 0, 0)
  # Striking a row and column out of a 1-by-1 leaves nothing at all.
  assert size(submatrix([[7]], 0, 0)) == 0
end

test "determinant at 1x1, 2x2, 3x3 and 4x4"
  assert determinant([[7]]) == 7
  assert determinant([[1, 2], [3, 4]]) == 0 - 2
  # A worked 3-by-3 anyone can check: 1(45-48) - 2(36-42) + 3(32-35).
  assert determinant([[1, 2, 3], [4, 5, 6], [7, 8, 10]]) == 0 - 3
  # A singular matrix: the second row is twice the first.
  assert determinant([[1, 2], [2, 4]]) == 0
  assert determinant(identity_matrix(4)) == 1
  # Odd order catches a reversed cofactor sign, which every even order hides.
  assert determinant(mscale(0 - 1, identity_matrix(3))) == 0 - 1
  assert determinant(mscale(0 - 1, identity_matrix(4))) == 1
  # Upper triangular: the determinant is the product of the diagonal, so a sign
  # error anywhere in the expansion shows up here.
  assert determinant([[2, 9, 9, 9], [0, 3, 9, 9], [0, 0, 4, 9], [0, 0, 0, 5]]) == 120
end

test "determinant is multiplicative and transpose-invariant"
  a = [[1, 2, 3], [0, 1, 4], [5, 6, 0]]
  b = [[2, 0, 1], [1, 3, 2], [0, 1, 1]]
  assert determinant(matmul(a, b)) == determinant(a) * determinant(b)
  assert determinant(transpose(a)) == determinant(a)
  # Swapping two rows negates the determinant.
  assert determinant([[0, 1, 4], [1, 2, 3], [5, 6, 0]]) == 0 - determinant(a)
end

test "inverse, and the singular matrix that has none"
  m = [[4, 7], [2, 6]]
  inv = inverse(m)
  assert matrix_near(inv, [[0.6, 0 - 0.7], [0 - 0.2, 0.4]]) == true
  # The property, not the numbers: a matrix times its inverse is the identity.
  assert matrix_near(matmul(m, inv), identity_matrix(2)) == true
  assert matrix_near(matmul(inv, m), identity_matrix(2)) == true
  t = [[1, 2, 3], [0, 1, 4], [5, 6, 0]]
  assert matrix_near(matmul(t, inverse(t)), identity_matrix(3)) == true
  # Dropping the transpose in the adjugate leaves an "inverse" that still works
  # for a symmetric matrix, so the non-symmetric cases above are the real test.
  assert size(inverse([[1, 2], [2, 4]])) == 0
end

test "matrix_power"
  m = [[1, 1], [1, 0]]
  assert matrix_power(m, 0) == identity_matrix(2)
  assert matrix_power(m, 1) == m
  assert matrix_power(m, 3) == matmul(m, matmul(m, m))
  # The Fibonacci matrix: the n-th power holds F(n+1), F(n), F(n), F(n-1).
  assert matrix_power(m, 6) == [[13, 8], [8, 5]]
  # det(m^n) == det(m)^n, which a power that multiplied entrywise fails.
  assert determinant(matrix_power([[1, 2], [3, 4]], 3)) == pow(determinant([[1, 2], [3, 4]]), 3)
end

test "solve by Cramer's rule"
  # 2x + y = 5, x + 3y = 10  =>  x = 1, y = 3.
  s = solve2x2([[2, 1], [1, 3]], [5, 10])
  assert vector_near(s, [1, 3]) == true
  # The residual check: it catches a solve that swapped the two columns, which
  # a symmetric right-hand side would let through.
  assert vector_near(mvmul([[2, 1], [1, 3]], s), [5, 10]) == true
  # A 3x3 system, to prove the general rule and not just the 2-by-2 shortcut.
  a = [[2, 1, 0 - 1], [0 - 3, 0 - 1, 2], [0 - 2, 1, 2]]
  rhs = [8, 0 - 11, 0 - 3]
  x = solve_cramer(a, rhs)
  assert vector_near(x, [2, 3, 0 - 1]) == true
  assert vector_near(mvmul(a, x), rhs) == true
  # Singular: no unique solution, so no answer rather than a division by zero.
  assert size(solve2x2([[1, 2], [2, 4]], [3, 6])) == 0
end

test "hadamard is not matmul"
  a = [[1, 2], [3, 4]]
  b = [[5, 6], [7, 8]]
  assert hadamard(a, b) == [[5, 12], [21, 32]]
  # The same two matrices, and the two products differ — which is the point.
  assert matmul(a, b) == [[19, 22], [43, 50]]
  # The identity of hadamard is the all-ones matrix, not identity_matrix.
  assert hadamard(a, filled(2, 2, 1)) == a
  assert hadamard(a, identity_matrix(2)) == [[1, 0], [0, 4]]
end

test "orthogonal matrices"
  # A rotation by a third of a turn: orthogonal, and not symmetric, so it also
  # catches an is_orthogonal that only compared m against its transpose.
  t = 2.0943951023931953
  r = [[cos(t), 0 - sin(t)], [sin(t), cos(t)]]
  assert is_orthogonal(r) == true
  assert is_symmetric(r) == false
  # A permutation matrix is orthogonal with exact integers.
  assert is_orthogonal([[0, 1], [1, 0]]) == true
  assert is_orthogonal(identity_matrix(3)) == true
  assert is_orthogonal([[1, 2], [3, 4]]) == false
  # An orthogonal matrix preserves length — the reason anyone cares.
  assert near(magnitude(mvmul(r, [3, 4])), 5) == true
end

test "replace_col"
  m = [[1, 2], [3, 4]]
  assert replace_col(m, 0, [9, 9]) == [[9, 2], [9, 4]]
  assert replace_col(m, 1, [9, 9]) == [[1, 9], [3, 9]]
  # Replacing a column with itself is the identity.
  assert replace_col(m, 1, col(m, 1)) == m
end
