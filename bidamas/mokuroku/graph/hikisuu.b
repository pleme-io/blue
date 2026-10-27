space("hikisuu", {status: :ratified})

verb(
  "hikisuu",
  "command",
  {
    kind: :effect,
    shape: "command(spec, f) -> value",
    laterals: [],
    fleet: "clap",
    today: "exists:hikisuu",
    meaning: "the program's door: help, completion and a usage refusal, else f called with the parsed record",
    wave: 0,
    origin: "G"
  }
)

verb(
  "hikisuu",
  "complete",
  {
    kind: :pure,
    shape: "complete(args, spec) -> [text]",
    laterals: [],
    fleet: "clap",
    today: "exists:hikisuu",
    meaning: "the words that may follow a partial command line",
    wave: 0,
    origin: "G"
  }
)

verb(
  "hikisuu",
  "parse",
  {
    kind: :pure,
    shape: "parse(args, spec) -> record",
    laterals: [],
    fleet: "clap",
    today: "exists:hikisuu",
    meaning: "a command line read by a spec into one record, every fault one usage error",
    wave: 0,
    origin: "G"
  }
)

verb(
  "hikisuu",
  "render",
  {
    kind: :pure,
    shape: "render(spec, command) -> text",
    laterals: [],
    fleet: "clap",
    today: "exists:hikisuu",
    meaning: "the help text of a spec or one of its commands",
    wave: 0,
    origin: "G"
  }
)
