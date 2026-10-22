space("junjo", {status: :ratified})

verb(
  "junjo",
  "max_by",
  {
    kind: :pure,
    shape: "max_by(list, f) -> item or nil",
    laterals: [],
    fleet: nil,
    today: "exists:junjo",
    meaning: "item with the greatest key",
    wave: 0,
    origin: "A"
  }
)

verb(
  "junjo",
  "merge",
  {
    kind: :pure,
    shape: "merge(a, b) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:junjo",
    meaning: "two sorted lists joined in order",
    wave: 0,
    origin: "A"
  }
)

verb(
  "junjo",
  "min_by",
  {
    kind: :pure,
    shape: "min_by(list, f) -> item or nil",
    laterals: [],
    fleet: nil,
    today: "exists:junjo",
    meaning: "item with the least key",
    wave: 0,
    origin: "A"
  }
)

verb(
  "junjo",
  "rank",
  {
    kind: :pure,
    shape: "rank(list) -> [int]",
    laterals: [],
    fleet: nil,
    today: "exists:junjo",
    meaning: "position each item would take when sorted",
    wave: 0,
    origin: "A"
  }
)

verb(
  "junjo",
  "search",
  {
    kind: :pure,
    shape: "search(list, item) -> int or nil",
    laterals: [],
    fleet: nil,
    today: "exists:junjo",
    meaning: "binary search in a sorted list",
    wave: 0,
    origin: "A"
  }
)

verb(
  "junjo",
  "sort",
  {
    kind: :pure,
    shape: "sort(list, opts) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:junjo",
    meaning: "items in ascending order; stable",
    wave: 0,
    origin: "A"
  }
)

verb(
  "junjo",
  "sort_by",
  {
    kind: :pure,
    shape: "sort_by(list, f, opts) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:junjo",
    meaning: "items ordered by the key f gives",
    wave: 0,
    origin: "A",
    contract: "sort_by(list, f) -> list"
  }
)

verb(
  "junjo",
  "sorted?",
  {
    kind: :pure,
    shape: "sorted?(list, opts) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:junjo",
    meaning: "whether the list is in order",
    wave: 0,
    origin: "A"
  }
)

verb(
  "junjo",
  "top",
  {
    kind: :pure,
    shape: "top(list, n, opts) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:junjo",
    meaning: "the n greatest items",
    wave: 0,
    origin: "A"
  }
)

edge("junjo::sort_by", :composes, "junjo::min_by", "compares keys")
edge("junjo::merge", :composes, "junjo::sort", "keeps two sorted lists sorted")
edge("junjo::rank", :composes, "junjo::sort", "index in the sorted list")
edge("junjo::top", :composes, "junjo::sort", "sort, then take")
edge("junjo::top", :composes, "retsu::take", "first n of the order")
edge("junjo::sort", :generalizes, "junjo::sort_by", "key is the item itself")
edge("junjo::sorted?", :guards, "junjo::search", "search needs order")
edge("junjo::min_by", :pairs, "junjo::max_by", "the two ends of the order")
edge("junjo::top", :pairs, "junjo::rank", "greatest versus position")
edge("junjo::sort", :pairs, "junjo::sorted?", "order and its test")
edge("junjo::search", :pairs, "retsu::index_of", "sorted versus unsorted")
edge("junjo::max_by", :refines, "junjo::top", "top of one, reversed")
edge("junjo::min_by", :refines, "junjo::top", "top of one")
edge("junjo::max_by", :refines, "retsu::reduce", "fold keeping the greatest")
edge("junjo::min_by", :refines, "retsu::reduce", "fold keeping the least")

edge(
  "junjo::search",
  :requires,
  "junjo::sorted?",
  "binary search on a sorted list"
)
