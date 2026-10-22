space("kenkou", {status: :ratified})

verb(
  "kenkou",
  "tick",
  {
    kind: :pure,
    shape: "tick(facts) -> facts",
    laterals: [],
    fleet: "arnes",
    today: "rust:kenkou",
    meaning: "one MCP health probe step",
    wave: 0,
    origin: "G"
  }
)

edge("kenkou::tick", :pairs, "joutai::segment", "health shown in status")
edge("kenkou::tick", :requires, "dairi?::list", "probes a server")
