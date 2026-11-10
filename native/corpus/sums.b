use("kiban", %i[put_byte put_int reclaim])

reclaim(:arena, "fill_region")
reclaim(:arena, "add_region")
reclaim(:arena, "in_region")

N = 100_000

def fill(n: Int, xs: List) -> List
  if n == 0
    xs
  else
    fill(n - 1, append(xs, [n % 1000]))
  end
end

def add(xs: List, i: Int, acc: Int) -> Int
  if i == count(xs)
    acc
  else
    add(xs, i + 1, acc + xs[i])
  end
end

def fill_region(n: Int, xs: List) -> List
  if n == 0
    xs
  else
    fill_region(n - 1, append(xs, [n % 1000]))
  end
end

def add_region(xs: List, i: Int, acc: Int) -> Int
  if i == -1
    acc
  else
    add_region(xs, i - 1, acc + xs[i])
  end
end

def in_region(n: Int) -> Int
  add_region(fill_region(n, []), n - 1, 0)
end

put_int(add(fill(N, []), 0, 0))
put_byte(32)
put_int(in_region(N))
put_byte(10)
