space("toukei", {status: :ratified})

verb(
  "toukei",
  "autocorrelation",
  {
    kind: :pure,
    shape: "autocorrelation(numbers, lag) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "how a series relates to itself later",
    wave: 3,
    origin: "A"
  }
)

verb(
  "toukei",
  "bootstrap",
  {
    kind: :pure,
    shape: "bootstrap(xs, f, n, seed) -> interval",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a confidence interval by seeded resampling",
    wave: 1,
    origin: "G"
  }
)

verb(
  "toukei",
  "correlate",
  {
    kind: :pure,
    shape: "correlate(xs, ys) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:toukei",
    meaning: "how two series move together",
    wave: 0,
    origin: "G"
  }
)

verb(
  "toukei",
  "correlation",
  {
    kind: :pure,
    shape: "correlation(xs, ys) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "exists:toukei",
    meaning: "strength of a linear link, -1 to 1",
    wave: 0,
    origin: "A"
  }
)

verb(
  "toukei",
  "covariance",
  {
    kind: :pure,
    shape: "covariance(xs, ys) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "exists:toukei",
    meaning: "how two series vary together",
    wave: 0,
    origin: "A"
  }
)

verb(
  "toukei",
  "describe",
  {
    kind: :pure,
    shape: "describe(xs) -> summary",
    laterals: [],
    fleet: nil,
    today: "exists:toukei",
    meaning: "count, mean, spread and quartiles",
    wave: 0,
    origin: "G"
  }
)

verb(
  "toukei",
  "ewma",
  {
    kind: :pure,
    shape: "ewma(numbers, alpha) -> [number]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "exponentially weighted moving average",
    wave: 2,
    origin: "A"
  }
)

verb(
  "toukei",
  "histogram",
  {
    kind: :pure,
    shape: "histogram(numbers, bins) -> [bin]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "counts of values per equal-width bin",
    wave: 2,
    origin: "A"
  }
)

verb(
  "toukei",
  "hypothesis",
  {
    kind: :pure,
    shape: "hypothesis(kind, samples, opts) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "t, chi-square or other test: statistic and p-value",
    wave: 1,
    origin: "A",
    contract: "hypothesis(kind, samples, kind) -> record"
  }
)

verb(
  "toukei",
  "interval",
  {
    kind: :pure,
    shape: "interval(numbers, level) -> range",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "confidence interval for the mean",
    wave: 3,
    origin: "A"
  }
)

verb(
  "toukei",
  "mean",
  {
    kind: :pure,
    shape: "mean(numbers) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "exists:toukei",
    meaning: "arithmetic average; empty raises",
    wave: 0,
    origin: "A"
  }
)

verb(
  "toukei",
  "median",
  {
    kind: :pure,
    shape: "median(numbers) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "exists:toukei",
    meaning: "middle value",
    wave: 0,
    origin: "A"
  }
)

verb(
  "toukei",
  "mode",
  {
    kind: :pure,
    shape: "mode(items) -> item",
    laterals: [],
    fleet: nil,
    today: "exists:toukei",
    meaning: "most frequent value",
    wave: 0,
    origin: "A"
  }
)

verb(
  "toukei",
  "moving_average",
  {
    kind: :pure,
    shape: "moving_average(numbers, n) -> [number]",
    laterals: [],
    fleet: nil,
    today: "exists:toukei",
    meaning: "average over a sliding window",
    wave: 0,
    origin: "A"
  }
)

verb(
  "toukei",
  "normalize",
  {
    kind: :pure,
    shape: "normalize(numbers, opts) -> [number]",
    laterals: [],
    fleet: nil,
    today: "partial:toukei",
    meaning: "rescale to a range or to unit variance",
    wave: 1,
    origin: "A"
  }
)

verb(
  "toukei",
  "outliers",
  {
    kind: :pure,
    shape: "outliers(numbers, opts) -> [number]",
    laterals: [],
    fleet: nil,
    today: "exists:toukei",
    meaning: "values beyond the quartile fences",
    wave: 0,
    origin: "A"
  }
)

verb(
  "toukei",
  "percentile",
  {
    kind: :pure,
    shape: "percentile(numbers, p) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "exists:toukei",
    meaning: "value below which a share p falls",
    wave: 0,
    origin: "A"
  }
)

verb(
  "toukei",
  "predict",
  {
    kind: :pure,
    shape: "predict(model, x) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "value a fitted model gives at x",
    wave: 2,
    origin: "A"
  }
)

