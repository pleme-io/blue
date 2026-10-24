space("kiwari", {status: :ratified})

verb(
  "kiwari",
  "check",
  {
    kind: :pure,
    shape: "check(grammar) -> [problem]",
    laterals: ["validate"],
    fleet: "blue-lang-kiwari",
    today: "partial:kiwari",
    meaning: "ambiguity, unused rules and missing closers",
    wave: 1,
    origin: "F"
  }
)

verb(
  "kiwari",
  "choice",
  {
    kind: :decl,
    shape: "choice(items) -> expr",
    laterals: [],
    fleet: "blue-lang-kiwari",
    today: "exists:kiwari",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kiwari",
  "field",
  {
    kind: :decl,
    shape: "field(name, item) -> expr",
    laterals: [],
    fleet: "blue-lang-kiwari",
    today: "exists:kiwari",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kiwari",
  "lit",
  {
    kind: :decl,
    shape: "lit(text) -> expr",
    laterals: [],
    fleet: "blue-lang-kiwari",
    today: "exists:kiwari",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kiwari",
  "literals",
  {
    kind: :pure,
    shape: "literals(grammar) -> [text]",
    laterals: [],
    fleet: "blue-lang-kiwari",
    today: "exists:kiwari",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kiwari",
  "opt",
  {
    kind: :decl,
    shape: "opt(item) -> expr",
    laterals: [],
    fleet: "blue-lang-kiwari",
    today: "exists:kiwari",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kiwari",
  "render",
  {
    kind: :pure,
    shape: "render(grammar, target) -> text",
    laterals: ["serialize"],
    fleet: "blue-lang-kiwari",
    today: "exists:kiwari",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kiwari",
  "rep",
  {
    kind: :decl,
    shape: "rep(item) -> expr",
    laterals: [],
    fleet: "blue-lang-kiwari",
    today: "exists:kiwari",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kiwari",
  "rule",
  {
    kind: :decl,
    shape: "rule(name, body, lower) -> rule",
    laterals: ["validate"],
    fleet: "blue-lang-kiwari",
    today: "exists:kiwari",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kiwari",
  "seq",
  {
    kind: :decl,
    shape: "seq(items) -> expr",
    laterals: [],
    fleet: "blue-lang-kiwari",
    today: "exists:kiwari",
    wave: 0,
    origin: "F"
  }
)

edge("kiwari::literals", :composes, "kiwari::lit", "collects them")
edge("kiwari::lit", :generalizes, "kiwari::field", "plain text part")
edge("kiwari::seq", :pairs, "kiwari::choice", "two ways to combine")
edge("kiwari::rep", :pairs, "kiwari::literals", "repeat and its tokens")
edge("kiwari::choice", :pairs, "kiwari::opt", "opt is choice with nothing")
edge("kiwari::seq", :pairs, "kiwari::rep", "sequence with repeat")
edge("kiwari::rule", :pairs, "koubun?::grammar", "a rule set is a grammar")
edge("kiwari::literals", :pairs, "koubun?::highlight", "keywords get a role")
edge("kiwari::render", :pairs, "koubun?::highlight", "emits highlight roles")
edge("kiwari::lit", :pairs, "koubun?::lex", "literals become tokens")
edge("kiwari::check", :pairs, "tesuto?::run", "grammar corpus is a test")
edge("kiwari::opt", :refines, "kiwari::choice", "choice of item or nothing")
edge("kiwari::field", :refines, "kiwari::lit", "a named part")
edge("kiwari::rep", :refines, "kiwari::opt", "zero or many")
edge("kiwari::render", :requires, "kiwari::check", "only a checked grammar")
edge("kiwari::check", :requires, "kiwari::rule", "checks all rules")
edge("kiwari::rule", :requires, "kiwari::seq", "bodies are built from forms")
