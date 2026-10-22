space("dairi?", {status: :provisional})

verb(
  "dairi?",
  "advance",
  {
    kind: :effect,
    shape: "advance(agent, state) -> state",
    laterals: ["trace"],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "one turn: ask, run tool calls, observe",
    wave: 2,
    origin: "G"
  }
)

verb(
  "dairi?",
  "agent",
  {
    kind: :decl,
    shape: "agent(spec) -> agent",
    laterals: ["config", "validate"],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "declare an agent: model, tools, policy, limits",
    wave: 1,
    origin: "G"
  }
)

verb(
  "dairi?",
  "approve",
  {
    kind: :effect,
    shape: "approve(request) -> decision",
    laterals: ["capability", "log"],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "let a person or policy allow one effect",
    wave: 1,
    origin: "G"
  }
)

verb(
  "dairi?",
  "budget",
  {
    kind: :decl,
    shape: "budget(limits) -> budget",
    laterals: ["config"],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "declare caps on tokens, cost, steps and time",
    wave: 1,
    origin: "G"
  }
)

verb(
  "dairi?",
  "call",
  {
    kind: :effect,
    shape: "call(tool, args, opts) -> result",
    laterals: ["deadline", "idempotent", "retry", "trace"],
    fleet: "arnes-mcp-client",
    today: "absent",
    meaning: "invoke one tool; failure is a typed result",
    wave: 2,
    origin: "G"
  }
)

verb(
  "dairi?",
  "compact",
  {
    kind: :pure,
    shape: "compact(state, opts) -> state",
    laterals: [],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "shorten history to fit the window, keep decisions",
    wave: 2,
    origin: "G"
  }
)

verb(
  "dairi?",
  "connect",
  {
    kind: :effect,
    shape: "connect(server, opts) -> client",
    laterals: ["deadline", "resource", "retry"],
    fleet: "arnes-mcp-client",
    today: "absent",
    meaning: "open an MCP client to a command or URL",
    wave: 2,
    origin: "G"
  }
)

verb(
  "dairi?",
  "delegate",
  {
    kind: :effect,
    shape: "delegate(agent, task, opts) -> outcome",
    laterals: ["deadline", "process"],
    fleet: nil,
    today: "absent",
    meaning: "hand a task to another agent and take its outcome",
    wave: 3,
    origin: "G"
  }
)

verb(
  "dairi?",
  "find",
  {
    kind: :effect,
    shape: "find(memory, query) -> facts",
    laterals: [],
    fleet: "arnes-store",
    today: "absent",
    meaning: "recall facts that match a query",
    wave: 3,
    origin: "G"
  }
)

verb(
  "dairi?",
  "get",
  {
    kind: :pure,
    shape: "get(memory, key) -> value or nil",
    laterals: [],
    fleet: "arnes-store",
    today: "absent",
    meaning: "recall a fact by key",
    wave: 2,
    origin: "G"
  }
)

verb(
  "dairi?",
  "list",
  {
    kind: :effect,
    shape: "list(client) -> tools",
    laterals: ["deadline"],
    fleet: "arnes-mcp-client",
    today: "absent",
    meaning: "the tools a connected server offers",
    wave: 2,
    origin: "G"
  }
)

verb(
  "dairi?",
  "on",
  {
    kind: :decl,
    shape: "on(agent, event, handler) -> agent",
    laterals: [],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "bind a hook to an agent event",
    wave: 1,
    origin: "G"
  }
)

verb(
  "dairi?",
  "plan",
  {
    kind: :pure,
    shape: "plan(agent, task) -> actions",
    laterals: [],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "what the agent would do, with no effect",
    wave: 2,
    origin: "G"
  }
)

verb(
  "dairi?",
  "put",
  {
    kind: :effect,
    shape: "put(memory, key, value) -> value",
    laterals: ["resource"],
    fleet: "arnes-store",
    today: "absent",
    meaning: "remember a fact across turns",
    wave: 2,
    origin: "G"
  }
)

verb(
  "dairi?",
  "replay",
  {
    kind: :effect,
    shape: "replay(trace, opts) -> outcome",
    laterals: ["test", "trace"],
    fleet: nil,
    today: "absent",
    meaning: "re-run a trace with recorded replies, no model",
    wave: 3,
    origin: "G"
  }
)

verb(
  "dairi?",
  "resume",
  {
    kind: :effect,
    shape: "resume(session) -> state",
    laterals: ["resource"],
    fleet: "arnes-store",
    today: "absent",
    meaning: "continue a saved session",
    wave: 1,
    origin: "G"
  }
)

verb(
  "dairi?",
  "run",
  {
    kind: :effect,
    shape: "run(agent, task, opts) -> outcome",
    laterals: ["cancel", "deadline", "log", "trace"],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "loop until the agent ends or a budget runs out",
    wave: 2,
    origin: "G"
  }
)

verb(
  "dairi?",
  "screen",
  {
    kind: :pure,
    shape: "screen(tool, args) -> {allow, ask, deny, why}",
    laterals: ["capability", "validate"],
    fleet: "guardrail",
    today: "absent",
    meaning: "rules decide a tool call before it runs",
    wave: 1,
    origin: "G"
  }
)

