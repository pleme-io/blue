space("byouga?", {status: :provisional})

verb(
  "byouga?",
  "camera",
  {
    kind: :decl,
    shape: "camera(kind, params) -> camera",
    laterals: ["validate"],
    fleet: "recanto",
    today: "absent",
    meaning: "declare a view: flat, tilted or perspective",
    wave: 2,
    origin: "G"
  }
)

verb(
  "byouga?",
  "capture",
  {
    kind: :effect,
    shape: "capture(surface, opts) -> image",
    laterals: ["resource"],
    fleet: "garasu",
    today: "absent",
    meaning: "draw without a window and return the pixels",
    wave: 3,
    origin: "G"
  }
)

verb(
  "byouga?",
  "check",
  {
    kind: :pure,
    shape: "check(subject, rules) -> findings",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "find a fault in a graph, shader or scene before drawing",
    wave: 2,
    origin: "G"
  }
)

verb(
  "byouga?",
  "compile",
  {
    kind: :pure,
    shape: "compile(graph) -> ordered passes",
    laterals: ["validate"],
    fleet: "engawa-wgpu",
    today: "absent",
    meaning: "order the passes and prove each input is made",
    wave: 2,
    origin: "G"
  }
)

verb(
  "byouga?",
  "composite",
  {
    kind: :pure,
    shape: "composite(layers, mode) -> image",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "layer images with alpha and a blend mode",
    wave: 2,
    origin: "G"
  }
)

verb(
  "byouga?",
  "convert",
  {
    kind: :pure,
    shape: "convert(color, space) -> color",
    laterals: [],
    fleet: "irodori",
    today: "absent",
    meaning: "a color in another space: sRGB, linear, OKLCH",
    wave: 1,
    origin: "G"
  }
)

verb(
  "byouga?",
  "draw",
  {
    kind: :effect,
    shape: "draw(surface, graph, scene) -> frame",
    laterals: %w[deadline resource],
    fleet: "garasu",
    today: "absent",
    meaning: "run the passes and fill the surface",
    wave: 3,
    origin: "G",
    contract: "draw(surface, graph) -> frame"
  }
)

verb(
  "byouga?",
  "graph",
  {
    kind: :decl,
    shape: "graph(passes) -> render graph",
    laterals: ["validate"],
    fleet: "engawa-wgpu",
    today: "absent",
    meaning: "declare passes and the data between them",
    wave: 3,
    origin: "G"
  }
)

verb(
  "byouga?",
  "hit",
  {
    kind: :pure,
    shape: "hit(scene, point) -> node or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the first node under a point or ray",
    wave: 2,
    origin: "G"
  }
)

verb(
  "byouga?",
  "info",
  {
    kind: :pure,
    shape: "info(surface) -> {size, format, frames}",
    laterals: [],
    fleet: "garasu",
    today: "absent",
    meaning: "state of a draw target",
    wave: 3,
    origin: "G"
  }
)

verb(
  "byouga?",
  "material",
  {
    kind: :decl,
    shape: "material(shader, params) -> material",
    laterals: ["validate"],
    fleet: "engawa-wgpu",
    today: "absent",
    meaning: "declare how a surface is shaded",
    wave: 3,
    origin: "G"
  }
)

verb(
  "byouga?",
  "pack",
  {
    kind: :pure,
    shape: "pack(items, size) -> atlas",
    laterals: [],
    fleet: "asobi-text",
    today: "absent",
    meaning: "fit rectangles into one atlas sheet",
    wave: 2,
    origin: "G"
  }
)

verb(
  "byouga?",
  "project",
  {
    kind: :pure,
    shape: "project(camera, point) -> screen point",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a world point as seen on the screen",
    wave: 2,
    origin: "G"
  }
)

verb(
  "byouga?",
  "rasterize",
  {
    kind: :pure,
    shape: "rasterize(shapes, size, opts) -> image",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "draw shapes into pixels on the CPU",
    wave: 3,
    origin: "G"
  }
)

verb(
  "byouga?",
  "render",
  {
    kind: :pure,
    shape: "render(program, target) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "a shader program as WGSL text, built from data",
    wave: 2,
    origin: "G"
  }
)

verb(
  "byouga?",
  "scene",
  {
    kind: :decl,
    shape: "scene(nodes) -> scene",
    laterals: ["validate"],
    fleet: "recanto",
    today: "absent",
    meaning: "declare drawable nodes, layered and posed",
    wave: 2,
    origin: "G"
  }
)

