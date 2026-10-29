space("bunpou?", {status: :provisional})

verb(
  "bunpou?",
  "check",
  {
    kind: :pure,
    shape: "check(grammar) -> nil",
    laterals: %w[error validate],
    fleet: nil,
    today: "absent",
    meaning: "refuse left recursion, ambiguity and unused rules",
    wave: 3,
    origin: "A"
  }
)

verb(
  "bunpou?",
  "expected",
  {
    kind: :pure,
    shape: "expected(text, grammar, at) -> [token]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "tokens that could come next at a position",
    wave: 4,
    origin: "A"
  }
)

verb(
  "bunpou?",
  "explain",
  {
    kind: :pure,
    shape: "explain(error) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "why a parse failed, with the nearest rule",
    wave: 3,
    origin: "A"
  }
)

verb(
  "bunpou?",
  "find_all",
  {
    kind: :pure,
    shape: "find_all(text, rule) -> [match]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "every place a rule matches in the text",
    wave: 3,
    origin: "A"
  }
)

verb(
  "bunpou?",
  "generate",
  {
    kind: :pure,
    shape: "generate(grammar, seed, opts) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a sentence of the language, for fuzzing",
    wave: 4,
    origin: "A"
  }
)

verb(
  "bunpou?",
  "grammar",
  {
    kind: :decl,
    shape: "grammar(rules) -> grammar",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare lexer and parser rules as data",
    wave: 2,
    origin: "A"
  }
)

verb(
  "bunpou?",
  "lex",
  {
    kind: :pure,
    shape: "lex(text, lexer) -> [token]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "text to tokens with spans",
    wave: 2,
    origin: "A"
  }
)

verb(
  "bunpou?",
  "lexer",
  {
    kind: :decl,
    shape: "lexer(tokens) -> lexer",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare token kinds by pattern",
    wave: 2,
    origin: "A"
  }
)

verb(
  "bunpou?",
  "matches?",
  {
    kind: :pure,
    shape: "matches?(text, grammar) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether the text is in the grammar's language",
    wave: 2,
    origin: "A"
  }
)

verb(
  "bunpou?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, grammar, opts) -> tree",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "text to a tree; failure names line and column",
    wave: 2,
    origin: "A"
  }
)

verb(
  "bunpou?",
  "render",
  {
    kind: :pure,
    shape: "render(tree, grammar) -> text",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "tree back to text by the same grammar",
    wave: 3,
    origin: "A"
  }
)

verb(
  "bunpou?",
  "spans",
  {
    kind: :pure,
    shape: "spans(text, grammar) -> [span]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "token or node kinds with offsets for highlighting",
    wave: 3,
    origin: "A"
  }
)

edge(
  "bunpou?::explain",
  :composes,
  "bunpou?::expected",
  "nearest rule from the next tokens"
)

edge("bunpou?::parse", :composes, "bunpou?::lex", "rules read tokens")
edge("bunpou?::spans", :composes, "bunpou?::lex", "token kinds with offsets")
edge("bunpou?::grammar", :composes, "bunpou?::lexer", "tokens feed the rules")

edge(
  "bunpou?::expected",
  :composes,
  "bunpou?::parse",
  "failure position gives the next tokens"
)

edge("bunpou?::find_all", :composes, "bunpou?::parse", "parse at each offset")
edge("bunpou?::matches?", :composes, "bunpou?::parse", "parse and test success")

edge(
  "bunpou?::check",
  :composes,
  "gurafu::cycle",
  "left recursion is a rule-graph cycle"
)

edge(
  "bunpou?::generate",
  :composes,
  "kakuritsu?::choice",
  "pick an alternative"
)

edge("bunpou?::lex", :composes, "moji::find", "one pattern per token kind")
edge("bunpou?::lexer", :composes, "moji::pattern", "tokens are patterns")

edge(
  "bunpou?::check",
  :guards,
  "bunpou?::grammar",
  "refuse bad grammars before use"
)

edge("bunpou?::lexer", :guards, "bunpou?::lex", "lex needs a lexer")
edge("bunpou?::render", :inverse, "bunpou?::parse", "tree and text round-trip")
edge("bunpou?::parse", :inverse, "bunpou?::render", "tree and text round-trip")

edge(
  "bunpou?::render",
  :pairs,
  "bunpou?::grammar",
  "printing uses the same rules"
)

edge("bunpou?::explain", :pairs, "bunpou?::parse", "turns a failure into prose")
edge("bunpou?::generate", :pairs, "bunpou?::parse", "produce and recognize")
edge("bunpou?::spans", :pairs, "moji::tokenize", "code versus prose")
edge("bunpou?::matches?", :refines, "bunpou?::parse", "only the verdict")
edge("bunpou?::generate", :requires, "bunpou?::grammar", "walks the rules")

edge(
  "bunpou?::parse",
  :requires,
  "bunpou?::grammar",
  "needs the declared rules"
)
