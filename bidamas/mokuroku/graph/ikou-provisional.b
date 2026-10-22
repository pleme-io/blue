space("ikou?", {status: :provisional})

verb(
  "ikou?",
  "apply",
  {
    kind: :effect,
    shape: "apply(target, migrations, opts) -> [step]",
    laterals: ["error", "idempotent", "log", "migrate"],
    fleet: "shinka",
    today: "absent",
    meaning: "run pending steps in order, recording each",
    wave: 1,
    origin: "B"
  }
)

verb(
  "ikou?",
  "backfill",
  {
    kind: :effect,
    shape: "backfill(target, f, opts) -> count",
    laterals: ["cancel", "ratelimit", "resource", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "rewrite existing data in resumable batches",
    wave: 3,
    origin: "B"
  }
)

verb(
  "ikou?",
  "baseline",
  {
    kind: :effect,
    shape: "baseline(target, version) -> nil",
    laterals: ["idempotent", "migrate"],
    fleet: nil,
    today: "absent",
    meaning: "mark a version as applied without running it",
    wave: 2,
    origin: "B"
  }
)

verb(
  "ikou?",
  "check",
  {
    kind: :pure,
    shape: "check(migrations) -> [problem]",
    laterals: ["validate"],
    fleet: "pleme-migrations",
    today: "absent",
    meaning: "find gaps, duplicates and unsafe operations",
    wave: 2,
    origin: "B"
  }
)

verb(
  "ikou?",
  "checksum",
  {
    kind: :pure,
    shape: "checksum(migration) -> text",
    laterals: [],
    fleet: "shinka",
    today: "absent",
    meaning: "the content hash recorded for a migration",
    wave: 1,
    origin: "B"
  }
)

verb(
  "ikou?",
  "contract",
  {
    kind: :decl,
    shape: "contract(change) -> migration",
    laterals: ["validate"],
    fleet: "pleme-migrations",
    today: "absent",
    meaning: "the removing last half once nothing reads the old shape",
    wave: 2,
    origin: "B"
  }
)

verb(
  "ikou?",
  "create",
  {
    kind: :effect,
    shape: "create(dir, name) -> path",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "scaffold a new empty migration file",
    wave: 2,
    origin: "B"
  }
)

verb(
  "ikou?",
  "define",
  {
    kind: :decl,
    shape: "define(version, up, down) -> migration",
    laterals: ["validate"],
    fleet: "pleme-migrations",
    today: "absent",
    meaning: "declare one versioned change with its way back",
    wave: 1,
    origin: "B"
  }
)

verb(
  "ikou?",
  "expand",
  {
    kind: :decl,
    shape: "expand(change) -> migration",
    laterals: ["validate"],
    fleet: "pleme-migrations",
    today: "absent",
    meaning: "the additive first half of a zero-downtime change",
    wave: 2,
    origin: "B"
  }
)

verb(
  "ikou?",
  "history",
  {
    kind: :effect,
    shape: "history(target) -> [record]",
    laterals: ["migrate"],
    fleet: "shinka",
    today: "absent",
    meaning: "every recorded step with time, checksum and outcome",
    wave: 1,
    origin: "B"
  }
)

verb(
  "ikou?",
  "plan",
  {
    kind: :pure,
    shape: "plan(target, migrations) -> [step]",
    laterals: ["validate"],
    fleet: "shinka",
    today: "absent",
    meaning: "the steps still to apply, changing nothing",
    wave: 1,
    origin: "B"
  }
)

verb(
  "ikou?",
  "rollback",
  {
    kind: :effect,
    shape: "rollback(target, opts) -> [step]",
    laterals: ["error", "migrate"],
    fleet: "pleme-migrations",
    today: "absent",
    meaning: "undo steps back to a version or by count",
    wave: 2,
    origin: "B"
  }
)

verb(
  "ikou?",
  "squash",
  {
    kind: :pure,
    shape: "squash(migrations, opts) -> migration",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "fold applied steps into one baseline step",
    wave: 3,
    origin: "B"
  }
)

verb(
  "ikou?",
  "status",
  {
    kind: :effect,
    shape: "status(target) -> {applied, pending, drift}",
    laterals: ["migrate"],
    fleet: "shinka",
    today: "absent",
    meaning: "what is applied, what waits, and what changed",
    wave: 1,
    origin: "B"
  }
)

verb(
  "ikou?",
  "verify?",
  {
    kind: :effect,
    shape: "verify?(target, migrations) -> Bool",
    laterals: ["migrate", "validate"],
    fleet: "shinka",
    today: "absent",
    meaning: "whether applied steps still match their checksums",
    wave: 1,
    origin: "B"
  }
)

edge("ikou?::create", :composes, "fairu::write", "scaffolds the file")

edge(
  "ikou?::verify?",
  :composes,
  "ikou?::checksum",
  "compares recorded and current"
)

edge(
  "ikou?::squash",
  :composes,
  "ikou?::define",
  "one baseline step replaces many"
)

edge("ikou?::status", :composes, "ikou?::history", "applied set from history")
edge("ikou?::apply", :composes, "ikou?::plan", "runs the planned steps")
edge("ikou?::apply", :composes, "rokku?::with_lock", "one runner at a time")
edge("ikou?::backfill", :composes, "rokku?::with_lock", "one runner at a time")

edge(
  "ikou?::backfill",
  :composes,
  "saishikou::retrying",
  "batches may fail and repeat"
)

edge("ikou?::checksum", :composes, "shomei::hash", "hash of the migration text")

edge(
  "ikou?::history",
  :composes,
  "teeburu::list",
  "applied set stored in a table"
)

edge(
  "ikou?::define",
  :composes,
  "teeburu::plan",
  "SQL steps come from schema changes"
)

edge(
  "ikou?::apply",
  :composes,
  "teeburu::with_transaction",
  "each step atomic where the target allows"
)

edge("ikou?::plan", :guards, "ikou?::apply", "preview before running")
edge("ikou?::verify?", :guards, "ikou?::apply", "refuse to run over drift")
edge("ikou?::baseline", :guards, "ikou?::plan", "declared steps are skipped")
edge("ikou?::check", :guards, "ikou?::plan", "reject gaps and unsafe steps")
edge("ikou?::check", :guards, "ikou?::squash", "only a clean set folds")
edge("ikou?::rollback", :inverse, "ikou?::apply", "runs the down steps")
edge("ikou?::apply", :inverse, "ikou?::rollback", "runs the down steps")
edge("ikou?::expand", :pairs, "ikou?::contract", "the two halves of one change")
edge("ikou?::define", :pairs, "ikou?::create", "declaration and its file")
edge("ikou?::history", :pairs, "ikou?::status", "log beside summary")

edge(
  "ikou?::baseline",
  :refines,
  "ikou?::apply",
  "marks applied without running"
)

edge(
  "ikou?::contract",
  :requires,
  "ikou?::backfill",
  "old shape goes after data moved"
)

edge(
  "ikou?::status",
  :requires,
  "ikou?::checksum",
  "drift needs the recorded hash"
)

edge(
  "ikou?::backfill",
  :requires,
  "ikou?::expand",
  "new shape must exist first"
)

edge("ikou?::rollback", :requires, "ikou?::history", "needs the recorded steps")

edge(
  "ikou?::plan",
  :requires,
  "ikou?::status",
  "needs applied versus available"
)
