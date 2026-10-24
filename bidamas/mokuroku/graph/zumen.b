space("zumen", {status: :ratified})

verb(
  "zumen",
  "check",
  {
    kind: :pure,
    shape: "check(sheet) -> findings",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "find overlaps, clipped text and low contrast",
    wave: 2,
    origin: "G"
  }
)

verb(
  "zumen",
  "diagram",
  {
    kind: :decl,
    shape: "diagram(kind, spec) -> sheet",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare a flow, sequence or architecture diagram",
    wave: 2,
    origin: "G"
  }
)

verb(
  "zumen",
  "layout",
  {
    kind: :pure,
    shape: "layout(nodes, edges, opts) -> placed graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "place a graph in layers with routed edges",
    wave: 2,
    origin: "G"
  }
)

verb(
  "zumen",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> sheet",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "DXF text to entities on layers",
    wave: 2,
    origin: "G"
  }
)

verb(
  "zumen",
  "plot",
  {
    kind: :pure,
    shape: "plot(series, opts) -> sheet",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a chart from series: line, bar, scatter",
    wave: 1,
    origin: "G"
  }
)

verb(
  "zumen",
  "project",
  {
    kind: :pure,
    shape: "project(mesh, view) -> sheet",
    laterals: [],
    fleet: nil,
    today: "exists:zumen",
    wave: 0,
    origin: "G"
  }
)

verb(
  "zumen",
  "render",
  {
    kind: :pure,
    shape: "render(sheet, format) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "partial:zumen",
    meaning: "a sheet as SVG or DXF text",
    wave: 0,
    origin: "G"
  }
)

edge("zumen::diagram", :composes, "zumen::layout", "a diagram is laid out")
edge("zumen::plot", :composes, "zumen::render", "a chart is a sheet")
edge("zumen::render", :inverse, "zumen::parse", "text to sheet")
edge("zumen::parse", :inverse, "zumen::render", "text to sheet")
edge("zumen::project", :pairs, "zumen::render", "view then drawing")
edge("zumen::check", :requires, "gamen?::contrast", "chart colors")
edge("zumen::plot", :requires, "gamen?::theme", "chart colors from a theme")
edge("zumen::project", :requires, "rittai::transform", "view is a pose")
edge("zumen::plot", :requires, "toukei::describe", "axes from data range")
edge("zumen::parse", :requires, "zumen::check", "check what was read")
edge("zumen::render", :requires, "zumen::check", "no output with faults")
edge("zumen::layout", :requires, "zumen::diagram", "places a diagram")
