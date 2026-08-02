use("kazu")
use("retsu")
# kikagaku (幾何学) — plane geometry on [x, y] points.
#
# A point is a two-element list, for the same reason a set is a list: no new
# type, so every list function keeps working. Areas come out of the shoelace
# formula, which handles any simple polygon rather than only triangles.

def px(p)
  nth(0, p)
end

def py(p)
  nth(1, p)
end

def distance_squared(a, b)
  dx = px(a) - px(b)
  dy = py(a) - py(b)
  (dx * dx) + (dy * dy)
end

def distance(a, b)
  sqrt(distance_squared(a, b))
end

def manhattan(a, b)
  abs(px(a) - px(b)) + abs(py(a) - py(b))
end

def midpoint(a, b)
  [(px(a) + px(b)) / 2, (py(a) + py(b)) / 2]
end

# Twice the signed area — positive for counter-clockwise winding.
def cross(o, a, b)
  ((px(a) - px(o)) * (py(b) - py(o))) - ((py(a) - py(o)) * (px(b) - px(o)))
end

# Shoelace formula: works for any simple polygon, convex or not.
def polygon_area(pts)
  n = size(pts)
  s = reduce(fn(acc, i) acc + ((px(nth(i, pts)) * py(nth((i + 1) % n, pts))) -
                              (px(nth((i + 1) % n, pts)) * py(nth(i, pts)))) end,
             0, range(0, n))
  abs(s) / 2
end

def perimeter(pts)
  n = size(pts)
  reduce(fn(acc, i) acc + distance(nth(i, pts), nth((i + 1) % n, pts)) end, 0, range(0, n))
end

def triangle_area(a, b, c)
  polygon_area([a, b, c])
end

def collinear(a, b, c)
  cross(a, b, c) == 0
end

def in_circle(p, centre, r)
  distance_squared(p, centre) <= r * r
end

def circle_area(r)
  3.141592653589793 * r * r
end

def pi()
  3.141592653589793
end

# Dot product of the two vectors leaving `o`. The sign alone answers "is the
# corner at o acute, right or obtuse", which is what most callers want and what
# `angle_at` would otherwise cost a bisection to tell them.
#
# Named `dot_at`, not `dot`: gyouretsu exports a two-vector `dot`, and a program
# importing both packages silently keeps whichever it named last — so a plain
# `dot` here would break at the call site on arity, far from the cause.
def dot_at(o, a, b)
  ((px(a) - px(o)) * (px(b) - px(o))) + ((py(a) - py(o)) * (py(b) - py(o)))
end

# 1 counter-clockwise, -1 clockwise, 0 collinear. The sign of `cross` and
# nothing else, so it stays exact on integer input where comparing areas drifts.
def orientation(a, b, c)
  sign(cross(a, b, c))
end

# Shoelace WITHOUT the abs. `polygon_area` throws the sign away; the winding it
# carries is exactly what centroid and is_convex need, so it is kept here.
def signed_area(pts)
  n = size(pts)
  s = reduce(fn(acc, i) acc + ((px(nth(i, pts)) * py(nth((i + 1) % n, pts))) -
                              (px(nth((i + 1) % n, pts)) * py(nth(i, pts)))) end,
             0, range(0, n))
  s / 2
end

# 1 if the vertices run counter-clockwise, -1 clockwise, 0 for zero area.
def winding(pts)
  sign(signed_area(pts))
end

# nil for a vertical line: it has no slope, and dividing would raise rather than
# hand back something the caller can branch on. Verticality is tested with
# `near` because a coordinate that came through a midpoint or a rotation is a
# float, and an exact `==` would miss it and then divide by ~0.
def slope(a, b)
  if near(px(a), px(b))
    nil
  else
    (py(b) - py(a)) / (px(b) - px(a))
  end
end

# The line through a and b as [A, B, C] of Ax + By + C = 0.
#
# Coefficients rather than slope-intercept because a vertical line HAS a
# representation here, and because no division happens, so integer input gives
# an exact integer line.
def line_through(a, b)
  [py(b) - py(a), px(a) - px(b), (px(b) * py(a)) - (px(a) * py(b))]
end

# Ax + By + C at p: zero on the line, and its sign tells which side p is on.
def line_value(line, p)
  (nth(0, line) * px(p)) + (nth(1, line) * py(p)) + nth(2, line)
end

def on_line(line, p)
  line_value(line, p) == 0
end

# Perpendicular distance from p to the INFINITE line ab. Degenerate ab (a == b)
# has no line, so it falls back to the distance to the point rather than
# dividing by zero.
def point_line_distance(p, a, b)
  d = distance(a, b)
  if near(d, 0)
    distance(p, a)
  else
    abs(cross(a, b, p)) / d
  end
end

# The point of segment ab nearest p — clamped to the segment, which is what
# makes it different from dropping a perpendicular onto the infinite line.
def closest_point_on_segment(p, a, b)
  d2 = distance_squared(a, b)
  if near(d2, 0)
    a
  else
    t = clamp(dot_at(a, b, p) / d2, 0, 1)
    [px(a) + (t * (px(b) - px(a))), py(a) + (t * (py(b) - py(a)))]
  end
