# Building strings
#
# Interpolation renders any value with to_s, so it needs no conversion calls.
# join takes the list first; split takes the string first and keeps empty
# fields. Build many lines as a list and join them once. moji holds the
# string words the runtime lacks (padding, lines, words).
use("moji", [:capitalize, :pad_left, :pad_right, :words])
use("retsu", [:concat_lists, :first, :last])

def row(name, n)
  "#{pad_right(name, 8, " ")}#{pad_left(to_s(n), 4, " ")}"
end

def report(rows)
  body = map(fn(r) row(first(r), last(r)) end, rows)
  join(concat_lists(["name     count", "-------------"], body), "\n")
end

test "interpolation renders any value"
  n = 3
  assert "n = #{n}, list = #{[1, 2]}, nil = [#{nil}]" ==
    "n = 3, list = [1, 2], nil = []"
end

test "a padded table, built as lines and joined once"
  assert report([["apples", 3], ["pears", 12]]) ==
    "name     count\n-------------\napples     3\npears     12"
end

test "split keeps empty fields, and join undoes it"
  assert split("a,,b", ",") == ["a", "", "b"]
  assert join(split("a,,b", ","), ",") == "a,,b"
end

test "the small string words"
  assert upcase("blue") == "BLUE"
  assert trim("  x  ") == "x"
  assert replace("a-b-c", "-", "+") == "a+b+c"
  assert starts_with?("blueshift", "blue")
  assert words("  two   words ") == ["two", "words"]
  assert capitalize("bLUE") == "Blue"
end

test "text compares with ==, and orders with compare, never <"
  assert "a" == "a"
  assert compare("apple", "pear") == -1
end
