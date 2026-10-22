space("rittai", {status: :ratified})

verb(
  "rittai",
  "boolean",
  {
    kind: :pure,
    shape: "boolean(a, b, op) -> mesh",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "union, difference or intersection of solids",
    wave: 4,
    origin: "G"
  }
)

verb(
  "rittai",
  "bounds",
  {
    kind: :pure,
    shape: "bounds(mesh) -> box",
    laterals: [],
    fleet: nil,
    today: "exists:rittai",
    meaning: "smallest axis-aligned box around a mesh",
    wave: 0,
    origin: "A"
  }
)

verb(
  "rittai",
  "centroid",
  {
    kind: :pure,
    shape: "centroid(mesh) -> point",
    laterals: [],
    fleet: nil,
    today: "exists:rittai",
    meaning: "centre of mass of a mesh",
    wave: 0,
    origin: "A"
  }
)

verb(
  "rittai",
  "check",
  {
    kind: :pure,
    shape: "check(mesh) -> findings",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:rittai",
    meaning: "find open edges and flipped faces",
    wave: 0,
    origin: "G"
  }
)

verb(
  "rittai",
  "extrude",
  {
    kind: :pure,
    shape: "extrude(outline, height) -> mesh",
    laterals: [],
    fleet: nil,
    today: "exists:rittai",
    meaning: "outline pulled into a solid",
    wave: 0,
    origin: "A"
  }
)

verb(
  "rittai",
  "measure",
  {
    kind: :pure,
    shape: "measure(mesh, metric) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:rittai",
    meaning: "volume, surface area or mass of a mesh",
    wave: 0,
    origin: "G"
  }
)

verb(
  "rittai",
  "merge",
  {
    kind: :pure,
    shape: "merge(a, b) -> mesh",
    laterals: [],
    fleet: nil,
    today: "exists:rittai",
    meaning: "two meshes as one",
    wave: 0,
    origin: "G"
  }
)

verb(
  "rittai",
  "mesh",
  {
    kind: :pure,
    shape: "mesh(vertices, faces) -> mesh",
    laterals: ["error"],
    fleet: nil,
    today: "exists:rittai",
    meaning: "solid made of triangles",
    wave: 0,
    origin: "A"
  }
)

verb(
  "rittai",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> mesh",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "STL or OBJ text to a mesh",
    wave: 1,
    origin: "G"
  }
)

verb(
  "rittai",
  "render",
  {
    kind: :pure,
    shape: "render(mesh, format) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "exists:rittai",
    meaning: "a mesh as STL text",
    wave: 0,
    origin: "G"
  }
)

verb(
  "rittai",
  "shift",
  {
    kind: :pure,
    shape: "shift(mesh, by) -> mesh",
    laterals: [],
    fleet: nil,
    today: "exists:rittai",
    meaning: "mesh moved by a vector",
    wave: 0,
    origin: "A"
  }
)

verb(
  "rittai",
  "slice",
  {
    kind: :pure,
    shape: "slice(mesh, height) -> region",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the cut of a mesh at a height",
    wave: 1,
    origin: "G",
    contract: "slice(mesh, height, from, to) -> region"
  }
)

verb(
  "rittai",
  "surface_area",
  {
    kind: :pure,
    shape: "surface_area(mesh) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:rittai",
    meaning: "total area of all faces",
    wave: 0,
    origin: "A"
  }
)

verb(
  "rittai",
  "transform",
  {
    kind: :pure,
    shape: "transform(mesh, pose) -> mesh",
    laterals: [],
    fleet: nil,
    today: "exists:rittai",
    meaning: "mesh moved and turned by a pose",
    wave: 0,
    origin: "A"
  }
)

verb(
  "rittai",
  "turn",
  {
    kind: :pure,
    shape: "turn(mesh, axis, angle) -> mesh",
    laterals: [],
    fleet: nil,
    today: "exists:rittai",
    meaning: "mesh turned about an axis",
    wave: 0,
    origin: "A"
  }
)

verb(
  "rittai",
  "volume",
  {
    kind: :pure,
    shape: "volume(mesh) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "exists:rittai",
    meaning: "enclosed volume of a closed mesh",
    wave: 0,
    origin: "A"
  }
)

verb(
  "rittai",
  "weld",
  {
    kind: :pure,
    shape: "weld(mesh, tolerance) -> mesh",
    laterals: [],
    fleet: nil,
    today: "exists:rittai",
    meaning: "merge vertices closer than a tolerance",
    wave: 0,
    origin: "A"
  }
)

edge(
  "rittai::volume",
  :composes,
  "gyouretsu::determinant",
  "signed tetrahedra volumes"
)

edge(
  "rittai::transform",
  :composes,
  "gyouretsu::multiply",
  "a pose is a matrix"
)

edge("rittai::extrude", :composes, "rittai::mesh", "walls and caps")
edge("rittai::transform", :composes, "rittai::turn", "rotate then move")
edge("rittai::centroid", :composes, "rittai::volume", "volume-weighted mean")
edge("rittai::check", :guards, "rittai::boolean", "no solid op on an open mesh")
edge("rittai::mesh", :guards, "rittai::volume", "volume needs a closed mesh")
edge("rittai::weld", :guards, "rittai::volume", "close gaps before measuring")
edge("rittai::slice", :inverse, "rittai::extrude", "solid to its cut region")
edge("rittai::render", :inverse, "rittai::parse", "mesh to text")
edge("rittai::parse", :inverse, "rittai::render", "mesh to text")
edge("rittai::extrude", :inverse, "rittai::slice", "solid to its cut region")
edge("rittai::bounds", :pairs, "rittai::centroid", "box and centre")
edge("rittai::transform", :pairs, "rittai::merge", "move then join")
edge("rittai::volume", :pairs, "rittai::surface_area", "inside and outside")
edge("rittai::render", :refines, "deeta::render", "output is a document")
edge("rittai::bounds", :refines, "kikagaku::bounds", "in three dimensions")
edge("rittai::centroid", :refines, "kikagaku::centroid", "in three dimensions")
edge("rittai::shift", :refines, "rittai::transform", "pose with no turn")
edge("rittai::turn", :refines, "rittai::transform", "pose with no move")
edge("rittai::extrude", :requires, "kikagaku::area", "a region has area")

edge(
  "rittai::measure",
  :requires,
  "rittai::check",
  "only closed meshes have volume"
)

edge("rittai::merge", :requires, "rittai::check", "only valid meshes")
edge("rittai::boolean", :requires, "rittai::merge", "combine solids")
edge("rittai::render", :requires, "rittai::mesh", "needs a closed mesh")
edge("rittai::measure", :requires, "rittai::transform", "measure in world pose")
edge("rittai::slice", :requires, "zumen::project", "slice becomes a drawing")
