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
    wave: 0,
    origin: "H"
  }
)
