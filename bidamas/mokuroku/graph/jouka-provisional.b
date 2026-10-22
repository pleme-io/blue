space("jouka?", {status: :provisional})

verb(
  "jouka?",
  "bind",
  {
    kind: :pure,
    shape: "bind(template, params, context) -> command",
    laterals: ["validate"],
    fleet: "kueri",
    today: "absent",
    meaning: "put values into a query or command as data, never code",
    wave: 1,
    origin: "D"
  }
)

verb(
  "jouka?",
  "bound",
  {
    kind: :pure,
    shape: "bound(value, limits) -> value",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "reject input too large, too deep or too long",
    wave: 1,
    origin: "D"
  }
)

verb(
  "jouka?",
  "canonical",
  {
    kind: :pure,
    shape: "canonical(text, form) -> text",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "normalise Unicode, case and encoding before checking",
    wave: 1,
    origin: "D"
  }
)

verb(
  "jouka?",
  "clear",
  {
    kind: :pure,
    shape: "clear(value, check) -> value",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "remove the mark once a check has passed",
    wave: 4,
    origin: "D"
  }
)

verb(
  "jouka?",
  "confusable?",
  {
    kind: :pure,
    shape: "confusable?(a, b) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "two strings look alike but differ (homoglyphs)",
    wave: 2,
    origin: "D"
  }
)

verb(
  "jouka?",
  "contain",
  {
    kind: :pure,
    shape: "contain(root, path) -> path",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "untrusted path under a root; raises :escapes_root",
    wave: 1,
    origin: "D"
  }
)

verb(
  "jouka?",
  "contain_real",
  {
    kind: :effect,
    shape: "contain_real(root, path) -> path",
    laterals: ["error", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "as contain, after resolving links on disk",
    wave: 2,
    origin: "D"
  }
)

verb(
  "jouka?",
  "escape",
  {
    kind: :pure,
    shape: "escape(text, context) -> text",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "make text inert inside HTML, URL, shell, SQL, regex or log",
    wave: 1,
    origin: "D"
  }
)

verb(
  "jouka?",
  "fits?",
  {
    kind: :pure,
    shape: "fits?(value, shape) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "value is inside an allow-list shape: pattern, set, range",
    wave: 1,
    origin: "D"
  }
)

verb(
  "jouka?",
  "hostile",
  {
    kind: :pure,
    shape: "hostile(context) -> [text]",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "known attack strings for a context, for tests",
    wave: 1,
    origin: "D"
  }
)

verb(
  "jouka?",
  "linear?",
  {
    kind: :pure,
    shape: "linear?(pattern) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "pattern cannot blow up on crafted input (ReDoS)",
    wave: 3,
    origin: "D"
  }
)

verb(
  "jouka?",
  "local?",
  {
    kind: :pure,
    shape: "local?(url, host) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "redirect stays on our own host",
    wave: 2,
    origin: "D"
  }
)

verb(
  "jouka?",
  "strip",
  {
    kind: :pure,
    shape: "strip(text, allowed) -> text",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "remove markup and control characters not on the allow-list",
    wave: 1,
    origin: "D"
  }
)

verb(
  "jouka?",
  "taint",
  {
    kind: :pure,
    shape: "taint(value, source) -> value",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "mark a value as coming from outside",
    wave: 4,
    origin: "D"
  }
)

verb(
  "jouka?",
  "vet",
  {
    kind: :effect,
    shape: "vet(url, rules) -> url",
    laterals: ["error", "resource", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "refuse targets inside private, link-local or metadata ranges",
    wave: 2,
    origin: "D"
  }
)

edge("jouka?::vet", :composes, "jouka?::fits?", "address range rules")

edge(
  "jouka?::hostile",
  :guards,
  "bougyo::limits",
  "attack inputs for posture tests"
)

edge("jouka?::contain", :guards, "fairu::write", "safe path before write")

edge(
  "jouka?::bound",
  :guards,
  "fuuin?::open_stream",
  "decompression and chunk limits"
)

edge(
  "jouka?::escape",
  :guards,
  "jouka?::bind",
  "escaping for contexts without binding"
)

edge("jouka?::fits?", :guards, "jouka?::bind", "values checked before binding")

edge(
  "jouka?::canonical",
  :guards,
  "jouka?::contain",
  "normalise before containing"
)

edge("jouka?::bound", :guards, "jouka?::fits?", "size check comes first")
edge("jouka?::canonical", :guards, "jouka?::fits?", "normalise before matching")

edge(
  "jouka?::linear?",
  :guards,
  "moji::pattern",
  "refuse patterns that blow up"
)

edge("jouka?::local?", :guards, "tsuushin::request", "redirect target check")
edge("jouka?::vet", :guards, "tsuushin::request", "check before connecting")
edge("jouka?::strip", :pairs, "jouka?::canonical", "canonicalise then strip")
edge("jouka?::taint", :pairs, "jouka?::clear", "mark then clear")
edge("jouka?::contain", :pairs, "jouka?::contain_real", "lexical then resolved")

edge(
  "jouka?::hostile",
  :pairs,
  "jouka?::escape",
  "tests escape against attacks"
)

edge(
  "jouka?::escape",
  :pairs,
  "jouka?::hostile",
  "hostile strings test escapes"
)

edge(
  "jouka?::contain_real",
  :refines,
  "jouka?::contain",
  "adds link resolution"
)

edge("jouka?::bind", :refines, "jouka?::escape", "structured form of escaping")

edge(
  "jouka?::strip",
  :refines,
  "jouka?::escape",
  "removes instead of neutralising"
)

edge(
  "jouka?::confusable?",
  :requires,
  "jouka?::canonical",
  "compare normalised forms"
)

edge("jouka?::clear", :requires, "jouka?::fits?", "a check clears a mark")
