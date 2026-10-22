space("ketsugi?", {status: :provisional})

verb(
  "ketsugi?",
  "decide",
  {
    kind: :effect,
    shape: "decide(record, outcome, why) -> record",
    laterals: ["log"],
    fleet: "okite",
    today: "partial:okite",
    meaning: "accept, reject or defer a record, with the reason",
    wave: 3,
    origin: "F"
  }
)

verb(
  "ketsugi?",
  "due?",
  {
    kind: :pure,
    shape: "due?(record, facts) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "whether a revisit trigger has fired",
    wave: 3,
    origin: "F"
  }
)

verb(
  "ketsugi?",
  "enforce",
  {
    kind: :decl,
    shape: "enforce(record, laws) -> row",
    laterals: ["test"],
    fleet: "okite",
    today: "partial:okite",
    meaning: "bind a decision to the laws that keep it true",
    wave: 2,
    origin: "F"
  }
)

verb(
  "ketsugi?",
  "get",
  {
    kind: :effect,
    shape: "get(store, id) -> record or nil",
    laterals: [],
    fleet: nil,
    today: "partial:okite",
    meaning: "one decision record or nil",
    wave: 3,
    origin: "F"
  }
)

verb(
  "ketsugi?",
  "link",
  {
    kind: :effect,
    shape: "link(record, to, kind) -> nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "relate a decision to code, tests or another record",
    wave: 3,
    origin: "F"
  }
)

verb(
  "ketsugi?",
  "list",
  {
    kind: :effect,
    shape: "list(store, filter) -> [record]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "decisions by state, area or date, sorted",
    wave: 3,
    origin: "F",
    contract: "list(store, opts) -> [record]"
  }
)

verb(
  "ketsugi?",
  "propose",
  {
    kind: :effect,
    shape: "propose(title, context, options) -> record",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "write a new decision record in proposed state",
    wave: 3,
    origin: "F"
  }
)

verb(
  "ketsugi?",
  "render",
  {
    kind: :pure,
    shape: "render(record, format) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "a record as a stable document",
    wave: 3,
    origin: "F"
  }
)

verb(
  "ketsugi?",
  "revisit",
  {
    kind: :decl,
    shape: "revisit(record, trigger) -> row",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "name the event or date that reopens a decision",
    wave: 3,
    origin: "F"
  }
)

verb(
  "ketsugi?",
  "supersede",
  {
    kind: :effect,
    shape: "supersede(old, new) -> nil",
    laterals: ["log"],
    fleet: nil,
    today: "absent",
    meaning: "mark a record replaced by a newer one",
    wave: 3,
    origin: "F"
  }
)

edge("ketsugi?::enforce", :composes, "okite::law", "decisions held by laws")
edge("ketsugi?::list", :generalizes, "ketsugi?::get", "many records")
edge("ketsugi?::get", :generalizes, "ketsugi?::list", "one record")

edge(
  "ketsugi?::propose",
  :inverse,
  "ketsugi?::decide",
  "opens and closes a record"
)

edge(
  "ketsugi?::decide",
  :inverse,
  "ketsugi?::propose",
  "opens and closes a record"
)

edge("ketsugi?::render", :inverse, "ketsugi?::propose", "record to document")
edge("ketsugi?::propose", :inverse, "ketsugi?::render", "record to document")
edge("ketsugi?::propose", :pairs, "chishiki?::put", "records live in the wiki")

edge(
  "ketsugi?::link",
  :pairs,
  "kakikae?::deprecate",
  "decisions link to deprecations"
)

edge(
  "ketsugi?::due?",
  :pairs,
  "keikaku?::milestone",
  "revisit dates are milestones"
)

edge("ketsugi?::revisit", :pairs, "ketsugi?::due?", "trigger and its test")
edge("ketsugi?::list", :pairs, "ketsugi?::get", "many versus one")
edge("ketsugi?::supersede", :pairs, "ketsugi?::link", "supersession is a link")
edge("ketsugi?::render", :pairs, "mokuroku::render", "both render docs")
edge("ketsugi?::decide", :pairs, "nisshi::append", "decisions are logged")

edge(
  "ketsugi?::revisit",
  :pairs,
  "shihyou::objective",
  "triggers can be objectives"
)

edge("ketsugi?::link", :pairs, "youken?::trace", "decisions link to needs")

edge(
  "ketsugi?::supersede",
  :refines,
  "ketsugi?::decide",
  "a decision by replacement"
)

edge(
  "ketsugi?::enforce",
  :requires,
  "ketsugi?::decide",
  "enforce accepted records"
)

edge(
  "ketsugi?::decide",
  :requires,
  "ketsugi?::propose",
  "only a proposed record"
)
