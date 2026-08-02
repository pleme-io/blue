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

# Three-place versions of the two orders. Written out rather than expressed as
# compose(f, compose(g, h)) so the argument order is visible at the definition
# instead of having to be re-derived from a nesting.
def compose3(f, g, h)
  fn(x) f(g(h(x))) end
end

def pipe3(f, g, h)
  fn(x) h(g(f(x))) end
end

# pipe_all folds a LIST of functions into one, left to right.
#
# The fold seeds with the identity function, which is why the empty list is not
# a special case: pipe_all([]) is `identity`, the unit of composition. A caller
# building a pipeline from data (a config, a list of enabled transforms) can
# therefore hand over an empty list without a guard at the call site.
def pipe_all(fs)
  reduce(fn(acc, f) fn(x) f(acc(x)) end end, identity, fs)
end

# The mathematical order: compose_all([f, g, h]) is f∘g∘h, so h runs first.
# Equivalent to pipe_all(reverse(fs)), and the tests pin that equivalence.
def compose_all(fs)
  reduce(fn(acc, f) fn(x) acc(f(x)) end end, identity, fs)
end

# curry2 turns f(a, b) into f(a)(b), so the first argument can be fixed and the
# result reused. That partial application is the point: it is how a binary
# operator becomes something `map` or `pipe_all` will accept.
def curry2(f)
  fn(a) fn(b) f(a, b) end end
end

def uncurry2(g)
  fn(a, b) g(a)(b) end
end

# f(f(x)). The general form is iterate_n; this exists because doubling up is
# common enough that spelling the 2 is noise, and because f∘f is the shape the
# involution tests in this distribution assert (rot13, transpose, reverse).
def apply_twice(f, x)
  f(f(x))
end

# The combinator form of iterate_n: n is fixed, the value is not.
#
# iterate_n takes the value, so it cannot be dropped into pipe_all. This can —
# pipe_all([iterated(dbl, 3), inc]) is a pipeline stage that repeats.
def iterated(f, n)
  fn(x) iterate_n(f, x, n) end
end

# Haskell's `on`: compare/combine two values THROUGH a key function.
#
# op comes first to match `on op key` and to keep the higher-order argument
# leftmost, as map/filter/reduce do here. The classic use is a comparator that
# orders by a derived value without the caller ever naming that value.
def on(op, key)
  fn(a, b) op(key(a), key(b)) end
end

# juxt(fs) applies EVERY function to ONE value and collects the results.
#
# The dual of pipe_all: pipe_all threads one value through many functions in
# series, juxt fans it out in parallel. Returns a function rather than taking
# the value so it can be handed straight to `map` — building a row per element
# from a list of column functions is the reason it exists.
def juxt(fs)
  fn(x) map(fn(f) f(x) end, fs) end
end

# The two-function case, named, because a pair is what most callers want and
# [f, g] spelled as a list is one bracket of noise per use site.
def both_results(f, g)
  fn(x) [f(x), g(x)] end
end

# fork is both_results with the pair already combined: op(f(x), g(x)).
#
# It exists because blue has no destructuring, so a caller handed [f(x), g(x)]
# has to go back through nth to use it. Anything of the shape "compute two
# things from one input and put them together" — a ratio, a difference, a span
# — is a fork, and written this way the intermediate pair is never built.
def fork(op, f, g)
  fn(x) op(f(x), g(x)) end
end

# tap runs f for its effect and hands the ORIGINAL value on.
#
# The point is that it is spliceable: pipe_all([a, tap(log), b]) leaves the
# pipeline's value untouched, whereas dropping `log` in directly would replace
# it with log's return. blue has no observable side effects today, so tap earns
# its place as the shape that keeps a stage from contaminating the value — and
# the test asserts exactly that discarding, since that is the whole contract.
def tap(f)
  fn(x)
    f(x)
    x
  end
end

# Apply f only where p holds; elsewhere pass the value through unchanged.
#
# This is what makes a transform safe to iterate: apply_when's result is the
# identity on everything outside p, so it reaches a fixed point exactly when p
# stops holding. until_stable below is its natural partner.
def apply_when(p, f)
  fn(x)
    if p(x)
      f(x)
    else
      x
    end
  end
end

# ---- fixpoints, memo-free -------------------------------------------------
#
# No cache anywhere: nothing is keyed on a value's equality and nothing grows.
# The price is that the only guard against a function that never settles is the
# step bound, so every one of these takes it explicitly rather than hiding a
# default. `f(x) == x` is the whole stopping rule, which also means these work
# on any value `==` compares — numbers, strings, lists.

def is_fixed_point(f, x)
  f(x) == x
end

# Apply f until the value stops changing, or until max_steps applications.
#
# THE TRAP: on exhausting the bound this returns the last value it saw, which
# is indistinguishable from a settled one. When the difference matters, ask
# `converges` — that is the only reason it is a separate function.
def until_stable(f, x, max_steps)
  if max_steps < 1
    x
  else
    nx = f(x)
    if nx == x
      x
    else
      until_stable(f, nx, max_steps - 1)
    end
  end
end

