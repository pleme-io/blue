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

def move_by(k: Int) -> Fn(Int) -> Int
  m = k * 2
  (x) -> x + m
end

def moved(x: Int, j: Int) -> Int
  m = j + 1
  apply_to(move_by(x), j) + apply_to((y) -> y * m, x)
end

def moved_up(x: Int, j: Int) -> Int
  m = j + 2
  apply_to(move_by(x), j) + apply_to((y) -> y * m, x)
end

def suffix_with(t: Str) -> Fn(Str) -> Str
  (s) -> "#{t}#{s}#{t}"
end

def apply_str(f: Fn(Str) -> Str, s: Str) -> Str
  f(s)
end

def framed(s: Str, n: Int) -> Str
  m = "#{n}"
  "#{apply_str(suffix_with(s), m)}#{apply_str((u) -> "#{u}#{m}", s)}"
end

def framed_up(s: Str, n: Int) -> Str
  m = "#{n}"
  "#{apply_str(suffix_with(s), m)}#{apply_str((u) -> "#{u}+#{m}", s)}"
end

def toward(q: pt, xs: List(Int)) -> Fn(pt) -> pt
  (p) -> pt(p.x + count(xs), q.y)
end

def apply_pt(f: Fn(pt) -> pt, p: pt) -> pt
  f(p)
end

def drawn(q: pt, n: Int) -> pt
  apply_pt(toward(q, [n, n]), pt(n, n))
end

def drawn_up(q: pt, n: Int) -> pt
  apply_pt(toward(q, [n, n, n]), pt(n, n))
end

def grow_by(k: Int) -> Fn(List(Int)) -> List(Int)
  (ys) -> append(ys, [k])
end

def apply_list(f: Fn(List(Int)) -> List(Int), ys: List(Int)) -> List(Int)
  f(ys)
end

def grown_by(xs: List(Int), k: Int) -> List(Int)
  apply_list(grow_by(k), apply_list((ys) -> append(ys, xs), xs))
end

def grown_by_up(xs: List(Int), k: Int) -> List(Int)
  apply_list(grow_by(k + 1), apply_list((ys) -> append(ys, xs), xs))
end

def keyed(k: Str) -> Fn(Map(Str, Int)) -> Int
  (m) -> get(m, k) + count(m)
end

def apply_map(f: Fn(Map(Str, Int)) -> Int, m: Map(Str, Int)) -> Int
  f(m)
end

def keyed_sum(m: Map(Str, Int), k: Str) -> Int
  apply_map(keyed(k), m) + apply_map((n) -> count(n) * 10, m)
end

def keyed_sum_up(m: Map(Str, Int), k: Str) -> Int
  apply_map(keyed(k), m) + apply_map((n) -> count(n) * 100, m)
end

def shifted_by(d: Int) -> Fn(List(pt)) -> List(pt)
  (ps) -> append(ps, [pt(d, d)])
end

def apply_pts(f: Fn(List(pt)) -> List(pt), ps: List(pt)) -> List(pt)
  f(ps)
end

def fanned(ps: List(pt), d: Int) -> List(pt)
  apply_pts(shifted_by(d), apply_pts((qs) -> append(qs, ps), ps))
end

def fanned_up(ps: List(pt), d: Int) -> List(pt)
  apply_pts(shifted_by(d + 1), apply_pts((qs) -> append(qs, ps), ps))
end

def cubed(x: Int) -> Int
  x * x * x
end

def cubing(k: Int) -> Fn(Int) -> Int
  (x) -> cubed(x) + k
end

def cubed_sum(x: Int, k: Int) -> Int
  apply_to(cubing(k), x) + apply_to((y) -> cubed(y + 1), x)
end

def cubed_sum_up(x: Int, k: Int) -> Int
  apply_to(cubing(k), x) + apply_to((y) -> cubed(y + 2), x)
end

def scaled_all(k: Int) -> Fn(List(Int)) -> List(Int)
  (ys) -> map((y) -> y * k, ys)
end

def rescaled(xs: List(Int), k: Int) -> List(Int)
  apply_list(scaled_all(k), xs)
end

def rescaled_up(xs: List(Int), k: Int) -> List(Int)
  apply_list(scaled_all(k + 1), xs)
end

def curried(k: Int) -> Fn(Int) -> Fn(Int) -> Int
  (x) -> (y) -> x * k + y
end

def apply_curried(g: Fn(Int) -> Fn(Int) -> Int, x: Int) -> Fn(Int) -> Int
  g(x)
end

def uncurried(x: Int, y: Int) -> Int
  apply_to(apply_curried(curried(3), x), y)
end

def uncurried_up(x: Int, y: Int) -> Int
  apply_to(apply_curried(curried(4), x), y)
end

def twice_after(k: Int) -> Fn(Fn(Int) -> Int, Int) -> Int
  (f, x) -> f(f(x + k))
end

def apply_twice(
  h: Fn(Fn(Int) -> Int, Int) -> Int,
  f: Fn(Int) -> Int,
  x: Int
) -> Int
  h(f, x)
end

def twiced(x: Int, m: Int) -> Int
  apply_twice(twice_after(1), (z) -> z * m, x)
end

def twiced_up(x: Int, m: Int) -> Int
  apply_twice(twice_after(2), (z) -> z * m, x)
end

def twice_of(f: Fn(Int) -> Int) -> Fn(Int) -> Int
  (x) -> f(f(x))
end

def doubled_twice(x: Int, k: Int) -> Int
  apply_to(twice_of(twice_of((y) -> y + k)), x)
end

def doubled_twice_up(x: Int, k: Int) -> Int
  apply_to(twice_of((y) -> y + k), x)
end

def tagger(t: Str) -> Fn(Str) -> Str
  wrap = (s) -> "#{t}#{s}#{t}"
  (u) -> wrap(wrap(u))
end

def tagged(s: Str) -> Str
  apply_str(tagger("*"), s)
end

def tagged_up(s: Str) -> Str
  apply_str(tagger("+"), s)
end