end

def point_segment_distance(p, a, b)
  distance(p, closest_point_on_segment(p, a, b))
end

# [[min x, min y], [max x, max y]], or nil for no points at all — an empty set
# has no box, and returning one would be a lie a caller cannot detect.
def bounding_box(pts)
  if is_empty(pts)
    nil
  else
    xs = map(fn(p) px(p) end, pts)
    ys = map(fn(p) py(p) end, pts)
    [[min_of(xs), min_of(ys)], [max_of(xs), max_of(ys)]]
  end
end

# Inclusive on the boundary, and the two corners may arrive in either order —
# a hand-written rect is as likely to be [top-right, bottom-left] as not.
def point_in_rect(p, rect)
  a = nth(0, rect)
  b = nth(1, rect)
  inx = px(p) >= min(px(a), px(b)) && px(p) <= max(px(a), px(b))
  iny = py(p) >= min(py(a), py(b)) && py(p) <= max(py(a), py(b))
  inx && iny
end

def circle_circumference(r)
  2 * pi() * r
end

def radians(deg)
  deg * pi() / 180
end

def degrees(rad)
  rad * 180 / pi()
end

# theta in RADIANS throughout, like sin/cos — a package that mixed the two
# units would be a trap no test could make obvious.
def arc_length(r, theta)
  r * theta
end

def sector_area(r, theta)
  r * r * theta / 2
end

def chord_length(r, theta)
  2 * r * sin(theta / 2)
end

# The inverse of cos, by bisection on cos, which is monotone across [0, pi].
#
# This runtime has sin, cos and tan and the inverse of NONE of them, so an angle
# in radians has to be searched for rather than computed. Bisection rather than
# Newton because Newton's step divides by sin, which is zero at both ends of
# exactly the interval an angle lives in. 60 halvings take pi down past the
# precision a float can hold, so the answer is as good as an intrinsic would be.
#
# Spelled `arc_cosine` and not `arccos` on purpose: gyouretsu exports its own
# `arccos`, and a program importing both would silently keep whichever package
# it named last.
def arc_cosine(v)
  if v >= 1
    0
  else
    if v <= 0 - 1
      pi()
    else
      arc_cosine_between(v, 0, pi(), 60)
    end
  end
end

def arc_cosine_between(v, lo, hi, fuel)
  if fuel < 1
    (lo + hi) / 2
  else
    mid = (lo + hi) / 2
    if cos(mid) > v
      arc_cosine_between(v, mid, hi, fuel - 1)
    else
      arc_cosine_between(v, lo, mid, fuel - 1)
    end
  end
end

# The angle at vertex `o` between the arms oa and ob, in radians, always in
# [0, pi]. The cosine is clamped before the arc_cosine because a dot product
# divided by two square roots overshoots 1 by a rounding error on a straight
# arm, and the arc cosine of 1.0000000001 is not a number.
def angle_at(o, a, b)
  da = distance(o, a)
  db = distance(o, b)
  if near(da, 0) || near(db, 0)
    0
  else
    arc_cosine(clamp(dot_at(o, a, b) / (da * db), 0 - 1, 1))
  end
end

# Compared on SQUARED lengths so integer input never goes through sqrt: a 3-4-5
# triangle answers exactly rather than within a tolerance. Three collinear
# points are not a triangle, so they answer false rather than reporting the
# degenerate straight corner as a right angle.
def is_right_triangle(a, b, c)
  if collinear(a, b, c)
    false
  else
    d1 = distance_squared(a, b)
    d2 = distance_squared(b, c)
    d3 = distance_squared(c, a)
    longest = max(d1, max(d2, d3))
    near(d1 + d2 + d3 - longest, longest)
  end
end

# "equilateral" / "isosceles" / "scalene", plus "degenerate" for three points on
# a line. Without that fourth answer the collinear case reports as scalene,
# which reads as a real triangle and is the bug this classification usually has.
# Equilateral is checked first because every equilateral triangle also satisfies
# the isosceles test.
def triangle_kind(a, b, c)
  if collinear(a, b, c)
    "degenerate"
  else
    d1 = distance_squared(a, b)
    d2 = distance_squared(b, c)
    d3 = distance_squared(c, a)
    if near(d1, d2) && near(d2, d3)
      "equilateral"
    else
      if near(d1, d2) || near(d2, d3) || near(d1, d3)
        "isosceles"
      else
        "scalene"
      end
    end
  end
end

# The mean of the vertices. Cheap, total, and NOT the centroid of the shape —
# see `centroid`. Kept because it is the right answer for a point cloud, where
# there is no enclosed area to balance.
def vertex_centroid(pts)
  n = size(pts)
  if n == 0
    nil
  else
    [sum(map(fn(p) px(p) end, pts)) / n, sum(map(fn(p) py(p) end, pts)) / n]
  end
end

def shoelace_term(pts, i)
  p = nth(i, pts)
  q = nth((i + 1) % size(pts), pts)
  (px(p) * py(q)) - (px(q) * py(p))
