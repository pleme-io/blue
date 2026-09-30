use("retsu", [:first, :is_empty])

# kyohi (拒否) — refusals, as data.
#
# A refusal is `[kind, why]`: a keyword naming what was refused and the reason,
# usually text. A check that can fail several ways at once returns EVERY
# refusal it finds, as a list, instead of throwing on the first, so a caller
# sees the whole picture and can test for one kind. `refuse` turns that list
# into one thrown error when the caller wants to stop.
#
# kueri, kinji and nisshi each wrote this vocabulary, and kueri's `refuse` and
# kinji's were the same definition. It lives here once; their names are
# bridges to these (`legacy_names`) until each package's 0.2.0.

# A refusal of `kind`, because `why`.
def refusal(kind, why)
  [kind, why]
end

# What was refused: the refusal's keyword.
def kind(r)
  first(r)
end

# Why it was refused.
def why(r)
  nth(1, r)
end

# The kind of each refusal, in order.
def kinds(refusals)
  map(fn(r) kind(r) end, refusals)
end

# nil when there is nothing to refuse; otherwise throws one error whose kind
# is the first refusal's and whose message joins every refusal's why.
def refuse(refusals)
  if is_empty(refusals) == false
    throw(
      error(kind(first(refusals)), join(map(fn(r) why(r) end, refusals), "; "))
    )
  end
  nil
end

test "a refusal is its kind and its why"
  r = refusal(:too_big, "3 > 2")
  assert r == [:too_big, "3 > 2"]
  assert kind(r) == :too_big
  assert why(r) == "3 > 2"
  assert kinds([r, refusal(:bad, "no")]) == [:too_big, :bad]
  assert kinds([]) == []
end

test "refuse passes nothing and throws everything, kind first"
  assert refuse([]) == nil
  caught = try(refuse([refusal(:a, "one"), refusal(:b, "two")]), catch(e(), e))
  assert error?(caught) == true
end
