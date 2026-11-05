@moduledoc """
chizu (地図) holds points and the legs between them: the example bidama of records.

    span(leg(point(0, 0), point(3, 4))) #=> 7
"""

@doc """
point is a place on a grid, in whole steps.

    point(3, 4).y #=> 4
"""
record point(x: Int, y: Int)

@doc """
leg is one straight walk between two points.

    point?(leg(point(0, 0), point(1, 1)).stop) #=> true
"""
record leg(start: point, stop: point)

@doc """
span is the steps a leg takes, along the grid.

    span(leg(point(1, 1), point(1, 3))) #=> 2
"""
def span(l)
  abs(l.stop.x - l.start.x) + abs(l.stop.y - l.start.y)
end

test "a leg of no distance spans nothing"
  p = point(5, 5)
  assert span(leg(p, p)) == 0
end

test "a leg holds points and nothing else"
  make = leg
  assert (make(1, 2) rescue :refused) == :refused
end
