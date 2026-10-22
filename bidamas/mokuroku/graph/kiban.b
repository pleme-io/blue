space("kiban", {status: :ratified})

verb(
  "kiban",
  "board",
  {
    kind: :decl,
    shape: "board(name) -> board",
    laterals: ["validate"],
    fleet: "blue-native",
    today: "rust:kiban",
    meaning: "a board spec: memory regions and devices",
    wave: 0,
    origin: "G"
  }
)

verb(
  "kiban",
  "device",
  {
    kind: :decl,
    shape: "device(name, kind, base) -> device",
    laterals: ["validate"],
    fleet: "blue-native",
    today: "rust:kiban",
    meaning: "a device on a board, with its base address",
    wave: 0,
    origin: "G"
  }
)

verb(
  "kiban",
  "get",
  {
    kind: :pure,
    shape: "get(board, name) -> device or nil",
    laterals: [],
    fleet: "blue-native",
    today: "rust:kiban",
    meaning: "the base address of a named device",
    wave: 0,
    origin: "G"
  }
)

edge("kiban::board", :generalizes, "kiban::device", "a board holds devices")
edge("kiban::get", :pairs, "kiban::device", "lookup and declaration")
edge("kiban::device", :requires, "kiban::board", "devices sit on a board")
edge("kiban::get", :requires, "kiban::device", "address of a device")
