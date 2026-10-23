space("jisho", {status: :ratified})

verb(
  "jisho",
  "delete",
  {
    kind: :pure,
    shape: "delete(map, key) -> map",
    laterals: [],
    fleet: nil,
    today: "exists",
    meaning: "new map without the key",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "empty?",
  {
    kind: :pure,
    shape: "empty?(map) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists",
    meaning: "whether the map has no entries",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "entries",
  {
    kind: :pure,
    shape: "entries(map) -> [pair]",
    laterals: [],
    fleet: nil,
    today: "exists",
    meaning: "key and value pairs in key order",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "filter",
  {
    kind: :pure,
    shape: "filter(map, f) -> map",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "keep entries where f(key, value) holds",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jisho",
  "from_entries",
  {
    kind: :pure,
    shape: "from_entries(pairs) -> map",
    laterals: ["error"],
    fleet: nil,
    today: "exists",
    meaning: "map built from key and value pairs",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "get",
  {
    kind: :pure,
    shape: "get(map, key, opts) -> value or nil",
    laterals: [],
    fleet: nil,
    today: "partial:deeta",
    meaning: "value at key, nil when absent",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "has?",
  {
    kind: :pure,
    shape: "has?(map, key) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists",
    meaning: "whether the key is present",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "invert",
  {
    kind: :pure,
    shape: "invert(map) -> map",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "swap keys and values",
    wave: 2,
    origin: "A"
  }
)

verb(
  "jisho",
  "keys",
  {
    kind: :pure,
    shape: "keys(map) -> [key]",
    laterals: [],
    fleet: nil,
    today: "exists",
    meaning: "keys in sorted order",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "map_keys",
  {
    kind: :pure,
    shape: "map_keys(map, f) -> map",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "apply f to every key",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jisho",
  "map_values",
  {
    kind: :pure,
    shape: "map_values(map, f) -> map",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "apply f to every value",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jisho",
  "merge",
  {
    kind: :pure,
    shape: "merge(a, b, opts) -> map",
    laterals: [],
    fleet: nil,
    today: "partial",
    meaning: "new map from a and b; b wins",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "need",
  {
    kind: :pure,
    shape: "need(map, key) -> value",
    laterals: ["error"],
    fleet: nil,
    today: "exists",
    meaning: "value at key, raises not_found when absent",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "omit",
  {
    kind: :pure,
    shape: "omit(map, keys) -> map",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "drop the listed keys",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jisho",
  "put",
  {
    kind: :pure,
    shape: "put(map, key, value) -> map",
    laterals: [],
    fleet: nil,
    today: "exists",
    meaning: "new map with key set",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "rename",
  {
    kind: :pure,
    shape: "rename(map, from, to) -> map",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "new map with one key renamed",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jisho",
  "select",
  {
    kind: :pure,
    shape: "select(map, keys) -> map",
    laterals: [],
    fleet: nil,
    today: "exists",
    meaning: "keep only the listed keys",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "size",
  {
    kind: :pure,
    shape: "size(map) -> int",
    laterals: [],
    fleet: nil,
    today: "exists",
    meaning: "number of entries",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "update",
  {
    kind: :pure,
    shape: "update(map, key, f) -> map",
    laterals: ["error"],
    fleet: nil,
    today: "exists",
    meaning: "new map with f applied to the value at key",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jisho",
  "values",
  {
    kind: :pure,
    shape: "values(map) -> [value]",
    laterals: [],
    fleet: nil,
    today: "exists",
    meaning: "values in key order",
    wave: 0,
    origin: "A"
  }
)

edge("jisho::omit", :composes, "jisho::delete", "drop each key")
edge("jisho::rename", :composes, "jisho::delete", "remove the old key")
edge("jisho::filter", :composes, "jisho::entries", "keep pairs where f holds")
edge("jisho::invert", :composes, "jisho::entries", "swap each pair")
edge("jisho::keys", :composes, "jisho::entries", "first of each pair")
edge("jisho::map_keys", :composes, "jisho::entries", "rewrite each pair")
edge("jisho::map_values", :composes, "jisho::entries", "rewrite each pair")
edge("jisho::values", :composes, "jisho::entries", "second of each pair")
edge("jisho::select", :composes, "jisho::get", "read each listed key")
edge("jisho::update", :composes, "jisho::get", "read the old value")
edge("jisho::size", :composes, "jisho::keys", "count of keys")
edge("jisho::from_entries", :composes, "jisho::put", "builds the map by puts")
edge("jisho::merge", :composes, "jisho::put", "fold entries of b into a")
edge("jisho::rename", :composes, "jisho::put", "store under the new key")
edge("jisho::update", :composes, "jisho::put", "store f(old)")
edge("jisho::empty?", :composes, "jisho::size", "size equals zero")
edge("jisho::has?", :guards, "jisho::need", "check presence first")
edge("jisho::put", :inverse, "jisho::delete", "removes what put sets")

edge(
  "jisho::from_entries",
  :inverse,
  "jisho::entries",
  "pairs and map round-trip"
)

edge(
  "jisho::entries",
  :inverse,
  "jisho::from_entries",
  "pairs and map round-trip"
)

edge("jisho::delete", :inverse, "jisho::put", "removes what put sets")
edge("jisho::put", :pairs, "jisho::get", "set what get reads")
edge("jisho::get", :pairs, "jisho::has?", "value and presence")
edge("jisho::merge", :pairs, "jisho::select", "combine versus restrict")
edge("jisho::omit", :pairs, "jisho::select", "drop versus keep")
edge("jisho::keys", :pairs, "jisho::values", "same order")
edge("jisho::from_entries", :pairs, "retsu::zip", "keys zipped with values")
edge("jisho::get", :refines, "deeta::get", "one key instead of a path")
edge("jisho::need", :refines, "jisho::get", "raises instead of nil")
edge("jisho::empty?", :refines, "retsu::empty?", "no entries")
edge("jisho::filter", :refines, "retsu::filter", "filter over the pairs")
edge("jisho::select", :refines, "retsu::filter", "keep chosen entries")
edge("jisho::map_values", :refines, "retsu::map", "map over the values")
edge("jisho::size", :refines, "retsu::size", "count of entries")
edge("jisho::update", :requires, "jisho::need", "missing key raises not_found")
