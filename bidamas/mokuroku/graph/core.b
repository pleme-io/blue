space("core", {status: :ratified})

verb(
  "core",
  "check",
  {
    kind: :effect,
    shape: "check(subject, rules?, opts) -> [finding]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "findings of a subject against rules; empty when sound; kyohi::enforce is the raising form",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "copy",
  {
    kind: :effect,
    shape: "copy(from, to, opts) -> nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "place a copy at a destination",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "create",
  {
    kind: :effect,
    shape: "create(store, key, value, opts) -> value",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "add a new entry; refuse to overwrite",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "delete",
  {
    kind: :effect,
    shape: "delete(store, key, opts) -> nil",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "make the entry absent; absent counts as done",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "diff",
  {
    kind: :effect,
    shape: "diff(a, b, opts) -> [change]",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "differences between two values as change records",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "exists?",
  {
    kind: :effect,
    shape: "exists?(subject, opts) -> Bool",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "whether the subject is there; never raises",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "find",
  {
    kind: :effect,
    shape: "find(subject, query, opts) -> item or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the first match of a query or predicate, else nil",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "flat_map",
  {
    kind: :pure,
    shape: "flat_map(xs, f) -> list",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "map then flatten one level",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "get",
  {
    kind: :effect,
    shape: "get(store, key, opts) -> value or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "one entry, nil when absent",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "group_by",
  {
    kind: :pure,
    shape: "group_by(xs, f) -> map",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "items grouped under f of each",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "has?",
  {
    kind: :effect,
    shape: "has?(store, key) -> Bool",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "whether the key is present",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "info",
  {
    kind: :effect,
    shape: "info(subject, opts) -> record",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "current state of the subject as a record",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "list",
  {
    kind: :effect,
    shape: "list(store, opts) -> [record]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "every entry, all pages, sorted",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "merge",
  {
    kind: :effect,
    shape: "merge(a, b, opts) -> value",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "combine b into a; one master verb for every space, gitto::merge refines it",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "move",
  {
    kind: :effect,
    shape: "move(from, to, opts) -> nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "move or rename atomically",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "need",
  {
    kind: :effect,
    shape: "need(store, key, opts) -> value",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "one entry, raising when absent",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format?, opts) -> value",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "text to a value",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "plan",
  {
    kind: :pure,
    shape: "plan(subject, target?, opts) -> [action]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "what the verb would do, as data, changing nothing",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "put",
  {
    kind: :effect,
    shape: "put(store, key, value, opts) -> value",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "create or replace an entry",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "read",
  {
    kind: :effect,
    shape: "read(source, opts) -> content",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "whole content of a source",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "render",
  {
    kind: :pure,
    shape: "render(value, format?, opts) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a value to canonical stable text",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "run",
  {
    kind: :effect,
    shape: "run(subject, input?, opts) -> result",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "run to completion and return the result",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "update",
  {
    kind: :effect,
    shape: "update(store, key, f, opts) -> value",
    laterals: [],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "replace an entry with f of the old value",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "verify",
  {
    kind: :effect,
    shape: "verify(subject, policy?, opts) -> verdict",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "check integrity against a record or policy; raises tampered on a bad verdict, verify? is the predicate pair",
    wave: 0,
    origin: "H"
  }
)

verb(
  "core",
  "verify?",
  {
    kind: :pure,
    shape: "verify?(data, signature?, key?) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a signature or proof holds",
    wave: 0,
    origin: "H"
  }
)

edge(
  "core::verify",
  :pairs,
  "core::verify?",
  "verify raises tampered; verify? answers Bool"
)
