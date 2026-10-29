space("chigai?", {status: :provisional})

verb(
  "chigai?",
  "align",
  {
    kind: :pure,
    shape: "align(a, b, opts) -> [pair]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "pair up matching items of two sequences",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chigai?",
  "compose",
  {
    kind: :pure,
    shape: "compose(first, second) -> [hunk]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "one set of hunks equal to two in order",
    wave: 3,
    origin: "A"
  }
)

verb(
  "chigai?",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b, opts) -> [hunk]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "changes between two texts or lists",
    wave: 1,
    origin: "A"
  }
)

verb(
  "chigai?",
  "invert",
  {
    kind: :pure,
    shape: "invert(hunks) -> [hunk]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "hunks that undo the given hunks",
    wave: 2,
    origin: "A"
  }
)

verb(
  "chigai?",
  "lcs",
  {
    kind: :pure,
    shape: "lcs(a, b) -> list",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "longest common subsequence",
    wave: 2,
    origin: "A"
  }
)

verb(
  "chigai?",
  "merge3",
  {
    kind: :pure,
    shape: "merge3(base, ours, theirs, opts) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "three-way merge with the conflicts listed",
    wave: 2,
    origin: "A"
  }
)

verb(
  "chigai?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text) -> [hunk]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "unified diff text to hunks",
    wave: 1,
    origin: "A"
  }
)

verb(
  "chigai?",
  "patch",
  {
    kind: :pure,
    shape: "patch(a, hunks, opts) -> value",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "apply hunks; a mismatch raises conflict",
    wave: 1,
    origin: "A"
  }
)

verb(
  "chigai?",
  "stat",
  {
    kind: :pure,
    shape: "stat(hunks) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "lines added, removed and changed",
    wave: 1,
    origin: "A"
  }
)

verb(
  "chigai?",
  "unify",
  {
    kind: :pure,
    shape: "unify(hunks, opts) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "hunks as unified diff text",
    wave: 1,
    origin: "A"
  }
)

edge(
  "chigai?::merge3",
  :composes,
  "chigai?::diff",
  "diff base against each side"
)

edge("chigai?::stat", :composes, "chigai?::diff", "count the hunks")

edge(
  "chigai?::diff",
  :composes,
  "chigai?::lcs",
  "common parts anchor the hunks"
)

edge("chigai?::merge3", :composes, "chigai?::patch", "apply both sets of hunks")
edge("chigai?::diff", :composes, "moji::lines", "text diffs work line by line")
edge("chigai?::lcs", :composes, "retsu::zip", "pair the common items")

edge(
  "chigai?::align",
  :generalizes,
  "chigai?::lcs",
  "pairs instead of one list"
)

edge("chigai?::diff", :generalizes, "gitto::diff", "any sequence, not commits")
edge("chigai?::patch", :inverse, "chigai?::diff", "applies what diff finds")

edge(
  "chigai?::unify",
  :inverse,
  "chigai?::parse",
  "hunks and unified text round-trip"
)

edge("chigai?::diff", :inverse, "chigai?::patch", "applies what diff finds")

edge(
  "chigai?::parse",
  :inverse,
  "chigai?::unify",
  "hunks and unified text round-trip"
)

edge("chigai?::lcs", :pairs, "chigai?::diff", "diff is built on it")
edge("chigai?::compose", :pairs, "chigai?::invert", "combine and undo")
edge("chigai?::invert", :pairs, "chigai?::patch", "apply the inverse to undo")
edge("chigai?::stat", :pairs, "chigai?::unify", "summary and full listing")

edge(
  "chigai?::merge3",
  :pairs,
  "gitto::merge",
  "text level versus commit level"
)

edge("chigai?::invert", :requires, "chigai?::diff", "swaps each hunk's sides")
edge("chigai?::patch", :requires, "chigai?::parse", "hunks may arrive as text")
