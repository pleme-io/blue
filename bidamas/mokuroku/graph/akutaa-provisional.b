space("akutaa?", {status: :provisional})

verb(
  "akutaa?",
  "alive?",
  {
    kind: :effect,
    shape: "alive?(pid) -> Bool",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Whether a process is running.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "call",
  {
    kind: :effect,
    shape: "call(pid, request, opts) -> reply",
    laterals: %w[deadline error process],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Send a request and wait for its reply.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "cast",
  {
    kind: :effect,
    shape: "cast(pid, request) -> nil",
    laterals: ["process"],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Send a request and do not wait.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "child",
  {
    kind: :decl,
    shape: "child(name, f, restart) -> spec",
    laterals: ["process"],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "One supervised child and when it restarts.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "connect",
  {
    kind: :effect,
    shape: "connect(node) -> nil",
    laterals: %w[capability process],
    fleet: nil,
    today: "absent",
    meaning: "Join another node so pids reach across.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "demonitor",
  {
    kind: :effect,
    shape: "demonitor(ref) -> nil",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Stop watching a monitored process.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "exit",
  {
    kind: :effect,
    shape: "exit(pid, reason) -> nil",
    laterals: ["process"],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Ask a process to end with a reason.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "info",
  {
    kind: :effect,
    shape: "info(pid) -> record",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Mailbox depth, links, status and memory of a process.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "isolate",
  {
    kind: :pure,
    shape: "isolate(f) -> value",
    laterals: %w[error process],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Run f with private state; return its result or exit reason.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "kill",
  {
    kind: :effect,
    shape: "kill(pid) -> nil",
    laterals: ["process"],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "End a process now; it cannot trap this.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "link",
  {
    kind: :effect,
    shape: "link(pid) -> nil",
    laterals: ["process"],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Tie exits together: one dies, both die.",
    wave: 0,
    origin: "C",
    contract: "link(pid, to, opts) -> nil"
  }
)

verb(
  "akutaa?",
  "list",
  {
    kind: :effect,
    shape: "list(opts) -> [pid]",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Every process on this node.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "migrate",
  {
    kind: :effect,
    shape: "migrate(pid, new code) -> nil",
    laterals: %w[migrate process],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Swap a running process to new code live.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "monitor",
  {
    kind: :effect,
    shape: "monitor(pid) -> ref",
    laterals: ["process"],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Get a down message when it exits; no coupling.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "node",
  {
    kind: :decl,
    shape: "node(name, opts) -> node",
    laterals: %w[capability process],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Declare a node that hosts processes.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "pool",
  {
    kind: :decl,
    shape: "pool(size, f) -> pool",
    laterals: %w[process resource],
    fleet: nil,
    today: "absent",
    meaning: "A fixed set of workers that share requests.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "receive",
  {
    kind: :effect,
    shape: "receive(patterns, opts) -> value",
    laterals: %w[deadline process],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Take the first mailbox message matching a pattern.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "register",
  {
    kind: :effect,
    shape: "register(name, pid) -> nil",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Give a process a name that others can find.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "replay",
  {
    kind: :effect,
    shape: "replay(trace) -> result",
    laterals: %w[test trace],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Re-run a crashed process from its trace without the host.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "reply",
  {
    kind: :effect,
    shape: "reply(request, answer) -> nil",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Answer a call from inside its handler.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "restart",
  {
    kind: :effect,
    shape: "restart(supervisor, child) -> pid",
    laterals: ["process"],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Restart one child with an empty mailbox.",
    wave: 0,
    origin: "C",
    contract: "restart(supervisor, opts) -> pid"
  }
)

verb(
  "akutaa?",
  "self",
  {
    kind: :effect,
    shape: "self() -> pid",
    laterals: ["process"],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "This process's id.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "send",
  {
    kind: :effect,
    shape: "send(pid, message) -> nil",
    laterals: ["process"],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Put a message in a process's mailbox.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "spawn",
  {
    kind: :effect,
    shape: "spawn(f, opts) -> pid",
    laterals: %w[process resource],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Start an isolated process running f.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "stop",
  {
    kind: :effect,
    shape: "stop(pid, opts) -> nil",
    laterals: %w[deadline process],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Ask, wait a grace period, then kill.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "supervise",
  {
    kind: :decl,
    shape: "supervise(strategy, children, opts) -> supervisor",
    laterals: %w[process retry],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "Declare children restarted by a strategy.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "task",
  {
    kind: :effect,
    shape: "task(f) -> handle",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Run f in a process and hold its single result.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "team",
  {
    kind: :effect,
    shape: "team(name) -> group",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Name a set of pids that can be addressed together.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "trace",
  {
    kind: :effect,
    shape: "trace(pid) -> trace",
    laterals: %w[log trace],
    fleet: "blue",
    today: "rust:blue-lang-proc",
    meaning: "The recorded crash trace of a process.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "unlink",
  {
    kind: :effect,
    shape: "unlink(pid) -> nil",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Undo a link.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "wait",
  {
    kind: :effect,
    shape: "wait(pid, opts) -> exit reason",
    laterals: %w[deadline process],
    fleet: nil,
    today: "absent",
    meaning: "Block until a process exits.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "akutaa?",
  "whereis",
  {
    kind: :effect,
    shape: "whereis(name) -> pid or nil",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "The pid under a name, or nil.",
    wave: 1,
    origin: "C"
  }
)

edge(
  "akutaa?::supervise",
  :composes,
  "akutaa?::child",
  "children under a strategy"
)

edge("akutaa?::stop", :composes, "akutaa?::exit", "ask first")
edge("akutaa?::alive?", :composes, "akutaa?::info", "info reduced to a Bool")
edge("akutaa?::stop", :composes, "akutaa?::kill", "then force after grace")

edge(
  "akutaa?::supervise",
  :composes,
  "akutaa?::link",
  "supervisor traps child exits"
)

edge(
  "akutaa?::wait",
  :composes,
  "akutaa?::monitor",
  "waits for the down message"
)

edge(
  "akutaa?::call",
  :composes,
  "akutaa?::receive",
  "selective receive of the answer"
)

edge("akutaa?::supervise", :composes, "akutaa?::restart", "restart by strategy")
edge("akutaa?::receive", :composes, "akutaa?::self", "reads own mailbox")
edge("akutaa?::call", :composes, "akutaa?::send", "send then wait for reply")
edge("akutaa?::isolate", :composes, "akutaa?::spawn", "spawn, wait and unwrap")
edge("akutaa?::pool", :composes, "akutaa?::spawn", "fixed set of spawns")

edge(
  "akutaa?::restart",
  :composes,
  "akutaa?::spawn",
  "new incarnation, empty mailbox"
)

edge("akutaa?::task", :composes, "akutaa?::spawn", "spawn plus one result")

edge(
  "akutaa?::pool",
  :composes,
  "akutaa?::supervise",
  "workers under a supervisor"
)

edge("akutaa?::isolate", :composes, "akutaa?::wait", "result back to caller")
edge("akutaa?::task", :composes, "akutaa?::wait", "result via wait")
edge("akutaa?::monitor", :generalizes, "akutaa?::link", "one-way observation")
edge("akutaa?::team", :generalizes, "akutaa?::register", "one name, many pids")
edge("akutaa?::monitor", :inverse, "akutaa?::demonitor", "watch and stop")
edge("akutaa?::spawn", :inverse, "akutaa?::kill", "start and end")
edge("akutaa?::unlink", :inverse, "akutaa?::link", "couple and uncouple")
edge("akutaa?::demonitor", :inverse, "akutaa?::monitor", "watch and stop")

edge(
  "akutaa?::send",
  :inverse,
  "akutaa?::receive",
  "put in, take out of a mailbox"
)

edge("akutaa?::whereis", :inverse, "akutaa?::register", "name in, pid out")

edge(
  "akutaa?::receive",
  :inverse,
  "akutaa?::send",
  "put in, take out of a mailbox"
)

edge("akutaa?::kill", :inverse, "akutaa?::spawn", "start and end")
edge("akutaa?::stop", :inverse, "akutaa?::spawn", "end versus start")
edge("akutaa?::spawn", :inverse, "akutaa?::stop", "end versus start")
edge("akutaa?::link", :inverse, "akutaa?::unlink", "couple and uncouple")
edge("akutaa?::register", :inverse, "akutaa?::whereis", "name in, pid out")
edge("akutaa?::list", :lifts, "akutaa?::info", "every process")
edge("akutaa?::node", :pairs, "akutaa?::connect", "declare then join")
edge("akutaa?::spawn", :pairs, "akutaa?::link", "spawn and link together")
edge("akutaa?::call", :pairs, "akutaa?::reply", "asker and answerer")

edge(
  "akutaa?::monitor",
  :pairs,
  "akutaa?::supervise",
  "supervision builds on monitoring"
)

edge(
  "akutaa?::supervise",
  :pairs,
  "heikou::policy",
  "restart intensity is a retry policy"
)

edge("akutaa?::task", :pairs, "heikou::spawn", "same shape at two levels")

edge(
  "akutaa?::receive",
  :pairs,
  "heikou::timeout",
  "receive with an after clause"
)

edge(
  "akutaa?::call",
  :pairs,
  "keiyaku?::call",
  "local and remote request-reply"
)

edge(
  "akutaa?::supervise",
  :pairs,
  "kyoujin?::breaker",
  "restart storms trip a breaker"
)

edge(
  "akutaa?::send",
  :pairs,
  "messeeji?::publish",
  "local and remote messaging"
)

edge("akutaa?::trace", :pairs, "nisshi::append", "crash traces are events")
edge("akutaa?::replay", :pairs, "nisshi::replay", "both fold recorded events")
edge("akutaa?::node", :pairs, "toutatsu?::peer", "nodes ride peer links")
edge("akutaa?::kill", :refines, "akutaa?::exit", "exit that cannot be trapped")
edge("akutaa?::cast", :refines, "akutaa?::send", "fire and forget request")
edge("akutaa?::exit", :refines, "akutaa?::send", "exit signal with reason")

edge(
  "akutaa?::child",
  :refines,
  "akutaa?::spawn",
  "a spawn the supervisor repeats"
)

edge("akutaa?::reply", :requires, "akutaa?::call", "only answers a call")

edge(
  "akutaa?::trace",
  :requires,
  "akutaa?::exit",
  "traces exist for crashed processes"
)

edge("akutaa?::connect", :requires, "akutaa?::node", "joins declared nodes")

edge(
  "akutaa?::whereis",
  :requires,
  "akutaa?::register",
  "lookup of a registered name"
)

edge("akutaa?::info", :requires, "akutaa?::spawn", "about a live process")
edge("akutaa?::migrate", :requires, "akutaa?::spawn", "upgrades a live process")
edge("akutaa?::send", :requires, "akutaa?::spawn", "needs a live pid")

edge(
  "akutaa?::replay",
  :requires,
  "akutaa?::trace",
  "replays what trace recorded"
)