end

# The AREA centroid — the balance point of the enclosed region.
#
# It is deliberately not the vertex mean: adding a redundant vertex halfway
# along an edge moves the vertex mean and must not move the centroid, and that
# is the difference every naive implementation gets wrong. A zero-area polygon
# has no area to balance, so it falls back to the vertex mean rather than
# dividing by zero.
def centroid(pts)
  a = signed_area(pts)
  if near(a, 0)
    vertex_centroid(pts)
  else
    n = size(pts)
    cx = reduce(fn(acc, i) acc + ((px(nth(i, pts)) + px(nth((i + 1) % n, pts))) * shoelace_term(pts, i)) end, 0, range(0, n))
    cy = reduce(fn(acc, i) acc + ((py(nth(i, pts)) + py(nth((i + 1) % n, pts))) * shoelace_term(pts, i)) end, 0, range(0, n))
    [cx / (6 * a), cy / (6 * a)]
  end
end

# Every turn the same way round. Collinear triples are dropped rather than
# rejected, so a square carrying a redundant midpoint vertex still counts as
# convex; a polygon that is ALL collinear encloses nothing and counts as
# neither convex nor a polygon.
def is_convex(pts)
  n = size(pts)
  if n < 3
    false
  else
    turns = filter(fn(s) s != 0 end,
                   map(fn(i) orientation(nth(i, pts), nth((i + 1) % n, pts), nth((i + 2) % n, pts)) end,
                       range(0, n)))
    if is_empty(turns)
      false
    else
      size(filter(fn(s) s == first(turns) end, turns)) == size(turns)
    end
  end
end

# Does a rightward ray from p cross edge ab? The straddle test comes first, and
# it is what makes the division safe: the two endpoints are on opposite sides of
# p's row, so their y values cannot be equal.
def crosses_ray(p, a, b)
  if (py(a) > py(p)) == (py(b) > py(p))
    false
  else
    px(p) < px(a) + ((py(p) - py(a)) * (px(b) - px(a)) / (py(b) - py(a)))
  end
end

def crossings_from(p, pts, i, n, inside)
  if i >= n
    inside
  else
    if crosses_ray(p, nth(i, pts), nth((i + 1) % n, pts))
      crossings_from(p, pts, i + 1, n, !inside)
    else
      crossings_from(p, pts, i + 1, n, inside)
    end
  end
end

# Ray casting: an odd number of edge crossings means inside.
#
# Works on a non-convex polygon, which is the whole point — the cheaper "same
# side of every edge" test silently reports the notch of an L as inside. A point
# exactly ON an edge is genuinely ambiguous under crossing parity and is not
# classified here; ask `point_on_polygon` if the boundary matters.
def point_in_polygon(p, pts)
  crossings_from(p, pts, 0, size(pts), false)
end

def point_on_polygon(p, pts)
  n = size(pts)
  if n < 2
    false
  else
    hits = filter(fn(i) near(point_segment_distance(p, nth(i, pts), nth((i + 1) % n, pts)), 0) end, range(0, n))
    size(hits) > 0
  end
end

def rotate_point(p, theta)
  [(px(p) * cos(theta)) - (py(p) * sin(theta)), (px(p) * sin(theta)) + (py(p) * cos(theta))]
end

# Rotation about an arbitrary centre, expressed as translate-rotate-translate
# rather than as its own matrix, so there is one rotation formula to be wrong.
def rotate_point_about(p, centre, theta)
  r = rotate_point([px(p) - px(centre), py(p) - py(centre)], theta)
  [px(r) + px(centre), py(r) + py(centre)]
end

# The whole-shape transforms carry `_polygon` rather than the bare `translate`
# and `scale` a reader would reach for first, because seimei and gyouretsu
# already export those names for a grid and a vector. Import collisions here are
# silent last-wins, so the suffix is what keeps two packages from quietly
# swapping meanings under a caller.
def translate_polygon(pts, dx, dy)
  map(fn(p) [px(p) + dx, py(p) + dy] end, pts)
end

# Scaling about the ORIGIN, which moves the shape as well as resizing it. Use
# `scale_polygon_about` to resize in place.
def scale_polygon(pts, k)
  map(fn(p) [px(p) * k, py(p) * k] end, pts)
end

def scale_polygon_about(pts, centre, k)
  map(fn(p) [px(centre) + ((px(p) - px(centre)) * k), py(centre) + ((py(p) - py(centre)) * k)] end, pts)
end

def rotate_polygon(pts, theta)
  map(fn(p) rotate_point(p, theta) end, pts)
end

# The lowest point, ties broken leftmost. It is provably on the hull, which is
# what lets the wrap below start somewhere and be sure of getting back there.
def hull_start(pts)
  reduce(fn(best, p)
    if (py(p) < py(best)) || ((py(p) == py(best)) && (px(p) < px(best)))
      p
    else
      best
    end
  end, first(pts), pts)
end

