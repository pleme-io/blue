space("kinji", {status: :ratified})

verb(
  "kinji",
  "advance",
  {
    kind: :pure,
    shape: "advance(ode, state, span) -> state",
    laterals: [],
    fleet: nil,
    today: "partial:kinji",
    meaning: "move an ODE state forward over a span",
    wave: 0,
    origin: "G",
    contract: "advance(ode, state, opts) -> state"
  }
)

verb(
  "kinji",
  "fit",
  {
    kind: :pure,
    shape: "fit(model, data) -> params",
    laterals: [],
    fleet: nil,
    today: "exists:kinji",
    meaning: "least-squares parameters for a model",
    wave: 0,
    origin: "G"
  }
)

verb(
  "kinji",
  "integrate",
  {
    kind: :pure,
    shape: "integrate(f, a, b) -> number",
    laterals: [],
    fleet: nil,
    today: "partial:kinji",
    meaning: "area under f from a to b",
    wave: 0,
    origin: "G"
  }
)

verb(
  "kinji",
  "interpolate",
  {
    kind: :pure,
    shape: "interpolate(points, x) -> number",
    laterals: [],
    fleet: nil,
    today: "partial:kinji",
    meaning: "a value between known points",
    wave: 0,
    origin: "G"
  }
)

verb(
  "kinji",
  "minimize",
  {
    kind: :pure,
    shape: "minimize(f, start) -> point",
    laterals: [],
    fleet: nil,
    today: "partial:kinji",
    meaning: "a point where f is least",
    wave: 0,
    origin: "G"
  }
)

verb(
  "kinji",
  "zero",
  {
    kind: :pure,
    shape: "zero(f, bracket) -> number",
    laterals: [],
    fleet: nil,
    today: "partial:kinji",
    meaning: "where f is zero in a bracket",
    wave: 0,
    origin: "G"
  }
)

edge("kinji::zero", :generalizes, "kinyuu?::irr", "a root of a function")
edge("kinji::advance", :refines, "waarudo?::advance", "an ODE step")

edge(
  "kinji::advance",
  :requires,
  "gyouretsu::solve",
  "implicit steps solve systems"
)

edge("kinji::integrate", :requires, "gyouretsu::solve", "quadrature weights")
edge("kinji::interpolate", :requires, "kinji::fit", "between known points")
edge("kinji::minimize", :requires, "kinji::fit", "fit is a minimum")
edge("kinji::integrate", :requires, "kinji::interpolate", "area under a curve")
edge("kinji::fit", :requires, "kinji::minimize", "least squares")
