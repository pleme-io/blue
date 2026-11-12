use("kiban", %i[put_byte put_int])

SEED = 7

CASES = 64

def digit(n: Int) -> Int
  if n < 10
    48 + n
  else
    87 + n
  end
end

def nibble(c: Int) -> Int
  if c < 58
    c - 48
  else
    c - 87
  end
end

def encode(bytes: List, i: Int, out: List) -> List
  if i == count(bytes)
    out
  else
    encode(
      bytes,
      i + 1,
      append(append(out, [digit(floor(bytes[i] / 16))]), [digit(bytes[i] % 16)])
    )
  end
end

def decode(text: List, i: Int, out: List) -> List
  if i >= count(text)
    out
  else
    decode(
      text,
      i + 2,
      append(out, [nibble(text[i]) * 16 + nibble(text[i + 1])])
    )
  end
end

def bytes_of(seed: Int, n: Int, i: Int, xs: List) -> List
  if i == n
    xs
  else
    bytes_of(
      seed,
      n,
      i + 1,
      append(xs, [(seed * 31 + i * 17 + i * i * seed) % 256])
    )
  end
end

def same(a: List, b: List, i: Int) -> Int
  if i == count(a)
    1
  elsif a[i] != b[i]
    0
  else
    same(a, b, i + 1)
  end
end

def show(xs: List, i: Int) -> Int
  if i == count(xs)
    put_byte(10)
  else
    put_byte(xs[i])
    show(xs, i + 1)
  end
end

def trial(bytes: List) -> Int
  show(encode(bytes, 0, []), 0)
  same(bytes, decode(encode(bytes, 0, []), 0, []), 0)
end

def run(k: Int, held: Int) -> Int
  if k == CASES
    held
  else
    run(k + 1, held + trial(bytes_of(SEED + k, k % 40, 0, [])))
  end
end

put_int(run(0, 0))
put_byte(10)