# The next hull vertex after p: the one that leaves every other point on its
# left.
#
# Seeded with p itself rather than with some other point, which looks wrong and
# is not: orientation(p, p, r) is 0 for every r, so the collinear branch takes
# over and picks the farthest candidate, and p can never win it back because
# nothing is farther from p than p. That removes the "pick any point that is not
# p" special case entirely.
def hull_next(p, pts)
  reduce(fn(q, r)
    o = orientation(p, q, r)
    if o < 0
      r
    else
      if o == 0 && distance_squared(p, r) > distance_squared(p, q)
        r
      else
        q
      end
    end
  end, p, pts)
end

def hull_walk(pts, p, acc, fuel)
  if fuel < 1
    acc
  else
    q = hull_next(p, pts)
    if q == first(acc)
      acc
    else
      hull_walk(pts, q, push(acc, q), fuel - 1)
    end
  end
end

# Convex hull by gift wrapping (Jarvis march), counter-clockwise from the lowest
# point.
#
# Gift wrapping rather than Graham scan because it needs no sort — this package
# would otherwise have to take on junjo for one — and because its inner test is
# the same `orientation` used everywhere else in this file, so there is one
# turn-direction rule here rather than two that can disagree.
#
# Points on a hull EDGE are dropped, not kept: the result is the minimal vertex
# set, so convex_hull(convex_hull(pts)) == convex_hull(pts). The distance
# tie-break in `hull_next` is what buys that, and it is also what stops the walk
# stalling between two collinear candidates.
def convex_hull(pts)
  n = size(pts)
  if n < 3
    pts
  else
    s = hull_start(pts)
    hull_walk(pts, s, [s], n)
  end
end

# Do the two closed segments share at least one point?
#
# The orientation test alone answers the general crossing; the four endpoint
# checks after it are not redundancy but the touching and overlapping cases,
# which the general test deliberately reports as no.
def segments_intersect(p1, p2, p3, p4)
  o1 = orientation(p1, p2, p3)
  o2 = orientation(p1, p2, p4)
  o3 = orientation(p3, p4, p1)
  o4 = orientation(p3, p4, p2)
  crossing = (o1 != o2) && (o3 != o4)
  t1 = near(point_segment_distance(p3, p1, p2), 0)
  t2 = near(point_segment_distance(p4, p1, p2), 0)
  t3 = near(point_segment_distance(p1, p3, p4), 0)
  t4 = near(point_segment_distance(p2, p3, p4), 0)
  crossing || t1 || t2 || t3 || t4
end

# The single point two segments cross at, or nil.
#
# nil covers three different situations — parallel, collinear-and-overlapping,
# and simply missing — because none of them has a single crossing point to
# return. Ask `segments_intersect` if the question is whether they touch at all;
# an overlap touches everywhere and so has no answer here.
def segment_intersection(p1, p2, p3, p4)
  r = [px(p2) - px(p1), py(p2) - py(p1)]
  s = [px(p4) - px(p3), py(p4) - py(p3)]
  den = (px(r) * py(s)) - (py(r) * px(s))
  if near(den, 0)
    nil
  else
    qp = [px(p3) - px(p1), py(p3) - py(p1)]
    t = ((px(qp) * py(s)) - (py(qp) * px(s))) / den
    u = ((px(qp) * py(r)) - (py(qp) * px(r))) / den
    if t < 0 || t > 1 || u < 0 || u > 1
      nil
    else
      [px(p1) + (t * px(r)), py(p1) + (t * py(r))]
    end
  end
end

# The centre of the circle through all three points, or nil when they are
# collinear — three points on a line lie on no circle, and the denominator here
# is zero for exactly that case, so the guard is the geometry rather than a
# defensive check bolted on.
def circumcenter(a, b, c)
  if collinear(a, b, c)
    nil
  else
    d = 2 * ((px(a) * (py(b) - py(c))) + (px(b) * (py(c) - py(a))) + (px(c) * (py(a) - py(b))))
    sa = (px(a) * px(a)) + (py(a) * py(a))
    sb = (px(b) * px(b)) + (py(b) * py(b))
    sc = (px(c) * px(c)) + (py(c) * py(c))
    ux = ((sa * (py(b) - py(c))) + (sb * (py(c) - py(a))) + (sc * (py(a) - py(b)))) / d
    uy = ((sa * (px(c) - px(b))) + (sb * (px(a) - px(c))) + (sc * (px(b) - px(a)))) / d
    [ux, uy]
  end
end

def circumradius(a, b, c)
  o = circumcenter(a, b, c)
  if o == nil
    nil
  else
    distance(o, a)
  end
end

# The member of pts closest to p, or nil for no candidates. Seeded with nil so
# that no point can be mistaken for the sentinel, and compared on SQUARED
# distance because the ordering is the same and the square roots are not free.
def nearest_point(p, pts)
  reduce(fn(best, q)
    if best == nil
      q
    else
      if distance_squared(p, q) < distance_squared(p, best)
        q
      else
        best
      end
    end
  end, nil, pts)
end

