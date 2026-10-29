space("kansuu", {status: :ratified})

verb(
  "kansuu",
  "compose",
  {
    kind: :pure,
    shape: "compose(fs) -> function",
    laterals: [],
    fleet: nil,
    today: "exists:kansuu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kansuu",
  "constantly",
  {
    kind: :pure,
    shape: "constantly(x) -> function",
    laterals: [],
    fleet: nil,
    today: "exists:kansuu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kansuu",
  "curry",
  {
    kind: :pure,
    shape: "curry(f, arity) -> function",
    laterals: [],
    fleet: nil,
    today: "partial:kansuu",
    meaning: "function that takes arguments one at a time",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kansuu",
  "fixpoint",
  {
    kind: :pure,
    shape: "fixpoint(f, x, opts) -> value",
    laterals: ["error"],
    fleet: nil,
    today: "partial:kansuu",
    meaning: "apply f until the result stops changing",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kansuu",
  "flip",
  {
    kind: :pure,
    shape: "flip(f) -> function",
    laterals: [],
    fleet: nil,
    today: "exists:kansuu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kansuu",
  "identity",
  {
    kind: :pure,
    shape: "identity(x) -> x",
    laterals: [],
    fleet: nil,
    today: "exists:kansuu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kansuu",
  "iterate",
  {
    kind: :pure,
    shape: "iterate(f, x, n) -> value",
    laterals: [],
    fleet: nil,
    today: "partial:kansuu",
    meaning: "apply f to x n times",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kansuu",
  "juxt",
  {
    kind: :pure,
    shape: "juxt(fs) -> function",
    laterals: [],
    fleet: nil,
    today: "exists:kansuu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kansuu",
  "memoize",
  {
    kind: :pure,
    shape: "memoize(f) -> function",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "function that remembers results per argument",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kansuu",
  "once",
  {
    kind: :pure,
    shape: "once(f) -> function",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "function that runs f only the first time",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kansuu",
  "partial",
  {
    kind: :pure,
    shape: "partial(f, args) -> function",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "function with leading arguments fixed",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kansuu",
  "pipe",
  {
    kind: :pure,
    shape: "pipe(x, fs) -> value",
    laterals: [],
    fleet: nil,
    today: "exists:kansuu",
    wave: 0,
    origin: "A",
    contract: "pipe(x, opts) -> value"
  }
)

verb(
  "kansuu",
  "tap",
  {
    kind: :pure,
    shape: "tap(x, f) -> x",
    laterals: [],
    fleet: nil,
    today: "exists:kansuu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kansuu",
  "volatile",
  {
    kind: :decl,
    shape: "volatile(f) -> nil",
    laterals: ["cache"],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "declare that f and every caller run on each call, never answered from the call memo",
    wave: 0,
    origin: "A"
  }
)

edge("kansuu::memoize", :composes, "jisho::put", "the cache is a map")

edge(
  "kansuu::iterate",
  :composes,
  "kansuu::compose",
  "compose f with itself n times"
)

edge("kansuu::pipe", :composes, "kansuu::compose", "reversed compose applied")
edge("kansuu::partial", :composes, "kansuu::curry", "curry then apply")
edge("kansuu::tap", :composes, "kansuu::identity", "returns the argument")
edge("kansuu::juxt", :composes, "retsu::map", "map each function over x")

edge(
  "kansuu::compose",
  :composes,
  "retsu::reduce",
  "fold the list of functions"
)

edge(
  "kansuu::fixpoint",
  :generalizes,
  "kansuu::iterate",
  "iterate until stable"
)

edge("kansuu::juxt", :pairs, "kansuu::compose", "fan out versus chain")

edge(
  "kansuu::identity",
  :pairs,
  "kansuu::constantly",
  "returns self versus fixed"
)

edge("kansuu::flip", :pairs, "kansuu::curry", "argument order and arity")

edge(
  "kansuu::memoize",
  :pairs,
  "kansuu::once",
  "remember per argument versus once"
)

edge("kansuu::curry", :pairs, "kansuu::partial", "all-at-once versus some")

edge(
  "kansuu::compose",
  :pairs,
  "kansuu::pipe",
  "right-to-left and left-to-right"
)

edge("kansuu::once", :refines, "kansuu::memoize", "memoize with no arguments")

edge(
  "kansuu::volatile",
  :pairs,
  "kansuu::memoize",
  "never cached versus cached on request"
)
