space("yuugou?", {status: :provisional})

verb(
  "yuugou?",
  "apply",
  {
    kind: :pure,
    shape: "apply(crdt, delta) -> crdt",
    laterals: [],
    fleet: "crdt-doc",
    today: "absent",
    meaning: "merge a delta received from another replica",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "clock",
  {
    kind: :pure,
    shape: "clock() -> vclock",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "an empty version vector",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "compare",
  {
    kind: :pure,
    shape: "compare(a, b) -> before, after, equal or concurrent",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "the causal order of two version vectors",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "concurrent?",
  {
    kind: :pure,
    shape: "concurrent?(a, b) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "whether neither version vector happened before the other",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "converge",
  {
    kind: :effect,
    shape: "converge(replicas, opts) -> crdt",
    laterals: ["cancel", "deadline", "retry"],
    fleet: "crdt-doc",
    today: "absent",
    meaning: "exchange deltas among replicas until all agree",
    wave: 4,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "counter",
  {
    kind: :pure,
    shape: "counter(replica) -> crdt",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a grow and shrink counter owned by one replica",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "delete",
  {
    kind: :pure,
    shape: "delete(crdt, x) -> crdt",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "remove x from a set or map; later adds can win",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "delta",
  {
    kind: :pure,
    shape: "delta(crdt, since) -> delta",
    laterals: [],
    fleet: "crdt-doc",
    today: "absent",
    meaning: "only the updates a replica has not yet seen",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "erase",
  {
    kind: :pure,
    shape: "erase(crdt, from, to) -> crdt",
    laterals: [],
    fleet: "crdt-doc",
    today: "absent",
    meaning: "remove a range of a text crdt",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "get",
  {
    kind: :pure,
    shape: "get(crdt, key) -> value or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "read a register or map key from the merged state",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "has?",
  {
    kind: :pure,
    shape: "has?(crdt, x) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a set holds x or a map holds the key",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "increment",
  {
    kind: :pure,
    shape: "increment(crdt, by) -> crdt",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "add to a counter, negative to subtract",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "insert",
  {
    kind: :pure,
    shape: "insert(crdt, pos, text) -> crdt",
    laterals: [],
    fleet: "crdt-doc",
    today: "absent",
    meaning: "put text at a position in a text crdt",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "map",
  {
    kind: :pure,
    shape: "map(replica) -> crdt",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a map of keys to crdt values",
    wave: 3,
    origin: "B",
    contract: "map(replica, f, opts) -> crdt"
  }
)

verb(
  "yuugou?",
  "merge",
  {
    kind: :pure,
    shape: "merge(a, b) -> crdt",
    laterals: [],
    fleet: "crdt-doc",
    today: "absent",
    meaning: "the join of two states: commutative, associative, idempotent",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "put",
  {
    kind: :pure,
    shape: "put(crdt, key, value) -> crdt",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "set a register or map key, returning the new state",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "register",
  {
    kind: :pure,
    shape: "register(replica, value) -> crdt",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a single value where the latest write wins",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "set",
  {
    kind: :pure,
    shape: "set(replica) -> crdt",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a set where adds and removes both converge",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "text",
  {
    kind: :pure,
    shape: "text(replica, initial) -> crdt",
    laterals: [],
    fleet: "crdt-doc",
    today: "absent",
    meaning: "a sequence of characters edited by many replicas",
    wave: 3,
    origin: "B",
    contract: "text(replica) -> crdt"
  }
)

verb(
  "yuugou?",
  "tick",
  {
    kind: :pure,
    shape: "tick(vclock, replica) -> vclock",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "advance one replica counter in a version vector",
    wave: 3,
    origin: "B"
  }
)

verb(
  "yuugou?",
  "value",
  {
    kind: :pure,
    shape: "value(crdt) -> plain",
    laterals: [],
    fleet: "crdt-doc",
    today: "absent",
    meaning: "the ordinary value the state currently stands for",
    wave: 3,
    origin: "B"
  }
)

edge(
  "yuugou?::converge",
  :composes,
  "yuugou?::apply",
  "applies them everywhere"
)

edge("yuugou?::compare", :composes, "yuugou?::clock", "orders two vectors")

edge(
  "yuugou?::delta",
  :composes,
  "yuugou?::compare",
  "what the other side lacks"
)

edge("yuugou?::converge", :composes, "yuugou?::delta", "exchanges deltas")
edge("yuugou?::apply", :composes, "yuugou?::merge", "delta is merged in")
edge("yuugou?::put", :inverse, "yuugou?::delete", "removes what put set")
edge("yuugou?::insert", :inverse, "yuugou?::erase", "removes inserted text")
edge("yuugou?::erase", :inverse, "yuugou?::insert", "removes inserted text")
edge("yuugou?::delete", :inverse, "yuugou?::put", "removes what put set")
edge("yuugou?::converge", :lifts, "yuugou?::merge", "many replicas")
edge("yuugou?::delta", :pairs, "yuugou?::clock", "delta since a vector")
edge("yuugou?::tick", :pairs, "yuugou?::compare", "advance then order")
edge("yuugou?::apply", :pairs, "yuugou?::delta", "delta out and delta in")
edge("yuugou?::map", :pairs, "yuugou?::get", "keyed read")
edge("yuugou?::put", :pairs, "yuugou?::get", "write and read of a key")
edge("yuugou?::set", :pairs, "yuugou?::has?", "membership test")
edge("yuugou?::counter", :pairs, "yuugou?::increment", "its only operation")
edge("yuugou?::text", :pairs, "yuugou?::insert", "sequence edit")
edge("yuugou?::value", :pairs, "yuugou?::merge", "merged state read as plain")
edge("yuugou?::register", :pairs, "yuugou?::put", "its only operation")
edge("yuugou?::value", :pairs, "yuugou?::text", "plain text of the sequence")
edge("yuugou?::clock", :pairs, "yuugou?::tick", "empty then advanced")
edge("yuugou?::get", :pairs, "yuugou?::value", "one key against the whole")
edge("yuugou?::increment", :pairs, "yuugou?::value", "reads the total")

edge(
  "yuugou?::merge",
  :refines,
  "rekishi?::merge",
  "conflict-free kind of merge"
)

edge(
  "yuugou?::concurrent?",
  :refines,
  "yuugou?::compare",
  "the concurrent case only"
)

edge("yuugou?::has?", :refines, "yuugou?::get", "existence only")
edge("yuugou?::tick", :requires, "yuugou?::clock", "needs a vector")

edge(
  "yuugou?::merge",
  :requires,
  "yuugou?::compare",
  "causal order of the inputs"
)
