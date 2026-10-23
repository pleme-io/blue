space("kikagaku", {status: :ratified})

verb(
  "kikagaku",
  "angle",
  {
    kind: :pure,
    shape: "angle(a, b, c) -> number",
    laterals: [],
    fleet: nil,
    today: "partial:kikagaku",
    meaning: "angle at b between a and c",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "area",
  {
    kind: :pure,
    shape: "area(shape) -> number",
    laterals: [],
    fleet: nil,
    today: "partial:kikagaku",
    meaning: "area of a polygon, circle or region",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "bounds",
  {
    kind: :pure,
    shape: "bounds(shape) -> box",
    laterals: [],
    fleet: nil,
    today: "partial:kikagaku",
    meaning: "smallest axis-aligned box around a shape",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "centroid",
  {
    kind: :pure,
    shape: "centroid(shape) -> point",
    laterals: [],
    fleet: nil,
    today: "exists:kikagaku",
    meaning: "centre of mass of a shape",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "closest",
  {
    kind: :pure,
    shape: "closest(shape, point) -> point",
    laterals: [],
    fleet: nil,
    today: "partial:kikagaku",
    meaning: "point of a shape nearest to a point",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "contains?",
  {
    kind: :pure,
    shape: "contains?(shape, point) -> Bool",
    laterals: [],
    fleet: nil,
    today: "partial:kikagaku",
    meaning: "whether a point is inside a shape",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "difference",
  {
    kind: :pure,
    shape: "difference(a, b) -> region",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "area of a not covered by b",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "distance",
  {
    kind: :pure,
    shape: "distance(a, b) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:kikagaku",
    meaning: "straight-line distance between points",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "grow",
  {
    kind: :pure,
    shape: "grow(polygon, distance) -> polygon",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "polygon grown or shrunk by a distance",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "hull",
  {
    kind: :pure,
    shape: "hull(points) -> polygon",
    laterals: [],
    fleet: nil,
    today: "exists:kikagaku",
    meaning: "smallest convex polygon around the points",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "intersect",
  {
    kind: :pure,
    shape: "intersect(a, b) -> point or nil",
    laterals: [],
    fleet: nil,
    today: "partial:kikagaku",
    meaning: "where two segments cross",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "midpoint",
  {
    kind: :pure,
    shape: "midpoint(a, b) -> point",
    laterals: [],
    fleet: nil,
    today: "exists:kikagaku",
    meaning: "point halfway between two points",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "overlap?",
  {
    kind: :pure,
    shape: "overlap?(a, b) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:kikagaku",
    meaning: "whether two shapes share area",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "perimeter",
  {
    kind: :pure,
    shape: "perimeter(shape) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:kikagaku",
    meaning: "length around a shape",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "scale",
  {
    kind: :pure,
    shape: "scale(shape, factor, about) -> shape",
    laterals: [],
    fleet: nil,
    today: "partial:kikagaku",
    meaning: "shape grown or shrunk about a point",
    wave: 0,
    origin: "A",
    contract: "scale(shape, factor, opts) -> shape"
  }
)

verb(
  "kikagaku",
  "shift",
  {
    kind: :pure,
    shape: "shift(shape, by) -> shape",
    laterals: [],
    fleet: nil,
    today: "partial:kikagaku",
    meaning: "shape moved by a vector",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "turn",
  {
    kind: :pure,
    shape: "turn(shape, angle, about) -> shape",
    laterals: [],
    fleet: nil,
    today: "partial:kikagaku",
    meaning: "shape turned about a point",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kikagaku",
  "union",
  {
    kind: :pure,
    shape: "union(a, b) -> region",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "area covered by either polygon",
    wave: 3,
    origin: "A"
  }
)

edge(
  "kikagaku::angle",
  :composes,
  "gyouretsu::dot",
  "cosine from the dot product"
)

edge("kikagaku::hull", :composes, "junjo::sort", "sort points, then sweep")
edge("kikagaku::angle", :composes, "kazu::atan2", "angle from components")
edge("kikagaku::turn", :composes, "kazu::cos", "rotation matrix terms")
edge("kikagaku::turn", :composes, "kazu::sin", "rotation matrix terms")

edge(
  "kikagaku::distance",
  :composes,
  "kazu::sqrt",
  "root of squared differences"
)

edge("kikagaku::hull", :composes, "kikagaku::angle", "keep left turns")
edge("kikagaku::centroid", :composes, "kikagaku::area", "area-weighted mean")

edge(
  "kikagaku::intersect",
  :composes,
  "kikagaku::bounds",
  "cheap box test first"
)

edge(
  "kikagaku::closest",
  :composes,
  "kikagaku::distance",
  "least distance on the shape"
)

edge(
  "kikagaku::perimeter",
  :composes,
  "kikagaku::distance",
  "sum of edge lengths"
)

edge("kikagaku::area", :composes, "kikagaku::hull", "region of a boundary")

edge(
  "kikagaku::overlap?",
  :composes,
  "kikagaku::intersect",
  "any crossing or containment"
)

edge(
  "kikagaku::difference",
  :composes,
  "kikagaku::overlap?",
  "only where they meet"
)

edge("kikagaku::grow", :composes, "kikagaku::shift", "move each edge outward")

edge(
  "kikagaku::hull",
  :generalizes,
  "kikagaku::area",
  "smallest enclosing polygon"
)

edge("kikagaku::union", :pairs, "kikagaku::difference", "add and subtract area")
edge("kikagaku::midpoint", :pairs, "kikagaku::distance", "halfway along it")
edge("kikagaku::grow", :pairs, "kikagaku::hull", "grow a hull")
edge("kikagaku::perimeter", :pairs, "kikagaku::hull", "boundary length")

edge(
  "kikagaku::bounds",
  :pairs,
  "kikagaku::overlap?",
  "box test before exact test"
)

edge("kikagaku::area", :pairs, "kikagaku::perimeter", "inside and around")
edge("kikagaku::shift", :pairs, "kikagaku::scale", "move and resize")
edge("kikagaku::turn", :pairs, "kikagaku::shift", "turn and move")

edge(
  "kikagaku::distance",
  :refines,
  "gyouretsu::norm",
  "norm of the difference"
)

edge(
  "kikagaku::contains?",
  :refines,
  "kikagaku::overlap?",
  "a point is a tiny shape"
)

edge("kikagaku::contains?", :requires, "kikagaku::area", "polygon test")
edge("kikagaku::grow", :requires, "kikagaku::area", "grow or shrink")
edge("kikagaku::scale", :requires, "kikagaku::bounds", "about a point")

edge(
  "kikagaku::closest",
  :requires,
  "kikagaku::contains?",
  "nearest inside or outside"
)

edge("kikagaku::intersect", :requires, "kikagaku::contains?", "overlap test")
edge("kikagaku::area", :requires, "kikagaku::hull", "area of a hull")
edge("kikagaku::closest", :requires, "kikagaku::hull", "nearest of a set")
