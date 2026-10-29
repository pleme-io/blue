space("waku", {status: :ratified})

verb(
  "waku",
  "allows?",
  {
    kind: :pure,
    shape: "allows?(frame, name) -> Bool",
    laterals: %w[capability validate],
    fleet: "blue-lang-waku",
    today: "absent",
    meaning: "frame grants one name",
    wave: 1,
    origin: "D"
  }
)

verb(
  "waku",
  "escapes",
  {
    kind: :pure,
    shape: "escapes(frame, program) -> [escape]",
    laterals: %w[capability validate],
    fleet: "blue-lang-waku",
    today: "rust:waku",
    meaning: "names a program uses that its frame does not grant",
    wave: 0,
    origin: "D"
  }
)

verb(
  "waku",
  "frame",
  {
    kind: :decl,
    shape: "frame(reach, when, where) -> frame",
    laterals: %w[capability config],
    fleet: "blue-lang-waku",
    today: "rust:waku",
    meaning: "what a computation may name, depend on and own",
    wave: 0,
    origin: "D"
  }
)

verb(
  "waku",
  "imports",
  {
    kind: :pure,
    shape: "imports(frame) -> [import]",
    laterals: ["capability"],
    fleet: "blue-lang-waku",
    today: "rust:waku",
    meaning: "host imports a frame lowers to",
    wave: 0,
    origin: "D"
  }
)

verb(
  "waku",
  "narrow",
  {
    kind: :pure,
    shape: "narrow(frame, bound) -> frame",
    laterals: %w[capability validate],
    fleet: "blue-lang-waku",
    today: "rust:waku",
    meaning: "meet of two frames; never wider than either",
    wave: 0,
    origin: "D"
  }
)

edge("waku::narrow", :guards, "waku::frame", "narrowing never widens")

edge(
  "waku::narrow",
  :inverse,
  "bunri?::elevate",
  "the only widening, root only"
)

edge(
  "waku::imports",
  :pairs,
  "bunri?::embed",
  "imports are what a module may call"
)

edge("waku::frame", :pairs, "waku::narrow", "frames form a lattice")

edge(
  "waku::allows?",
  :refines,
  "waku::escapes",
  "one name instead of a program"
)

edge("waku::escapes", :requires, "waku::frame", "checked against a frame")
edge("waku::imports", :requires, "waku::frame", "derived from a frame")
