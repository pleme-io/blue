space("joutai", {status: :ratified})

verb(
  "joutai",
  "segment",
  {
    kind: :pure,
    shape: "segment(text) -> segment",
    laterals: [],
    fleet: "arnes",
    today: "rust:joutai",
    meaning: "one piece of the status line",
    wave: 0,
    origin: "G"
  }
)

edge("joutai::segment", :requires, "dairi?::run", "status shows run state")
edge("joutai::segment", :requires, "gamen?::paint", "status text is painted")
