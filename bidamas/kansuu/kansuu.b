# kansuu (関数) — functions about functions.
#
# The smallest bidama with the widest reach: every other package here composes
# through these. Clojure's argument that one abstraction carries a library
# applies to combinators before it applies to sequences — `pipe` is what lets a
# caller build a transformation without naming an intermediate.

def identity(x)
  x
end

# The constant function. Useful wherever a callback is required and ignored.
def constantly(x)
  fn(ignored) x end
end

# compose(f, g) applies g FIRST, then f — the mathematical order.
#
# Named for the maths rather than for reading order on purpose: `compose` is
# the word people reach for expecting f∘g, and quietly reversing it would make
# every use site subtly wrong. `pipe` below is the left-to-right one.
def compose(f, g)
  fn(x) f(g(x)) end
end

# pipe(f, g) applies f FIRST — reading order.
def pipe(f, g)
  fn(x) g(f(x)) end
end

# flip a two-argument function's arguments.
def flip(f)
  fn(a, b) f(b, a) end
end

# Apply f to x, n times.
def iterate_n(f, x, n)
  if n < 1
    x
  else
    iterate_n(f, f(x), n - 1)
  end
end

test "identity and constantly"
  assert identity(7) == 7
  assert constantly(3)(99) == 3
end

test "compose applies right to left, pipe left to right"
  inc = fn(n) n + 1 end
  dbl = fn(n) n * 2 end
  # compose: double THEN increment -> 2*5+1
  assert compose(inc, dbl)(5) == 11
  # pipe: increment THEN double -> (5+1)*2
  assert pipe(inc, dbl)(5) == 12
end

test "flip swaps arguments"
  assert flip(fn(a, b) a - b end)(3, 10) == 7
end

test "iterate_n applies repeatedly"
  assert iterate_n(fn(n) n * 2 end, 1, 10) == 1024
  assert iterate_n(fn(n) n + 1 end, 0, 0) == 0
end
