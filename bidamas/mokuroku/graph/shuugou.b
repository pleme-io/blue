space("shuugou", {status: :ratified})

verb(
  "shuugou",
  "dense",
  {
    kind: :pure,
    shape: "dense(items, bound) -> set",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "set of small integers kept as a bitset",
    wave: 3,
    origin: "A"
  }
)

verb(
  "shuugou",
  "difference",
  {
    kind: :pure,
    shape: "difference(a, b) -> set",
    laterals: [],
    fleet: nil,
    today: "exists:shuugou",
    meaning: "members of a that are not in b",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "disjoint?",
  {
    kind: :pure,
    shape: "disjoint?(a, b) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:shuugou",
    meaning: "whether the sets share no member",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "empty?",
  {
    kind: :pure,
    shape: "empty?(set) -> Bool",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "whether the set has no member",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "has?",
  {
    kind: :pure,
    shape: "has?(set, item) -> Bool",
    laterals: [],
    fleet: nil,
    today: "partial:shuugou",
    meaning: "whether the item is a member",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "insert",
  {
    kind: :pure,
    shape: "insert(set, item) -> set",
    laterals: [],
    fleet: nil,
    today: "exists:shuugou",
    meaning: "set with the item added",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "intersection",
  {
    kind: :pure,
    shape: "intersection(a, b) -> set",
    laterals: [],
    fleet: nil,
    today: "exists:shuugou",
    meaning: "members of both sets",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "power_set",
  {
    kind: :pure,
    shape: "power_set(set) -> [set]",
    laterals: [],
    fleet: nil,
    today: "exists:shuugou",
    meaning: "every subset of a set",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "product",
  {
    kind: :pure,
    shape: "product(a, b) -> [pair]",
    laterals: [],
    fleet: nil,
    today: "exists:shuugou",
    meaning: "every pair of one member from each set",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "remove",
  {
    kind: :pure,
    shape: "remove(set, item) -> set",
    laterals: [],
    fleet: nil,
    today: "exists:shuugou",
    meaning: "set without the item",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "set",
  {
    kind: :pure,
    shape: "set(items) -> set",
    laterals: [],
    fleet: nil,
    today: "partial:shuugou",
    meaning: "set built from a list",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "size",
  {
    kind: :pure,
    shape: "size(set) -> int",
    laterals: [],
    fleet: nil,
    today: "partial:shuugou",
    meaning: "number of members",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "subset?",
  {
    kind: :pure,
    shape: "subset?(a, b) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:shuugou",
    meaning: "whether every member of a is in b",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "symmetric_difference",
  {
    kind: :pure,
    shape: "symmetric_difference(a, b) -> set",
    laterals: [],
    fleet: nil,
    today: "exists:shuugou",
    meaning: "members of exactly one of the sets",
    wave: 0,
    origin: "A"
  }
)

verb(
  "shuugou",
  "union",
  {
    kind: :pure,
    shape: "union(a, b) -> set",
    laterals: [],
    fleet: nil,
    today: "exists:shuugou",
    meaning: "members of either set",
    wave: 0,
    origin: "A"
  }
)

edge(
  "shuugou::power_set",
  :composes,
  "kumiawase::combinations",
  "all sizes together"
)

edge("shuugou::product", :composes, "retsu::flat_map", "pair each with each")
edge("shuugou::set", :composes, "retsu::unique", "drop repeats")
edge("shuugou::subset?", :composes, "shuugou::difference", "a minus b is empty")

edge(
  "shuugou::symmetric_difference",
  :composes,
  "shuugou::difference",
  "a minus b, b minus a"
)

edge(
  "shuugou::disjoint?",
  :composes,
  "shuugou::intersection",
  "intersection is empty"
)

edge("shuugou::empty?", :composes, "shuugou::size", "size equals zero")
edge("shuugou::symmetric_difference", :composes, "shuugou::union", "joined")
edge("shuugou::union", :generalizes, "shuugou::insert", "insert a whole set")
edge("shuugou::remove", :inverse, "shuugou::insert", "undoes insert")
edge("shuugou::insert", :inverse, "shuugou::remove", "undoes insert")
edge("shuugou::union", :pairs, "retsu::concat", "unique versus plain join")
edge("shuugou::difference", :pairs, "retsu::reject", "set minus versus filter")
edge("shuugou::power_set", :pairs, "shuugou::product", "subsets versus pairs")
edge("shuugou::insert", :pairs, "shuugou::remove", "add and drop a member")

edge(
  "shuugou::difference",
  :pairs,
  "shuugou::union",
  "subtraction and addition"
)

edge("shuugou::intersection", :pairs, "shuugou::union", "inner and outer")
edge("shuugou::has?", :refines, "retsu::contains?", "fast membership")
edge("shuugou::size", :refines, "retsu::size", "count of members")
edge("shuugou::dense", :refines, "shuugou::set", "same verbs, compact form")
