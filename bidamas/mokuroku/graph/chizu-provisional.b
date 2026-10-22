space("chizu?", {status: :provisional})

verb(
  "chizu?",
  "bearing",
  {
    kind: :pure,
    shape: "bearing(a, b) -> degrees",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "compass direction from a to b",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "bounds",
  {
    kind: :pure,
    shape: "bounds(geometry) -> box",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the bounding box of a geometry",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "buffer",
  {
    kind: :pure,
    shape: "buffer(geometry, meters) -> geometry",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a geometry grown by a distance",
    wave: 2,
    origin: "G"
  }
)

verb(
  "chizu?",
  "cell",
  {
    kind: :pure,
    shape: "cell(point, level) -> cell",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the grid cell that holds a point: geohash or H3",
    wave: 2,
    origin: "G"
  }
)

verb(
  "chizu?",
  "centroid",
  {
    kind: :pure,
    shape: "centroid(geometry) -> point",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the center of a geometry",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "contains?",
  {
    kind: :pure,
    shape: "contains?(region, point) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a point is inside a region",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "destination",
  {
    kind: :pure,
    shape: "destination(point, bearing, meters) -> point",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the point reached by going a bearing and distance",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "distance",
  {
    kind: :pure,
    shape: "distance(a, b, opts) -> meters",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "great-circle distance of two points",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "geocode",
  {
    kind: :effect,
    shape: "geocode(text, opts) -> places",
    laterals: ["cache", "deadline", "ratelimit", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "places that match an address or name",
    wave: 2,
    origin: "G"
  }
)

verb(
  "chizu?",
  "intersects?",
  {
    kind: :pure,
    shape: "intersects?(a, b) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether two geometries touch",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "locate",
  {
    kind: :effect,
    shape: "locate(point, opts) -> place or nil",
    laterals: ["cache", "deadline", "ratelimit", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "the place at a point; nil if none",
    wave: 2,
    origin: "G"
  }
)

verb(
  "chizu?",
  "measure",
  {
    kind: :pure,
    shape: "measure(geometry, metric) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "length, area or elevation gain",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "neighbors",
  {
    kind: :pure,
    shape: "neighbors(cell) -> cells",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the cells beside a cell",
    wave: 2,
    origin: "G"
  }
)

verb(
  "chizu?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> geometry",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "GeoJSON, WKT or GPX text to geometry",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "path",
  {
    kind: :effect,
    shape: "path(from, to, opts) -> steps",
    laterals: ["cache", "deadline", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "a route over roads or tracks between two points",
    wave: 2,
    origin: "G",
    contract: "path(from, to, to, opts) -> steps"
  }
)

verb(
  "chizu?",
  "point",
  {
    kind: :decl,
    shape: "point(lat, lon, opts) -> point",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "a position; latitude and longitude range refused",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "project",
  {
    kind: :pure,
    shape: "project(point, crs) -> xy",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a point in a flat system: Web Mercator, UTM",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "render",
  {
    kind: :pure,
    shape: "render(geometry, format) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "a geometry as GeoJSON or WKT text",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "simplify",
  {
    kind: :pure,
    shape: "simplify(line, tolerance) -> line",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a line with fewer points, same shape",
    wave: 1,
    origin: "G"
  }
)

verb(
  "chizu?",
  "unproject",
  {
    kind: :pure,
    shape: "unproject(xy, crs) -> point",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a flat coordinate as latitude and longitude",
    wave: 1,
    origin: "G"
  }
)

edge("chizu?::point", :generalizes, "chizu?::distance", "distance of points")

edge(
  "chizu?::destination",
  :inverse,
  "chizu?::bearing",
  "distance and bearing to a point"
)

edge(
  "chizu?::bearing",
  :inverse,
  "chizu?::destination",
  "distance and bearing to a point"
)

edge("chizu?::locate", :inverse, "chizu?::geocode", "place to text")
edge("chizu?::geocode", :inverse, "chizu?::locate", "place to text")
edge("chizu?::render", :inverse, "chizu?::parse", "geometry to text")
edge("chizu?::unproject", :inverse, "chizu?::project", "flat to geo")
edge("chizu?::parse", :inverse, "chizu?::render", "geometry to text")
edge("chizu?::project", :inverse, "chizu?::unproject", "flat to geo")
edge("chizu?::neighbors", :pairs, "chizu?::cell", "cell and its ring")
edge("chizu?::point", :pairs, "chizu?::project", "geo and flat")

edge(
  "chizu?::project",
  :refines,
  "byouga?::project",
  "a point into another system"
)

edge("chizu?::contains?", :refines, "kikagaku::contains?", "on a sphere")
edge("chizu?::centroid", :refines, "rittai::measure", "center of a shape")
edge("chizu?::path", :refines, "sekai?::path", "a route over a road graph")
edge("chizu?::intersects?", :requires, "chizu?::bounds", "test boxes first")
edge("chizu?::neighbors", :requires, "chizu?::cell", "beside a cell")

edge(
  "chizu?::destination",
  :requires,
  "chizu?::distance",
  "distance along a bearing"
)

edge(
  "chizu?::measure",
  :requires,
  "chizu?::distance",
  "length is summed distance"
)

edge("chizu?::path", :requires, "chizu?::distance", "cost of a leg")
edge("chizu?::simplify", :requires, "chizu?::measure", "tolerance from length")
edge("chizu?::bounds", :requires, "chizu?::parse", "geometry in hand")
edge("chizu?::bearing", :requires, "chizu?::point", "two points")
edge("chizu?::cell", :requires, "chizu?::point", "a cell holds points")
edge("chizu?::distance", :requires, "chizu?::point", "two points")
edge("chizu?::buffer", :requires, "chizu?::project", "grow in a flat system")

edge(
  "chizu?::centroid",
  :requires,
  "chizu?::project",
  "average in a flat system"
)

edge(
  "chizu?::contains?",
  :requires,
  "kikagaku::contains?",
  "planar test after project"
)

edge("chizu?::buffer", :requires, "kikagaku::grow", "planar offset")
edge("chizu?::bounds", :requires, "kikagaku::hull", "box around a shape")
edge("chizu?::simplify", :requires, "kikagaku::hull", "shape kept")
edge("chizu?::intersects?", :requires, "kikagaku::intersect", "planar test")
