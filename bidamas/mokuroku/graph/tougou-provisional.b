space("tougou?", {status: :provisional})

verb(
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
  "converge",
  {
    kind: :effect,
    shape: "converge(replicas, opts) -> crdt",
    laterals: %w[cancel deadline retry],
    fleet: "crdt-doc",
    today: "absent",
    meaning: "exchange deltas among replicas until all agree",
    wave: 4,
    origin: "B"
  }
)

verb(
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?",
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
  "tougou?::converge",
  :composes,
  "tougou?::apply",
  "applies them everywhere"
)

edge("tougou?::compare", :composes, "tougou?::clock", "orders two vectors")

edge(
  "tougou?::delta",
  :composes,
  "tougou?::compare",
  "what the other side lacks"
)

edge("tougou?::converge", :composes, "tougou?::delta", "exchanges deltas")
edge("tougou?::apply", :composes, "tougou?::merge", "delta is merged in")
edge("tougou?::put", :inverse, "tougou?::delete", "removes what put set")
edge("tougou?::insert", :inverse, "tougou?::erase", "removes inserted text")
edge("tougou?::erase", :inverse, "tougou?::insert", "removes inserted text")
edge("tougou?::delete", :inverse, "tougou?::put", "removes what put set")
edge("tougou?::converge", :lifts, "tougou?::merge", "many replicas")
edge("tougou?::delta", :pairs, "tougou?::clock", "delta since a vector")
edge("tougou?::tick", :pairs, "tougou?::compare", "advance then order")
edge("tougou?::apply", :pairs, "tougou?::delta", "delta out and delta in")
edge("tougou?::map", :pairs, "tougou?::get", "keyed read")
edge("tougou?::put", :pairs, "tougou?::get", "write and read of a key")
edge("tougou?::set", :pairs, "tougou?::has?", "membership test")
edge("tougou?::counter", :pairs, "tougou?::increment", "its only operation")
edge("tougou?::text", :pairs, "tougou?::insert", "sequence edit")
edge("tougou?::value", :pairs, "tougou?::merge", "merged state read as plain")
edge("tougou?::register", :pairs, "tougou?::put", "its only operation")
edge("tougou?::value", :pairs, "tougou?::text", "plain text of the sequence")
edge("tougou?::clock", :pairs, "tougou?::tick", "empty then advanced")
edge("tougou?::get", :pairs, "tougou?::value", "one key against the whole")
edge("tougou?::increment", :pairs, "tougou?::value", "reads the total")

edge(
  "tougou?::merge",
  :refines,
  "rekishi?::merge",
  "conflict-free kind of merge"
)

edge(
  "tougou?::concurrent?",
  :refines,
  "tougou?::compare",
  "the concurrent case only"
)

edge("tougou?::has?", :refines, "tougou?::get", "existence only")
edge("tougou?::tick", :requires, "tougou?::clock", "needs a vector")

edge(
  "tougou?::merge",
  :requires,
  "tougou?::compare",
  "causal order of the inputs"
)
