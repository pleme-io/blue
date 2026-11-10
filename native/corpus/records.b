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
  point(**p, y: p.y + d)
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

P = point(3, 4)

put_int(area(circle(2)))

put_byte(32)
put_int(area(rect(3, 4)))
put_byte(32)
put_int(area(P))
put_byte(32)
put_int(shift(P, 10).y)
put_byte(32)
put_int(mirror(P).x)
put_byte(32)
put_int(area(pick(4)))
put_byte(32)
put_int(area(pick(6)))
put_byte(32)
put_int(area(pick(8)))
put_byte(32)
put_int(pick(8).x)
put_byte(32)

if point(1, 2) == point(1, 2)
  put_int(1)
  put_byte(32)
end

if mirror(P) != P
  put_int(2)
  put_byte(32)
end

put_byte(10)