# Did it actually settle within the bound? The question until_stable's return
# value cannot answer.
#
# Nested if rather than elsif on purpose: `elsif` parses in this runtime and
# then dies at evaluation with `unbound symbol: elsif`, so no package in this
# distribution uses it.
def converges(f, x, max_steps)
  if is_fixed_point(f, x)
    true
  else
    if max_steps < 1
      false
    else
      converges(f, f(x), max_steps - 1)
    end
  end
end

# How many applications until stable; max_steps if it never got there.
# Already-stable is 0, not 1 — no application was needed.
def stable_steps(f, x, max_steps)
  if is_fixed_point(f, x)
    0
  else
    if max_steps < 1
      0
    else
      1 + stable_steps(f, f(x), max_steps - 1)
    end
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

test "compose3 and pipe3 are each other read backwards"
  inc = fn(n) n + 1 end
  dbl = fn(n) n * 2 end
  neg = fn(n) 0 - n end
  # inc LAST: neg(1) = -1, dbl = -2, inc = -1
  assert compose3(inc, dbl, neg)(1) == 0 - 1
  # inc FIRST: 1+1 = 2, dbl = 4, neg = -4
  assert pipe3(inc, dbl, neg)(1) == 0 - 4
  # the two orders agree once the arguments are reversed - which is the whole
  # claim, and it only holds because the operations do NOT commute
  assert compose3(inc, dbl, neg)(3) == pipe3(neg, dbl, inc)(3)
end

test "pipe_all folds a list of functions, empty list included"
  inc = fn(n) n + 1 end
  dbl = fn(n) n * 2 end
  # the empty pipeline is identity, not an error and not zero
  assert pipe_all([])(9) == 9
  assert pipe_all([inc])(9) == 10
  # agrees with the hand-written two-place version
  assert pipe_all([inc, dbl])(5) == pipe(inc, dbl)(5)
  assert pipe_all([inc, dbl])(5) == 12
  # three stages, order-sensitive: an implementation that folded the other way
  # would give 11 here and still pass any test built from commuting operations
  assert pipe_all([inc, dbl, inc])(5) == 13
end

test "compose_all is pipe_all reversed"
  inc = fn(n) n + 1 end
  dbl = fn(n) n * 2 end
  sq = fn(n) n * n end
  assert compose_all([])(9) == 9
  assert compose_all([inc, dbl])(5) == compose(inc, dbl)(5)
  assert compose_all([inc, dbl])(5) == 11
  fs = [inc, dbl, sq]
  assert compose_all(fs)(3) == pipe_all(reverse(fs))(3)
  # 3^2 = 9, doubled = 18, +1 = 19
  assert compose_all(fs)(3) == 19
end

test "curry2 partial application is reusable, uncurry2 undoes it"
  sub = fn(a, b) a - b end
  # subtraction does not commute, so an argument swap cannot hide here
  assert curry2(sub)(10)(3) == 7
  from_ten = curry2(sub)(10)
  # the SAME partial applied twice - proves it is a value, not a one-shot
  assert from_ten(1) == 9
  assert from_ten(2) == 8
  assert uncurry2(curry2(sub))(10, 3) == 7
  # curried, a binary operator becomes something map will take
  assert map(curry2(fn(a, b) a * b end)(3), [1, 2, 3]) == [3, 6, 9]
end

test "apply_twice and iterated agree with iterate_n"
  dbl = fn(n) n * 2 end
  assert apply_twice(dbl, 3) == 12
  assert apply_twice(dbl, 3) == iterate_n(dbl, 3, 2)
  assert iterated(dbl, 2)(3) == 12
  assert iterated(dbl, 0)(3) == 3
  # applying an involution twice is the identity - the reason this shape matters
  assert apply_twice(reverse, [1, 2, 3]) == [1, 2, 3]
  # iterated composes where iterate_n cannot: it is unary
  assert pipe_all([iterated(dbl, 3), fn(n) n + 1 end])(1) == 9
end

test "juxt fans one value across many functions"
  inc = fn(n) n + 1 end
  dbl = fn(n) n * 2 end
  sq = fn(n) n * n end
  # no functions means no results - an empty list, not nil and not the input
  assert juxt([])(5) == []
  assert juxt([inc])(5) == [6]
  assert juxt([inc, dbl, sq])(5) == [6, 10, 25]
  # the reason it returns a function: it is a `map` argument
  assert map(juxt([inc, dbl]), [1, 2]) == [[2, 2], [3, 4]]
end

test "both_results is the two-function juxt"
  neg = fn(n) 0 - n end
  sq = fn(n) n * n end
  assert both_results(neg, sq)(3) == [0 - 3, 9]
  assert both_results(neg, sq)(3) == juxt([neg, sq])(3)
  # order is preserved, so the two entries are not interchangeable
  assert both_results(sq, neg)(3) == [9, 0 - 3]
end

