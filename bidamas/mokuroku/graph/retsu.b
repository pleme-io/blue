space("retsu", {status: :ratified})

verb(
  "retsu",
  "append",
  {
    kind: :pure,
    shape: "append(list, item) -> list",
    laterals: [],
    fleet: nil,
    today: "partial:retsu",
    meaning: "new list with an item at the end",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "at",
  {
    kind: :pure,
    shape: "at(list, index) -> item or nil",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "exists:retsu",
    meaning: "item at an index; negative counts from the end",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "chunk",
  {
    kind: :pure,
    shape: "chunk(list, n) -> [list]",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "consecutive groups of n items",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "concat",
  {
    kind: :pure,
    shape: "concat(lists) -> list",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "exists:retsu",
    meaning: "lists joined end to end",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "contains?",
  {
    kind: :pure,
    shape: "contains?(list, item) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "whether an equal item is in the list",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "count",
  {
    kind: :pure,
    shape: "count(list, f) -> int",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "number of items where f holds",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "drop",
  {
    kind: :pure,
    shape: "drop(list, n) -> list",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "exists:retsu",
    meaning: "all but the first n items",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "drop_while",
  {
    kind: :pure,
    shape: "drop_while(list, f) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "skip leading items while f holds",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "each",
  {
    kind: :effect,
    shape: "each(list, f) -> nil",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "call f on each item for its effect",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "empty?",
  {
    kind: :pure,
    shape: "empty?(list) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "whether the list has no items",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "filter",
  {
    kind: :pure,
    shape: "filter(list, f) -> list",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "items where f holds",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "find",
  {
    kind: :pure,
    shape: "find(list, f) -> item or nil",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "first item where f holds",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "first",
  {
    kind: :pure,
    shape: "first(list) -> item or nil",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "first item, nil when empty",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "flat_map",
  {
    kind: :pure,
    shape: "flat_map(list, f) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "map then flatten one level",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "flatten",
  {
    kind: :pure,
    shape: "flatten(list, depth) -> list",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "exists:retsu",
    meaning: "nested lists to one level",
    wave: 0,
    origin: "A",
    contract: "flatten(list) -> list"
  }
)

verb(
  "retsu",
  "group_by",
  {
    kind: :pure,
    shape: "group_by(list, f) -> map",
    laterals: [],
    fleet: nil,
    today: "exists:shuugou",
    meaning: "items grouped under the key f gives",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "index_of",
  {
    kind: :pure,
    shape: "index_of(list, item) -> int or nil",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "index of the first equal item",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "insert",
  {
    kind: :pure,
    shape: "insert(list, index, item) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "new list with an item placed at an index",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "interleave",
  {
    kind: :pure,
    shape: "interleave(a, b) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "items of two lists taken in turn",
    wave: 0,
    origin: "A",
    contract: "interleave(a) -> list"
  }
)

verb(
  "retsu",
  "last",
  {
    kind: :pure,
    shape: "last(list) -> item or nil",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "last item, nil when empty",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "map",
  {
    kind: :pure,
    shape: "map(list, f) -> list",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "apply f to each item",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "partition",
  {
    kind: :pure,
    shape: "partition(list, f) -> record",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "items split by whether f holds",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "prepend",
  {
    kind: :pure,
    shape: "prepend(list, item) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "new list with an item at the front",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "range",
  {
    kind: :pure,
    shape: "range(from, to, step) -> list",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "absent",
    meaning: "numbers from a start up to an end",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "reduce",
  {
    kind: :pure,
    shape: "reduce(list, start, f) -> value",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "fold items into one value",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "reject",
  {
    kind: :pure,
    shape: "reject(list, f) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "items where f does not hold",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "remove",
  {
    kind: :pure,
    shape: "remove(list, index) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "new list without the item at an index",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "rest",
  {
    kind: :pure,
    shape: "rest(list) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "every item after the first",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "reverse",
  {
    kind: :pure,
    shape: "reverse(list) -> list",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "items in opposite order",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "sample",
  {
    kind: :pure,
    shape: "sample(list, rng, n) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "n items chosen with a seeded stream",
    wave: 2,
    origin: "A"
  }
)

verb(
  "retsu",
  "scan",
  {
    kind: :pure,
    shape: "scan(list, start, f) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "every running result of a fold",
    wave: 0,
    origin: "A",
    contract: "scan(list, start, opts) -> list"
  }
)

verb(
  "retsu",
  "shuffle",
  {
    kind: :pure,
    shape: "shuffle(list, rng) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "items in random order from a seeded stream",
    wave: 2,
    origin: "A"
  }
)

verb(
  "retsu",
  "size",
  {
    kind: :pure,
    shape: "size(list) -> int",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "number of items",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "slice",
  {
    kind: :pure,
    shape: "slice(list, from, to) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "items from an index up to another",
    wave: 0,
    origin: "A",
    contract: "slice(list, from, to, to) -> list"
  }
)

verb(
  "retsu",
  "take",
  {
    kind: :pure,
    shape: "take(list, n) -> list",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "exists:retsu",
    meaning: "the first n items",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "take_while",
  {
    kind: :pure,
    shape: "take_while(list, f) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "leading items while f holds",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "tally",
  {
    kind: :pure,
    shape: "tally(list) -> map",
    laterals: [],
    fleet: nil,
    today: "exists:toukei",
    meaning: "how often each item occurs",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "turn",
  {
    kind: :pure,
    shape: "turn(list, n) -> list",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "items moved n places, wrapping around",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "unique",
  {
    kind: :pure,
    shape: "unique(list) -> list",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "exists:shuugou",
    meaning: "first of each equal item, order kept",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "unzip",
  {
    kind: :pure,
    shape: "unzip(pairs) -> record",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "a list of pairs split into two lists",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "update",
  {
    kind: :pure,
    shape: "update(list, index, f) -> list",
    laterals: ["error"],
    fleet: nil,
    today: "exists:retsu",
    meaning: "new list with f applied at an index",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "windows",
  {
    kind: :pure,
    shape: "windows(list, n) -> [list]",
    laterals: [],
    fleet: nil,
    today: "exists:retsu",
    meaning: "every run of n adjacent items",
    wave: 0,
    origin: "A"
  }
)

verb(
  "retsu",
  "zip",
  {
    kind: :pure,
    shape: "zip(a, b) -> [pair]",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "exists:retsu",
    meaning: "items of two lists paired by position",
    wave: 0,
    origin: "A"
  }
)

edge("retsu::group_by", :composes, "jisho::put", "collect into a map")
edge("retsu::tally", :composes, "jisho::update", "increment per item")
edge("retsu::sample", :composes, "kakuritsu?::int", "draws indexes")
edge("retsu::shuffle", :composes, "kakuritsu?::int", "draws swap positions")
edge("retsu::first", :composes, "retsu::at", "index zero")
edge("retsu::last", :composes, "retsu::at", "index minus one")
edge("retsu::flatten", :composes, "retsu::concat", "concat the inner lists")
edge("retsu::insert", :composes, "retsu::concat", "join head, item, tail")
edge("retsu::prepend", :composes, "retsu::concat", "a one-item list in front")
edge("retsu::rest", :composes, "retsu::drop", "drop one")
edge("retsu::slice", :composes, "retsu::drop", "prefix of the suffix")
edge("retsu::count", :composes, "retsu::filter", "size of the matches")
edge("retsu::find", :composes, "retsu::filter", "first of the matches")
edge("retsu::partition", :composes, "retsu::filter", "the kept half")

edge(
  "retsu::reject",
  :composes,
  "retsu::filter",
  "filter with the test negated"
)

edge("retsu::index_of", :composes, "retsu::find", "position instead of item")
edge("retsu::flat_map", :composes, "retsu::flatten", "then flatten one level")
edge("retsu::flat_map", :composes, "retsu::map", "map first")
edge("retsu::reverse", :composes, "retsu::reduce", "fold from the end")
edge("retsu::scan", :composes, "retsu::reduce", "keeps each partial result")
edge("retsu::partition", :composes, "retsu::reject", "the other half")
edge("retsu::update", :composes, "retsu::remove", "replace at an index")
edge("retsu::sample", :composes, "retsu::shuffle", "first n of a shuffle")
edge("retsu::empty?", :composes, "retsu::size", "size equals zero")
edge("retsu::chunk", :composes, "retsu::slice", "consecutive slices")
edge("retsu::turn", :composes, "retsu::slice", "move a prefix to the end")
edge("retsu::windows", :composes, "retsu::slice", "slice at each offset")
edge("retsu::insert", :composes, "retsu::take", "keep the head")
edge("retsu::slice", :composes, "retsu::take", "prefix of the suffix")
edge("retsu::take_while", :composes, "retsu::take", "take up to the first miss")
edge("retsu::interleave", :composes, "retsu::zip", "flatten the pairs")
edge("retsu::contains?", :composes, "ronri::any", "any item equal")
edge("retsu::reject", :composes, "ronri::not", "negated test")
edge("retsu::concat", :generalizes, "retsu::append", "many items at once")
edge("retsu::filter", :generalizes, "retsu::find", "all matches, not the first")
edge("retsu::reduce", :generalizes, "retsu::map", "map is a fold")

edge(
  "retsu::group_by",
  :generalizes,
  "retsu::partition",
  "many groups, not two"
)

edge(
  "retsu::chunk",
  :generalizes,
  "retsu::windows",
  "windows that do not overlap"
)

edge("retsu::remove", :inverse, "retsu::insert", "undoes insert")
edge("retsu::insert", :inverse, "retsu::remove", "undoes insert")
edge("retsu::zip", :inverse, "retsu::unzip", "pairs and two lists round-trip")
edge("retsu::unzip", :inverse, "retsu::zip", "pairs and two lists round-trip")
edge("retsu::windows", :pairs, "retsu::chunk", "overlapping versus not")
edge("retsu::append", :pairs, "retsu::concat", "one item versus many")
edge("retsu::take", :pairs, "retsu::drop", "prefix and suffix")
edge("retsu::take_while", :pairs, "retsu::drop_while", "prefix and rest")
edge("retsu::size", :pairs, "retsu::empty?", "count and its zero test")
edge("retsu::map", :pairs, "retsu::filter", "transform versus select")
edge("retsu::rest", :pairs, "retsu::first", "head and tail")
edge("retsu::at", :pairs, "retsu::index_of", "item and position")
edge("retsu::zip", :pairs, "retsu::interleave", "pair versus alternate")
edge("retsu::first", :pairs, "retsu::last", "the two ends")
edge("retsu::each", :pairs, "retsu::map", "effect versus value")
edge("retsu::append", :pairs, "retsu::prepend", "the two ends")
edge("retsu::sample", :pairs, "retsu::shuffle", "n items versus all")
edge("retsu::range", :pairs, "retsu::take", "bounded slices of a sequence")
edge("retsu::find", :pairs, "ronri::any", "the item versus existence")
edge("retsu::at", :refines, "jisho::get", "index is the key")
edge("retsu::contains?", :refines, "retsu::find", "Bool answer only")
edge("retsu::tally", :refines, "retsu::group_by", "group sizes only")
edge("retsu::unique", :refines, "shuugou::set", "a set keeps one of each")
