space("kyohi", {status: :ratified})

verb(
  "kyohi",
  "check",
  {
    kind: :pure,
    shape: "check(subject, rules) -> [finding]",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "exists:kyohi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "kyohi",
  "enforce",
  {
    kind: :effect,
    shape: "enforce(subject, rules, opts) -> nil",
    laterals: ["error"],
    fleet: nil,
    today: "exists:kyohi",
    wave: 0,
    origin: "H"
  }
)

verb(
  "kyohi",
  "exit_status",
  {
    kind: :pure,
    shape: "exit_status(kind) -> int",
    laterals: ["error"],
    fleet: nil,
    today: "exists:kyohi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "kyohi",
  "kind",
  {
    kind: :pure,
    shape: "kind(refusal) -> keyword",
    laterals: ["error"],
    fleet: nil,
    today: "exists:kyohi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "kyohi",
  "kinds",
  {
    kind: :pure,
    shape: "kinds(refusals) -> [keyword]",
    laterals: ["error"],
    fleet: nil,
    today: "exists:kyohi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "kyohi",
  "ledger",
  {
    kind: :decl,
    shape: "ledger() -> [record]",
    laterals: ["config", "error"],
    fleet: nil,
    today: "exists:kyohi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "kyohi",
  "refusal",
  {
    kind: :pure,
    shape: "refusal(kind, why) -> refusal",
    laterals: ["error"],
    fleet: nil,
    today: "exists:kyohi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "kyohi",
  "retryable?",
  {
    kind: :pure,
    shape: "retryable?(kind) -> Bool",
    laterals: ["error", "retry"],
    fleet: nil,
    today: "exists:kyohi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "kyohi",
  "standing",
  {
    kind: :pure,
    shape: "standing(entries, marks) -> [entry]",
    laterals: ["error"],
    fleet: nil,
    today: "exists:kyohi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "kyohi",
  "why",
  {
    kind: :pure,
    shape: "why(refusal) -> text",
    laterals: ["error"],
    fleet: nil,
    today: "exists:kyohi",
    wave: 0,
    origin: "D"
  }
)

edge(
  "kyohi::enforce",
  :composes,
  "core::check",
  "the findings come from the master check"
)

edge("kyohi::check", :composes, "kyohi::kinds", "the kinds of the findings")

edge(
  "kyohi::ledger",
  :generalizes,
  "kyohi::kind",
  "kinds with status and retry"
)

edge("kyohi::ledger", :guards, "kengen?::permit", "denied is a ledger kind")
edge("kyohi::kinds", :lifts, "kyohi::kind", "kind of each refusal")

edge(
  "kyohi::check",
  :pairs,
  "kyohi::enforce",
  "enforce is the raising form of check"
)

edge("kyohi::refusal", :pairs, "kyohi::kind", "a refusal has a kind")
edge("kyohi::standing", :refines, "kyohi::check", "entries left standing")

edge(
  "kyohi::exit_status",
  :requires,
  "kyohi::ledger",
  "reads the status column"
)

edge("kyohi::retryable?", :requires, "kyohi::ledger", "reads the retry column")
edge("kyohi::check", :requires, "kyohi::refusal", "a finding is a refusal")
edge("kyohi::kind", :requires, "kyohi::refusal", "reads a refusal")
edge("kyohi::why", :requires, "kyohi::refusal", "reads a refusal")
