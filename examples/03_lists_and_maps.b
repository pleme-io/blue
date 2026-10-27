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
  map((x) -> x * x, filter((x) -> x % 2 == 0, xs))
end

# Tally words into a map with reduce and assoc.
def tally(words)
  reduce((m, w) -> assoc(m, w, (get(m, w) or 0) + 1), {}, words)
end

test "map and filter take the function first"
  assert squares_of_evens([1, 2, 3, 4]) == [4, 16]
  assert squares_of_evens([]) == []
end

test "the total list words accept the empty list"
  assert size([]) == 0
  assert size(nil) == 0
  assert first([]).nil?
  assert rest([7]) == []
  assert is_empty([])
end

test "nth takes the index first, and answers nil past the end"
  assert [:a, :b, :c][1] == :b
  assert [:a][9].nil?
end

test "a map built up and read back"
  m = tally(["a", "b", "a"])
  assert m["a"] == 2
  assert m["z"].nil?
  assert dissoc(m, "b") == {"a" => 2}
  assert {a: 1, b: 2} == {b: 2, a: 1}
end

test "grouping and counting return pairs"
  assert frequencies([:x, :y, :x]) == [[:x, 2], [:y, 1]]
  assert group_by([1, 2, 3], (n) -> n % 2) == [[1, [1, 3]], [0, [2]]]
  assert lookup(frequencies([:x, :y, :x]), :x) == 2
end

test "sorting by a key"
  people = [{name: "ana", age: 41}, {name: "bo", age: 29}]
  assert map((p) -> p[:name], sort_by((p) -> p[:age], people)) == ["bo", "ana"]
end
