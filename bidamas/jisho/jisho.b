@moduledoc """
jisho (辞書) — dictionaries: maps as values, read and changed by key, each change a new map.

jisho holds `keys`, `values`, `entries`, `size`, `empty?`, `has?` (true for
a key that holds nil), `put`, `delete`, `need` (raises `:not_found`),
`update`, `select`, `merge` (b wins) and `from_entries`. The master verbs
reach jisho for a plain map.

    merge({"a" => 1, "b" => 2}, {"b" => 3}) #=> {"a" => 1, "b" => 3}
"""

use("retsu", %i[first is_empty rest])

def keys(m)
  map(first, map_entries(m))
end

def values(m)
  map((e) -> e[1], map_entries(m))
end

def entries(m)
  map_entries(m)
end

def size(m)
  retsu::size(map_entries(m))
end

@doc """
empty?: Whether xs is nil or has no elements.

    empty?({}) #=> true
"""
def empty?(m)
  is_empty(map_entries(m))
end

@doc """
has?: Whether the key is present. A plain map goes to jisho.
"""
def has?(m, key)
  member?(key, keys(m))
end

@doc """
put: Create or replace an entry; a plain map goes to jisho, which returns a new map.
"""
def put(m, key, value)
  merge(m, {key => value})
end

@doc """
delete: Make an entry absent; absent counts as done. A plain map goes to jisho; in_space("gitto", repo) deletes a branch or tag.
"""
def delete(m, key)
  dissoc(m, key)
end

@doc """
need: One entry, raising :not_found when absent. A plain map goes to jisho.
"""
def need(m, key)
  if has?(m, key)
    get(m, key)
  else
    raise(:not_found, "no key #{key} in the map")
  end
end

@doc """
update: Replace an entry with f of the old value; raises :not_found when absent. A plain map goes to jisho.
"""
def update(m, key, f)
  put(m, key, f(need(m, key)))
end

def select(m, wanted)
  reduce(
    fn(acc, k)
      if has?(m, k)
        put(acc, k, get(m, k))
      else
        acc
      end
    end,
    {},
    wanted
  )
end

@doc """
get_any: The value at the first of `keys` that holds one, or nil; a field read under its preferred name, then its fallbacks.

    get_any({b: 2}, %i[a b]) #=> 2
"""
def get_any(m, keys)
  v = get(m, first(keys))
  if v.nil? and not is_empty(keys)
    get_any(m, rest(keys))
  else
    v
  end
end

@doc """
push_at: A new map whose list at key k gains v at its end; an absent key starts the list.

    push_at({}, :seen, 1) #=> {seen: [1]}
"""
def push_at(m, k, v)
  append_at(m, k, [v])
end

@doc """
append_at: A new map whose list at key k gains every item of xs at its end; an absent key starts the list.

    append_at({seen: [1]}, :seen, [2, 3]) #=> {seen: [1, 2, 3]}
    append_at({}, :seen, []) #=> {seen: []}
"""
def append_at(m, k, xs)
  assoc(m, k, append(get(m, k), xs))
end

test "append_at extends the list at a key and starts an absent one"
  assert append_at({}, :seen, []) == {seen: []}
  assert append_at({seen: [1]}, :seen, []) == {seen: [1]}
  assert append_at({seen: [1]}, :seen, [2, 3]) == {seen: [1, 2, 3]}
  assert append_at({a: [0]}, :b, [9]) == {a: [0], b: [9]}
end

def from_entries(pairs)
  zipmap(map(first, pairs), map((e) -> e[1], pairs))
end

def merge(a, b)
  reduce((acc, e) -> assoc(acc, first(e), e[1]), a, map_entries(b))
end

space_for(:map, "jisho")
verb_for("jisho", "has?", has?)
verb_for("jisho", "need", need)
verb_for("jisho", "put", put)
verb_for("jisho", "update", update)
verb_for("jisho", "delete", delete)

test "keys values entries and size read a map in key order"
  m = {"b" => 2, "a" => 1}
  assert keys(m) == %w[a b]
  assert values(m) == [1, 2]
  assert entries(m) == [["a", 1], ["b", 2]]
  assert size(m) == 2
  assert size({}) == 0
  assert empty?({}) == true
  assert empty?(m) == false
end

test "put and delete return new maps and leave the original"
  m = {"a" => 1}
  assert put(m, "b", 2) == {"a" => 1, "b" => 2}
  assert put(m, "a", 9) == {"a" => 9}
  assert m == {"a" => 1}
  assert delete(m, "a") == {}
  assert delete(m, "zz") == m
end

test "has? sees a key whose value is nil and need raises on an absent key"
  m = {"a" => nil, "b" => 2}
  assert has?(m, "a") == true
  assert has?(m, "c") == false
  assert need(m, "b") == 2
  caught = begin
    need(m, "c")
  rescue e
    e.kind
  end
  assert caught == :not_found
end

test "update applies f to the existing value and raises when absent"
  m = {"n" => 1}
  assert update(m, "n", (x) -> x + 1) == {"n" => 2}
  caught = begin
    update(m, "z", (x) -> x)
  rescue e
    e.kind
  end
  assert caught == :not_found
end

test "select keeps listed keys that exist and merge lets b win"
  m = {"a" => 1, "b" => 2, "c" => 3}
  assert select(m, %w[c a x]) == {"a" => 1, "c" => 3}
  assert merge({"a" => 1, "b" => 2}, {"b" => 3, "c" => 4}) ==
    {"a" => 1, "b" => 3, "c" => 4}
  assert merge({}, {}) == {}
end

test "get_any answers the first key that holds a value"
  assert get_any({}, %i[a b]).nil?
  assert get_any({a: 1}, []).nil?
  assert get_any({a: 1, b: 2}, %i[a b]) == 1
  assert get_any({a: nil, b: 2}, %i[a b]) == 2
  assert get_any({a: false, b: 2}, %i[a b]) == false
end

test "push_at appends to the list at a key and leaves the original"
  m = {seen: [1]}
  assert push_at({}, :seen, 1) == {seen: [1]}
  assert push_at(m, :seen, 2) == {seen: [1, 2]}
  assert m == {seen: [1]}
  assert push_at({n: 0}, :seen, [3]) == {n: 0, seen: [[3]]}
end

test "from_entries inverts entries"
  m = {"a" => 1, "b" => 2}
  assert from_entries(entries(m)) == m
  assert from_entries([]) == {}
end

test "the master verbs reach jisho for a plain map"
  m = {"a" => 1, "b" => nil}
  assert blue::has?(m, "b") == true
  assert blue::has?(m, "z") == false
  assert blue::has?({}, "a") == false
  assert blue::need(m, "a") == 1
  assert blue::put(m, "c", 3) == put(m, "c", 3)
  assert blue::put({}, "a", 1) == {"a" => 1}
  assert blue::update(m, "a", (x) -> x + 1) == {"a" => 2, "b" => nil}
  assert blue::delete(m, "a") == {"b" => nil}
  assert blue::delete({}, "a") == {}
end

test "a master verb on a map raises what jisho raises"
  caught = begin
    blue::need({}, "z")
  rescue e
    e.kind
  end
  assert caught == :not_found
  caught = begin
    blue::update({}, "z", (x) -> x)
  rescue e
    e.kind
  end
  assert caught == :not_found
end

test "a map is owned by jisho and a tagged map by its own space"
  assert space_of({}) == "jisho"
  assert space_of({"a" => 1}) == "jisho"
  assert space_of(in_space("gitto", {})) == "gitto"
  assert space_of([]).nil?
  assert space_of(nil).nil?
end
