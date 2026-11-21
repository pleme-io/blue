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

record tag(label: Str, n: Int)

def bumped(t: tag, d: Int) -> tag
  tag(**t, n: t.n + d)
end

def shrunk(t: tag, d: Int) -> tag
  tag(**t, n: t.n - d)
end

def relabeled(t: tag, s: Str) -> tag
  tag(**t, label: "#{t.label}#{s}")
end

record bag(xs: List(Int), n: Int)

def pushed(b: bag, x: Int) -> bag
  bag(**b, xs: append(b.xs, [x]))
end

def pushed_twice(b: bag, x: Int) -> bag
  bag(**b, xs: append(b.xs, [x, x]))
end

def tallied(b: bag) -> bag
  bag(**b, n: count(b.xs))
end

def put_word(m: Map(Str, Int), k: Str, v: Int) -> Map(Str, Int)
  assoc(m, k, v)
end

def put_double(m: Map(Str, Int), k: Str, v: Int) -> Map(Str, Int)
  assoc(m, k, v * 2)
end

def looked_up(m: Map(Str, Int), k: Str) -> Int
  get(m, k) + count(m)
end

def placed(ps: List(pt), x: Int) -> List(pt)
  append(ps, [pt(x, -x)])
end

def placed_twice(ps: List(pt), x: Int) -> List(pt)
  append(ps, [pt(x, -x), pt(x, -x)])
end

def swept(ps: List(pt), i: Int, acc: pt) -> pt
  if i == count(ps)
    acc
  else
    swept(ps, i + 1, pt(acc.x + ps[i].x, acc.y * ps[i].y))
  end
end

def joined(ts: List(tag), us: List(tag)) -> List(tag)
  append(append(ts, us), [tag("end", count(ts))])
end

def headed(ts: List(tag)) -> tag
  tag(**first(ts), n: count(ts))
end

def scaled(xs: List(Int), k: Int) -> List(Int)
  map((x) -> x * k, xs)
end

def scaled_up(xs: List(Int), k: Int) -> List(Int)
  map((x) -> x * k + 1, xs)
end

def kept(xs: List(Int), k: Int) -> List(Int)
  filter((x) -> x > k, xs)
end

def crossed(xs: List(Int), ys: List(Int)) -> Int
  reduce((a, x) -> a + reduce((b, y) -> b + x * y, 0, ys), 0, xs)
end

def nudged(ps: List(pt), d: Int) -> List(pt)
  map((q) -> pt(q.x + d, q.y), ps)
end

def held(xs: List(Int), k: Int) -> List(Int)
  f = (x) -> x * k
  map(f, xs)
end

def held_up(xs: List(Int), k: Int) -> List(Int)
  f = (x) -> x * k + 1
  map(f, xs)
end

def picked(xs: List(Int), k: Int) -> List(Int)
  over = (x) -> x > k
  filter(over, xs)
end

def applied(a: Int, k: Int) -> Int
  f = (x) -> x + k
  f(a) + f(a * 2)
end

def add_to(k: Int) -> Fn(Int) -> Int
  (x) -> x + k
end

def apply_to(f: Fn(Int) -> Int, x: Int) -> Int
  f(x)
end

def offset(x: Int, j: Int) -> Int
  apply_to(add_to(2), x) + apply_to((y) -> y * j, x)
end

def offset_up(x: Int, j: Int) -> Int
  apply_to(add_to(3), x) + apply_to((y) -> y * j, x)
end
