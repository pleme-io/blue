use("kazu")
use("retsu")
# kika (幾何) — plane geometry on [x, y] points.
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
