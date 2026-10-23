space("waarudo?", {status: :provisional})

verb(
  "waarudo?",
  "advance",
  {
    kind: :effect,
    shape: "advance(world, dt) -> world",
    laterals: ["time"],
    fleet: "asobi-ecs",
    today: "partial:seimei",
    meaning: "one fixed time step of every system",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "arrange",
  {
    kind: :pure,
    shape: "arrange(systems) -> order",
    laterals: ["validate"],
    fleet: "asobi-ecs",
    today: "absent",
    meaning: "order systems so no two clash on a write",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "body",
  {
    kind: :decl,
    shape: "body(shape, mass, opts) -> body",
    laterals: ["validate"],
    fleet: "zairyo",
    today: "absent",
    meaning: "declare a rigid body: shape, mass, material",
    wave: 3,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "check",
  {
    kind: :pure,
    shape: "check(world, invariants) -> findings",
    laterals: ["test", "validate"],
    fleet: "zairyo",
    today: "absent",
    meaning: "find a broken law: leaked energy, mass or entity",
    wave: 2,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "collide",
  {
    kind: :pure,
    shape: "collide(a, b) -> contact or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the contact of two bodies, if they touch",
    wave: 3,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "delete",
  {
    kind: :effect,
    shape: "delete(world, entity) -> nil",
    laterals: ["idempotent"],
    fleet: "asobi-ecs",
    today: "absent",
    meaning: "remove an entity; absent counts as done",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "field",
  {
    kind: :pure,
    shape: "field(kind, seed, point) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "smooth value noise at a point: gradient, simplex, cell",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "generate",
  {
    kind: :pure,
    shape: "generate(grammar, seed, opts) -> content",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "build a level, name or map from rules and a seed",
    wave: 2,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "get",
  {
    kind: :pure,
    shape: "get(world, entity, kind) -> component or nil",
    laterals: [],
    fleet: "asobi-ecs",
    today: "absent",
    meaning: "read one component; nil if absent",
    wave: 1,
    origin: "G",
    contract: "get(world, entity, opts) -> component or nil"
  }
)

verb(
  "waarudo?",
  "grammar",
  {
    kind: :decl,
    shape: "grammar(rules) -> grammar",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare production rules or tile constraints",
    wave: 2,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "hit",
  {
    kind: :pure,
    shape: "hit(world, ray) -> entity or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the first entity that a ray meets",
    wave: 3,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "on",
  {
    kind: :decl,
    shape: "on(world, event, handler) -> world",
    laterals: [],
    fleet: "asobi-ecs",
    today: "absent",
    meaning: "bind a handler to a world event",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "path",
  {
    kind: :pure,
    shape: "path(graph, from, to, opts) -> steps",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the cheapest steps from one cell to another",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "put",
  {
    kind: :effect,
    shape: "put(world, entity, component) -> nil",
    laterals: [],
    fleet: "asobi-ecs",
    today: "absent",
    meaning: "set one component on an entity",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "query",
  {
    kind: :pure,
    shape: "query(world, shape) -> rows",
    laterals: [],
    fleet: "asobi-ecs",
    today: "absent",
    meaning: "entities that carry the listed components",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "read",
  {
    kind: :effect,
    shape: "read(src, opts) -> world",
    laterals: ["resource"],
    fleet: "asobi-save",
    today: "absent",
    meaning: "load a saved world, version and checksum checked",
    wave: 2,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "replay",
  {
    kind: :effect,
    shape: "replay(world, log) -> world",
    laterals: ["test", "trace"],
    fleet: "asobi-net-rollback",
    today: "absent",
    meaning: "re-run recorded inputs; same seed, same world",
    wave: 2,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "rollback",
  {
    kind: :effect,
    shape: "rollback(world, tick, inputs) -> world",
    laterals: [],
    fleet: "asobi-net-rollback",
    today: "absent",
    meaning: "return to an earlier tick and replay the inputs",
    wave: 3,
    origin: "G",
    contract: "rollback(world, tick, opts) -> world"
  }
)

verb(
  "waarudo?",
  "send",
  {
    kind: :effect,
    shape: "send(world, event) -> nil",
    laterals: [],
    fleet: "asobi-ecs",
    today: "absent",
    meaning: "deliver one event to the systems that read it",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "simulate",
  {
    kind: :effect,
    shape: "simulate(world, ticks, opts) -> world",
    laterals: ["deadline"],
    fleet: "asobi-ecs",
    today: "absent",
    meaning: "advance a world a number of ticks",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "spawn",
  {
    kind: :effect,
    shape: "spawn(world, components) -> entity",
    laterals: [],
    fleet: "asobi-ecs",
    today: "absent",
    meaning: "bring a new entity into the world",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "system",
  {
    kind: :decl,
    shape: "system(name, reads, writes, f) -> system",
    laterals: ["validate"],
    fleet: "asobi-ecs",
    today: "absent",
    meaning: "declare a rule over components, with its reads and writes",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "world",
  {
    kind: :decl,
    shape: "world(spec) -> world",
    laterals: ["validate"],
    fleet: "asobi-ecs",
    today: "absent",
    meaning: "declare components, systems and resources",
    wave: 1,
    origin: "G"
  }
)

verb(
  "waarudo?",
  "write",
  {
    kind: :effect,
    shape: "write(world, target, opts) -> nil",
    laterals: ["resource", "serialize"],
    fleet: "asobi-save",
    today: "absent",
    meaning: "save a world, versioned and checksummed",
    wave: 2,
    origin: "G"
  }
)

edge("waarudo?::generate", :composes, "ran::pick", "seeded choice")
edge("waarudo?::simulate", :composes, "waarudo?::advance", "ticks in a row")
edge("waarudo?::advance", :composes, "waarudo?::arrange", "runs the order")
edge("waarudo?::advance", :composes, "waarudo?::system", "each system once")
edge("waarudo?::world", :composes, "waarudo?::system", "a world runs systems")
edge("waarudo?::query", :generalizes, "waarudo?::get", "many entities, not one")
edge("waarudo?::arrange", :guards, "waarudo?::advance", "no write clash")
edge("waarudo?::check", :guards, "waarudo?::advance", "laws hold each tick")

edge(
  "waarudo?::spawn",
  :inverse,
  "waarudo?::delete",
  "add and remove an entity"
)

edge("waarudo?::write", :inverse, "waarudo?::read", "load what was saved")

edge(
  "waarudo?::delete",
  :inverse,
  "waarudo?::spawn",
  "add and remove an entity"
)

edge("waarudo?::read", :inverse, "waarudo?::write", "load what was saved")

edge(
  "waarudo?::simulate",
  :pairs,
  "ugoki?::play",
  "a fixed step under a frame clock"
)

edge("waarudo?::field", :pairs, "waarudo?::generate", "noise feeds generation")
edge("waarudo?::put", :pairs, "waarudo?::get", "component write and read")
edge("waarudo?::send", :pairs, "waarudo?::on", "an event needs a handler")
edge("waarudo?::body", :pairs, "waarudo?::put", "a body is a component")
edge("waarudo?::get", :pairs, "waarudo?::put", "component read and write")
edge("waarudo?::rollback", :pairs, "waarudo?::write", "snapshots to rewind to")
edge("waarudo?::hit", :refines, "byouga?::hit", "first thing a ray meets")
edge("waarudo?::collide", :requires, "kikagaku::intersect", "shape overlap")
edge("waarudo?::field", :requires, "ran::draw", "seeded values")
edge("waarudo?::replay", :requires, "ran::fork", "same seed, same world")
edge("waarudo?::replay", :requires, "waarudo?::advance", "inputs drive steps")
edge("waarudo?::world", :requires, "waarudo?::arrange", "systems are ordered")
edge("waarudo?::body", :requires, "waarudo?::collide", "bodies touch")

edge(
  "waarudo?::grammar",
  :requires,
  "waarudo?::generate",
  "rules need a runner"
)

edge("waarudo?::generate", :requires, "waarudo?::grammar", "runs rules")
edge("waarudo?::check", :requires, "waarudo?::query", "reads every entity")
edge("waarudo?::hit", :requires, "waarudo?::query", "searches bodies")
edge("waarudo?::path", :requires, "waarudo?::query", "graph from the world")
edge("waarudo?::system", :requires, "waarudo?::query", "a system reads a query")
edge("waarudo?::rollback", :requires, "waarudo?::replay", "rewind then replay")
edge("waarudo?::on", :requires, "waarudo?::system", "handlers are systems")
edge("waarudo?::send", :requires, "waarudo?::world", "events live in a world")
