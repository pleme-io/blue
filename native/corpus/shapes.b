use("kiban", %i[put_byte put_int])

N = 1_000_000

record point(x, y)
record circle(r)
record rect(w, h)

def area(s) -> Int
  if circle?(s)
    s.r * s.r * 3
  elsif rect?(s)
    s.w * s.h
  else
    s.x - s.y
  end
end

def pick(n: Int)
  if n % 3 == 0
    circle(n % 100)
  elsif n % 3 == 1
    rect(n % 50, n % 7)
  else
    point(n % 11, n % 13)
  end
end

def nudge(p: point, d: Int) -> point
  point(**p, x: p.x + d)
end

def walk(i: Int, acc: Int) -> Int
  if i == 0
    acc
  else
    walk(i - 1, acc + area(pick(i)) + nudge(point(i, i), 1).x)
  end
end

put_int(walk(N, 0))
put_byte(10)
