space("kenban", {status: :ratified})

verb(
  "kenban",
  "exports",
  {
    kind: :decl,
    shape: "exports() -> rows",
    laterals: [],
    fleet: "arnes",
    today: "rust:kenban",
    meaning: "default key bindings handed to arnes",
    wave: 0,
    origin: "G"
  }
)

edge("kenban::exports", :pairs, "yushutsu::exports", "how bindings reach arnes")
edge("kenban::exports", :requires, "gamen?::put", "key bindings")