verb(
  "toukei",
  "regression",
  {
    kind: :pure,
    shape: "regression(xs, ys, opts) -> model",
    laterals: ["error"],
    fleet: "kinji",
    today: "partial:kinji",
    meaning: "best-fit line or polynomial and its error",
    wave: 2,
    origin: "A"
  }
)

verb(
  "toukei",
  "rolling",
  {
    kind: :pure,
    shape: "rolling(numbers, n, f) -> [number]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "f over a sliding window",
    wave: 2,
    origin: "A"
  }
)

verb(
  "toukei",
  "stddev",
  {
    kind: :pure,
    shape: "stddev(numbers, opts) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "exists:toukei",
    meaning: "square root of the variance",
    wave: 0,
    origin: "A"
  }
)

verb(
  "toukei",
  "summary",
  {
    kind: :pure,
    shape: "summary(numbers) -> record",
    laterals: [],
    fleet: nil,
    today: "exists:toukei",
    meaning: "count, extremes, quartiles, mean and spread",
    wave: 0,
    origin: "A"
  }
)

verb(
  "toukei",
  "variance",
  {
    kind: :pure,
    shape: "variance(numbers, opts) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "exists:toukei",
    meaning: "mean squared distance from the mean",
    wave: 0,
    origin: "A"
  }
)

verb(
  "toukei",
  "zscore",
  {
    kind: :pure,
    shape: "zscore(numbers) -> [number]",
    laterals: ["error"],
    fleet: nil,
    today: "exists:toukei",
    meaning: "distance from the mean in standard deviations",
    wave: 0,
    origin: "A"
  }
)

edge("toukei::regression", :composes, "gyouretsu::solve", "normal equations")
edge("toukei::median", :composes, "junjo::sort", "middle of the order")

edge(
  "toukei::hypothesis",
  :composes,
  "kakuritsu?::cdf",
  "p-value from the distribution"
)

edge("toukei::interval", :composes, "kakuritsu?::quantile", "critical value")
edge("toukei::mean", :composes, "kazu::sum", "total over count")
edge("toukei::histogram", :composes, "retsu::group_by", "group by bin")
edge("toukei::mode", :composes, "retsu::tally", "largest tally")
edge("toukei::rolling", :composes, "retsu::windows", "f over each window")

edge(
  "toukei::correlation",
  :composes,
  "toukei::covariance",
  "scaled by deviations"
)

edge(
  "toukei::regression",
  :composes,
  "toukei::covariance",
  "slope from covariance"
)

edge("toukei::covariance", :composes, "toukei::mean", "mean of products")
edge("toukei::summary", :composes, "toukei::mean", "centre")

edge(
  "toukei::variance",
  :composes,
  "toukei::mean",
  "squared distance from the mean"
)

edge("toukei::zscore", :composes, "toukei::mean", "centre first")
edge("toukei::outliers", :composes, "toukei::percentile", "quartile fences")
edge("toukei::summary", :composes, "toukei::percentile", "quartiles")
edge("toukei::correlation", :composes, "toukei::stddev", "scaled by deviations")
edge("toukei::interval", :composes, "toukei::stddev", "spread of the mean")
edge("toukei::zscore", :composes, "toukei::stddev", "distance in deviations")
edge("toukei::stddev", :composes, "toukei::variance", "square root")
edge("toukei::normalize", :composes, "toukei::zscore", "unit variance form")

edge(
  "toukei::percentile",
  :pairs,
  "toukei::histogram",
  "position versus counts"
)

edge("toukei::hypothesis", :pairs, "toukei::interval", "verdict and range")
edge("toukei::mode", :pairs, "toukei::mean", "most common and average")
edge("toukei::mean", :pairs, "toukei::median", "average and middle")
edge("toukei::ewma", :pairs, "toukei::moving_average", "weighted versus flat")
edge("toukei::variance", :pairs, "toukei::stddev", "squared and rooted")

edge(
  "toukei::autocorrelation",
  :refines,
  "toukei::correlation",
  "a series against itself"
)

edge("toukei::median", :refines, "toukei::percentile", "percentile fifty")
edge("toukei::moving_average", :refines, "toukei::rolling", "rolling mean")
edge("toukei::percentile", :requires, "junjo::sort", "reads a sorted list")
edge("toukei::bootstrap", :requires, "ran::draw", "seeded resampling")
edge("toukei::describe", :requires, "toukei::correlate", "summary of series")

edge(
  "toukei::bootstrap",
  :requires,
  "toukei::describe",
  "statistic of each resample"
)

edge("toukei::correlate", :requires, "toukei::describe", "two series")
edge("toukei::hypothesis", :requires, "toukei::describe", "test on summaries")
edge("toukei::predict", :requires, "toukei::regression", "needs a fitted model")
