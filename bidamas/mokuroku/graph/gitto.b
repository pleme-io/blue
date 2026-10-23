space("gitto", {status: :ratified})

verb(
  "gitto",
  "ancestor?",
  {
    kind: :effect,
    shape: "ancestor?(repo, a, b) -> Bool",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "whether a is reachable from b",
    wave: 0,
    origin: "F"
  }
)

verb(
  "gitto",
  "bisect",
  {
    kind: :effect,
    shape: "bisect(repo, good, bad, f) -> commit",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "first commit where a test fails",
    wave: 2,
    origin: "E"
  }
)

verb(
  "gitto",
  "blame",
  {
    kind: :effect,
    shape: "blame(repo, path, {at:}) -> [line record]",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "who last changed each line",
    wave: 2,
    origin: "E"
  }
)

verb(
  "gitto",
  "changed",
  {
    kind: :effect,
    shape: "changed(repo, a, b) -> [path]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "paths touched between two refs",
    wave: 1,
    origin: "E"
  }
)

verb(
  "gitto",
  "clone",
  {
    kind: :effect,
    shape: "clone(url, dir, opts) -> repo",
    laterals: ["deadline", "error", "process", "resource", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "copy a remote repository",
    wave: 0,
    origin: "E"
  }
)

verb(
  "gitto",
  "commit",
  {
    kind: :effect,
    shape: "commit(repo, message, opts) -> commit",
    laterals: ["error", "idempotent", "process"],
    fleet: nil,
    today: "absent",
    meaning: "record staged paths as a commit",
    wave: 0,
    origin: "E"
  }
)

verb(
  "gitto",
  "conflicts",
  {
    kind: :effect,
    shape: "conflicts(repo) -> [file]",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "files left unmerged after a merge or rebase",
    wave: 1,
    origin: "F"
  }
)

verb(
  "gitto",
  "create",
  {
    kind: :effect,
    shape: "create(repo, key, value, opts) -> value",
    laterals: ["error", "idempotent", "process"],
    fleet: nil,
    today: "absent",
    meaning: "make a branch or tag that must not exist",
    wave: 0,
    origin: "E"
  }
)

verb(
  "gitto",
  "delete",
  {
    kind: :effect,
    shape: "delete(repo, key) -> nil",
    laterals: ["error", "idempotent", "process"],
    fleet: nil,
    today: "absent",
    meaning: "remove a branch or tag, absent counts done",
    wave: 0,
    origin: "E"
  }
)

verb(
  "gitto",
  "describe",
  {
    kind: :effect,
    shape: "describe(repo, ref) -> {tag:, distance:}",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "nearest tag and distance from it",
    wave: 1,
    origin: "E"
  }
)

verb(
  "gitto",
  "diff",
  {
    kind: :effect,
    shape: "diff(repo, a, b, opts) -> [change]",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "changes between two refs",
    wave: 0,
    origin: "E",
    contract: "diff(repo, a, opts) -> [change]"
  }
)

verb(
  "gitto",
  "exists?",
  {
    kind: :effect,
    shape: "exists?(repo, ref) -> Bool",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "whether a ref resolves",
    wave: 0,
    origin: "E",
    contract: "exists?(repo, opts) -> Bool"
  }
)

verb(
  "gitto",
  "fetch",
  {
    kind: :effect,
    shape: "fetch(repo, opts) -> nil",
    laterals: ["deadline", "error", "process", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "update remote refs without touching the tree",
    wave: 0,
    origin: "E"
  }
)

verb(
  "gitto",
  "get",
  {
    kind: :effect,
    shape: "get(repo, ref) -> commit or nil",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "one commit, nil when the ref is absent",
    wave: 0,
    origin: "E"
  }
)

verb(
  "gitto",
  "graft",
  {
    kind: :effect,
    shape: "graft(repo, ref) -> commit",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "apply one commit onto the current branch",
    wave: 2,
    origin: "E"
  }
)

verb(
  "gitto",
  "hook",
  {
    kind: :decl,
    shape: "hook(event, step) -> hook",
    laterals: ["switch", "test"],
    fleet: "blue",
    today: "absent",
    meaning: "declare a step git runs before commit or push",
    wave: 1,
    origin: "F"
  }
)

verb(
  "gitto",
  "ignore?",
  {
    kind: :effect,
    shape: "ignore?(repo, path) -> Bool",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "whether ignore rules hide a path",
    wave: 2,
    origin: "F"
  }
)

verb(
  "gitto",
  "info",
  {
    kind: :effect,
    shape: "info(repo) -> record",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "branch, head, ahead, behind, changes",
    wave: 0,
    origin: "E"
  }
)

verb(
  "gitto",
  "list",
  {
    kind: :effect,
    shape: "list(repo, what, opts) -> [record]",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "branches, tags, commits, remotes or worktrees",
    wave: 0,
    origin: "E",
    contract: "list(repo, opts) -> [record]"
  }
)

verb(
  "gitto",
  "merge",
  {
    kind: :effect,
    shape: "merge(repo, ref, opts) -> commit",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "fast-forward only by default",
    wave: 0,
    origin: "E"
  }
)

verb(
  "gitto",
  "merge_base",
  {
    kind: :effect,
    shape: "merge_base(repo, a, b) -> commit",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "the newest commit that both refs contain",
    wave: 1,
    origin: "F"
  }
)

verb(
  "gitto",
  "need",
  {
    kind: :effect,
    shape: "need(repo, ref) -> commit",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "one commit, raises when absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "gitto",
  "patch",
  {
    kind: :pure,
    shape: "patch(repo, change) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "a change rendered as an applicable patch",
    wave: 2,
    origin: "E"
  }
)

verb(
  "gitto",
  "push",
  {
    kind: :effect,
    shape: "push(repo, opts) -> nil",
    laterals: ["error", "process", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "publish refs, rebase or refuse, never force",
    wave: 0,
    origin: "E"
  }
)

verb(
  "gitto",
  "read",
  {
    kind: :effect,
    shape: "read(repo, path, {at:}) -> bytes",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "a file's content at a ref",
    wave: 0,
    origin: "E",
    contract: "read(repo, opts) -> bytes"
  }
)

verb(
  "gitto",
  "rebase",
  {
    kind: :effect,
    shape: "rebase(repo, onto, opts) -> nil",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "replay local commits on a new base; refuse on conflict",
    wave: 1,
    origin: "F"
  }
)

verb(
  "gitto",
  "revert",
  {
    kind: :effect,
    shape: "revert(repo, ref) -> commit",
    laterals: ["error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "a commit that undoes another",
    wave: 1,
    origin: "E"
  }
)

verb(
  "gitto",
  "stage",
  {
    kind: :effect,
    shape: "stage(repo, paths) -> nil",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "choose paths for the next commit",
    wave: 1,
    origin: "F"
  }
)

verb(
  "gitto",
  "tag",
  {
    kind: :effect,
    shape: "tag(repo, name, {at:, sign:}) -> tag",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "annotate a commit with a name",
    wave: 1,
    origin: "E",
    contract: "tag(repo, name, opts) -> tag"
  }
)

verb(
  "gitto",
  "worktree",
  {
    kind: :effect,
    shape: "worktree(repo, branch, dir) -> repo",
    laterals: ["error", "process", "resource"],
    fleet: "tend",
    today: "absent",
    meaning: "a second checkout of one repository",
    wave: 1,
    origin: "E"
  }
)

edge("gitto::bisect", :composes, "gitto::diff", "narrow by halves")
edge("gitto::changed", :composes, "gitto::diff", "paths only")
edge("gitto::patch", :composes, "gitto::diff", "diff as text")
edge("gitto::need", :composes, "gitto::get", "get then raise")
edge("gitto::bisect", :composes, "gitto::graft", "test each midpoint")
edge("gitto::describe", :composes, "gitto::list", "walks commits to a tag")
edge("gitto::list", :composes, "gitto::need", "refs resolve to commits")
edge("gitto::blame", :composes, "gitto::read", "history of lines")
edge("gitto::get", :generalizes, "gitto::exists?", "returns the commit")
edge("gitto::list", :generalizes, "gitto::get", "many refs")
edge("gitto::push", :guards, "gitto::ancestor?", "refuse when not ahead")
edge("gitto::hook", :guards, "gitto::commit", "runs before commit")
edge("gitto::fetch", :guards, "gitto::merge", "merge only after fetch")
edge("gitto::hook", :guards, "gitto::push", "runs before push")
edge("gitto::ignore?", :guards, "gitto::stage", "ignored paths are not staged")
edge("gitto::push", :guards, "rirezu?::cut", "published only after tests")
edge("gitto::delete", :inverse, "gitto::clone", "make and remove a copy")
edge("gitto::revert", :inverse, "gitto::commit", "undo by a new commit")
edge("gitto::delete", :inverse, "gitto::create", "make and remove a ref")
edge("gitto::clone", :inverse, "gitto::delete", "make and remove a copy")
edge("gitto::create", :inverse, "gitto::delete", "make and remove a ref")
edge("gitto::worktree", :inverse, "gitto::delete", "remove a checkout")
edge("gitto::push", :inverse, "gitto::fetch", "publish versus update")
edge("gitto::revert", :inverse, "gitto::graft", "undo versus apply")
edge("gitto::fetch", :inverse, "gitto::push", "publish versus update")
edge("gitto::commit", :inverse, "gitto::revert", "undo by a new commit")
edge("gitto::graft", :inverse, "gitto::revert", "undo versus apply")
edge("gitto::delete", :inverse, "gitto::worktree", "remove a checkout")
edge("gitto::blame", :pairs, "genin?::bisect", "blame or bisect for the cause")
edge("gitto::stage", :pairs, "gitto::commit", "stage then commit")
edge("gitto::info", :pairs, "gitto::fetch", "info after fetch is true")
edge("gitto::list", :pairs, "gitto::get", "many versus one")
edge("gitto::fetch", :pairs, "gitto::merge", "house rule fetch then ff merge")
edge("gitto::fetch", :pairs, "gitto::push", "fetch before push")
edge("gitto::rebase", :pairs, "gitto::push", "rebased branches push")
edge("gitto::clone", :pairs, "kaihatsu?::bootstrap", "clone then bootstrap")

edge(
  "gitto::ignore?",
  :pairs,
  "kenshutsu?::scan",
  "ignored files are not scanned"
)

edge("gitto::conflicts", :pairs, "rebyuu?::ready?", "conflicts block landing")
edge("gitto::create", :pairs, "rebyuu?::request", "a branch opens a review")
edge("gitto::tag", :pairs, "rirezu?::cut", "release marks a tag")
edge("gitto::commit", :pairs, "rirezu?::next", "commit kind drives the version")
edge("gitto::graft", :pairs, "rirezu?::pin", "backports pick fixes")
edge("gitto::revert", :pairs, "rirezu?::rollback", "revert or roll back")
edge("gitto::worktree", :pairs, "tesuto?::run", "isolated runs per ref")
edge("gitto::clone", :refines, "core::copy", "remote to local")
edge("gitto::create", :refines, "core::create", "branch or tag")
edge("gitto::diff", :refines, "core::diff", "between refs")
edge("gitto::exists?", :refines, "core::exists?", "ref resolves")
edge("gitto::get", :refines, "core::get", "nil when ref absent")
edge("gitto::info", :refines, "core::info", "repo state")
edge("gitto::list", :refines, "core::list", "refs, commits or worktrees")

edge(
  "gitto::merge",
  :refines,
  "core::merge",
  "git merge is the master merge on commits"
)

edge("gitto::need", :refines, "core::need", "raises when ref absent")
edge("gitto::read", :refines, "core::read", "file at a ref")
edge("gitto::merge_base", :refines, "gitto::ancestor?", "returns the commit")
edge("gitto::graft", :refines, "gitto::commit", "copies a commit")
edge("gitto::tag", :refines, "gitto::create", "a tag is a named ref")
edge("gitto::worktree", :refines, "gitto::create", "extra checkout")
edge("gitto::exists?", :refines, "gitto::get", "Bool for get")
edge("gitto::info", :refines, "gitto::get", "state of the whole repo")
edge("gitto::rebase", :refines, "gitto::merge", "linear history form")

edge(
  "gitto::merge",
  :requires,
  "gitto::ancestor?",
  "fast-forward needs ancestry"
)

edge("gitto::rebase", :requires, "gitto::conflicts", "stop on conflict")
edge("gitto::worktree", :requires, "gitto::create", "one worktree per ref")
edge("gitto::read", :requires, "gitto::exists?", "ref must resolve")
edge("gitto::merge", :requires, "gitto::fetch", "merge needs fresh refs")
edge("gitto::push", :requires, "gitto::fetch", "know the remote first")
edge("gitto::diff", :requires, "gitto::get", "two commits")
edge("gitto::merge_base", :requires, "gitto::get", "both refs exist")
edge("gitto::commit", :requires, "gitto::info", "needs a dirty tree")
edge("gitto::merge", :requires, "gitto::info", "clean tree needed")
edge("gitto::stage", :requires, "gitto::info", "changes are seen first")
edge("gitto::conflicts", :requires, "gitto::merge", "only after a merge")
edge("gitto::graft", :requires, "gitto::need", "commit must exist")
edge("gitto::blame", :requires, "gitto::read", "reads file history")
edge("gitto::describe", :requires, "gitto::tag", "nearest tag")
