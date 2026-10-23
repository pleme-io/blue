space("rogu", {status: :ratified})

verb(
  "rogu",
  "collapse",
  {
    kind: :pure,
    shape: "collapse(lines, window) -> [line]",
    laterals: ["log", "ratelimit"],
    fleet: nil,
    today: "absent",
    meaning: "merge repeated lines into one with a count",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rogu",
  "debug",
  {
    kind: :effect,
    shape: "debug(message, fields) -> nil",
    laterals: ["log", "switch"],
    fleet: "logging-go",
    today: "exists:rogu",
    meaning: "write a structured line at debug level",
    wave: 0,
    origin: "F"
  }
)

verb(
  "rogu",
  "enabled?",
  {
    kind: :pure,
    shape: "enabled?(level) -> Bool",
    laterals: ["log", "switch"],
    fleet: nil,
    today: "exists:rogu",
    meaning: "whether a line at this level would be written",
    wave: 0,
    origin: "F"
  }
)

verb(
  "rogu",
  "error",
  {
    kind: :effect,
    shape: "error(message, fields) -> nil",
    laterals: ["error", "log"],
    fleet: "logging-go",
    today: "exists:rogu",
    meaning: "write a structured line at error level; carries an error record",
    wave: 0,
    origin: "F"
  }
)

verb(
  "rogu",
  "info",
  {
    kind: :effect,
    shape: "info(message, fields) -> nil",
    laterals: ["log"],
    fleet: "logging-go",
    today: "exists:rogu",
    meaning: "write a structured line at info level",
    wave: 0,
    origin: "F",
    contract: "info(message, opts) -> nil"
  }
)

verb(
  "rogu",
  "level",
  {
    kind: :pure,
    shape: "level() -> keyword",
    laterals: ["log", "switch"],
    fleet: nil,
    today: "exists:rogu",
    meaning: "the active level from BLUE_LOG; info when unset",
    wave: 0,
    origin: "F"
  }
)

verb(
  "rogu",
  "parse",
  {
    kind: :pure,
    shape: "parse(line, format) -> record",
    laterals: ["log", "serialize"],
    fleet: nil,
    today: "absent",
    meaning: "a log line (json, logfmt, syslog) to a record",
    wave: 1,
    origin: "F"
  }
)

verb(
  "rogu",
  "query",
  {
    kind: :effect,
    shape: "query(source, question, opts) -> [record]",
    laterals: ["deadline", "log"],
    fleet: nil,
    today: "absent",
    meaning: "ask a log store a question in its own language",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rogu",
  "read",
  {
    kind: :effect,
    shape: "read(source, opts) -> [record]",
    laterals: ["log", "serialize"],
    fleet: nil,
    today: "absent",
    meaning: "all log records from a file, journal or cluster source",
    wave: 1,
    origin: "F"
  }
)

verb(
  "rogu",
  "redact",
  {
    kind: :pure,
    shape: "redact(fields, rules) -> fields",
    laterals: ["capability", "log"],
    fleet: nil,
    today: "absent",
    meaning: "replace secret and personal values before they are written",
    wave: 0,
    origin: "F"
  }
)

verb(
  "rogu",
  "render",
  {
    kind: :pure,
    shape: "render(record, format) -> text",
    laterals: ["log", "serialize"],
    fleet: nil,
    today: "absent",
    meaning: "a record to a log line in a stable format",
    wave: 0,
    origin: "F"
  }
)

verb(
  "rogu",
  "rotate",
  {
    kind: :effect,
    shape: "rotate(file, policy) -> nil",
    laterals: ["log", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "start a new log file by size or age; prune old",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rogu",
  "sample?",
  {
    kind: :pure,
    shape: "sample?(rule, line) -> Bool",
    laterals: ["log", "ratelimit"],
    fleet: nil,
    today: "absent",
    meaning: "decide whether to keep a line under a rate or key rule",
    wave: 2,
    origin: "F"
  }
)

verb(
  "rogu",
  "scope",
  {
    kind: :effect,
    shape: "scope(fields, f) -> value",
    laterals: ["log", "trace"],
    fleet: "pleme-observability",
    today: "absent",
    meaning: "run f with extra fields on every line it logs",
    wave: 1,
    origin: "F",
    contract: "scope(fields) -> value"
  }
)

verb(
  "rogu",
  "sink",
  {
    kind: :decl,
    shape: "sink(target, opts) -> sink",
    laterals: ["config", "log", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "choose where lines go: stderr, file, NATS, journal",
    wave: 1,
    origin: "F"
  }
)

verb(
  "rogu",
  "warn",
  {
    kind: :effect,
    shape: "warn(message, fields) -> nil",
    laterals: ["log"],
    fleet: "logging-go",
    today: "exists:rogu",
    meaning: "write a structured line at warn level",
    wave: 0,
    origin: "F"
  }
)

verb(
  "rogu",
  "watch",
  {
    kind: :stream,
    shape: "watch(source, f, opts) -> nil",
    laterals: ["cancel", "log"],
    fleet: nil,
    today: "absent",
    meaning: "call f per new record until it returns stop",
    wave: 1,
    origin: "F"
  }
)

verb(
  "rogu",
  "with",
  {
    kind: :pure,
    shape: "with(fields) -> logger",
    laterals: ["log"],
    fleet: nil,
    today: "exists:rogu",
    meaning: "a logger that adds fields to every line",
    wave: 0,
    origin: "F"
  }
)

edge("rogu::scope", :composes, "rogu::info", "adds fields to each line")
edge("rogu::with", :composes, "rogu::info", "adds fields to each line")
edge("rogu::query", :composes, "rogu::parse", "store answers become records")
edge("rogu::read", :composes, "rogu::parse", "each source line is parsed")
edge("rogu::collapse", :composes, "rogu::sample?", "both limit repeated lines")
edge("rogu::query", :generalizes, "rogu::read", "asks a store, not a file")
edge("rogu::info", :guards, "rogu::enabled?", "skips work when level is off")
edge("rogu::redact", :guards, "rogu::sink", "runs before any line leaves")
edge("rogu::sample?", :guards, "rogu::sink", "drops lines before they leave")
edge("rogu::render", :inverse, "rogu::parse", "line to record and back")
edge("rogu::sink", :inverse, "rogu::read", "reads what a sink wrote")
edge("rogu::parse", :inverse, "rogu::render", "line to record and back")
edge("rogu::read", :inverse, "rogu::sink", "reads what a sink wrote")
edge("rogu::watch", :lifts, "rogu::read", "follows new records")

edge(
  "rogu::info",
  :pairs,
  "nisshi::append",
  "operator lines versus audit records"
)

edge("rogu::parse", :pairs, "rogu::collapse", "parsed lines are collapsed")
edge("rogu::level", :pairs, "rogu::enabled?", "level then ask")
edge("rogu::sink", :pairs, "rogu::redact", "sink applies redaction")
edge("rogu::enabled?", :pairs, "rogu::sample?", "level then sample")
edge("rogu::rotate", :pairs, "rogu::sink", "file sinks need rotation")
edge("rogu::error", :pairs, "shougai?::note", "errors feed incident notes")
edge("rogu::scope", :pairs, "tsuiseki?::span", "fields and spans share scope")
edge("rogu::debug", :refines, "rogu::info", "lower level, same shape")

edge(
  "rogu::error",
  :refines,
  "rogu::info",
  "highest level, carries error record"
)

edge("rogu::warn", :refines, "rogu::info", "higher level, same shape")

edge(
  "rogu::debug",
  :requires,
  "rogu::enabled?",
  "checked before building fields"
)

edge("rogu::sink", :requires, "rogu::info", "lines need a destination")
edge("rogu::redact", :requires, "rogu::scope", "fields are redacted at scope")
