use("retsu")
use("kansuu")
# ronri (論理) — predicates, and the algebra over them.
#
# A predicate is a function to a boolean, and predicates compose the way
# booleans do. Building `all_of` from `every` rather than writing three
# recursive walks is the point: the combinators are the library.

def every(p, xs)
  if is_empty(xs)
    true
  else
    if p(first(xs))
      every(p, rest(xs))
    else
      false
    end
  end
end

def any(p, xs)
  if is_empty(xs)
    false
  else
    if p(first(xs))
      true
    else
      any(p, rest(xs))
    end
  end
end

def none(p, xs)
  !any(p, xs)
end

def count_if(p, xs)
  size(filter(p, xs))
end

def complement(p)
  fn(x) !p(x) end
end

def both(p, q)
  fn(x) p(x) && q(x) end
end

def either(p, q)
  fn(x) p(x) || q(x) end
end

test "the vacuous cases, which is where predicate libraries go wrong"
  # Everything holds of nothing; nothing holds of nothing.
  assert every(fn(x) x > 0 end, []) == true
  assert any(fn(x) x > 0 end, []) == false
  assert none(fn(x) x > 0 end, []) == true
end

test "every, any, none"
  pos = fn(x) x > 0 end
  assert every(pos, [1, 2, 3]) == true
  assert every(pos, [1, 0, 3]) == false
  assert any(pos, [0 - 1, 2]) == true
  assert none(pos, [0 - 1, 0 - 2]) == true
end

test "count_if"
  assert count_if(fn(x) x % 2 == 0 end, [1, 2, 3, 4, 5, 6]) == 3
end

test "predicate algebra"
  pos = fn(x) x > 0 end
  even_p = fn(x) x % 2 == 0 end
  assert both(pos, even_p)(4) == true
  assert both(pos, even_p)(3) == false
  assert either(pos, even_p)(0 - 2) == true
  assert complement(pos)(0 - 1) == true
end
