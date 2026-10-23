space("seimei", {status: :ratified})

verb(
  "seimei",
  "advance",
  {
    kind: :pure,
    shape: "advance(grid, rule) -> grid",
    laterals: [],
    fleet: nil,
    today: "exists:seimei",
    meaning: "one generation of a cellular automaton",
    wave: 0,
    origin: "G"
  }
)

edge("seimei::advance", :pairs, "ran::draw", "seeded rules")
edge("seimei::advance", :refines, "waarudo?::advance", "a grid world step")
