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
