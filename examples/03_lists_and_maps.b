# Lists and maps
#
# Lists are values: every operation returns a new list. retsu's words are
# total (size, first, rest, last and is_empty accept [] and nil), so prefer
# them to length, car and cdr. A map is read with get and extended with assoc;
# grouping and counting return [key, value] pairs, because blue cannot list
# a map's keys.
use("junjo", [:sort_by])
use("retsu", [:first, :is_empty, :rest, :size])
use("shuugou", [:frequencies, :group_by, :lookup])

def squares_of_evens(xs)
  map(fn(x) x * x end, filter(fn(x) x % 2 == 0 end, xs))
end

# Tally words into a map with reduce and assoc.
def tally(words)
  reduce(fn(m, w) assoc(m, w, (get(m, w) || 0) + 1) end, {}, words)
end

test "map and filter take the function first"
  assert squares_of_evens([1, 2, 3, 4]) == [4, 16]
  assert squares_of_evens([]) == []
end

test "the total list words accept the empty list"
  assert size([]) == 0
  assert size(nil) == 0
  assert first([]) == nil
  assert rest([7]) == []
  assert is_empty([])
end

test "nth takes the index first, and answers nil past the end"
  assert nth(1, [:a, :b, :c]) == :b
  assert nth(9, [:a]) == nil
end

test "a map built up and read back"
  m = tally(["a", "b", "a"])
  assert get(m, "a") == 2
  assert get(m, "z") == nil
  assert dissoc(m, "b") == {"a" => 2}
  assert {a: 1, b: 2} == {b: 2, a: 1}
end

test "grouping and counting return pairs"
  assert frequencies([:x, :y, :x]) == [[:x, 2], [:y, 1]]
  assert group_by(fn(n) n % 2 end, [1, 2, 3]) == [[1, [1, 3]], [0, [2]]]
  assert lookup(frequencies([:x, :y, :x]), :x) == 2
end

test "sorting by a key"
  people = [{name: "ana", age: 41}, {name: "bo", age: 29}]
  assert map(
    fn(p) get(p, :name) end,
    sort_by(fn(p) get(p, :age) end, people)
  ) ==
    ["bo", "ana"]
end
