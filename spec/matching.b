# `case` — value matching.
#
# Blue's case compares with the same `equal?` the `==` operator uses, so it
# matches by VALUE across every class. It does not destructure: Elixir's case
# binds pattern variables, which needs a pattern language and a binder blue does
# not have — and a case that LOOKED like Elixir's while silently only comparing
# would be worse than one that plainly compares.

def describe(n)
  case n
  when 1
    "one"
  when 2
    "two"
  else
    "many"
  end
end
test "a matching arm wins"
  assert describe(1) == "one"
  assert describe(2) == "two"
end
test "else catches the rest"
  assert describe(99) == "many"
end
test "no match and no else is nil, as in Ruby"
  result = case 9
  when 1
    "one"
  end
  assert result == nil
end
test "matching is structural, not numeric"
  assert case "b"
  when "a"
    1
  when "b"
    2
  end == 2
end
test "a list matches by value"
  assert case [1, 2]
  when [1, 2]
    "matched"
  end == "matched"
end
