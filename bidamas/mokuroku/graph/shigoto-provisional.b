space("shigoto?", {status: :provisional})

verb(
  "shigoto?",
  "after",
  {
    kind: :effect,
    shape: "after(duration, f) -> timer",
    laterals: ["cancel", "time"],
    fleet: nil,
    today: "absent",
    meaning: "Call f once after a duration.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "backfill",
  {
    kind: :effect,
    shape: "backfill(schedule, range, f) -> count",
    laterals: ["idempotent", "time"],
    fleet: nil,
    today: "absent",
    meaning: "Run f for every firing in a past range.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "budget",
  {
    kind: :decl,
    shape: "budget(opts) -> budget",
    laterals: ["config", "resource"],
    fleet: "shigoto-budget",
    today: "absent",
    meaning: "Bound parallelism on three axes.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "cancel",
  {
    kind: :effect,
    shape: "cancel(run, reason) -> nil",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "End a run and compensate completed steps.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "claim",
  {
    kind: :effect,
    shape: "claim(queue, opts) -> job or nil",
    laterals: ["deadline", "resource"],
    fleet: "shigoto",
    today: "absent",
    meaning: "Take the next job under a lease.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "compensate",
  {
    kind: :effect,
    shape: "compensate(saga, from) -> nil",
    laterals: ["error", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "Run undos for completed steps in reverse order.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "complete",
  {
    kind: :effect,
    shape: "complete(job, result) -> nil",
    laterals: ["idempotent"],
    fleet: "shigoto",
    today: "absent",
    meaning: "Mark a claimed job finished.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "dag",
  {
    kind: :decl,
    shape: "dag(jobs, deps) -> graph",
    laterals: ["validate"],
    fleet: "shigoto-dag",
    today: "absent",
    meaning: "Declare jobs with dependencies; cycles are refused.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "defer",
  {
    kind: :effect,
    shape: "defer(job, duration) -> nil",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "Hand a job back to run later.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "enqueue",
  {
    kind: :effect,
    shape: "enqueue(queue, job, opts) -> id",
    laterals: ["error", "idempotent"],
    fleet: "shigoto",
    today: "absent",
    meaning: "Add a job to a queue; a duplicate key is one job.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "every",
  {
    kind: :effect,
    shape: "every(schedule, f, opts) -> timer",
    laterals: ["cancel", "process", "time"],
    fleet: nil,
    today: "absent",
    meaning: "Call f on each firing until cancelled.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "fail",
  {
    kind: :effect,
    shape: "fail(job, error) -> nil",
    laterals: ["error", "retry"],
    fleet: "shigoto-retry",
    today: "absent",
    meaning: "Mark a claimed job failed; the policy decides to retry.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "gate",
  {
    kind: :decl,
    shape: "gate(job, precondition) -> job",
    laterals: ["validate"],
    fleet: "shigoto-gate",
    today: "absent",
    meaning: "Hold a job until a precondition passes.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "info",
  {
    kind: :effect,
    shape: "info(run) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "A run's state, step and history.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "missed",
  {
    kind: :pure,
    shape: "missed(schedule, since, now) -> [instant]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "Firings that fell between two instants.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "next",
  {
    kind: :pure,
    shape: "next(schedule, from) -> instant",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "The next time a schedule fires.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, :cron) -> schedule",
    laterals: ["error", "time"],
    fleet: "lava-cron",
    today: "absent",
    meaning: "Read a cron or interval expression into a schedule.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "pause",
  {
    kind: :effect,
    shape: "pause(run) -> nil",
    laterals: ["switch"],
    fleet: nil,
    today: "absent",
    meaning: "Stop taking steps; keep state.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "plan",
  {
    kind: :pure,
    shape: "plan(graph, opts) -> [step]",
    laterals: [],
    fleet: "shigoto",
    today: "absent",
    meaning: "The order and parallelism a run would use.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "rank",
  {
    kind: :pure,
    shape: "rank(jobs, opts) -> [job]",
    laterals: [],
    fleet: "shigoto-rank",
    today: "absent",
    meaning: "Order jobs so none starves.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "resume",
  {
    kind: :effect,
    shape: "resume(run) -> nil",
    laterals: ["switch"],
    fleet: nil,
    today: "absent",
    meaning: "Continue a paused run.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "run",
  {
    kind: :effect,
    shape: "run(graph, opts) -> record",
    laterals: ["cancel", "error", "process"],
    fleet: "shigoto",
    today: "absent",
    meaning: "Run a graph in dependency order within a budget.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "saga",
  {
    kind: :decl,
    shape: "saga(steps) -> saga",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "Steps each paired with an undo.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "signal",
  {
    kind: :effect,
    shape: "signal(run, name, payload) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "Send an outside event to a waiting run.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "start",
  {
    kind: :effect,
    shape: "start(workflow, input, opts) -> run",
    laterals: ["idempotent", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "Begin a workflow run under a key.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "timer",
  {
    kind: :effect,
    shape: "timer(instant, f) -> timer",
    laterals: ["cancel", "time"],
    fleet: nil,
    today: "absent",
    meaning: "Call f once at an instant.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "wait",
  {
    kind: :effect,
    shape: "wait(run, opts) -> result",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Block until a run ends.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "shigoto?",
  "workflow",
  {
    kind: :decl,
    shape: "workflow(name, steps) -> workflow",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "Declare a durable multi-step flow.",
    wave: 3,
    origin: "C"
  }
)

edge("shigoto?::run", :composes, "heikou::map", "parallel by level")
edge("shigoto?::fail", :composes, "heikou::retry", "policy decides redelivery")
edge("shigoto?::after", :composes, "jikan::sleep", "sleep then call")
edge("shigoto?::every", :composes, "jikan::sleep", "waits between firings")
edge("shigoto?::start", :composes, "nisshi::append", "each step is logged")

edge(
  "shigoto?::info",
  :composes,
  "nisshi::replay",
  "state is folded from the log"
)

edge(
  "shigoto?::cancel",
  :composes,
  "shigoto?::compensate",
  "undo completed steps"
)

edge(
  "shigoto?::backfill",
  :composes,
  "shigoto?::missed",
  "runs each missed firing"
)

edge("shigoto?::every", :composes, "shigoto?::next", "sleep to each firing")

edge(
  "shigoto?::missed",
  :composes,
  "shigoto?::next",
  "firings between two instants"
)

edge(
  "shigoto?::workflow",
  :generalizes,
  "shigoto?::dag",
  "durable and signal-aware graph"
)

edge("shigoto?::gate", :guards, "shigoto?::claim", "held until precondition")

edge(
  "shigoto?::budget",
  :guards,
  "shigoto?::run",
  "bounds parallelism of a run"
)

edge("shigoto?::enqueue", :inverse, "shigoto?::claim", "add and take")
edge("shigoto?::claim", :inverse, "shigoto?::enqueue", "add and take")

edge(
  "shigoto?::parse",
  :inverse,
  "shigoto?::next",
  "text to schedule, schedule to time"
)

edge(
  "shigoto?::next",
  :inverse,
  "shigoto?::parse",
  "text to schedule, schedule to time"
)

edge("shigoto?::resume", :inverse, "shigoto?::pause", "stop and continue")
edge("shigoto?::run", :inverse, "shigoto?::plan", "the plan changes nothing")
edge("shigoto?::pause", :inverse, "shigoto?::resume", "stop and continue")
edge("shigoto?::plan", :inverse, "shigoto?::run", "the plan changes nothing")

edge(
  "shigoto?::every",
  :pairs,
  "goui?::with_lock",
  "run one copy of a schedule"
)

edge("shigoto?::cancel", :pairs, "heikou::cancel", "run-level cancel")

edge(
  "shigoto?::compensate",
  :pairs,
  "heikou::retry",
  "undos retried until done"
)

edge("shigoto?::enqueue", :pairs, "kyoujin?::key", "duplicate key is one job")
edge("shigoto?::backfill", :pairs, "kyoujin?::once", "each firing runs once")

edge(
  "shigoto?::fail",
  :pairs,
  "messeeji?::park",
  "exhausted jobs go to a dead queue"
)

edge("shigoto?::enqueue", :pairs, "messeeji?::publish", "a queue over a log")
edge("shigoto?::run", :pairs, "nisshi::append", "runs are recorded")
edge("shigoto?::rank", :pairs, "shigoto?::claim", "claim order")
edge("shigoto?::dag", :pairs, "shigoto?::run", "declare then run")

edge(
  "shigoto?::timer",
  :refines,
  "shigoto?::after",
  "absolute instead of relative"
)

edge(
  "shigoto?::defer",
  :refines,
  "shigoto?::fail",
  "failure with a chosen delay"
)

edge(
  "shigoto?::every",
  :refines,
  "shigoto?::timer",
  "at repeated by a schedule"
)

edge(
  "shigoto?::saga",
  :refines,
  "shigoto?::workflow",
  "steps each with an undo"
)

edge("shigoto?::claim", :requires, "goui?::acquire", "a claim is a lease")
edge("shigoto?::parse", :requires, "jikan::parse", "schedules use time parsing")

edge(
  "shigoto?::complete",
  :requires,
  "shigoto?::claim",
  "only the claimant completes"
)

edge(
  "shigoto?::defer",
  :requires,
  "shigoto?::claim",
  "hands back a claimed job"
)

edge("shigoto?::fail", :requires, "shigoto?::claim", "only the claimant fails")
edge("shigoto?::plan", :requires, "shigoto?::dag", "plans a declared graph")
edge("shigoto?::run", :requires, "shigoto?::dag", "runs a declared graph")
edge("shigoto?::next", :requires, "shigoto?::parse", "computed from a schedule")

edge(
  "shigoto?::compensate",
  :requires,
  "shigoto?::saga",
  "undoes a declared saga"
)

edge("shigoto?::info", :requires, "shigoto?::start", "inspects a run")
edge("shigoto?::signal", :requires, "shigoto?::start", "targets a run")
edge("shigoto?::wait", :requires, "shigoto?::start", "waits on a run")

edge(
  "shigoto?::start",
  :requires,
  "shigoto?::workflow",
  "runs a declared workflow"
)
