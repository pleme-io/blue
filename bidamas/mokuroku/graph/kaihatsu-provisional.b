space("kaihatsu?", {status: :provisional})

verb(
  "kaihatsu?",
  "bootstrap",
  {
    kind: :effect,
    shape: "bootstrap(project, opts) -> nil",
    laterals: %w[idempotent process],
    fleet: nil,
    today: "absent",
    meaning: "make a fresh checkout ready to build and test",
    wave: 2,
    origin: "F",
    contract: "bootstrap(project, statistic, rng, n) -> nil"
  }
)

verb(
  "kaihatsu?",
  "doctor",
  {
    kind: :effect,
    shape: "doctor(env) -> [problem]",
    laterals: %w[capability process],
    fleet: nil,
    today: "absent",
    meaning: "check the tools, versions and access a project needs",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kaihatsu?",
  "gate",
  {
    kind: :effect,
    shape: "gate(project, event) -> verdict",
    laterals: %w[process test],
    fleet: "blue",
    today: "absent",
    meaning: "run the steps declared for an event; any red stops it",
    wave: 1,
    origin: "F"
  }
)

verb(
  "kaihatsu?",
  "new",
  {
    kind: :effect,
    shape: "new(kind, name, opts) -> project",
    laterals: ["idempotent"],
    fleet: "blue-lang-cli",
    today: "rust:blue-lang-cli",
    meaning: "start a project that passes its own tests",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kaihatsu?",
  "onboard",
  {
    kind: :pure,
    shape: "onboard(person, project) -> [step]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the ordered steps to a first merged change",
    wave: 4,
    origin: "F"
  }
)

verb(
  "kaihatsu?",
  "rehearse",
  {
    kind: :effect,
    shape: "rehearse(project, ci) -> report",
    laterals: %w[process test],
    fleet: nil,
    today: "absent",
    meaning: "run the CI jobs locally, in the same order",
    wave: 3,
    origin: "F"
  }
)

verb(
  "kaihatsu?",
  "repl",
  {
    kind: :effect,
    shape: "repl(opts) -> nil",
    laterals: ["capability"],
    fleet: "blue-lang-cli",
    today: "rust:blue-lang-cli",
    meaning: "an evaluation session at the terminal",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kaihatsu?",
  "run",
  {
    kind: :effect,
    shape: "run(task, opts) -> result",
    laterals: %w[deadline process],
    fleet: nil,
    today: "absent",
    meaning: "run one declared task in the project environment",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kaihatsu?",
  "tasks",
  {
    kind: :pure,
    shape: "tasks(project) -> [task]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the named tasks a project declares",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kaihatsu?",
  "watch",
  {
    kind: :stream,
    shape: "watch(paths, task) -> nil",
    laterals: ["cancel"],
    fleet: "blue-lang-cli",
    today: "rust:blue-lang-cli",
    meaning: "rerun a task when watched files change",
    wave: 0,
    origin: "F"
  }
)

edge(
  "kaihatsu?::new",
  :composes,
  "hinagata?::scaffold",
  "starts from an archetype"
)

edge(
  "kaihatsu?::onboard",
  :composes,
  "kaihatsu?::doctor",
  "first steps include it"
)

edge("kaihatsu?::rehearse", :composes, "kaihatsu?::run", "CI jobs as tasks")
edge("kaihatsu?::bootstrap", :composes, "kaihatsu?::tasks", "runs setup tasks")

edge(
  "kaihatsu?::gate",
  :composes,
  "kenshutsu?::check",
  "checks are a gate step"
)

edge("kaihatsu?::gate", :composes, "tesuto?::run", "tests are a gate step")
edge("kaihatsu?::tasks", :generalizes, "kaihatsu?::run", "the runnable set")

edge(
  "kaihatsu?::doctor",
  :guards,
  "kaihatsu?::bootstrap",
  "checks what bootstrap needs"
)

edge("kaihatsu?::watch", :lifts, "kaihatsu?::run", "reruns on change")
edge("kaihatsu?::repl", :pairs, "bunmyaku?::eval", "a terminal over eval")
edge("kaihatsu?::onboard", :pairs, "chishiki?::get", "steps live in the wiki")
edge("kaihatsu?::watch", :pairs, "fairu::watch", "files drive the loop")

edge(
  "kaihatsu?::doctor",
  :pairs,
  "genin?::diagnose",
  "environment versus program"
)

edge(
  "kaihatsu?::rehearse",
  :pairs,
  "habu::dispatch",
  "CI jobs run remotely too"
)

edge("kaihatsu?::gate", :pairs, "hadome::failures", "the gate reads baselines")
edge("kaihatsu?::new", :pairs, "kaihatsu?::bootstrap", "new then ready")
edge("kaihatsu?::tasks", :pairs, "kaihatsu?::gate", "gate steps are tasks")
edge("kaihatsu?::repl", :pairs, "koubun?::parse", "every line is parsed")
edge("kaihatsu?::run", :pairs, "shisutemu::run", "a task is a process")
edge("kaihatsu?::gate", :requires, "gitto::hook", "runs declared hooks")
edge("kaihatsu?::run", :requires, "kaihatsu?::tasks", "a declared task")
