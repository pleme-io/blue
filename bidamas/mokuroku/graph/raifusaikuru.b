space("raifusaikuru", {status: :ratified})

verb(
  "raifusaikuru",
  "admit",
  {
    kind: :pure,
    shape: "admit(definition, state, event) -> verdict",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:raifusaikuru",
    meaning: "whether an event is allowed in a state, with the refusal",
    wave: 0,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "advance",
  {
    kind: :effect,
    shape: "advance(engine, id) -> state",
    laterals: ["deadline", "error", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "run an instance until it rests or ends",
    wave: 2,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "cancel",
  {
    kind: :effect,
    shape: "cancel(engine, id, opts) -> state",
    laterals: ["cancel", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "end an instance and run its compensations",
    wave: 3,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "check",
  {
    kind: :pure,
    shape: "check(definition) -> [problem]",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:raifusaikuru",
    meaning: "find unreachable states, duplicates and bad guards",
    wave: 0,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "compensate",
  {
    kind: :effect,
    shape: "compensate(engine, id) -> state",
    laterals: ["error", "idempotent", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "undo completed steps in reverse order, as a saga",
    wave: 3,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "create",
  {
    kind: :effect,
    shape: "create(engine, definition, input) -> instance",
    laterals: ["error", "idempotent", "trace"],
    fleet: nil,
    today: "absent",
    meaning: "start a persisted instance of a lifecycle",
    wave: 2,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "event",
  {
    kind: :decl,
    shape: "event(name, fields) -> decl",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:raifusaikuru",
    meaning: "declare an event type and its payload fields",
    wave: 0,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "gate",
  {
    kind: :decl,
    shape: "gate(transition, predicate) -> decl",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:raifusaikuru",
    meaning: "declare a condition a transition must meet",
    wave: 0,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "get",
  {
    kind: :effect,
    shape: "get(engine, id) -> instance or nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "one instance with its state, or nil",
    wave: 2,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "history",
  {
    kind: :effect,
    shape: "history(engine, id) -> [record]",
    laterals: ["trace"],
    fleet: nil,
    today: "absent",
    meaning: "the event records an instance has seen",
    wave: 2,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "initial",
  {
    kind: :decl,
    shape: "initial(state) -> decl",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:raifusaikuru",
    meaning: "declare the state an instance begins in",
    wave: 0,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "list",
  {
    kind: :effect,
    shape: "list(engine, opts) -> [instance]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "instances filtered by state, sorted",
    wave: 2,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "on",
  {
    kind: :decl,
    shape: "on(state, event, to) -> decl",
    laterals: ["validate"],
    fleet: "pleme-state-machines",
    today: "exists:raifusaikuru",
    meaning: "declare a transition from a state on an event",
    wave: 0,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "permit",
  {
    kind: :decl,
    shape: "permit(name, limit, window) -> decl",
    laterals: ["ratelimit", "validate"],
    fleet: nil,
    today: "exists:raifusaikuru",
    meaning: "declare a count limit on a kind of event",
    wave: 0,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "render",
  {
    kind: :pure,
    shape: "render(definition, format) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "draw the machine as a diagram or table",
    wave: 2,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "replay",
  {
    kind: :pure,
    shape: "replay(definition, events) -> state",
    laterals: [],
    fleet: nil,
    today: "partial:raifusaikuru",
    meaning: "fold events from the start into the current state",
    wave: 0,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "resume",
  {
    kind: :effect,
    shape: "resume(engine, opts) -> count",
    laterals: ["cancel", "error"],
    fleet: nil,
    today: "absent",
    meaning: "continue every unfinished instance after a restart",
    wave: 3,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "rule",
  {
    kind: :decl,
    shape: "rule(name, predicate, task) -> decl",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:raifusaikuru",
    meaning: "declare a guard that names the rule and the task",
    wave: 0,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "signal",
  {
    kind: :effect,
    shape: "signal(engine, id, event, payload) -> state",
    laterals: ["error", "idempotent", "trace"],
    fleet: nil,
    today: "absent",
    meaning: "deliver an event to an instance and persist the result",
    wave: 2,
    origin: "B",
    contract: "signal(engine, id, event, opts) -> state"
  }
)

verb(
  "raifusaikuru",
  "states",
  {
    kind: :decl,
    shape: "states(names) -> decl",
    laterals: ["validate"],
    fleet: "pleme-state-machines",
    today: "exists:raifusaikuru",
    meaning: "declare the states of a lifecycle",
    wave: 0,
    origin: "B"
  }
)

verb(
  "raifusaikuru",
  "timer",
  {
    kind: :decl,
    shape: "timer(state, duration, event) -> decl",
    laterals: ["time", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare an event raised after a state lasts too long",
    wave: 3,
    origin: "B",
    contract: "timer(state, duration, opts) -> decl"
  }
)

verb(
  "raifusaikuru",
  "wait",
  {
    kind: :effect,
    shape: "wait(engine, id, opts) -> state",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "block until an instance reaches a terminal state",
    wave: 2,
    origin: "B"
  }
)

edge(
  "raifusaikuru::create",
  :composes,
  "nisshi::append",
  "first record persists"
)

edge("raifusaikuru::signal", :composes, "nisshi::append", "persists it")

edge(
  "raifusaikuru::history",
  :composes,
  "nisshi::read",
  "records of one instance"
)

edge("raifusaikuru::get", :composes, "nisshi::replay", "state from the log")

edge(
  "raifusaikuru::signal",
  :composes,
  "raifusaikuru::admit",
  "checks the event"
)

edge(
  "raifusaikuru::resume",
  :composes,
  "raifusaikuru::advance",
  "continues each"
)

edge(
  "raifusaikuru::cancel",
  :composes,
  "raifusaikuru::compensate",
  "undo before ending"
)

edge(
  "raifusaikuru::admit",
  :composes,
  "raifusaikuru::gate",
  "evaluates the conditions"
)

edge(
  "raifusaikuru::wait",
  :composes,
  "raifusaikuru::get",
  "polls for a terminal state"
)

edge(
  "raifusaikuru::create",
  :composes,
  "raifusaikuru::initial",
  "begins in the start state"
)

edge(
  "raifusaikuru::resume",
  :composes,
  "raifusaikuru::list",
  "finds unfinished ones"
)

edge(
  "raifusaikuru::admit",
  :composes,
  "raifusaikuru::permit",
  "evaluates the limits"
)

edge(
  "raifusaikuru::advance",
  :composes,
  "raifusaikuru::signal",
  "signals until it rests"
)

edge(
  "raifusaikuru::signal",
  :composes,
  "rokku?::with_lock",
  "one writer per instance"
)

edge(
  "raifusaikuru::timer",
  :composes,
  "taiki?::schedule",
  "delivery of the timeout"
)

edge(
  "raifusaikuru::check",
  :guards,
  "raifusaikuru::create",
  "only a clean definition runs"
)

edge(
  "raifusaikuru::gate",
  :guards,
  "raifusaikuru::on",
  "condition on a transition"
)

edge(
  "raifusaikuru::compensate",
  :inverse,
  "raifusaikuru::advance",
  "undoes completed steps"
)

edge(
  "raifusaikuru::advance",
  :inverse,
  "raifusaikuru::compensate",
  "undoes completed steps"
)

edge("raifusaikuru::replay", :lifts, "raifusaikuru::admit", "folds many events")
edge("raifusaikuru::list", :lifts, "raifusaikuru::get", "many instances")
edge("raifusaikuru::replay", :pairs, "nisshi::replay", "fold from the log")

edge(
  "raifusaikuru::check",
  :pairs,
  "raifusaikuru::admit",
  "static and dynamic checks"
)

edge("raifusaikuru::wait", :pairs, "raifusaikuru::advance", "run then wait")

edge(
  "raifusaikuru::render",
  :pairs,
  "raifusaikuru::check",
  "diagram beside the checks"
)

edge(
  "raifusaikuru::initial",
  :pairs,
  "raifusaikuru::create",
  "declared then begun"
)

edge(
  "raifusaikuru::event",
  :pairs,
  "raifusaikuru::on",
  "events drive transitions"
)

edge("raifusaikuru::list", :pairs, "raifusaikuru::resume", "find then continue")

edge(
  "raifusaikuru::get",
  :pairs,
  "raifusaikuru::signal",
  "state and its change"
)

edge("raifusaikuru::cancel", :pairs, "raifusaikuru::wait", "end then confirm")

edge(
  "raifusaikuru::timer",
  :refines,
  "raifusaikuru::event",
  "an event raised by time"
)

edge(
  "raifusaikuru::permit",
  :refines,
  "raifusaikuru::gate",
  "count limit on events"
)

edge(
  "raifusaikuru::rule",
  :refines,
  "raifusaikuru::gate",
  "names rule and task"
)

edge(
  "raifusaikuru::advance",
  :requires,
  "raifusaikuru::get",
  "needs the current state"
)

edge(
  "raifusaikuru::initial",
  :requires,
  "raifusaikuru::states",
  "start is one of the states"
)

edge(
  "raifusaikuru::on",
  :requires,
  "raifusaikuru::states",
  "transitions join states"
)
