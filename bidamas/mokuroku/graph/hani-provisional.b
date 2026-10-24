space("hani?", {status: :provisional})

verb(
  "hani?",
  "clamp",
  {
    kind: :pure,
    shape: "clamp(x, range) -> value",
    laterals: [],
    fleet: nil,
    today: "partial:kazu",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hani?",
  "coalesce",
  {
    kind: :pure,
    shape: "coalesce(ranges) -> [range]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "join overlapping ranges into disjoint ones",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hani?",
  "contains?",
  {
    kind: :pure,
    shape: "contains?(range, x) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a point or range lies inside",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hani?",
  "gaps",
  {
    kind: :pure,
    shape: "gaps(ranges, within) -> [range]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "parts of a range that no range covers",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hani?",
  "hull",
  {
    kind: :pure,
    shape: "hull(a, b) -> range",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "smallest range holding both",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hani?",
  "intersect",
  {
    kind: :pure,
    shape: "intersect(a, b) -> range or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the shared part of two ranges",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hani?",
  "length",
  {
    kind: :pure,
    shape: "length(range) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "distance from low to high",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hani?",
  "overlaps?",
  {
    kind: :pure,
    shape: "overlaps?(a, b) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether two ranges share a point",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hani?",
  "range",
  {
    kind: :pure,
    shape: "range(low, high, opts) -> range",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "build a range; ends open or closed",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hani?",
  "shift",
  {
    kind: :pure,
    shape: "shift(range, by) -> range",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "move both ends by the same amount",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hani?",
  "split",
  {
    kind: :pure,
    shape: "split(range, at) -> [range]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "cut a range at a point",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hani?",
  "touches?",
  {
    kind: :pure,
    shape: "touches?(a, b) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether two ranges overlap or meet end to end",
    wave: 2,
    origin: "A"
  }
)

edge("hani?::gaps", :composes, "hani?::coalesce", "what the merged ranges miss")
edge("hani?::clamp", :composes, "hani?::contains?", "pull the point inside")

edge(
  "hani?::coalesce",
  :composes,
  "hani?::hull",
  "each joined pair becomes a hull"
)

edge(
  "hani?::split",
  :composes,
  "hani?::intersect",
  "cut into the inside and the rest"
)

edge("hani?::coalesce", :composes, "hani?::touches?", "join ranges that touch")

edge(
  "hani?::length",
  :composes,
  "jikan::between",
  "time ranges measure a duration"
)

edge(
  "hani?::overlaps?",
  :composes,
  "shuugou::disjoint?",
  "overlap is not disjoint"
)

edge("hani?::clamp", :generalizes, "kazu::clamp", "any range, not two numbers")

edge(
  "hani?::range",
  :guards,
  "hani?::contains?",
  "builds the value contains? tests"
)

edge("hani?::split", :inverse, "hani?::hull", "cut versus join")
edge("hani?::hull", :inverse, "hani?::split", "cut versus join")
edge("hani?::touches?", :pairs, "hani?::coalesce", "meeting ranges join")
edge("hani?::hull", :pairs, "hani?::intersect", "outer and inner cover")
edge("hani?::shift", :pairs, "hani?::split", "move versus cut")
edge("hani?::contains?", :pairs, "shuugou::has?", "range versus set membership")
edge("hani?::contains?", :refines, "hani?::overlaps?", "inside implies overlap")

edge(
  "hani?::overlaps?",
  :refines,
  "hani?::touches?",
  "overlap implies touching"
)

edge("hani?::gaps", :refines, "shuugou::difference", "ranges as sets of points")

edge(
  "hani?::intersect",
  :refines,
  "shuugou::intersection",
  "ranges as sets of points"
)

edge("hani?::coalesce", :refines, "shuugou::union", "ranges as sets of points")
edge("hani?::intersect", :requires, "hani?::overlaps?", "empty when no overlap")
edge("hani?::length", :requires, "hani?::range", "needs low and high")
edge("hani?::shift", :requires, "hani?::range", "moves both ends")
edge("hani?::touches?", :requires, "hani?::range", "needs two built ranges")
