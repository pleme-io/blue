space("junban?", {status: :provisional})

verb(
  "junban?",
  "empty?",
  {
    kind: :pure,
    shape: "empty?(queue) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether nothing is waiting",
    wave: 2,
    origin: "A"
  }
)

verb(
  "junban?",
  "from",
  {
    kind: :pure,
    shape: "from(kind, items, opts) -> queue",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "queue filled from a list",
    wave: 2,
    origin: "A"
  }
)

verb(
  "junban?",
  "full?",
  {
    kind: :pure,
    shape: "full?(queue) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a bounded queue is at capacity",
    wave: 2,
    origin: "A"
  }
)

verb(
  "junban?",
  "merge",
  {
    kind: :pure,
    shape: "merge(a, b) -> queue",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "one priority queue holding both",
    wave: 3,
    origin: "A"
  }
)

verb(
  "junban?",
  "peek",
  {
    kind: :pure,
    shape: "peek(queue) -> item or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "next item without removing it",
    wave: 2,
    origin: "A"
  }
)

verb(
  "junban?",
  "pop",
  {
    kind: :pure,
    shape: "pop(queue) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "next item and the remaining queue",
    wave: 2,
    origin: "A"
  }
)

verb(
  "junban?",
  "push",
  {
    kind: :pure,
    shape: "push(queue, item, opts) -> queue",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "queue with an item added; a full ring drops its oldest",
    wave: 2,
    origin: "A"
  }
)

verb(
  "junban?",
  "queue",
  {
    kind: :decl,
    shape: "queue(kind, opts) -> queue",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "empty fifo, lifo, priority or ring queue",
    wave: 2,
    origin: "A"
  }
)

verb(
  "junban?",
  "reprioritize",
  {
    kind: :pure,
    shape: "reprioritize(queue, item, priority) -> queue",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "change the priority of a queued item",
    wave: 3,
    origin: "A"
  }
)

verb(
  "junban?",
  "size",
  {
    kind: :pure,
    shape: "size(queue) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "number of items waiting",
    wave: 2,
    origin: "A"
  }
)

verb(
  "junban?",
  "to_list",
  {
    kind: :pure,
    shape: "to_list(queue) -> list",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "items in pop order, queue unchanged",
    wave: 2,
    origin: "A"
  }
)

verb(
  "junban?",
  "unload",
  {
    kind: :pure,
    shape: "unload(queue) -> list",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "every item in pop order",
    wave: 2,
    origin: "A"
  }
)

edge("junban?::pop", :composes, "junban?::peek", "peek, then remove")
edge("junban?::unload", :composes, "junban?::pop", "pop until empty")
edge("junban?::from", :composes, "junban?::push", "push each item")
edge("junban?::merge", :composes, "junban?::push", "push each item of b")

edge(
  "junban?::reprioritize",
  :composes,
  "junban?::push",
  "remove then push again"
)

edge("junban?::empty?", :composes, "junban?::size", "size equals zero")
edge("junban?::push", :composes, "retsu::append", "a fifo adds at the tail")
edge("junban?::peek", :guards, "junban?::pop", "pop of an empty queue raises")
edge("junban?::queue", :guards, "junban?::push", "push needs a queue")
edge("junban?::unload", :lifts, "junban?::pop", "batch form of pop")
edge("junban?::size", :pairs, "junban?::empty?", "count and its zero test")
edge("junban?::push", :pairs, "junban?::pop", "add and take")
edge("junban?::reprioritize", :pairs, "junban?::pop", "decrease-key then take")
edge("junban?::full?", :pairs, "junban?::push", "check before adding")
edge("junban?::unload", :pairs, "junjo::sort", "a priority drain is a sort")
edge("junban?::to_list", :refines, "junban?::unload", "drain without consuming")
edge("junban?::empty?", :refines, "retsu::empty?", "no items")
edge("junban?::size", :refines, "retsu::size", "count of items")
edge("junban?::full?", :requires, "junban?::size", "compare against capacity")
