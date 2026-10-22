space("kakuritsu?", {status: :provisional})

verb(
  "kakuritsu?",
  "bayes",
  {
    kind: :pure,
    shape: "bayes(prior, likelihood, evidence) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "posterior chance after seeing evidence",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "bootstrap",
  {
    kind: :pure,
    shape: "bootstrap(data, statistic, rng, n) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "resampled spread of a statistic",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "bytes",
  {
    kind: :pure,
    shape: "bytes(rng, n) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "n pseudo-random bytes and the next stream",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "cdf",
  {
    kind: :pure,
    shape: "cdf(dist, x) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "chance of a value at or below x",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "choice",
  {
    kind: :pure,
    shape: "choice(rng, list) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "one item at random and the next stream",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "distribution",
  {
    kind: :decl,
    shape: "distribution(kind, params) -> distribution",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare normal, uniform, binomial, poisson and others",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "draw",
  {
    kind: :pure,
    shape: "draw(rng) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "float in [0,1) and the next stream",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "entropy",
  {
    kind: :effect,
    shape: "entropy(n) -> bytes",
    laterals: ["capability"],
    fleet: "tatara-lisp-script",
    today: "absent",
    meaning: "n bytes from the operating system",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "estimate",
  {
    kind: :pure,
    shape: "estimate(f, rng, n) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Monte Carlo mean and error of f over n runs",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "expectation",
  {
    kind: :pure,
    shape: "expectation(dist, f) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "average of f over a distribution",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "fit",
  {
    kind: :pure,
    shape: "fit(kind, data) -> distribution",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "distribution parameters estimated from data",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "fork",
  {
    kind: :pure,
    shape: "fork(rng) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "two independent streams from one",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "int",
  {
    kind: :pure,
    shape: "int(rng, low, high) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "integer in a range and the next stream",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "likelihood",
  {
    kind: :pure,
    shape: "likelihood(dist, data) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "how probable the data is under a distribution",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "mean",
  {
    kind: :pure,
    shape: "mean(dist) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "expected value of a distribution",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "pdf",
  {
    kind: :pure,
    shape: "pdf(dist, x) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "density or mass at a point",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "quantile",
  {
    kind: :pure,
    shape: "quantile(dist, p) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "value below which a share p falls",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "sample",
  {
    kind: :pure,
    shape: "sample(dist, rng, n) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "n draws from a distribution",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "seed",
  {
    kind: :pure,
    shape: "seed(value) -> rng",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a random stream fixed by a number or text",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "variance",
  {
    kind: :pure,
    shape: "variance(dist) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "spread of a distribution",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kakuritsu?",
  "weighted",
  {
    kind: :pure,
    shape: "weighted(rng, items, weights) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "one item chosen by weight",
    wave: 2,
    origin: "A"
  }
)

edge(
  "kakuritsu?::bytes",
  :composes,
  "kakuritsu?::draw",
  "fill bytes from draws"
)

edge(
  "kakuritsu?::fork",
  :composes,
  "kakuritsu?::draw",
  "derive two child seeds"
)

edge("kakuritsu?::int", :composes, "kakuritsu?::draw", "scale into a range")

edge(
  "kakuritsu?::weighted",
  :composes,
  "kakuritsu?::draw",
  "walk cumulative weights"
)

edge("kakuritsu?::choice", :composes, "kakuritsu?::int", "pick an index")

edge(
  "kakuritsu?::bayes",
  :composes,
  "kakuritsu?::likelihood",
  "prior times likelihood"
)

edge(
  "kakuritsu?::likelihood",
  :composes,
  "kakuritsu?::pdf",
  "product of densities"
)

edge(
  "kakuritsu?::sample",
  :composes,
  "kakuritsu?::quantile",
  "inverse transform sampling"
)

edge(
  "kakuritsu?::bootstrap",
  :composes,
  "kakuritsu?::sample",
  "resample the data"
)

edge(
  "kakuritsu?::estimate",
  :composes,
  "kakuritsu?::sample",
  "average f over draws"
)

edge(
  "kakuritsu?::seed",
  :composes,
  "shomei::hash",
  "text seeds hash to a state"
)

edge("kakuritsu?::fit", :composes, "toukei::mean", "estimate the centre")

edge(
  "kakuritsu?::bootstrap",
  :composes,
  "toukei::percentile",
  "read the interval"
)

edge("kakuritsu?::fit", :composes, "toukei::stddev", "estimate the spread")

edge(
  "kakuritsu?::draw",
  :generalizes,
  "kakuritsu?::int",
  "int is a scaled draw"
)

edge(
  "kakuritsu?::expectation",
  :generalizes,
  "kakuritsu?::mean",
  "mean of f(x)"
)

edge(
  "kakuritsu?::seed",
  :guards,
  "kakuritsu?::draw",
  "every draw needs a stream"
)

edge(
  "kakuritsu?::distribution",
  :guards,
  "kakuritsu?::pdf",
  "queries need a distribution"
)

edge("kakuritsu?::quantile", :inverse, "kakuritsu?::cdf", "quantile undoes cdf")
edge("kakuritsu?::sample", :inverse, "kakuritsu?::fit", "estimate from draws")
edge("kakuritsu?::cdf", :inverse, "kakuritsu?::quantile", "quantile undoes cdf")
edge("kakuritsu?::fit", :inverse, "kakuritsu?::sample", "estimate from draws")
edge("kakuritsu?::sample", :lifts, "kakuritsu?::draw", "n draws at once")

edge(
  "kakuritsu?::pdf",
  :pairs,
  "kakuritsu?::cdf",
  "density and its running total"
)

edge("kakuritsu?::bytes", :pairs, "kakuritsu?::entropy", "seeded versus system")
edge("kakuritsu?::draw", :pairs, "kakuritsu?::entropy", "seeded versus system")

edge(
  "kakuritsu?::estimate",
  :pairs,
  "kakuritsu?::expectation",
  "simulated versus exact average"
)

edge(
  "kakuritsu?::entropy",
  :pairs,
  "kakuritsu?::seed",
  "the only way to a fresh seed"
)

edge("kakuritsu?::mean", :pairs, "kakuritsu?::variance", "centre and spread")

edge(
  "kakuritsu?::distribution",
  :pairs,
  "sukiima?::shape",
  "params are a record"
)

edge("kakuritsu?::mean", :pairs, "toukei::mean", "distribution versus data")

edge(
  "kakuritsu?::quantile",
  :pairs,
  "toukei::percentile",
  "distribution versus data"
)

edge(
  "kakuritsu?::variance",
  :pairs,
  "toukei::variance",
  "distribution versus data"
)

edge("kakuritsu?::choice", :refines, "kakuritsu?::weighted", "equal weights")
