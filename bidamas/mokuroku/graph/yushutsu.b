space("yushutsu", {status: :ratified})

verb(
  "yushutsu",
  "exports",
  {
    kind: :decl,
    shape: "exports() -> rows",
    laterals: [],
    fleet: "arnes",
    today: "rust:yushutsu",
    meaning: "what a hosted package tells arnes it serves",
    wave: 0,
    origin: "G"
  }
)

edge("yushutsu::exports", :pairs, "dairi?::serve", "what a package serves")
edge("yushutsu::exports", :pairs, "meirei::help", "exports list commands")
