space("chiri?", {status: :provisional})

verb(
  "chiri?",
  "area",
  {
    kind: :pure,
    shape: "area(region) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "surface area in square metres",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "bearing",
  {
    kind: :pure,
    shape: "bearing(a, b) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "initial compass heading from a to b",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "bounds",
  {
    kind: :pure,
    shape: "bounds(points) -> box",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "smallest box holding every point",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "cell",
  {
    kind: :pure,
    shape: "cell(point, system, level) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "geohash, H3 or S2 cell holding a point",
    wave: 4,
    origin: "A"
  }
)

verb(
  "chiri?",
  "cell_point",
  {
    kind: :pure,
    shape: "cell_point(cell) -> point",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "centre of a cell",
    wave: 4,
    origin: "A"
  }
)

verb(
  "chiri?",
  "contains?",
  {
    kind: :pure,
    shape: "contains?(region, point) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a point lies inside a region",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "destination",
  {
    kind: :pure,
    shape: "destination(point, bearing, distance) -> point",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "point reached by travelling a distance on a heading",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "distance",
  {
    kind: :pure,
    shape: "distance(a, b, opts) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "surface distance in metres by haversine or ellipsoid",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "midpoint",
  {
    kind: :pure,
    shape: "midpoint(a, b) -> point",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "point halfway along the great circle",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "nearest",
  {
    kind: :pure,
    shape: "nearest(point, points) -> point or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "closest point of a set",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "neighbors",
  {
    kind: :pure,
    shape: "neighbors(cell) -> [text]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "cells touching a cell",
    wave: 4,
    origin: "A"
  }
)

verb(
  "chiri?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> point",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "degrees-minutes-seconds, decimal, WKT or plus code to a point",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "point",
  {
    kind: :pure,
    shape: "point(latitude, longitude, opts) -> point",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "a place on the earth; bad ranges raise",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "project",
  {
    kind: :pure,
    shape: "project(point, crs) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "point in a flat coordinate system such as UTM",
    wave: 4,
    origin: "A"
  }
)

verb(
  "chiri?",
  "region",
  {
    kind: :decl,
    shape: "region(shape, opts) -> region",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare a box, circle or polygon on the earth",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "render",
  {
    kind: :pure,
    shape: "render(point, format) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "point as decimal, DMS, WKT or plus code",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chiri?",
  "simplify",
  {
    kind: :pure,
    shape: "simplify(line, tolerance) -> line",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "line with fewer points inside a tolerance",
    wave: 4,
    origin: "A"
  }
)

verb(
  "chiri?",
  "unproject",
  {
    kind: :pure,
    shape: "unproject(xy, crs) -> point",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "flat coordinates back to latitude and longitude",
    wave: 4,
    origin: "A"
  }
)

verb(
  "chiri?",
  "within",
  {
    kind: :pure,
    shape: "within(point, points, radius) -> [point]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "points no farther than a radius",
    wave: 3,
    origin: "A"
  }
)

edge("chiri?::neighbors", :composes, "chiri?::cell", "cells around a cell")

edge(
  "chiri?::midpoint",
  :composes,
  "chiri?::destination",
  "halfway along the heading"
)

edge("chiri?::nearest", :composes, "chiri?::distance", "least distance wins")

edge(
  "chiri?::bounds",
  :composes,
  "chiri?::point",
  "min and max of the coordinates"
)

edge("chiri?::bearing", :composes, "kazu::atan2", "heading from components")
edge("chiri?::distance", :composes, "kazu::atan2", "haversine angle")
edge("chiri?::distance", :composes, "kazu::sin", "haversine terms")
edge("chiri?::parse", :composes, "moji::find", "degrees, minutes, seconds text")

edge(
  "chiri?::point",
  :composes,
  "sukiima?::refine",
  "range checks are refinements"
)

edge(
  "chiri?::within",
  :generalizes,
  "chiri?::nearest",
  "every point inside a radius"
)

edge(
  "chiri?::point",
  :guards,
  "chiri?::distance",
  "distance needs valid points"
)

edge(
  "chiri?::cell_point",
  :inverse,
  "chiri?::cell",
  "cell and centre round-trip"
)

edge(
  "chiri?::cell",
  :inverse,
  "chiri?::cell_point",
  "cell and centre round-trip"
)

edge("chiri?::render", :inverse, "chiri?::parse", "text and point round-trip")
edge("chiri?::unproject", :inverse, "chiri?::project", "flat and round-trip")
edge("chiri?::parse", :inverse, "chiri?::render", "text and point round-trip")
edge("chiri?::project", :inverse, "chiri?::unproject", "flat and round-trip")

edge(
  "chiri?::destination",
  :pairs,
  "chiri?::bearing",
  "walk a bearing and distance"
)

edge("chiri?::distance", :pairs, "chiri?::bearing", "how far and which way")
edge("chiri?::area", :pairs, "chiri?::bounds", "measure versus box")
edge("chiri?::contains?", :pairs, "chiri?::within", "region versus radius")
edge("chiri?::neighbors", :refines, "gurafu::neighbors", "grid cells as nodes")
edge("chiri?::area", :refines, "kikagaku::area", "on the sphere")
edge("chiri?::bounds", :refines, "kikagaku::bounds", "on the sphere")
edge("chiri?::contains?", :refines, "kikagaku::contains?", "on the sphere")
edge("chiri?::distance", :refines, "kikagaku::distance", "on the sphere")
edge("chiri?::midpoint", :refines, "kikagaku::midpoint", "on the sphere")
edge("chiri?::region", :requires, "chiri?::point", "built from points")

edge(
  "chiri?::simplify",
  :requires,
  "chiri?::project",
  "tolerance in flat metres"
)
