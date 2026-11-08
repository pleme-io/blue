# `case` — value matching and patterns.
#
# Blue's case compares with the same `equal?` the `==` operator uses, so it
# matches by VALUE across every class. A `when` that holds a name destructures:
# `rect(w, h)` matches a record by position, `[x, *rest]` a list by head and
# rest, `{name:}` a map holding :name. Inside a pattern a name binds, `_`
# matches anything and a literal compares. A pattern with no name in it
# compares by value, as before.

record point(x, y)

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
  assert result.nil?
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

test "a record pattern binds its fields by position"
  assert case point(3, 4)
  when point(a, b)
    a - b
  end == -1
end

test "a list pattern binds the head and the rest"
  assert case [1, 2, 3]
  when [x, *rest]
    [x, rest]
  end == [1, [2, 3]]
end

test "a map pattern binds a key it holds"
  assert case {name: "a", age: 3}
  when {name: _, age: 4}
    :four
  when {name:}
    name
  end == "a"
end
