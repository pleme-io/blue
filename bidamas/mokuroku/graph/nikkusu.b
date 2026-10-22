space("nikkusu", {status: :ratified})

verb(
  "nikkusu",
  "find",
  {
    kind: :pure,
    shape: "find(tree, query) -> [node]",
    laterals: [],
    fleet: "nikkusu",
    today: "exists:nikkusu",
    meaning: "nodes matching a call head, attrpath or path",
    wave: 0,
    origin: "E"
  }
)

verb(
  "nikkusu",
  "get",
  {
    kind: :pure,
    shape: "get(tree, attrpath) -> node or nil",
    laterals: [],
    fleet: "nikkusu",
    today: "exists:nikkusu",
    meaning: "the binding at an attribute path",
    wave: 0,
    origin: "E"
  }
)

verb(
  "nikkusu",
  "parse",
  {
    kind: :pure,
    shape: "parse(text) -> tree",
    laterals: ["error"],
    fleet: "nikkusu",
    today: "exists:nikkusu",
    meaning: "nix source as a lossless tree",
    wave: 0,
    origin: "E"
  }
)

verb(
  "nikkusu",
  "render",
  {
    kind: :pure,
    shape: "render(tree) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "nix source back from a tree, comments kept",
    wave: 2,
    origin: "E"
  }
)

edge("nikkusu::get", :composes, "nikkusu::find", "one match by path")
edge("nikkusu::render", :inverse, "nikkusu::parse", "text to tree and back")
edge("nikkusu::parse", :inverse, "nikkusu::render", "text to tree and back")
edge("nikkusu::find", :refines, "core::find", "search a tree")
edge("nikkusu::get", :refines, "core::get", "nil when no binding")
edge("nikkusu::render", :refines, "core::render", "tree to source")
edge("nikkusu::find", :requires, "nikkusu::parse", "queries a tree")
edge("nikkusu::get", :requires, "nikkusu::parse", "reads a tree")
