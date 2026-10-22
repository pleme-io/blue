space("shikibetsu?", {status: :provisional})

verb(
  "shikibetsu?",
  "compare",
  {
    kind: :pure,
    shape: "compare(a, b) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "order two ids; time-ordered ids sort by time",
    wave: 1,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "derive",
  {
    kind: :pure,
    shape: "derive(kind, namespace, name) -> id",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "same id every time for the same name",
    wave: 1,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "kind",
  {
    kind: :pure,
    shape: "kind(id) -> symbol",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "which scheme an id belongs to",
    wave: 1,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "make",
  {
    kind: :effect,
    shape: "make(kind, opts) -> id",
    laterals: ["capability"],
    fleet: "tatara-lisp-script",
    today: "absent",
    meaning: "new uuid, ulid, nanoid or similar id",
    wave: 1,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "nil_id",
  {
    kind: :pure,
    shape: "nil_id(kind) -> id",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the all-zero id of a kind",
    wave: 1,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "obscure",
  {
    kind: :pure,
    shape: "obscure(number, salt) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "integer to a short reversible public id",
    wave: 3,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text) -> id",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "text to an id; a malformed one raises",
    wave: 1,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "render",
  {
    kind: :pure,
    shape: "render(id, format) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "id as canonical, compact or URN text",
    wave: 1,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "reveal",
  {
    kind: :pure,
    shape: "reveal(text, salt) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "undo obscure with the same salt",
    wave: 3,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "short",
  {
    kind: :pure,
    shape: "short(id, n) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "first n characters, for display only",
    wave: 1,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "timestamp",
  {
    kind: :pure,
    shape: "timestamp(id) -> instant or nil",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "the time inside a time-ordered id",
    wave: 2,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "valid?",
  {
    kind: :pure,
    shape: "valid?(text, kind) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "whether text is a well-formed id of a kind",
    wave: 1,
    origin: "A"
  }
)

verb(
  "shikibetsu?",
  "version",
  {
    kind: :pure,
    shape: "version(id) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "uuid version number",
    wave: 1,
    origin: "A"
  }
)

edge("shikibetsu?::obscure", :composes, "deeta::encode", "encode with the salt")

edge(
  "shikibetsu?::render",
  :composes,
  "deeta::encode",
  "compact forms use base encodings"
)

edge("shikibetsu?::timestamp", :composes, "jikan::instant", "build the instant")
edge("shikibetsu?::make", :composes, "jikan::now", "time-ordered kinds")
edge("shikibetsu?::make", :composes, "kakuritsu?::entropy", "random bits")
edge("shikibetsu?::valid?", :composes, "moji::matches?", "format pattern")

edge(
  "shikibetsu?::short",
  :composes,
  "shikibetsu?::render",
  "prefix of the text"
)

edge(
  "shikibetsu?::compare",
  :composes,
  "shikibetsu?::timestamp",
  "time-ordered kinds sort by time"
)

edge(
  "shikibetsu?::derive",
  :composes,
  "shomei::hash",
  "name-based ids are hashes"
)

edge(
  "shikibetsu?::valid?",
  :guards,
  "shikibetsu?::parse",
  "test before parsing"
)

edge("shikibetsu?::reveal", :inverse, "shikibetsu?::obscure", "undoes obscure")

edge(
  "shikibetsu?::render",
  :inverse,
  "shikibetsu?::parse",
  "text and id round-trip"
)

edge(
  "shikibetsu?::parse",
  :inverse,
  "shikibetsu?::render",
  "text and id round-trip"
)

edge("shikibetsu?::obscure", :inverse, "shikibetsu?::reveal", "undoes obscure")
edge("shikibetsu?::derive", :pairs, "shikibetsu?::make", "stable versus fresh")

edge(
  "shikibetsu?::make",
  :pairs,
  "shikibetsu?::short",
  "full id versus display id"
)

edge("shikibetsu?::compare", :pairs, "shikibetsu?::timestamp", "time order")
edge("shikibetsu?::version", :refines, "shikibetsu?::kind", "uuid version")
edge("shikibetsu?::nil_id", :refines, "shikibetsu?::make", "the fixed id")

edge(
  "shikibetsu?::timestamp",
  :requires,
  "shikibetsu?::kind",
  "only time-ordered kinds"
)

edge(
  "shikibetsu?::kind",
  :requires,
  "shikibetsu?::parse",
  "read the scheme from the text"
)