test "fork combines what both_results would have paired"
  sub = fn(a, b) a - b end
  sq = fn(n) n * n end
  dbl = fn(n) n * 2 end
  # 3^2 - 3*2 = 3
  assert fork(sub, sq, dbl)(3) == 3
  # the identity that ties it to both_results: pairing IS an operator
  assert fork(fn(a, b) [a, b] end, sq, dbl)(3) == both_results(sq, dbl)(3)
  # both branches see the SAME input - not the first branch's output
  assert fork(sub, identity, identity)(9) == 0
  # spread of a list, without naming the list twice
  span = fork(sub, fn(xs) nth(0, xs) end, fn(xs) nth(1, xs) end)
  assert span([10, 4]) == 6
end

test "tap discards its function's result and keeps the value"
  inc = fn(n) n + 1 end
  dbl = fn(n) n * 2 end
  # f returns something entirely different; the value passes through anyway
  assert tap(fn(n) n * 1000 end)(7) == 7
  assert tap(constantly("ignored"))(7) == 7
  # spliced mid-pipeline: 1 -> 2 -> (tap doubles, discarded) -> 3.
  # A tap that leaked f's result would give 5 here.
  assert pipe_all([inc, tap(dbl), inc])(1) == 3
end

test "apply_when transforms only where the predicate holds"
  halve_evens = apply_when(fn(n) modulo(n, 2) == 0 end, fn(n) floor(n / 2) end)
  assert halve_evens(8) == 4
  assert halve_evens(7) == 7
  # outside the predicate it IS the identity, which is what makes it iterable
  assert map(halve_evens, [1, 2, 3, 4]) == [1, 1, 3, 2]
end

test "until_stable reaches a fixed point and reports the last value otherwise"
  countdown = fn(n) max(0, n - 1) end
  # 5 -> 4 -> 3 -> 2 -> 1 -> 0, and 0 is fixed
  assert until_stable(countdown, 5, 100) == 0
  # already stable: returned untouched, and identity is fixed everywhere
  assert until_stable(identity, 7, 10) == 7
  # THE distinguishing case: the bound ran out, so this is NOT a fixed point.
  # An implementation that only ever returned the true fixed point fails here.
  assert until_stable(countdown, 5, 2) == 3
  # the fixpoint law - re-running from the answer changes nothing
  once = until_stable(countdown, 9, 100)
  assert until_stable(countdown, once, 100) == once
  # works on any value == compares, not just numbers
  assert until_stable(fn(xs) take(2, xs) end, [1, 2, 3, 4], 10) == [1, 2]
end

test "converges answers what until_stable cannot"
  countdown = fn(n) max(0, n - 1) end
  inc = fn(n) n + 1 end
  assert converges(countdown, 5, 100) == true
  # exactly 5 steps are needed, so 5 is enough and 4 is not - an
  # always-true implementation passes the first and fails the second
  assert converges(countdown, 5, 5) == true
  assert converges(countdown, 5, 4) == false
  # nothing settles a strictly increasing function, at any bound
  assert converges(inc, 0, 50) == false
  assert is_fixed_point(countdown, 0) == true
  assert is_fixed_point(inc, 0) == false
end

test "stable_steps counts applications, zero when already stable"
  countdown = fn(n) max(0, n - 1) end
  inc = fn(n) n + 1 end
  assert stable_steps(countdown, 5, 100) == 5
  # already a fixed point: no application was needed
  assert stable_steps(identity, 7, 10) == 0
  assert stable_steps(countdown, 0, 10) == 0
  # never settles, so the answer is the bound itself
  assert stable_steps(inc, 0, 4) == 4
  # the count and the convergence verdict agree at the boundary
  assert converges(countdown, 5, stable_steps(countdown, 5, 100)) == true
end

test "the combinators compose with each other"
  inc = fn(n) n + 1 end
  dbl = fn(n) n * 2 end
  # iterate a conditional transform until the condition stops holding:
  # 10 -> 7 -> 4 -> 1, and 1 fails the guard so 1 is the fixed point
  drain = apply_when(fn(n) n > 2 end, fn(n) n - 3 end)
  assert until_stable(drain, 10, 100) == 1
  assert stable_steps(drain, 10, 100) == 3
  # pipe_all a pipeline that ends in a fan-out
  assert pipe_all([inc, dbl, juxt([inc, dbl])])(1) == [5, 8]
  # on + flip + curry2: subtract magnitudes, arguments the other way round
  by_abs = on(fn(a, b) a - b end, abs)
  assert flip(by_abs)(0 - 2, 5) == 3
  assert curry2(by_abs)(0 - 7)(3) == 4
  # a pipeline assembled from data, including the empty one
  stages = [inc, dbl, inc]
  assert pipe_all(stages)(0) == 3
  assert compose_all(stages)(0) == 3
  assert pipe_all([])(compose_all([])(4)) == 4
end

test "on applies the key function before the operator"
  sub = fn(a, b) a - b end
  sq = fn(n) n * n end
  # 3^2 - 2^2 = 5, NOT (3-2)^2 = 1
  assert on(sub, sq)(3, 2) == 5
  # by-magnitude comparison: the key is what is compared, not the input
  by_size = on(fn(a, b) max(a, b) end, abs)
  assert by_size(0 - 7, 3) == 7
  # key = identity degenerates to the bare operator
  assert on(sub, identity)(10, 4) == sub(10, 4)
end
