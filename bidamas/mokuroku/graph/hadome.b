space("hadome", {status: :ratified})

verb(
  "hadome",
  "failures",
  {
    kind: :pure,
    shape: "failures(rows, kind, measurements) -> [failure]",
    laterals: ["test"],
    fleet: nil,
    today: "exists:hadome",
    wave: 0,
    origin: "F"
  }
)

verb(
  "hadome",
  "judge",
  {
    kind: :pure,
    shape: "judge(rows, kind, key, measured) -> verdict",
    laterals: ["test"],
    fleet: nil,
    today: "exists:hadome",
    wave: 0,
    origin: "F",
    contract: "judge(rows, kind, key, opts) -> verdict"
  }
)

verb(
  "hadome",
  "orphans",
  {
    kind: :pure,
    shape: "orphans(rows, kind, live) -> [key]",
    laterals: ["test"],
    fleet: nil,
    today: "exists:hadome",
    wave: 0,
    origin: "F"
  }
)

verb(
  "hadome",
  "parse",
  {
    kind: :pure,
    shape: "parse(text) -> [row]",
    laterals: ["serialize"],
    fleet: nil,
    today: "exists:hadome",
    wave: 0,
    origin: "F"
  }
)

verb(
  "hadome",
  "render",
  {
    kind: :pure,
    shape: "render(kind, measurements) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "exists:hadome",
    wave: 0,
    origin: "F"
  }
)

verb(
  "hadome",
  "shrunk",
  {
    kind: :pure,
    shape: "shrunk(rows, kind, measurements) -> [key]",
    laterals: ["test"],
    fleet: nil,
    today: "exists:hadome",
    wave: 0,
    origin: "F"
  }
)

verb(
  "hadome",
  "tighten",
  {
    kind: :pure,
    shape: "tighten(rows, kind, measurements) -> [row]",
    laterals: ["migrate", "test"],
    fleet: nil,
    today: "partial:hadome",
    meaning: "rows lowered to the new sizes, never raised",
    wave: 1,
    origin: "F"
  }
)

verb(
  "hadome",
  "waive",
  {
    kind: :decl,
    shape: "waive(key, reason, until) -> row",
    laterals: ["switch"],
    fleet: nil,
    today: "absent",
    meaning: "a dated, reasoned exception to a ratchet",
    wave: 1,
    origin: "F"
  }
)

edge("hadome::failures", :composes, "hadome::judge", "judge each key")
edge("hadome::shrunk", :composes, "hadome::judge", "keys that fell")
edge("hadome::tighten", :composes, "hadome::shrunk", "lowers recorded sizes")

edge(
  "hadome::waive",
  :guards,
  "hadome::failures",
  "a waiver turns a failure off"
)

edge("hadome::render", :inverse, "hadome::parse", "file to rows and back")
edge("hadome::parse", :inverse, "hadome::render", "file to rows and back")
edge("hadome::judge", :pairs, "hadome::failures", "one key versus all keys")
edge("hadome::shrunk", :pairs, "hadome::orphans", "both lower the file")

edge(
  "hadome::orphans",
  :pairs,
  "hadome::tighten",
  "stale rows removed together"
)

edge(
  "hadome::render",
  :pairs,
  "hadome::tighten",
  "tighten writes rendered rows"
)

edge("hadome::tighten", :pairs, "kaihatsu?::gate", "gate refuses growth")
edge("hadome::failures", :pairs, "kenshutsu?::census", "census input")

edge(
  "hadome::waive",
  :pairs,
  "kenshutsu?::census",
  "census counts the ratchets"
)

edge("hadome::waive", :requires, "hadome::judge", "waives a judged key")
edge("hadome::judge", :requires, "hadome::parse", "against recorded rows")
