record pt(x: Int, y: Int)

def square(x: Int) -> Int
  x * x
end

def sum_squares(n: Int, acc: Int) -> Int
  if n == 0
    acc
  else
    sum_squares(n - 1, acc + square(n))
  end
end

def fib(n: Int) -> Int
  if n < 2
    n
  else
    fib(n - 1) + fib(n - 2)
  end
end

def small(n: Int) -> Bool
  n < 3
end

def big(n: Int) -> Bool
  n > 3
end

def pick(b: Bool, x: Int) -> Int
  if b
    x
  else
    0
  end
end

def area(r: Float) -> Float
  3.5 * r * r
end

def half(x: Float) -> Float
  x / 2
end

def wide(x: Float, n: Int) -> Bool
  x > n
end

def shout(s: Str, n: Int) -> Str
  "#{s}!#{n}"
end

def width(s: Str) -> Int
  length(s)
end

def twice(s: Str) -> Str
  concat(s, s)
end

def bang(s: Str) -> Str
  "#{s}!"
end

def grown(xs: List(Int), n: Int) -> List(Int)
  append(xs, [n])
end

def doubled(xs: List(Int), n: Int) -> List(Int)
  append(xs, [n, n])
end

def tally(xs: List(Int)) -> Int
  count(xs)
end

def shifted(p: pt, d: Int) -> pt
  pt(**p, x: p.x + d)
end

def lifted(p: pt, d: Int) -> pt
  pt(**p, y: p.y + d)
end

def spread(p: pt) -> Int
  p.x - p.y
end

def hits(xs: List(Int), n: Int, acc: Int) -> Int
  if n == 0
    acc
  else
    hits(
      xs,
      n - 1,
      if member?(n % 7, xs)
        acc + 1
      else
        acc
      end
    )
  end
end

def drain(xs: List(Int), acc: Int) -> Int
  if count(xs) == 0
    acc
  else
    drain(rest(xs), acc + first(xs))
  end
end

record gauge(on: Bool, w: Float, n: Int)

def weighed(g: gauge, d: Float) -> gauge
  gauge(**g, w: g.w + d)
end

def switched(g: gauge) -> gauge
  gauge(**g, on: not g.on)
end

def lightened(g: gauge, d: Float) -> gauge
  gauge(**g, w: g.w - d)
end
