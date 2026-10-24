space("kumiawase", {status: :ratified})

verb(
  "kumiawase",
  "choose",
  {
    kind: :pure,
    shape: "choose(n, k) -> big",
    laterals: ["error"],
    fleet: nil,
    today: "exists:kumiawase",
    wave: 0,
    origin: "A",
    contract: "choose(n, opts) -> big"
  }
)

verb(
  "kumiawase",
  "combinations",
  {
    kind: :pure,
    shape: "combinations(list, k) -> [list]",
    laterals: [],
    fleet: nil,
    today: "exists:kumiawase",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kumiawase",
  "factorial",
  {
    kind: :pure,
    shape: "factorial(n) -> big",
    laterals: ["error"],
    fleet: nil,
    today: "exists:kumiawase",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kumiawase",
  "partitions",
  {
    kind: :pure,
    shape: "partitions(n) -> [list]",
    laterals: [],
    fleet: nil,
    today: "exists:kumiawase",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kumiawase",
  "permutations",
  {
    kind: :pure,
    shape: "permutations(list, k) -> [list]",
    laterals: [],
    fleet: nil,
    today: "exists:kumiawase",
    wave: 0,
    origin: "A"
  }
)

edge("kumiawase::choose", :composes, "kumiawase::factorial", "n! over k!(n-k)!")
edge("kumiawase::factorial", :composes, "retsu::reduce", "product of 1 up to n")

edge(
  "kumiawase::combinations",
  :pairs,
  "kumiawase::choose",
  "count equals choose"
)

edge(
  "kumiawase::factorial",
  :pairs,
  "kumiawase::choose",
  "choose uses factorials"
)

edge(
  "kumiawase::permutations",
  :pairs,
  "kumiawase::factorial",
  "n! orders of n items"
)

edge(
  "kumiawase::partitions",
  :pairs,
  "kumiawase::permutations",
  "both enumerate arrangements"
)

edge(
  "kumiawase::permutations",
  :pairs,
  "retsu::shuffle",
  "one random permutation"
)

edge(
  "kumiawase::factorial",
  :requires,
  "seimitsu?::big",
  "results exceed 64 bits"
)
