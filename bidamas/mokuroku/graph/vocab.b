vocab(
  "acquire",
  {
    subject: "source",
    args: %w[~source name],
    opts: true,
    returns: "lease",
    raises: ["timeout"],
    kind: :effect,
    meaning: "take a lease or credential",
    ref: nil,
    status: :decided
  }
)

vocab(
  "add",
  {
    subject: "a",
    args: %w[a b],
    opts: false,
    returns: "value",
    raises: [],
    kind: :pure,
    meaning: "a moved or summed by b",
    ref: "§3.5",
    status: :stdlib
  }
)

vocab(
  "address",
  {
    subject: "data",
    args: %w[data algorithm?],
    opts: true,
    returns: "oid",
    raises: [],
    kind: :pure,
    meaning: "content address of a value",
    ref: nil,
    status: :decided
  }
)

vocab(
  "admit",
  {
    subject: "subject",
    args: %w[subject policy event?],
    opts: true,
    returns: "decision",
    raises: [],
    kind: :any,
    meaning: "decide whether a thing may pass",
    ref: nil,
    status: :decided
  }
)

vocab(
  "advance",
  {
    subject: "subject",
    args: %w[subject by],
    opts: true,
    returns: "state",
    raises: [],
    kind: :effect,
    meaning: "move a world, run or clock forward",
    ref: nil,
    status: :decided
  }
)

vocab(
  "alive?",
  {
    subject: "subject",
    args: %w[subject now?],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :any,
    meaning: "whether a process, link or session is alive",
    ref: nil,
    status: :decided
  }
)

