space("fuka?", {status: :provisional})

verb(
  "fuka?",
  "blast",
  {
    kind: :pure,
    shape: "blast(target, radius) -> scope",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "bound which targets a fault may touch",
    wave: 3,
    origin: "F"
  }
)

verb(
  "fuka?",
  "experiment",
  {
    kind: :effect,
    shape: "experiment(spec) -> verdict",
    laterals: ["cancel", "capability", "test"],
    fleet: "vendaval",
    today: "absent",
    meaning: "test a steady-state claim under a fault and always heal",
    wave: 3,
    origin: "F"
  }
)

verb(
  "fuka?",
  "fault",
  {
    kind: :effect,
    shape: "fault(target, kind, opts) -> handle",
    laterals: ["capability", "resource", "time"],
    fleet: "vendaval",
    today: "absent",
    meaning: "inject a failure: kill, delay, loss, partition or corrupt",
    wave: 3,
    origin: "F"
  }
)

verb(
  "fuka?",
  "guard",
  {
    kind: :decl,
    shape: "guard(probe, limit) -> guard",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "declare a stop condition that aborts an experiment",
    wave: 3,
    origin: "F"
  }
)

verb(
  "fuka?",
  "heal",
  {
    kind: :effect,
    shape: "heal(handle) -> nil",
    laterals: ["idempotent", "resource"],
    fleet: "vendaval",
    today: "absent",
    meaning: "undo an injected fault",
    wave: 3,
    origin: "F"
  }
)

verb(
  "fuka?",
  "judge",
  {
    kind: :pure,
    shape: "judge(report, thresholds) -> verdict",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "whether a load report stays within every threshold",
    wave: 2,
    origin: "F"
  }
)

verb(
  "fuka?",
  "mirror",
  {
    kind: :stream,
    shape: "mirror(source, target, opts) -> report",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "copy live requests to a shadow target and compare answers",
    wave: 4,
    origin: "F"
  }
)

verb(
  "fuka?",
  "ramp",
  {
    kind: :decl,
    shape: "ramp(from, to, over) -> shape",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "declare load that grows over a duration",
    wave: 2,
    origin: "F"
  }
)

verb(
  "fuka?",
  "run",
  {
    kind: :effect,
    shape: "run(scenario, shape, opts) -> report",
    laterals: ["cancel", "deadline", "process"],
    fleet: "vendaval",
    today: "absent",
    meaning: "apply load and record latency, errors and saturation",
    wave: 2,
    origin: "F"
  }
)

verb(
  "fuka?",
  "scenario",
  {
    kind: :decl,
    shape: "scenario(steps) -> scenario",
    laterals: ["test"],
    fleet: "vendaval",
    today: "absent",
    meaning: "declare a user journey as ordered requests",
    wave: 2,
    origin: "F"
  }
)

verb(
  "fuka?",
  "soak",
  {
    kind: :effect,
    shape: "soak(scenario, shape, opts) -> report",
    laterals: ["resource", "time"],
    fleet: "vendaval",
    today: "absent",
    meaning: "hold load for hours and watch for drift and leaks",
    wave: 3,
    origin: "F"
  }
)

verb(
  "fuka?",
  "spike",
  {
    kind: :decl,
    shape: "spike(base, peak, at, for) -> shape",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "declare a short burst on top of base load",
    wave: 2,
    origin: "F"
  }
)

verb(
  "fuka?",
  "steady",
  {
    kind: :decl,
    shape: "steady(rate, for) -> shape",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "declare constant load for a duration",
    wave: 2,
    origin: "F"
  }
)

verb(
  "fuka?",
  "threshold",
  {
    kind: :decl,
    shape: "threshold(metric, limit) -> threshold",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "declare a limit a load run must stay within",
    wave: 2,
    origin: "F"
  }
)

edge("fuka?::experiment", :composes, "fuka?::fault", "injects inside the run")
edge("fuka?::experiment", :composes, "fuka?::heal", "always heals after")
edge("fuka?::run", :composes, "keisoku?::observe", "records latency")
edge("fuka?::judge", :composes, "shihyou::meets?", "limits mirror objectives")
edge("fuka?::guard", :guards, "fuka?::experiment", "aborts on a stop condition")
edge("fuka?::blast", :guards, "fuka?::fault", "bounds the targets")

edge(
  "fuka?::judge",
  :guards,
  "hakkou?::promote",
  "failing load stops promotion"
)

edge("fuka?::heal", :inverse, "fuka?::fault", "inject and undo")
edge("fuka?::fault", :inverse, "fuka?::heal", "inject and undo")
edge("fuka?::blast", :pairs, "fuka?::guard", "scope and stop")
edge("fuka?::steady", :pairs, "fuka?::ramp", "shapes combine in order")
edge("fuka?::soak", :pairs, "genin?::stuck", "long runs find hangs")
edge("fuka?::run", :pairs, "keisoku?::bench", "bench of a whole service")
edge("fuka?::soak", :pairs, "keisoku?::cardinality", "soak shows label growth")
edge("fuka?::guard", :pairs, "shihyou::burn", "stop when burn is high")

edge(
  "fuka?::threshold",
  :pairs,
  "shihyou::objective",
  "limits come from objectives"
)

edge(
  "fuka?::experiment",
  :pairs,
  "shougai?::drill",
  "a drill is an experiment on people"
)

edge(
  "fuka?::mirror",
  :pairs,
  "tsuiseki?::carry",
  "shadow requests keep context"
)

edge("fuka?::scenario", :pairs, "tsuiseki?::span", "each step is a span")
edge("fuka?::mirror", :refines, "fuka?::run", "real traffic as load")
edge("fuka?::soak", :refines, "fuka?::run", "long hold")
edge("fuka?::ramp", :refines, "fuka?::steady", "rate changes over time")
edge("fuka?::spike", :refines, "fuka?::steady", "a burst on a base")
edge("fuka?::heal", :requires, "fuka?::fault", "only an injected fault")
edge("fuka?::run", :requires, "fuka?::scenario", "load needs a journey")
edge("fuka?::run", :requires, "fuka?::steady", "and a shape")
edge("fuka?::judge", :requires, "fuka?::threshold", "checks the limits")
edge("fuka?::fault", :requires, "shougai?::silence", "silence alerts you cause")
