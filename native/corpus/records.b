use("kiban", %i[put_byte put_int])

record point(x, y)
record circle(r)
record rect(w, h)

def area(s) -> Int
  if circle?(s)
    s.r * s.r * 3
  elsif rect?(s)
    s.w * s.h
  else
    0
  end
end

def shift(p: point, d: Int) -> point
  point(**p, x: p.x + d)
end

def mirror(p: point) -> point
  point({x: p.y, y: p.x})
end

def pick(n: Int)
  if n % 3 == 0
    circle(n)
  elsif n % 3 == 1
    rect(n, n + 1)
  else
    point(n, -n)
  end
end

def show(n: Int) -> Int
  put_int(n)
  put_byte(32)
end

P = point(3, 4)

show(area(circle(2)))
show(area(rect(3, 4)))
show(area(P))
show(shift(P, 10).x)
show(mirror(P).x)
show(area(pick(4)))
show(area(pick(6)))
show(area(pick(8)))
show(pick(8).x)

if point(1, 2) == point(1, 2)
  show(1)
end

if mirror(P) != P
  show(2)
end

put_byte(10)
