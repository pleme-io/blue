space("saiten?", {status: :provisional})

verb(
  "saiten?",
  "agreement",
  {
    kind: :pure,
    shape: "agreement(raters) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "how far two judges or labelers agree: kappa",
    wave: 2,
    origin: "G"
  }
)

verb(
  "saiten?",
  "balance",
  {
    kind: :pure,
    shape: "balance(dataset, by, opts) -> dataset",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "even out classes by seeded sampling",
    wave: 2,
    origin: "G"
  }
)

verb(
  "saiten?",
  "calibrate",
  {
    kind: :pure,
    shape: "calibrate(scores, labels) -> curve",
    laterals: [],
    fleet: "chokkan",
    today: "absent",
    meaning: "map raw scores to true rates",
    wave: 3,
    origin: "G"
  }
)

verb(
  "saiten?",
  "case",
  {
    kind: :decl,
    shape: "case(input, expected, meta) -> case",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare one evaluation case",
    wave: 1,
    origin: "G",
    contract: "case(input, expected) -> case"
  }
)

verb(
  "saiten?",
  "check",
  {
    kind: :pure,
    shape: "check(dataset, rules) -> findings",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "find rows that break the shape, leak or repeat",
    wave: 1,
    origin: "G"
  }
)

verb(
  "saiten?",
  "compare",
  {
    kind: :pure,
    shape: "compare(runs_a, runs_b, opts) -> report",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "which run is better, with spread and significance",
    wave: 2,
    origin: "G"
  }
)

verb(
  "saiten?",
  "dataset",
  {
    kind: :decl,
    shape: "dataset(rows, shape) -> dataset",
    laterals: ["serialize", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare training or test rows with a shape",
    wave: 1,
    origin: "G"
  }
)

verb(
  "saiten?",
  "dedupe",
  {
    kind: :pure,
    shape: "dedupe(dataset, opts) -> dataset",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "drop exact and near duplicate rows",
    wave: 2,
    origin: "G"
  }
)

verb(
  "saiten?",
  "diff",
  {
    kind: :pure,
    shape: "diff(baseline, results) -> changes",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "cases that got better or worse than a baseline",
    wave: 1,
    origin: "G"
  }
)

verb(
  "saiten?",
  "drift",
  {
    kind: :pure,
    shape: "drift(baseline, current) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "how far a new data set moved from the old",
    wave: 3,
    origin: "G"
  }
)

verb(
  "saiten?",
  "estimate",
  {
    kind: :pure,
    shape: "estimate(dataset, model) -> {tokens, cost}",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "tokens and cost of a run over a dataset",
    wave: 1,
    origin: "G"
  }
)

verb(
  "saiten?",
  "gate",
  {
    kind: :pure,
    shape: "gate(results, thresholds) -> verdict",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "pass or refuse a run against minimum scores",
    wave: 1,
    origin: "G"
  }
)

verb(
  "saiten?",
  "holdout",
  {
    kind: :pure,
    shape: "holdout(dataset, ratio, opts) -> {train, test}",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a stable split chosen by hash, not by position",
    wave: 1,
    origin: "G"
  }
)

verb(
  "saiten?",
  "judge",
  {
    kind: :effect,
    shape: "judge(a, b, criteria, opts) -> {winner, why}",
    laterals: ["cache", "deadline", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "blind pairwise grade of two outputs by a model",
    wave: 2,
    origin: "G"
  }
)

verb(
  "saiten?",
  "label",
  {
    kind: :effect,
    shape: "label(dataset, labeler, opts) -> dataset",
    laterals: ["cache", "deadline", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "add labels from a function, model or person",
    wave: 2,
    origin: "G"
  }
)

verb(
  "saiten?",
  "run",
  {
    kind: :effect,
    shape: "run(suite, subject, opts) -> results",
    laterals: ["cache", "deadline", "ratelimit", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "run every case on a function, model or agent",
    wave: 2,
    origin: "G"
  }
)

verb(
  "saiten?",
  "score",
  {
    kind: :pure,
    shape: "score(output, rubric) -> number",
    laterals: [],
    fleet: "chokkan",
    today: "partial:chokkan",
    meaning: "grade an output: exact, pattern, similarity or judge",
    wave: 1,
    origin: "G"
  }
)

verb(
  "saiten?",
  "suite",
  {
    kind: :decl,
    shape: "suite(cases, opts) -> suite",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare a set of cases with a metric",
    wave: 1,
    origin: "G"
  }
)

verb(
  "saiten?",
  "train",
  {
    kind: :effect,
    shape: "train(spec, dataset, opts) -> handle",
    laterals: ["cancel", "deadline", "resource"],
    fleet: "ml-forge",
    today: "absent",
    meaning: "start a hosted fine-tune; local GPU training stays Rust",
    wave: 4,
    origin: "G",
    contract: "train(spec) -> handle"
  }
)

edge("saiten?::estimate", :composes, "mokei?::cost", "price them")
edge("saiten?::estimate", :composes, "mokei?::tokens", "count tokens")
edge("saiten?::suite", :composes, "saiten?::case", "a suite holds cases")
edge("saiten?::run", :composes, "saiten?::score", "grade each output")
edge("saiten?::compare", :composes, "toukei::hypothesis", "significance")
edge("saiten?::dedupe", :guards, "saiten?::holdout", "clean before split")

edge(
  "saiten?::agreement",
  :guards,
  "saiten?::label",
  "trust labels only if raters agree"
)

edge("saiten?::gate", :guards, "saiten?::run", "stop a merge on a drop")
edge("saiten?::check", :guards, "saiten?::train", "no bad rows reach a run")
edge("saiten?::balance", :pairs, "saiten?::dedupe", "both shape a dataset")
edge("saiten?::diff", :pairs, "saiten?::gate", "diff then gate")
edge("saiten?::drift", :pairs, "saiten?::gate", "drift can gate")
edge("saiten?::judge", :refines, "saiten?::score", "a model grades")
edge("saiten?::check", :requires, "bunsho?::redact", "find personal data")
edge("saiten?::judge", :requires, "chokkan::choice", "a typed question")
edge("saiten?::label", :requires, "mokei?::classify", "model labels")
edge("saiten?::balance", :requires, "ran::pick", "seeded sampling")
edge("saiten?::score", :requires, "saiten?::case", "against the expected")
edge("saiten?::dataset", :requires, "saiten?::check", "rows meet the shape")
edge("saiten?::case", :requires, "saiten?::dataset", "cases are rows")
edge("saiten?::holdout", :requires, "saiten?::dedupe", "no leak into test")
edge("saiten?::train", :requires, "saiten?::estimate", "cost before start")
edge("saiten?::train", :requires, "saiten?::holdout", "train on the train part")
edge("saiten?::compare", :requires, "saiten?::run", "two result sets")
edge("saiten?::diff", :requires, "saiten?::run", "against a baseline")
edge("saiten?::calibrate", :requires, "saiten?::score", "raw scores to rates")
edge("saiten?::run", :requires, "saiten?::suite", "runs a suite")

edge(
  "saiten?::agreement",
  :requires,
  "toukei::correlate",
  "agreement is correlation"
)

edge("saiten?::calibrate", :requires, "toukei::describe", "rates from counts")
edge("saiten?::drift", :requires, "toukei::describe", "compare summaries")
edge("saiten?::gate", :requires, "toukei::hypothesis", "significance, not luck")
