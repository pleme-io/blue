space("meirei", {status: :ratified})

verb(
  "meirei",
  "help",
  {
    kind: :effect,
    shape: "help(args) -> nil",
    laterals: [],
    fleet: "arnes",
    today: "rust:meirei",
    meaning: "a built-in slash command that lists commands",
    wave: 0,
    origin: "G"
  }
)

edge("meirei::help", :refines, "gamen?::show", "a command that prints")
edge("meirei::help", :requires, "gamen?::show", "prints through show")
