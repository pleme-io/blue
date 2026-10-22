space("shuusei", {status: :ratified})

verb(
  "shuusei",
  "deep_merge",
  {
    kind: :pure,
    shape: "deep_merge(a, b) -> value",
    laterals: [],
    fleet: nil,
    today: "exists:shuusei",
    meaning: "maps merge key by key and b replaces the rest",
    wave: 0,
    origin: "H"
  }
)

verb(
  "shuusei",
  "put",
  {
    kind: :pure,
    shape: "put(doc, path, value) -> doc",
    laterals: [],
    fleet: nil,
    today: "exists:shuusei",
    meaning: "doc with value at path; absent map keys are created",
    wave: 0,
    origin: "H"
  }
)
