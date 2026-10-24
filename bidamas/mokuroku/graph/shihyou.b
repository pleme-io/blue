space("shihyou", {status: :ratified})

verb(
  "shihyou",
  "alerts",
  {
    kind: :pure,
    shape: "alerts(slo) -> [rule]",
    laterals: [],
    fleet: nil,
    today: "exists:shihyou",
    wave: 0,
    origin: "F"
  }
)

verb(
  "shihyou",
  "budget",
  {
    kind: :pure,
    shape: "budget(slo, window) -> ratio",
    laterals: ["time"],
    fleet: nil,
    today: "exists:shihyou",
    wave: 0,
    origin: "F"
  }
)

verb(
  "shihyou",
  "burn",
  {
    kind: :pure,
    shape: "burn(slo, window) -> number",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "how fast the budget is spent, as a multiple of even use",
    wave: 1,
    origin: "F"
  }
)

verb(
  "shihyou",
  "cycle_time",
  {
    kind: :pure,
    shape: "cycle_time(items, window) -> stats",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "time from work started to done, as a distribution",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shihyou",
  "dashboard",
  {
    kind: :pure,
    shape: "dashboard(slo) -> panels",
    laterals: ["serialize"],
    fleet: nil,
    today: "exists:shihyou",
    wave: 0,
    origin: "F"
  }
)

verb(
  "shihyou",
  "dora",
  {
    kind: :pure,
    shape: "dora(events, window) -> record",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "deploy frequency, lead time, failure rate and restore time",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shihyou",
  "error_ratio",
  {
    kind: :pure,
    shape: "error_ratio(name, w) -> query",
    laterals: [],
    fleet: "blue",
    today: "exists:shihyou",
    wave: 0,
    origin: "C"
  }
)

verb(
  "shihyou",
  "exhausted?",
  {
    kind: :effect,
    shape: "exhausted?(objective) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Whether the error budget is spent.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shihyou",
  "indicator",
  {
    kind: :decl,
    shape: "indicator(name, good, total) -> sli",
    laterals: ["config"],
    fleet: nil,
    today: "partial:shihyou",
    meaning: "declare what counts as good events over all events",
    wave: 0,
    origin: "F"
  }
)

verb(
  "shihyou",
  "meets?",
  {
    kind: :pure,
    shape: "meets?(slo, samples) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether samples satisfy the objective",
    wave: 1,
    origin: "F"
  }
)

verb(
  "shihyou",
  "objective",
  {
    kind: :decl,
    shape: "objective(name, target, window) -> slo",
    laterals: ["config"],
    fleet: nil,
    today: "partial:shihyou",
    meaning: "declare a service level objective",
    wave: 0,
    origin: "F"
  }
)

verb(
  "shihyou",
  "objectives",
  {
    kind: :pure,
    shape: "objectives(svc) -> [objective]",
    laterals: [],
    fleet: "blue",
    today: "exists:shihyou",
    wave: 0,
    origin: "C"
  }
)

verb(
  "shihyou",
  "review_time",
  {
    kind: :pure,
    shape: "review_time(reviews, window) -> stats",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "time a change waits for and spends in review",
    wave: 3,
    origin: "F"
  }
)

verb(
  "shihyou",
  "rules",
  {
    kind: :pure,
    shape: "rules(slo) -> [rule]",
    laterals: ["serialize"],
    fleet: nil,
    today: "exists:shihyou",
    wave: 0,
    origin: "F"
  }
)

verb(
  "shihyou",
  "runway",
  {
    kind: :pure,
    shape: "runway(slo) -> duration",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "how long until the budget runs out at this burn",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shihyou",
  "slow_ratio",
  {
    kind: :pure,
    shape: "slow_ratio(name, le, w) -> query",
    laterals: [],
    fleet: "blue",
    today: "exists:shihyou",
    wave: 0,
    origin: "C"
  }
)

verb(
  "shihyou",
  "throughput",
  {
    kind: :pure,
    shape: "throughput(items, window) -> number",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "items finished per unit of time",
    wave: 2,
    origin: "F"
  }
)

edge(
  "shihyou::indicator",
  :composes,
  "keisoku?::rate",
  "ratio of rates of events"
)

edge("shihyou::alerts", :composes, "shihyou::burn", "alerts fire on burn")

edge(
  "shihyou::exhausted?",
  :composes,
  "shihyou::burn",
  "spent when burn crosses budget"
)

edge("shihyou::runway", :composes, "shihyou::burn", "budget over burn")

edge(
  "shihyou::dora",
  :composes,
  "shihyou::cycle_time",
  "lead time is a cycle time"
)

edge(
  "shihyou::alerts",
  :composes,
  "shihyou::error_ratio",
  "burn alerts use ratios"
)

edge("shihyou::burn", :composes, "shihyou::error_ratio", "ratio over budget")

edge(
  "shihyou::rules",
  :composes,
  "shihyou::indicator",
  "recording rules per indicator"
)

edge(
  "shihyou::dashboard",
  :composes,
  "shihyou::rules",
  "panels show the same rules"
)

edge(
  "shihyou::exhausted?",
  :guards,
  "kyoujin?::shed",
  "spent budget can trigger shedding"
)

edge("shihyou::meets?", :pairs, "fuka?::judge", "same verdict shape")

edge(
  "shihyou::budget",
  :pairs,
  "hadome::judge",
  "a ratchet is a budget that shrinks"
)

edge("shihyou::dashboard", :pairs, "keisoku?::query", "panels run queries")

edge(
  "shihyou::objective",
  :pairs,
  "ketsugi?::enforce",
  "objectives are decisions held by rules"
)

edge(
  "shihyou::error_ratio",
  :pairs,
  "kyuuji::observe",
  "ratio of what observe counted"
)

edge("shihyou::runway", :pairs, "puran?::forecast", "both predict an end date")
edge("shihyou::dora", :pairs, "rirezu?::promote", "deploys are the events")
edge("shihyou::burn", :pairs, "shihyou::alerts", "alerts fire on burn")

edge(
  "shihyou::objectives",
  :pairs,
  "shihyou::budget",
  "objective and its allowed errors"
)

edge(
  "shihyou::review_time",
  :pairs,
  "shihyou::cycle_time",
  "a slice of cycle time"
)

edge("shihyou::throughput", :pairs, "shihyou::cycle_time", "flow measures")
edge("shihyou::slow_ratio", :pairs, "shihyou::error_ratio", "two indicators")
edge("shihyou::error_ratio", :pairs, "shihyou::slow_ratio", "two indicators")
edge("shihyou::rules", :pairs, "shougai?::route", "alerts go to routes")
edge("shihyou::alerts", :refines, "shihyou::rules", "alert rules are rules")

edge(
  "shihyou::cycle_time",
  :requires,
  "kadai?::list",
  "reads issue state changes"
)

edge("shihyou::throughput", :requires, "kadai?::list", "counts finished items")

edge(
  "shihyou::dora",
  :requires,
  "nisshi::read",
  "reads change and deploy events"
)

edge(
  "shihyou::review_time",
  :requires,
  "rebyuu?::list",
  "reads review timestamps"
)

edge("shihyou::burn", :requires, "shihyou::budget", "speed of budget use")

edge(
  "shihyou::objective",
  :requires,
  "shihyou::indicator",
  "a target is over an indicator"
)

edge(
  "shihyou::budget",
  :requires,
  "shihyou::objective",
  "budget of an objective"
)

edge(
  "shihyou::meets?",
  :requires,
  "shihyou::objective",
  "judges samples against it"
)

edge(
  "shihyou::budget",
  :requires,
  "shihyou::objectives",
  "derived from a target"
)

edge(
  "shihyou::dashboard",
  :requires,
  "shihyou::objectives",
  "panels per objective"
)
