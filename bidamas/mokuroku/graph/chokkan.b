space("chokkan", {status: :ratified})

verb(
  "chokkan",
  "ask",
  {
    kind: :decl,
    shape: "ask(name, question) -> question",
    laterals: [],
    fleet: "arnes",
    today: "exists:chokkan",
    wave: 0,
    origin: "G"
  }
)

verb(
  "chokkan",
  "choice",
  {
    kind: :decl,
    shape: "choice(instructions, options) -> question",
    laterals: [],
    fleet: "arnes",
    today: "exists:chokkan",
    wave: 0,
    origin: "G"
  }
)

verb(
  "chokkan",
  "request",
  {
    kind: :pure,
    shape: "request(model, state, questions) -> request",
    laterals: [],
    fleet: "arnes",
    today: "exists:chokkan",
    wave: 0,
    origin: "G",
    contract: "request(model, state, opts) -> request"
  }
)

verb(
  "chokkan",
  "score",
  {
    kind: :decl,
    shape: "score(instructions, levels) -> question",
    laterals: [],
    fleet: "arnes",
    today: "exists:chokkan",
    wave: 0,
    origin: "G"
  }
)

edge("chokkan::score", :composes, "chokkan::ask", "a scored question")

edge(
  "chokkan::ask",
  :composes,
  "chokkan::choice",
  "a question is a choice or a score"
)

edge("chokkan::ask", :pairs, "chokkan::request", "questions go in a request")
edge("chokkan::choice", :refines, "chokkan::ask", "a closed question")
edge("chokkan::choice", :refines, "mokei?::classify", "closed answers")
edge("chokkan::score", :refines, "saiten?::score", "numbered levels")
edge("chokkan::request", :requires, "mokei?::ask", "the call that carries it")