# The interior angle at each vertex, in order, in radians.
#
# Meaningful only for a CONVEX polygon: `angle_at` always answers in [0, pi], so
# a reflex corner comes back as its explement and the classic (n - 2) * pi sum
# quietly stops holding. Checking convexity is the caller's job and `is_convex`
# is right there — this function does not do it, because the per-vertex angles
# are still the right answer to a different question on a concave shape.
def interior_angles(pts)
  n = size(pts)
  map(fn(i) angle_at(nth(i, pts), nth((i + n - 1) % n, pts), nth((i + 1) % n, pts)) end, range(0, n))
end

test "distance, including the 3-4-5 triangle"
  assert near(distance([0, 0], [3, 4]), 5) == true
  assert distance_squared([0, 0], [3, 4]) == 25
  assert manhattan([0, 0], [3, 4]) == 7
  assert midpoint([0, 0], [2, 4]) == [1, 2]
end

test "polygon area by shoelace"
  # A unit square, then the same square scaled — area must scale by 4.
  assert polygon_area([[0, 0], [1, 0], [1, 1], [0, 1]]) == 1
  assert polygon_area([[0, 0], [2, 0], [2, 2], [0, 2]]) == 4
  # An L-shaped, non-convex polygon: the case a triangle-fan gets wrong.
  assert polygon_area([[0, 0], [2, 0], [2, 1], [1, 1], [1, 2], [0, 2]]) == 3
end

test "area is independent of winding direction"
  cw = [[0, 0], [0, 1], [1, 1], [1, 0]]
  ccw = [[0, 0], [1, 0], [1, 1], [0, 1]]
  assert polygon_area(cw) == polygon_area(ccw)
end

test "triangles and collinearity"
  assert triangle_area([0, 0], [4, 0], [0, 3]) == 6
  assert collinear([0, 0], [1, 1], [2, 2]) == true
  assert collinear([0, 0], [1, 1], [2, 3]) == false
  # Three collinear points enclose no area.
  assert triangle_area([0, 0], [1, 1], [2, 2]) == 0
end

test "perimeter and circles"
  assert near(perimeter([[0, 0], [3, 0], [3, 4]]), 12) == true
  assert in_circle([1, 1], [0, 0], 2) == true
  assert in_circle([3, 0], [0, 0], 2) == false
  # A point exactly on the boundary counts as inside.
  assert in_circle([2, 0], [0, 0], 2) == true
  assert near(circle_area(1), 3.14159265) == true
end

test "orientation and signed area carry winding, which polygon_area discards"
  ccw = [[0, 0], [1, 0], [1, 1], [0, 1]]
  cw = [[0, 0], [0, 1], [1, 1], [1, 0]]
  assert signed_area(ccw) == 1
  assert signed_area(cw) == 0 - 1
  assert polygon_area(cw) == polygon_area(ccw)
  assert winding(ccw) == 1
  assert winding(cw) == 0 - 1
  # A degenerate "polygon" winds neither way.
  assert winding([[0, 0], [1, 1], [2, 2]]) == 0
  assert orientation([0, 0], [1, 0], [1, 1]) == 1
  assert orientation([0, 0], [1, 1], [1, 0]) == 0 - 1
  assert orientation([0, 0], [1, 1], [2, 2]) == 0
end

test "dot_at sign classifies a corner without any trigonometry"
  # Right angle at the origin between the axes.
  assert dot_at([0, 0], [1, 0], [0, 1]) == 0
  # Acute: both arms on the same side.
  assert dot_at([0, 0], [1, 0], [1, 1]) > 0
  # Obtuse: the arms point away from each other.
  assert dot_at([0, 0], [1, 0], [0 - 1, 1]) < 0
end

test "slope, and the vertical line that has none"
  assert slope([0, 0], [2, 4]) == 2
  assert slope([0, 0], [4, 2]) == 0.5
  assert slope([0, 5], [3, 5]) == 0
  # A vertical line answers nil rather than raising on the division.
  assert slope([2, 0], [2, 9]) == nil
  # Reversing the two points cannot change the slope.
  assert slope([2, 4], [0, 0]) == slope([0, 0], [2, 4])
end

test "line_through represents the vertical line slope cannot"
  vert = line_through([2, 0], [2, 5])
  assert on_line(vert, [2, 99]) == true
  assert on_line(vert, [3, 0]) == false
  diag = line_through([0, 0], [1, 1])
  assert on_line(diag, [7, 7]) == true
  # The sign of line_value separates the two half-planes.
  assert sign(line_value(diag, [0, 1])) == 0 - sign(line_value(diag, [1, 0]))
end

test "distance to a line versus distance to a segment"
  # The perpendicular foot lands ON the segment: both agree.
  assert near(point_line_distance([1, 3], [0, 0], [5, 0]), 3) == true
  assert near(point_segment_distance([1, 3], [0, 0], [5, 0]), 3) == true
  # The foot lands off the end: the line still says 3, the segment says 5.
  assert near(point_line_distance([9, 3], [0, 0], [5, 0]), 3) == true
  assert near(point_segment_distance([9, 3], [0, 0], [5, 0]), 5) == true
  assert closest_point_on_segment([9, 3], [0, 0], [5, 0]) == [5, 0]
  # A degenerate segment is a point, not a division by zero.
  assert near(point_segment_distance([3, 4], [0, 0], [0, 0]), 5) == true
  assert near(point_line_distance([3, 4], [0, 0], [0, 0]), 5) == true
