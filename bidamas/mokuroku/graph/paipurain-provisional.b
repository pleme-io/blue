space("paipurain?", {status: :provisional})

verb(
  "paipurain?",
  "approve",
  {
    kind: :effect,
    shape: "approve(run, gate, opts) -> nil",
    laterals: ["capability", "log"],
    fleet: nil,
    today: "absent",
    meaning: "let a held gate pass, naming who",
    wave: 2,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "artifacts",
  {
    kind: :effect,
    shape: "artifacts(run) -> [artifact]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "files a run produced",
    wave: 2,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "cancel",
  {
    kind: :effect,
    shape: "cancel(run) -> nil",
    laterals: ["cancel", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "stop a run and its jobs",
    wave: 2,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "declare",
  {
    kind: :decl,
    shape: "declare(name, spec) -> pipeline",
    laterals: ["config", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "a pipeline as stages, jobs and gates",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "get",
  {
    kind: :effect,
    shape: "get(id) -> run or nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "one run with job states",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "lint",
  {
    kind: :pure,
    shape: "lint(pipeline) -> [finding]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "refuse a pipeline that cannot run",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "list",
  {
    kind: :effect,
    shape: "list(opts) -> [run]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "runs, newest first",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "matrix",
  {
    kind: :pure,
    shape: "matrix(axes) -> [record]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "every combination of axis values",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "order",
  {
    kind: :pure,
    shape: "order(pipeline) -> [[job]]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "jobs in dependency waves",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "plan",
  {
    kind: :pure,
    shape: "plan(pipeline, event) -> [job]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "jobs an event would start, after filters",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "read",
  {
    kind: :effect,
    shape: "read(run, job) -> text",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "the log of one job",
    wave: 1,
    origin: "E",
    contract: "read(run, opts) -> text"
  }
)

verb(
  "paipurain?",
  "retry",
  {
    kind: :effect,
    shape: "retry(run, opts) -> run",
    laterals: ["retry"],
    fleet: nil,
    today: "absent",
    meaning: "run failed jobs again",
    wave: 2,
    origin: "E",
    contract: "retry(run, policy) -> run"
  }
)

verb(
  "paipurain?",
  "run",
  {
    kind: :effect,
    shape: "run(pipeline, event, opts) -> run",
    laterals: ["deadline", "log", "process"],
    fleet: nil,
    today: "absent",
    meaning: "start a pipeline for an event",
    wave: 1,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "schedule",
  {
    kind: :decl,
    shape: "schedule(pipeline, cron) -> entry",
    laterals: ["config", "time"],
    fleet: nil,
    today: "absent",
    meaning: "run a pipeline on a calendar",
    wave: 3,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "skip?",
  {
    kind: :pure,
    shape: "skip?(job, changed) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether path filters make a job unneeded",
    wave: 2,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "triage",
  {
    kind: :pure,
    shape: "triage(runs) -> [cluster]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "failed runs grouped by shared cause",
    wave: 2,
    origin: "E"
  }
)

verb(
  "paipurain?",
  "watch",
  {
    kind: :stream,
    shape: "watch(run, f, opts) -> nil",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "call f per job state change",
    wave: 1,
    origin: "E"
  }
)

edge(
  "paipurain?::declare",
  :composes,
  "birudo?::build",
  "jobs name build steps"
)

edge("paipurain?::run", :composes, "birudo?::build", "jobs are builds")
edge("paipurain?::retry", :composes, "paipurain?::get", "find failed jobs")
edge("paipurain?::watch", :composes, "paipurain?::list", "poll runs")
edge("paipurain?::plan", :composes, "paipurain?::matrix", "expand axes")
edge("paipurain?::plan", :composes, "paipurain?::order", "waves of jobs")
edge("paipurain?::run", :composes, "paipurain?::plan", "plan then start")

edge(
  "paipurain?::triage",
  :composes,
  "paipurain?::read",
  "cluster by log cause"
)

edge("paipurain?::schedule", :composes, "paipurain?::run", "timer fires a run")
edge("paipurain?::plan", :composes, "paipurain?::skip?", "drop unneeded jobs")
edge("paipurain?::lint", :guards, "paipurain?::declare", "refuse bad pipelines")
edge("paipurain?::approve", :guards, "paipurain?::run", "held gate opens")
edge("paipurain?::run", :inverse, "paipurain?::cancel", "stop a run")
edge("paipurain?::cancel", :inverse, "paipurain?::run", "stop a run")
edge("paipurain?::watch", :lifts, "paipurain?::get", "stream of state")
edge("paipurain?::triage", :pairs, "paipurain?::list", "group the list")

edge(
  "paipurain?::approve",
  :pairs,
  "tenkai?::approve",
  "gate in CI and in rollout"
)

edge("paipurain?::matrix", :refines, "core::flat_map", "all combinations")
edge("paipurain?::get", :refines, "core::get", "one run")
edge("paipurain?::artifacts", :refines, "core::list", "files a run made")
edge("paipurain?::list", :refines, "core::list", "runs")
edge("paipurain?::declare", :refines, "core::parse", "pipeline as data")
edge("paipurain?::plan", :refines, "core::plan", "jobs an event starts")
edge("paipurain?::read", :refines, "core::read", "job log")
edge("paipurain?::schedule", :refines, "paipurain?::declare", "timed trigger")
edge("paipurain?::retry", :refines, "paipurain?::run", "rerun failed jobs")
edge("paipurain?::skip?", :requires, "gitto::changed", "path filters")

edge(
  "paipurain?::order",
  :requires,
  "paipurain?::declare",
  "needs the job graph"
)

edge("paipurain?::cancel", :requires, "paipurain?::get", "needs a live run")
