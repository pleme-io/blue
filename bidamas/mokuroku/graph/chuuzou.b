space("chuuzou", {status: :ratified})

verb(
  "chuuzou",
  "assemble",
  {
    kind: :effect,
    shape: "assemble(ast, board) -> image",
    laterals: ["process"],
    fleet: "blue-native",
    today: "rust:chuuzou",
    meaning: "link emitted code into a board image",
    wave: 0,
    origin: "G"
  }
)

verb(
  "chuuzou",
  "build",
  {
    kind: :effect,
    shape: "build(program, board) -> image",
    laterals: ["process", "resource"],
    fleet: "blue-native",
    today: "rust:chuuzou",
    meaning: "emit, link and measure one board image",
    wave: 2,
    origin: "G"
  }
)

verb(
  "chuuzou",
  "emit",
  {
    kind: :pure,
    shape: "emit(program) -> Rust AST",
    laterals: ["validate"],
    fleet: "blue-native",
    today: "rust:chuuzou",
    meaning: "a checked program as a typed Rust AST",
    wave: 2,
    origin: "G"
  }
)

verb(
  "chuuzou",
  "measure",
  {
    kind: :pure,
    shape: "measure(image) -> {text, data, ram}",
    laterals: [],
    fleet: "blue-native",
    today: "rust:chuuzou",
    meaning: "code and data size of an image",
    wave: 0,
    origin: "G"
  }
)

edge("chuuzou::build", :composes, "chuuzou::assemble", "then link")
edge("chuuzou::build", :composes, "chuuzou::emit", "emit first")
edge("chuuzou::build", :composes, "chuuzou::measure", "then measure")
edge("chuuzou::measure", :guards, "chuuzou::build", "size within the region")
edge("chuuzou::assemble", :requires, "chuuzou::emit", "links emitted code")
edge("chuuzou::emit", :requires, "kiban::board", "specialised to a board")
