space("rekishi?", {status: :provisional})

verb(
  "rekishi?",
  "ancestors",
  {
    kind: :effect,
    shape: "ancestors(repo, oid) -> [oid]",
    laterals: ["cancel", "error"],
    fleet: "daicho",
    today: "absent",
    meaning: "every commit that leads to this one",
    wave: 3,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "base",
  {
    kind: :effect,
    shape: "base(repo, a, b) -> oid or nil",
    laterals: ["error"],
    fleet: "daicho",
    today: "absent",
    meaning: "the newest common ancestor of two commits",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "bisect",
  {
    kind: :effect,
    shape: "bisect(repo, good, bad, test) -> oid",
    laterals: ["cancel", "deadline", "error"],
    fleet: nil,
    today: "absent",
    meaning: "find the first commit where a test turns bad",
    wave: 3,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "blame",
  {
    kind: :effect,
    shape: "blame(repo, path) -> [{line, commit}]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "the commit that last changed each line",
    wave: 3,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "commit",
  {
    kind: :effect,
    shape: "commit(repo, snapshot, opts) -> oid",
    laterals: ["error", "idempotent", "time"],
    fleet: "daicho",
    today: "absent",
    meaning: "record a snapshot with parents, author and a message",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "create",
  {
    kind: :effect,
    shape: "create(repo, name, oid) -> oid",
    laterals: ["error", "idempotent"],
    fleet: "galho",
    today: "absent",
    meaning: "add a branch or tag ref; exists if taken",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "delete",
  {
    kind: :effect,
    shape: "delete(repo, name) -> nil",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "remove a ref; absent counts as done",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "diff",
  {
    kind: :effect,
    shape: "diff(repo, a, b, opts) -> [change]",
    laterals: ["error"],
    fleet: "daicho",
    today: "absent",
    meaning: "the changes between two commits or refs",
    wave: 2,
    origin: "B",
    contract: "diff(repo, a, opts) -> [change]"
  }
)

verb(
  "rekishi?",
  "get",
  {
    kind: :effect,
    shape: "get(repo, ref) -> commit or nil",
    laterals: ["error"],
    fleet: "daicho",
    today: "absent",
    meaning: "the commit a ref or id names, or nil",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "graft",
  {
    kind: :effect,
    shape: "graft(repo, oid, onto) -> oid",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "replay one commit onto another line",
    wave: 3,
    origin: "B",
    contract: "graft(repo, oid) -> oid"
  }
)

verb(
  "rekishi?",
  "invert",
  {
    kind: :pure,
    shape: "invert(changes) -> changes",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the changes that undo these changes",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "list",
  {
    kind: :effect,
    shape: "list(repo, opts) -> [{name, oid}]",
    laterals: ["error"],
    fleet: "galho",
    today: "absent",
    meaning: "every ref, sorted",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "log",
  {
    kind: :effect,
    shape: "log(repo, opts) -> [commit]",
    laterals: ["error"],
    fleet: "daicho",
    today: "absent",
    meaning: "commits from a ref backward, optionally for a path",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "merge",
  {
    kind: :effect,
    shape: "merge(repo, a, b, opts) -> {oid, conflicts}",
    laterals: ["error", "idempotent"],
    fleet: "daicho",
    today: "absent",
    meaning: "join two histories with a strategy; conflicts are data",
    wave: 2,
    origin: "B",
    contract: "merge(repo, a, opts) -> {oid, conflicts}"
  }
)

verb(
  "rekishi?",
  "patch",
  {
    kind: :pure,
    shape: "patch(value, changes) -> value",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "apply change records to a value",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "read",
  {
    kind: :effect,
    shape: "read(repo, ref, path) -> content",
    laterals: ["error"],
    fleet: "daicho",
    today: "absent",
    meaning: "the content of a path as it was at a ref",
    wave: 2,
    origin: "B",
    contract: "read(repo, opts) -> content"
  }
)

verb(
  "rekishi?",
  "rebase",
  {
    kind: :effect,
    shape: "rebase(repo, branch, onto) -> oid",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "replay a branch commits on a new base",
    wave: 3,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "restore",
  {
    kind: :effect,
    shape: "restore(repo, ref, to) -> nil",
    laterals: ["capability", "error"],
    fleet: nil,
    today: "absent",
    meaning: "bring a past state back to a directory or store",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "revert",
  {
    kind: :effect,
    shape: "revert(repo, oid) -> oid",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "add a commit that undoes an earlier one",
    wave: 3,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "squash",
  {
    kind: :effect,
    shape: "squash(repo, from, to, opts) -> oid",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "fold a run of commits into one",
    wave: 3,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "three_way",
  {
    kind: :pure,
    shape: "three_way(base, ours, theirs) -> {merged, conflicts}",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "merge two edits of one base, marking overlaps",
    wave: 2,
    origin: "B"
  }
)

verb(
  "rekishi?",
  "update",
  {
    kind: :effect,
    shape: "update(repo, name, f) -> oid",
    laterals: ["error", "idempotent", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "move a ref with f(old) and refuse a concurrent move",
    wave: 2,
    origin: "B"
  }
)

edge("rekishi?::diff", :composes, "genbo?::diff", "compares trees")

edge(
  "rekishi?::restore",
  :composes,
  "genbo?::export",
  "writes the old tree out"
)

edge("rekishi?::read", :composes, "genbo?::get", "reads the stored content")
edge("rekishi?::commit", :composes, "genbo?::put", "stores the commit object")
edge("rekishi?::commit", :composes, "genbo?::tree", "snapshot becomes a tree")

edge(
  "rekishi?::base",
  :composes,
  "rekishi?::ancestors",
  "first shared ancestor"
)

edge("rekishi?::bisect", :composes, "rekishi?::ancestors", "narrows the range")
edge("rekishi?::merge", :composes, "rekishi?::base", "finds the base")
edge("rekishi?::graft", :composes, "rekishi?::commit", "records the result")
edge("rekishi?::revert", :composes, "rekishi?::commit", "records the undo")

edge(
  "rekishi?::squash",
  :composes,
  "rekishi?::commit",
  "one commit replaces a run"
)

edge("rekishi?::blame", :composes, "rekishi?::diff", "finds each line origin")

edge(
  "rekishi?::three_way",
  :composes,
  "rekishi?::diff",
  "both sides against the base"
)

edge("rekishi?::read", :composes, "rekishi?::get", "resolves the ref")

edge(
  "rekishi?::update",
  :composes,
  "rekishi?::get",
  "compares the old ref target"
)

edge("rekishi?::rebase", :composes, "rekishi?::graft", "replays each commit")
edge("rekishi?::revert", :composes, "rekishi?::invert", "changes reversed")
edge("rekishi?::bisect", :composes, "rekishi?::log", "candidate commits")
edge("rekishi?::blame", :composes, "rekishi?::log", "walks history")

edge(
  "rekishi?::graft",
  :composes,
  "rekishi?::patch",
  "applies the commit changes"
)

edge("rekishi?::merge", :composes, "rekishi?::three_way", "combines the edits")
edge("rekishi?::create", :generalizes, "gitto::create", "git branch is one ref")

edge(
  "rekishi?::diff",
  :generalizes,
  "gitto::diff",
  "git diff is one history kind"
)

edge(
  "rekishi?::merge",
  :generalizes,
  "gitto::merge",
  "git merge is one history kind"
)

edge(
  "rekishi?::read",
  :generalizes,
  "gitto::read",
  "a git blob at a ref is one history kind"
)

edge(
  "rekishi?::update",
  :generalizes,
  "rekishi?::create",
  "create is update from nothing"
)

edge("rekishi?::base", :guards, "rekishi?::merge", "merge needs a common base")

edge(
  "rekishi?::restore",
  :inverse,
  "rekishi?::commit",
  "brings a recorded state back"
)

edge("rekishi?::delete", :inverse, "rekishi?::create", "removes the ref")
edge("rekishi?::create", :inverse, "rekishi?::delete", "removes the ref")
edge("rekishi?::patch", :inverse, "rekishi?::diff", "applies what diff found")
edge("rekishi?::diff", :inverse, "rekishi?::patch", "applies what diff found")

edge(
  "rekishi?::commit",
  :inverse,
  "rekishi?::restore",
  "brings a recorded state back"
)

edge("rekishi?::log", :lifts, "rekishi?::get", "walks parents")
edge("rekishi?::get", :pairs, "rekishi?::commit", "look up what was committed")
edge("rekishi?::list", :pairs, "rekishi?::create", "refs and their names")
edge("rekishi?::invert", :pairs, "rekishi?::diff", "changes reversed")
edge("rekishi?::log", :pairs, "rekishi?::diff", "commits then their changes")
edge("rekishi?::commit", :pairs, "rekishi?::log", "record and read back")
edge("rekishi?::three_way", :pairs, "rekishi?::patch", "merged result applied")

edge(
  "rekishi?::restore",
  :pairs,
  "rekishi?::read",
  "whole state beside one path"
)

edge("rekishi?::ancestors", :refines, "rekishi?::log", "ids only")
edge("rekishi?::squash", :requires, "rekishi?::log", "needs the run of commits")