verb(
  "dairi?",
  "serve",
  {
    kind: :effect,
    shape: "serve(tools, transport) -> handle",
    laterals: ["capability", "resource"],
    fleet: "kotoba",
    today: "absent",
    meaning: "offer tools as an MCP server",
    wave: 2,
    origin: "G"
  }
)

verb(
  "dairi?",
  "skill",
  {
    kind: :decl,
    shape: "skill(name, body) -> skill",
    laterals: ["validate"],
    fleet: "arnes-tools",
    today: "absent",
    meaning: "declare reusable instructions an agent can load",
    wave: 1,
    origin: "G"
  }
)

verb(
  "dairi?",
  "spawn",
  {
    kind: :effect,
    shape: "spawn(agent, task) -> handle",
    laterals: ["process", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "start a sub-agent without waiting",
    wave: 3,
    origin: "G"
  }
)

verb(
  "dairi?",
  "stop",
  {
    kind: :effect,
    shape: "stop(handle) -> nil",
    laterals: ["cancel"],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "end a run at the next safe point",
    wave: 2,
    origin: "G"
  }
)

verb(
  "dairi?",
  "tool",
  {
    kind: :decl,
    shape: "tool(name, schema, f) -> tool",
    laterals: ["validate"],
    fleet: "arnes-tools",
    today: "absent",
    meaning: "declare a tool: name, input shape, body",
    wave: 1,
    origin: "G"
  }
)

verb(
  "dairi?",
  "wait",
  {
    kind: :effect,
    shape: "wait(handle, opts) -> outcome",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "wait for a sub-agent to end",
    wave: 3,
    origin: "G"
  }
)

edge("dairi?::run", :composes, "dairi?::advance", "a loop of turns")
edge("dairi?::agent", :composes, "dairi?::budget", "and limits")
edge("dairi?::advance", :composes, "dairi?::call", "the tool turn")
edge("dairi?::delegate", :composes, "dairi?::spawn", "start")
edge("dairi?::agent", :composes, "dairi?::tool", "an agent has tools")
edge("dairi?::delegate", :composes, "dairi?::wait", "join")
edge("dairi?::advance", :composes, "moderu?::ask", "the model turn")
edge("dairi?::compact", :guards, "dairi?::advance", "fit the window each turn")

edge(
  "dairi?::screen",
  :guards,
  "dairi?::approve",
  "only ask when rules say ask"
)

edge("dairi?::budget", :guards, "dairi?::run", "stops a runaway loop")
edge("dairi?::plan", :guards, "dairi?::run", "show before doing")
edge("dairi?::run", :inverse, "dairi?::resume", "continue a stored run")
edge("dairi?::resume", :inverse, "dairi?::run", "continue a stored run")
edge("dairi?::stop", :inverse, "dairi?::run", "ends the loop")
edge("dairi?::run", :inverse, "dairi?::stop", "ends the loop")
edge("dairi?::put", :pairs, "dairi?::get", "memory write and read")
edge("dairi?::get", :pairs, "dairi?::put", "memory read and write")
edge("dairi?::connect", :pairs, "dairi?::serve", "client and server")
edge("dairi?::wait", :pairs, "dairi?::spawn", "start and join")
edge("dairi?::stop", :pairs, "dairi?::wait", "end then join")
edge("dairi?::find", :refines, "dairi?::get", "by query, not by key")
edge("dairi?::skill", :refines, "dairi?::tool", "instructions, not an effect")
edge("dairi?::skill", :requires, "bunsho?::parse", "a skill is a document")
edge("dairi?::on", :requires, "dairi?::agent", "hooks on an agent")
edge("dairi?::spawn", :requires, "dairi?::agent", "a sub-agent")

edge(
  "dairi?::delegate",
  :requires,
  "dairi?::budget",
  "child budget from parent"
)

edge("dairi?::stop", :requires, "dairi?::budget", "budget can stop")
edge("dairi?::approve", :requires, "dairi?::call", "guards a call")
edge("dairi?::list", :requires, "dairi?::connect", "tools of a client")
edge("dairi?::call", :requires, "dairi?::list", "call a listed tool")
edge("dairi?::replay", :requires, "dairi?::resume", "trace is a stored run")
edge("dairi?::on", :requires, "dairi?::run", "hooks fire inside a run")
edge("dairi?::call", :requires, "dairi?::screen", "rules before effect")
edge("dairi?::tool", :requires, "dairi?::screen", "every call is screened")
edge("dairi?::plan", :requires, "dairi?::tool", "tools a plan would call")
edge("dairi?::serve", :requires, "dairi?::tool", "offers tools")
edge("dairi?::approve", :requires, "gamen?::prompt", "ask a person")

edge(
  "dairi?::connect",
  :requires,
  "gamen?::start",
  "a client may need a surface"
)

edge("dairi?::find", :requires, "kensaku?::search", "memory is an index")

edge(
  "dairi?::replay",
  :requires,
  "moderu?::ask",
  "replies are recorded, not asked"
)

edge("dairi?::compact", :requires, "moderu?::fit", "shared budget rule")
edge("dairi?::call", :requires, "moderu?::tokens", "result size is bounded")
