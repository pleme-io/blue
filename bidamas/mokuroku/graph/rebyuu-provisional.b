space("rebyuu?", {status: :provisional})

verb(
  "rebyuu?",
  "approve",
  {
    kind: :effect,
    shape: "approve(review, opts) -> nil",
    laterals: ["capability", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "record that the reviewer accepts the change",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "assign",
  {
    kind: :effect,
    shape: "assign(review, who) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "name the reviewers who must answer",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "block",
  {
    kind: :effect,
    shape: "block(review, reason) -> nil",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "record a reason the change must not land",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "catchup",
  {
    kind: :effect,
    shape: "catchup(review, opts) -> nil",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "bring the review branch up to its base by merge",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "comment",
  {
    kind: :effect,
    shape: "comment(review, at, text) -> thread",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "start a thread on a line or the whole change",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "land",
  {
    kind: :effect,
    shape: "land(review, opts) -> commit",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "merge a ready review by the repo policy",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "list",
  {
    kind: :effect,
    shape: "list(source, filter) -> [review]",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "reviews matching a filter, all pages",
    wave: 2,
    origin: "F",
    contract: "list(source, opts) -> [review]"
  }
)

verb(
  "rebyuu?",
  "owners",
  {
    kind: :pure,
    shape: "owners(paths, rules) -> [who]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the people who own the paths a change touches",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "read",
  {
    kind: :effect,
    shape: "read(review) -> record",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "a review with its threads, checks and state",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "ready?",
  {
    kind: :effect,
    shape: "ready?(review) -> verdict",
    laterals: ["capability", "test"],
    fleet: nil,
    today: "absent",
    meaning: "whether checks, approvals and threads allow landing",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "request",
  {
    kind: :effect,
    shape: "request(change, reviewers, opts) -> review",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "ask for review of a change",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "resolve",
  {
    kind: :effect,
    shape: "resolve(thread) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "mark a thread as dealt with",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "size",
  {
    kind: :pure,
    shape: "size(review) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "lines, files and areas a change touches",
    wave: 3,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "suggest",
  {
    kind: :effect,
    shape: "suggest(review, at, patch) -> thread",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "propose an exact edit the author can accept",
    wave: 3,
    origin: "F"
  }
)

verb(
  "rebyuu?",
  "train",
  {
    kind: :effect,
    shape: "train(reviews) -> [review]",
    laterals: ["error"],
    fleet: "confluence-pr-refresh",
    today: "absent",
    meaning: "reviews that depend on each other, in merge order",
    wave: 2,
    origin: "F"
  }
)

edge("rebyuu?::size", :composes, "gitto::diff", "measures the diff")

edge(
  "rebyuu?::catchup",
  :composes,
  "gitto::merge",
  "branch is updated by merge"
)

edge("rebyuu?::land", :composes, "gitto::merge", "merge by repo policy")

edge(
  "rebyuu?::request",
  :composes,
  "habu::create",
  "a pull request is a habu entry"
)

edge("rebyuu?::read", :composes, "habu::get", "a pull request by id")
edge("rebyuu?::list", :composes, "habu::list", "filtered pull requests")

edge(
  "rebyuu?::suggest",
  :composes,
  "kakikae?::apply",
  "accepted patch is applied"
)

edge("rebyuu?::ready?", :composes, "rebyuu?::approve", "approvals counted")
edge("rebyuu?::ready?", :composes, "tesuto?::run", "checks counted")
edge("rebyuu?::block", :guards, "rebyuu?::land", "a block stops landing")
edge("rebyuu?::request", :pairs, "gitto::push", "push then request")
edge("rebyuu?::block", :pairs, "rebyuu?::approve", "the two verdicts")

edge(
  "rebyuu?::request",
  :pairs,
  "rebyuu?::assign",
  "request then name reviewers"
)

edge(
  "rebyuu?::size",
  :pairs,
  "rebyuu?::assign",
  "big changes need more reviewers"
)

edge("rebyuu?::train", :pairs, "rebyuu?::land", "land in stack order")
edge("rebyuu?::read", :pairs, "rebyuu?::list", "one versus many")
edge("rebyuu?::approve", :pairs, "rebyuu?::ready?", "approvals count")
edge("rebyuu?::comment", :pairs, "rebyuu?::resolve", "open and close a thread")

edge(
  "rebyuu?::catchup",
  :pairs,
  "rebyuu?::train",
  "stacks are updated in order"
)

edge("rebyuu?::owners", :pairs, "youken?::trace", "owners know the needs")
edge("rebyuu?::suggest", :refines, "rebyuu?::comment", "comment with a patch")
edge("rebyuu?::train", :requires, "gitto::ancestor?", "order by ancestry")
edge("rebyuu?::owners", :requires, "gitto::diff", "paths the change touches")
edge("rebyuu?::resolve", :requires, "rebyuu?::comment", "closes a thread")
edge("rebyuu?::assign", :requires, "rebyuu?::owners", "picks reviewers")
edge("rebyuu?::approve", :requires, "rebyuu?::read", "approves what was read")
edge("rebyuu?::comment", :requires, "rebyuu?::read", "comments on a review")
edge("rebyuu?::land", :requires, "rebyuu?::ready?", "land only when ready")