verb(
  "byouga?",
  "shader",
  {
    kind: :decl,
    shape: "shader(stage, program) -> shader",
    laterals: ["validate"],
    fleet: "garasu",
    today: "absent",
    meaning: "declare a shader program as data",
    wave: 3,
    origin: "G"
  }
)

verb(
  "byouga?",
  "shape",
  {
    kind: :pure,
    shape: "shape(text, font, opts) -> glyph run",
    laterals: [],
    fleet: "garasu",
    today: "absent",
    meaning: "text to positioned glyphs for a font",
    wave: 3,
    origin: "G",
    contract: "shape(text) -> glyph run"
  }
)

verb(
  "byouga?",
  "surface",
  {
    kind: :decl,
    shape: "surface(kind, size, opts) -> surface",
    laterals: %w[resource validate],
    fleet: "garasu",
    today: "absent",
    meaning: "declare a draw target: window, offscreen or terminal",
    wave: 3,
    origin: "G"
  }
)

verb(
  "byouga?",
  "tessellate",
  {
    kind: :pure,
    shape: "tessellate(path, tolerance) -> mesh",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a vector path as triangles",
    wave: 2,
    origin: "G"
  }
)

verb(
  "byouga?",
  "unproject",
  {
    kind: :pure,
    shape: "unproject(camera, point) -> ray",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the world ray under a screen point",
    wave: 2,
    origin: "G"
  }
)

edge("byouga?::graph", :composes, "byouga?::material", "passes use materials")

edge(
  "byouga?::hit",
  :composes,
  "byouga?::unproject",
  "ray from the screen point"
)

edge(
  "byouga?::camera",
  :generalizes,
  "byouga?::project",
  "projection comes from a camera"
)

edge(
  "byouga?::shader",
  :generalizes,
  "byouga?::render",
  "WGSL text comes from the program"
)

edge("byouga?::convert", :guards, "byouga?::composite", "blend in linear space")
edge("byouga?::check", :guards, "byouga?::draw", "no draw of a bad graph")
edge("byouga?::unproject", :inverse, "byouga?::project", "screen to world")
edge("byouga?::shader", :inverse, "byouga?::render", "data to text")
edge("byouga?::render", :inverse, "byouga?::shader", "data to text")
edge("byouga?::project", :inverse, "byouga?::unproject", "screen to world")
edge("byouga?::hit", :pairs, "gamen?::send", "a hit becomes an event")
edge("byouga?::surface", :pairs, "gamen?::start", "an app owns a surface")
edge("byouga?::capture", :pairs, "gazou?::diff", "screenshots compared")

edge(
  "byouga?::capture",
  :refines,
  "byouga?::draw",
  "draw offscreen and read back"
)

edge("byouga?::rasterize", :refines, "byouga?::draw", "CPU draw without a GPU")

edge(
  "byouga?::scene",
  :requires,
  "byouga?::camera",
  "a scene is seen by a camera"
)

edge("byouga?::check", :requires, "byouga?::compile", "a plan to verify")
edge("byouga?::draw", :requires, "byouga?::compile", "runs the ordered passes")

edge(
  "byouga?::tessellate",
  :requires,
  "byouga?::draw",
  "the GPU draws triangles"
)

edge("byouga?::compile", :requires, "byouga?::graph", "orders a graph")
edge("byouga?::capture", :requires, "byouga?::info", "size from the surface")
edge("byouga?::surface", :requires, "byouga?::info", "state of the target")
edge("byouga?::shape", :requires, "byouga?::pack", "glyphs sit in an atlas")
edge("byouga?::composite", :requires, "byouga?::rasterize", "layers of pixels")
edge("byouga?::draw", :requires, "byouga?::scene", "draws a scene")

edge(
  "byouga?::material",
  :requires,
  "byouga?::shader",
  "material wraps a shader"
)

edge("byouga?::pack", :requires, "byouga?::shape", "atlas holds glyphs")
edge("byouga?::info", :requires, "byouga?::surface", "reads a surface")

edge(
  "byouga?::convert",
  :requires,
  "gazou?::convert",
  "same color math as images"
)

edge("byouga?::tessellate", :requires, "kikagaku::area", "polygon input")

edge(
  "byouga?::tessellate",
  :requires,
  "rittai::extrude",
  "solids and paths share meshes"
)
