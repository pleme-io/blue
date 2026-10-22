space("sekai?", {status: :provisional})

verb(
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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
  "sekai?",
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

edge("sekai?::generate", :composes, "ran::pick", "seeded choice")
edge("sekai?::simulate", :composes, "sekai?::advance", "ticks in a row")
edge("sekai?::advance", :composes, "sekai?::arrange", "runs the order")
edge("sekai?::advance", :composes, "sekai?::system", "each system once")
edge("sekai?::world", :composes, "sekai?::system", "a world runs systems")
edge("sekai?::query", :generalizes, "sekai?::get", "many entities, not one")
edge("sekai?::arrange", :guards, "sekai?::advance", "no write clash")
edge("sekai?::check", :guards, "sekai?::advance", "laws hold each tick")
edge("sekai?::spawn", :inverse, "sekai?::delete", "add and remove an entity")
edge("sekai?::write", :inverse, "sekai?::read", "load what was saved")
edge("sekai?::delete", :inverse, "sekai?::spawn", "add and remove an entity")
edge("sekai?::read", :inverse, "sekai?::write", "load what was saved")
edge("sekai?::field", :pairs, "sekai?::generate", "noise feeds generation")
edge("sekai?::put", :pairs, "sekai?::get", "component write and read")
edge("sekai?::send", :pairs, "sekai?::on", "an event needs a handler")
edge("sekai?::body", :pairs, "sekai?::put", "a body is a component")
edge("sekai?::get", :pairs, "sekai?::put", "component read and write")
edge("sekai?::rollback", :pairs, "sekai?::write", "snapshots to rewind to")

edge(
  "sekai?::simulate",
  :pairs,
  "ugoki?::play",
  "a fixed step under a frame clock"
)

edge("sekai?::hit", :refines, "byouga?::hit", "first thing a ray meets")
edge("sekai?::collide", :requires, "kikagaku::intersect", "shape overlap")
edge("sekai?::field", :requires, "ran::draw", "seeded values")
edge("sekai?::replay", :requires, "ran::fork", "same seed, same world")
edge("sekai?::replay", :requires, "sekai?::advance", "inputs drive steps")
edge("sekai?::world", :requires, "sekai?::arrange", "systems are ordered")
edge("sekai?::body", :requires, "sekai?::collide", "bodies touch")
edge("sekai?::grammar", :requires, "sekai?::generate", "rules need a runner")
edge("sekai?::generate", :requires, "sekai?::grammar", "runs rules")
edge("sekai?::check", :requires, "sekai?::query", "reads every entity")
edge("sekai?::hit", :requires, "sekai?::query", "searches bodies")
edge("sekai?::path", :requires, "sekai?::query", "graph from the world")
edge("sekai?::system", :requires, "sekai?::query", "a system reads a query")
edge("sekai?::rollback", :requires, "sekai?::replay", "rewind then replay")
edge("sekai?::on", :requires, "sekai?::system", "handlers are systems")
edge("sekai?::send", :requires, "sekai?::world", "events live in a world")