vocab(
  "all",
  {
    subject: "fs",
    args: ["fs"],
    opts: true,
    returns: "[value]",
    raises: ["first error"],
    kind: :effect,
    meaning: "run functions concurrently; values in order",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "all?",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :pure,
    meaning: "whether f holds for every item",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "analyze",
  {
    subject: "subject",
    args: %w[subject by?],
    opts: true,
    returns: "verdict",
    raises: [],
    kind: :pure,
    meaning: "derive findings from a subject",
    ref: nil,
    status: :decided
  }
)

vocab(
  "any?",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :pure,
    meaning: "whether f holds for at least one item",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "append",
  {
    subject: "target",
    args: %w[target content],
    opts: true,
    returns: "nil",
    raises: ["permission_denied"],
    kind: :effect,
    meaning: "add to the end of a target",
    ref: "§3.1",
    status: :stdlib
  }
)

vocab(
  "apply",
  {
    subject: "target",
    args: %w[target change?],
    opts: true,
    returns: "result",
    raises: ["conflict"],
    kind: :effect,
    meaning: "carry out a reviewed plan, patch or delta; behind a reconciler, raises conflict",
    ref: "§3.3",
    status: :decided
  }
)

vocab(
  "approve",
  {
    subject: "subject",
    args: %w[subject gate?],
    opts: true,
    returns: "decision",
    raises: [],
    kind: :effect,
    meaning: "record approval of a request or gate",
    ref: nil,
    status: :decided
  }
)

vocab(
  "arrange",
  {
    subject: "systems",
    args: ["systems"],
    opts: false,
    returns: "order",
    raises: [],
    kind: :pure,
    meaning: "order systems so no two clash on a write",
    ref: nil,
    status: :decided
  }
)

vocab(
  "assemble",
  {
    subject: "ast",
    args: %w[ast board],
    opts: false,
    returns: "image",
    raises: [],
    kind: :pure,
    meaning: "link emitted code into an image",
    ref: nil,
    status: :decided
  }
)

vocab(
  "assign",
  {
    subject: "subject",
    args: %w[subject who],
    opts: true,
    returns: "nil",
    raises: ["not_found"],
    kind: :effect,
    meaning: "name the owner of a subject",
    ref: nil,
    status: :decided
  }
)

vocab(
  "at",
  {
    subject: "subject",
    args: %w[subject position],
    opts: false,
    returns: "item or nil",
    raises: [],
    kind: :pure,
    meaning: "the item or state at a position",
    ref: nil,
    status: :decided
  }
)

vocab(
  "audit",
  {
    subject: "actor",
    args: %w[actor action target outcome],
    opts: true,
    returns: "record",
    raises: [],
    kind: :effect,
    meaning: "append who did what to what, with the result",
    ref: nil,
    status: :decided
  }
)

vocab(
  "audit_lock",
  {
    subject: "lock",
    args: ["lock"],
    opts: true,
    returns: "[advisory]",
    raises: [],
    kind: :effect,
    meaning: "locked packages checked against advisories",
    ref: nil,
    status: :decided
  }
)

vocab(
  "batch",
  {
    subject: "store",
    args: %w[store ops],
    opts: true,
    returns: "[result]",
    raises: [],
    kind: :effect,
    meaning: "several operations in one call",
    ref: nil,
    status: :decided
  }
)

vocab(
  "become",
  {
    subject: "command",
    args: %w[command args?],
    opts: true,
    returns: "never",
    raises: ["command_not_found"],
    kind: :effect,
    meaning: "replace this program with a command",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "bind",
  {
    subject: "subject",
    args: %w[subject role scope],
    opts: true,
    returns: "binding",
    raises: [],
    kind: :effect,
    meaning: "give a subject a role inside a scope",
    ref: nil,
    status: :decided
  }
)

vocab(
  "bisect",
  {
    subject: "candidates",
    args: %w[candidates good? bad? test],
    opts: false,
    returns: "candidate",
    raises: [],
    kind: :effect,
    meaning: "find the first bad candidate by halving",
    ref: nil,
    status: :decided
  }
)

vocab(
  "bootstrap",
  {
    subject: "data",
    args: %w[data statistic rng n],
    opts: false,
    returns: "interval",
    raises: [],
    kind: :pure,
    meaning: "resample to estimate a statistic",
    ref: nil,
    status: :decided
  }
)

vocab(
  "bounds",
  {
    subject: "shape",
    args: ["shape"],
    opts: false,
    returns: "box",
    raises: [],
    kind: :pure,
    meaning: "the smallest box holding a shape",
    ref: nil,
    status: :decided
  }
)

vocab(
  "budget",
  {
    subject: "scope",
    args: %w[scope? amount? period?],
    opts: true,
    returns: "budget",
    raises: [],
    kind: :pure,
    meaning: "a limit on spend, error or work",
    ref: nil,
    status: :decided
  }
)

vocab(
  "build",
  {
    subject: "project",
    args: %w[project targets?],
    opts: true,
    returns: "artifact",
    raises: ["command_failed"],
    kind: :effect,
    meaning: "produce outputs from a project",
    ref: nil,
    status: :decided
  }
)

vocab(
  "build_log",
  {
    subject: "installable",
    args: ["installable"],
    opts: false,
    returns: "text",
    raises: [],
    kind: :effect,
    meaning: "the build log of a derivation",
    ref: nil,
    status: :decided
  }
)

vocab(
  "call",
  {
    subject: "target",
    args: %w[target input],
    opts: true,
    returns: "reply",
    raises: ["timeout"],
    kind: :effect,
    meaning: "invoke one remote operation and wait for its reply",
    ref: nil,
    status: :decided
  }
)

vocab(
  "cancel",
  {
    subject: "handle",
    args: %w[handle reason?],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "ask a running thing to stop",
    ref: nil,
    status: :decided
  }
)

vocab(
  "capture",
  {
    subject: "command",
    args: %w[command args?],
    opts: true,
    returns: "text",
    raises: %w[command_not_found command_failed],
    kind: :effect,
    meaning: "run and return stdout without its trailing newline",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "case",
  {
    subject: "name",
    args: %w[name f],
    opts: false,
    returns: "test",
    raises: [],
    kind: :pure,
    meaning: "declare one named test",
    ref: nil,
    status: :decided
  }
)

vocab(
  "catchup",
  {
    subject: "review",
    args: ["review"],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "bring a branch up to its base",
    ref: nil,
    status: :decided
  }
)

vocab(
  "centroid",
  {
    subject: "shape",
    args: ["shape"],
    opts: false,
    returns: "point",
    raises: [],
    kind: :pure,
    meaning: "the centre of a shape",
    ref: nil,
    status: :decided
  }
)

vocab(
  "chain",
  {
    subject: "prev",
    args: %w[prev payload],
    opts: false,
    returns: "hash",
    raises: [],
    kind: :pure,
    meaning: "the hash that follows prev when payload is appended",
    ref: nil,
    status: :decided
  }
)

vocab(
  "chain_of",
  {
    subject: "chain",
    args: %w[chain roots],
    opts: true,
    returns: "[cert]",
    raises: [],
    kind: :pure,
    meaning: "a valid chain from a leaf to a trusted root",
    ref: nil,
    status: :decided
  }
)

vocab(
  "check",
  {
    subject: "subject",
    args: %w[subject rules?],
    opts: true,
    returns: "[finding]",
    raises: [],
    kind: :any,
    meaning: "findings of a subject against rules; empty when sound; kyohi::enforce is the raising form",
    ref: "§4.9",
    status: :decided
  }
)

vocab(
  "checksum",
  {
    subject: "data",
    args: %w[data algorithm?],
    opts: true,
    returns: "integer",
    raises: [],
    kind: :pure,
    meaning: "a short integrity number over data",
    ref: nil,
    status: :decided
  }
)

vocab(
  "choice",
  {
    subject: "instructions",
    args: %w[instructions options?],
    opts: false,
    returns: "question",
    raises: [],
    kind: :pure,
    meaning: "a closed question with a fixed set of answers",
    ref: nil,
    status: :decided
  }
)

vocab(
  "choose",
  {
    subject: "items",
    args: ["items"],
    opts: true,
    returns: "item or nil",
    raises: [],
    kind: :effect,
    meaning: "a human picks from a list",
    ref: nil,
    status: :decided
  }
)

vocab(
  "chunk",
  {
    subject: "xs",
    args: %w[xs n?],
    opts: true,
    returns: "[list]",
    raises: [],
    kind: :pure,
    meaning: "the items in consecutive groups of n",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "claim",
  {
    subject: "stack",
    args: ["stack"],
    opts: true,
    returns: "lease",
    raises: ["conflict"],
    kind: :effect,
    meaning: "claim the state against a second writer",
    ref: nil,
    status: :decided
  }
)

vocab(
  "classify",
  {
    subject: "subject",
    args: %w[subject rules?],
    opts: true,
    returns: "label",
    raises: [],
    kind: :pure,
    meaning: "put a subject in one of a closed set of classes",
    ref: nil,
    status: :decided
  }
)

vocab(
  "clear",
  {
    subject: "store",
    args: %w[store prefix?],
    opts: true,
    returns: "count",
    raises: [],
    kind: :effect,
    meaning: "remove every entry, or those under a prefix",
    ref: nil,
    status: :decided
  }
)

vocab(
  "close",
  {
    subject: "handle",
    args: ["handle"],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "release a handle; closing twice is done",
    ref: nil,
    status: :decided
  }
)

vocab(
  "closure",
  {
    subject: "lock",
    args: ["lock"],
    opts: false,
    returns: "graph",
    raises: [],
    kind: :pure,
    meaning: "the dependency graph a lock implies",
    ref: nil,
    status: :decided
  }
)

vocab(
  "coalesce",
  {
    subject: "ranges",
    args: ["ranges"],
    opts: false,
    returns: "[range]",
    raises: [],
    kind: :pure,
    meaning: "join overlapping ranges into disjoint ones",
    ref: nil,
    status: :decided
  }
)

vocab(
  "command",
  {
    subject: "spec",
    args: %w[spec f],
    opts: false,
    returns: "value",
    raises: [],
    kind: :effect,
    meaning: "run a program through its declared command line",
    ref: nil,
    status: :decided
  }
)

vocab(
  "commit",
  {
    subject: "subject",
    args: %w[subject what?],
    opts: true,
    returns: "oid or nil",
    raises: [],
    kind: :effect,
    meaning: "make staged changes or a position durable",
    ref: nil,
    status: :decided
  }
)

vocab(
  "compact",
  {
    subject: "store",
    args: %w[store policy?],
    opts: true,
    returns: "count",
    raises: [],
    kind: :effect,
    meaning: "reclaim space or fold old records",
    ref: nil,
    status: :decided
  }
)

vocab(
  "compare",
  {
    subject: "a",
    args: %w[a b],
    opts: true,
    returns: "-1, 0 or 1",
    raises: [],
    kind: :pure,
    meaning: "order two values",
    ref: nil,
    status: :decided
  }
)

vocab(
  "compile",
  {
    subject: "graph",
    args: ["graph"],
    opts: true,
    returns: "compiled graph",
    raises: [],
    kind: :pure,
    meaning: "compile a graph; shapes proved before any run",
    ref: nil,
    status: :decided
  }
)

vocab(
  "complete",
  {
    subject: "args",
    args: %w[args spec],
    opts: false,
    returns: "[text]",
    raises: [],
    kind: :pure,
    meaning: "the words that may follow a partial input",
    ref: nil,
    status: :decided
  }
)

vocab(
  "compose",
  {
    subject: "first",
    args: %w[first second?],
    opts: false,
    returns: "function",
    raises: [],
    kind: :pure,
    meaning: "join two functions or parts into one",
    ref: nil,
    status: :decided
  }
)

vocab(
  "compress",
  {
    subject: "data",
    args: %w[data algorithm?],
    opts: true,
    returns: "bytes",
    raises: [],
    kind: :pure,
    meaning: "bytes made smaller",
    ref: nil,
    status: :decided
  }
)

vocab(
  "connect",
  {
    subject: "address",
    args: ["address"],
    opts: true,
    returns: "conn",
    raises: ["timeout"],
    kind: :effect,
    meaning: "open a connection to an address",
    ref: nil,
    status: :decided
  }
)

vocab(
  "constraint",
  {
    subject: "text",
    args: ["text"],
    opts: false,
    returns: "constraint",
    raises: [],
    kind: :pure,
    meaning: "a version constraint as a value",
    ref: nil,
    status: :decided
  }
)

vocab(
  "contains?",
  {
    subject: "xs",
    args: %w[xs x],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :pure,
    meaning: "whether x is among the items or the text",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "convert",
  {
    subject: "value",
    args: %w[value to from?],
    opts: true,
    returns: "value",
    raises: [],
    kind: :pure,
    meaning: "a value in another unit, format or space",
    ref: nil,
    status: :decided
  }
)

vocab(
  "copy",
  {
    subject: "from",
    args: %w[from to],
    opts: true,
    returns: "nil",
    raises: %w[not_found exists],
    kind: :effect,
    meaning: "place a copy at a destination",
    ref: "§3.1",
    status: :stdlib
  }
)

vocab(
  "correlate",
  {
    subject: "a",
    args: %w[a b],
    opts: true,
    returns: "[record]",
    raises: [],
    kind: :pure,
    meaning: "link records that share an identity or window",
    ref: nil,
    status: :decided
  }
)

vocab(
  "cors",
  {
    subject: "handler",
    args: %w[handler policy],
    opts: false,
    returns: "handler",
    raises: [],
    kind: :pure,
    meaning: "add cross-origin headers to a handler's answers by policy",
    ref: nil,
    status: :decided
  }
)

vocab(
  "count",
  {
    subject: "xs",
    args: %w[xs f?],
    opts: true,
    returns: "int",
    raises: [],
    kind: :any,
    meaning: "how many items, or how many match",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "coverage",
  {
    subject: "subject",
    args: %w[subject locales?],
    opts: false,
    returns: "ratio",
    raises: [],
    kind: :pure,
    meaning: "how much of a whole is covered",
    ref: nil,
    status: :decided
  }
)

vocab(
  "create",
  {
    subject: "store",
    args: %w[~store key value],
    opts: true,
    returns: "value",
    raises: ["exists"],
    kind: :any,
    meaning: "add a new entry; refuse to overwrite",
    ref: "§3.2",
    status: :stdlib
  }
)

vocab(
  "cut",
  {
    subject: "clip",
    args: %w[clip from to],
    opts: false,
    returns: "clip",
    raises: [],
    kind: :pure,
    meaning: "the part of a clip between two times",
    ref: nil,
    status: :decided
  }
)

vocab(
  "debug",
  {
    subject: "message",
    args: %w[message fields?],
    opts: false,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "a structured log line at debug level",
    ref: "§3.5",
    status: :stdlib
  }
)

vocab(
  "decide",
  {
    subject: "facts",
    args: %w[facts history? policy? now?],
    opts: false,
    returns: "decision",
    raises: [],
    kind: :pure,
    meaning: "choose an outcome from facts and a policy",
    ref: nil,
    status: :decided
  }
)

vocab(
  "declare",
  {
    subject: "name",
    args: %w[name spec?],
    opts: true,
    returns: "decl",
    raises: [],
    kind: :pure,
    meaning: "declare an entry; nothing runs",
    ref: nil,
    status: :decided
  }
)

vocab(
  "decode",
  {
    subject: "data",
    args: %w[data encoding],
    opts: false,
    returns: "bytes",
    raises: ["decode_error"],
    kind: :pure,
    meaning: "text to bytes in an encoding",
    ref: "§3.4",
    status: :stdlib
  }
)

vocab(
  "dedupe",
  {
    subject: "xs",
    args: %w[xs key?],
    opts: true,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "drop repeats",
    ref: nil,
    status: :decided
  }
)

vocab(
  "defaults",
  {
    subject: "app",
    args: ["app?"],
    opts: false,
    returns: "record",
    raises: [],
    kind: :pure,
    meaning: "the default values of a subject",
    ref: nil,
    status: :decided
  }
)

vocab(
  "delete",
  {
    subject: "store",
    args: %w[~store key],
    opts: true,
    returns: "nil",
    raises: ["permission_denied"],
    kind: :any,
    meaning: "make the entry absent; absent counts as done",
    ref: "§3.2",
    status: :stdlib
  }
)

vocab(
  "delta",
  {
    subject: "crdt",
    args: %w[crdt since],
    opts: false,
    returns: "delta",
    raises: [],
    kind: :pure,
    meaning: "only the updates a replica has not yet seen",
    ref: nil,
    status: :decided
  }
)

vocab(
  "depend",
  {
    subject: "project",
    args: %w[project dep],
    opts: true,
    returns: "[changed pin]",
    raises: [],
    kind: :effect,
    meaning: "declare a dependency and re-lock",
    ref: nil,
    status: :decided
  }
)

vocab(
  "derive",
  {
    subject: "secret",
    args: %w[secret salt info?],
    opts: true,
    returns: "key",
    raises: [],
    kind: :pure,
    meaning: "a key or id derived from inputs",
    ref: nil,
    status: :decided
  }
)

vocab(
  "describe",
  {
    subject: "subject",
    args: %w[subject at?],
    opts: false,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "a plain-language account of a subject",
    ref: nil,
    status: :decided
  }
)

vocab(
  "detect",
  {
    subject: "data",
    args: %w[data rules?],
    opts: true,
    returns: "format or nil",
    raises: [],
    kind: :pure,
    meaning: "find which format or event the data is",
    ref: nil,
    status: :decided
  }
)

vocab(
  "diagsum",
  {
    subject: "m",
    args: ["m"],
    opts: false,
    returns: "number",
    raises: [],
    kind: :pure,
    meaning: "the sum of the diagonal of a matrix",
    ref: nil,
    status: :decided
  }
)

vocab(
  "diff",
  {
    subject: "a",
    args: %w[a b],
    opts: true,
    returns: "[change]",
    raises: [],
    kind: :any,
    meaning: "differences between two values as change records",
    ref: "§3.4",
    status: :stdlib
  }
)

vocab(
  "dimension",
  {
    subject: "expr",
    args: ["expr"],
    opts: false,
    returns: "dimension",
    raises: [],
    kind: :pure,
    meaning: "the unit dimension an expression proves to have",
    ref: nil,
    status: :decided
  }
)

vocab(
  "distance",
  {
    subject: "a",
    args: %w[a b],
    opts: true,
    returns: "number",
    raises: [],
    kind: :pure,
    meaning: "how far apart two values are",
    ref: nil,
    status: :decided
  }
)

vocab(
  "drain",
  {
    subject: "subject",
    args: ["subject"],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "stop taking new work and finish what is held",
    ref: nil,
    status: :decided
  }
)

vocab(
  "draw",
  {
    subject: "rng",
    args: %w[rng kind?],
    opts: false,
    returns: "value",
    raises: [],
    kind: :pure,
    meaning: "one random value from a stream",
    ref: nil,
    status: :decided
  }
)

vocab(
  "drift",
  {
    subject: "a",
    args: %w[a b?],
    opts: true,
    returns: "[change]",
    raises: [],
    kind: :effect,
    meaning: "differences between wanted and actual state",
    ref: nil,
    status: :decided
  }
)

vocab(
  "drop",
  {
    subject: "xs",
    args: %w[xs n],
    opts: false,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "all but the first n items",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "drop_while",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "the items after the leading run where f holds",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "due?",
  {
    subject: "subject",
    args: %w[subject now last?],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :pure,
    meaning: "whether a time, key or trigger has come",
    ref: nil,
    status: :decided
  }
)

vocab(
  "each",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "call f on each item for its effect",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "embed",
  {
    subject: "model",
    args: %w[~model input],
    opts: true,
    returns: "vector",
    raises: [],
    kind: :effect,
    meaning: "text or items as vectors",
    ref: nil,
    status: :decided
  }
)

vocab(
  "empty?",
  {
    subject: "xs",
    args: ["xs"],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :pure,
    meaning: "whether there are no items",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "enabled?",
  {
    subject: "level",
    args: ["level"],
    opts: false,
    returns: "Bool",
    raises: ["bad_option"],
    kind: :pure,
    meaning: "whether a line at this level would be written",
    ref: "§3.5",
    status: :decided
  }
)

vocab(
  "enclose",
  {
    subject: "data",
    args: %w[data key_id],
    opts: true,
    returns: "envelope",
    raises: [],
    kind: :effect,
    meaning: "envelope encryption with a fresh data key wrapped by a managed key",
    ref: nil,
    status: :decided
  }
)

vocab(
  "encode",
  {
    subject: "data",
    args: %w[data encoding],
    opts: false,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "bytes to text in an encoding",
    ref: "§3.4",
    status: :stdlib
  }
)

vocab(
  "enforce",
  {
    subject: "subject",
    args: %w[subject rules?],
    opts: true,
    returns: "nil",
    raises: ["refused"],
    kind: :effect,
    meaning: "check a subject, then raise one error carrying every finding; nil when sound",
    ref: nil,
    status: :decided
  }
)

vocab(
  "enter",
  {
    subject: "group",
    args: %w[group member?],
    opts: false,
    returns: "view",
    raises: [],
    kind: :effect,
    meaning: "join a group",
    ref: nil,
    status: :decided
  }
)

vocab(
  "entries",
  {
    subject: "m",
    args: ["m"],
    opts: false,
    returns: "[pair]",
    raises: [],
    kind: :pure,
    meaning: "the key and value pairs of a map",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "entry",
  {
    subject: "fields",
    args: ["fields"],
    opts: false,
    returns: "record",
    raises: [],
    kind: :pure,
    meaning: "build one record value with its links",
    ref: nil,
    status: :decided
  }
)

vocab(
  "error",
  {
    subject: "message",
    args: %w[message fields?],
    opts: false,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "a structured log line at error level",
    ref: "§3.5",
    status: :stdlib
  }
)

vocab(
  "estimate",
  {
    subject: "subject",
    args: %w[subject method? n?],
    opts: true,
    returns: "estimate",
    raises: [],
    kind: :pure,
    meaning: "a value with its range from a method",
    ref: nil,
    status: :decided
  }
)

vocab(
  "eval",
  {
    subject: "flag",
    args: %w[flag context],
    opts: true,
    returns: "value",
    raises: [],
    kind: :effect,
    meaning: "the value of a flag for a context",
    ref: nil,
    status: :decided
  }
)

vocab(
  "events",
  {
    subject: "subject",
    args: ["~subject"],
    opts: true,
    returns: "[event]",
    raises: [],
    kind: :effect,
    meaning: "events about a subject",
    ref: nil,
    status: :decided
  }
)

vocab(
  "exists?",
  {
    subject: "subject",
    args: ["subject"],
    opts: true,
    returns: "Bool",
    raises: [],
    kind: :effect,
    meaning: "whether the subject is there; never raises",
    ref: "§3.1",
    status: :stdlib
  }
)

vocab(
  "exit_status",
  {
    subject: "kind",
    args: ["kind"],
    opts: false,
    returns: "int",
    raises: [],
    kind: :pure,
    meaning: "the exit status the ledger gives a kind",
    ref: nil,
    status: :decided
  }
)

vocab(
  "expand",
  {
    subject: "subject",
    args: %w[subject by?],
    opts: true,
    returns: "value",
    raises: [],
    kind: :pure,
    meaning: "a short form made long",
    ref: nil,
    status: :decided
  }
)

vocab(
  "explain",
  {
    subject: "subject",
    args: %w[subject path?],
    opts: false,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "why a result or finding came out as it did",
    ref: nil,
    status: :decided
  }
)

vocab(
  "export",
  {
    subject: "store",
    args: %w[store target],
    opts: true,
    returns: "count",
    raises: [],
    kind: :effect,
    meaning: "write a store out to a target",
    ref: nil,
    status: :decided
  }
)

vocab(
  "extract",
  {
    subject: "source",
    args: %w[source kind?],
    opts: true,
    returns: "[part]",
    raises: [],
    kind: :pure,
    meaning: "pull named parts out of a source",
    ref: nil,
    status: :decided
  }
)

vocab(
  "eye",
  {
    subject: "n",
    args: ["n"],
    opts: false,
    returns: "matrix",
    raises: [],
    kind: :pure,
    meaning: "the identity matrix of size n",
    ref: nil,
    status: :decided
  }
)

vocab(
  "fetch",
  {
    subject: "source",
    args: %w[source version?],
    opts: true,
    returns: "local copy",
    raises: ["not_found"],
    kind: :effect,
    meaning: "bring a remote thing to local disk",
    ref: nil,
    status: :decided
  }
)

vocab(
  "file",
  {
    subject: "app",
    args: %w[app tier],
    opts: false,
    returns: "path",
    raises: [],
    kind: :pure,
    meaning: "where the config file of a tier lives",
    ref: nil,
    status: :decided
  }
)

vocab(
  "fill",
  {
    subject: "template",
    args: %w[template data],
    opts: false,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "a template with its holes filled",
    ref: nil,
    status: :decided
  }
)

vocab(
  "filter",
  {
    subject: "xs",
    args: %w[xs f],
    opts: true,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "the items where f holds",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "find",
  {
    subject: "subject",
    args: %w[subject query],
    opts: true,
    returns: "item or nil",
    raises: [],
    kind: :any,
    meaning: "the first match of a query or predicate, else nil",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "fingerprint",
  {
    subject: "cert",
    args: ["cert"],
    opts: false,
    returns: "hex",
    raises: [],
    kind: :pure,
    meaning: "a hash of the public key, for pinning",
    ref: nil,
    status: :decided
  }
)

vocab(
  "first",
  {
    subject: "xs",
    args: ["xs"],
    opts: false,
    returns: "item or nil",
    raises: [],
    kind: :pure,
    meaning: "the first item",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "fit",
  {
    subject: "model",
    args: %w[model data],
    opts: true,
    returns: "params",
    raises: [],
    kind: :pure,
    meaning: "choose parameters that match data",
    ref: nil,
    status: :decided
  }
)

vocab(
  "flat_map",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "map then flatten one level",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "flatten",
  {
    subject: "xs",
    args: ["xs"],
    opts: false,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "nested lists as one list",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "fold",
  {
    subject: "log",
    args: %w[log projection],
    opts: true,
    returns: "view",
    raises: [],
    kind: :effect,
    meaning: "keep a read model current from a log",
    ref: nil,
    status: :decided
  }
)

vocab(
  "forecast",
  {
    subject: "series",
    args: %w[series horizon],
    opts: true,
    returns: "series",
    raises: [],
    kind: :pure,
    meaning: "a series continued forward",
    ref: nil,
    status: :decided
  }
)

vocab(
  "fork",
  {
    subject: "rng",
    args: %w[rng label?],
    opts: false,
    returns: "rng",
    raises: [],
    kind: :pure,
    meaning: "an independent stream from one",
    ref: nil,
    status: :decided
  }
)

vocab(
  "fragment",
  {
    subject: "name",
    args: %w[name spec],
    opts: false,
    returns: "fragment",
    raises: [],
    kind: :pure,
    meaning: "declare a named field selection on one type; nothing runs",
    ref: nil,
    status: :decided
  }
)

vocab(
  "frames",
  {
    subject: "session",
    args: ["session"],
    opts: false,
    returns: "[frame]",
    raises: [],
    kind: :effect,
    meaning: "the frames of a paused program or a dump",
    ref: nil,
    status: :decided
  }
)

vocab(
  "freeze",
  {
    subject: "name",
    args: %w[name reason],
    opts: false,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "stop changes to an environment",
    ref: nil,
    status: :decided
  }
)

vocab(
  "fresh?",
  {
    subject: "subject",
    args: %w[subject now],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :pure,
    meaning: "whether a thing is still within its lifetime",
    ref: nil,
    status: :decided
  }
)

vocab(
  "fuse",
  {
    subject: "lists",
    args: ["lists"],
    opts: true,
    returns: "[hit]",
    raises: [],
    kind: :pure,
    meaning: "several rankings combined into one",
    ref: nil,
    status: :decided
  }
)

vocab(
  "gate",
  {
    subject: "subject",
    args: %w[subject rule],
    opts: false,
    returns: "verdict",
    raises: [],
    kind: :pure,
    meaning: "a pass or fail verdict against a rule",
    ref: nil,
    status: :decided
  }
)

vocab(
  "generate",
  {
    subject: "spec",
    args: %w[spec target?],
    opts: true,
    returns: "content",
    raises: [],
    kind: :any,
    meaning: "produce content or keys from a spec",
    ref: nil,
    status: :decided
  }
)

vocab(
  "get",
  {
    subject: "store",
    args: %w[~store key],
    opts: true,
    returns: "value or nil",
    raises: [],
    kind: :any,
    meaning: "one entry, nil when absent",
    ref: "§3.2",
    status: :stdlib
  }
)

vocab(
  "glob",
  {
    subject: "pattern",
    args: ["pattern"],
    opts: true,
    returns: "[path]",
    raises: [],
    kind: :effect,
    meaning: "paths matching a pattern, sorted",
    ref: "§3.1",
    status: :stdlib
  }
)

vocab(
  "graft",
  {
    subject: "repo",
    args: %w[repo commits],
    opts: false,
    returns: "[commit]",
    raises: [],
    kind: :effect,
    meaning: "copy commits onto the current branch",
    ref: nil,
    status: :decided
  }
)

vocab(
  "grammar",
  {
    subject: "rules",
    args: ["rules"],
    opts: false,
    returns: "grammar",
    raises: [],
    kind: :pure,
    meaning: "declare a grammar from rules",
    ref: nil,
    status: :decided
  }
)

vocab(
  "grant",
  {
    subject: "subject",
    args: %w[subject permission resource],
    opts: true,
    returns: "relation",
    raises: ["permission_denied"],
    kind: :effect,
    meaning: "let a subject do something to a resource",
    ref: nil,
    status: :decided
  }
)

vocab(
  "graph",
  {
    subject: "edges",
    args: ["edges"],
    opts: true,
    returns: "graph",
    raises: [],
    kind: :pure,
    meaning: "build or read a graph of nodes and edges",
    ref: nil,
    status: :decided
  }
)

vocab(
  "group",
  {
    subject: "subject",
    args: %w[subject keys?],
    opts: true,
    returns: "group",
    raises: [],
    kind: :any,
    meaning: "a set of things taken together",
    ref: nil,
    status: :decided
  }
)

vocab(
  "group_by",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "map",
    raises: [],
    kind: :pure,
    meaning: "items grouped under f of each",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "grow",
  {
    subject: "polygon",
    args: %w[polygon distance],
    opts: false,
    returns: "polygon",
    raises: [],
    kind: :pure,
    meaning: "a polygon grown or shrunk by a distance",
    ref: nil,
    status: :decided
  }
)

vocab(
  "guard",
  {
    subject: "handler",
    args: %w[handler check],
    opts: false,
    returns: "handler",
    raises: [],
    kind: :pure,
    meaning: "refuse what fails a check before the handler runs",
    ref: nil,
    status: :decided
  }
)

vocab(
  "has?",
  {
    subject: "store",
    args: %w[~store key],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :any,
    meaning: "whether the key is present",
    ref: "§3.2",
    status: :stdlib
  }
)

vocab(
  "hash",
  {
    subject: "data",
    args: %w[data algorithm?],
    opts: true,
    returns: "hex",
    raises: ["bad_option"],
    kind: :pure,
    meaning: "a digest in lowercase hex",
    ref: "§3.4",
    status: :stdlib
  }
)

vocab(
  "header",
  {
    subject: "message",
    args: %w[message name],
    opts: false,
    returns: "text?",
    raises: [],
    kind: :pure,
    meaning: "one header of a request or response, its name in any case",
    ref: nil,
    status: :decided
  }
)

vocab(
  "highlight",
  {
    subject: "code",
    args: %w[code language?],
    opts: false,
    returns: "spans",
    raises: [],
    kind: :pure,
    meaning: "the spans of text worth marking",
    ref: nil,
    status: :decided
  }
)

vocab(
  "history",
  {
    subject: "subject",
    args: %w[subject range?],
    opts: false,
    returns: "[record]",
    raises: [],
    kind: :effect,
    meaning: "past records of a subject, in order",
    ref: nil,
    status: :decided
  }
)

vocab(
  "hydrate",
  {
    subject: "tree",
    args: %w[tree root],
    opts: true,
    returns: "app",
    raises: [],
    kind: :effect,
    meaning: "attach behaviour to output another stage already rendered",
    ref: nil,
    status: :decided
  }
)

vocab(
  "hypothesis",
  {
    subject: "a",
    args: %w[a b kind],
    opts: false,
    returns: "record",
    raises: [],
    kind: :pure,
    meaning: "a statistical test: statistic and p-value",
    ref: nil,
    status: :decided
  }
)

vocab(
  "identity",
  {
    subject: "x",
    args: ["x"],
    opts: false,
    returns: "x",
    raises: [],
    kind: :pure,
    meaning: "the value unchanged",
    ref: nil,
    status: :decided
  }
)

vocab(
  "import",
  {
    subject: "store",
    args: %w[store entries],
    opts: true,
    returns: "count",
    raises: [],
    kind: :effect,
    meaning: "bring entries into a store",
    ref: nil,
    status: :decided
  }
)

vocab(
  "index",
  {
    subject: "store",
    args: %w[store field?],
    opts: true,
    returns: "index",
    raises: [],
    kind: :effect,
    meaning: "build or declare an index",
    ref: nil,
    status: :decided
  }
)

vocab(
  "index_of",
  {
    subject: "xs",
    args: %w[xs x],
    opts: false,
    returns: "int or nil",
    raises: [],
    kind: :pure,
    meaning: "the position of the first x",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "info",
  {
    subject: "subject",
    args: ["subject"],
    opts: true,
    returns: "record",
    raises: ["not_found"],
    kind: :effect,
    meaning: "current state of the subject as a record",
    ref: "§3.1,§3.5",
    status: :decided
  }
)

vocab(
  "initial",
  {
    subject: "state",
    args: ["state"],
    opts: false,
    returns: "decl",
    raises: [],
    kind: :pure,
    meaning: "declare the state an instance begins in",
    ref: nil,
    status: :decided
  }
)

vocab(
  "insert",
  {
    subject: "xs",
    args: %w[xs at? item],
    opts: false,
    returns: "xs",
    raises: [],
    kind: :pure,
    meaning: "xs with an item placed at a position",
    ref: nil,
    status: :decided
  }
)

vocab(
  "install",
  {
    subject: "package",
    args: %w[package dest?],
    opts: true,
    returns: "installed",
    raises: ["not_found"],
    kind: :effect,
    meaning: "put a package in place so it can run",
    ref: nil,
    status: :decided
  }
)

vocab(
  "interleave",
  {
    subject: "logs",
    args: ["logs"],
    opts: false,
    returns: "[record]",
    raises: [],
    kind: :pure,
    meaning: "several logs merged into one ordered list",
    ref: nil,
    status: :decided
  }
)

vocab(
  "intersect",
  {
    subject: "a",
    args: %w[a b],
    opts: false,
    returns: "x or nil",
    raises: [],
    kind: :pure,
    meaning: "what two values have in common",
    ref: nil,
    status: :decided
  }
)

vocab(
  "invert",
  {
    subject: "x",
    args: ["x"],
    opts: true,
    returns: "x",
    raises: [],
    kind: :pure,
    meaning: "the opposite of a value",
    ref: nil,
    status: :decided
  }
)

vocab(
  "island",
  {
    subject: "view",
    args: ["view"],
    opts: true,
    returns: "node",
    raises: [],
    kind: :pure,
    meaning: "mark a subtree that activates on its own; nothing runs",
    ref: nil,
    status: :decided
  }
)

vocab(
  "join",
  {
    subject: "xs",
    args: %w[xs sep?],
    opts: false,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "items joined into one value with a separator",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "judge",
  {
    subject: "subject",
    args: %w[subject criteria b?],
    opts: true,
    returns: "verdict",
    raises: [],
    kind: :pure,
    meaning: "a verdict from criteria",
    ref: nil,
    status: :decided
  }
)

vocab(
  "key",
  {
    subject: "parts",
    args: ["parts"],
    opts: false,
    returns: "key",
    raises: [],
    kind: :pure,
    meaning: "one canonical key built from ordered parts",
    ref: nil,
    status: :decided
  }
)

vocab(
  "keys",
  {
    subject: "m",
    args: ["m"],
    opts: true,
    returns: "[key]",
    raises: [],
    kind: :pure,
    meaning: "the keys of a map",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "kind",
  {
    subject: "node",
    args: ["node"],
    opts: false,
    returns: "name",
    raises: [],
    kind: :pure,
    meaning: "the kind or scheme a value belongs to",
    ref: nil,
    status: :decided
  }
)

vocab(
  "labels",
  {
    subject: "set",
    args: %w[set entries],
    opts: false,
    returns: "table",
    raises: ["bad_option"],
    kind: :pure,
    meaning: "display text keyed by each value of a closed set; nothing runs",
    ref: nil,
    status: :decided
  }
)

vocab(
  "lag",
  {
    subject: "consumer",
    args: %w[consumer log?],
    opts: false,
    returns: "number",
    raises: [],
    kind: :effect,
    meaning: "how far behind a consumer is",
    ref: nil,
    status: :decided
  }
)

vocab(
  "land",
  {
    subject: "change",
    args: ["change"],
    opts: true,
    returns: "record",
    raises: ["conflict"],
    kind: :effect,
    meaning: "merge a reviewed change into its base",
    ref: nil,
    status: :decided
  }
)

vocab(
  "last",
  {
    subject: "xs",
    args: ["xs"],
    opts: false,
    returns: "item or nil",
    raises: [],
    kind: :pure,
    meaning: "the last item",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "ledger",
  {
    subject: "accounts",
    args: %w[accounts? rules?],
    opts: true,
    returns: "ledger",
    raises: [],
    kind: :any,
    meaning: "a closed list or record of entries",
    ref: nil,
    status: :decided
  }
)

vocab(
  "level",
  {
    subject: "",
    args: [],
    opts: false,
    returns: "keyword",
    raises: ["bad_option"],
    kind: :effect,
    meaning: "the active log level from the environment",
    ref: "§3.5",
    status: :decided
  }
)

vocab(
  "limit",
  {
    subject: "subject",
    args: %w[subject amount?],
    opts: true,
    returns: "limit",
    raises: [],
    kind: :pure,
    meaning: "a cap on a resource or a flow",
    ref: nil,
    status: :decided
  }
)

vocab(
  "limiter",
  {
    subject: "count",
    args: %w[count duration],
    opts: false,
    returns: "limiter",
    raises: [],
    kind: :pure,
    meaning: "declare a sliding-window limiter",
    ref: nil,
    status: :decided
  }
)

vocab(
  "link",
  {
    subject: "from",
    args: %w[from to kind?],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "relate two things",
    ref: nil,
    status: :decided
  }
)

vocab(
  "lint",
  {
    subject: "subject",
    args: ["subject"],
    opts: true,
    returns: "[finding]",
    raises: [],
    kind: :pure,
    meaning: "style and quality findings",
    ref: nil,
    status: :decided
  }
)

vocab(
  "list",
  {
    subject: "store",
    args: ["~store"],
    opts: true,
    returns: "[record]",
    raises: ["not_found"],
    kind: :any,
    meaning: "every entry, all pages, sorted",
    ref: "§3.2",
    status: :stdlib
  }
)

vocab(
  "listen",
  {
    subject: "device",
    args: ["device"],
    opts: true,
    returns: "handle",
    raises: [],
    kind: :effect,
    meaning: "capture from an input device",
    ref: nil,
    status: :decided
  }
)

vocab(
  "lock",
  {
    subject: "project",
    args: ["project"],
    opts: true,
    returns: "[changed pin]",
    raises: [],
    kind: :effect,
    meaning: "write the lock of a project from its manifest",
    ref: nil,
    status: :decided
  }
)

vocab(
  "log",
  {
    subject: "repo",
    args: ["repo"],
    opts: true,
    returns: "[commit]",
    raises: [],
    kind: :effect,
    meaning: "commits from a ref backward",
    ref: nil,
    status: :decided
  }
)

vocab(
  "logarithm",
  {
    subject: "n",
    args: %w[n base?],
    opts: false,
    returns: "number",
    raises: [],
    kind: :pure,
    meaning: "the logarithm of n in a base",
    ref: nil,
    status: :decided
  }
)

vocab(
  "map",
  {
    subject: "xs",
    args: %w[xs f],
    opts: true,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "a list of f applied to each item",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "mark",
  {
    subject: "state",
    args: ["state"],
    opts: false,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "the symbol a state shows",
    ref: nil,
    status: :decided
  }
)

vocab(
  "matches?",
  {
    subject: "subject",
    args: %w[subject pattern],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :pure,
    meaning: "whether a subject matches a pattern",
    ref: nil,
    status: :decided
  }
)

vocab(
  "max_by",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "item or nil",
    raises: [],
    kind: :pure,
    meaning: "the item with the greatest f",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "measure",
  {
    subject: "subject",
    args: %w[subject metric?],
    opts: true,
    returns: "number",
    raises: [],
    kind: :any,
    meaning: "a size or a rate of a subject",
    ref: nil,
    status: :decided
  }
)

vocab(
  "merge",
  {
    subject: "a",
    args: %w[a b],
    opts: true,
    returns: "value",
    raises: ["conflict"],
    kind: :any,
    meaning: "combine b into a; one master verb for every space, gitto::merge refines it",
    ref: "§3.4",
    status: :decided
  }
)

vocab(
  "meter",
  {
    subject: "fraction",
    args: %w[fraction width],
    opts: false,
    returns: "node",
    raises: [],
    kind: :pure,
    meaning: "a fraction drawn as a bar",
    ref: nil,
    status: :decided
  }
)

vocab(
  "min_by",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "item or nil",
    raises: [],
    kind: :pure,
    meaning: "the item with the least f",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "mirror",
  {
    subject: "from",
    args: %w[from to],
    opts: true,
    returns: "report",
    raises: [],
    kind: :effect,
    meaning: "make a destination equal a source",
    ref: nil,
    status: :decided
  }
)

vocab(
  "mount",
  {
    subject: "parent",
    args: %w[parent at child],
    opts: true,
    returns: "parent",
    raises: [],
    kind: :any,
    meaning: "place a child under a parent at a named point",
    ref: nil,
    status: :decided
  }
)

vocab(
  "move",
  {
    subject: "from",
    args: %w[from to],
    opts: true,
    returns: "nil",
    raises: %w[not_found exists],
    kind: :effect,
    meaning: "move or rename atomically",
    ref: "§3.1",
    status: :stdlib
  }
)

vocab(
  "need",
  {
    subject: "store",
    args: %w[~store key],
    opts: true,
    returns: "value",
    raises: ["not_found"],
    kind: :any,
    meaning: "one entry, raising when absent",
    ref: "§3.2",
    status: :stdlib
  }
)

vocab(
  "negotiate",
  {
    subject: "client",
    args: %w[client server],
    opts: false,
    returns: "version",
    raises: [],
    kind: :pure,
    meaning: "pick the highest version both sides speak",
    ref: nil,
    status: :decided
  }
)

vocab(
  "neighbors",
  {
    subject: "graph",
    args: %w[~graph node],
    opts: false,
    returns: "[node]",
    raises: [],
    kind: :pure,
    meaning: "the nodes next to a node",
    ref: nil,
    status: :decided
  }
)

vocab(
  "next",
  {
    subject: "schedule",
    args: %w[schedule after],
    opts: false,
    returns: "instant or nil",
    raises: [],
    kind: :pure,
    meaning: "the next occurrence after a point",
    ref: nil,
    status: :decided
  }
)

vocab(
  "none?",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :pure,
    meaning: "whether f holds for no item",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "normalize",
  {
    subject: "x",
    args: %w[x form?],
    opts: true,
    returns: "x",
    raises: [],
    kind: :pure,
    meaning: "the one canonical form of a value",
    ref: nil,
    status: :decided
  }
)

vocab(
  "notes",
  {
    subject: "root",
    args: %w[root kind],
    opts: false,
    returns: "notes",
    raises: [],
    kind: :pure,
    meaning: "the notes of a scale from a root",
    ref: nil,
    status: :decided
  }
)

vocab(
  "now",
  {
    subject: "",
    args: [],
    opts: false,
    returns: "instant",
    raises: [],
    kind: :effect,
    meaning: "the current instant",
    ref: "§3.5",
    status: :stdlib
  }
)

vocab(
  "nth_root",
  {
    subject: "n",
    args: %w[n degree],
    opts: false,
    returns: "number",
    raises: [],
    kind: :pure,
    meaning: "the n-th root of a number",
    ref: nil,
    status: :decided
  }
)

vocab(
  "observe",
  {
    subject: "subject",
    args: %w[~subject value? labels?],
    opts: true,
    returns: "nil or state",
    raises: [],
    kind: :effect,
    meaning: "record or read one measurement",
    ref: nil,
    status: :decided
  }
)

vocab(
  "offset",
  {
    subject: "subject",
    args: %w[subject key],
    opts: false,
    returns: "number or nil",
    raises: [],
    kind: :pure,
    meaning: "a position relative to a reference",
    ref: nil,
    status: :decided
  }
)

vocab(
  "on",
  {
    subject: "subject",
    args: %w[subject event handler],
    opts: false,
    returns: "subject",
    raises: [],
    kind: :pure,
    meaning: "attach a handler to an event",
    ref: nil,
    status: :decided
  }
)

vocab(
  "open",
  {
    subject: "spec",
    args: ["spec"],
    opts: true,
    returns: "handle",
    raises: %w[not_found permission_denied],
    kind: :effect,
    meaning: "open or connect a store, log or session",
    ref: nil,
    status: :decided
  }
)

vocab(
  "order",
  {
    subject: "subject",
    args: ["subject"],
    opts: false,
    returns: "[x]",
    raises: [],
    kind: :pure,
    meaning: "the sequence a collection takes",
    ref: nil,
    status: :decided
  }
)

vocab(
  "outline",
  {
    subject: "tree",
    args: %w[tree span name],
    opts: false,
    returns: "[edit]",
    raises: [],
    kind: :pure,
    meaning: "edits that move a span into a new definition",
    ref: nil,
    status: :decided
  }
)

vocab(
  "pack",
  {
    subject: "items",
    args: %w[items format?],
    opts: true,
    returns: "bytes",
    raises: [],
    kind: :pure,
    meaning: "bundle items into one value",
    ref: nil,
    status: :decided
  }
)

vocab(
  "parent",
  {
    subject: "node",
    args: %w[~tree node],
    opts: false,
    returns: "node or nil",
    raises: [],
    kind: :pure,
    meaning: "the node that holds a node, nil at the root",
    ref: nil,
    status: :decided
  }
)

vocab(
  "parse",
  {
    subject: "text",
    args: %w[text format?],
    opts: true,
    returns: "value",
    raises: ["parse_error"],
    kind: :pure,
    meaning: "text to a value",
    ref: "§3.4",
    status: :stdlib
  }
)

vocab(
  "partition",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "[list]",
    raises: [],
    kind: :pure,
    meaning: "two lists: where f holds and where it does not",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "patch",
  {
    subject: "base",
    args: %w[base delta],
    opts: true,
    returns: "value",
    raises: ["conflict"],
    kind: :any,
    meaning: "a value changed by a set of edits",
    ref: nil,
    status: :decided
  }
)

vocab(
  "path",
  {
    subject: "graph",
    args: %w[graph from to],
    opts: true,
    returns: "[node] or nil",
    raises: [],
    kind: :pure,
    meaning: "the cheapest route between two nodes",
    ref: nil,
    status: :decided
  }
)

vocab(
  "pause",
  {
    subject: "handle",
    args: ["handle"],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "hold a run without ending it",
    ref: nil,
    status: :decided
  }
)

vocab(
  "peek",
  {
    subject: "queue",
    args: %w[queue n?],
    opts: false,
    returns: "item or nil",
    raises: [],
    kind: :effect,
    meaning: "look at the next item without taking it",
    ref: nil,
    status: :decided
  }
)

vocab(
  "period",
  {
    subject: "a",
    args: %w[a modulus],
    opts: false,
    returns: "int",
    raises: [],
    kind: :pure,
    meaning: "the smallest power of a equal to one",
    ref: nil,
    status: :decided
  }
)

vocab(
  "phrase",
  {
    subject: "items",
    args: %w[locale items],
    opts: false,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "items joined as a phrase in a locale",
    ref: nil,
    status: :decided
  }
)

vocab(
  "pick",
  {
    subject: "source",
    args: %w[source rule],
    opts: true,
    returns: "item or nil",
    raises: [],
    kind: :pure,
    meaning: "choose one item by a rule",
    ref: nil,
    status: :decided
  }
)

vocab(
  "pin",
  {
    subject: "subject",
    args: %w[subject to?],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "fix a subject to one exact version",
    ref: nil,
    status: :decided
  }
)

vocab(
  "pipe",
  {
    subject: "stages",
    args: ["stages"],
    opts: true,
    returns: "result",
    raises: ["command_failed"],
    kind: :effect,
    meaning: "run stages joined stdout to stdin",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "places",
  {
    subject: "decimal",
    args: ["decimal"],
    opts: false,
    returns: "int",
    raises: [],
    kind: :pure,
    meaning: "digits after the decimal point",
    ref: nil,
    status: :decided
  }
)

vocab(
  "plain",
  {
    subject: "status",
    args: %w[status body],
    opts: false,
    returns: "response",
    raises: [],
    kind: :pure,
    meaning: "a plain-text response",
    ref: nil,
    status: :decided
  }
)

vocab(
  "plan",
  {
    subject: "subject",
    args: %w[subject target?],
    opts: true,
    returns: "[action]",
    raises: ["as the verb"],
    kind: :pure,
    meaning: "what the verb would do, as data, changing nothing",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "pledge",
  {
    subject: "value",
    args: %w[value nonce],
    opts: false,
    returns: "hex",
    raises: [],
    kind: :pure,
    meaning: "a hiding binding commitment to a value",
    ref: nil,
    status: :decided
  }
)

vocab(
  "policy",
  {
    subject: "name",
    args: %w[name? rules?],
    opts: true,
    returns: "policy",
    raises: [],
    kind: :pure,
    meaning: "declare rules that decide",
    ref: nil,
    status: :decided
  }
)

vocab(
  "pool",
  {
    subject: "size",
    args: %w[size f],
    opts: true,
    returns: "pool",
    raises: [],
    kind: :effect,
    meaning: "a fixed set of workers that share requests",
    ref: nil,
    status: :decided
  }
)

vocab(
  "prefix",
  {
    subject: "prompt",
    args: %w[prompt mark],
    opts: false,
    returns: "prompt",
    raises: [],
    kind: :pure,
    meaning: "mark the stable prefix a provider may cache",
    ref: nil,
    status: :decided
  }
)

vocab(
  "principal",
  {
    subject: "cert",
    args: ["cert"],
    opts: false,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "the workload identity a certificate names",
    ref: nil,
    status: :decided
  }
)

vocab(
  "probe",
  {
    subject: "target",
    args: %w[target check?],
    opts: true,
    returns: "record",
    raises: [],
    kind: :effect,
    meaning: "test whether a target is healthy",
    ref: nil,
    status: :decided
  }
)

vocab(
  "profile",
  {
    subject: "subject",
    args: ["subject"],
    opts: true,
    returns: "profile",
    raises: [],
    kind: :any,
    meaning: "where time or resource goes",
    ref: nil,
    status: :decided
  }
)

vocab(
  "project",
  {
    subject: "subject",
    args: %w[subject onto],
    opts: false,
    returns: "projection",
    raises: [],
    kind: :pure,
    meaning: "a subject seen in another space",
    ref: nil,
    status: :decided
  }
)

vocab(
  "promote",
  {
    subject: "subject",
    args: %w[subject to?],
    opts: true,
    returns: "subject",
    raises: [],
    kind: :effect,
    meaning: "move a thing to the next stage",
    ref: nil,
    status: :decided
  }
)

vocab(
  "protect",
  {
    subject: "breaker",
    args: %w[breaker f],
    opts: true,
    returns: "value",
    raises: ["breaker_open"],
    kind: :effect,
    meaning: "run f through a breaker; open breaker raises at once",
    ref: nil,
    status: :decided
  }
)

vocab(
  "publish",
  {
    subject: "artifact",
    args: %w[artifact target],
    opts: true,
    returns: "record",
    raises: [],
    kind: :effect,
    meaning: "send an artifact or message to a target",
    ref: nil,
    status: :decided
  }
)

vocab(
  "purge",
  {
    subject: "store",
    args: %w[store filter?],
    opts: true,
    returns: "count",
    raises: [],
    kind: :effect,
    meaning: "remove entries matching a filter",
    ref: nil,
    status: :decided
  }
)

vocab(
  "push",
  {
    subject: "subject",
    args: %w[subject item?],
    opts: true,
    returns: "nil or digest",
    raises: [],
    kind: :effect,
    meaning: "send an item to a remote or queue",
    ref: nil,
    status: :decided
  }
)

vocab(
  "put",
  {
    subject: "store",
    args: %w[~store key value],
    opts: true,
    returns: "value",
    raises: ["permission_denied"],
    kind: :any,
    meaning: "create or replace an entry",
    ref: "§3.2",
    status: :stdlib
  }
)

vocab(
  "query",
  {
    subject: "store",
    args: %w[store question params?],
    opts: true,
    returns: "[record]",
    raises: ["query_error"],
    kind: :any,
    meaning: "ask the store in its own language",
    ref: "§3.2",
    status: :stdlib
  }
)

vocab(
  "quota",
  {
    subject: "limiter",
    args: %w[limiter key],
    opts: false,
    returns: "record",
    raises: [],
    kind: :effect,
    meaning: "remaining, limit and reset time of a key under a limiter",
    ref: nil,
    status: :decided
  }
)

vocab(
  "range",
  {
    subject: "from",
    args: %w[from to step?],
    opts: true,
    returns: "range",
    raises: [],
    kind: :pure,
    meaning: "numbers or keys between two ends",
    ref: nil,
    status: :decided
  }
)

vocab(
  "rank",
  {
    subject: "items",
    args: %w[items query?],
    opts: true,
    returns: "ranked",
    raises: [],
    kind: :pure,
    meaning: "items ordered by a score",
    ref: nil,
    status: :decided
  }
)

vocab(
  "read",
  {
    subject: "source",
    args: ["source"],
    opts: true,
    returns: "content",
    raises: %w[not_found permission_denied parse_error],
    kind: :effect,
    meaning: "whole content of a source",
    ref: "§3.1",
    status: :stdlib
  }
)

vocab(
  "ready?",
  {
    subject: "subject",
    args: ["subject"],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :any,
    meaning: "whether a thing is ready to use",
    ref: nil,
    status: :decided
  }
)

vocab(
  "receive",
  {
    subject: "source",
    args: %w[source subject?],
    opts: true,
    returns: "message or nil",
    raises: [],
    kind: :effect,
    meaning: "take the next message from a source",
    ref: nil,
    status: :decided
  }
)

vocab(
  "record",
  {
    subject: "subject",
    args: %w[subject entry],
    opts: true,
    returns: "receipt",
    raises: [],
    kind: :effect,
    meaning: "append an outcome to a history or ledger",
    ref: nil,
    status: :decided
  }
)

vocab(
  "recover",
  {
    subject: "handler",
    args: ["handler"],
    opts: false,
    returns: "handler",
    raises: [],
    kind: :pure,
    meaning: "turn what a handler raises into an answer",
    ref: nil,
    status: :decided
  }
)

vocab(
  "redact",
  {
    subject: "doc",
    args: %w[doc rules],
    opts: false,
    returns: "doc",
    raises: [],
    kind: :pure,
    meaning: "a value with sensitive parts hidden",
    ref: nil,
    status: :decided
  }
)

vocab(
  "redirect",
  {
    subject: "status",
    args: %w[status location],
    opts: false,
    returns: "response",
    raises: [],
    kind: :pure,
    meaning: "an answer that sends the client to another location",
    ref: nil,
    status: :decided
  }
)

vocab(
  "reduce",
  {
    subject: "xs",
    args: %w[xs f init?],
    opts: false,
    returns: "value",
    raises: [],
    kind: :pure,
    meaning: "fold the items into one value",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "refresh",
  {
    subject: "subject",
    args: %w[subject key? f?],
    opts: true,
    returns: "value",
    raises: [],
    kind: :effect,
    meaning: "replace a held value with a fresh one",
    ref: nil,
    status: :decided
  }
)

vocab(
  "register",
  {
    subject: "subject",
    args: %w[subject target?],
    opts: true,
    returns: "registration",
    raises: [],
    kind: :effect,
    meaning: "enter a name or device in a registry",
    ref: nil,
    status: :decided
  }
)

vocab(
  "reject",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "the items where f does not hold",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "remember",
  {
    subject: "cache",
    args: %w[cache key f],
    opts: true,
    returns: "value",
    raises: [],
    kind: :effect,
    meaning: "the cached value, computed by f when missing",
    ref: nil,
    status: :decided
  }
)

vocab(
  "remove",
  {
    subject: "xs",
    args: %w[xs item],
    opts: false,
    returns: "xs",
    raises: [],
    kind: :pure,
    meaning: "xs without an item",
    ref: nil,
    status: :decided
  }
)

vocab(
  "render",
  {
    subject: "value",
    args: %w[value format?],
    opts: true,
    returns: "text",
    raises: ["render_error"],
    kind: :pure,
    meaning: "a value to canonical stable text",
    ref: "§3.4",
    status: :stdlib
  }
)

vocab(
  "renew",
  {
    subject: "subject",
    args: %w[subject by?],
    opts: true,
    returns: "subject",
    raises: [],
    kind: :effect,
    meaning: "lengthen the life of a lease, session or cert",
    ref: nil,
    status: :decided
  }
)

vocab(
  "replay",
  {
    subject: "log",
    args: %w[log definition?],
    opts: true,
    returns: "state",
    raises: [],
    kind: :any,
    meaning: "re-run recorded events to a state",
    ref: nil,
    status: :decided
  }
)

vocab(
  "request",
  {
    subject: "target",
    args: %w[target input],
    opts: true,
    returns: "reply",
    raises: [],
    kind: :effect,
    meaning: "ask a service for something and wait",
    ref: nil,
    status: :decided
  }
)

vocab(
  "reserve",
  {
    subject: "lines",
    args: %w[lines options],
    opts: false,
    returns: "plan",
    raises: [],
    kind: :pure,
    meaning: "layered purchase commitments for steady use",
    ref: nil,
    status: :decided
  }
)

vocab(
  "reset",
  {
    subject: "subject",
    args: ["subject"],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "return a thing to its initial state",
    ref: nil,
    status: :decided
  }
)

vocab(
  "resize",
  {
    subject: "workload",
    args: %w[workload n],
    opts: true,
    returns: "workload",
    raises: [],
    kind: :effect,
    meaning: "set the instance count or the capacity",
    ref: nil,
    status: :decided
  }
)

vocab(
  "resolve",
  {
    subject: "ref",
    args: %w[ref context?],
    opts: true,
    returns: "value",
    raises: [],
    kind: :any,
    meaning: "turn a reference into what it names",
    ref: nil,
    status: :decided
  }
)

vocab(
  "rest",
  {
    subject: "xs",
    args: ["xs"],
    opts: false,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "all but the first item",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "restart",
  {
    subject: "unit",
    args: ["unit"],
    opts: true,
    returns: "nil",
    raises: %w[not_found command_failed],
    kind: :effect,
    meaning: "stop then start a service",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "restore",
  {
    subject: "source",
    args: %w[source to? version?],
    opts: true,
    returns: "manifest",
    raises: [],
    kind: :effect,
    meaning: "bring back a saved state",
    ref: nil,
    status: :decided
  }
)

vocab(
  "resume",
  {
    subject: "handle",
    args: ["handle"],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "continue a paused run",
    ref: nil,
    status: :decided
  }
)

vocab(
  "retain",
  {
    subject: "subject",
    args: %w[subject key?],
    opts: true,
    returns: "nil or policy",
    raises: [],
    kind: :effect,
    meaning: "set how long things are kept",
    ref: nil,
    status: :decided
  }
)

vocab(
  "retry",
  {
    subject: "f",
    args: %w[f policy],
    opts: false,
    returns: "value",
    raises: ["last error"],
    kind: :effect,
    meaning: "call f again under a policy while it raises a retryable kind",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "reverse",
  {
    subject: "x",
    args: ["x"],
    opts: false,
    returns: "x",
    raises: [],
    kind: :pure,
    meaning: "the same in the opposite order",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "revoke",
  {
    subject: "subject",
    args: %w[subject reason?],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "withdraw a grant, lease or certificate",
    ref: nil,
    status: :decided
  }
)

vocab(
  "rollback",
  {
    subject: "subject",
    args: %w[subject to?],
    opts: true,
    returns: "outcome",
    raises: [],
    kind: :effect,
    meaning: "return to an earlier state",
    ref: nil,
    status: :decided
  }
)

vocab(
  "root",
  {
    subject: "tree",
    args: ["tree"],
    opts: false,
    returns: "node",
    raises: [],
    kind: :pure,
    meaning: "the top node of a tree",
    ref: nil,
    status: :decided
  }
)

vocab(
  "rotate",
  {
    subject: "secret",
    args: %w[secret policy?],
    opts: true,
    returns: "secret",
    raises: [],
    kind: :effect,
    meaning: "replace a credential or log segment with a fresh one",
    ref: nil,
    status: :decided
  }
)

vocab(
  "round",
  {
    subject: "n",
    args: %w[n unit?],
    opts: true,
    returns: "number",
    raises: [],
    kind: :pure,
    meaning: "a value to the nearest whole unit",
    ref: nil,
    status: :decided
  }
)

vocab(
  "route",
  {
    subject: "subject",
    args: %w[subject rules],
    opts: false,
    returns: "[target]",
    raises: [],
    kind: :pure,
    meaning: "choose targets for a subject by rules",
    ref: nil,
    status: :decided
  }
)

vocab(
  "router",
  {
    subject: "routes",
    args: ["routes"],
    opts: true,
    returns: "app",
    raises: [],
    kind: :decl,
    meaning: "compose routes into one app, refusing each overlap alone",
    ref: nil,
    status: :decided
  }
)

vocab(
  "rule",
  {
    subject: "name",
    args: %w[name match body?],
    opts: true,
    returns: "rule",
    raises: [],
    kind: :pure,
    meaning: "declare one rule",
    ref: nil,
    status: :decided
  }
)

vocab(
  "run",
  {
    subject: "subject",
    args: %w[subject input?],
    opts: true,
    returns: "result",
    raises: %w[command_not_found command_failed timeout],
    kind: :effect,
    meaning: "run to completion and return the result",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "sample",
  {
    subject: "dist",
    args: %w[dist rng? n?],
    opts: false,
    returns: "record",
    raises: [],
    kind: :pure,
    meaning: "draws from a distribution or a source",
    ref: nil,
    status: :decided
  }
)

vocab(
  "save",
  {
    subject: "subject",
    args: %w[subject path],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "write a held state to storage",
    ref: nil,
    status: :decided
  }
)

vocab(
  "say",
  {
    subject: "line",
    args: ["line"],
    opts: false,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "a line of program output on stdout",
    ref: "§3.5",
    status: :stdlib
  }
)

vocab(
  "scale",
  {
    subject: "subject",
    args: %w[subject factor],
    opts: true,
    returns: "x",
    raises: [],
    kind: :pure,
    meaning: "a value multiplied by a plain factor",
    ref: nil,
    status: :decided
  }
)

vocab(
  "scan",
  {
    subject: "subject",
    args: %w[subject rules?],
    opts: true,
    returns: "[finding]",
    raises: [],
    kind: :effect,
    meaning: "findings from looking over a subject",
    ref: nil,
    status: :decided
  }
)

vocab(
  "schedule",
  {
    subject: "spec",
    args: %w[spec target?],
    opts: true,
    returns: "schedule",
    raises: [],
    kind: :any,
    meaning: "declare or compute when things happen",
    ref: nil,
    status: :decided
  }
)

vocab(
  "schema",
  {
    subject: "subject",
    args: ["subject"],
    opts: false,
    returns: "schema",
    raises: [],
    kind: :pure,
    meaning: "the shape a subject has or implies",
    ref: nil,
    status: :decided
  }
)

vocab(
  "scope",
  {
    subject: "f",
    args: ["f"],
    opts: false,
    returns: "value",
    raises: [],
    kind: :effect,
    meaning: "a scope where every child ends before it returns",
    ref: nil,
    status: :decided
  }
)

vocab(
  "score",
  {
    subject: "output",
    args: %w[output rubric?],
    opts: true,
    returns: "number",
    raises: [],
    kind: :pure,
    meaning: "a number saying how good a result is",
    ref: nil,
    status: :decided
  }
)

vocab(
  "seal",
  {
    subject: "subject",
    args: %w[subject key?],
    opts: true,
    returns: "envelope",
    raises: [],
    kind: :effect,
    meaning: "close a thing so later change is refused or unreadable",
    ref: nil,
    status: :decided
  }
)

vocab(
  "search",
  {
    subject: "index",
    args: %w[index query],
    opts: true,
    returns: "[hit]",
    raises: [],
    kind: :effect,
    meaning: "ranked hits for a query",
    ref: nil,
    status: :decided
  }
)

vocab(
  "segment",
  {
    subject: "source",
    args: ["source"],
    opts: true,
    returns: "spans",
    raises: [],
    kind: :pure,
    meaning: "a source cut into spans",
    ref: nil,
    status: :decided
  }
)

vocab(
  "select",
  {
    subject: "x",
    args: %w[x keys],
    opts: false,
    returns: "x",
    raises: [],
    kind: :pure,
    meaning: "only the listed parts of a value",
    ref: nil,
    status: :decided
  }
)

vocab(
  "send",
  {
    subject: "target",
    args: %w[target message],
    opts: true,
    returns: "receipt",
    raises: [],
    kind: :effect,
    meaning: "deliver a message or event to a target",
    ref: nil,
    status: :decided
  }
)

vocab(
  "serve",
  {
    subject: "address",
    args: %w[address handler],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "answer requests at an address",
    ref: nil,
    status: :decided
  }
)

vocab(
  "settle",
  {
    subject: "store",
    args: %w[store change outcome],
    opts: false,
    returns: "state",
    raises: ["conflict"],
    kind: :effect,
    meaning: "end a pending change as kept or rolled back",
    ref: nil,
    status: :decided
  }
)

vocab(
  "shape",
  {
    subject: "fields",
    args: ["fields"],
    opts: false,
    returns: "shape",
    raises: [],
    kind: :pure,
    meaning: "the shape of a record with named typed fields",
    ref: nil,
    status: :decided
  }
)

vocab(
  "shield",
  {
    subject: "key",
    args: %w[key wrapping_key],
    opts: false,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "encrypt one key under another key",
    ref: nil,
    status: :decided
  }
)

vocab(
  "shift",
  {
    subject: "shape",
    args: %w[shape by],
    opts: false,
    returns: "shape",
    raises: [],
    kind: :pure,
    meaning: "a shape moved by a vector",
    ref: nil,
    status: :decided
  }
)

vocab(
  "sign",
  {
    subject: "data",
    args: %w[data secret?],
    opts: true,
    returns: "signature",
    raises: ["bad_key"],
    kind: :pure,
    meaning: "a signature over data",
    ref: "§3.4",
    status: :stdlib
  }
)

vocab(
  "signal",
  {
    subject: "target",
    args: %w[target event payload?],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "deliver an event to a running thing",
    ref: nil,
    status: :decided
  }
)

vocab(
  "signum",
  {
    subject: "n",
    args: ["n"],
    opts: false,
    returns: "-1, 0 or 1",
    raises: [],
    kind: :pure,
    meaning: "the sign of a number",
    ref: nil,
    status: :decided
  }
)

vocab(
  "simulate",
  {
    subject: "world",
    args: %w[world ticks],
    opts: true,
    returns: "world",
    raises: [],
    kind: :effect,
    meaning: "advance a world a number of ticks",
    ref: nil,
    status: :decided
  }
)

vocab(
  "since",
  {
    subject: "instant",
    args: ["instant"],
    opts: false,
    returns: "duration",
    raises: [],
    kind: :effect,
    meaning: "duration from an instant to now",
    ref: "§3.5",
    status: :stdlib
  }
)

vocab(
  "size",
  {
    subject: "xs",
    args: ["xs"],
    opts: false,
    returns: "int",
    raises: [],
    kind: :pure,
    meaning: "how many items or keys",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "sleep",
  {
    subject: "duration",
    args: ["duration"],
    opts: false,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "pause for a duration",
    ref: "§3.5",
    status: :stdlib
  }
)

vocab(
  "slice",
  {
    subject: "store",
    args: %w[store key from to],
    opts: false,
    returns: "bytes",
    raises: [],
    kind: :effect,
    meaning: "read a byte range of an object",
    ref: nil,
    status: :decided
  }
)

vocab(
  "snapshot",
  {
    subject: "subject",
    args: ["subject"],
    opts: true,
    returns: "snapshot",
    raises: [],
    kind: :effect,
    meaning: "a frozen copy of a state",
    ref: nil,
    status: :decided
  }
)

vocab(
  "sort",
  {
    subject: "xs",
    args: ["xs"],
    opts: true,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "the items in order",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "sort_by",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "the items ordered by f of each",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "spawn",
  {
    subject: "subject",
    args: %w[subject input?],
    opts: true,
    returns: "handle",
    raises: ["command_not_found"],
    kind: :effect,
    meaning: "start without waiting; return a handle",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "split",
  {
    subject: "text",
    args: %w[text pattern],
    opts: true,
    returns: "[text]",
    raises: [],
    kind: :pure,
    meaning: "cut text at each match",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "stack",
  {
    subject: "items",
    args: %w[items axis?],
    opts: false,
    returns: "combined",
    raises: [],
    kind: :pure,
    meaning: "several items layered or joined as one",
    ref: nil,
    status: :decided
  }
)

vocab(
  "stale?",
  {
    subject: "subject",
    args: %w[subject policy?],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :pure,
    meaning: "whether a thing is older than allowed",
    ref: nil,
    status: :decided
  }
)

vocab(
  "start",
  {
    subject: "subject",
    args: %w[subject input?],
    opts: true,
    returns: "handle or nil",
    raises: %w[not_found command_failed],
    kind: :effect,
    meaning: "start a service, run or session",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "status",
  {
    subject: "subject",
    args: ["subject"],
    opts: false,
    returns: "record",
    raises: [],
    kind: :effect,
    meaning: "the summary state of a subject",
    ref: nil,
    status: :decided
  }
)

vocab(
  "stop",
  {
    subject: "handle",
    args: ["handle"],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "end it: grace period, then kill",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "stream",
  {
    subject: "source",
    args: %w[source input? f],
    opts: true,
    returns: "result",
    raises: ["as run"],
    kind: :stream,
    meaning: "call f per item as it arrives",
    ref: "§3.3,§2.6",
    status: :stdlib
  }
)

vocab(
  "subscribe",
  {
    subject: "bus",
    args: %w[bus subject f],
    opts: true,
    returns: "subscription",
    raises: [],
    kind: :effect,
    meaning: "call f for each message on a subject",
    ref: nil,
    status: :decided
  }
)

vocab(
  "succeeds?",
  {
    subject: "command",
    args: %w[command args?],
    opts: true,
    returns: "Bool",
    raises: ["command_not_found"],
    kind: :effect,
    meaning: "whether the command exits with an ok status",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "sum",
  {
    subject: "xs",
    args: ["xs"],
    opts: false,
    returns: "number",
    raises: [],
    kind: :pure,
    meaning: "the total of the numbers",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "sync",
  {
    subject: "from",
    args: %w[from to?],
    opts: true,
    returns: "report",
    raises: [],
    kind: :effect,
    meaning: "make two places agree",
    ref: nil,
    status: :decided
  }
)

vocab(
  "table",
  {
    subject: "rows",
    args: %w[rows opts],
    opts: true,
    returns: "node",
    raises: [],
    kind: :pure,
    meaning: "rows laid out as aligned columns",
    ref: nil,
    status: :decided
  }
)

vocab(
  "tag",
  {
    subject: "subject",
    args: %w[subject name],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "attach a name or label to a subject",
    ref: nil,
    status: :decided
  }
)

vocab(
  "take",
  {
    subject: "xs",
    args: %w[xs n],
    opts: false,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "the first n items",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "take_while",
  {
    subject: "xs",
    args: %w[xs f],
    opts: false,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "the leading items where f holds",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "tally",
  {
    subject: "xs",
    args: ["xs"],
    opts: false,
    returns: "map",
    raises: [],
    kind: :pure,
    meaning: "a count of each distinct item",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "tape",
  {
    subject: "f",
    args: ["f"],
    opts: true,
    returns: "trace",
    raises: [],
    kind: :effect,
    meaning: "run f and keep the host reads needed to replay it",
    ref: nil,
    status: :decided
  }
)

vocab(
  "team",
  {
    subject: "name",
    args: ["name"],
    opts: false,
    returns: "group",
    raises: [],
    kind: :effect,
    meaning: "name a set of processes addressed together",
    ref: nil,
    status: :decided
  }
)

vocab(
  "terminal",
  {
    subject: "board",
    args: %w[board name],
    opts: false,
    returns: "pin",
    raises: [],
    kind: :pure,
    meaning: "declare a hardware pin",
    ref: nil,
    status: :decided
  }
)

vocab(
  "test",
  {
    subject: "project",
    args: %w[project suite?],
    opts: true,
    returns: "report",
    raises: [],
    kind: :effect,
    meaning: "run tests and return a report",
    ref: nil,
    status: :decided
  }
)

vocab(
  "text",
  {
    subject: "node",
    args: ["node"],
    opts: false,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "the text under a node",
    ref: nil,
    status: :decided
  }
)

vocab(
  "throttle",
  {
    subject: "handler",
    args: %w[handler bucket],
    opts: false,
    returns: "handler",
    raises: [],
    kind: :effect,
    meaning: "answer 429 past a bucket",
    ref: nil,
    status: :decided
  }
)

vocab(
  "tick",
  {
    subject: "clock",
    args: %w[clock event?],
    opts: false,
    returns: "clock",
    raises: [],
    kind: :pure,
    meaning: "advance a clock by one step",
    ref: nil,
    status: :decided
  }
)

vocab(
  "timer",
  {
    subject: "instant",
    args: %w[instant f],
    opts: true,
    returns: "timer",
    raises: [],
    kind: :effect,
    meaning: "call f once at an instant",
    ref: nil,
    status: :decided
  }
)

vocab(
  "top",
  {
    subject: "xs",
    args: %w[xs n? by?],
    opts: true,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "the n greatest items",
    ref: nil,
    status: :decided
  }
)

vocab(
  "trace",
  {
    subject: "subject",
    args: ["subject"],
    opts: true,
    returns: "trace",
    raises: [],
    kind: :effect,
    meaning: "the recorded path of a run",
    ref: nil,
    status: :decided
  }
)

vocab(
  "train",
  {
    subject: "reviews",
    args: ["reviews"],
    opts: false,
    returns: "[review]",
    raises: [],
    kind: :pure,
    meaning: "reviews that depend on each other, in merge order",
    ref: nil,
    status: :decided
  }
)

vocab(
  "translate",
  {
    subject: "key",
    args: %w[key locale args?],
    opts: true,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "the message for a key in a locale",
    ref: nil,
    status: :decided
  }
)

vocab(
  "tree",
  {
    subject: "value",
    args: %w[value kids?],
    opts: false,
    returns: "tree",
    raises: [],
    kind: :pure,
    meaning: "a rooted tree of values",
    ref: nil,
    status: :decided
  }
)

vocab(
  "triage",
  {
    subject: "alert",
    args: %w[alert context?],
    opts: false,
    returns: "verdict",
    raises: [],
    kind: :pure,
    meaning: "sort items by urgency",
    ref: nil,
    status: :decided
  }
)

vocab(
  "trim",
  {
    subject: "text",
    args: ["text"],
    opts: true,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "drop space from both ends",
    ref: nil,
    status: :decided
  }
)

vocab(
  "truncate",
  {
    subject: "subject",
    args: %w[subject limit],
    opts: true,
    returns: "x or count",
    raises: [],
    kind: :any,
    meaning: "cut to a limit",
    ref: nil,
    status: :decided
  }
)

vocab(
  "turn",
  {
    subject: "shape",
    args: %w[shape angle about?],
    opts: false,
    returns: "shape",
    raises: [],
    kind: :pure,
    meaning: "a shape or list turned by an angle or n places",
    ref: nil,
    status: :decided
  }
)

vocab(
  "union",
  {
    subject: "a",
    args: %w[a b],
    opts: true,
    returns: "x",
    raises: [],
    kind: :pure,
    meaning: "everything in either",
    ref: nil,
    status: :decided
  }
)

vocab(
  "unique",
  {
    subject: "xs",
    args: ["xs"],
    opts: false,
    returns: "list",
    raises: [],
    kind: :pure,
    meaning: "the items with repeats dropped",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "unload",
  {
    subject: "queue",
    args: ["queue"],
    opts: false,
    returns: "list",
    raises: [],
    kind: :effect,
    meaning: "take every item in pop order",
    ref: nil,
    status: :decided
  }
)

vocab(
  "unpack",
  {
    subject: "archive",
    args: %w[archive to?],
    opts: true,
    returns: "[entry]",
    raises: ["decode_error"],
    kind: :effect,
    meaning: "take entries out of an archive",
    ref: nil,
    status: :decided
  }
)

vocab(
  "unpack_to",
  {
    subject: "archive",
    args: %w[archive to],
    opts: true,
    returns: "[path]",
    raises: [],
    kind: :effect,
    meaning: "write an archive under a directory; traversal refused",
    ref: nil,
    status: :decided
  }
)

vocab(
  "unproject",
  {
    subject: "point",
    args: %w[subject point],
    opts: false,
    returns: "point",
    raises: [],
    kind: :pure,
    meaning: "a projected point back in its source space",
    ref: nil,
    status: :decided
  }
)

vocab(
  "unseal",
  {
    subject: "envelope",
    args: %w[envelope key],
    opts: true,
    returns: "bytes",
    raises: ["tampered"],
    kind: :pure,
    meaning: "decrypt and check an envelope",
    ref: nil,
    status: :decided
  }
)

vocab(
  "until",
  {
    subject: "instant",
    args: ["instant"],
    opts: false,
    returns: "duration",
    raises: [],
    kind: :effect,
    meaning: "duration from now to an instant",
    ref: "§3.5",
    status: :stdlib
  }
)

vocab(
  "unzip",
  {
    subject: "pairs",
    args: ["pairs"],
    opts: false,
    returns: "[list]",
    raises: [],
    kind: :pure,
    meaning: "a list of pairs split into two lists",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "update",
  {
    subject: "store",
    args: %w[~store key f],
    opts: true,
    returns: "value",
    raises: %w[not_found conflict],
    kind: :any,
    meaning: "replace an entry with f of the old value",
    ref: "§3.2",
    status: :stdlib
  }
)

vocab(
  "upgrade",
  {
    subject: "subject",
    args: %w[subject names?],
    opts: true,
    returns: "[change]",
    raises: [],
    kind: :effect,
    meaning: "move to a newer allowed version",
    ref: nil,
    status: :decided
  }
)

vocab(
  "validate",
  {
    subject: "value",
    args: %w[value schema],
    opts: true,
    returns: "value",
    raises: ["bad_option"],
    kind: :pure,
    meaning: "the value if valid, else the problems",
    ref: nil,
    status: :decided
  }
)

vocab(
  "values",
  {
    subject: "m",
    args: ["m"],
    opts: false,
    returns: "[value]",
    raises: [],
    kind: :pure,
    meaning: "the values of a map",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "variance",
  {
    subject: "xs",
    args: ["xs"],
    opts: true,
    returns: "number",
    raises: [],
    kind: :pure,
    meaning: "how spread out numbers are",
    ref: nil,
    status: :decided
  }
)

vocab(
  "verify",
  {
    subject: "subject",
    args: %w[subject policy?],
    opts: true,
    returns: "verdict",
    raises: ["tampered"],
    kind: :any,
    meaning: "check integrity against a record or policy; raises tampered on a bad verdict, verify? is the predicate pair",
    ref: nil,
    status: :decided
  }
)

vocab(
  "verify?",
  {
    subject: "data",
    args: %w[data signature? key?],
    opts: false,
    returns: "Bool",
    raises: [],
    kind: :pure,
    meaning: "whether a signature or proof holds",
    ref: "§3.4",
    status: :stdlib
  }
)

vocab(
  "version",
  {
    subject: "subject",
    args: ["subject"],
    opts: false,
    returns: "version",
    raises: [],
    kind: :pure,
    meaning: "the version of a subject",
    ref: nil,
    status: :decided
  }
)

vocab(
  "versions",
  {
    subject: "function",
    args: ["function"],
    opts: false,
    returns: "[version]",
    raises: [],
    kind: :effect,
    meaning: "published versions of a function",
    ref: nil,
    status: :decided
  }
)

vocab(
  "volatile",
  {
    subject: "f",
    args: ["f"],
    opts: false,
    returns: "nil",
    raises: ["type"],
    kind: :decl,
    meaning: "f and every caller run on each call, never answered from the call memo",
    ref: nil,
    status: :stdlib
  }
)

vocab(
  "wait",
  {
    subject: "handle",
    args: %w[handle until?],
    opts: true,
    returns: "result",
    raises: ["timeout"],
    kind: :effect,
    meaning: "wait for a handle to finish",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "waive",
  {
    subject: "subject",
    args: %w[subject reason until?],
    opts: false,
    returns: "waiver",
    raises: [],
    kind: :pure,
    meaning: "a recorded exception to a rule",
    ref: nil,
    status: :decided
  }
)

vocab(
  "walk",
  {
    subject: "root",
    args: ["root"],
    opts: true,
    returns: "[node]",
    raises: ["not_found"],
    kind: :any,
    meaning: "every node under a root, in a fixed order",
    ref: "§3.1",
    status: :stdlib
  }
)

vocab(
  "warn",
  {
    subject: "message",
    args: %w[message fields?],
    opts: false,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "a structured log line at warn level",
    ref: "§3.5",
    status: :stdlib
  }
)

vocab(
  "watch",
  {
    subject: "store",
    args: %w[store f],
    opts: true,
    returns: "nil",
    raises: ["not_found"],
    kind: :stream,
    meaning: "call f per change until it returns stop",
    ref: "§3.2",
    status: :stdlib
  }
)

vocab(
  "waveform",
  {
    subject: "kind",
    args: %w[kind params],
    opts: false,
    returns: "signal",
    raises: [],
    kind: :pure,
    meaning: "declare a level, pulse train or PWM wave",
    ref: nil,
    status: :decided
  }
)

vocab(
  "weigh",
  {
    subject: "upstreams",
    args: %w[upstreams weights],
    opts: false,
    returns: "rule",
    raises: [],
    kind: :pure,
    meaning: "divide traffic by weight",
    ref: nil,
    status: :decided
  }
)

vocab(
  "which",
  {
    subject: "name",
    args: ["name"],
    opts: false,
    returns: "path or nil",
    raises: [],
    kind: :effect,
    meaning: "absolute path of a command on PATH, or nil",
    ref: "§3.3",
    status: :stdlib
  }
)

vocab(
  "whole",
  {
    subject: "n",
    args: ["n"],
    opts: false,
    returns: "int",
    raises: [],
    kind: :pure,
    meaning: "the integer part of n toward zero",
    ref: nil,
    status: :decided
  }
)

vocab(
  "why",
  {
    subject: "decision",
    args: %w[subject name?],
    opts: false,
    returns: "text",
    raises: [],
    kind: :pure,
    meaning: "the rules or path behind a decision",
    ref: nil,
    status: :decided
  }
)

vocab(
  "windows",
  {
    subject: "xs",
    args: %w[xs n],
    opts: false,
    returns: "[list]",
    raises: [],
    kind: :pure,
    meaning: "every run of n consecutive items",
    ref: "§3.6",
    status: :stdlib
  }
)

vocab(
  "with",
  {
    subject: "fields",
    args: ["fields"],
    opts: false,
    returns: "logger",
    raises: [],
    kind: :pure,
    meaning: "a logger that adds fields to every line",
    ref: "§3.5",
    status: :decided
  }
)

vocab(
  "with_lock",
  {
    subject: "name",
    args: %w[name f],
    opts: true,
    returns: "value",
    raises: ["timeout"],
    kind: :effect,
    meaning: "run f while holding a named lease",
    ref: nil,
    status: :decided
  }
)

vocab(
  "wrap",
  {
    subject: "x",
    args: %w[x with],
    opts: false,
    returns: "x",
    raises: [],
    kind: :pure,
    meaning: "surround a value with another layer",
    ref: nil,
    status: :decided
  }
)

vocab(
  "write",
  {
    subject: "target",
    args: %w[target content],
    opts: true,
    returns: "nil",
    raises: ["permission_denied"],
    kind: :effect,
    meaning: "replace the whole content atomically",
    ref: "§3.1",
    status: :stdlib
  }
)

vocab(
  "yank",
  {
    subject: "name",
    args: %w[name version registry?],
    opts: true,
    returns: "nil",
    raises: [],
    kind: :effect,
    meaning: "withdraw a published version",
    ref: nil,
    status: :decided
  }
)

vocab(
  "zero",
  {
    subject: "f",
    args: %w[f bracket],
    opts: true,
    returns: "number",
    raises: [],
    kind: :pure,
    meaning: "where f is zero inside a bracket",
    ref: nil,
    status: :decided
  }
)

vocab(
  "zip",
  {
    subject: "xs",
    args: %w[xs ys],
    opts: false,
    returns: "[pair]",
    raises: [],
    kind: :pure,
    meaning: "items of two lists paired by position",
    ref: "§3.6",
    status: :stdlib
  }
)
