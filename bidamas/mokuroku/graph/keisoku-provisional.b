space("keisoku?", {status: :provisional})

verb(
  "keisoku?",
  "bench",
  {
    kind: :effect,
    shape: "bench(f, opts) -> stats",
    laterals: ["deadline", "time"],
    fleet: "tundra-gwbench",
    today: "absent",
    meaning: "run f many times; report spread, not one number",
    wave: 1,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "cardinality",
  {
    kind: :pure,
    shape: "cardinality(samples) -> [row]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "distinct series per metric, to catch label explosions",
    wave: 2,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "counter",
  {
    kind: :decl,
    shape: "counter(name, opts) -> instrument",
    laterals: ["config"],
    fleet: "metrics-go",
    today: "absent",
    meaning: "declare a value that only goes up",
    wave: 0,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b, opts) -> [change]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "compare two profiles or bench runs, with significance",
    wave: 2,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "gauge",
  {
    kind: :decl,
    shape: "gauge(name, opts) -> instrument",
    laterals: ["config"],
    fleet: "metrics-go",
    today: "absent",
    meaning: "declare a value that goes up and down",
    wave: 0,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "histogram",
  {
    kind: :decl,
    shape: "histogram(name, bounds, opts) -> instrument",
    laterals: ["config"],
    fleet: "metrics-go",
    today: "partial:kyuuji",
    meaning: "declare a value recorded into buckets",
    wave: 0,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "increase",
  {
    kind: :effect,
    shape: "increase(counter, by, labels) -> nil",
    laterals: ["idempotent"],
    fleet: "metrics-go",
    today: "absent",
    meaning: "add to a counter",
    wave: 0,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "measure",
  {
    kind: :effect,
    shape: "measure(histogram, f, labels) -> value",
    laterals: ["error", "time"],
    fleet: "metrics-go",
    today: "absent",
    meaning: "run f and record how long it took",
    wave: 0,
    origin: "F",
    contract: "measure(histogram, f, opts) -> value"
  }
)

verb(
  "keisoku?",
  "observe",
  {
    kind: :effect,
    shape: "observe(histogram, value, labels) -> nil",
    laterals: ["time"],
    fleet: "metrics-go",
    today: "exists:kyuuji",
    meaning: "record one value into a histogram",
    wave: 0,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> [sample]",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "exposition text (Prometheus, OpenMetrics) to samples",
    wave: 1,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "profile",
  {
    kind: :effect,
    shape: "profile(f, opts) -> profile",
    laterals: ["resource", "time"],
    fleet: nil,
    today: "rust:blue-lang-cli",
    meaning: "run f and report calls, time and allocation per function",
    wave: 0,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "push",
  {
    kind: :effect,
    shape: "push(sink, samples, opts) -> nil",
    laterals: ["deadline", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "send samples to a remote store",
    wave: 2,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "put",
  {
    kind: :effect,
    shape: "put(gauge, value, labels) -> nil",
    laterals: ["idempotent"],
    fleet: "metrics-go",
    today: "absent",
    meaning: "set a gauge to a value",
    wave: 0,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "quantile",
  {
    kind: :pure,
    shape: "quantile(histogram, q) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "estimate a quantile from buckets",
    wave: 1,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "query",
  {
    kind: :effect,
    shape: "query(store, expr, opts) -> [series]",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "ask a metrics store with its query language",
    wave: 2,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "rate",
  {
    kind: :pure,
    shape: "rate(series, window) -> series",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "per-second change of a counter over a window",
    wave: 1,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "read",
  {
    kind: :effect,
    shape: "read(source, opts) -> [sample]",
    laterals: ["deadline", "serialize"],
    fleet: nil,
    today: "absent",
    meaning: "scrape samples from an endpoint or exposition text",
    wave: 1,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "render",
  {
    kind: :pure,
    shape: "render(samples, format) -> text",
    laterals: ["serialize"],
    fleet: "metrics-go",
    today: "exists:kyuuji",
    meaning: "samples to exposition text, stable order",
    wave: 0,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "top",
  {
    kind: :pure,
    shape: "top(profile, n, by) -> [row]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the n costliest functions of a profile",
    wave: 1,
    origin: "F"
  }
)

verb(
  "keisoku?",
  "watch",
  {
    kind: :stream,
    shape: "watch(source, f, opts) -> nil",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "call f per scrape until it returns stop",
    wave: 2,
    origin: "F"
  }
)

edge(
  "keisoku?::measure",
  :composes,
  "keisoku?::observe",
  "times f, observes the span"
)

edge(
  "keisoku?::read",
  :composes,
  "keisoku?::parse",
  "scrape text then parse it"
)

edge("keisoku?::top", :composes, "keisoku?::profile", "ranks profile rows")

edge(
  "keisoku?::query",
  :composes,
  "keisoku?::quantile",
  "queries apply quantile"
)

edge("keisoku?::query", :composes, "keisoku?::rate", "queries apply rate")

edge(
  "keisoku?::query",
  :generalizes,
  "keisoku?::read",
  "asks a store, not an endpoint"
)

edge(
  "keisoku?::cardinality",
  :guards,
  "keisoku?::increase",
  "catches label explosions"
)

edge(
  "keisoku?::render",
  :inverse,
  "keisoku?::parse",
  "samples to text and back"
)

edge("keisoku?::read", :inverse, "keisoku?::push", "send and scrape")
edge("keisoku?::push", :inverse, "keisoku?::read", "send and scrape")

edge(
  "keisoku?::parse",
  :inverse,
  "keisoku?::render",
  "samples to text and back"
)

edge("keisoku?::watch", :lifts, "keisoku?::read", "follows scrapes")
edge("keisoku?::top", :pairs, "genin?::diagnose", "hot spots are evidence")

edge(
  "keisoku?::profile",
  :pairs,
  "genin?::trace",
  "both observe a running program"
)

edge("keisoku?::bench", :pairs, "hadome::judge", "bench results get a ratchet")
edge("keisoku?::counter", :pairs, "keisoku?::gauge", "two instrument kinds")
edge("keisoku?::gauge", :pairs, "keisoku?::histogram", "two instrument kinds")

edge(
  "keisoku?::histogram",
  :pairs,
  "keisoku?::quantile",
  "buckets then quantile"
)

edge("keisoku?::increase", :pairs, "keisoku?::rate", "counter then rate")

edge(
  "keisoku?::push",
  :pairs,
  "keisoku?::render",
  "remote write sends rendered samples"
)

edge("keisoku?::watch", :pairs, "shihyou::alerts", "feeds alert rules")
edge("keisoku?::measure", :pairs, "tsuiseki?::span", "one timing, two records")
edge("keisoku?::put", :refines, "jisho::put", "store verb for gauges")

edge(
  "keisoku?::bench",
  :refines,
  "keisoku?::measure",
  "repeated, with statistics"
)

edge("keisoku?::diff", :requires, "keisoku?::bench", "compares bench runs")

edge(
  "keisoku?::counter",
  :requires,
  "keisoku?::increase",
  "instrument before use"
)

edge(
  "keisoku?::rate",
  :requires,
  "keisoku?::increase",
  "a rate needs a counter"
)

edge("keisoku?::profile", :requires, "keisoku?::measure", "time per function")

edge(
  "keisoku?::histogram",
  :requires,
  "keisoku?::observe",
  "instrument before use"
)

edge(
  "keisoku?::quantile",
  :requires,
  "keisoku?::observe",
  "needs histogram buckets"
)

edge("keisoku?::diff", :requires, "keisoku?::profile", "compares profiles")
edge("keisoku?::gauge", :requires, "keisoku?::put", "instrument before use")

edge(
  "keisoku?::cardinality",
  :requires,
  "keisoku?::read",
  "counts scraped series"
)

edge("keisoku?::parse", :requires, "keisoku?::read", "text from a scrape")
