use("retsu", [:first, :is_empty])

def keys(m)
  map(first, map_entries(m))
end

def values(m)
  map((e) -> nth(1, e), map_entries(m))
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

def from_entries(pairs)
  zipmap(map(first, pairs), map((e) -> nth(1, e), pairs))
end

def merge(a, b)
  reduce((acc, e) -> assoc(acc, first(e), nth(1, e)), a, map_entries(b))
end

space_for(:map, "jisho")
verb_for("jisho", "has?", has?)
verb_for("jisho", "need", need)
verb_for("jisho", "put", put)
verb_for("jisho", "update", update)
verb_for("jisho", "delete", delete)

test "keys values entries and size read a map in key order"
  m = {"b" => 2, "a" => 1}
  assert keys(m) == ["a", "b"]
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
  assert select(m, ["c", "a", "x"]) == {"a" => 1, "c" => 3}
  assert merge({"a" => 1, "b" => 2}, {"b" => 3, "c" => 4}) ==
    {"a" => 1, "b" => 3, "c" => 4}
  assert merge({}, {}) == {}
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
