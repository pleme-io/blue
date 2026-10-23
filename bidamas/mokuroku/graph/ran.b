space("ran", {status: :ratified})

verb(
  "ran",
  "draw",
  {
    kind: :pure,
    shape: "draw(seed, kind) -> {value, seed}",
    laterals: [],
    fleet: nil,
    today: "exists:ran",
    meaning: "the next random value and the next seed",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ran",
  "fork",
  {
    kind: :pure,
    shape: "fork(seed, label) -> seed",
    laterals: [],
    fleet: nil,
    today: "exists:ran",
    meaning: "a new independent seed from a parent seed",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ran",
  "pick",
  {
    kind: :pure,
    shape: "pick(seed, xs, opts) -> {value, seed}",
    laterals: [],
    fleet: nil,
    today: "exists:ran",
    meaning: "one random element, weighted if asked",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ran",
  "shuffle",
  {
    kind: :pure,
    shape: "shuffle(seed, xs) -> {value, seed}",
    laterals: [],
    fleet: nil,
    today: "exists:ran",
    meaning: "a random order of a list",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ran",
  "stream_seed",
  {
    kind: :pure,
    shape: "stream_seed(seed, i) -> seed",
    laterals: [],
    fleet: nil,
    today: "exists:ran",
    meaning: "the seed of stream i from one experiment seed",
    wave: 0,
    origin: "H"
  }
)

verb(
  "ran",
  "walk",
  {
    kind: :pure,
    shape: "walk(seed, steps, opts) -> path",
    laterals: [],
    fleet: nil,
    today: "exists:ran",
    meaning: "a seeded random walk",
    wave: 0,
    origin: "G",
    contract: "walk(seed, opts) -> path"
  }
)

edge("ran::walk", :composes, "ran::draw", "a draw per step")
edge("ran::shuffle", :composes, "ran::pick", "pick without repeat")
edge("ran::draw", :generalizes, "ran::pick", "a pick is a draw")
edge("ran::fork", :requires, "ran::draw", "a seed from a seed")
edge("ran::pick", :requires, "ran::draw", "one draw per pick")
edge("ran::shuffle", :requires, "ran::draw", "one draw per slot")
edge("ran::walk", :requires, "waarudo?::field", "walks over a field")
