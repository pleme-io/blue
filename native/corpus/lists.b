use("kiban", %i[put_byte put_int reclaim])

reclaim(:arena, "build_in_region")
reclaim(:arena, "sum_in_region")
reclaim(:arena, "region_total")
reclaim(:arena, "forked")

def build(n: Int, xs: List) -> List
  if n == 0
    xs
  else
    build(n - 1, append(xs, [n * n % 7]))
  end
end

def sum(xs: List, i: Int, acc: Int) -> Int
  if i < 0
    acc
  else
    sum(xs, i - 1, acc + xs[i])
  end
end

def build_in_region(n: Int, xs: List) -> List
  if n == 0
    xs
  else
    build_in_region(n - 1, append(xs, [n * n % 7]))
  end
end

def sum_in_region(xs: List, i: Int, acc: Int) -> Int
  if i >= count(xs)
    acc
  else
    sum_in_region(xs, i + 1, acc + xs[i])
  end
end

def region_total(n: Int) -> Int
  xs = build_in_region(n, [])
  sum_in_region(append(xs, xs), 0, 0) + first(xs)
end

def forked(n: Int) -> Int
  ys = build_in_region(n, [])
  zs = append(ys, [1])
  ws = append(ys, [2])
  sum_in_region(zs, 0, 0) * 100 + sum_in_region(ws, 0, 0) * 10 + count(ys)
end

def both(xs: List) -> Int
  sum(xs, count(xs) - 1, 0) * 1000 + count(xs)
end

R = build(10, [4, 5])
put_int(sum(R, count(R) - 1, 0))
put_byte(32)
put_int(count(R))
put_byte(32)
put_int(R[3])
put_byte(32)
put_int(region_total(10))
put_byte(32)
put_int(sum_in_region(R, 0, 0))
put_byte(32)
put_int(sum(build_in_region(6, [1]), 6, 0))
put_byte(32)
put_int(forked(4))
put_byte(32)
put_int(both(append(R, [9], build(3, []))))
put_byte(32)
put_byte(10)
