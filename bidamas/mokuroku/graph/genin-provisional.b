space("genin?", {status: :provisional})

verb(
  "genin?",
  "attach",
  {
    kind: :effect,
    shape: "attach(target, opts) -> session",
    laterals: ["capability", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "connect a debugger to a running process",
    wave: 3,
    origin: "F"
  }
)

verb(
  "genin?",
  "backtrace",
  {
    kind: :pure,
    shape: "backtrace(dump) -> [frame]",
    laterals: [],
    fleet: "caixa-backtrace",
    today: "absent",
    meaning: "the call stack of a crash dump",
    wave: 2,
    origin: "F"
  }
)

verb(
  "genin?",
  "bisect",
  {
    kind: :effect,
    shape: "bisect(candidates, f) -> candidate",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "find the first candidate where f turns bad",
    wave: 1,
    origin: "F"
  }
)

verb(
  "genin?",
  "detach",
  {
    kind: :effect,
    shape: "detach(session) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "disconnect a debugger and leave the process running",
    wave: 3,
    origin: "F"
  }
)

verb(
  "genin?",
  "diagnose",
  {
    kind: :effect,
    shape: "diagnose(subject, opts) -> [finding]",
    laterals: ["log", "trace"],
    fleet: nil,
    today: "absent",
    meaning: "collect evidence about a failing subject and rank causes",
    wave: 2,
    origin: "F"
  }
)

verb(
  "genin?",
  "dump",
  {
    kind: :effect,
    shape: "dump(process, opts) -> core",
    laterals: ["capability", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "write the memory and state of a process to a file",
    wave: 3,
    origin: "F"
  }
)

verb(
  "genin?",
  "fingerprint",
  {
    kind: :pure,
    shape: "fingerprint(crash) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "a stable hash that groups crashes of one cause",
    wave: 2,
    origin: "F"
  }
)

verb(
  "genin?",
  "frames",
  {
    kind: :effect,
    shape: "frames(session) -> [frame]",
    laterals: [],
    fleet: "caixa-backtrace",
    today: "absent",
    meaning: "the frames of a paused program or a dump",
    wave: 2,
    origin: "F"
  }
)

verb(
  "genin?",
  "inspect",
  {
    kind: :effect,
    shape: "inspect(session, expr) -> value",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "evaluate an expression in a paused frame",
    wave: 3,
    origin: "F"
  }
)

verb(
  "genin?",
  "pause",
  {
    kind: :effect,
    shape: "pause(target, at, opts) -> breakpoint",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "stop a running program at a place or condition",
    wave: 3,
    origin: "F",
    contract: "pause(target, opts) -> breakpoint"
  }
)

verb(
  "genin?",
  "replay",
  {
    kind: :effect,
    shape: "replay(trace, opts) -> verdict",
    laterals: ["test"],
    fleet: nil,
    today: "rust:blue-lang-proc",
    meaning: "run a recorded crash again and say if it crashed the same",
    wave: 0,
    origin: "F"
  }
)

verb(
  "genin?",
  "reproduce",
  {
    kind: :effect,
    shape: "reproduce(report, opts) -> recipe",
    laterals: ["process", "test"],
    fleet: nil,
    today: "absent",
    meaning: "build a command list that triggers the reported failure",
    wave: 3,
    origin: "F"
  }
)

verb(
  "genin?",
  "resume",
  {
    kind: :effect,
    shape: "resume(session, opts) -> nil",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "let a paused program run on",
    wave: 3,
    origin: "F"
  }
)

verb(
  "genin?",
  "shrink",
  {
    kind: :pure,
    shape: "shrink(input, f) -> input",
    laterals: ["test"],
    fleet: "caixa-proptest",
    today: "absent",
    meaning: "the smallest input for which f still fails",
    wave: 1,
    origin: "F"
  }
)

verb(
  "genin?",
  "step",
  {
    kind: :effect,
    shape: "step(session, how) -> frame",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "run one step: over, into or out",
    wave: 3,
    origin: "F"
  }
)

verb(
  "genin?",
  "stuck",
  {
    kind: :effect,
    shape: "stuck(process) -> [wait]",
    laterals: ["deadline", "process"],
    fleet: nil,
    today: "absent",
    meaning: "what a hung process waits on, as a chain",
    wave: 3,
    origin: "F"
  }
)

verb(
  "genin?",
  "symbolize",
  {
    kind: :pure,
    shape: "symbolize(addresses, binary) -> [frame]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "turn addresses into function names and lines",
    wave: 3,
    origin: "F"
  }
)

verb(
  "genin?",
  "tape",
  {
    kind: :effect,
    shape: "tape(f, opts) -> trace",
    laterals: ["resource", "trace"],
    fleet: nil,
    today: "rust:blue-lang-proc",
    meaning: "run f and keep the host reads needed to replay it",
    wave: 0,
    origin: "F"
  }
)

verb(
  "genin?",
  "trace",
  {
    kind: :stream,
    shape: "trace(program, def, opts) -> nil",
    laterals: ["trace"],
    fleet: nil,
    today: "rust:blue-lang-cli",
    meaning: "print each call of a definition with arguments and result",
    wave: 0,
    origin: "F",
    contract: "trace(program, opts) -> nil"
  }
)

verb(
  "genin?",
  "watch",
  {
    kind: :stream,
    shape: "watch(session, expr, f) -> nil",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "call f when an expression changes value",
    wave: 3,
    origin: "F",
    contract: "watch(session, expr, opts) -> nil"
  }
)

edge(
  "genin?::fingerprint",
  :composes,
  "genin?::backtrace",
  "hash of the top frames"
)

edge("genin?::reproduce", :composes, "genin?::shrink", "minimal recipe")

edge(
  "genin?::backtrace",
  :composes,
  "genin?::symbolize",
  "names the raw addresses"
)

edge("genin?::bisect", :composes, "gitto::list", "walks candidate commits")

edge(
  "genin?::diagnose",
  :composes,
  "tsuiseki?::correlate",
  "evidence from logs and traces"
)

edge(
  "genin?::bisect",
  :generalizes,
  "gitto::ancestor?",
  "any ordered candidates"
)

edge("genin?::detach", :inverse, "genin?::attach", "connect and leave")
edge("genin?::dump", :inverse, "genin?::backtrace", "write and read a dump")
edge("genin?::attach", :inverse, "genin?::detach", "connect and leave")
edge("genin?::backtrace", :inverse, "genin?::dump", "write and read a dump")
edge("genin?::resume", :inverse, "genin?::pause", "lets the program go")
edge("genin?::tape", :inverse, "genin?::replay", "capture and rerun")
edge("genin?::pause", :inverse, "genin?::resume", "lets the program go")
edge("genin?::replay", :inverse, "genin?::tape", "capture and rerun")
edge("genin?::watch", :lifts, "genin?::inspect", "inspect on every change")
edge("genin?::dump", :pairs, "genin?::backtrace", "dump then read its stack")
edge("genin?::stuck", :pairs, "genin?::dump", "a dump shows the wait")
edge("genin?::frames", :pairs, "genin?::inspect", "frames then values")
edge("genin?::step", :pairs, "genin?::inspect", "step then look")
edge("genin?::watch", :pairs, "genin?::pause", "a watch can pause")
edge("genin?::bisect", :pairs, "genin?::reproduce", "bisect needs a repro")

edge(
  "genin?::shrink",
  :pairs,
  "okite::counterexample",
  "shrunk counterexamples"
)

edge("genin?::tape", :pairs, "shougai?::drill", "drills may record a crash")

edge(
  "genin?::diagnose",
  :pairs,
  "shougai?::note",
  "findings land in the timeline"
)

edge("genin?::shrink", :pairs, "tesuto?::fuzz", "fuzz crashes are shrunk")

edge(
  "genin?::fingerprint",
  :pairs,
  "tesuto?::quarantine",
  "group repeats of one failure"
)

edge("genin?::replay", :pairs, "tesuto?::run", "a replay becomes a test")

edge(
  "genin?::trace",
  :pairs,
  "tsuiseki?::span",
  "call trace versus request trace"
)

edge(
  "genin?::shrink",
  :refines,
  "genin?::bisect",
  "searches input, not history"
)

edge("genin?::stuck", :refines, "genin?::diagnose", "hang-specific evidence")
edge("genin?::backtrace", :refines, "genin?::frames", "stack of a dump")
edge("genin?::step", :refines, "genin?::resume", "resume by one step")
edge("genin?::trace", :refines, "genin?::tape", "prints calls, no replay data")
edge("genin?::pause", :requires, "genin?::attach", "needs a session")

edge(
  "genin?::reproduce",
  :requires,
  "genin?::fingerprint",
  "same cause as the report"
)

edge("genin?::frames", :requires, "genin?::pause", "frames of the pause")
edge("genin?::inspect", :requires, "genin?::pause", "reads a paused frame")
edge("genin?::step", :requires, "genin?::pause", "steps from a paused frame")
edge("genin?::replay", :requires, "genin?::tape", "needs the trace file")

edge(
  "genin?::attach",
  :requires,
  "kaihatsu?::doctor",
  "access is checked first"
)

edge(
  "genin?::symbolize",
  :requires,
  "rirezu?::build",
  "needs the build symbols"
)