end

test "bounding box and rectangle containment"
  pts = [[1, 5], [0 - 2, 3], [4, 0 - 1]]
  assert bounding_box(pts) == [[0 - 2, 0 - 1], [4, 5]]
  # No points, no box — nil rather than a fabricated one.
  assert bounding_box([]) == nil
  box = bounding_box(pts)
  assert point_in_rect([0, 0], box) == true
  assert point_in_rect([9, 9], box) == false
  # Every generating point is inside its own box, boundary included.
  assert point_in_rect([4, 0 - 1], box) == true
  # Corners given the wrong way round still describe the same rectangle.
  assert point_in_rect([1, 1], [[2, 2], [0, 0]]) == true
end

test "circles, arcs and sectors agree at a full turn"
  assert near(circle_circumference(1), 2 * pi()) == true
  # A full-turn arc is the circumference and a full-turn sector is the area:
  # the case a factor-of-two slip in either formula still gets wrong.
  assert near(arc_length(3, 2 * pi()), circle_circumference(3)) == true
  assert near(sector_area(3, 2 * pi()), circle_area(3)) == true
  # A half turn is half of each.
  assert near(sector_area(2, pi()), circle_area(2) / 2) == true
  assert near(radians(180), pi()) == true
  assert near(degrees(pi()), 180) == true
  # radians and degrees must invert each other, not merely look plausible.
  assert near(degrees(radians(37)), 37) == true
  # The chord across a half turn is the diameter.
  assert near(chord_length(5, pi()), 10) == true
end

test "arc_cosine inverts cos, which this runtime cannot do for us"
  assert near(arc_cosine(1), 0) == true
  assert near(arc_cosine(0), pi() / 2) == true
  assert near(arc_cosine(0 - 1), pi()) == true
  assert near(arc_cosine(0.5), pi() / 3) == true
  # The round trip is the real check: a bisection that searched the wrong
  # direction still lands on plausible-looking endpoints.
  assert near(arc_cosine(cos(1.2345)), 1.2345) == true
  # Out of domain is clamped rather than left to produce a non-number.
  assert arc_cosine(2) == 0
  assert near(arc_cosine(0 - 2), pi()) == true
end

test "angles at a vertex, and the sum that must come out to pi"
  assert near(angle_at([0, 0], [1, 0], [0, 1]), pi() / 2) == true
  assert near(angle_at([0, 0], [1, 0], [1, 1]), pi() / 4) == true
  # A straight arm pair is pi, not a rounding failure past the arc cosine domain.
  assert near(angle_at([0, 0], [1, 0], [0 - 1, 0]), pi()) == true
  # The three interior angles of any triangle sum to pi — the identity a
  # wrong-but-plausible formula (say, missing a normalisation) breaks.
  a = [0, 0]
  b = [4, 0]
  c = [1, 3]
  total = angle_at(a, b, c) + angle_at(b, a, c) + angle_at(c, a, b)
  assert near(total, pi()) == true
end

test "right triangles are decided on squared lengths, exactly"
  assert is_right_triangle([0, 0], [3, 0], [0, 4]) == true
  # The right angle need not be at the first vertex.
  assert is_right_triangle([3, 0], [0, 0], [0, 4]) == true
  assert is_right_triangle([0, 0], [4, 0], [1, 1]) == false
  # Collinear points are not a triangle, though 0 + d == d holds for them.
  assert is_right_triangle([0, 0], [1, 1], [2, 2]) == false
  # 5-12-13, so a float tolerance cannot be what makes 3-4-5 pass.
  assert is_right_triangle([0, 0], [5, 0], [0, 12]) == true
end

test "triangle classification, degenerate case included"
  assert triangle_kind([0, 0], [4, 0], [0, 3]) == "scalene"
  assert triangle_kind([0, 0], [4, 0], [2, 3]) == "isosceles"
  # No equilateral triangle has all-integer coordinates, so this one is exact
  # only in the squared lengths: 1, 1, 1.
  assert triangle_kind([0, 0], [1, 0], [0.5, sqrt(3) / 2]) == "equilateral"
  # Three points on a line are reported as such, not as a scalene triangle.
  assert triangle_kind([0, 0], [1, 1], [2, 2]) == "degenerate"
end

test "the area centroid is not the vertex mean"
  square = [[0, 0], [2, 0], [2, 2], [0, 2]]
  assert near(px(centroid(square)), 1) == true
  assert near(py(centroid(square)), 1) == true
  # Adding a redundant vertex halfway along one edge changes the SHAPE not at
  # all, so it must not move the centroid — while it does move the vertex mean.
  padded = [[0, 0], [1, 0], [2, 0], [2, 2], [0, 2]]
  assert near(px(centroid(padded)), 1) == true
  assert near(py(centroid(padded)), 1) == true
  assert near(py(vertex_centroid(padded)), 0.8) == true
  # A triangle's centroid is the mean of its vertices, so the two agree there.
  tri = [[0, 0], [6, 0], [0, 6]]
  assert near(px(centroid(tri)), 2) == true
  assert near(py(centroid(tri)), 2) == true
  # Winding must not matter.
  assert near(px(centroid(reverse(square))), 1) == true
  # A flat "polygon" has no area to balance and falls back to the vertex mean.
  assert centroid([[0, 0], [2, 0], [4, 0]]) == [2, 0]
  assert vertex_centroid([]) == nil
