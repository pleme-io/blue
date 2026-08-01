# Macros: the metaprogramming surface, specified in blue itself.

defmacro double(x)
  quote
    unquote(x) + unquote(x)
  end
end
defmacro square(e)
  quote
    unquote(e) * unquote(e)
  end
end
test "a macro expands"
  assert double(21) == 42
end
test "a macro operates on the FORM, so it may duplicate its argument"
  assert square(2 + 3) == 25
end
test "macros compose"
  assert double(double(5)) == 20
end
