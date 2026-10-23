space("hiyou?", {status: :provisional})

verb(
  "hiyou?",
  "attribute",
  {
    kind: :pure,
    shape: "attribute(lines, rules) -> [line]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "spend assigned to an owner",
    wave: 3,
    origin: "E"
  }
)

verb(
  "hiyou?",
  "breach?",
  {
    kind: :pure,
    shape: "breach?(budget, lines) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "whether spend passes a budget",
    wave: 4,
    origin: "E"
  }
)

verb(
  "hiyou?",
  "budget",
  {
    kind: :decl,
    shape: "budget(scope, amount, period) -> budget",
    laterals: ["config", "time"],
    fleet: nil,
    today: "absent",
    meaning: "a spend limit for a scope",
    wave: 4,
    origin: "E"
  }
)

verb(
  "hiyou?",
  "check",
  {
    kind: :pure,
    shape: "check(resources, policy) -> [finding]",
    laterals: ["validate"],
    fleet: "tag-forge",
    today: "absent",
    meaning: "resources missing required cost tags",
    wave: 3,
    origin: "E"
  }
)

verb(
  "hiyou?",
  "cost",
  {
    kind: :effect,
    shape: "cost(scope, range, opts) -> [line]",
    laterals: ["error", "time"],
    fleet: nil,
    today: "absent",
    meaning: "spend by scope and period",
    wave: 3,
    origin: "E"
  }
)

verb(
  "hiyou?",
  "forecast",
  {
    kind: :pure,
    shape: "forecast(lines, horizon) -> [line]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "expected spend ahead",
    wave: 4,
    origin: "E"
  }
)

verb(
  "hiyou?",
  "recommend",
  {
    kind: :effect,
    shape: "recommend(workload, usage) -> [action]",
    laterals: ["resource"],
    fleet: "rightsize-forge",
    today: "absent",
    meaning: "right-sized requests and limits",
    wave: 3,
    origin: "E"
  }
)

verb(
  "hiyou?",
  "reserve",
  {
    kind: :pure,
    shape: "reserve(lines, options) -> plan",
    laterals: [],
    fleet: "commitment-forge",
    today: "absent",
    meaning: "layered purchase commitments for steady use",
    wave: 4,
    origin: "E"
  }
)

verb(
  "hiyou?",
  "showback",
  {
    kind: :pure,
    shape: "showback(lines, owners) -> report",
    laterals: ["serialize"],
    fleet: "showback-forge",
    today: "absent",
    meaning: "spend per owner as a report",
    wave: 3,
    origin: "E"
  }
)

verb(
  "hiyou?",
  "unit",
  {
    kind: :pure,
    shape: "unit(lines, measure) -> record",
    laterals: [],
    fleet: "unit-econ-forge",
    today: "absent",
    meaning: "cost per request, tenant or build",
    wave: 4,
    origin: "E"
  }
)

verb(
  "hiyou?",
  "waste",
  {
    kind: :effect,
    shape: "waste(scope) -> [resource]",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "idle resources still costing money",
    wave: 4,
    origin: "E"
  }
)

edge("hiyou?::showback", :composes, "hiyou?::attribute", "owner report")
edge("hiyou?::unit", :composes, "hiyou?::attribute", "per measure")
edge("hiyou?::waste", :composes, "hiyou?::cost", "priced idle")
edge("hiyou?::reserve", :composes, "hiyou?::forecast", "steady use drives buys")
edge("hiyou?::cost", :composes, "kuraudo?::list", "resources carry price")
edge("hiyou?::waste", :composes, "kuraudo?::list", "idle resources")
edge("hiyou?::recommend", :composes, "youryou?::observe", "usage drives sizing")
edge("hiyou?::check", :guards, "hiyou?::attribute", "untagged cannot attribute")
edge("hiyou?::budget", :guards, "hiyou?::breach?", "limit it checks")

edge(
  "hiyou?::budget",
  :pairs,
  "hiyou?::forecast",
  "budget compared to forecast"
)

edge("hiyou?::recommend", :pairs, "youryou?::plan", "sizing action")
edge("hiyou?::cost", :refines, "core::list", "spend lines")
edge("hiyou?::forecast", :refines, "core::plan", "spend ahead")
edge("hiyou?::showback", :refines, "core::render", "report")
edge("hiyou?::check", :refines, "kijun::check", "tag policy as rules")
edge("hiyou?::breach?", :requires, "hiyou?::cost", "compares real spend")
edge("hiyou?::unit", :requires, "hiyou?::cost", "spend first")
edge("hiyou?::attribute", :requires, "kuraudo?::tags", "tags name owners")