end

test "convexity, including the collinear vertex that must not break it"
  assert is_convex([[0, 0], [2, 0], [2, 2], [0, 2]]) == true
  # The L shape: exactly one reflex corner is enough to fail.
  assert is_convex([[0, 0], [2, 0], [2, 1], [1, 1], [1, 2], [0, 2]]) == false
  # A redundant vertex mid-edge leaves the shape convex.
  assert is_convex([[0, 0], [1, 0], [2, 0], [2, 2], [0, 2]]) == true
  # Clockwise is just as convex as counter-clockwise.
  assert is_convex([[0, 2], [2, 2], [2, 0], [0, 0]]) == true
  # Degenerate inputs enclose nothing.
  assert is_convex([[0, 0], [1, 1]]) == false
  assert is_convex([[0, 0], [1, 1], [2, 2]]) == false
end

test "point in polygon by ray casting, on a shape convexity tests get wrong"
  square = [[0, 0], [4, 0], [4, 4], [0, 4]]
  assert point_in_polygon([2, 2], square) == true
  assert point_in_polygon([5, 2], square) == false
  # Left of the polygon: the ray still crosses two edges, so parity says out.
  assert point_in_polygon([0 - 1, 2], square) == false
  ell = [[0, 0], [4, 0], [4, 1], [1, 1], [1, 4], [0, 4]]
  assert point_in_polygon([0.5, 0.5], ell) == true
  # The notch of the L is inside the bounding box and outside the polygon —
  # the case a "same side of every edge" test reports as inside.
  assert point_in_polygon([3, 3], ell) == false
  assert point_in_rect([3, 3], bounding_box(ell)) == true
  # A concave polygon whose interior needs three crossings to reach.
  assert point_in_polygon([3.5, 0.5], ell) == true
  assert point_on_polygon([2, 0], square) == true
  assert point_on_polygon([2, 2], square) == false
end

test "transforms preserve what they must"
  square = [[0, 0], [2, 0], [2, 2], [0, 2]]
  assert near(px(rotate_point([1, 0], pi() / 2)), 0) == true
  assert near(py(rotate_point([1, 0], pi() / 2)), 1) == true
  # Four quarter turns is the identity — the check a sign slip in the matrix
  # survives when only one turn is tested.
  back = rotate_point(rotate_point(rotate_point(rotate_point([3, 5], pi() / 2), pi() / 2), pi() / 2), pi() / 2)
  assert near(px(back), 3) == true
  assert near(py(back), 5) == true
  # Rotation about a point leaves that point alone.
  assert near(px(rotate_point_about([7, 7], [7, 7], 1.1)), 7) == true
  # Rotation and translation preserve area and perimeter; scaling squares it.
  assert near(polygon_area(rotate_polygon(square, 0.7)), 4) == true
  assert near(perimeter(rotate_polygon(square, 0.7)), 8) == true
  assert polygon_area(translate_polygon(square, 10, 0 - 5)) == 4
  assert polygon_area(scale_polygon(square, 3)) == 36
  assert polygon_area(scale_polygon_about(square, [1, 1], 3)) == 36
  # scale_polygon moves the shape away from the origin; scale_polygon_about does not.
  assert near(px(centroid(scale_polygon(square, 3))), 3) == true
  assert near(px(centroid(scale_polygon_about(square, [1, 1], 3))), 1) == true
  # Translation moves the centroid by exactly the offset.
  assert centroid(translate_polygon(square, 10, 0 - 5)) == [11, 0 - 4]
end

test "convex hull of a square with an interior point"
  pts = [[0, 0], [2, 0], [2, 2], [0, 2], [1, 1]]
  hull = convex_hull(pts)
  assert size(hull) == 4
  # Counter-clockwise from the lowest-leftmost point.
  assert hull == [[0, 0], [2, 0], [2, 2], [0, 2]]
  assert contains(hull, [1, 1]) == false
  assert polygon_area(hull) == 4
  assert winding(hull) == 1
  assert is_convex(hull) == true
end

test "the hull is idempotent and drops points on an edge"
  # [1, 0] sits ON the bottom edge: a hull that keeps it is not minimal.
  pts = [[0, 0], [1, 0], [2, 0], [2, 2], [0, 2]]
  hull = convex_hull(pts)
  assert size(hull) == 4
  assert contains(hull, [1, 0]) == false
  # Wrapping an already-wrapped hull must change nothing — the identity that
  # fails the moment collinear vertices are kept.
  assert convex_hull(hull) == hull
  # Order of the input cannot matter.
  assert convex_hull(reverse(pts)) == hull
end

