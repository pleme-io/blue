space("youryou?", {status: :provisional})

verb(
  "youryou?",
  "bound",
  {
    kind: :pure,
    shape: "bound(band) -> {floor:, ceiling:}",
    laterals: ["resource", "validate"],
    fleet: "breathe",
    today: "absent",
    meaning: "the limits a band may never cross",
    wave: 1,
    origin: "E"
  }
)

verb(
  "youryou?",
  "burst",
  {
    kind: :effect,
    shape: "burst(workload, load, opts) -> report",
    laterals: ["resource", "time"],
    fleet: "burst-forge",
    today: "absent",
    meaning: "drive load and record scaling behaviour",
    wave: 4,
    origin: "E"
  }
)

verb(
  "youryou?",
  "confirm",
  {
    kind: :effect,
    shape: "confirm(band) -> band",
    laterals: ["capability", "log"],
    fleet: "breathe",
    today: "absent",
    meaning: "promote a calibrating band to live writes",
    wave: 2,
    origin: "E"
  }
)

verb(
  "youryou?",
  "explain",
  {
    kind: :pure,
    shape: "explain(band) -> text",
    laterals: [],
    fleet: "breathe",
    today: "absent",
    meaning: "why a band is shadowed or live",
    wave: 1,
    origin: "E"
  }
)

verb(
  "youryou?",
  "forecast",
  {
    kind: :pure,
    shape: "forecast(series, horizon) -> series",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "expected demand ahead",
    wave: 3,
    origin: "E"
  }
)

verb(
  "youryou?",
  "get",
  {
    kind: :effect,
    shape: "get(band) -> record or nil",
    laterals: ["error"],
    fleet: "breathe",
    today: "absent",
    meaning: "one band with its resolved write gate",
    wave: 1,
    origin: "E"
  }
)

verb(
  "youryou?",
  "headroom",
  {
    kind: :effect,
    shape: "headroom(pool) -> {free:, reserved:}",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "capacity left in a pool",
    wave: 2,
    origin: "E"
  }
)

verb(
  "youryou?",
  "intent",
  {
    kind: :effect,
    shape: "intent(band, mode, opts) -> band",
    laterals: ["capability", "log", "switch"],
    fleet: "breathe",
    today: "absent",
    meaning: "set a band to observe, calibrate, write or frozen",
    wave: 1,
    origin: "E"
  }
)

verb(
  "youryou?",
  "list",
  {
    kind: :effect,
    shape: "list(opts) -> [band]",
    laterals: ["error"],
    fleet: "breathe",
    today: "absent",
    meaning: "resource bands and their state",
    wave: 1,
    origin: "E"
  }
)

verb(
  "youryou?",
  "observe",
  {
    kind: :effect,
    shape: "observe(workload, opts) -> usage",
    laterals: ["resource", "time"],
    fleet: "breathe",
    today: "absent",
    meaning: "utilization over a window",
    wave: 1,
    origin: "E"
  }
)

verb(
  "youryou?",
  "plan",
  {
    kind: :pure,
    shape: "plan(band, usage) -> action",
    laterals: ["resource"],
    fleet: "breathe",
    today: "absent",
    meaning: "the limit change a band would make",
    wave: 1,
    origin: "E"
  }
)

verb(
  "youryou?",
  "put",
  {
    kind: :effect,
    shape: "put(band, spec) -> band",
    laterals: ["idempotent", "log"],
    fleet: "breathe",
    today: "absent",
    meaning: "create or replace a band declaration",
    wave: 2,
    origin: "E"
  }
)

verb(
  "youryou?",
  "resize",
  {
    kind: :effect,
    shape: "resize(workload, n, opts) -> workload",
    laterals: ["log", "resource", "switch"],
    fleet: nil,
    today: "absent",
    meaning: "set the replica count",
    wave: 3,
    origin: "E"
  }
)

edge("youryou?::headroom", :composes, "kurasuta::top", "capacity less usage")
edge("youryou?::observe", :composes, "kurasuta::top", "usage source")
edge("youryou?::plan", :composes, "youryou?::bound", "within floor and ceiling")
edge("youryou?::get", :composes, "youryou?::list", "lookup by name")

edge(
  "youryou?::burst",
  :composes,
  "youryou?::observe",
  "record scaling under load"
)

edge(
  "youryou?::forecast",
  :composes,
  "youryou?::observe",
  "history drives forecast"
)

edge("youryou?::plan", :composes, "youryou?::observe", "plan from usage")
edge("youryou?::resize", :guards, "tenkai?::step", "capacity before rollout")
edge("youryou?::intent", :guards, "youryou?::put", "write gate decides effect")

edge(
  "youryou?::headroom",
  :guards,
  "youryou?::resize",
  "no scale beyond headroom"
)

edge("youryou?::put", :pairs, "youryou?::bound", "declaration carries bounds")
edge("youryou?::intent", :pairs, "youryou?::explain", "gate and its reason")
edge("youryou?::get", :refines, "core::get", "one band")
edge("youryou?::bound", :refines, "core::info", "capacity limits")
edge("youryou?::explain", :refines, "core::info", "why shadow or live")
edge("youryou?::list", :refines, "core::list", "bands")
edge("youryou?::plan", :refines, "core::plan", "limit change as data")
edge("youryou?::put", :refines, "core::put", "band declaration")
edge("youryou?::observe", :refines, "core::read", "utilization")

edge(
  "youryou?::forecast",
  :refines,
  "hiyou?::forecast",
  "same shape over demand"
)

edge("youryou?::confirm", :refines, "youryou?::intent", "calibrate to write")
edge("youryou?::resize", :refines, "youryou?::put", "replica band write")
