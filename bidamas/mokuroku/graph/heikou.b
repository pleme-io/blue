space("heikou", {status: :ratified})

verb(
  "heikou",
  "all",
  {
    kind: :effect,
    shape: "all(fs, opts) -> [value]",
    laterals: ["cancel", "error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "Run all; first failure cancels the rest.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "any",
  {
    kind: :effect,
    shape: "any(fs, opts) -> value",
    laterals: ["cancel", "error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "Return the first success; fail only if all fail.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "backoff",
  {
    kind: :pure,
    shape: "backoff(policy, attempt) -> duration",
    laterals: ["retry", "time"],
    fleet: nil,
    today: "absent",
    meaning: "The wait before a given attempt.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "batch",
  {
    kind: :pure,
    shape: "batch(xs, size) -> [[x]]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Cut a list into groups of a size.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "cancel",
  {
    kind: :effect,
    shape: "cancel(token, reason) -> nil",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "Signal cancellation to everything holding the token.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "cancelled?",
  {
    kind: :pure,
    shape: "cancelled?(token) -> Bool",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "Whether cancellation was signalled.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "deadline",
  {
    kind: :effect,
    shape: "deadline(instant, f) -> value",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Run f with an absolute deadline inherited by callees.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "debounce",
  {
    kind: :effect,
    shape: "debounce(f, duration) -> function",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "Call f once after calls stop for a duration.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "heikou",
  "each",
  {
    kind: :effect,
    shape: "each(xs, f, opts) -> nil",
    laterals: ["cancel", "error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "Parallel side effects with a limit.",
    wave: 1,
    origin: "C",
    contract: "each(xs, f) -> nil"
  }
)

verb(
  "heikou",
  "limit",
  {
    kind: :decl,
    shape: "limit(count) -> semaphore",
    laterals: ["resource"],
    fleet: "shigoto-budget",
    today: "absent",
    meaning: "Make a bound on how many run at once.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "heikou",
  "map",
  {
    kind: :effect,
    shape: "map(xs, f, opts) -> [value]",
    laterals: ["cancel", "error", "process", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "Parallel map with a limit; results in order.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "policy",
  {
    kind: :decl,
    shape: "policy(opts) -> policy",
    laterals: ["config", "retry"],
    fleet: "shigoto-retry",
    today: "absent",
    meaning: "Declare attempts, backoff, jitter and which kinds retry.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "race",
  {
    kind: :effect,
    shape: "race(fs, opts) -> value",
    laterals: ["cancel", "process"],
    fleet: nil,
    today: "absent",
    meaning: "Return the first finisher; cancel the rest.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "remaining",
  {
    kind: :pure,
    shape: "remaining() -> duration",
    laterals: ["deadline", "time"],
    fleet: nil,
    today: "absent",
    meaning: "Time left before the current deadline.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "retry",
  {
    kind: :effect,
    shape: "retry(f, policy) -> value",
    laterals: ["deadline", "error", "retry", "time"],
    fleet: "shigoto-retry",
    today: "absent",
    meaning: "Call f again under a policy while its error is retryable.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "run",
  {
    kind: :effect,
    shape: "run(f, opts) -> value",
    laterals: ["deadline", "process"],
    fleet: nil,
    today: "absent",
    meaning: "Run f in a process with a timeout.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "scope",
  {
    kind: :effect,
    shape: "scope(f) -> value",
    laterals: ["cancel", "process", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "A scope where every child ends before it returns.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "heikou",
  "shield",
  {
    kind: :effect,
    shape: "shield(f) -> value",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "Run f to the end even if cancelled meanwhile.",
    wave: 3,
    origin: "C",
    contract: "shield(f, wrapping_key) -> value"
  }
)

verb(
  "heikou",
  "spawn",
  {
    kind: :effect,
    shape: "spawn(f, opts) -> handle",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Start f without waiting.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "stop",
  {
    kind: :effect,
    shape: "stop(handle, opts) -> nil",
    laterals: ["cancel", "process"],
    fleet: nil,
    today: "absent",
    meaning: "Cancel a handle and wait for it to end.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "throttle",
  {
    kind: :effect,
    shape: "throttle(f, duration) -> function",
    laterals: ["ratelimit", "time"],
    fleet: nil,
    today: "absent",
    meaning: "Call f at most once per duration.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "heikou",
  "timeout",
  {
    kind: :effect,
    shape: "timeout(f, duration) -> value",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Run f; raise timeout when the duration passes.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "token",
  {
    kind: :decl,
    shape: "token() -> cancel token",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "Make a token that signals cancellation.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "heikou",
  "wait",
  {
    kind: :effect,
    shape: "wait(handle, opts) -> value",
    laterals: ["deadline", "process"],
    fleet: nil,
    today: "absent",
    meaning: "Wait for a handle's result.",
    wave: 1,
    origin: "C"
  }
)

edge("heikou::map", :composes, "heikou::all", "map is all over f applied")
edge("heikou::retry", :composes, "heikou::backoff", "wait computed per attempt")
edge("heikou::race", :composes, "heikou::cancel", "cancel losers")
edge("heikou::stop", :composes, "heikou::cancel", "cancel then wait")
edge("heikou::all", :composes, "heikou::spawn", "spawn each, then wait")
edge("heikou::race", :composes, "heikou::spawn", "spawn all")
edge("heikou::run", :composes, "heikou::spawn", "spawn then wait")
edge("heikou::scope", :composes, "heikou::spawn", "children of one scope")

edge(
  "heikou::scope",
  :composes,
  "heikou::stop",
  "ends children at the scope end"
)

edge("heikou::run", :composes, "heikou::timeout", "bounded by a timeout")
edge("heikou::deadline", :composes, "heikou::token", "expiry cancels the token")
edge("heikou::all", :composes, "heikou::wait", "collect results")

edge(
  "heikou::throttle",
  :composes,
  "kyoujin?::bucket",
  "rate cap from a bucket"
)

edge("heikou::cancelled?", :guards, "heikou::cancel", "check before acting")
edge("heikou::shield", :guards, "heikou::cancel", "work survives cancellation")
edge("heikou::limit", :guards, "heikou::map", "bounds the concurrency")
edge("heikou::policy", :guards, "heikou::retry", "declared bounds on attempts")
edge("heikou::token", :inverse, "heikou::cancel", "make and fire a token")
edge("heikou::stop", :inverse, "heikou::spawn", "start and end")
edge("heikou::spawn", :inverse, "heikou::stop", "start and end")
edge("heikou::cancel", :inverse, "heikou::token", "make and fire a token")
edge("heikou::map", :lifts, "heikou::run", "many bounded runs")
edge("heikou::cancel", :pairs, "akutaa?::exit", "task cancel and process exit")
edge("heikou::run", :pairs, "akutaa?::spawn", "the task over the process")
edge("heikou::spawn", :pairs, "akutaa?::spawn", "task level over process level")

edge(
  "heikou::retry",
  :pairs,
  "heikou::deadline",
  "a deadline ends the attempts"
)

edge("heikou::batch", :pairs, "heikou::map", "batches then parallel work")
edge("heikou::deadline", :pairs, "heikou::remaining", "set and read the budget")

edge(
  "heikou::map",
  :pairs,
  "kyoujin?::bulkhead",
  "concurrency bound per resource"
)

edge("heikou::timeout", :pairs, "shigoto::after", "deadline versus timer")

edge(
  "heikou::timeout",
  :refines,
  "heikou::deadline",
  "relative form of a deadline"
)

edge("heikou::each", :refines, "heikou::map", "map that drops results")
edge("heikou::any", :refines, "heikou::race", "race that skips failures")

edge(
  "heikou::debounce",
  :refines,
  "heikou::throttle",
  "trailing edge instead of rate cap"
)

edge(
  "heikou::remaining",
  :requires,
  "heikou::deadline",
  "only inside a deadline"
)

edge("heikou::backoff", :requires, "heikou::policy", "derived from the policy")
edge("heikou::retry", :requires, "heikou::policy", "retry needs a policy")
edge("heikou::wait", :requires, "heikou::spawn", "waits on a handle")

edge(
  "heikou::all",
  :requires,
  "heikou::token",
  "first failure cancels through a token"
)

edge("heikou::cancel", :requires, "heikou::token", "fires a token")
edge("heikou::cancelled?", :requires, "heikou::token", "reads a token")