test "hull edge cases: too few points, duplicates, a straight line"
  assert convex_hull([]) == []
  assert convex_hull([[3, 4]]) == [[3, 4]]
  assert convex_hull([[0, 0], [1, 1]]) == [[0, 0], [1, 1]]
  # Every point identical: one vertex, and the walk must still terminate.
  assert convex_hull([[2, 2], [2, 2], [2, 2]]) == [[2, 2]]
  # A degenerate cloud on one line collapses to its two extremes.
  assert convex_hull([[0, 0], [1, 1], [2, 2], [3, 3]]) == [[0, 0], [3, 3]]
end

test "the hull contains every input point"
  pts = [[0, 0], [5, 1], [3, 4], [1, 5], [0 - 2, 3], [1, 2], [2, 2]]
  hull = convex_hull(pts)
  assert is_convex(hull) == true
  # Interior points are excluded from the hull but still inside it.
  assert contains(hull, [1, 2]) == false
  assert point_in_polygon([1, 2], hull) == true
  assert point_in_polygon([2, 2], hull) == true
  # And the hull's area is at least the area of the polygon through the points.
  assert polygon_area(hull) >= polygon_area(pts)
  # Every original point is inside or on the hull.
  outside = filter(fn(p) !(point_in_polygon(p, hull) || point_on_polygon(p, hull)) end, pts)
  assert is_empty(outside) == true
end

test "segments: crossing, touching, parallel and merely collinear"
  # A clean X.
  assert segments_intersect([0, 0], [4, 4], [0, 4], [4, 0]) == true
  # Compared component-wise with near: the crossing point comes out of a
  # division, so it is [2.0, 2.0] and never == the integer pair [2, 2].
  x = segment_intersection([0, 0], [4, 4], [0, 4], [4, 0])
  assert near(px(x), 2) == true
  assert near(py(x), 2) == true
  # Same infinite lines, but the segments stop short of each other.
  assert segments_intersect([0, 0], [1, 1], [3, 0], [4, 0 - 1]) == false
  assert segment_intersection([0, 0], [1, 1], [3, 0], [4, 0 - 1]) == nil
  # Touching at an endpoint counts as intersecting; the orientation test alone
  # would say no.
  assert segments_intersect([0, 0], [2, 0], [2, 0], [2, 2]) == true
  # T-junction: an endpoint landing in the middle of the other segment.
  assert segments_intersect([0, 0], [4, 0], [2, 0], [2, 3]) == true
  t = segment_intersection([0, 0], [4, 0], [2, 0], [2, 3])
  assert near(px(t), 2) == true
  assert near(py(t), 0) == true
  # Parallel and distinct: no crossing and no single point.
  assert segments_intersect([0, 0], [4, 0], [0, 1], [4, 1]) == false
  assert segment_intersection([0, 0], [4, 0], [0, 1], [4, 1]) == nil
  # Collinear and overlapping: they DO touch, but at no single point.
  assert segments_intersect([0, 0], [4, 0], [2, 0], [6, 0]) == true
  assert segment_intersection([0, 0], [4, 0], [2, 0], [6, 0]) == nil
end

test "circumcircle: the centre is equidistant from all three vertices"
  a = [0, 0]
  b = [4, 0]
  c = [0, 3]
  o = circumcenter(a, b, c)
  # A right triangle's circumcentre is the midpoint of its hypotenuse, and the
  # radius is half of it — a value a reader can check without the formula.
  assert near(px(o), 2) == true
  assert near(py(o), 1.5) == true
  assert near(circumradius(a, b, c), 2.5) == true
  # The defining property, which a transposed term in the formula still breaks:
  # all three vertices are the same distance away.
  assert near(distance(o, a), distance(o, b)) == true
  assert near(distance(o, b), distance(o, c)) == true
  # And every vertex is on the circle, not merely near it.
  assert in_circle(a, o, circumradius(a, b, c)) == true
  # Three points on a line lie on no circle.
  assert circumcenter([0, 0], [1, 1], [2, 2]) == nil
  assert circumradius([0, 0], [1, 1], [2, 2]) == nil
end

test "nearest point in a set"
  pts = [[10, 0], [0, 3], [4, 4]]
  assert nearest_point([0, 0], pts) == [0, 3]
  assert nearest_point([9, 1], pts) == [10, 0]
  # No candidates, no answer — nil rather than a fabricated point.
  assert nearest_point([0, 0], []) == nil
  assert nearest_point([5, 5], [[5, 5]]) == [5, 5]
end

test "interior angles sum to (n - 2) * pi on a convex polygon"
  square = [[0, 0], [2, 0], [2, 2], [0, 2]]
  angles = interior_angles(square)
  assert size(angles) == 4
  assert near(nth(0, angles), pi() / 2) == true
  assert near(sum(angles), 2 * pi()) == true
  tri = [[0, 0], [4, 0], [1, 3]]
  assert near(sum(interior_angles(tri)), pi()) == true
  # A rectangle's corners are all right angles however long it is.
  assert near(sum(interior_angles([[0, 0], [9, 0], [9, 1], [0, 1]])), 2 * pi()) == true
end
