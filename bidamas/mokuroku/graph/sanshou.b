space("sanshou", {status: :ratified})

verb(
  "sanshou",
  "paths",
  {
    kind: :pure,
    shape: "paths(prompt) -> paths",
    laterals: [],
    fleet: "arnes",
    today: "rust:sanshou",
    meaning: "file mentions in a prompt, in order",
    wave: 0,
    origin: "G"
  }
)

edge("sanshou::paths", :pairs, "dairi?::call", "mentions become tool calls")
edge("sanshou::paths", :refines, "bunsho?::extract", "mentions as parts")
