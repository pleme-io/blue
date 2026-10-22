space("wariate", {status: :ratified})

verb(
  "wariate",
  "decide",
  {
    kind: :pure,
    shape: "decide(facts, judged, memory) -> decision",
    laterals: [],
    fleet: "arnes",
    today: "rust:wariate",
    meaning: "which model route answers the next turn, and why",
    wave: 0,
    origin: "G"
  }
)

verb(
  "wariate",
  "eligible",
  {
    kind: :pure,
    shape: "eligible(facts, judged) -> routes",
    laterals: [],
    fleet: "arnes",
    today: "rust:wariate",
    meaning: "routes that fit the window, tools and price",
    wave: 0,
    origin: "G"
  }
)

verb(
  "wariate",
  "explain",
  {
    kind: :pure,
    shape: "explain(memory) -> text",
    laterals: [],
    fleet: "arnes",
    today: "rust:wariate",
    meaning: "say why the last route was picked",
    wave: 0,
    origin: "G"
  }
)

verb(
  "wariate",
  "gate",
  {
    kind: :pure,
    shape: "gate(facts, judged, m, e, pick, why) -> decision",
    laterals: [],
    fleet: "arnes",
    today: "rust:wariate",
    meaning: "admit a route change or refuse it",
    wave: 0,
    origin: "G",
    contract: "gate(facts, judged) -> decision"
  }
)

edge("wariate::gate", :guards, "wariate::decide", "admit or refuse a change")
edge("wariate::explain", :pairs, "joutai::segment", "reason shown in status")

edge(
  "wariate::eligible",
  :requires,
  "moderu?::info",
  "window and price per route"
)

edge("wariate::explain", :requires, "wariate::decide", "says why")

edge(
  "wariate::decide",
  :requires,
  "wariate::eligible",
  "choose among eligible routes"
)

edge("wariate::gate", :requires, "wariate::eligible", "only eligible routes")
